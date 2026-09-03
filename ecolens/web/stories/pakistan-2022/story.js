/* ─────────────────────────────────────────────────────────────
   Pakistan 2022 storymap — interactive scrollytelling
   Light theme · MapLibre Positron · 19 steps across 5 sections
   ───────────────────────────────────────────────────────────── */

const BUILD = 'atlas-map-quality-v20';
const DATA = 'data/';

const HASH_ROUTES = {
  '#micro-sim': { id: 'micro-sim', step: 8.5 },
  '#human-scenes': { id: 'human-scenes', step: 10.5 },
  '#closing-map': { id: 'closing-map', step: 19 },
};

if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
window.addEventListener('load', () => {
  if (!window.location.hash) setTimeout(() => window.scrollTo(0, 0), 0);
});

const C = {
  water: '#1E6FB8', waterDeep: '#0B4D8C', waterFaint: 'rgba(30,111,184,0.40)',
  ink: '#1A1A1A', inkSoft: '#4A4A4A', inkFaint: '#777777',
  accent: '#1A7D5A', alert: '#C4452E', gold: '#C19A1A',
  bg: '#FAF7F2', panel: '#FFFFFF', panelLine: '#E2DDD0',
  city: '#3B5BA9', international: '#7A4FC7', response: '#E56B2E',
  ecoFill: 'rgba(26, 125, 90, 0.32)', ecoLine: '#1A7D5A',
};

const CITY_SPOTLIGHTS = [
  {
    id: 'dadu',
    title: 'Dadu, Sindh',
    kicker: 'Homes and roads isolated',
    center: [67.7771, 26.7319],
    zoom: 12.9,
    pitch: 48,
    bearing: -18,
    color: C.alert,
    areaKm: 18,
    image: 'assets/spotlights/dadu.jpg',
    scene: 'A town turns into an island.',
    losses: ['homes', 'roads', 'clinics', 'fields'],
    copy: 'One of the hardest-hit floodplain districts. The city-level view shows why the disaster was not just water on a map: roads, fields, clinics, and homes were cut off together.',
    facts: ['Sindh floodplain', 'Dadu district', 'Long-duration flooding'],
    credit: 'Image: Wikimedia Commons/local asset. Map flood extent: UNOSAT.',
  },
  {
    id: 'manchar',
    title: 'Manchar Lake',
    kicker: 'Breach zone',
    center: [67.6573, 26.417],
    zoom: 11.25,
    pitch: 48,
    bearing: 22,
    color: C.water,
    areaKm: 24,
    image: 'assets/spotlights/manchar.jpg',
    scene: 'A breach protects one place by flooding another.',
    losses: ['fishing', 'villages', 'livestock', 'boats'],
    copy: 'Manchar Lake swelled against its embankments, then a protective breach was opened on 5 September 2022. That decision lowered risk for one place by pushing floodwater toward another.',
    facts: ['Lake expansion', '5 Sep breach', 'Mohana fishers'],
    credit: 'Image: NASA Earth Observatory/local asset.',
  },
  {
    id: 'sukkur',
    title: 'Sukkur Barrage',
    kicker: 'River-control infrastructure',
    center: [68.843, 27.6936],
    zoom: 13.4,
    pitch: 52,
    bearing: 30,
    color: C.gold,
    areaKm: 11,
    image: 'assets/spotlights/sukkur.jpg',
    scene: 'The engineered river becomes part of the crisis.',
    losses: ['canals', 'drains', 'barrages', 'markets'],
    copy: 'Sukkur shows the engineered lower Indus: barrages, canals, embankments, and settlements packed into a flat corridor. In 2022, the system was under pressure from local rain and upstream flow.',
    facts: ['Lower Indus', 'Canal network', 'Drainage pressure'],
    credit: 'Image: Wikimedia Commons/local asset.',
  },
  {
    id: 'hyderabad',
    title: 'Hyderabad region',
    kicker: 'Lower-Indus corridor',
    center: [68.3578, 25.396],
    zoom: 12.2,
    pitch: 42,
    bearing: -10,
    color: C.city,
    areaKm: 16,
    image: 'assets/spotlights/hyderabad.jpg',
    scene: 'The flood reaches the urban corridor.',
    losses: ['transport', 'shops', 'schools', 'services'],
    copy: 'Hyderabad anchors the lower-Indus urban and agricultural corridor. It helps the audience understand that floods moved through markets, transport links, farms, and dense settlement patterns at once.',
    facts: ['Urban corridor', 'Sindh', 'Trade and farms'],
    credit: 'Image: NASA Earth Observatory/local asset.',
  },
  {
    id: 'jacobabad',
    title: 'Jacobabad, Sindh',
    kicker: 'Heat before rain',
    center: [68.4514, 28.2769],
    zoom: 12.6,
    pitch: 42,
    bearing: 18,
    color: C.alert,
    areaKm: 13,
    image: 'assets/spotlights/jacobabad.jpg',
    scene: 'Before the water, there was heat.',
    losses: ['heat stress', 'soil moisture', 'water demand', 'livelihoods'],
    copy: 'Jacobabad is the prelude: before the flood story becomes water, it is heat. The June 2022 heatwave helped dry soil, stress people, and amplify upstream melt before the monsoon peaked.',
    facts: ['51 C reported', 'Pre-monsoon heat', 'Sindh'],
    credit: 'Image: NASA/local asset.',
  },
  {
    id: 'hunza',
    title: 'Hunza / Shisper Glacier',
    kicker: 'Mountain warning',
    center: [74.645, 36.3219],
    zoom: 11.7,
    pitch: 62,
    bearing: 20,
    color: C.waterDeep,
    areaKm: 10,
    image: 'assets/spotlights/hunza.jpg',
    scene: 'The warning starts in the mountains.',
    losses: ['bridge', 'road access', 'valley links', 'glacier risk'],
    copy: 'Hundreds of kilometres upstream, the Shisper glacial-lake outburst destroyed the Hassanabad Bridge on 7 May 2022. It gives the story a northern bookend before the floodplain disaster downstream.',
    facts: ['7 May 2022 GLOF', 'Karakoram', 'Hassanabad Bridge'],
    credit: 'Image: NASA/local asset.',
  },
];

const SPOTLIGHT_PATH_COORDS = [
  [74.645, 36.3219],
  [72.2, 34.4],
  [70.3, 31.2],
  [68.843, 27.6936],
  [67.6573, 26.417],
  [67.7771, 26.7319],
  [68.3578, 25.396],
];

/* ─── MAP INIT ─────────────────────────────────────────────── */
const map = new maplibregl.Map({
  container: 'map',
  style: 'https://tiles.openfreemap.org/styles/positron',  // light basemap
  center: [69.5, 30.5],
  zoom: 4.4,
  attributionControl: false,
  pitch: 55,            // start tilted — cinematic from the first frame
  bearing: -8,
  maxPitch: 80,         // v5 allows deeper tilt for ground-level immersion
});
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');

let GEO = {}, terrainOn = false, extrudeOn = false, imageryOn = true, currentChapter = null;
let ecoSubTimer = null;
let cameraSettleTimer = null;

