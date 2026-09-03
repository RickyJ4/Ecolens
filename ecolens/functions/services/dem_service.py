"""DEM (Digital Elevation Model) terrain data service using OpenTopography and Copernicus.

Provides DEM retrieval from SRTM GL1 (30 m) and Copernicus GLO-30 via
OpenTopography, conversion to Unity-compatible heightmaps, terrain
statistics, and hillshade generation.
"""

import io
import logging
import math
import os
import struct
from typing import Any, Dict, Optional, Tuple

import numpy as np
import requests
from cachetools import TTLCache

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OPENTOPO_API_BASE = "https://portal.opentopography.org/API/globaldem"
OPENTOPO_API_KEY = os.environ.get("OPENTOPO_API_KEY", "")

# Cache DEM tiles for 2 hours
_dem_cache: TTLCache = TTLCache(maxsize=16, ttl=7200)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def fetch_dem_srtm(
    bbox: Tuple[float, float, float, float],
    output_format: str = "GTiff",
) -> Optional[bytes]:
    """Fetch SRTM GL1 (30 m) DEM from OpenTopography.

    Args:
        bbox: Bounding box (west, south, east, north) in EPSG:4326.
        output_format: Output raster format (``"GTiff"`` or ``"AAIGrid"``).

    Returns:
        Raw bytes of the DEM raster (GeoTIFF by default), or ``None``
        on failure.
    """
    cache_key = f"srtm_{bbox}_{output_format}"
    if cache_key in _dem_cache:
        return _dem_cache[cache_key]

    w, s, e, n = bbox

    params: Dict[str, str] = {
        "demtype": "SRTMGL1",
        "south": str(s),
        "north": str(n),
        "west": str(w),
        "east": str(e),
        "outputFormat": output_format,
    }
    if OPENTOPO_API_KEY:
        params["API_Key"] = OPENTOPO_API_KEY

    try:
        resp = requests.get(OPENTOPO_API_BASE, params=params, timeout=60)
        resp.raise_for_status()

        if len(resp.content) < 100:
            logger.warning("SRTM response too small (%d bytes); likely an error.", len(resp.content))
            return None

        _dem_cache[cache_key] = resp.content
        return resp.content

    except Exception as exc:
        logger.error("OpenTopography SRTM fetch failed: %s", exc)
        return None


def fetch_dem_copernicus(
    bbox: Tuple[float, float, float, float],
) -> Optional[bytes]:
    """Fetch Copernicus GLO-30 DEM from OpenTopography.

    Falls back to SRTM GL1 if Copernicus is unavailable.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        GeoTIFF bytes or ``None``.
    """
    cache_key = f"cop30_{bbox}"
    if cache_key in _dem_cache:
        return _dem_cache[cache_key]

    w, s, e, n = bbox

    params: Dict[str, str] = {
        "demtype": "COP30",
        "south": str(s),
        "north": str(n),
        "west": str(w),
        "east": str(e),
        "outputFormat": "GTiff",
    }
    if OPENTOPO_API_KEY:
        params["API_Key"] = OPENTOPO_API_KEY

    try:
        resp = requests.get(OPENTOPO_API_BASE, params=params, timeout=60)
        resp.raise_for_status()

        if len(resp.content) < 100:
            logger.warning("COP30 response too small; falling back to SRTM.")
            return fetch_dem_srtm(bbox)

        _dem_cache[cache_key] = resp.content
        return resp.content

    except Exception as exc:
        logger.warning("Copernicus DEM fetch failed: %s; trying SRTM fallback.", exc)
        return fetch_dem_srtm(bbox)


def _compute_bbox_dimensions_metres(
    bbox: Tuple[float, float, float, float],
) -> Tuple[float, float, float, float]:
    """Compute real-world dimensions of a bounding box in metres.

    Uses the WGS84 ellipsoid for accurate distance at any latitude.

    Args:
        bbox: (west, south, east, north) in decimal degrees.

    Returns:
        (width_m, height_m, center_lat, center_lon) — width and height
        in metres and the geographic centre of the bbox.
    """
    w, s, e, n = bbox
    center_lat = (s + n) / 2.0
    center_lon = (w + e) / 2.0

    # Metres per degree of latitude (nearly constant ~111 320 m)
    m_per_deg_lat = 111_320.0

    # Metres per degree of longitude varies with latitude
    lat_rad = math.radians(center_lat)
    m_per_deg_lon = 111_320.0 * math.cos(lat_rad)

    width_m = abs(e - w) * m_per_deg_lon
    height_m = abs(n - s) * m_per_deg_lat

    return width_m, height_m, center_lat, center_lon


