"""Real-time flood monitoring using NOAA NWPS, GloFAS, and Open-Meteo Flood API.

Combines gauge observations from NOAA National Water Prediction Service,
river discharge forecasts from the Open-Meteo Flood API (backed by GloFAS),
and optional Copernicus EWDS alerts for global coverage.
"""

import logging
import math
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NOAA_NWPS_BASE = "https://api.water.noaa.gov/nwps/v1"
OPEN_METEO_FLOOD_BASE = "https://flood-api.open-meteo.com/v1/flood"
ECCC_HYDROMETRIC_URL = (
    "https://api.weather.gc.ca/collections/hydrometric-realtime/items"
)

# Cache flood gauge data for 10 minutes
_gauge_cache: TTLCache = TTLCache(maxsize=32, ttl=600)
_forecast_cache: TTLCache = TTLCache(maxsize=128, ttl=1800)
_eccc_cache: TTLCache = TTLCache(maxsize=32, ttl=600)

# Severity ordering for comparisons
SEVERITY_ORDER = {
    "no_flooding": 0,
    "action": 1,
    "minor": 2,
    "moderate": 3,
    "major": 4,
}

# Buffer radii in degrees (~111 km per degree at equator)
BUFFER_RADII = {
    "no_flooding": 0.0,
    "action": 0.01,
    "minor": 0.02,
    "moderate": 0.04,
    "major": 0.08,
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_flood_gauges(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Fetch flood gauge observations from NOAA NWPS.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.

    Returns:
        GeoJSON FeatureCollection of gauge point features.  Properties
        include ``status``, ``observed_stage``, ``flood_stage``,
        ``gauge_id``, and ``name``.
    """
    cache_key = f"gauges_{bbox}"
    if cache_key in _gauge_cache:
        return _gauge_cache[cache_key]

    features: List[Dict[str, Any]] = []

    try:
        params: Dict[str, Any] = {
            "srid": "EPSG_4326",
            "limit": 500,
        }
        if bbox:
            w, s, e, n = bbox
            params["bbox"] = f"{w},{s},{e},{n}"

        resp = requests.get(
            f"{NOAA_NWPS_BASE}/gauges",
            params=params,
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        for gauge in data.get("gauges", []):
            lat = gauge.get("latitude")
            lon = gauge.get("longitude")
            if lat is None or lon is None:
                continue

            status = _parse_gauge_status(gauge)
            observed = gauge.get("status", {}).get("observed", {})
            flood_stage = gauge.get("flood", {}).get("stage")

            feature = {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [float(lon), float(lat)],
                },
                "properties": {
                    "gauge_id": gauge.get("lid", ""),
                    "name": gauge.get("name", "Unknown Gauge"),
                    "status": status,
                    "observed_stage": observed.get("primary"),
                    "observed_unit": observed.get("primaryUnit", "ft"),
                    "flood_stage": flood_stage,
                    "moderate_stage": gauge.get("moderate", {}).get("stage"),
                    "major_stage": gauge.get("major", {}).get("stage"),
                    "wfo": gauge.get("wfo", ""),
                    "state": gauge.get("state", ""),
                    "hazard_type": "flood",
                    "source": "NOAA_NWPS",
                },
            }
            features.append(feature)

    except Exception as exc:
        logger.error("NOAA NWPS gauge fetch failed: %s", exc)

    result = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "NOAA_NWPS",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
    _gauge_cache[cache_key] = result
    return result


def fetch_canadian_hydrometric(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Fetch real-time Canadian river/lake gauges from ECCC GeoMet API.

    Covers Canadian waterways the US-only NOAA NWPS doesn't reach.
    Free, no auth. Returns GeoJSON.
    """
    cache_key = f"eccc_{bbox}"
    if cache_key in _eccc_cache:
        return _eccc_cache[cache_key]

    features: List[Dict[str, Any]] = []
    try:
        params: Dict[str, Any] = {"f": "json", "limit": 500}
        if bbox:
            w, s, e, n = bbox
            params["bbox"] = f"{w},{s},{e},{n}"

        resp = requests.get(ECCC_HYDROMETRIC_URL, params=params, timeout=20)
        resp.raise_for_status()
        data = resp.json()

        for item in data.get("features", []):
            geom = item.get("geometry") or {}
            coords = geom.get("coordinates")
            if not coords or len(coords) < 2:
                continue
            props = item.get("properties", {}) or {}
            level = props.get("LEVEL")
            discharge = props.get("DISCHARGE")

            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": coords[:2]},
                "properties": {
                    "gauge_id": props.get("STATION_NUMBER", ""),
                    "name": props.get("STATION_NAME", "Unknown station"),
                    "observed_stage": level,
                    "observed_unit": "m",
                    "discharge_cms": discharge,
                    "datetime": props.get("DATETIME", ""),
                    "province": props.get("PROV_TERR_STATE_LOC", ""),
                    "status": "no_flooding",
                    "hazard_type": "flood",
                    "source": "ECCC_HYDROMETRIC",
                },
            })
    except Exception as exc:
        logger.error("ECCC hydrometric fetch failed: %s", exc)

    result = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "ECCC_HYDROMETRIC",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
    _eccc_cache[cache_key] = result
    return result


