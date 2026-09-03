/**
 * EcoLens Story Viewer - Spatial Audio Manager
 * Uses Howler.js for immersive 3D positional audio in 360° panoramas
 *
 * AUDIO EXPERIENCE:
 * - Ambient forest soundscapes that surround the user
 * - Species calls positioned in 3D space matching hotspot locations
 * - Head-tracking integration for realistic audio orientation
 * - Smooth crossfades when entering/exiting immersive mode
 */

const SpatialAudio = {
    // State
    _initialized: false,
    _soundscape: null,
    _oneShotSounds: [],
    _masterVolume: 1.0,
    _isMuted: false,
    _isPlaying: false,
    _audioFailed: false, // Track if audio loading failed - we continue without sound
    _audioUnlocked: false, // Track if audio context has been unlocked by user interaction
    _pendingSoundscape: null, // Soundscape waiting to play after unlock

    // Listener orientation (from gyroscope)
    _listenerOrientation: {
        alpha: 0,  // Compass direction (0-360)
        beta: 0,   // Front/back tilt (-180 to 180)
        gamma: 0   // Left/right tilt (-90 to 90)
    },

    /**
     * Initialize the spatial audio system
     */
    init() {
        if (this._initialized) return;

        // Check if Howler is available
        if (typeof Howl === 'undefined') {
            console.warn('[SpatialAudio] Howler.js not loaded');
            return;
        }

        // Configure Howler for spatial audio
        Howler.pos(0, 0, 0);
        Howler.orientation(0, 0, -1, 0, 1, 0);

        // Set up audio unlock on user interaction (required for web browsers)
        this._setupAudioUnlock();

        this._initialized = true;
        console.log('[SpatialAudio] Initialized');
    },

    /**
     * Set up audio context unlock on first user interaction
     * Browsers require user gesture before playing audio
     */
    _setupAudioUnlock() {
        if (this._audioUnlocked) return;

        const unlockAudio = () => {
            if (this._audioUnlocked) return;

            console.log('[SpatialAudio] Unlocking audio context...');

            // Create and play a silent buffer to unlock audio context
            const ctx = Howler.ctx;
            if (ctx && ctx.state === 'suspended') {
                ctx.resume().then(() => {
                    console.log('[SpatialAudio] Audio context resumed');
                    this._audioUnlocked = true;
                    this._onAudioUnlocked();
                }).catch(e => {
                    console.warn('[SpatialAudio] Failed to resume audio context:', e);
                });
            } else {
                // Context already running
                this._audioUnlocked = true;
                this._onAudioUnlocked();
            }

            // Remove listeners after first unlock
            document.removeEventListener('click', unlockAudio);
            document.removeEventListener('touchstart', unlockAudio);
            document.removeEventListener('keydown', unlockAudio);
        };

        // Listen for any user interaction
        document.addEventListener('click', unlockAudio);
        document.addEventListener('touchstart', unlockAudio);
        document.addEventListener('keydown', unlockAudio);

        console.log('[SpatialAudio] Audio unlock listeners added - waiting for user interaction');
    },

    /**
     * Called when audio is unlocked - play any pending soundscape
     */
    _onAudioUnlocked() {
        console.log('[SpatialAudio] Audio unlocked!');

        // Hide the audio hint if shown
        this._hideAudioHint();

        // If there's a pending soundscape, load and play it now
        if (this._pendingSoundscape) {
            console.log('[SpatialAudio] Playing pending soundscape');
            const config = this._pendingSoundscape;
            this._pendingSoundscape = null;
            this.loadSoundscape(config);
            this.fadeIn(2000);
        }
    },

    /**
     * Show a hint to users that they need to interact to enable audio
     */
    _showAudioHint() {
        // Don't show if already shown
        if (document.getElementById('audioHint')) return;

        const hint = document.createElement('div');
        hint.id = 'audioHint';
        hint.innerHTML = `
            <div style="
                position: fixed;
                bottom: 100px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(0, 210, 106, 0.9);
                color: white;
                padding: 12px 24px;
                border-radius: 30px;
                font-family: 'Inter', sans-serif;
                font-size: 14px;
                font-weight: 500;
                z-index: 1000;
                display: flex;
                align-items: center;
                gap: 10px;
                box-shadow: 0 4px 20px rgba(0, 210, 106, 0.4);
                cursor: pointer;
                animation: pulseHint 2s ease-in-out infinite;
            ">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M11 5L6 9H2v6h4l5 4V5z"/>
                    <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
                    <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
                </svg>
                <span>Tap anywhere to enable audio</span>
            </div>
        `;

        // Add pulse animation
        const style = document.createElement('style');
        style.id = 'audioHintStyle';
        style.textContent = `
            @keyframes pulseHint {
                0%, 100% { transform: translateX(-50%) scale(1); }
                50% { transform: translateX(-50%) scale(1.05); }
            }
        `;
        document.head.appendChild(style);

        document.body.appendChild(hint);
        console.log('[SpatialAudio] Audio hint shown');
    },

    /**
     * Hide the audio hint
     */
    _hideAudioHint() {
        const hint = document.getElementById('audioHint');
        if (hint) {
            hint.style.transition = 'opacity 0.3s ease';
            hint.style.opacity = '0';
            setTimeout(() => hint.remove(), 300);
        }
        const style = document.getElementById('audioHintStyle');
        if (style) style.remove();
        console.log('[SpatialAudio] Audio hint hidden');
    },

    /**
     * Load a soundscape for the current immersive scene
     * @param {Object} config - Soundscape configuration
     * @param {string} config.ambientUrl - URL for ambient loop (forest sounds, etc)
     * @param {number} [config.ambientVolume=0.6] - Ambient volume (0-1)
     * @param {boolean} [config.spatial=true] - Enable spatial positioning
     * @param {Array} [config.layers=[]] - Additional audio layers
     */
    loadSoundscape(config) {
        if (!this._initialized) {
            this.init();
        }

        // Unload previous soundscape
        this.stop();

        if (!config || !config.ambientUrl) {
            console.warn('[SpatialAudio] No ambient URL provided - immersive mode will continue without audio');
            return;
        }

        // If audio not unlocked yet (browser autoplay policy), queue for later
        if (!this._audioUnlocked) {
            console.log('[SpatialAudio] Audio not unlocked yet - queuing soundscape for user interaction');
            this._pendingSoundscape = config;
            // Show a hint to the user
            this._showAudioHint();
            return;
        }

        console.log('[SpatialAudio] Loading soundscape:', config.ambientUrl);

        // Track if audio failed to load - we'll continue silently
        this._audioFailed = false;

        // Create the ambient sound
        this._soundscape = new Howl({
            src: [config.ambientUrl],
            loop: true,
            volume: 0, // Start silent for fade in
            html5: true, // Better for long audio files
            preload: true,
            onload: () => {
                console.log('[SpatialAudio] Soundscape loaded successfully');
                this._audioFailed = false;
                if (window.FlutterBridge) {
                    FlutterBridge.notifyFlutter('audioLoaded', {
                        type: 'soundscape',
                        url: config.ambientUrl
                    });
                }
            },
            onloaderror: (id, err) => {
                // Audio failed to load - this is OK, we continue without audio
                console.warn('[SpatialAudio] Audio unavailable (continuing without sound):', err);
                this._audioFailed = true;
                // Clean up the failed soundscape
                if (this._soundscape) {
                    this._soundscape.unload();
                    this._soundscape = null;
                }
            },
            onplayerror: (id, err) => {
                console.warn('[SpatialAudio] Playback issue (continuing):', err);
                // Try to unlock and play again
                if (this._soundscape) {
                    this._soundscape.once('unlock', () => {
                        this._soundscape.play();
                    });
                }
            }
        });

        // Store target volume for fade operations
        if (this._soundscape) {
            this._soundscape._targetVolume = config.ambientVolume || 0.6;
        }

        // Load additional layers if provided
        if (config.layers && config.layers.length > 0) {
            this._loadLayers(config.layers);
        }
    },

    /**
     * Load additional audio layers (birds, insects, water, etc)
     */
    _loadLayers(layers) {
        layers.forEach((layer, index) => {
            const sound = new Howl({
                src: [layer.url],
                loop: layer.loop !== false,
                volume: 0,
                html5: true,
                preload: true
            });

            sound._targetVolume = layer.volume || 0.3;
            sound._layerIndex = index;

            // Store reference for cleanup
            if (!this._soundscape._layers) {
                this._soundscape._layers = [];
            }
            this._soundscape._layers.push(sound);
        });
    },

    /**
     * Update listener orientation based on device gyroscope
     * @param {number} alpha - Compass direction (0-360)
     * @param {number} beta - Front/back tilt (-180 to 180)
     * @param {number} gamma - Left/right tilt (-90 to 90)
     */
    updateListenerOrientation(alpha, beta, gamma) {
        this._listenerOrientation = { alpha, beta, gamma };

        // Convert device orientation to 3D listener orientation
        // Alpha = compass heading, Beta = pitch, Gamma = roll
        const alphaRad = (alpha || 0) * Math.PI / 180;
        const betaRad = (beta || 0) * Math.PI / 180;

        // Calculate forward vector
        const fx = Math.sin(alphaRad) * Math.cos(betaRad);
        const fy = Math.sin(betaRad);
        const fz = -Math.cos(alphaRad) * Math.cos(betaRad);

        // Update Howler listener orientation
        // Forward vector (fx, fy, fz), Up vector (0, 1, 0)
        Howler.orientation(fx, fy, fz, 0, 1, 0);
    },

    /**
     * Start playing the soundscape
     */
    play() {
        if (!this._soundscape || this._isPlaying || this._audioFailed) return;

        console.log('[SpatialAudio] Playing soundscape');
        this._soundscape.play();
        this._isPlaying = true;

        // Play layers if any
        if (this._soundscape._layers) {
            this._soundscape._layers.forEach(layer => layer.play());
        }
    },

    /**
     * Pause the soundscape
     */
    pause() {
        if (!this._soundscape || !this._isPlaying) return;

        console.log('[SpatialAudio] Pausing soundscape');
        this._soundscape.pause();
        this._isPlaying = false;

        // Pause layers
        if (this._soundscape._layers) {
            this._soundscape._layers.forEach(layer => layer.pause());
        }
    },

    /**
     * Stop and unload the soundscape
     */
    stop() {
        if (this._soundscape) {
            console.log('[SpatialAudio] Stopping soundscape');

            // Stop and unload layers
            if (this._soundscape._layers) {
                this._soundscape._layers.forEach(layer => {
                    layer.stop();
                    layer.unload();
                });
            }

            this._soundscape.stop();
            this._soundscape.unload();
            this._soundscape = null;
        }

        // Clean up one-shot sounds
        this._oneShotSounds.forEach(sound => {
            sound.stop();
            sound.unload();
        });
        this._oneShotSounds = [];

        this._isPlaying = false;
    },

    /**
     * Fade in the soundscape
     * @param {number} durationMs - Fade duration in milliseconds
     */
    fadeIn(durationMs = 2000) {
        // Gracefully handle missing audio - just skip silently
        if (!this._soundscape || this._audioFailed) {
            console.log('[SpatialAudio] No audio to fade in - continuing without sound');
            return;
        }

        console.log(`[SpatialAudio] Fading in over ${durationMs}ms`);

        // Start playing if not already
        if (!this._isPlaying) {
            this.play();
        }

        // Fade to target volume
        const targetVolume = this._soundscape._targetVolume * this._masterVolume;
        this._soundscape.fade(0, this._isMuted ? 0 : targetVolume, durationMs);

        // Fade in layers with slight delay for natural feel
        if (this._soundscape._layers) {
            this._soundscape._layers.forEach((layer, index) => {
                setTimeout(() => {
                    const layerTarget = layer._targetVolume * this._masterVolume;
                    layer.fade(0, this._isMuted ? 0 : layerTarget, durationMs);
                }, index * 300); // Stagger layer fade-ins
            });
        }
    },

    /**
     * Fade out the soundscape
     * @param {number} durationMs - Fade duration in milliseconds
     */
    fadeOut(durationMs = 1500) {
        // Gracefully handle missing audio
        if (!this._soundscape || this._audioFailed) {
            this._isPlaying = false;
            return;
        }

        console.log(`[SpatialAudio] Fading out over ${durationMs}ms`);

        // Fade to zero
        this._soundscape.fade(this._soundscape.volume(), 0, durationMs);

        // Fade out layers
        if (this._soundscape._layers) {
            this._soundscape._layers.forEach(layer => {
                layer.fade(layer.volume(), 0, durationMs);
            });
        }

        // Stop after fade completes
        setTimeout(() => {
            this.stop();
        }, durationMs + 100);
    },

    /**
     * Trigger a one-shot positional sound (species call, etc)
     * @param {string} url - Audio file URL
     * @param {Object} position - 3D position {x, y, z}
     * @param {Object} [options] - Additional options
     */
    triggerOneShot(url, position, options = {}) {
        if (!this._initialized) {
            this.init();
        }

        console.log('[SpatialAudio] Triggering one-shot:', url, position);

        const sound = new Howl({
            src: [url],
            volume: (options.volume || 0.8) * this._masterVolume,
            html5: false, // Use Web Audio for spatial positioning
            preload: true,
            onend: () => {
                // Remove from tracking array
                const index = this._oneShotSounds.indexOf(sound);
                if (index > -1) {
                    this._oneShotSounds.splice(index, 1);
                }
                sound.unload();
            }
        });

        // Set 3D position
        sound.pos(position.x || 0, position.y || 0, position.z || 0);

        // Configure spatial properties
        sound.pannerAttr({
            panningModel: 'HRTF',
            distanceModel: 'inverse',
            refDistance: 1,
            maxDistance: 10000,
            rolloffFactor: 1,
            coneInnerAngle: 360,
            coneOuterAngle: 360,
            coneOuterGain: 0
        });

        // Track for cleanup
        this._oneShotSounds.push(sound);

        // Play the sound
        sound.play();

        return sound;
    },

    /**
     * Trigger a species call at a specific hotspot position
     * @param {Object} hotspot - Hotspot with pitch, yaw, and soundUrl
     */
    triggerSpeciesCall(hotspot) {
        if (!hotspot.soundUrl) return;

        // Convert pitch/yaw to 3D position
        const distance = 3; // Virtual distance in 3D space
        const pitchRad = (hotspot.pitch || 0) * Math.PI / 180;
        const yawRad = (hotspot.yaw || 0) * Math.PI / 180;

        const position = {
            x: Math.sin(yawRad) * Math.cos(pitchRad) * distance,
            y: Math.sin(pitchRad) * distance,
            z: Math.cos(yawRad) * Math.cos(pitchRad) * distance
        };

        return this.triggerOneShot(hotspot.soundUrl, position, {
            volume: hotspot.volume || 0.9
        });
    },

    /**
     * Set master volume
     * @param {number} volume - Volume level (0-1)
     */
    setMasterVolume(volume) {
        this._masterVolume = Math.max(0, Math.min(1, volume));
        Howler.volume(this._masterVolume);
        console.log('[SpatialAudio] Master volume:', this._masterVolume);
    },

    /**
     * Mute all audio
     */
    mute() {
        this._isMuted = true;
        Howler.mute(true);
        console.log('[SpatialAudio] Muted');
    },

    /**
     * Unmute all audio
     */
    unmute() {
        this._isMuted = false;
        Howler.mute(false);
        console.log('[SpatialAudio] Unmuted');
    },

    /**
     * Toggle mute state
     */
    toggleMute() {
        if (this._isMuted) {
            this.unmute();
        } else {
            this.mute();
        }
        return this._isMuted;
    },

    /**
     * Check if audio is currently playing
     */
    isPlaying() {
        return this._isPlaying;
    },

    /**
     * Get current listener orientation
     */
    getListenerOrientation() {
        return { ...this._listenerOrientation };
    },

    /**
     * Cleanup and destroy
     */
    destroy() {
        this.stop();
        this._initialized = false;
        console.log('[SpatialAudio] Destroyed');
    }
};

// Make globally available
window.SpatialAudio = SpatialAudio;
