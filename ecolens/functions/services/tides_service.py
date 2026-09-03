"""Canadian tides + water levels via the CHS IWLS API.

Replaces the NOAA Tides & Currents listed in the original data plan —
NOAA is US-only and has zero stations in Vancouver / Burrard Inlet.
The Canadian Hydrographic Service (CHS) Integrated Water Level System
(IWLS) is the authoritative source for Canadian coastal stations.

Free, no auth. Public API operated by Fisheries and Oceans Canada.
Docs: https://api-iwls.dfo-mpo.gc.ca/swagger-ui/index.html
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

IWLS_BASE = "https://api-iwls.dfo-mpo.gc.ca/api/v1"

# 10-minute cache for live water levels; 6-hour cache for station metadata
_levels_cache: TTLCache = TTLCache(maxsize=64, ttl=600)
_stations_cache: TTLCache = TTLCache(maxsize=8, ttl=21600)


def fetch_tide_stations(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """List CHS tide/water-level stations, optionally within a bbox.

    Returns GeoJSON FeatureCollection. Each feature carries the station
    code, name, and operating status.
    """
    cache_key = f"stations_{bbox}"
    if cache_key in _stations_cache:
        return _stations_cache[cache_key]

    features: List[Dict[str, Any]] = []
    try:
        resp = requests.get(f"{IWLS_BASE}/stations", timeout=20)
        resp.raise_for_status()
        stations = resp.json() or []

        for s in stations:
            lat = s.get("latitude")
            lon = s.get("longitude")
            if lat is None or lon is None:
                continue
            if bbox:
                w, south, e, n = bbox
                if not (w <= lon <= e and south <= lat <= n):
                    continue
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": {
                    "station_id": s.get("id"),
                    "code": s.get("code"),
                    "name": s.get("officialName") or s.get("operatingDirective", ""),
                    "type": s.get("type", ""),
                    "operating": s.get("operating", False),
                    "time_series": s.get("timeSeries", []),
                    "hazard_type": "tides",
                    "source": "CHS_IWLS",
                },
            })
    except Exception as exc:
        logger.error("CHS IWLS station list failed: %s", exc)

    result = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "source": "CHS_IWLS",
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
    _stations_cache[cache_key] = result
    return result


def fetch_water_level_series(
    station_id: str,
    hours: int = 48,
    time_series_code: str = "wlo",
) -> Dict[str, Any]:
    """Fetch a recent water-level time series for a CHS station.

    Args:
        station_id: CHS IWLS station ID (UUID).
        hours: Lookback window. Max 168 (7 days) per IWLS rate limits.
        time_series_code: "wlo" = observed water level, "wlp" = predicted,
            "wlf" = forecast. Defaults to observed.

    Returns dict with observations: [{eventDate, value, qcFlagCode}].
    """
    cache_key = f"levels_{station_id}_{hours}_{time_series_code}"
    if cache_key in _levels_cache:
        return _levels_cache[cache_key]

    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=min(max(hours, 1), 168))
    params = {
        "time-series-code": time_series_code,
        "from": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "to": end.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    observations: List[Dict[str, Any]] = []
    try:
        resp = requests.get(
            f"{IWLS_BASE}/stations/{station_id}/data",
            params=params,
            timeout=20,
        )
        resp.raise_for_status()
        observations = resp.json() or []
    except Exception as exc:
        logger.error(
            "CHS water-level fetch failed (station=%s): %s", station_id, exc
        )

    result = {
        "station_id": station_id,
        "time_series_code": time_series_code,
        "observations": observations,
        "metadata": {
            "source": "CHS_IWLS",
            "from": params["from"],
            "to": params["to"],
            "count": len(observations),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
    _levels_cache[cache_key] = result
    return result


def fetch_nearest_station_tides(
    lat: float,
    lng: float,
    hours: int = 48,
) -> Dict[str, Any]:
    """Convenience: find the closest CHS station to a lat/lng and return its
    recent observed water levels.

    Useful for any coastal story — "what are the tides doing at this
    community's stretch of coastline right now?"
    """
    stations = fetch_tide_stations()
    nearest_id = None
    nearest_name = ""
    nearest_dist = float("inf")
    for feat in stations.get("features", []):
        lon, slat = feat["geometry"]["coordinates"]
        d = (slat - lat) ** 2 + (lon - lng) ** 2
        if d < nearest_dist:
            nearest_dist = d
            nearest_id = feat["properties"]["station_id"]
            nearest_name = feat["properties"]["name"]

    if not nearest_id:
        return {
            "available": False,
            "error": "No CHS station found",
            "source": "CHS_IWLS",
        }

    series = fetch_water_level_series(nearest_id, hours=hours)
    return {
        "available": True,
        "station_id": nearest_id,
        "station_name": nearest_name,
        "distance_deg": round(nearest_dist ** 0.5, 4),
        **series,
    }