/* ─── LOAD DATA + LAYERS ──────────────────────────────────── */
map.on('load', async () => {
  const j = async (n) => (await fetch(`${DATA}${n}.geojson`)).json();
  const opt = async (n) => { try { return await j(n); } catch (_) { return null; } };
  [GEO.provinces, GEO.districts, GEO.floodCum, GEO.floodWeekly, GEO.floodSindh,
   GEO.ngos, GEO.communityResponses, GEO.species, GEO.landmarks, GEO.cities,
   GEO.international, GEO.recovery, GEO.ecosystems, GEO.preflood] = await Promise.all([
    j('provinces'), j('districts_pop'), j('flood_cumulative'),
    j('flood_weekly'), opt('flood_sindh_peak'),
    j('ngo_pins'), j('community_response_sites'), j('species_pins'), j('landmarks'),
    j('cities'), j('international'), j('recovery_sites'), j('ecosystems'),
    j('preflood_events'),
  ]);
  GEO.stats = await (await fetch(`${DATA}stats.json`)).json();
  GEO.country = await (await fetch(`${DATA}country_profile.json`)).json();

  /* ─── Terrain (AWS Terrarium, free) + hillshade ─── */
  map.addSource('terrain-dem', {
    type: 'raster-dem',
    tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],
    tileSize: 256, encoding: 'terrarium', maxzoom: 12,
  });
  map.addLayer({
    id: 'hillshade', type: 'hillshade', source: 'terrain-dem',
    paint: {
      'hillshade-shadow-color': '#5a5040',
      'hillshade-highlight-color': '#ffffff',
      'hillshade-exaggeration': 0.25,
    },
  });

  map.addSource('satellite_imagery', {
    type: 'raster',
    tiles: [
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    ],
    tileSize: 256,
    attribution: 'Imagery (c) Esri, Maxar, Earthstar Geographics, and the GIS User Community',
  });
  map.addLayer({
    id: 'satellite-imagery',
    type: 'raster',
    source: 'satellite_imagery',
    paint: {
      'raster-opacity': 0.82,
      'raster-saturation': -0.08,
      'raster-contrast': 0.08,
      'raster-brightness-min': 0.05,
      'raster-brightness-max': 0.92,
    },
  });

  /* ─── Sources ─── */
  for (const [id, data] of Object.entries({
    provinces: GEO.provinces, districts_pop: GEO.districts,
    flood_cumulative: GEO.floodCum, flood_weekly: GEO.floodWeekly,
    ngos: GEO.ngos, community_responses: GEO.communityResponses,
    species: GEO.species, landmarks: GEO.landmarks,
    cities: GEO.cities, international: GEO.international,
    recovery: GEO.recovery, ecosystems: GEO.ecosystems,
    preflood: GEO.preflood,
  })) {
    if (data) map.addSource(id, { type: 'geojson', data });
  }
  if (GEO.floodSindh) map.addSource('flood_sindh', { type: 'geojson', data: GEO.floodSindh });

  /* ─── Provinces (subtle backdrop) ─── */
  map.addLayer({ id: 'provinces-fill', type: 'fill', source: 'provinces',
    paint: { 'fill-color': '#EFE9DC', 'fill-opacity': 0.4 } });
  map.addLayer({ id: 'provinces-line', type: 'line', source: 'provinces',
    paint: { 'line-color': '#9A8F77', 'line-width': 0.7, 'line-opacity': 0.65 } });

  /* ─── Ecosystem polygons ─── */
  map.addLayer({ id: 'ecosystems-fill', type: 'fill', source: 'ecosystems',
    paint: {
      'fill-color': C.ecoFill,
      'fill-opacity': ['case', ['==', ['feature-state', 'highlight'], true], 0.7, 0],
    },
  });
  map.addLayer({ id: 'ecosystems-line', type: 'line', source: 'ecosystems',
    paint: {
      'line-color': C.ecoLine,
      'line-width': 1.5,
      'line-opacity': ['case', ['==', ['feature-state', 'highlight'], true], 1, 0],
    },
  });

  /* ─── Districts choropleth + extrusion ─── */
  map.addLayer({ id: 'districts-choropleth', type: 'fill', source: 'districts_pop',
    paint: {
      'fill-color': [
        'interpolate', ['linear'], ['get', 'pop_in_flood'],
        0, '#F5F2EA', 100000, '#C9DEEC', 500000, '#7FB2D8',
        1500000, '#3F87C1', 3500000, '#E89B3C', 6000000, '#C4452E',
      ],
      'fill-opacity': 0,
    },
  });
  map.addLayer({ id: 'districts-line', type: 'line', source: 'districts_pop',
    paint: { 'line-color': '#8C8273', 'line-width': 0.4, 'line-opacity': 0 } });
  map.addLayer({ id: 'districts-extrude', type: 'fill-extrusion', source: 'districts_pop',
    paint: {
      'fill-extrusion-color': [
        'interpolate', ['linear'], ['get', 'pop_in_flood'],
        0, '#C9DEEC', 500000, '#7FB2D8', 1500000, '#3F87C1',
        3500000, '#E89B3C', 6000000, '#C4452E',
      ],
      'fill-extrusion-height': ['*', ['sqrt', ['get', 'pop_in_flood']], 100],
      'fill-extrusion-base': 0,
      'fill-extrusion-opacity': 0,
    },
  });

  /* ─── Flood layers ─── */
  map.addLayer({ id: 'flood-cumulative-fill', type: 'fill', source: 'flood_cumulative',
    paint: { 'fill-color': C.water, 'fill-opacity': 0 } });
  map.addLayer({ id: 'flood-cumulative-line', type: 'line', source: 'flood_cumulative',
    paint: { 'line-color': C.waterDeep, 'line-width': 0.4, 'line-opacity': 0 } });
  map.addLayer({ id: 'flood-weekly-fill', type: 'fill', source: 'flood_weekly',
    paint: { 'fill-color': C.water, 'fill-opacity': 0 },
    filter: ['==', 'key', 'w1'],
  });
  if (GEO.floodSindh) {
    map.addLayer({ id: 'flood-sindh-fill', type: 'fill', source: 'flood_sindh',
      paint: { 'fill-color': C.water, 'fill-opacity': 0 } });
  }

  /* ─── Pin layers ─── */
  addPinLayer('cities', C.city, 6, 'name');
  addPinLayer('landmarks', C.alert, 5, '');
  addPinLayer('ngos', C.accent, 9, 'name');
  addPinLayer('community_responses', C.response, 8, 'name');
  addPinLayer('species', C.gold, 8, 'name');
  addPinLayer('international', C.international, 9, 'name');
  addPinLayer('recovery', '#B8860B', 8, '');

  // Pre-flood events: 2 layers (climate vs structural) for color coding
  map.addLayer({
    id: 'preflood-pins', type: 'circle', source: 'preflood',
    paint: {
      'circle-radius': 7,
      'circle-color': ['case',
        ['==', ['get', 'category'], 'climate'], C.water,
        C.alert],
      'circle-stroke-color': '#FFFFFF',
      'circle-stroke-width': 2,
      'circle-stroke-opacity': 0,
      'circle-opacity': 0,
    },
  });

  addMicroSceneLayers();
  addCitySpotlightLayers();
  attachPopups();
  bindSpotlightClicks();
  bindToolbar();
  bindJumpControls();

  /* ─── IMMERSIVE / "YOU ARE THERE" SETUP ─────────────────────
     Globe curvature at world scale, real 3D terrain from frame one,
     and a warm, dusty atmospheric sky + ground haze for depth.    */
  try { map.setProjection({ type: 'globe' }); } catch (e) { /* v4 fallback: stays mercator */ }

  // Terrain ON by default so the very first scene already feels three-dimensional
  terrainOn = true;
  map.setTerrain({ source: 'terrain-dem', exaggeration: 1.6 });
  const btn3d = document.getElementById('btn-toggle-3d');
  if (btn3d) btn3d.classList.add('active');

  // Atmospheric sky + fog (fog requires terrain, which is now on)
  if (typeof map.setSky === 'function') {
    map.setSky({
      'sky-color': '#9cc0de',          // soft daylight blue overhead
      'sky-horizon-blend': 0.7,
      'horizon-color': '#e9dac0',       // warm dusty haze along the horizon
      'horizon-fog-blend': 0.6,
      'fog-color': '#ddccb0',           // heat/dust haze sitting on the ground
      'fog-ground-blend': 0.78,
      // strong atmosphere far out, fading away as you drop into close-ups
      'atmosphere-blend': ['interpolate', ['linear'], ['zoom'], 0, 0.9, 5, 0.7, 9, 0.45, 13, 0],
    });
  }

  setImagery(true);
  applyChapter(1, true);
  applyInitialHash();
});

function addPinLayer(srcId, color, radius, labelField) {
  map.addLayer({
    id: `${srcId}-pins`, type: 'circle', source: srcId,
    paint: {
      'circle-radius': radius, 'circle-color': color,
      'circle-stroke-color': '#FFFFFF', 'circle-stroke-width': 2,
      'circle-stroke-opacity': 0, 'circle-opacity': 0,
    },
  });
  if (labelField) {
    map.addLayer({
      id: `${srcId}-labels`, type: 'symbol', source: srcId,
      layout: {
        'text-field': ['get', labelField], 'text-font': ['Noto Sans Bold'],
        'text-size': 11, 'text-offset': [0, 1.4], 'text-anchor': 'top',
      },
      paint: {
        'text-color': C.ink, 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5,
        'text-opacity': 0,
      },
    });
  }
}

function citySpotlightCollection() {
  return {
    type: 'FeatureCollection',
    features: CITY_SPOTLIGHTS.map((item, index) => ({
      type: 'Feature',
      properties: {
        id: item.id,
        title: item.title,
        kicker: item.kicker,
        index,
        color: item.color,
      },
      geometry: { type: 'Point', coordinates: item.center },
    })),
  };
}

function circlePolygonFeature(center, radiusKm, props, steps = 72) {
  const [lng, lat] = center;
  const latRadius = radiusKm / 111.32;
  const lngRadius = radiusKm / (111.32 * Math.cos(lat * Math.PI / 180));
  const coords = [];
  for (let i = 0; i <= steps; i++) {
    const angle = (i / steps) * Math.PI * 2;
    coords.push([
      lng + Math.cos(angle) * lngRadius,
      lat + Math.sin(angle) * latRadius,
    ]);
  }
  return {
    type: 'Feature',
    properties: props,
    geometry: { type: 'Polygon', coordinates: [coords] },
  };
}

function citySpotlightAreaCollection() {
  return {
    type: 'FeatureCollection',
    features: CITY_SPOTLIGHTS.map((item, index) => circlePolygonFeature(
      item.center,
      item.areaKm,
      { id: item.id, title: item.title, index, color: item.color }
    )),
  };
}

function spotlightPathCollection() {
  return {
    type: 'FeatureCollection',
    features: [{
      type: 'Feature',
      properties: { name: 'Follow the water path' },
      geometry: { type: 'LineString', coordinates: SPOTLIGHT_PATH_COORDS },
    }],
  };
}

