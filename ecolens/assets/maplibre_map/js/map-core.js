/* ============================================================
   EcoLens - Map Core Initialization
   Sets up MapLibre GL JS with 3D terrain, sky, hillshade,
   navigation controls, and view state management.
   ============================================================ */

const MapCore = (() => {
    'use strict';

    /** The MapLibre map instance */
    let map = null;

    /** Terrain enabled state */
    let terrainEnabled = true;

    /** Terrain exaggeration factor — 1.8 makes terrain clearly visible */
    const TERRAIN_EXAGGERATION = 1.8;

    /** View state storage key */
    const VIEW_STATE_KEY = 'ecolens_view_state';

    /** Debounce timer for view change events */
    let viewChangeTimer = null;

    // ==========================================================
    //  MAP INITIALIZATION
    // ==========================================================

    /**
     * Initialize the MapLibre map with 3D terrain, sky, and all controls.
     * This is the main entry point called from index.html.
     */
    const init = async () => {
        console.log('[MapCore] Initializing MapLibre GL JS map...');

        // Clear stale view states from older versions
        try { localStorage.removeItem(VIEW_STATE_KEY); } catch (_) {}

        // The default basemap is the bespoke EcoLens Paper style — Liberty
        // re-toned through the design system at runtime. Stock Liberty is
        // the graceful fallback if the style fetch fails.
        let style = 'https://tiles.openfreemap.org/styles/liberty';
        if (window.PaperBasemap) {
            try {
                style = await PaperBasemap.build();
            } catch (e) {
                console.warn('[MapCore] Paper style build failed, using Liberty:', e.message);
            }
        }

        // Open on the reader's own country (IP-derived, no permission
        // prompt, cached for a day). A shared permalink's camera always
        // wins; the Africa/Europe globe is only the last resort.
        let home = null;
        if (!/[#&]c=/.test(location.hash)) {
            try {
                home = JSON.parse(localStorage.getItem('ecolens-home-view') || 'null');
                if (!home || (Date.now() - home.at) > 86400000) {
                    const resp = await fetch('https://ipwho.is/',
                        { signal: AbortSignal.timeout(2500) });
                    const ip = await resp.json();
                    if (ip && ip.success !== false && isFinite(ip.latitude)) {
                        home = { center: [ip.longitude, ip.latitude], at: Date.now() };
                        localStorage.setItem('ecolens-home-view', JSON.stringify(home));
                    }
                }
            } catch (e) { home = null; }
        }

        // Create the map — the reader's country, or the global view
        map = new maplibregl.Map({
            container: 'map',
            style,
            center: (home && home.center) || [10, 25],
            zoom: home ? 4.5 : 2.8,   // country scale vs global overview
            pitch: 50,            // Isometric-style tilt for 3D city feel
            bearing: 0,
            maxPitch: 85,
            antialias: true,
            attributionControl: false,
            hash: false,
            // ?pdb=1 = compatibility capture mode for GPUs where MapCard's
            // render-frame screenshot reads back blank
            preserveDrawingBuffer: /[?&]pdb=1/.test(location.search)
        });

        // Expose globally for bridge and other modules
        window.ecoMap = map;

        // Set up map event handlers
        map.on('load', onMapLoaded);
        map.on('error', onMapError);

        // View change tracking (debounced)
        map.on('moveend', () => debounceViewChange());
        map.on('zoomend', () => debounceViewChange());
        map.on('pitchend', () => debounceViewChange());
        map.on('rotateend', () => debounceViewChange());
    };

    /**
     * Called when the map style has fully loaded.
     * Adds terrain, sky, controls, and initializes hazard layers.
     */
    /**
     * The paper globe: at world zoom the map renders as an actual globe
     * (MapLibre v5 vertical-perspective → globe), which with the warm
     * paper palette and hillshade reads like an engraved library globe.
     * Zooming in transitions seamlessly to the flat map. Guarded — on
     * engines without globe support the map simply stays mercator.
     */
    // Flat mercator by Laurence's call (2026-07-28) — the globe tried and
    // reverted. Kept as an explicit reset so a style that carries a
    // projection can never sneak the sphere back in.
    const applyGlobe = () => {
        try {
            if (map.setProjection) map.setProjection({ type: 'mercator' });
        } catch (e) { /* mercator is the default anyway */ }
    };

    /**
     * Graticule — the fine survey grid of a printed plate. 10° lines in
     * rule-ink, fading out as real geography takes over from zoom 6.
     */
    const addGraticule = () => {
        if (map.getSource('graticule-source')) return;
        const lines = [];
        for (let lon = -180; lon <= 180; lon += 10) {
            const coords = [];
            for (let lat = -85; lat <= 85; lat += 5) coords.push([lon, lat]);
            lines.push({ type: 'Feature', geometry: { type: 'LineString', coordinates: coords } });
        }
        for (let lat = -80; lat <= 80; lat += 10) {
            const coords = [];
            for (let lon = -180; lon <= 180; lon += 5) coords.push([lon, lat]);
            lines.push({ type: 'Feature', geometry: { type: 'LineString', coordinates: coords } });
        }
        map.addSource('graticule-source', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features: lines },
        });
        map.addLayer({
            id: 'graticule-layer',
            type: 'line',
            source: 'graticule-source',
            maxzoom: 7,
            paint: {
                'line-color': '#A89F8A',
                'line-width': 0.6,
                'line-opacity': [
                    'interpolate', ['linear'], ['zoom'],
                    0, 0.28,
                    5, 0.18,
                    7, 0,
                ],
            },
        }, getFirstSymbolLayerId());
    };

    const onMapLoaded = async () => {
        console.log('[MapCore] Map style loaded');

        // --- The paper globe + survey graticule ---
        applyGlobe();
        addGraticule();

        // --- Add 3D Terrain Source (await: hillshade needs the source) ---
        await addTerrainSource();

        // --- Add Sky / Atmosphere Layer ---
        addSkyLayer();

        // --- Add 3D Buildings ---
        add3DBuildings();

        // --- Add Hillshade Layer ---
        addHillshadeLayer();

        // --- Add Navigation Controls ---
        addControls();

        // --- Initialize Hazard Layers ---
        HazardLayers.init(map);

        // --- Initialize Intelligence Layers (weather / response / correlations) ---
        if (window.IntelligenceLayers) {
            window.IntelligenceLayers.init(map);
        }

        // --- Initialize Story Pins (the Places spine: investigations on the map) ---
        if (window.StoryPins) {
            window.StoryPins.init(map);
        }

        // --- Initialize Event Simulations ---
        EventSimulations.init(map);

        // --- Initialize In-Map Simulation ---
        InMapSimulation.init(map);

        // --- Initialize Focus Area Analysis ---
        FocusArea.init(map);

        // --- Right-click context menu ---
        map.on('contextmenu', (e) => {
            e.preventDefault();
            showContextMenu(e.lngLat, e.point);
        });

        // --- Simulation click handler ---
        map.on('click', (e) => {
            if (simulationMode && simulationClickMode) {
                if (simulationClickMode === 'fire') {
                    InMapSimulation.startFireSimulation(e.lngLat);
                } else if (simulationClickMode === 'flood') {
                    InMapSimulation.startFloodSimulation(e.lngLat);
                }
                simulationMode = false;
                simulationClickMode = null;
                map.getCanvas().style.cursor = '';
            }
        });

        // --- Load Initial Data ---
        await loadAllHazardData();

        // --- Start Auto-Refresh for Real-Time Data ---
        setupAutoRefresh();

        // --- Remember / Reason / Report modules ---
        // Each init is defensive: a missing/offline dependency degrades to a
        // hidden feature, never a broken map.
        const lateInit = (name) => {
            try {
                if (window[name] && typeof window[name].init === 'function') {
                    window[name].init();
                }
            } catch (e) {
                console.warn('[MapCore] ' + name + '.init failed:', e);
            }
        };
        ['ChromeShell', 'HistoryArchive', 'Permalink', 'MapCard', 'AskTheMap',
         'TimePlayback', 'SwipeCompare', 'AnomalyDesk', 'Bivariate', 'AtlasBridge',
         'MapAnnotations'].forEach(lateInit);
        const cmpBtn = document.getElementById('fires-compare-btn');
        if (cmpBtn && window.SwipeCompare) {
            cmpBtn.addEventListener('click', () => window.SwipeCompare.compareFiresWithLastWeek());
        }

        // --- Hide Loading Overlay ---
        const overlay = document.getElementById('loading-overlay');
        if (overlay) {
            overlay.classList.add('hidden');
        }

        // --- Notify Flutter ---
        if (window.EcoLensBridge) {
            window.EcoLensBridge.sendToFlutter('mapReady', {
                center: map.getCenter().toArray(),
                zoom: map.getZoom(),
                pitch: map.getPitch(),
                bearing: map.getBearing()
            });
        }

        console.log('[MapCore] Map fully initialized and ready');
    };

    /**
     * Handle map errors gracefully.
     */
    const onMapError = (e) => {
        console.error('[MapCore] Map error:', e.error || e);
        if (window.EcoLensBridge) {
            window.EcoLensBridge.sendToFlutter('error', {
                message: e.error?.message || 'Map error',
                type: 'map_error'
            });
        }
    };

    // ==========================================================
    //  3D TERRAIN
    // ==========================================================

    /**
     * Add the terrain raster-DEM source and enable 3D terrain.
     */
    // Real global elevation: AWS Open Data Terrain Tiles (Terrarium
    // encoding, keyless, z0-15 worldwide). The MapLibre demo tiles used
    // before are world-scale only — they render essentially flat, which
    // is why hillshade never showed. AWS is CORS-probed once because
    // some WebView contexts have blocked it; the demo tileset stays as
    // the fallback so terrain never hard-fails.
    const TERRAIN_TILESETS = {
        terrarium: {
            type: 'raster-dem',
            tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],
            encoding: 'terrarium',
            tileSize: 256,
            maxzoom: 15,
            attribution: 'Terrain: Mapzen/AWS Open Data',
        },
        demo: {
            type: 'raster-dem',
            url: 'https://demotiles.maplibre.org/terrain-tiles/tiles.json',
            tileSize: 256,
        },
    };
    const terrariumProbe = fetch(
        'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/2/1/1.png',
        { mode: 'cors' }
    ).then(r => r.ok).catch(() => false);

    const addTerrainSource = async () => {
        if (!map.getSource('terrain-source')) {
            const useTerrarium = await terrariumProbe;
            if (map.getSource('terrain-source')) return; // raced by a second call
            map.addSource('terrain-source',
                TERRAIN_TILESETS[useTerrarium ? 'terrarium' : 'demo']);
            console.log('[MapCore] Terrain DEM: ' + (useTerrarium ? 'AWS Terrarium (global z15)' : 'demo tiles (fallback)'));
        }

        // Enable terrain with exaggeration
        map.setTerrain({
            source: 'terrain-source',
            exaggeration: TERRAIN_EXAGGERATION
        });

        terrainEnabled = true;
        console.log('[MapCore] 3D terrain enabled (exaggeration: ' + TERRAIN_EXAGGERATION + ')');
    };

    /**
     * Toggle 3D terrain on/off.
     * @returns {boolean} New terrain state
     */
    const toggleTerrain = () => {
        if (terrainEnabled) {
            map.setTerrain(null);
            terrainEnabled = false;
        } else {
            map.setTerrain({
                source: 'terrain-source',
                exaggeration: TERRAIN_EXAGGERATION
            });
            terrainEnabled = true;
        }
        console.log(`[MapCore] Terrain ${terrainEnabled ? 'enabled' : 'disabled'}`);
        return terrainEnabled;
    };

    // ==========================================================
    //  SKY & ATMOSPHERE
    // ==========================================================

    /**
     * Add a sky/atmosphere layer for realistic 3D appearance.
     */
    const addSkyLayer = () => {
        if (map.getLayer('sky-layer')) return;

        map.addLayer({
            id: 'sky-layer',
            type: 'sky',
            paint: {
                'sky-type': 'atmosphere',
                'sky-atmosphere-sun': [210.0, 55.0],       // afternoon sun — warm directional light
                'sky-atmosphere-sun-intensity': 6,
                // Atmosphere in the paper palette — a pale survey-blue wash
                // with a warm paper halo, not a video-game blue sky
                'sky-atmosphere-color': 'rgba(176, 196, 202, 0.65)',
                'sky-atmosphere-halo-color': 'rgba(242, 239, 228, 0.55)',
                'sky-gradient-center': [0, 0],
                'sky-gradient-radius': 90,
                'sky-opacity': [
                    'interpolate', ['linear'], ['zoom'],
                    0, 1,
                    12, 0.6,
                    22, 0.1
                ]
            }
        });

        console.log('[MapCore] Sky/atmosphere layer added');
    };

    // ==========================================================
    //  3D BUILDINGS
    // ==========================================================

    /**
     * Add realistic 3D building extrusion layers — isometric city style.
     * Uses fine-grained height steps to cycle colors, creating visual variety.
     */
    function add3DBuildings() {
        const style = map.getStyle();
        if (!style) return;

        // Find the basemap's vector tile source (OpenMapTiles)
        const sources = style.sources || {};
        let vectorSource = null;
        for (const [name, src] of Object.entries(sources)) {
            if (src.type === 'vector') { vectorSource = name; break; }
        }

        if (!vectorSource) {
            console.warn('[MapCore] No vector source found for 3D buildings');
            return;
        }

        const labelLayerId = getFirstSymbolLayerIdFrom(style);

        // ── Main 3D buildings layer ──
        // Color cycles through 8 tones every 1m of height, creating
        // natural variety even among similar-height buildings.
        map.addLayer({
            id: '3d-buildings',
            source: vectorSource,
            'source-layer': 'building',
            type: 'fill-extrusion',
            minzoom: 13,
            filter: ['!=', ['get', 'hide_3d'], true],
            paint: {
                'fill-extrusion-color': [
                    'case',
                    ['has', 'colour'], ['get', 'colour'],
                    // Fine-grained height steps — cycles palette every ~8m
                    ['step',
                        ['coalesce', ['get', 'render_height'], 5],
                        '#F0E8DA',     // 0: warm white
                        1, '#E2D4B8',  // 1: light sand
                        2, '#D4BFA0',  // 2: sandstone
                        3, '#C9A882',  // 3: tan
                        4, '#C4956A',  // 4: terracotta
                        5, '#B87A5A',  // 5: warm brick
                        6, '#A86050',  // 6: brick red
                        7, '#BCC8B0',  // 7: sage green
                        8, '#E8DDD0',  // 8: cream (restart warm)
                        9, '#DDD0B8',  // 9: light sandstone
                        10, '#D0C0A0', // 10: golden sand
                        11, '#C09570', // 11: copper
                        12, '#B08060', // 12: clay
                        13, '#A8B8A0', // 13: olive
                        14, '#D0C8C0', // 14: light concrete
                        15, '#C0B8B0', // 15: warm gray
                        16, '#F2EDE4', // 16: white (restart)
                        17, '#E0D0B8', // 17: buff
                        18, '#D8C098', // 18: wheat
                        19, '#C8A878', // 19: amber
                        20, '#B89068', // 20: sienna
                        22, '#C8C0B8', // 22: concrete
                        24, '#B8B0A8', // 24: warm concrete
                        26, '#A8B0B8', // 26: cool concrete
                        28, '#98A8B0', // 28: steel-concrete
                        30, '#B0B8C0', // 30: blue-gray
                        35, '#A0A8B8', // 35: steel
                        40, '#98A0B0', // 40: steel blue
                        50, '#8898A8', // 50: dark steel
                        60, '#7888A0', // 60: blue glass
                        80, '#6878A0', // 80: deep glass
                        100, '#5868A0',// 100: tower glass
                        150, '#4858A0' // 150+: dark tower
                    ]
                ],
                'fill-extrusion-height': [
                    'interpolate', ['linear'], ['zoom'],
                    13, 0,
                    14, ['coalesce', ['get', 'render_height'], 5]
                ],
                'fill-extrusion-base': [
                    'case',
                    ['>=', ['zoom'], 15],
                    ['coalesce', ['get', 'render_min_height'], 0],
                    0
                ],
                'fill-extrusion-opacity': [
                    'interpolate', ['linear'], ['zoom'],
                    13, 0.3,
                    14, 0.85,
                    15, 0.95,
                    17, 1.0
                ],
                'fill-extrusion-vertical-gradient': true
            }
        }, labelLayerId);

        console.log('[MapCore] 3D buildings added with varied city colors');

        // Debug: log building properties on first render to verify data
        map.once('idle', () => {
            const features = map.queryRenderedFeatures({ layers: ['3d-buildings'] });
            if (features.length > 0) {
                console.log('[MapCore] Building sample props:', JSON.stringify(features[0].properties));
                console.log('[MapCore] Total visible buildings:', features.length);
            } else {
                console.warn('[MapCore] No 3d-buildings features rendered — check source/zoom');
            }
        });
    }

    /** Helper: find first symbol layer from a style object */
    function getFirstSymbolLayerIdFrom(style) {
        const layers = style.layers || [];
        for (let i = 0; i < layers.length; i++) {
            if (layers[i].type === 'symbol' && layers[i].layout && layers[i].layout['text-field']) {
                return layers[i].id;
            }
        }
        return undefined;
    }

    // ==========================================================
    //  HILLSHADE
    // ==========================================================

    /**
     * Add a hillshade layer for terrain visualization.
     */
    const addHillshadeLayer = () => {
        if (map.getLayer('hillshade-layer')) return;

        // Use the terrain DEM source for hillshade too
        // Relief in the paper palette: warm ink shadows, page-white light —
        // an engraved plate, not a blue-gray web overlay.
        map.addLayer({
            id: 'hillshade-layer',
            type: 'hillshade',
            source: 'terrain-source',
            paint: {
                'hillshade-illumination-direction': 335,
                'hillshade-exaggeration': [
                    'interpolate', ['linear'], ['zoom'],
                    3, 0.30,
                    8, 0.45,
                    13, 0.25,
                ],
                'hillshade-shadow-color': 'rgba(87, 80, 63, 0.55)',
                'hillshade-highlight-color': 'rgba(251, 249, 241, 0.55)',
                'hillshade-accent-color': 'rgba(35, 32, 25, 0.12)'
            }
        }, getFirstSymbolLayerId()); // Insert below labels
    };

    /**
     * Find the first symbol layer ID in the style to insert layers below labels.
     * @returns {string|undefined}
     */
    const getFirstSymbolLayerId = () => {
        const layers = map.getStyle().layers || [];
        for (const layer of layers) {
            if (layer.type === 'symbol') {
                return layer.id;
            }
        }
        return undefined;
    };

    // ==========================================================
    //  CONTROLS
    // ==========================================================

    /**
     * Add all map controls: navigation, scale, terrain toggle.
     */
    const addControls = () => {
        // Navigation control (zoom, pitch, compass)
        map.addControl(
            new maplibregl.NavigationControl({
                visualizePitch: true,
                showCompass: true,
                showZoom: true
            }),
            'top-right'
        );

        // Scale bar
        map.addControl(
            new maplibregl.ScaleControl({
                maxWidth: 150,
                unit: 'metric'
            }),
            'bottom-left'
        );

        // Terrain toggle (custom control)
        map.addControl(new TerrainToggleControl(), 'top-right');

        // Fullscreen control
        map.addControl(new maplibregl.FullscreenControl(), 'top-right');

        // Geolocate control
        map.addControl(
            new maplibregl.GeolocateControl({
                positionOptions: { enableHighAccuracy: true },
                trackUserLocation: false,
                showUserHeading: true
            }),
            'top-right'
        );

        console.log('[MapCore] Controls added');
    };

    /**
     * Custom Terrain Toggle Control for MapLibre.
     */
    class TerrainToggleControl {
        onAdd(mapInstance) {
            this._map = mapInstance;
            this._container = document.createElement('div');
            this._container.className = 'maplibregl-ctrl terrain-toggle-ctrl';

            const btn = document.createElement('button');
            btn.className = 'terrain-toggle-btn active';
            btn.title = 'Toggle 3D Terrain';
            btn.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M2 20L8 10L14 16L18 12L22 20Z"/>
                <path d="M7 4L9 6L7 8" opacity="0.5"/>
            </svg>`;

            btn.addEventListener('click', () => {
                const enabled = toggleTerrain();
                btn.classList.toggle('active', enabled);
                if (window.EcoLensBridge) {
                    window.EcoLensBridge.showToast(
                        `3D Terrain ${enabled ? 'enabled' : 'disabled'}`,
                        'info',
                        2000
                    );
                }
            });

            this._container.appendChild(btn);
            return this._container;
        }

        onRemove() {
            this._container.parentNode.removeChild(this._container);
            this._map = undefined;
        }
    }

    // ==========================================================
    //  GEOCODER / SEARCH
    // ==========================================================

    /**
     * Geocode a location query using Nominatim (OpenStreetMap).
     * @param {string} query - Search text
     * @returns {Promise<Array>} Array of result objects
     */
    const geocode = async (query) => {
        if (!query || query.trim().length < 2) return [];

        try {
            const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=5&addressdetails=1`;
            const response = await fetch(url, {
                headers: { 'Accept': 'application/json' }
            });
            const results = await response.json();

            return results.map(r => ({
                name: r.display_name,
                lat: parseFloat(r.lat),
                lng: parseFloat(r.lon),
                bbox: r.boundingbox
                    ? [parseFloat(r.boundingbox[2]), parseFloat(r.boundingbox[0]),
                       parseFloat(r.boundingbox[3]), parseFloat(r.boundingbox[1])]
                    : null,
                type: r.type || r.class,
                cls: r.class,
                // Nominatim's own relevance signal — callers can rank with it
                importance: typeof r.importance === 'number' ? r.importance : 0
            }));
        } catch (err) {
            console.warn('[MapCore] Geocode error:', err.message);
            return [];
        }
    };

    /**
     * Fly to a geocode result.
     * @param {object} result - { name, lat, lng, bbox }
     */
    const flyToResult = (result) => {
        if (!map || !result) return;

        if (result.bbox) {
            map.fitBounds(
                [[result.bbox[0], result.bbox[1]], [result.bbox[2], result.bbox[3]]],
                { padding: 60, maxZoom: 14, duration: 2500 }
            );
        } else {
            map.flyTo({
                center: [result.lng, result.lat],
                zoom: 15.5,
                pitch: 60,
                bearing: -20,
                duration: 2500
            });
        }
    };

    // ==========================================================
    //  BASEMAP SWITCHING
    // ==========================================================

    /**
     * Switch the map basemap style.
     * Preserves all hazard layers and data across the style change.
     *
     * @param {string} styleName - 'liberty', 'bright', 'positron', 'satellite'
     */
    const switchBasemap = async (styleName) => {
        if (!map) return;

        const styleUrls = {
            liberty: 'https://tiles.openfreemap.org/styles/liberty',
            bright: 'https://tiles.openfreemap.org/styles/bright',
            positron: 'https://tiles.openfreemap.org/styles/positron',
            satellite: null // Handled separately
        };

        // Save current data from all hazard sources
        const savedData = {};
        Object.entries(HazardLayers.LAYER_DEFS).forEach(([type, def]) => {
            const source = map.getSource(def.sourceId);
            if (source && source._data) {
                savedData[type] = source._data;
            }
        });

        // Save camera state
        const camera = {
            center: map.getCenter(),
            zoom: map.getZoom(),
            pitch: map.getPitch(),
            bearing: map.getBearing()
        };

        if (styleName === 'liberty' && window.PaperBasemap) {
            // "liberty" is the EcoLens Paper style (Liberty re-toned);
            // fall back to stock Liberty only if the build fails.
            try {
                map.setStyle(await PaperBasemap.build());
            } catch (e) {
                map.setStyle(styleUrls.liberty);
            }
        } else if (styleName === 'satellite') {
            // Build a satellite-like style using ESRI World Imagery
            const satStyle = {
                version: 8,
                name: 'satellite',
                sources: {
                    'satellite-tiles': {
                        type: 'raster',
                        tiles: [
                            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        ],
                        tileSize: 256,
                        maxzoom: 18
                    }
                },
                layers: [
                    {
                        id: 'satellite-layer',
                        type: 'raster',
                        source: 'satellite-tiles',
                        paint: {
                            'raster-opacity': 1
                        }
                    }
                ],
                glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf'
            };
            map.setStyle(satStyle);
        } else {
            const url = styleUrls[styleName];
            if (url) {
                map.setStyle(url);
            }
        }

        // After style loads, re-add terrain, sky, hillshade, and hazard layers
        map.once('style.load', async () => {
            // Restore camera
            map.jumpTo(camera);

            // Re-assert globe + graticule (style swaps reset both)
            applyGlobe();
            addGraticule();

            // Re-add terrain (await: hillshade needs the source)
            await addTerrainSource();
            addSkyLayer();
            add3DBuildings();
            addHillshadeLayer();

            // Re-initialize hazard layers
            HazardLayers.init(map);

            // Restore saved data
            Object.entries(savedData).forEach(([type, data]) => {
                if (data) {
                    HazardLayers.updateSource(type, data);
                }
            });

            // Rebuild the intelligence overlays too. setStyle() wipes
            // every source and layer, and only the impacts layer is ever
            // fetched once — without this rehydrate a basemap switch
            // silently emptied 'Who is affected' and 'Areas affected'
            // for the rest of the session while their pills stayed on
            // and their counts kept showing the pre-switch numbers.
            if (window.IntelligenceLayers?.rehydrate) {
                try {
                    window.IntelligenceLayers.rehydrate(map);
                } catch (err) {
                    console.warn('[MapCore] IntelligenceLayers.rehydrate failed:', err.message);
                }
            }

            console.log(`[MapCore] Basemap switched to: ${styleName}`);
        });
    };

    // ==========================================================
    //  VIEW STATE MANAGEMENT
    // ==========================================================

    /**
     * Save current camera position to localStorage.
     */
    const saveViewState = () => {
        if (!map) return;
        try {
            const state = {
                center: map.getCenter().toArray(),
                zoom: map.getZoom(),
                pitch: map.getPitch(),
                bearing: map.getBearing()
            };
            localStorage.setItem(VIEW_STATE_KEY, JSON.stringify(state));
        } catch (e) {
            // localStorage might not be available in WebView
        }
    };

    /**
     * Restore saved camera position from localStorage.
     * @returns {object|null}
     */
    const restoreViewState = () => {
        try {
            const saved = localStorage.getItem(VIEW_STATE_KEY);
            if (saved) {
                return JSON.parse(saved);
            }
        } catch (e) {
            // Ignore
        }
        return null;
    };

    /**
     * Debounced handler for view change events.
     */
    const debounceViewChange = () => {
        clearTimeout(viewChangeTimer);
        viewChangeTimer = setTimeout(() => {
            saveViewState();

            if (window.EcoLensBridge) {
                window.EcoLensBridge.sendToFlutter('viewChanged', {
                    center: map.getCenter().toArray(),
                    zoom: map.getZoom(),
                    pitch: map.getPitch(),
                    bearing: map.getBearing(),
                    bounds: map.getBounds().toArray()
                });
            }
        }, 300);
    };

    // ==========================================================
    //  DATA LOADING
    // ==========================================================

    /**
     * Load all hazard data concurrently and populate map layers.
     */
    const loadAllHazardData = async () => {
        // History mode owns fires-source — live loads must not clobber
        // an archive frame mid-playback (see TimePlayback).
        if (window.EcoLensHistoryMode) {
            console.log('[MapCore] History mode active — skipping live data load');
            return;
        }
        console.log('[MapCore] Loading hazard data...');

        const loadTasks = [
            {
                name: 'fires',
                fetch: () => DataFetchers.fetchActiveFires(),
                update: (data) => HazardLayers.updateSource('fires', data)
            },
            {
                name: 'floods',
                fetch: () => DataFetchers.fetchFloodAlerts(),
                update: (data) => HazardLayers.updateSource('floods', data)
            },
            {
                name: 'drought',
                fetch: () => DataFetchers.fetchDroughtData(),
                update: (data) => HazardLayers.updateSource('drought', data)
            },
            {
                name: 'glaciers',
                fetch: () => DataFetchers.fetchGlacierData(),
                update: (data) => HazardLayers.updateSource('glaciers', data)
            },
            {
                name: 'watershed',
                fetch: () => DataFetchers.fetchWatershedData(),
                update: (data) => HazardLayers.updateSource('watershed', data)
            },
            {
                name: 'earthquakes',
                fetch: () => DataFetchers.fetchEarthquakes(),
                update: (data) => HazardLayers.updateSource('earthquakes', data)
            },
            {
                name: 'airquality',
                fetch: () => DataFetchers.fetchAirQuality(),
                update: (data) => HazardLayers.updateSource('airquality', data)
            },
            {
                name: 'volcanoes',
                fetch: () => DataFetchers.fetchVolcanoes(),
                update: (data) => HazardLayers.updateSource('volcanoes', data)
            }
        ];

        // Track loaded data for risk surface generation
        const allData = {};

        // Hard per-task timeout so a single hanging fetch can't block the diagnostic.
        const withTimeout = (p, ms, label) => Promise.race([
            p,
            new Promise((_, reject) => setTimeout(
                () => reject(new Error(`${label} timeout after ${ms}ms`)), ms)),
        ]);

        const results = await Promise.allSettled(
            loadTasks.map(async (task) => {
                try {
                    const data = await withTimeout(task.fetch(), 35000, task.name);
                    task.update(data);
                    allData[task.name] = data;

                    if (window.EcoLensBridge) {
                        window.EcoLensBridge.sendToFlutter('dataLoaded', {
                            type: task.name,
                            featureCount: data.features ? data.features.length : 0
                        });
                    }

                    const featureCount = data.features ? data.features.length : 0;
                    return { name: task.name, count: featureCount };
                } catch (err) {
                    console.warn(`[MapCore] Failed to load ${task.name}:`, err.message);
                    return { name: task.name, count: 0, error: err.message };
                }
            })
        );

        // Apply default layer visibility — significance ships on by default:
        // at world zoom the first thing a visitor reads is which clusters
        // MEAN something, not just where every detection is.
        const defaultVisible = ['fires', 'hotspots', 'earthquakes'];
        const allHazardLayers = ['fires', 'hotspots', 'bivariate', 'floods', 'drought', 'glaciers', 'ndvi', 'earthquakes', 'airquality', 'volcanoes', 'watershed', 'risk'];
        allHazardLayers.forEach(l => {
            const on = defaultVisible.includes(l);
            HazardLayers.setLayerVisibility(l, on);
            const cb = document.getElementById(`toggle-${l}`);
            if (cb) cb.checked = on;
        });

        // Generate composite risk surface (data only — layer stays hidden)
        const riskData = DataFetchers.generateRiskSurface(allData);
        HazardLayers.updateSource('risk', riskData);
        HazardLayers.setLayerVisibility('risk', false);

        // Ensure the visible hazard layers render ON TOP of the basemap.
        // Order matters: heatmap first (bottom), then points (above).
        const fireLayerIds = ['fires-heatmap', 'fires-points'];
        const quakeLayerIds = ['earthquakes-glow', 'earthquakes-circle', 'earthquakes-labels'];
        [...fireLayerIds, ...quakeLayerIds].forEach(id => {
            if (map.getLayer(id)) {
                try { map.moveLayer(id); } catch (e) { /* no-op */ }
            }
        });

        // (diagnostic overlay removed — issue identified)

        // Defensive: re-apply default visibility after 2s in case a late-loading
        // basemap style reset any layout.visibility properties.
        setTimeout(() => {
            defaultVisible.forEach(l => HazardLayers.setLayerVisibility(l, true));
            console.log('[MapCore] Re-applied default visibility (safety pass).');
        }, 2000);

        console.log('[MapCore] All hazard data loaded');
        results.forEach(r => {
            if (r.status === 'fulfilled') {
                console.log(`  ${r.value.name}: ${r.value.count} features${r.value.error ? ' (error: ' + r.value.error + ')' : ''}`);
            }
        });

        // Kick off intelligence layers AFTER hazard data is loaded so
        // correlations (fire×wind, flood×precip) have a non-empty source to
        // sample from. Runs independently — failures don't block the map.
        if (window.IntelligenceLayers?.loadAll) {
            window.IntelligenceLayers.loadAll().catch(err =>
                console.warn('[MapCore] IntelligenceLayers.loadAll failed:', err.message));
        }
    };

    /**
     * Set up auto-refresh intervals for time-sensitive data.
     */
    const setupAutoRefresh = () => {
        // Fire data: refresh every 5 minutes
        DataFetchers.startAutoRefresh('fires', DataFetchers.fetchActiveFires, 5 * 60 * 1000, (data) => {
            if (window.EcoLensHistoryMode) return; // playback owns fires-source
            HazardLayers.updateSource('fires', data);
            // Check for new high-priority fires
            const highPriority = data.features.filter(f =>
                f.properties.confidence === 'high' && f.properties.frp > 100
            );
            if (highPriority.length > 0 && window.EcoLensBridge) {
                window.EcoLensBridge.sendToFlutter('hazardAlert', {
                    type: 'fire',
                    count: highPriority.length,
                    message: `${highPriority.length} high-intensity fire(s) detected`
                });
            }
        });

        // Flood data: refresh every 15 minutes
        DataFetchers.startAutoRefresh('floods', DataFetchers.fetchFloodAlerts, 15 * 60 * 1000, (data) => {
            HazardLayers.updateSource('floods', data);
            const majorFloods = data.features.filter(f => f.properties.status === 'major');
            if (majorFloods.length > 0 && window.EcoLensBridge) {
                window.EcoLensBridge.sendToFlutter('hazardAlert', {
                    type: 'flood',
                    count: majorFloods.length,
                    message: `${majorFloods.length} major flood alert(s) active`
                });
            }
        });
    };

    // ==========================================================
    //  CONTEXT MENU (Right-Click Simulation Launcher)
    // ==========================================================

    /**
     * Show a context menu at the right-clicked map location.
     * @param {LngLat} lngLat - Coordinates of the click
     * @param {Point} point - Screen coordinates of the click
     */
    function showContextMenu(lngLat, point) {
        // Remove existing menu
        let menu = document.getElementById('ctx-menu');
        if (menu) menu.remove();

        menu = document.createElement('div');
        menu.id = 'ctx-menu';
        menu.className = 'ctx-menu';
        menu.style.left = point.x + 'px';
        menu.style.top = point.y + 'px';

        const bounds = map.getBounds();
        const boundsJson = JSON.stringify({
            south: bounds.getSouth(), north: bounds.getNorth(),
            west: bounds.getWest(), east: bounds.getEast(),
            clickLat: lngLat.lat, clickLon: lngLat.lng
        });

        menu.innerHTML = `
            <div class="ctx-menu-item" onclick="InMapSimulation.startFireSimulation({lat:${lngLat.lat},lng:${lngLat.lng}}); hideContextMenu();">\uD83D\uDD25 Simulate Wildfire Here</div>
            <div class="ctx-menu-item" onclick="InMapSimulation.startFloodSimulation({lat:${lngLat.lat},lng:${lngLat.lng}}); hideContextMenu();">\uD83C\uDF0A Simulate Flood Here</div>
            <div class="ctx-menu-item" onclick="generateRiskMap(${boundsJson.replace(/"/g, '&quot;')}); hideContextMenu();">\uD83D\uDDFA\uFE0F Generate Risk Map</div>
            <div class="ctx-menu-item" onclick="FocusArea.analyzePoint({lat:${lngLat.lat},lng:${lngLat.lng}}); hideContextMenu();">\uD83D\uDCCA Analyze Risk Here</div>
            <div class="ctx-menu-item" onclick="FocusArea.analyzePoint({lat:${lngLat.lat},lng:${lngLat.lng}}); hideContextMenu();">\uD83C\uDFD9\uFE0F Area Intelligence</div>
        `;

        function sendToFlutter(event, data) {
            if (window.EcoLensBridge) {
                window.EcoLensBridge.sendToFlutter(event, data);
            }
            console.log('[MapCore] Sent to Flutter:', event, data);
        }

        function generateRiskMap(boundsData) {
            console.log('[MapCore] Generating risk map for bounds:', boundsData);

            // Show the risk heatmap layer for the visible area
            HazardLayers.setLayerVisibility('risk', true);
            const riskToggle = document.getElementById('toggle-risk');
            if (riskToggle) riskToggle.checked = true;

            // Fly to the clicked area with tilt for 3D effect
            map.flyTo({
                center: [boundsData.clickLon, boundsData.clickLat],
                zoom: Math.max(map.getZoom(), 10),
                pitch: 50,
                duration: 2000,
            });

            // Show a notification
            const note = document.createElement('div');
            note.style.cssText = 'position:fixed;top:80px;left:50%;transform:translateX(-50%);background:rgba(76,175,80,0.9);color:#fff;padding:10px 24px;border-radius:8px;z-index:500;font-family:Inter,sans-serif;font-size:13px;backdrop-filter:blur(8px);';
            note.textContent = 'Risk heatmap generated for visible area';
            document.body.appendChild(note);
            setTimeout(() => note.remove(), 3000);
        }

        document.body.appendChild(menu);

        // Close on click elsewhere
        setTimeout(() => {
            document.addEventListener('click', hideContextMenu, { once: true });
        }, 100);
    }

    /**
     * Hide and remove the context menu.
     */
    function hideContextMenu() {
        const menu = document.getElementById('ctx-menu');
        if (menu) menu.remove();
    }

    // Expose hideContextMenu globally for inline onclick handlers
    window.hideContextMenu = hideContextMenu;

    // Expose openPhotorealistic3D globally
    window.openPhotorealistic3D = function() {
        const center = map.getCenter();
        const zoom = map.getZoom();

        // Open CesiumJS 3D viewer in a full-screen overlay
        let overlay = document.getElementById('cesium-3d-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'cesium-3d-overlay';
            overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:10000;background:#000;';
            document.body.appendChild(overlay);
        }

        const simPath = window.location.href.includes('/assets/')
            ? '../3d_simulations/index.html#lat=' + center.lat + '&lon=' + center.lng + '&zoom=' + zoom
            : '/assets/3d_simulations/index.html#lat=' + center.lat + '&lon=' + center.lng + '&zoom=' + zoom;

        overlay.innerHTML = `
            <iframe src="${simPath}" style="width:100%;height:100%;border:none;" allow="autoplay"></iframe>
            <button onclick="document.getElementById('cesium-3d-overlay').remove();" style="
                position:fixed;top:16px;right:16px;z-index:10001;background:rgba(200,30,30,0.85);
                color:#fff;border:none;padding:10px 20px;border-radius:8px;cursor:pointer;
                font-family:Inter,sans-serif;font-size:13px;font-weight:600;">✕ Exit 3D</button>
        `;

        console.log('[MapCore] Opened photorealistic 3D view at', center.lat.toFixed(4), center.lng.toFixed(4));
    };

    // ==========================================================
    //  SCREENSHOT / EXPORT
    // ==========================================================

    /**
     * Capture the current map view as a PNG data URL.
     * @returns {string|null} Data URL or null
     */
    const captureScreenshot = () => {
        if (!map) return null;
        try {
            return map.getCanvas().toDataURL('image/png');
        } catch (e) {
            console.warn('[MapCore] Screenshot failed:', e.message);
            return null;
        }
    };

    /**
     * Download the map as a PNG image.
     */
    const downloadScreenshot = () => {
        const dataUrl = captureScreenshot();
        if (!dataUrl) {
            if (window.EcoLensBridge) {
                window.EcoLensBridge.showToast('Failed to capture screenshot', 'error');
            }
            return;
        }

        const link = document.createElement('a');
        link.download = `ecolens-map-${new Date().toISOString().slice(0, 10)}.png`;
        link.href = dataUrl;
        link.click();

        if (window.EcoLensBridge) {
            window.EcoLensBridge.showToast('Screenshot saved', 'success', 2000);
        }
    };

    // ==========================================================
    //  Public API
    // ==========================================================

    return {
        init,
        toggleTerrain,
        geocode,
        flyToResult,
        switchBasemap,
        saveViewState,
        captureScreenshot,
        downloadScreenshot,
        loadAllHazardData,
        getMap: () => map
    };
})();

