// ============================================================
// EcoLens SwipeCompare — A/B comparison for any hazard layer
//
// Compares the live state of a layer (A) against an alternate
// FeatureCollection (B — typically an archived window from
// HistoryArchive) using cloned "-cmp" layers and a draggable divider
// mapped to a crossfade. Same visual technique as the existing
// simulation swipe (MapLibre renders one canvas, so a true spatial
// clip needs a second map instance — out of scope; the divider maps
// to opacity crossfade, disclosed in the UI label).
//
// Deliberately standalone from EventSimulations' satellite swipe:
// that rig stays untouched.
// ============================================================

const SwipeCompare = (function () {
    'use strict';

    let active = null; // { type, cloneIds, sourceId }
    let dragging = false;

    const el = (id) => document.getElementById(id);

    // ---------- UI ----------

    function injectUI() {
        if (el('swipe-bar')) return;
        const style = document.createElement('style');
        style.textContent = `
            #swipe-bar { position: fixed; inset: 0; z-index: 205; pointer-events: none; display: none; }
            #swipe-bar.active { display: block; }
            #swipe-divider { position: absolute; top: 0; bottom: 0; left: 50%; width: 2px;
                background: var(--ink, #232019); pointer-events: auto; cursor: ew-resize;
                box-shadow: 0 0 10px rgba(35,32,25,0.4); }
            #swipe-divider::after { content: '⇔'; position: absolute; top: 50%; left: 50%;
                transform: translate(-50%,-50%); width: 32px; height: 32px; border-radius: 50%;
                background: var(--paper, #F2EFE4); color: var(--ink, #232019); display: flex; align-items: center;
                justify-content: center; font-size: 14px; border: 1px solid var(--ink, #232019); }
            .swipe-label { position: absolute; top: 84px; padding: 4px 10px; border-radius: 2px;
                background: var(--paper, #F2EFE4); color: var(--ink, #232019); font-size: 10.5px; font-weight: 700;
                border: 1px solid var(--ink, #232019);
                font-family: system-ui, sans-serif; pointer-events: none; }
            #swipe-label-a { left: 20px; }
            #swipe-label-b { right: 20px; }
            #swipe-exit { position: absolute; bottom: 110px; left: 50%; transform: translateX(-50%);
                pointer-events: auto; background: var(--paper, #F2EFE4); color: var(--ink, #232019);
                border: 1px solid var(--ink, #232019); border-radius: 3px; padding: 7px 16px;
                font-size: 12px; cursor: pointer; font-family: system-ui, sans-serif; }
            #swipe-exit:hover { background: var(--ink, #232019); color: var(--paper, #F2EFE4); }
        `;
        document.head.appendChild(style);

        const bar = document.createElement('div');
        bar.id = 'swipe-bar';
        bar.innerHTML =
            '<div id="swipe-divider"></div>' +
            '<span class="swipe-label" id="swipe-label-a">Now</span>' +
            '<span class="swipe-label" id="swipe-label-b">Comparison</span>' +
            '<button id="swipe-exit" type="button">Exit comparison</button>';
        document.body.appendChild(bar);

        const divider = el('swipe-divider');
        const getPct = (e) => {
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            return Math.max(2, Math.min(98, (clientX / window.innerWidth) * 100));
        };
        divider.addEventListener('mousedown', (e) => { dragging = true; e.preventDefault(); });
        divider.addEventListener('touchstart', (e) => { dragging = true; e.preventDefault(); }, { passive: false });
        document.addEventListener('mousemove', (e) => { if (dragging) setRatio(getPct(e)); });
        document.addEventListener('touchmove', (e) => { if (dragging) setRatio(getPct(e)); }, { passive: true });
        document.addEventListener('mouseup', () => { dragging = false; });
        document.addEventListener('touchend', () => { dragging = false; });
        el('swipe-exit').addEventListener('click', stop);
    }

    // ---------- Crossfade ----------

    const OPACITY_PROP = {
        heatmap: 'heatmap-opacity', circle: 'circle-opacity',
        fill: 'fill-opacity', line: 'line-opacity', raster: 'raster-opacity',
    };

    function setLayerGroupOpacity(map, ids, value) {
        for (const id of ids) {
            const layer = map.getLayer(id);
            if (!layer) continue;
            const prop = OPACITY_PROP[layer.type];
            if (prop) {
                try { map.setPaintProperty(id, prop, value); } catch (e) { /* noop */ }
            }
        }
    }

    function setRatio(pct) {
        if (!active || !window.ecoMap) return;
        const divider = el('swipe-divider');
        if (divider) divider.style.left = pct + '%';
        const r = pct / 100;
        const map = window.ecoMap;
        // Left of divider ≈ A (live), right ≈ B: divider position drives the
        // crossfade between the two states.
        setLayerGroupOpacity(map, active.liveIds, Math.max(0.15, 1 - r));
        setLayerGroupOpacity(map, active.cloneIds, r);
    }

    // ---------- Start / stop ----------

    /**
     * @param {string} type      hazard type present in HazardLayers.LAYER_DEFS
     * @param {object} fcB       FeatureCollection for the comparison side
     * @param {object} labels    {a, b} display labels
     */
    function start(type, fcB, labels) {
        const map = window.ecoMap;
        const defs = window.HazardLayers && window.HazardLayers.LAYER_DEFS;
        if (!map || !defs || !defs[type]) return false;
        stop();
        injectUI();

        const def = defs[type];
        const sourceId = type + '-cmp-source';
        if (map.getSource(sourceId)) {
            for (const l of def.layers) {
                if (map.getLayer(l.id + '-cmp')) map.removeLayer(l.id + '-cmp');
            }
            map.removeSource(sourceId);
        }
        map.addSource(sourceId, { type: 'geojson', data: fcB });

        const cloneIds = [];
        for (const l of def.layers) {
            if (l.filter && JSON.stringify(l.filter).includes('never')) continue; // skip stubs
            const clone = {
                id: l.id + '-cmp',
                type: l.type,
                source: sourceId,
                paint: JSON.parse(JSON.stringify(l.paint || {})),
            };
            if (l.minzoom) clone.minzoom = l.minzoom;
            if (l.maxzoom) clone.maxzoom = l.maxzoom;
            try {
                map.addLayer(clone);
                cloneIds.push(clone.id);
            } catch (e) {
                console.warn('[SwipeCompare] clone failed', clone.id, e.message);
            }
        }

        const liveIds = def.layers.map(l => l.id);
        active = { type, cloneIds, liveIds, sourceId };

        window.HazardLayers.setLayerVisibility(type, true);
        el('swipe-bar').classList.add('active');
        el('swipe-label-a').textContent = (labels && labels.a) || 'Now';
        el('swipe-label-b').textContent = (labels && labels.b) || 'Comparison';
        setRatio(50);
        return true;
    }

    function stop() {
        if (!active || !window.ecoMap) { active = null; return; }
        const map = window.ecoMap;
        for (const id of active.cloneIds) {
            if (map.getLayer(id)) map.removeLayer(id);
        }
        if (map.getSource(active.sourceId)) map.removeSource(active.sourceId);
        // Restore live opacities to their authored paint values by re-adding
        // is heavy; nudging back to full opacity is sufficient for these layers.
        setLayerGroupOpacity(map, active.liveIds, 1);
        const bar = el('swipe-bar');
        if (bar) bar.classList.remove('active');
        active = null;
    }

    /**
     * One-call demo comparison: live fires vs the archived previous week.
     */
    async function compareFiresWithLastWeek() {
        if (!window.HistoryArchive) return;
        const days = window.HistoryArchive.archiveDays('fires');
        if (days.length < 8) {
            alert('Needs at least 8 archived days (have ' + days.length + ').');
            return;
        }
        const lastWeek = days.slice(-14, -7);
        const parts = await window.HistoryArchive.getRange(
            'fires', lastWeek[0], lastWeek[lastWeek.length - 1]);
        const merged = {
            type: 'FeatureCollection',
            features: parts.flatMap(p => p.geojson.features || []),
        };
        start('fires', merged, { a: 'This week (live)', b: 'Previous week (archive)' });
    }

    function init() {
        console.log('[SwipeCompare] Ready');
    }

    return { init, start, stop, compareFiresWithLastWeek, isActive: () => !!active };
})();

window.SwipeCompare = SwipeCompare;
