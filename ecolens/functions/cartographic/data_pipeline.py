"""
Cartographic Data Pipeline

Unified data sourcing system for the Cartographic Intelligence Engine.
Discovers, fetches, validates, and caches geospatial data from 10+ credible
sources for map generation.

Architecture:
  DataSourceRegistry  — catalog of all available data sources with metadata
  DataFetcher         — dispatches to existing EcoLens services + new fetchers
  DataValidator       — schema checks, outlier detection, completeness
  DataPipeline        — orchestrates discovery → fetch → validate → cache

Reuses existing services:
  - FIRMSService (NASA fire data)
  - GFWService (Global Forest Watch)
  - ProfessionalGISService (OSM, buffers, proximity)
  - DEM functions (SRTM, Copernicus elevation)
  - NDVI functions (MODIS, Sentinel vegetation)
  - WorldPopService (population density)
  - SentinelVerificationAgent (Sentinel-2 imagery)
  - TerrainAnalysisAgent (slope, aspect)
  - SoilAnalysisAgent (soil properties)
  - HydrologyAnalysisAgent (water features)
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Callable

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════
# DATA SOURCE METADATA
# ═══════════════════════════════════════════════════════════════════════

class SourceCategory(Enum):
    """Categories of geospatial data."""
    BASEMAP = "basemap"                # Background context (admin boundaries, coastlines)
    ENVIRONMENTAL = "environmental"    # Vegetation, land cover, ecosystem health
    HAZARD = "hazard"                  # Fires, floods, earthquakes, drought
    DEMOGRAPHIC = "demographic"        # Population, settlements
    TERRAIN = "terrain"                # Elevation, slope, aspect
    INFRASTRUCTURE = "infrastructure"  # Roads, rivers, protected areas
    SOIL = "soil"                      # Soil properties, fertility
    HYDROLOGY = "hydrology"            # Water features, precipitation


class DataFormat(Enum):
    """Format of fetched data."""
    GEOJSON = "geojson"       # Vector features
    DICT = "dict"             # Structured dictionary (most EcoLens services)
    GEOTIFF = "geotiff"       # Raster data
    CSV = "csv"               # Tabular (fire points)
    IMAGE_URL = "image_url"   # Remote image (Sentinel tiles)


class UpdateFrequency(Enum):
    """How often the source data is updated."""
    REALTIME = "realtime"         # Updated continuously (FIRMS)
    DAILY = "daily"               # Updated daily
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    ANNUAL = "annual"             # Yearly updates (GFW tree loss)
    STATIC = "static"             # Never changes (Natural Earth)


@dataclass
class DataSource:
    """
    Metadata for a geospatial data source.

    Each source has a unique ID, provider info, quality metadata,
    and a reference to the fetch function to call.
    """
    id: str
    name: str
    provider: str
    category: SourceCategory
    themes: list[str]               # Which EcoLens themes this source serves
    description: str
    attribution: str                # Required credit text for maps
    spatial_resolution: str         # "375m", "30m", "1:10m", etc.
    update_frequency: UpdateFrequency
    data_format: DataFormat
    requires_bbox: bool             # Does it need a bounding box?
    requires_point: bool            # Does it need a center point?
    coverage: str                   # "global", "tropical", "land_only", etc.
    fetch_method: str               # Name of method in DataFetcher to call
    quality_tier: int               # 1=gold standard, 2=good, 3=acceptable
    max_bbox_deg: float | None      # Max bbox size in degrees (None = unlimited)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "provider": self.provider,
            "category": self.category.value,
            "themes": self.themes,
            "description": self.description,
            "attribution": self.attribution,
            "spatial_resolution": self.spatial_resolution,
            "update_frequency": self.update_frequency.value,
            "data_format": self.data_format.value,
            "coverage": self.coverage,
            "quality_tier": self.quality_tier,
        }


# ═══════════════════════════════════════════════════════════════════════
# DATA SOURCE REGISTRY
# ═══════════════════════════════════════════════════════════════════════

class DataSourceRegistry:
    """
    Catalog of all credible geospatial data sources.

    Provides discovery by:
    - Geographic extent (bbox)
    - Theme (deforestation, fire_risk, etc.)
    - Category (hazard, environmental, etc.)
    - Quality tier
    """

    # ─── SOURCE CATALOG ───────────────────────────────────────────

    SOURCES: dict[str, DataSource] = {

        # ─── BASEMAP / REFERENCE ──────────────────────────────────

        "natural_earth_admin": DataSource(
            id="natural_earth_admin",
            name="Natural Earth Admin Boundaries",
            provider="Natural Earth",
            category=SourceCategory.BASEMAP,
            themes=["all"],
            description="Country, state/province boundaries at 1:10m/50m/110m scales. "
                       "The gold standard for basemap boundaries.",
            attribution="Made with Natural Earth. naturalearthdata.com",
            spatial_resolution="1:10m",
            update_frequency=UpdateFrequency.STATIC,
            data_format=DataFormat.GEOJSON,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_natural_earth",
            quality_tier=1,
            max_bbox_deg=None,
        ),

        "natural_earth_physical": DataSource(
            id="natural_earth_physical",
            name="Natural Earth Physical Features",
            provider="Natural Earth",
            category=SourceCategory.BASEMAP,
            themes=["all"],
            description="Coastlines, rivers, lakes, glaciated areas. "
                       "Essential context for any map.",
            attribution="Made with Natural Earth. naturalearthdata.com",
            spatial_resolution="1:10m",
            update_frequency=UpdateFrequency.STATIC,
            data_format=DataFormat.GEOJSON,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_natural_earth_physical",
            quality_tier=1,
            max_bbox_deg=None,
        ),

        # ─── HAZARD DATA ─────────────────────────────────────────

        "nasa_firms": DataSource(
            id="nasa_firms",
            name="NASA FIRMS Active Fires",
            provider="NASA",
            category=SourceCategory.HAZARD,
            themes=["fire_risk", "multi_hazard", "change_detection"],
            description="Near-real-time active fire detections from VIIRS (375m). "
                       "Updated every few hours. Gold standard for fire monitoring.",
            attribution="NASA FIRMS. firms.modaps.eosdis.nasa.gov",
            spatial_resolution="375m",
            update_frequency=UpdateFrequency.REALTIME,
            data_format=DataFormat.DICT,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_firms_fires",
            quality_tier=1,
            max_bbox_deg=10.0,
        ),

        "usgs_earthquakes": DataSource(
            id="usgs_earthquakes",
            name="USGS Earthquake Hazards",
            provider="USGS",
            category=SourceCategory.HAZARD,
            themes=["earthquake", "multi_hazard"],
            description="Real-time and historical earthquake catalog. "
                       "Magnitude, depth, location for all M2.5+ events.",
            attribution="USGS Earthquake Hazards Program. earthquake.usgs.gov",
            spatial_resolution="point",
            update_frequency=UpdateFrequency.REALTIME,
            data_format=DataFormat.GEOJSON,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_usgs_earthquakes",
            quality_tier=1,
            max_bbox_deg=None,
        ),

        # ─── ENVIRONMENTAL ───────────────────────────────────────

        "global_forest_watch": DataSource(
            id="global_forest_watch",
            name="Global Forest Watch Tree Cover Loss",
            provider="World Resources Institute / UMD",
            category=SourceCategory.ENVIRONMENTAL,
            themes=["deforestation", "change_detection", "biodiversity"],
            description="Annual tree cover loss 2001-present from Hansen/UMD. "
                       "30m resolution Landsat-derived. The definitive deforestation dataset.",
            attribution="Hansen/UMD/Google/USGS/NASA, Global Forest Watch. globalforestwatch.org",
            spatial_resolution="30m",
            update_frequency=UpdateFrequency.ANNUAL,
            data_format=DataFormat.DICT,
            requires_bbox=False,
            requires_point=True,
            coverage="global",
            fetch_method="fetch_gfw_tree_loss",
            quality_tier=1,
            max_bbox_deg=5.0,
        ),

        "ndvi_modis": DataSource(
            id="ndvi_modis",
            name="MODIS NDVI Vegetation Index",
            provider="NASA",
            category=SourceCategory.ENVIRONMENTAL,
            themes=["vegetation_health", "drought", "change_detection", "biodiversity"],
            description="16-day NDVI composite from MODIS (MOD13Q1). "
                       "250m resolution. Long time series from 2000.",
            attribution="NASA LP DAAC, MODIS MOD13Q1",
            spatial_resolution="250m",
            update_frequency=UpdateFrequency.MONTHLY,
            data_format=DataFormat.DICT,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_ndvi",
            quality_tier=1,
            max_bbox_deg=5.0,
        ),

        "sentinel2_imagery": DataSource(
            id="sentinel2_imagery",
            name="Sentinel-2 Satellite Imagery",
            provider="ESA / Copernicus",
            category=SourceCategory.ENVIRONMENTAL,
            themes=["vegetation_health", "deforestation", "change_detection"],
            description="10m multispectral imagery with cloud-free composites. "
                       "Change detection and vegetation indices.",
            attribution="Contains modified Copernicus Sentinel data",
            spatial_resolution="10m",
            update_frequency=UpdateFrequency.WEEKLY,
            data_format=DataFormat.IMAGE_URL,
            requires_bbox=False,
            requires_point=True,
            coverage="global_land",
            fetch_method="fetch_sentinel2",
            quality_tier=1,
            max_bbox_deg=2.0,
        ),

        # ─── TERRAIN ─────────────────────────────────────────────

        "copernicus_dem": DataSource(
            id="copernicus_dem",
            name="Copernicus DEM / SRTM Elevation",
            provider="ESA Copernicus / NASA",
            category=SourceCategory.TERRAIN,
            themes=["flood_risk", "multi_hazard", "terrain"],
            description="30m digital elevation model (SRTM GL1). "
                       "Elevation, slope, aspect, hillshade generation.",
            attribution="NASA SRTM / Copernicus GLO-30",
            spatial_resolution="30m",
            update_frequency=UpdateFrequency.STATIC,
            data_format=DataFormat.GEOTIFF,
            requires_bbox=True,
            requires_point=False,
            coverage="global_land",
            fetch_method="fetch_dem",
            quality_tier=1,
            max_bbox_deg=5.0,
        ),

        "terrain_analysis": DataSource(
            id="terrain_analysis",
            name="Terrain Slope & Aspect Analysis",
            provider="Open-Elevation / NASA",
            category=SourceCategory.TERRAIN,
            themes=["flood_risk", "fire_risk", "multi_hazard"],
            description="Slope, aspect, ruggedness analysis from elevation data. "
                       "Includes suitability classification.",
            attribution="Open-Elevation API / NASA SRTM",
            spatial_resolution="30m",
            update_frequency=UpdateFrequency.STATIC,
            data_format=DataFormat.DICT,
            requires_bbox=True,
            requires_point=False,
            coverage="global_land",
            fetch_method="fetch_terrain_analysis",
            quality_tier=2,
            max_bbox_deg=5.0,
        ),

        # ─── DEMOGRAPHIC ─────────────────────────────────────────

        "worldpop": DataSource(
            id="worldpop",
            name="WorldPop Population Density",
            provider="WorldPop / University of Southampton",
            category=SourceCategory.DEMOGRAPHIC,
            themes=["population_exposure", "multi_hazard", "flood_risk"],
            description="High-resolution population density estimates. "
                       "100m resolution, 2020 calibrated, UN-adjusted.",
            attribution="WorldPop, University of Southampton. worldpop.org",
            spatial_resolution="100m",
            update_frequency=UpdateFrequency.ANNUAL,
            data_format=DataFormat.DICT,
            requires_bbox=False,
            requires_point=True,
            coverage="global_land",
            fetch_method="fetch_worldpop",
            quality_tier=1,
            max_bbox_deg=None,
        ),

        # ─── INFRASTRUCTURE ──────────────────────────────────────

        "osm_infrastructure": DataSource(
            id="osm_infrastructure",
            name="OpenStreetMap Infrastructure",
            provider="OpenStreetMap Contributors",
            category=SourceCategory.INFRASTRUCTURE,
            themes=["multi_hazard", "population_exposure", "flood_risk"],
            description="Roads, buildings, settlements, waterways from OSM. "
                       "Crowdsourced but highly detailed in populated areas.",
            attribution="© OpenStreetMap contributors",
            spatial_resolution="vector",
            update_frequency=UpdateFrequency.DAILY,
            data_format=DataFormat.DICT,
            requires_bbox=True,
            requires_point=True,
            coverage="global",
            fetch_method="fetch_osm_infrastructure",
            quality_tier=2,
            max_bbox_deg=2.0,
        ),

        "protected_areas": DataSource(
            id="protected_areas",
            name="WDPA Protected Areas",
            provider="UNEP-WCMC / IUCN",
            category=SourceCategory.INFRASTRUCTURE,
            themes=["biodiversity", "deforestation", "conservation"],
            description="World Database on Protected Areas. IUCN categories, "
                       "management effectiveness, coverage.",
            attribution="UNEP-WCMC and IUCN, Protected Planet. protectedplanet.net",
            spatial_resolution="vector",
            update_frequency=UpdateFrequency.MONTHLY,
            data_format=DataFormat.GEOJSON,
            requires_bbox=True,
            requires_point=False,
            coverage="global",
            fetch_method="fetch_protected_areas",
            quality_tier=1,
            max_bbox_deg=10.0,
        ),

        # ─── SOIL ────────────────────────────────────────────────

        "isric_soilgrids": DataSource(
            id="isric_soilgrids",
            name="ISRIC SoilGrids",
            provider="ISRIC — World Soil Information",
            category=SourceCategory.SOIL,
            themes=["biodiversity", "drought", "vegetation_health"],
            description="Global soil property predictions at 250m. "
                       "pH, texture, organic carbon, fertility classification.",
            attribution="ISRIC — World Soil Information. soilgrids.org",
            spatial_resolution="250m",
            update_frequency=UpdateFrequency.STATIC,
            data_format=DataFormat.DICT,
            requires_bbox=False,
            requires_point=True,
            coverage="global_land",
            fetch_method="fetch_soil",
            quality_tier=1,
            max_bbox_deg=None,
        ),

        # ─── HYDROLOGY ───────────────────────────────────────────

        "hydrology_features": DataSource(
            id="hydrology_features",
            name="Water Features & Stress",
            provider="OSM / Regional Water Data",
            category=SourceCategory.HYDROLOGY,
            themes=["flood_risk", "drought", "biodiversity"],
            description="Nearby rivers, lakes, water stress assessment. "
                       "Includes seasonal patterns and accessibility rating.",
            attribution="OpenStreetMap contributors / Regional water authorities",
            spatial_resolution="vector",
            update_frequency=UpdateFrequency.MONTHLY,
            data_format=DataFormat.DICT,
            requires_bbox=True,
            requires_point=True,
            coverage="global",
            fetch_method="fetch_hydrology",
            quality_tier=2,
            max_bbox_deg=5.0,
        ),
    }

    def discover(
        self,
        bbox: tuple[float, float, float, float] | None = None,
        theme: str | None = None,
        categories: list[SourceCategory] | None = None,
        min_quality_tier: int = 3,
    ) -> list[DataSource]:
        """
        Discover available data sources for given parameters.

        Args:
            bbox: (west, south, east, north) in WGS84 degrees
            theme: EcoLens theme (deforestation, fire_risk, etc.)
            categories: Filter by source categories
            min_quality_tier: Maximum quality tier (1=best, 3=acceptable)

        Returns:
            List of DataSource objects matching criteria, sorted by quality_tier
        """
        results = []

        for source in self.SOURCES.values():
            # Quality filter
            if source.quality_tier > min_quality_tier:
                continue

            # Theme filter
            if theme and "all" not in source.themes and theme not in source.themes:
                continue

            # Category filter
            if categories and source.category not in categories:
                continue

            # Note: we do NOT filter by max_bbox_deg here.
            # Discovery shows what's thematically relevant.
            # The fetcher handles bbox-too-large by tiling or center-point fallback.

            results.append(source)

        # Sort by quality tier (best first)
        results.sort(key=lambda s: s.quality_tier)
        return results

    def get_source(self, source_id: str) -> DataSource | None:
        """Get a specific source by ID."""
        return self.SOURCES.get(source_id)

    def get_attributions(self, source_ids: list[str]) -> list[str]:
        """Get attribution strings for a list of source IDs."""
        attributions = []
        for sid in source_ids:
            source = self.SOURCES.get(sid)
            if source:
                attributions.append(source.attribution)
        return attributions

    def list_all(self) -> list[dict]:
        """List all sources with basic metadata."""
        return [s.to_dict() for s in self.SOURCES.values()]


# ═══════════════════════════════════════════════════════════════════════
# DATA QUALITY REPORT
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class DataQualityReport:
    """Quality assessment of fetched data."""
    source_id: str
    passed: bool
    record_count: int
    null_count: int
    null_percentage: float
    has_geometry: bool
    geometry_type: str | None
    crs: str | None
    bbox_coverage: float          # 0-1, how much of requested bbox is covered
    outlier_count: int
    issues: list[str]
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "source_id": self.source_id,
            "passed": self.passed,
            "record_count": self.record_count,
            "null_count": self.null_count,
            "null_percentage": round(self.null_percentage, 2),
            "has_geometry": self.has_geometry,
            "geometry_type": self.geometry_type,
            "crs": self.crs,
            "bbox_coverage": round(self.bbox_coverage, 2),
            "outlier_count": self.outlier_count,
            "issues": self.issues,
        }


# ═══════════════════════════════════════════════════════════════════════
# DATA FETCHER — DISPATCHES TO EXISTING SERVICES
# ═══════════════════════════════════════════════════════════════════════

class DataFetcher:
    """
    Fetches data from all registered sources by dispatching to
    existing EcoLens services and new fetchers.

    Each fetch method returns a standardized FetchResult dict:
    {
        "available": bool,
        "data": Any,           # The actual data (GeoJSON, dict, bytes)
        "format": str,         # "geojson", "dict", "geotiff", "image_url"
        "record_count": int,
        "source_id": str,
        "attribution": str,
        "metadata": dict,      # Resolution, date range, CRS, etc.
        "error": str | None,
    }
    """

    def __init__(self):
        """Initialize with lazy service loading."""
        self._firms = None
        self._gfw = None
        self._gis = None
        self._worldpop = None
        self._sentinel = None
        self._terrain = None
        self._soil = None
        self._hydrology = None

    # ─── LAZY SERVICE ACCESSORS ───────────────────────────────────

    @property
    def firms(self):
        if self._firms is None:
            try:
                from services.firms_service import FIRMSService
                self._firms = FIRMSService()
            except (ImportError, ValueError):
                logger.warning("FIRMSService not available")
        return self._firms

    @property
    def gfw(self):
        if self._gfw is None:
            try:
                from services.gfw_service import GFWService
                self._gfw = GFWService()
            except (ImportError, ValueError):
                logger.warning("GFWService not available")
        return self._gfw

    @property
    def gis(self):
        if self._gis is None:
            try:
                from services.professional_gis_service import ProfessionalGISService
                self._gis = ProfessionalGISService()
            except ImportError:
                logger.warning("ProfessionalGISService not available")
        return self._gis

    @property
    def worldpop(self):
        if self._worldpop is None:
            try:
                from services.worldpop_service import WorldPopService
                self._worldpop = WorldPopService()
            except ImportError:
                logger.warning("WorldPopService not available")
        return self._worldpop

    @property
    def sentinel(self):
        if self._sentinel is None:
            try:
                from agents.sentinel_verification_agent import SentinelVerificationAgent
                self._sentinel = SentinelVerificationAgent()
            except ImportError:
                logger.warning("SentinelVerificationAgent not available")
        return self._sentinel

    @property
    def terrain_agent(self):
        if self._terrain is None:
            try:
                from agents.terrain_analysis_agent import TerrainAnalysisAgent
                self._terrain = TerrainAnalysisAgent()
            except ImportError:
                logger.warning("TerrainAnalysisAgent not available")
        return self._terrain

    @property
    def soil_agent(self):
        if self._soil is None:
            try:
                from agents.soil_analysis_agent import SoilAnalysisAgent
                self._soil = SoilAnalysisAgent()
            except ImportError:
                logger.warning("SoilAnalysisAgent not available")
        return self._soil

    @property
    def hydrology_agent(self):
        if self._hydrology is None:
            try:
                from agents.hydrology_analysis_agent import HydrologyAnalysisAgent
                self._hydrology = HydrologyAnalysisAgent()
            except ImportError:
                logger.warning("HydrologyAnalysisAgent not available")
        return self._hydrology

    # ─── FETCH METHODS ────────────────────────────────────────────

    def fetch(
        self,
        source: DataSource,
        bbox: tuple[float, float, float, float] | None = None,
        center: tuple[float, float] | None = None,
        date_range: tuple[str, str] | None = None,
        **kwargs,
    ) -> dict:
        """
        Dispatch to the appropriate fetch method for a data source.

        Args:
            source: DataSource to fetch from
            bbox: (west, south, east, north)
            center: (lat, lng) center point
            date_range: (start_date, end_date) ISO format
            **kwargs: Additional source-specific parameters

        Returns:
            Standardized FetchResult dict
        """
        method = getattr(self, source.fetch_method, None)
        if method is None:
            return self._error_result(source.id, f"No fetch method: {source.fetch_method}")

        try:
            return method(source=source, bbox=bbox, center=center,
                         date_range=date_range, **kwargs)
        except Exception as e:
            logger.error(f"Fetch failed for {source.id}: {e}")
            return self._error_result(source.id, str(e))

    def fetch_firms_fires(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch NASA FIRMS active fire detections."""
        if not bbox:
            return self._error_result(source.id, "FIRMS requires bbox")
        if not self.firms:
            return self._error_result(source.id, "FIRMSService not available")

        bbox_dict = {
            "min_lng": bbox[0], "min_lat": bbox[1],
            "max_lng": bbox[2], "max_lat": bbox[3],
        }
        fires = self.firms.fetch(bbox_dict)

        if not fires:
            return self._empty_result(source.id, "No active fires in bbox")

        # Convert to GeoJSON FeatureCollection for uniform handling
        features = []
        for f in fires:
            lat = f.get("latitude") or f.get("lat")
            lng = f.get("longitude") or f.get("lng") or f.get("lon")
            if lat and lng:
                features.append({
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [float(lng), float(lat)]},
                    "properties": {
                        "brightness": f.get("bright_ti4") or f.get("brightness"),
                        "confidence": f.get("confidence"),
                        "frp": f.get("frp"),
                        "acq_date": f.get("acq_date"),
                        "satellite": f.get("satellite", "VIIRS"),
                        "source": "NASA FIRMS",
                    },
                })

        geojson = {"type": "FeatureCollection", "features": features}
        return {
            "available": True,
            "data": geojson,
            "format": "geojson",
            "record_count": len(features),
            "source_id": source.id,
            "attribution": source.attribution,
            "metadata": {
                "resolution": "375m",
                "satellite": "VIIRS SNPP",
                "update_frequency": "near-realtime",
            },
            "error": None,
        }

    def fetch_usgs_earthquakes(
        self, source: DataSource, bbox: tuple | None = None,
        date_range: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch USGS earthquake catalog via GeoJSON API."""
        import requests

        if not bbox:
            return self._error_result(source.id, "USGS earthquakes requires bbox")

        params = {
            "format": "geojson",
            "minlatitude": bbox[1],
            "maxlatitude": bbox[3],
            "minlongitude": bbox[0],
            "maxlongitude": bbox[2],
            "minmagnitude": kwargs.get("min_magnitude", 4.0),
            "orderby": "magnitude",
            "limit": kwargs.get("limit", 500),
        }

        if date_range:
            params["starttime"] = date_range[0]
            params["endtime"] = date_range[1]
        else:
            # Default to last 25 years
            params["starttime"] = "2000-01-01"

        try:
            resp = requests.get(
                "https://earthquake.usgs.gov/fdsnws/event/1/query",
                params=params,
                timeout=30,
            )
            resp.raise_for_status()
            geojson = resp.json()

            return {
                "available": True,
                "data": geojson,
                "format": "geojson",
                "record_count": len(geojson.get("features", [])),
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "min_magnitude": params["minmagnitude"],
                    "date_range": [params.get("starttime"), params.get("endtime")],
                    "api": "USGS FDSN Event Web Service",
                },
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"USGS API error: {e}")

    def fetch_gfw_tree_loss(
        self, source: DataSource, center: tuple | None = None,
        date_range: tuple | None = None, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch Global Forest Watch tree cover loss data."""
        if not self.gfw:
            return self._error_result(source.id, "GFWService not available")

        if bbox:
            # Create GeoJSON polygon from bbox
            west, south, east, north = bbox
            aoi = {
                "type": "Polygon",
                "coordinates": [[
                    [west, south], [east, south], [east, north],
                    [west, north], [west, south],
                ]],
            }
        elif center:
            # Create a small polygon around center point
            lat, lng = center
            delta = 0.5  # ~50km radius
            aoi = {
                "type": "Polygon",
                "coordinates": [[
                    [lng - delta, lat - delta], [lng + delta, lat - delta],
                    [lng + delta, lat + delta], [lng - delta, lat + delta],
                    [lng - delta, lat - delta],
                ]],
            }
        else:
            return self._error_result(source.id, "GFW requires bbox or center point")

        start = date_range[0] if date_range else "2001-01-01"
        end = date_range[1] if date_range else datetime.now().strftime("%Y-%m-%d")

        try:
            result = self.gfw.fetch_tree_loss(aoi, start, end)
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "resolution": "30m",
                    "date_range": [start, end],
                    "source_dataset": "Hansen/UMD",
                },
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"GFW error: {e}")

    def fetch_ndvi(
        self, source: DataSource, bbox: tuple | None = None,
        date_range: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch MODIS NDVI vegetation index."""
        if not bbox:
            return self._error_result(source.id, "NDVI requires bbox")

        try:
            from services.ndvi_service import fetch_ndvi_modis
            start = date_range[0] if date_range else None
            end = date_range[1] if date_range else None
            result = fetch_ndvi_modis(bbox, start_date=start, end_date=end)

            return {
                "available": result.get("available", True),
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "resolution": "250m",
                    "product": "MOD13Q1",
                    "satellite": "MODIS Terra",
                },
                "error": result.get("error"),
            }
        except Exception as e:
            return self._error_result(source.id, f"NDVI error: {e}")

    def fetch_dem(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch DEM elevation data."""
        if not bbox:
            return self._error_result(source.id, "DEM requires bbox")

        try:
            from services.dem_service import get_terrain_stats, generate_hillshade
            stats = get_terrain_stats(bbox)

            return {
                "available": True,
                "data": stats,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "resolution": "30m",
                    "source_dem": "SRTM GL1 / Copernicus GLO-30",
                },
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"DEM error: {e}")

    def fetch_terrain_analysis(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch terrain slope/aspect analysis."""
        if not bbox:
            return self._error_result(source.id, "Terrain analysis requires bbox")
        if not self.terrain_agent:
            return self._error_result(source.id, "TerrainAnalysisAgent not available")

        try:
            bbox_dict = {
                "min_lat": bbox[1], "max_lat": bbox[3],
                "min_lng": bbox[0], "max_lng": bbox[2],
            }
            result = self.terrain_agent.analyze(bbox_dict)
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {"analysis": "slope, aspect, ruggedness"},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"Terrain error: {e}")

    def fetch_worldpop(
        self, source: DataSource, center: tuple | None = None,
        bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch WorldPop population data."""
        if not self.worldpop:
            return self._error_result(source.id, "WorldPopService not available")

        lat, lng = None, None
        if center:
            lat, lng = center
        elif bbox:
            lat = (bbox[1] + bbox[3]) / 2
            lng = (bbox[0] + bbox[2]) / 2

        if lat is None:
            return self._error_result(source.id, "WorldPop requires center or bbox")

        try:
            radius_km = kwargs.get("radius_km", 50)
            result = self.worldpop.get_population_estimate(lat, lng, radius_km)
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "resolution": "100m",
                    "calibration_year": 2020,
                    "radius_km": radius_km,
                },
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"WorldPop error: {e}")

    def fetch_sentinel2(
        self, source: DataSource, center: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch Sentinel-2 verification imagery."""
        if not self.sentinel:
            return self._error_result(source.id, "SentinelVerificationAgent not available")

        if not center:
            return self._error_result(source.id, "Sentinel-2 requires center point")

        try:
            lat, lng = center
            result = self.sentinel.verify_with_sentinel(lat, lng)
            return {
                "available": True,
                "data": result,
                "format": "image_url",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {
                    "resolution": "10m",
                    "satellite": "Sentinel-2 L2A",
                },
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"Sentinel error: {e}")

    def fetch_soil(
        self, source: DataSource, center: tuple | None = None,
        bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch ISRIC SoilGrids properties."""
        if not self.soil_agent:
            return self._error_result(source.id, "SoilAnalysisAgent not available")

        lat, lng = None, None
        if center:
            lat, lng = center
        elif bbox:
            lat = (bbox[1] + bbox[3]) / 2
            lng = (bbox[0] + bbox[2]) / 2

        if lat is None:
            return self._error_result(source.id, "Soil requires center or bbox")

        try:
            result = self.soil_agent.analyze(lat, lng)
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {"resolution": "250m", "depth": "5-15cm"},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"Soil error: {e}")

    def fetch_hydrology(
        self, source: DataSource, center: tuple | None = None,
        bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch water features and hydrological assessment."""
        if not self.hydrology_agent:
            return self._error_result(source.id, "HydrologyAnalysisAgent not available")

        lat, lng = None, None
        if center:
            lat, lng = center
        elif bbox:
            lat = (bbox[1] + bbox[3]) / 2
            lng = (bbox[0] + bbox[2]) / 2

        if lat is None:
            return self._error_result(source.id, "Hydrology requires center or bbox")

        try:
            bbox_dict = None
            if bbox:
                bbox_dict = {
                    "min_lat": bbox[1], "max_lat": bbox[3],
                    "min_lng": bbox[0], "max_lng": bbox[2],
                }
            result = self.hydrology_agent.analyze(lat, lng, bbox_dict or {})
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {"analysis": "water features, stress, accessibility"},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"Hydrology error: {e}")

    def fetch_osm_infrastructure(
        self, source: DataSource, center: tuple | None = None,
        bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch infrastructure data via ProfessionalGISService."""
        if not self.gis:
            return self._error_result(source.id, "ProfessionalGISService not available")

        lat, lng = None, None
        if center:
            lat, lng = center
        elif bbox:
            lat = (bbox[1] + bbox[3]) / 2
            lng = (bbox[0] + bbox[2]) / 2

        if lat is None:
            return self._error_result(source.id, "OSM requires center or bbox")

        try:
            bbox_dict = None
            if bbox:
                bbox_dict = {
                    "min_lat": bbox[1], "max_lat": bbox[3],
                    "min_lng": bbox[0], "max_lng": bbox[2],
                }
            result = self.gis.comprehensive_analysis(lat, lng, bbox_dict or {})
            return {
                "available": True,
                "data": result,
                "format": "dict",
                "record_count": 1,
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {"source": "OpenStreetMap Overpass API"},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"OSM/GIS error: {e}")

    def fetch_natural_earth(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """
        Fetch Natural Earth admin boundaries.

        Uses the Natural Earth GeoJSON hosted on GitHub
        (no shapefile download needed).
        """
        import requests

        scale = kwargs.get("scale", "110m")  # 10m, 50m, or 110m
        layer = kwargs.get("layer", "admin_0_countries")

        url = (
            f"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
            f"master/geojson/ne_{scale}_{layer}.geojson"
        )

        try:
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            geojson = resp.json()

            # Filter to bbox if provided
            if bbox:
                filtered = self._filter_geojson_by_bbox(geojson, bbox)
            else:
                filtered = geojson

            return {
                "available": True,
                "data": filtered,
                "format": "geojson",
                "record_count": len(filtered.get("features", [])),
                "source_id": source.id,
                "attribution": source.attribution,
                "metadata": {"scale": scale, "layer": layer},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"Natural Earth error: {e}")

    def fetch_natural_earth_physical(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """Fetch Natural Earth physical features (coastlines, rivers, lakes)."""
        return self.fetch_natural_earth(
            source=source, bbox=bbox,
            layer=kwargs.get("layer", "coastline"),
            scale=kwargs.get("scale", "110m"),
        )

    def fetch_protected_areas(
        self, source: DataSource, bbox: tuple | None = None, **kwargs
    ) -> dict:
        """
        Fetch WDPA protected areas via the Protected Planet API.
        Falls back to OSM protected areas if API unavailable.
        """
        import requests

        if not bbox:
            return self._error_result(source.id, "WDPA requires bbox")

        # Use Protected Planet API v3
        token = kwargs.get("api_token", os.environ.get("WDPA_API_TOKEN", ""))

        if token:
            try:
                resp = requests.get(
                    "https://api.protectedplanet.net/v3/protected_areas/search",
                    params={
                        "token": token,
                        "with_geometry": "true",
                        "per_page": 50,
                        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}",
                    },
                    timeout=30,
                )
                resp.raise_for_status()
                data = resp.json()

                features = []
                for pa in data.get("protected_areas", []):
                    geo = pa.get("geojson", {}).get("geometry")
                    if geo:
                        features.append({
                            "type": "Feature",
                            "geometry": geo,
                            "properties": {
                                "name": pa.get("name"),
                                "iucn_category": pa.get("iucn_category", {}).get("name"),
                                "designation": pa.get("designation", {}).get("name"),
                                "reported_area_km2": pa.get("reported_area"),
                                "source": "WDPA",
                            },
                        })

                geojson = {"type": "FeatureCollection", "features": features}
                return {
                    "available": True,
                    "data": geojson,
                    "format": "geojson",
                    "record_count": len(features),
                    "source_id": source.id,
                    "attribution": source.attribution,
                    "metadata": {"api": "Protected Planet v3"},
                    "error": None,
                }
            except Exception as e:
                logger.warning(f"WDPA API failed, falling back to OSM: {e}")

        # Fallback: query OSM for protected areas
        return self._fetch_osm_protected_areas(source, bbox)

    def _fetch_osm_protected_areas(
        self, source: DataSource, bbox: tuple
    ) -> dict:
        """Fallback: fetch protected areas from OpenStreetMap."""
        import requests

        overpass_query = f"""
        [out:json][timeout:25];
        (
          way["boundary"="protected_area"]({bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]});
          relation["boundary"="protected_area"]({bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]});
          way["boundary"="national_park"]({bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]});
          relation["boundary"="national_park"]({bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]});
        );
        out center;
        """

        try:
            resp = requests.post(
                "https://overpass-api.de/api/interpreter",
                data={"data": overpass_query},
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()

            features = []
            for elem in data.get("elements", []):
                center = elem.get("center", {})
                lat = center.get("lat") or elem.get("lat")
                lon = center.get("lon") or elem.get("lon")
                if lat and lon:
                    tags = elem.get("tags", {})
                    features.append({
                        "type": "Feature",
                        "geometry": {"type": "Point", "coordinates": [lon, lat]},
                        "properties": {
                            "name": tags.get("name", "Unknown"),
                            "protection_class": tags.get("protect_class"),
                            "designation": tags.get("designation"),
                            "source": "OpenStreetMap",
                        },
                    })

            geojson = {"type": "FeatureCollection", "features": features}
            return {
                "available": True,
                "data": geojson,
                "format": "geojson",
                "record_count": len(features),
                "source_id": source.id,
                "attribution": "© OpenStreetMap contributors",
                "metadata": {"source": "OpenStreetMap Overpass (fallback)"},
                "error": None,
            }
        except Exception as e:
            return self._error_result(source.id, f"OSM protected areas error: {e}")

    # ─── HELPER METHODS ──────────────────────────────────────────

    @staticmethod
    def _filter_geojson_by_bbox(
        geojson: dict, bbox: tuple[float, float, float, float]
    ) -> dict:
        """Filter GeoJSON features to those intersecting a bbox."""
        west, south, east, north = bbox
        filtered_features = []

        for feature in geojson.get("features", []):
            coords = feature.get("geometry", {}).get("coordinates")
            if not coords:
                continue

            # Simple centroid check for polygons/multipolygons
            geo_type = feature.get("geometry", {}).get("type", "")

            if geo_type == "Point":
                lon, lat = coords[0], coords[1]
                if west <= lon <= east and south <= lat <= north:
                    filtered_features.append(feature)

            elif geo_type in ("Polygon", "MultiPolygon"):
                # Check if any coordinate falls within bbox
                flat_coords = _flatten_coordinates(coords)
                for lon, lat in flat_coords:
                    if west <= lon <= east and south <= lat <= north:
                        filtered_features.append(feature)
                        break

            else:
                # For lines and other types, include by default
                filtered_features.append(feature)

        return {
            "type": "FeatureCollection",
            "features": filtered_features,
        }

    @staticmethod
    def _error_result(source_id: str, error: str) -> dict:
        return {
            "available": False,
            "data": None,
            "format": None,
            "record_count": 0,
            "source_id": source_id,
            "attribution": "",
            "metadata": {},
            "error": error,
        }

    @staticmethod
    def _empty_result(source_id: str, message: str) -> dict:
        return {
            "available": True,
            "data": {"type": "FeatureCollection", "features": []},
            "format": "geojson",
            "record_count": 0,
            "source_id": source_id,
            "attribution": "",
            "metadata": {"note": message},
            "error": None,
        }


def _flatten_coordinates(coords, depth=0) -> list[tuple[float, float]]:
    """Recursively flatten GeoJSON coordinate arrays to (lon, lat) pairs."""
    if depth > 5:
        return []
    if not coords:
        return []
    if isinstance(coords[0], (int, float)):
        return [(coords[0], coords[1])]
    result = []
    for item in coords:
        result.extend(_flatten_coordinates(item, depth + 1))
    return result


# ═══════════════════════════════════════════════════════════════════════
# DATA VALIDATOR
# ═══════════════════════════════════════════════════════════════════════

class DataValidator:
    """
    Validates fetched data for quality and completeness.

    Checks:
    - Record count (not empty)
    - Null/missing values
    - Geometry validity
    - Outlier detection (IQR method)
    - Bbox coverage
    """

    def validate(
        self,
        fetch_result: dict,
        requested_bbox: tuple[float, float, float, float] | None = None,
    ) -> DataQualityReport:
        """
        Validate a fetch result and return a quality report.
        """
        source_id = fetch_result.get("source_id", "unknown")

        if not fetch_result.get("available"):
            return DataQualityReport(
                source_id=source_id,
                passed=False,
                record_count=0,
                null_count=0,
                null_percentage=0,
                has_geometry=False,
                geometry_type=None,
                crs=None,
                bbox_coverage=0,
                outlier_count=0,
                issues=[fetch_result.get("error", "Data not available")],
            )

        data = fetch_result.get("data")
        fmt = fetch_result.get("format", "dict")

        if fmt == "geojson":
            return self._validate_geojson(source_id, data, requested_bbox)
        elif fmt == "dict":
            return self._validate_dict(source_id, data)
        elif fmt == "image_url":
            return self._validate_image_url(source_id, data)
        else:
            return DataQualityReport(
                source_id=source_id,
                passed=True,
                record_count=fetch_result.get("record_count", 0),
                null_count=0,
                null_percentage=0,
                has_geometry=False,
                geometry_type=None,
                crs="EPSG:4326",
                bbox_coverage=1.0,
                outlier_count=0,
                issues=[],
            )

    def _validate_geojson(
        self, source_id: str, geojson: dict,
        bbox: tuple | None = None,
    ) -> DataQualityReport:
        """Validate GeoJSON data."""
        issues = []
        features = geojson.get("features", [])
        record_count = len(features)

        if record_count == 0:
            return DataQualityReport(
                source_id=source_id,
                passed=True,  # Empty is valid (no data in area)
                record_count=0,
                null_count=0,
                null_percentage=0,
                has_geometry=True,
                geometry_type=None,
                crs="EPSG:4326",
                bbox_coverage=0,
                outlier_count=0,
                issues=["No features in result (area may have no data)"],
            )

        # Check for null geometries
        null_count = sum(
            1 for f in features
            if not f.get("geometry") or not f["geometry"].get("coordinates")
        )
        null_pct = (null_count / record_count * 100) if record_count > 0 else 0

        if null_pct > 10:
            issues.append(f"{null_pct:.0f}% of features have null geometry")

        # Detect geometry type
        geo_types = set()
        for f in features:
            geo = f.get("geometry", {})
            if geo.get("type"):
                geo_types.add(geo["type"])
        geo_type = ", ".join(sorted(geo_types)) if geo_types else None

        # Bbox coverage
        coverage = 1.0
        if bbox and features:
            data_bbox = self._compute_geojson_bbox(features)
            if data_bbox:
                coverage = self._bbox_overlap_ratio(bbox, data_bbox)

        # Outlier check on numeric properties
        outlier_count = 0
        numeric_props = self._extract_numeric_properties(features)
        for prop_name, values in numeric_props.items():
            outliers = self._iqr_outliers(values)
            if outliers > 0:
                outlier_count += outliers

        passed = null_pct <= 20 and record_count > 0

        return DataQualityReport(
            source_id=source_id,
            passed=passed,
            record_count=record_count,
            null_count=null_count,
            null_percentage=null_pct,
            has_geometry=True,
            geometry_type=geo_type,
            crs="EPSG:4326",
            bbox_coverage=coverage,
            outlier_count=outlier_count,
            issues=issues,
        )

    def _validate_dict(self, source_id: str, data: dict) -> DataQualityReport:
        """Validate dictionary data (most EcoLens services)."""
        issues = []

        if not data:
            return DataQualityReport(
                source_id=source_id,
                passed=False,
                record_count=0,
                null_count=0,
                null_percentage=0,
                has_geometry=False,
                geometry_type=None,
                crs=None,
                bbox_coverage=0,
                outlier_count=0,
                issues=["Empty data dictionary"],
            )

        # Check for error indicators
        if data.get("error") or data.get("available") is False:
            issues.append(f"Data source reported error: {data.get('error', 'unknown')}")

        return DataQualityReport(
            source_id=source_id,
            passed=len(issues) == 0,
            record_count=1,
            null_count=0,
            null_percentage=0,
            has_geometry=False,
            geometry_type=None,
            crs="EPSG:4326",
            bbox_coverage=1.0,
            outlier_count=0,
            issues=issues,
        )

    def _validate_image_url(self, source_id: str, data: dict) -> DataQualityReport:
        """Validate image URL data (Sentinel imagery)."""
        issues = []

        # Check if URLs are present
        has_urls = any(
            isinstance(v, str) and v.startswith("http")
            for v in (data.values() if isinstance(data, dict) else [])
        )

        if not has_urls and isinstance(data, dict):
            # Check nested dicts
            for v in data.values():
                if isinstance(v, dict):
                    has_urls = any(
                        isinstance(sv, str) and sv.startswith("http")
                        for sv in v.values()
                    )
                    if has_urls:
                        break

        if not has_urls:
            issues.append("No image URLs found in result")

        return DataQualityReport(
            source_id=source_id,
            passed=len(issues) == 0,
            record_count=1,
            null_count=0,
            null_percentage=0,
            has_geometry=False,
            geometry_type=None,
            crs=None,
            bbox_coverage=1.0,
            outlier_count=0,
            issues=issues,
        )

    @staticmethod
    def _compute_geojson_bbox(
        features: list[dict],
    ) -> tuple[float, float, float, float] | None:
        """Compute bounding box of GeoJSON features."""
        min_lon = float("inf")
        min_lat = float("inf")
        max_lon = float("-inf")
        max_lat = float("-inf")

        for f in features:
            coords = _flatten_coordinates(
                f.get("geometry", {}).get("coordinates", [])
            )
            for lon, lat in coords:
                min_lon = min(min_lon, lon)
                min_lat = min(min_lat, lat)
                max_lon = max(max_lon, lon)
                max_lat = max(max_lat, lat)

        if min_lon == float("inf"):
            return None
        return (min_lon, min_lat, max_lon, max_lat)

    @staticmethod
    def _bbox_overlap_ratio(
        requested: tuple[float, float, float, float],
        actual: tuple[float, float, float, float],
    ) -> float:
        """Compute what fraction of the requested bbox is covered by actual data."""
        # Intersection
        inter_west = max(requested[0], actual[0])
        inter_south = max(requested[1], actual[1])
        inter_east = min(requested[2], actual[2])
        inter_north = min(requested[3], actual[3])

        if inter_west >= inter_east or inter_south >= inter_north:
            return 0.0

        inter_area = (inter_east - inter_west) * (inter_north - inter_south)
        req_area = (requested[2] - requested[0]) * (requested[3] - requested[1])

        if req_area <= 0:
            return 0.0
        return min(1.0, inter_area / req_area)

    @staticmethod
    def _extract_numeric_properties(features: list[dict]) -> dict[str, list[float]]:
        """Extract numeric property values from GeoJSON features."""
        props: dict[str, list[float]] = {}
        for f in features:
            for key, val in f.get("properties", {}).items():
                if isinstance(val, (int, float)) and not isinstance(val, bool):
                    if key not in props:
                        props[key] = []
                    props[key].append(float(val))
        return props

    @staticmethod
    def _iqr_outliers(values: list[float]) -> int:
        """Count outliers using the IQR method."""
        if len(values) < 4:
            return 0
        sorted_vals = sorted(values)
        n = len(sorted_vals)
        q1 = sorted_vals[n // 4]
        q3 = sorted_vals[3 * n // 4]
        iqr = q3 - q1
        lower = q1 - 1.5 * iqr
        upper = q3 + 1.5 * iqr
        return sum(1 for v in sorted_vals if v < lower or v > upper)


# ═══════════════════════════════════════════════════════════════════════
# DATA CACHE
# ═══════════════════════════════════════════════════════════════════════

class DataCache:
    """
    In-memory + file cache for fetched data.

    TTL-based: static data cached for 24h, real-time data for 5min.
    File cache in /tmp/ecolens_cartographic_cache/ for cross-invocation
    reuse (Cloud Functions warm instances).
    """

    DEFAULT_TTL = {
        UpdateFrequency.STATIC: 86400,      # 24 hours
        UpdateFrequency.ANNUAL: 86400,       # 24 hours
        UpdateFrequency.MONTHLY: 3600,       # 1 hour
        UpdateFrequency.WEEKLY: 1800,        # 30 min
        UpdateFrequency.DAILY: 600,          # 10 min
        UpdateFrequency.REALTIME: 300,       # 5 min
    }

    def __init__(self, cache_dir: str | None = None):
        self._memory: dict[str, tuple[float, dict]] = {}  # key -> (expiry, data)
        self._cache_dir = Path(cache_dir or "/tmp/ecolens_cartographic_cache")

    def get(self, key: str) -> dict | None:
        """Get cached data if not expired."""
        # Check memory first
        if key in self._memory:
            expiry, data = self._memory[key]
            if time.time() < expiry:
                return data
            else:
                del self._memory[key]

        # Check file cache
        file_path = self._cache_dir / f"{key}.json"
        if file_path.exists():
            try:
                with open(file_path, "r") as f:
                    cached = json.load(f)
                if time.time() < cached.get("expiry", 0):
                    data = cached["data"]
                    # Promote to memory
                    self._memory[key] = (cached["expiry"], data)
                    return data
                else:
                    file_path.unlink(missing_ok=True)
            except (json.JSONDecodeError, KeyError):
                file_path.unlink(missing_ok=True)

        return None

    def set(
        self,
        key: str,
        data: dict,
        frequency: UpdateFrequency = UpdateFrequency.DAILY,
    ):
        """Cache data with TTL based on update frequency."""
        ttl = self.DEFAULT_TTL.get(frequency, 600)
        expiry = time.time() + ttl

        # Memory cache
        self._memory[key] = (expiry, data)

        # File cache (for static/slow-changing data only)
        if frequency in (UpdateFrequency.STATIC, UpdateFrequency.ANNUAL,
                        UpdateFrequency.MONTHLY):
            try:
                self._cache_dir.mkdir(parents=True, exist_ok=True)
                file_path = self._cache_dir / f"{key}.json"
                with open(file_path, "w") as f:
                    json.dump({"expiry": expiry, "data": data}, f)
            except (OSError, TypeError) as e:
                logger.warning(f"File cache write failed for {key}: {e}")

    @staticmethod
    def make_key(
        source_id: str,
        bbox: tuple | None = None,
        center: tuple | None = None,
        date_range: tuple | None = None,
    ) -> str:
        """Generate a deterministic cache key."""
        parts = [source_id]
        if bbox:
            parts.append(f"bbox_{bbox[0]:.2f}_{bbox[1]:.2f}_{bbox[2]:.2f}_{bbox[3]:.2f}")
        if center:
            parts.append(f"center_{center[0]:.4f}_{center[1]:.4f}")
        if date_range:
            parts.append(f"dates_{date_range[0]}_{date_range[1]}")
        raw = "|".join(parts)
        return hashlib.md5(raw.encode()).hexdigest()


# ═══════════════════════════════════════════════════════════════════════
# DATA PIPELINE — THE ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════

class DataPipeline:
    """
    Orchestrates the full data sourcing pipeline:
      1. Discover relevant sources for the map request
      2. Fetch data from each source (with caching)
      3. Validate data quality
      4. Return curated, validated data + quality reports + attributions

    Usage:
        pipeline = DataPipeline()

        # Discover what's available for Amazon deforestation map
        sources = pipeline.discover(
            bbox=(-73.0, -16.5, -44.0, 5.3),
            theme="deforestation",
        )

        # Fetch all discovered data
        results = pipeline.fetch_all(
            sources=sources,
            bbox=(-73.0, -16.5, -44.0, 5.3),
        )

        # Or use the one-shot method
        bundle = pipeline.prepare_map_data(
            bbox=(-73.0, -16.5, -44.0, 5.3),
            theme="deforestation",
            layer_ids=["global_forest_watch", "natural_earth_admin"],
        )
    """

    def __init__(self):
        self.registry = DataSourceRegistry()
        self.fetcher = DataFetcher()
        self.validator = DataValidator()
        self.cache = DataCache()

    def discover(
        self,
        bbox: tuple[float, float, float, float] | None = None,
        theme: str | None = None,
        categories: list[SourceCategory] | None = None,
    ) -> list[DataSource]:
        """
        Discover available data sources for the map parameters.
        """
        return self.registry.discover(
            bbox=bbox, theme=theme, categories=categories,
        )

    def fetch_source(
        self,
        source: DataSource,
        bbox: tuple[float, float, float, float] | None = None,
        center: tuple[float, float] | None = None,
        date_range: tuple[str, str] | None = None,
        use_cache: bool = True,
        **kwargs,
    ) -> dict:
        """
        Fetch a single data source with caching and validation.

        Returns the fetch result dict augmented with quality_report.
        """
        # Check cache
        if use_cache:
            cache_key = self.cache.make_key(source.id, bbox, center, date_range)
            cached = self.cache.get(cache_key)
            if cached is not None:
                cached["_from_cache"] = True
                return cached

        # Fetch
        result = self.fetcher.fetch(
            source=source, bbox=bbox, center=center,
            date_range=date_range, **kwargs,
        )

        # Validate
        quality = self.validator.validate(result, requested_bbox=bbox)
        result["quality_report"] = quality.to_dict()

        # Cache if successful
        if use_cache and result.get("available"):
            cache_key = self.cache.make_key(source.id, bbox, center, date_range)
            self.cache.set(cache_key, result, source.update_frequency)

        result["_from_cache"] = False
        return result

    def fetch_all(
        self,
        sources: list[DataSource],
        bbox: tuple[float, float, float, float] | None = None,
        center: tuple[float, float] | None = None,
        date_range: tuple[str, str] | None = None,
        use_cache: bool = True,
    ) -> dict[str, dict]:
        """
        Fetch all specified data sources.

        Returns dict keyed by source_id -> fetch result.
        """
        results = {}
        for source in sources:
            results[source.id] = self.fetch_source(
                source=source, bbox=bbox, center=center,
                date_range=date_range, use_cache=use_cache,
            )
        return results

    def prepare_map_data(
        self,
        bbox: tuple[float, float, float, float],
        theme: str | None = None,
        layer_ids: list[str] | None = None,
        date_range: tuple[str, str] | None = None,
    ) -> dict:
        """
        One-shot method: discover + fetch + validate + bundle.

        This is the main entry point for the composition engine.

        Args:
            bbox: Map extent
            theme: EcoLens theme for auto-discovery
            layer_ids: Explicit layer IDs (overrides auto-discovery)
            date_range: Temporal scope

        Returns:
            {
                "layers": {source_id: fetch_result, ...},
                "attributions": [str, ...],
                "quality_summary": {
                    "total_sources": int,
                    "successful": int,
                    "failed": int,
                    "from_cache": int,
                    "reports": {source_id: quality_report, ...},
                },
                "available_sources": [source_id, ...],
            }
        """
        center = ((bbox[1] + bbox[3]) / 2, (bbox[0] + bbox[2]) / 2)

        # Determine which sources to fetch
        if layer_ids:
            sources = [
                self.registry.get_source(sid)
                for sid in layer_ids
                if self.registry.get_source(sid)
            ]
        else:
            sources = self.discover(bbox=bbox, theme=theme)

        # Always include basemap if not explicitly excluded
        has_basemap = any(s.category == SourceCategory.BASEMAP for s in sources)
        if not has_basemap:
            admin = self.registry.get_source("natural_earth_admin")
            if admin:
                sources.insert(0, admin)

        # Fetch all
        results = self.fetch_all(
            sources=sources, bbox=bbox, center=center,
            date_range=date_range,
        )

        # Compile summary
        successful = sum(1 for r in results.values() if r.get("available"))
        failed = sum(1 for r in results.values() if not r.get("available"))
        from_cache = sum(1 for r in results.values() if r.get("_from_cache"))

        attributions = []
        for r in results.values():
            attr = r.get("attribution", "")
            if attr and attr not in attributions:
                attributions.append(attr)

        quality_reports = {
            sid: r.get("quality_report", {})
            for sid, r in results.items()
        }

        return {
            "layers": results,
            "attributions": attributions,
            "quality_summary": {
                "total_sources": len(sources),
                "successful": successful,
                "failed": failed,
                "from_cache": from_cache,
                "reports": quality_reports,
            },
            "available_sources": [
                sid for sid, r in results.items() if r.get("available")
            ],
        }

    def get_layer_catalog(
        self,
        bbox: tuple[float, float, float, float] | None = None,
        theme: str | None = None,
    ) -> list[dict]:
        """
        Return the catalog of available layers for the Flutter UI.

        Each entry includes source metadata and whether it's available
        for the given extent.
        """
        all_sources = self.registry.list_all()
        available = self.discover(bbox=bbox, theme=theme)
        available_ids = {s.id for s in available}

        for source_dict in all_sources:
            source_dict["available_for_extent"] = source_dict["id"] in available_ids

        return all_sources
