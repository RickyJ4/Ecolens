"""
Symbol Designer

Cartographic symbol design for map features:
  - Proportional symbols (area-scaled circles, Flannery correction)
  - Graduated colors (classified fills)
  - Hazard-specific icons (fire, flood, earthquake, drought)
  - Pattern fills for qualitative data
  - Point markers with custom shapes
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import numpy as np


@dataclass
class SymbolSpec:
    """Specification for a map symbol."""
    shape: str = "circle"          # circle, square, triangle, diamond, star
    size_px: float = 10.0          # Size in pixels (or points)
    fill_color: str = "#3388ff"
    stroke_color: str = "#222222"
    stroke_width: float = 0.8
    opacity: float = 0.75
    label: str | None = None
    zorder: int = 10


class SymbolDesigner:
    """
    Designs cartographic symbols following professional standards.

    Key principles:
    - Proportional symbols: area scales with value (Flannery 1971)
    - Min/max size constraints for readability
    - Semi-transparency for overlapping symbols
    - Consistent visual hierarchy
    """

    # Flannery perceptual scaling exponent
    # People underestimate circle area — Flannery found 0.5716 corrects for this
    FLANNERY_EXPONENT = 0.5716

    # Size constraints (in points)
    MIN_SYMBOL_SIZE = 3.0
    MAX_SYMBOL_SIZE = 60.0

    # ─── HAZARD SYMBOLS ──────────────────────────────────────────

    HAZARD_MARKERS = {
        "wildfire": {
            "marker": "^",    # Triangle (flame-like)
            "color": "#FF4500",
            "edge_color": "#8B0000",
            "label": "Wildfire",
        },
        "flood": {
            "marker": "v",    # Inverted triangle (water drop)
            "color": "#1E90FF",
            "edge_color": "#00008B",
            "label": "Flood",
        },
        "earthquake": {
            "marker": "*",    # Star (seismic burst)
            "color": "#FFD700",
            "edge_color": "#B8860B",
            "label": "Earthquake",
        },
        "drought": {
            "marker": "D",    # Diamond
            "color": "#DEB887",
            "edge_color": "#8B4513",
            "label": "Drought",
        },
        "volcano": {
            "marker": "^",    # Triangle
            "color": "#FF6347",
            "edge_color": "#8B0000",
            "label": "Volcano",
        },
        "tsunami": {
            "marker": "s",    # Square
            "color": "#4169E1",
            "edge_color": "#00008B",
            "label": "Tsunami",
        },
        "landslide": {
            "marker": "p",    # Pentagon
            "color": "#A0522D",
            "edge_color": "#654321",
            "label": "Landslide",
        },
    }

    def proportional_sizes(
        self,
        values: list[float],
        min_size: float | None = None,
        max_size: float | None = None,
        use_flannery: bool = True,
    ) -> list[float]:
        """
        Calculate proportional symbol sizes from data values.

        Uses area-proportional scaling (sqrt) with optional Flannery
        perceptual correction.

        Args:
            values: Data values to scale
            min_size: Minimum symbol size (points)
            max_size: Maximum symbol size (points)
            use_flannery: Apply Flannery perceptual correction

        Returns:
            List of symbol sizes in points
        """
        min_s = min_size or self.MIN_SYMBOL_SIZE
        max_s = max_size or self.MAX_SYMBOL_SIZE

        if not values:
            return []

        min_val = min(v for v in values if v > 0) if any(v > 0 for v in values) else 0.001
        max_val = max(values) or 1.0

        sizes = []
        for v in values:
            if v <= 0:
                sizes.append(min_s)
                continue

            # Normalize to 0-1
            normalized = (v - min_val) / (max_val - min_val) if max_val > min_val else 0.5

            if use_flannery:
                # Flannery perceptual scaling
                scaled = normalized ** self.FLANNERY_EXPONENT
            else:
                # Standard area-proportional (sqrt)
                scaled = math.sqrt(normalized)

            # Map to size range
            size = min_s + scaled * (max_s - min_s)
            sizes.append(size)

        return sizes

    def graduated_colors(
        self,
        values: list[float],
        palette: list[str],
        breaks: list[float] | None = None,
        method: str = "natural_breaks",
    ) -> list[str]:
        """
        Assign colors to values based on classification.

        Args:
            values: Data values
            palette: List of hex colors (one per class)
            breaks: Manual break points (optional)
            method: Classification method if breaks not provided

        Returns:
            List of hex colors, one per value
        """
        n_classes = len(palette)

        if breaks is None:
            breaks = self._compute_breaks(values, n_classes, method)

        colors = []
        for v in values:
            class_idx = 0
            for i, brk in enumerate(breaks):
                if v > brk:
                    class_idx = min(i + 1, n_classes - 1)
            colors.append(palette[min(class_idx, len(palette) - 1)])

        return colors

    def get_hazard_marker(self, hazard_type: str) -> dict:
        """Get marker specification for a hazard type."""
        return self.HAZARD_MARKERS.get(
            hazard_type,
            {
                "marker": "o",
                "color": "#808080",
                "edge_color": "#404040",
                "label": hazard_type.title(),
            },
        )

    def create_legend_symbols(
        self,
        values: list[float],
        sizes: list[float],
        n_legend: int = 4,
    ) -> list[dict]:
        """
        Create representative symbols for a proportional symbol legend.

        Returns the classic "nested circles" legend entries.
        """
        if not values or not sizes:
            return []

        # Pick representative values (min, ~33%, ~66%, max)
        sorted_pairs = sorted(zip(values, sizes), key=lambda x: x[0])
        n = len(sorted_pairs)

        indices = [0]
        for frac in [0.33, 0.66]:
            indices.append(int(frac * (n - 1)))
        indices.append(n - 1)

        # Remove duplicates while preserving order
        seen = set()
        unique_indices = []
        for idx in indices:
            if idx not in seen:
                seen.add(idx)
                unique_indices.append(idx)

        entries = []
        for idx in unique_indices[:n_legend]:
            val, size = sorted_pairs[idx]
            entries.append({
                "value": val,
                "size": size,
                "label": self._format_value(val),
            })

        return entries

    def bivariate_color_matrix(
        self,
        palette_x: list[str],
        palette_y: list[str],
    ) -> list[list[str]]:
        """
        Generate a bivariate color matrix by blending two palettes.

        Args:
            palette_x: Colors for x-axis variable (e.g., 3 colors)
            palette_y: Colors for y-axis variable (e.g., 3 colors)

        Returns:
            2D list of hex colors [y][x]
        """
        matrix = []
        for y_color in palette_y:
            row = []
            for x_color in palette_x:
                blended = self._blend_colors(x_color, y_color)
                row.append(blended)
            matrix.append(row)
        return matrix

    @staticmethod
    def _blend_colors(hex1: str, hex2: str, weight: float = 0.5) -> str:
        """Blend two hex colors."""
        h1 = hex1.lstrip("#")
        h2 = hex2.lstrip("#")

        r = int(int(h1[0:2], 16) * weight + int(h2[0:2], 16) * (1 - weight))
        g = int(int(h1[2:4], 16) * weight + int(h2[2:4], 16) * (1 - weight))
        b = int(int(h1[4:6], 16) * weight + int(h2[4:6], 16) * (1 - weight))

        return f"#{min(255,r):02x}{min(255,g):02x}{min(255,b):02x}"

    @staticmethod
    def _compute_breaks(
        values: list[float],
        n_classes: int,
        method: str,
    ) -> list[float]:
        """Compute classification breaks."""
        arr = np.array([v for v in values if not np.isnan(v)])
        if len(arr) == 0:
            return [0.0] * (n_classes - 1)

        if method == "natural_breaks":
            try:
                import mapclassify
                classifier = mapclassify.NaturalBreaks(arr, k=n_classes)
                return list(classifier.bins[:-1])
            except Exception:
                method = "quantile"  # Fallback

        if method == "quantile":
            percentiles = np.linspace(0, 100, n_classes + 1)[1:-1]
            return list(np.percentile(arr, percentiles))

        if method == "equal_interval":
            mn, mx = arr.min(), arr.max()
            step = (mx - mn) / n_classes
            return [mn + step * i for i in range(1, n_classes)]

        if method == "std_deviation":
            mean = arr.mean()
            std = arr.std()
            return [mean + std * i for i in range(-n_classes // 2 + 1, n_classes // 2 + 1)]

        # Default: equal interval
        mn, mx = arr.min(), arr.max()
        step = (mx - mn) / n_classes
        return [mn + step * i for i in range(1, n_classes)]

    @staticmethod
    def _format_value(v: float) -> str:
        """Format a numeric value for legend labels."""
        if abs(v) >= 1_000_000:
            return f"{v/1_000_000:.1f}M"
        if abs(v) >= 1_000:
            return f"{v/1_000:.1f}K"
        if abs(v) >= 10:
            return f"{v:.0f}"
        if abs(v) >= 1:
            return f"{v:.1f}"
        return f"{v:.2f}"
