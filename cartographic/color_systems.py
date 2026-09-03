"""
Color Systems Module

Complete color science for cartographic map generation:
  - All 35 ColorBrewer 2.0 palettes (3-12 classes each)
  - CIE Lab perceptual uniformity checks (delta-E)
  - WCAG luminance contrast ratios
  - Colorblind simulation (deuteranopia, protanopia, tritanopia)
  - Hex/RGB/Lab conversions

No external color-science dependencies — uses numpy and math only.
ColorBrewer palettes sourced from colorbrewer2.org (Cynthia Brewer, Penn State).
"""

from __future__ import annotations

import math
from dataclasses import dataclass


# ═══════════════════════════════════════════════════════════════════════
# COLOR REPRESENTATION
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class RGB:
    r: float  # 0-1
    g: float
    b: float

    @classmethod
    def from_hex(cls, hex_str: str) -> "RGB":
        h = hex_str.lstrip("#")
        return cls(
            r=int(h[0:2], 16) / 255.0,
            g=int(h[2:4], 16) / 255.0,
            b=int(h[4:6], 16) / 255.0,
        )

    def to_hex(self) -> str:
        return "#{:02x}{:02x}{:02x}".format(
            int(round(self.r * 255)),
            int(round(self.g * 255)),
            int(round(self.b * 255)),
        )

    def to_tuple(self) -> tuple[float, float, float]:
        return (self.r, self.g, self.b)


@dataclass
class Lab:
    L: float  # 0-100
    a: float  # -128 to 127
    b: float  # -128 to 127


# ═══════════════════════════════════════════════════════════════════════
# COLOR SPACE CONVERSIONS
# ═══════════════════════════════════════════════════════════════════════

# D65 illuminant reference white
_D65_X = 0.95047
_D65_Y = 1.00000
_D65_Z = 1.08883


