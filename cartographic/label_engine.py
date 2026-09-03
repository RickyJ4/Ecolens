"""
Label Placement Engine

Greedy label placement algorithm based on cartographic best practices:
  - 8 candidate positions per label (compass + diagonal)
  - Priority queue by feature importance
  - Collision detection via bounding box intersection
  - Halo/mask rendering for readability
  - Respects knowledge base typography rules

Falls back to QGIS PAL labeling engine when PyQGIS is available.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

import matplotlib.pyplot as plt
import matplotlib.patheffects as patheffects
from matplotlib.axes import Axes
from matplotlib.figure import Figure


@dataclass
class LabelSpec:
    """Specification for a single label to place."""
    text: str
    x: float                    # Data coordinate (longitude)
    y: float                    # Data coordinate (latitude)
    importance: int             # Higher = more important (placed first)
    font_size: float = 9.0
    font_family: str = "sans-serif"
    font_weight: str = "normal"
    font_style: str = "normal"
    color: str = "#333333"
    halo_color: str = "#ffffff"
    halo_width: float = 1.0
    rotation: float = 0.0       # Degrees
    feature_type: str = "feature"  # For hierarchy lookup
    anchor: str = "auto"        # "auto", "center", or specific position


@dataclass
class PlacedLabel:
    """A label that has been placed with final position."""
    spec: LabelSpec
    offset_x: float             # Offset from anchor in points
    offset_y: float
    position_name: str          # Which of the 8 positions was used
    bbox: tuple[float, float, float, float]  # (x0, y0, x1, y1) in display coords
    placed: bool = True         # False if label couldn't be placed


# 8 candidate offsets (in points) relative to anchor
# Order is priority: right, upper-right, upper-left, left, etc.
_CANDIDATE_OFFSETS = [
    ("right",       ( 6,  0)),
    ("upper-right", ( 5,  5)),
    ("upper-left",  (-5,  5)),
    ("left",        (-6,  0)),
    ("lower-right", ( 5, -5)),
    ("lower-left",  (-5, -5)),
    ("above",       ( 0,  6)),
    ("below",       ( 0, -6)),
]


class LabelEngine:
    """
    Places labels on a matplotlib axes using a greedy algorithm.

    Usage:
        engine = LabelEngine()
        labels = [
            LabelSpec("Jakarta", 106.8, -6.2, importance=10, font_size=11),
            LabelSpec("Bandung", 107.6, -6.9, importance=5, font_size=9),
        ]
        placed = engine.place_labels(ax, labels)
    """

    def __init__(self, max_labels: int = 200, padding: float = 2.0):
        """
        Args:
            max_labels: Maximum labels to attempt placing
            padding: Extra padding (points) around label bounding boxes
        """
        self.max_labels = max_labels
        self.padding = padding

    def place_labels(
        self,
        ax: Axes,
        labels: list[LabelSpec],
        existing_bboxes: list[tuple] | None = None,
    ) -> list[PlacedLabel]:
        """
        Place labels on the axes using greedy collision avoidance.

        Args:
            ax: matplotlib Axes to place labels on
            labels: List of LabelSpec to place
            existing_bboxes: Pre-existing occupied regions to avoid

        Returns:
            List of PlacedLabel with final positions
        """
        # Sort by importance (highest first)
        sorted_labels = sorted(labels, key=lambda l: l.importance, reverse=True)

        # Limit count
        sorted_labels = sorted_labels[:self.max_labels]

        # Track occupied regions
        occupied: list[tuple[float, float, float, float]] = []
        if existing_bboxes:
            occupied.extend(existing_bboxes)

        placed: list[PlacedLabel] = []
        renderer = ax.figure.canvas.get_renderer()

        for spec in sorted_labels:
            result = self._place_single(ax, spec, occupied, renderer)
            placed.append(result)
            if result.placed:
                occupied.append(result.bbox)

        return placed

    def _place_single(
        self,
        ax: Axes,
        spec: LabelSpec,
        occupied: list[tuple],
        renderer,
    ) -> PlacedLabel:
        """Try to place a single label in one of 8 candidate positions."""
        # Create text object (invisible) to measure bbox
        for pos_name, (dx, dy) in _CANDIDATE_OFFSETS:
            text = ax.annotate(
                spec.text,
                xy=(spec.x, spec.y),
                xytext=(dx, dy),
                textcoords="offset points",
                fontsize=spec.font_size,
                fontfamily=spec.font_family,
                fontweight=spec.font_weight,
                fontstyle=spec.font_style,
                color=spec.color,
                rotation=spec.rotation,
                ha=self._ha_for_position(pos_name),
                va=self._va_for_position(pos_name),
                visible=False,
            )

            # Get bounding box in display coordinates
            try:
                bbox = text.get_window_extent(renderer=renderer)
                x0 = bbox.x0 - self.padding
                y0 = bbox.y0 - self.padding
                x1 = bbox.x1 + self.padding
                y1 = bbox.y1 + self.padding
                candidate_bbox = (x0, y0, x1, y1)
            except Exception:
                text.remove()
                continue

            # Check for collisions
            if not self._collides(candidate_bbox, occupied):
                # Accept this position — make visible with halo
                text.remove()
                self._render_label(ax, spec, dx, dy, pos_name)
                return PlacedLabel(
                    spec=spec,
                    offset_x=dx,
                    offset_y=dy,
                    position_name=pos_name,
                    bbox=candidate_bbox,
                    placed=True,
                )
            else:
                text.remove()

        # Could not place — return unplaced
        return PlacedLabel(
            spec=spec,
            offset_x=0,
            offset_y=0,
            position_name="none",
            bbox=(0, 0, 0, 0),
            placed=False,
        )

    def _render_label(
        self,
        ax: Axes,
        spec: LabelSpec,
        dx: float,
        dy: float,
        pos_name: str,
    ):
        """Render the final label with halo effect."""
        effects = [
            patheffects.withStroke(
                linewidth=spec.halo_width * 2,
                foreground=spec.halo_color,
            ),
        ]

        ax.annotate(
            spec.text,
            xy=(spec.x, spec.y),
            xytext=(dx, dy),
            textcoords="offset points",
            fontsize=spec.font_size,
            fontfamily=spec.font_family,
            fontweight=spec.font_weight,
            fontstyle=spec.font_style,
            color=spec.color,
            rotation=spec.rotation,
            ha=self._ha_for_position(pos_name),
            va=self._va_for_position(pos_name),
            path_effects=effects,
            zorder=100,
        )

    @staticmethod
    def _collides(
        candidate: tuple[float, float, float, float],
        occupied: list[tuple[float, float, float, float]],
    ) -> bool:
        """Check if candidate bbox overlaps any occupied region."""
        cx0, cy0, cx1, cy1 = candidate
        for ox0, oy0, ox1, oy1 in occupied:
            if cx0 < ox1 and cx1 > ox0 and cy0 < oy1 and cy1 > oy0:
                return True
        return False

    @staticmethod
    def _ha_for_position(pos_name: str) -> str:
        if "right" in pos_name:
            return "left"
        if "left" in pos_name:
            return "right"
        return "center"

    @staticmethod
    def _va_for_position(pos_name: str) -> str:
        if "upper" in pos_name or pos_name == "above":
            return "bottom"
        if "lower" in pos_name or pos_name == "below":
            return "top"
        return "center"

    def create_labels_from_geojson(
        self,
        geojson: dict,
        label_field: str = "NAME",
        importance_field: str | None = None,
        base_font_size: float = 9.0,
        feature_type: str = "feature",
        color: str = "#333333",
    ) -> list[LabelSpec]:
        """
        Generate LabelSpec list from GeoJSON features.

        Args:
            geojson: GeoJSON FeatureCollection
            label_field: Property key to use as label text
            importance_field: Property key for importance ranking
            base_font_size: Base font size
            feature_type: Feature type for hierarchy lookup
            color: Label color
        """
        labels = []
        features = geojson.get("features", [])

        for i, f in enumerate(features):
            props = f.get("properties", {})
            text = props.get(label_field) or props.get(label_field.lower())
            if not text:
                continue

            # Get centroid coordinates
            geom = f.get("geometry", {})
            centroid = self._get_centroid(geom)
            if not centroid:
                continue

            importance = 0
            if importance_field and importance_field in props:
                importance = props[importance_field]
            else:
                importance = len(features) - i  # Order-based

            labels.append(LabelSpec(
                text=str(text),
                x=centroid[0],
                y=centroid[1],
                importance=int(importance),
                font_size=base_font_size,
                feature_type=feature_type,
                color=color,
            ))

        return labels

    @staticmethod
    def _get_centroid(geometry: dict) -> tuple[float, float] | None:
        """Get approximate centroid of a GeoJSON geometry."""
        geo_type = geometry.get("type", "")
        coords = geometry.get("coordinates", [])

        if geo_type == "Point":
            return (coords[0], coords[1]) if len(coords) >= 2 else None

        if geo_type == "MultiPoint":
            if not coords:
                return None
            xs = [c[0] for c in coords]
            ys = [c[1] for c in coords]
            return (sum(xs) / len(xs), sum(ys) / len(ys))

        if geo_type in ("Polygon", "MultiPolygon"):
            # Flatten and average
            flat = _flatten_coords_recursive(coords)
            if not flat:
                return None
            xs = [c[0] for c in flat]
            ys = [c[1] for c in flat]
            return (sum(xs) / len(xs), sum(ys) / len(ys))

        if geo_type in ("LineString", "MultiLineString"):
            flat = _flatten_coords_recursive(coords)
            if not flat:
                return None
            mid = flat[len(flat) // 2]
            return (mid[0], mid[1])

        return None


def _flatten_coords_recursive(coords, depth=0) -> list[tuple[float, float]]:
    """Flatten nested coordinate arrays."""
    if depth > 5 or not coords:
        return []
    if isinstance(coords[0], (int, float)):
        return [(coords[0], coords[1])]
    result = []
    for item in coords:
        result.extend(_flatten_coords_recursive(item, depth + 1))
    return result
