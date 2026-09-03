// ============================================================
// EcoLens SpatialStats — in-browser spatial statistics engine
// ("the map that reasons")
//
// Pure functions, zero DOM dependencies (worker-portable, Node-testable).
// Pipeline: hexBin(points) → giStar(cells) → toGeoJSON(cells).
//
// Method notes (disclosed in the layer popup):
// - Hexes are flat-top, laid out in Web Mercator meters, so real cell
//   area shrinks toward the poles (fires cluster within ±60° latitude,
//   where the distortion is acceptable for screening-level analysis).
// - Hot spots use Getis-Ord Gi* with binary weights over the 7-cell
//   neighborhood (self included). Significance buckets use plain z
//   thresholds (±1.96 / ±2.58); no FDR correction in v1.
// ============================================================

(function (root, factory) {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = factory();
    } else {
        root.SpatialStats = factory();
    }
})(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    const R = 6378137; // Web Mercator earth radius (m)
    const MAX_LAT = 85.05112878;

    function project(lon, lat) {
        lat = Math.max(-MAX_LAT, Math.min(MAX_LAT, lat));
        return [
            R * lon * Math.PI / 180,
            R * Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)),
        ];
    }

    function unproject(x, y) {
        return [
            (x / R) * 180 / Math.PI,
            (2 * Math.atan(Math.exp(y / R)) - Math.PI / 2) * 180 / Math.PI,
        ];
    }

    // Flat-top hexagons; `size` = center-to-vertex distance in meters.
    function sizeFor(cellKm) {
        return (cellKm * 1000) / 2; // hex width (2*size) == cellKm
    }

    function axialFromPoint(x, y, size) {
        const qf = (2 / 3) * x / size;
        const rf = (-1 / 3 * x + Math.sqrt(3) / 3 * y) / size;
        // Cube rounding
        const xf = qf, zf = rf, yf = -xf - zf;
        let rx = Math.round(xf), ry = Math.round(yf), rz = Math.round(zf);
        const dx = Math.abs(rx - xf), dy = Math.abs(ry - yf), dz = Math.abs(rz - zf);
        if (dx > dy && dx > dz) rx = -ry - rz;
        else if (dy > dz) ry = -rx - rz;
        else rz = -rx - ry;
        return [rx, rz]; // [q, r]
    }

    function centerOf(q, r, size) {
        return [
            size * 1.5 * q,
            size * Math.sqrt(3) * (r + q / 2),
        ];
    }

    const NEIGHBORS = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];

    function mark(name) {
        if (typeof performance !== 'undefined' && performance.mark) {
            try { performance.mark(name); } catch (e) { /* noop */ }
        }
    }

    function measure(name, a, b) {
        if (typeof performance !== 'undefined' && performance.measure) {
            try {
                performance.measure(name, a, b);
                const entries = performance.getEntriesByName(name);
                const last = entries[entries.length - 1];
                if (last && last.duration > 100) {
                    console.warn('[SpatialStats] ' + name + ' took ' +
                        Math.round(last.duration) + 'ms (>100ms budget — consider Web Worker)');
                }
            } catch (e) { /* noop */ }
        }
    }

    // ---------- Binning ----------

    // features: GeoJSON Point features. Returns array of cells
    // {q, r, count, sum} where sum aggregates opts.valueProp (default frp).
    function hexBin(features, opts) {
        opts = opts || {};
        const cellKm = opts.cellKm || 25;
        const valueProp = opts.valueProp || 'frp';
        const size = sizeFor(cellKm);

        mark('ss-bin-start');
        const cells = new Map();
        for (let i = 0; i < features.length; i++) {
            const f = features[i];
            const geom = f && f.geometry;
            if (!geom || geom.type !== 'Point') continue;
            const lon = geom.coordinates[0], lat = geom.coordinates[1];
            if (typeof lon !== 'number' || typeof lat !== 'number') continue;
            const p = project(lon, lat);
            const qr = axialFromPoint(p[0], p[1], size);
            const key = qr[0] + ',' + qr[1];
            let cell = cells.get(key);
            if (!cell) {
                cell = { q: qr[0], r: qr[1], count: 0, sum: 0 };
                cells.set(key, cell);
            }
            cell.count += 1;
            const v = f.properties && f.properties[valueProp];
            if (typeof v === 'number' && isFinite(v)) cell.sum += v;
        }
        mark('ss-bin-end');
        measure('SpatialStats.hexBin', 'ss-bin-start', 'ss-bin-end');
        return Array.from(cells.values());
    }

    // ---------- Getis-Ord Gi* ----------

    // cells: output of hexBin. Mutates each cell with gi_z and p_bucket.
    // Study area = occupied cells dilated by one ring of zero-valued cells,
    // so an isolated cell isn't compared only against itself.
    function giStar(cells, opts) {
        opts = opts || {};
        const valueOf = opts.value || (c => c.count);

        mark('ss-gi-start');
        const study = new Map(); // key -> value
        for (const c of cells) study.set(c.q + ',' + c.r, valueOf(c));
        if (opts.study !== 'occupied') {
            for (const c of cells) {
                for (const d of NEIGHBORS) {
                    const key = (c.q + d[0]) + ',' + (c.r + d[1]);
                    if (!study.has(key)) study.set(key, 0);
                }
            }
        }

        const n = study.size;
        if (n < 3) {
            for (const c of cells) { c.gi_z = 0; c.p_bucket = 'ns'; }
            return cells;
        }
        let sum = 0, sumSq = 0;
        for (const v of study.values()) { sum += v; sumSq += v * v; }
        const mean = sum / n;
        const sd = Math.sqrt(Math.max(sumSq / n - mean * mean, 0));

        for (const c of cells) {
            let localSum = valueOf(c);
            let w = 1; // binary weights, self included
            for (const d of NEIGHBORS) {
                const key = (c.q + d[0]) + ',' + (c.r + d[1]);
                if (study.has(key)) { localSum += study.get(key); w += 1; }
            }
            const denom = sd * Math.sqrt((n * w - w * w) / (n - 1));
            const z = denom > 0 ? (localSum - mean * w) / denom : 0;
            c.gi_z = Math.round(z * 1000) / 1000;
            c.p_bucket =
                z >= 2.58 ? 'hot99' :
                z >= 1.96 ? 'hot95' :
                z <= -1.96 ? 'cold95' : 'ns';
        }
        mark('ss-gi-end');
        measure('SpatialStats.giStar', 'ss-gi-start', 'ss-gi-end');
        return cells;
    }

    // ---------- GeoJSON output ----------

    // The hex FC schema contract: Polygon features with
    // {hex_id, count, sum_frp, gi_z, p_bucket}. Reused by the Atlas
    // upload (peer review), anomaly baselines, and the bivariate layer.
    function toGeoJSON(cells, opts) {
        opts = opts || {};
        const size = sizeFor(opts.cellKm || 25);
        const features = [];
        for (const c of cells) {
            const center = centerOf(c.q, c.r, size);
            const ring = [];
            for (let k = 0; k < 6; k++) {
                const angle = Math.PI / 3 * k;
                ring.push(unproject(
                    center[0] + size * Math.cos(angle),
                    center[1] + size * Math.sin(angle)
                ).map(v => Math.round(v * 1e5) / 1e5));
            }
            ring.push(ring[0]);
            features.push({
                type: 'Feature',
                geometry: { type: 'Polygon', coordinates: [ring] },
                properties: {
                    hex_id: c.q + ',' + c.r,
                    count: c.count,
                    sum_frp: Math.round(c.sum * 10) / 10,
                    gi_z: c.gi_z !== undefined ? c.gi_z : null,
                    p_bucket: c.p_bucket || 'ns',
                },
            });
        }
        return { type: 'FeatureCollection', features };
    }

    // ---------- Point-in-polygon with a bbox index ----------

    function ringContains(ring, lon, lat) {
        let inside = false;
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
            const xi = ring[i][0], yi = ring[i][1];
            const xj = ring[j][0], yj = ring[j][1];
            if (((yi > lat) !== (yj > lat)) &&
                (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
                inside = !inside;
            }
        }
        return inside;
    }

    function polyContains(coordinates, lon, lat) {
        if (!ringContains(coordinates[0], lon, lat)) return false;
        for (let h = 1; h < coordinates.length; h++) {
            if (ringContains(coordinates[h], lon, lat)) return false; // in a hole
        }
        return true;
    }

    // Returns {query(lon, lat) -> properties | null} over a Polygon /
    // MultiPolygon FeatureCollection.
    function pointInPolygonIndex(fc) {
        const entries = [];
        for (const f of (fc && fc.features) || []) {
            const geom = f.geometry;
            if (!geom) continue;
            const polys = geom.type === 'Polygon' ? [geom.coordinates]
                : geom.type === 'MultiPolygon' ? geom.coordinates : [];
            for (const coords of polys) {
                let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
                for (const pt of coords[0]) {
                    if (pt[0] < minx) minx = pt[0];
                    if (pt[0] > maxx) maxx = pt[0];
                    if (pt[1] < miny) miny = pt[1];
                    if (pt[1] > maxy) maxy = pt[1];
                }
                entries.push({ bbox: [minx, miny, maxx, maxy], coords, props: f.properties });
            }
        }
        return {
            query(lon, lat) {
                for (const e of entries) {
                    const b = e.bbox;
                    if (lon < b[0] || lon > b[2] || lat < b[1] || lat > b[3]) continue;
                    if (polyContains(e.coords, lon, lat)) return e.props;
                }
                return null;
            },
            size: entries.length,
        };
    }

    return {
        hexBin,
        giStar,
        toGeoJSON,
        pointInPolygonIndex,
        // exported for tests
        _project: project,
        _unproject: unproject,
        _axialFromPoint: axialFromPoint,
        _centerOf: centerOf,
        _sizeFor: sizeFor,
    };
});
