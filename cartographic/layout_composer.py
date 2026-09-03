"""
Layout Composer

Handles all map furniture (marginalia) following cartographic conventions:
  - Title block (title, subtitle, timestamp)
  - Legend (classified, continuous, proportional, bivariate matrix)
  - Scale bar (with computed ground distance)
  - North arrow (only when needed)
  - Source attribution
  - Coordinate grid / graticule
  - Inset/locator map

Layout proportions validated against knowledge base rules:
  - Map body: 60-80% of total area
  - Margins: >= 3% each side
  - Legend within 5% of map body edge
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.patheffects as patheffects
from matplotlib.axes import Axes
from matplotlib.figure import Figure
import numpy as np


@dataclass
class LayoutMetrics:
    """Measured layout proportions for validation."""
    map_body_ratio: float
    margin_top: float
    margin_bottom: float
    margin_left: float
    margin_right: float
    legend_area_ratio: float
    title_position: str
    has_scale_bar: bool
    has_north_arrow: bool
    has_source_attribution: bool
    projection_is_north_up: bool
    map_aspect: float
    geo_aspect: float
    source_attribution_visible: bool

    def to_dict(self) -> dict:
        return {
            "map_body_ratio": round(self.map_body_ratio, 3),
            "margin_top": round(self.margin_top, 3),
            "margin_bottom": round(self.margin_bottom, 3),
            "margin_left": round(self.margin_left, 3),
            "margin_right": round(self.margin_right, 3),
            "legend_area_ratio": round(self.legend_area_ratio, 3),
            "title_position": self.title_position,
            "has_scale_bar": self.has_scale_bar,
            "has_north_arrow": self.has_north_arrow,
            "source_attribution_visible": self.source_attribution_visible,
            "projection_is_north_up": self.projection_is_north_up,
            "map_aspect": round(self.map_aspect, 3),
            "geo_aspect": round(self.geo_aspect, 3),
        }


class LayoutComposer:
    """
    Composes professional map layouts with all required marginalia.

    Usage:
        composer = LayoutComposer()
        fig, ax_map = composer.create_layout(
            width_inches=16, height_inches=12,
            title="Deforestation Rates — Amazon Basin",
            subtitle="Annual tree cover loss 2020-2024",
        )
        # ... render data on ax_map ...
        composer.add_legend(fig, legend_spec)
        composer.add_scale_bar(ax_map, center_lat=-5.0)
        composer.add_source_attribution(fig, ["NASA FIRMS", "GFW"])
        metrics = composer.compute_metrics()
    """

    # Standard EcoLens typography
    TITLE_FONT = {
        "family": "sans-serif",
        "weight": "bold",
        "size": 18,
    }
    SUBTITLE_FONT = {
        "family": "sans-serif",
        "weight": "normal",
        "size": 11,
        "color": "#666666",
    }
    CREDIT_FONT = {
        "family": "sans-serif",
        "weight": "normal",
        "size": 7,
        "color": "#888888",
    }
    LEGEND_TITLE_FONT = {
        "family": "sans-serif",
        "weight": "semibold",
        "size": 10,
    }
    LEGEND_LABEL_FONT = {
        "family": "sans-serif",
        "weight": "normal",
        "size": 8,
    }

    def __init__(self):
        self._fig: Figure | None = None
        self._ax_map: Axes | None = None
        self._has_scale_bar = False
        self._has_north_arrow = False
        self._has_attribution = False
        self._title_position = "top-center"
        self._attribution_texts: list[str] = []

    def create_layout(
        self,
        width_inches: float = 16,
        height_inches: float = 12,
        title: str | None = None,
        subtitle: str | None = None,
        dpi: int = 150,
        background_color: str = "#ffffff",
        dark_mode: bool = False,
    ) -> tuple[Figure, Axes]:
        """
        Create the figure and map axes with proper proportions.

        Returns (fig, ax_map) — ax_map is the main map axes.
        """
        if dark_mode:
            background_color = "#1a1a2e"
            plt.rcParams.update({
                "text.color": "#e0e0e0",
                "axes.labelcolor": "#e0e0e0",
                "xtick.color": "#888888",
                "ytick.color": "#888888",
            })

        fig = plt.figure(figsize=(width_inches, height_inches), dpi=dpi,
                        facecolor=background_color)
        self._fig = fig

        # Layout: map body takes ~72% of figure area
        # Margins: top 12% (title), bottom 8% (credits), left/right 5%
        top_margin = 0.08
        bottom_margin = 0.06
        left_margin = 0.05
        right_margin = 0.05

        if title:
            top_margin = 0.12

        ax_map = fig.add_axes([
            left_margin,
            bottom_margin,
            1.0 - left_margin - right_margin,
            1.0 - top_margin - bottom_margin,
        ])

        # Style the map axes
        ax_map.set_facecolor("#f0f0f0" if not dark_mode else "#16213e")
        for spine in ax_map.spines.values():
            spine.set_color("#cccccc" if not dark_mode else "#333333")
            spine.set_linewidth(0.5)

        self._ax_map = ax_map

        # Add title
        if title:
            self._add_title(fig, title, subtitle, dark_mode)

        return fig, ax_map

    def _add_title(
        self,
        fig: Figure,
        title: str,
        subtitle: str | None = None,
        dark_mode: bool = False,
    ):
        """Add title block to the figure."""
        title_color = "#1a1a1a" if not dark_mode else "#e0e0e0"
        sub_color = "#666666" if not dark_mode else "#999999"

        fig.text(
            0.5, 0.96,
            title,
            ha="center", va="top",
            fontsize=self.TITLE_FONT["size"],
            fontweight=self.TITLE_FONT["weight"],
            fontfamily=self.TITLE_FONT["family"],
            color=title_color,
        )

        if subtitle:
            fig.text(
                0.5, 0.93,
                subtitle,
                ha="center", va="top",
                fontsize=self.SUBTITLE_FONT["size"],
                fontweight=self.SUBTITLE_FONT["weight"],
                fontfamily=self.SUBTITLE_FONT["family"],
                color=sub_color,
            )

        self._title_position = "top-center"

    def add_classified_legend(
        self,
        ax: Axes,
        colors: list[str],
        labels: list[str],
        title: str = "Legend",
        position: str = "lower-right",
    ):
        """
        Add a classified (discrete swatch) legend.

        Args:
            ax: Map axes
            colors: Hex colors for each class
            labels: Labels for each class
            title: Legend title
            position: "lower-right", "lower-left", "upper-right", "upper-left"
        """
        patches = []
        for color, label in zip(colors, labels):
            patches.append(mpatches.Patch(
                facecolor=color,
                edgecolor="#333333",
                linewidth=0.5,
                label=label,
            ))

        loc_map = {
            "lower-right": "lower right",
            "lower-left": "lower left",
            "upper-right": "upper right",
            "upper-left": "upper left",
        }
        loc = loc_map.get(position, "lower right")

        legend = ax.legend(
            handles=patches,
            title=title,
            loc=loc,
            fontsize=self.LEGEND_LABEL_FONT["size"],
            title_fontsize=self.LEGEND_TITLE_FONT["size"],
            frameon=True,
            framealpha=0.9,
            edgecolor="#cccccc",
            fancybox=False,
            borderpad=0.8,
            labelspacing=0.4,
            handlelength=1.2,
            handleheight=0.8,
        )
        legend.get_frame().set_linewidth(0.5)

    def add_continuous_legend(
        self,
        fig: Figure,
        ax: Axes,
        vmin: float,
        vmax: float,
        cmap_name: str,
        title: str = "",
        orientation: str = "vertical",
    ):
        """Add a continuous color bar legend."""
        import matplotlib.cm as cm
        from matplotlib.colors import Normalize

        norm = Normalize(vmin=vmin, vmax=vmax)
        sm = cm.ScalarMappable(norm=norm, cmap=cmap_name)
        sm.set_array([])

        if orientation == "vertical":
            cax = fig.add_axes([0.92, 0.15, 0.015, 0.5])
        else:
            cax = fig.add_axes([0.25, 0.04, 0.5, 0.015])

        cbar = fig.colorbar(sm, cax=cax, orientation=orientation)
        cbar.set_label(title, fontsize=self.LEGEND_TITLE_FONT["size"])
        cbar.ax.tick_params(labelsize=self.LEGEND_LABEL_FONT["size"])

    def add_proportional_legend(
        self,
        ax: Axes,
        legend_entries: list[dict],
        title: str = "Legend",
        position: str = "lower-right",
        color: str = "#3388ff",
    ):
        """
        Add a proportional symbol (nested circles) legend.

        Args:
            legend_entries: List of {"value": float, "size": float, "label": str}
        """
        handles = []
        for entry in reversed(legend_entries):  # Largest first
            handles.append(plt.scatter(
                [], [],
                s=entry["size"] ** 2,
                c=color,
                alpha=0.6,
                edgecolors="#222222",
                linewidths=0.8,
                label=entry["label"],
            ))

        loc_map = {
            "lower-right": "lower right",
            "lower-left": "lower left",
            "upper-right": "upper right",
            "upper-left": "upper left",
        }

        legend = ax.legend(
            handles=handles,
            title=title,
            loc=loc_map.get(position, "lower right"),
            fontsize=self.LEGEND_LABEL_FONT["size"],
            title_fontsize=self.LEGEND_TITLE_FONT["size"],
            frameon=True,
            framealpha=0.9,
            edgecolor="#cccccc",
            scatterpoints=1,
            labelspacing=1.5,
        )
        legend.get_frame().set_linewidth(0.5)

    def add_scale_bar(
        self,
        ax: Axes,
        center_lat: float,
        position: str = "lower-left",
        bar_length_km: float | None = None,
        dark_mode: bool = False,
    ):
        """
        Add a scale bar to the map.

        Auto-calculates appropriate length based on map extent.
        """
        xlim = ax.get_xlim()
        ylim = ax.get_ylim()

        # Calculate map width in km
        map_width_deg = xlim[1] - xlim[0]
        meters_per_deg = 111320 * math.cos(math.radians(center_lat))
        map_width_km = map_width_deg * meters_per_deg / 1000

        # Choose nice bar length (~15% of map width)
        if bar_length_km is None:
            target = map_width_km * 0.15
            nice_lengths = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
            bar_length_km = min(nice_lengths, key=lambda x: abs(x - target))

        # Convert bar length back to degrees
        bar_length_deg = bar_length_km * 1000 / meters_per_deg

        # Position
        if "left" in position:
            x_start = xlim[0] + map_width_deg * 0.05
        else:
            x_start = xlim[1] - map_width_deg * 0.05 - bar_length_deg

        map_height = ylim[1] - ylim[0]
        if "lower" in position:
            y_pos = ylim[0] + map_height * 0.05
        else:
            y_pos = ylim[1] - map_height * 0.05

        bar_color = "#333333" if not dark_mode else "#cccccc"
        text_color = "#333333" if not dark_mode else "#e0e0e0"

        # Draw the bar
        bar_height = map_height * 0.005
        ax.add_patch(plt.Rectangle(
            (x_start, y_pos),
            bar_length_deg, bar_height,
            facecolor=bar_color,
            edgecolor=bar_color,
            linewidth=0.5,
            zorder=50,
        ))

        # Alternating pattern (two halves)
        half = bar_length_deg / 2
        ax.add_patch(plt.Rectangle(
            (x_start + half, y_pos),
            half, bar_height,
            facecolor="#ffffff" if not dark_mode else "#555555",
            edgecolor=bar_color,
            linewidth=0.5,
            zorder=51,
        ))

        # Label
        label = f"{bar_length_km} km"
        ax.text(
            x_start + bar_length_deg / 2,
            y_pos + bar_height * 3,
            label,
            ha="center", va="bottom",
            fontsize=7,
            fontfamily="sans-serif",
            color=text_color,
            zorder=52,
            path_effects=[
                patheffects.withStroke(linewidth=2, foreground="white" if not dark_mode else "#1a1a2e"),
            ],
        )

        self._has_scale_bar = True

    def add_north_arrow(
        self,
        ax: Axes,
        position: str = "upper-right",
        dark_mode: bool = False,
    ):
        """Add a north arrow to the map."""
        xlim = ax.get_xlim()
        ylim = ax.get_ylim()
        w = xlim[1] - xlim[0]
        h = ylim[1] - ylim[0]

        if "right" in position:
            x = xlim[1] - w * 0.05
        else:
            x = xlim[0] + w * 0.05

        if "upper" in position:
            y = ylim[1] - h * 0.05
        else:
            y = ylim[0] + h * 0.15

        arrow_len = h * 0.06
        color = "#333333" if not dark_mode else "#cccccc"

        ax.annotate(
            "N",
            xy=(x, y + arrow_len),
            xytext=(x, y),
            fontsize=10,
            fontweight="bold",
            ha="center", va="bottom",
            color=color,
            arrowprops=dict(
                arrowstyle="->",
                color=color,
                lw=1.5,
            ),
            zorder=50,
        )

        self._has_north_arrow = True

    def add_source_attribution(
        self,
        fig: Figure,
        attributions: list[str],
        timestamp: str | None = None,
        dark_mode: bool = False,
    ):
        """Add data source credits at the bottom of the map."""
        credit_parts = []
        if timestamp:
            credit_parts.append(f"Generated: {timestamp}")
        credit_parts.append("Data: " + " | ".join(attributions))
        credit_parts.append("Map: EcoLens Cartographic Intelligence Engine")

        credit_text = "  •  ".join(credit_parts)
        text_color = "#888888" if not dark_mode else "#666666"

        fig.text(
            0.5, 0.01,
            credit_text,
            ha="center", va="bottom",
            fontsize=self.CREDIT_FONT["size"],
            fontfamily=self.CREDIT_FONT["family"],
            color=text_color,
            style="italic",
        )

        self._has_attribution = True
        self._attribution_texts = attributions

    def add_graticule(
        self,
        ax: Axes,
        interval_deg: float | None = None,
        dark_mode: bool = False,
    ):
        """Add coordinate grid lines and labels."""
        xlim = ax.get_xlim()
        ylim = ax.get_ylim()

        if interval_deg is None:
            # Auto-calculate nice interval
            span = max(xlim[1] - xlim[0], ylim[1] - ylim[0])
            nice = [0.1, 0.5, 1, 2, 5, 10, 15, 30]
            interval_deg = min(nice, key=lambda x: abs(span / x - 5))

        grid_color = "#cccccc" if not dark_mode else "#333333"
        label_color = "#999999" if not dark_mode else "#555555"

        ax.set_axisbelow(True)
        ax.grid(True, linewidth=0.3, color=grid_color, alpha=0.5, zorder=0)

        # Set tick interval
        import matplotlib.ticker as ticker
        ax.xaxis.set_major_locator(ticker.MultipleLocator(interval_deg))
        ax.yaxis.set_major_locator(ticker.MultipleLocator(interval_deg))

        ax.tick_params(
            axis="both", which="major",
            labelsize=6, colors=label_color,
            length=3, width=0.5,
        )

        # Format as lat/lon
        ax.xaxis.set_major_formatter(ticker.FuncFormatter(
            lambda x, p: f"{abs(x):.1f}°{'E' if x >= 0 else 'W'}"
        ))
        ax.yaxis.set_major_formatter(ticker.FuncFormatter(
            lambda y, p: f"{abs(y):.1f}°{'N' if y >= 0 else 'S'}"
        ))

    def compute_metrics(
        self,
        bbox: tuple[float, float, float, float] | None = None,
        projection_is_north_up: bool = True,
    ) -> LayoutMetrics:
        """
        Compute layout metrics for validation against knowledge base rules.
        """
        fig = self._fig
        ax = self._ax_map

        if fig is None or ax is None:
            return LayoutMetrics(
                map_body_ratio=0.7,
                margin_top=0.05, margin_bottom=0.05,
                margin_left=0.05, margin_right=0.05,
                legend_area_ratio=0.08,
                title_position="top-center",
                has_scale_bar=False,
                has_north_arrow=False,
                has_source_attribution=False,
                projection_is_north_up=True,
                map_aspect=1.0, geo_aspect=1.0,
                source_attribution_visible=False,
            )

        # Get axes position in figure coordinates
        pos = ax.get_position()

        map_body_ratio = pos.width * pos.height
        margin_left = pos.x0
        margin_right = 1.0 - (pos.x0 + pos.width)
        margin_bottom = pos.y0
        margin_top = 1.0 - (pos.y0 + pos.height)

        # Map aspect ratio
        fig_w, fig_h = fig.get_size_inches()
        map_aspect = (pos.width * fig_w) / (pos.height * fig_h) if pos.height > 0 else 1.0

        # Geographic aspect ratio
        geo_aspect = 1.0
        if bbox:
            geo_w = bbox[2] - bbox[0]
            geo_h = bbox[3] - bbox[1]
            if geo_h > 0:
                # Correct for latitude
                center_lat = (bbox[1] + bbox[3]) / 2
                geo_w_corrected = geo_w * math.cos(math.radians(center_lat))
                geo_aspect = geo_w_corrected / geo_h

        # Legend area (approximate)
        legend_area = 0.08  # Default estimate
        if ax.get_legend():
            try:
                renderer = fig.canvas.get_renderer()
                lb = ax.get_legend().get_window_extent(renderer)
                fig_area = fig_w * fig_h * fig.dpi * fig.dpi
                legend_area = (lb.width * lb.height) / fig_area
            except Exception:
                pass

        return LayoutMetrics(
            map_body_ratio=map_body_ratio,
            margin_top=margin_top,
            margin_bottom=margin_bottom,
            margin_left=margin_left,
            margin_right=margin_right,
            legend_area_ratio=legend_area,
            title_position=self._title_position,
            has_scale_bar=self._has_scale_bar,
            has_north_arrow=self._has_north_arrow,
            has_source_attribution=self._has_attribution,
            projection_is_north_up=projection_is_north_up,
            map_aspect=map_aspect,
            geo_aspect=geo_aspect,
            source_attribution_visible=self._has_attribution,
        )
