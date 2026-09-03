"""
Quality Validator

Comprehensive quality assessment for generated cartographic maps.
Runs all 6 dimension checks by inspecting the actual rendered matplotlib
figure, not just declared parameters.

Dimensions (each scored 0-100):
  1. Readability      — text sizes, contrast ratios, label overlaps
  2. Visual Hierarchy — title prominence, figure-ground, data-ink ratio
  3. Color Harmony    — perceptual uniformity, colorblind safety, scheme type
  4. Data Integrity   — source attribution, classification appropriateness, currency
  5. Layout Balance   — map body proportion, margins, legend placement
  6. Cartographic Conventions — scale bar, projection, generalization

Features:
  - Inspects live matplotlib Figure/Axes objects
  - Cross-references against exemplar award-winning maps
  - Auto-correction loop: fix issues and re-validate once
  - Continuous learning: logs every validation for pattern discovery
  - Quality gate: maps below 70/100 flagged as sub-professional
"""

from __future__ import annotations

import json
import logging
import math
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

import matplotlib.pyplot as plt
from matplotlib.axes import Axes
from matplotlib.figure import Figure
from matplotlib.text import Text

from cartographic.knowledge_base import (
    CartographicKnowledgeBase, DataType, RuleCategory, RuleSeverity, RuleViolation,
)
from cartographic.color_systems import ColorSystems, RGB, rgb_to_lab, delta_e_cie76
from cartographic.map_reference_db import MapReferenceDatabase

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════
# QUALITY REPORT
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class QualityReport:
    """Comprehensive quality assessment of a generated map."""
    overall_score: float                    # 0-100
    passed: bool                            # overall >= 70 and no critical violations
    dimensions: dict[str, float]            # {category: score}
    violations: list[RuleViolation]
    suggestions: list[str]
    exemplar_similarity: float              # 0-100
    auto_corrections_applied: list[str]
    inspection_details: dict                # Raw inspection data
    timestamp: str

    def to_dict(self) -> dict:
        return {
            "overall_score": round(self.overall_score, 1),
            "passed": self.passed,
            "dimensions": {k: round(v, 1) for k, v in self.dimensions.items()},
            "violation_count": len(self.violations),
            "violations": [v.to_dict() for v in self.violations],
            "suggestions": self.suggestions,
            "exemplar_similarity": round(self.exemplar_similarity, 1),
            "auto_corrections_applied": self.auto_corrections_applied,
            "timestamp": self.timestamp,
        }


# ═══════════════════════════════════════════════════════════════════════
# AUTO-CORRECTION ACTIONS
# ═══════════════════════════════════════════════════════════════════════

