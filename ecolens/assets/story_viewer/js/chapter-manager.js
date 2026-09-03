/**
 * EcoLens Story Viewer - Chapter Manager
 * Handles chapter state, transitions, UI updates, and narrator-driven timing
 *
 * RENDERER MODES:
 * - 'cesium': CesiumJS for satellite/data chapters (default)
 * - 'pannellum': Pannellum for immersive 360° forest chapters
 */

// Forest panoramas from Poly Haven (CC0 license, equirectangular 360°)
// Each chapter gets a distinct forest scene for visual variety
const FOREST_PANORAMAS = {
    // Chapter: Introduction - Arrival at forest edge
    arrival: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/forest_slope.jpg',
    // Chapter: Discovery - Deep in the canopy discovering species
    discovery: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/forest_path.jpg',
    // Chapter: Immersive - Heart of the rainforest
    immersive: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/autumn_forest_01.jpg',
    // Chapter: Restoration - Hope, new growth, sunlight
    restoration: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/mossy_forest.jpg',
    // Fallback
    fallback: 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/forest_path.jpg'
};

// Audio for different moods - using Freesound CDN (CORS-friendly previews)
// These are CC0/CC-BY ambient nature sounds
const FOREST_AUDIO = {
    // Dawn ambience - morning birds chirping
    dawn: 'https://cdn.freesound.org/previews/531/531947_5674468-lq.mp3',
    // Dense jungle/forest - tropical rainforest ambience
    jungle: 'https://cdn.freesound.org/previews/467/467011_3905081-lq.mp3',
    // Peaceful forest - gentle wind through trees
    peaceful: 'https://cdn.freesound.org/previews/398/398632_4284968-lq.mp3'
};

