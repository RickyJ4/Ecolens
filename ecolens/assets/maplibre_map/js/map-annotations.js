// ============================================================
// EcoLens MapAnnotations — the map annotates itself.
//
// A printed atlas doesn't make you click: the strongest features
// carry their own captions. This module writes small ink labels
// straight onto the sheet for the things that matter most:
//   - the top significant fire clusters (from the Gi* hotspot
//     cells): "1,214 detections · near Kamloops"
//   - major earthquakes (M5.5+ in the active window): "M6.1"
// Labels regenerate whenever the underlying sources change, use
// the basemap's own glyphs, and survive basemap switches.
// ============================================================

const MapAnnotations = (function () {
    'use strict';

    const SOURCE_ID = 'annotations-source';
    const LAYER_ID = 'annotation-labels';
    const MAX_FIRE_LABELS = 10;
    const MIN_SEPARATION_KM = 130;

    let map = null;
    let timer = null;

    function haversineKm(lat1, lon1, lat2, lon2) {
        const rad = Math.PI / 180;
        const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
        const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function polygonCenter(geom) {
        const ring = geom && geom.coordinates && geom.coordinates[0];
        if (!ring || !ring.length) return null;
        let sx = 0, sy = 0;
        for (const [x, y] of ring) { sx += x; sy += y; }
        return [sx / ring.length, sy / ring.length];
    }

    function placeName(lat, lon) {
        if (window.AnomalyDesk && window.AnomalyDesk.regionLabel) {
            return window.AnomalyDesk.regionLabel(lat, lon);
        }
        return lat.toFixed(1) + '°, ' + lon.toFixed(1) + '°';
    }

    // ---------- label building ----------

    function fireClusterLabels() {
        const src = map.getSource('hotspots-source');
        const cells = (src && src._data && src._data.features) || [];
        const hot = cells
            .filter(f => {
                const b = f.properties && f.properties.p_bucket;
                return b === 'hot99' || b === 'hot95';
            })
            .map(f => {
                const c = polygonCenter(f.geometry);
                return c && {
                    lon: c[0], lat: c[1],
                    count: f.properties.count || 0,
                    frp: f.properties.sum_frp || 0,
                };
            })
            .filter(Boolean)
            .sort((a, b) => b.frp - a.frp);

        // Greedy thinning: strongest first, suppress near neighbours so
        // one complex reads as one caption, not a pile of them.
        const kept = [];
        for (const h of hot) {
            if (kept.length >= MAX_FIRE_LABELS) break;
            if (kept.some(k => haversineKm(k.lat, k.lon, h.lat, h.lon) < MIN_SEPARATION_KM)) continue;
            kept.push(h);
        }

        return kept.map((h, i) => ({
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [h.lon, h.lat] },
            properties: {
                kind: 'fire',
                rank: i + 1,
                label: h.count.toLocaleString() + ' detections\n' + placeName(h.lat, h.lon),
            },
        }));
    }

    function quakeLabels() {
        const src = map.getSource('earthquakes-source');
        const feats = (src && src._data && src._data.features) || [];
        const cutoff = Date.now() -
            (Number(window.EcoLensTimeWindowHours) || 168) * 3600 * 1000;
        return feats
            .filter(f => (f.properties?.mag || 0) >= 5.5 &&
                (!f.properties.time || Number(f.properties.time) >= cutoff))
            .sort((a, b) => (b.properties.mag || 0) - (a.properties.mag || 0))
            .slice(0, 12)
            .map((f, i) => ({
                type: 'Feature',
                geometry: f.geometry,
                properties: {
                    kind: 'quake',
                    rank: i + 1,
                    label: 'M' + (f.properties.mag || 0).toFixed(1),
                },
            }));
    }

    // ---------- rendering ----------

    function ensureLayer() {
        if (!map.getSource(SOURCE_ID)) {
            map.addSource(SOURCE_ID, {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] },
            });
        }
        if (!map.getLayer(LAYER_ID)) {
            map.addLayer({
                id: LAYER_ID,
                type: 'symbol',
                source: SOURCE_ID,
                minzoom: 2.2,
                maxzoom: 11,
                layout: {
                    'text-field': ['get', 'label'],
                    'text-font': ['Noto Sans Bold'],
                    'text-size': [
                        'interpolate', ['linear'], ['zoom'],
                        2.5, ['match', ['get', 'kind'], 'quake', 9.5, 9],
                        7, ['match', ['get', 'kind'], 'quake', 12, 11.5],
                    ],
                    'text-anchor': 'bottom',
                    // Clear the cluster itself. MapLibre only resolves
                    // collisions between SYMBOL layers, so a label will
                    // happily sit on top of the circle layer beneath it —
                    // the offset and halo are what keep it readable.
                    'text-offset': [0, -1.6],
                    'text-line-height': 1.3,
                    'text-letter-spacing': 0.04,
                    'symbol-sort-key': ['get', 'rank'],
                    'text-allow-overlap': false,
                    'text-padding': 8,
                    'text-max-width': 11,
                },
                paint: {
                    'text-color': [
                        'match', ['get', 'kind'],
                        'quake', '#4A3F62',
                        '#8E1B12',
                    ],
                    'text-halo-color': '#F6F3E9',
                    'text-halo-width': 2.6,
                    'text-halo-blur': 0.2,
                },
            });
        }
    }

    function refresh() {
        if (!map || !map.getStyle) return;
        try {
            ensureLayer();
            const features = [...fireClusterLabels(), ...quakeLabels()];
            map.getSource(SOURCE_ID).setData({ type: 'FeatureCollection', features });
        } catch (e) {
            console.warn('[MapAnnotations]', e.message || e);
        }
    }

    function schedule() {
        clearTimeout(timer);
        timer = setTimeout(refresh, 600);
    }

    function init() {
        map = window.ecoMap;
        if (!map) return;
        // Regenerate when the inputs change (hotspot recompute, window
        // change, live refresh) — sourcedata fires often, debounce absorbs.
        map.on('sourcedata', (e) => {
            if (e.sourceId === 'hotspots-source' || e.sourceId === 'earthquakes-source') {
                schedule();
            }
        });
        // Survive basemap switches like the other overlay modules.
        map.on('style.load', () => setTimeout(refresh, 400));
        schedule();
        console.log('[MapAnnotations] Ready — the map now captions itself');
    }

    return { init, refresh };
})();

window.MapAnnotations = MapAnnotations;
