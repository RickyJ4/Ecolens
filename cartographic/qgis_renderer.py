"""
QGIS Cartographic Renderer — Production Quality

Renders maps using PyQGIS with:
  - Raster DEM elevation basemap with hypsometric tinting (blue→green→yellow→red)
  - Hillshade underlay for terrain depth
  - Vector overlays (points, polygons, lines) with graduated symbology
  - PAL label engine for collision-free labeling
  - QgsLayout print composition with legend, scale bar, north arrow
  - High-DPI export (300 DPI for print, 200 for screen)

Reference quality targets:
  - Morocco Fire Map: elevation raster + fire points + city labels
  - Tsunami Risk Map: classified polygons over topo basemap + legend
  - Jinan Heritage Map: elevation raster + graduated points + rivers
"""

from __future__ import annotations

import io
import json
import logging
import math
import os
import tempfile
from pathlib import Path
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

_QGIS_AVAILABLE = False
_qgis_app = None


def _init_qgis():
    global _QGIS_AVAILABLE, _qgis_app
    if _qgis_app is not None:
        return True
    try:
        from qgis.core import QgsApplication
        _qgis_app = QgsApplication([], False)
        _qgis_app.setPrefixPath(os.environ.get("QGIS_PREFIX_PATH", "/usr"), True)
        _qgis_app.initQgis()
        _QGIS_AVAILABLE = True
        logger.info("QGIS initialized")
        return True
    except Exception as e:
        logger.info(f"QGIS not available: {e}")
        _QGIS_AVAILABLE = False
        return False


def is_qgis_available() -> bool:
    return _init_qgis()


# ═══════════════════════════════════════════════════════════════════════
# DEM / RASTER UTILITIES
# ═══════════════════════════════════════════════════════════════════════

def fetch_dem(bbox: tuple[float, float, float, float], output_path: str | None = None) -> str | None:
    """
    Fetch SRTM 30m DEM as a GeoTIFF for a bounding box.
    Downloads individual 1-degree tiles from AWS public SRTM archive,
    merges and warps to the requested extent.

    Returns path to the GeoTIFF file, or None on failure.
    """
    import gzip
    import requests
    from osgeo import gdal

    w, s, e, n = bbox

    # Clamp to reasonable size
    if (e - w) > 10 or (n - s) > 10:
        logger.warning(f"DEM bbox too large ({e-w:.0f}x{n-s:.0f} deg), skipping")
        return None

    # Determine which SRTM tiles we need
    tile_paths = []
    for lat in range(int(math.floor(s)), int(math.ceil(n))):
        for lon in range(int(math.floor(w)), int(math.ceil(e))):
            lat_str = f"N{lat:02d}" if lat >= 0 else f"S{abs(lat):02d}"
            lon_str = f"E{lon:03d}" if lon >= 0 else f"W{abs(lon):03d}"
            tile_name = f"{lat_str}{lon_str}"

            url = f"https://elevation-tiles-prod.s3.amazonaws.com/skadi/{lat_str}/{tile_name}.hgt.gz"
            hgt_path = f"/tmp/{tile_name}.hgt"

            if os.path.exists(hgt_path):
                tile_paths.append(hgt_path)
                continue

            try:
                resp = requests.get(url, timeout=30)
                if resp.status_code == 200 and len(resp.content) > 1000:
                    with open(hgt_path, "wb") as f:
                        f.write(gzip.decompress(resp.content))
                    tile_paths.append(hgt_path)
                    logger.info(f"Downloaded SRTM tile: {tile_name}")
            except Exception as ex:
                logger.warning(f"SRTM tile {tile_name} failed: {ex}")

    if not tile_paths:
        logger.warning("No SRTM tiles downloaded")
        return None

    # Merge and warp tiles to bbox as GeoTIFF
    if output_path is None:
        output_path = tempfile.mktemp(suffix=".tif")

    # Calculate resolution based on bbox size
    span = max(e - w, n - s)
    res_pixels = 1000 if span < 3 else 800 if span < 5 else 600

    try:
        result = gdal.Warp(
            output_path, tile_paths,
            outputBounds=[w, s, e, n],
            width=res_pixels,
            height=int(res_pixels * (n - s) / (e - w)),
            resampleAlg="bilinear",
            format="GTiff",
        )
        result = None  # Close dataset

        if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
            logger.info(f"DEM created: {output_path} ({os.path.getsize(output_path):,} bytes)")
            return output_path
    except Exception as ex:
        logger.warning(f"DEM warp failed: {ex}")

    return None