const ChapterManager = {
    viewer: null,
    storyConfig: null,
    chapters: [],
    currentChapterIndex: -1,
    isPlaying: false,
    autoAdvanceTimer: null,

    // Renderer state
    _currentRenderer: 'cesium', // 'cesium' or 'pannellum'

    // Intro sequence state
    _introPlaying: false,
    _introComplete: false,

    // Narrator timing state
    _narratorFinished: false,
    _minimumTimeElapsed: false,
    _chapterStartTime: 0,
    _minimumDurationMs: 0,
    _narratorFallbackTimer: null,

    // UI element references
    ui: {
        panel: null,
        number: null,
        title: null,
        description: null,
        dataCards: null,
        indicator: null,
        prevBtn: null,
        nextBtn: null,
        speciesContainer: null,
        loadingScreen: null
    },

    /**
     * Initialize chapter manager
     */
    init(viewer) {
        this.viewer = viewer;
        this._cacheUIElements();
        this._setupKeyboardNav();

        // Initialize WebNarrator for web platforms
        if (window.WebNarrator) {
            WebNarrator.init();
            console.log('[ChapterManager] WebNarrator initialized for web narration');
        }
    },

    /**
     * Check if we're running on web (standalone page, not in InAppWebView)
     */
    _isWebPlatform() {
        // If flutter_inappwebview is available, we're in mobile app
        const isWeb = !window.flutter_inappwebview;
        console.log('[ChapterManager] _isWebPlatform check:', isWeb, '(flutter_inappwebview:', !!window.flutter_inappwebview, ')');
        return isWeb;
    },

    /**
     * Narrate text - uses WebNarrator on web, Flutter TTS on mobile
     */
    _narrate(chapterIndex, text, title, onComplete) {
        console.log('[ChapterManager] === _narrate() called ===');
        console.log('[ChapterManager] Chapter index:', chapterIndex);
        console.log('[ChapterManager] Title:', title);
        console.log('[ChapterManager] Text length:', text?.length || 0);

        if (!text || text.trim() === '') {
            console.log('[ChapterManager] Empty text, skipping narration');
            if (onComplete) onComplete();
            return;
        }

        const isWeb = this._isWebPlatform();
        const hasWebNarrator = !!window.WebNarrator;
        const webNarratorAvailable = hasWebNarrator && WebNarrator.isAvailable();

        console.log('[ChapterManager] isWeb:', isWeb);
        console.log('[ChapterManager] hasWebNarrator:', hasWebNarrator);
        console.log('[ChapterManager] webNarratorAvailable:', webNarratorAvailable);

        // On web, use WebNarrator (browser Speech API)
        if (isWeb && hasWebNarrator && webNarratorAvailable) {
            console.log('[ChapterManager] ✓ Using WebNarrator for:', title || `Chapter ${chapterIndex}`);
            WebNarrator.speak(text, () => {
                console.log('[ChapterManager] WebNarrator callback - finished');
                if (onComplete) onComplete();
                // Also call narratorFinished to trigger chapter advance
                this.narratorFinished(chapterIndex);
            });
            return;
        }

        console.log('[ChapterManager] Not using WebNarrator, falling back to Flutter TTS');

        // On mobile, notify Flutter to use native TTS
        if (window.FlutterBridge) {
            console.log('[ChapterManager] Notifying Flutter for TTS');
            FlutterBridge.notifyFlutter('narrateChapter', {
                chapter: chapterIndex,
                text: text,
                title: title
            });
        } else {
            console.log('[ChapterManager] No FlutterBridge available');
        }
    },

    /**
     * Cache UI element references
     */
    _cacheUIElements() {
        this.ui.panel = document.getElementById('chapterPanel');
        this.ui.number = document.getElementById('chapterNumber');
        this.ui.title = document.getElementById('chapterTitle');
        this.ui.description = document.getElementById('chapterDescription');
        this.ui.dataCards = document.getElementById('dataCards');
        this.ui.indicator = document.getElementById('chapterIndicator');
        this.ui.prevBtn = document.getElementById('prevBtn');
        this.ui.nextBtn = document.getElementById('nextBtn');
        this.ui.speciesContainer = document.getElementById('speciesContainer');
        this.ui.loadingScreen = document.getElementById('loadingScreen');
    },

    /**
     * Setup keyboard navigation
     */
    _setupKeyboardNav() {
        document.addEventListener('keydown', (e) => {
            switch (e.key) {
                case 'ArrowRight':
                case ' ':
                    e.preventDefault();
                    this.nextChapter();
                    break;
                case 'ArrowLeft':
                    e.preventDefault();
                    this.previousChapter();
                    break;
                case 'Escape':
                    this.closeStory();
                    break;
            }
        });
    },

    /**
     * Load story configuration
     */
    loadStory(storyConfig) {
        this.storyConfig = storyConfig;

        // Log what data we received from backend
        console.log('[ChapterManager] === STORY DATA RECEIVED ===');
        console.log('[ChapterManager] Location:', storyConfig.location?.name || 'MISSING');
        console.log('[ChapterManager] Metrics:', JSON.stringify(storyConfig.metrics || {}));
        console.log('[ChapterManager] Species POIs:', storyConfig.speciesPOIs?.length || 0);
        console.log('[ChapterManager] Sentinel imagery:', storyConfig.sentinelImagery?.available ? 'AVAILABLE' : 'unavailable');
        console.log('[ChapterManager] Chapters from backend:', storyConfig.chapters?.length || 0);
        console.log('[ChapterManager] Panorama config:', storyConfig.panorama ? 'PROVIDED' : 'missing (using defaults)');

        // Get chapters from config or generate defaults
        let chapters = storyConfig.chapters || this._generateDefaultChapters();

        // Ensure immersive chapters have proper panorama configs
        // Also inject immersive chapter if completely missing
        const hasImmersive = chapters.some(c => c.renderer === 'pannellum' || c.id === 'immersive');
        if (!hasImmersive) {
            console.log('[ChapterManager] Injecting immersive 360° chapter');
            const immersiveChapter = {
                id: 'immersive',
                title: 'Into the Forest',
                narrative: 'Step into the heart of the rainforest. Look around you. Listen to the sounds of life that fill this ancient woodland.',
                renderer: 'pannellum',
                panorama: {
                    imageUrl: storyConfig.panorama?.imageUrl || FOREST_PANORAMAS.immersive,
                    pitch: 0,
                    yaw: 0,
                    hfov: 100,
                    hotspots: this._generatePanoramaHotspots()
                },
                soundscape: {
                    ambientUrl: storyConfig.panorama?.ambientUrl || FOREST_AUDIO.jungle,
                    ambientVolume: 0.6
                },
                gyroscope: true,
                dataCards: [
                    { label: 'Experience', value: '360° View', class: 'positive' }
                ]
            };

            // Insert after 'discovery' chapter, or at position 2
            const discoveryIndex = chapters.findIndex(c => c.id === 'discovery');
            if (discoveryIndex >= 0) {
                chapters.splice(discoveryIndex + 1, 0, immersiveChapter);
            } else {
                chapters.splice(2, 0, immersiveChapter);
            }
        }

        // Upgrade existing chapters to immersive if they should be
        chapters.forEach(chapter => {
            // Add panorama config to immersive chapters that don't have one
            if (chapter.renderer === 'pannellum' && !chapter.panorama) {
                chapter.panorama = {
                    imageUrl: FOREST_PANORAMAS[chapter.id] || FOREST_PANORAMAS.fallback,
                    pitch: 0,
                    yaw: 0,
                    hfov: 100,
                    hotspots: chapter.showSpecies ? this._generatePanoramaHotspots() : []
                };
            }
            // Add soundscape if missing
            if (chapter.renderer === 'pannellum' && !chapter.soundscape) {
                chapter.soundscape = {
                    ambientUrl: FOREST_AUDIO.jungle,
                    ambientVolume: 0.5
                };
            }
            // Enable gyroscope by default for immersive
            if (chapter.renderer === 'pannellum' && chapter.gyroscope === undefined) {
                chapter.gyroscope = true;
            }
        });

        this.chapters = chapters;

        // Build chapter indicators
        this._buildChapterIndicators();

        // Add Sentinel imagery if available
        if (storyConfig.sentinelImagery && window.SentinelLayer) {
            SentinelLayer.addImagery(
                storyConfig.sentinelImagery,
                storyConfig.location
            );
        }

        // Add species POIs
        if (storyConfig.speciesPOIs && window.DataOverlays) {
            DataOverlays.addSpeciesPOIs(
                storyConfig.speciesPOIs,
                storyConfig.location
            );
        }

        console.log(`[ChapterManager] Loaded story with ${this.chapters.length} chapters`);
    },

    /**
     * Generate default chapters - mix of immersive 360° and satellite views
     * Immersive chapters: introduction, discovery, immersive, restoration
     * Data chapters: temporal, impact (need satellite imagery)
     */
    _generateDefaultChapters() {
        const location = this.storyConfig?.location || { name: 'This Region' };
        const metrics = this.storyConfig?.metrics || {};
        const speciesCount = this.storyConfig?.speciesPOIs?.length || 0;

        return [
            // IMMERSIVE: Arrival at the forest edge
            {
                id: 'introduction',
                title: 'Arrival',
                narrative: `Welcome to ${location.name}. You stand at the edge of one of Earth's most critical ecosystems, home to thousands of species found nowhere else on the planet.`,
                renderer: 'pannellum',
                panorama: {
                    imageUrl: this.storyConfig?.panorama?.imageUrl || FOREST_PANORAMAS.arrival,
                    pitch: 5,
                    yaw: 0,
                    hfov: 110
                },
                soundscape: {
                    ambientUrl: FOREST_AUDIO.dawn,
                    ambientVolume: 0.5
                },
                gyroscope: true,
                dataCards: [
                    { label: 'Location', value: location.name?.split(',')[0] || 'Region' },
                    { label: 'Coordinates', value: `${location.lat?.toFixed(2)}°, ${location.lng?.toFixed(2)}°` }
                ]
            },
            // IMMERSIVE: Deep in the forest discovering species
            {
                id: 'discovery',
                title: 'The Species',
                narrative: 'Look around you. The wildlife that calls this place home depends on every tree, every stream, every inch of this ecosystem.',
                renderer: 'pannellum',
                panorama: {
                    imageUrl: FOREST_PANORAMAS.discovery,
                    pitch: 0,
                    yaw: -30,
                    hfov: 100,
                    hotspots: this._generatePanoramaHotspots()
                },
                soundscape: {
                    ambientUrl: FOREST_AUDIO.jungle,
                    ambientVolume: 0.6
                },
                gyroscope: true,
                showSpecies: true,
                dataCards: [
                    { label: 'Species at Risk', value: speciesCount, class: 'risk-high' }
                ]
            },
            // IMMERSIVE: Heart of the rainforest - main immersive experience
            {
                id: 'immersive',
                title: 'Into the Forest',
                narrative: 'Step into the heart of the rainforest. Listen to the sounds of life that fill this ancient woodland. Every creature here plays a role in this delicate balance.',
                renderer: 'pannellum',
                panorama: {
                    imageUrl: this.storyConfig?.panorama?.imageUrl || FOREST_PANORAMAS.immersive,
                    pitch: 0,
                    yaw: 0,
                    hfov: 100,
                    hotspots: this._generatePanoramaHotspots()
                },
                soundscape: {
                    ambientUrl: this.storyConfig?.panorama?.ambientUrl || FOREST_AUDIO.jungle,
                    ambientVolume: 0.7
                },
                gyroscope: true,
                dataCards: [
                    { label: 'Experience', value: '360° View', class: 'positive' }
                ]
            },
            // SATELLITE: Show deforestation data - needs CesiumJS
            {
                id: 'temporal',
                title: 'What Happened',
                narrative: 'Witness the transformation from above. Satellite imagery reveals the scars of deforestation spreading through this once-pristine landscape.',
                renderer: 'cesium',
                cameraPath: {
                    type: 'descent',
                    startAltitude: 5000,
                    endAltitude: 1000,
                    pitch: -60,
                    endPitch: -45,
                    duration: 5
                },
                showTimelapse: true,
                dataCards: [
                    { label: 'Risk Level', value: `${metrics.riskScore || 0}%`, class: metrics.riskScore > 70 ? 'risk-high' : 'risk-medium' }
                ]
            },
            // SATELLITE: Impact data visualization - needs CesiumJS
            {
                id: 'impact',
                title: 'The Impact',
                narrative: 'The effects extend far beyond the forest. Communities lose their livelihoods. The climate loses a vital carbon sink.',
                renderer: 'cesium',
                cameraPath: {
                    type: 'pullback',
                    altitude: 3000,
                    pitch: -30,
                    duration: 4
                },
                dataCards: [
                    { label: 'People Affected', value: (metrics.population || 0).toLocaleString() },
                    { label: 'Carbon Loss', value: `${((metrics.carbonStock || 0) / 1000).toFixed(0)}k t` }
                ]
            },
            // IMMERSIVE: Hope and restoration - back in the forest
            {
                id: 'restoration',
                title: 'The Hope',
                narrative: 'But there is hope. With intervention, this land can heal. The forest can return. New growth reaches toward the light. The future is not yet written.',
                renderer: 'pannellum',
                panorama: {
                    imageUrl: FOREST_PANORAMAS.restoration,
                    pitch: 10,
                    yaw: 45,
                    hfov: 100
                },
                soundscape: {
                    ambientUrl: FOREST_AUDIO.peaceful,
                    ambientVolume: 0.5
                },
                gyroscope: true,
                dataCards: [
                    { label: 'Potential', value: 'Recovery Possible', class: 'positive' },
                    { label: 'Timeline', value: '5-10 years', class: 'positive' }
                ]
            }
        ];
    },

    /**
     * Build chapter indicator dots
     */
    _buildChapterIndicators() {
        if (!this.ui.indicator) return;

        this.ui.indicator.innerHTML = '';
        this.chapters.forEach((chapter, index) => {
            const dot = document.createElement('div');
            dot.className = 'chapter-dot';
            dot.title = chapter.title;
            dot.onclick = () => this.goToChapter(index);
            this.ui.indicator.appendChild(dot);
        });
    },

    /**
     * Start the story - plays intro sequence first, then chapters
     */
    start() {
        this.isPlaying = true;
        this._introComplete = false;

        // Play intro sequence before starting Chapter 1
        this._playIntroSequence();
    },

    /**
     * Play the intro sequence (Chapter 0) before real chapters begin
     */
    _playIntroSequence() {
        this._introPlaying = true;
        const location = this.storyConfig?.location || { name: 'This Region' };

        console.log('[ChapterManager] Starting intro sequence');

        // Show loading screen with intro text
        if (this.ui.loadingScreen) {
            this.ui.loadingScreen.classList.remove('hidden');

            // Update loading text to welcome message
            const loadingText = this.ui.loadingScreen.querySelector('.loading-text');
            const loadingSubtext = this.ui.loadingScreen.querySelector('.loading-subtext');

            if (loadingText) {
                loadingText.textContent = `Welcome to ${location.name}`;
            }
            if (loadingSubtext) {
                loadingSubtext.textContent = 'Preparing your immersive journey...';
            }
        }

        // Position camera high up (50km) for intro
        if (this.viewer && this.storyConfig?.location) {
            const loc = this.storyConfig.location;
            this.viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(loc.lng, loc.lat, 50000),
                orientation: {
                    heading: 0,
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0
                }
            });

            // Start slow descent during intro
            this.viewer.camera.flyTo({
                destination: Cesium.Cartesian3.fromDegrees(loc.lng, loc.lat, 15000),
                orientation: {
                    heading: Cesium.Math.toRadians(30),
                    pitch: Cesium.Math.toRadians(-35),
                    roll: 0
                },
                duration: 8
            });
        }

        // Build intro narrative
        const introText = this._buildIntroNarrative(location);

        // Narrate intro (uses WebNarrator on web, Flutter TTS on mobile)
        this._narrate(-1, introText, 'Introduction', () => {
            // This callback is for web narration completion
            // Mobile uses narratorFinished() callback from Flutter
        });

        // Set fallback timer based on intro text length
        // TTS uses slow speech rate (0.42) = ~1 word/second
        const wordCount = introText.split(/\s+/).length;
        const estimatedSpeakingMs = (wordCount / 1.0) * 1000;
        const fallbackMs = Math.max(estimatedSpeakingMs + 3000, 15000);

        this._narratorFallbackTimer = setTimeout(() => {
            if (this._introPlaying) {
                console.log('[ChapterManager] Intro fallback timer triggered');
                this._onIntroComplete();
            }
        }, fallbackMs);
    },

    /**
     * Build intro narrative based on location
     */
    _buildIntroNarrative(location) {
        const name = location.name || 'this region';
        const metrics = this.storyConfig?.metrics || {};
        const speciesCount = this.storyConfig?.speciesPOIs?.length || 0;

        // Check region type for customized intro
        const lat = location.lat || 0;
        const lng = location.lng || 0;

        let regionDescription = '';
        if (lat >= -20 && lat <= 10 && lng >= -80 && lng <= -34) {
            regionDescription = 'the Amazon Basin, the lungs of our planet';
        } else if (lat >= -10 && lat <= 10 && lng >= 10 && lng <= 35) {
            regionDescription = 'the Congo rainforest, Africa\'s green heart';
        } else if (lat >= -10 && lat <= 25 && lng >= 90 && lng <= 150) {
            regionDescription = 'Southeast Asia\'s tropical forests';
        } else {
            regionDescription = 'one of Earth\'s vital ecosystems';
        }

        return `Welcome to ${name}. You are entering ${regionDescription}. ` +
               `This is home to ${speciesCount > 0 ? speciesCount + ' documented species at risk' : 'countless species'}, ` +
               `many found nowhere else on Earth. ` +
               `What you are about to witness tells the story of this land—its beauty, its struggle, and its hope for the future.`;
    },

    /**
     * Called when intro narration finishes
     */
    narratorFinished(chapterIndex) {
        // Handle intro (chapter -1)
        if (chapterIndex === -1) {
            console.log('[ChapterManager] Intro narration finished');
            this._onIntroComplete();
            return;
        }

        // Only accept if it's for the current chapter
        if (chapterIndex !== this.currentChapterIndex) return;

        console.log('[ChapterManager] Narrator finished chapter', chapterIndex + 1);
        this._narratorFinished = true;

        // Clear the fallback timer
        if (this._narratorFallbackTimer) {
            clearTimeout(this._narratorFallbackTimer);
            this._narratorFallbackTimer = null;
        }

        // Try to advance (will wait if minimum time hasn't elapsed)
        this._tryAdvance();
    },

    /**
     * Called when intro sequence completes
     */
    _onIntroComplete() {
        if (this._introComplete) return;

        this._introComplete = true;
        this._introPlaying = false;

        // Clear fallback timer
        if (this._narratorFallbackTimer) {
            clearTimeout(this._narratorFallbackTimer);
            this._narratorFallbackTimer = null;
        }

        console.log('[ChapterManager] Intro complete, starting Chapter 1');

        // Hide loading screen
        if (this.ui.loadingScreen) {
            this.ui.loadingScreen.classList.add('hidden');
        }

        // Small delay before starting Chapter 1
        setTimeout(() => {
            this.goToChapter(0);
        }, 500);
    },

    /**
     * Go to a specific chapter with narrator-driven timing
     */
    async goToChapter(index) {
        if (index < 0 || index >= this.chapters.length) return;

        // Stop any pending advance timers
        if (this.autoAdvanceTimer) {
            clearTimeout(this.autoAdvanceTimer);
            this.autoAdvanceTimer = null;
        }
        if (this._narratorFallbackTimer) {
            clearTimeout(this._narratorFallbackTimer);
            this._narratorFallbackTimer = null;
        }

        // Stop current narration when switching chapters
        if (window.WebNarrator) {
            WebNarrator.stop();
        }

        // Reset timing state
        this._narratorFinished = false;
        this._minimumTimeElapsed = false;
        this._chapterStartTime = Date.now();

        const prevIndex = this.currentChapterIndex;
        this.currentChapterIndex = index;
        const chapter = this.chapters[index];

        // Determine required renderer
        const requiredRenderer = chapter.renderer || 'cesium';

        // Handle renderer switching
        if (requiredRenderer === 'pannellum' && this._currentRenderer !== 'pannellum') {
            await this._switchToPannellum(chapter);
        } else if (requiredRenderer === 'cesium' && this._currentRenderer !== 'cesium') {
            await this._switchToCesium();
        }

        // Calculate minimum duration - longer for immersive chapters
        if (requiredRenderer === 'pannellum') {
            this._minimumDurationMs = 15000; // 15s minimum for immersive exploration
        } else {
            const cameraDuration = (chapter.cameraPath?.duration || 3) * 1000;
            this._minimumDurationMs = cameraDuration + 1000;
        }

        // Update UI
        this._updateIndicators(index);
        this._updateNavButtons(index);

        // Fade out panel
        if (this.ui.panel) {
            this.ui.panel.classList.remove('visible');
        }

        // Execute camera action (only for CesiumJS chapters)
        if (requiredRenderer === 'cesium' && chapter.cameraPath && window.CameraController) {
            CameraController.executePath({
                ...chapter.cameraPath,
                location: this.storyConfig.location
            });
        }

        // Update panel content after brief animation delay
        setTimeout(() => {
            this._executeChapterActions(chapter, prevIndex);
            this._updatePanel(chapter, index);
        }, 300);

        // Start minimum duration timer
        setTimeout(() => {
            this._minimumTimeElapsed = true;
            this._tryAdvance();
        }, this._minimumDurationMs);

        // Notify Flutter of chapter change
        if (window.FlutterBridge) {
            FlutterBridge.onChapterChanged(index, chapter);
        }

        // Narrate the chapter (uses WebNarrator on web, Flutter TTS on mobile)
        const narrativeText = chapter.narrative || chapter.description || '';
        this._narrate(index, narrativeText, chapter.title, () => {
            // This callback is for web narration completion
            // Mobile uses narratorFinished() callback from Flutter
        });

        // FALLBACK: Estimate reading time from text length if no TTS callback received
        // TTS uses slow speech rate (0.42) for documentary style = ~1 word/second
        // Normal rate ~2.5 words/sec, but at 0.42 rate it's ~1 word/sec
        const wordCount = narrativeText.split(/\s+/).length;
        const estimatedSpeakingMs = (wordCount / 1.0) * 1000; // 1 word per second for slow narration
        // Add 3s buffer for pauses, completion delay, and margin of safety
        const fallbackMs = Math.max(estimatedSpeakingMs + 3000, 8000);

        this._narratorFallbackTimer = setTimeout(() => {
            if (!this._narratorFinished) {
                console.log('[ChapterManager] Narrator fallback — estimated time elapsed');
                this._narratorFinished = true;
                this._tryAdvance();
            }
        }, fallbackMs);
    },

    /**
     * Only advances when BOTH narrator is done AND minimum camera time has passed.
     */
    _tryAdvance() {
        if (!this._narratorFinished || !this._minimumTimeElapsed) return;
        if (!this.isPlaying) return;

        // Don't auto-advance on the last chapter
        if (this.currentChapterIndex >= this.chapters.length - 1) {
            if (window.FlutterBridge) {
                FlutterBridge.onStoryComplete();
            }
            return;
        }

        // Brief pause so the last words land before transitioning
        this.autoAdvanceTimer = setTimeout(() => {
            this.nextChapter();
        }, 1500);
    },

    /**
     * Execute chapter-specific actions including Sentinel timelapse
     */
    _executeChapterActions(chapter, prevIndex) {
        console.log('[ChapterManager] Executing actions for chapter:', chapter.id);
        console.log('[ChapterManager] Chapter renderer:', chapter.renderer || 'cesium');
        console.log('[ChapterManager] Panorama config:', this.storyConfig?.panorama);
        console.log('[ChapterManager] ImmersiveViewer available:', !!window.ImmersiveViewer);
        console.log('[ChapterManager] Current renderer:', this._currentRenderer);

        // Species visibility
        if (window.DataOverlays) {
            if (chapter.showSpecies) {
                DataOverlays.setSpeciesVisible(true);
                DataOverlays.animateSpeciesIn();
            } else {
                DataOverlays.setSpeciesVisible(false);
            }
        }

        // Sentinel before/after timelapse — INSIDE the story, not a separate toggle
        if (chapter.showTimelapse && window.SentinelLayer) {
            // Start at "before" state
            SentinelLayer.showBefore();

            // After 2 seconds (user sees "before"), animate to "after"
            setTimeout(() => {
                SentinelLayer.animateTimelapse(4000);
                // After timelapse completes, optionally show NDVI
                setTimeout(() => {
                    SentinelLayer.showNDVI(true);
                }, 4500);
            }, 2000);
        }

        // Chapters without timelapse — ensure Sentinel is in correct state
        if (!chapter.showTimelapse && window.SentinelLayer) {
            // "Arrival" and "Discovery": show "before" (healthy) state
            if (chapter.id === 'introduction' || chapter.id === 'discovery') {
                SentinelLayer.showBefore();
                SentinelLayer.showNDVI(false);
            }
            // "Impact" and "Restoration": stay on "after" state
            if (chapter.id === 'impact' || chapter.id === 'restoration') {
                SentinelLayer.showAfter();
                SentinelLayer.showNDVI(false);
            }
        }

        // Species cards in UI sidebar
        if (chapter.showSpecies) {
            this._showSpeciesCards();
        } else {
            this._hideSpeciesCards();
        }
    },

    /**
     * Update chapter panel UI
     */
    _updatePanel(chapter, index) {
        if (this.ui.number) {
            this.ui.number.textContent = `CHAPTER ${index + 1}`;
        }
        if (this.ui.title) {
            this.ui.title.textContent = chapter.title;
        }
        if (this.ui.description) {
            this.ui.description.textContent = chapter.narrative || chapter.description;
        }

        // Update data cards
        this._updateDataCards(chapter.dataCards);

        // Show panel
        if (this.ui.panel) {
            this.ui.panel.classList.add('visible');
        }
    },

    /**
     * Update indicator dots
     */
    _updateIndicators(activeIndex) {
        if (!this.ui.indicator) return;

        const dots = this.ui.indicator.querySelectorAll('.chapter-dot');
        dots.forEach((dot, i) => {
            dot.classList.toggle('active', i === activeIndex);
        });
    },

    /**
     * Update navigation buttons
     */
    _updateNavButtons(index) {
        if (this.ui.prevBtn) {
            this.ui.prevBtn.disabled = index === 0;
        }
        if (this.ui.nextBtn) {
            this.ui.nextBtn.disabled = index === this.chapters.length - 1;
        }
    },

    /**
     * Update data cards
     */
    _updateDataCards(cards) {
        if (!this.ui.dataCards || !cards) return;

        this.ui.dataCards.innerHTML = '';
        cards.forEach(card => {
            const div = document.createElement('div');
            div.className = 'data-card';
            div.innerHTML = `
                <div class="data-card-label">${card.label}</div>
                <div class="data-card-value ${card.class || ''}">${card.value}</div>
            `;
            this.ui.dataCards.appendChild(div);
        });
    },

    /**
     * Show species cards in side panel
     */
    _showSpeciesCards() {
        if (!this.ui.speciesContainer) return;

        this.ui.speciesContainer.innerHTML = '';
        this.ui.speciesContainer.style.display = 'flex';

        const species = this.storyConfig?.speciesPOIs || [];
        species.forEach((s, index) => {
            const card = document.createElement('div');
            card.className = 'species-card';
            card.innerHTML = `
                <div class="species-icon">${s.icon || this._getSpeciesIcon(s.category)}</div>
                <div class="species-info">
                    <h4>${s.name || s.common_name}</h4>
                    <span class="species-status ${this._getStatusClass(s.conservation_status || s.status)}">
                        ${s.conservation_status || s.status}
                    </span>
                </div>
            `;

            this.ui.speciesContainer.appendChild(card);

            // Animate in with delay
            setTimeout(() => {
                card.classList.add('visible');
            }, 200 + (index * 150));
        });
    },

    /**
     * Hide species cards
     */
    _hideSpeciesCards() {
        if (this.ui.speciesContainer) {
            this.ui.speciesContainer.style.display = 'none';
        }
    },

    /**
     * Get species icon by category
     */
    _getSpeciesIcon(category) {
        const icons = {
            'mammal': '🐾',
            'bird': '🦅',
            'reptile': '🦎',
            'fish': '🐟',
            'plant': '🌿',
            'fauna': '🐾',
            'flora': '🌿'
        };
        return icons[category?.toLowerCase()] || '🌍';
    },

    /**
     * Get status CSS class
     */
    _getStatusClass(status) {
        if (!status) return '';
        const s = status.toLowerCase();
        if (s.includes('critically') || s.includes('endangered')) return 'endangered';
        if (s.includes('vulnerable')) return 'vulnerable';
        return '';
    },

    /**
     * Generate panorama hotspots from species POIs
     */
    _generatePanoramaHotspots() {
        const species = this.storyConfig?.speciesPOIs || [];
        if (species.length === 0) return [];

        // Distribute species around the 360° view
        return species.slice(0, 6).map((s, index) => {
            const yaw = (index * 60) - 150; // Spread around the view
            const pitch = (index % 2 === 0) ? -10 : 15; // Alternate heights

            return {
                id: s.id || `species-${index}`,
                name: s.name || s.common_name,
                status: s.conservation_status || s.status,
                icon: s.icon || this._getSpeciesIcon(s.category),
                pitch: pitch,
                yaw: yaw,
                soundUrl: s.soundUrl || null
            };
        });
    },

    /**
     * Switch to immersive Pannellum renderer
     */
    async _switchToPannellum(chapter) {
        if (this._currentRenderer === 'pannellum') return;

        console.log('[ChapterManager] Switching to Pannellum renderer');

        // Enter immersive mode with ImmersiveViewer
        if (window.ImmersiveViewer) {
            const config = {
                imageUrl: chapter.panorama?.imageUrl,
                pitch: chapter.panorama?.pitch || 0,
                yaw: chapter.panorama?.yaw || 0,
                hfov: chapter.panorama?.hfov || 100,
                hotspots: chapter.panorama?.hotspots || [],
                gyroscope: chapter.gyroscope !== false
            };

            await ImmersiveViewer.enterImmersiveMode(config);

            // Setup hotspot click handler
            ImmersiveViewer.onHotspotClick((hotspot) => {
                this._onPanoramaHotspotClick(hotspot);
            });
        }

        // Start spatial audio
        if (window.SpatialAudio && chapter.soundscape) {
            SpatialAudio.loadSoundscape(chapter.soundscape);
            SpatialAudio.fadeIn(2000);
        }

        this._currentRenderer = 'pannellum';
    },

    /**
     * Switch back to CesiumJS renderer
     */
    async _switchToCesium() {
        if (this._currentRenderer === 'cesium') return;

        console.log('[ChapterManager] Switching to CesiumJS renderer');

        // Fade out spatial audio first
        if (window.SpatialAudio) {
            SpatialAudio.fadeOut(1500);
        }

        // Exit immersive mode
        if (window.ImmersiveViewer) {
            await ImmersiveViewer.exitImmersiveMode();
        }

        this._currentRenderer = 'cesium';
    },

    /**
     * Handle hotspot click in panorama mode
     */
    _onPanoramaHotspotClick(hotspot) {
        console.log('[ChapterManager] Panorama hotspot clicked:', hotspot.name);

        // Trigger haptic feedback
        if (window.FlutterBridge) {
            FlutterBridge.notifyFlutter('haptic', { type: 'light' });

            // Show species card in Flutter UI
            FlutterBridge.notifyFlutter('speciesSelected', {
                id: hotspot.id,
                name: hotspot.name,
                status: hotspot.status,
                icon: hotspot.icon
            });
        }

        // Play species sound at position
        if (window.SpatialAudio && hotspot.soundUrl) {
            SpatialAudio.triggerSpeciesCall(hotspot);
        }
    },

    /**
     * Go to next chapter
     */
    nextChapter() {
        if (this.currentChapterIndex < this.chapters.length - 1) {
            this.goToChapter(this.currentChapterIndex + 1);
        } else {
            // Story complete
            if (window.FlutterBridge) {
                FlutterBridge.onStoryComplete();
            }
        }
    },

    /**
     * Go to previous chapter
     */
    previousChapter() {
        if (this.currentChapterIndex > 0) {
            this.goToChapter(this.currentChapterIndex - 1);
        }
    },

    /**
     * Close story and notify Flutter
     */
    async closeStory() {
        this.isPlaying = false;
        if (this.autoAdvanceTimer) {
            clearTimeout(this.autoAdvanceTimer);
        }
        if (this._narratorFallbackTimer) {
            clearTimeout(this._narratorFallbackTimer);
        }

        // Stop web narrator if active
        if (window.WebNarrator) {
            WebNarrator.stop();
        }

        // Clean up immersive mode if active
        if (this._currentRenderer === 'pannellum') {
            if (window.SpatialAudio) {
                SpatialAudio.fadeOut(500);
            }
            if (window.ImmersiveViewer) {
                await ImmersiveViewer.exitImmersiveMode();
            }
            this._currentRenderer = 'cesium';
        }

        if (window.FlutterBridge) {
            FlutterBridge.onCloseRequest();
        }
    },

    /**
     * Pause playback
     */
    pause() {
        this.isPlaying = false;
        if (this.autoAdvanceTimer) {
            clearTimeout(this.autoAdvanceTimer);
        }
    },

    /**
     * Resume playback
     */
    resume() {
        this.isPlaying = true;
    },

    /**
     * Get current chapter data
     */
    getCurrentChapter() {
        return this.chapters[this.currentChapterIndex];
    },

    /**
     * Get progress percentage
     */
    getProgress() {
        return (this.currentChapterIndex + 1) / this.chapters.length;
    }
};

// Make globally available
window.ChapterManager = ChapterManager;
