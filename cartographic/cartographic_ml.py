"""
Cartographic Machine Learning Engine

Learns to produce better maps by optimizing rendering parameters
based on quality feedback from every map generated.

Architecture:
  - NOT generating pixels with ML — QGIS/matplotlib does rendering
  - ML learns WHICH PARAMETERS produce highest quality scores
  - Reward signal: 6-dimension quality scores from QualityValidator
  - Features: map context (extent, theme, data density, geometry types)
  - Targets: optimal rendering parameters (palette, n_classes, symbol sizes, etc.)

Models:
  1. ParameterPredictor  — predicts best params for a new map request
  2. QualityEstimator    — estimates quality score before rendering (fast pre-flight)
  3. StyleTransfer        — learns palette/symbology preferences from exemplar maps

Training loop:
  1. Map requested → ML predicts optimal parameters
  2. Map rendered with those parameters
  3. Quality validator scores the result
  4. (context, parameters, scores) logged as training sample
  5. Model retrains periodically on accumulated samples
  6. Next map benefits from learned preferences

Uses scikit-learn (already in requirements) — no heavy deep learning deps needed.
"""

from __future__ import annotations

import json
import logging
import math
import os
import pickle
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

# Try importing sklearn — available in Cloud Functions (requirements.txt)
try:
    from sklearn.ensemble import GradientBoostingRegressor, RandomForestClassifier
    from sklearn.preprocessing import StandardScaler, LabelEncoder
    from sklearn.model_selection import cross_val_score
    HAS_SKLEARN = True
except ImportError:
    HAS_SKLEARN = False
    logger.warning("scikit-learn not available — ML features disabled")