def compute_hillshade(dem_path: str, output_path: str) -> bool:
    """Generate hillshade GeoTIFF from DEM using GDAL (available in QGIS container)."""
    try:
        from osgeo import gdal
        gdal.UseExceptions()
        result = gdal.DEMProcessing(
            output_path, dem_path, "hillshade",
            azimuth=315, altitude=45,
            computeEdges=True,
        )
        result = None  # Close dataset
        return os.path.exists(output_path)
    except Exception as e:
        logger.warning(f"Hillshade generation failed: {e}")
        return False


def get_dem_stats(dem_path: str) -> tuple[float, float]:
    """Get min/max elevation from a DEM file."""
    try:
        from osgeo import gdal
        ds = gdal.Open(dem_path)
        band = ds.GetRasterBand(1)
        stats = band.ComputeStatistics(False)
        ds = None
        return stats[0], stats[1]  # min, max
    except Exception:
        return 0.0, 1000.0


# ═══════════════════════════════════════════════════════════════════════
# QGIS RENDERER
# ═══════════════════════════════════════════════════════════════════════

class QGISRenderer:
    """
    Professional cartographic renderer using PyQGIS with raster basemaps.
    """

    def __init__(self):
        if not is_qgis_available():
            raise RuntimeError("QGIS not available")
        from qgis.core import QgsProject
        self._project = QgsProject.instance()
        self._project.clear()
        self._temp_files: list[str] = []

    def _temp_file(self, suffix: str) -> str:
        tmp = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
        tmp.close()
        self._temp_files.append(tmp.name)
        return tmp.name

    def _cleanup(self):
        for f in self._temp_files:
            try:
                os.unlink(f)
            except OSError:
                pass
        self._temp_files.clear()

    def render(
        self,
        geojson_layers: dict[str, dict],
        bbox: tuple[float, float, float, float],
        title: str | None = None,
        subtitle: str | None = None,
        attributions: list[str] | None = None,
        projection_epsg: int | None = None,
        projection_proj4: str | None = None,
        width_mm: float = 400,
        height_mm: float = 280,
        dpi: int = 300,
        dark_mode: bool = False,
        theme: str | None = None,
        map_type: str = "choropleth",
        palette_name: str = "YlOrRd",
        n_classes: int = 5,
        classification: str = "natural_breaks",
        output_format: str = "png",
        show_legend: bool = True,
        show_scale_bar: bool = True,
        show_north_arrow: bool = False,
        show_grid: bool = True,
        fetch_elevation: bool = True,
        **kwargs,
    ) -> bytes:
        """Full rendering pipeline with raster basemap."""
        from qgis.core import (
            QgsProject, QgsVectorLayer, QgsRasterLayer,
            QgsCoordinateReferenceSystem, QgsRectangle,
            QgsLayout, QgsLayoutExporter, QgsLayoutItemMap,
            QgsLayoutItemLabel, QgsLayoutItemLegend, QgsLayoutItemScaleBar,
            QgsLayoutSize, QgsLayoutPoint, QgsUnitTypes,
            QgsCoordinateTransform,
        )
        from qgis.PyQt.QtGui import QColor, QFont

        project = self._project
        project.clear()

        # ─── CRS ─────────────────────────────────────────────────
        wgs84 = QgsCoordinateReferenceSystem("EPSG:4326")
        if projection_proj4:
            crs = QgsCoordinateReferenceSystem()
            crs.createFromProj4(projection_proj4)
            if not crs.isValid():
                crs = wgs84
        elif projection_epsg:
            crs = QgsCoordinateReferenceSystem(f"EPSG:{projection_epsg}")
        else:
            crs = wgs84
        project.setCrs(crs)

        # Transform bbox
        west, south, east, north = bbox
        source_extent = QgsRectangle(west, south, east, north)
        if crs != wgs84 and crs.isValid():
            transform = QgsCoordinateTransform(wgs84, crs, project)
            projected_extent = transform.transformBoundingBox(source_extent)
        else:
            projected_extent = source_extent

        layers_to_render = []

        # ─── RASTER BASEMAP (elevation + hillshade) ──────────────
        if fetch_elevation:
            dem_path = fetch_dem(bbox)
            if dem_path:
                self._temp_files.append(dem_path)
                min_elev, max_elev = get_dem_stats(dem_path)

                # Hillshade underlay
                hs_path = self._temp_file("_hillshade.tif")
                if compute_hillshade(dem_path, hs_path):
                    hs_layer = QgsRasterLayer(hs_path, "Hillshade", "gdal")
                    if hs_layer.isValid():
                        # Hillshade: very subtle, just gives depth
                        hs_layer.setOpacity(0.20)
                        project.addMapLayer(hs_layer)
                        layers_to_render.append(hs_layer)

                # Elevation: HEAVILY subdued — risk zones are the star
                dem_layer = QgsRasterLayer(dem_path, "Elevation", "gdal")
                if dem_layer.isValid():
                    self._style_elevation_raster(dem_layer, min_elev, max_elev, dark_mode)
                    dem_layer.setOpacity(0.35)  # Very faint — just geographic context
                    project.addMapLayer(dem_layer)
                    layers_to_render.append(dem_layer)

        # ─── RISK SURFACE RASTER (if analysed) ────────────────────
        for layer_name, layer_config in geojson_layers.items():
            geojson_data = layer_config.get("geojson", {})
            raster_path = None
            if isinstance(geojson_data, dict):
                raster_path = geojson_data.get("raster_path")

            if layer_name == "risk_zones" and raster_path:
                import os as _os
                logger.info(f"Loading risk raster: {raster_path} (exists={_os.path.exists(raster_path)})")
                from qgis.core import QgsRasterLayer
                risk_layer = QgsRasterLayer(raster_path, "Seismic Risk", "gdal")
                logger.info(f"Risk raster valid: {risk_layer.isValid()}")
                if risk_layer.isValid():
                    self._style_risk_raster(risk_layer, dark_mode,
                                           geojson_data.get("levels"))
                    risk_layer.setOpacity(0.55)  # Semi-transparent — terrain visible underneath
                    project.addMapLayer(risk_layer)
                    layers_to_render.append(risk_layer)
                    self._temp_files.append(raster_path)

        # ─── VECTOR LAYERS ───────────────────────────────────────
        for layer_name, layer_config in geojson_layers.items():
            geojson = layer_config.get("geojson")
            role = layer_config.get("role", "data")
            value_field = layer_config.get("value_field")

            if not geojson or not isinstance(geojson, dict):
                continue

            # Skip risk_zones if it was handled as raster above
            if layer_name == "risk_zones" and geojson.get("raster_path"):
                continue

            features = geojson.get("features")
            if not features:
                continue

            geojson_path = self._temp_file(".geojson")
            with open(geojson_path, "w") as f:
                json.dump(geojson, f)

            layer = QgsVectorLayer(geojson_path, layer_name, "ogr")
            if not layer.isValid():
                continue

            if role == "basemap":
                self._style_basemap(layer, dark_mode, has_raster=bool(layers_to_render))
            elif layer_name == "risk_zones":
                self._style_risk_zones(layer, dark_mode)
            elif layer_name == "major_events":
                # Impact radius circles — thin stroked rings
                self._style_impact_circles(layer, dark_mode)
            elif layer_name == "affected_cities":
                # City markers with population-scaled sizes
                self._style_city_markers(layer, dark_mode)
            elif layer_name == "raw_points":
                # Original data points — small context dots
                self._style_context_points(layer, dark_mode)
            elif role == "data":
                self._style_data(layer, map_type, value_field,
                               palette_name, n_classes, classification, dark_mode)

            # Labels
            label_field = layer_config.get("label_field")
            if label_field:
                if layer_name == "affected_cities":
                    self._configure_city_labels(layer, label_field, dark_mode)
                elif role == "basemap":
                    self._configure_labels(layer, label_field, dark_mode)

            project.addMapLayer(layer)
            layers_to_render.append(layer)

        if not layers_to_render:
            raise RuntimeError("No valid layers to render")

        # ═══════════════════════════════════════════════════════════
        # LAYOUT — MAP CONTENT ONLY (Pillow handles marginalia)
        # ═══════════════════════════════════════════════════════════
        layout = QgsLayout(project)
        layout.initializeDefaults()

        page = layout.pageCollection().page(0)
        page.setPageSize(QgsLayoutSize(width_mm, height_mm, QgsUnitTypes.LayoutMillimeters))

        # Full-bleed map — no margins, no title space, no legend column
        # Pillow compositor adds all marginalia AFTER this renders
        map_x = 0
        map_y = 0
        map_w = width_mm
        map_h = height_mm

        # ─── MAP FRAME ───────────────────────────────────────────
        map_item = QgsLayoutItemMap(layout)
        map_item.attemptMove(QgsLayoutPoint(map_x, map_y, QgsUnitTypes.LayoutMillimeters))
        map_item.attemptResize(QgsLayoutSize(map_w, map_h, QgsUnitTypes.LayoutMillimeters))
        map_item.setExtent(projected_extent)
        map_item.setCrs(crs)
        map_item.setLayers(list(reversed(layers_to_render)))

        # Ocean background
        ocean = QColor("#0a1220") if dark_mode else QColor("#b8cee0")
        map_item.setBackgroundColor(ocean)
        map_item.setBackgroundEnabled(True)

        # Thin frame
        map_item.setFrameEnabled(True)
        frame_c = QColor("#3a5a7a") if dark_mode else QColor("#888888")
        map_item.setFrameStrokeColor(frame_c)
        try:
            from qgis.core import QgsLayoutMeasurement
            map_item.setFrameStrokeWidth(QgsLayoutMeasurement(0.3, QgsUnitTypes.LayoutMillimeters))
        except ImportError:
            pass

        # Coordinate grid
        if show_grid:
            grid = map_item.grid()
            grid.setEnabled(True)
            gc = QColor(255, 255, 255, 25) if dark_mode else QColor(0, 0, 0, 30)
            from qgis.core import QgsLineSymbol
            grid.setLineSymbol(QgsLineSymbol.createSimple({"color": gc.name(), "width": "0.08"}))
            span = max(east - west, north - south)
            interval = 10 if span > 50 else 5 if span > 20 else 2 if span > 8 else 1 if span > 3 else 0.5
            grid.setIntervalX(interval)
            grid.setIntervalY(interval)
            grid.setAnnotationEnabled(True)
            grid.setAnnotationFont(QFont("Noto Sans", 10))
            grid.setAnnotationFontColor(QColor("#777777") if dark_mode else QColor("#555555"))

        layout.addLayoutItem(map_item)

        # Title, subtitle, legend, scale bar, attribution all handled by Pillow
        # QGIS renders MAP CONTENT ONLY

        # ALL marginalia (title, legend, scale bar, attribution) handled
        # by Pillow compositor — see compose_final_image()

        # ─── EXPORT ──────────────────────────────────────────────
        exporter = QgsLayoutExporter(layout)
        output_path = self._temp_file(f".{output_format}")

        if output_format == "pdf":
            settings = QgsLayoutExporter.PdfExportSettings()
            settings.dpi = dpi
            result = exporter.exportToPdf(output_path, settings)
        elif output_format == "svg":
            settings = QgsLayoutExporter.SvgExportSettings()
            settings.dpi = dpi
            result = exporter.exportToSvg(output_path, settings)
        else:
            settings = QgsLayoutExporter.ImageExportSettings()
            settings.dpi = dpi
            result = exporter.exportToImage(output_path, settings)

        if result != QgsLayoutExporter.Success:
            raise RuntimeError(f"QGIS export failed: {result}")

        with open(output_path, "rb") as f:
            image_bytes = f.read()

        self._cleanup()
        return image_bytes

    # ═══════════════════════════════════════════════════════════════
    # RASTER STYLING
    # ═══════════════════════════════════════════════════════════════

    def _style_elevation_raster(
        self, layer, min_elev: float, max_elev: float, dark_mode: bool
    ):
        """
        Hypsometric tinting with DESATURATED earth tones.

        Key principle: elevation basemap must RECEDE (30-40% visual weight).
        Thematic data (earthquakes, fires) must POP against it.

        Color ramp: muted blues/greens for lowlands → warm tans → muted browns for highlands.
        NOT screaming neon — professional maps use subdued natural tones.
        """
        from qgis.core import (
            QgsSingleBandPseudoColorRenderer,
            QgsRasterShader, QgsColorRampShader,
        )
        from qgis.PyQt.QtGui import QColor

        ramp_range = max_elev - min_elev
        if ramp_range < 1:
            ramp_range = 1000

        # Clamp ocean depths to 0 for land-focused maps
        sea_level = max(min_elev, -50)

        if dark_mode:
            # Dark mode: deep navy → dark green → dark tan → dark brown
            # Very muted so bright data symbols stand out
            items = [
                QgsColorRampShader.ColorRampItem(sea_level, QColor("#0d1b2a"), ""),
                QgsColorRampShader.ColorRampItem(0, QColor("#1b2d3e"), "0m"),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.1, QColor("#1e3a2f"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.25, QColor("#2d4a35"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.40, QColor("#3d5a3a"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.55, QColor("#4a5a3a"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.70, QColor("#5a5535"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.85, QColor("#5a4a30"), ""),
                QgsColorRampShader.ColorRampItem(max_elev, QColor("#4a3a25"), f"{max_elev:.0f}m"),
            ]
        else:
            # Light mode: soft blue (sea) → muted green → tan → warm brown
            # Classic atlas hypsometric tinting — subdued, professional
            items = [
                QgsColorRampShader.ColorRampItem(sea_level, QColor("#c6dae8"), ""),
                QgsColorRampShader.ColorRampItem(0, QColor("#d4e5c8"), "0m"),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.08, QColor("#c8ddb8"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.18, QColor("#bdd5a0"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.30, QColor("#d0d89a"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.45, QColor("#e0d898"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.60, QColor("#dcc58a"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.75, QColor("#c8a878"), ""),
                QgsColorRampShader.ColorRampItem(ramp_range * 0.90, QColor("#b08a60"), ""),
                QgsColorRampShader.ColorRampItem(max_elev, QColor("#8a6a48"), f"{max_elev:.0f}m"),
            ]

        shader_fn = QgsColorRampShader(min_elev, max_elev)
        shader_fn.setColorRampType(QgsColorRampShader.Interpolated)
        shader_fn.setColorRampItemList(items)

        shader = QgsRasterShader()
        shader.setRasterShaderFunction(shader_fn)

        renderer = QgsSingleBandPseudoColorRenderer(
            layer.dataProvider(), 1, shader,
        )
        layer.setRenderer(renderer)

    # ═══════════════════════════════════════════════════════════════
    # VECTOR STYLING
    # ═══════════════════════════════════════════════════════════════

    def _style_basemap(self, layer, dark_mode: bool, has_raster: bool = False):
        """
        Basemap boundaries — thin, subtle, don't compete with data.
        If we have a raster basemap, make polygons transparent with just borders.
        """
        from qgis.core import QgsSingleSymbolRenderer, QgsFillSymbol
        from qgis.PyQt.QtGui import QColor

        if has_raster:
            # Transparent fill, thin subtle borders — don't compete with data
            border_color = "255,255,255,60" if dark_mode else "100,100,100,80"
            symbol = QgsFillSymbol.createSimple({
                "color": "0,0,0,0",
                "outline_color": border_color,
                "outline_width": "0.15",
                "outline_style": "solid",
            })
        else:
            # No raster — use a muted fill
            fill = "#1c2632" if dark_mode else "#f2ede4"
            stroke = "#2d3d50" if dark_mode else "#c8bfb0"
            symbol = QgsFillSymbol.createSimple({
                "color": fill,
                "outline_color": stroke,
                "outline_width": "0.2",
            })

        renderer = QgsSingleSymbolRenderer(symbol)
        layer.setRenderer(renderer)

    def _style_risk_raster(self, layer, dark_mode: bool, levels=None):
        """
        Style the risk surface raster with a smooth continuous color ramp.
        This produces natural-looking risk gradients — NO jagged edges.
        """
        from qgis.core import (
            QgsSingleBandPseudoColorRenderer,
            QgsRasterShader, QgsColorRampShader,
        )
        from qgis.PyQt.QtGui import QColor

        # Smooth gradient: transparent (0) → blue → yellow → orange → red → dark red (1)
        items = [
            QgsColorRampShader.ColorRampItem(0.00, QColor(0, 0, 0, 0), ""),      # Transparent
            QgsColorRampShader.ColorRampItem(0.05, QColor(0, 0, 0, 0), ""),      # Still transparent
            QgsColorRampShader.ColorRampItem(0.08, QColor("#4393c3"), "Very Low"),
            QgsColorRampShader.ColorRampItem(0.15, QColor("#74add1"), "Low"),
            QgsColorRampShader.ColorRampItem(0.25, QColor("#fee08b"), "Moderate"),
            QgsColorRampShader.ColorRampItem(0.40, QColor("#fdae61"), ""),
            QgsColorRampShader.ColorRampItem(0.55, QColor("#f46d43"), "High"),
            QgsColorRampShader.ColorRampItem(0.75, QColor("#d73027"), "Very High"),
            QgsColorRampShader.ColorRampItem(0.90, QColor("#a50026"), "Critical"),
            QgsColorRampShader.ColorRampItem(1.00, QColor("#67001f"), ""),
        ]

        shader_fn = QgsColorRampShader(0, 1)
        shader_fn.setColorRampType(QgsColorRampShader.Interpolated)
        shader_fn.setColorRampItemList(items)

        shader = QgsRasterShader()
        shader.setRasterShaderFunction(shader_fn)

        renderer = QgsSingleBandPseudoColorRenderer(
            layer.dataProvider(), 1, shader,
        )
        layer.setRenderer(renderer)

    def _style_risk_zones(self, layer, dark_mode: bool):
        """
        Style risk zone polygons using categorized renderer.
        Each feature has a pre-assigned color from the map_analyst.
        This is THE story layer — classified risk zones with transparency.
        """
        from qgis.core import (
            QgsCategorizedSymbolRenderer, QgsRendererCategory, QgsFillSymbol,
        )
        from qgis.PyQt.QtGui import QColor

        categories = []
        risk_styles = {
            "Very Low":  ("#4393c3", 0.45),
            "Low":       ("#92c5de", 0.55),
            "Moderate":  ("#fee08b", 0.65),
            "High":      ("#f46d43", 0.72),
            "Very High": ("#d73027", 0.78),
            "Critical":  ("#a50026", 0.85),
        }

        for level_name, (color, opacity) in risk_styles.items():
            symbol = QgsFillSymbol.createSimple({
                "color": color,
                "outline_color": "0,0,0,0",
                "outline_width": "0",
                "outline_style": "no",
            })
            symbol.setOpacity(opacity)
            cat = QgsRendererCategory(level_name, symbol, level_name)
            categories.append(cat)

        renderer = QgsCategorizedSymbolRenderer("risk_level", categories)
        layer.setRenderer(renderer)

    def _style_impact_circles(self, layer, dark_mode: bool):
        """Major event impact radii — clean rings showing blast/shake zone."""
        from qgis.core import QgsSingleSymbolRenderer, QgsFillSymbol
        from qgis.PyQt.QtGui import QColor

        ring_color = "#ff4444" if dark_mode else "#cc0000"
        symbol = QgsFillSymbol.createSimple({
            "color": "0,0,0,0",  # No fill — ring only
            "outline_color": ring_color,
            "outline_width": "0.6",
            "outline_style": "dot",
        })
        symbol.setOpacity(0.55)
        layer.setRenderer(QgsSingleSymbolRenderer(symbol))

    def _style_city_markers(self, layer, dark_mode: bool):
        """City markers — solid diamonds, visible against any background."""
        from qgis.core import (
            QgsSingleSymbolRenderer, QgsMarkerSymbol, QgsSimpleMarkerSymbolLayer,
        )
        from qgis.PyQt.QtGui import QColor

        symbol = QgsMarkerSymbol()
        ml = QgsSimpleMarkerSymbolLayer()
        ml.setShape(QgsSimpleMarkerSymbolLayer.Diamond)
        ml.setColor(QColor("#ffffff"))
        ml.setStrokeColor(QColor("#000000"))
        ml.setStrokeWidth(0.5)
        ml.setSize(6.0)
        symbol.changeSymbolLayer(0, ml)
        symbol.setOpacity(0.95)

        layer.setRenderer(QgsSingleSymbolRenderer(symbol))

    def _style_context_points(self, layer, dark_mode: bool):
        """Raw data points: tiny white dots. Context only, NOT the story."""
        from qgis.core import (
            QgsSingleSymbolRenderer, QgsMarkerSymbol, QgsSimpleMarkerSymbolLayer,
        )
        from qgis.PyQt.QtGui import QColor

        symbol = QgsMarkerSymbol()
        ml = QgsSimpleMarkerSymbolLayer()
        ml.setShape(QgsSimpleMarkerSymbolLayer.Circle)
        ml.setColor(QColor("#ffffff"))
        ml.setStrokeColor(QColor(0, 0, 0, 80))
        ml.setStrokeWidth(0.1)
        ml.setSize(1.0)  # Tiny — just shows data density
        symbol.changeSymbolLayer(0, ml)
        symbol.setOpacity(0.35)

        layer.setRenderer(QgsSingleSymbolRenderer(symbol))

    def _configure_city_labels(self, layer, label_field: str, dark_mode: bool):
        """
        City labels: name on first line, population on second.
        Bold, readable, proper halo. These tell the user WHO is at risk.
        """
        from qgis.core import (
            QgsPalLayerSettings, QgsVectorLayerSimpleLabeling,
            QgsTextFormat, QgsTextBufferSettings,
        )
        from qgis.PyQt.QtGui import QColor, QFont

        settings = QgsPalLayerSettings()
        # Show name + population (use expression for multi-line label)
        settings.isExpression = True
        settings.fieldName = (
            "concat(\"name\", '\\n', "
            "format_number(\"population\", 0))"
        )
        settings.enabled = True

        fmt = QgsTextFormat()
        font = QFont("Noto Sans", 22)
        font.setBold(True)
        fmt.setFont(font)
        fmt.setSize(22)
        fmt.setColor(QColor("#ffffff") if dark_mode else QColor("#111111"))

        # Very thick halo — must be readable over any risk zone color
        buf = QgsTextBufferSettings()
        buf.setEnabled(True)
        buf.setSize(3.5)
        halo = QColor("#000000") if dark_mode else QColor("#ffffff")
        halo.setAlpha(230)
        buf.setColor(halo)
        fmt.setBuffer(buf)

        settings.setFormat(fmt)
        settings.placement = QgsPalLayerSettings.OrderedPositionsAroundPoint
        settings.priority = 10

        layer.setLabeling(QgsVectorLayerSimpleLabeling(settings))
        layer.setLabelsEnabled(True)

    def _style_data(self, layer, map_type, value_field, palette_name,
                    n_classes, classification, dark_mode):
        """Route to appropriate data styler."""
        geom_type = layer.geometryType()

        if geom_type == 0:  # Points
            self._style_graduated_points(
                layer, value_field, palette_name, n_classes, classification, dark_mode,
            )
        elif geom_type == 2:  # Polygons
            if value_field:
                self._style_graduated_polygons(
                    layer, value_field, palette_name, n_classes, classification, dark_mode,
                )

    def _style_graduated_points(self, layer, value_field, palette_name,
                                 n_classes, classification, dark_mode):
        """
        Graduated symbols following professional cartographic standards:

        - USGS ShakeMap color progression for earthquakes
        - Exponential size scaling: radius = 2 * (1.5 ^ value)
        - Semi-transparent fills (0.65-0.80) with solid dark strokes
        - Size range 3mm to 18mm (visible but not overwhelming)
        - Smallest symbols on top (QGIS handles this with graduated renderer)
        """
        from qgis.core import (
            QgsGraduatedSymbolRenderer, QgsMarkerSymbol,
            QgsSimpleMarkerSymbolLayer, QgsRendererRange,
            QgsClassificationJenks, QgsClassificationQuantile,
            QgsClassificationEqualInterval,
        )
        from qgis.PyQt.QtGui import QColor

        # USGS ShakeMap-inspired progression: green → yellow → orange → red → dark red
        # These are the international standard for seismic hazard visualization
        usgs_colors = [
            "#7AFF93",  # Light green (low)
            "#FFFF00",  # Yellow
            "#FFC800",  # Orange-yellow
            "#FF9100",  # Orange
            "#FF0000",  # Red
            "#C80000",  # Dark red (high)
        ]

        # Use USGS colors for earthquake theme, palette colors for others
        if palette_name in ("YlOrRd", "OrRd") or value_field == "mag":
            colors = usgs_colors[:n_classes]
        else:
            from cartographic.color_systems import ColorSystems
            colors = ColorSystems().get_palette(palette_name, n_classes)

        renderer = QgsGraduatedSymbolRenderer(value_field or "")

        if classification == "quantile":
            renderer.setClassificationMethod(QgsClassificationQuantile())
        elif classification == "equal_interval":
            renderer.setClassificationMethod(QgsClassificationEqualInterval())
        else:
            renderer.setClassificationMethod(QgsClassificationJenks())

        # Graduate by BOTH size and color
        renderer.setGraduatedMethod(QgsGraduatedSymbolRenderer.GraduatedSize)

        # Size range: 3mm (small events) to 18mm (major events)
        renderer.setSymbolSizes(3.0, 18.0)

        # Base symbol: semi-transparent circle with dark stroke
        stroke_color = QColor("#1a1a1a")
        stroke_color.setAlpha(200)

        base = QgsMarkerSymbol()
        ml = QgsSimpleMarkerSymbolLayer()
        ml.setShape(QgsSimpleMarkerSymbolLayer.Circle)
        ml.setColor(QColor(colors[-1]))
        ml.setStrokeColor(stroke_color)
        ml.setStrokeWidth(0.3)
        base.changeSymbolLayer(0, ml)

        renderer.setSourceSymbol(base)
        actual = min(n_classes, max(2, layer.featureCount()))
        renderer.updateClasses(layer, actual)

        # Apply per-class colors and opacity
        for i, rng in enumerate(renderer.ranges()):
            sym = rng.symbol().clone()
            color_idx = min(i, len(colors) - 1)
            sym.setColor(QColor(colors[color_idx]))
            # Lower values more transparent, higher values more opaque
            opacity = 0.60 + (i / max(len(renderer.ranges()) - 1, 1)) * 0.25
            sym.setOpacity(opacity)
            renderer.updateRangeSymbol(i, sym)

        layer.setRenderer(renderer)

    def _style_graduated_polygons(self, layer, value_field, palette_name,
                                   n_classes, classification, dark_mode):
        """Graduated fill for choropleth."""
        from qgis.core import (
            QgsGraduatedSymbolRenderer, QgsFillSymbol,
            QgsClassificationJenks, QgsClassificationQuantile,
            QgsClassificationEqualInterval,
        )
        from qgis.PyQt.QtGui import QColor
        from cartographic.color_systems import ColorSystems

        colors = ColorSystems().get_palette(palette_name, n_classes)
        renderer = QgsGraduatedSymbolRenderer(value_field)

        if classification == "quantile":
            renderer.setClassificationMethod(QgsClassificationQuantile())
        elif classification == "equal_interval":
            renderer.setClassificationMethod(QgsClassificationEqualInterval())
        else:
            renderer.setClassificationMethod(QgsClassificationJenks())

        edge = "#444444" if dark_mode else "#333333"
        base = QgsFillSymbol.createSimple({
            "color": colors[0], "outline_color": edge, "outline_width": "0.2",
        })
        renderer.setSourceSymbol(base)
        renderer.updateClasses(layer, min(n_classes, max(2, layer.featureCount())))

        for i, r in enumerate(renderer.ranges()):
            sym = r.symbol().clone()
            sym.setColor(QColor(colors[min(i, len(colors) - 1)]))
            sym.setOpacity(0.85)
            renderer.updateRangeSymbol(i, sym)

        layer.setRenderer(renderer)

    def _configure_labels(self, layer, label_field, dark_mode):
        """
        PAL labels following professional cartographic standards:
        - Skip point data layers (too many features = clutter)
        - Country/region names: 12pt bold, UPPERCASE, letter-spacing
        - White halo: 1.5px, 60% opacity (not solid white)
        - Placement: prefer above-right (Imhof rules)
        """
        from qgis.core import (
            QgsPalLayerSettings, QgsVectorLayerSimpleLabeling,
            QgsTextFormat, QgsTextBufferSettings,
        )
        from qgis.PyQt.QtGui import QColor, QFont

        # Never label point data layers — too many features
        if layer.geometryType() == 0:
            return

        settings = QgsPalLayerSettings()
        settings.fieldName = label_field
        settings.enabled = True

        fmt = QgsTextFormat()
        font = QFont("Noto Sans", 20)
        font.setWeight(QFont.DemiBold)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1.5)
        fmt.setFont(font)
        fmt.setSize(20)

        # Text color: light on dark, dark on light — must contrast with basemap
        if dark_mode:
            fmt.setColor(QColor(200, 210, 220, 200))  # Slightly transparent
        else:
            fmt.setColor(QColor(60, 60, 60, 210))

        # Halo: 1.5px, semi-transparent — NOT solid white
        buf = QgsTextBufferSettings()
        buf.setEnabled(True)
        buf.setSize(1.5)
        if dark_mode:
            halo = QColor("#0d1520")
            halo.setAlpha(160)  # 63% opacity
        else:
            halo = QColor("#ffffff")
            halo.setAlpha(150)  # 59% opacity
        buf.setColor(halo)
        fmt.setBuffer(buf)

        settings.setFormat(fmt)
        settings.placement = QgsPalLayerSettings.OverPoint
        settings.priority = 6  # Medium priority — don't overwhelm data

        layer.setLabeling(QgsVectorLayerSimpleLabeling(settings))
        layer.setLabelsEnabled(True)


# ═══════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════

def render_with_qgis(geojson_layers, bbox, **kwargs) -> bytes | None:
    """Render using QGIS if available, return None if not."""
    if not is_qgis_available():
        return None
    try:
        renderer = QGISRenderer()
        return renderer.render(geojson_layers=geojson_layers, bbox=bbox, **kwargs)
    except Exception as e:
        logger.warning(f"QGIS rendering failed: {e}")
        import traceback
        traceback.print_exc()
        return None
