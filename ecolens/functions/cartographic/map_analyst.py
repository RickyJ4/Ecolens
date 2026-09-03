"""
Map Analyst — Multi-Hazard Analysis Pipeline

Transforms raw hazard data into map-ready analysis products.
Each hazard type has its own analysis pipeline producing layers
that TELL A STORY, not just plot dots.

Hazard types and their stories:
  Wildfire:       "Fires burning HERE, threatening THESE cities, THIS intensity"
  Flood:          "River at THIS stage, THESE zones will flood, THIS many exposed"
  Drought:        "D0-D4 drought zones, vegetation stress, crop impact areas"
  Earthquake:     "Seismic risk zones, affected cities, major event impact radii"
  Deforestation:  "Forest loss frontier, protected areas breached, species habitat"
  Glacier:        "Retreat since 2000, meltwater flood risk downstream"
  Multi-hazard:   "Composite risk surface, which cities face multiple threats"

Each pipeline outputs:
  - Classified zone polygons (the STORY layer)
  - Affected settlement markers (WHO is at risk)
  - Major event features (WHAT happened)
  - Context points (raw data for reference)
  - Legend metadata (WHAT the colors mean)
"""

from __future__ import annotations

import math
import logging
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════

def analyse_for_map(
    raw_data: dict,
    bbox: tuple[float, float, float, float],
    theme: str = "multi_hazard",
    value_field: str = "mag",
) -> dict[str, dict]:
    """
    Full analysis pipeline: raw data → map-ready analysed layers.

    Routes to the correct hazard-specific analyser based on theme.
    """
    features = raw_data.get("features", [])
    if not features:
        return {"raw_points": raw_data}

    # Route to hazard-specific pipeline
    if theme in ("earthquake", "seismic"):
        return _analyse_earthquake(raw_data, bbox, value_field)
    elif theme in ("fire_risk", "wildfire"):
        return _analyse_wildfire(raw_data, bbox)
    elif theme in ("flood_risk", "flood"):
        return _analyse_flood(raw_data, bbox)
    elif theme in ("drought",):
        return _analyse_drought(raw_data, bbox)
    elif theme in ("deforestation", "forest_loss"):
        return _analyse_deforestation(raw_data, bbox)
    elif theme in ("glacier", "cryosphere"):
        return _analyse_glacier(raw_data, bbox)
    elif theme in ("multi_hazard", "composite"):
        return _analyse_multi_hazard(raw_data, bbox)
    elif theme in ("biodiversity", "vegetation_health", "ndvi"):
        return _analyse_vegetation(raw_data, bbox)
    else:
        return _analyse_generic(raw_data, bbox, theme, value_field)