def dem_to_heightmap(
    dem_bytes: bytes,
    target_size: int = 1025,
    bbox: Optional[Tuple[float, float, float, float]] = None,
) -> Dict[str, Any]:
    """Convert a GeoTIFF DEM to a Unity-compatible RAW16 heightmap.

    Unity terrain expects a square, power-of-two-plus-one (e.g. 1025)
    heightmap stored as little-endian unsigned 16-bit integers with the
    rows flipped vertically (bottom-to-top).

    When *bbox* is provided the response includes precise real-world
    terrain dimensions so that Unity can position the terrain correctly
    in geographic space.

    Args:
        dem_bytes: Raw GeoTIFF bytes.
        target_size: Side length of the output square heightmap.  Must
            be a power of two plus one (e.g. 129, 257, 513, 1025).
        bbox: Optional (west, south, east, north) used to compute
            real-world width/height in metres for Unity terrain sizing.

    Returns:
        Dictionary with keys:
        - ``raw_data``: ``bytes`` of the uint16 heightmap
        - ``width``, ``height``: Pixel dimensions
        - ``min_elevation``, ``max_elevation``: Elevation range in metres
        - ``crs``: Coordinate reference system string
        - ``terrain_width_m``: Real-world E-W extent in metres
        - ``terrain_height_m``: Real-world N-S extent in metres
        - ``origin_lat``, ``origin_lon``: Geographic centre of the DEM
        - ``bbox``: The bounding box used (west, south, east, north)
    """
    import rasterio
    from rasterio.enums import Resampling

    try:
        with rasterio.open(io.BytesIO(dem_bytes)) as src:
            # Read first band as float
            dem = src.read(1).astype(np.float32)
            crs = str(src.crs) if src.crs else "EPSG:4326"
            transform = src.transform

            # Derive bbox from GeoTIFF if not explicitly provided
            if bbox is None:
                bbox = (
                    src.bounds.left,
                    src.bounds.bottom,
                    src.bounds.right,
                    src.bounds.top,
                )

            # Handle nodata
            nodata = src.nodata
            if nodata is not None:
                dem[dem == nodata] = np.nan

            # Compute elevation range before resampling
            valid = dem[~np.isnan(dem)]
            if len(valid) == 0:
                return {
                    "raw_data": b"",
                    "width": 0,
                    "height": 0,
                    "min_elevation": 0.0,
                    "max_elevation": 0.0,
                    "error": "No valid elevation data.",
                }

            min_elev = float(np.min(valid))
            max_elev = float(np.max(valid))
            elev_range = max_elev - min_elev if max_elev > min_elev else 1.0

        # Compute real-world dimensions from bbox
        terrain_w, terrain_h, origin_lat, origin_lon = _compute_bbox_dimensions_metres(bbox)

        # Resample to target size
        with rasterio.open(io.BytesIO(dem_bytes)) as src:
            data = src.read(
                1,
                out_shape=(target_size, target_size),
                resampling=Resampling.bilinear,
            ).astype(np.float32)

        # Replace NaN with min elevation
        data[np.isnan(data)] = min_elev

        # Normalise to 0-65535 uint16
        normalised = ((data - min_elev) / elev_range * 65535).clip(0, 65535)
        heightmap = normalised.astype(np.uint16)

        # Flip vertically for Unity convention (GDAL is top-down,
        # Unity terrain is bottom-up)
        heightmap = np.flipud(heightmap)

        # Serialize to raw bytes (little-endian)
        raw_data = heightmap.tobytes()

        return {
            "raw_data": raw_data,
            "width": target_size,
            "height": target_size,
            "min_elevation": round(min_elev, 2),
            "max_elevation": round(max_elev, 2),
            "crs": crs,
            "terrain_width_m": round(terrain_w, 1),
            "terrain_height_m": round(terrain_h, 1),
            "origin_lat": round(origin_lat, 7),
            "origin_lon": round(origin_lon, 7),
            "bbox": [round(v, 7) for v in bbox],
        }

    except Exception as exc:
        logger.error("DEM to heightmap conversion failed: %s", exc)
        return {
            "raw_data": b"",
            "width": 0,
            "height": 0,
            "min_elevation": 0.0,
            "max_elevation": 0.0,
            "error": str(exc),
        }


