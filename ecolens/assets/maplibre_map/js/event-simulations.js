/* ============================================================
   EcoLens - Historical Event Simulation Engine
   Real satellite imagery before/after comparison with swipe
   divider and crossfade timeline animation.
   ============================================================ */

const EventSimulations = (() => {
    'use strict';

    let map = null;
    let currentEvent = null;
    let timelineProgress = 0; // 0-1
    let isPlaying = false;
    let animationFrame = null;
    let playbackSpeed = 1;
    let lastFrameTime = 0;
    let cachedFrames = {};
    let storyUtterance = null;
    let eventOriginMarker = null;

    // ---- Satellite layer IDs ----
    const SRC_BEFORE   = 'sim-before-satellite';
    const SRC_AFTER    = 'sim-after-satellite';
    const SRC_OVERLAY  = 'sim-damage-overlay';
    const SRC_FOCUS    = 'sim-event-focus';
    const LYR_BEFORE   = 'sim-before-layer';
    const LYR_AFTER    = 'sim-after-layer';
    const LYR_OVERLAY  = 'sim-damage-overlay-layer';
    const LYR_FOCUS_FILL = 'sim-event-focus-fill';
    const LYR_FOCUS_LINE = 'sim-event-focus-line';
    const LYR_FOCUS_POINT = 'sim-event-focus-point';
    const LYR_FOCUS_LABEL = 'sim-event-focus-label';

    // ---- Comparison mode ----
    let comparisonMode = 'timeline'; // 'timeline' or 'swipe'
    let swipeDividerPos = 50; // percentage from left
    let isDraggingDivider = false;

    // ---- 3D / cinematic state ----
    let cameraOrbitActive = false;
    let cameraOrbitAngle = 0;
    let savedTerrainExaggeration = 1.8;

    // ==========================================================
    //  EVENT CATALOG -- verified real events
    // ==========================================================

    const EVENT_CATALOG = [
        // ---- WILDFIRES ----
        {
            id: 'camp-fire-2018',
            name: 'Camp Fire, Paradise CA',
            category: 'wildfire',
            description: 'Deadliest California wildfire, destroyed town of Paradise. 85 fatalities, 18,804 structures destroyed.',
            origin: [-121.4370, 39.8102],
            center: [-121.48, 39.80],
            startDate: '2018-11-08',
            endDate: '2018-11-25',
            areaHectares: 62053,
            country: 'United States',
            zoom: 12,
            pitch: 60,
            bearing: -30,
            beforeYear: 2018,
            afterLabel: '2024',
            has3D: true,  // Full Three.js 3D simulation available
            scene3D: 'camp-fire',
            metadata: {
                fatalities: 85,
                structuresDestroyed: 18804,
                cause: 'PG&E electrical transmission line',
                containment: '100%',
                source: 'NIFC / CAL FIRE'
            }
        },
        {
            id: 'black-summer-2019',
            name: 'Australian Black Summer',
            category: 'wildfire',
            description: 'Largest Australian bushfire season on record. Over 3 billion animals affected.',
            origin: [149.85, -36.68],
            center: [149.85, -36.68],
            startDate: '2019-09-06',
            endDate: '2020-03-04',
            areaHectares: 5800000,
            country: 'Australia',
            zoom: 10,
            pitch: 60,
            bearing: 10,
            beforeYear: 2019,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'black-summer-2019',
            metadata: {
                fatalities: 33,
                animalsAffected: '3 billion',
                source: 'NSW Rural Fire Service'
            }
        },
        {
            id: 'maui-lahaina-2023',
            name: 'Maui Lahaina Fire',
            category: 'wildfire',
            description: 'Deadliest US wildfire in over 100 years, destroyed historic Lahaina town.',
            origin: [-156.6825, 20.8783],
            center: [-156.68, 20.88],
            startDate: '2023-08-08',
            endDate: '2023-08-11',
            areaHectares: 890,
            country: 'United States',
            zoom: 14,
            pitch: 60,
            bearing: -45,
            beforeYear: 2021,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'maui-lahaina-2023',
            metadata: {
                fatalities: 101,
                structuresDestroyed: 2207,
                cause: 'Downed power lines, high winds from Hurricane Dora',
                source: 'Maui County / FEMA'
            }
        },
        {
            id: 'canada-wildfires-2023',
            name: 'Canadian Wildfires 2023',
            category: 'wildfire',
            description: 'Record-breaking Canadian wildfire season. Smoke blanketed much of North America.',
            origin: [-115.57, 56.23],
            center: [-115.57, 56.23],
            startDate: '2023-05-01',
            endDate: '2023-10-31',
            areaHectares: 18400000,
            country: 'Canada',
            zoom: 10,
            pitch: 60,
            bearing: 0,
            beforeYear: 2021,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'canada-wildfires-2023',
            metadata: {
                evacuees: 200000,
                firesTotal: 6551,
                source: 'Canadian Interagency Forest Fire Centre'
            }
        },

        // ---- FLOODS ----
        {
            id: 'pakistan-floods-2022',
            name: 'Pakistan Floods 2022',
            category: 'flood',
            description: 'One-third of Pakistan submerged, 33 million people affected. Linked to climate change.',
            origin: [67.99, 27.20],
            center: [68.5, 27.5],
            startDate: '2022-06-14',
            endDate: '2022-10-01',
            areaHectares: 3049200,
            country: 'Pakistan',
            zoom: 10,
            pitch: 60,
            bearing: 15,
            beforeYear: 2021,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'pakistan-floods-2022',
            metadata: {
                fatalities: 1739,
                displaced: '33 million',
                economicLoss: '$30 billion',
                source: 'NDMA Pakistan / UN OCHA'
            }
        },
        {
            id: 'ahr-valley-2021',
            name: 'Germany Ahr Valley Flood',
            category: 'flood',
            description: 'Catastrophic flash flood killed 184 in Rhineland-Palatinate, worst German flood disaster in decades.',
            origin: [7.10, 50.53],
            center: [7.10, 50.53],
            startDate: '2021-07-14',
            endDate: '2021-07-16',
            areaHectares: 18000,
            country: 'Germany',
            zoom: 12,
            pitch: 60,
            bearing: -20,
            beforeYear: 2020,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'ahr-valley-2021',
            metadata: {
                fatalities: 184,
                cause: 'Extreme rainfall -- 148mm in 48 hours',
                economicLoss: '$40 billion',
                source: 'DWD / Copernicus EMS'
            }
        },

        // ---- DROUGHT ----
        {
            id: 'us-megadrought-2020',
            name: 'US Western Mega-Drought',
            category: 'drought',
            description: 'Worst drought in 1,200 years across western North America. Lake Mead hit record lows.',
            origin: [-114.74, 36.02],
            center: [-114.74, 36.02],
            startDate: '2020-01-01',
            endDate: '2022-12-31',
            areaHectares: 300000000,
            country: 'United States',
            zoom: 12,
            pitch: 60,
            bearing: 0,
            beforeYear: 2018,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'us-megadrought-2020',
            metadata: {
                peakSeverity: 'D4 Exceptional',
                lakeMeadLevel: '1040 ft (record low)',
                source: 'US Drought Monitor (USDM)'
            }
        },

        // ---- GLACIAL RETREAT ----
        {
            id: 'jakobshavn-glacier',
            name: 'Jakobshavn Glacier Retreat',
            category: 'glacier',
            description: 'One of the fastest retreating glaciers on Earth, lost 97 billion tons of ice 1985-2022.',
            origin: [-49.83, 69.17],
            center: [-49.83, 69.17],
            startDate: '2000-01-01',
            endDate: '2020-12-31',
            areaHectares: 110000,
            country: 'Greenland',
            zoom: 11,
            pitch: 60,
            bearing: 30,
            beforeYear: 2018,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'jakobshavn-glacier',
            metadata: {
                retreatDistance: '40+ km since 1850',
                iceSpeed: '46 m/day',
                source: 'NSIDC / ESA CryoSat'
            }
        },
        {
            id: 'gangotri-glacier',
            name: 'Gangotri Glacier Retreat',
            category: 'glacier',
            description: 'Source of the Ganges River, retreated 1,850 meters in 28 years. Threatens water supply for millions.',
            origin: [79.17, 30.92],
            center: [79.17, 30.92],
            startDate: '1993-01-01',
            endDate: '2021-12-31',
            areaHectares: 14300,
            country: 'India',
            zoom: 12,
            pitch: 60,
            bearing: -10,
            beforeYear: 2018,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'gangotri-glacier',
            metadata: {
                retreatDistance: '1,850 m (1993-2021)',
                retreatRate: '~66 m/year',
                source: 'GSI / ISRO'
            }
        },

        // ---- DEFORESTATION ----
        {
            id: 'amazon-deforestation-2019',
            name: 'Amazon Deforestation 2019-2023',
            category: 'deforestation',
            description: 'Peak deforestation under weakened enforcement. Dramatic NDVI loss across Para state.',
            origin: [-54.95, -5.15],
            center: [-54.95, -5.15],
            startDate: '2019-01-01',
            endDate: '2023-12-31',
            areaHectares: 5100000,
            country: 'Brazil',
            zoom: 12,
            pitch: 60,
            bearing: 5,
            beforeYear: 2018,
            afterLabel: '2024',
            has3D: true,
            scene3D: 'amazon-deforestation-2019',
            metadata: {
                annualPeak: '13,235 km2 (2021)',
                source: 'INPE PRODES / Hansen GFC'
            }
        }
    ];

    const getEvidence = (eventId) => {
        const registry = window.HistoricalEventEvidence || {};
        return registry[eventId] || {};
    };

    const enrichEvent = (evt) => {
        if (!evt) return null;
        const evidence = getEvidence(evt.id);
        return {
            ...evt,
            ...evidence,
            metadata: {
                ...(evt.metadata || {}),
                ...(evidence.metadata || {})
            }
        };
    };

    const esc = (value) => String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');

    // ==========================================================
    //  SATELLITE TILE SOURCES
    // ==========================================================

    /**
     * Sentinel-2 Cloudless annual mosaics by EOX.
     * Available years: 2018, 2019, 2020, 2021
     */
    const getSentinel2Url = (year) => {
        const validYears = [2018, 2019, 2020, 2021];
        const y = validYears.includes(year) ? year : 2018;
        return `https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-${y}_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg`;
    };

    /** ESRI World Imagery (current / most recent) */
    const ESRI_WORLD_IMAGERY = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

    // ==========================================================
    //  CATEGORY-SPECIFIC OVERLAY COLORS
    // ==========================================================

    const CATEGORY_OVERLAY = {
        wildfire:      { color: 'rgba(255, 60, 0, 0.15)', borderColor: '#FF4500' },
        flood:         { color: 'rgba(0, 100, 255, 0.12)', borderColor: '#1E90FF' },
        drought:       { color: 'rgba(180, 120, 20, 0.10)', borderColor: '#DAA520' },
        glacier:       { color: 'rgba(100, 180, 255, 0.10)', borderColor: '#87CEEB' },
        deforestation: { color: 'rgba(139, 90, 43, 0.12)', borderColor: '#228B22' }
    };

    // ==========================================================
    //  FRAME GENERATORS -- for stats/date labels during playback
    // ==========================================================

    const timelineBeatForProgress = (timeline, progress) => {
        if (!Array.isArray(timeline) || timeline.length === 0) return null;
        const beats = [...timeline].sort((a, b) => (a.progress ?? 0) - (b.progress ?? 0));
        let current = beats[0];
        for (const beat of beats) {
            if ((beat.progress ?? 0) <= progress) current = beat;
        }
        return current;
    };

    const buildEvidenceFrames = (evt) => {
        const steps = 30;
        const frames = [];
        for (let i = 0; i <= steps; i++) {
            const t = i / steps;
            const beat = timelineBeatForProgress(evt.timeline, t);
            frames.push({
                date: beat?.date || evt.startDate,
                stats: {
                    label: beat?.label || evt.evidenceLabel || evt.description,
                    note: beat?.note || evt.evidenceNote || ''
                }
            });
        }
        return frames;
    };

    const buildFrames = (evt) => {
        if (cachedFrames[evt.id]) return cachedFrames[evt.id];

        if (Array.isArray(evt.timeline) && evt.timeline.length > 0) {
            cachedFrames[evt.id] = buildEvidenceFrames(evt);
            return cachedFrames[evt.id];
        }

        const steps = 30;
        const frames = [];
        const start = new Date(evt.startDate);
        const end = new Date(evt.endDate);
        const span = end - start;

        for (let i = 0; i <= steps; i++) {
            const t = i / steps;
            const date = new Date(start.getTime() + span * t);
            const eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;

            let label = '';
            let dateStr = date.toISOString().slice(0, 10);

            switch (evt.category) {
                case 'wildfire': {
                    const burned = Math.round(evt.areaHectares * eased);
                    const containment = Math.min(100, Math.round(t * t * 100));
                    label = `${burned.toLocaleString()} ha burned | ${containment}% contained`;
                    break;
                }
                case 'flood': {
                    let waterLevel;
                    if (evt.id === 'ahr-valley-2021') {
                        waterLevel = t < 0.3 ? t / 0.3 : 1 - (t - 0.3) * 0.4;
                    } else {
                        waterLevel = t < 0.7 ? Math.pow(t / 0.7, 0.6) : 1 - (t - 0.7) / 0.3 * 0.3;
                    }
                    waterLevel = Math.max(0, Math.min(1, waterLevel));
                    const flooded = Math.round(evt.areaHectares * waterLevel);
                    label = `${flooded.toLocaleString()} ha inundated`;
                    break;
                }
                case 'drought': {
                    const severity = Math.sin(t * Math.PI) * 1.2;
                    const dLevel = Math.min(4, Math.max(0, Math.round(severity * 4)));
                    const dLabels = ['D0 Abnormally Dry', 'D1 Moderate', 'D2 Severe', 'D3 Extreme', 'D4 Exceptional'];
                    const coverage = Math.round((0.3 + severity * 0.5) * 100);
                    label = `${dLabels[dLevel]} | ${coverage}% area affected`;
                    dateStr = date.toISOString().slice(0, 7);
                    break;
                }
                case 'glacier': {
                    const remaining = 1 - t * 0.35;
                    const areaLost = Math.round(evt.areaHectares * (1 - remaining));
                    label = `${areaLost.toLocaleString()} ha lost since ${start.getFullYear()}`;
                    dateStr = `${date.getFullYear()}`;
                    break;
                }
                case 'deforestation': {
                    const cleared = Math.pow(t, 1.3);
                    const totalCleared = Math.round(evt.areaHectares * cleared);
                    label = `${totalCleared.toLocaleString()} ha deforested`;
                    dateStr = date.toISOString().slice(0, 7);
                    break;
                }
            }

            frames.push({
                date: dateStr,
                stats: { label }
            });
        }

        cachedFrames[evt.id] = frames;
        return frames;
    };

    // ==========================================================
    //  SATELLITE LAYER MANAGEMENT
    // ==========================================================

    const addSatelliteLayers = (evt) => {
        if (!map) return;

        const beforeYear = evt.beforeYear || 2018;
        const beforeUrl = getSentinel2Url(beforeYear);
        const afterUrl = ESRI_WORLD_IMAGERY;

        // ---- "Before" satellite (Sentinel-2 cloudless mosaic) ----
        if (!map.getSource(SRC_BEFORE)) {
            map.addSource(SRC_BEFORE, {
                type: 'raster',
                tiles: [beforeUrl],
                tileSize: 256,
                maxzoom: 14,
                attribution: `Sentinel-2 Cloudless ${beforeYear} by EOX`
            });
        }

        if (!map.getLayer(LYR_BEFORE)) {
            const firstLayerId = map.getStyle().layers[0]?.id;
            map.addLayer({
                id: LYR_BEFORE,
                type: 'raster',
                source: SRC_BEFORE,
                paint: {
                    'raster-opacity': 1.0,
                    'raster-saturation': 0.1,
                    'raster-contrast': 0.05
                }
            }, firstLayerId);
        }

        // ---- "After" satellite (ESRI World Imagery -- current) ----
        if (!map.getSource(SRC_AFTER)) {
            map.addSource(SRC_AFTER, {
                type: 'raster',
                tiles: [afterUrl],
                tileSize: 256,
                maxzoom: 19,
                attribution: 'Esri World Imagery'
            });
        }

        if (!map.getLayer(LYR_AFTER)) {
            map.addLayer({
                id: LYR_AFTER,
                type: 'raster',
                source: SRC_AFTER,
                paint: {
                    'raster-opacity': 0.0, // starts invisible, fades in during playback
                    'raster-saturation': 0.1,
                    'raster-contrast': 0.05
                }
            });
        }

        // Dim vector layers so satellite dominates
        dimVectorLayers();

        console.log(`[EventSim] Satellite layers added: Before=${beforeYear}, After=ESRI current`);
    };

    const removeSatelliteLayers = () => {
        if (!map) return;
        [LYR_OVERLAY, LYR_AFTER, LYR_BEFORE].forEach(id => {
            try { if (map.getLayer(id)) map.removeLayer(id); } catch (_) {}
        });
        [SRC_OVERLAY, SRC_AFTER, SRC_BEFORE].forEach(id => {
            try { if (map.getSource(id)) map.removeSource(id); } catch (_) {}
        });
        restoreVectorLayers();
    };

    const dimVectorLayers = () => {
        if (!map) return;
        try {
            const style = map.getStyle();
            style.layers.forEach(layer => {
                if (layer.id.startsWith('sim-')) return;
                try {
                    if (layer.type === 'symbol') {
                        map.setPaintProperty(layer.id, 'text-opacity', 0.3);
                        map.setPaintProperty(layer.id, 'icon-opacity', 0.3);
                    } else if (layer.type === 'fill' && !layer.id.startsWith('fire') && !layer.id.startsWith('flood') && !layer.id.startsWith('drought') && !layer.id.startsWith('glacier') && !layer.id.startsWith('ndvi') && !layer.id.startsWith('watershed') && !layer.id.startsWith('risk')) {
                        map.setPaintProperty(layer.id, 'fill-opacity', 0.05);
                    } else if (layer.type === 'line') {
                        map.setPaintProperty(layer.id, 'line-opacity', 0.15);
                    }
                } catch (_) {}
            });
        } catch (_) {}
    };

    const restoreVectorLayers = () => {
        if (!map) return;
        try {
            const style = map.getStyle();
            style.layers.forEach(layer => {
                try {
                    if (layer.type === 'symbol') {
                        map.setPaintProperty(layer.id, 'text-opacity', 1);
                        map.setPaintProperty(layer.id, 'icon-opacity', 1);
                    } else if (layer.type === 'fill' && !layer.id.startsWith('sim-') && !layer.id.startsWith('fire') && !layer.id.startsWith('flood') && !layer.id.startsWith('drought') && !layer.id.startsWith('glacier') && !layer.id.startsWith('ndvi') && !layer.id.startsWith('watershed') && !layer.id.startsWith('risk')) {
                        map.setPaintProperty(layer.id, 'fill-opacity', 1);
                    } else if (layer.type === 'line' && !layer.id.startsWith('sim-')) {
                        map.setPaintProperty(layer.id, 'line-opacity', 1);
                    }
                } catch (_) {}
            });
        } catch (_) {}
    };

    // ==========================================================
    //  SWIPE DIVIDER -- draggable before/after comparison
    // ==========================================================

    const showSwipeUI = () => {
        const container = document.getElementById('sim-swipe-container');
        if (container) container.classList.remove('hidden');
        updateSwipeLabels();
    };

    const hideSwipeUI = () => {
        const container = document.getElementById('sim-swipe-container');
        if (container) container.classList.add('hidden');
    };

    const updateSwipeLabels = () => {
        if (!currentEvent) return;
        const beforeLabel = document.querySelector('.sim-swipe-before');
        const afterLabel = document.querySelector('.sim-swipe-after');
        if (beforeLabel) beforeLabel.textContent = `${currentEvent.beforeYear || 2018}`;
        if (afterLabel) afterLabel.textContent = currentEvent.afterLabel || '2024';
    };

    const updateSwipeDividerPosition = (pct) => {
        swipeDividerPos = Math.max(2, Math.min(98, pct));
        const divider = document.getElementById('sim-swipe-divider');
        if (divider) divider.style.left = `${swipeDividerPos}%`;

        const beforeLabel = document.querySelector('.sim-swipe-before');
        const afterLabel = document.querySelector('.sim-swipe-after');
        if (beforeLabel) beforeLabel.style.left = `${Math.max(5, swipeDividerPos - 12)}%`;
        if (afterLabel) afterLabel.style.left = `${Math.min(95, swipeDividerPos + 4)}%`;

        // Apply clip to the after layer canvas
        applySwipeClip();
    };

    /**
     * Apply clip-path to the "after" raster layer.
     * MapLibre does not natively support per-layer clipping, so we use the
     * canvas approach: we set the after layer's opacity and use a custom
     * render approach. For simplicity, we clip using the map container overlay.
     *
     * ACTUAL approach: We use opacity + a visual divider. In swipe mode,
     * the "before" layer is always opacity 1, and we use a CSS overlay
     * to visually indicate the split. The after layer opacity is 1 on the
     * right side via a clip-path on a positioned overlay element.
     *
     * Since MapLibre renders to a single canvas, true per-layer clipping
     * requires a workaround: we'll render the after layer at full opacity
     * and use a CSS clip-path on an overlay div that covers the left side
     * with the before imagery. For the simplest effective approach:
     * - Both layers at opacity 1
     * - After layer on top
     * - We clip the ENTIRE map canvas? No, that clips everything.
     *
     * SIMPLEST EFFECTIVE: In swipe mode, keep both at opacity 1, but use
     * the after layer opacity + the divider as a visual metaphor. The user
     * sees the "after" fading in from left to right as they drag the divider.
     * Actually we set after-layer opacity based on divider position in a
     * gradient fashion using the divider position as a threshold.
     *
     * BEST APPROACH: Use two map canvases (maplibre-gl-compare style).
     * But that's complex. Instead: timeline crossfade + a visual divider
     * that the user can drag. The divider position maps to the crossfade
     * progress. Dragging right = more "after" visible (higher opacity).
     */
    const applySwipeClip = () => {
        if (!map || comparisonMode !== 'swipe') return;

        // Map divider position to after-layer opacity
        // At 0% (divider fully left): after opacity = 0 (all "before")
        // At 100% (divider fully right): after opacity = 1 (all "after")
        const afterOpacity = swipeDividerPos / 100;

        try {
            if (map.getLayer(LYR_AFTER)) {
                map.setPaintProperty(LYR_AFTER, 'raster-opacity', afterOpacity);
            }
        } catch (_) {}
    };

    const initSwipeDrag = () => {
        const container = document.getElementById('sim-swipe-container');
        const divider = document.getElementById('sim-swipe-divider');
        if (!container || !divider) return;

        const getPosition = (e) => {
            const rect = container.getBoundingClientRect();
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            return ((clientX - rect.left) / rect.width) * 100;
        };

        const onStart = (e) => {
            if (comparisonMode !== 'swipe') return;
            isDraggingDivider = true;
            e.preventDefault();
        };

        const onMove = (e) => {
            if (!isDraggingDivider) return;
            const pct = getPosition(e);
            updateSwipeDividerPosition(pct);
        };

        const onEnd = () => {
            isDraggingDivider = false;
        };

        divider.addEventListener('mousedown', onStart);
        divider.addEventListener('touchstart', onStart, { passive: false });
        document.addEventListener('mousemove', onMove);
        document.addEventListener('touchmove', onMove, { passive: true });
        document.addEventListener('mouseup', onEnd);
        document.addEventListener('touchend', onEnd);
    };

    // ==========================================================
    //  COMPARISON MODE TOGGLE
    // ==========================================================

    const setComparisonMode = (mode) => {
        comparisonMode = mode;
        const btn = document.getElementById('sim-compare-btn');

        if (mode === 'swipe') {
            if (btn) btn.classList.add('active');
            showSwipeUI();
            // In swipe mode: after layer tracks divider position
            updateSwipeDividerPosition(swipeDividerPos);
        } else {
            if (btn) btn.classList.remove('active');
            hideSwipeUI();
            // In timeline mode: after layer tracks playback progress
            updateAfterOpacity(timelineProgress);
        }
    };

    const toggleComparisonMode = () => {
        setComparisonMode(comparisonMode === 'timeline' ? 'swipe' : 'timeline');
    };

    // ==========================================================
    //  CROSSFADE ANIMATION
    // ==========================================================

    /**
     * Update the "after" satellite layer opacity based on timeline progress.
     * This creates the dramatic crossfade from before to after imagery.
     */
    const updateAfterOpacity = (progress) => {
        if (!map || comparisonMode !== 'timeline') return;

        // Smooth crossfade curve: slow start, accelerate in middle, slow finish
        const eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - Math.pow(-2 * progress + 2, 2) / 2;

        try {
            if (map.getLayer(LYR_AFTER)) {
                map.setPaintProperty(LYR_AFTER, 'raster-opacity', eased);
            }
        } catch (_) {}
    };

    // ==========================================================
    //  UI -- playback bar & info panel
    // ==========================================================

    const showPlaybackUI = () => {
        const bar = document.getElementById('sim-playback-bar');
        if (bar) bar.classList.remove('hidden');
        const info = document.getElementById('sim-info-panel');
        if (info) info.classList.remove('hidden');
        // Hide normal time slider and sidebar
        const ts = document.getElementById('time-slider-container');
        if (ts) ts.style.display = 'none';
        const sidebar = document.getElementById('sidebar');
        if (sidebar) sidebar.classList.add('collapsed');
        const toggleBtn = document.getElementById('sidebar-toggle');
        if (toggleBtn) toggleBtn.style.display = 'none';
    };

    const hidePlaybackUI = () => {
        const bar = document.getElementById('sim-playback-bar');
        if (bar) bar.classList.add('hidden');
        const info = document.getElementById('sim-info-panel');
        if (info) info.classList.add('hidden');
        const ts = document.getElementById('time-slider-container');
        if (ts) ts.style.display = '';
        const sidebar = document.getElementById('sidebar');
        if (sidebar) sidebar.classList.remove('collapsed');
        const toggleBtn = document.getElementById('sidebar-toggle');
        if (toggleBtn) toggleBtn.style.display = '';
        hideSwipeUI();
    };

    const updatePlaybackUI = (frame, progress) => {
        const dateEl = document.getElementById('sim-date-label');
        if (dateEl && frame) dateEl.textContent = frame.date;

        const statEl = document.getElementById('sim-stat-label');
        if (statEl && frame && frame.stats) statEl.textContent = frame.stats.label || '';

        const beatEl = document.getElementById('event-story-current-beat');
        if (beatEl && frame?.stats) {
            beatEl.innerHTML = `<strong>${esc(frame.stats.label || '')}</strong><br>${esc(frame.stats.note || '')}`;
        }

        const scrubber = document.getElementById('sim-scrubber');
        if (scrubber) scrubber.value = Math.round(progress * 1000);

        const pctEl = document.getElementById('sim-progress-pct');
        if (pctEl) pctEl.textContent = `${Math.round(progress * 100)}%`;

        // Update play/pause icon
        const playIcon = document.getElementById('sim-play-icon');
        const pauseIcon = document.getElementById('sim-pause-icon');
        if (playIcon && pauseIcon) {
            playIcon.style.display = isPlaying ? 'none' : 'block';
            pauseIcon.style.display = isPlaying ? 'block' : 'none';
        }
    };

    const updateInfoPanel = (evt) => {
        const title = document.getElementById('sim-info-title');
        if (title) title.textContent = evt.name;

        const cat = document.getElementById('sim-info-category');
        if (cat) {
            cat.textContent = evt.category.charAt(0).toUpperCase() + evt.category.slice(1);
            cat.className = 'sim-category-badge sim-cat-' + evt.category;
        }

        const desc = document.getElementById('sim-info-description');
        if (desc) desc.textContent = evt.description;

        const dates = document.getElementById('sim-info-dates');
        if (dates) dates.textContent = `${evt.startDate} to ${evt.endDate}`;

        const area = document.getElementById('sim-info-area');
        if (area) area.textContent = `${evt.areaHectares.toLocaleString()} ha`;

        const country = document.getElementById('sim-info-country');
        if (country) country.textContent = evt.country;

        // Evidence and metadata rows
        const metaContainer = document.getElementById('sim-info-metadata');
        if (metaContainer) {
            metaContainer.innerHTML = '';

            if (evt.evidenceLabel || evt.evidenceNote) {
                const evidenceRow = document.createElement('div');
                evidenceRow.className = 'info-row sim-evidence-row';
                evidenceRow.innerHTML = `<span class="info-key">Map Evidence</span><span class="info-value">${esc(evt.evidenceLabel || evt.evidenceNote)}</span>`;
                metaContainer.appendChild(evidenceRow);
            }

            if (Array.isArray(evt.localImpacts) && evt.localImpacts.length > 0) {
                const impactRow = document.createElement('div');
                impactRow.className = 'info-row sim-evidence-row';
                impactRow.innerHTML = `<span class="info-key">Local Anchors</span><span class="info-value">${esc(evt.localImpacts.slice(0, 2).join(' '))}</span>`;
                metaContainer.appendChild(impactRow);
            }

            Object.entries(evt.metadata || {}).forEach(([k, v]) => {
                const row = document.createElement('div');
                row.className = 'info-row';
                const key = k.replace(/([A-Z])/g, ' $1').replace(/^./, s => s.toUpperCase());
                row.innerHTML = `<span class="info-key">${esc(key)}</span><span class="info-value">${esc(v)}</span>`;
                metaContainer.appendChild(row);
            });
        }
    };

    // ==========================================================
    //  PLAYBACK ENGINE
    // ==========================================================

    const renderFrame = (progress) => {
        if (!currentEvent) return;
        const frames = buildFrames(currentEvent);
        if (!frames || frames.length === 0) return;

        const idx = Math.min(frames.length - 1, Math.floor(progress * frames.length));
        const frame = frames[idx];

        // Update satellite crossfade based on progress
        if (comparisonMode === 'timeline') {
            updateAfterOpacity(progress);
        }

        // In swipe mode during playback, sweep the divider from left to right
        if (comparisonMode === 'swipe' && isPlaying) {
            updateSwipeDividerPosition(progress * 100);
        }

        updatePlaybackUI(frame, progress);
    };

    const animationLoop = (timestamp) => {
        if (!isPlaying || !currentEvent) return;

        if (lastFrameTime === 0) lastFrameTime = timestamp;
        const dt = (timestamp - lastFrameTime) / 1000;
        lastFrameTime = timestamp;

        const frames = buildFrames(currentEvent);
        const totalDuration = frames.length / (2 * playbackSpeed);
        const progressPerSec = 1 / totalDuration;
        timelineProgress = Math.min(1, timelineProgress + progressPerSec * dt);

        renderFrame(timelineProgress);

        if (timelineProgress >= 1) {
            isPlaying = false;
            updatePlaybackUI(frames[frames.length - 1], 1);
            return;
        }

        animationFrame = requestAnimationFrame(animationLoop);
    };

    // ==========================================================
    //  CAMERA ORBIT
    // ==========================================================

    let orbitRAF = null;

    const startCameraOrbit = (evt) => {
        cameraOrbitActive = true;
        const orbitSpeed = 0.04; // degrees per frame

        const orbitStep = () => {
            if (!cameraOrbitActive || !map) return;
            cameraOrbitAngle = (cameraOrbitAngle + orbitSpeed) % 360;
            map.setBearing(cameraOrbitAngle);
            orbitRAF = requestAnimationFrame(orbitStep);
        };
        orbitRAF = requestAnimationFrame(orbitStep);
    };

    const stopCameraOrbit = () => {
        cameraOrbitActive = false;
        if (orbitRAF) {
            cancelAnimationFrame(orbitRAF);
            orbitRAF = null;
        }
    };

    // ==========================================================
    //  ATMOSPHERIC EFFECTS
    // ==========================================================

    const applyAtmosphericEffects = (category) => {
        if (!map) return;
        try {
            switch (category) {
                case 'wildfire':
                    map.setSky({
                        'sky-color': '#4A2000',
                        'sky-horizon-blend': 0.7,
                        'horizon-color': '#FF6B35',
                        'horizon-fog-blend': 0.9,
                        'fog-color': '#8B4513',
                        'fog-ground-blend': 0.7,
                        'atmosphere-blend': 0.9
                    });
                    break;
                case 'flood':
                    map.setSky({
                        'sky-color': '#1a2a3a',
                        'sky-horizon-blend': 0.6,
                        'horizon-color': '#4a6a8a',
                        'horizon-fog-blend': 0.8,
                        'fog-color': '#6a7a8a',
                        'fog-ground-blend': 0.6,
                        'atmosphere-blend': 0.85
                    });
                    break;
                case 'drought':
                    map.setSky({
                        'sky-color': '#F5E6C8',
                        'sky-horizon-blend': 0.5,
                        'horizon-color': '#E8D5B7',
                        'horizon-fog-blend': 0.6,
                        'fog-color': '#D4C4A8',
                        'fog-ground-blend': 0.4,
                        'atmosphere-blend': 0.7
                    });
                    break;
                case 'glacier':
                    map.setSky({
                        'sky-color': '#B8D4E8',
                        'sky-horizon-blend': 0.4,
                        'horizon-color': '#E0EFF8',
                        'horizon-fog-blend': 0.5,
                        'fog-color': '#FFFFFF',
                        'fog-ground-blend': 0.3,
                        'atmosphere-blend': 0.6
                    });
                    break;
                case 'deforestation':
                    map.setSky({
                        'sky-color': '#6B8E6B',
                        'sky-horizon-blend': 0.5,
                        'horizon-color': '#A0B090',
                        'horizon-fog-blend': 0.7,
                        'fog-color': '#8B9B7B',
                        'fog-ground-blend': 0.5,
                        'atmosphere-blend': 0.75
                    });
                    break;
            }
        } catch (e) {
            console.warn('[EventSim] Sky/fog not supported:', e.message);
        }
    };

    const restoreAtmosphere = () => {
        if (!map) return;
        try {
            map.setSky({
                'sky-color': '#88C6FC',
                'sky-horizon-blend': 0.5,
                'horizon-color': '#f0e8d8',
                'horizon-fog-blend': 0.8,
                'fog-color': '#ffffff',
                'fog-ground-blend': 0.5,
                'atmosphere-blend': 0.8
            });
        } catch (_) {}
    };

    // ==========================================================
    //  STORY MODE / ORIGIN FOCUS
    // ==========================================================

    const getFocusCenter = (evt) => evt.origin || evt.center;

    const estimateFocusRadiusKm = (evt) => {
        const areaHa = evt.areaHectares || 1000;
        const radius = Math.sqrt((areaHa / 100) / Math.PI);
        return Math.max(1.5, Math.min(radius, 90));
    };

    const buildCircle = (center, radiusKm, steps = 128) => {
        const coords = [];
        const cosLat = Math.max(0.2, Math.cos(center[1] * Math.PI / 180));
        for (let i = 0; i <= steps; i++) {
            const angle = (i / steps) * Math.PI * 2;
            const wave = 1 + 0.08 * Math.sin(angle * 3) + 0.05 * Math.cos(angle * 7);
            const r = radiusKm * wave;
            coords.push([
                center[0] + (r * Math.cos(angle)) / (111.32 * cosLat),
                center[1] + (r * Math.sin(angle)) / 110.54
            ]);
        }
        return coords;
    };

    const fallbackFocusGeometry = (evt) => {
        const center = getFocusCenter(evt);
        const radiusKm = estimateFocusRadiusKm(evt);
        return {
            type: 'FeatureCollection',
            features: [{
                type: 'Feature',
                geometry: { type: 'Polygon', coordinates: [buildCircle(center, radiusKm)] },
                properties: {
                    id: evt.id,
                    name: 'Modeled impact radius',
                    role: 'modeled-radius',
                    radius_km: radiusKm,
                    area_hectares: evt.areaHectares || 0
                }
            }]
        };
    };

    const focusGeometryFor = (evt) => {
        const source = evt.focusGeometry || fallbackFocusGeometry(evt);
        const cloned = JSON.parse(JSON.stringify(source));
        cloned.features = (cloned.features || []).map((feature) => ({
            ...feature,
            properties: {
                id: evt.id,
                event_id: evt.id,
                ...(feature.properties || {})
            }
        }));
        return cloned;
    };

    const eachCoordinate = (coords, visit) => {
        if (!Array.isArray(coords)) return;
        if (typeof coords[0] === 'number' && typeof coords[1] === 'number') {
            visit(coords);
            return;
        }
        coords.forEach((part) => eachCoordinate(part, visit));
    };

    const boundsFromGeometry = (featureCollection) => {
        if (!window.maplibregl || !featureCollection?.features?.length) return null;
        let bounds = null;
        featureCollection.features.forEach((feature) => {
            eachCoordinate(feature.geometry?.coordinates, (coord) => {
                if (!bounds) {
                    bounds = new maplibregl.LngLatBounds(coord, coord);
                } else {
                    bounds.extend(coord);
                }
            });
        });
        return bounds;
    };

    const removeEventFocus = () => {
        if (!map) return;
        [LYR_FOCUS_LABEL, LYR_FOCUS_POINT, LYR_FOCUS_LINE, LYR_FOCUS_FILL].forEach(id => {
            try { if (map.getLayer(id)) map.removeLayer(id); } catch (_) {}
        });
        try { if (map.getSource(SRC_FOCUS)) map.removeSource(SRC_FOCUS); } catch (_) {}
        if (eventOriginMarker) {
            eventOriginMarker.remove();
            eventOriginMarker = null;
        }
    };

    const showEventFocus = (evt) => {
        if (!map) return;
        removeEventFocus();
        const center = getFocusCenter(evt);
        const overlay = CATEGORY_OVERLAY[evt.category] || CATEGORY_OVERLAY.wildfire;
        const data = focusGeometryFor(evt);

        map.addSource(SRC_FOCUS, { type: 'geojson', data });
        map.addLayer({
            id: LYR_FOCUS_FILL,
            type: 'fill',
            source: SRC_FOCUS,
            filter: ['match', ['geometry-type'], ['Polygon', 'MultiPolygon'], true, false],
            paint: {
                'fill-color': overlay.borderColor,
                'fill-opacity': 0.14
            }
        });
        map.addLayer({
            id: LYR_FOCUS_LINE,
            type: 'line',
            source: SRC_FOCUS,
            filter: ['match', ['geometry-type'], ['LineString', 'MultiLineString', 'Polygon', 'MultiPolygon'], true, false],
            paint: {
                'line-color': overlay.borderColor,
                'line-width': 3,
                'line-dasharray': [2, 1],
                'line-opacity': 0.9
            }
        });
        map.addLayer({
            id: LYR_FOCUS_POINT,
            type: 'circle',
            source: SRC_FOCUS,
            filter: ['==', ['geometry-type'], 'Point'],
            paint: {
                'circle-radius': [
                    'case',
                    ['==', ['get', 'role'], 'origin'], 7,
                    5
                ],
                'circle-color': '#ffffff',
                'circle-stroke-color': overlay.borderColor,
                'circle-stroke-width': 3,
                'circle-opacity': 0.96
            }
        });
        map.addLayer({
            id: LYR_FOCUS_LABEL,
            type: 'symbol',
            source: SRC_FOCUS,
            filter: ['==', ['geometry-type'], 'Point'],
            layout: {
                'text-field': ['get', 'name'],
                'text-size': 12,
                'text-font': ['Open Sans Semibold', 'Arial Unicode MS Bold'],
                'text-anchor': 'top',
                'text-offset': [0, 1.1],
                'text-allow-overlap': false,
                'text-optional': true
            },
            paint: {
                'text-color': '#ffffff',
                'text-halo-color': '#0a0f18',
                'text-halo-width': 1.6
            }
        });

        const markerEl = document.createElement('div');
        markerEl.className = 'event-origin-marker';
        markerEl.style.borderColor = overlay.borderColor;
        markerEl.title = `${evt.name} origin / focus point`;
        eventOriginMarker = new maplibregl.Marker({ element: markerEl, anchor: 'center' })
            .setLngLat(center)
            .addTo(map);
    };

    const moveCameraToEvent = (evt, targetPitch, targetBearing) => {
        if (!map) return;
        const focusCenter = getFocusCenter(evt);
        const closeZoom = Math.min(Math.max(evt.zoom || 10, 7), 14);
        const focusData = focusGeometryFor(evt);
        const bounds = evt.fitFootprint ? boundsFromGeometry(focusData) : null;

        if (bounds) {
            try {
                map.fitBounds(bounds, {
                    padding: { top: 96, right: 420, bottom: 110, left: 80 },
                    maxZoom: evt.maxFocusZoom || closeZoom,
                    duration: 4000,
                    curve: 1.6,
                    essential: true
                });
                window.setTimeout(() => {
                    if (currentEvent && currentEvent.id === evt.id) {
                        map.easeTo({
                            pitch: targetPitch,
                            bearing: targetBearing,
                            duration: 1100,
                            essential: true
                        });
                    }
                }, 450);
                return;
            } catch (e) {
                console.warn('[EventSim] fitBounds failed, falling back to flyTo:', e.message);
            }
        }

        map.flyTo({
            center: focusCenter,
            zoom: closeZoom,
            pitch: targetPitch,
            bearing: targetBearing,
            duration: 4000,
            curve: 1.6,
            essential: true
        });
    };

    const eventPayload = (evt) => {
        const center = getFocusCenter(evt);
        return {
            id: evt.id,
            name: evt.name,
            title: evt.name,
            type: evt.category,
            category: evt.category,
            description: evt.description,
            desc: evt.description,
            startDate: evt.startDate,
            endDate: evt.endDate,
            areaHectares: evt.areaHectares,
            country: evt.country,
            origin: evt.origin,
            center: evt.center,
            lat: center[1],
            lng: center[0],
            impactRadiusKm: estimateFocusRadiusKm(evt),
            zoom: evt.zoom,
            source: evt.metadata?.source || 'Historical event catalog',
            confidence: 'documented event',
            status: 'historical reconstruction',
            evidenceLabel: evt.evidenceLabel || '',
            evidenceNote: evt.evidenceNote || '',
            localImpacts: evt.localImpacts || [],
            timeline: evt.timeline || [],
            metadata: evt.metadata || {}
        };
    };

    const formatMetricKey = (key) =>
        key.replace(/([A-Z])/g, ' $1').replace(/^./, s => s.toUpperCase());

    const storyForCategory = (evt) => {
        if (evt.story) return evt.story;
        switch (evt.category) {
            case 'wildfire':
                return 'The story here is fire meeting fuels, weather, terrain, and human exposure. The before image gives the baseline; the after image shows the burn scar, smoke legacy, and recovery challenge.';
            case 'flood':
                return 'The story here is water overwhelming the normal channel and moving through settlements, roads, farms, and public services. The timeline helps separate peak inundation from the longer recovery footprint.';
            case 'drought':
                return 'The story here is slow-onset stress. It is not one impact point; it is accumulating heat, rainfall deficit, vegetation stress, water supply pressure, and wildfire amplification.';
            case 'glacier':
                return 'The story here is long-term ice loss changing downstream water timing, slope stability, and future flood potential. The event is slower, but the consequences are structural.';
            case 'deforestation':
                return 'The story here is land-cover conversion. The important comparison is the spread of cleared edges, habitat fragmentation, access corridors, and lost carbon storage.';
            default:
                return 'The story here is a documented environmental disruption. Use the timeline to compare the baseline, the event footprint, and the recovery condition.';
        }
    };

    const buildNarrative = (evt) => {
        const metaText = Object.entries(evt.metadata || {})
            .map(([k, v]) => `${formatMetricKey(k)}: ${v}`)
            .join('. ');
        const localText = Array.isArray(evt.localImpacts) && evt.localImpacts.length > 0
            ? ` Local evidence anchors: ${evt.localImpacts.join(' ')}`
            : '';
        const evidenceText = evt.evidenceNote ? ` Evidence note: ${evt.evidenceNote}` : '';
        return `${evt.name}. ${evt.description} The event ran from ${evt.startDate} to ${evt.endDate} in ${evt.country}. ${storyForCategory(evt)}${localText}${evidenceText} ${metaText ? `Key documented impacts include ${metaText}.` : ''}`;
    };

    const stopNarration = () => {
        try {
            if (window.speechSynthesis) window.speechSynthesis.cancel();
        } catch (_) {}
        storyUtterance = null;
    };

    const narrateEvent = (evt) => {
        if (!window.speechSynthesis || !evt) return;
        stopNarration();
        storyUtterance = new SpeechSynthesisUtterance(buildNarrative(evt));
        storyUtterance.rate = 0.92;
        storyUtterance.pitch = 1;
        storyUtterance.volume = 0.95;
        window.speechSynthesis.speak(storyUtterance);
    };

    const hideStoryPanel = () => {
        const panel = document.getElementById('event-story-panel');
        if (panel) panel.remove();
    };

    const showStoryPanel = (evt) => {
        hideStoryPanel();
        const overlay = CATEGORY_OVERLAY[evt.category] || CATEGORY_OVERLAY.wildfire;
        const metrics = Object.entries(evt.metadata || {})
            .map(([k, v]) => `
                <div class="event-story-metric">
                    <span>${esc(formatMetricKey(k))}</span>
                    <strong>${esc(v)}</strong>
                </div>
            `)
            .join('');
        const impacts = Array.isArray(evt.localImpacts) && evt.localImpacts.length > 0
            ? `<ul class="event-story-local-list">${evt.localImpacts.map(item => `<li>${esc(item)}</li>`).join('')}</ul>`
            : '';
        const evidenceNote = evt.evidenceNote
            ? `<p class="event-story-evidence">${esc(evt.evidenceNote)}</p>`
            : '';
        const activeBeat = timelineBeatForProgress(evt.timeline, timelineProgress);

        const panel = document.createElement('div');
        panel.id = 'event-story-panel';
        panel.className = 'event-story-panel';
        panel.style.setProperty('--event-story-color', overlay.borderColor);
        panel.innerHTML = `
            <div class="event-story-header">
                <div>
                    <span class="event-story-kicker">${esc(evt.evidenceLabel || 'Historical Event Story')}</span>
                    <h3>${esc(evt.name)}</h3>
                </div>
                <button class="event-story-close" title="Close story">x</button>
            </div>
            <div class="event-story-body">
                <p>${esc(storyForCategory(evt))}</p>
                <div class="event-story-timeline">
                    <span>${esc(evt.startDate)}</span>
                    <div></div>
                    <span>${esc(evt.endDate)}</span>
                </div>
                ${activeBeat ? `<p id="event-story-current-beat" class="event-story-beat"><strong>${esc(activeBeat.label)}</strong><br>${esc(activeBeat.note || '')}</p>` : ''}
                <p>${esc(evt.description)}</p>
                ${impacts}
                ${evidenceNote}
                <div class="event-story-metrics">${metrics}</div>
            </div>
            <div class="event-story-actions">
                <button data-story-action="narrate">Narrate</button>
                <button data-story-action="pause">Stop Voice</button>
                <button data-story-action="insights">Open Environmental News</button>
            </div>
        `;
        document.body.appendChild(panel);

        panel.querySelector('.event-story-close')?.addEventListener('click', () => {
            stopNarration();
            hideStoryPanel();
        });
        panel.querySelector('[data-story-action="narrate"]')?.addEventListener('click', () => narrateEvent(evt));
        panel.querySelector('[data-story-action="pause"]')?.addEventListener('click', stopNarration);
        panel.querySelector('[data-story-action="insights"]')?.addEventListener('click', () => {
            if (window.EcoLensBridge) {
                window.EcoLensBridge.sendToFlutter('openHistoricalEventInsights', eventPayload(evt));
            }
        });
    };

    // ==========================================================
    //  LOAD & PLAY
    // ==========================================================

    const loadEvent = (eventId) => {
        const evt = enrichEvent(EVENT_CATALOG.find(e => e.id === eventId));
        if (!evt) { console.warn('[EventSim] Event not found:', eventId); return; }

        // Stop any current playback
        pause();
        stopCameraOrbit();
        stopNarration();
        removeSatelliteLayers();
        removeEventFocus();
        hideStoryPanel();
        currentEvent = evt;
        timelineProgress = 0;
        comparisonMode = 'timeline';

        // ---- STEP 1: Add before/after satellite layers ----
        addSatelliteLayers(evt);

        // ---- STEP 2: Boost terrain ----
        try {
            savedTerrainExaggeration = 1.8;
            map.setTerrain({ source: 'terrain-source', exaggeration: 2.2 });
        } catch (e) {
            console.warn('[EventSim] Could not boost terrain:', e.message);
        }

        // ---- STEP 3: Atmospheric effects ----
        applyAtmosphericEffects(evt.category);

        // ---- STEP 4: Cinematic fly-in to the event origin/focus area ----
        const focusCenter = getFocusCenter(evt);
        const targetPitch = evt.pitch || 60;
        cameraOrbitAngle = evt.bearing || 0;
        moveCameraToEvent(evt, targetPitch, cameraOrbitAngle);

        // ---- STEP 5: Start orbit after fly-in ----
        setTimeout(() => {
            if (currentEvent && currentEvent.id === evt.id) {
                startCameraOrbit(evt);
            }
        }, 4500);

        // ---- STEP 6: Show UI ----
        updateInfoPanel(evt);
        showPlaybackUI();
        showEventFocus(evt);
        showStoryPanel(evt);
        renderFrame(0);
        setTimeout(() => {
            if (currentEvent && currentEvent.id === evt.id) {
                play();
                narrateEvent(evt);
            }
        }, 900);

        // Reset compare button
        const btn = document.getElementById('sim-compare-btn');
        if (btn) btn.classList.remove('active');

        // Notify Flutter
        if (window.EcoLensBridge) {
            window.EcoLensBridge.sendToFlutter('simulationLoaded', {
                eventId: evt.id,
                name: evt.name,
                category: evt.category,
                lat: focusCenter[1],
                lng: focusCenter[0],
                areaHectares: evt.areaHectares
            });
            window.EcoLensBridge.sendToFlutter('eventSelected', eventPayload(evt));
        }

        // Close catalog
        const catalog = document.getElementById('event-catalog-panel');
        if (catalog) catalog.classList.add('hidden');

        console.log(`[EventSim] Loaded: ${evt.name} | Before: Sentinel-2 ${evt.beforeYear}, After: ESRI current`);
    };

    const play = () => {
        if (!currentEvent) return;
        if (timelineProgress >= 1) timelineProgress = 0;
        isPlaying = true;
        lastFrameTime = 0;
        animationFrame = requestAnimationFrame(animationLoop);
    };

    const pause = () => {
        isPlaying = false;
        if (animationFrame) {
            cancelAnimationFrame(animationFrame);
            animationFrame = null;
        }
    };

    const seek = (progress) => {
        timelineProgress = Math.max(0, Math.min(1, progress));
        renderFrame(timelineProgress);
    };

    const setSpeed = (multiplier) => {
        playbackSpeed = multiplier;
        const speedLabel = document.getElementById('sim-speed-label');
        if (speedLabel) speedLabel.textContent = `${multiplier}x`;
    };

    const exit = () => {
        pause();
        stopCameraOrbit();
        stopNarration();
        currentEvent = null;
        timelineProgress = 0;

        // Remove satellite layers
        removeSatelliteLayers();
        removeEventFocus();
        hideStoryPanel();
        hidePlaybackUI();

        // Restore terrain and atmosphere
        try {
            map.setTerrain({ source: 'terrain-source', exaggeration: savedTerrainExaggeration });
        } catch (_) {}
        restoreAtmosphere();

        // Restore view
        map.flyTo({
            center: [10, 25],
            zoom: 2.8,
            pitch: 40,
            bearing: 0,
            duration: 2000,
            essential: true
        });

        // Show sidebar again
        const sidebar = document.getElementById('sidebar');
        if (sidebar) sidebar.classList.remove('sim-hidden', 'collapsed');

        if (window.EcoLensBridge) {
            window.EcoLensBridge.sendToFlutter('simulationExited', {});
        }

        console.log('[EventSim] Exited simulation mode');
    };

    const getEventCatalog = () => {
        return EVENT_CATALOG.map(enrichEvent).map(e => ({
            id: e.id,
            name: e.name,
            category: e.category,
            description: e.description,
            startDate: e.startDate,
            endDate: e.endDate,
            areaHectares: e.areaHectares,
            country: e.country,
            origin: e.origin,
            center: e.center,
            metadata: e.metadata || {},
            evidenceQuality: e.evidenceQuality || '',
            evidenceLabel: e.evidenceLabel || '',
            evidenceNote: e.evidenceNote || '',
            localImpacts: e.localImpacts || [],
            has3D: e.has3D || false,
            scene3D: e.scene3D || null
        }));
    };

    // ==========================================================
    //  BIND DOM CONTROLS
    // ==========================================================

    const bindPlaybackControls = () => {
        // Play/Pause
        const playBtn = document.getElementById('sim-play-btn');
        if (playBtn) {
            playBtn.addEventListener('click', () => {
                if (isPlaying) pause(); else play();
                const playIcon = document.getElementById('sim-play-icon');
                const pauseIcon = document.getElementById('sim-pause-icon');
                if (playIcon && pauseIcon) {
                    playIcon.style.display = isPlaying ? 'none' : 'block';
                    pauseIcon.style.display = isPlaying ? 'block' : 'none';
                }
            });
        }

        // Scrubber
        const scrubber = document.getElementById('sim-scrubber');
        if (scrubber) {
            scrubber.addEventListener('input', (e) => {
                const val = parseInt(e.target.value, 10);
                seek(val / 1000);
            });
        }

        // Speed
        const speedBtn = document.getElementById('sim-speed-btn');
        if (speedBtn) {
            speedBtn.addEventListener('click', () => {
                const speeds = [1, 2, 5];
                const idx = speeds.indexOf(playbackSpeed);
                const next = speeds[(idx + 1) % speeds.length];
                setSpeed(next);
            });
        }

        // Compare mode toggle
        const compareBtn = document.getElementById('sim-compare-btn');
        if (compareBtn) {
            compareBtn.addEventListener('click', toggleComparisonMode);
        }

        // Exit
        const exitBtn = document.getElementById('sim-exit-btn');
        if (exitBtn) {
            exitBtn.addEventListener('click', exit);
        }

        // Swipe divider drag
        initSwipeDrag();
    };

    // ==========================================================
    //  PUBLIC API
    // ==========================================================

    const init = (mapInstance) => {
        map = mapInstance;
        console.log('[EventSim] Initialized -- satellite before/after comparison engine');
        bindPlaybackControls();
    };

    return {
        init,
        loadEvent,
        play,
        pause,
        seek,
        setSpeed,
        exit,
        getEventCatalog
    };
})();

window.EventSimulations = EventSimulations;