# ═══════════════════════════════════════════════════════════════════════
# TRAINING SAMPLE
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class MapSample:
    """A single training sample: context + parameters + quality outcome."""

    # Context features (what kind of map was requested)
    bbox_width_deg: float
    bbox_height_deg: float
    bbox_center_lat: float
    bbox_center_lon: float
    extent_category: str          # "local", "regional", "continental", "global"
    theme: str                    # "earthquake", "deforestation", etc.
    map_type: str                 # "choropleth", "proportional_symbol", etc.
    feature_count: int            # Number of data features
    geometry_type: str            # "point", "polygon", "mixed"
    data_value_range: float       # max - min of the value field
    data_value_skewness: float    # Skewness of value distribution
    dark_mode: bool

    # Parameters used (what the engine chose)
    palette_name: str
    palette_type: str             # "sequential", "diverging", "qualitative"
    n_classes: int
    classification_method: str
    symbol_min_size: float
    symbol_max_size: float
    label_font_size: float
    basemap_opacity: float
    show_grid: bool
    show_labels: bool
    dpi: int
    projection_type: str          # "equal_area", "conformal", "utm", "plate_carree"

    # Quality outcome (reward signal)
    overall_score: float
    visual_hierarchy_score: float
    color_theory_score: float
    typography_score: float
    layout_score: float
    generalization_score: float
    data_integrity_score: float
    violation_count: int
    passed: bool

    # Metadata
    timestamp: str = ""
    renderer: str = ""            # "qgis" or "matplotlib"

    def to_feature_vector(self) -> np.ndarray:
        """Convert context features to numeric array for ML input."""
        extent_map = {"local": 0, "regional": 1, "continental": 2, "global": 3}
        theme_map = {
            "earthquake": 0, "deforestation": 1, "fire_risk": 2,
            "flood_risk": 3, "multi_hazard": 4, "biodiversity": 5,
            "vegetation_health": 6, "drought": 7, "population_exposure": 8,
        }
        type_map = {
            "choropleth": 0, "heatmap": 1, "proportional_symbol": 2,
            "dot_density": 3, "isopleth": 4, "bivariate_choropleth": 5,
            "multi_hazard_risk": 6,
        }
        geom_map = {"point": 0, "polygon": 1, "line": 2, "mixed": 3}

        return np.array([
            self.bbox_width_deg,
            self.bbox_height_deg,
            self.bbox_center_lat,
            self.bbox_center_lon,
            extent_map.get(self.extent_category, 1),
            theme_map.get(self.theme, 4),
            type_map.get(self.map_type, 0),
            self.feature_count,
            geom_map.get(self.geometry_type, 3),
            self.data_value_range,
            self.data_value_skewness,
            1.0 if self.dark_mode else 0.0,
        ], dtype=np.float64)

    def to_parameter_vector(self) -> np.ndarray:
        """Convert chosen parameters to numeric array for ML output."""
        palette_type_map = {"sequential": 0, "diverging": 1, "qualitative": 2}
        class_map = {"natural_breaks": 0, "quantile": 1, "equal_interval": 2}
        proj_map = {"equal_area": 0, "conformal": 1, "utm": 2, "plate_carree": 3}

        return np.array([
            self.n_classes,
            palette_type_map.get(self.palette_type, 0),
            class_map.get(self.classification_method, 0),
            self.symbol_min_size,
            self.symbol_max_size,
            self.label_font_size,
            self.basemap_opacity,
            1.0 if self.show_grid else 0.0,
            1.0 if self.show_labels else 0.0,
            self.dpi,
            proj_map.get(self.projection_type, 0),
        ], dtype=np.float64)

    def to_dict(self) -> dict:
        """Serialize for storage."""
        return {
            "context": {
                "bbox_width_deg": self.bbox_width_deg,
                "bbox_height_deg": self.bbox_height_deg,
                "bbox_center_lat": self.bbox_center_lat,
                "bbox_center_lon": self.bbox_center_lon,
                "extent_category": self.extent_category,
                "theme": self.theme,
                "map_type": self.map_type,
                "feature_count": self.feature_count,
                "geometry_type": self.geometry_type,
                "data_value_range": self.data_value_range,
                "data_value_skewness": self.data_value_skewness,
                "dark_mode": self.dark_mode,
            },
            "parameters": {
                "palette_name": self.palette_name,
                "palette_type": self.palette_type,
                "n_classes": self.n_classes,
                "classification_method": self.classification_method,
                "symbol_min_size": self.symbol_min_size,
                "symbol_max_size": self.symbol_max_size,
                "label_font_size": self.label_font_size,
                "basemap_opacity": self.basemap_opacity,
                "show_grid": self.show_grid,
                "show_labels": self.show_labels,
                "dpi": self.dpi,
                "projection_type": self.projection_type,
            },
            "quality": {
                "overall_score": self.overall_score,
                "visual_hierarchy": self.visual_hierarchy_score,
                "color_theory": self.color_theory_score,
                "typography": self.typography_score,
                "layout": self.layout_score,
                "generalization": self.generalization_score,
                "data_integrity": self.data_integrity_score,
                "violation_count": self.violation_count,
                "passed": self.passed,
            },
            "metadata": {
                "timestamp": self.timestamp,
                "renderer": self.renderer,
            },
        }

    @classmethod
    def from_dict(cls, d: dict) -> "MapSample":
        ctx = d.get("context", {})
        params = d.get("parameters", {})
        quality = d.get("quality", {})
        meta = d.get("metadata", {})
        return cls(
            bbox_width_deg=ctx.get("bbox_width_deg", 0),
            bbox_height_deg=ctx.get("bbox_height_deg", 0),
            bbox_center_lat=ctx.get("bbox_center_lat", 0),
            bbox_center_lon=ctx.get("bbox_center_lon", 0),
            extent_category=ctx.get("extent_category", "regional"),
            theme=ctx.get("theme", "multi_hazard"),
            map_type=ctx.get("map_type", "choropleth"),
            feature_count=ctx.get("feature_count", 0),
            geometry_type=ctx.get("geometry_type", "mixed"),
            data_value_range=ctx.get("data_value_range", 0),
            data_value_skewness=ctx.get("data_value_skewness", 0),
            dark_mode=ctx.get("dark_mode", False),
            palette_name=params.get("palette_name", "YlOrRd"),
            palette_type=params.get("palette_type", "sequential"),
            n_classes=params.get("n_classes", 5),
            classification_method=params.get("classification_method", "natural_breaks"),
            symbol_min_size=params.get("symbol_min_size", 3.0),
            symbol_max_size=params.get("symbol_max_size", 35.0),
            label_font_size=params.get("label_font_size", 9.0),
            basemap_opacity=params.get("basemap_opacity", 1.0),
            show_grid=params.get("show_grid", True),
            show_labels=params.get("show_labels", True),
            dpi=params.get("dpi", 200),
            projection_type=params.get("projection_type", "equal_area"),
            overall_score=quality.get("overall_score", 0),
            visual_hierarchy_score=quality.get("visual_hierarchy", 0),
            color_theory_score=quality.get("color_theory", 0),
            typography_score=quality.get("typography", 0),
            layout_score=quality.get("layout", 0),
            generalization_score=quality.get("generalization", 0),
            data_integrity_score=quality.get("data_integrity", 0),
            violation_count=quality.get("violation_count", 0),
            passed=quality.get("passed", False),
            timestamp=meta.get("timestamp", ""),
            renderer=meta.get("renderer", ""),
        )