// Global access
window.MapCore = MapCore;

// ==========================================================
//  LAYER SWITCHING & SIMULATION MODE (Global)
// ==========================================================

// Active primary layer
let activePrimaryLayer = 'fires';
let simulationMode = false;
let simulationClickMode = null;

function switchPrimaryLayer(layerName) {
    simulationMode = false;
    activePrimaryLayer = layerName;

    // Hide all layers except the selected one, and sync the sidebar checkboxes
    const allLayers = ['fires', 'hotspots', 'bivariate', 'floods', 'drought', 'glaciers', 'ndvi', 'earthquakes', 'airquality', 'volcanoes', 'watershed', 'risk'];
    allLayers.forEach(l => {
        HazardLayers.setLayerVisibility(l, l === layerName);
        const cb = document.getElementById(`toggle-${l}`);
        if (cb) cb.checked = (l === layerName);
    });

    console.log('[MapCore] Switched primary layer to:', layerName);
}

function enterSimulationMode() {
    simulationMode = true;

    // Hide all hazard layers
    const allLayers = ['fires', 'hotspots', 'bivariate', 'floods', 'drought', 'glaciers', 'ndvi', 'earthquakes', 'airquality', 'volcanoes', 'watershed', 'risk'];
    allLayers.forEach(l => {
        HazardLayers.setLayerVisibility(l, false);
        const cb = document.getElementById(`toggle-${l}`);
        if (cb) cb.checked = false;
    });

    const map = MapCore.getMap();
    if (map) map.getCanvas().style.cursor = 'crosshair';

    showSimTypeSelector();
    console.log('[MapCore] Entered simulation mode');
}