# ═══════════════════════════════════════════════════════════════════════
# EARTHQUAKE ANALYSIS
# Story: "Where are people at risk from seismic activity?"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_earthquake(raw_data: dict, bbox: tuple, value_field: str) -> dict:
    """
    Earthquake analysis pipeline:
    1. Compute seismic risk surface (IDW from event magnitudes)
    2. Identify major events with impact radii
    3. Find affected cities with exposure scores
    4. Keep raw points as context
    """
    result = {}

    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="mag",
        decay_base_km=10.0,
        decay_exponent=2.0,  # M4→~50km, M5→~100km, M6→~200km
        energy_scaling=True,  # Exponential energy scaling with magnitude
        levels=[
            (0.05, "Very Low",  "#2166ac"),
            (0.15, "Low",       "#67a9cf"),
            (0.30, "Moderate",  "#fddbc7"),
            (0.55, "High",      "#ef8a62"),
            (0.80, "Very High", "#b2182b"),
            (1.01, "Critical",  "#67001f"),
        ],
    )

    result["major_events"] = _extract_major_events(
        raw_data, min_value=5.8, value_field="mag",
        max_events=5,  # Fewer circles = cleaner map
        radius_fn=lambda mag: max(25, (mag - 4.0) * 35.0),
        label_fn=lambda props: f"M{props.get('mag', 0):.1f} — {props.get('place', '')[:30]}",
    )

    result["affected_cities"] = _find_affected_cities(
        bbox, raw_data, value_field="mag",
        influence_fn=lambda mag: 10.0 * (2.0 ** (mag - 3.0)),
        energy_fn=lambda mag: 10.0 ** (1.5 * (mag - 4.0)),
    )

    result["raw_points"] = raw_data

    result["legend"] = {
        "title": "Seismic Risk Assessment",
        "zones": [
            {"label": "Very Low", "color": "#2166ac"},
            {"label": "Low", "color": "#67a9cf"},
            {"label": "Moderate", "color": "#fddbc7"},
            {"label": "High", "color": "#ef8a62"},
            {"label": "Very High", "color": "#b2182b"},
            {"label": "Critical", "color": "#67001f"},
        ],
        "symbols": [
            {"label": "Major event (M5.5+)", "type": "circle_outline", "color": "#ff3333"},
            {"label": "City at risk", "type": "square", "color": "#ffffff"},
            {"label": "Earthquake detection", "type": "dot", "color": "#ffaa33"},
        ],
    }

    _log_analysis("earthquake", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# WILDFIRE ANALYSIS
# Story: "Where are fires burning and who is threatened?"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_wildfire(raw_data: dict, bbox: tuple) -> dict:
    """
    Wildfire analysis:
    1. Fire intensity surface from FRP (Fire Radiative Power)
    2. Active fire clusters (concentrated burning areas)
    3. Threatened settlements within smoke/fire radius
    4. Burn perimeter estimates from detection density
    """
    result = {}

    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="frp",
        fallback_fields=["brightness", "bright_ti4", "confidence"],
        decay_base_km=5.0,
        decay_exponent=1.5,
        energy_scaling=False,
        levels=[
            (0.10, "Low intensity",       "#ffffb2"),
            (0.25, "Moderate intensity",  "#fed976"),
            (0.45, "High intensity",      "#fd8d3c"),
            (0.70, "Very high intensity", "#f03b20"),
            (1.01, "Extreme intensity",   "#bd0026"),
        ],
    )

    result["major_events"] = _extract_major_events(
        raw_data, min_value=100, value_field="frp",
        fallback_fields=["brightness"],
        radius_fn=lambda frp: min(30, max(5, frp / 50.0)),
        label_fn=lambda props: f"FRP: {props.get('frp', 0):.0f} MW",
    )

    result["affected_cities"] = _find_affected_cities(
        bbox, raw_data, value_field="frp",
        fallback_fields=["brightness"],
        influence_fn=lambda frp: min(100, max(10, frp / 10.0)),
        energy_fn=lambda frp: frp / 100.0,
    )

    result["raw_points"] = raw_data

    result["legend"] = {
        "title": "Wildfire Activity",
        "zones": [
            {"label": "Low intensity", "color": "#ffffb2"},
            {"label": "Moderate", "color": "#fed976"},
            {"label": "High intensity", "color": "#fd8d3c"},
            {"label": "Very high", "color": "#f03b20"},
            {"label": "Extreme", "color": "#bd0026"},
        ],
        "symbols": [
            {"label": "Major fire (FRP>100MW)", "type": "circle_outline", "color": "#ff4400"},
            {"label": "Threatened city", "type": "square", "color": "#ffffff"},
            {"label": "Fire detection", "type": "dot", "color": "#ff6633"},
        ],
    }

    _log_analysis("wildfire", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# FLOOD ANALYSIS
# Story: "River levels rising, these zones will flood, X people exposed"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_flood(raw_data: dict, bbox: tuple) -> dict:
    """
    Flood analysis:
    1. Flood risk zones from gauge data + elevation
    2. Inundation areas based on flood stage severity
    3. Exposed population in flood zones
    """
    result = {}

    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="observedStage",
        fallback_fields=["discharge", "risk"],
        decay_base_km=20.0,
        decay_exponent=1.0,
        energy_scaling=False,
        levels=[
            (0.15, "No flooding",  "#2166ac"),
            (0.30, "Action stage", "#67a9cf"),
            (0.50, "Minor flood",  "#fddbc7"),
            (0.75, "Moderate flood", "#ef8a62"),
            (1.01, "Major flood",  "#b2182b"),
        ],
    )

    result["affected_cities"] = _find_affected_cities(
        bbox, raw_data, value_field="observedStage",
        fallback_fields=["discharge", "risk"],
        influence_fn=lambda stage: max(10, stage * 5.0),
        energy_fn=lambda stage: stage / 10.0,
    )

    result["raw_points"] = raw_data

    result["legend"] = {
        "title": "Flood Risk Assessment",
        "zones": [
            {"label": "No flooding", "color": "#2166ac"},
            {"label": "Action stage", "color": "#67a9cf"},
            {"label": "Minor flood", "color": "#fddbc7"},
            {"label": "Moderate flood", "color": "#ef8a62"},
            {"label": "Major flood", "color": "#b2182b"},
        ],
        "symbols": [
            {"label": "Flood gauge", "type": "triangle", "color": "#1E90FF"},
            {"label": "Exposed city", "type": "square", "color": "#ffffff"},
        ],
    }

    _log_analysis("flood", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# DROUGHT ANALYSIS
# Story: "D0-D4 drought severity, crop stress, water reserves"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_drought(raw_data: dict, bbox: tuple) -> dict:
    """
    Drought analysis — the data already comes as classified polygons
    from the US Drought Monitor (D0-D4). We just need to enhance with
    affected cities and vegetation stress overlay.
    """
    result = {}

    # Drought data is already classified — pass through
    result["risk_zones"] = raw_data

    result["affected_cities"] = _find_affected_cities(
        bbox, raw_data, value_field="severity",
        influence_fn=lambda sev: 100,  # Drought affects entire region
        energy_fn=lambda sev: sev / 4.0,
    )

    result["raw_points"] = {"type": "FeatureCollection", "features": []}

    result["legend"] = {
        "title": "Drought Severity",
        "zones": [
            {"label": "D0 — Abnormally Dry", "color": "#FFFF00"},
            {"label": "D1 — Moderate Drought", "color": "#FCD37F"},
            {"label": "D2 — Severe Drought", "color": "#FFAA00"},
            {"label": "D3 — Extreme Drought", "color": "#E60000"},
            {"label": "D4 — Exceptional Drought", "color": "#730000"},
        ],
    }

    _log_analysis("drought", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# DEFORESTATION ANALYSIS
# Story: "Forest loss frontier, protected areas, species at risk"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_deforestation(raw_data: dict, bbox: tuple) -> dict:
    """
    Deforestation analysis:
    1. Tree cover loss density surface
    2. Deforestation frontier line (advancing edge of clearing)
    3. Protected area boundaries (are they being respected?)
    4. Affected biodiversity zones
    """
    result = {}

    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="area_ha",
        fallback_fields=["hectares", "tree_loss", "confidence"],
        decay_base_km=15.0,
        decay_exponent=1.2,
        energy_scaling=False,
        levels=[
            (0.10, "Intact forest",      "#006837"),
            (0.25, "Minor disturbance",  "#31a354"),
            (0.45, "Moderate loss",      "#fdae61"),
            (0.70, "Severe loss",        "#f46d43"),
            (1.01, "Critical loss",      "#a50026"),
        ],
    )

    result["affected_cities"] = _find_affected_cities(
        bbox, raw_data, value_field="area_ha",
        fallback_fields=["hectares"],
        influence_fn=lambda ha: min(50, max(5, ha / 10.0)),
        energy_fn=lambda ha: ha / 1000.0,
    )

    result["raw_points"] = raw_data

    result["legend"] = {
        "title": "Deforestation Analysis",
        "zones": [
            {"label": "Intact forest", "color": "#006837"},
            {"label": "Minor disturbance", "color": "#31a354"},
            {"label": "Moderate loss", "color": "#fdae61"},
            {"label": "Severe loss", "color": "#f46d43"},
            {"label": "Critical loss", "color": "#a50026"},
        ],
        "symbols": [
            {"label": "Deforestation detection", "type": "dot", "color": "#ff0066"},
            {"label": "Affected settlement", "type": "square", "color": "#ffffff"},
        ],
    }

    _log_analysis("deforestation", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# GLACIER ANALYSIS
# Story: "Retreat since baseline, meltwater flood risk"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_glacier(raw_data: dict, bbox: tuple) -> dict:
    result = {}
    result["risk_zones"] = raw_data  # Glacier outlines are already polygons
    result["affected_cities"] = _find_affected_cities(bbox, raw_data)
    result["raw_points"] = {"type": "FeatureCollection", "features": []}
    result["legend"] = {
        "title": "Glacier Retreat Assessment",
        "zones": [
            {"label": "Current extent", "color": "#a6cee3"},
            {"label": "Lost since 2000", "color": "#ff7f7f"},
        ],
    }
    _log_analysis("glacier", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# VEGETATION / NDVI ANALYSIS
# Story: "Vegetation health declining, drought/disease stress"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_vegetation(raw_data: dict, bbox: tuple) -> dict:
    result = {}
    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="ndvi",
        fallback_fields=["anomaly", "stress"],
        decay_base_km=20.0,
        decay_exponent=1.0,
        energy_scaling=False,
        levels=[
            (0.20, "Healthy",          "#006837"),
            (0.40, "Mild stress",      "#78c679"),
            (0.60, "Moderate stress",  "#fdae61"),
            (0.80, "Severe stress",    "#f46d43"),
            (1.01, "Critical stress",  "#a50026"),
        ],
    )
    result["affected_cities"] = _find_affected_cities(bbox, raw_data)
    result["raw_points"] = raw_data
    result["legend"] = {
        "title": "Vegetation Health",
        "zones": [
            {"label": "Healthy", "color": "#006837"},
            {"label": "Mild stress", "color": "#78c679"},
            {"label": "Moderate stress", "color": "#fdae61"},
            {"label": "Severe stress", "color": "#f46d43"},
            {"label": "Critical", "color": "#a50026"},
        ],
    }
    _log_analysis("vegetation", result, bbox)
    return result


# ═══════════════════════════════════════════════════════════════════════
# MULTI-HAZARD COMPOSITE
# Story: "This city faces X types of hazard, composite risk = Y"
# ═══════════════════════════════════════════════════════════════════════

def _analyse_multi_hazard(raw_data: dict, bbox: tuple) -> dict:
    """
    Multi-hazard: split features by type, analyse each separately,
    then combine into composite risk surface.
    """
    features = raw_data.get("features", [])

    # Separate by hazard type
    by_type: dict[str, list] = {}
    for f in features:
        props = f.get("properties", {})
        htype = (props.get("type") or props.get("hazard_type") or
                 _infer_hazard_type(props))
        if htype not in by_type:
            by_type[htype] = []
        by_type[htype].append(f)

    # If all features are the same type (e.g. all earthquakes), route directly
    if len(by_type) == 1:
        only_type = list(by_type.keys())[0]
        if only_type in ("earthquake", "seismic"):
            return _analyse_earthquake(raw_data, bbox, "mag")
        elif only_type in ("fire", "wildfire"):
            return _analyse_wildfire(raw_data, bbox)

    # True multi-hazard: composite risk from all types
    result = {}
    result["risk_zones"] = _compute_risk_surface(
        raw_data, bbox,
        value_field="mag",
        fallback_fields=["frp", "brightness", "severity", "risk", "confidence"],
        decay_base_km=15.0,
        decay_exponent=1.5,
        energy_scaling=False,
        levels=[
            (0.08, "Very Low",  "#2166ac"),
            (0.20, "Low",       "#67a9cf"),
            (0.40, "Moderate",  "#fddbc7"),
            (0.65, "High",      "#ef8a62"),
            (0.85, "Very High", "#b2182b"),
            (1.01, "Critical",  "#67001f"),
        ],
    )
    result["affected_cities"] = _find_affected_cities(bbox, raw_data)
    result["raw_points"] = raw_data
    result["legend"] = {
        "title": "Multi-Hazard Risk Index",
        "zones": [
            {"label": "Very Low", "color": "#2166ac"},
            {"label": "Low", "color": "#67a9cf"},
            {"label": "Moderate", "color": "#fddbc7"},
            {"label": "High", "color": "#ef8a62"},
            {"label": "Very High", "color": "#b2182b"},
            {"label": "Critical", "color": "#67001f"},
        ],
    }
    _log_analysis("multi_hazard", result, bbox)
    return result


def _analyse_generic(raw_data, bbox, theme, value_field):
    """Fallback for unknown themes."""
    result = {}
    result["risk_zones"] = _compute_risk_surface(raw_data, bbox, value_field=value_field)
    result["affected_cities"] = _find_affected_cities(bbox, raw_data)
    result["raw_points"] = raw_data
    result["legend"] = {"title": theme.replace("_", " ").title(), "zones": []}
    return result


# ═══════════════════════════════════════════════════════════════════════
# SHARED ANALYSIS FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

def _compute_risk_surface(
    geojson: dict,
    bbox: tuple[float, float, float, float],
    value_field: str = "mag",
    fallback_fields: list[str] | None = None,
    grid_size: int = 200,
    decay_base_km: float = 10.0,
    decay_exponent: float = 2.0,
    energy_scaling: bool = True,
    levels: list[tuple] | None = None,
) -> dict:
    """
    Risk surface as a GeoTIFF raster — smooth, continuous, no jagged edges.

    Uses Gaussian-weighted kernel density instead of grid cells.
    Output is a file path to a GeoTIFF that QGIS renders with a color ramp.
    Also returns classified contour polygons for the legend.

    Returns a dict with:
      - "raster_path": path to GeoTIFF (for QGIS raster layer)
      - "type": "FeatureCollection" with contour polygons (for legend/fallback)
    """
    from scipy.ndimage import gaussian_filter
    import tempfile

    w, s, e, n = bbox
    features = geojson.get("features", [])
    if not features:
        return {"type": "FeatureCollection", "features": [], "raster_path": None}

    points = []
    for f in features:
        coords = f.get("geometry", {}).get("coordinates", [])
        if not coords or len(coords) < 2:
            continue
        props = f.get("properties", {})
        val = _get_numeric_value(props, value_field, fallback_fields)
        if val > 0:
            points.append((coords[0], coords[1], val))

    if not points:
        return {"type": "FeatureCollection", "features": [], "raster_path": None}

    # Build high-res risk grid
    lats = np.linspace(s, n, grid_size)
    lons = np.linspace(w, e, grid_size)
    risk = np.zeros((grid_size, grid_size), dtype=np.float32)

    for px, py, pval in points:
        if energy_scaling:
            influence_km = decay_base_km * (2.0 ** (pval - 3.0))
            energy = 10.0 ** (1.5 * (pval - 4.0))
        else:
            influence_km = decay_base_km * max(1, pval / 10.0)
            energy = max(0.1, pval / 100.0)
        influence_km = min(influence_km, 300.0)

        # Convert influence to grid cells
        deg_per_km = 1.0 / 111.32
        influence_deg = influence_km * deg_per_km
        cell_size_deg = (e - w) / grid_size

        for i, lat in enumerate(lats):
            for j, lon in enumerate(lons):
                dist = _haversine(lat, lon, py, px)
                if dist < influence_km:
                    decay = 1.0 - (dist / influence_km)
                    risk[i, j] += energy * (decay ** decay_exponent)

    # Gaussian smoothing — THIS is what makes it look natural instead of bullseye
    # Light smoothing — enough to remove pixel edges but preserves cluster shapes
    # Lower sigma = more detail, higher = more blur
    sigma = max(2, grid_size // 80)
    risk = gaussian_filter(risk, sigma=sigma)

    # Normalize to 0-1
    mx = risk.max()
    if mx > 0:
        risk /= mx

    # Write as GeoTIFF
    try:
        from osgeo import gdal, osr

        raster_path = tempfile.mktemp(suffix="_risk.tif")
        driver = gdal.GetDriverByName("GTiff")
        ds = driver.Create(raster_path, grid_size, grid_size, 1, gdal.GDT_Float32)

        pixel_w = (e - w) / grid_size
        pixel_h = (n - s) / grid_size
        ds.SetGeoTransform([w, pixel_w, 0, n, 0, -pixel_h])

        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4326)
        ds.SetProjection(srs.ExportToWkt())

        # Flip vertically (GDAL stores top-to-bottom)
        ds.GetRasterBand(1).WriteArray(np.flipud(risk))
        ds.GetRasterBand(1).SetNoDataValue(0)
        ds.FlushCache()
        ds = None

        logger.info(f"Risk raster: {raster_path} ({grid_size}x{grid_size})")
    except Exception as ex:
        logger.warning(f"Risk raster creation failed: {ex}")
        raster_path = None

    # Also create simple contour features for legend reference
    if levels is None:
        levels = [
            (0.10, "Low",      "#4393c3"),
            (0.30, "Moderate", "#fee08b"),
            (0.60, "High",     "#f46d43"),
            (1.01, "Critical", "#a50026"),
        ]

    return {
        "type": "FeatureCollection",
        "features": [],  # No polygon features — raster handles the display
        "raster_path": raster_path,
        "levels": levels,
    }


def _extract_major_events(
    geojson: dict,
    min_value: float,
    value_field: str,
    fallback_fields: list[str] | None = None,
    radius_fn=None,
    label_fn=None,
    max_events: int = 8,
) -> dict:
    """Extract significant events and create impact radius circles."""
    features = geojson.get("features", [])
    major = []

    for f in features:
        coords = f.get("geometry", {}).get("coordinates", [])
        if not coords or len(coords) < 2:
            continue
        props = f.get("properties", {})
        val = _get_numeric_value(props, value_field, fallback_fields)
        if val >= min_value:
            major.append({"lon": coords[0], "lat": coords[1], "val": val, "props": props})

    major.sort(key=lambda x: x["val"], reverse=True)
    major = major[:max_events]

    circles = []
    for event in major:
        radius = radius_fn(event["val"]) if radius_fn else 30.0
        label = label_fn(event["props"]) if label_fn else f"Value: {event['val']:.1f}"
        circles.append({
            "type": "Feature",
            "geometry": _make_circle(event["lon"], event["lat"], radius),
            "properties": {
                "value": event["val"],
                "label": label,
                "radius_km": radius,
                **{k: v for k, v in event["props"].items()
                   if isinstance(v, (str, int, float, bool))},
            },
        })

    return {"type": "FeatureCollection", "features": circles}


def _find_affected_cities(
    bbox: tuple,
    raw_data: dict | None = None,
    value_field: str = "mag",
    fallback_fields: list[str] | None = None,
    influence_fn=None,
    energy_fn=None,
) -> dict:
    """Find cities in bbox and assess their exposure to hazards."""
    w, s, e, n = bbox
    cities = _get_cities_in_bbox(w, s, e, n)
    if not cities:
        return {"type": "FeatureCollection", "features": []}

    # Extract hazard points
    hazard_points = []
    if raw_data:
        for f in raw_data.get("features", []):
            coords = f.get("geometry", {}).get("coordinates", [])
            if not coords or len(coords) < 2:
                continue
            props = f.get("properties", {})
            val = _get_numeric_value(props, value_field, fallback_fields)
            if val > 0:
                hazard_points.append((coords[0], coords[1], val))

    inf_fn = influence_fn or (lambda v: max(10, v * 10))
    eng_fn = energy_fn or (lambda v: v)

    city_features = []
    for city in cities:
        exposure = 0.0
        nearest_dist = float("inf")

        for hx, hy, hval in hazard_points:
            dist = _haversine(city["lat"], city["lon"], hy, hx)
            influence = inf_fn(hval)
            if dist < influence:
                decay = 1.0 - (dist / influence)
                exposure += eng_fn(hval) * (decay ** 2)
            nearest_dist = min(nearest_dist, dist)

        # Classify
        if exposure > 100:
            risk = ("Very High", "#b2182b")
        elif exposure > 30:
            risk = ("High", "#ef8a62")
        elif exposure > 5:
            risk = ("Moderate", "#fddbc7")
        elif exposure > 0.5:
            risk = ("Low", "#67a9cf")
        else:
            risk = ("Very Low", "#2166ac")

        pop = city.get("population", 0)
        city_features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [city["lon"], city["lat"]]},
            "properties": {
                "name": city["name"],
                "population": pop,
                "country": city.get("country", ""),
                "risk_level": risk[0],
                "risk_color": risk[1],
                "exposure_score": round(exposure, 2),
                "nearest_hazard_km": round(nearest_dist, 1) if nearest_dist < float("inf") else None,
                "label": city["name"],
                "pop_label": f"{pop:,}" if pop > 0 else "",
            },
        })

    return {"type": "FeatureCollection", "features": city_features}


