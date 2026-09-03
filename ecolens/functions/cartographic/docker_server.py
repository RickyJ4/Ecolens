"""
Standalone Flask server for the QGIS Cartographic Engine.
Runs inside the Docker container, exposes map generation via HTTP.

Endpoints:
  POST /generate  — generate a map (accepts same JSON as Cloud Function)
  GET  /health    — health check
  GET  /templates — return catalog of templates, palettes, showcases
"""

import base64
import json
import os
import sys
import traceback

from flask import Flask, request, jsonify

# Ensure cartographic package is importable
sys.path.insert(0, "/app")

app = Flask(__name__)


# CORS — allow Flutter web app to call this server
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    return response


@app.route("/generate", methods=["OPTIONS"])
@app.route("/health", methods=["OPTIONS"])
@app.route("/templates", methods=["OPTIONS"])
def handle_options():
    """Handle CORS preflight."""
    return "", 204


@app.route("/health", methods=["GET"])
def health():
    """Health check — verifies QGIS is working."""
    try:
        from cartographic.qgis_renderer import is_qgis_available
        qgis_ok = is_qgis_available()
    except Exception as e:
        qgis_ok = False

    return jsonify({
        "status": "ok",
        "qgis_available": qgis_ok,
        "engine": "EcoLens Cartographic Intelligence Engine",
    })


@app.route("/generate", methods=["POST"])
def generate():
    """
    Generate a cartographic map.

    Accepts JSON body matching the Cloud Function schema.
    Returns JSON with image_base64 and quality_report.
    """
    import matplotlib
    matplotlib.use("Agg")

    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON body required"}), 400

        from cartographic.composition_engine import (
            CartographicCompositionEngine, MapRequest,
        )

        engine = CartographicCompositionEngine()

        # Check for showcase mode
        showcase_id = data.get("showcase_id")
        if showcase_id:
            result = engine.compose_showcase(showcase_id)
        else:
            bbox = data.get("bbox")
            if not bbox or len(bbox) != 4:
                return jsonify({"error": "bbox [west, south, east, north] required"}), 400

            date_range = None
            dr = data.get("date_range")
            if dr and len(dr) == 2:
                date_range = (str(dr[0]), str(dr[1]))

            map_request = MapRequest(
                bbox=tuple(float(x) for x in bbox),
                map_type=data.get("map_type", "choropleth"),
                theme=data.get("theme"),
                title=data.get("title"),
                subtitle=data.get("subtitle"),
                layer_ids=data.get("layer_ids"),
                geojson_data=data.get("geojson_data"),
                value_field=data.get("value_field"),
                label_field=data.get("label_field"),
                date_range=date_range,
                classification_method=data.get("classification_method", "natural_breaks"),
                n_classes=int(data.get("n_classes", 5)),
                color_palette=data.get("color_palette"),
                dark_mode=bool(data.get("dark_mode", False)),
                show_labels=bool(data.get("show_labels", True)),
                show_legend=bool(data.get("show_legend", True)),
                show_scale_bar=bool(data.get("show_scale_bar", True)),
                show_north_arrow=bool(data.get("show_north_arrow", False)),
                show_grid=bool(data.get("show_grid", True)),
                show_source_attribution=bool(data.get("show_source_attribution", True)),
                output_format=data.get("output_format", "png"),
                output_dpi=int(data.get("output_dpi", 200)),
                width_inches=float(data.get("width_inches", 16)),
                height_inches=float(data.get("height_inches", 12)),
            )
            result = engine.compose(map_request)

        response = {
            "quality_report": result.quality_report,
            "metadata": result.metadata,
            "violations": result.violations,
            "suggestions": result.suggestions,
            "passed_validation": result.passed_validation,
            "attributions": result.attributions,
            "projection": result.projection,
            "width_px": result.width_px,
            "height_px": result.height_px,
            "format": result.format,
            "image_base64": base64.b64encode(result.image_bytes).decode("utf-8"),
        }

        renderer = result.metadata.get("renderer", "matplotlib")
        print(f"Map generated via {renderer}: "
              f"{result.width_px}x{result.height_px}, "
              f"quality={result.quality_report.get('overall', 0)}/100")

        return jsonify(response)

    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/templates", methods=["GET"])
def templates():
    """Return the full catalog of templates, palettes, and showcases."""
    try:
        from cartographic.templates import TemplateRegistry
        from cartographic.color_systems import ColorSystems

        registry = TemplateRegistry()
        colors = ColorSystems()

        catalog = registry.get_all_templates_as_catalog()
        palettes = {
            "sequential": colors.get_available_palettes("sequential"),
            "diverging": colors.get_available_palettes("diverging"),
            "qualitative": colors.get_available_palettes("qualitative"),
        }

        return jsonify({
            "templates": catalog["templates"],
            "showcase_examples": catalog["showcase_examples"],
            "palettes": palettes,
        })

    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"EcoLens Cartographic Engine starting on port {port}")

    # Initialize QGIS in the MAIN thread before Flask starts
    try:
        from cartographic.qgis_renderer import is_qgis_available
        if is_qgis_available():
            print("QGIS renderer: ACTIVE (initialized in main thread)")
        else:
            print("QGIS renderer: NOT AVAILABLE (matplotlib fallback)")
    except Exception:
        print("QGIS renderer: IMPORT FAILED (matplotlib fallback)")

    # CRITICAL: Flask must run single-threaded for QGIS Qt compatibility
    # QGIS uses Qt which is NOT thread-safe
    app.run(host="0.0.0.0", port=port, debug=False, threaded=False)
