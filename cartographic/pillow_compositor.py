"""
Pillow Map Compositor

Takes a raw map image from QGIS and composites it into a final
professional cartographic product with pixel-perfect control over:
  - Title block (large, bold, unmissable)
  - Subtitle / description
  - Legend (color gradient bar + classified swatches)
  - Scale bar
  - Source attribution
  - Data summary

This separation of concerns is how professional cartographic
workflows operate: the spatial renderer (QGIS) handles map content,
the layout tool (this module) handles graphic design.
"""

from __future__ import annotations

import io
import math
from typing import Any

from PIL import Image, ImageDraw, ImageFont

import logging
logger = logging.getLogger(__name__)


def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Load Noto Sans font, fall back to default if not available."""
    font_paths = [
        "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/truetype/noto/NotoSans-SemiBold.ttf" if bold
        else "/usr/share/fonts/truetype/noto/NotoSans-Medium.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in font_paths:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def compose_final_image(
    map_image_bytes: bytes,
    title: str = "",
    subtitle: str = "",
    legend_items: list[dict] | None = None,
    attributions: list[str] | None = None,
    data_summary: str = "",
    dark_mode: bool = True,
    scale_km: float | None = None,
    output_width: int = 4800,
) -> bytes:
    """
    Composite the final map image with professional layout.

    Args:
        map_image_bytes: Raw map PNG from QGIS
        title: Map title
        subtitle: Description text
        legend_items: List of {"label": str, "color": str}
        attributions: Data source credits
        data_summary: e.g. "608 events analyzed | 2020-2025"
        dark_mode: Color scheme
        scale_km: Approximate scale bar distance
        output_width: Final image width in pixels

    Returns:
        Final composed PNG as bytes
    """
    # Load the map image
    map_img = Image.open(io.BytesIO(map_image_bytes)).convert("RGBA")

    # Color scheme
    if dark_mode:
        bg_color = (15, 21, 30)
        text_color = (240, 240, 240)
        text_secondary = (170, 170, 180)
        text_muted = (120, 120, 130)
        panel_bg = (18, 26, 38, 240)
        panel_border = (50, 70, 95)
    else:
        bg_color = (245, 245, 240)
        text_color = (20, 20, 20)
        text_secondary = (80, 80, 80)
        text_muted = (140, 140, 140)
        panel_bg = (255, 255, 255, 240)
        panel_border = (180, 180, 180)

    # Scale factor — fonts must scale with output resolution
    scale = output_width / 1600.0  # Base design at 1600px width

    # Layout dimensions (all scaled)
    margin = int(50 * scale)
    title_h = int(160 * scale) if title else int(20 * scale)
    legend_w = int(420 * scale) if legend_items else 0
    credit_h = int(60 * scale)
    map_area_w = output_width - 2 * margin - legend_w - (int(20 * scale) if legend_w else 0)
    map_area_h = int(map_area_w * map_img.height / map_img.width)
    total_h = margin + title_h + map_area_h + credit_h + margin

    # Create canvas
    canvas = Image.new("RGB", (output_width, total_h), bg_color)
    draw = ImageDraw.Draw(canvas)

    # Load fonts — ALL scaled to output resolution
    font_title = _load_font(int(60 * scale), bold=True)
    font_subtitle = _load_font(int(32 * scale), bold=False)
    font_legend_title = _load_font(int(36 * scale), bold=True)
    font_legend = _load_font(int(28 * scale), bold=False)
    font_credit = _load_font(int(22 * scale), bold=False)
    font_summary = _load_font(int(26 * scale), bold=False)
    font_scale = _load_font(int(28 * scale), bold=True)

    y_cursor = margin

    # ─── TITLE ────────────────────────────────────────────────
    if title:
        draw.text((margin, y_cursor), title, fill=text_color, font=font_title)
        y_cursor += int(85 * scale)

    if subtitle:
        draw.text((margin, y_cursor), subtitle, fill=text_secondary, font=font_subtitle)
        y_cursor += int(45 * scale)

    y_cursor += int(15 * scale)

    # ─── MAP IMAGE ────────────────────────────────────────────
    map_resized = map_img.resize((map_area_w, map_area_h), Image.LANCZOS)
    map_x = margin
    map_y = y_cursor

    # Draw map border
    draw.rectangle(
        [map_x - 2, map_y - 2, map_x + map_area_w + 1, map_y + map_area_h + 1],
        outline=panel_border, width=2,
    )
    canvas.paste(map_resized, (map_x, map_y))

    # ─── SCALE BAR (lower-left inside map) ────────────────────
    if scale_km:
        sb_x = map_x + int(40 * scale)
        sb_y = map_y + map_area_h - int(70 * scale)
        sb_w = int(map_area_w * 0.15)
        sb_h = int(12 * scale)

        # Bar background
        bg_pad = int(15 * scale)
        bar_bg = Image.new("RGBA", (sb_w + bg_pad * 2, int(65 * scale)),
                          (0, 0, 0, 180) if dark_mode else (255, 255, 255, 220))
        canvas.paste(Image.alpha_composite(
            Image.new("RGBA", bar_bg.size, (0, 0, 0, 0)), bar_bg,
        ).convert("RGB"), (sb_x - bg_pad, sb_y - int(5 * scale)))

        # Bar
        bar_y = sb_y + int(30 * scale)
        seg_w = sb_w // 2
        draw.rectangle([sb_x, bar_y, sb_x + seg_w, bar_y + sb_h],
                       fill=(240, 240, 240) if dark_mode else (40, 40, 40))
        draw.rectangle([sb_x + seg_w, bar_y, sb_x + sb_w, bar_y + sb_h],
                       fill=(120, 120, 120) if dark_mode else (160, 160, 160))
        draw.rectangle([sb_x, bar_y, sb_x + sb_w, bar_y + sb_h],
                       outline=(200, 200, 200) if dark_mode else (40, 40, 40), width=int(2 * scale))

        # Labels
        draw.text((sb_x, sb_y), "0", fill=text_color, font=font_scale)
        draw.text((sb_x + sb_w + int(5 * scale), sb_y),
                  f"{scale_km:.0f} km", fill=text_color, font=font_scale)

    # ─── LEGEND (right column) ────────────────────────────────
    if legend_items:
        pad = int(25 * scale)
        leg_x = map_x + map_area_w + int(20 * scale)
        leg_y = map_y
        leg_w = legend_w - int(10 * scale)
        swatch_h = int(30 * scale)
        row_h = int(42 * scale)
        sym_size = int(22 * scale)

        # Legend panel background
        panel = Image.new("RGBA", (leg_w, map_area_h), panel_bg)
        panel_draw = ImageDraw.Draw(panel)
        panel_draw.rectangle([0, 0, leg_w - 1, map_area_h - 1],
                            outline=panel_border, width=int(2 * scale))
        canvas.paste(Image.alpha_composite(
            Image.new("RGBA", panel.size, (0, 0, 0, 0)), panel,
        ).convert("RGB"), (leg_x, leg_y))

        # Legend title
        ly = leg_y + pad
        draw.text((leg_x + pad, ly), "Degree of Risk", fill=text_color, font=font_legend_title)
        ly += int(50 * scale)

        # Separator
        draw.line([(leg_x + pad, ly), (leg_x + leg_w - pad, ly)],
                  fill=panel_border, width=int(2 * scale))
        ly += int(20 * scale)

        # Color swatches — WIDE rectangles with labels
        bar_x = leg_x + pad
        bar_w = leg_w - 2 * pad

        # Swatches: color block on left, label on right (same row)
        swatch_block_w = int(50 * scale)
        for i, item in enumerate(legend_items):
            color = hex_to_rgb(item["color"])
            swatch_y = ly + i * row_h

            # Color swatch (left)
            draw.rectangle(
                [bar_x, swatch_y, bar_x + swatch_block_w, swatch_y + swatch_h],
                fill=color,
                outline=(80, 80, 80) if dark_mode else (160, 160, 160),
                width=max(1, int(1 * scale)),
            )
            # Label (right of swatch, same row)
            draw.text(
                (bar_x + swatch_block_w + int(12 * scale), swatch_y + int(4 * scale)),
                item["label"],
                fill=text_secondary,
                font=font_legend,
            )

        # Symbols section
        ly = ly + len(legend_items) * row_h + int(30 * scale)
        draw.line([(leg_x + pad, ly), (leg_x + leg_w - pad, ly)],
                  fill=panel_border, width=int(2 * scale))
        ly += int(20 * scale)

        draw.text((leg_x + pad, ly), "Symbols", fill=text_color, font=font_legend_title)
        ly += int(50 * scale)

        sx = leg_x + pad
        tx = sx + sym_size + int(15 * scale)

        # City marker (diamond)
        d = sym_size // 2
        cx = sx + d
        draw.polygon(
            [(cx, ly), (cx + d, ly + d), (cx, ly + sym_size), (cx - d, ly + d)],
            fill=(255, 255, 255) if dark_mode else (40, 40, 40),
            outline=(0, 0, 0), width=int(2 * scale),
        )
        draw.text((tx, ly + int(2 * scale)), "City (population)", fill=text_secondary, font=font_legend)
        ly += int(45 * scale)

        # Impact circle
        draw.ellipse([sx, ly, sx + sym_size, ly + sym_size],
                    outline=(255, 70, 70), width=int(3 * scale))
        draw.text((tx, ly + int(2 * scale)), "Major event radius", fill=text_secondary, font=font_legend)
        ly += int(45 * scale)

        # Data dot
        dot_r = int(6 * scale)
        dot_cx = sx + sym_size // 2
        dot_cy = ly + sym_size // 2
        draw.ellipse([dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
                    fill=(255, 255, 255) if dark_mode else (100, 100, 100))
        draw.text((tx, ly + int(2 * scale)), "Earthquake detection", fill=text_secondary, font=font_legend)

        # Data summary at bottom of legend
        if data_summary:
            ly = leg_y + map_area_h - int(60 * scale)
            draw.text((leg_x + pad, ly), data_summary, fill=text_muted, font=font_summary)

    # ─── ATTRIBUTION (bottom) ─────────────────────────────────
    if attributions:
        credit_text = "Data: " + " | ".join(attributions) + "  •  Map: EcoLens Cartographic Intelligence Engine"
        credit_y = map_y + map_area_h + int(20 * scale)
        draw.text((margin, credit_y), credit_text, fill=text_muted, font=font_credit)

    # Export
    buf = io.BytesIO()
    canvas.save(buf, format="PNG", quality=95)
    buf.seek(0)
    return buf.read()