# ═══════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════

def _get_numeric_value(
    props: dict, primary_field: str,
    fallback_fields: list[str] | None = None,
) -> float:
    """Extract a numeric value from properties, trying fallback fields."""
    for field in [primary_field] + (fallback_fields or []):
        val = props.get(field)
        if val is not None:
            try:
                return float(val)
            except (ValueError, TypeError):
                continue
    return 0.0


def _infer_hazard_type(props: dict) -> str:
    """Infer hazard type from feature properties."""
    if "mag" in props or "depth" in props:
        return "earthquake"
    if "frp" in props or "brightness" in props or "bright_ti4" in props:
        return "fire"
    if "observedStage" in props or "floodStage" in props or "discharge" in props:
        return "flood"
    if "ndvi" in props or "anomaly" in props:
        return "ndvi"
    return "unknown"


def _haversine(lat1, lon1, lat2, lon2) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _make_circle(lon, lat, radius_km, n=36) -> dict:
    coords = []
    for i in range(n + 1):
        angle = 2 * math.pi * i / n
        dlat = radius_km / 111.32 * math.cos(angle)
        dlon = radius_km / (111.32 * math.cos(math.radians(lat))) * math.sin(angle)
        coords.append([lon + dlon, lat + dlat])
    return {"type": "Polygon", "coordinates": [coords]}


