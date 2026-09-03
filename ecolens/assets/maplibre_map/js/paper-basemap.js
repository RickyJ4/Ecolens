// ============================================================
// EcoLens PaperBasemap — the bespoke "paper & ink" cartographic style.
//
// MapLibre styles are JSON, so instead of shipping a 300KB fork of
// OpenFreeMap Liberty we fetch it at runtime and re-tone every color
// through the paper design system: land becomes the page (#F2EFE4
// family), water a muted survey-tinted blue, roads warm hairlines,
// boundaries fine ink. Data layers (fire red, hotspot crimson) become
// the only saturated marks on screen — "color belongs to data".
//
// Deterministic hue-bucket rules rather than per-layer-id tables, so
// upstream style refactors can't silently break the treatment. The
// handful of surfaces that define the page (background, water,
// buildings, boundaries) are pinned explicitly on top.
//
// build() resolves to a style OBJECT (cached); callers fall back to
// the stock Liberty URL if the fetch fails (offline, CORS, outage).
// ============================================================

const PaperBasemap = (function () {
    'use strict';

    const SOURCE_STYLE = 'https://tiles.openfreemap.org/styles/liberty';

    const PINNED = {
        background: '#F2EFE4',
        waterFill: '#B7CBCF',
        waterLine: '#A6C0C6',
        building: '#E6E1CF',
        boundary: '#7A7260',
        halo: 'rgba(242,239,228,0.9)',
    };

    let cached = null;

    // ---------- color parsing ----------

    function hexToRgba(str) {
        let h = str.slice(1);
        if (h.length === 3 || h.length === 4) {
            h = h.split('').map(c => c + c).join('');
        }
        if (h.length !== 6 && h.length !== 8) return null;
        const n = parseInt(h, 16);
        if (isNaN(n)) return null;
        if (h.length === 6) {
            return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1];
        }
        return [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, (n & 255) / 255];
    }

    function cssToRgba(str) {
        const s = str.trim().toLowerCase();
        if (s === 'white') return [255, 255, 255, 1];
        if (s === 'black') return [0, 0, 0, 1];
        if (s[0] === '#') return hexToRgba(s);
        let m = s.match(/^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/);
        if (m) return [+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]];
        m = s.match(/^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$/);
        if (m) {
            const rgb = hslToRgb(+m[1] / 360, +m[2] / 100, +m[3] / 100);
            return [rgb[0], rgb[1], rgb[2], m[4] === undefined ? 1 : +m[4]];
        }
        return null;
    }

    function rgbToHsl(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        const l = (max + min) / 2;
        if (max === min) return [0, 0, l];
        const d = max - min;
        const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        let h;
        if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
        else if (max === g) h = ((b - r) / d + 2) / 6;
        else h = ((r - g) / d + 4) / 6;
        return [h * 360, s, l];
    }

    function hslToRgb(h, s, l) {
        if (s === 0) {
            const v = Math.round(l * 255);
            return [v, v, v];
        }
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        const p = 2 * l - q;
        const f = (t) => {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1 / 6) return p + (q - p) * 6 * t;
            if (t < 1 / 2) return q;
            if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
            return p;
        };
        return [
            Math.round(f(h + 1 / 3) * 255),
            Math.round(f(h) * 255),
            Math.round(f(h - 1 / 3) * 255),
        ];
    }

    function hsla(h, s, l, a) {
        const [r, g, b] = hslToRgb(((h % 360) + 360) % 360 / 360, clamp01(s), clamp01(l));
        return a >= 1 ? `rgb(${r},${g},${b})` : `rgba(${r},${g},${b},${+a.toFixed(3)})`;
    }

    const clamp01 = (v) => Math.max(0, Math.min(1, v));
    const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

    // ---------- the toning rules ----------

    function tone(css) {
        const rgba = cssToRgba(css);
        if (!rgba) return css;
        const [r, g, b, a] = rgba;
        if (a === 0) return css;
        let [h, s, l] = rgbToHsl(r, g, b);

        // Near-whites (road fills, ice): warm cream, never pure white
        if (l > 0.93) return hsla(48, 0.35, 0.94, a);

        // Neutral grays
        if (s <= 0.12) {
            return l >= 0.6
                ? hsla(45, 0.10, clamp(l, 0.72, 0.92), a)   // light chrome / minor roads
                : hsla(40, 0.12, l, a);                     // dark lines & text → warm ink
        }

        // Blues → the water family (survey-tinted, muted)
        if (h >= 180 && h <= 265) {
            return l > 0.55
                ? hsla(195, Math.min(0.28, s * 0.6), clamp(l, 0.70, 0.84), a)
                : hsla(202, 0.35, clamp(l, 0.30, 0.45), a); // water labels ≈ survey ink
        }

        // Greens → sage (landcover, parks)
        if (h >= 60 && h < 180) {
            return l > 0.55
                ? hsla(96, Math.min(0.20, s * 0.5), clamp(l, 0.74, 0.88), a)
                : hsla(100, 0.25, clamp(l, 0.28, 0.45), a);
        }

        // Warm hues & magentas (road oranges, rail reds, boundary purples)
        return l > 0.5
            ? hsla(42, Math.min(0.30, s * 0.4), clamp(l, 0.70, 0.90), a)
            : hsla(35, Math.min(0.25, s * 0.4), l, a);
    }

    // Deep-walk any paint/layout value; re-tone every color string found
    // (colors hide inside interpolate/step/match/case expressions).
    function toneValue(v) {
        if (typeof v === 'string') {
            return cssToRgba(v) ? tone(v) : v;
        }
        if (Array.isArray(v)) return v.map(toneValue);
        if (v && typeof v === 'object') {
            const out = {};
            for (const k of Object.keys(v)) out[k] = toneValue(v[k]);
            return out;
        }
        return v;
    }

    // ---------- layer treatment ----------

    function paperizeLayer(layer) {
        if (layer.paint) layer.paint = toneValue(layer.paint);
        if (layer.layout) layer.layout = toneValue(layer.layout);
        const id = layer.id || '';
        const paint = layer.paint || (layer.paint = {});

        if (layer.type === 'background') {
            paint['background-color'] = PINNED.background;
            delete paint['background-pattern'];
        }
        if (layer.type === 'fill' && /water|ocean/.test(id) && !/way/.test(id)) {
            paint['fill-color'] = PINNED.waterFill;
            delete paint['fill-pattern'];
        }
        if (layer.type === 'line' && /waterway|water_/.test(id)) {
            paint['line-color'] = PINNED.waterLine;
        }
        if (layer.type === 'fill' && /building/.test(id)) {
            paint['fill-color'] = PINNED.building;
        }
        if (layer.type === 'fill-extrusion' && /building/.test(id)) {
            paint['fill-extrusion-color'] = PINNED.building;
        }
        if (layer.type === 'line' && /^boundary|admin/.test(id)) {
            paint['line-color'] = PINNED.boundary;
        }
        if (layer.type === 'symbol') {
            // One halo for every label: the paper itself
            if (paint['text-halo-color'] !== undefined || layer.layout?.['text-field']) {
                paint['text-halo-color'] = PINNED.halo;
                if (!paint['text-halo-width']) paint['text-halo-width'] = 1.2;
            }
        }
        return layer;
    }

    // ---------- entry ----------

    async function build() {
        if (cached) return cached;
        const resp = await fetch(SOURCE_STYLE, { signal: AbortSignal.timeout(12000) });
        if (!resp.ok) throw new Error(`style fetch ${resp.status}`);
        const style = await resp.json();
        style.name = 'EcoLens Paper';
        style.layers = (style.layers || []).map(paperizeLayer);
        cached = style;
        console.log('[PaperBasemap] Built paper style from Liberty',
            `(${style.layers.length} layers re-toned)`);
        return style;
    }

    return { build, _tone: tone };
})();

window.PaperBasemap = PaperBasemap;
