"""Multi-hazard spatial risk surface computation following UNDRR methodology.

Generates gridded risk surfaces by combining individual hazard scores
(wildfire, flood, drought, glacier) with configurable weights into a
composite risk index.  Supports exposure analysis when population data
is available.
"""

import logging
import math
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Default hazard weights (UNDRR-inspired)
# ---------------------------------------------------------------------------

WEIGHTS: Dict[str, float] = {
    "fire": 0.30,
    "flood": 0.30,
    "drought": 0.20,
    "glacier": 0.20,
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def compute_risk_surface(
    bbox: Tuple[float, float, float, float],
    hazards: Optional[Dict[str, Any]] = None,
    resolution: float = 0.01,
    weights: Optional[Dict[str, float]] = None,
) -> Dict[str, Any]:
    """Compute a multi-hazard risk surface as a GeoJSON grid.

    Creates a regular grid over the bounding box.  For each cell, the
    function computes individual hazard scores (fire, flood, drought,
    glacier), normalises them to [0, 1], and produces a weighted
    composite risk index.

    Args:
        bbox: Bounding box (west, south, east, north).
        hazards: Pre-fetched hazard data dictionary keyed by hazard type
            (``"fire"``, ``"flood"``, ``"drought"``, ``"glacier"``).
            If ``None``, the function will attempt to fetch data using
            the corresponding service modules.
        resolution: Grid cell size in degrees (default 0.01, ~ 1 km).
        weights: Optional custom weights dict overriding :data:`WEIGHTS`.

    Returns:
        GeoJSON FeatureCollection where each cell feature carries
        ``fire_risk``, ``flood_risk``, ``drought_risk``,
        ``glacier_risk``, and ``combined_risk`` properties.
    """
    w_map = weights if weights else WEIGHTS
    # Normalise weights so they sum to 1
    w_total = sum(w_map.values()) or 1.0
    w_norm = {k: v / w_total for k, v in w_map.items()}

    w, s, e, n = bbox
    cols = max(1, int(math.ceil((e - w) / resolution)))
    rows = max(1, int(math.ceil((n - s) / resolution)))

    # Limit grid size to avoid excessive computation
    max_cells = 10000
    if rows * cols > max_cells:
        scale = math.sqrt((rows * cols) / max_cells)
        resolution = resolution * scale
        cols = max(1, int(math.ceil((e - w) / resolution)))
        rows = max(1, int(math.ceil((n - s) / resolution)))
        logger.info("Downscaled risk grid to %dx%d (resolution %.4f deg).", cols, rows, resolution)

    # Lazy-load hazard data if not provided
    if hazards is None:
        hazards = _fetch_hazard_data(bbox)

    # Pre-compute hazard feature positions for proximity calculations
    fire_points = _extract_points(hazards.get("fire", {}))
    flood_points = _extract_points(hazards.get("flood", {}))
    drought_severity = _extract_drought_severity(hazards.get("drought", {}))
    glacier_points = _extract_points(hazards.get("glacier", {}))

    features: List[Dict[str, Any]] = []

    for r in range(rows):
        for c in range(cols):
            cell_w = w + c * resolution
            cell_s = s + r * resolution
            cell_e = cell_w + resolution
            cell_n = cell_s + resolution
            cx = (cell_w + cell_e) / 2
            cy = (cell_s + cell_n) / 2

            # --- Individual hazard scores (0-1) ---
            fire_risk = _proximity_score(cx, cy, fire_points, max_dist_deg=0.5)
            flood_risk = _proximity_score(cx, cy, flood_points, max_dist_deg=0.3)
            drought_risk = _drought_score(cx, cy, drought_severity)
            glacier_risk = _proximity_score(cx, cy, glacier_points, max_dist_deg=1.0) * 0.5

            # --- Combined risk ---
            combined = (
                w_norm.get("fire", 0) * fire_risk
                + w_norm.get("flood", 0) * flood_risk
                + w_norm.get("drought", 0) * drought_risk
                + w_norm.get("glacier", 0) * glacier_risk
            )
            combined = round(max(0.0, min(1.0, combined)), 4)

            # Risk classification
            if combined >= 0.75:
                risk_class = "extreme"
            elif combined >= 0.50:
                risk_class = "high"
            elif combined >= 0.25:
                risk_class = "moderate"
            else:
                risk_class = "low"

            feature = {
                "type": "Feature",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [round(cell_w, 6), round(cell_s, 6)],
                        [round(cell_e, 6), round(cell_s, 6)],
                        [round(cell_e, 6), round(cell_n, 6)],
                        [round(cell_w, 6), round(cell_n, 6)],
                        [round(cell_w, 6), round(cell_s, 6)],
                    ]],
                },
                "properties": {
                    "fire_risk": round(fire_risk, 4),
                    "flood_risk": round(flood_risk, 4),
                    "drought_risk": round(drought_risk, 4),
                    "glacier_risk": round(glacier_risk, 4),
                    "combined_risk": combined,
                    "risk_class": risk_class,
                    "cell_center": [round(cx, 6), round(cy, 6)],
                },
            }
            features.append(feature)

    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "bbox": list(bbox),
            "resolution_deg": resolution,
            "grid_rows": rows,
            "grid_cols": cols,
            "total_cells": len(features),
            "weights": w_norm,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def compute_exposure(
    risk_surface: Dict[str, Any],
    population_data: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Combine a risk surface with population data to compute exposure.

    Exposure = risk * population density.  When population data is not
    available, the function returns risk statistics alone.

    Args:
        risk_surface: GeoJSON from :func:`compute_risk_surface`.
        population_data: Optional GeoJSON or dict mapping cell centres
            to population density (people/km^2).

    Returns:
        Dictionary with exposure index per cell and summary statistics.
    """
    features = risk_surface.get("features", [])
    if not features:
        return {"exposure_cells": [], "summary": {}, "error": "No risk surface features."}

    combined_risks: List[float] = []
    exposure_cells: List[Dict[str, Any]] = []

    for feat in features:
        props = feat.get("properties", {})
        combined = props.get("combined_risk", 0)
        combined_risks.append(combined)

        # Look up population density
        pop_density = 0.0
        if population_data:
            center = props.get("cell_center", [0, 0])
            pop_density = _lookup_population(center, population_data)

        exposure = combined * pop_density
        exposure_cells.append({
            "cell_center": props.get("cell_center"),
            "combined_risk": combined,
            "population_density": round(pop_density, 1),
            "exposure_index": round(exposure, 2),
        })

    arr = np.array(combined_risks)
    exposure_vals = np.array([c["exposure_index"] for c in exposure_cells])

    summary = {
        "risk_mean": round(float(np.mean(arr)), 4),
        "risk_max": round(float(np.max(arr)), 4),
        "risk_min": round(float(np.min(arr)), 4),
        "cells_high_risk": int(np.sum(arr >= 0.5)),
        "cells_extreme_risk": int(np.sum(arr >= 0.75)),
        "total_cells": len(arr),
    }

    if population_data:
        summary["exposure_mean"] = round(float(np.mean(exposure_vals)), 2)
        summary["exposure_max"] = round(float(np.max(exposure_vals)), 2)
        summary["total_exposed_population"] = round(float(np.sum(exposure_vals)), 0)

    return {
        "exposure_cells": exposure_cells,
        "summary": summary,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def generate_risk_report(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Generate a summary risk report for a bounding box.

    Fetches hazard data, computes the risk surface, and returns
    actionable statistics and recommendations.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        Comprehensive risk report dictionary.
    """
    risk_surface = compute_risk_surface(bbox, resolution=0.02)
    features = risk_surface.get("features", [])

    if not features:
        return {
            "bbox": list(bbox),
            "error": "No risk data available.",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    combined = [f["properties"]["combined_risk"] for f in features]
    fire_risks = [f["properties"]["fire_risk"] for f in features]
    flood_risks = [f["properties"]["flood_risk"] for f in features]
    drought_risks = [f["properties"]["drought_risk"] for f in features]
    glacier_risks = [f["properties"]["glacier_risk"] for f in features]

    # Identify top risk areas (cells above 75th percentile)
    threshold_75 = float(np.percentile(combined, 75)) if combined else 0
    top_risk_cells = [
        f["properties"]
        for f in features
        if f["properties"]["combined_risk"] >= threshold_75
    ][:10]  # Limit to top 10

    # Determine dominant hazard overall
    hazard_means = {
        "fire": float(np.mean(fire_risks)) if fire_risks else 0,
        "flood": float(np.mean(flood_risks)) if flood_risks else 0,
        "drought": float(np.mean(drought_risks)) if drought_risks else 0,
        "glacier": float(np.mean(glacier_risks)) if glacier_risks else 0,
    }
    dominant_hazard = max(hazard_means, key=hazard_means.get)

    # Recommendations
    recommendations = _generate_recommendations(hazard_means, combined)

    return {
        "bbox": list(bbox),
        "overall_risk": {
            "mean": round(float(np.mean(combined)), 4),
            "max": round(float(np.max(combined)), 4),
            "min": round(float(np.min(combined)), 4),
            "std": round(float(np.std(combined)), 4),
        },
        "hazard_breakdown": {
            k: round(v, 4) for k, v in hazard_means.items()
        },
        "dominant_hazard": dominant_hazard,
        "risk_distribution": {
            "low": int(np.sum(np.array(combined) < 0.25)),
            "moderate": int(np.sum((np.array(combined) >= 0.25) & (np.array(combined) < 0.50))),
            "high": int(np.sum((np.array(combined) >= 0.50) & (np.array(combined) < 0.75))),
            "extreme": int(np.sum(np.array(combined) >= 0.75)),
        },
        "top_risk_areas": top_risk_cells,
        "recommendations": recommendations,
        "total_cells_assessed": len(features),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _fetch_hazard_data(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Fetch all hazard layers for risk surface computation."""
    result: Dict[str, Any] = {}

    try:
        from services.wildfire_service import fetch_active_fires
        result["fire"] = fetch_active_fires(bbox=bbox, days=2)
    except Exception as exc:
        logger.warning("Fire data fetch failed: %s", exc)
        result["fire"] = {"features": []}

    try:
        from services.flood_service import fetch_flood_gauges
        result["flood"] = fetch_flood_gauges(bbox=bbox)
    except Exception as exc:
        logger.warning("Flood data fetch failed: %s", exc)
        result["flood"] = {"features": []}

    try:
        from services.drought_service import fetch_drought_polygons
        result["drought"] = fetch_drought_polygons()
    except Exception as exc:
        logger.warning("Drought data fetch failed: %s", exc)
        result["drought"] = {"features": []}

    try:
        from services.glacier_service import fetch_glacier_outlines
        result["glacier"] = fetch_glacier_outlines(bbox)
    except Exception as exc:
        logger.warning("Glacier data fetch failed: %s", exc)
        result["glacier"] = {"features": []}

    return result


def _extract_points(
    geojson: Dict[str, Any],
) -> List[Tuple[float, float, float]]:
    """Extract (lon, lat, severity_score) tuples from GeoJSON features."""
    points: List[Tuple[float, float, float]] = []
    for feat in geojson.get("features", []):
        geom = feat.get("geometry", {})
        coords = geom.get("coordinates")
        if not coords:
            continue

        props = feat.get("properties", {})
        severity = _severity_to_score(props.get("severity", "moderate"))

        if geom.get("type") == "Point":
            points.append((coords[0], coords[1], severity))
        elif geom.get("type") == "Polygon":
            # Use centroid
            ring = coords[0] if coords else []
            if ring:
                cx = sum(c[0] for c in ring) / len(ring)
                cy = sum(c[1] for c in ring) / len(ring)
                points.append((cx, cy, severity))

    return points


def _extract_drought_severity(
    geojson: Dict[str, Any],
) -> List[Tuple[Any, float]]:
    """Extract drought polygons with severity scores.

    Returns list of (shapely_geometry, severity_score) or
    (bbox_tuple, severity_score) pairs.
    """
    results: List[Tuple[Any, float]] = []
    try:
        from shapely.geometry import shape

        for feat in geojson.get("features", []):
            try:
                geom = shape(feat["geometry"])
                props = feat.get("properties", {})
                sev = props.get("severity", "D0")
                score_map = {"D4": 1.0, "D3": 0.8, "D2": 0.6, "D1": 0.4, "D0": 0.2, "None": 0.0}
                score = score_map.get(sev, 0.2)
                results.append((geom, score))
            except Exception:
                continue
    except ImportError:
        logger.warning("shapely unavailable; drought spatial analysis limited.")

    return results


def _proximity_score(
    cx: float,
    cy: float,
    points: List[Tuple[float, float, float]],
    max_dist_deg: float = 0.5,
) -> float:
    """Compute a proximity-based risk score for a cell centre.

    The score is the maximum of ``severity / (1 + distance/scale)`` over
    all hazard points.
    """
    if not points:
        return 0.0

    max_score = 0.0
    for px, py, sev in points:
        dist = math.sqrt((cx - px) ** 2 + (cy - py) ** 2)
        if dist > max_dist_deg:
            continue
        score = sev * (1.0 - dist / max_dist_deg)
        max_score = max(max_score, score)

    return max(0.0, min(1.0, max_score))


def _drought_score(
    cx: float,
    cy: float,
    drought_severity: List[Tuple[Any, float]],
) -> float:
    """Determine drought score for a cell based on polygon containment."""
    if not drought_severity:
        return 0.0

    try:
        from shapely.geometry import Point

        pt = Point(cx, cy)
        for geom, score in drought_severity:
            try:
                if geom.contains(pt):
                    return score
            except Exception:
                continue
    except ImportError:
        pass

    return 0.0


def _severity_to_score(severity: str) -> float:
    """Map severity label to 0-1 numeric score."""
    mapping = {
        "extreme": 1.0,
        "high": 0.8,
        "moderate": 0.5,
        "low": 0.2,
        "minimal": 0.1,
        "none": 0.0,
    }
    return mapping.get(str(severity).lower(), 0.3)


def _lookup_population(
    center: List[float],
    population_data: Dict[str, Any],
) -> float:
    """Look up population density for a cell centre."""
    # Support a simple dict mapping "lat,lon" to density
    if isinstance(population_data, dict):
        key = f"{center[1]:.2f},{center[0]:.2f}"
        return float(population_data.get(key, population_data.get("default", 50.0)))
    return 50.0  # Global average fallback


def _generate_recommendations(
    hazard_means: Dict[str, float],
    combined: List[float],
) -> List[Dict[str, str]]:
    """Generate actionable recommendations based on risk profile."""
    recs: List[Dict[str, str]] = []

    if hazard_means.get("fire", 0) > 0.3:
        recs.append({
            "priority": "high",
            "hazard": "wildfire",
            "action": "Establish fire breaks and defensible space around critical infrastructure.",
            "rationale": "Elevated wildfire risk detected in the area.",
        })

    if hazard_means.get("flood", 0) > 0.3:
        recs.append({
            "priority": "high",
            "hazard": "flood",
            "action": "Review and reinforce flood defences; update evacuation plans.",
            "rationale": "Multiple flood gauges are above action or flood stage.",
        })

    if hazard_means.get("drought", 0) > 0.3:
        recs.append({
            "priority": "medium",
            "hazard": "drought",
            "action": "Implement water conservation measures and monitor soil moisture.",
            "rationale": "Drought conditions detected which may affect agriculture and water supply.",
        })

    if hazard_means.get("glacier", 0) > 0.2:
        recs.append({
            "priority": "medium",
            "hazard": "glacier",
            "action": "Monitor glacial lake outburst flood (GLOF) risk and downstream communities.",
            "rationale": "Glacial retreat detected; downstream flood risk may increase.",
        })

    overall_mean = float(np.mean(combined)) if combined else 0
    if overall_mean > 0.5:
        recs.append({
            "priority": "critical",
            "hazard": "multi-hazard",
            "action": "Activate multi-hazard early warning systems and coordinate inter-agency response.",
            "rationale": "Overall risk level is elevated across multiple hazard types.",
        })

    if not recs:
        recs.append({
            "priority": "info",
            "hazard": "none",
            "action": "Continue routine monitoring.  No immediate hazard escalation detected.",
            "rationale": "All hazard indicators are within normal ranges.",
        })

    return recs
