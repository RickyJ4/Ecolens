"""Real-time wildfire monitoring using NASA FIRMS and NIFC data.

Integrates NASA FIRMS (Fire Information for Resource Management System) VIIRS
active fire detections with NIFC (National Interagency Fire Center) perimeter
data to provide comprehensive wildfire situational awareness.
"""

import csv
import io
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

NASA_FIRMS_MAP_KEY = os.environ.get("NASA_FIRMS_MAP_KEY", "")
FIRMS_BASE_URL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
NIFC_PERIMETERS_URL = (
    "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/"
    "WFIGS_Interagency_Perimeters/FeatureServer/0/query"
)
# BC Wildfire Service - Open Government BC active fires layer (ArcGIS)
BC_WILDFIRE_ACTIVE_URL = (
    "https://services6.arcgis.com/ubm4tcTYICKBpist/arcgis/rest/services/"
    "BCWS_ActiveFires_PublicView/FeatureServer/0/query"
)

# In-memory TTL cache: 300 seconds (5 min) for active fire queries
_fire_cache: TTLCache = TTLCache(maxsize=64, ttl=300)
_bc_fire_cache: TTLCache = TTLCache(maxsize=32, ttl=300)

# Severity classification thresholds
BRIGHTNESS_THRESHOLDS = {"high": 400, "extreme": 500}
FRP_THRESHOLDS = {"moderate": 30, "high": 100, "extreme": 300}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_active_fires(
    bbox: Optional[Tuple[float, float, float, float]] = None,
    country: Optional[str] = None,
    days: int = 1,
) -> Dict[str, Any]:
    """Fetch active fire detections as a GeoJSON FeatureCollection.

    Tries NASA FIRMS VIIRS SNPP NRT first; falls back to NIFC ArcGIS
    FeatureServer if FIRMS is unavailable or returns no data.

    Args:
        bbox: Bounding box as (west, south, east, north) in EPSG:4326.
        country: ISO-3166 three-letter country code (e.g. ``"USA"``).
        days: Number of trailing days to query (1-10).

    Returns:
        GeoJSON FeatureCollection with point features for each fire
        detection.  Properties include ``brightness``, ``confidence``,
        ``satellite``, ``acq_date``, ``frp``, ``severity``, and
        ``source``.
    """
    cache_key = f"fires_{bbox}_{country}_{days}"
    if cache_key in _fire_cache:
        return _fire_cache[cache_key]

    days = max(1, min(days, 10))

    # Try NASA FIRMS first
    result = _fetch_firms(bbox, country, days)
    if result and result["features"]:
        _fire_cache[cache_key] = result
        return result

    # Fallback to NIFC perimeters converted to centroids
    logger.warning("FIRMS returned no data; falling back to NIFC perimeters.")
    result = _fetch_nifc_as_points(bbox)
    _fire_cache[cache_key] = result
    return result


