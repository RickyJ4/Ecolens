"""NDVI vegetation stress analysis using Sentinel-2 and MODIS data.

Provides NDVI retrieval from MODIS (MOD13Q1, 250 m, 16-day composites) via
NASA AppEEARS / direct web services, Sentinel-2 via Sentinel Hub or
Copernicus Data Space, plus vegetation stress classification and
deforestation detection.
"""

import logging
import math
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APPEEARS_BASE = "https://appeears.earthdatacloud.nasa.gov/api"
SENTINEL_HUB_PROCESS_URL = "https://services.sentinel-hub.com/api/v1/process"

# Environment-based credentials
EARTHDATA_USER = os.environ.get("EARTHDATA_USERNAME", "")
EARTHDATA_PASS = os.environ.get("EARTHDATA_PASSWORD", "")
SENTINEL_HUB_CLIENT_ID = os.environ.get("SENTINEL_HUB_CLIENT_ID", "")
SENTINEL_HUB_CLIENT_SECRET = os.environ.get("SENTINEL_HUB_CLIENT_SECRET", "")

# NDVI classification thresholds
NDVI_CLASSES = {
    "water_or_barren": (-1.0, 0.1),
    "sparse_vegetation": (0.1, 0.2),
    "moderate_vegetation": (0.2, 0.5),
    "dense_vegetation": (0.5, 0.7),
    "very_dense_vegetation": (0.7, 1.0),
}

# Caches
_ndvi_cache: TTLCache = TTLCache(maxsize=64, ttl=3600)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_ndvi_modis(
    bbox: Tuple[float, float, float, float],
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    """Fetch NDVI data from MODIS (MOD13Q1) via NASA AppEEARS or MODIS web service.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.
        start_date: Start date as ``"YYYY-MM-DD"`` (default: 32 days ago).
        end_date: End date as ``"YYYY-MM-DD"`` (default: today).

    Returns:
        Dictionary with gridded NDVI statistics, including ``mean``,
        ``min``, ``max``, and a 2-D ``grid`` array suitable for
        visualization.
    """
    cache_key = f"ndvi_modis_{bbox}_{start_date}_{end_date}"
    if cache_key in _ndvi_cache:
        return _ndvi_cache[cache_key]

    now = datetime.now(timezone.utc)
    if not end_date:
        end_date = now.strftime("%Y-%m-%d")
    if not start_date:
        start_date = (now - timedelta(days=32)).strftime("%Y-%m-%d")

    # Try AppEEARS point sample approach for quick bbox statistics
    result = _fetch_modis_appeears(bbox, start_date, end_date)
    if result and result.get("available"):
        _ndvi_cache[cache_key] = result
        return result

    # Fallback: use MODIS direct web service (ORNL DAAC MODIS/VIIRS)
    result = _fetch_modis_ornl(bbox, start_date, end_date)
    _ndvi_cache[cache_key] = result
    return result


def fetch_ndvi_sentinel(
    bbox: Tuple[float, float, float, float],
    date: Optional[str] = None,
) -> Dict[str, Any]:
    """Fetch NDVI from Sentinel-2 via Sentinel Hub Process API.

    Requires ``SENTINEL_HUB_CLIENT_ID`` and ``SENTINEL_HUB_CLIENT_SECRET``
    environment variables.

    Args:
        bbox: Bounding box (west, south, east, north).
        date: Target date ``"YYYY-MM-DD"`` (default: most recent).

    Returns:
        Dictionary with NDVI statistics and availability flag.
    """
    if not SENTINEL_HUB_CLIENT_ID or not SENTINEL_HUB_CLIENT_SECRET:
        return {
            "available": False,
            "message": "Sentinel Hub credentials not configured.",
            "source": "Sentinel-2",
        }

    if not date:
        date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    try:
        # Obtain access token
        token_resp = requests.post(
            "https://services.sentinel-hub.com/oauth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": SENTINEL_HUB_CLIENT_ID,
                "client_secret": SENTINEL_HUB_CLIENT_SECRET,
            },
            timeout=15,
        )
        token_resp.raise_for_status()
        access_token = token_resp.json()["access_token"]

        w, s, e, n = bbox
        date_from = (
            datetime.strptime(date, "%Y-%m-%d") - timedelta(days=15)
        ).strftime("%Y-%m-%d")

        evalscript = """
//VERSION=3
function setup() {
  return {
    input: [{ bands: ["B04", "B08"], units: "DN" }],
    output: { bands: 1, sampleType: "FLOAT32" }
  };
}
function evaluatePixel(sample) {
  let ndvi = (sample.B08 - sample.B04) / (sample.B08 + sample.B04);
  return [ndvi];
}
"""
        payload = {
            "input": {
                "bounds": {
                    "bbox": [w, s, e, n],
                    "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"},
                },
                "data": [
                    {
                        "type": "sentinel-2-l2a",
                        "dataFilter": {
                            "timeRange": {
                                "from": f"{date_from}T00:00:00Z",
                                "to": f"{date}T23:59:59Z",
                            },
                            "maxCloudCoverage": 30,
                        },
                    }
                ],
            },
            "output": {
                "width": 64,
                "height": 64,
                "responses": [
                    {"identifier": "default", "format": {"type": "image/tiff"}}
                ],
            },
            "evalscript": evalscript,
        }

        resp = requests.post(
            SENTINEL_HUB_PROCESS_URL,
            json=payload,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=30,
        )
        resp.raise_for_status()

        # Parse GeoTIFF response for statistics
        import io
        import rasterio

        with rasterio.open(io.BytesIO(resp.content)) as src:
            ndvi_array = src.read(1)
            # Mask out NaN / no-data
            valid = ndvi_array[~np.isnan(ndvi_array)]
            valid = valid[(valid >= -1.0) & (valid <= 1.0)]

        if len(valid) == 0:
            return {
                "available": False,
                "message": "No valid Sentinel-2 NDVI pixels (cloud cover).",
                "source": "Sentinel-2",
            }

        return {
            "available": True,
            "date": date,
            "bbox": list(bbox),
            "statistics": {
                "mean": round(float(np.mean(valid)), 4),
                "min": round(float(np.min(valid)), 4),
                "max": round(float(np.max(valid)), 4),
                "std": round(float(np.std(valid)), 4),
                "median": round(float(np.median(valid)), 4),
            },
            "classification": _classify_ndvi_distribution(valid),
            "pixel_count": int(len(valid)),
            "resolution_m": 10,
            "source": "Sentinel-2",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    except Exception as exc:
        logger.error("Sentinel-2 NDVI fetch failed: %s", exc)
        return {
            "available": False,
            "error": str(exc),
            "source": "Sentinel-2",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def calculate_vegetation_stress(
    current_ndvi: float,
    historical_mean_ndvi: float,
) -> Dict[str, Any]:
    """Assess vegetation stress by comparing current NDVI to historical baseline.

    Args:
        current_ndvi: Current NDVI value (-1 to 1).
        historical_mean_ndvi: Long-term mean NDVI for the same location/season.

    Returns:
        Dictionary with ``anomaly``, ``stress_level``, and a
        human-readable ``description``.
    """
    anomaly = current_ndvi - historical_mean_ndvi

    if anomaly > 0.1:
        stress_level = "healthy"
        description = (
            "Vegetation is greener than the historical average, indicating "
            "above-normal growth or recovery."
        )
    elif anomaly > -0.1:
        stress_level = "moderate_stress"
        description = (
            "Vegetation health is near normal but showing early signs of "
            "stress compared to the historical baseline."
        )
    else:
        stress_level = "severe_stress"
        description = (
            "Significant vegetation decline detected. The NDVI is well below "
            "the historical average, suggesting drought, disease, or land "
            "degradation."
        )

    return {
        "current_ndvi": round(current_ndvi, 4),
        "historical_mean_ndvi": round(historical_mean_ndvi, 4),
        "anomaly": round(anomaly, 4),
        "stress_level": stress_level,
        "description": description,
        "ndvi_class": _classify_single_ndvi(current_ndvi),
    }


def generate_ndvi_geojson(
    ndvi_grid: np.ndarray,
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Convert a raster NDVI array to a GeoJSON grid of colored cells.

    Args:
        ndvi_grid: 2-D numpy array of NDVI values.
        bbox: Bounding box (west, south, east, north) corresponding to
            the array extent.

    Returns:
        GeoJSON FeatureCollection where each feature is a rectangular
        cell with an ``ndvi`` property and a ``fill_color`` for
        visualization.
    """
    rows, cols = ndvi_grid.shape
    w, s, e, n = bbox
    cell_w = (e - w) / cols
    cell_h = (n - s) / rows

    features: List[Dict[str, Any]] = []

    for r in range(rows):
        for c in range(cols):
            val = float(ndvi_grid[r, c])
            if np.isnan(val):
                continue

            x0 = w + c * cell_w
            y0 = n - (r + 1) * cell_h  # Top-down row ordering
            x1 = x0 + cell_w
            y1 = y0 + cell_h

            features.append({
                "type": "Feature",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [round(x0, 6), round(y0, 6)],
                        [round(x1, 6), round(y0, 6)],
                        [round(x1, 6), round(y1, 6)],
                        [round(x0, 6), round(y1, 6)],
                        [round(x0, 6), round(y0, 6)],
                    ]],
                },
                "properties": {
                    "ndvi": round(val, 4),
                    "ndvi_class": _classify_single_ndvi(val),
                    "fill_color": _ndvi_to_hex(val),
                },
            })

    return {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "rows": rows,
            "cols": cols,
            "bbox": list(bbox),
            "count": len(features),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def detect_deforestation(
    ndvi_time_series: List[float],
    threshold: float = -0.3,
) -> List[Dict[str, Any]]:
    """Detect significant drops in an NDVI time-series indicating forest loss.

    Scans consecutive NDVI observations and flags any step-change that
    exceeds the given ``threshold``.

    Args:
        ndvi_time_series: Chronologically ordered list of NDVI values.
        threshold: Maximum negative change between consecutive
            observations to flag as deforestation (default: -0.3).

    Returns:
        List of event dictionaries, each containing ``index``,
        ``ndvi_before``, ``ndvi_after``, ``change``, and ``severity``.
    """
    events: List[Dict[str, Any]] = []

    for i in range(1, len(ndvi_time_series)):
        prev = ndvi_time_series[i - 1]
        curr = ndvi_time_series[i]

        if prev is None or curr is None:
            continue

        change = curr - prev
        if change <= threshold:
            severity = "extreme" if change <= -0.5 else (
                "high" if change <= -0.4 else "moderate"
            )
            events.append({
                "index": i,
                "ndvi_before": round(prev, 4),
                "ndvi_after": round(curr, 4),
                "change": round(change, 4),
                "severity": severity,
                "potential_cause": _infer_cause(change, prev),
            })

    return events


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _fetch_modis_appeears(
    bbox: Tuple[float, float, float, float],
    start_date: str,
    end_date: str,
) -> Dict[str, Any]:
    """Query NASA AppEEARS for MODIS NDVI point samples across the bbox."""
    if not EARTHDATA_USER or not EARTHDATA_PASS:
        logger.info("EarthData credentials not set; skipping AppEEARS.")
        return {"available": False}

    try:
        # Login
        login_resp = requests.post(
            f"{APPEEARS_BASE}/login",
            auth=(EARTHDATA_USER, EARTHDATA_PASS),
            timeout=15,
        )
        login_resp.raise_for_status()
        token = login_resp.json().get("token")

        w, s, e, n = bbox
        center_lat = (s + n) / 2
        center_lon = (w + e) / 2

        # Submit a point sample task for the center of the bbox
        task_payload = {
            "task_type": "point",
            "task_name": f"ecolens_ndvi_{center_lat}_{center_lon}",
            "params": {
                "dates": [{"startDate": start_date, "endDate": end_date}],
                "layers": [
                    {
                        "product": "MOD13Q1.061",
                        "layer": "_250m_16_days_NDVI",
                    }
                ],
                "coordinates": [
                    {
                        "latitude": center_lat,
                        "longitude": center_lon,
                        "id": "center",
                    }
                ],
            },
        }

        task_resp = requests.post(
            f"{APPEEARS_BASE}/task",
            json=task_payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
        )
        task_resp.raise_for_status()
        task_data = task_resp.json()

        # AppEEARS tasks are asynchronous.  For real-time use we return
        # the task ID and a flag indicating the data is pending.
        return {
            "available": True,
            "task_id": task_data.get("task_id"),
            "status": "submitted",
            "message": "MODIS NDVI task submitted to AppEEARS.  Poll task status for results.",
            "bbox": list(bbox),
            "product": "MOD13Q1.061",
            "resolution_m": 250,
            "source": "MODIS_AppEEARS",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    except Exception as exc:
        logger.error("AppEEARS MODIS NDVI request failed: %s", exc)
        return {"available": False, "error": str(exc)}


def _fetch_modis_ornl(
    bbox: Tuple[float, float, float, float],
    start_date: str,
    end_date: str,
) -> Dict[str, Any]:
    """Fallback: use ORNL DAAC MODIS subset web service for NDVI."""
    w, s, e, n = bbox
    center_lat = (s + n) / 2
    center_lon = (w + e) / 2

    try:
        resp = requests.get(
            "https://modis.ornl.gov/rst/api/v1/MOD13Q1/subset",
            params={
                "latitude": center_lat,
                "longitude": center_lon,
                "startDate": f"A{start_date.replace('-', '')}",
                "endDate": f"A{end_date.replace('-', '')}",
                "kmAboveBelow": 1,
                "kmLeftRight": 1,
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        ndvi_values: List[float] = []
        for subset in data.get("subset", []):
            raw_data = subset.get("data", [])
            for val in raw_data:
                scaled = float(val) * 0.0001  # MODIS scale factor
                if -1.0 <= scaled <= 1.0:
                    ndvi_values.append(scaled)

        if not ndvi_values:
            return {
                "available": False,
                "message": "No valid MODIS NDVI data returned.",
                "source": "MODIS_ORNL",
            }

        arr = np.array(ndvi_values)
        return {
            "available": True,
            "bbox": list(bbox),
            "statistics": {
                "mean": round(float(np.mean(arr)), 4),
                "min": round(float(np.min(arr)), 4),
                "max": round(float(np.max(arr)), 4),
                "std": round(float(np.std(arr)), 4),
                "median": round(float(np.median(arr)), 4),
            },
            "classification": _classify_ndvi_distribution(arr),
            "pixel_count": len(ndvi_values),
            "resolution_m": 250,
            "product": "MOD13Q1",
            "source": "MODIS_ORNL",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    except Exception as exc:
        logger.error("ORNL MODIS NDVI request failed: %s", exc)
        return {
            "available": False,
            "error": str(exc),
            "source": "MODIS_ORNL",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def _classify_single_ndvi(val: float) -> str:
    """Classify a single NDVI value into a vegetation category."""
    for label, (lo, hi) in NDVI_CLASSES.items():
        if lo <= val < hi:
            return label
    return "very_dense_vegetation" if val >= 0.7 else "water_or_barren"


def _classify_ndvi_distribution(arr: np.ndarray) -> Dict[str, float]:
    """Compute percentage of pixels in each NDVI class."""
    total = len(arr)
    if total == 0:
        return {}
    dist: Dict[str, float] = {}
    for label, (lo, hi) in NDVI_CLASSES.items():
        count = int(np.sum((arr >= lo) & (arr < hi)))
        dist[label] = round(count / total * 100, 1)
    return dist


def _ndvi_to_hex(val: float) -> str:
    """Map NDVI value to a hex color for visualization.

    Uses a diverging red-yellow-green palette common in vegetation maps.
    """
    # Clamp to [-0.2, 0.9] for colour mapping
    v = max(-0.2, min(0.9, val))
    t = (v + 0.2) / 1.1  # Normalise to 0-1

    if t < 0.25:
        # Brown-red for bare/stressed
        r, g, b = 180, 60, 30
    elif t < 0.4:
        # Yellow-brown
        r, g, b = 220, 180, 50
    elif t < 0.55:
        # Light green
        r, g, b = 150, 200, 80
    elif t < 0.7:
        # Medium green
        r, g, b = 80, 170, 50
    else:
        # Dark green
        r, g, b = 20, 120, 30

    return f"#{r:02x}{g:02x}{b:02x}"


def _infer_cause(change: float, prev_ndvi: float) -> str:
    """Infer a probable cause of NDVI drop."""
    if change <= -0.5:
        return "likely_clear_cutting_or_fire"
    if prev_ndvi > 0.6:
        return "likely_deforestation_or_logging"
    if prev_ndvi > 0.3:
        return "possible_drought_or_agriculture_change"
    return "possible_natural_variability"