function addCitySpotlightLayers() {
  map.addSource('spotlight_areas', { type: 'geojson', data: citySpotlightAreaCollection() });
  map.addSource('spotlight_path', { type: 'geojson', data: spotlightPathCollection() });
  map.addSource('city_spotlights', { type: 'geojson', data: citySpotlightCollection() });
  map.addLayer({
    id: 'spotlight-path-shadow',
    type: 'line',
    source: 'spotlight_path',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: {
      'line-color': '#FFFFFF',
      'line-width': 8,
      'line-opacity': 0,
    },
  });
  map.addLayer({
    id: 'spotlight-path',
    type: 'line',
    source: 'spotlight_path',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: {
      'line-color': C.waterDeep,
      'line-width': 4,
      'line-opacity': 0,
      'line-dasharray': [1.2, 1.1],
    },
  });
  map.addLayer({
    id: 'spotlight-areas',
    type: 'fill',
    source: 'spotlight_areas',
    paint: {
      'fill-color': ['get', 'color'],
      'fill-opacity': 0,
    },
  });
  map.addLayer({
    id: 'spotlight-active-area',
    type: 'fill',
    source: 'spotlight_areas',
    filter: ['==', ['get', 'id'], 'none'],
    paint: {
      'fill-color': ['get', 'color'],
      'fill-opacity': 0,
    },
  });
  map.addLayer({
    id: 'spotlight-active-outline',
    type: 'line',
    source: 'spotlight_areas',
    filter: ['==', ['get', 'id'], 'none'],
    paint: {
      'line-color': ['get', 'color'],
      'line-width': 3,
      'line-opacity': 0,
      'line-dasharray': [1.5, 0.8],
    },
  });
  map.addLayer({
    id: 'spotlight-halo',
    type: 'circle',
    source: 'city_spotlights',
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 5, 12, 13, 26],
      'circle-color': ['get', 'color'],
      'circle-opacity': 0,
      'circle-blur': 0.55,
    },
  });
  map.addLayer({
    id: 'spotlight-pins',
    type: 'circle',
    source: 'city_spotlights',
    paint: {
      'circle-radius': 7.5,
      'circle-color': ['get', 'color'],
      'circle-stroke-color': '#FFFFFF',
      'circle-stroke-width': 2.5,
      'circle-stroke-opacity': 0,
      'circle-opacity': 0,
    },
  });
  map.addLayer({
    id: 'spotlight-labels',
    type: 'symbol',
    source: 'city_spotlights',
    layout: {
      'text-field': ['get', 'title'],
      'text-font': ['Noto Sans Bold'],
      'text-size': 12,
      'text-offset': [0, 1.45],
      'text-anchor': 'top',
    },
    paint: {
      'text-color': C.ink,
      'text-halo-color': '#FFFFFF',
      'text-halo-width': 1.8,
      'text-opacity': 0,
    },
  });
}

/* ─── POPUPS ──────────────────────────────────────────────── */
/* Close-up conceptual flood scene near the Dadu-Manchar floodplain. */
function rectFeature(cx, cy, w, h, props) {
  return {
    type: 'Feature',
    properties: props,
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [cx - w / 2, cy - h / 2],
        [cx + w / 2, cy - h / 2],
        [cx + w / 2, cy + h / 2],
        [cx - w / 2, cy + h / 2],
        [cx - w / 2, cy - h / 2],
      ]],
    },
  };
}

function polygonFeature(coords, props) {
  return {
    type: 'Feature',
    properties: props,
    geometry: { type: 'Polygon', coordinates: [coords] },
  };
}

function pointFeature(coord, props) {
  return {
    type: 'Feature',
    properties: props,
    geometry: { type: 'Point', coordinates: coord },
  };
}

function makeMicroSceneData() {
  const houses = [];
  const rows = [
    { y: 26.73345, stage: 2, heights: [15, 17, 15, 18] },
    { y: 26.73405, stage: 3, heights: [17, 16, 22, 17] },
    { y: 26.73465, stage: 3, heights: [15, 18, 17, 16] },
  ];
  rows.forEach((row, r) => {
    row.heights.forEach((height, c) => {
      const kind = r === 1 && c === 2 ? 'Village clinic' : r === 2 && c === 0 ? 'School room' : 'Family home';
      houses.push(rectFeature(
        67.7850 + c * 0.00055,
        row.y,
        0.00038,
        0.00030,
        { kind, height, hit_stage: row.stage, story: 'Low masonry and mud-brick structure in the floodplain.' }
      ));
    });
  });

  return {
    houses: { type: 'FeatureCollection', features: houses },
    farms: {
      type: 'FeatureCollection',
      features: [
        rectFeature(67.7818, 26.7332, 0.0024, 0.00145, { kind: 'Cotton field', hit_stage: 1, story: 'Crop land saturates before homes are reached.' }),
        rectFeature(67.7825, 26.7350, 0.0026, 0.00125, { kind: 'Rice plot', hit_stage: 1, story: 'Standing water can destroy seed, crop, and soil quality.' }),
        rectFeature(67.7878, 26.7356, 0.0020, 0.00115, { kind: 'Grazing patch', hit_stage: 3, story: 'Livestock movement becomes difficult once roads are cut.' }),
      ],
    },
    road: {
      type: 'FeatureCollection',
      features: [{
        type: 'Feature',
        properties: { kind: 'Raised road', hit_stage: 2, story: 'When this road is cut, families lose access to markets, clinics, and relief trucks.' },
        geometry: {
          type: 'LineString',
          coordinates: [
            [67.7810, 26.7324],
            [67.7832, 26.7333],
            [67.7854, 26.7338],
            [67.7889, 26.7352],
          ],
        },
      }],
    },
    labels: {
      type: 'FeatureCollection',
      features: [
        pointFeature([67.7820, 26.7349], { label: 'Farm plots', anchor: 'top' }),
        pointFeature([67.7852, 26.7338], { label: 'Raised road', anchor: 'bottom' }),
        pointFeature([67.7862, 26.7344], { label: 'Homes + clinic', anchor: 'top' }),
        pointFeature([67.7811, 26.7330], { label: 'Floodwater', anchor: 'bottom' }),
      ],
    },
  };
}

const MICRO_FLOOD_STAGES = [
  {
    label: 'Dry ground',
    body: 'The settlement is still connected. Farm plots, road, and homes are visible.',
    height: 0,
    impact: 0,
    coords: [[67.7790, 26.7310], [67.7791, 26.7310], [67.7791, 26.7311], [67.7790, 26.7311], [67.7790, 26.7310]],
  },
  {
    label: 'Fields saturate',
    body: 'Water reaches the lowest crop land first. Livelihood damage begins before homes flood.',
    height: 2.5,
    impact: 1,
    coords: [[67.7791, 26.7312], [67.7832, 26.7312], [67.7840, 26.7364], [67.7790, 26.7362], [67.7791, 26.7312]],
  },
  {
    label: 'Road access fails',
    body: 'The water cuts the raised road. Movement to clinics, markets, and relief points slows down.',
    height: 4.5,
    impact: 2,
    coords: [[67.7790, 26.7307], [67.7860, 26.7310], [67.7867, 26.7370], [67.7790, 26.7368], [67.7790, 26.7307]],
  },
  {
    label: 'Homes become unsafe',
    body: 'Water surrounds the first houses. Families move to roofs, embankments, relatives, or camps.',
    height: 6.8,
    impact: 3,
    coords: [[67.7786, 26.7304], [67.7890, 26.7308], [67.7893, 26.7374], [67.7786, 26.7372], [67.7786, 26.7304]],
  },
  {
    label: 'Settlement isolated',
    body: 'The map no longer shows only water. It shows lost shelter, cut roads, ruined crops, and delayed relief.',
    height: 8.5,
    impact: 3,
    coords: [[67.7783, 26.7300], [67.7900, 26.7304], [67.7906, 26.7379], [67.7782, 26.7377], [67.7783, 26.7300]],
  },
];