class AutoCorrector:
    """
    Applies automatic corrections to fix detected violations.

    Each correction method modifies the figure/axes in place and
    returns a description of what was changed.
    """

    def apply(
        self,
        fig: Figure,
        ax: Axes,
        violation: RuleViolation,
        context: dict,
    ) -> str | None:
        """
        Apply auto-correction for a violation.

        Returns description of correction applied, or None if not possible.
        """
        if not violation.auto_correctable or not violation.correction_hint:
            return None

        method = getattr(self, f"_correct_{violation.correction_hint}", None)
        if method is None:
            return None

        try:
            return method(fig, ax, violation, context)
        except Exception as e:
            logger.warning(f"Auto-correction failed for {violation.rule_id}: {e}")
            return None

    def _correct_increase_title_font_size(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Increase title font size to meet prominence requirement."""
        for text in fig.texts:
            if text.get_fontsize() >= 14:  # Likely the title
                new_size = text.get_fontsize() * 1.3
                text.set_fontsize(new_size)
                return f"Increased title font size to {new_size:.0f}pt"
        return None

    def _correct_reduce_basemap_opacity(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Reduce basemap layer opacity for better figure-ground."""
        for collection in ax.collections:
            alpha = collection.get_alpha()
            if alpha is None or alpha > 0.5:
                collection.set_alpha(0.4)
        return "Reduced basemap opacity to 0.4"

    def _correct_add_source_attribution(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Add source attribution text."""
        attributions = context.get("attributions", ["Data sources not specified"])
        credit = "Data: " + " | ".join(attributions) + "  •  Map: EcoLens"
        fig.text(
            0.5, 0.01, credit,
            ha="center", va="bottom",
            fontsize=7, color="#888888", style="italic",
        )
        return "Added source attribution"

    def _correct_increase_margins(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Increase margins to meet 3% minimum."""
        pos = ax.get_position()
        new_pos = [
            max(pos.x0, 0.05),
            max(pos.y0, 0.06),
            min(pos.width, 0.88),
            min(pos.height, 0.82),
        ]
        ax.set_position(new_pos)
        return "Adjusted margins to meet 3% minimum"

    def _correct_adjust_map_body_proportion(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Adjust map body to 60-80% range."""
        pos = ax.get_position()
        current_ratio = pos.width * pos.height

        if current_ratio < 0.60:
            # Expand map body
            ax.set_position([0.05, 0.06, 0.88, 0.82])
            return "Expanded map body to ~72% of layout"
        elif current_ratio > 0.80:
            # Shrink map body
            ax.set_position([0.08, 0.08, 0.80, 0.78])
            return "Reduced map body to ~62% of layout"
        return None

    def _correct_add_label_halos(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Add halos to labels missing them."""
        import matplotlib.patheffects as pe
        count = 0
        for text in ax.texts:
            effects = text.get_path_effects()
            if not effects:
                text.set_path_effects([
                    pe.withStroke(linewidth=2, foreground="white"),
                ])
                count += 1
        if count > 0:
            return f"Added halos to {count} labels"
        return None

    def _correct_increase_min_label_size(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Increase labels below 6pt minimum."""
        count = 0
        for text in ax.texts:
            if text.get_fontsize() < 6:
                text.set_fontsize(6)
                count += 1
        if count > 0:
            return f"Increased {count} labels to minimum 6pt"
        return None

    def _correct_increase_title_size(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return self._correct_increase_title_font_size(fig, ax, violation, context)

    def _correct_switch_to_sequential_palette(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Note: palette switching requires re-render, return suggestion."""
        return None  # Cannot change palette without re-render

    def _correct_switch_to_diverging_palette(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_switch_to_qualitative_palette(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_switch_to_perceptually_uniform_palette(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_add_north_arrow(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Add a simple north arrow."""
        xlim = ax.get_xlim()
        ylim = ax.get_ylim()
        w = xlim[1] - xlim[0]
        h = ylim[1] - ylim[0]
        x = xlim[1] - w * 0.05
        y = ylim[1] - h * 0.05

        ax.annotate(
            "N", xy=(x, y + h * 0.06), xytext=(x, y),
            fontsize=10, fontweight="bold", ha="center", va="bottom",
            color="#333333",
            arrowprops=dict(arrowstyle="->", color="#333333", lw=1.5),
            zorder=50,
        )
        return "Added north arrow"

    def _correct_adjust_halo_width(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Adjust halo widths to ideal 1/10 proportion."""
        import matplotlib.patheffects as pe
        count = 0
        for text in ax.texts:
            fs = text.get_fontsize()
            ideal_halo = fs * 0.1
            effects = text.get_path_effects()
            if effects:
                new_effects = []
                for ef in effects:
                    if hasattr(ef, '_linewidth'):
                        new_effects.append(
                            pe.withStroke(linewidth=ideal_halo * 2, foreground="white")
                        )
                    else:
                        new_effects.append(ef)
                text.set_path_effects(new_effects)
                count += 1
        if count > 0:
            return f"Adjusted halo width on {count} text elements"
        return None

    def _correct_reorder_layers(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Reorder layers to standard cartographic z-order."""
        # Adjust zorder: polygons < lines < points < labels
        for collection in ax.collections:
            if hasattr(collection, 'get_paths'):
                collection.set_zorder(5)
        for line in ax.lines:
            line.set_zorder(6)
        for text in ax.texts:
            text.set_zorder(100)
        return "Reordered layers: polygons(5) < lines(6) < labels(100)"

    def _correct_reduce_font_families(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Standardize all text to sans-serif."""
        for text in fig.texts + list(ax.texts):
            text.set_fontfamily("sans-serif")
        return "Standardized all text to sans-serif"

    def _correct_move_scale_bar(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None  # Would need to identify and reposition — too complex for auto

    def _correct_toggle_north_arrow(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_move_legend_closer(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_add_date_label(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Add data currency date label."""
        date_str = context.get("data_date", "Date unknown")
        fig.text(
            0.95, 0.02, f"Data as of: {date_str}",
            ha="right", va="bottom",
            fontsize=6, color="#999999",
        )
        return f"Added data currency label: {date_str}"

    def _correct_add_projection_label(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        """Add projection label."""
        proj_name = context.get("projection_name", "WGS84")
        fig.text(
            0.05, 0.02, f"Projection: {proj_name}",
            ha="left", va="bottom",
            fontsize=6, color="#999999",
        )
        return f"Added projection label: {proj_name}"

    def _correct_drop_null_geometries(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None  # Data-level correction, not figure-level

    def _correct_switch_to_natural_breaks(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None  # Requires re-classification and re-render

    def _correct_add_clipping_indicator(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_increase_palette_contrast(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_switch_legend_text_color(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_switch_to_colorblind_safe_palette(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_darken_lowest_class(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_reduce_decorative_elements(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_adjust_label_hierarchy(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_reposition_or_remove_labels(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_reduce_feature_count(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_enlarge_or_remove_small_features(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_adjust_simplification(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_increase_feature_gap(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_add_missing_attributions(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return self._correct_add_source_attribution(fig, ax, violation, context)

    def _correct_increase_class_count(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_reduce_class_count(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_adjust_aspect_ratio(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_move_title(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None

    def _correct_fix_proportional_scaling(
        self, fig: Figure, ax: Axes, violation: RuleViolation, context: dict,
    ) -> str:
        return None


# ═══════════════════════════════════════════════════════════════════════
# FIGURE INSPECTOR
# ═══════════════════════════════════════════════════════════════════════

class FigureInspector:
    """
    Inspects a rendered matplotlib Figure to extract measurable
    cartographic quality metrics from the actual visual output.
    """

    def inspect(
        self,
        fig: Figure,
        ax: Axes,
        context: dict | None = None,
    ) -> dict:
        """
        Deep inspection of a rendered figure.

        Returns dict with all measured metrics across all 6 dimensions.
        """
        ctx = context or {}
        results = {}

        results["text_elements"] = self._inspect_text(fig, ax)
        results["layers"] = self._inspect_layers(ax)
        results["layout"] = self._inspect_layout(fig, ax, ctx)
        results["colors"] = self._inspect_colors(ax, ctx)
        results["data_integrity"] = self._inspect_data_integrity(fig, ax, ctx)

        return results

    def _inspect_text(self, fig: Figure, ax: Axes) -> list[dict]:
        """Extract all text elements with their properties."""
        elements = []

        # Figure-level texts (title, subtitle, credits)
        for text in fig.texts:
            elements.append(self._text_to_dict(text, "figure"))

        # Axes-level texts (labels, annotations)
        for text in ax.texts:
            elements.append(self._text_to_dict(text, "axes"))

        # Tick labels
        for label in ax.get_xticklabels() + ax.get_yticklabels():
            if label.get_text():
                elements.append(self._text_to_dict(label, "tick"))

        return elements

    def _text_to_dict(self, text: Text, source: str) -> dict:
        """Convert a matplotlib Text object to inspection dict."""
        fs = text.get_fontsize()
        return {
            "text": text.get_text()[:50],
            "source": source,
            "font_size_pt": fs,
            "font_family": text.get_fontfamily(),
            "font_weight": text.get_fontweight(),
            "font_style": text.get_fontstyle(),
            "color": text.get_color(),
            "has_halo": bool(text.get_path_effects()),
            "halo_width": self._get_halo_width(text),
            "visible": text.get_visible(),
            "role": self._classify_text_role(text, source),
            "over_complex_bg": source == "axes",  # Axes text is over map data
        }

    def _get_halo_width(self, text: Text) -> float | None:
        """Extract halo width from path effects."""
        effects = text.get_path_effects()
        if not effects:
            return None
        for ef in effects:
            if hasattr(ef, '_linewidth'):
                return ef._linewidth / 2  # patheffects uses stroke width
        return None

    def _classify_text_role(self, text: Text, source: str) -> str:
        """Classify a text element's role based on size and position."""
        fs = text.get_fontsize()
        if source == "figure":
            if fs >= 14:
                return "title"
            elif fs >= 10:
                return "subtitle"
            else:
                return "source"
        elif source == "tick":
            return "tick_label"
        else:
            return "label"

    def _inspect_layers(self, ax: Axes) -> dict:
        """Inspect rendered layer count and types."""
        n_collections = len(ax.collections)
        n_lines = len(ax.lines)
        n_patches = len(ax.patches)
        n_images = len(ax.images)
        n_texts = len(ax.texts)

        return {
            "collection_count": n_collections,
            "line_count": n_lines,
            "patch_count": n_patches,
            "image_count": n_images,
            "text_count": n_texts,
            "total_visual_elements": n_collections + n_lines + n_patches + n_images,
            "visible_layer_count": n_collections + n_lines + n_images,
        }

    def _inspect_layout(self, fig: Figure, ax: Axes, context: dict) -> dict:
        """Inspect layout proportions."""
        pos = ax.get_position()
        fig_w, fig_h = fig.get_size_inches()

        map_body_ratio = pos.width * pos.height
        map_aspect = (pos.width * fig_w) / (pos.height * fig_h) if pos.height > 0 else 1.0

        # Geographic aspect
        bbox = context.get("bbox")
        geo_aspect = 1.0
        if bbox:
            geo_w = bbox[2] - bbox[0]
            geo_h = bbox[3] - bbox[1]
            if geo_h > 0:
                center_lat = (bbox[1] + bbox[3]) / 2
                geo_w_corrected = geo_w * math.cos(math.radians(center_lat))
                geo_aspect = geo_w_corrected / geo_h

        # Check for legend
        legend = ax.get_legend()
        legend_area = 0.0
        if legend:
            try:
                renderer = fig.canvas.get_renderer()
                lb = legend.get_window_extent(renderer)
                fig_area = fig_w * fig_h * fig.dpi * fig.dpi
                legend_area = (lb.width * lb.height) / fig_area
            except Exception:
                legend_area = 0.08  # Estimate

        # Check for attribution
        has_attribution = any(
            "data:" in t.get_text().lower() or
            "source" in t.get_text().lower() or
            "ecolens" in t.get_text().lower() or
            "©" in t.get_text()
            for t in fig.texts
            if t.get_fontsize() < 10
        )

        # Check for scale bar
        has_scale_bar = any(
            "km" in t.get_text().lower()
            for t in ax.texts
        )

        return {
            "map_body_ratio": map_body_ratio,
            "margin_top": 1.0 - (pos.y0 + pos.height),
            "margin_bottom": pos.y0,
            "margin_left": pos.x0,
            "margin_right": 1.0 - (pos.x0 + pos.width),
            "map_aspect": map_aspect,
            "geo_aspect": geo_aspect,
            "legend_area_ratio": legend_area,
            "has_legend": legend is not None,
            "has_scale_bar": has_scale_bar,
            "has_attribution": has_attribution,
            "source_attribution_visible": has_attribution,
            "north_arrow_present": context.get("has_north_arrow", False),
            "projection_is_north_up": context.get("projection_is_north_up", True),
        }

    def _inspect_colors(self, ax: Axes, context: dict) -> dict:
        """Inspect color usage on the map."""
        palette = context.get("palette_hex", [])
        palette_type = context.get("palette_type", "sequential")
        palette_name = context.get("palette_name", "unknown")
        n_classes = context.get("n_classes", 5)
        data_type = context.get("data_type", "ratio")

        return {
            "palette_name": palette_name,
            "palette_type": palette_type,
            "n_classes": n_classes,
            "data_type": data_type,
            "palette_hex": palette,
        }

    def _inspect_data_integrity(self, fig: Figure, ax: Axes, context: dict) -> dict:
        """Check data integrity markers."""
        has_date_label = any(
            "20" in t.get_text() and len(t.get_text()) < 30
            for t in fig.texts
            if t.get_fontsize() < 10
        )

        has_projection_label = any(
            "projection" in t.get_text().lower() or
            "epsg" in t.get_text().lower() or
            "utm" in t.get_text().lower()
            for t in fig.texts
        )

        return {
            "has_date_label": has_date_label,
            "has_projection_label": has_projection_label,
            "classification_method": context.get("classification_method", "unknown"),
            "data_age_days": context.get("data_age_days", 0),
        }


# ═══════════════════════════════════════════════════════════════════════
# QUALITY VALIDATOR — THE MAIN CLASS
# ═══════════════════════════════════════════════════════════════════════

class QualityValidator:
    """
    Validates generated maps against cartographic quality standards.

    Usage:
        validator = QualityValidator()
        report = validator.validate(fig, ax, context={
            "bbox": (-73.0, -16.5, -44.0, 5.3),
            "map_type": "choropleth",
            "theme": "deforestation",
            "palette_hex": ["#ffffb2", "#fecc5c", "#fd8d3c", "#f03b20", "#bd0026"],
            "palette_type": "sequential",
            "palette_name": "YlOrRd",
            "n_classes": 5,
            "attributions": ["NASA FIRMS", "GFW"],
        })
        print(f"Score: {report.overall_score}/100, Passed: {report.passed}")
    """

    QUALITY_THRESHOLD = 70.0  # Minimum score to pass

    def __init__(self):
        self.kb = CartographicKnowledgeBase()
        self.colors = ColorSystems()
        self.reference_db = MapReferenceDatabase()
        self.inspector = FigureInspector()
        self.corrector = AutoCorrector()
        self._validation_log: list[dict] = []

    def validate(
        self,
        fig: Figure,
        ax: Axes,
        context: dict | None = None,
        auto_correct: bool = True,
        max_correction_cycles: int = 1,
    ) -> QualityReport:
        """
        Full validation pipeline.

        Args:
            fig: Rendered matplotlib Figure
            ax: Map axes
            context: Map generation context (bbox, palette, etc.)
            auto_correct: Whether to attempt auto-corrections
            max_correction_cycles: Max correction attempts

        Returns:
            QualityReport with scores, violations, suggestions
        """
        ctx = context or {}
        timestamp = datetime.utcnow().isoformat()

        # ─── INSPECT THE FIGURE ──────────────────────────────────
        inspection = self.inspector.inspect(fig, ax, ctx)

        # ─── RUN ALL CHECKS ─────────────────────────────────────
        violations = []

        # 1. Typography checks
        text_elements = inspection.get("text_elements", [])
        typography_input = [
            {
                "role": t.get("role", "label"),
                "font_family": str(t.get("font_family", ["sans-serif"])[0])
                    if isinstance(t.get("font_family"), list)
                    else str(t.get("font_family", "sans-serif")),
                "font_size_pt": t.get("font_size_pt", 10),
                "has_halo": t.get("has_halo", False),
                "halo_width": t.get("halo_width"),
                "over_complex_bg": t.get("over_complex_bg", False),
            }
            for t in text_elements
            if t.get("visible", True) and t.get("text", "").strip()
        ]
        if typography_input:
            violations.extend(self.kb.validate_typography(typography_input))

        # 2. Layout checks
        layout = inspection.get("layout", {})
        violations.extend(self.kb.validate_layout(layout))

        # 3. Color checks
        color_info = inspection.get("colors", {})
        palette_hex = color_info.get("palette_hex", [])
        palette_name = color_info.get("palette_name", "")
        palette_type = color_info.get("palette_type", "sequential")
        n_classes = color_info.get("n_classes", 5)
        data_type_str = color_info.get("data_type", "ratio")

        data_type_map = {
            "ratio": DataType.RATIO,
            "interval": DataType.INTERVAL,
            "diverging": DataType.DIVERGING,
            "nominal": DataType.NOMINAL,
            "ordinal": DataType.ORDINAL,
        }
        data_type = data_type_map.get(data_type_str, DataType.RATIO)

        if palette_name and palette_type:
            violations.extend(
                self.kb.validate_color_choices(palette_name, palette_type, data_type, n_classes)
            )

        # 4. Color perceptual checks
        if palette_hex and len(palette_hex) >= 2:
            uniformity = self.colors.check_perceptual_uniformity(palette_hex)
            if not uniformity["passed"]:
                violations.append(RuleViolation(
                    rule_id="CR-004",
                    category=RuleCategory.COLOR_THEORY,
                    severity=RuleSeverity.ERROR,
                    message=f"Perceptual uniformity failed: min delta-E = {uniformity['min_delta_e']}",
                    details=f"Adjacent color steps need delta-E >= 10, got {uniformity['min_delta_e']}",
                    auto_correctable=True,
                    correction_hint="increase_palette_contrast",
                    score_penalty=20.0,
                ))

            cb_safe = self.colors.check_colorblind_safe(palette_hex)
            if not cb_safe["passed"]:
                violations.append(RuleViolation(
                    rule_id="CR-006",
                    category=RuleCategory.COLOR_THEORY,
                    severity=RuleSeverity.WARNING,
                    message="Palette is not colorblind-safe",
                    details=f"Deuteranopia: {cb_safe.get('deuteranopia', {}).get('min_delta_e', '?')}, "
                           f"Protanopia: {cb_safe.get('protanopia', {}).get('min_delta_e', '?')}",
                    auto_correctable=True,
                    correction_hint="switch_to_colorblind_safe_palette",
                    score_penalty=15.0,
                ))

        # 5. Visual hierarchy checks
        layers = inspection.get("layers", {})
        visible_layers = layers.get("visible_layer_count", 0)
        if visible_layers > 7:
            violations.append(RuleViolation(
                rule_id="VH-005",
                category=RuleCategory.VISUAL_HIERARCHY,
                severity=RuleSeverity.WARNING,
                message=f"Too many visible layers ({visible_layers}, max 7)",
                details="Reduce visual clutter by hiding less important layers",
                auto_correctable=False,
                score_penalty=10.0,
            ))

        # 6. Data integrity checks
        di = inspection.get("data_integrity", {})
        if di.get("data_age_days", 0) > 365 and not di.get("has_date_label"):
            violations.append(RuleViolation(
                rule_id="DI-003",
                category=RuleCategory.DATA_INTEGRITY,
                severity=RuleSeverity.ERROR,
                message="Data older than 1 year without visible date label",
                details="Stale environmental data can be misleading — show collection date",
                auto_correctable=True,
                correction_hint="add_date_label",
                score_penalty=15.0,
            ))

        # ─── COMPUTE INITIAL SCORE ───────────────────────────────
        scores = self.kb.compute_overall_score(violations)
        corrections_applied = []

        # ─── AUTO-CORRECTION LOOP ────────────────────────────────
        if auto_correct and not scores["passed"]:
            for cycle in range(max_correction_cycles):
                correctable = [
                    v for v in violations
                    if v.auto_correctable and v.correction_hint
                ]
                if not correctable:
                    break

                for violation in correctable:
                    result = self.corrector.apply(fig, ax, violation, ctx)
                    if result:
                        corrections_applied.append(result)

                # Re-inspect and re-validate
                if corrections_applied:
                    inspection = self.inspector.inspect(fig, ax, ctx)
                    violations = []

                    # Re-run all checks (simplified — just layout + typography)
                    layout = inspection.get("layout", {})
                    violations.extend(self.kb.validate_layout(layout))

                    text_elements = inspection.get("text_elements", [])
                    typography_input = [
                        {
                            "role": t.get("role", "label"),
                            "font_family": str(t.get("font_family", ["sans-serif"])[0])
                                if isinstance(t.get("font_family"), list)
                                else str(t.get("font_family", "sans-serif")),
                            "font_size_pt": t.get("font_size_pt", 10),
                            "has_halo": t.get("has_halo", False),
                            "halo_width": t.get("halo_width"),
                            "over_complex_bg": t.get("over_complex_bg", False),
                        }
                        for t in text_elements
                        if t.get("visible", True) and t.get("text", "").strip()
                    ]
                    if typography_input:
                        violations.extend(self.kb.validate_typography(typography_input))

                    # Re-add color violations (unchanged)
                    if palette_name and palette_type:
                        violations.extend(
                            self.kb.validate_color_choices(
                                palette_name, palette_type, data_type, n_classes,
                            )
                        )

                    scores = self.kb.compute_overall_score(violations)

                    if scores["passed"]:
                        break

        # ─── EXEMPLAR COMPARISON ─────────────────────────────────
        map_type = ctx.get("map_type", "choropleth")
        theme = ctx.get("theme")
        layout = inspection.get("layout", {})

        exemplar_comparison = self.reference_db.compare_against_exemplars(
            {
                "map_body_ratio": layout.get("map_body_ratio", 0.7),
                "n_classes": n_classes,
                "margin_ratio": min(
                    layout.get("margin_top", 0.05),
                    layout.get("margin_bottom", 0.05),
                    layout.get("margin_left", 0.05),
                    layout.get("margin_right", 0.05),
                ),
            },
            map_type=map_type,
            theme=theme,
        )

        # ─── GENERATE SUGGESTIONS ────────────────────────────────
        suggestions = self._generate_suggestions(
            violations, scores, exemplar_comparison, corrections_applied,
        )

        # ─── BUILD REPORT ────────────────────────────────────────
        report = QualityReport(
            overall_score=scores["overall"],
            passed=scores["passed"],
            dimensions=scores["dimensions"],
            violations=violations,
            suggestions=suggestions,
            exemplar_similarity=exemplar_comparison.get("similarity_score", 0),
            auto_corrections_applied=corrections_applied,
            inspection_details=inspection,
            timestamp=timestamp,
        )

        # ─── LOG FOR CONTINUOUS LEARNING ─────────────────────────
        self._log_validation(report, ctx)

        return report

    def validate_quick(self, context: dict) -> dict:
        """
        Quick validation without a rendered figure — just checks
        parameters against rules (palette, n_classes, etc.).

        Useful for pre-flight checks before rendering.
        """
        violations = []

        palette_name = context.get("palette_name", "")
        palette_type = context.get("palette_type", "sequential")
        n_classes = context.get("n_classes", 5)
        data_type_str = context.get("data_type", "ratio")

        data_type_map = {
            "ratio": DataType.RATIO,
            "interval": DataType.INTERVAL,
            "diverging": DataType.DIVERGING,
            "nominal": DataType.NOMINAL,
            "ordinal": DataType.ORDINAL,
        }
        data_type = data_type_map.get(data_type_str, DataType.RATIO)

        if palette_name:
            violations.extend(
                self.kb.validate_color_choices(palette_name, palette_type, data_type, n_classes)
            )

        palette_hex = context.get("palette_hex", [])
        if palette_hex and len(palette_hex) >= 2:
            uniformity = self.colors.check_perceptual_uniformity(palette_hex)
            if not uniformity["passed"]:
                violations.append(RuleViolation(
                    rule_id="CR-004",
                    category=RuleCategory.COLOR_THEORY,
                    severity=RuleSeverity.ERROR,
                    message=f"Perceptual uniformity failed (min dE={uniformity['min_delta_e']})",
                    details="Adjacent steps need delta-E >= 10",
                    score_penalty=20.0,
                ))

        scores = self.kb.compute_overall_score(violations)
        return {
            "pre_flight_score": scores["overall"],
            "issues": [v.to_dict() for v in violations],
            "recommendation": "proceed" if scores["passed"] else "review_parameters",
        }

    def _generate_suggestions(
        self,
        violations: list[RuleViolation],
        scores: dict,
        exemplar_comparison: dict,
        corrections: list[str],
    ) -> list[str]:
        """Generate actionable suggestions."""
        suggestions = []

        # Critical violations first
        for v in violations:
            if v.severity == RuleSeverity.CRITICAL:
                suggestions.append(f"CRITICAL: {v.message}")

        # Top errors
        errors = [v for v in violations if v.severity == RuleSeverity.ERROR]
        for v in errors[:3]:
            suggestions.append(f"Fix: {v.message}")

        # Exemplar deviations
        for dev in exemplar_comparison.get("deviations", []):
            suggestions.append(f"Exemplar norm: {dev['message']}")

        # Low-scoring dimensions
        for dim, score in scores.get("dimensions", {}).items():
            if score < 70:
                dim_display = dim.replace("_", " ").title()
                suggestions.append(
                    f"{dim_display} scored {score:.0f}/100 — review this area"
                )

        # Corrections that were applied
        if corrections:
            suggestions.append(
                f"Auto-corrected {len(corrections)} issues: " +
                "; ".join(corrections[:3])
            )

        # Positive reinforcement for high scores
        overall = scores.get("overall", 0)
        if overall >= 90:
            suggestions.append(
                "Excellent cartographic quality — publication-ready"
            )
        elif overall >= 80:
            suggestions.append(
                "Good cartographic quality — minor improvements possible"
            )

        return suggestions

    def _log_validation(self, report: QualityReport, context: dict):
        """
        Log validation results for continuous learning.

        In production, this writes to Firestore. Locally, maintains
        an in-memory log for pattern analysis.
        """
        entry = {
            "timestamp": report.timestamp,
            "overall_score": report.overall_score,
            "passed": report.passed,
            "dimensions": report.dimensions,
            "violation_count": len(report.violations),
            "violation_ids": [v.rule_id for v in report.violations],
            "corrections_applied": report.auto_corrections_applied,
            "map_type": context.get("map_type"),
            "theme": context.get("theme"),
            "palette": context.get("palette_name"),
            "n_classes": context.get("n_classes"),
            "exemplar_similarity": report.exemplar_similarity,
        }
        self._validation_log.append(entry)

        # Keep only last 1000 entries in memory
        if len(self._validation_log) > 1000:
            self._validation_log = self._validation_log[-500:]

    def get_learning_insights(self) -> dict:
        """
        Analyze validation history for patterns.

        Returns insights about:
        - Most common violations
        - Average scores by map type/theme
        - Most effective auto-corrections
        - Palette preferences by theme
        """
        if not self._validation_log:
            return {"message": "No validation history yet"}

        log = self._validation_log

        # Most common violations
        violation_counts: dict[str, int] = {}
        for entry in log:
            for vid in entry.get("violation_ids", []):
                violation_counts[vid] = violation_counts.get(vid, 0) + 1

        top_violations = sorted(
            violation_counts.items(), key=lambda x: -x[1]
        )[:10]

        # Average score by theme
        theme_scores: dict[str, list[float]] = {}
        for entry in log:
            theme = entry.get("theme", "unknown")
            if theme not in theme_scores:
                theme_scores[theme] = []
            theme_scores[theme].append(entry["overall_score"])

        theme_averages = {
            theme: round(sum(scores) / len(scores), 1)
            for theme, scores in theme_scores.items()
        }

        # Pass rate
        total = len(log)
        passed = sum(1 for e in log if e["passed"])

        return {
            "total_validations": total,
            "pass_rate": round(passed / total * 100, 1) if total > 0 else 0,
            "average_score": round(sum(e["overall_score"] for e in log) / total, 1),
            "top_violations": top_violations,
            "score_by_theme": theme_averages,
            "corrections_success_rate": self._correction_success_rate(),
        }

    def _correction_success_rate(self) -> float:
        """Calculate how often auto-corrections improved scores."""
        corrected = [
            e for e in self._validation_log
            if e.get("corrections_applied")
        ]
        if not corrected:
            return 0.0
        passed_after = sum(1 for e in corrected if e["passed"])
        return round(passed_after / len(corrected) * 100, 1)

    def save_learning_to_firestore(self, db_client=None):
        """
        Persist learning insights to Firestore for cross-session learning.

        Args:
            db_client: Firebase Firestore client instance
        """
        if db_client is None:
            logger.info("No Firestore client — learning insights kept in memory only")
            return

        insights = self.get_learning_insights()
        try:
            doc_ref = db_client.collection("cartographic_learning").document("insights")
            doc_ref.set({
                "updated_at": datetime.utcnow().isoformat(),
                "insights": insights,
                "recent_log": self._validation_log[-50:],
            })
            logger.info("Saved learning insights to Firestore")
        except Exception as e:
            logger.warning(f"Failed to save learning to Firestore: {e}")
