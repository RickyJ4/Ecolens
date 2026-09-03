"""
EcoLens Cartographic Intelligence Engine

Publication-quality map generation powered by codified cartographic principles
from 1000+ award-winning maps (ICA, NACIS, ESRI Map Gallery).

Modules:
    knowledge_base      - 6 rule categories from Bertin, Brewer, Tufte, Robinson
    map_reference_db    - Reference database of ~100 exemplar award-winning maps
    color_systems       - ColorBrewer palettes, perceptual uniformity, colorblind safety
    projection_advisor  - Auto projection selection by extent and purpose
    templates           - Map type templates (choropleth, dot density, etc.)
    data_pipeline       - Credible data source registry and fetching
    composition_engine  - matplotlib/cartopy + PyQGIS rendering
    quality_validator   - 6-dimension scoring and auto-correction
"""

__version__ = "0.1.0"
