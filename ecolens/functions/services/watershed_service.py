"""Watershed analysis using HydroSHEDS and USGS Watershed Boundary Dataset.

Provides HUC-level watershed polygons from the USGS WBD, river network
geometries, hazard-overlay statistics, and a simple D8-based watershed
delineation algorithm for DEM data.
"""

import io
import logging
import math
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

USGS_WBD_WFS_BASE = (
    "https://hydro.nationalmap.gov/arcgis/services/wbd/MapServer/WFSServer"
)
USGS_NHD_WFS_BASE = (
    "https://hydro.nationalmap.gov/arcgis/services/nhd/MapServer/WFSServer"
)

# Cache WBD data for 1 hour
_wbd_cache: TTLCache = TTLCache(maxsize=32, ttl=3600)
_river_cache: TTLCache = TTLCache(maxsize=32, ttl=3600)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_watersheds_usgs(
    bbox: Tuple[float, float, float, float],
    huc_level: int = 8,
) -> Dict[str, Any]:
    """Fetch watershed polygons from the USGS Watershed Boundary Dataset.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.
        huc_level: HUC level to query (2, 4, 6, 8, 10, or 12).

    Returns:
        GeoJSON FeatureCollection of watershed polygons with HUC codes
        and names.
    """
    huc_level = max(2, min(12, huc_level))
    cache_key = f"wbd_{bbox}_{huc_level}"
    if cache_key in _wbd_cache:
        return _wbd_cache[cache_key]

    w, s, e, n = bbox
    bbox_str = f"{w},{s},{e},{n}"

    # Map HUC level to USGS WFS layer name
    layer_map = {
        2: "wbd:HUC2",
        4: "wbd:HUC4",
        6: "wbd:HUC6",
        8: "wbd:HUC8",
        10: "wbd:HUC10",
        12: "wbd:HUC12",
    }
    type_name = layer_map.get(huc_level, "wbd:HUC8")

    try:
        resp = requests.get(
            USGS_WBD_WFS_BASE,
            params={
                "service": "WFS",
                "version": "1.1.0",
                "request": "GetFeature",
                "typeName": type_name,
                "bbox": bbox_str,
                "outputFormat": "application/json",
                "maxFeatures": "200",
                "srsName": "EPSG:4326",
            },
            timeout=45,
        )
        resp.raise_for_status()
        geojson = resp.json()

        # Enrich features
        for feat in geojson.get("features", []):
            props = feat.get("properties", {})
            props["huc_level"] = huc_level
            props["huc_code"] = (
                props.get(f"huc{huc_level}")
                or props.get("huc_code")
                or props.get("HUC" + str(huc_level), "")
            )
            props["watershed_name"] = props.get("name", props.get("NAME", ""))
            props["area_sq_km"] = _safe_float(
                props.get("areasqkm", props.get("AreaSqKm", 0))
            )
            props["hazard_type"] = "watershed"
            props["source"] = "USGS_WBD"

        _wbd_cache[cache_key] = geojson
        return geojson

    except Exception as exc:
        logger.error("USGS WBD fetch failed: %s", exc)
        return _empty_fc("USGS_WBD")


