"""Drought monitoring using US Drought Monitor and SPEI Global Drought Monitor.

Provides county- and state-level drought statistics from the US Drought
Monitor (USDM), polygon boundaries for current drought severity classes
(D0-D4), and a simplified SPI/SPEI-like drought index calculator.
"""

import logging
import math
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

USDM_API_BASE = (
    "https://usdmdataservices.unl.edu/api/CountyStatistics/"
    "GetDroughtSeverityStatisticsByAreaPercent"
)
USDM_GEOJSON_URL = (
    "https://droughtmonitor.unl.edu/data/json/usdm_current.json"
)

# D0-D4 severity descriptions
DROUGHT_CATEGORIES = {
    "D0": "Abnormally Dry",
    "D1": "Moderate Drought",
    "D2": "Severe Drought",
    "D3": "Extreme Drought",
    "D4": "Exceptional Drought",
    "None": "No Drought",
}

# Cache drought data for 6 hours (it updates weekly on Thursdays)
_status_cache: TTLCache = TTLCache(maxsize=32, ttl=21600)
_polygon_cache: TTLCache = TTLCache(maxsize=8, ttl=21600)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_drought_status(
    area_type: str = "us",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    """Fetch drought severity statistics from the US Drought Monitor API.

    Args:
        area_type: Area of interest code.  Use ``"us"`` for the entire
            US, a two-letter state abbreviation (e.g. ``"CA"``), or a
            five-digit FIPS code for a county.
        start_date: Start date as ``"YYYY-MM-DD"`` (default: 4 weeks ago).
        end_date: End date as ``"YYYY-MM-DD"`` (default: today).

    Returns:
        Dictionary containing D0-D4 percentages and parsed drought
        category summaries.
    """
    cache_key = f"drought_{area_type}_{start_date}_{end_date}"
    if cache_key in _status_cache:
        return _status_cache[cache_key]

    now = datetime.now(timezone.utc)
    if not end_date:
        end_date = now.strftime("%Y-%m-%d")
    if not start_date:
        start_date = (now - timedelta(weeks=4)).strftime("%Y-%m-%d")

    # USDM API expects dates as m/d/yyyy
    start_fmt = _reformat_date(start_date)
    end_fmt = _reformat_date(end_date)

    try:
        resp = requests.get(
            USDM_API_BASE,
            params={
                "aoi": area_type,
                "startdate": start_fmt,
                "enddate": end_fmt,
                "statisticsType": "1",
            },
            timeout=20,
        )
        resp.raise_for_status()
        raw = resp.json()

        # Parse the USDM response
        records: List[Dict[str, Any]] = []
        for entry in raw if isinstance(raw, list) else [raw]:
            record = {
                "date": entry.get("MapDate", entry.get("mapDate", "")),
                "area_code": entry.get("FIPS", entry.get("fips", area_type)),
                "D0": _safe_float(entry.get("D0")),
                "D1": _safe_float(entry.get("D1")),
                "D2": _safe_float(entry.get("D2")),
                "D3": _safe_float(entry.get("D3")),
                "D4": _safe_float(entry.get("D4")),
                "None_pct": _safe_float(entry.get("Nothing", entry.get("None"))),
            }
            # Determine dominant category
            record["dominant_category"] = _dominant_category(record)
            records.append(record)

        result: Dict[str, Any] = {
            "area": area_type,
            "start_date": start_date,
            "end_date": end_date,
            "records": records,
            "latest": records[-1] if records else {},
            "source": "US_Drought_Monitor",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        _status_cache[cache_key] = result
        return result

    except Exception as exc:
        logger.error("USDM drought status fetch failed: %s", exc)
        return {
            "area": area_type,
            "records": [],
            "error": str(exc),
            "source": "US_Drought_Monitor",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def fetch_drought_polygons() -> Dict[str, Any]:
    """Fetch current US Drought Monitor boundary polygons as GeoJSON.

    Returns:
        GeoJSON FeatureCollection with polygons classified D0 through
        D4 and a ``severity`` property.
    """
    cache_key = "drought_polygons_current"
    if cache_key in _polygon_cache:
        return _polygon_cache[cache_key]

    try:
        resp = requests.get(USDM_GEOJSON_URL, timeout=30)
        resp.raise_for_status()
        geojson = resp.json()

        # Enrich features
        for feat in geojson.get("features", []):
            props = feat.get("properties", {})
            dm = props.get("DM", props.get("dm", -1))
            category_key = f"D{dm}" if isinstance(dm, int) and 0 <= dm <= 4 else "None"
            props["severity"] = category_key
            props["severity_label"] = DROUGHT_CATEGORIES.get(category_key, "Unknown")
            props["hazard_type"] = "drought"
            props["source"] = "US_Drought_Monitor"

        _polygon_cache[cache_key] = geojson
        return geojson

    except Exception as exc:
        logger.error("USDM polygon fetch failed: %s", exc)
        return {
            "type": "FeatureCollection",
            "features": [],
            "metadata": {
                "error": str(exc),
                "source": "US_Drought_Monitor",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        }


def calculate_drought_index(
    precipitation: float,
    temperature: float,
    soil_moisture: float,
) -> Dict[str, Any]:
    """Compute a simplified SPI/SPEI-like drought severity index.

    This function implements a lightweight analogue of the Standardised
    Precipitation-Evapotranspiration Index (SPEI) suitable for quick
    assessments without requiring long climatological baselines.

    Args:
        precipitation: Recent precipitation in mm (e.g. 30-day total).
        temperature: Mean temperature in Celsius over the same period.
        soil_moisture: Volumetric soil moisture as a fraction (0-1).

    Returns:
        Dictionary with ``index`` (float), ``severity`` (str), and
        component scores.
    """
    # --- Precipitation anomaly (simplified) ---
    # Assume 80 mm/month as a global temperate baseline
    precip_baseline = 80.0
    precip_ratio = precipitation / max(precip_baseline, 0.01)
    precip_score = max(-3.0, min(3.0, (precip_ratio - 1.0) * 3.0))

    # --- Evapotranspiration proxy via temperature ---
    # Thornthwaite-style PET approximation; higher temp = more PET = drier
    pet_factor = max(0.0, (temperature - 10.0) / 30.0)
    pet_score = max(-2.0, min(2.0, -pet_factor * 2.0))

    # --- Soil moisture deficit ---
    # 0.3 is a rough field-capacity reference
    sm_score = max(-2.0, min(2.0, (soil_moisture - 0.3) * 5.0))

    # Combined index
    index = round(0.45 * precip_score + 0.30 * pet_score + 0.25 * sm_score, 2)

    # Classify
    if index <= -2.0:
        severity = "D4"
    elif index <= -1.5:
        severity = "D3"
    elif index <= -1.0:
        severity = "D2"
    elif index <= -0.5:
        severity = "D1"
    elif index <= 0.0:
        severity = "D0"
    else:
        severity = "None"

    return {
        "index": index,
        "severity": severity,
        "severity_label": DROUGHT_CATEGORIES.get(severity, "Unknown"),
        "components": {
            "precipitation_score": round(precip_score, 2),
            "temperature_pet_score": round(pet_score, 2),
            "soil_moisture_score": round(sm_score, 2),
        },
        "inputs": {
            "precipitation_mm": precipitation,
            "temperature_c": temperature,
            "soil_moisture": soil_moisture,
        },
    }


def get_drought_trends(
    fips_code: str,
    months: int = 12,
) -> List[Dict[str, Any]]:
    """Retrieve historical drought progression for a given FIPS location.

    Queries the USDM API in monthly steps to build a time-series of
    drought severity.

    Args:
        fips_code: Five-digit county FIPS code or two-letter state code.
        months: Number of months of history to retrieve (max 24).

    Returns:
        List of monthly drought records, each containing D0-D4
        percentages and a dominant category.
    """
    months = max(1, min(months, 24))
    now = datetime.now(timezone.utc)
    trends: List[Dict[str, Any]] = []

    for i in range(months):
        target_date = now - timedelta(days=30 * i)
        end_str = target_date.strftime("%Y-%m-%d")
        start_str = (target_date - timedelta(days=7)).strftime("%Y-%m-%d")

        status = fetch_drought_status(
            area_type=fips_code,
            start_date=start_str,
            end_date=end_str,
        )

        latest = status.get("latest", {})
        if latest:
            latest["query_date"] = end_str
            trends.append(latest)

    # Reverse to chronological order
    trends.reverse()
    return trends


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _reformat_date(iso_date: str) -> str:
    """Convert ``YYYY-MM-DD`` to ``M/D/YYYY`` for USDM API."""
    try:
        dt = datetime.strptime(iso_date, "%Y-%m-%d")
        return f"{dt.month}/{dt.day}/{dt.year}"
    except ValueError:
        return iso_date


def _safe_float(val: Any) -> float:
    """Safely convert a value to float, defaulting to 0.0."""
    if val is None:
        return 0.0
    try:
        return round(float(val), 2)
    except (ValueError, TypeError):
        return 0.0


def _dominant_category(record: Dict[str, Any]) -> str:
    """Return the most severe drought category with non-zero percentage."""
    for cat in ("D4", "D3", "D2", "D1", "D0"):
        if record.get(cat, 0) > 0:
            return cat
    return "None"