function addMicroSceneLayers() {
  const micro = makeMicroSceneData();
  map.addSource('micro_houses', { type: 'geojson', data: micro.houses });
  map.addSource('micro_farms', { type: 'geojson', data: micro.farms });
  map.addSource('micro_road', { type: 'geojson', data: micro.road });
  map.addSource('micro_flood', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
  map.addSource('micro_labels', { type: 'geojson', data: micro.labels });

  map.addLayer({ id: 'micro-farms', type: 'fill', source: 'micro_farms',
    paint: { 'fill-color': '#D6B36B', 'fill-opacity': 0 } });
  map.addLayer({ id: 'micro-farms-outline', type: 'line', source: 'micro_farms',
    paint: { 'line-color': '#8C6F34', 'line-width': 1, 'line-opacity': 0 } });
  map.addLayer({ id: 'micro-road', type: 'line', source: 'micro_road',
    paint: { 'line-color': '#65584B', 'line-width': 0, 'line-opacity': 0 } });
  map.addLayer({ id: 'micro-houses', type: 'fill-extrusion', source: 'micro_houses',
    paint: {
      'fill-extrusion-color': '#D6C8B5',
      'fill-extrusion-height': ['get', 'height'],
      'fill-extrusion-base': 0,
      'fill-extrusion-opacity': 0,
    },
  });
  map.addLayer({ id: 'micro-flood-fill', type: 'fill', source: 'micro_flood',
    paint: { 'fill-color': C.water, 'fill-opacity': 0 } });
  map.addLayer({ id: 'micro-flood-extrude', type: 'fill-extrusion', source: 'micro_flood',
    paint: {
      'fill-extrusion-color': C.water,
      'fill-extrusion-height': ['get', 'height'],
      'fill-extrusion-base': 0,
      'fill-extrusion-opacity': 0,
      'fill-extrusion-vertical-gradient': true,
    },
  });
  map.addLayer({
    id: 'micro-labels',
    type: 'symbol',
    source: 'micro_labels',
    layout: {
      'text-field': ['get', 'label'],
      'text-font': ['Noto Sans Bold'],
      'text-size': 12,
      'text-anchor': ['get', 'anchor'],
      'text-offset': [0, 0.65],
      'text-allow-overlap': true,
    },
    paint: {
      'text-color': C.ink,
      'text-halo-color': '#FFFFFF',
      'text-halo-width': 2,
      'text-opacity': 0,
    },
  });
}

function attachPopups() {
  const popup = new maplibregl.Popup({ closeButton: false, closeOnClick: true, offset: 14 });
  const bind = (layerId, html) => {
    map.on('mouseenter', layerId, () => map.getCanvas().style.cursor = 'pointer');
    map.on('mouseleave', layerId, () => { map.getCanvas().style.cursor = ''; popup.remove(); });
    map.on('click', layerId, (e) => {
      const f = e.features[0];
      const coords = f.geometry.type === 'Point' ? f.geometry.coordinates : e.lngLat;
      popup.setLngLat(coords).setHTML(html(f.properties)).addTo(map);
    });
  };
  ['districts-choropleth', 'districts-extrude'].forEach(l => bind(l, (p) => `
    <h4>${p.NAME_2}, ${p.NAME_1}</h4>
    <div class="pop-sub">Population in 2022 flood zone</div>
    <div style="font-size:1.45rem;color:${C.waterDeep};font-weight:600;margin-top:0.3rem;">
      ${Number(p.pop_in_flood).toLocaleString()}
    </div>
    <div class="pop-sub">${Number(p.flood_area_km2).toLocaleString()} km² flooded</div>
  `));
  bind('cities-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.province} · pop ${Number(p.metro_pop_2024).toLocaleString()}</div>
    <p class="pop-body">${p.role}</p>
  `);
  bind('landmarks-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.kind}</div>
    <p class="pop-body">${p.story}</p>
  `);
  bind('ngos-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.city}</div>
    <p class="pop-body">${p.what}</p>
    ${p.url ? `<a href="${p.url}" target="_blank" style="color:${C.water};font-size:0.78rem;">${p.url.replace('https://','')}</a>` : ''}
  `);
  bind('community_responses-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.response_type || 'community response'} · ${p.location_name || ''}</div>
    <p class="pop-body">${p.what}</p>
    ${p.needs ? `<p class="pop-body"><strong>Needs:</strong> ${p.needs}</p>` : ''}
    ${p.verification_status ? `<div class="pop-sub">Verification: ${p.verification_status}</div>` : ''}
    ${p.support_url ? `<a href="${p.support_url}" target="_blank" style="color:${C.response};font-size:0.78rem;">support / learn more</a>` : ''}
  `);
  bind('species-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub"><em>${p.scientific}</em> · IUCN: <strong style="color:${C.alert};">${p.iucn}</strong></div>
    <p class="pop-body">${p.story}</p>
  `);
  bind('international-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.city}</div>
    <p class="pop-body">${p.role}</p>
    <div style="margin-top:0.5rem;font-size:0.78rem;color:${C.inkFaint};">${p.amount_label}</div>
    <div style="font-size:1.2rem;color:${C.international};font-weight:600;">
      $${(Number(p.amount_usd)/1e6).toLocaleString(undefined, {maximumFractionDigits: 0})} M
    </div>
  `);
  bind('recovery-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.kind}</div>
    <p class="pop-body">${p.story}</p>
    <div style="margin-top:0.4rem;font-size:1.2rem;color:${C.alert};font-weight:600;">
      ${Number(p.value).toLocaleString()}
    </div>
    <div class="pop-sub">${p.value_label}</div>
  `);
  bind('ecosystems-fill', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">${p.kind}</div>
    <p class="pop-body">${p.story}</p>
  `);
  bind('preflood-pins', (p) => `
    <h4>${p.name}</h4>
    <div class="pop-sub">
      <span style="color:${p.category === 'climate' ? C.water : C.alert};font-weight:600;text-transform:uppercase;letter-spacing:0.06em;">${p.category}</span>
      · ${p.date}
    </div>
    <p class="pop-body">${p.story}</p>
  `);
  bind('micro-houses', (p) => `
    <h4>${p.kind}</h4>
    <div class="pop-sub">Conceptual close-up</div>
    <p class="pop-body">${p.story}</p>
  `);
  bind('micro-farms', (p) => `
    <h4>${p.kind}</h4>
    <div class="pop-sub">Conceptual close-up</div>
    <p class="pop-body">${p.story}</p>
  `);
}

function bindSpotlightClicks() {
  ['spotlight-pins', 'spotlight-halo', 'spotlight-labels', 'spotlight-areas', 'spotlight-active-area'].forEach((layerId) => {
    map.on('mouseenter', layerId, () => {
      if (currentChapter === 10.5) map.getCanvas().style.cursor = 'pointer';
    });
    map.on('mouseleave', layerId, () => { map.getCanvas().style.cursor = ''; });
    map.on('click', layerId, (e) => {
      if (currentChapter !== 10.5) return;
      const f = e.features && e.features[0];
      if (!f) return;
      focusSpotlight(Number(f.properties.index), true);
    });
  });
}

function applyInitialHash() {
  const route = HASH_ROUTES[window.location.hash];
  if (!route) return;
  const el = document.getElementById(route.id);
  if (!el) return;
  setTimeout(() => {
    el.scrollIntoView({ block: 'center' });
    applyChapter(route.step, true);
  }, 250);
}

function jumpToHash(hash) {
  const route = HASH_ROUTES[hash];
  if (!route) return;
  const el = document.getElementById(route.id);
  if (el) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  if (window.location.hash !== hash) history.replaceState(null, '', hash);
  applyChapter(route.step, true);
}

function bindJumpControls() {
  document.querySelectorAll('[data-jump-hash]').forEach((btn) => {
    btn.addEventListener('click', () => jumpToHash(btn.dataset.jumpHash));
  });
}

window.addEventListener('hashchange', applyInitialHash);

/* ─── TOOLBAR ─────────────────────────────────────────────── */
function bindToolbar() {
  const imageryBtn = document.getElementById('btn-toggle-imagery');
  if (imageryBtn) imageryBtn.addEventListener('click', () => setImagery(!imageryOn));
  document.getElementById('btn-toggle-3d').addEventListener('click', () => {
    terrainOn = !terrainOn;
    if (terrainOn) {
      map.setTerrain({ source: 'terrain-dem', exaggeration: 1.5 });
      map.easeTo({ pitch: 55, duration: 700 });
      document.getElementById('btn-toggle-3d').classList.add('active');
    } else {
      map.setTerrain(null);
      map.easeTo({ pitch: 0, duration: 700 });
      document.getElementById('btn-toggle-3d').classList.remove('active');
    }
  });
  document.getElementById('btn-toggle-extrude').addEventListener('click', () => {
    extrudeOn = !extrudeOn;
    const op = extrudeOn ? 0.92 : 0;
    setPaint('districts-extrude', { 'fill-extrusion-opacity': op });
    if (extrudeOn) {
      setPaint('districts-choropleth', { 'fill-opacity': 0 });
      map.easeTo({ pitch: 55, duration: 800 });
      document.getElementById('btn-toggle-extrude').classList.add('active');
    } else {
      const handler = CHAPTERS[currentChapter];
      if (handler) handler();
      document.getElementById('btn-toggle-extrude').classList.remove('active');
    }
  });
  document.getElementById('btn-reset').addEventListener('click', () => {
    map.flyTo({ center: [69.5, 30.5], zoom: 4.4, pitch: terrainOn ? 55 : 0, bearing: 0, duration: 900 });
  });
  const range = document.getElementById('scrubber-range');
  const readout = document.getElementById('scrubber-readout');
  range.addEventListener('input', (e) => {
    const i = +e.target.value;
    const w = WEEKS[i];
    map.setFilter('flood-weekly-fill', ['==', 'key', w]);
    readout.textContent = WEEK_LABELS[w];
    legend([[C.water, `Flood extent — ${WEEK_LABELS[w]}`]],
           'Drag the slider to scrub through the monsoon');
  });
}

/* ─── HELPERS ─────────────────────────────────────────────── */
function setPaint(layerId, props) {
  if (!map.getLayer(layerId)) return;
  for (const [k, v] of Object.entries(props)) {
    map.setPaintProperty(layerId, k, v);
    if (k === 'circle-opacity') map.setPaintProperty(layerId, 'circle-stroke-opacity', v);
  }
}
function setImagery(on) {
  imageryOn = !!on;
  setPaint('satellite-imagery', { 'raster-opacity': imageryOn ? 0.9 : 0 });
  setPaint('hillshade', { 'hillshade-exaggeration': imageryOn ? 0.08 : 0.25 });
  const btn = document.getElementById('btn-toggle-imagery');
  if (btn) btn.classList.toggle('active', imageryOn);
}
function moveCamera(camera, duration = 1600) {
  clearTimeout(cameraSettleTimer);
  const targetChapter = currentChapter;
  const finalCamera = { bearing: 0, ...camera };
  map.stop();
  map.flyTo({ ...finalCamera, duration, essential: true });
  cameraSettleTimer = setTimeout(() => {
    if (currentChapter === targetChapter) map.jumpTo(finalCamera);
  }, duration + 220);
}
const ALL_FLOOD_FILLS = ['flood-cumulative-fill', 'flood-weekly-fill', 'flood-sindh-fill'];
const ALL_FLOOD_LINES = ['flood-cumulative-line'];
const ALL_PIN_LAYERS = [
  ['cities-pins','circle-opacity'], ['cities-labels','text-opacity'],
  ['landmarks-pins','circle-opacity'],
  ['ngos-pins','circle-opacity'], ['ngos-labels','text-opacity'],
  ['community_responses-pins','circle-opacity'], ['community_responses-labels','text-opacity'],
  ['species-pins','circle-opacity'], ['species-labels','text-opacity'],
  ['international-pins','circle-opacity'], ['international-labels','text-opacity'],
  ['recovery-pins','circle-opacity'],
  ['preflood-pins','circle-opacity'],
  ['spotlight-halo','circle-opacity'], ['spotlight-pins','circle-opacity'], ['spotlight-labels','text-opacity'],
];
function hideAllFloods() {
  ALL_FLOOD_FILLS.forEach(l => map.getLayer(l) && setPaint(l, { 'fill-opacity': 0 }));
  ALL_FLOOD_LINES.forEach(l => map.getLayer(l) && setPaint(l, { 'line-opacity': 0 }));
  if (map.getLayer('flood-weekly-extrude')) {
    setPaint('flood-weekly-extrude', { 'fill-extrusion-opacity': 0 });
  }
  hideMicroScene();
}
function hideAllPins() {
  ALL_PIN_LAYERS.forEach(([l, prop]) => map.getLayer(l) && setPaint(l, { [prop]: 0 }));
  showSpotlightLayers(false);
  showIndusRoute(false);
  hideSpotlightPanel();
}
function hideDistricts() {
  setPaint('districts-choropleth', { 'fill-opacity': 0 });
  setPaint('districts-line', { 'line-opacity': 0 });
  setPaint('districts-extrude', { 'fill-extrusion-opacity': 0 });
}
function showSpotlightLayers(show) {
  setPaint('spotlight-path-shadow', { 'line-opacity': show ? 0.65 : 0 });
  setPaint('spotlight-path', { 'line-opacity': show ? 0.88 : 0 });
  setPaint('spotlight-areas', { 'fill-opacity': show ? 0.14 : 0 });
  setPaint('spotlight-active-area', { 'fill-opacity': show ? 0.36 : 0 });
  setPaint('spotlight-active-outline', { 'line-opacity': show ? 0.95 : 0 });
  setPaint('spotlight-halo', { 'circle-opacity': show ? 0.08 : 0 });
  setPaint('spotlight-pins', { 'circle-opacity': show ? 0.32 : 0 });
  setPaint('spotlight-labels', { 'text-opacity': show ? 1 : 0 });
  if (!show) {
    if (map.getLayer('spotlight-active-area')) map.setFilter('spotlight-active-area', ['==', ['get', 'id'], 'none']);
    if (map.getLayer('spotlight-active-outline')) map.setFilter('spotlight-active-outline', ['==', ['get', 'id'], 'none']);
  }
}
function showIndusRoute(show) {
  setPaint('spotlight-path-shadow', { 'line-opacity': show ? 0.82 : 0 });
  setPaint('spotlight-path', { 'line-opacity': show ? 0.96 : 0 });
}
function showClosingLandscape() {
  showSpotlightLayers(true);
  setPaint('spotlight-areas', { 'fill-opacity': 0.22 });
  setPaint('spotlight-active-area', { 'fill-opacity': 0 });
  setPaint('spotlight-active-outline', { 'line-opacity': 0 });
  setPaint('spotlight-halo', { 'circle-opacity': 0 });
  setPaint('spotlight-pins', { 'circle-opacity': 0 });
  setPaint('spotlight-labels', { 'text-opacity': 0 });
  hideSpotlightPanel();
}
function hideSpotlightPanel() {
  const panel = document.getElementById('spotlight-panel');
  if (panel) panel.classList.add('hidden');
}
function focusSpotlight(index, fly = true) {
  const item = CITY_SPOTLIGHTS[((index % CITY_SPOTLIGHTS.length) + CITY_SPOTLIGHTS.length) % CITY_SPOTLIGHTS.length];
  if (!item) return;
  if (map.getLayer('spotlight-active-area')) map.setFilter('spotlight-active-area', ['==', ['get', 'id'], item.id]);
  if (map.getLayer('spotlight-active-outline')) map.setFilter('spotlight-active-outline', ['==', ['get', 'id'], item.id]);
  if (fly) {
    moveCamera({
      center: item.center,
      zoom: item.zoom,
      pitch: item.pitch,
      bearing: item.bearing,
    }, 2300);
  }
  const panel = document.getElementById('spotlight-panel');
  if (!panel) return;
  const img = document.getElementById('spotlight-img');
  img.onerror = () => {
    img.onerror = null;
    img.src = 'assets/hero_during.jpg';
  };
  img.src = item.image;
  img.alt = `${item.title} documentary image`;
  document.getElementById('spotlight-counter').textContent = `Scene ${CITY_SPOTLIGHTS.indexOf(item) + 1} of ${CITY_SPOTLIGHTS.length}`;
  document.getElementById('spotlight-kicker').textContent = item.kicker;
  document.getElementById('spotlight-title').textContent = item.title;
  document.getElementById('spotlight-scene').textContent = item.scene;
  document.getElementById('spotlight-losses').innerHTML = item.losses.map(loss => `<span>${loss}</span>`).join('');
  document.getElementById('spotlight-copy').textContent = item.copy;
  document.getElementById('spotlight-facts').innerHTML = item.facts.map(f => `<span>${f}</span>`).join('');
  document.getElementById('spotlight-credit').textContent = item.credit;
  panel.classList.remove('hidden');
}
function hideMicroScene() {
  setPaint('micro-farms', { 'fill-opacity': 0 });
  setPaint('micro-farms-outline', { 'line-opacity': 0 });
  setPaint('micro-flood-fill', { 'fill-opacity': 0 });
  if (map.getLayer('micro-road')) setPaint('micro-road', { 'line-opacity': 0, 'line-width': 0 });
  if (map.getLayer('micro-houses')) setPaint('micro-houses', { 'fill-extrusion-opacity': 0 });
  if (map.getLayer('micro-flood-extrude')) setPaint('micro-flood-extrude', { 'fill-extrusion-opacity': 0 });
  setPaint('micro-labels', { 'text-opacity': 0 });
  const src = map.getSource('micro_flood');
  if (src) src.setData({ type: 'FeatureCollection', features: [] });
  const callout = document.getElementById('micro-callout');
  if (callout) callout.classList.add('hidden');
}
function setMicroFloodStage(i) {
  const stage = MICRO_FLOOD_STAGES[i % MICRO_FLOOD_STAGES.length];
  const floodSource = map.getSource('micro_flood');
  if (floodSource) {
    const features = stage.height > 0 ? [
      polygonFeature(stage.coords, { height: stage.height, label: stage.label }),
    ] : [];
    floodSource.setData({ type: 'FeatureCollection', features });
  }
  setPaint('micro-farms', {
    'fill-opacity': 0.76,
    'fill-color': ['case', ['<=', ['get', 'hit_stage'], stage.impact], '#8E9F73', '#D6B36B'],
  });
  setPaint('micro-farms-outline', { 'line-opacity': 0.7 });
  setPaint('micro-road', {
    'line-width': 4,
    'line-opacity': 1,
    'line-color': ['case', ['<=', ['get', 'hit_stage'], stage.impact], C.alert, '#65584B'],
  });
  setPaint('micro-houses', {
    'fill-extrusion-opacity': 0.94,
    'fill-extrusion-color': ['case', ['<=', ['get', 'hit_stage'], stage.impact], '#B84A3A', '#D6C8B5'],
  });
  setPaint('micro-flood-fill', { 'fill-opacity': stage.height > 0 ? 0.45 : 0 });
  setPaint('micro-flood-extrude', { 'fill-extrusion-opacity': stage.height > 0 ? 0.72 : 0 });
  setPaint('micro-labels', { 'text-opacity': 1 });
  const callout = document.getElementById('micro-callout');
  if (callout) {
    callout.classList.remove('hidden');
    document.getElementById('micro-title').textContent = stage.label;
    document.getElementById('micro-body').textContent = stage.body;
  }
  legend([
    ['#D6C8B5', 'Homes / school / clinic'],
    ['#D6B36B', 'Farm plots'],
    [C.alert, 'Affected at current stage'],
    [C.water, 'Rising floodwater'],
  ], 'Conceptual close-up - Dadu-Manchar floodplain');
}
function highlightEcosystems(names) {
  if (!GEO.ecosystems) return;
  GEO.ecosystems.features.forEach((f, i) => {
    const on = names.includes(f.properties.name);
    map.setFeatureState(
      { source: 'ecosystems', id: i },
      { highlight: on }
    );
  });
}
function clearEcosystems() { highlightEcosystems([]); }
// Promise-based delay
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function stopEcoTour() {
  if (ecoSubTimer) { clearTimeout(ecoSubTimer); ecoSubTimer = null; }
}

/* ─── WEEKLY SCRUBBER ─────────────────────────────────────── */
const WEEKS = ['w1','w2','w3','w4','w5','w6'];
const WEEK_LABELS = {
  w1: 'Jul 12 – 21', w2: 'Aug 3 – 23', w3: 'Aug 25 – 31',
  w4: 'Sep 1 – 7',  w5: 'Sep 8 – 14', w6: 'Sep 15 – 21',
};
function showScrubber(show) {
  document.getElementById('scrubber').classList.toggle('hidden', !show);
}

/* ─── LAYER PANEL ─────────────────────────────────────────── */
function showLayerPanel(title, items) {
  const p = document.getElementById('layer-panel');
  if (!items || items.length === 0) { p.classList.add('hidden'); return; }
  p.classList.remove('hidden');
  document.getElementById('layer-title').textContent = title;
  document.getElementById('layer-list').innerHTML = items.map((it) => `
    <label class="layer-row">
      <input type="checkbox" data-layer="${it.layerId}" ${it.checked ? 'checked' : ''}/>
      <span class="layer-swatch" style="background:${it.color}"></span>
      <span>${it.label}</span>
    </label>
  `).join('');
  p.querySelectorAll('input[type=checkbox]').forEach(cb => {
    cb.addEventListener('change', () => {
      const id = cb.dataset.layer;
      const op = cb.checked ? 1 : 0;
      setPaint(`${id}-pins`, { 'circle-opacity': op });
      if (map.getLayer(`${id}-labels`)) setPaint(`${id}-labels`, { 'text-opacity': op });
    });
  });
}
function hideLayerPanel() { document.getElementById('layer-panel').classList.add('hidden'); }

/* ─── LEGEND ──────────────────────────────────────────────── */
function legend(rows, title) {
  const el = document.getElementById('map-legend');
  if (!title && (!rows || rows.length === 0)) { el.classList.add('hidden'); el.innerHTML = ''; return; }
  el.classList.remove('hidden');
  el.innerHTML = (title ? `<div class="legend-title">${title}</div>` : '') +
    (rows || []).map(([c, t]) =>
      `<div class="legend-row"><span class="swatch" style="background:${c}"></span><span>${t}</span></div>`
    ).join('');
}
function resetMapState() {
  clearTimeout(cameraSettleTimer);
  cameraSettleTimer = null;
  clearEcosystems();
  hideAllFloods();
  hideAllPins();
  hideDistricts();
  showScrubber(false);
  hideLayerPanel();
  legend([], '');
  setPaint('cities-pins', { 'circle-radius': 6 });
  setPaint('landmarks-pins', { 'circle-radius': 5 });
  setPaint('preflood-pins', { 'circle-radius': 7 });
}

/* ─── CHAPTER STATE MACHINE (19 chapters across 5 sections) ─ */
// helper — guarantee terrain ON for chapters that need true 3D
const STEP_ORDER = [1,2,3,4,5,6,7,8,8.5,9,10,10.5,11,12,13,14,15,16,17,18,19];
function updateProgress(n) {
  const idx = Math.max(0, STEP_ORDER.indexOf(n));
  const pct = ((idx + 1) / STEP_ORDER.length) * 100;
  const meta = n <= 4 ? ['Chapter 1 of 6', 'Region']
    : n <= 7 ? ['Chapter 2 of 6', 'Pressure before rain']
    : n <= 9 ? ['Chapter 3 of 6', 'Flood arrives']
    : n <= 13 ? ['Chapter 4 of 6', 'Who and what was hit']
    : n <= 16 ? ['Chapter 5 of 6', 'Relief and response']
    : ['Chapter 6 of 6', 'Recovery now'];
  const kicker = document.getElementById('progress-kicker');
  const step = document.getElementById('progress-step');
  const title = document.getElementById('progress-title');
  const fill = document.getElementById('progress-fill');
  if (!kicker || !step || !title || !fill) return;
  kicker.textContent = meta[0];
  step.textContent = `${idx + 1}/${STEP_ORDER.length}`;
  title.textContent = meta[1];
  fill.style.width = `${pct}%`;
}

function ensureTerrain(exag = 1.5) {
  if (!terrainOn) {
    map.setTerrain({ source: 'terrain-dem', exaggeration: exag });
    terrainOn = true;
    document.getElementById('btn-toggle-3d').classList.add('active');
  } else {
    // re-apply in case style was reloaded
    map.setTerrain({ source: 'terrain-dem', exaggeration: exag });
  }
}
const CHAPTERS = {
  // ─── SECTION 1: Pakistan ───
  1: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [69.5, 30.5], zoom: 4.5, pitch: terrainOn ? 55 : 0 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts();
    setImagery(true);
    showIndusRoute(true);
    setPaint('cities-pins', { 'circle-opacity': 1, 'circle-radius': 8 });
    setPaint('cities-labels', { 'text-opacity': 1 });
    showScrubber(false); hideLayerPanel();
    legend([
      [C.waterDeep, 'Indus story route - mountains to Sindh'],
      [C.city, 'Major cities - click for role'],
    ], 'Pakistan - follow the water');
  },
  2: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [70.5, 30.5], zoom: 5.0, pitch: terrainOn ? 50 : 0 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts();
    setImagery(true);
    showIndusRoute(true);
    setPaint('cities-pins', { 'circle-opacity': 1, 'circle-radius': 8 });
    setPaint('cities-labels', { 'text-opacity': 1 });
    legend([
      [C.waterDeep, 'Water corridor that shapes settlement'],
      [C.city, 'Cities by metro population'],
    ], '251 million people');
  },
  3: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [71.5, 30.5], zoom: 5.0, pitch: 52 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts();
    setImagery(true);
    showIndusRoute(true);
    setPaint('cities-pins', { 'circle-opacity': 1, 'circle-radius': 8 });
    setPaint('cities-labels', { 'text-opacity': 1 });
    legend([
      [C.waterDeep, 'Indus route behind the economy'],
      [C.city, 'Industrial + agricultural cities'],
    ], 'Where the work happens');
  },
  4: () => {
    stopEcoTour();
    // Sweep from Karakoram to delta — dramatic terrain reveal
    moveCamera({ center: [73.5, 33], zoom: 5.2, pitch: 66 }, 1800);
    if (!terrainOn) {
      // auto-enable terrain here so the geography point lands
      map.setTerrain({ source: 'terrain-dem', exaggeration: 1.5 });
      terrainOn = true;
      document.getElementById('btn-toggle-3d').classList.add('active');
    }
    hideAllFloods(); hideAllPins(); hideDistricts();
    showIndusRoute(true);
    setPaint('cities-pins', { 'circle-opacity': 0.75, 'circle-radius': 7 });
    setPaint('landmarks-pins', { 'circle-opacity': 1, 'circle-radius': 9 });
    highlightEcosystems(['Karakoram glacier zone', 'Indus delta mangroves']);
    legend([
      [C.waterDeep, 'Indus route - mountains to delta'],
      [C.city, 'Major cities'],
      [C.alert, 'Geography landmarks'],
      [C.ecoLine, 'Glacier and delta focus zones'],
    ], 'The terrain that matters');
  },

  // ─── SECTION 2: The disaster ───
  5: () => {
    // ── NEW: Pre-flood timeline — auto-tour through events
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [70, 30], zoom: 4.3, pitch: 0, bearing: 0 }, 1800);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('preflood-pins', { 'circle-opacity': 1 });
    legend([
      [C.alert, 'Structural / governance fragility (pre-existing)'],
      [C.water, 'Climate triggers (2022-specific)'],
    ], 'Pre-flood — the stage was already set');
    // Auto-tour through the 5 most important pre-flood event locations
    const tour = [
      { name: 'Tarbela + Mangla dams — silted',
        center: [73.0, 33.99], zoom: 7.0, pitch: 50 },
      { name: 'Climate Change Authority — chronically underfunded',
        center: [73.05, 33.68], zoom: 8.0, pitch: 30 },
      { name: 'Karakoram anomaly reversal',
        center: [76.0, 35.5], zoom: 6.5, pitch: 55 },
      { name: 'Shisper Glacier outburst (GLOF)',
        center: [74.65, 36.32], zoom: 8.5, pitch: 60 },
      { name: 'March–May 2022 heatwave',
        center: [68.45, 28.28], zoom: 7.0, pitch: 30 },
      { name: 'Sukkur Barrage — 1930s design limit',
        center: [68.84, 27.69], zoom: 8.0, pitch: 50 },
    ];
    let i = 0;
    const step = () => {
      if (currentChapter !== 5) return;
      if (tour[i].pitch >= 45) ensureTerrain(1.5);
      const t = tour[i % tour.length];
      moveCamera({ center: t.center, zoom: t.zoom, pitch: t.pitch }, 2400);
      legend([
        [C.alert, 'Structural fragility'],
        [C.water, 'Climate triggers'],
        ['#888', `Now showing: ${t.name}`],
      ], 'Pre-flood — auto-touring the contributing events');
      i++;
      ecoSubTimer = setTimeout(step, 5500);
    };
    step();
  },
  6: () => {
    stopEcoTour();
    // Fly all the way to Hunza/Shisper — high Karakoram (was chapter 5)
    moveCamera({ center: [74.65, 36.32], zoom: 8.5, pitch: 72, bearing: 15 }, 2200);
    ensureTerrain(1.9);
    hideAllFloods(); hideAllPins(); hideDistricts();
    setPaint('landmarks-pins', { 'circle-opacity': 1, 'circle-radius': 10 });
    highlightEcosystems(['Karakoram glacier zone']);
    legend([
      [C.alert, 'Shisper Glacier + Hassanabad Bridge'],
      [C.ecoLine, 'Karakoram glacier zone'],
    ], 'May 7 2022 — the GLOF that bookended the disaster');
  },
  7: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [69.5, 30.5], zoom: 4.6, pitch: 48 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts();
    legend([], '190% of normal rainfall, nationally');
  },
  8: () => {
    // 3D FLOOD SIMULATION — terrain on, max tilt, dramatic water columns, auto-play
    stopEcoTour(); clearEcosystems();
    ensureTerrain(1.8);   // force terrain ON with strong exaggeration
    hideAllFloods(); hideAllPins(); hideDistricts();
    setImagery(true);
    showIndusRoute(false);
    hideLayerPanel();
    // Strong tilt + low altitude flyover of Sindh
    const floodCamera = {
      center: [68.5, 27.0], zoom: 6.5, pitch: 70, bearing: 35,
    };
    moveCamera({
      ...floodCamera,
    }, 2400);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.18 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.35 });
    setPaint('flood-weekly-fill', { 'fill-opacity': 0.35 });
    if (!map.getLayer('flood-weekly-extrude')) {
      map.addLayer({
        id: 'flood-weekly-extrude', type: 'fill-extrusion', source: 'flood_weekly',
        paint: {
          'fill-extrusion-color': C.water,
          // 15 km tall water columns — unmistakable at any tilt/zoom
          'fill-extrusion-height': 15000,
          'fill-extrusion-base': 0,
          'fill-extrusion-opacity': 0.88,
          'fill-extrusion-vertical-gradient': true,
        },
        filter: ['==', 'key', 'w1'],
      });
    } else {
      setPaint('flood-weekly-extrude', { 'fill-extrusion-opacity': 0.88 });
    }
    showScrubber(true);
    legend([[C.water, 'Flood water column (extruded, 15 km)']],
      '3D flood simulation — auto-playing');

    // Auto-play through weeks every 1.8 seconds, with slight bearing drift for cinema
    let idx = 0;
    document.getElementById('scrubber-range').value = 0;
    document.getElementById('scrubber-readout').textContent = WEEK_LABELS.w1;
    const advance = () => {
      if (currentChapter !== 8) return;
      const w = WEEKS[idx];
      map.setFilter('flood-weekly-fill', ['==', 'key', w]);
      if (map.getLayer('flood-weekly-extrude')) {
        map.setFilter('flood-weekly-extrude', ['==', 'key', w]);
      }
      document.getElementById('scrubber-range').value = idx;
      document.getElementById('scrubber-readout').textContent = WEEK_LABELS[w];
      legend([[C.water, `Flood — ${WEEK_LABELS[w]}`]],
        '3D simulation — auto-playing (or drag slider)');
      // camera holds still — let the rising water carry the motion, not the camera
      idx = (idx + 1) % WEEKS.length;
      ecoSubTimer = setTimeout(advance, 1800);
    };
    ecoSubTimer = setTimeout(advance, 2900);
  },
  8.5: () => {
    stopEcoTour(); clearEcosystems();
    ensureTerrain(1.15);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false); hideLayerPanel();
    const microCamera = {
      center: [67.7852, 26.7343],
      zoom: 15.45,
      pitch: 62,
      bearing: -25,
    };
    moveCamera({
      ...microCamera,
    }, 2300);
    setMicroFloodStage(0);
    let idx = 0;
    const advance = () => {
      if (currentChapter !== 8.5) return;
      setMicroFloodStage(idx);
      idx = (idx + 1) % MICRO_FLOOD_STAGES.length;
      // camera holds the framing; the flood stages advance beneath it
      ecoSubTimer = setTimeout(advance, idx === 1 ? 1400 : 2300);
    };
    ecoSubTimer = setTimeout(advance, 2800);
  },
  9: () => {
    stopEcoTour();
    // Zoom into Sukkur Barrage first
    moveCamera({ center: [68.84, 27.69], zoom: 8.2, pitch: terrainOn ? 55 : 30 }, 2200);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.55 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    setPaint('landmarks-pins', { 'circle-opacity': 1 });
    highlightEcosystems(['Manchar Lake']);
    legend([
      [C.water, '2022 flood extent'],
      [C.alert, 'Infrastructure pressure sites (click each)'],
      [C.ecoLine, 'Manchar Lake — the deliberate breach'],
    ], 'Sukkur Barrage → Manchar Lake breach');
    // After 5s, pan to Manchar to show the second failure
    ecoSubTimer = setTimeout(() => {
      if (currentChapter !== 9) return;
      moveCamera({ center: [67.66, 26.42], zoom: 9.5, pitch: terrainOn ? 55 : 30 }, 2400);
    }, 5500);
  },

  // ─── SECTION 3: Demographics + displacement + ECOSYSTEMS ───
  10: () => {
    stopEcoTour();
    moveCamera({ center: [69.5, 29.5], zoom: 5.0, pitch: 42 }, 1400);
    hideAllFloods(); hideAllPins(); showScrubber(false); clearEcosystems();
    setPaint('districts-choropleth', { 'fill-opacity': 0.85 });
    setPaint('districts-line', { 'line-opacity': 0.55 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    legend([
      ['#C9DEEC', '< 500 k'],
      ['#7FB2D8', '0.5M – 1.5M'],
      ['#3F87C1', '1.5M – 3.5M'],
      ['#E89B3C', '3.5M – 6M'],
      ['#C4452E', '> 6M people in flood zone'],
    ], 'Population per division in 2022 flood zone');
  },
  10.5: () => {
    stopEcoTour(); clearEcosystems();
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false); hideLayerPanel();
    setImagery(true);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.32 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    showSpotlightLayers(true);
    legend([
      [C.water, '2022 flood footprint'],
      [C.alert, 'Active affected landscape'],
      [C.waterDeep, 'Upstream-to-downstream story path'],
    ], 'Six human scenes, not points');

    let idx = 0;
    const tour = () => {
      if (currentChapter !== 10.5) return;
      focusSpotlight(idx, true);
      idx = (idx + 1) % CITY_SPOTLIGHTS.length;
      ecoSubTimer = setTimeout(tour, 5600);
    };
    tour();
  },
  11: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [69.5, 29.5], zoom: 5.0, pitch: 42 }, 1400);
    hideAllFloods(); hideAllPins(); showScrubber(false);
    setPaint('districts-choropleth', { 'fill-opacity': 0.85 });
    setPaint('districts-line', { 'line-opacity': 0.55 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.45 });
    legend([['#C4452E', 'Densest child-population districts']], '16 million children lived inside the flooded districts');
  },
  12: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [68.5, 27.5], zoom: 5.6, pitch: 46 }, 1400);
    hideAllFloods(); hideAllPins(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.4 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    setPaint('districts-choropleth', { 'fill-opacity': 0.5 });
    setPaint('districts-line', { 'line-opacity': 0.35 });
    setPaint('landmarks-pins', { 'circle-opacity': 1 });
    legend([
      [C.water, 'Cumulative flood extent'],
      [C.alert, 'Worst-hit displacement districts'],
    ], '7.9M displaced — most stayed in home district');
  },
  13: () => {
    // Ecosystems auto-tour (shifted from chapter 12)
    stopEcoTour();
    moveCamera({ center: [68.5, 26.5], zoom: 6.2, pitch: terrainOn ? 45 : 0 }, 1600);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.3 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.45 });
    setPaint('species-pins',  { 'circle-opacity': 1 });
    setPaint('landmarks-pins',{ 'circle-opacity': 0.7 });
    const tour = [
      { name: 'Indus River dolphin habitat', center: [68.4, 27.0], zoom: 7.2 },
      { name: 'Sindh riverine forests',      center: [68.3, 26.5], zoom: 7.4 },
      { name: 'Manchar Lake',                center: [67.66, 26.42], zoom: 9.0 },
      { name: 'Indus delta mangroves',       center: [67.6, 24.3], zoom: 8.2 },
    ];
    let i = 0;
    const step = () => {
      if (currentChapter !== 13) return;
      const t = tour[i % tour.length];
      highlightEcosystems([t.name]);
      moveCamera({ center: t.center, zoom: t.zoom, pitch: terrainOn ? 50 : 0 }, 2400);
      legend([
        [C.ecoLine, t.name],
        [C.gold, 'Species at risk — click any pin'],
      ], 'Affected ecosystems — auto-touring');
      i++;
      ecoSubTimer = setTimeout(step, 6500);
    };
    step();
  },

  // ─── SECTION 4: Response ───
  14: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [40, 30], zoom: 2.3, pitch: 0 }, 1800);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('international-pins', { 'circle-opacity': 1 });
    setPaint('international-labels', { 'text-opacity': 1 });
    showLayerPanel('Responders', [
      { layerId: 'international', label: 'International (UN, WB, ADB, bilateral)', color: C.international, checked: true },
      { layerId: 'ngos',          label: 'Pakistani NGOs (grassroots)',             color: C.accent,        checked: false },
      { layerId: 'community_responses', label: 'Field response sites',              color: C.response,      checked: false },
    ]);
    legend([
      [C.international, 'International responder HQs — click for $ amounts'],
    ], 'International response — global map view');
  },
  15: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [71, 30], zoom: 5.0, pitch: 48 }, 1600);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.28 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.4 });
    setPaint('ngos-pins',   { 'circle-opacity': 0.35 });
    setPaint('ngos-labels', { 'text-opacity': 0.25 });
    setPaint('community_responses-pins',   { 'circle-opacity': 1 });
    setPaint('community_responses-labels', { 'text-opacity': 1 });
    showLayerPanel('Responders', [
      { layerId: 'international', label: 'International', color: C.international, checked: false },
      { layerId: 'ngos',          label: 'NGO headquarters', color: C.accent,     checked: false },
      { layerId: 'community_responses', label: 'Field response sites', color: C.response, checked: true },
    ]);
    legend([
      [C.response, 'Field response sites — click for needs + verification'],
      [C.accent, 'NGO HQs — institutional base'],
      [C.water, 'Cumulative 2022 flood extent'],
    ], 'Map the Response — communities on the ground');
  },
  16: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [55, 30], zoom: 3.5, pitch: 0 }, 1600);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.25 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.4 });
    setPaint('ngos-pins',          { 'circle-opacity': 1 });
    setPaint('ngos-labels',        { 'text-opacity': 1 });
    setPaint('community_responses-pins',   { 'circle-opacity': 1 });
    setPaint('community_responses-labels', { 'text-opacity': 1 });
    setPaint('international-pins', { 'circle-opacity': 0.6 });
    showLayerPanel('Compare', [
      { layerId: 'international', label: 'International', color: C.international, checked: true },
      { layerId: 'ngos',          label: 'NGO HQs',       color: C.accent,        checked: true },
      { layerId: 'community_responses', label: 'Field response', color: C.response, checked: true },
    ]);
    legend([
      [C.response, 'Grassroots field response — who acted locally'],
      [C.accent, 'Pakistani NGOs — institutional base'],
      [C.international, 'International — who pledged the money'],
    ], 'Pledged vs delivered — the asymmetry');
  },

  // ─── SECTION 5: Recovery + present day ───
  17: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [69, 29], zoom: 5.0, pitch: 46 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false); hideLayerPanel();
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.42 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    setPaint('recovery-pins', { 'circle-opacity': 1 });
    legend([
      [C.water, '2022 flood extent — still the baseline 4 years later'],
      ['#B8860B', 'Recovery sites — click to see numbers'],
    ], 'Recovery gap — Sindh + Balochistan');
  },
  18: () => {
    stopEcoTour(); clearEcosystems();
    moveCamera({ center: [69.5, 30], zoom: 4.8, pitch: 44 }, 1400);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.42 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.55 });
    setPaint('recovery-pins', { 'circle-opacity': 0.85 });
    legend([['#B8860B', 'Where the gap shows up']], 'Why the recovery stalled');
  },
  19: () => {
    stopEcoTour();
    moveCamera({ center: [69.5, 30.5], zoom: 4.4, pitch: 60 }, 1600);
    hideAllFloods(); hideAllPins(); hideDistricts(); showScrubber(false); hideLayerPanel();
    setImagery(true);
    setPaint('flood-cumulative-fill', { 'fill-opacity': 0.48 });
    setPaint('flood-cumulative-line', { 'line-opacity': 0.6 });
    setPaint('community_responses-pins', { 'circle-opacity': 1 });
    setPaint('community_responses-labels', { 'text-opacity': 1 });
    showClosingLandscape();
    highlightEcosystems(['Indus delta mangroves', 'Karakoram glacier zone',
                         'Indus River dolphin habitat', 'Manchar Lake', 'Sindh riverine forests']);
    legend([
      [C.water, 'Flood footprint that remains the baseline'],
      [C.alert, 'Places where the story became lived experience'],
      [C.waterDeep, 'Follow the water - mountain to floodplain'],
    ], 'Closing map - not dots, consequences');
  },
};

