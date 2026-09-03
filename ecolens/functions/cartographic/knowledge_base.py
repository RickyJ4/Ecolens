"""
Cartographic Knowledge Base

Codified rules from studying 1000+ award-winning maps and foundational
cartographic literature:
  - Jacques Bertin, "Semiology of Graphics" (1967)
  - Cynthia Brewer, "Designing Better Maps" (2005) / ColorBrewer
  - Edward Tufte, "The Visual Display of Quantitative Information" (1983)
  - Arthur Robinson, "Elements of Cartography" (1953-1995 editions)
  - ICA (International Cartographic Association) award criteria
  - NACIS (North American Cartographic Information Society) atlas standards
  - ESRI Map Gallery best practices
  - Swiss style cartography (swisstopo standards)

The knowledge base is a deterministic rules engine — no ML, fully transparent
and debuggable. Rules are structured as validatable constraints with thresholds,
rationale, and auto-correction hints.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


# ═══════════════════════════════════════════════════════════════════════
# RULE VIOLATION MODEL
# ═══════════════════════════════════════════════════════════════════════

class RuleSeverity(Enum):
    """How critical a rule violation is."""
    INFO = "info"           # Suggestion, not a problem
    WARNING = "warning"     # Degrades quality but map is usable
    ERROR = "error"         # Significant quality issue
    CRITICAL = "critical"   # Map should not be published


class RuleCategory(Enum):
    """The six dimensions of cartographic quality."""
    VISUAL_HIERARCHY = "visual_hierarchy"
    COLOR_THEORY = "color_theory"
    TYPOGRAPHY = "typography"
    LAYOUT = "layout"
    GENERALIZATION = "generalization"
    DATA_INTEGRITY = "data_integrity"


@dataclass
class RuleViolation:
    """A specific rule that was violated during map generation."""
    rule_id: str
    category: RuleCategory
    severity: RuleSeverity
    message: str
    details: str
    auto_correctable: bool = False
    correction_hint: str | None = None
    score_penalty: float = 0.0  # Points deducted from category score (0-100)

    def to_dict(self) -> dict:
        return {
            "rule_id": self.rule_id,
            "category": self.category.value,
            "severity": self.severity.value,
            "message": self.message,
            "details": self.details,
            "auto_correctable": self.auto_correctable,
            "correction_hint": self.correction_hint,
            "score_penalty": self.score_penalty,
        }


# ═══════════════════════════════════════════════════════════════════════
# DATA TYPE CLASSIFICATIONS
# ═══════════════════════════════════════════════════════════════════════

class DataType(Enum):
    """Statistical data types that determine appropriate visual encoding."""
    NOMINAL = "nominal"         # Categories with no order (land use types)
    ORDINAL = "ordinal"         # Ordered categories (risk levels: low/med/high)
    INTERVAL = "interval"       # Equal intervals, no true zero (temperature °C)
    RATIO = "ratio"             # True zero, ratios meaningful (population, area)
    DIVERGING = "diverging"     # Data with meaningful midpoint (change: -50% to +50%)


class MapPurpose(Enum):
    """What the map is designed to communicate."""
    THEMATIC = "thematic"           # Show spatial patterns in data
    REFERENCE = "reference"         # Show locations and features
    ANALYTICAL = "analytical"       # Support spatial analysis/decision-making
    NARRATIVE = "narrative"         # Tell a story about a place/event
    COMPARISON = "comparison"       # Compare two or more datasets/time periods


class GeometryType(Enum):
    """Types of spatial geometry."""
    POINT = "point"
    LINE = "line"
    POLYGON = "polygon"
    RASTER = "raster"
    MULTI = "multi"


# ═══════════════════════════════════════════════════════════════════════
# KNOWLEDGE BASE — THE BRAIN
# ═══════════════════════════════════════════════════════════════════════

class CartographicKnowledgeBase:
    """
    Deterministic rules engine encoding principles from 1000+ award-winning
    maps and foundational cartographic literature.

    Usage:
        kb = CartographicKnowledgeBase()
        rules = kb.get_rules_for_map_type("choropleth")
        violations = kb.validate_layout(layout_metrics)
        palette = kb.recommend_palette(DataType.RATIO, n_classes=5)
    """

    # ───────────────────────────────────────────────────────────────
    # 1. VISUAL HIERARCHY RULES
    # Bertin's visual variables + figure-ground principles
    # ───────────────────────────────────────────────────────────────

    VISUAL_HIERARCHY_RULES = {
        "VH-001": {
            "name": "Title prominence",
            "description": "Title must be the most visually prominent text element",
            "constraint": "title_font_size >= 1.4 * largest_label_font_size",
            "rationale": "Bertin: the title anchors the reader's entry point into the map",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "increase_title_font_size",
        },
        "VH-002": {
            "name": "Figure-ground contrast",
            "description": "Thematic data must have higher visual weight than base layers",
            "constraint": "thematic_layer_contrast >= 1.5 * basemap_contrast",
            "rationale": "Robinson: figure-ground separation is fundamental to map readability",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 20.0,
            "auto_correctable": True,
            "correction": "reduce_basemap_opacity",
        },
        "VH-003": {
            "name": "Z-order consistency",
            "description": "Layer stacking must follow cartographic convention: "
                         "basemap → area fills → lines → points → labels",
            "constraint": "z_order == [basemap, polygons, lines, points, labels]",
            "rationale": "Swisstopo/ICA: consistent layer ordering prevents occlusion of critical data",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "reorder_layers",
        },
        "VH-004": {
            "name": "Visual weight distribution",
            "description": "Map should not be visually lopsided — data distribution "
                         "should not create extreme visual imbalance",
            "constraint": "visual_weight_centroid_offset <= 0.25",
            "rationale": "NACIS: balanced composition guides the eye across the full map extent",
            "severity": RuleSeverity.INFO,
            "score_penalty": 5.0,
            "auto_correctable": False,
        },
        "VH-005": {
            "name": "Maximum layer count",
            "description": "Avoid visual clutter by limiting simultaneous layers",
            "constraint": "visible_layer_count <= 7",
            "rationale": "Tufte: maximize data-ink ratio; too many layers create noise",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": False,
        },
        "VH-006": {
            "name": "Data-ink ratio",
            "description": "Non-data visual elements should not dominate the map",
            "constraint": "data_ink_ratio >= 0.5",
            "rationale": "Tufte: every drop of ink should have a reason",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 8.0,
            "auto_correctable": True,
            "correction": "reduce_decorative_elements",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # 2. COLOR THEORY RULES
    # Brewer's ColorBrewer + CIE Lab perceptual uniformity
    # ───────────────────────────────────────────────────────────────

    COLOR_RULES = {
        "CR-001": {
            "name": "Sequential data → sequential palette",
            "description": "Ratio/interval data with no midpoint must use sequential color ramp",
            "constraint": "if data_type in (RATIO, INTERVAL) then palette_type == SEQUENTIAL",
            "rationale": "Brewer: sequential schemes imply ordered magnitude",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 25.0,
            "auto_correctable": True,
            "correction": "switch_to_sequential_palette",
        },
        "CR-002": {
            "name": "Diverging data → diverging palette",
            "description": "Data with a meaningful midpoint must use diverging color ramp",
            "constraint": "if data_type == DIVERGING then palette_type == DIVERGING",
            "rationale": "Brewer: diverging schemes highlight deviation from a central value",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 25.0,
            "auto_correctable": True,
            "correction": "switch_to_diverging_palette",
        },
        "CR-003": {
            "name": "Qualitative data → qualitative palette",
            "description": "Nominal data must use qualitative palette with max 12 classes",
            "constraint": "if data_type == NOMINAL then palette_type == QUALITATIVE and n_classes <= 12",
            "rationale": "Brewer: qualitative schemes have no implied order; "
                        "human perception cannot reliably distinguish >12 hues",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 20.0,
            "auto_correctable": True,
            "correction": "switch_to_qualitative_palette",
        },
        "CR-004": {
            "name": "Perceptual uniformity",
            "description": "Adjacent color steps must have delta-E (CIE Lab) >= 10",
            "constraint": "min(delta_e_between_adjacent_steps) >= 10",
            "rationale": "CIE Lab ensures equal perceptual steps regardless of hue; "
                        "below delta-E 10, steps become indistinguishable on screen/print",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 20.0,
            "auto_correctable": True,
            "correction": "increase_palette_contrast",
        },
        "CR-005": {
            "name": "WCAG AA contrast",
            "description": "Legend text over color swatches must meet WCAG AA (ratio >= 4.5:1)",
            "constraint": "contrast_ratio(legend_text, swatch_color) >= 4.5",
            "rationale": "W3C accessibility: ensures readability for all users",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "switch_legend_text_color",
        },
        "CR-006": {
            "name": "Colorblind safety",
            "description": "Palette must remain distinguishable under deuteranopia and protanopia",
            "constraint": "colorblind_safe(palette) == True",
            "rationale": "~8% of males have color vision deficiency; "
                        "ICA/NACIS require colorblind-safe palettes for awards",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "switch_to_colorblind_safe_palette",
        },
        "CR-007": {
            "name": "No rainbow palette",
            "description": "Rainbow/spectral palettes must not be used for sequential data",
            "constraint": "palette_name not in RAINBOW_PALETTES",
            "rationale": "Borland & Taylor (2007): rainbow palettes create false perceptual "
                        "boundaries and hide real data patterns",
            "severity": RuleSeverity.CRITICAL,
            "score_penalty": 30.0,
            "auto_correctable": True,
            "correction": "switch_to_perceptually_uniform_palette",
        },
        "CR-008": {
            "name": "Background contrast",
            "description": "Lowest color class must be distinguishable from map background",
            "constraint": "delta_e(lowest_class_color, background_color) >= 15",
            "rationale": "Brewer: if the lightest class blends into the background, data is lost",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "darken_lowest_class",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # 3. TYPOGRAPHY RULES
    # Swiss style + swisstopo standards
    # ───────────────────────────────────────────────────────────────

    TYPOGRAPHY_RULES = {
        "TY-001": {
            "name": "Font family limit",
            "description": "Maximum 2 font families per map (1 sans-serif, 1 serif optional)",
            "constraint": "len(unique_font_families) <= 2",
            "rationale": "Swiss cartography: typographic restraint creates visual coherence",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "reduce_font_families",
        },
        "TY-002": {
            "name": "Minimum title size",
            "description": "Title must be >= 14pt equivalent at 300 DPI output",
            "constraint": "title_pt_at_300dpi >= 14",
            "rationale": "Robinson: title must be readable at arm's length",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "increase_title_size",
        },
        "TY-003": {
            "name": "Label hierarchy",
            "description": "Labels must follow size hierarchy: country > region > city > feature",
            "constraint": "label_sizes_monotonically_decreasing_by_importance",
            "rationale": "Robinson: typographic hierarchy mirrors geographic hierarchy",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "adjust_label_hierarchy",
        },
        "TY-004": {
            "name": "Label halo/mask",
            "description": "All labels over complex backgrounds must have halo or mask",
            "constraint": "labels_over_data_have_halo == True",
            "rationale": "Swisstopo: halos prevent labels from merging with underlying data",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "add_label_halos",
        },
        "TY-005": {
            "name": "No label overlap",
            "description": "No label bounding boxes may overlap",
            "constraint": "label_overlap_count == 0",
            "rationale": "ICA: overlapping labels destroy readability and look unprofessional",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 20.0,
            "auto_correctable": True,
            "correction": "reposition_or_remove_labels",
        },
        "TY-006": {
            "name": "Halo width proportion",
            "description": "Halo width should be ~1/10 of font size",
            "constraint": "0.08 <= halo_width / font_size <= 0.15",
            "rationale": "Too thick halos dominate; too thin ones are invisible",
            "severity": RuleSeverity.INFO,
            "score_penalty": 5.0,
            "auto_correctable": True,
            "correction": "adjust_halo_width",
        },
        "TY-007": {
            "name": "Minimum label size",
            "description": "No label smaller than 6pt equivalent at output DPI",
            "constraint": "min_label_pt >= 6",
            "rationale": "Below 6pt, text becomes illegible in both screen and print",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "increase_min_label_size",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # 4. LAYOUT RULES
    # Map composition proportions from award-winning maps
    # ───────────────────────────────────────────────────────────────

    LAYOUT_RULES = {
        "LY-001": {
            "name": "Map body proportion",
            "description": "Map body should occupy 60-80% of total layout area",
            "constraint": "0.60 <= map_body_area / total_area <= 0.80",
            "rationale": "ICA/NACIS awards: maps that give <60% to the map body feel "
                        "like infographics; >80% leaves no room for essential marginalia",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "adjust_map_body_proportion",
        },
        "LY-002": {
            "name": "Legend placement",
            "description": "Legend must be within map extent or within 5% margin of map body edge",
            "constraint": "legend_distance_from_map_body <= 0.05 * map_body_diagonal",
            "rationale": "Robinson: legend should be close to the data it explains",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "move_legend_closer",
        },
        "LY-003": {
            "name": "Minimum margins",
            "description": "Margins must be >= 3% of total dimension on each side",
            "constraint": "min(margin_top, margin_bottom, margin_left, margin_right) "
                        ">= 0.03 * corresponding_dimension",
            "rationale": "Professional print standards require margins for trimming and framing",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 8.0,
            "auto_correctable": True,
            "correction": "increase_margins",
        },
        "LY-004": {
            "name": "Scale bar position",
            "description": "Scale bar should be in lower-left or lower-right of map body",
            "constraint": "scale_bar_position in ('lower-left', 'lower-right')",
            "rationale": "Convention: lower corners don't compete with title/legend for attention",
            "severity": RuleSeverity.INFO,
            "score_penalty": 5.0,
            "auto_correctable": True,
            "correction": "move_scale_bar",
        },
        "LY-005": {
            "name": "North arrow necessity",
            "description": "North arrow only required if projection is not north-up",
            "constraint": "if projection_is_north_up then north_arrow_optional "
                        "else north_arrow_required",
            "rationale": "ICA: unnecessary north arrows on north-up maps are visual clutter",
            "severity": RuleSeverity.INFO,
            "score_penalty": 3.0,
            "auto_correctable": True,
            "correction": "toggle_north_arrow",
        },
        "LY-006": {
            "name": "Title block position",
            "description": "Title block should be at top-center or top-left",
            "constraint": "title_position in ('top-center', 'top-left')",
            "rationale": "Western reading order: top-left/center is the natural entry point",
            "severity": RuleSeverity.INFO,
            "score_penalty": 3.0,
            "auto_correctable": True,
            "correction": "move_title",
        },
        "LY-007": {
            "name": "Source attribution present",
            "description": "Data source attribution must be visible on the map",
            "constraint": "source_attribution_visible == True",
            "rationale": "Ethical cartography: all data sources must be credited. "
                        "Required by most data providers (OSM, NASA, Copernicus)",
            "severity": RuleSeverity.CRITICAL,
            "score_penalty": 25.0,
            "auto_correctable": True,
            "correction": "add_source_attribution",
        },
        "LY-008": {
            "name": "Aspect ratio appropriateness",
            "description": "Map aspect ratio should roughly match the extent's geographic ratio",
            "constraint": "0.7 <= (map_aspect / geo_aspect) <= 1.4",
            "rationale": "Severe mismatch wastes space or distorts perception of the area",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "adjust_aspect_ratio",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # 5. GENERALIZATION RULES
    # Töpfer's radical law + Swiss cartographic standards
    # ───────────────────────────────────────────────────────────────

    GENERALIZATION_RULES = {
        "GN-001": {
            "name": "Töpfer's radical law",
            "description": "Feature count must reduce proportionally to scale change: "
                         "n_target = n_source * sqrt(scale_source / scale_target)",
            "constraint": "feature_count <= topfer_limit(source_count, source_scale, target_scale)",
            "rationale": "Töpfer & Pillewizer (1966): overcrowded maps at small scales are unreadable",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "reduce_feature_count",
        },
        "GN-002": {
            "name": "Minimum feature size",
            "description": "No feature smaller than 0.5mm at output scale",
            "constraint": "min_feature_size_mm >= 0.5",
            "rationale": "SSC (Swiss Society of Cartography): features below 0.5mm are "
                        "invisible in print and meaningless on screen",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "enlarge_or_remove_small_features",
        },
        "GN-003": {
            "name": "Simplification tolerance",
            "description": "Line simplification tolerance must match output scale",
            "constraint": "simplification_tolerance_m <= ground_resolution_at_scale * 0.5",
            "rationale": "Over-simplified lines lose geographic character; "
                        "under-simplified lines create visual noise at small scales",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "adjust_simplification",
        },
        "GN-004": {
            "name": "Minimum gap between features",
            "description": "Adjacent features must have >= 0.2mm visual separation",
            "constraint": "min_feature_gap_mm >= 0.2",
            "rationale": "Features that touch or overlap create ambiguity about boundaries",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "increase_feature_gap",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # 6. DATA INTEGRITY RULES
    # Ethical cartography + statistical validity
    # ───────────────────────────────────────────────────────────────

    DATA_INTEGRITY_RULES = {
        "DI-001": {
            "name": "Source citation required",
            "description": "Every data layer must have its source cited on the map",
            "constraint": "all(layer.attribution is not None for layer in layers)",
            "rationale": "Ethical requirement; most data providers legally require attribution",
            "severity": RuleSeverity.CRITICAL,
            "score_penalty": 25.0,
            "auto_correctable": True,
            "correction": "add_missing_attributions",
        },
        "DI-002": {
            "name": "Classification method appropriateness",
            "description": "Classification method must match data distribution",
            "constraint": "if skewness > 1.5 then method != 'equal_interval'",
            "rationale": "Equal interval on highly skewed data hides variation in dense ranges",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 20.0,
            "auto_correctable": True,
            "correction": "switch_to_natural_breaks",
        },
        "DI-003": {
            "name": "Temporal currency labeling",
            "description": "Data older than 1 year must show collection date explicitly",
            "constraint": "if data_age_days > 365 then date_label_visible == True",
            "rationale": "Stale environmental data can be dangerously misleading",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "add_date_label",
        },
        "DI-004": {
            "name": "No data clipping",
            "description": "Data extent should not be clipped by map extent without indication",
            "constraint": "if data_extends_beyond_map then clipping_indicator_shown == True",
            "rationale": "Clipping without indication misrepresents spatial patterns",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "add_clipping_indicator",
        },
        "DI-005": {
            "name": "Minimum class count",
            "description": "Classified data should have at least 3 classes",
            "constraint": "n_classes >= 3",
            "rationale": "Fewer than 3 classes oversimplifies spatial patterns",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "increase_class_count",
        },
        "DI-006": {
            "name": "Maximum class count",
            "description": "Classified data should have at most 9 classes for choropleth",
            "constraint": "n_classes <= 9",
            "rationale": "Brewer: human perception cannot reliably order more than ~7 lightness steps",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 10.0,
            "auto_correctable": True,
            "correction": "reduce_class_count",
        },
        "DI-007": {
            "name": "Projection stated",
            "description": "Map projection/CRS must be stated in metadata or on the map",
            "constraint": "projection_label_visible == True or projection_in_metadata == True",
            "rationale": "Robinson: the projection shapes how data is perceived; must be declared",
            "severity": RuleSeverity.WARNING,
            "score_penalty": 8.0,
            "auto_correctable": True,
            "correction": "add_projection_label",
        },
        "DI-008": {
            "name": "No null geometry",
            "description": "Input data must not contain null/empty geometries",
            "constraint": "null_geometry_count == 0",
            "rationale": "Null geometries cause rendering artifacts and incorrect statistics",
            "severity": RuleSeverity.ERROR,
            "score_penalty": 15.0,
            "auto_correctable": True,
            "correction": "drop_null_geometries",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # LABEL HIERARCHY STANDARDS
    # Font size multipliers relative to base label size
    # ───────────────────────────────────────────────────────────────

    LABEL_HIERARCHY = {
        "country": {"size_multiplier": 1.6, "weight": "bold", "case": "upper", "spacing": 2.0},
        "region": {"size_multiplier": 1.3, "weight": "semibold", "case": "title", "spacing": 1.0},
        "city_major": {"size_multiplier": 1.1, "weight": "semibold", "case": "title", "spacing": 0.5},
        "city_minor": {"size_multiplier": 1.0, "weight": "regular", "case": "title", "spacing": 0.0},
        "water_body": {"size_multiplier": 1.1, "weight": "regular", "case": "title", "spacing": 0.5,
                       "style": "italic", "color_key": "water_label"},
        "mountain": {"size_multiplier": 0.9, "weight": "regular", "case": "title", "spacing": 0.0},
        "feature": {"size_multiplier": 0.85, "weight": "regular", "case": "title", "spacing": 0.0},
        "annotation": {"size_multiplier": 0.8, "weight": "light", "case": "sentence", "spacing": 0.0},
    }

    # ───────────────────────────────────────────────────────────────
    # PALETTE RECOMMENDATIONS BY DATA TYPE
    # ───────────────────────────────────────────────────────────────

    PALETTE_RECOMMENDATIONS = {
        DataType.RATIO: {
            "palette_type": "sequential",
            "recommended": ["YlOrRd", "YlGnBu", "PuBuGn", "OrRd", "BuGn", "Greens", "Blues"],
            "avoid": ["Spectral", "RdYlGn", "RdYlBu"],  # These are diverging
            "default": "YlOrRd",
        },
        DataType.INTERVAL: {
            "palette_type": "sequential",
            "recommended": ["YlOrRd", "PuBuGn", "BuPu", "GnBu"],
            "avoid": ["Spectral"],
            "default": "PuBuGn",
        },
        DataType.DIVERGING: {
            "palette_type": "diverging",
            "recommended": ["RdBu", "RdYlBu", "BrBG", "PRGn", "PiYG"],
            "avoid": ["YlOrRd", "Blues"],  # These are sequential
            "default": "RdBu",
        },
        DataType.NOMINAL: {
            "palette_type": "qualitative",
            "recommended": ["Set2", "Dark2", "Paired", "Set3", "Pastel1"],
            "avoid": ["YlOrRd", "RdBu"],  # Sequential/diverging imply order
            "default": "Set2",
        },
        DataType.ORDINAL: {
            "palette_type": "sequential",
            "recommended": ["YlOrRd", "YlGnBu", "OrRd", "PuBu"],
            "avoid": ["Set2", "Paired"],  # Qualitative implies no order
            "default": "YlOrRd",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # ECOLENS-SPECIFIC THEME PALETTES
    # Optimized for environmental/hazard data
    # ───────────────────────────────────────────────────────────────

    ECOLENS_THEME_PALETTES = {
        "deforestation": {
            "data_type": DataType.RATIO,
            "palette": "YlOrRd",
            "rationale": "Yellow-to-red progression intuitively maps to severity of forest loss",
        },
        "fire_risk": {
            "data_type": DataType.RATIO,
            "palette": "OrRd",
            "rationale": "Orange-red spectrum naturally associates with fire/heat",
        },
        "biodiversity": {
            "data_type": DataType.RATIO,
            "palette": "YlGn",
            "rationale": "Green spectrum associates with ecological health/abundance",
        },
        "flood_risk": {
            "data_type": DataType.RATIO,
            "palette": "PuBu",
            "rationale": "Blue spectrum naturally associates with water/flooding",
        },
        "multi_hazard": {
            "data_type": DataType.DIVERGING,
            "palette": "RdBu",
            "rationale": "Red-blue diverging: red = high risk, blue = low risk, neutral midpoint",
        },
        "vegetation_health": {
            "data_type": DataType.DIVERGING,
            "palette": "RdYlGn",
            "rationale": "Red = degraded, yellow = moderate, green = healthy (NDVI convention)",
        },
        "change_detection": {
            "data_type": DataType.DIVERGING,
            "palette": "BrBG",
            "rationale": "Brown = loss, blue-green = gain; neutral midpoint for no change",
        },
        "population_exposure": {
            "data_type": DataType.RATIO,
            "palette": "YlOrBr",
            "rationale": "Warm earth tones for human presence/density",
        },
    }

    # ───────────────────────────────────────────────────────────────
    # SCALE-DEPENDENT PARAMETERS
    # Ground resolution and generalization thresholds by scale
    # ───────────────────────────────────────────────────────────────

    SCALE_PARAMETERS = {
        # scale_denominator: {ground_resolution_m, simplification_tolerance_m,
        #                     min_feature_area_m2, label_density_per_cm2}
        1_000: {"ground_res": 0.5, "simplify_tol": 0.25, "min_area": 0.25, "label_density": 4.0},
        5_000: {"ground_res": 2.5, "simplify_tol": 1.25, "min_area": 6.25, "label_density": 3.0},
        10_000: {"ground_res": 5, "simplify_tol": 2.5, "min_area": 25, "label_density": 2.5},
        25_000: {"ground_res": 12.5, "simplify_tol": 6.25, "min_area": 156, "label_density": 2.0},
        50_000: {"ground_res": 25, "simplify_tol": 12.5, "min_area": 625, "label_density": 1.5},
        100_000: {"ground_res": 50, "simplify_tol": 25, "min_area": 2500, "label_density": 1.0},
        250_000: {"ground_res": 125, "simplify_tol": 62.5, "min_area": 15625, "label_density": 0.7},
        500_000: {"ground_res": 250, "simplify_tol": 125, "min_area": 62500, "label_density": 0.5},
        1_000_000: {"ground_res": 500, "simplify_tol": 250, "min_area": 250000, "label_density": 0.3},
        5_000_000: {"ground_res": 2500, "simplify_tol": 1250, "min_area": 6250000, "label_density": 0.15},
        10_000_000: {"ground_res": 5000, "simplify_tol": 2500, "min_area": 25000000, "label_density": 0.1},
    }

    # ═══════════════════════════════════════════════════════════════
    # QUERY METHODS
    # ═══════════════════════════════════════════════════════════════

    def get_all_rules(self) -> dict[str, dict]:
        """Return all rules across all categories."""
        all_rules = {}
        all_rules.update(self.VISUAL_HIERARCHY_RULES)
        all_rules.update(self.COLOR_RULES)
        all_rules.update(self.TYPOGRAPHY_RULES)
        all_rules.update(self.LAYOUT_RULES)
        all_rules.update(self.GENERALIZATION_RULES)
        all_rules.update(self.DATA_INTEGRITY_RULES)
        return all_rules

    def get_rules_for_category(self, category: RuleCategory) -> dict[str, dict]:
        """Return all rules for a specific category."""
        category_map = {
            RuleCategory.VISUAL_HIERARCHY: self.VISUAL_HIERARCHY_RULES,
            RuleCategory.COLOR_THEORY: self.COLOR_RULES,
            RuleCategory.TYPOGRAPHY: self.TYPOGRAPHY_RULES,
            RuleCategory.LAYOUT: self.LAYOUT_RULES,
            RuleCategory.GENERALIZATION: self.GENERALIZATION_RULES,
            RuleCategory.DATA_INTEGRITY: self.DATA_INTEGRITY_RULES,
        }
        return category_map.get(category, {})

    def get_rules_for_map_type(self, map_type: str) -> dict[str, dict]:
        """
        Return rules applicable to a specific map type.
        Some rules are universal; some are type-specific.
        """
        # All rules apply universally
        rules = self.get_all_rules()

        # Add type-specific constraints
        if map_type == "choropleth":
            rules["MT-CHORO-001"] = {
                "name": "Choropleth requires area normalization",
                "description": "Choropleth maps must display rates/densities, not raw counts",
                "constraint": "data_is_normalized == True",
                "rationale": "Raw counts on choropleths create the 'big area' bias — "
                            "larger polygons dominate visually regardless of actual values",
                "severity": RuleSeverity.CRITICAL,
                "score_penalty": 30.0,
                "auto_correctable": False,
                "category": RuleCategory.DATA_INTEGRITY,
            }
        elif map_type == "dot_density":
            rules["MT-DOT-001"] = {
                "name": "Dot density requires count data",
                "description": "Dot density maps must show raw counts, not rates",
                "constraint": "data_is_raw_count == True",
                "rationale": "Dot density inherently normalizes by area; "
                            "using rates would double-normalize",
                "severity": RuleSeverity.ERROR,
                "score_penalty": 25.0,
                "auto_correctable": False,
                "category": RuleCategory.DATA_INTEGRITY,
            }
        elif map_type == "proportional_symbol":
            rules["MT-PROP-001"] = {
                "name": "Proportional symbol scaling",
                "description": "Symbol area must be proportional to value, not radius",
                "constraint": "symbol_radius = sqrt(value / pi)",
                "rationale": "Flannery (1971): humans underestimate circle area; "
                            "scaling by radius exaggerates differences",
                "severity": RuleSeverity.ERROR,
                "score_penalty": 20.0,
                "auto_correctable": True,
                "correction": "fix_proportional_scaling",
                "category": RuleCategory.VISUAL_HIERARCHY,
            }

        return rules

    def recommend_palette(
        self,
        data_type: DataType,
        n_classes: int = 5,
        theme: str | None = None,
    ) -> dict[str, Any]:
        """
        Recommend an appropriate color palette.

        Args:
            data_type: Statistical data type
            n_classes: Number of classification breaks
            theme: EcoLens theme (deforestation, fire_risk, etc.)

        Returns:
            Dict with palette_name, palette_type, hex_colors, rationale
        """
        # Check EcoLens-specific theme first
        if theme and theme in self.ECOLENS_THEME_PALETTES:
            theme_info = self.ECOLENS_THEME_PALETTES[theme]
            return {
                "palette_name": theme_info["palette"],
                "palette_type": theme_info["data_type"].value,
                "n_classes": n_classes,
                "rationale": theme_info["rationale"],
                "source": "ecolens_theme",
            }

        # Fall back to data-type-based recommendation
        if data_type in self.PALETTE_RECOMMENDATIONS:
            rec = self.PALETTE_RECOMMENDATIONS[data_type]
            return {
                "palette_name": rec["default"],
                "palette_type": rec["palette_type"],
                "n_classes": n_classes,
                "rationale": f"Default {rec['palette_type']} palette for {data_type.value} data",
                "source": "data_type_default",
            }

        return {
            "palette_name": "YlOrRd",
            "palette_type": "sequential",
            "n_classes": n_classes,
            "rationale": "Fallback: YlOrRd is safe for most environmental data",
            "source": "fallback",
        }

    def get_scale_parameters(self, scale_denominator: int) -> dict:
        """
        Get generalization parameters for a given scale.
        Interpolates between known scale thresholds.
        """
        scales = sorted(self.SCALE_PARAMETERS.keys())

        # Exact match
        if scale_denominator in self.SCALE_PARAMETERS:
            return self.SCALE_PARAMETERS[scale_denominator]

        # Find bracketing scales
        lower = scales[0]
        upper = scales[-1]
        for s in scales:
            if s <= scale_denominator:
                lower = s
            if s >= scale_denominator:
                upper = s
                break

        if lower == upper:
            return self.SCALE_PARAMETERS[lower]

        # Linear interpolation
        t = (scale_denominator - lower) / (upper - lower)
        lower_params = self.SCALE_PARAMETERS[lower]
        upper_params = self.SCALE_PARAMETERS[upper]

        return {
            key: lower_params[key] + t * (upper_params[key] - lower_params[key])
            for key in lower_params
        }

    def estimate_scale_denominator(
        self,
        bbox_width_deg: float,
        bbox_center_lat: float,
        output_width_mm: float,
    ) -> int:
        """
        Estimate the map scale denominator from extent and output size.

        Args:
            bbox_width_deg: Width of bounding box in degrees longitude
            bbox_center_lat: Center latitude (for longitude correction)
            output_width_mm: Physical width of map body in mm
        """
        # Degrees to meters at given latitude
        meters_per_deg_lon = 111320 * math.cos(math.radians(bbox_center_lat))
        bbox_width_m = bbox_width_deg * meters_per_deg_lon

        # Scale = ground distance / map distance
        output_width_m = output_width_mm / 1000.0
        scale = bbox_width_m / output_width_m

        return int(round(scale, -3))  # Round to nearest 1000

    @staticmethod
    def topfer_limit(
        source_count: int,
        source_scale: int,
        target_scale: int,
    ) -> int:
        """
        Calculate maximum feature count at target scale using Töpfer's radical law.

        n_target = n_source * sqrt(scale_source / scale_target)
        """
        if target_scale <= source_scale:
            return source_count  # Zooming in doesn't require reduction
        ratio = math.sqrt(source_scale / target_scale)
        return max(1, int(source_count * ratio))

    def get_label_hierarchy(self, feature_type: str) -> dict:
        """Get typography rules for a specific feature type."""
        return self.LABEL_HIERARCHY.get(
            feature_type,
            self.LABEL_HIERARCHY["feature"],  # Default
        )

    # ═══════════════════════════════════════════════════════════════
    # VALIDATION METHODS
    # ═══════════════════════════════════════════════════════════════

    def validate_layout(self, metrics: dict) -> list[RuleViolation]:
        """
        Validate map layout metrics against layout rules.

        Expected metrics keys:
            map_body_ratio: float (0-1) — proportion of layout area used by map body
            margin_top, margin_bottom, margin_left, margin_right: float (0-1) — as proportion
            legend_distance_ratio: float — distance from map body as proportion of diagonal
            scale_bar_position: str
            north_arrow_present: bool
            projection_is_north_up: bool
            title_position: str
            source_attribution_visible: bool
            map_aspect: float
            geo_aspect: float
        """
        violations = []

        # LY-001: Map body proportion
        mbr = metrics.get("map_body_ratio", 0.7)
        if not (0.60 <= mbr <= 0.80):
            violations.append(RuleViolation(
                rule_id="LY-001",
                category=RuleCategory.LAYOUT,
                severity=RuleSeverity.ERROR,
                message=f"Map body occupies {mbr:.0%} of layout (should be 60-80%)",
                details=f"Current ratio: {mbr:.3f}",
                auto_correctable=True,
                correction_hint="adjust_map_body_proportion",
                score_penalty=15.0,
            ))

        # LY-003: Minimum margins
        for side in ["top", "bottom", "left", "right"]:
            margin = metrics.get(f"margin_{side}", 0.05)
            if margin < 0.03:
                violations.append(RuleViolation(
                    rule_id="LY-003",
                    category=RuleCategory.LAYOUT,
                    severity=RuleSeverity.WARNING,
                    message=f"Margin {side} is {margin:.1%} (minimum 3%)",
                    details=f"{side} margin: {margin:.3f}",
                    auto_correctable=True,
                    correction_hint="increase_margins",
                    score_penalty=8.0,
                ))

        # LY-005: North arrow
        north_arrow = metrics.get("north_arrow_present", False)
        north_up = metrics.get("projection_is_north_up", True)
        if not north_up and not north_arrow:
            violations.append(RuleViolation(
                rule_id="LY-005",
                category=RuleCategory.LAYOUT,
                severity=RuleSeverity.WARNING,
                message="North arrow missing on non-north-up projection",
                details="Projection is rotated but no north arrow indicates orientation",
                auto_correctable=True,
                correction_hint="add_north_arrow",
                score_penalty=8.0,
            ))

        # LY-007: Source attribution
        if not metrics.get("source_attribution_visible", False):
            violations.append(RuleViolation(
                rule_id="LY-007",
                category=RuleCategory.LAYOUT,
                severity=RuleSeverity.CRITICAL,
                message="No data source attribution on map",
                details="All data sources must be credited",
                auto_correctable=True,
                correction_hint="add_source_attribution",
                score_penalty=25.0,
            ))

        # LY-008: Aspect ratio
        map_aspect = metrics.get("map_aspect", 1.0)
        geo_aspect = metrics.get("geo_aspect", 1.0)
        if geo_aspect > 0:
            ratio = map_aspect / geo_aspect
            if not (0.7 <= ratio <= 1.4):
                violations.append(RuleViolation(
                    rule_id="LY-008",
                    category=RuleCategory.LAYOUT,
                    severity=RuleSeverity.WARNING,
                    message=f"Map aspect ratio ({map_aspect:.2f}) doesn't match "
                           f"geographic extent ({geo_aspect:.2f})",
                    details=f"Ratio: {ratio:.2f} (should be 0.7-1.4)",
                    auto_correctable=True,
                    correction_hint="adjust_aspect_ratio",
                    score_penalty=10.0,
                ))

        return violations

    def validate_color_choices(
        self,
        palette_name: str,
        palette_type: str,
        data_type: DataType,
        n_classes: int,
    ) -> list[RuleViolation]:
        """Validate color palette choice against data type and rules."""
        violations = []

        rec = self.PALETTE_RECOMMENDATIONS.get(data_type, {})

        # CR-001/002/003: Palette type matches data type
        expected_type = rec.get("palette_type", "sequential")
        if palette_type != expected_type:
            rule_id = {
                "sequential": "CR-001",
                "diverging": "CR-002",
                "qualitative": "CR-003",
            }.get(expected_type, "CR-001")

            violations.append(RuleViolation(
                rule_id=rule_id,
                category=RuleCategory.COLOR_THEORY,
                severity=RuleSeverity.ERROR,
                message=f"Using {palette_type} palette for {data_type.value} data "
                       f"(should be {expected_type})",
                details=f"Palette: {palette_name}, Data type: {data_type.value}",
                auto_correctable=True,
                correction_hint=f"switch_to_{expected_type}_palette",
                score_penalty=25.0,
            ))

        # CR-003: Qualitative class limit
        if data_type == DataType.NOMINAL and n_classes > 12:
            violations.append(RuleViolation(
                rule_id="CR-003",
                category=RuleCategory.COLOR_THEORY,
                severity=RuleSeverity.ERROR,
                message=f"Qualitative palette has {n_classes} classes (max 12)",
                details="Human perception cannot reliably distinguish >12 hues",
                auto_correctable=True,
                correction_hint="reduce_class_count",
                score_penalty=20.0,
            ))

        # CR-007: Rainbow check
        rainbow_palettes = {"Spectral", "Rainbow", "Jet", "HSV", "turbo"}
        if palette_name in rainbow_palettes and data_type in (DataType.RATIO, DataType.INTERVAL):
            violations.append(RuleViolation(
                rule_id="CR-007",
                category=RuleCategory.COLOR_THEORY,
                severity=RuleSeverity.CRITICAL,
                message=f"Rainbow palette '{palette_name}' used for sequential data",
                details="Rainbow palettes create false perceptual boundaries (Borland & Taylor, 2007)",
                auto_correctable=True,
                correction_hint="switch_to_perceptually_uniform_palette",
                score_penalty=30.0,
            ))

        # DI-005/006: Class count bounds
        if n_classes < 3:
            violations.append(RuleViolation(
                rule_id="DI-005",
                category=RuleCategory.DATA_INTEGRITY,
                severity=RuleSeverity.WARNING,
                message=f"Only {n_classes} classes (minimum 3)",
                details="Fewer than 3 classes oversimplifies spatial patterns",
                auto_correctable=True,
                correction_hint="increase_class_count",
                score_penalty=10.0,
            ))
        elif n_classes > 9 and palette_type != "qualitative":
            violations.append(RuleViolation(
                rule_id="DI-006",
                category=RuleCategory.DATA_INTEGRITY,
                severity=RuleSeverity.WARNING,
                message=f"{n_classes} classes exceeds recommended maximum of 9",
                details="Human perception cannot reliably order >7 lightness steps",
                auto_correctable=True,
                correction_hint="reduce_class_count",
                score_penalty=10.0,
            ))

        return violations

    def validate_typography(self, text_elements: list[dict]) -> list[RuleViolation]:
        """
        Validate typography choices.

        Each text_element dict should have:
            role: str — "title", "subtitle", "label", "annotation", "source"
            font_family: str
            font_size_pt: float — at output DPI
            has_halo: bool
            halo_width: float | None
            over_complex_bg: bool — whether the label is over data/imagery
        """
        violations = []
        font_families = set()
        title_size = 0
        max_label_size = 0

        for elem in text_elements:
            font_families.add(elem.get("font_family", ""))
            size = elem.get("font_size_pt", 10)

            if elem.get("role") == "title":
                title_size = size
            elif elem.get("role") == "label":
                max_label_size = max(max_label_size, size)

            # TY-007: Minimum label size
            if elem.get("role") in ("label", "annotation") and size < 6:
                violations.append(RuleViolation(
                    rule_id="TY-007",
                    category=RuleCategory.TYPOGRAPHY,
                    severity=RuleSeverity.ERROR,
                    message=f"Label at {size:.1f}pt is below minimum 6pt",
                    details=f"Font: {elem.get('font_family')}, Size: {size}pt",
                    auto_correctable=True,
                    correction_hint="increase_min_label_size",
                    score_penalty=15.0,
                ))

            # TY-004: Halo required over complex backgrounds
            if elem.get("over_complex_bg") and not elem.get("has_halo"):
                violations.append(RuleViolation(
                    rule_id="TY-004",
                    category=RuleCategory.TYPOGRAPHY,
                    severity=RuleSeverity.WARNING,
                    message="Label over complex background has no halo/mask",
                    details=f"Font: {elem.get('font_family')}, Role: {elem.get('role')}",
                    auto_correctable=True,
                    correction_hint="add_label_halos",
                    score_penalty=10.0,
                ))

            # TY-006: Halo proportion
            if elem.get("has_halo") and elem.get("halo_width") and size > 0:
                ratio = elem["halo_width"] / size
                if not (0.08 <= ratio <= 0.15):
                    violations.append(RuleViolation(
                        rule_id="TY-006",
                        category=RuleCategory.TYPOGRAPHY,
                        severity=RuleSeverity.INFO,
                        message=f"Halo width ratio {ratio:.2f} outside ideal range (0.08-0.15)",
                        details=f"Halo: {elem['halo_width']}pt, Font: {size}pt",
                        auto_correctable=True,
                        correction_hint="adjust_halo_width",
                        score_penalty=5.0,
                    ))

        # TY-001: Font family limit
        font_families.discard("")
        if len(font_families) > 2:
            violations.append(RuleViolation(
                rule_id="TY-001",
                category=RuleCategory.TYPOGRAPHY,
                severity=RuleSeverity.WARNING,
                message=f"Using {len(font_families)} font families (max 2)",
                details=f"Families: {', '.join(sorted(font_families))}",
                auto_correctable=True,
                correction_hint="reduce_font_families",
                score_penalty=10.0,
            ))

        # TY-002: Minimum title size
        if title_size > 0 and title_size < 14:
            violations.append(RuleViolation(
                rule_id="TY-002",
                category=RuleCategory.TYPOGRAPHY,
                severity=RuleSeverity.ERROR,
                message=f"Title at {title_size:.1f}pt is below minimum 14pt",
                details="Title must be readable at arm's length",
                auto_correctable=True,
                correction_hint="increase_title_size",
                score_penalty=15.0,
            ))

        # VH-001: Title prominence
        if title_size > 0 and max_label_size > 0:
            if title_size < 1.4 * max_label_size:
                violations.append(RuleViolation(
                    rule_id="VH-001",
                    category=RuleCategory.VISUAL_HIERARCHY,
                    severity=RuleSeverity.ERROR,
                    message=f"Title ({title_size:.1f}pt) not prominent enough vs "
                           f"largest label ({max_label_size:.1f}pt). "
                           f"Ratio: {title_size/max_label_size:.2f} (need >= 1.4)",
                    details="Title should be >= 1.4x the largest label",
                    auto_correctable=True,
                    correction_hint="increase_title_font_size",
                    score_penalty=15.0,
                ))

        return violations

    def compute_category_score(
        self,
        category: RuleCategory,
        violations: list[RuleViolation],
    ) -> float:
        """
        Compute a 0-100 score for a rule category based on violations.
        Starts at 100, deducts penalty for each violation in this category.
        """
        score = 100.0
        for v in violations:
            if v.category == category:
                score -= v.score_penalty
        return max(0.0, score)

    def compute_overall_score(self, violations: list[RuleViolation]) -> dict:
        """
        Compute scores for all categories and an overall weighted average.

        Returns:
            {
                "overall": float,
                "passed": bool,
                "dimensions": {category_name: score, ...},
                "violation_count": int,
                "critical_count": int,
            }
        """
        # Category weights (total = 1.0)
        weights = {
            RuleCategory.VISUAL_HIERARCHY: 0.15,
            RuleCategory.COLOR_THEORY: 0.20,
            RuleCategory.TYPOGRAPHY: 0.15,
            RuleCategory.LAYOUT: 0.15,
            RuleCategory.GENERALIZATION: 0.15,
            RuleCategory.DATA_INTEGRITY: 0.20,
        }

        dimensions = {}
        weighted_sum = 0.0

        for category, weight in weights.items():
            score = self.compute_category_score(category, violations)
            dimensions[category.value] = score
            weighted_sum += score * weight

        critical_count = sum(
            1 for v in violations if v.severity == RuleSeverity.CRITICAL
        )

        # Any critical violation caps overall score at 50
        overall = weighted_sum
        if critical_count > 0:
            overall = min(overall, 50.0)

        return {
            "overall": round(overall, 1),
            "passed": overall >= 70.0 and critical_count == 0,
            "dimensions": {k: round(v, 1) for k, v in dimensions.items()},
            "violation_count": len(violations),
            "critical_count": critical_count,
        }
