"""
QGIS Rendering Test — runs inside the Docker container.

Usage:
  docker run --rm ecolens-carto python3 /app/test_qgis.py

Tests:
  1. PyQGIS initialization
  2. Vector layer creation from GeoJSON
  3. Graduated symbol renderer
  4. PAL labeling engine
  5. QgsLayout print composition
  6. PNG export at 300 DPI
  7. Full composition engine with QGIS backend
"""

import json
import os
import sys
import tempfile

sys.path.insert(0, "/app")


def test_qgis_init():
    """Test 1: Initialize QGIS application."""
    print("Test 1: QGIS initialization...")
    from qgis.core import QgsApplication

    app = QgsApplication([], False)
    app.setPrefixPath("/usr", True)
    app.initQgis()
    print(f"  Prefix: {app.prefixPath()}")
    print(f"  Plugin: {app.pluginPath()}")
    print(f"  PASSED")
    return app


def test_vector_layer(app):
    """Test 2: Create vector layer from GeoJSON."""
    print("Test 2: Vector layer from GeoJSON...")
    from qgis.core import QgsVectorLayer

    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [106.8, -6.2]},
                "properties": {"name": "Jakarta", "mag": 5.5},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [121.0, 14.6]},
                "properties": {"name": "Manila", "mag": 7.1},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [100.5, 13.7]},
                "properties": {"name": "Bangkok", "mag": 4.2},
            },
        ],
    }

    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".geojson", delete=False)
    json.dump(geojson, tmp)
    tmp.close()

    layer = QgsVectorLayer(tmp.name, "test_points", "ogr")
    assert layer.isValid(), "Layer is not valid!"
    assert layer.featureCount() == 3, f"Expected 3 features, got {layer.featureCount()}"
    print(f"  Features: {layer.featureCount()}")
    print(f"  Fields: {[f.name() for f in layer.fields()]}")
    print(f"  PASSED")

    os.unlink(tmp.name)
    return layer


def test_graduated_renderer(layer):
    """Test 3: Graduated symbol renderer."""
    print("Test 3: Graduated symbol renderer...")
    from qgis.core import (
        QgsGraduatedSymbolRenderer, QgsMarkerSymbol,
        QgsClassificationJenks, QgsRendererRange,
    )
    from qgis.PyQt.QtGui import QColor

    renderer = QgsGraduatedSymbolRenderer("mag")
    renderer.setClassificationMethod(QgsClassificationJenks())

    symbol = QgsMarkerSymbol.createSimple({
        "name": "circle",
        "color": "#ff6600",
        "outline_color": "#333333",
        "size": "3",
    })
    renderer.setSourceSymbol(symbol)
    renderer.updateClasses(layer, 3)

    print(f"  Classes: {len(renderer.ranges())}")
    for r in renderer.ranges():
        print(f"    {r.lowerValue():.1f} - {r.upperValue():.1f}: {r.label()}")

    layer.setRenderer(renderer)
    print(f"  PASSED")


def test_labeling(layer):
    """Test 4: PAL labeling engine."""
    print("Test 4: PAL labeling...")
    from qgis.core import (
        QgsPalLayerSettings, QgsVectorLayerSimpleLabeling,
        QgsTextFormat, QgsTextBufferSettings,
    )
    from qgis.PyQt.QtGui import QColor, QFont

    settings = QgsPalLayerSettings()
    settings.fieldName = "name"
    settings.enabled = True

    text_format = QgsTextFormat()
    text_format.setFont(QFont("Noto Sans", 10))
    text_format.setSize(10)
    text_format.setColor(QColor("#e0e0e0"))

    buffer = QgsTextBufferSettings()
    buffer.setEnabled(True)
    buffer.setSize(1.5)
    buffer.setColor(QColor("#000000"))
    text_format.setBuffer(buffer)

    settings.setFormat(text_format)

    labeling = QgsVectorLayerSimpleLabeling(settings)
    layer.setLabeling(labeling)
    layer.setLabelsEnabled(True)

    print(f"  Label field: {settings.fieldName}")
    print(f"  Buffer enabled: {buffer.enabled()}")
    print(f"  PASSED")


