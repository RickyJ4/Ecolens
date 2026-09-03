// ============================================================
// EcoLens Bivariate — fire density × drought severity choropleth
//
// Scope (honest): Contiguous US only, because the drought layer is the
// US Drought Monitor. The legend carries that label.
//
// Method: live fire detections hex-binned at 50 km, clipped to CONUS;
// each occupied hex samples the max USDM class at its center via
// point-in-polygon. Fire density classed by terciles among occupied
// cells; drought bucketed None–D1 / D2–D3 / D4. 3×3 = 9 classes,
// orange (fire) × purple (drought) blend.
// ============================================================

const Bivariate = (function () {
    'use strict';

    const CELL_KM = 50;
    const CONUS = { minLon: -125, minLat: 24.5, maxLon: -66.9, maxLat: 49.5 };

    // rows: drought bucket (0 none–D1, 1 D2–D3, 2 D4)
    // cols: fire tercile (0 low, 1 mid, 2 high)
    const PALETTE = [
        ['#e8e8e8', '#e4d9ac', '#c8b35a'],
        ['#cbb8d7', '#c8ada0', '#af8e53'],
        ['#9972af', '#976b82', '#804d36'],
    ];
    const FIRE_LABELS = ['Lower', 'Middle', 'Upper'];
    const DROUGHT_LABELS = ['None–D1', 'D2–D3', 'D4 exceptional'];

    let recomputeTimer = null;

    function sourceData(sourceId) {
        const map = window.ecoMap;
        const src = map && map.getSource(sourceId);
        return (src && src._data) || null;
    }

    function droughtBucket(props) {
        if (!props) return 0;
        const sev = Number(props.severity_index) || 0; // 1..5 = D0..D4
        if (sev >= 5) return 2;
        if (sev >= 3) return 1;
        return 0;
    }

    function recompute() {
        if (!window.SpatialStats || !window.HazardLayers || !window.ecoMap) return;
        const S = window.SpatialStats;

        const fires = sourceData('fires-source');
        const drought = sourceData('drought-source');
        const droughtFeatures = (drought && drought.features) || [];

        const inConus = ((fires && fires.features) || []).filter(f => {
            const c = f.geometry && f.geometry.type === 'Point' && f.geometry.coordinates;
            return c && c[0] >= CONUS.minLon && c[0] <= CONUS.maxLon &&
                c[1] >= CONUS.minLat && c[1] <= CONUS.maxLat;
        });

        const cells = S.hexBin(inConus, { cellKm: CELL_KM });
        if (!cells.length) {
            window.HazardLayers.updateSource('bivariate',
                { type: 'FeatureCollection', features: [] });
            return;
        }

        // Fire terciles among occupied cells
        const counts = cells.map(c => c.count).sort((a, b) => a - b);
        const t1 = counts[Math.floor(counts.length / 3)];
        const t2 = counts[Math.floor(2 * counts.length / 3)];
        const fireClass = (n) => (n > t2 ? 2 : n > t1 ? 1 : 0);

        const pip = droughtFeatures.length ? S.pointInPolygonIndex(drought) : null;

        const fc = S.toGeoJSON(cells, { cellKm: CELL_KM });
        for (let i = 0; i < fc.features.length; i++) {
            const f = fc.features[i];
            const cell = cells[i];
            const center = S._unproject(...(function () {
                const c = S._centerOf(cell.q, cell.r, S._sizeFor(CELL_KM));
                return [c[0], c[1]];
            })());
            const dProps = pip ? pip.query(center[0], center[1]) : null;
            const dc = droughtBucket(dProps);
            const fcls = fireClass(cell.count);
            f.properties.fire_class = fcls;
            f.properties.drought_class = dc;
            f.properties.bi_class = dc + '-' + fcls;
            f.properties.bi_color = PALETTE[dc][fcls];
            f.properties.fire_label = FIRE_LABELS[fcls];
            f.properties.drought_label = DROUGHT_LABELS[dc];
            f.properties.drought_area = dProps ? (dProps.county || dProps.state || '') : '';
        }
        fc.metadata = {
            scope: 'Contiguous US',
            method: 'Fire detections per 50 km hex (terciles) × max USDM class at hex center',
            fire_breaks: [t1, t2],
            computed_at: new Date().toISOString(),
        };
        window.HazardLayers.updateSource('bivariate', fc);
    }

    function scheduleRecompute() {
        clearTimeout(recomputeTimer);
        recomputeTimer = setTimeout(recompute, 400);
    }

    function init() {
        const cb = document.getElementById('toggle-bivariate');
        if (cb) {
            cb.addEventListener('change', () => {
                if (cb.checked) scheduleRecompute();
            });
        }
        // Refresh periodically while visible (fires update every 5 min)
        setInterval(() => {
            const checkbox = document.getElementById('toggle-bivariate');
            if (checkbox && checkbox.checked) scheduleRecompute();
        }, 10 * 60 * 1000);
        console.log('[Bivariate] Ready');
    }

    return { init, recompute, PALETTE, FIRE_LABELS, DROUGHT_LABELS };
})();

window.Bivariate = Bivariate;