function applyChapter(n, force = false) {
  if (!force && currentChapter === n) return;
  stopEcoTour();
  currentChapter = n;
  resetMapState();
  updateProgress(n);
  const handler = CHAPTERS[n];
  if (handler) handler();
}

/* ─── SCROLLAMA ───────────────────────────────────────────── */
const scroller = scrollama();
scroller
  .setup({ step: '.step', offset: 0.55, debug: false })
  .onStepEnter(({ element }) => {
    const n = +element.dataset.step;
    applyChapter(n);
    element.style.opacity = '1';
  })
  .onStepExit(({ element, direction }) => {
    if (direction === 'down') element.style.opacity = '0.55';
  });

function visibleStepNumber() {
  const steps = [...document.querySelectorAll('.step')];
  if (!steps.length) return null;
  const anchor = window.innerHeight * 0.48;
  let best = null;
  let bestDistance = Infinity;
  steps.forEach((step) => {
    const rect = step.getBoundingClientRect();
    const center = rect.top + rect.height * 0.5;
    const inside = rect.top <= anchor && rect.bottom >= anchor;
    const distance = inside ? 0 : Math.abs(center - anchor);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = step;
    }
  });
  return best ? +best.dataset.step : null;
}

let scrollSyncQueued = false;
function queueScrollSync() {
  if (scrollSyncQueued) return;
  scrollSyncQueued = true;
  requestAnimationFrame(() => {
    scrollSyncQueued = false;
    const n = visibleStepNumber();
    if (Number.isFinite(n)) applyChapter(n);
  });
}

