// Node fixture test for permalink.js parse — run: node test/permalink.test.js
'use strict';

const path = require('path');
const P = require(path.join(__dirname, '..', 'js', 'permalink.js'));

let failures = 0;
function assert(cond, msg) {
    if (cond) { console.log('  ok - ' + msg); }
    else { failures++; console.error('  FAIL - ' + msg); }
}

{
    const hash = '#v1&c=-120.3300,50.6700,7.25,15,45&l=fires.85,hotspots.100&t=168&b=satellite';
    const s = P.parse(hash);
    assert(!!s, 'v1 hash parses');
    assert(s.camera && s.camera.center[0] === -120.33 && s.camera.center[1] === 50.67,
        'camera center round-trips');
    assert(s.camera.zoom === 7.25 && s.camera.bearing === 15 && s.camera.pitch === 45,
        'zoom/bearing/pitch parsed');
    assert(s.layers.length === 2 && s.layers[0].type === 'fires' &&
        Math.abs(s.layers[0].opacity - 0.85) < 1e-9, 'layer list + opacity parsed');
    assert(s.hours === 168, 'time window parsed');
    assert(s.basemap === 'satellite', 'basemap parsed');
}

{
    assert(P.parse('#not-a-permalink') === null, 'non-v1 hash rejected');
    assert(P.parse('') === null, 'empty hash rejected');
    const partial = P.parse('#v1&c=1,2,3');
    assert(partial && partial.camera && partial.camera.bearing === 0,
        'missing bearing/pitch default to 0');
    const junk = P.parse('#v1&c=abc,def,ghi&l=&t=xyz');
    assert(junk && !junk.camera && junk.layers.length === 0,
        'malformed values dropped without throwing');
}

console.log(failures === 0 ? '\nALL TESTS PASSED' : '\n' + failures + ' FAILURES');
process.exit(failures === 0 ? 0 : 1);
