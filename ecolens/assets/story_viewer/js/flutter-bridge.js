/**
 * EcoLens Story Viewer - Flutter Communication Bridge
 * Handles bidirectional communication between WebView and Flutter app
 */

const FlutterBridge = {
    // Store callback references
    _callbacks: {},

    // Story configuration received from Flutter
    storyConfig: null,

    /**
     * Initialize the bridge and listen for messages from Flutter
     */
    init() {
        console.log('[FlutterBridge] Initializing bridge...');

        // Listen for postMessage from Flutter WebView
        window.addEventListener('message', (event) => {
            console.log('[FlutterBridge] Raw message received:', typeof event.data, event.data);

            let data = event.data;
            // Parse JSON string if needed (web iframe sends JSON strings)
            if (typeof data === 'string') {
                console.log('[FlutterBridge] Parsing JSON string...');
                try {
                    data = JSON.parse(data);
                    console.log('[FlutterBridge] Parsed successfully:', data);
                } catch (e) {
                    console.warn('[FlutterBridge] Failed to parse message:', e);
                    return;
                }
            }
            this._handleMessage(data);
        });

        console.log('[FlutterBridge] Message listener registered');

        // WORKAROUND: Listen for custom event from parent (Flutter web iframe fix)
        window.addEventListener('ecolens_config_ready', (event) => {
            console.log('[FlutterBridge] Custom event received!');
            try {
                const config = JSON.parse(event.detail);
                console.log('[FlutterBridge] Config from custom event:', config);
                this._handleMessage({ type: 'initStory', config: config });
            } catch (e) {
                console.error('[FlutterBridge] Failed to parse custom event:', e);
            }
        });

        // WORKAROUND: Also check parent's localStorage periodically
        this._checkParentConfig();
        console.log('[FlutterBridge] Parent config checker started');

        // Expose global function for Flutter JavaScriptChannel
        window.initStory = (config) => {
            this._handleMessage({ type: 'initStory', config });
        };

        // Expose updateProximity for Silent Hunt
        window.updateSilentHunt = (data) => {
            this._handleMessage({ type: 'silentHuntUpdate', data });
        };

        // Notify Flutter we're ready
        this.notifyFlutter('bridgeReady', { version: '2.0' });
    },

    /**
     * Handle incoming message from Flutter
     */
    _handleMessage(data) {
        if (!data || !data.type) {
            console.log('[FlutterBridge] Ignored invalid message:', data);
            return;
        }

        console.log('[FlutterBridge] Received:', data.type, data);

        switch (data.type) {
            case 'initStory':
                console.log('[FlutterBridge] Processing initStory with config:', data.config);
                this.storyConfig = data.config;
                console.log('[FlutterBridge] Triggering onStoryConfig callback...');
                this._triggerCallback('onStoryConfig', data.config);
                console.log('[FlutterBridge] onStoryConfig callback triggered');
                break;

            case 'goToChapter':
                this._triggerCallback('onChapterRequest', data.chapter);
                break;

            case 'pauseStory':
                this._triggerCallback('onPause');
                break;

            case 'resumeStory':
                this._triggerCallback('onResume');
                break;

            case 'setTemporalPosition':
                this._triggerCallback('onTemporalChange', data.position);
                break;

            case 'silentHuntUpdate':
                this._triggerCallback('onSilentHuntUpdate', data.data);
                break;

            case 'toggleOverlay':
                this._triggerCallback('onOverlayToggle', data.overlay, data.visible);
                break;

            case 'narratorFinished':
                // Flutter finished TTS — tell ChapterManager to potentially advance
                if (window.ChapterManager) {
                    ChapterManager.narratorFinished(data.chapter);
                }
                break;

            case 'lookAtHotspot':
                // Flutter requests looking at a specific hotspot in 360° mode
                if (window.ImmersiveViewer && ImmersiveViewer.isImmersive()) {
                    ImmersiveViewer.setLookDirection(data.pitch || 0, data.yaw || 0, data.duration || 1000);
                }
                break;

            case 'setAudioVolume':
                // Flutter requests audio volume change
                if (window.SpatialAudio) {
                    SpatialAudio.setMasterVolume(data.volume || 1.0);
                }
                break;

            case 'toggleAudioMute':
                // Flutter requests mute toggle
                if (window.SpatialAudio) {
                    SpatialAudio.toggleMute();
                }
                break;

            case 'exitImmersive':
                // Flutter requests exit from immersive mode
                if (window.ImmersiveViewer && ImmersiveViewer.isImmersive()) {
                    ImmersiveViewer.exitImmersiveMode();
                }
                break;
        }
    },

    /**
     * Register a callback for an event
     */
    on(event, callback) {
        this._callbacks[event] = callback;
    },

    /**
     * Trigger a registered callback
     */
    _triggerCallback(event, ...args) {
        console.log('[FlutterBridge] _triggerCallback called for event:', event);
        console.log('[FlutterBridge] Registered callbacks:', Object.keys(this._callbacks));
        if (this._callbacks[event]) {
            console.log('[FlutterBridge] Callback found, calling it...');
            this._callbacks[event](...args);
            console.log('[FlutterBridge] Callback executed');
        } else {
            console.warn('[FlutterBridge] No callback registered for event:', event);
        }
    },

    /**
     * WORKAROUND: Check localStorage for config (standalone web page)
     */
    _configLoaded: false,
    _checkCount: 0,
    _checkParentConfig() {
        if (this._configLoaded) return;

        const checkConfig = () => {
            if (this._configLoaded) return;
            this._checkCount++;

            console.log(`[FlutterBridge] localStorage check #${this._checkCount}`);
            console.log('[FlutterBridge] All localStorage keys:', Object.keys(localStorage));

            try {
                // Check localStorage first, then sessionStorage as backup
                let configJson = localStorage.getItem('ecolens_story_config');
                console.log('[FlutterBridge] localStorage config:', configJson ? `${configJson.substring(0, 100)}...` : 'NULL');

                if (!configJson) {
                    configJson = sessionStorage.getItem('ecolens_story_config');
                    console.log('[FlutterBridge] sessionStorage config:', configJson ? `${configJson.substring(0, 100)}...` : 'NULL');
                }

                if (configJson) {
                    console.log('[FlutterBridge] Found config! Parsing...');
                    const config = JSON.parse(configJson);
                    console.log('[FlutterBridge] Config parsed successfully:', config.location?.name);
                    this._configLoaded = true;
                    // Clear it so we don't reload on refresh
                    localStorage.removeItem('ecolens_story_config');
                    sessionStorage.removeItem('ecolens_story_config');
                    this._handleMessage({ type: 'initStory', config: config });
                    return;
                }
            } catch (e) {
                console.error('[FlutterBridge] Storage check failed:', e);
            }

            // Keep checking for up to 10 seconds (20 checks)
            if (this._checkCount < 20) {
                setTimeout(checkConfig, 500);
            } else {
                console.warn('[FlutterBridge] Gave up waiting for config after 10 seconds');
            }
        };

        // Start checking immediately
        console.log('[FlutterBridge] Starting localStorage config polling...');
        setTimeout(checkConfig, 100);
    },

    /**
     * Send notification to Flutter
     */
    notifyFlutter(eventType, data = {}) {
        const message = { type: eventType, ...data };

        // Try flutter_inappwebview first (Android/iOS)
        if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify(message));
            return;
        }

        // Try webview_flutter JavaScriptChannel
        if (window.FlutterBridge && window.FlutterBridge.postMessage) {
            window.FlutterBridge.postMessage(JSON.stringify(message));
            return;
        }

        // Fallback to postMessage (web preview in iframe)
        if (window.parent !== window) {
            window.parent.postMessage(message, '*');
        }

        // Handle close/complete events on standalone web page
        if (eventType === 'closeStory' || eventType === 'storyComplete') {
            console.log('[FlutterBridge] Standalone web - navigating back to app');
            // Set completion flag so Flutter knows we're done
            try {
                localStorage.setItem('ecolens_story_complete', 'true');
            } catch (e) {
                console.warn('[FlutterBridge] Could not set completion flag:', e);
            }
            // Navigate back to Flutter app
            if (window.history.length > 1) {
                window.history.back();
            } else {
                // Fallback: navigate to app root
                window.location.href = '/';
            }
            return;
        }

        console.log('[FlutterBridge] Sent:', eventType, data);
    },

    // Convenience methods for common events

    /**
     * Notify chapter change
     */
    onChapterChanged(chapterIndex, chapterData) {
        this.notifyFlutter('chapterChanged', {
            chapter: chapterIndex,
            id: chapterData.id,
            title: chapterData.title
        });
    },

    /**
     * Request Flutter to narrate chapter text via TTS
     */
    requestNarration(chapterIndex, text) {
        this.notifyFlutter('narrateChapter', {
            chapter: chapterIndex,
            text: text
        });
    },

    /**
     * Notify story complete
     */
    onStoryComplete() {
        this.notifyFlutter('storyComplete');
    },

    /**
     * Notify close request
     */
    onCloseRequest() {
        this.notifyFlutter('closeStory');
    },

    /**
     * Notify user interaction (for pausing scripted camera)
     */
    onUserInteraction() {
        this.notifyFlutter('userInteracted');
    },

    /**
     * Notify camera position update
     */
    onCameraMove(position) {
        this.notifyFlutter('cameraMoved', {
            lat: position.latitude,
            lng: position.longitude,
            alt: position.height,
            heading: position.heading,
            pitch: position.pitch
        });
    },

    /**
     * Notify species POI interaction
     */
    onSpeciesSelected(speciesId, speciesData) {
        this.notifyFlutter('speciesSelected', {
            id: speciesId,
            name: speciesData.name,
            status: speciesData.conservationStatus
        });
    },

    /**
     * Notify loading state change
     */
    onLoadingStateChange(isLoading, progress = 0) {
        this.notifyFlutter('loadingState', { isLoading, progress });
    },

    /**
     * Notify error
     */
    onError(code, message) {
        this.notifyFlutter('error', { code, message });
    },

    // ============ Immersive Mode Events ============

    /**
     * Request haptic feedback from Flutter
     * @param {string} type - Haptic type: 'light', 'medium', 'heavy', 'selection', 'success', 'warning', 'error'
     */
    triggerHaptic(type = 'light') {
        this.notifyFlutter('haptic', { type });
    },

    /**
     * Notify immersive mode state change
     * @param {boolean} active - Whether immersive mode is active
     */
    onImmersiveModeChanged(active) {
        this.notifyFlutter('immersiveModeChanged', { active });
    },

    /**
     * Notify gyroscope permission status
     * @param {boolean} granted - Whether permission was granted
     */
    onGyroscopePermission(granted) {
        this.notifyFlutter('gyroscopePermission', { granted });
    },

    /**
     * Notify view direction change in 360° mode
     * @param {number} pitch - Vertical look angle
     * @param {number} yaw - Horizontal look angle
     * @param {number} hfov - Field of view
     */
    onViewDirectionChanged(pitch, yaw, hfov) {
        this.notifyFlutter('viewDirectionChanged', { pitch, yaw, hfov });
    },

    /**
     * Notify hotspot interaction in 360° mode
     * @param {Object} hotspot - Hotspot data
     * @param {string} action - Action type: 'hover', 'click', 'focus'
     */
    onHotspotInteraction(hotspot, action = 'click') {
        this.triggerHaptic(action === 'click' ? 'light' : 'selection');
        this.notifyFlutter('hotspotInteraction', {
            id: hotspot.id,
            name: hotspot.name,
            action: action
        });
    },

    /**
     * Notify audio state change
     * @param {string} state - Audio state: 'playing', 'paused', 'stopped', 'loading'
     */
    onAudioStateChanged(state) {
        this.notifyFlutter('audioStateChanged', { state });
    },

    /**
     * Request Flutter to show species detail card
     * @param {Object} species - Species data
     */
    showSpeciesCard(species) {
        this.triggerHaptic('light');
        this.notifyFlutter('showSpeciesCard', {
            id: species.id,
            name: species.name,
            status: species.status,
            icon: species.icon,
            description: species.description
        });
    }
};

// Make globally available
window.FlutterBridge = FlutterBridge;
