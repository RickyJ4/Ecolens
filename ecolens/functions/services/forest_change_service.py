"""Hansen Global Forest Change via Google Earth Engine.

Annual tree-cover loss (2000–latest) for any bounding box. Adds the
historical depth needed for storytelling — "this place lost X% of its
tree cover over 20 years" is a concrete, citable claim derived from
30m Landsat-based mapping.

Data source: Hansen/UMD/Google/USGS/NASA Global Forest Change v1.11
(asset: UMD/hansen/global_forest_change_2023_v1_11)
Attribution: Hansen, M. C. et al. (2013) "High-Resolution Global Maps
of 21st-Century Forest Cover Change." Science 342: 850-853.

GEE auth is shared with sentinel_verification_agent.py.
"""

import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

from cachetools import TTLCache

logger = logging.getLogger(__name__)

# 6-hour cache (Hansen data is annual; no need to refetch frequently)
_loss_cache: TTLCache = TTLCache(maxsize=64, ttl=21600)

# UMD Hansen asset (update version when UMD releases a new year)
HANSEN_ASSET = "UMD/hansen/global_forest_change_2023_v1_11"
# Hansen Year 1 = 2001, so lossyear=23 means 2023 loss
HANSEN_BASE_YEAR = 2000


def fetch_forest_loss_summary(
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Compute annual tree-cover loss inside a bounding box.

    Returns a GeoJSON-shaped envelope so the orchestrator can merge it
    into the hazard layer set. The properties carry the real numbers:
    total loss area, per-year breakdown, percent of original cover.
    """
    if bbox is None:
        return _empty_result("bbox required")

    cache_key = f"forest_loss_{round(bbox[0], 2)}_{round(bbox[1], 2)}_{round(bbox[2], 2)}_{round(bbox[3], 2)}"
    if cache_key in _loss_cache:
        return _loss_cache[cache_key]

    try:
        import ee
        try:
            ee.Initialize()
        except Exception:
            # Already initialized elsewhere is fine
            pass

        w, s, e, n = bbox
        region = ee.Geometry.BBox(w, s, e, n)
        hansen = ee.Image(HANSEN_ASSET)

        # 2000 baseline tree cover (treecover2000, %)
        cover_pct = hansen.select("treecover2000")
        # Loss mask (1 = lost between 2001 and asset year)
        loss = hansen.select("loss")
        loss_year = hansen.select("lossyear")  # 1..23 => 2001..2023

        # Pixel area (m^2) used for proper km^2 calculations
        pixel_area_m2 = ee.Image.pixelArea()

        # Total loss area (m^2)
        total_loss_m2 = (
            pixel_area_m2.updateMask(loss)
            .reduceRegion(
                reducer=ee.Reducer.sum(),
                geometry=region,
                scale=30,
                maxPixels=1e10,
            )
            .get("area")
        )

        # Baseline 2000 forest area (cells where cover >= 30%, m^2)
        baseline_mask = cover_pct.gte(30)
        baseline_m2 = (
            pixel_area_m2.updateMask(baseline_mask)
            .reduceRegion(
                reducer=ee.Reducer.sum(),
                geometry=region,
                scale=30,
                maxPixels=1e10,
            )
            .get("area")
        )

        # Per-year loss area histogram
        year_hist = (
            pixel_area_m2.addBands(loss_year)
            .updateMask(loss)
            .reduceRegion(
                reducer=ee.Reducer.sum().group(groupField=1, groupName="lossyear"),
                geometry=region,
                scale=30,
                maxPixels=1e10,
            )
            .get("groups")
        )

        total_loss_val = ee.Number(total_loss_m2).getInfo() or 0
        baseline_val = ee.Number(baseline_m2).getInfo() or 0
        groups_val = year_hist.getInfo() or []

        per_year = {}
        for g in groups_val:
            ly = g.get("lossyear")
            area_m2 = g.get("sum", 0)
            if ly is None:
                continue
            year = HANSEN_BASE_YEAR + int(ly)
            per_year[year] = round(area_m2 / 10000.0, 2)  # ha

        total_loss_ha = round(total_loss_val / 10000.0, 2)
        baseline_ha = round(baseline_val / 10000.0, 2)
        loss_pct = (
            round((total_loss_ha / baseline_ha) * 100, 2)
            if baseline_ha > 0 else 0.0
        )

        # Wrap as a GeoJSON-style feature so orchestrator merging works
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [w, s], [e, s], [e, n], [w, n], [w, s],
                ]],
            },
            "properties": {
                "total_loss_ha": total_loss_ha,
                "baseline_forest_ha": baseline_ha,
                "loss_pct_of_baseline": loss_pct,
                "per_year_loss_ha": per_year,
                "year_range": f"2001-{HANSEN_BASE_YEAR + 23}",
                "hazard_type": "forest_loss",
                "source": "HANSEN_GFC_V1_11",
            },
        }

        result = {
            "type": "FeatureCollection",
            "features": [feature],
            "metadata": {
                "source": "HANSEN_GFC_V1_11",
                "attribution": "Hansen/UMD/Google/USGS/NASA",
                "asset": HANSEN_ASSET,
                "count": 1,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        }
        _loss_cache[cache_key] = result
        return result
    except Exception as exc:
        logger.error("Hansen forest loss computation failed: %s", exc)
        return _empty_result(str(exc))


def _empty_result(reason: str) -> Dict[str, Any]:
    return {
        "type": "FeatureCollection",
        "features": [],
        "metadata": {
            "source": "HANSEN_GFC_V1_11",
            "count": 0,
            "error": reason,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }
