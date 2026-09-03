// ============================================================
// EcoLens Permalink — every map state is a shareable URL
//
// Hash format (own format; MapLibre's `hash` option stays false):
//   #v1&c={lng},{lat},{zoom},{bearing},{pitch}
//      &l=fires.85,hotspots.100        (visible layers, opacity ×100)
//      &t=168                          (time window hours)
//      &b=satellite                    (basemap key)
//
// Read once at map load; written (debounced) on camera/layer/time/basemap
// changes via history.replaceState, and mirrored to the parent Flutter
// shell via postMessage {type:'ecolens-state'} so the outer app URL can
// carry it (?mapstate=... → iframe hash).
// ============================================================

const Permalink = (function () {
    'use strict';

    let writeTimer = null;
    let applying = false;

    function currentBasemap() {
        return window.EcoLensCurrentBasemap || 'liberty';
    }

    // ---------- Serialize ----------

    function serialize() {
        const map = window.ecoMap;
        if (!map) return '';
        const c = map.getCenter();
        const parts = ['v1'];
        parts.push('c=' + [
            c.lng.toFixed(4), c.lat.toFixed(4),
            map.getZoom().toFixed(2),
            Math.round(map.getBearing()),
            Math.round(map.getPitch()),
        ].join(','));

        const layers = [];
        document.querySelectorAll('#layer-toggles input[type="checkbox"]').forEach(cb => {
            if (!cb.checked) return;
            const type = cb.id.replace('toggle-', '');
            const slider = document.getElementById('opacity-' + type);
            layers.push(type + '.' + (slider ? slider.value : '100'));
        });
        if (layers.length) parts.push('l=' + layers.join(','));

        const hours = Number(window.EcoLensTimeWindowHours) || 168;
        parts.push('t=' + hours);
        parts.push('b=' + currentBasemap());
        return parts.join('&');
    }

    function parse(hashString) {
        const hash = (hashString != null ? hashString : location.hash).replace(/^#/, '');
        if (!hash.startsWith('v1')) return null;
        const state = { layers: [] };
        for (const piece of hash.split('&')) {
            const eq = piece.indexOf('=');
            if (eq < 0) continue;
            const key = piece.slice(0, eq), val = piece.slice(eq + 1);
            if (key === 'c') {
                const n = val.split(',').map(Number);
                if (n.length >= 3 && n.every(x => isFinite(x))) {
                    state.camera = {
                        center: [n[0], n[1]], zoom: n[2],
                        bearing: n[3] || 0, pitch: n[4] || 0,
                    };
                }
            }
            if (key === 'l') {
                state.layers = val.split(',').map(entry => {
                    const [type, op] = entry.split('.');
                    return { type, opacity: op != null ? Number(op) / 100 : 1 };
                }).filter(l => l.type);
            }
            if (key === 't') state.hours = Number(val) || undefined;
            if (key === 'b') state.basemap = val;
        }
        return state;
    }

    // ---------- Apply ----------

    function apply(state) {
        if (!state || !window.ecoMap) return;
        applying = true;
        try {
            const map = window.ecoMap;
            if (state.camera) map.jumpTo(state.camera);

            if (state.layers && state.layers.length) {
                const wanted = new Map(state.layers.map(l => [l.type, l]));
                document.querySelectorAll('#layer-toggles input[type="checkbox"]').forEach(cb => {
                    const type = cb.id.replace('toggle-', '');
                    const on = wanted.has(type);
                    cb.checked = on;
                    const wrap = cb.closest('.layer-toggle-wrap');
                    if (wrap) wrap.classList.toggle('is-on', on);
                    if (window.HazardLayers) window.HazardLayers.setLayerVisibility(type, on);
                    if (on) {
                        const entry = wanted.get(type);
                        if (entry.opacity != null && entry.opacity < 1 && window.HazardLayers) {
                            window.HazardLayers.setLayerOpacity(type, entry.opacity);
                            const slider = document.getElementById('opacity-' + type);
                            if (slider) slider.value = Math.round(entry.opacity * 100);
                        }
                    }
                });
            }

            if (state.hours && window.FilterControls) {
                window.FilterControls.applyTimeWindow(state.hours, { hydrate: false });
                const btns = document.querySelectorAll('.time-window-btn');
                btns.forEach(b => b.classList.toggle('active',
                    Number(b.dataset.hours) === state.hours));
                const slider = document.getElementById('time-slider');
                if (slider) slider.value = state.hours;
            }

            if (state.basemap && state.basemap !== currentBasemap() && window.MapCore) {
                window.MapCore.switchBasemap(state.basemap);
            }
        } finally {
            setTimeout(() => { applying = false; }, 500);
        }
    }

    // ---------- Write-back ----------

    function scheduleWrite() {
        if (applying) return;
        clearTimeout(writeTimer);
        writeTimer = setTimeout(() => {
            const hash = serialize();
            if (!hash) return;
            try {
                history.replaceState(null, '', '#' + hash);
            } catch (e) { /* sandboxed iframe without history access */ }
            try {
                if (window.parent && window.parent !== window) {
                    window.parent.postMessage(
                        { source: 'ecolens-map', event: 'ecolens-state', data: { state: hash } }, '*');
                }
            } catch (e) { /* no parent */ }
        }, 500);
    }

    // ---------- Init ----------

    function init() {
        const map = window.ecoMap;
        if (!map) return;

        // Record basemap switches (MapCore doesn't track its own current key)
        if (window.MapCore && window.MapCore.switchBasemap && !window.MapCore.__permalinkWrapped) {
            const original = window.MapCore.switchBasemap;
            window.MapCore.switchBasemap = function (name) {
                window.EcoLensCurrentBasemap = name;
                const out = original.apply(this, arguments);
                scheduleWrite();
                return out;
            };
            window.MapCore.__permalinkWrapped = true;
        }

        const initial = parse();
        if (initial) apply(initial);

        map.on('moveend', scheduleWrite);
        document.addEventListener('change', (e) => {
            if (e.target && e.target.matches &&
                (e.target.matches('#layer-toggles input[type="checkbox"]') ||
                 e.target.matches('#time-slider') ||
                 e.target.matches('.layer-opacity-row input[type="range"]'))) {
                scheduleWrite();
            }
        });

        // Flutter-facing API (evaluateJavascript on mobile, postMessage on web)
        window.ecolensGetState = serialize;
        window.ecolensApplyState = (str) => apply(parse(str));
        console.log('[Permalink] Ready' + (initial ? ' (state restored from URL)' : ''));
    }

    return { init, parse, serialize, apply };
})();

if (typeof window !== 'undefined') {
    window.Permalink = Permalink;
}

// UMD hook for Node fixture tests (parse/serialize round-trip)
if (typeof module !== 'undefined' && module.exports) {
    module.exports = Permalink;
}
