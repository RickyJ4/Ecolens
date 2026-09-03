/**
 * EcoLens Story Viewer - Main Initialization
 * Creates CesiumJS viewer and wires up all modules
 */

// IMMEDIATE DEBUG - check storage before anything else
console.log('[StoryViewer] === STORAGE DEBUG ON LOAD ===');
console.log('[StoryViewer] URL:', window.location.href);
console.log('[StoryViewer] Hash:', window.location.hash);
console.log('[StoryViewer] Origin:', window.location.origin);
console.log('[StoryViewer] localStorage keys:', Object.keys(localStorage));
console.log('[StoryViewer] sessionStorage keys:', Object.keys(sessionStorage));
const lsConfig = localStorage.getItem('ecolens_story_config');
const ssConfig = sessionStorage.getItem('ecolens_story_config');
console.log('[StoryViewer] localStorage config:', lsConfig ? `EXISTS (${lsConfig.length} chars)` : 'NULL');
console.log('[StoryViewer] sessionStorage config:', ssConfig ? `EXISTS (${ssConfig.length} chars)` : 'NULL');

// If hash indicates config should exist but storage is empty, log warning
if (window.location.hash.includes('hasConfig=true') && !lsConfig && !ssConfig) {
    console.error('[StoryViewer] URL says config exists but storage is empty! Origin mismatch?');
}

let viewer = null;
let _pendingConfig = null;
let _viewerReady = false;

// Define IMMEDIATELY — before init() runs
// This ensures Flutter can call initStory() even before CesiumJS is ready
window.initStory = function(config) {
    console.log('[StoryViewer] initStory called from Flutter');
    if (typeof config === 'string') {
        try { config = JSON.parse(config); } catch(e) {
            console.error('[StoryViewer] Failed to parse config:', e);
            return;
        }
    }
    if (_viewerReady) {
        console.log('[StoryViewer] Viewer ready, loading story immediately');
        loadStory(config);
    } else {
        console.log('[StoryViewer] Viewer not ready, queuing config');
        _pendingConfig = config;
    }
};

