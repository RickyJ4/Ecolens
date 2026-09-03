// Node fixture test for spatial-stats.js — run: node test/spatial-stats.test.js
'use strict';

const path = require('path');
const S = require(path.join(__dirname, '..', 'js', 'spatial-stats.js'));

let failures = 0;
function assert(cond, msg) {
    if (cond) { console.log('  ok - ' + msg); }
    else { failures++; console.error('  FAIL - ' + msg); }
}

// --- Projection round-trip ---
{
    const [x, y] = S._project(-122.8, 49.2);
    const [lon, lat] = S._unproject(x, y);
    assert(Math.abs(lon - -122.8) < 1e-9 && Math.abs(lat - 49.2) < 1e-6,
        'mercator project/unproject round-trip');
}

// --- Axial round-trip: hex centers map back to their own hex ---
{
    const size = S._sizeFor(25);
    let ok = true;
    for (const [q, r] of [[0, 0], [3, -2], [-5, 7], [100, -40]]) {
        const c = S._centerOf(q, r, size);
        const back = S._axialFromPoint(c[0], c[1], size);
        if (back[0] !== q || back[1] !== r) ok = false;
    }
    assert(ok, 'axial center round-trip');
}

// --- Fixture: 37k background points + planted cluster ---
function mulberry32(seed) {
    return function () {
        let t = (seed += 0x6D2B79F5);
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
const rand = mulberry32(42);
const features = [];
// Sparse background: 36,500 points scattered over a continent-sized area
for (let i = 0; i < 36500; i++) {
    features.push({
        type: 'Feature',
        geometry: {
            type: 'Point',
            coordinates: [-130 + rand() * 60, 30 + rand() * 25],
        },
        properties: { frp: rand() * 20 },
    });
}
// Planted dense cluster: 500 points inside ~10km near Kamloops
for (let i = 0; i < 500; i++) {
    features.push({
        type: 'Feature',
        geometry: {
            type: 'Point',
            coordinates: [-120.33 + (rand() - 0.5) * 0.1, 50.67 + (rand() - 0.5) * 0.07],
        },
        properties: { frp: 50 + rand() * 100 },
    });
}

{
    const t0 = Date.now();
    const cells = S.giStar(S.hexBin(features, { cellKm: 25 }));
    const fc = S.toGeoJSON(cells, { cellKm: 25 });
    const elapsed = Date.now() - t0;
    console.log('  info - ' + features.length + ' points -> ' + cells.length +
        ' cells in ' + elapsed + 'ms');
    assert(elapsed < 200, 'bin+Gi*+toGeoJSON under 200ms (was ' + elapsed + 'ms)');

    // The planted cluster's hex must be hot99
    const size = S._sizeFor(25);
    const p = S._project(-120.33, 50.67);
    const [q, r] = S._axialFromPoint(p[0], p[1], size);
    const clusterCell = cells.find(c => c.q === q && c.r === r);
    assert(!!clusterCell, 'planted cluster cell exists');
    assert(clusterCell && clusterCell.p_bucket === 'hot99',
        'planted cluster is hot99 (z=' + (clusterCell && clusterCell.gi_z) + ')');

    // Background cells should be overwhelmingly not-significant
    const hot = cells.filter(c => c.p_bucket === 'hot99').length;
    assert(hot < cells.length * 0.05,
        'hot99 cells are rare (' + hot + '/' + cells.length + ')');

    // Schema contract
    const f0 = fc.features[0];
    const keys = Object.keys(f0.properties).sort().join(',');
    assert(keys === 'count,gi_z,hex_id,p_bucket,sum_frp',
        'hex FC schema contract {hex_id,count,sum_frp,gi_z,p_bucket}');
    assert(f0.geometry.type === 'Polygon' &&
        f0.geometry.coordinates[0].length === 7,
        'hex polygons are closed 6-gons');
}

// --- Point-in-polygon index ---
{
    const square = {
        type: 'FeatureCollection',
        features: [{
            type: 'Feature',
            geometry: {
                type: 'Polygon',
                coordinates: [[[-1, -1], [1, -1], [1, 1], [-1, 1], [-1, -1]]],
            },
            properties: { name: 'square' },
        }],
    };
    const idx = S.pointInPolygonIndex(square);
    assert(idx.query(0, 0) && idx.query(0, 0).name === 'square', 'PIP inside hit');
    assert(idx.query(2, 2) === null, 'PIP outside miss');
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : '\n' + failures + ' FAILURES');
process.exit(failures === 0 ? 0 : 1);