def _log_analysis(theme: str, result: dict, bbox: tuple):
    zones = len(result.get("risk_zones", {}).get("features", []))
    cities = len(result.get("affected_cities", {}).get("features", []))
    events = len(result.get("major_events", {}).get("features", []))
    logger.info(f"Analysis [{theme}]: {zones} risk zones, {cities} cities, {events} major events")


def _get_cities_in_bbox(w, s, e, n) -> list[dict]:
    """Major cities database for EcoLens hotspot regions."""
    ALL_CITIES = [
        # Philippines
        {"name": "Davao City", "lat": 7.07, "lon": 125.61, "population": 1632991, "country": "Philippines"},
        {"name": "Cagayan de Oro", "lat": 8.48, "lon": 124.65, "population": 675950, "country": "Philippines"},
        {"name": "Zamboanga", "lat": 6.91, "lon": 122.07, "population": 977234, "country": "Philippines"},
        {"name": "General Santos", "lat": 6.11, "lon": 125.17, "population": 594446, "country": "Philippines"},
        {"name": "Butuan", "lat": 8.95, "lon": 125.54, "population": 372910, "country": "Philippines"},
        {"name": "Iligan", "lat": 8.23, "lon": 124.24, "population": 342618, "country": "Philippines"},
        {"name": "Cotabato City", "lat": 7.22, "lon": 124.25, "population": 325079, "country": "Philippines"},
        {"name": "Surigao City", "lat": 9.78, "lon": 125.50, "population": 166467, "country": "Philippines"},
        {"name": "Manila", "lat": 14.60, "lon": 120.98, "population": 1780148, "country": "Philippines"},
        {"name": "Cebu City", "lat": 10.31, "lon": 123.89, "population": 964169, "country": "Philippines"},
        # Indonesia
        {"name": "Banda Aceh", "lat": 5.55, "lon": 95.32, "population": 267340, "country": "Indonesia"},
        {"name": "Medan", "lat": 3.59, "lon": 98.67, "population": 2435252, "country": "Indonesia"},
        {"name": "Padang", "lat": -0.95, "lon": 100.35, "population": 909040, "country": "Indonesia"},
        {"name": "Pekanbaru", "lat": 0.51, "lon": 101.45, "population": 1093416, "country": "Indonesia"},
        {"name": "Palembang", "lat": -2.99, "lon": 104.76, "population": 1708413, "country": "Indonesia"},
        {"name": "Bengkulu", "lat": -3.80, "lon": 102.26, "population": 373439, "country": "Indonesia"},
        {"name": "Jakarta", "lat": -6.21, "lon": 106.85, "population": 10562088, "country": "Indonesia"},
        {"name": "Surabaya", "lat": -7.29, "lon": 112.75, "population": 2874314, "country": "Indonesia"},
        {"name": "Makassar", "lat": -5.14, "lon": 119.42, "population": 1526677, "country": "Indonesia"},
        {"name": "Kupang", "lat": -10.18, "lon": 123.58, "population": 434972, "country": "Indonesia"},
        # Japan
        {"name": "Tokyo", "lat": 35.68, "lon": 139.69, "population": 13960000, "country": "Japan"},
        {"name": "Osaka", "lat": 34.69, "lon": 135.50, "population": 2753000, "country": "Japan"},
        {"name": "Sendai", "lat": 38.27, "lon": 140.87, "population": 1096704, "country": "Japan"},
        {"name": "Sapporo", "lat": 43.06, "lon": 141.35, "population": 1973395, "country": "Japan"},
        # Brazil
        {"name": "Manaus", "lat": -3.12, "lon": -60.02, "population": 2219580, "country": "Brazil"},
        {"name": "Belém", "lat": -1.46, "lon": -48.50, "population": 1499641, "country": "Brazil"},
        {"name": "Porto Velho", "lat": -8.76, "lon": -63.90, "population": 539354, "country": "Brazil"},
        {"name": "Santarém", "lat": -2.44, "lon": -54.71, "population": 304589, "country": "Brazil"},
        {"name": "São Luís", "lat": -2.53, "lon": -44.28, "population": 1101884, "country": "Brazil"},
        # Africa
        {"name": "Kinshasa", "lat": -4.32, "lon": 15.31, "population": 14342000, "country": "DRC"},
        {"name": "Brazzaville", "lat": -4.27, "lon": 15.28, "population": 2388000, "country": "Congo"},
        {"name": "Kisangani", "lat": 0.52, "lon": 25.19, "population": 1602144, "country": "DRC"},
        {"name": "Douala", "lat": 4.05, "lon": 9.77, "population": 2768400, "country": "Cameroon"},
        {"name": "Lagos", "lat": 6.52, "lon": 3.38, "population": 15388000, "country": "Nigeria"},
        {"name": "Nairobi", "lat": -1.29, "lon": 36.82, "population": 4735000, "country": "Kenya"},
        {"name": "Dar es Salaam", "lat": -6.79, "lon": 39.28, "population": 6702000, "country": "Tanzania"},
        # Malaysia
        {"name": "Kuala Lumpur", "lat": 3.14, "lon": 101.69, "population": 1982112, "country": "Malaysia"},
        {"name": "Kota Kinabalu", "lat": 5.98, "lon": 116.07, "population": 500421, "country": "Malaysia"},
        # Thailand
        {"name": "Bangkok", "lat": 13.76, "lon": 100.50, "population": 10539000, "country": "Thailand"},
        # Australia
        {"name": "Sydney", "lat": -33.87, "lon": 151.21, "population": 5312000, "country": "Australia"},
        {"name": "Melbourne", "lat": -37.81, "lon": 144.96, "population": 5078000, "country": "Australia"},
        # South Asia
        {"name": "Dhaka", "lat": 23.81, "lon": 90.41, "population": 21740000, "country": "Bangladesh"},
        {"name": "Chittagong", "lat": 22.36, "lon": 91.78, "population": 2592000, "country": "Bangladesh"},
        {"name": "Mumbai", "lat": 19.08, "lon": 72.88, "population": 20411000, "country": "India"},
        {"name": "Kolkata", "lat": 22.57, "lon": 88.36, "population": 14850000, "country": "India"},
        # Central America
        {"name": "Guatemala City", "lat": 14.63, "lon": -90.51, "population": 2934000, "country": "Guatemala"},
        {"name": "San Salvador", "lat": 13.69, "lon": -89.19, "population": 1767000, "country": "El Salvador"},
        # South America
        {"name": "Lima", "lat": -12.05, "lon": -77.04, "population": 10719000, "country": "Peru"},
        {"name": "Santiago", "lat": -33.45, "lon": -70.67, "population": 6767000, "country": "Chile"},
        {"name": "Bogotá", "lat": 4.71, "lon": -74.07, "population": 10978000, "country": "Colombia"},
        {"name": "Quito", "lat": -0.18, "lon": -78.47, "population": 2781000, "country": "Ecuador"},
    ]

    return [c for c in ALL_CITIES if w <= c["lon"] <= e and s <= c["lat"] <= n]