def fetch_river_network(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Fetch river/stream network lines from USGS NHD.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        GeoJSON FeatureCollection of LineString geometries.
    """
    cache_key = f"rivers_{bbox}"
    if cache_key in _river_cache:
        return _river_cache[cache_key]

    w, s, e, n = bbox
    bbox_str = f"{w},{s},{e},{n}"

    try:
        resp = requests.get(
            USGS_NHD_WFS_BASE,
            params={
                "service": "WFS",
                "version": "1.1.0",
                "request": "GetFeature",
                "typeName": "nhd:NHDFlowline",
                "bbox": bbox_str,
                "outputFormat": "application/json",
                "maxFeatures": "500",
                "srsName": "EPSG:4326",
            },
            timeout=45,
        )
        resp.raise_for_status()
        geojson = resp.json()

        for feat in geojson.get("features", []):
            props = feat.get("properties", {})
            props["stream_name"] = props.get("gnis_name", props.get("GNIS_NAME", ""))
            props["stream_order"] = _safe_int(
                props.get("streamorde", props.get("StreamOrde", 0))
            )
            props["hazard_type"] = "river"
            props["source"] = "USGS_NHD"

        _river_cache[cache_key] = geojson
        return geojson

    except Exception as exc:
        logger.error("USGS NHD river fetch failed: %s", exc)
        return _empty_fc("USGS_NHD")


def calculate_watershed_stats(
    watershed_geojson: Dict[str, Any],
    hazard_data: Dict[str, Any],
) -> Dict[str, Any]:
    """Overlay hazards on watersheds and compute per-watershed statistics.

    For each watershed polygon, determines which hazard features
    intersect it and computes a composite risk score.

    Args:
        watershed_geojson: GeoJSON FeatureCollection of watershed polygons.
        hazard_data: Combined GeoJSON FeatureCollection of hazard features
            (fires, floods, drought, etc.).

    Returns:
        Dictionary mapping HUC codes to statistics: ``affected_area``,
        ``dominant_hazard``, ``risk_score``, and ``hazard_counts``.
    """
    try:
        from shapely.geometry import shape, mapping

        watersheds = watershed_geojson.get("features", [])
        hazards = hazard_data.get("features", [])

        # Pre-build shapely geometries for hazards
        hazard_shapes = []
        for hf in hazards:
            try:
                geom = shape(hf["geometry"])
                hazard_shapes.append((geom, hf.get("properties", {})))
            except Exception:
                continue

        results: Dict[str, Any] = {}

        for ws_feat in watersheds:
            ws_props = ws_feat.get("properties", {})
            huc_code = ws_props.get("huc_code", "unknown")

            try:
                ws_geom = shape(ws_feat["geometry"])
            except Exception:
                continue

            ws_area_km2 = ws_props.get("area_sq_km", 0)
            hazard_counts: Dict[str, int] = {}
            severity_scores: List[float] = []

            for h_geom, h_props in hazard_shapes:
                try:
                    if ws_geom.intersects(h_geom):
                        h_type = h_props.get("hazard_type", "unknown")
                        hazard_counts[h_type] = hazard_counts.get(h_type, 0) + 1
                        severity_scores.append(
                            _severity_to_score(h_props.get("severity", "low"))
                        )
                except Exception:
                    continue

            risk_score = (
                round(sum(severity_scores) / len(severity_scores), 2)
                if severity_scores
                else 0.0
            )
            dominant = (
                max(hazard_counts, key=hazard_counts.get)
                if hazard_counts
                else "none"
            )

            results[huc_code] = {
                "huc_code": huc_code,
                "watershed_name": ws_props.get("watershed_name", ""),
                "area_sq_km": ws_area_km2,
                "hazard_counts": hazard_counts,
                "total_hazard_features": sum(hazard_counts.values()),
                "dominant_hazard": dominant,
                "risk_score": risk_score,
            }

        return {
            "watersheds": results,
            "total_assessed": len(results),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    except ImportError:
        logger.error("shapely not available; returning empty stats.")
        return {"watersheds": {}, "total_assessed": 0, "error": "shapely unavailable"}
    except Exception as exc:
        logger.error("Watershed stats calculation failed: %s", exc)
        return {"watersheds": {}, "total_assessed": 0, "error": str(exc)}


def delineate_watershed(
    pour_point_lat: float,
    pour_point_lon: float,
    dem_data: bytes,
) -> Dict[str, Any]:
    """Delineate a watershed from a DEM using a D8 flow-direction algorithm.

    This is a simplified, numpy-only implementation suitable for small
    DEM extents.  For production-scale delineation, consider using
    pysheds or TauDEM.

    Args:
        pour_point_lat: Latitude of the watershed outlet.
        pour_point_lon: Longitude of the watershed outlet.
        dem_data: GeoTIFF bytes of the DEM covering the area.

    Returns:
        GeoJSON FeatureCollection with the delineated watershed polygon
        and basic hydrological statistics.
    """
    try:
        import rasterio
        from rasterio.transform import rowcol

        with rasterio.open(io.BytesIO(dem_data)) as src:
            dem = src.read(1).astype(np.float32)
            transform = src.transform
            nodata = src.nodata

        if nodata is not None:
            dem[dem == nodata] = np.nan

        rows, cols = dem.shape

        # Locate pour point in pixel space
        pp_row, pp_col = rowcol(transform, pour_point_lon, pour_point_lat)
        pp_row = int(max(0, min(rows - 1, pp_row)))
        pp_col = int(max(0, min(cols - 1, pp_col)))

        # D8 flow direction: for each cell, determine which of 8
        # neighbours has the steepest descent
        flow_dir = np.full((rows, cols), -1, dtype=np.int8)
        # Neighbour offsets: N, NE, E, SE, S, SW, W, NW
        dr = [-1, -1, 0, 1, 1, 1, 0, -1]
        dc = [0, 1, 1, 1, 0, -1, -1, -1]
        dist = [1.0, 1.414, 1.0, 1.414, 1.0, 1.414, 1.0, 1.414]

        for r in range(1, rows - 1):
            for c in range(1, cols - 1):
                if np.isnan(dem[r, c]):
                    continue
                max_drop = 0.0
                max_dir = -1
                for d in range(8):
                    nr, nc = r + dr[d], c + dc[d]
                    if np.isnan(dem[nr, nc]):
                        continue
                    drop = (dem[r, c] - dem[nr, nc]) / dist[d]
                    if drop > max_drop:
                        max_drop = drop
                        max_dir = d
                flow_dir[r, c] = max_dir

        # Trace upstream from pour point using BFS
        watershed_mask = np.zeros((rows, cols), dtype=bool)
        watershed_mask[pp_row, pp_col] = True

        # Build reverse flow graph: for each cell, which cells flow into it?
        # Opposite directions
        opposite = [4, 5, 6, 7, 0, 1, 2, 3]

        queue = [(pp_row, pp_col)]
        visited = set()
        visited.add((pp_row, pp_col))

        while queue:
            r, c = queue.pop(0)
            for d in range(8):
                nr, nc = r + dr[d], c + dc[d]
                if 0 <= nr < rows and 0 <= nc < cols and (nr, nc) not in visited:
                    # Does cell (nr, nc) flow into (r, c)?
                    if flow_dir[nr, nc] == opposite[d]:
                        visited.add((nr, nc))
                        watershed_mask[nr, nc] = True
                        queue.append((nr, nc))

        # Convert mask to polygon
        boundary_points = _mask_to_boundary(watershed_mask, transform)

        if len(boundary_points) < 4:
            return _empty_fc("D8_delineation")

        # Close the ring
        boundary_points.append(boundary_points[0])

        watershed_area_px = int(np.sum(watershed_mask))
        pixel_area_m2 = abs(transform.a * transform.e) * (111320 ** 2)
        watershed_area_km2 = watershed_area_px * pixel_area_m2 / 1e6

        # Elevation stats within watershed
        ws_elevations = dem[watershed_mask & ~np.isnan(dem)]

        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": [boundary_points],
            },
            "properties": {
                "pour_point": {"lat": pour_point_lat, "lon": pour_point_lon},
                "area_km2": round(watershed_area_km2, 3),
                "pixel_count": watershed_area_px,
                "elevation_min_m": round(float(np.min(ws_elevations)), 1) if len(ws_elevations) else 0,
                "elevation_max_m": round(float(np.max(ws_elevations)), 1) if len(ws_elevations) else 0,
                "elevation_mean_m": round(float(np.mean(ws_elevations)), 1) if len(ws_elevations) else 0,
                "relief_m": round(
                    float(np.max(ws_elevations) - np.min(ws_elevations)), 1
                ) if len(ws_elevations) else 0,
                "hazard_type": "watershed_delineation",
                "source": "D8_algorithm",
            },
        }

        return {
            "type": "FeatureCollection",
            "features": [feature],
            "metadata": {
                "method": "D8_flow_direction",
                "dem_rows": rows,
                "dem_cols": cols,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        }

    except Exception as exc:
        logger.error("Watershed delineation failed: %s", exc)
        return {
            "type": "FeatureCollection",
            "features": [],
            "metadata": {"error": str(exc)},
        }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _mask_to_boundary(
    mask: np.ndarray,
    transform: Any,
) -> List[List[float]]:
    """Extract the boundary of a boolean mask as coordinate pairs.

    Uses a simple contour-tracing approach that walks the edge of the
    True region and converts pixel indices to geographic coordinates.
    """
    import rasterio

    rows_with_true = np.where(mask.any(axis=1))[0]
    if len(rows_with_true) == 0:
        return []

    boundary: List[List[float]] = []

    # Simple approach: scan each row, collect leftmost and rightmost True pixels
    left_edge: List[Tuple[int, int]] = []
    right_edge: List[Tuple[int, int]] = []

    for r in rows_with_true:
        cols_true = np.where(mask[r])[0]
        if len(cols_true) == 0:
            continue
        left_edge.append((r, int(cols_true[0])))
        right_edge.append((r, int(cols_true[-1])))

    # Build polygon: left edge top-to-bottom, then right edge bottom-to-top
    for r, c in left_edge:
        x, y = rasterio.transform.xy(transform, r, c)
        boundary.append([round(x, 6), round(y, 6)])

    for r, c in reversed(right_edge):
        x, y = rasterio.transform.xy(transform, r, c)
        boundary.append([round(x, 6), round(y, 6)])

    return boundary


def _severity_to_score(severity: str) -> float:
    """Map a severity label to a 0-1 numeric score."""
    mapping = {
        "extreme": 1.0,
        "major": 0.9,
        "high": 0.8,
        "moderate": 0.5,
        "minor": 0.3,
        "action": 0.2,
        "low": 0.1,
        "no_flooding": 0.0,
        "none": 0.0,
    }
    return mapping.get(severity.lower(), 0.3)


def _safe_float(val: Any) -> float:
    """Safely convert to float."""
    try:
        return round(float(val), 3)
    except (ValueError, TypeError):
        return 0.0


def _safe_int(val: Any) -> int:
    """Safely convert to int."""
    try:
        return int(val)
    except (ValueError, TypeError):
        return 0


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
