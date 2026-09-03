"""Glacial monitoring using GLIMS, Randolph Glacier Inventory, and NASA ITS_LIVE.

Provides glacier outline polygons from GLIMS (Global Land Ice Measurements
from Space), velocity data from NASA ITS_LIVE, and retreat-rate analytics
for change detection.
"""

import logging
import math
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GLIMS_WFS_BASE = "https://www.glims.org/geoserver/ows"
ITS_LIVE_STAC_URL = "https://stac.itslive.cloud"

# Cache glacier outlines for 1 hour
_outline_cache: TTLCache = TTLCache(maxsize=32, ttl=3600)
_velocity_cache: TTLCache = TTLCache(maxsize=64, ttl=3600)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_glacier_outlines(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Fetch glacier outline polygons from the GLIMS WFS.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.

    Returns:
        GeoJSON FeatureCollection of glacier polygons.  Properties
        include ``glacier_name``, ``area_km2``, ``source_date``, and
        ``country``.
    """
    cache_key = f"glacier_outlines_{bbox}"
    if cache_key in _outline_cache:
        return _outline_cache[cache_key]

    w, s, e, n = bbox
    bbox_str = f"{s},{w},{n},{e}"  # GLIMS WFS expects lat/lon ordering

    try:
        resp = requests.get(
            GLIMS_WFS_BASE,
            params={
                "service": "WFS",
                "version": "1.1.0",
                "request": "GetFeature",
                "typeName": "glims:glacier_polygons",
                "outputFormat": "application/json",
                "maxFeatures": "500",
                "bbox": bbox_str,
            },
            timeout=45,
        )
        resp.raise_for_status()
        geojson = resp.json()

        # Enrich features with standardised properties
        for feat in geojson.get("features", []):
            props = feat.get("properties", {})
            props["glacier_name"] = (
                props.get("glac_name")
                or props.get("glacier_name")
                or "Unnamed Glacier"
            )
            # Area in km^2
            area_raw = props.get("area", props.get("db_area", 0))
            props["area_km2"] = round(float(area_raw), 3) if area_raw else 0.0
            props["source_date"] = props.get("src_date", props.get("anlys_time", ""))
            props["country"] = props.get("chief_affl", props.get("country", ""))
            props["glims_id"] = props.get("glac_id", "")
            props["hazard_type"] = "glacier"
            props["source"] = "GLIMS"

        _outline_cache[cache_key] = geojson
        return geojson

    except Exception as exc:
        logger.error("GLIMS WFS request failed: %s", exc)
        return _empty_fc("GLIMS")


def fetch_glacier_velocity(
    glacier_id: Optional[str] = None,
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Retrieve glacier velocity data from NASA ITS_LIVE STAC catalog.

    Searches the ITS_LIVE STAC for velocity datacubes intersecting the
    specified glacier or bounding box.

    Args:
        glacier_id: Optional GLIMS glacier ID.
        bbox: Optional bounding box (west, south, east, north).

    Returns:
        Dictionary with velocity statistics (mean, max, min in m/yr)
        and metadata.
    """
    cache_key = f"velocity_{glacier_id}_{bbox}"
    if cache_key in _velocity_cache:
        return _velocity_cache[cache_key]

    if not bbox and not glacier_id:
        return {"error": "Either glacier_id or bbox must be provided."}

    try:
        # Query ITS_LIVE STAC search endpoint
        search_body: Dict[str, Any] = {
            "collections": ["its-live-data"],
            "limit": 10,
        }
        if bbox:
            search_body["bbox"] = list(bbox)

        resp = requests.post(
            f"{ITS_LIVE_STAC_URL}/search",
            json=search_body,
            timeout=30,
        )
        resp.raise_for_status()
        stac_results = resp.json()

        items = stac_results.get("features", [])
        if not items:
            return {
                "glacier_id": glacier_id,
                "bbox": bbox,
                "velocity": None,
                "message": "No ITS_LIVE velocity data found for this area.",
                "source": "NASA_ITS_LIVE",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

        # Aggregate velocity statistics from STAC item properties
        velocities: List[float] = []
        date_range_start = ""
        date_range_end = ""

        for item in items:
            item_props = item.get("properties", {})
            v = item_props.get("v", item_props.get("velocity"))
            if v is not None:
                velocities.append(float(v))
            ds = item_props.get("datetime", item_props.get("start_datetime", ""))
            de = item_props.get("end_datetime", "")
            if ds and (not date_range_start or ds < date_range_start):
                date_range_start = ds
            if de and (not date_range_end or de > date_range_end):
                date_range_end = de

        vel_stats: Dict[str, Any] = {}
        if velocities:
            vel_stats = {
                "mean_m_yr": round(sum(velocities) / len(velocities), 2),
                "max_m_yr": round(max(velocities), 2),
                "min_m_yr": round(min(velocities), 2),
                "sample_count": len(velocities),
            }

        result = {
            "glacier_id": glacier_id,
            "bbox": bbox,
            "velocity": vel_stats if vel_stats else None,
            "date_range": {
                "start": date_range_start,
                "end": date_range_end,
            },
            "stac_items_found": len(items),
            "source": "NASA_ITS_LIVE",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        _velocity_cache[cache_key] = result
        return result

    except Exception as exc:
        logger.error("ITS_LIVE velocity fetch failed: %s", exc)
        return {
            "glacier_id": glacier_id,
            "bbox": bbox,
            "velocity": None,
            "error": str(exc),
            "source": "NASA_ITS_LIVE",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def calculate_retreat_rate(
    glacier_id: str,
    start_year: int,
    end_year: int,
) -> Dict[str, Any]:
    """Compare glacier extents between two dates to estimate retreat rate.

    This function queries GLIMS for outlines closest to the requested
    years and computes area change.  When multiple outlines are not
    available, it returns an estimate based on global average retreat
    rates.

    Args:
        glacier_id: GLIMS glacier ID.
        start_year: Beginning year for comparison.
        end_year: Ending year for comparison.

    Returns:
        Dictionary with ``area_change_km2``, ``rate_km2_per_year``,
        and ``percent_change``.
    """
    if end_year <= start_year:
        return {"error": "end_year must be greater than start_year."}

    duration = end_year - start_year

    try:
        # Attempt to fetch glacier-specific data from GLIMS
        resp = requests.get(
            GLIMS_WFS_BASE,
            params={
                "service": "WFS",
                "version": "1.1.0",
                "request": "GetFeature",
                "typeName": "glims:glacier_polygons",
                "outputFormat": "application/json",
                "maxFeatures": "50",
                "CQL_FILTER": f"glac_id='{glacier_id}'",
            },
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        features = data.get("features", [])
        if len(features) < 2:
            # Not enough temporal snapshots; use global estimate
            logger.info(
                "Only %d outlines for %s; using estimated retreat rate.",
                len(features),
                glacier_id,
            )
            # Global average retreat ~0.5-1.0% area/year (WGMS reference)
            estimated_area = 0.0
            if features:
                props = features[0].get("properties", {})
                estimated_area = float(
                    props.get("area", props.get("db_area", 10))
                )

            annual_rate = estimated_area * 0.007  # 0.7% per year
            total_change = annual_rate * duration

            return {
                "glacier_id": glacier_id,
                "start_year": start_year,
                "end_year": end_year,
                "duration_years": duration,
                "area_start_km2": round(estimated_area, 3),
                "area_end_km2": round(estimated_area - total_change, 3),
                "area_change_km2": round(-total_change, 3),
                "rate_km2_per_year": round(-annual_rate, 4),
                "percent_change": round(-0.7 * duration, 2),
                "method": "global_average_estimate",
                "source": "GLIMS_estimated",
            }

        # Sort outlines by date
        dated = []
        for feat in features:
            props = feat.get("properties", {})
            date_str = props.get("src_date", props.get("anlys_time", ""))
            area_val = float(props.get("area", props.get("db_area", 0)))
            try:
                year = int(date_str[:4])
            except (ValueError, IndexError):
                continue
            dated.append({"year": year, "area_km2": area_val, "date": date_str})

        dated.sort(key=lambda x: x["year"])

        # Find closest matches to start/end years
        best_start = min(dated, key=lambda x: abs(x["year"] - start_year))
        best_end = min(dated, key=lambda x: abs(x["year"] - end_year))

        if best_start["year"] == best_end["year"]:
            # Only one epoch available
            annual_rate = best_start["area_km2"] * 0.007
            total_change = annual_rate * duration
            return {
                "glacier_id": glacier_id,
                "start_year": start_year,
                "end_year": end_year,
                "duration_years": duration,
                "area_start_km2": round(best_start["area_km2"], 3),
                "area_end_km2": round(best_start["area_km2"] - total_change, 3),
                "area_change_km2": round(-total_change, 3),
                "rate_km2_per_year": round(-annual_rate, 4),
                "percent_change": round(-0.7 * duration, 2),
                "method": "single_epoch_estimate",
                "source": "GLIMS",
            }

        area_change = best_end["area_km2"] - best_start["area_km2"]
        actual_duration = max(1, best_end["year"] - best_start["year"])
        rate = area_change / actual_duration
        pct = (area_change / max(best_start["area_km2"], 0.001)) * 100

        return {
            "glacier_id": glacier_id,
            "start_year": best_start["year"],
            "end_year": best_end["year"],
            "duration_years": actual_duration,
            "area_start_km2": round(best_start["area_km2"], 3),
            "area_end_km2": round(best_end["area_km2"], 3),
            "area_change_km2": round(area_change, 3),
            "rate_km2_per_year": round(rate, 4),
            "percent_change": round(pct, 2),
            "method": "multi_epoch_observed",
            "source": "GLIMS",
        }

    except Exception as exc:
        logger.error("Retreat rate calculation failed for %s: %s", glacier_id, exc)
        return {
            "glacier_id": glacier_id,
            "error": str(exc),
            "source": "GLIMS",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }


def get_glacier_stats(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Compute summary statistics for glaciers within a bounding box.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        Dictionary with ``total_glaciers``, ``total_area_km2``,
        ``average_area_km2``, ``named_glaciers``, and
        ``average_retreat_rate_pct_yr``.
    """
    outlines = fetch_glacier_outlines(bbox)
    features = outlines.get("features", [])

    if not features:
        return {
            "total_glaciers": 0,
            "total_area_km2": 0.0,
            "average_area_km2": 0.0,
            "named_glaciers": 0,
            "average_retreat_rate_pct_yr": 0.0,
            "bbox": list(bbox),
            "source": "GLIMS",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    total_area = 0.0
    named_count = 0
    areas: List[float] = []

    for feat in features:
        props = feat.get("properties", {})
        area = props.get("area_km2", 0.0)
        areas.append(area)
        total_area += area
        name = props.get("glacier_name", "")
        if name and name != "Unnamed Glacier":
            named_count += 1

    avg_area = total_area / len(features) if features else 0.0

    return {
        "total_glaciers": len(features),
        "total_area_km2": round(total_area, 3),
        "average_area_km2": round(avg_area, 3),
        "largest_km2": round(max(areas), 3) if areas else 0.0,
        "smallest_km2": round(min(areas), 3) if areas else 0.0,
        "named_glaciers": named_count,
        "average_retreat_rate_pct_yr": -0.7,  # Global average reference
        "bbox": list(bbox),
        "source": "GLIMS",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _empty_fc(source: str) -> Dict[str, Any]:
    """Return an empty GeoJSON FeatureCollection."""
    return {
        "type": "FeatureCollection",
        "features": [],
        "metadata": {
            "source": source,
            "count": 0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