def fetch_flood_gauges_combined(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Combined NOAA + ECCC flood gauge fetch.

    Returns both US (NOAA NWPS) and Canadian (ECCC) gauges in one
    GeoJSON FeatureCollection — fixes the "no signals in Canada" gap.
    """
    us = fetch_flood_gauges(bbox=bbox)
    ca = fetch_canadian_hydrometric(bbox=bbox)
    return {
        "type": "FeatureCollection",
        "features": us.get("features", []) + ca.get("features", []),
        "metadata": {
            "source": "NOAA_NWPS + ECCC_HYDROMETRIC",
            "count": len(us.get("features", [])) + len(ca.get("features", [])),
            "us_count": len(us.get("features", [])),
            "ca_count": len(ca.get("features", [])),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def fetch_flood_forecast(lat: float, lon: float) -> Dict[str, Any]:
    """Retrieve 7-day river discharge forecast from Open-Meteo Flood API.

    Args:
        lat: Latitude of the query point.
        lon: Longitude of the query point.

    Returns:
        Dictionary containing daily river discharge forecasts, peak
        discharge information, and a flood risk assessment.
    """
    cache_key = f"forecast_{round(lat, 3)}_{round(lon, 3)}"
    if cache_key in _forecast_cache:
        return _forecast_cache[cache_key]

    try:
        resp = requests.get(
            OPEN_METEO_FLOOD_BASE,
            params={
                "latitude": lat,
                "longitude": lon,
                "daily": "river_discharge",
                "forecast_days": 7,
            },
            timeout=20,
        )
        resp.raise_for_status()
        data = resp.json()

        daily = data.get("daily", {})
        times = daily.get("time", [])
        discharges = daily.get("river_discharge", [])

        forecast_days: List[Dict[str, Any]] = []
        peak_discharge = 0.0
        peak_date = ""

        for t, d in zip(times, discharges):
            discharge_val = d if d is not None else 0.0
            forecast_days.append({"date": t, "river_discharge_m3s": discharge_val})
            if discharge_val > peak_discharge:
                peak_discharge = discharge_val
                peak_date = t

        # Simple risk heuristic based on discharge magnitude
        if peak_discharge > 5000:
            risk = "high"
        elif peak_discharge > 1000:
            risk = "moderate"
        elif peak_discharge > 200:
            risk = "low"
        else:
            risk = "minimal"

        result: Dict[str, Any] = {
            "location": {"lat": lat, "lon": lon},
            "forecast": forecast_days,
            "peak": {
                "discharge_m3s": round(peak_discharge, 2),
                "date": peak_date,
            },
            "flood_risk": risk,
            "source": "Open-Meteo_Flood_API",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        _forecast_cache[cache_key] = result
        return result

    except Exception as exc:
        logger.error("Open-Meteo Flood forecast failed: %s", exc)
        return {
            "location": {"lat": lat, "lon": lon},
            "forecast": [],
            "peak": {"discharge_m3s": 0, "date": ""},
            "flood_risk": "unknown",
            "error": str(exc),
            "source": "Open-Meteo_Flood_API",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def fetch_glofas_alerts() -> Dict[str, Any]:
    """Fetch GloFAS global flood alerts from Copernicus EWDS.

    GloFAS alerts are typically distributed through the Copernicus
    Emergency Early Warning and Dissemination System.  This function
    returns cached/summary data when the live feed is not accessible.

    Returns:
        Dictionary with a list of alert records.
    """
    # GloFAS real-time alerts require CDS API credentials.  Provide a
    # graceful degradation path.
    cds_url = os.environ.get("COPERNICUS_CDS_URL")
    cds_key = os.environ.get("COPERNICUS_CDS_KEY")

    if not cds_url or not cds_key:
        logger.info(
            "Copernicus CDS credentials not configured; returning empty GloFAS alerts."
        )
        return {
            "alerts": [],
            "source": "GloFAS_EWDS",
            "status": "credentials_not_configured",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    try:
        resp = requests.get(
            f"{cds_url}/glofas-forecast",
            headers={"Authorization": f"Bearer {cds_key}"},
            timeout=30,
        )
        resp.raise_for_status()
        return {
            "alerts": resp.json().get("alerts", []),
            "source": "GloFAS_EWDS",
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error("GloFAS alert fetch failed: %s", exc)
        return {
            "alerts": [],
            "source": "GloFAS_EWDS",
            "status": "error",
            "error": str(exc),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def generate_flood_zones(
    gauges_geojson: Dict[str, Any],
    dem_data: Optional[bytes] = None,
) -> Dict[str, Any]:
    """Generate flood risk zone polygons around gauge locations.

    When DEM data is unavailable, the function uses a simple circular
    buffer whose radius scales with flood severity.  When DEM bytes
    (GeoTIFF) are provided, terrain-aware modelling is performed so
    that the flood zone fills only grid cells below the flood stage
    elevation.

    Args:
        gauges_geojson: GeoJSON FeatureCollection from
            :func:`fetch_flood_gauges`.
        dem_data: Optional GeoTIFF bytes for terrain-aware modelling.

    Returns:
        GeoJSON FeatureCollection of polygon flood zone geometries.
    """
    features: List[Dict[str, Any]] = []

    for gauge_feat in gauges_geojson.get("features", []):
        props = gauge_feat.get("properties", {})
        status = props.get("status", "no_flooding")
        if status == "no_flooding":
            continue

        coords = gauge_feat["geometry"]["coordinates"]
        lon, lat = coords[0], coords[1]
        radius_deg = BUFFER_RADII.get(status, 0.02)

        if dem_data is not None:
            polygon = _terrain_aware_zone(lon, lat, radius_deg, dem_data, props)
        else:
            polygon = _circular_buffer(lon, lat, radius_deg)

        severity_label = classify_flood_severity(
            observed_stage=props.get("observed_stage"),
            flood_stage=props.get("flood_stage"),
            moderate_stage=props.get("moderate_stage"),
            major_stage=props.get("major_stage"),
        )

        features.append({
            "type": "Feature",
            "geometry": polygon,
            "properties": {
                "gauge_id": props.get("gauge_id", ""),
                "name": props.get("name", ""),
                "severity": severity_label,
                "status": status,
                "hazard_type": "flood_zone",
                "source": "computed",
            },
        })

    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "flood_zone_model",
            "count": len(features),
            "dem_enhanced": dem_data is not None,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def classify_flood_severity(
    observed_stage: Optional[float],
    flood_stage: Optional[float],
    moderate_stage: Optional[float],
    major_stage: Optional[float],
) -> str:
    """Classify flood severity from stage readings.

    Args:
        observed_stage: Current observed river stage (ft or m).
        flood_stage: Stage at which flooding begins.
        moderate_stage: Stage for moderate flooding.
        major_stage: Stage for major flooding.

    Returns:
        ``"no_flooding"``, ``"action"``, ``"minor"``, ``"moderate"``,
        or ``"major"``.
    """
    if observed_stage is None or flood_stage is None:
        return "no_flooding"

    try:
        obs = float(observed_stage)
        flood = float(flood_stage)
    except (ValueError, TypeError):
        return "no_flooding"

    if major_stage is not None and obs >= float(major_stage):
        return "major"
    if moderate_stage is not None and obs >= float(moderate_stage):
        return "moderate"
    if obs >= flood:
        return "minor"
    if obs >= flood * 0.9:
        return "action"
    return "no_flooding"


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _parse_gauge_status(gauge: Dict[str, Any]) -> str:
    """Extract a simple status string from a NOAA gauge object."""
    status_obj = gauge.get("status", {})
    if isinstance(status_obj, str):
        return status_obj

    # The NWPS API may include a 'floodCategory' or 'observed' sub-object
    category = (
        status_obj.get("floodCategory", "")
        or status_obj.get("flood_category", "")
    )
    if category:
        return category.lower().replace(" ", "_")

    return "no_flooding"


def _circular_buffer(
    lon: float,
    lat: float,
    radius_deg: float,
    num_points: int = 32,
) -> Dict[str, Any]:
    """Create a circular polygon (approximation) in GeoJSON."""
    coords = []
    for i in range(num_points + 1):
        angle = 2 * math.pi * i / num_points
        dx = radius_deg * math.cos(angle)
        # Correct for longitude distortion at latitude
        dy = radius_deg * math.sin(angle) / max(math.cos(math.radians(lat)), 0.01)
        coords.append([round(lon + dx, 6), round(lat + dy, 6)])
    return {"type": "Polygon", "coordinates": [coords]}


def _terrain_aware_zone(
    lon: float,
    lat: float,
    radius_deg: float,
    dem_data: bytes,
    gauge_props: Dict[str, Any],
) -> Dict[str, Any]:
    """Create a terrain-aware flood zone using DEM data.

    Attempts to use rasterio to read the DEM, then fills cells within
    the buffer radius that lie below the flood-stage elevation.  Falls
    back to a circular buffer on error.
    """
    try:
        import io as _io

        import numpy as np
        import rasterio
        from rasterio.transform import rowcol

        with rasterio.open(_io.BytesIO(dem_data)) as src:
            dem_array = src.read(1)
            transform = src.transform

            # Gauge position in pixel space
            row_c, col_c = rowcol(transform, lon, lat)
            flood_elev = dem_array[row_c, col_c]

            # Add observed stage above terrain to get water surface elevation
            observed = gauge_props.get("observed_stage")
            if observed is not None:
                flood_elev += float(observed)

            # Determine pixel radius
            pixel_size_deg = abs(transform.a)
            px_radius = max(1, int(radius_deg / pixel_size_deg))

            # Collect flooded cells
            flooded_coords: List[List[float]] = []
            r_min = max(0, row_c - px_radius)
            r_max = min(dem_array.shape[0], row_c + px_radius)
            c_min = max(0, col_c - px_radius)
            c_max = min(dem_array.shape[1], col_c + px_radius)

            for r in range(r_min, r_max):
                for c in range(c_min, c_max):
                    if dem_array[r, c] <= flood_elev:
                        x, y = rasterio.transform.xy(transform, r, c)
                        flooded_coords.append([round(x, 6), round(y, 6)])

            if len(flooded_coords) < 4:
                return _circular_buffer(lon, lat, radius_deg)

            # Compute convex hull of flooded cells
            from shapely.geometry import MultiPoint

            hull = MultiPoint(flooded_coords).convex_hull
            if hull.geom_type == "Polygon":
                return {
                    "type": "Polygon",
                    "coordinates": [
                        [[round(x, 6), round(y, 6)] for x, y in hull.exterior.coords]
                    ],
                }

        return _circular_buffer(lon, lat, radius_deg)

    except Exception as exc:
        logger.warning("Terrain-aware flood zone failed: %s; using buffer.", exc)
        return _circular_buffer(lon, lat, radius_deg)