def get_terrain_stats(
    bbox: Tuple[float, float, float, float],
) -> Dict[str, Any]:
    """Compute terrain statistics (elevation, slope) for a bounding box.

    Fetches DEM data and derives elevation and slope metrics.

    Args:
        bbox: Bounding box (west, south, east, north).

    Returns:
        Dictionary with elevation and slope statistics.
    """
    dem_bytes = fetch_dem_copernicus(bbox)
    if not dem_bytes:
        dem_bytes = fetch_dem_srtm(bbox)
    if not dem_bytes:
        return {
            "available": False,
            "error": "Could not retrieve DEM data.",
            "bbox": list(bbox),
        }

    try:
        import rasterio

        with rasterio.open(io.BytesIO(dem_bytes)) as src:
            dem = src.read(1).astype(np.float32)
            nodata = src.nodata
            pixel_size_m = abs(src.transform.a) * 111320  # Approx metres

        if nodata is not None:
            dem[dem == nodata] = np.nan

        valid = dem[~np.isnan(dem)]
        if len(valid) == 0:
            return {"available": False, "error": "No valid elevation data."}

        # Slope calculation (degrees) using numpy gradient
        dy, dx = np.gradient(dem, pixel_size_m, pixel_size_m)
        slope_rad = np.arctan(np.sqrt(dx ** 2 + dy ** 2))
        slope_deg = np.degrees(slope_rad)
        valid_slope = slope_deg[~np.isnan(slope_deg)]

        # Compute real-world terrain dimensions
        terrain_w, terrain_h, origin_lat, origin_lon = _compute_bbox_dimensions_metres(bbox)

        return {
            "available": True,
            "bbox": list(bbox),
            "origin_lat": round(origin_lat, 7),
            "origin_lon": round(origin_lon, 7),
            "terrain_width_m": round(terrain_w, 1),
            "terrain_height_m": round(terrain_h, 1),
            "elevation": {
                "min_m": round(float(np.nanmin(valid)), 1),
                "max_m": round(float(np.nanmax(valid)), 1),
                "mean_m": round(float(np.nanmean(valid)), 1),
                "std_m": round(float(np.nanstd(valid)), 1),
                "median_m": round(float(np.nanmedian(valid)), 1),
            },
            "slope": {
                "min_deg": round(float(np.min(valid_slope)), 1) if len(valid_slope) else 0.0,
                "max_deg": round(float(np.max(valid_slope)), 1) if len(valid_slope) else 0.0,
                "mean_deg": round(float(np.mean(valid_slope)), 1) if len(valid_slope) else 0.0,
                "std_deg": round(float(np.std(valid_slope)), 1) if len(valid_slope) else 0.0,
            },
            "source": "OpenTopography",
        }

    except Exception as exc:
        logger.error("Terrain stats computation failed: %s", exc)
        return {
            "available": False,
            "error": str(exc),
            "bbox": list(bbox),
        }


def generate_hillshade(
    dem_bytes: bytes,
    azimuth: float = 315.0,
    altitude: float = 45.0,
) -> Optional[bytes]:
    """Generate a hillshade visualisation from DEM data as a PNG image.

    Args:
        dem_bytes: GeoTIFF DEM bytes.
        azimuth: Sun azimuth in degrees (default 315 = NW).
        altitude: Sun altitude angle in degrees above horizon.

    Returns:
        PNG image bytes, or ``None`` on failure.
    """
    try:
        import rasterio
        from PIL import Image

        with rasterio.open(io.BytesIO(dem_bytes)) as src:
            dem = src.read(1).astype(np.float32)
            nodata = src.nodata
            pixel_size_m = abs(src.transform.a) * 111320

        if nodata is not None:
            dem[np.isclose(dem, nodata)] = np.nan

        # Fill NaN with mean for gradient calculation
        mean_val = float(np.nanmean(dem))
        dem_filled = np.where(np.isnan(dem), mean_val, dem)

        dy, dx = np.gradient(dem_filled, pixel_size_m, pixel_size_m)
        slope = np.arctan(np.sqrt(dx ** 2 + dy ** 2))
        aspect = np.arctan2(-dx, dy)

        az_rad = math.radians(azimuth)
        alt_rad = math.radians(altitude)

        hillshade = (
            np.sin(alt_rad) * np.cos(slope)
            + np.cos(alt_rad) * np.sin(slope) * np.cos(az_rad - aspect)
        )

        # Normalise to 0-255
        hs_norm = ((hillshade - hillshade.min()) / max(hillshade.ptp(), 1e-6) * 255).astype(np.uint8)

        img = Image.fromarray(hs_norm, mode="L")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    except Exception as exc:
        logger.error("Hillshade generation failed: %s", exc)
        return None