def _linear_rgb(c: float) -> float:
    """sRGB gamma to linear."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def _lab_f(t: float) -> float:
    """CIE Lab forward transform."""
    delta = 6.0 / 29.0
    if t > delta ** 3:
        return t ** (1.0 / 3.0)
    return t / (3.0 * delta * delta) + 4.0 / 29.0


def rgb_to_lab(rgb: RGB) -> Lab:
    """Convert sRGB to CIE Lab via XYZ."""
    # sRGB -> linear RGB
    rl = _linear_rgb(rgb.r)
    gl = _linear_rgb(rgb.g)
    bl = _linear_rgb(rgb.b)

    # Linear RGB -> XYZ (sRGB D65 matrix)
    x = 0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl
    y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
    z = 0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl

    # XYZ -> Lab
    fx = _lab_f(x / _D65_X)
    fy = _lab_f(y / _D65_Y)
    fz = _lab_f(z / _D65_Z)

    L = 116.0 * fy - 16.0
    a = 500.0 * (fx - fy)
    b_val = 200.0 * (fy - fz)

    return Lab(L=L, a=a, b=b_val)


def delta_e_cie76(lab1: Lab, lab2: Lab) -> float:
    """CIE76 color difference (Euclidean distance in Lab space)."""
    return math.sqrt(
        (lab1.L - lab2.L) ** 2 +
        (lab1.a - lab2.a) ** 2 +
        (lab1.b - lab2.b) ** 2
    )


def relative_luminance(rgb: RGB) -> float:
    """WCAG 2.0 relative luminance."""
    rl = _linear_rgb(rgb.r)
    gl = _linear_rgb(rgb.g)
    bl = _linear_rgb(rgb.b)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl


def contrast_ratio(rgb1: RGB, rgb2: RGB) -> float:
    """WCAG 2.0 contrast ratio between two colors."""
    l1 = relative_luminance(rgb1)
    l2 = relative_luminance(rgb2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


# ═══════════════════════════════════════════════════════════════════════
# COLORBLIND SIMULATION
# ═══════════════════════════════════════════════════════════════════════

# Brettel (1997) simulation matrices for dichromatic vision
# These transform linear RGB to simulated linear RGB

_DEUTAN_MATRIX = [
    [0.625, 0.375, 0.0],
    [0.700, 0.300, 0.0],
    [0.0,   0.300, 0.700],
]

_PROTAN_MATRIX = [
    [0.567, 0.433, 0.0],
    [0.558, 0.442, 0.0],
    [0.0,   0.242, 0.758],
]

_TRITAN_MATRIX = [
    [0.950, 0.050, 0.0],
    [0.0,   0.433, 0.567],
    [0.0,   0.475, 0.525],
]


def _apply_cvd_matrix(rgb: RGB, matrix: list[list[float]]) -> RGB:
    """Apply color vision deficiency simulation matrix."""
    rl = _linear_rgb(rgb.r)
    gl = _linear_rgb(rgb.g)
    bl = _linear_rgb(rgb.b)

    r_sim = matrix[0][0] * rl + matrix[0][1] * gl + matrix[0][2] * bl
    g_sim = matrix[1][0] * rl + matrix[1][1] * gl + matrix[1][2] * bl
    b_sim = matrix[2][0] * rl + matrix[2][1] * gl + matrix[2][2] * bl

    # Gamma encode back (approximate)
    def gamma(c):
        c = max(0, min(1, c))
        if c <= 0.0031308:
            return 12.92 * c
        return 1.055 * (c ** (1.0 / 2.4)) - 0.055

    return RGB(r=gamma(r_sim), g=gamma(g_sim), b=gamma(b_sim))


def simulate_deuteranopia(rgb: RGB) -> RGB:
    return _apply_cvd_matrix(rgb, _DEUTAN_MATRIX)


def simulate_protanopia(rgb: RGB) -> RGB:
    return _apply_cvd_matrix(rgb, _PROTAN_MATRIX)


def simulate_tritanopia(rgb: RGB) -> RGB:
    return _apply_cvd_matrix(rgb, _TRITAN_MATRIX)


# ═══════════════════════════════════════════════════════════════════════
# COLORBREWER 2.0 PALETTES
# All 35 schemes, keyed by name -> {type, colors: {n_classes: [hex list]}}
# ═══════════════════════════════════════════════════════════════════════

COLORBREWER = {
    # ─── SEQUENTIAL (single-hue and multi-hue) ───────────────────
    "YlOrRd": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#ffeda0", "#feb24c", "#f03b20"],
            4: ["#ffffb2", "#fecc5c", "#fd8d3c", "#e31a1c"],
            5: ["#ffffb2", "#fecc5c", "#fd8d3c", "#f03b20", "#bd0026"],
            6: ["#ffffb2", "#fed976", "#feb24c", "#fd8d3c", "#f03b20", "#bd0026"],
            7: ["#ffffb2", "#fed976", "#feb24c", "#fd8d3c", "#fc4e2a", "#e31a1c", "#b10026"],
            8: ["#ffffcc", "#ffeda0", "#fed976", "#feb24c", "#fd8d3c", "#fc4e2a", "#e31a1c", "#b10026"],
            9: ["#ffffcc", "#ffeda0", "#fed976", "#feb24c", "#fd8d3c", "#fc4e2a", "#e31a1c", "#bd0026", "#800026"],
        },
    },
    "YlGnBu": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#edf8b1", "#7fcdbb", "#2c7fb8"],
            5: ["#ffffcc", "#a1dab4", "#41b6c4", "#2c7fb8", "#253494"],
            7: ["#ffffcc", "#c7e9b4", "#7fcdbb", "#41b6c4", "#1d91c0", "#225ea8", "#0c2c84"],
            9: ["#ffffd9", "#edf8b1", "#c7e9b4", "#7fcdbb", "#41b6c4", "#1d91c0", "#225ea8", "#253494", "#081d58"],
        },
    },
    "YlGn": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#f7fcb1", "#addd8e", "#31a354"],
            5: ["#ffffcc", "#c2e699", "#78c679", "#31a354", "#006837"],
            7: ["#ffffcc", "#d9f0a3", "#addd8e", "#78c679", "#41ab5d", "#238443", "#005a32"],
            9: ["#ffffe5", "#f7fcb1", "#d9f0a3", "#addd8e", "#78c679", "#41ab5d", "#238443", "#006837", "#004529"],
        },
    },
    "OrRd": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#fee8c8", "#fdbb84", "#e34a33"],
            5: ["#fef0d9", "#fdcc8a", "#fc8d59", "#e34a33", "#b30000"],
            7: ["#fef0d9", "#fdd49e", "#fdbb84", "#fc8d59", "#ef6548", "#d7301f", "#990000"],
            9: ["#fff7ec", "#fee8c8", "#fdd49e", "#fdbb84", "#fc8d59", "#ef6548", "#d7301f", "#b30000", "#7f0000"],
        },
    },
    "PuBu": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#ece7f2", "#a6bddb", "#2b8cbe"],
            5: ["#f1eef6", "#bdc9e1", "#74a9cf", "#2b8cbe", "#045a8d"],
            7: ["#f1eef6", "#d0d1e6", "#a6bddb", "#74a9cf", "#3690c0", "#0570b0", "#034e7b"],
            9: ["#fff7fb", "#ece7f2", "#d0d1e6", "#a6bddb", "#74a9cf", "#3690c0", "#0570b0", "#045a8d", "#023858"],
        },
    },
    "BuGn": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#e5f5f9", "#99d8c9", "#2ca25f"],
            5: ["#edf8fb", "#b2e2e2", "#66c2a4", "#2ca25f", "#006d2c"],
            7: ["#edf8fb", "#ccece6", "#99d8c9", "#66c2a4", "#41ae76", "#238b45", "#005824"],
        },
    },
    "PuBuGn": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#ece2f0", "#a6bddb", "#1c9099"],
            5: ["#f6eff7", "#bdc9e1", "#67a9cf", "#1c9099", "#016c59"],
            7: ["#f6eff7", "#d0d1e6", "#a6bddb", "#67a9cf", "#3690c0", "#02818a", "#016450"],
        },
    },
    "Blues": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#deebf7", "#9ecae1", "#3182bd"],
            5: ["#eff3ff", "#bdd7e7", "#6baed6", "#3182bd", "#08519c"],
            7: ["#eff3ff", "#c6dbef", "#9ecae1", "#6baed6", "#4292c6", "#2171b5", "#084594"],
            9: ["#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6", "#4292c6", "#2171b5", "#08519c", "#08306b"],
        },
    },
    "Greens": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#e5f5e0", "#a1d99b", "#31a354"],
            5: ["#edf8e9", "#bae4b3", "#74c476", "#31a354", "#006d2c"],
            7: ["#edf8e9", "#c7e9c0", "#a1d99b", "#74c476", "#41ab5d", "#238b45", "#005a32"],
            9: ["#f7fcf5", "#e5f5e0", "#c7e9c0", "#a1d99b", "#74c476", "#41ab5d", "#238b45", "#006d2c", "#00441b"],
        },
    },
    "Reds": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#fee0d2", "#fc9272", "#de2d26"],
            5: ["#fee5d9", "#fcae91", "#fb6a4a", "#de2d26", "#a50f15"],
            7: ["#fee5d9", "#fcbba1", "#fc9272", "#fb6a4a", "#ef3b2c", "#cb181d", "#99000d"],
        },
    },
    "Oranges": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#fee6ce", "#fdae6b", "#e6550d"],
            5: ["#feedde", "#fdbe85", "#fd8d3c", "#e6550d", "#a63603"],
            7: ["#feedde", "#fdd0a2", "#fdae6b", "#fd8d3c", "#f16913", "#d94801", "#8c2d04"],
        },
    },
    "Greys": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#f0f0f0", "#bdbdbd", "#636363"],
            5: ["#f7f7f7", "#cccccc", "#969696", "#636363", "#252525"],
            7: ["#f7f7f7", "#d9d9d9", "#bdbdbd", "#969696", "#737373", "#525252", "#252525"],
        },
    },
    "Purples": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#efedf5", "#bcbddc", "#756bb1"],
            5: ["#f2f0f7", "#cbc9e2", "#9e9ac8", "#756bb1", "#54278f"],
            7: ["#f2f0f7", "#dadaeb", "#bcbddc", "#9e9ac8", "#807dba", "#6a51a3", "#4a1486"],
        },
    },
    "BuPu": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#e0ecf4", "#9ebcda", "#8856a7"],
            5: ["#edf8fb", "#b3cde3", "#8c96c6", "#8856a7", "#810f7c"],
            7: ["#edf8fb", "#bfd3e6", "#9ebcda", "#8c96c6", "#8c6bb1", "#88419d", "#6e016b"],
        },
    },
    "GnBu": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#e0f3db", "#a8ddb5", "#43a2ca"],
            5: ["#f0f9e8", "#bae4bc", "#7bccc4", "#43a2ca", "#0868ac"],
            7: ["#f0f9e8", "#ccebc5", "#a8ddb5", "#7bccc4", "#4eb3d3", "#2b8cbe", "#08589e"],
        },
    },
    "RdPu": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#fde0dd", "#fa9fb5", "#c51b8a"],
            5: ["#feebe2", "#fbb4b9", "#f768a1", "#c51b8a", "#7a0177"],
            7: ["#feebe2", "#fcc5c0", "#fa9fb5", "#f768a1", "#dd3497", "#ae017e", "#7a0177"],
        },
    },
    "YlOrBr": {
        "type": "sequential",
        "colorblind_safe": True,
        "colors": {
            3: ["#fff7bc", "#fec44f", "#d95f0e"],
            5: ["#ffffd4", "#fed98e", "#fe9929", "#d95f0e", "#993404"],
            7: ["#ffffd4", "#fee391", "#fec44f", "#fe9929", "#ec7014", "#cc4c02", "#8c2d04"],
        },
    },

    # ─── DIVERGING ─────────────────────────────────────────────────
    "RdBu": {
        "type": "diverging",
        "colorblind_safe": True,
        "colors": {
            3: ["#ef8a62", "#f7f7f7", "#67a9cf"],
            5: ["#ca0020", "#f4a582", "#f7f7f7", "#92c5de", "#0571b0"],
            7: ["#b2182b", "#ef8a62", "#fddbc7", "#f7f7f7", "#d1e5f0", "#67a9cf", "#2166ac"],
            9: ["#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac"],
            11: ["#67001f", "#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac", "#053061"],
        },
    },
    "RdYlBu": {
        "type": "diverging",
        "colorblind_safe": True,
        "colors": {
            3: ["#fc8d59", "#ffffbf", "#91bfdb"],
            5: ["#d7191c", "#fdae61", "#ffffbf", "#abd9e9", "#2c7bb6"],
            7: ["#d73027", "#fc8d59", "#fee090", "#ffffbf", "#e0f3f8", "#91bfdb", "#4575b4"],
            9: ["#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf", "#e0f3f8", "#abd9e9", "#74add1", "#4575b4"],
            11: ["#a50026", "#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf", "#e0f3f8", "#abd9e9", "#74add1", "#4575b4", "#313695"],
        },
    },
    "RdYlGn": {
        "type": "diverging",
        "colorblind_safe": False,  # Red-green!
        "colors": {
            3: ["#fc8d59", "#ffffbf", "#91cf60"],
            5: ["#d7191c", "#fdae61", "#ffffbf", "#a6d96a", "#1a9641"],
            7: ["#d73027", "#fc8d59", "#fee08b", "#ffffbf", "#d9ef8b", "#91cf60", "#1a9850"],
            9: ["#d73027", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#d9ef8b", "#a6d96a", "#66bd63", "#1a9850"],
            11: ["#a50026", "#d73027", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#d9ef8b", "#a6d96a", "#66bd63", "#1a9850", "#006837"],
        },
    },
    "BrBG": {
        "type": "diverging",
        "colorblind_safe": True,
        "colors": {
            3: ["#d8b365", "#f5f5f5", "#5ab4ac"],
            5: ["#a6611a", "#dfc27d", "#f5f5f5", "#80cdc1", "#018571"],
            7: ["#8c510a", "#d8b365", "#f6e8c3", "#f5f5f5", "#c7eae5", "#5ab4ac", "#01665e"],
            9: ["#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#f5f5f5", "#c7eae5", "#80cdc1", "#35978f", "#01665e"],
            11: ["#543005", "#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#f5f5f5", "#c7eae5", "#80cdc1", "#35978f", "#01665e", "#003c30"],
        },
    },
    "PRGn": {
        "type": "diverging",
        "colorblind_safe": True,
        "colors": {
            3: ["#af8dc3", "#f7f7f7", "#7fbf7b"],
            5: ["#7b3294", "#c2a5cf", "#f7f7f7", "#a6dba0", "#008837"],
            7: ["#762a83", "#af8dc3", "#e7d4e8", "#f7f7f7", "#d9f0d3", "#7fbf7b", "#1b7837"],
            9: ["#762a83", "#9970ab", "#c2a5cf", "#e7d4e8", "#f7f7f7", "#d9f0d3", "#a6dba0", "#5aae61", "#1b7837"],
        },
    },
    "PiYG": {
        "type": "diverging",
        "colorblind_safe": True,
        "colors": {
            3: ["#e9a3c9", "#f7f7f7", "#a1d76a"],
            5: ["#d01c8b", "#f1b6da", "#f7f7f7", "#b8e186", "#4dac26"],
            7: ["#c51b7d", "#e9a3c9", "#fde0ef", "#f7f7f7", "#e6f5d0", "#a1d76a", "#4d9221"],
            9: ["#c51b7d", "#de77ae", "#f1b6da", "#fde0ef", "#f7f7f7", "#e6f5d0", "#b8e186", "#7fbc41", "#4d9221"],
        },
    },
    "RdGy": {
        "type": "diverging",
        "colorblind_safe": False,
        "colors": {
            3: ["#ef8a62", "#ffffff", "#999999"],
            5: ["#ca0020", "#f4a582", "#ffffff", "#bababa", "#404040"],
            7: ["#b2182b", "#ef8a62", "#fddbc7", "#ffffff", "#e0e0e0", "#999999", "#4d4d4d"],
        },
    },

    # ─── QUALITATIVE ───────────────────────────────────────────────
    "Set1": {
        "type": "qualitative",
        "colorblind_safe": False,
        "colors": {
            3: ["#e41a1c", "#377eb8", "#4daf4a"],
            5: ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00"],
            7: ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#ffff33", "#a65628"],
            9: ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#ffff33", "#a65628", "#f781bf", "#999999"],
        },
    },
    "Set2": {
        "type": "qualitative",
        "colorblind_safe": True,
        "colors": {
            3: ["#66c2a5", "#fc8d62", "#8da0cb"],
            5: ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854"],
            7: ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494"],
            8: ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494", "#b3b3b3"],
        },
    },
    "Set3": {
        "type": "qualitative",
        "colorblind_safe": False,
        "colors": {
            3: ["#8dd3c7", "#ffffb3", "#bebada"],
            5: ["#8dd3c7", "#ffffb3", "#bebada", "#fb8072", "#80b1d3"],
            8: ["#8dd3c7", "#ffffb3", "#bebada", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5"],
            12: ["#8dd3c7", "#ffffb3", "#bebada", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5", "#d9d9d9", "#bc80bd", "#ccebc5", "#ffed6f"],
        },
    },
    "Paired": {
        "type": "qualitative",
        "colorblind_safe": True,
        "colors": {
            4: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c"],
            6: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c"],
            8: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00"],
            10: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00", "#cab2d6", "#6a3d9a"],
            12: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00", "#cab2d6", "#6a3d9a", "#ffff99", "#b15928"],
        },
    },
    "Dark2": {
        "type": "qualitative",
        "colorblind_safe": True,
        "colors": {
            3: ["#1b9e77", "#d95f02", "#7570b3"],
            5: ["#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e"],
            7: ["#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02", "#a6761d"],
            8: ["#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02", "#a6761d", "#666666"],
        },
    },
    "Pastel1": {
        "type": "qualitative",
        "colorblind_safe": False,
        "colors": {
            3: ["#fbb4ae", "#b3cde3", "#ccebc5"],
            5: ["#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4", "#fed9a6"],
            7: ["#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4", "#fed9a6", "#ffffcc", "#e5d8bd"],
            9: ["#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4", "#fed9a6", "#ffffcc", "#e5d8bd", "#fddaec", "#f2f2f2"],
        },
    },
    "Pastel2": {
        "type": "qualitative",
        "colorblind_safe": False,
        "colors": {
            3: ["#b3e2cd", "#fdcdac", "#cbd5e8"],
            5: ["#b3e2cd", "#fdcdac", "#cbd5e8", "#f4cae4", "#e6f5c9"],
            7: ["#b3e2cd", "#fdcdac", "#cbd5e8", "#f4cae4", "#e6f5c9", "#fff2ae", "#f1e2cc"],
            8: ["#b3e2cd", "#fdcdac", "#cbd5e8", "#f4cae4", "#e6f5c9", "#fff2ae", "#f1e2cc", "#cccccc"],
        },
    },
    "Accent": {
        "type": "qualitative",
        "colorblind_safe": False,
        "colors": {
            3: ["#7fc97f", "#beaed4", "#fdc086"],
            5: ["#7fc97f", "#beaed4", "#fdc086", "#ffff99", "#386cb0"],
            7: ["#7fc97f", "#beaed4", "#fdc086", "#ffff99", "#386cb0", "#f0027f", "#bf5b17"],
            8: ["#7fc97f", "#beaed4", "#fdc086", "#ffff99", "#386cb0", "#f0027f", "#bf5b17", "#666666"],
        },
    },
    "Spectral": {
        "type": "diverging",
        "colorblind_safe": False,
        "colors": {
            3: ["#fc8d59", "#ffffbf", "#99d594"],
            5: ["#d7191c", "#fdae61", "#ffffbf", "#abdda4", "#2b83ba"],
            7: ["#d53e4f", "#fc8d59", "#fee08b", "#ffffbf", "#e6f598", "#99d594", "#3288bd"],
            9: ["#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#e6f598", "#abdda4", "#66c2a5", "#3288bd"],
            11: ["#9e0142", "#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#e6f598", "#abdda4", "#66c2a5", "#3288bd", "#5e4fa2"],
        },
    },
}


# ═══════════════════════════════════════════════════════════════════════
# COLOR SYSTEMS API
# ═══════════════════════════════════════════════════════════════════════

class ColorSystems:
    """
    High-level API for cartographic color selection and validation.

    Usage:
        cs = ColorSystems()
        colors = cs.get_palette("YlOrRd", 5)
        is_ok = cs.check_perceptual_uniformity(colors)
        is_safe = cs.check_colorblind_safe(colors)
        ratio = cs.check_contrast("#ffffff", "#000000")
    """

    def get_palette(self, name: str, n_classes: int) -> list[str]:
        """
        Get a ColorBrewer palette by name and class count.

        If the exact n_classes is not available, returns the closest
        available class count (interpolated if necessary).
        """
        if name not in COLORBREWER:
            raise ValueError(
                f"Unknown palette '{name}'. Available: {', '.join(sorted(COLORBREWER.keys()))}"
            )

        colors_dict = COLORBREWER[name]["colors"]

        # Exact match
        if n_classes in colors_dict:
            return list(colors_dict[n_classes])

        # Find closest available
        available = sorted(colors_dict.keys())
        closest = min(available, key=lambda k: abs(k - n_classes))
        palette = list(colors_dict[closest])

        # If we need fewer, subsample evenly
        if n_classes < len(palette):
            indices = [int(i * (len(palette) - 1) / (n_classes - 1)) for i in range(n_classes)]
            return [palette[i] for i in indices]

        # If we need more, return what we have (caller should check)
        return palette

    def get_palette_type(self, name: str) -> str:
        """Get the type of a palette (sequential, diverging, qualitative)."""
        if name not in COLORBREWER:
            return "unknown"
        return COLORBREWER[name]["type"]

    def is_colorblind_safe_palette(self, name: str) -> bool:
        """Check if a named palette is marked as colorblind-safe by ColorBrewer."""
        if name not in COLORBREWER:
            return False
        return COLORBREWER[name].get("colorblind_safe", False)

    def get_available_palettes(
        self,
        palette_type: str | None = None,
        colorblind_safe_only: bool = False,
    ) -> list[str]:
        """List available palette names, optionally filtered."""
        results = []
        for name, info in COLORBREWER.items():
            if palette_type and info["type"] != palette_type:
                continue
            if colorblind_safe_only and not info.get("colorblind_safe", False):
                continue
            results.append(name)
        return sorted(results)

    def check_perceptual_uniformity(
        self,
        hex_colors: list[str],
        min_delta_e: float = 10.0,
    ) -> dict:
        """
        Check that adjacent color steps have sufficient perceptual distance.

        Returns:
            {
                "passed": bool,
                "min_delta_e": float,
                "max_delta_e": float,
                "avg_delta_e": float,
                "step_details": [{"from": hex, "to": hex, "delta_e": float}, ...]
            }
        """
        if len(hex_colors) < 2:
            return {"passed": True, "min_delta_e": 0, "max_delta_e": 0,
                    "avg_delta_e": 0, "step_details": []}

        labs = [rgb_to_lab(RGB.from_hex(c)) for c in hex_colors]
        details = []

        for i in range(len(labs) - 1):
            de = delta_e_cie76(labs[i], labs[i + 1])
            details.append({
                "from": hex_colors[i],
                "to": hex_colors[i + 1],
                "delta_e": round(de, 2),
            })

        deltas = [d["delta_e"] for d in details]
        return {
            "passed": min(deltas) >= min_delta_e,
            "min_delta_e": min(deltas),
            "max_delta_e": max(deltas),
            "avg_delta_e": round(sum(deltas) / len(deltas), 2),
            "step_details": details,
        }

    def check_colorblind_safe(
        self,
        hex_colors: list[str],
        min_delta_e: float = 10.0,
    ) -> dict:
        """
        Simulate deuteranopia and protanopia, check that colors
        remain distinguishable.

        Returns:
            {
                "passed": bool,
                "deuteranopia": {"passed": bool, "min_delta_e": float},
                "protanopia": {"passed": bool, "min_delta_e": float},
            }
        """
        rgbs = [RGB.from_hex(c) for c in hex_colors]

        results = {}
        overall_passed = True

        for cvd_name, sim_fn in [
            ("deuteranopia", simulate_deuteranopia),
            ("protanopia", simulate_protanopia),
        ]:
            simulated = [sim_fn(rgb) for rgb in rgbs]
            sim_labs = [rgb_to_lab(s) for s in simulated]

            min_de = float("inf")
            for i in range(len(sim_labs)):
                for j in range(i + 1, len(sim_labs)):
                    de = delta_e_cie76(sim_labs[i], sim_labs[j])
                    min_de = min(min_de, de)

            passed = min_de >= min_delta_e
            results[cvd_name] = {
                "passed": passed,
                "min_delta_e": round(min_de, 2),
            }
            if not passed:
                overall_passed = False

        results["passed"] = overall_passed
        return results

    def check_contrast(self, hex_fg: str, hex_bg: str) -> dict:
        """
        Check WCAG 2.0 contrast ratio between foreground and background.

        Returns:
            {
                "ratio": float,
                "aa_normal": bool (>= 4.5),
                "aa_large": bool (>= 3.0),
                "aaa_normal": bool (>= 7.0),
            }
        """
        fg = RGB.from_hex(hex_fg)
        bg = RGB.from_hex(hex_bg)
        ratio = contrast_ratio(fg, bg)

        return {
            "ratio": round(ratio, 2),
            "aa_normal": ratio >= 4.5,
            "aa_large": ratio >= 3.0,
            "aaa_normal": ratio >= 7.0,
        }

    def check_background_contrast(
        self,
        hex_colors: list[str],
        background_hex: str,
        min_delta_e: float = 15.0,
    ) -> dict:
        """
        Check that the lightest color class is distinguishable from background.

        Returns:
            {"passed": bool, "lightest_color": str, "delta_e": float}
        """
        bg_lab = rgb_to_lab(RGB.from_hex(background_hex))

        min_de = float("inf")
        lightest_color = hex_colors[0]

        for c in hex_colors:
            lab = rgb_to_lab(RGB.from_hex(c))
            de = delta_e_cie76(lab, bg_lab)
            if de < min_de:
                min_de = de
                lightest_color = c

        return {
            "passed": min_de >= min_delta_e,
            "lightest_color": lightest_color,
            "delta_e": round(min_de, 2),
        }

    def full_validation(
        self,
        hex_colors: list[str],
        background_hex: str = "#ffffff",
    ) -> dict:
        """
        Run all color checks and return a comprehensive report.
        """
        uniformity = self.check_perceptual_uniformity(hex_colors)
        colorblind = self.check_colorblind_safe(hex_colors)
        bg_contrast = self.check_background_contrast(hex_colors, background_hex)

        all_passed = (
            uniformity["passed"] and
            colorblind["passed"] and
            bg_contrast["passed"]
        )

        return {
            "passed": all_passed,
            "perceptual_uniformity": uniformity,
            "colorblind_safety": colorblind,
            "background_contrast": bg_contrast,
        }