function showSimTypeSelector() {
    let sel = document.getElementById('sim-type-selector');
    if (!sel) {
        sel = document.createElement('div');
        sel.id = 'sim-type-selector';
        sel.style.cssText = 'position:fixed;bottom:70px;left:50%;transform:translateX(-50%);background:rgba(10,10,20,0.95);backdrop-filter:blur(12px);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:12px 16px;z-index:350;display:flex;gap:10px;font-family:Inter,system-ui,sans-serif;';
        sel.innerHTML = `
            <button class="sim-type-btn" style="background:rgba(255,69,0,0.2);border:1px solid rgba(255,69,0,0.4);color:#FF4500;padding:10px 20px;border-radius:8px;cursor:pointer;font-size:13px;font-family:inherit;"
                onclick="simulationClickMode='fire'; document.getElementById('sim-type-selector').remove();">
                \uD83D\uDD25 Click to start wildfire
            </button>
            <button class="sim-type-btn" style="background:rgba(0,180,216,0.2);border:1px solid rgba(0,180,216,0.4);color:#00B4D8;padding:10px 20px;border-radius:8px;cursor:pointer;font-size:13px;font-family:inherit;"
                onclick="simulationClickMode='flood'; document.getElementById('sim-type-selector').remove();">
                \uD83C\uDF0A Click to start flood
            </button>
            <button class="sim-type-btn" style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.2);color:#fff;padding:10px 20px;border-radius:8px;cursor:pointer;font-size:13px;font-family:inherit;"
                onclick="simulationMode=false; document.getElementById('sim-type-selector').remove(); var m=MapCore.getMap(); if(m) m.getCanvas().style.cursor=''; switchPrimaryLayer(activePrimaryLayer);">
                \u2715 Cancel
            </button>
        `;
        document.body.appendChild(sel);
    }
}

// ==========================================================
//  AREA INTELLIGENCE (Global)
// ==========================================================

let areaIntelMode = false;

function toggleAreaIntelMode() {
    areaIntelMode = !areaIntelMode;
    const btn = document.getElementById('area-intel-btn');
    const map = MapCore.getMap();
    if (btn) btn.style.borderColor = areaIntelMode ? '#4CAF50' : 'rgba(255,255,255,0.1)';
    if (map) map.getCanvas().style.cursor = areaIntelMode ? 'crosshair' : '';

    if (areaIntelMode && map) {
        map.once('click', (e) => {
            FocusArea.analyzePoint(e.lngLat);
            areaIntelMode = false;
            if (btn) btn.style.borderColor = 'rgba(255,255,255,0.1)';
            map.getCanvas().style.cursor = '';
        });
    }
}

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    MapCore.init();
});
