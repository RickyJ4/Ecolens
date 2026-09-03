"""
Map Type Templates

7 map type templates, each with:
  - Required data types and geometry
  - Default styling parameters
  - Classification method recommendations
  - Legend configuration
  - Real EcoLens disaster showcase examples

Each template is a blueprint that the composition engine uses to
configure rendering automatically. Users can override any parameter.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class ClassificationMethod(Enum):
    """Statistical classification methods for thematic maps."""
    NATURAL_BREAKS = "natural_breaks"     # Jenks optimization
    QUANTILE = "quantile"                 # Equal count per class
    EQUAL_INTERVAL = "equal_interval"     # Equal value range per class
    STANDARD_DEVIATION = "std_deviation"  # Classes by std dev from mean
    MANUAL = "manual"                     # User-defined breaks
    GEOMETRICAL = "geometrical"           # Geometric progression


class LegendType(Enum):
    """Legend display type."""
    CLASSIFIED = "classified"             # Discrete color swatches with ranges
    CONTINUOUS = "continuous"             # Gradient bar
    PROPORTIONAL = "proportional"         # Nested circles/symbols
    BIVARIATE_MATRIX = "bivariate_matrix" # 3x3 or 4x4 grid
    CATEGORICAL = "categorical"           # Named categories with swatches
    DOT_VALUE = "dot_value"              # "1 dot = N units"


@dataclass
class MapTemplate:
    """
    Blueprint for a specific map type.

    The composition engine uses this to set defaults for all rendering
    parameters. Users can override any field via MapRequest.
    """
    id: str
    name: str
    description: str
    required_geometry: list[str]           # ["polygon"], ["point"], etc.
    supported_data_types: list[str]        # ["sequential", "diverging", etc.]
    classification_methods: list[ClassificationMethod]
    default_classification: ClassificationMethod
    default_palette_type: str              # "sequential", "diverging", "qualitative"
    default_n_classes: int
    legend_type: LegendType
    requires_normalization: bool           # True for choropleth (rates, not counts)
    supports_basemap: bool
    default_basemap: str | None            # "satellite", "terrain", "osm", None
    min_classes: int
    max_classes: int
    rendering_notes: str                   # Tips for the composition engine

    # Default visual parameters
    default_opacity: float = 0.85
    default_stroke_width: float = 0.5
    default_stroke_color: str = "#333333"
    show_labels: bool = True
    label_field: str | None = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "required_geometry": self.required_geometry,
            "supported_data_types": self.supported_data_types,
            "classification_methods": [m.value for m in self.classification_methods],
            "default_classification": self.default_classification.value,
            "default_palette_type": self.default_palette_type,
            "default_n_classes": self.default_n_classes,
            "legend_type": self.legend_type.value,
            "requires_normalization": self.requires_normalization,
            "min_classes": self.min_classes,
            "max_classes": self.max_classes,
        }


@dataclass
class ShowcaseExample:
    """
    A real-world disaster/event that demonstrates a map template.

    Each example includes:
    - The actual geographic coordinates (bbox)
    - Data sources to fetch
    - Expected visual output description
    - Why this template is the right choice for this data
    """
    id: str
    template_id: str
    title: str
    subtitle: str
    disaster_type: str
    description: str
    bbox: tuple[float, float, float, float]  # west, south, east, north
    data_sources: list[str]                   # Source IDs from DataPipeline
    palette: str                              # Recommended palette name
    n_classes: int
    classification: str                       # Classification method
    why_this_template: str                    # Educational explanation
    key_findings: list[str]                   # What the map reveals
    date_range: str                           # Temporal scope


# ═══════════════════════════════════════════════════════════════════════
# THE 7 MAP TEMPLATES
# ═══════════════════════════════════════════════════════════════════════

TEMPLATES: dict[str, MapTemplate] = {

    # ─── 1. CHOROPLETH ────────────────────────────────────────────
    "choropleth": MapTemplate(
        id="choropleth",
        name="Choropleth Map",
        description="Colors areas (polygons) by classified data values. "
                   "The workhorse of thematic cartography. MUST use normalized "
                   "data (rates, densities, percentages) — never raw counts.",
        required_geometry=["polygon"],
        supported_data_types=["sequential", "diverging"],
        classification_methods=[
            ClassificationMethod.NATURAL_BREAKS,
            ClassificationMethod.QUANTILE,
            ClassificationMethod.EQUAL_INTERVAL,
            ClassificationMethod.STANDARD_DEVIATION,
            ClassificationMethod.MANUAL,
        ],
        default_classification=ClassificationMethod.NATURAL_BREAKS,
        default_palette_type="sequential",
        default_n_classes=5,
        legend_type=LegendType.CLASSIFIED,
        requires_normalization=True,
        supports_basemap=True,
        default_basemap=None,
        min_classes=3,
        max_classes=9,
        rendering_notes="Use natural breaks (Jenks) for skewed environmental data. "
                       "Ensure polygon boundaries are visible (thin dark stroke). "
                       "Equal-area projection REQUIRED to prevent visual bias.",
        default_opacity=0.85,
        default_stroke_width=0.5,
        default_stroke_color="#333333",
    ),

    # ─── 2. HEATMAP / DENSITY ─────────────────────────────────────
    "heatmap": MapTemplate(
        id="heatmap",
        name="Heat Map / Kernel Density",
        description="Continuous density surface from point data. Shows spatial "
                   "concentration patterns. Uses kernel density estimation (KDE) "
                   "to create a smooth interpolated surface.",
        required_geometry=["point"],
        supported_data_types=["sequential"],
        classification_methods=[
            ClassificationMethod.NATURAL_BREAKS,
            ClassificationMethod.QUANTILE,
        ],
        default_classification=ClassificationMethod.NATURAL_BREAKS,
        default_palette_type="sequential",
        default_n_classes=7,
        legend_type=LegendType.CONTINUOUS,
        requires_normalization=False,
        supports_basemap=True,
        default_basemap="dark",
        min_classes=5,
        max_classes=12,
        rendering_notes="Dark basemap provides best contrast for heat colors. "
                       "Use adaptive bandwidth KDE for unevenly distributed data. "
                       "Semi-transparent overlay blends with basemap for context.",
        default_opacity=0.70,
        show_labels=False,
    ),

    # ─── 3. PROPORTIONAL SYMBOL ───────────────────────────────────
    "proportional_symbol": MapTemplate(
        id="proportional_symbol",
        name="Proportional Symbol Map",
        description="Scaled symbols (circles) where area is proportional to data value. "
                   "Shows magnitude at point locations. Symbol AREA (not radius) "
                   "must scale with value (Flannery correction).",
        required_geometry=["point"],
        supported_data_types=["sequential"],
        classification_methods=[
            ClassificationMethod.NATURAL_BREAKS,
            ClassificationMethod.QUANTILE,
            ClassificationMethod.MANUAL,
        ],
        default_classification=ClassificationMethod.NATURAL_BREAKS,
        default_palette_type="sequential",
        default_n_classes=4,
        legend_type=LegendType.PROPORTIONAL,
        requires_normalization=False,
        supports_basemap=True,
        default_basemap="terrain",
        min_classes=3,
        max_classes=7,
        rendering_notes="Scale radius = sqrt(value * scale_factor / pi) for "
                       "perceptually correct area scaling. Use semi-transparency (0.6) "
                       "to show overlapping symbols. Nested circle legend.",
        default_opacity=0.65,
        default_stroke_width=0.8,
        default_stroke_color="#222222",
    ),

    # ─── 4. DOT DENSITY ──────────────────────────────────────────
    "dot_density": MapTemplate(
        id="dot_density",
        name="Dot Density Map",
        description="Each dot represents a fixed quantity. Dots placed randomly "
                   "within polygons to show distribution patterns. Uses raw counts "
                   "(NOT rates) — the density is inherent in the dot pattern.",
        required_geometry=["polygon"],
        supported_data_types=["sequential"],
        classification_methods=[ClassificationMethod.MANUAL],
        default_classification=ClassificationMethod.MANUAL,
        default_palette_type="qualitative",
        default_n_classes=1,
        legend_type=LegendType.DOT_VALUE,
        requires_normalization=False,  # Must be raw counts
        supports_basemap=True,
        default_basemap="satellite",
        min_classes=1,
        max_classes=4,
        rendering_notes="Dot value = total_sum / desired_dot_count. "
                       "Aim for ~500-2000 dots for visual clarity. "
                       "Dots placed using constrained random within polygon boundaries.",
        default_opacity=0.90,
        show_labels=False,
    ),

    # ─── 5. ISOPLETH (CONTOUR) ───────────────────────────────────
    "isopleth": MapTemplate(
        id="isopleth",
        name="Isopleth / Contour Map",
        description="Lines connecting points of equal value (isolines). "
                   "Shows continuous phenomena like precipitation, temperature, "
                   "or risk gradients. Often combined with filled contours.",
        required_geometry=["raster", "point"],
        supported_data_types=["sequential", "diverging"],
        classification_methods=[
            ClassificationMethod.EQUAL_INTERVAL,
            ClassificationMethod.MANUAL,
            ClassificationMethod.NATURAL_BREAKS,
        ],
        default_classification=ClassificationMethod.EQUAL_INTERVAL,
        default_palette_type="sequential",
        default_n_classes=8,
        legend_type=LegendType.CONTINUOUS,
        requires_normalization=False,
        supports_basemap=True,
        default_basemap="terrain",
        min_classes=5,
        max_classes=15,
        rendering_notes="Generate contours using marching squares on interpolated "
                       "surface. Label contour lines with values. Fill between contours "
                       "with classified colors. Add hillshade underlay for terrain context.",
        default_opacity=0.75,
        default_stroke_width=1.0,
    ),

    # ─── 6. BIVARIATE CHOROPLETH ──────────────────────────────────
    "bivariate_choropleth": MapTemplate(
        id="bivariate_choropleth",
        name="Bivariate Choropleth Map",
        description="Shows two variables simultaneously using a 3x3 (or 4x4) "
                   "color matrix. Each axis maps to a variable, creating 9-16 "
                   "unique color combinations. Powerful but complex to read.",
        required_geometry=["polygon"],
        supported_data_types=["diverging", "sequential"],
        classification_methods=[
            ClassificationMethod.QUANTILE,
            ClassificationMethod.NATURAL_BREAKS,
        ],
        default_classification=ClassificationMethod.QUANTILE,
        default_palette_type="diverging",
        default_n_classes=9,  # 3x3 grid
        legend_type=LegendType.BIVARIATE_MATRIX,
        requires_normalization=True,
        supports_basemap=False,
        default_basemap=None,
        min_classes=4,
        max_classes=16,
        rendering_notes="Use 3x3 grid (9 classes) for readability — 4x4 is too complex "
                       "for most audiences. Pick two corner hues that don't share a channel "
                       "(e.g., blue + red, blue + orange). The diagonal represents correlation.",
        default_opacity=0.90,
        default_stroke_width=0.5,
    ),

    # ─── 7. MULTI-HAZARD RISK ─────────────────────────────────────
    "multi_hazard_risk": MapTemplate(
        id="multi_hazard_risk",
        name="Multi-Hazard Risk Map",
        description="Composite risk surface combining multiple hazard types "
                   "(fire, flood, drought, seismic) into a unified risk index. "
                   "EcoLens signature map type. Uses weighted overlay analysis.",
        required_geometry=["polygon", "point", "raster"],
        supported_data_types=["sequential"],
        classification_methods=[
            ClassificationMethod.NATURAL_BREAKS,
            ClassificationMethod.EQUAL_INTERVAL,
            ClassificationMethod.MANUAL,
        ],
        default_classification=ClassificationMethod.NATURAL_BREAKS,
        default_palette_type="sequential",
        default_n_classes=5,
        legend_type=LegendType.CLASSIFIED,
        requires_normalization=True,
        supports_basemap=True,
        default_basemap="dark",
        min_classes=3,
        max_classes=7,
        rendering_notes="Render risk surface as classified raster. Overlay hazard-specific "
                       "point symbols (fire=flame, flood=water, earthquake=wave). "
                       "Dark basemap with warm color ramp (YlOrRd). "
                       "Include per-hazard breakdown in legend or sidebar.",
        default_opacity=0.80,
        default_stroke_width=0.3,
        show_labels=True,
    ),
}


# ═══════════════════════════════════════════════════════════════════════
# 7 SHOWCASE EXAMPLES — REAL NATURAL DISASTERS
# ═══════════════════════════════════════════════════════════════════════

SHOWCASE_EXAMPLES: list[ShowcaseExample] = [

    # ─── 1. CHOROPLETH: Amazon Deforestation ──────────────────────
    ShowcaseExample(
        id="showcase-amazon-deforestation",
        template_id="choropleth",
        title="Amazon Deforestation Rate by Municipality",
        subtitle="Annual tree cover loss as % of total forest area, 2020-2024",
        disaster_type="deforestation",
        description="Choropleth showing deforestation rates across Brazilian Amazon "
                   "municipalities. Uses natural breaks classification to highlight "
                   "the most critical areas while preserving variation in moderate zones.",
        bbox=(-73.98, -16.50, -44.00, 5.27),
        data_sources=["global_forest_watch", "natural_earth_admin"],
        palette="YlOrRd",
        n_classes=5,
        classification="natural_breaks",
        why_this_template="Choropleth is ideal because we're showing a RATE (% of forest "
                         "lost per year) across defined administrative boundaries. Raw hectares "
                         "would create visual bias toward larger municipalities. Natural breaks "
                         "reveal the natural clustering in deforestation rates.",
        key_findings=[
            "Arc of deforestation clearly visible along southern Amazon frontier",
            "Municipalities near major highways (BR-163, BR-364) show highest rates",
            "Indigenous territories show dramatically lower deforestation rates",
            "Pará state accounts for 40% of total Amazon deforestation",
        ],
        date_range="2020-01-01 to 2024-12-31",
    ),

    # ─── 2. HEATMAP: Australian Bushfires ─────────────────────────
    ShowcaseExample(
        id="showcase-australia-bushfires",
        template_id="heatmap",
        title="2019-2020 Australian Bushfire Intensity",
        subtitle="Kernel density estimation of MODIS fire detections (NASA FIRMS)",
        disaster_type="wildfire",
        description="Heat map showing the spatial concentration of fire detections "
                   "during Australia's catastrophic 2019-2020 bushfire season. "
                   "KDE surface reveals fire corridors and sustained burn zones.",
        bbox=(140.0, -44.0, 154.0, -25.0),
        data_sources=["nasa_firms", "natural_earth_coastline"],
        palette="OrRd",
        n_classes=7,
        classification="natural_breaks",
        why_this_template="Heat map is perfect for fire detection data because individual "
                         "point locations are less meaningful than the PATTERN of fire "
                         "concentration. KDE smooths the raw MODIS detections into a "
                         "continuous intensity surface that reveals fire corridors.",
        key_findings=[
            "NSW and Victoria bore the brunt: continuous fire corridors along Great Dividing Range",
            "Kangaroo Island shows as an isolated high-intensity cluster",
            "Fire followed eucalyptus forest distribution almost exactly",
            "Over 12.6 million hectares burned — visible as sustained red zones",
        ],
        date_range="2019-09-01 to 2020-03-31",
    ),

    # ─── 3. PROPORTIONAL SYMBOL: Global Earthquakes ───────────────
    ShowcaseExample(
        id="showcase-global-earthquakes",
        template_id="proportional_symbol",
        title="Major Earthquakes M6.0+ (2000-2025)",
        subtitle="Circle area proportional to magnitude; color indicates depth",
        disaster_type="earthquake",
        description="Proportional symbol map showing 25 years of major earthquakes. "
                   "Symbol area scales with magnitude (Flannery-corrected). "
                   "Color encodes focal depth (shallow=red, deep=blue).",
        bbox=(-180.0, -60.0, 180.0, 70.0),
        data_sources=["usgs_earthquake", "natural_earth_coastline"],
        palette="YlOrRd",
        n_classes=4,
        classification="natural_breaks",
        why_this_template="Proportional symbols show MAGNITUDE at specific locations — "
                         "each earthquake is a discrete event with a measured value. "
                         "Area scaling prevents the common error of radius scaling "
                         "(which exaggerates differences). Semi-transparency reveals "
                         "overlap along plate boundaries.",
        key_findings=[
            "Ring of Fire clearly delineated by earthquake concentration",
            "2011 Tohoku (M9.1) and 2004 Sumatra (M9.1) dominate visually — correct behavior",
            "Mid-Atlantic Ridge visible as narrow band of moderate events",
            "Mediterranean shows high frequency of moderate earthquakes",
        ],
        date_range="2000-01-01 to 2025-04-01",
    ),

    # ─── 4. DOT DENSITY: Congo Basin Tree Cover Loss ─────────────
    ShowcaseExample(
        id="showcase-congo-tree-loss",
        template_id="dot_density",
        title="Congo Basin Tree Cover Loss",
        subtitle="1 dot = 500 hectares of tree cover loss (2001-2023)",
        disaster_type="deforestation",
        description="Dot density map showing cumulative tree cover loss across "
                   "the Congo Basin. Each dot represents 500 hectares of forest lost. "
                   "The spatial pattern reveals deforestation frontiers.",
        bbox=(8.0, -10.0, 32.0, 8.0),
        data_sources=["global_forest_watch", "natural_earth_admin"],
        palette="OrRd",
        n_classes=1,
        classification="manual",
        why_this_template="Dot density is the right choice when we want to show raw COUNTS "
                         "(hectares of forest lost) without normalizing by area. Unlike "
                         "choropleth, dot density naturally shows distribution WITHIN "
                         "regions — deforestation along roads and rivers becomes visible.",
        key_findings=[
            "DRC shows concentrated loss along major rivers (navigation routes for logging)",
            "Cameroon-Nigeria border shows agricultural frontier expansion",
            "Central Congo Basin (Salonga) remains largely intact — protected area effect",
            "Eastern DRC shows mining-driven deforestation clusters",
        ],
        date_range="2001-01-01 to 2023-12-31",
    ),

    # ─── 5. ISOPLETH: Bangladesh Flood Risk ──────────────────────
    ShowcaseExample(
        id="showcase-bangladesh-floods",
        template_id="isopleth",
        title="Bangladesh Flood Risk Contour Map",
        subtitle="Interpolated flood risk surface with 10% iso-risk contours",
        disaster_type="flood",
        description="Isopleth map showing flood risk as continuous contour lines "
                   "across Bangladesh's deltaic landscape. Filled contours with "
                   "hillshade underlay reveal the topographic drivers of flood risk.",
        bbox=(87.5, 20.5, 92.7, 26.8),
        data_sources=["copernicus_dem", "worldpop", "natural_earth_admin"],
        palette="PuBu",
        n_classes=8,
        classification="equal_interval",
        why_this_template="Isopleth (contour) maps excel at showing CONTINUOUS spatial "
                         "phenomena. Flood risk varies smoothly across the landscape — "
                         "it doesn't jump at administrative boundaries. Contour lines "
                         "reveal the gradient direction (where risk increases fastest).",
        key_findings=[
            "Lowest-lying delta regions show 90%+ flood probability (Khulna, Barisal)",
            "Sylhet basin identified as secondary high-risk zone (flash floods)",
            "Chittagong Hill Tracts show steep risk gradient — elevation transition zone",
            "Dhaka sits in a moderate risk zone but with extreme population exposure",
        ],
        date_range="Modeled from 1990-2024 historical flood data",
    ),

    # ─── 6. BIVARIATE: East Africa Climate Risk vs Capacity ──────
    ShowcaseExample(
        id="showcase-eastafrica-climate-risk",
        template_id="bivariate_choropleth",
        title="Climate Risk vs Adaptive Capacity — East Africa",
        subtitle="Bivariate 3x3: Red axis = climate hazard exposure, Blue axis = governance capacity",
        disaster_type="drought",
        description="Bivariate choropleth showing the intersection of climate hazard "
                   "exposure (drought, flood, heat stress) and adaptive capacity "
                   "(governance, infrastructure, economic resilience). The most "
                   "vulnerable areas are high-risk AND low-capacity (red corner).",
        bbox=(25.0, -12.0, 52.0, 15.0),
        data_sources=["worldpop", "natural_earth_admin", "copernicus_dem"],
        palette="RdBu",
        n_classes=9,
        classification="quantile",
        why_this_template="Bivariate choropleth answers a question no single-variable map "
                         "can: WHERE does high risk coincide with low capacity? The 3x3 "
                         "color matrix lets viewers instantly identify the most vulnerable "
                         "areas (dark red) vs resilient areas (dark blue).",
        key_findings=[
            "Somalia and South Sudan show worst combination: high risk + low capacity",
            "Kenya coast shows moderate risk but low capacity — hidden vulnerability",
            "Ethiopia highlands show high capacity despite moderate climate risk",
            "Rwanda/Burundi show surprising resilience — strong governance offsets risk",
        ],
        date_range="2024 composite index",
    ),

    # ─── 7. MULTI-HAZARD: Pacific Ring of Fire ───────────────────
    ShowcaseExample(
        id="showcase-pacific-multihazard",
        template_id="multi_hazard_risk",
        title="Multi-Hazard Risk Index — Southeast Asia",
        subtitle="Composite index: earthquake (30%) + volcanic (25%) + flood (25%) + typhoon (20%)",
        disaster_type="multi_hazard",
        description="Multi-hazard risk map combining four hazard types into a unified "
                   "risk surface for Southeast Asia. Uses weighted overlay analysis "
                   "with hazard-specific point symbols overlaid on the risk surface.",
        bbox=(95.0, -11.0, 141.0, 21.0),
        data_sources=["usgs_earthquake", "nasa_firms", "copernicus_dem",
                      "worldpop", "natural_earth_admin"],
        palette="YlOrRd",
        n_classes=5,
        classification="natural_breaks",
        why_this_template="Multi-hazard risk maps are EcoLens's signature product. "
                         "This template composites multiple hazard layers into a single "
                         "actionable risk surface, with individual hazard symbols providing "
                         "specificity. Users see both the 'big picture' and the details.",
        key_findings=[
            "Philippines shows highest composite risk — exposed to ALL four hazard types",
            "Java-Sumatra corridor: volcanic + seismic + flood creates extreme risk band",
            "Bangkok sits in a flood-dominant risk zone with moderate seismic exposure",
            "Borneo interior shows lowest risk — away from plate boundaries and typhoon tracks",
        ],
        date_range="2020-2025 composite analysis",
    ),
]


# ═══════════════════════════════════════════════════════════════════════
# TEMPLATE REGISTRY API
# ═══════════════════════════════════════════════════════════════════════

class TemplateRegistry:
    """
    Registry for map templates and showcase examples.

    Usage:
        registry = TemplateRegistry()
        template = registry.get_template("choropleth")
        examples = registry.get_showcase_examples("heatmap")
        all_templates = registry.list_templates()
    """

    def __init__(self):
        self._templates = TEMPLATES
        self._examples = {e.id: e for e in SHOWCASE_EXAMPLES}

    def get_template(self, template_id: str) -> MapTemplate | None:
        """Get a template by ID."""
        return self._templates.get(template_id)

    def list_templates(self) -> list[dict]:
        """List all templates with basic info."""
        return [
            {
                "id": t.id,
                "name": t.name,
                "description": t.description,
                "default_palette_type": t.default_palette_type,
                "default_n_classes": t.default_n_classes,
                "requires_normalization": t.requires_normalization,
            }
            for t in self._templates.values()
        ]

    def get_showcase_examples(self, template_id: str | None = None) -> list[ShowcaseExample]:
        """Get showcase examples, optionally filtered by template."""
        if template_id:
            return [e for e in SHOWCASE_EXAMPLES if e.template_id == template_id]
        return list(SHOWCASE_EXAMPLES)

    def get_showcase_by_disaster(self, disaster_type: str) -> list[ShowcaseExample]:
        """Get showcase examples by disaster type."""
        return [e for e in SHOWCASE_EXAMPLES if e.disaster_type == disaster_type]

    def recommend_template(
        self,
        geometry_type: str,
        data_type: str,
        has_two_variables: bool = False,
        is_composite: bool = False,
    ) -> MapTemplate:
        """
        Recommend the best template based on data characteristics.

        Args:
            geometry_type: "point", "polygon", "raster", "line"
            data_type: "sequential", "diverging", "qualitative"
            has_two_variables: Whether two variables need simultaneous display
            is_composite: Whether data is a composite index (multi-hazard)
        """
        if is_composite:
            return self._templates["multi_hazard_risk"]

        if has_two_variables and geometry_type == "polygon":
            return self._templates["bivariate_choropleth"]

        if geometry_type == "point":
            # Heatmap for dense points, proportional symbol for sparse
            return self._templates["heatmap"]

        if geometry_type == "polygon":
            return self._templates["choropleth"]

        if geometry_type == "raster":
            return self._templates["isopleth"]

        # Default
        return self._templates["choropleth"]

    def get_template_for_ecolens_theme(self, theme: str) -> MapTemplate:
        """
        EcoLens-specific template recommendation by environmental theme.
        """
        theme_template_map = {
            "deforestation": "choropleth",
            "fire_risk": "heatmap",
            "biodiversity": "heatmap",
            "flood_risk": "isopleth",
            "multi_hazard": "multi_hazard_risk",
            "vegetation_health": "choropleth",
            "change_detection": "choropleth",
            "population_exposure": "proportional_symbol",
            "drought": "isopleth",
            "earthquake": "proportional_symbol",
        }
        template_id = theme_template_map.get(theme, "choropleth")
        return self._templates[template_id]

    def get_all_templates_as_catalog(self) -> dict:
        """
        Return full catalog for the Flutter UI to populate pickers.
        """
        return {
            "templates": [t.to_dict() for t in self._templates.values()],
            "showcase_examples": [
                {
                    "id": e.id,
                    "template_id": e.template_id,
                    "title": e.title,
                    "subtitle": e.subtitle,
                    "disaster_type": e.disaster_type,
                    "description": e.description,
                    "bbox": list(e.bbox),
                    "palette": e.palette,
                    "n_classes": e.n_classes,
                    "why_this_template": e.why_this_template,
                    "key_findings": e.key_findings,
                    "date_range": e.date_range,
                }
                for e in SHOWCASE_EXAMPLES
            ],
        }