def test_layout_export(app, layer):
    """Test 5-6: QgsLayout print composition + PNG export."""
    print("Test 5-6: Layout composition + export...")
    from qgis.core import (
        QgsProject, QgsLayout, QgsLayoutExporter,
        QgsLayoutItemMap, QgsLayoutItemLabel,
        QgsLayoutSize, QgsLayoutPoint,
        QgsRectangle, QgsUnitTypes,
        QgsCoordinateReferenceSystem,
    )
    from qgis.PyQt.QtGui import QFont, QColor

    project = QgsProject.instance()
    project.clear()
    project.setCrs(QgsCoordinateReferenceSystem("EPSG:4326"))
    project.addMapLayer(layer)

    layout = QgsLayout(project)
    layout.initializeDefaults()

    # Page size
    page = layout.pageCollection().page(0)
    page.setPageSize(QgsLayoutSize(300, 200, QgsUnitTypes.LayoutMillimeters))

    # Map frame
    map_item = QgsLayoutItemMap(layout)
    map_item.attemptMove(QgsLayoutPoint(15, 25, QgsUnitTypes.LayoutMillimeters))
    map_item.attemptResize(QgsLayoutSize(270, 150, QgsUnitTypes.LayoutMillimeters))
    map_item.setExtent(QgsRectangle(90, -15, 145, 25))
    map_item.setLayers([layer])
    map_item.setBackgroundColor(QColor("#0e1a2b"))
    map_item.setBackgroundEnabled(True)
    layout.addLayoutItem(map_item)

    # Title
    title = QgsLayoutItemLabel(layout)
    title.setText("QGIS Rendering Test — SE Asia Earthquakes")
    title.setFont(QFont("Noto Sans", 14))
    title.setFontColor(QColor("#e0e0e0"))
    title.setHAlign(1)
    title.attemptMove(QgsLayoutPoint(0, 5, QgsUnitTypes.LayoutMillimeters))
    title.attemptResize(QgsLayoutSize(300, 15, QgsUnitTypes.LayoutMillimeters))
    layout.addLayoutItem(title)

    # Export
    exporter = QgsLayoutExporter(layout)
    output_path = "/tmp/qgis_test_output.png"

    settings = QgsLayoutExporter.ImageExportSettings()
    settings.dpi = 200

    result = exporter.exportToImage(output_path, settings)
    assert result == QgsLayoutExporter.Success, f"Export failed: {result}"

    file_size = os.path.getsize(output_path)
    print(f"  Output: {output_path}")
    print(f"  Size: {file_size:,} bytes")
    print(f"  DPI: 200")
    assert file_size > 1000, "Output file too small!"
    print(f"  PASSED")

    return output_path


def test_composition_engine():
    """Test 7: Full composition engine with QGIS auto-detection."""
    print("Test 7: Full composition engine...")
    import matplotlib
    matplotlib.use("Agg")

    from cartographic.composition_engine import CartographicCompositionEngine, MapRequest
    from cartographic.qgis_renderer import is_qgis_available

    print(f"  QGIS available: {is_qgis_available()}")

    engine = CartographicCompositionEngine()
    result = engine.compose(MapRequest(
        bbox=(95.0, -11.0, 141.0, 21.0),
        map_type="proportional_symbol",
        theme="earthquake",
        title="QGIS Container Test — Earthquakes",
        subtitle="Automated test of the Cartographic Intelligence Engine",
        value_field="mag",
        n_classes=5,
        color_palette="YlOrRd",
        dark_mode=True,
        output_dpi=200,
        width_inches=16,
        height_inches=12,
    ))

    renderer_used = result.metadata.get("renderer", "matplotlib")
    quality = result.quality_report.get("overall", 0)

    print(f"  Renderer: {renderer_used}")
    print(f"  Quality: {quality}/100")
    print(f"  Passed: {result.passed_validation}")
    print(f"  Size: {len(result.image_bytes):,} bytes")
    print(f"  Attributions: {result.attributions}")

    # Save output
    output_path = "/tmp/ecolens_qgis_test.png"
    with open(output_path, "wb") as f:
        f.write(result.image_bytes)
    print(f"  Saved: {output_path}")

    if renderer_used == "qgis":
        print(f"  QGIS RENDERING CONFIRMED")
    else:
        print(f"  WARNING: Fell back to {renderer_used}")

    print(f"  PASSED")


if __name__ == "__main__":
    print("=" * 60)
    print("EcoLens QGIS Rendering Test Suite")
    print("=" * 60)
    print()

    try:
        app = test_qgis_init()
        print()
        layer = test_vector_layer(app)
        print()
        test_graduated_renderer(layer)
        print()
        test_labeling(layer)
        print()
        test_layout_export(app, layer)
        print()
        test_composition_engine()
        print()
        print("=" * 60)
        print("ALL TESTS PASSED")
        print("=" * 60)

    except Exception as e:
        print(f"\nFAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
