/**
 * EcoLens Story Viewer - Library Loader
 * Handles loading of external libraries with local fallback
 * Ensures Pannellum, Howler, and CesiumJS are available before init
 */

const LibraryLoader = {
    // Track loading state
    _loaded: {
        cesium: false,
        pannellum: false,
        howler: false
    },

    // CDN URLs
    _cdnUrls: {
        pannellumJs: 'https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js',
        pannellumCss: 'https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css',
        howler: 'https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js',
        cesiumJs: 'https://cesium.com/downloads/cesiumjs/releases/1.114/Build/Cesium/Cesium.js',
        cesiumCss: 'https://cesium.com/downloads/cesiumjs/releases/1.114/Build/Cesium/Widgets/widgets.css'
    },

    // CDN fallback URLs (if local files fail)
    _cdnFallbackUrls: {
        pannellumJs: 'https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.js',
        pannellumCss: 'https://cdn.jsdelivr.net/npm/pannellum@2.5.6/build/pannellum.css',
        howler: 'https://cdn.jsdelivr.net/npm/howler@2.2.4/dist/howler.min.js'
    },

    /**
     * Check if all required libraries are loaded
     */
    checkLibraries() {
        const cesiumOk = typeof Cesium !== 'undefined';
        const pannellumOk = typeof pannellum !== 'undefined';
        const howlerOk = typeof Howl !== 'undefined';

        console.log('[LibraryLoader] === Library Status ===');
        console.log('[LibraryLoader] CesiumJS:', cesiumOk ? 'LOADED' : 'MISSING');
        console.log('[LibraryLoader] Pannellum:', pannellumOk ? 'LOADED' : 'MISSING');
        console.log('[LibraryLoader] Howler:', howlerOk ? 'LOADED' : 'MISSING');

        this._loaded.cesium = cesiumOk;
        this._loaded.pannellum = pannellumOk;
        this._loaded.howler = howlerOk;

        return { cesium: cesiumOk, pannellum: pannellumOk, howler: howlerOk };
    },

    /**
     * Attempt to load missing libraries from CDN fallback
     */
    async loadMissingLibraries() {
        const status = this.checkLibraries();
        const promises = [];

        // Load Pannellum if missing (try CDN fallback)
        if (!status.pannellum) {
            console.log('[LibraryLoader] Attempting CDN fallback for Pannellum...');
            promises.push(this._loadScript(this._cdnFallbackUrls.pannellumJs, 'pannellum'));
            promises.push(this._loadCss(this._cdnFallbackUrls.pannellumCss));
        }

        // Load Howler if missing (try CDN fallback)
        if (!status.howler) {
            console.log('[LibraryLoader] Attempting CDN fallback for Howler...');
            promises.push(this._loadScript(this._cdnFallbackUrls.howler, 'howler'));
        }

        if (promises.length > 0) {
            try {
                await Promise.all(promises);
                console.log('[LibraryLoader] CDN fallback loading complete');
            } catch (e) {
                console.error('[LibraryLoader] Failed to load some libraries:', e);
            }
        }

        // Re-check after loading attempts
        return this.checkLibraries();
    },

    /**
     * Load a script from URL
     */
    _loadScript(url, name) {
        return new Promise((resolve, reject) => {
            // Check if already loaded
            if (name === 'pannellum' && typeof pannellum !== 'undefined') {
                resolve();
                return;
            }
            if (name === 'howler' && typeof Howl !== 'undefined') {
                resolve();
                return;
            }

            const script = document.createElement('script');
            script.src = url;
            script.onload = () => {
                console.log(`[LibraryLoader] Loaded ${name} from ${url}`);
                resolve();
            };
            script.onerror = (e) => {
                console.warn(`[LibraryLoader] Failed to load ${name} from ${url}`);
                // Don't reject - we'll check availability later
                resolve();
            };
            document.head.appendChild(script);
        });
    },

    /**
     * Load a CSS file from URL
     */
    _loadCss(url) {
        return new Promise((resolve) => {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = url;
            link.onload = () => {
                console.log(`[LibraryLoader] Loaded CSS from ${url}`);
                resolve();
            };
            link.onerror = () => {
                console.warn(`[LibraryLoader] Failed to load CSS from ${url}`);
                resolve();
            };
            document.head.appendChild(link);
        });
    },

    /**
     * Get human-readable status for debugging
     */
    getStatusMessage() {
        const status = this.checkLibraries();
        const missing = [];

        if (!status.cesium) missing.push('CesiumJS');
        if (!status.pannellum) missing.push('Pannellum');
        if (!status.howler) missing.push('Howler');

        if (missing.length === 0) {
            return 'All libraries loaded successfully';
        }
        return `Missing libraries: ${missing.join(', ')}`;
    },

    /**
     * Can we run the full immersive experience?
     */
    canRunImmersive() {
        return this._loaded.pannellum;
    },

    /**
     * Can we run spatial audio?
     */
    canRunSpatialAudio() {
        return this._loaded.howler;
    }
};

// Make globally available
window.LibraryLoader = LibraryLoader;
