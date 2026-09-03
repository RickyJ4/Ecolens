"""Central orchestrator for multi-hazard environmental monitoring.

Coordinates all hazard services (wildfire, flood, drought, glacier, NDVI)
using parallel execution, provides unified query interfaces, location
monitoring, and alert generation.
"""

import logging
import math
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ALL_HAZARD_TYPES: Set[str] = {
    "fire", "flood", "drought", "glacier", "ndvi", "tides", "forest_loss"
}

ALERT_THRESHOLDS = {
    "fire": {
        "severity": {"extreme", "high"},
        "min_frp": 100,
    },
    "flood": {
        "status": {"major", "moderate"},
    },
    "drought": {
        "severity": {"D3", "D4"},
    },
    "glacier": {
        "retreat_pct_yr": -2.0,
    },
    "ndvi": {
        "anomaly": -0.2,
    },
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_all_hazards(
    bbox: Tuple[float, float, float, float],
    include: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Fetch all hazard layers in parallel and return a combined GeoJSON.

    Uses :class:`concurrent.futures.ThreadPoolExecutor` for parallel
    I/O-bound requests.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.
        include: Optional list of hazard types to include.  Accepted
            values: ``"fire"``, ``"flood"``, ``"drought"``,
            ``"glacier"``, ``"ndvi"``.  Defaults to all.

    Returns:
        Combined GeoJSON FeatureCollection with all hazard features,
        each tagged with a ``hazard_type`` property.
    """
    requested = set(include) & ALL_HAZARD_TYPES if include else ALL_HAZARD_TYPES

    all_features: List[Dict[str, Any]] = []
    layer_meta: Dict[str, Any] = {}
    errors: Dict[str, str] = {}

    # Map of hazard type to fetch function
    fetch_map = _build_fetch_map(bbox)

    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_type = {}
        for h_type in requested:
            if h_type in fetch_map:
                future = executor.submit(fetch_map[h_type])
                future_to_type[future] = h_type

        for future in as_completed(future_to_type):
            h_type = future_to_type[future]
            try:
                result = future.result()
                features = result.get("features", [])
                all_features.extend(features)
                layer_meta[h_type] = {
                    "count": len(features),
                    "source": result.get("metadata", {}).get("source", "unknown"),
                }
            except Exception as exc:
                logger.error("Hazard fetch failed for %s: %s", h_type, exc)
                errors[h_type] = str(exc)
                layer_meta[h_type] = {"count": 0, "error": str(exc)}

    return {
        "type": "FeatureCollection",
        "features": all_features,
        "metadata": {
            "bbox": list(bbox),
            "layers": layer_meta,
            "total_features": len(all_features),
            "errors": errors if errors else None,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def get_hazard_summary(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Generate a quick summary of hazard counts and overall risk level.

    This is a lightweight alternative to :func:`fetch_all_hazards` that
    only returns aggregate counts.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        Summary dict with per-type counts and an overall risk label.
    """
    combined = fetch_all_hazards(bbox)
    meta = combined.get("metadata", {})
    layers = meta.get("layers", {})

    total = meta.get("total_features", 0)

    # Simple overall risk heuristic
    if total == 0:
        overall = "low"
    elif total < 5:
        overall = "moderate"
    elif total < 20:
        overall = "high"
    else:
        overall = "extreme"

    return {
        "bbox": list(bbox),
        "counts": {k: v.get("count", 0) for k, v in layers.items()},
        "total_features": total,
        "overall_risk": overall,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def monitor_location(
    lat: float,
    lon: float,
    radius_km: float = 50.0,
) -> Dict[str, Any]:
    """Comprehensive hazard monitoring for a specific location.

    Creates a bounding box from the radius, fetches all hazards, runs a
    risk surface computation, and returns a unified assessment.

    Args:
        lat: Latitude of the monitoring point.
        lon: Longitude of the monitoring point.
        radius_km: Monitoring radius in kilometres (default 50).

    Returns:
        Dictionary with hazard data, risk assessment, alerts, and
        summary statistics.
    """
    # Convert km to approximate degrees
    lat_offset = radius_km / 111.0
    lon_offset = radius_km / (111.0 * max(math.cos(math.radians(lat)), 0.01))
    bbox = (
        round(lon - lon_offset, 6),
        round(lat - lat_offset, 6),
        round(lon + lon_offset, 6),
        round(lat + lat_offset, 6),
    )

    # Fetch all hazards
    hazard_data = fetch_all_hazards(bbox)

    # Generate risk surface (lower resolution for speed)
    try:
        from services.risk_surface_service import compute_risk_surface, generate_risk_report
        risk_report = generate_risk_report(bbox)
    except Exception as exc:
        logger.error("Risk report generation failed: %s", exc)
        risk_report = {"error": str(exc)}

    # Generate alerts
    alerts = generate_alert(hazard_data)

    # Compile result
    total_features = hazard_data.get("metadata", {}).get("total_features", 0)
    alert_count = len(alerts)

    return {
        "location": {"lat": lat, "lon": lon},
        "radius_km": radius_km,
        "bbox": list(bbox),
        "hazard_data": hazard_data,
        "risk_report": risk_report,
        "alerts": alerts,
        "summary": {
            "total_hazard_features": total_features,
            "alert_count": alert_count,
            "overall_risk": risk_report.get("overall_risk", {}).get("mean", 0)
            if isinstance(risk_report.get("overall_risk"), dict)
            else "unknown",
            "dominant_hazard": risk_report.get("dominant_hazard", "none"),
        },
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def generate_alert(
    hazard_data: Dict[str, Any],
    thresholds: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """Check hazard features against alert thresholds and emit alerts.

    Args:
        hazard_data: Combined GeoJSON from :func:`fetch_all_hazards`.
        thresholds: Optional custom thresholds overriding
            :data:`ALERT_THRESHOLDS`.

    Returns:
        List of alert dictionaries, each containing ``type``,
        ``severity``, ``message``, ``location``, and ``feature_id``.
    """
    thresh = thresholds if thresholds else ALERT_THRESHOLDS
    alerts: List[Dict[str, Any]] = []

    for feat in hazard_data.get("features", []):
        props = feat.get("properties", {})
        h_type = props.get("hazard_type", "")
        geom = feat.get("geometry", {})
        coords = geom.get("coordinates", [0, 0])

        # Determine location based on geometry type
        if geom.get("type") == "Point":
            loc = {"lon": coords[0], "lat": coords[1]}
        elif geom.get("type") == "Polygon" and coords:
            ring = coords[0]
            loc = {
                "lon": round(sum(c[0] for c in ring) / len(ring), 4),
                "lat": round(sum(c[1] for c in ring) / len(ring), 4),
            }
        else:
            loc = {"lon": 0, "lat": 0}

        alert = _check_thresholds(h_type, props, loc, thresh)
        if alert:
            alerts.append(alert)

    # Sort by severity
    severity_order = {"critical": 0, "high": 1, "moderate": 2, "low": 3, "info": 4}
    alerts.sort(key=lambda a: severity_order.get(a.get("severity", "info"), 5))

    return alerts


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _build_fetch_map(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Build a mapping of hazard type to parameterless fetch callables."""
    fetch_map: Dict[str, Any] = {}

    try:
        from services.wildfire_service import fetch_active_fires_combined
        # Combined FIRMS satellite hotspots + BC Wildfire Service incidents
        fetch_map["fire"] = lambda: fetch_active_fires_combined(bbox=bbox, days=2)
    except ImportError:
        logger.warning("wildfire_service not available.")

    try:
        from services.flood_service import fetch_flood_gauges_combined
        # Combined NOAA (US) + ECCC (Canada) coverage
        fetch_map["flood"] = lambda: fetch_flood_gauges_combined(bbox=bbox)
    except ImportError:
        logger.warning("flood_service not available.")

    try:
        from services.drought_service import fetch_drought_polygons
        fetch_map["drought"] = lambda: fetch_drought_polygons()
    except ImportError:
        logger.warning("drought_service not available.")

    try:
        from services.glacier_service import fetch_glacier_outlines
        fetch_map["glacier"] = lambda: fetch_glacier_outlines(bbox)
    except ImportError:
        logger.warning("glacier_service not available.")

    try:
        from services.ndvi_service import fetch_ndvi_modis
        fetch_map["ndvi"] = lambda: _ndvi_to_geojson_wrapper(bbox)
    except ImportError:
        logger.warning("ndvi_service not available.")

    try:
        from services.tides_service import fetch_tide_stations
        fetch_map["tides"] = lambda: fetch_tide_stations(bbox=bbox)
    except ImportError:
        logger.warning("tides_service not available.")

    try:
        from services.forest_change_service import fetch_forest_loss_summary
        fetch_map["forest_loss"] = lambda: fetch_forest_loss_summary(bbox=bbox)
    except ImportError:
        logger.warning("forest_change_service not available.")

    return fetch_map


def _ndvi_to_geojson_wrapper(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Wrap NDVI service result into a GeoJSON FeatureCollection."""
    from services.ndvi_service import fetch_ndvi_modis

    ndvi_data = fetch_ndvi_modis(bbox)
    if not ndvi_data.get("available"):
        return {"type": "FeatureCollection", "features": [], "metadata": {"source": "NDVI"}}

    # Create a single summary feature for the bbox
    w, s, e, n = bbox
    stats = ndvi_data.get("statistics", {})

    feature = {
        "type": "Feature",
        "geometry": {
            "type": "Polygon",
            "coordinates": [[
                [w, s], [e, s], [e, n], [w, n], [w, s],
            ]],
        },
        "properties": {
            "hazard_type": "ndvi",
            "ndvi_mean": stats.get("mean", 0),
            "ndvi_min": stats.get("min", 0),
            "ndvi_max": stats.get("max", 0),
            "source": ndvi_data.get("source", "MODIS"),
            "severity": _ndvi_to_severity(stats.get("mean", 0.5)),
        },
    }

    return {
        "type": "FeatureCollection",
        "features": [feature],
        "metadata": {"source": "NDVI", "count": 1},
    }


def _ndvi_to_severity(mean_ndvi: float) -> str:
    """Map mean NDVI to a severity label."""
    if mean_ndvi < 0.15:
        return "extreme"
    if mean_ndvi < 0.25:
        return "high"
    if mean_ndvi < 0.4:
        return "moderate"
    return "low"


def _check_thresholds(
    hazard_type: str,
    props: Dict[str, Any],
    location: Dict[str, float],
    thresholds: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """Check a single feature against alert thresholds."""

    # --- Wildfire alerts ---
    if hazard_type in ("wildfire", "wildfire_perimeter"):
        fire_thresh = thresholds.get("fire", {})
        severity = props.get("severity", "")
        frp = props.get("frp", 0)

        if severity in fire_thresh.get("severity", set()):
            return {
                "type": "wildfire",
                "severity": "critical" if severity == "extreme" else "high",
                "message": (
                    f"Active wildfire detected ({severity} severity, "
                    f"FRP: {frp} MW) near {location['lat']:.3f}, {location['lon']:.3f}."
                ),
                "location": location,
                "properties": {
                    "fire_severity": severity,
                    "frp": frp,
                    "source": props.get("source", ""),
                },
            }

    # --- Flood alerts ---
    if hazard_type in ("flood", "flood_zone"):
        flood_thresh = thresholds.get("flood", {})
        status = props.get("status", "")

        if status in flood_thresh.get("status", set()):
            return {
                "type": "flood",
                "severity": "critical" if status == "major" else "high",
                "message": (
                    f"Flood gauge at {props.get('name', 'Unknown')} reporting "
                    f"{status} flooding (stage: {props.get('observed_stage', 'N/A')})."
                ),
                "location": location,
                "properties": {
                    "gauge_id": props.get("gauge_id", ""),
                    "status": status,
                    "observed_stage": props.get("observed_stage"),
                    "flood_stage": props.get("flood_stage"),
                },
            }

    # --- Drought alerts ---
    if hazard_type == "drought":
        drought_thresh = thresholds.get("drought", {})
        severity = props.get("severity", "")

        if severity in drought_thresh.get("severity", set()):
            return {
                "type": "drought",
                "severity": "high" if severity == "D4" else "moderate",
                "message": (
                    f"Drought severity {severity} "
                    f"({props.get('severity_label', '')}) detected in area."
                ),
                "location": location,
                "properties": {
                    "drought_severity": severity,
                    "label": props.get("severity_label", ""),
                },
            }

    # --- Glacier alerts ---
    if hazard_type == "glacier":
        # Glacier alerts are less time-critical; flag rapid retreat
        pass

    return None