function refreshScroller() {
  // Re-fit the MapLibre canvas to its container. Without this, resizing the
  // window (e.g. leaving full-screen) leaves the map at its old dimensions and
  // the story text bleeds over it.
  if (typeof map !== 'undefined' && map && typeof map.resize === 'function') map.resize();
  scroller.resize();
  queueScrollSync();
}

window.addEventListener('scroll', queueScrollSync, { passive: true });
window.addEventListener('resize', refreshScroller);
window.addEventListener('load', () => {
  setTimeout(refreshScroller, 300);
  setTimeout(refreshScroller, 1200);
});
document.querySelectorAll('img, iframe, video').forEach((el) => {
  el.addEventListener('load', refreshScroller, { passive: true });
});

/* ─── CHARTS ──────────────────────────────────────────────── */
Chart.defaults.color = C.inkSoft;
Chart.defaults.borderColor = C.panelLine;
Chart.defaults.font.family = '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif';

fetch(`${DATA}stats.json`).then(r => r.json()).then(stats => {
  drawDistrictsChart(stats.top_districts);
  drawDistrictsTimeChart();
  drawRecoveryChart(stats.headline);
  drawPledgedChart(stats.headline);
});

function drawDistrictsChart(top) {
  const ctx = document.getElementById('chart-districts');
  if (!ctx) return;
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: top.map(d => `${d.name} (${d.province})`),
      datasets: [{
        data: top.map(d => d.pop_in_flood),
        backgroundColor: top.map((_, i) =>
          i < 3 ? C.alert : i < 6 ? '#E89B3C' : C.water),
        borderWidth: 0,
      }],
    },
    options: {
      indexAxis: 'y',
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: (c) => `${c.parsed.x.toLocaleString()} people` } } },
      scales: {
        x: { grid: { color: C.panelLine },
             ticks: { callback: v => (v >= 1e6 ? (v/1e6).toFixed(1)+'M' : (v/1e3).toFixed(0)+'k') } },
        y: { grid: { display: false } },
      },
      animation: { duration: 800 },
    },
  });
}
function drawDistrictsTimeChart() {
  const ctx = document.getElementById('chart-districts-time');
  if (!ctx) return;
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['Mid-Jul', 'End-Aug', '17 Oct', 'End-Oct'],
      datasets: [{
        label: 'Calamity-hit districts', data: [22, 72, 85, 94],
        borderColor: C.alert,
        backgroundColor: 'rgba(196,69,46,0.16)',
        fill: true, tension: 0.35,
        pointBackgroundColor: C.alert, pointRadius: 4,
      }],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: {
        x: { grid: { color: C.panelLine } },
        y: { grid: { color: C.panelLine }, beginAtZero: true },
      },
    },
  });
}
function drawRecoveryChart(h) {
  const ctx = document.getElementById('chart-recovery');
  if (!ctx) return;
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['2,100,000 homes destroyed', '800 climate-resilient rebuilt by 2026'],
      datasets: [{
        data: [h.homes_damaged, h.homes_climate_resilient_rebuilt],
        backgroundColor: [C.alert, C.accent], borderWidth: 0,
      }],
    },
    options: {
      indexAxis: 'y',
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: (c) => `${c.parsed.x.toLocaleString()}` } } },
      scales: {
        x: { type: 'logarithmic', min: 1, grid: { color: C.panelLine },
             ticks: { callback: v => Number(v).toLocaleString() } },
        y: { grid: { display: false } },
      },
    },
  });
}
function drawPledgedChart(h) {
  const ctx = document.getElementById('chart-pledged');
  if (!ctx) return;
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PDNA need', 'Pledged Geneva 2023', 'Disbursed by May 2026'],
      datasets: [{
        data: [h.pdna_need_usd / 1e9, h.pledged_geneva_usd / 1e9, h.disbursed_by_2026_usd / 1e9],
        backgroundColor: ['#E89B3C', C.international, C.accent],
        borderWidth: 0,
      }],
    },
    options: {
      plugins: { legend: { display: false },
        tooltip: { callbacks: { label: (c) => `$${c.parsed.y.toFixed(1)} B` } } },
      scales: {
        y: { grid: { color: C.panelLine }, ticks: { callback: v => `$${v} B` } },
        x: { grid: { display: false } },
      },
    },
  });
}