async function init() {
    // Check library availability FIRST using LibraryLoader
    console.log('[StoryViewer] === Library Check ===');

    let libStatus;
    if (window.LibraryLoader) {
        libStatus = LibraryLoader.checkLibraries();

        // If CDN failed to load Pannellum/Howler, try local fallback
        if (!libStatus.pannellum || !libStatus.howler) {
            console.log('[StoryViewer] Some libraries missing, attempting local fallback...');
            updateLoadingText('Loading additional libraries...');
            libStatus = await LibraryLoader.loadMissingLibraries();
        }

        console.log('[StoryViewer] Final library status:', LibraryLoader.getStatusMessage());
    } else {
        // Fallback if LibraryLoader not available
        console.log('[StoryViewer] Cesium available:', typeof Cesium !== 'undefined');
        console.log('[StoryViewer] Pannellum available:', typeof pannellum !== 'undefined');
        console.log('[StoryViewer] Howler available:', typeof Howl !== 'undefined');
    }

    // Set intro video FIRST (forest canopy, NOT ocean)
    const introVideo = document.getElementById('introVideo');
    const introSrc = document.getElementById('introVideoSrc');
    if (introSrc && introVideo) {
        // Forest canopy drone footage — NEVER ocean/underwater
        introSrc.src = 'https://cdn.pixabay.com/video/2021/04/06/70166-533319434_large.mp4';
        introVideo.load();
    }

    try {
        console.log('[StoryViewer] Initializing CesiumJS...');
        updateLoadingText('Loading 3D terrain engine...');

        // Set Cesium Ion token from config
        console.log('[StoryViewer] Setting Cesium Ion token...');
        Cesium.Ion.defaultAccessToken = EcoLensConfig.cesiumToken;
        console.log('[StoryViewer] Token set successfully');

        // Create terrain provider — CesiumJS 1.104+ async API
        console.log('[StoryViewer] About to create terrain provider...');
        const terrainProvider = await Cesium.CesiumTerrainProvider.fromIonAssetId(1, {
            requestWaterMask: true,
            requestVertexNormals: true
        });
        console.log('[StoryViewer] Terrain provider created successfully');

        // Create CesiumJS viewer with real 3D terrain
        console.log('[StoryViewer] About to create viewer...');
        viewer = new Cesium.Viewer('cesiumContainer', {
            terrainProvider: terrainProvider,
            baseLayerPicker: false,
            geocoder: false,
            homeButton: false,
            sceneModePicker: false,
            selectionIndicator: false,
            timeline: false,
            animation: false,
            fullscreenButton: false,
            navigationHelpButton: false,
            infoBox: false,
            creditContainer: document.createElement('div'), // Hide credits
        });
        console.log('[StoryViewer] Viewer created successfully');

        // Add Bing Aerial imagery — CesiumJS 1.104+ async API
        console.log('[StoryViewer] About to create imagery provider...');
        const imageryProvider = await Cesium.IonImageryProvider.fromAssetId(2);
        viewer.imageryLayers.addImageryProvider(imageryProvider);
        console.log('[StoryViewer] Imagery provider added successfully');

        // Enable terrain depth testing (objects behind terrain are hidden)
        viewer.scene.globe.depthTestAgainstTerrain = true;

        // Enable lighting for realistic sun shadows
        viewer.scene.globe.enableLighting = true;

        // Atmosphere
        viewer.scene.skyAtmosphere.show = true;

        console.log('[StoryViewer] CesiumJS viewer created');
        updateLoadingText('Initializing story engine...');

        // Initialize all modules with the viewer
        FlutterBridge.init();
        CameraController.init(viewer);
        SentinelLayer.init(viewer);
        DataOverlays.init(viewer);

        // Log WebNarrator status before ChapterManager init
        console.log('[StoryViewer] === WebNarrator Status ===');
        if (window.WebNarrator) {
            console.log('[StoryViewer] WebNarrator status:', WebNarrator.getStatus());
        } else {
            console.warn('[StoryViewer] WebNarrator not available!');
        }

        ChapterManager.init(viewer);

        // Initialize immersive 360° viewer (Pannellum)
        if (window.ImmersiveViewer) {
            ImmersiveViewer.init();
            console.log('[StoryViewer] ImmersiveViewer initialized');
        }

        // Initialize spatial audio (Howler.js)
        if (window.SpatialAudio) {
            SpatialAudio.init();
            console.log('[StoryViewer] SpatialAudio initialized');
        }

        // Listen for story config from Flutter
        console.log('[StoryViewer] Registering onStoryConfig callback...');
        FlutterBridge.on('onStoryConfig', (config) => {
            console.log('[StoryViewer] *** onStoryConfig CALLBACK TRIGGERED ***');
            console.log('[StoryViewer] Config received:', config);
            loadStory(config);
        });
        console.log('[StoryViewer] onStoryConfig callback registered');

        console.log('[StoryViewer] All modules initialized. Waiting for storyConfig from Flutter...');
        updateLoadingText('Waiting for story data...');
        FlutterBridge.onLoadingStateChange(false, 50);

        // Mark viewer as ready and process any pending config
        _viewerReady = true;
        if (_pendingConfig) {
            console.log('[StoryViewer] Processing pending config');
            loadStory(_pendingConfig);
            _pendingConfig = null;
        }

    } catch (error) {
        const msg = error?.message || error?.toString?.() || JSON.stringify(error);
        console.error('[StoryViewer] Initialization failed:', msg);
        console.error('[StoryViewer] Full error:', JSON.stringify(error, Object.getOwnPropertyNames(error || {})));
        console.error('[StoryViewer] Error stack:', error?.stack);
        updateLoadingText('Failed to load: ' + msg);
        FlutterBridge.onError('INIT_FAILED', msg);

        // FALLBACK: If CesiumJS fails (e.g. bad token, no WebGL), fall back to Leaflet
        console.warn('[StoryViewer] Falling back to Leaflet 2D map...');
        initLeafletFallback();
    }
}

function loadStory(config) {
    console.log('[StoryViewer] Loading story:', config.location?.name);

    // Check if we need user interaction for web platform
    const isWebPlatform = !window.flutter_inappwebview;
    const needsInteraction = isWebPlatform && window.WebNarrator && !WebNarrator._userInteracted;

    console.log('[StoryViewer] isWebPlatform:', isWebPlatform);
    console.log('[StoryViewer] needsInteraction:', needsInteraction);

    if (needsInteraction) {
        // Show "tap to begin" overlay
        showTapToBegin(config);
        return;
    }

    // Proceed with loading
    startStoryExperience(config);
}