# ═══════════════════════════════════════════════════════════════════════
# CARTOGRAPHIC ML ENGINE
# ═══════════════════════════════════════════════════════════════════════

class CartographicML:
    """
    Machine learning engine that learns to produce better maps.

    Three models:
    1. QualityPredictor  — estimates quality score from (context, params)
                           without rendering. Used for fast parameter search.
    2. ParameterOptimizer — given context, predicts params that maximize quality.
    3. PaletteSelector   — classifies best palette for a given context.

    Usage:
        ml = CartographicML()
        ml.load_or_initialize()

        # Before rendering: predict optimal parameters
        optimal_params = ml.predict_parameters(context)

        # After rendering: log the result for training
        ml.log_sample(sample)

        # Periodically: retrain on accumulated data
        ml.retrain()
    """

    MODEL_DIR = Path("/tmp/ecolens_ml_models")
    DATA_DIR = Path("/tmp/ecolens_ml_data")

    # Parameter search space for optimization
    PARAM_SPACE = {
        "n_classes": [3, 4, 5, 6, 7, 8, 9],
        "palette_type": ["sequential", "diverging", "qualitative"],
        "classification_method": ["natural_breaks", "quantile", "equal_interval"],
        "symbol_min_size": [2.0, 3.0, 4.0, 5.0],
        "symbol_max_size": [25.0, 30.0, 35.0, 40.0, 45.0],
        "label_font_size": [7.0, 8.0, 9.0, 10.0, 11.0],
        "basemap_opacity": [0.6, 0.7, 0.8, 0.9, 1.0],
    }

    # Palette recommendations learned from exemplars + cartographic rules
    PALETTE_RULES = {
        # (theme, data_type) → ranked palette list
        ("earthquake", "point"): ["YlOrRd", "OrRd", "Reds", "YlOrBr"],
        ("deforestation", "polygon"): ["YlOrRd", "OrRd", "YlOrBr", "Reds"],
        ("fire_risk", "point"): ["OrRd", "YlOrRd", "Reds", "Oranges"],
        ("flood_risk", "polygon"): ["PuBu", "Blues", "GnBu", "YlGnBu"],
        ("biodiversity", "polygon"): ["YlGn", "Greens", "BuGn", "PuBuGn"],
        ("vegetation_health", "polygon"): ["RdYlGn", "BrBG", "PRGn"],
        ("drought", "polygon"): ["YlOrBr", "OrRd", "Oranges"],
        ("multi_hazard", "mixed"): ["YlOrRd", "OrRd", "RdBu"],
        ("population_exposure", "polygon"): ["YlOrBr", "OrRd", "PuRd"],
    }

    def __init__(self):
        self._samples: list[MapSample] = []
        self._quality_model = None       # GradientBoostingRegressor
        self._palette_model = None       # RandomForestClassifier
        self._scaler = None              # StandardScaler
        self._palette_encoder = None     # LabelEncoder
        self._is_trained = False
        self._train_count = 0
        self._generation_count = 0

    def load_or_initialize(self):
        """Load saved models and training data, or initialize fresh."""
        self.MODEL_DIR.mkdir(parents=True, exist_ok=True)
        self.DATA_DIR.mkdir(parents=True, exist_ok=True)

        # Load training data
        data_path = self.DATA_DIR / "training_samples.json"
        if data_path.exists():
            try:
                with open(data_path, "r") as f:
                    raw = json.load(f)
                self._samples = [MapSample.from_dict(d) for d in raw]
                logger.info(f"Loaded {len(self._samples)} training samples")
            except Exception as e:
                logger.warning(f"Failed to load training data: {e}")

        # Load models
        model_path = self.MODEL_DIR / "quality_model.pkl"
        if model_path.exists() and HAS_SKLEARN:
            try:
                with open(model_path, "rb") as f:
                    saved = pickle.load(f)
                self._quality_model = saved.get("quality_model")
                self._palette_model = saved.get("palette_model")
                self._scaler = saved.get("scaler")
                self._palette_encoder = saved.get("palette_encoder")
                self._is_trained = True
                self._train_count = saved.get("train_count", 0)
                logger.info(f"Loaded trained models (trained on {self._train_count} samples)")
            except Exception as e:
                logger.warning(f"Failed to load models: {e}")

        # Seed with exemplar-derived synthetic samples if empty
        if not self._samples:
            self._seed_from_exemplars()

    def _seed_from_exemplars(self):
        """
        Generate synthetic training samples from the exemplar map database
        and cartographic rules. This gives the model a starting point before
        any real maps are generated.
        """
        try:
            from cartographic.map_reference_db import MapReferenceDatabase
            db = MapReferenceDatabase()
            exemplars = db.get_all()
        except Exception:
            exemplars = []

        # Generate synthetic samples from exemplar metadata
        # Each exemplar tells us what parameters work well for its map type
        synthetic = []

        # High-quality samples from exemplars
        for ex in exemplars:
            # Simulate context features from exemplar metadata
            sample = MapSample(
                bbox_width_deg=30.0 if "global" not in ex.name.lower() else 360.0,
                bbox_height_deg=20.0 if "global" not in ex.name.lower() else 130.0,
                bbox_center_lat=0.0,
                bbox_center_lon=0.0,
                extent_category="continental",
                theme=ex.theme if ex.theme in ("environmental", "hazard") else "multi_hazard",
                map_type=ex.map_type,
                feature_count=100,
                geometry_type="polygon" if ex.map_type == "choropleth" else "point",
                data_value_range=100.0,
                data_value_skewness=1.5,
                dark_mode=ex.background_lightness == "dark",
                palette_name=ex.palette_name or "YlOrRd",
                palette_type=ex.palette_type,
                n_classes=ex.n_classes,
                classification_method="natural_breaks",
                symbol_min_size=3.0,
                symbol_max_size=35.0,
                label_font_size=9.0,
                basemap_opacity=0.8,
                show_grid=True,
                show_labels=True,
                dpi=200,
                projection_type="equal_area",
                # Exemplars are award-winning → high scores
                overall_score=92.0,
                visual_hierarchy_score=95.0,
                color_theory_score=93.0,
                typography_score=90.0,
                layout_score=88.0,
                generalization_score=92.0,
                data_integrity_score=95.0,
                violation_count=0,
                passed=True,
                timestamp=datetime.utcnow().isoformat(),
                renderer="exemplar",
            )
            synthetic.append(sample)

        # Also generate known-bad samples so the model learns contrast
        bad_combos = [
            # Wrong palette type for data
            {"theme": "earthquake", "palette_name": "Set2", "palette_type": "qualitative",
             "overall_score": 45.0, "color_theory_score": 25.0},
            # Rainbow palette
            {"theme": "deforestation", "palette_name": "Spectral", "palette_type": "diverging",
             "overall_score": 40.0, "color_theory_score": 20.0},
            # Too many classes
            {"theme": "flood_risk", "n_classes": 15, "overall_score": 55.0,
             "data_integrity_score": 50.0},
            # Too few classes
            {"theme": "fire_risk", "n_classes": 2, "overall_score": 60.0,
             "data_integrity_score": 55.0},
            # No labels on dense data
            {"theme": "multi_hazard", "show_labels": False, "feature_count": 500,
             "overall_score": 65.0, "typography_score": 50.0},
            # Sequential palette for diverging data
            {"theme": "vegetation_health", "palette_name": "YlOrRd", "palette_type": "sequential",
             "overall_score": 50.0, "color_theory_score": 30.0},
            # Low DPI
            {"theme": "earthquake", "dpi": 72, "overall_score": 60.0,
             "visual_hierarchy_score": 55.0},
        ]

        for bad in bad_combos:
            sample = MapSample(
                bbox_width_deg=30.0, bbox_height_deg=20.0,
                bbox_center_lat=0.0, bbox_center_lon=0.0,
                extent_category="continental",
                theme=bad.get("theme", "multi_hazard"),
                map_type="choropleth",
                feature_count=bad.get("feature_count", 50),
                geometry_type="polygon",
                data_value_range=100.0,
                data_value_skewness=1.5,
                dark_mode=False,
                palette_name=bad.get("palette_name", "YlOrRd"),
                palette_type=bad.get("palette_type", "sequential"),
                n_classes=bad.get("n_classes", 5),
                classification_method="natural_breaks",
                symbol_min_size=3.0,
                symbol_max_size=35.0,
                label_font_size=9.0,
                basemap_opacity=0.8,
                show_grid=True,
                show_labels=bad.get("show_labels", True),
                dpi=bad.get("dpi", 200),
                projection_type="equal_area",
                overall_score=bad.get("overall_score", 50.0),
                visual_hierarchy_score=bad.get("visual_hierarchy_score", 70.0),
                color_theory_score=bad.get("color_theory_score", 70.0),
                typography_score=bad.get("typography_score", 70.0),
                layout_score=bad.get("layout_score", 70.0),
                generalization_score=bad.get("generalization_score", 70.0),
                data_integrity_score=bad.get("data_integrity_score", 70.0),
                violation_count=3,
                passed=False,
                timestamp=datetime.utcnow().isoformat(),
                renderer="synthetic_bad",
            )
            synthetic.append(sample)

        # Generate varied good samples across themes and map types
        themes = ["earthquake", "deforestation", "fire_risk", "flood_risk",
                  "multi_hazard", "biodiversity", "vegetation_health", "drought"]
        map_types = ["choropleth", "proportional_symbol", "heatmap"]

        for theme in themes:
            for mt in map_types:
                for n_cls in [4, 5, 6, 7]:
                    for dark in [True, False]:
                        # Good parameters for this combo
                        palette = self._rule_based_palette(theme, mt)
                        score = 85.0 + np.random.normal(0, 5)
                        score = max(60, min(100, score))

                        sample = MapSample(
                            bbox_width_deg=20.0 + np.random.uniform(-10, 30),
                            bbox_height_deg=15.0 + np.random.uniform(-5, 20),
                            bbox_center_lat=np.random.uniform(-40, 40),
                            bbox_center_lon=np.random.uniform(-180, 180),
                            extent_category="regional",
                            theme=theme,
                            map_type=mt,
                            feature_count=int(50 + np.random.exponential(200)),
                            geometry_type="point" if mt in ("proportional_symbol", "heatmap") else "polygon",
                            data_value_range=np.random.uniform(10, 1000),
                            data_value_skewness=np.random.uniform(0, 3),
                            dark_mode=dark,
                            palette_name=palette,
                            palette_type="sequential",
                            n_classes=n_cls,
                            classification_method="natural_breaks",
                            symbol_min_size=3.0,
                            symbol_max_size=35.0,
                            label_font_size=9.0,
                            basemap_opacity=0.8,
                            show_grid=True,
                            show_labels=True,
                            dpi=200,
                            projection_type="equal_area",
                            overall_score=score,
                            visual_hierarchy_score=score + np.random.normal(0, 3),
                            color_theory_score=score + np.random.normal(0, 3),
                            typography_score=score + np.random.normal(0, 3),
                            layout_score=score + np.random.normal(0, 5),
                            generalization_score=score + np.random.normal(0, 3),
                            data_integrity_score=score + np.random.normal(0, 3),
                            violation_count=0 if score > 80 else int(np.random.poisson(2)),
                            passed=score >= 70,
                            timestamp=datetime.utcnow().isoformat(),
                            renderer="synthetic_good",
                        )
                        synthetic.append(sample)

        self._samples.extend(synthetic)
        logger.info(f"Seeded {len(synthetic)} synthetic training samples")

    def _rule_based_palette(self, theme: str, map_type: str) -> str:
        """Get palette from learned rules."""
        geom = "point" if map_type in ("proportional_symbol", "heatmap") else "polygon"
        key = (theme, geom)
        palettes = self.PALETTE_RULES.get(key, ["YlOrRd"])
        return palettes[0]

    # ═══════════════════════════════════════════════════════════════
    # PREDICTION
    # ═══════════════════════════════════════════════════════════════

    def predict_parameters(self, context: dict) -> dict:
        """
        Predict optimal rendering parameters for a map request.

        Args:
            context: {
                "bbox": [w, s, e, n],
                "theme": str,
                "map_type": str,
                "feature_count": int,
                "geometry_type": str,
                "data_value_range": float,
                "data_value_skewness": float,
                "dark_mode": bool,
            }

        Returns:
            Optimized parameter dict ready to merge into MapRequest
        """
        bbox = context.get("bbox", [0, 0, 0, 0])
        theme = context.get("theme", "multi_hazard")
        map_type = context.get("map_type", "choropleth")
        feature_count = context.get("feature_count", 100)
        geom_type = context.get("geometry_type", "mixed")
        dark_mode = context.get("dark_mode", False)

        # Start with rule-based defaults
        params = self._rule_based_prediction(context)

        # If model is trained, override with ML predictions
        if self._is_trained and self._quality_model is not None and HAS_SKLEARN:
            try:
                ml_params = self._ml_prediction(context)
                # Only override if ML is confident (trained on enough data)
                if self._train_count >= 50:
                    params.update(ml_params)
                else:
                    # Blend: weight ML predictions by confidence
                    confidence = min(self._train_count / 50.0, 1.0)
                    for key, ml_val in ml_params.items():
                        if key in params and isinstance(ml_val, (int, float)):
                            rule_val = params[key]
                            if isinstance(rule_val, (int, float)):
                                params[key] = rule_val * (1 - confidence) + ml_val * confidence
            except Exception as e:
                logger.warning(f"ML prediction failed, using rules: {e}")

        return params

    def _rule_based_prediction(self, context: dict) -> dict:
        """
        Predict parameters using codified cartographic rules.
        This is the baseline — always available, no training needed.
        """
        bbox = context.get("bbox", [0, 0, 0, 0])
        theme = context.get("theme", "multi_hazard")
        map_type = context.get("map_type", "choropleth")
        feature_count = context.get("feature_count", 100)
        geom_type = context.get("geometry_type", "mixed")
        dark_mode = context.get("dark_mode", False)

        width = bbox[2] - bbox[0] if len(bbox) == 4 else 30
        height = bbox[3] - bbox[1] if len(bbox) == 4 else 20

        # Palette selection from rules
        palette_key = (theme, geom_type)
        if palette_key not in self.PALETTE_RULES:
            palette_key = (theme, "polygon" if map_type == "choropleth" else "point")
        palettes = self.PALETTE_RULES.get(palette_key, ["YlOrRd"])
        palette = palettes[0]

        # N classes: depends on feature count and extent
        if feature_count < 20:
            n_classes = 3
        elif feature_count < 100:
            n_classes = 5
        elif feature_count < 500:
            n_classes = 6
        else:
            n_classes = 7

        # Classification: natural breaks for skewed, quantile for uniform
        skewness = context.get("data_value_skewness", 1.5)
        classification = "natural_breaks" if skewness > 1.0 else "quantile"

        # Symbol sizes: scale with extent
        if map_type == "proportional_symbol":
            if width > 100:  # Global
                symbol_min, symbol_max = 2.0, 25.0
            elif width > 30:  # Continental
                symbol_min, symbol_max = 3.0, 35.0
            else:  # Regional/local
                symbol_min, symbol_max = 4.0, 40.0
        else:
            symbol_min, symbol_max = 3.0, 35.0

        # Label font: larger for fewer features
        if feature_count < 20:
            label_size = 11.0
        elif feature_count < 100:
            label_size = 9.0
        else:
            label_size = 8.0

        # Show labels: disable for very dense maps
        show_labels = feature_count < 300

        # DPI: higher for smaller extents (more detail needed)
        dpi = 200 if width < 30 else 150

        return {
            "color_palette": palette,
            "n_classes": n_classes,
            "classification_method": classification,
            "symbol_min_size": symbol_min,
            "symbol_max_size": symbol_max,
            "label_font_size": label_size,
            "basemap_opacity": 0.8,
            "show_labels": show_labels,
            "show_grid": True,
            "output_dpi": dpi,
        }

    def _ml_prediction(self, context: dict) -> dict:
        """Predict parameters using trained ML model."""
        if not self._quality_model or not self._scaler:
            return {}

        bbox = context.get("bbox", [0, 0, 0, 0])
        width = bbox[2] - bbox[0] if len(bbox) == 4 else 30
        height = bbox[3] - bbox[1] if len(bbox) == 4 else 20

        # Build feature vector
        features = np.array([[
            width, height,
            (bbox[1] + bbox[3]) / 2 if len(bbox) == 4 else 0,
            (bbox[0] + bbox[2]) / 2 if len(bbox) == 4 else 0,
            1,  # extent category
            0,  # theme (encoded)
            0,  # map type (encoded)
            context.get("feature_count", 100),
            0,  # geometry type
            context.get("data_value_range", 100),
            context.get("data_value_skewness", 1.5),
            1.0 if context.get("dark_mode") else 0.0,
        ]])

        # Find best n_classes by predicting quality for each option
        best_score = -1
        best_n_classes = 5

        for n_cls in self.PARAM_SPACE["n_classes"]:
            # Augment features with n_classes
            aug = np.column_stack([features, [[n_cls]]])
            try:
                scaled = self._scaler.transform(aug)
                predicted_score = self._quality_model.predict(scaled)[0]
                if predicted_score > best_score:
                    best_score = predicted_score
                    best_n_classes = n_cls
            except Exception:
                pass

        # Predict palette
        predicted_palette = None
        if self._palette_model and self._palette_encoder:
            try:
                scaled = self._scaler.transform(
                    np.column_stack([features, [[best_n_classes]]])
                )
                palette_idx = self._palette_model.predict(scaled)[0]
                predicted_palette = self._palette_encoder.inverse_transform([palette_idx])[0]
            except Exception:
                pass

        result = {"n_classes": best_n_classes}
        if predicted_palette:
            result["color_palette"] = predicted_palette

        return result

    def predict_quality(self, context: dict, params: dict) -> float:
        """
        Estimate quality score without rendering.
        Used for fast pre-flight parameter comparison.
        """
        if not self._is_trained or not self._quality_model:
            return 80.0  # Default estimate

        try:
            bbox = context.get("bbox", [0, 0, 0, 0])
            features = np.array([[
                bbox[2] - bbox[0], bbox[3] - bbox[1],
                (bbox[1] + bbox[3]) / 2, (bbox[0] + bbox[2]) / 2,
                1, 0, 0,
                context.get("feature_count", 100),
                0,
                context.get("data_value_range", 100),
                context.get("data_value_skewness", 1.5),
                1.0 if context.get("dark_mode") else 0.0,
                params.get("n_classes", 5),
            ]])
            scaled = self._scaler.transform(features)
            return float(self._quality_model.predict(scaled)[0])
        except Exception:
            return 80.0

    # ═══════════════════════════════════════════════════════════════
    # LOGGING + TRAINING
    # ═══════════════════════════════════════════════════════════════

    def log_sample(self, sample: MapSample):
        """Log a rendered map's parameters and quality for training."""
        self._samples.append(sample)
        self._generation_count += 1

        # Save training data periodically
        if self._generation_count % 10 == 0:
            self._save_training_data()

        # Retrain periodically
        if self._generation_count % 25 == 0 and len(self._samples) >= 30:
            self.retrain()

    def log_from_result(
        self,
        request_context: dict,
        params_used: dict,
        quality_report: dict,
        metadata: dict,
    ):
        """
        Convenience: log a sample from composition engine output.
        Called automatically after every map generation.
        """
        bbox = request_context.get("bbox", [0, 0, 0, 0])
        dims = quality_report.get("dimensions", {})

        sample = MapSample(
            bbox_width_deg=bbox[2] - bbox[0] if len(bbox) == 4 else 0,
            bbox_height_deg=bbox[3] - bbox[1] if len(bbox) == 4 else 0,
            bbox_center_lat=(bbox[1] + bbox[3]) / 2 if len(bbox) == 4 else 0,
            bbox_center_lon=(bbox[0] + bbox[2]) / 2 if len(bbox) == 4 else 0,
            extent_category=request_context.get("extent_category", "regional"),
            theme=request_context.get("theme", "multi_hazard"),
            map_type=request_context.get("map_type", "choropleth"),
            feature_count=request_context.get("feature_count", 0),
            geometry_type=request_context.get("geometry_type", "mixed"),
            data_value_range=request_context.get("data_value_range", 0),
            data_value_skewness=request_context.get("data_value_skewness", 0),
            dark_mode=request_context.get("dark_mode", False),
            palette_name=params_used.get("color_palette", "YlOrRd"),
            palette_type=params_used.get("palette_type", "sequential"),
            n_classes=params_used.get("n_classes", 5),
            classification_method=params_used.get("classification_method", "natural_breaks"),
            symbol_min_size=params_used.get("symbol_min_size", 3.0),
            symbol_max_size=params_used.get("symbol_max_size", 35.0),
            label_font_size=params_used.get("label_font_size", 9.0),
            basemap_opacity=params_used.get("basemap_opacity", 0.8),
            show_grid=params_used.get("show_grid", True),
            show_labels=params_used.get("show_labels", True),
            dpi=params_used.get("dpi", 200),
            projection_type=params_used.get("projection_type", "equal_area"),
            overall_score=quality_report.get("overall", 0),
            visual_hierarchy_score=dims.get("visual_hierarchy", 0),
            color_theory_score=dims.get("color_theory", 0),
            typography_score=dims.get("typography", 0),
            layout_score=dims.get("layout", 0),
            generalization_score=dims.get("generalization", 0),
            data_integrity_score=dims.get("data_integrity", 0),
            violation_count=quality_report.get("violation_count", 0),
            passed=quality_report.get("passed", False),
            timestamp=datetime.utcnow().isoformat(),
            renderer=metadata.get("renderer", "unknown"),
        )
        self.log_sample(sample)

    def retrain(self):
        """
        Retrain all models on accumulated training data.

        Called automatically every 25 map generations, or manually.
        """
        if not HAS_SKLEARN:
            logger.warning("scikit-learn not available — cannot train")
            return

        if len(self._samples) < 20:
            logger.info(f"Not enough samples to train ({len(self._samples)} < 20)")
            return

        logger.info(f"Retraining on {len(self._samples)} samples...")
        start = time.time()

        try:
            # Build training matrices
            X_context = []  # Context features
            X_full = []     # Context + n_classes (for quality prediction)
            y_quality = []  # Overall quality score
            y_palette = []  # Palette name (for classification)

            for s in self._samples:
                ctx = s.to_feature_vector()
                X_context.append(ctx)
                X_full.append(np.append(ctx, s.n_classes))
                y_quality.append(s.overall_score)
                y_palette.append(s.palette_name)

            X_context = np.array(X_context)
            X_full = np.array(X_full)
            y_quality = np.array(y_quality)

            # ─── MODEL 1: Quality Predictor ──────────────────────
            self._scaler = StandardScaler()
            X_scaled = self._scaler.fit_transform(X_full)

            self._quality_model = GradientBoostingRegressor(
                n_estimators=100,
                max_depth=5,
                learning_rate=0.1,
                min_samples_leaf=5,
                random_state=42,
            )
            self._quality_model.fit(X_scaled, y_quality)

            # Cross-validation score
            cv_scores = cross_val_score(
                self._quality_model, X_scaled, y_quality,
                cv=min(5, len(self._samples) // 5 + 1),
                scoring="r2",
            )
            r2 = np.mean(cv_scores)

            # ─── MODEL 2: Palette Classifier ─────────────────────
            self._palette_encoder = LabelEncoder()
            y_palette_encoded = self._palette_encoder.fit_transform(y_palette)

            self._palette_model = RandomForestClassifier(
                n_estimators=50,
                max_depth=8,
                random_state=42,
            )
            self._palette_model.fit(X_scaled, y_palette_encoded)

            palette_accuracy = self._palette_model.score(X_scaled, y_palette_encoded)

            self._is_trained = True
            self._train_count = len(self._samples)

            elapsed = time.time() - start
            logger.info(
                f"Training complete in {elapsed:.1f}s: "
                f"quality R²={r2:.3f}, palette accuracy={palette_accuracy:.3f}, "
                f"samples={self._train_count}"
            )

            # Save models
            self._save_models()

        except Exception as e:
            logger.error(f"Training failed: {e}")
            import traceback
            traceback.print_exc()

    def _save_training_data(self):
        """Persist training samples to disk."""
        try:
            self.DATA_DIR.mkdir(parents=True, exist_ok=True)
            data_path = self.DATA_DIR / "training_samples.json"
            with open(data_path, "w") as f:
                json.dump([s.to_dict() for s in self._samples[-2000:]], f)
        except Exception as e:
            logger.warning(f"Failed to save training data: {e}")

    def _save_models(self):
        """Persist trained models to disk."""
        try:
            self.MODEL_DIR.mkdir(parents=True, exist_ok=True)
            model_path = self.MODEL_DIR / "quality_model.pkl"
            with open(model_path, "wb") as f:
                pickle.dump({
                    "quality_model": self._quality_model,
                    "palette_model": self._palette_model,
                    "scaler": self._scaler,
                    "palette_encoder": self._palette_encoder,
                    "train_count": self._train_count,
                }, f)
        except Exception as e:
            logger.warning(f"Failed to save models: {e}")

    # ═══════════════════════════════════════════════════════════════
    # INSIGHTS
    # ═══════════════════════════════════════════════════════════════

    def get_insights(self) -> dict:
        """
        Return learning insights — what has the model learned?
        """
        if not self._samples:
            return {"status": "no_data", "message": "No training samples yet"}

        scores = [s.overall_score for s in self._samples]
        passed = [s for s in self._samples if s.passed]

        # Best parameters per theme
        theme_best = {}
        for s in self._samples:
            if s.overall_score >= 85 and s.renderer != "synthetic_bad":
                if s.theme not in theme_best or s.overall_score > theme_best[s.theme]["score"]:
                    theme_best[s.theme] = {
                        "score": s.overall_score,
                        "palette": s.palette_name,
                        "n_classes": s.n_classes,
                        "classification": s.classification_method,
                    }

        # Feature importance (if model trained)
        feature_importance = {}
        if self._is_trained and self._quality_model:
            feature_names = [
                "bbox_width", "bbox_height", "center_lat", "center_lon",
                "extent_category", "theme", "map_type", "feature_count",
                "geometry_type", "value_range", "skewness", "dark_mode",
                "n_classes",
            ]
            importances = self._quality_model.feature_importances_
            for name, imp in zip(feature_names, importances):
                feature_importance[name] = round(float(imp), 4)

        return {
            "status": "trained" if self._is_trained else "rules_only",
            "total_samples": len(self._samples),
            "real_samples": sum(1 for s in self._samples if s.renderer not in ("synthetic_good", "synthetic_bad", "exemplar")),
            "synthetic_samples": sum(1 for s in self._samples if s.renderer in ("synthetic_good", "synthetic_bad", "exemplar")),
            "average_score": round(np.mean(scores), 1),
            "pass_rate": round(len(passed) / len(self._samples) * 100, 1),
            "best_by_theme": theme_best,
            "feature_importance": feature_importance,
            "generation_count": self._generation_count,
            "train_count": self._train_count,
        }
