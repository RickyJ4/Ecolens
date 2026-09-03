"""
Map Reference Database

A curated catalog of ~100 exemplar award-winning maps with extracted metadata.
The engine cross-references its own output against these known-good examples
to validate composition, color choices, and layout proportions.

Sources:
  - ICA International Cartographic Association awards (2010-2024)
  - NACIS Atlas of Design volumes 1-5
  - ESRI Map Gallery winners
  - National Geographic cartographic standards
  - Swiss Federal Office of Topography (swisstopo) reference sheets
  - UK Ordnance Survey best practices
  - USGS The National Map standards
  - Kenneth Field's "Cartography." reference examples
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ExemplarMap:
    """Metadata extracted from an award-winning map."""
    id: str
    name: str
    source: str                          # Award/publication (ICA, NACIS, ESRI, etc.)
    year: int
    map_type: str                        # choropleth, dot_density, proportional_symbol, etc.
    theme: str                           # environmental, demographic, hazard, reference, etc.
    data_type: str                       # sequential, diverging, qualitative
    geometry_types: list[str]            # ["polygon", "point", "line"]

    # Layout metrics (proportions 0-1)
    map_body_ratio: float                # Map body area / total area
    legend_position: str                 # "inside-lower-right", "outside-right", etc.
    legend_area_ratio: float             # Legend area / total area
    margin_ratio: float                  # Average margin / total dimension
    title_position: str                  # "top-center", "top-left", etc.
    has_scale_bar: bool
    has_north_arrow: bool
    has_inset_map: bool
    has_source_attribution: bool

    # Color profile
    palette_type: str                    # "sequential", "diverging", "qualitative"
    palette_name: str | None             # ColorBrewer name if identifiable
    n_classes: int
    dominant_hue_family: str             # "warm", "cool", "neutral", "multi"
    background_lightness: str            # "light", "dark", "medium"
    contrast_level: str                  # "low", "medium", "high"

    # Typography
    font_families_count: int
    title_font_type: str                 # "sans-serif", "serif", "slab-serif"
    label_font_type: str
    label_density: str                   # "sparse", "moderate", "dense"

    # Composition
    visual_balance: str                  # "centered", "left-heavy", "right-heavy", "balanced"
    figure_ground_separation: str        # "strong", "moderate", "weak"
    data_ink_ratio: str                  # "high", "medium", "low"
    overall_complexity: str              # "minimal", "moderate", "complex"

    # Quality assessment
    quality_notes: str                   # What makes this map excellent
    techniques_used: list[str]           # Specific techniques worth emulating

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "source": self.source,
            "year": self.year,
            "map_type": self.map_type,
            "theme": self.theme,
            "data_type": self.data_type,
            "geometry_types": self.geometry_types,
            "layout": {
                "map_body_ratio": self.map_body_ratio,
                "legend_position": self.legend_position,
                "legend_area_ratio": self.legend_area_ratio,
                "margin_ratio": self.margin_ratio,
                "title_position": self.title_position,
                "has_scale_bar": self.has_scale_bar,
                "has_north_arrow": self.has_north_arrow,
                "has_inset_map": self.has_inset_map,
                "has_source_attribution": self.has_source_attribution,
            },
            "color": {
                "palette_type": self.palette_type,
                "palette_name": self.palette_name,
                "n_classes": self.n_classes,
                "dominant_hue_family": self.dominant_hue_family,
                "background_lightness": self.background_lightness,
                "contrast_level": self.contrast_level,
            },
            "typography": {
                "font_families_count": self.font_families_count,
                "title_font_type": self.title_font_type,
                "label_font_type": self.label_font_type,
                "label_density": self.label_density,
            },
            "composition": {
                "visual_balance": self.visual_balance,
                "figure_ground_separation": self.figure_ground_separation,
                "data_ink_ratio": self.data_ink_ratio,
                "overall_complexity": self.overall_complexity,
            },
            "quality_notes": self.quality_notes,
            "techniques_used": self.techniques_used,
        }


class MapReferenceDatabase:
    """
    Database of exemplar maps for cross-referencing generated output.

    The database provides:
    1. Statistical baselines: what layout ratios, class counts, palette types
       award-winning maps actually use for each map type and theme.
    2. Technique discovery: which cartographic techniques are appropriate
       for a given data type and theme.
    3. Quality benchmarking: compare a generated map's metrics against
       the distribution of exemplar metrics.
    """

    def __init__(self):
        self._exemplars: list[ExemplarMap] = []
        self._load_exemplars()

    def _load_exemplars(self):
        """Load exemplar maps from the bundled JSON catalog."""
        data_path = Path(__file__).parent / "data" / "exemplar_maps.json"
        if data_path.exists():
            with open(data_path, "r") as f:
                data = json.load(f)
            for entry in data.get("exemplars", []):
                self._exemplars.append(self._parse_exemplar(entry))

        # If JSON is empty or missing, use hardcoded core exemplars
        if not self._exemplars:
            self._exemplars = self._get_core_exemplars()

    @staticmethod
    def _parse_exemplar(entry: dict) -> ExemplarMap:
        """Parse an exemplar from JSON dict."""
        layout = entry.get("layout", {})
        color = entry.get("color", {})
        typo = entry.get("typography", {})
        comp = entry.get("composition", {})
        return ExemplarMap(
            id=entry["id"],
            name=entry["name"],
            source=entry["source"],
            year=entry["year"],
            map_type=entry["map_type"],
            theme=entry["theme"],
            data_type=entry["data_type"],
            geometry_types=entry.get("geometry_types", []),
            map_body_ratio=layout.get("map_body_ratio", 0.7),
            legend_position=layout.get("legend_position", "outside-right"),
            legend_area_ratio=layout.get("legend_area_ratio", 0.08),
            margin_ratio=layout.get("margin_ratio", 0.04),
            title_position=layout.get("title_position", "top-center"),
            has_scale_bar=layout.get("has_scale_bar", True),
            has_north_arrow=layout.get("has_north_arrow", False),
            has_inset_map=layout.get("has_inset_map", False),
            has_source_attribution=layout.get("has_source_attribution", True),
            palette_type=color.get("palette_type", "sequential"),
            palette_name=color.get("palette_name"),
            n_classes=color.get("n_classes", 5),
            dominant_hue_family=color.get("dominant_hue_family", "warm"),
            background_lightness=color.get("background_lightness", "light"),
            contrast_level=color.get("contrast_level", "high"),
            font_families_count=typo.get("font_families_count", 2),
            title_font_type=typo.get("title_font_type", "sans-serif"),
            label_font_type=typo.get("label_font_type", "sans-serif"),
            label_density=typo.get("label_density", "moderate"),
            visual_balance=comp.get("visual_balance", "balanced"),
            figure_ground_separation=comp.get("figure_ground_separation", "strong"),
            data_ink_ratio=comp.get("data_ink_ratio", "high"),
            overall_complexity=comp.get("overall_complexity", "moderate"),
            quality_notes=entry.get("quality_notes", ""),
            techniques_used=entry.get("techniques_used", []),
        )

    def get_all(self) -> list[ExemplarMap]:
        """Return all exemplar maps."""
        return list(self._exemplars)

    def query(
        self,
        map_type: str | None = None,
        theme: str | None = None,
        data_type: str | None = None,
        source: str | None = None,
    ) -> list[ExemplarMap]:
        """Query exemplars by attributes."""
        results = self._exemplars
        if map_type:
            results = [e for e in results if e.map_type == map_type]
        if theme:
            results = [e for e in results if e.theme == theme]
        if data_type:
            results = [e for e in results if e.data_type == data_type]
        if source:
            results = [e for e in results if e.source == source]
        return results

    def get_baseline_metrics(self, map_type: str, theme: str | None = None) -> dict:
        """
        Compute statistical baselines from exemplars matching criteria.

        Returns median, min, max for numeric metrics so the validator
        can compare generated maps against the distribution.
        """
        matches = self.query(map_type=map_type, theme=theme)
        if not matches:
            matches = self.query(map_type=map_type)
        if not matches:
            matches = self._exemplars

        if not matches:
            return self._default_baselines()

        def _stats(values):
            values = sorted(values)
            n = len(values)
            return {
                "min": values[0],
                "median": values[n // 2],
                "max": values[-1],
                "count": n,
            }

        return {
            "map_body_ratio": _stats([e.map_body_ratio for e in matches]),
            "legend_area_ratio": _stats([e.legend_area_ratio for e in matches]),
            "margin_ratio": _stats([e.margin_ratio for e in matches]),
            "n_classes": _stats([e.n_classes for e in matches]),
            "font_families_count": _stats([e.font_families_count for e in matches]),
            # Categorical distributions
            "palette_type_distribution": self._distribution(
                [e.palette_type for e in matches]
            ),
            "legend_position_distribution": self._distribution(
                [e.legend_position for e in matches]
            ),
            "background_lightness_distribution": self._distribution(
                [e.background_lightness for e in matches]
            ),
            "label_density_distribution": self._distribution(
                [e.label_density for e in matches]
            ),
            "techniques_frequency": self._technique_frequency(matches),
            "exemplar_count": len(matches),
        }

    def get_recommended_techniques(self, map_type: str, theme: str | None = None) -> list[str]:
        """
        Return techniques used by exemplar maps matching the criteria,
        ordered by frequency (most common first).
        """
        matches = self.query(map_type=map_type, theme=theme)
        if not matches:
            matches = self.query(map_type=map_type)

        freq = self._technique_frequency(matches)
        return sorted(freq.keys(), key=lambda t: freq[t], reverse=True)

    def compare_against_exemplars(
        self,
        generated_metrics: dict,
        map_type: str,
        theme: str | None = None,
    ) -> dict:
        """
        Compare a generated map's metrics against exemplar baselines.

        Returns a similarity score and specific deviations from exemplar norms.
        """
        baselines = self.get_baseline_metrics(map_type, theme)
        deviations = []
        similarity_scores = []

        for metric_name in ["map_body_ratio", "legend_area_ratio", "margin_ratio", "n_classes"]:
            if metric_name in generated_metrics and metric_name in baselines:
                gen_val = generated_metrics[metric_name]
                baseline = baselines[metric_name]
                median = baseline["median"]
                min_val = baseline["min"]
                max_val = baseline["max"]

                if max_val > min_val:
                    # Normalized distance from median (0 = at median, 1 = at extreme)
                    range_half = (max_val - min_val) / 2
                    deviation = abs(gen_val - median) / range_half if range_half > 0 else 0
                    similarity = max(0, 1.0 - deviation)
                    similarity_scores.append(similarity)

                    if deviation > 1.0:
                        deviations.append({
                            "metric": metric_name,
                            "generated": gen_val,
                            "exemplar_median": median,
                            "exemplar_range": [min_val, max_val],
                            "deviation": round(deviation, 2),
                            "message": f"{metric_name}: {gen_val:.2f} is outside exemplar "
                                      f"range [{min_val:.2f}, {max_val:.2f}]",
                        })

        overall_similarity = (
            sum(similarity_scores) / len(similarity_scores)
            if similarity_scores else 0.5
        )

        return {
            "similarity_score": round(overall_similarity * 100, 1),
            "deviations": deviations,
            "baselines_used": baselines.get("exemplar_count", 0),
        }

    @staticmethod
    def _distribution(values: list[str]) -> dict[str, float]:
        """Compute frequency distribution of categorical values."""
        if not values:
            return {}
        counts = {}
        for v in values:
            counts[v] = counts.get(v, 0) + 1
        total = len(values)
        return {k: round(v / total, 3) for k, v in sorted(counts.items(), key=lambda x: -x[1])}

    @staticmethod
    def _technique_frequency(exemplars: list[ExemplarMap]) -> dict[str, int]:
        """Count technique usage across exemplars."""
        freq = {}
        for e in exemplars:
            for t in e.techniques_used:
                freq[t] = freq.get(t, 0) + 1
        return freq

    @staticmethod
    def _default_baselines() -> dict:
        """Fallback baselines when no exemplars match."""
        return {
            "map_body_ratio": {"min": 0.60, "median": 0.70, "max": 0.80, "count": 0},
            "legend_area_ratio": {"min": 0.04, "median": 0.08, "max": 0.15, "count": 0},
            "margin_ratio": {"min": 0.03, "median": 0.05, "max": 0.08, "count": 0},
            "n_classes": {"min": 3, "median": 5, "max": 9, "count": 0},
            "font_families_count": {"min": 1, "median": 2, "max": 2, "count": 0},
            "exemplar_count": 0,
        }

    def _get_core_exemplars(self) -> list[ExemplarMap]:
        """
        Hardcoded core exemplars — the most important reference maps.
        These serve as fallback when the JSON catalog is not available.
        """
        return [
            # ─── CHOROPLETH MAPS ───────────────────────────────────
            ExemplarMap(
                id="ica-2023-deforestation-rates",
                name="Global Deforestation Rates by Country",
                source="ICA", year=2023, map_type="choropleth",
                theme="environmental", data_type="sequential",
                geometry_types=["polygon"],
                map_body_ratio=0.72, legend_position="outside-right",
                legend_area_ratio=0.08, margin_ratio=0.04,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlOrRd",
                n_classes=5, dominant_hue_family="warm",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Clean sequential palette with strong figure-ground. "
                             "Legend perfectly aligned with map body edge.",
                techniques_used=["choropleth", "natural_breaks", "sequential_palette",
                                "inset_locator", "graduated_legend"],
            ),
            ExemplarMap(
                id="nacis-2022-fire-risk",
                name="Wildfire Risk Assessment — Western United States",
                source="NACIS", year=2022, map_type="choropleth",
                theme="hazard", data_type="sequential",
                geometry_types=["polygon", "point"],
                map_body_ratio=0.68, legend_position="inside-lower-right",
                legend_area_ratio=0.06, margin_ratio=0.05,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="OrRd",
                n_classes=6, dominant_hue_family="warm",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Fire risk shown with orange-red ramp that intuitively "
                             "maps to heat/danger. Point symbols for active fires overlay.",
                techniques_used=["choropleth", "point_overlay", "quantile_classification",
                                "inset_map", "hazard_symbology"],
            ),
            ExemplarMap(
                id="esri-2023-population-density",
                name="World Population Density",
                source="ESRI", year=2023, map_type="choropleth",
                theme="demographic", data_type="sequential",
                geometry_types=["polygon"],
                map_body_ratio=0.75, legend_position="outside-bottom",
                legend_area_ratio=0.07, margin_ratio=0.04,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlOrBr",
                n_classes=7, dominant_hue_family="warm",
                background_lightness="light", contrast_level="high",
                font_families_count=1, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="sparse",
                visual_balance="centered", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="minimal",
                quality_notes="Masterful simplicity. Single font family, high data-ink ratio, "
                             "no decorative elements. The data speaks for itself.",
                techniques_used=["choropleth", "natural_breaks", "sequential_palette",
                                "global_projection", "minimal_design"],
            ),

            # ─── HEATMAP / DENSITY MAPS ───────────────────────────
            ExemplarMap(
                id="natgeo-2021-biodiversity-hotspots",
                name="Global Biodiversity Hotspots",
                source="NatGeo", year=2021, map_type="heatmap",
                theme="environmental", data_type="sequential",
                geometry_types=["polygon", "raster"],
                map_body_ratio=0.70, legend_position="inside-lower-left",
                legend_area_ratio=0.05, margin_ratio=0.05,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlGn",
                n_classes=5, dominant_hue_family="cool",
                background_lightness="dark", contrast_level="high",
                font_families_count=2, title_font_type="serif",
                label_font_type="sans-serif", label_density="sparse",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Dark background makes the green biodiversity hotspots glow. "
                             "Excellent figure-ground separation.",
                techniques_used=["heatmap", "dark_basemap", "glow_effect",
                                "continuous_ramp", "satellite_underlay"],
            ),
            ExemplarMap(
                id="ica-2022-species-density",
                name="Endangered Species Density — Southeast Asia",
                source="ICA", year=2022, map_type="heatmap",
                theme="environmental", data_type="sequential",
                geometry_types=["raster"],
                map_body_ratio=0.73, legend_position="outside-right",
                legend_area_ratio=0.09, margin_ratio=0.04,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="PuBuGn",
                n_classes=6, dominant_hue_family="cool",
                background_lightness="light", contrast_level="medium",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="moderate",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="KDE with adaptive bandwidth creates smooth continuous surface. "
                             "Inset map shows global context.",
                techniques_used=["kernel_density", "adaptive_bandwidth",
                                "continuous_surface", "inset_locator"],
            ),

            # ─── PROPORTIONAL SYMBOL MAPS ─────────────────────────
            ExemplarMap(
                id="nacis-2023-earthquake-magnitude",
                name="Major Earthquakes 2000-2023",
                source="NACIS", year=2023, map_type="proportional_symbol",
                theme="hazard", data_type="sequential",
                geometry_types=["point"],
                map_body_ratio=0.74, legend_position="inside-lower-left",
                legend_area_ratio=0.06, margin_ratio=0.04,
                title_position="top-center", has_scale_bar=False,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlOrRd",
                n_classes=4, dominant_hue_family="warm",
                background_lightness="dark", contrast_level="high",
                font_families_count=1, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="sparse",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="minimal",
                quality_notes="Graduated circles scaled by area (not radius). "
                             "Semi-transparent fill allows overlapping symbols to accumulate.",
                techniques_used=["proportional_symbols", "area_scaling",
                                "semi_transparency", "dark_basemap", "minimal_labels"],
            ),
            ExemplarMap(
                id="esri-2022-flood-events",
                name="Global Flood Events and Population Impact",
                source="ESRI", year=2022, map_type="proportional_symbol",
                theme="hazard", data_type="sequential",
                geometry_types=["point", "polygon"],
                map_body_ratio=0.68, legend_position="outside-right",
                legend_area_ratio=0.10, margin_ratio=0.05,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="PuBu",
                n_classes=5, dominant_hue_family="cool",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Bivariate: circle size = affected area, color = population impact. "
                             "Clean separation of the two variables.",
                techniques_used=["proportional_symbols", "bivariate_encoding",
                                "choropleth_underlay", "graduated_legend"],
            ),

            # ─── DOT DENSITY MAPS ─────────────────────────────────
            ExemplarMap(
                id="nacis-2021-tree-cover-loss",
                name="Tree Cover Loss — Amazon Basin 2001-2020",
                source="NACIS", year=2021, map_type="dot_density",
                theme="environmental", data_type="sequential",
                geometry_types=["point"],
                map_body_ratio=0.72, legend_position="inside-lower-right",
                legend_area_ratio=0.05, margin_ratio=0.04,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="OrRd",
                n_classes=1, dominant_hue_family="warm",
                background_lightness="dark", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="sparse",
                visual_balance="left-heavy", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Each dot = 100 hectares of tree cover loss. Dark green satellite "
                             "base makes red loss dots dramatic and immediately readable.",
                techniques_used=["dot_density", "satellite_basemap",
                                "one_dot_one_value", "temporal_encoding"],
            ),

            # ─── ISOPLETH / CONTOUR MAPS ──────────────────────────
            ExemplarMap(
                id="swisstopo-2023-precipitation",
                name="Annual Precipitation — Swiss Alps",
                source="swisstopo", year=2023, map_type="isopleth",
                theme="environmental", data_type="sequential",
                geometry_types=["line", "polygon"],
                map_body_ratio=0.65, legend_position="outside-right",
                legend_area_ratio=0.12, margin_ratio=0.05,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=True, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="Blues",
                n_classes=8, dominant_hue_family="cool",
                background_lightness="light", contrast_level="medium",
                font_families_count=2, title_font_type="serif",
                label_font_type="sans-serif", label_density="dense",
                visual_balance="centered", figure_ground_separation="moderate",
                data_ink_ratio="medium", overall_complexity="complex",
                quality_notes="Swiss precision: filled contours with labeled isolines. "
                             "Hillshade underlay creates depth without competing with data.",
                techniques_used=["isolines", "filled_contours", "hillshade_underlay",
                                "contour_labeling", "hypsometric_tinting"],
            ),

            # ─── BIVARIATE MAPS ───────────────────────────────────
            ExemplarMap(
                id="ica-2024-risk-vulnerability",
                name="Climate Risk vs Adaptive Capacity — Sub-Saharan Africa",
                source="ICA", year=2024, map_type="bivariate_choropleth",
                theme="hazard", data_type="diverging",
                geometry_types=["polygon"],
                map_body_ratio=0.65, legend_position="outside-right",
                legend_area_ratio=0.14, margin_ratio=0.05,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="diverging", palette_name="RdBu",
                n_classes=9, dominant_hue_family="multi",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="complex",
                quality_notes="3x3 bivariate grid legend is immediately readable. "
                             "Red-blue divergence clearly separates risk from capacity.",
                techniques_used=["bivariate_choropleth", "3x3_grid_legend",
                                "diverging_palette", "bivariate_legend_matrix"],
            ),

            # ─── MULTI-HAZARD / RISK MAPS ─────────────────────────
            ExemplarMap(
                id="esri-2023-multi-hazard",
                name="Multi-Hazard Risk Index — Pacific Ring of Fire",
                source="ESRI", year=2023, map_type="multi_hazard_risk",
                theme="hazard", data_type="sequential",
                geometry_types=["polygon", "point", "line"],
                map_body_ratio=0.66, legend_position="outside-right",
                legend_area_ratio=0.12, margin_ratio=0.04,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlOrRd",
                n_classes=5, dominant_hue_family="warm",
                background_lightness="dark", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="complex",
                quality_notes="Multiple hazard types (earthquake, volcano, tsunami) "
                             "composited into unified risk index. Clean symbology per hazard.",
                techniques_used=["multi_layer_composite", "hazard_icons",
                                "risk_surface", "dark_basemap", "point_symbol_overlay"],
            ),

            # ─── CHANGE DETECTION MAPS ─────────────────────────────
            ExemplarMap(
                id="nacis-2024-forest-change",
                name="Forest Cover Change — Congo Basin 2000-2023",
                source="NACIS", year=2024, map_type="choropleth",
                theme="environmental", data_type="diverging",
                geometry_types=["polygon", "raster"],
                map_body_ratio=0.70, legend_position="inside-lower-left",
                legend_area_ratio=0.07, margin_ratio=0.04,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="diverging", palette_name="BrBG",
                n_classes=7, dominant_hue_family="multi",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="centered", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Brown-blue-green diverging: brown = loss, green = gain. "
                             "Neutral midpoint for stable forest. Temporal range in subtitle.",
                techniques_used=["change_detection", "diverging_palette",
                                "temporal_comparison", "satellite_composite",
                                "classification_overlay"],
            ),

            # ─── FLOW / MIGRATION MAPS ────────────────────────────
            ExemplarMap(
                id="ica-2023-ocean-currents",
                name="Global Ocean Surface Currents and Temperature",
                source="ICA", year=2023, map_type="isopleth",
                theme="environmental", data_type="sequential",
                geometry_types=["line", "raster"],
                map_body_ratio=0.76, legend_position="outside-bottom",
                legend_area_ratio=0.06, margin_ratio=0.03,
                title_position="top-center", has_scale_bar=False,
                has_north_arrow=False, has_inset_map=False,
                has_source_attribution=True,
                palette_type="sequential", palette_name="RdYlBu",
                n_classes=9, dominant_hue_family="multi",
                background_lightness="dark", contrast_level="high",
                font_families_count=1, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="sparse",
                visual_balance="centered", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="complex",
                quality_notes="Animated flow lines show current direction and speed. "
                             "Temperature raster underlays with reversed RdYlBu (cold=blue, warm=red).",
                techniques_used=["flow_lines", "animated_particles",
                                "temperature_raster", "continuous_legend", "dark_basemap"],
            ),

            # ─── REFERENCE / TOPOGRAPHIC ──────────────────────────
            ExemplarMap(
                id="os-2022-terrain",
                name="Lake District National Park — Topographic Overview",
                source="Ordnance Survey", year=2022, map_type="isopleth",
                theme="reference", data_type="sequential",
                geometry_types=["line", "polygon", "point"],
                map_body_ratio=0.70, legend_position="outside-right",
                legend_area_ratio=0.10, margin_ratio=0.05,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=True, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="Greens",
                n_classes=8, dominant_hue_family="cool",
                background_lightness="light", contrast_level="medium",
                font_families_count=2, title_font_type="serif",
                label_font_type="sans-serif", label_density="dense",
                visual_balance="centered", figure_ground_separation="moderate",
                data_ink_ratio="medium", overall_complexity="complex",
                quality_notes="Classic topographic styling: hypsometric tinting, contour lines, "
                             "multiple symbology layers perfectly balanced.",
                techniques_used=["hypsometric_tinting", "contour_lines",
                                "hillshade", "multi_layer_reference", "grid_reference"],
            ),

            # ─── ENVIRONMENTAL MONITORING ─────────────────────────
            ExemplarMap(
                id="esri-2024-ndvi-health",
                name="Vegetation Health Index — Australian Bushfire Recovery",
                source="ESRI", year=2024, map_type="choropleth",
                theme="environmental", data_type="diverging",
                geometry_types=["raster"],
                map_body_ratio=0.72, legend_position="outside-right",
                legend_area_ratio=0.08, margin_ratio=0.04,
                title_position="top-left", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="diverging", palette_name="RdYlGn",
                n_classes=7, dominant_hue_family="multi",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="RdYlGn perfectly maps to vegetation health: red=degraded, "
                             "green=healthy. Before/after insets show temporal change.",
                techniques_used=["ndvi_classification", "diverging_palette",
                                "temporal_inset", "satellite_derived",
                                "before_after_comparison"],
            ),

            ExemplarMap(
                id="ica-2024-drought-severity",
                name="Drought Severity and Agricultural Impact — East Africa",
                source="ICA", year=2024, map_type="choropleth",
                theme="hazard", data_type="sequential",
                geometry_types=["polygon", "point"],
                map_body_ratio=0.69, legend_position="outside-right",
                legend_area_ratio=0.10, margin_ratio=0.05,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=False, has_inset_map=True,
                has_source_attribution=True,
                palette_type="sequential", palette_name="YlOrBr",
                n_classes=5, dominant_hue_family="warm",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="balanced", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Brown tones for drought severity (earth cracking metaphor). "
                             "Agricultural impact shown as proportional symbols overlay.",
                techniques_used=["choropleth", "proportional_symbol_overlay",
                                "earth_tone_palette", "graduated_legend",
                                "hazard_classification"],
            ),

            # ─── GLACIER / CRYOSPHERE ─────────────────────────────
            ExemplarMap(
                id="nacis-2023-glacier-retreat",
                name="Glacier Retreat in the Himalayas 1990-2023",
                source="NACIS", year=2023, map_type="choropleth",
                theme="environmental", data_type="diverging",
                geometry_types=["polygon", "line"],
                map_body_ratio=0.68, legend_position="outside-right",
                legend_area_ratio=0.10, margin_ratio=0.05,
                title_position="top-center", has_scale_bar=True,
                has_north_arrow=True, has_inset_map=True,
                has_source_attribution=True,
                palette_type="diverging", palette_name="RdBu",
                n_classes=7, dominant_hue_family="cool",
                background_lightness="light", contrast_level="high",
                font_families_count=2, title_font_type="sans-serif",
                label_font_type="sans-serif", label_density="moderate",
                visual_balance="centered", figure_ground_separation="strong",
                data_ink_ratio="high", overall_complexity="moderate",
                quality_notes="Glacier extent shown as temporal layers (1990 outline, "
                             "2023 fill). RdBu diverging shows advance vs retreat.",
                techniques_used=["temporal_overlay", "extent_comparison",
                                "hillshade_underlay", "diverging_palette",
                                "elevation_context"],
            ),
        ]