function showTapToBegin(config) {
    console.log('[StoryViewer] Showing tap to begin overlay');

    const loadingScreen = document.getElementById('loadingScreen');
    if (loadingScreen) {
        const loadingText = loadingScreen.querySelector('.loading-text');
        const loadingSubtext = loadingScreen.querySelector('.loading-subtext');
        const spinner = loadingScreen.querySelector('.loading-spinner');

        if (spinner) spinner.style.display = 'none';
        if (loadingText) loadingText.textContent = config.location?.name || 'Story Ready';
        if (loadingSubtext) {
            loadingSubtext.innerHTML = `
                <div style="margin-top: 20px; cursor: pointer;">
                    <div style="font-size: 48px; margin-bottom: 16px;">🌿</div>
                    <div style="font-size: 18px; color: #00D26A; font-weight: 600;">Tap to Begin</div>
                    <div style="font-size: 12px; color: #6E7681; margin-top: 8px;">Enable immersive narration</div>
                </div>
            `;
        }

        // Click anywhere to start
        const startHandler = (e) => {
            console.log('[StoryViewer] User tapped - starting experience');

            // Mark as interacted for WebNarrator
            if (window.WebNarrator) {
                WebNarrator._userInteracted = true;
                console.log('[StoryViewer] WebNarrator userInteracted set to true');
            }

            // Remove listener and start
            loadingScreen.removeEventListener('click', startHandler);
            loadingScreen.removeEventListener('touchstart', startHandler);

            startStoryExperience(config);
        };

        loadingScreen.addEventListener('click', startHandler);
        loadingScreen.addEventListener('touchstart', startHandler, { passive: true });
    }
}

function startStoryExperience(config) {
    console.log('[StoryViewer] Starting story experience');

    // Hide loading screen
    const loadingScreen = document.getElementById('loadingScreen');
    if (loadingScreen) loadingScreen.classList.add('hidden');

    // Load story into chapter manager (which handles Sentinel, species, etc.)
    ChapterManager.loadStory(config);

    // Fly camera to story location
    if (config.location && config.location.lat && config.location.lng) {
        viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                config.location.lng,
                config.location.lat,
                50000 // Start from 50km altitude
            ),
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(-45),
                roll: 0
            },
            duration: 2
        });
    }

    // Start first chapter after camera arrives
    setTimeout(() => {
        ChapterManager.start();
        FlutterBridge.onLoadingStateChange(false, 100);
    }, 2500);
}

/**
 * Leaflet fallback for devices without WebGL / when CesiumJS fails
 * This preserves the existing 2D experience as a degraded fallback
 */
function initLeafletFallback() {
    // Dynamically load Leaflet
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(link);

    const script = document.createElement('script');
    script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    script.onload = () => {
        // Replace cesiumContainer with a Leaflet map
        const container = document.getElementById('cesiumContainer');
        container.id = 'mapContainer';

        const map = L.map('mapContainer', { zoomControl: false, attributionControl: false })
            .setView([0, 0], 2);
        L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
            maxZoom: 19
        }).addTo(map);

        // Re-init modules with Leaflet-compatible stubs
        CameraController.map = map;
        CameraController.viewer = null;
        CameraController.executePath = function(pathConfig) {
            if (!pathConfig.location) return;
            let zoom = 10;
            const alt = pathConfig.altitude || 50000;
            if (alt > 100000) zoom = 4;
            else if (alt > 50000) zoom = 6;
            else if (alt > 20000) zoom = 8;
            else if (alt > 8000) zoom = 10;
            else if (alt > 5000) zoom = 12;
            else zoom = 14;
            map.flyTo([pathConfig.location.lat, pathConfig.location.lng], zoom, {
                duration: pathConfig.duration || 2
            });
        };

        // ChapterManager already works with the DOM (chapter panel, dots, etc.)
        // It just won't have 3D features

        window.initStory = function(config) {
            if (typeof config === 'string') config = JSON.parse(config);
            document.getElementById('loadingScreen')?.classList.add('hidden');
            ChapterManager.loadStory(config);
            if (config.location) map.setView([config.location.lat, config.location.lng], 8);
            setTimeout(() => ChapterManager.start(), 300);
        };

        updateLoadingText('Ready (2D fallback mode)');
    };
    document.head.appendChild(script);
}

function updateLoadingText(text) {
    const el = document.getElementById('loadingSubtext');
    if (el) el.textContent = text;
}

window.onload = init;