def fetch_bc_wildfires(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Fetch active BC Wildfire Service incidents (Public View layer).

    Adds BC-specific incident detail (incident name, suppression status,
    incident number, hectares) that FIRMS satellite detections don't carry.
    Free, no auth. Returns GeoJSON.
    """
    cache_key = f"bcw_{bbox}"
    if cache_key in _bc_fire_cache:
        return _bc_fire_cache[cache_key]

    params: Dict[str, str] = {
        "where": "1=1",
        "outFields": "*",
        "f": "geojson",
        "resultRecordCount": "500",
    }
    if bbox:
        w, s, e, n = bbox
        params["geometry"] = f"{w},{s},{e},{n}"
        params["geometryType"] = "esriGeometryEnvelope"
        params["inSR"] = "4326"
        params["spatialRel"] = "esriSpatialRelIntersects"

    features: List[Dict[str, Any]] = []
    try:
        resp = requests.get(BC_WILDFIRE_ACTIVE_URL, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        for feat in data.get("features", []):
            props = feat.get("properties", {}) or {}
            status = (props.get("FIRE_STATUS") or "").lower()
            severity = "extreme" if status == "out of control" else (
                "high" if status == "being held" else "moderate"
            )
            features.append({
                "type": "Feature",
                "geometry": feat.get("geometry"),
                "properties": {
                    **props,
                    "incident_name": props.get("INCIDENT_NAME", ""),
                    "incident_number": props.get("FIRE_NUMBER", ""),
                    "fire_status": props.get("FIRE_STATUS", ""),
                    "discovered_date": props.get("DISCOVERY_DATE", ""),
                    "size_ha": props.get("CURRENT_SIZE", 0),
                    "fire_cause": props.get("FIRE_CAUSE", ""),
                    "severity": severity,
                    "hazard_type": "fire",
                    "source": "BC_WILDFIRE_SERVICE",
                },
            })
    except Exception as exc:
        logger.error("BC Wildfire Service fetch failed: %s", exc)

    result = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "BC_WILDFIRE_SERVICE",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
    _bc_fire_cache[cache_key] = result
    return result


def fetch_active_fires_combined(
    bbox: Optional[Tuple[float, float, float, float]] = None,
    days: int = 2,
) -> Dict[str, Any]:
    """Combined NASA FIRMS + BC Wildfire Service fetch.

    FIRMS provides satellite hotspot detections (global). BC Wildfire
    Service provides incident-level detail (BC only). Both merged into
    one GeoJSON. BC features are tagged source=BC_WILDFIRE_SERVICE so
    the UI can render them differently if desired.
    """
    firms = fetch_active_fires(bbox=bbox, days=days)
    bcw = fetch_bc_wildfires(bbox=bbox)
    return {
        "type": "FeatureCollection",
        "features": firms.get("features", []) + bcw.get("features", []),
        "metadata": {
            "source": "FIRMS + BC_WILDFIRE_SERVICE",
            "count": len(firms.get("features", [])) + len(bcw.get("features", [])),
            "firms_count": len(firms.get("features", [])),
            "bcw_count": len(bcw.get("features", [])),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def get_fire_perimeters(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Fetch active fire perimeter polygons from NIFC ArcGIS FeatureServer.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        GeoJSON FeatureCollection of polygon geometries.
    """
    params: Dict[str, str] = {
        "where": "1=1",
        "outFields": "*",
        "f": "geojson",
        "resultRecordCount": "500",
    }
    if bbox:
        w, s, e, n = bbox
        params["geometry"] = f"{w},{s},{e},{n}"
        params["geometryType"] = "esriGeometryEnvelope"
        params["inSR"] = "4326"
        params["spatialRel"] = "esriSpatialRelIntersects"

    try:
        resp = requests.get(NIFC_PERIMETERS_URL, params=params, timeout=30)
        resp.raise_for_status()
        geojson = resp.json()

        # Enrich features
        for feat in geojson.get("features", []):
            props = feat.get("properties", {})
            props["source"] = "NIFC"
            props["hazard_type"] = "wildfire_perimeter"

        return geojson
    except Exception as exc:
        logger.error("NIFC perimeters request failed: %s", exc)
        return _empty_feature_collection()


def classify_fire_severity(
    brightness: float,
    frp: float,
    confidence: str,
) -> str:
    """Classify an individual fire detection into a severity level.

    The classification uses a weighted decision combining satellite
    brightness temperature, fire radiative power (FRP), and the
    confidence flag from VIIRS.

    Args:
        brightness: Brightness temperature in Kelvin (bright_ti4 channel).
        frp: Fire Radiative Power in MW.
        confidence: VIIRS confidence string (``"low"``, ``"nominal"``,
            ``"high"``).

    Returns:
        One of ``"low"``, ``"moderate"``, ``"high"``, or ``"extreme"``.
    """
    score = 0.0

    # Brightness contribution (0-3)
    if brightness >= BRIGHTNESS_THRESHOLDS["extreme"]:
        score += 3.0
    elif brightness >= BRIGHTNESS_THRESHOLDS["high"]:
        score += 2.0
    elif brightness >= 350:
        score += 1.0

    # FRP contribution (0-3)
    if frp >= FRP_THRESHOLDS["extreme"]:
        score += 3.0
    elif frp >= FRP_THRESHOLDS["high"]:
        score += 2.0
    elif frp >= FRP_THRESHOLDS["moderate"]:
        score += 1.0

    # Confidence contribution (0-1)
    conf_map = {"high": 1.0, "nominal": 0.5, "low": 0.0}
    score += conf_map.get(str(confidence).lower().strip(), 0.3)

    if score >= 5.5:
        return "extreme"
    if score >= 3.5:
        return "high"
    if score >= 1.5:
        return "moderate"
    return "low"


def calculate_fire_risk(
    ndvi: float,
    temperature: float,
    humidity: float,
    wind_speed: float,
) -> float:
    """Estimate fire ignition/spread risk on a 0-1 scale.

    This is a simplified analogue of the Canadian Fire Weather Index
    (FWI) using readily-available environmental variables.

    Args:
        ndvi: Normalised Difference Vegetation Index (0-1).  Lower NDVI
            implies drier vegetation, increasing risk.
        temperature: Air temperature in Celsius.
        humidity: Relative humidity as a percentage (0-100).
        wind_speed: Wind speed in m/s.

    Returns:
        Risk score between 0.0 (minimal) and 1.0 (extreme).
    """
    # Vegetation dryness factor (low NDVI = dry = higher risk)
    veg_factor = max(0.0, min(1.0, 1.0 - ndvi))

    # Temperature factor (hotter = higher risk, scaled 0-1 with 45 C cap)
    temp_factor = max(0.0, min(1.0, temperature / 45.0))

    # Humidity factor (lower humidity = higher risk)
    hum_factor = max(0.0, min(1.0, 1.0 - humidity / 100.0))

    # Wind factor (stronger wind = higher risk, capped at 30 m/s)
    wind_factor = max(0.0, min(1.0, wind_speed / 30.0))

    # Weighted combination
    risk = (
        0.30 * veg_factor
        + 0.25 * temp_factor
        + 0.25 * hum_factor
        + 0.20 * wind_factor
    )
    return round(max(0.0, min(1.0, risk)), 4)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _fetch_firms(
    bbox: Optional[Tuple[float, float, float, float]],
    country: Optional[str],
    days: int,
) -> Dict[str, Any]:
    """Query NASA FIRMS VIIRS SNPP NRT CSV endpoint."""
    if not NASA_FIRMS_MAP_KEY:
        logger.warning("NASA_FIRMS_MAP_KEY not set; skipping FIRMS query.")
        return _empty_feature_collection()

    # Build area string
    if bbox:
        w, s, e, n = bbox
        area = f"{w},{s},{e},{n}"
    elif country:
        area = country
    else:
        area = "world"

    url = f"{FIRMS_BASE_URL}/{NASA_FIRMS_MAP_KEY}/VIIRS_SNPP_NRT/{area}/{days}"

    try:
        resp = requests.get(url, timeout=45)
        resp.raise_for_status()
        return _parse_firms_csv(resp.text)
    except Exception as exc:
        logger.error("FIRMS request failed: %s", exc)
        return _empty_feature_collection()


def _parse_firms_csv(csv_text: str) -> Dict[str, Any]:
    """Convert FIRMS CSV response to a GeoJSON FeatureCollection."""
    features: List[Dict[str, Any]] = []
    reader = csv.DictReader(io.StringIO(csv_text))

    for row in reader:
        try:
            lat = float(row.get("latitude", 0))
            lon = float(row.get("longitude", 0))
            brightness = float(row.get("bright_ti4", row.get("brightness", 0)))
            frp = float(row.get("frp", 0))
            confidence = row.get("confidence", "nominal")
            acq_date = row.get("acq_date", "")
            acq_time = row.get("acq_time", "")
            satellite = row.get("satellite", "VIIRS")

            severity = classify_fire_severity(brightness, frp, confidence)

            feature: Dict[str, Any] = {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [lon, lat],
                },
                "properties": {
                    "brightness": brightness,
                    "bright_ti4": float(row.get("bright_ti4", 0)),
                    "bright_ti5": float(row.get("bright_ti5", 0)),
                    "scan": float(row.get("scan", 0)),
                    "track": float(row.get("track", 0)),
                    "confidence": confidence,
                    "satellite": satellite,
                    "acq_date": acq_date,
                    "acq_time": acq_time,
                    "frp": frp,
                    "version": row.get("version", ""),
                    "severity": severity,
                    "source": "NASA_FIRMS",
                    "hazard_type": "wildfire",
                },
            }
            features.append(feature)
        except (ValueError, TypeError) as parse_err:
            logger.debug("Skipping malformed FIRMS row: %s", parse_err)

    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "NASA_FIRMS_VIIRS_SNPP_NRT",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def _fetch_nifc_as_points(
    bbox: Optional[Tuple[float, float, float, float]],
) -> Dict[str, Any]:
    """Fetch NIFC perimeters and convert centroids to point features."""
    perimeters = get_fire_perimeters(bbox)
    features: List[Dict[str, Any]] = []

    for feat in perimeters.get("features", []):
        geom = feat.get("geometry", {})
        coords = geom.get("coordinates")
        if not coords:
            continue

        # Compute simple centroid from the first ring of the first polygon
        try:
            ring = coords
            while isinstance(ring[0][0], (list, tuple)):
                ring = ring[0]
            lons = [c[0] for c in ring]
            lats = [c[1] for c in ring]
            centroid_lon = sum(lons) / len(lons)
            centroid_lat = sum(lats) / len(lats)
        except Exception:
            continue

        props = feat.get("properties", {})
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [centroid_lon, centroid_lat]},
            "properties": {
                "brightness": 0,
                "confidence": "nominal",
                "satellite": "NIFC",
                "acq_date": props.get("FireDiscoveryDateTime", ""),
                "frp": 0,
                "severity": "high",
                "source": "NIFC",
                "hazard_type": "wildfire",
                "fire_name": props.get("IncidentName", "Unknown"),
                "acres": props.get("GISAcres", 0),
            },
        })

    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "NIFC_Fallback",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def _empty_feature_collection() -> Dict[str, Any]:
    """Return an empty GeoJSON FeatureCollection."""
    return {
        "type": "FeatureCollection",
        "features": [],
        "metadata": {
            "source": "none",
            "count": 0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
