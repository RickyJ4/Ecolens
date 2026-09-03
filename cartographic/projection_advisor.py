"""
Projection Advisor

Automatically selects the most appropriate map projection based on:
  - Geographic extent (bbox size and location)
  - Map purpose (thematic, reference, analytical)
  - Data type (area-preserving for choropleth, etc.)

Uses pyproj for CRS construction and validation.

Decision logic based on:
  - Robinson's projection selection guidelines
  - Snyder's "Map Projections: A Working Manual" (USGS PP 1395)
  - ICA recommendations for thematic cartography
"""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class ProjectionRecommendation:
    """A recommended projection with rationale."""
    epsg: int | None              # EPSG code if available, None for custom proj4
    name: str                      # Human-readable name
    proj4: str                     # proj4 string for custom projections
    rationale: str                 # Why this projection was chosen
    properties: list[str]          # ["equal-area", "conformal", "equidistant", etc.]
    distortion_note: str           # What distortions to expect

    def to_dict(self) -> dict:
        return {
            "epsg": self.epsg,
            "name": self.name,
            "proj4": self.proj4,
            "rationale": self.rationale,
            "properties": self.properties,
            "distortion_note": self.distortion_note,
        }


class ProjectionAdvisor:
    """
    Recommends the best map projection for a given extent and purpose.

    Usage:
        advisor = ProjectionAdvisor()
        rec = advisor.recommend(
            bbox=(-73.0, -4.0, -44.0, 5.0),
            purpose="thematic",
            map_type="choropleth",
        )
        print(rec.name, rec.epsg, rec.rationale)
    """

    def recommend(
        self,
        bbox: tuple[float, float, float, float],
        purpose: str = "thematic",
        map_type: str | None = None,
    ) -> ProjectionRecommendation:
        """
        Recommend a projection.

        Args:
            bbox: (west, south, east, north) in WGS84 degrees
            purpose: "thematic", "reference", "analytical", "navigation"
            map_type: Optional map type for type-specific rules

        Returns:
            ProjectionRecommendation with EPSG, name, rationale
        """
        west, south, east, north = bbox
        center_lat = (south + north) / 2.0
        center_lon = (west + east) / 2.0
        width_deg = east - west
        height_deg = north - south

        # Handle antimeridian crossing
        if width_deg < 0:
            width_deg += 360

        extent_category = self._classify_extent(width_deg, height_deg)

        # Choropleth / thematic maps MUST be equal-area (Robinson's rule)
        needs_equal_area = (
            purpose == "thematic" or
            map_type in ("choropleth", "dot_density", "heatmap", "multi_hazard_risk")
        )

        # Navigation maps need conformal
        needs_conformal = purpose == "navigation"

        # Route the decision
        if extent_category == "global":
            return self._global_projection(needs_equal_area, needs_conformal)
        elif extent_category == "continental":
            return self._continental_projection(
                center_lat, center_lon, width_deg, height_deg,
                needs_equal_area, needs_conformal,
            )
        elif extent_category == "regional":
            return self._regional_projection(
                center_lat, center_lon, width_deg, height_deg,
                needs_equal_area, needs_conformal,
            )
        else:  # local
            return self._local_projection(
                center_lat, center_lon, width_deg,
                needs_equal_area, needs_conformal,
            )

    def _classify_extent(self, width_deg: float, height_deg: float) -> str:
        """Classify the geographic extent size."""
        max_dim = max(width_deg, height_deg)
        if max_dim > 150:
            return "global"
        elif max_dim > 50:
            return "continental"
        elif max_dim > 6:
            return "regional"
        else:
            return "local"

    def _global_projection(
        self,
        needs_equal_area: bool,
        needs_conformal: bool,
    ) -> ProjectionRecommendation:
        """Select projection for global-scale maps."""
        if needs_equal_area:
            return ProjectionRecommendation(
                epsg=54009,
                name="Mollweide",
                proj4="+proj=moll +lon_0=0 +datum=WGS84",
                rationale="Equal-area projection ideal for global thematic maps. "
                         "Preserves area for accurate choropleth/density display.",
                properties=["equal-area", "pseudocylindrical"],
                distortion_note="Shape distortion increases toward edges; "
                               "acceptable for thematic data display.",
            )
        elif needs_conformal:
            return ProjectionRecommendation(
                epsg=3857,
                name="Web Mercator",
                proj4="+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0",
                rationale="Conformal projection for navigation. Warning: extreme "
                         "area distortion at high latitudes.",
                properties=["conformal", "cylindrical"],
                distortion_note="Greenland appears as large as Africa. "
                               "Never use for thematic/choropleth maps.",
            )
        else:
            return ProjectionRecommendation(
                epsg=54030,
                name="Robinson",
                proj4="+proj=robin +lon_0=0 +datum=WGS84",
                rationale="Compromise projection — neither equal-area nor conformal "
                         "but minimizes overall distortion. Standard for reference maps.",
                properties=["compromise", "pseudocylindrical"],
                distortion_note="Mild area and shape distortion everywhere; "
                               "no extreme distortion anywhere.",
            )

    def _continental_projection(
        self,
        center_lat: float,
        center_lon: float,
        width_deg: float,
        height_deg: float,
        needs_equal_area: bool,
        needs_conformal: bool,
    ) -> ProjectionRecommendation:
        """Select projection for continental-scale maps."""
        # Polar regions
        if abs(center_lat) > 60:
            if needs_equal_area:
                return ProjectionRecommendation(
                    epsg=None,
                    name="Lambert Azimuthal Equal Area (Polar)",
                    proj4=f"+proj=laea +lat_0={90 if center_lat > 0 else -90} "
                          f"+lon_0={center_lon:.1f} +datum=WGS84",
                    rationale="Equal-area azimuthal centered on pole. Best for "
                             "polar thematic maps.",
                    properties=["equal-area", "azimuthal"],
                    distortion_note="Shape distortion increases toward edges of map.",
                )
            else:
                epsg = 3995 if center_lat > 0 else 3031
                return ProjectionRecommendation(
                    epsg=epsg,
                    name=f"Polar Stereographic ({'North' if center_lat > 0 else 'South'})",
                    proj4=f"+proj=stere +lat_0={90 if center_lat > 0 else -90} "
                          f"+lon_0={center_lon:.1f} +datum=WGS84",
                    rationale="Conformal polar projection. Preserves shapes around the pole.",
                    properties=["conformal", "azimuthal"],
                    distortion_note="Area distortion increases away from the pole.",
                )

        # Mid-latitudes: Albers Equal Area Conic (the workhorse)
        if needs_equal_area:
            std_par_1 = center_lat - height_deg / 6.0
            std_par_2 = center_lat + height_deg / 6.0
            return ProjectionRecommendation(
                epsg=None,
                name="Albers Equal Area Conic",
                proj4=f"+proj=aea +lat_1={std_par_1:.1f} +lat_2={std_par_2:.1f} "
                      f"+lat_0={center_lat:.1f} +lon_0={center_lon:.1f} +datum=WGS84",
                rationale=f"Equal-area conic with standard parallels at "
                         f"{std_par_1:.1f} and {std_par_2:.1f}. "
                         f"Gold standard for continental thematic maps.",
                properties=["equal-area", "conic"],
                distortion_note="Shape distortion minimal between standard parallels; "
                               "increases toward map edges.",
            )

        if needs_conformal:
            std_par_1 = center_lat - height_deg / 6.0
            std_par_2 = center_lat + height_deg / 6.0
            return ProjectionRecommendation(
                epsg=None,
                name="Lambert Conformal Conic",
                proj4=f"+proj=lcc +lat_1={std_par_1:.1f} +lat_2={std_par_2:.1f} "
                      f"+lat_0={center_lat:.1f} +lon_0={center_lon:.1f} +datum=WGS84",
                rationale=f"Conformal conic with standard parallels at "
                         f"{std_par_1:.1f} and {std_par_2:.1f}. "
                         f"Excellent for continental reference maps.",
                properties=["conformal", "conic"],
                distortion_note="Area distortion increases away from standard parallels.",
            )

        # Default: Albers (equal-area is safer default for unknown purpose)
        std_par_1 = center_lat - height_deg / 6.0
        std_par_2 = center_lat + height_deg / 6.0
        return ProjectionRecommendation(
            epsg=None,
            name="Albers Equal Area Conic",
            proj4=f"+proj=aea +lat_1={std_par_1:.1f} +lat_2={std_par_2:.1f} "
                  f"+lat_0={center_lat:.1f} +lon_0={center_lon:.1f} +datum=WGS84",
            rationale="Default equal-area conic for continental extent.",
            properties=["equal-area", "conic"],
            distortion_note="Minimal distortion between standard parallels.",
        )

    def _regional_projection(
        self,
        center_lat: float,
        center_lon: float,
        width_deg: float,
        height_deg: float,
        needs_equal_area: bool,
        needs_conformal: bool,
    ) -> ProjectionRecommendation:
        """Select projection for regional-scale maps (6-50 degrees)."""
        # Equatorial regions: Mercator variants are reasonable
        if abs(center_lat) < 15 and not needs_equal_area:
            return ProjectionRecommendation(
                epsg=None,
                name="Transverse Mercator",
                proj4=f"+proj=tmerc +lat_0={center_lat:.1f} +lon_0={center_lon:.1f} "
                      f"+k=0.9996 +datum=WGS84",
                rationale="Transverse Mercator centered on the region. "
                         "Good for near-equatorial regions with N-S extent.",
                properties=["conformal", "cylindrical"],
                distortion_note="Area distortion increases away from central meridian.",
            )

        if needs_equal_area:
            return ProjectionRecommendation(
                epsg=None,
                name="Lambert Azimuthal Equal Area",
                proj4=f"+proj=laea +lat_0={center_lat:.1f} +lon_0={center_lon:.1f} "
                      f"+datum=WGS84",
                rationale="Equal-area azimuthal centered on the region. "
                         "Ideal for regional thematic maps.",
                properties=["equal-area", "azimuthal"],
                distortion_note="Shape distortion increases toward map edges.",
            )

        # Default for regional: Lambert Conformal Conic
        std_par_1 = center_lat - height_deg / 6.0
        std_par_2 = center_lat + height_deg / 6.0
        return ProjectionRecommendation(
            epsg=None,
            name="Lambert Conformal Conic",
            proj4=f"+proj=lcc +lat_1={std_par_1:.1f} +lat_2={std_par_2:.1f} "
                  f"+lat_0={center_lat:.1f} +lon_0={center_lon:.1f} +datum=WGS84",
            rationale="Conformal conic for regional display. Good shape preservation.",
            properties=["conformal", "conic"],
            distortion_note="Minimal distortion between standard parallels.",
        )

    def _local_projection(
        self,
        center_lat: float,
        center_lon: float,
        width_deg: float,
        needs_equal_area: bool,
        needs_conformal: bool,
    ) -> ProjectionRecommendation:
        """Select projection for local-scale maps (< 6 degrees)."""
        # UTM is the standard for local-scale maps
        utm_zone = self._get_utm_zone(center_lon)
        hemisphere = "north" if center_lat >= 0 else "south"
        epsg = 32600 + utm_zone if center_lat >= 0 else 32700 + utm_zone

        return ProjectionRecommendation(
            epsg=epsg,
            name=f"UTM Zone {utm_zone}{hemisphere[0].upper()}",
            proj4=f"+proj=utm +zone={utm_zone} "
                  f"+{'north' if center_lat >= 0 else 'south'} +datum=WGS84",
            rationale=f"UTM Zone {utm_zone}{hemisphere[0].upper()} — the standard for "
                     f"local-scale maps within a 6-degree longitude band. "
                     f"Conformal with minimal distortion at this scale.",
            properties=["conformal", "transverse-cylindrical"],
            distortion_note="< 0.04% scale distortion within the zone. "
                          "Effectively equal-area at this scale.",
        )

    @staticmethod
    def _get_utm_zone(longitude: float) -> int:
        """Calculate UTM zone number from longitude."""
        return int((longitude + 180) / 6) % 60 + 1

    def is_north_up(self, projection: ProjectionRecommendation) -> bool:
        """
        Determine if a projection is north-up (grid north = true north).

        Most standard projections are north-up. Non-north-up projections
        include oblique aspects and rotated grids.
        """
        proj4 = projection.proj4.lower()

        # Oblique projections are not north-up
        if "+alpha=" in proj4 or "+gamma=" in proj4:
            return False

        # Standard cylindrical, conic, azimuthal at lat_0=90/-90 are north-up
        # Polar stereographic is NOT north-up (there is no "north" at the pole)
        if "+proj=stere" in proj4:
            if "+lat_0=90" in proj4 or "+lat_0=-90" in proj4:
                return False

        return True

    def recommend_for_ecolens_theme(
        self,
        bbox: tuple[float, float, float, float],
        theme: str,
    ) -> ProjectionRecommendation:
        """
        EcoLens-specific projection recommendation.

        Maps environmental data to appropriate projections:
        - Deforestation/biodiversity → equal-area (area accuracy critical)
        - Fire/flood risk → equal-area (risk zones must be accurately sized)
        - Multi-hazard → equal-area
        - Vegetation health → equal-area (NDVI represents surface area)
        """
        # All EcoLens environmental themes need equal-area
        equal_area_themes = {
            "deforestation", "fire_risk", "biodiversity", "flood_risk",
            "multi_hazard", "vegetation_health", "change_detection",
            "population_exposure", "drought",
        }

        purpose = "thematic" if theme in equal_area_themes else "reference"
        map_type = "choropleth"  # Default for EcoLens thematic maps

        return self.recommend(bbox, purpose=purpose, map_type=map_type)
