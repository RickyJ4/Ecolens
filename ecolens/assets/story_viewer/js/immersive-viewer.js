/**
 * EcoLens Story Viewer - Immersive 360° Viewer
 * Manages Pannellum panorama viewer, gyroscope control, and renderer switching
 *
 * EXPERIENCE FLOW:
 * - CesiumJS for data chapters (satellite view, stats, overlays)
 * - Pannellum for immersive chapters (360° forest, species hotspots)
 * - Smooth crossfade between renderers
 * - Gyroscope for phone-as-eyes experience
 */

const ImmersiveViewer = {
    // State
    _isImmersive: false,
    _pannellumViewer: null,
    _gyroscopeEnabled: false,
    _gyroscopePermissionGranted: false,
    _currentConfig: null,

    // DOM elements
    _panoramaContainer: null,
    _cesiumContainer: null,
    _permissionOverlay: null,

    // Callbacks
    _onHotspotClick: null,

    /**
     * Initialize the immersive viewer
     */
    init() {
        this._panoramaContainer = document.getElementById('panoramaContainer');
        this._cesiumContainer = document.getElementById('cesiumContainer');
        this._permissionOverlay = document.getElementById('gyroPermissionOverlay');

        // Setup permission buttons
        const enableBtn = document.getElementById('enableGyroBtn');
        const skipBtn = document.getElementById('skipGyroBtn');

        if (enableBtn) {
            enableBtn.addEventListener('click', () => this._requestGyroscopePermission());
        }
        if (skipBtn) {
            skipBtn.addEventListener('click', () => this._skipGyroscope());
        }

        console.log('[ImmersiveViewer] Initialized');
    },

    /**
     * Enter immersive 360° mode
     * @param {Object} config - Panorama configuration
     * @param {string} config.imageUrl - Equirectangular panorama JPEG URL
     * @param {number} [config.pitch=0] - Initial vertical look angle
     * @param {number} [config.yaw=0] - Initial horizontal look angle
     * @param {number} [config.hfov=100] - Field of view
     * @param {Array} [config.hotspots=[]] - Species markers
     * @param {boolean} [config.gyroscope=true] - Enable phone orientation
     */
    async enterImmersiveMode(config) {
        console.log('[ImmersiveViewer] === enterImmersiveMode CALLED ===');
        console.log('[ImmersiveViewer] Config:', JSON.stringify(config, null, 2));
        console.log('[ImmersiveViewer] Pannellum available:', typeof pannellum !== 'undefined');

        if (!config || !config.imageUrl) {
            console.warn('[ImmersiveViewer] No panorama URL provided');
            return false;
        }

        if (typeof pannellum === 'undefined') {
            console.error('[ImmersiveViewer] Pannellum library not loaded!');
            return false;
        }

        console.log('[ImmersiveViewer] Entering immersive mode:', config.imageUrl);
        this._currentConfig = config;

        // Pause CesiumJS rendering to free GPU
        this._pauseCesium();

        // Crossfade: hide CesiumJS, show panorama
        await this._crossfadeToPanorama();

        // Create or update Pannellum viewer
        this._createPannellumViewer(config);

        // Handle gyroscope
        if (config.gyroscope !== false) {
            await this._setupGyroscope();
        }

        this._isImmersive = true;

        // Notify Flutter
        if (window.FlutterBridge) {
            FlutterBridge.notifyFlutter('immersiveModeChanged', { active: true });
        }

        return true;
    },

    /**
     * Exit immersive mode, return to CesiumJS
     */
    async exitImmersiveMode() {
        console.log('[ImmersiveViewer] === exitImmersiveMode CALLED ===');
        if (!this._isImmersive) {
            console.log('[ImmersiveViewer] Not in immersive mode, skipping exit');
            return;
        }

        console.log('[ImmersiveViewer] Exiting immersive mode');

        // Stop spatial audio
        if (window.SpatialAudio) {
            SpatialAudio.fadeOut(1500);
        }

        // Crossfade: hide panorama, show CesiumJS
        await this._crossfadeToCesium();

        // Destroy Pannellum
        this._destroyPannellum();

        // Resume CesiumJS rendering
        this._resumeCesium();

        this._isImmersive = false;

        // Notify Flutter
        if (window.FlutterBridge) {
            FlutterBridge.notifyFlutter('immersiveModeChanged', { active: false });
        }
    },

    /**
     * Create Pannellum viewer
     */
    _createPannellumViewer(config) {
        // Destroy existing viewer if any
        this._destroyPannellum();

        const viewerConfig = {
            type: 'equirectangular',
            panorama: config.imageUrl,
            autoLoad: true,
            showControls: false,
            showFullscreenCtrl: false,
            showZoomCtrl: false,
            compass: false,
            mouseZoom: false,
            hfov: config.hfov || 100,
            pitch: config.pitch || 0,
            yaw: config.yaw || 0,
            minHfov: 60,
            maxHfov: 120,
            friction: 0.15,
            hotSpots: []
        };

        try {
            this._pannellumViewer = pannellum.viewer('panoramaContainer', viewerConfig);

            // Add hotspots after viewer is loaded
            this._pannellumViewer.on('load', () => {
                console.log('[ImmersiveViewer] Panorama loaded');
                if (config.hotspots && config.hotspots.length > 0) {
                    this._addHotspots(config.hotspots);
                }
            });

            this._pannellumViewer.on('error', (err) => {
                console.error('[ImmersiveViewer] Pannellum error:', err);
            });
        } catch (e) {
            console.error('[ImmersiveViewer] Failed to create viewer:', e);
        }
    },

    /**
     * Destroy Pannellum viewer
     */
    _destroyPannellum() {
        if (this._pannellumViewer) {
            try {
                this._pannellumViewer.destroy();
            } catch (e) {
                console.warn('[ImmersiveViewer] Error destroying viewer:', e);
            }
            this._pannellumViewer = null;
        }
    },

    /**
     * Add species hotspots to the 360° scene
     */
    _addHotspots(hotspots) {
        if (!this._pannellumViewer) return;

        hotspots.forEach((hotspot, index) => {
            const id = `species-${index}`;

            this._pannellumViewer.addHotSpot({
                id: id,
                pitch: hotspot.pitch || 0,
                yaw: hotspot.yaw || 0,
                type: 'custom',
                cssClass: 'species-hotspot',
                createTooltipFunc: (hotSpotDiv) => {
                    hotSpotDiv.innerHTML = hotspot.icon || '🌿';
                },
                clickHandlerFunc: () => {
                    this._handleHotspotClick(hotspot);
                }
            });
        });

        console.log(`[ImmersiveViewer] Added ${hotspots.length} hotspots`);
    },

    /**
     * Add a single hotspot
     */
    addHotspot(config) {
        if (!this._pannellumViewer) return;

        const id = `species-${Date.now()}`;
        this._pannellumViewer.addHotSpot({
            id: id,
            pitch: config.pitch || 0,
            yaw: config.yaw || 0,
            type: 'custom',
            cssClass: 'species-hotspot',
            createTooltipFunc: (hotSpotDiv) => {
                hotSpotDiv.innerHTML = config.icon || '🌿';
            },
            clickHandlerFunc: () => {
                this._handleHotspotClick(config);
            }
        });
    },

    /**
     * Handle hotspot click
     */
    _handleHotspotClick(hotspot) {
        console.log('[ImmersiveViewer] Hotspot clicked:', hotspot.name);

        // Trigger haptic
        if (window.FlutterBridge) {
            FlutterBridge.notifyFlutter('haptic', { type: 'light' });
        }

        // Play spatial audio for species call
        if (window.SpatialAudio && hotspot.soundUrl) {
            SpatialAudio.triggerOneShot(hotspot.soundUrl, {
                x: Math.sin(hotspot.yaw * Math.PI / 180) * 3,
                y: Math.sin(hotspot.pitch * Math.PI / 180) * 3,
                z: Math.cos(hotspot.yaw * Math.PI / 180) * 3
            });
        }

        // Notify Flutter to show species card
        if (window.FlutterBridge) {
            FlutterBridge.notifyFlutter('speciesSelected', {
                id: hotspot.id,
                name: hotspot.name,
                status: hotspot.status,
                icon: hotspot.icon
            });
        }

        // Trigger callback if set
        if (this._onHotspotClick) {
            this._onHotspotClick(hotspot);
        }
    },

    /**
     * Set hotspot click callback
     */
    onHotspotClick(callback) {
        this._onHotspotClick = callback;
    },

    /**
     * Setup gyroscope control
     */
    async _setupGyroscope() {
        // Check if already granted
        if (this._gyroscopePermissionGranted) {
            this._enableGyroscope();
            return;
        }

        // Check if device supports DeviceOrientation
        if (!window.DeviceOrientationEvent) {
            console.log('[ImmersiveViewer] Device does not support orientation');
            return;
        }

        // iOS 13+ requires permission request
        if (typeof DeviceOrientationEvent.requestPermission === 'function') {
            // Show permission overlay
            this._showPermissionOverlay();
        } else {
            // Android - just enable it
            this._gyroscopePermissionGranted = true;
            this._enableGyroscope();
            this._showGyroscopeHint();
        }
    },

    /**
     * Show permission overlay
     */
    _showPermissionOverlay() {
        if (this._permissionOverlay) {
            this._permissionOverlay.style.display = 'flex';
        }
    },

    /**
     * Hide permission overlay
     */
    _hidePermissionOverlay() {
        if (this._permissionOverlay) {
            this._permissionOverlay.style.display = 'none';
        }
    },

    /**
     * Request gyroscope permission (iOS)
     */
    async _requestGyroscopePermission() {
        try {
            const response = await DeviceOrientationEvent.requestPermission();
            this._hidePermissionOverlay();

            if (response === 'granted') {
                this._gyroscopePermissionGranted = true;
                this._enableGyroscope();
                console.log('[ImmersiveViewer] Gyroscope permission granted');
            } else {
                console.log('[ImmersiveViewer] Gyroscope permission denied');
            }
        } catch (e) {
            console.error('[ImmersiveViewer] Permission request error:', e);
            this._hidePermissionOverlay();
        }
    },

    /**
     * Skip gyroscope, use touch controls
     */
    _skipGyroscope() {
        this._hidePermissionOverlay();
        console.log('[ImmersiveViewer] Using touch controls');
    },

    /**
     * Enable gyroscope control
     */
    _enableGyroscope() {
        if (!this._pannellumViewer) return;

        try {
            this._pannellumViewer.startOrientation();
            this._gyroscopeEnabled = true;
            console.log('[ImmersiveViewer] Gyroscope enabled');

            // Update listener orientation for spatial audio
            window.addEventListener('deviceorientation', this._handleDeviceOrientation.bind(this));
        } catch (e) {
            console.warn('[ImmersiveViewer] Could not enable gyroscope:', e);
        }
    },

    /**
     * Show brief gyroscope hint on Android
     */
    _showGyroscopeHint() {
        // Create toast notification
        const toast = document.createElement('div');
        toast.innerHTML = '📱 Move your phone to look around';
        toast.style.cssText = `
            position: fixed;
            bottom: 100px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 12px 24px;
            border-radius: 24px;
            font-size: 14px;
            z-index: 1000;
            pointer-events: none;
            animation: fadeInOut 3s ease-in-out forwards;
        `;

        // Add animation
        const style = document.createElement('style');
        style.textContent = `
            @keyframes fadeInOut {
                0% { opacity: 0; transform: translateX(-50%) translateY(20px); }
                20% { opacity: 1; transform: translateX(-50%) translateY(0); }
                80% { opacity: 1; transform: translateX(-50%) translateY(0); }
                100% { opacity: 0; transform: translateX(-50%) translateY(-20px); }
            }
        `;
        document.head.appendChild(style);

        document.body.appendChild(toast);

        // Remove after animation
        setTimeout(() => {
            toast.remove();
            style.remove();
        }, 3000);
    },

    /**
     * Handle device orientation event
     */
    _handleDeviceOrientation(event) {
        // Update spatial audio listener orientation
        if (window.SpatialAudio && this._isImmersive) {
            SpatialAudio.updateListenerOrientation(
                event.alpha || 0,
                event.beta || 0,
                event.gamma || 0
            );
        }
    },

    /**
     * Programmatically set look direction
     */
    setLookDirection(pitch, yaw, duration = 1000) {
        if (!this._pannellumViewer) return;

        // Temporarily disable gyroscope for smooth animation
        const wasGyroEnabled = this._gyroscopeEnabled;
        if (wasGyroEnabled) {
            this._pannellumViewer.stopOrientation();
        }

        // Animate to new position
        const startPitch = this._pannellumViewer.getPitch();
        const startYaw = this._pannellumViewer.getYaw();
        const startTime = Date.now();

        const animate = () => {
            const elapsed = Date.now() - startTime;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 3); // Ease-out cubic

            const currentPitch = startPitch + (pitch - startPitch) * eased;
            const currentYaw = startYaw + (yaw - startYaw) * eased;

            this._pannellumViewer.setPitch(currentPitch);
            this._pannellumViewer.setYaw(currentYaw);

            if (progress < 1) {
                requestAnimationFrame(animate);
            } else if (wasGyroEnabled) {
                this._pannellumViewer.startOrientation();
            }
        };

        animate();
    },

    /**
     * Pause CesiumJS rendering
     */
    _pauseCesium() {
        if (window.viewer) {
            window.viewer.useDefaultRenderLoop = false;
            console.log('[ImmersiveViewer] CesiumJS paused');
        }
    },

    /**
     * Resume CesiumJS rendering
     */
    _resumeCesium() {
        if (window.viewer) {
            window.viewer.useDefaultRenderLoop = true;
            console.log('[ImmersiveViewer] CesiumJS resumed');
        }
    },

    /**
     * Crossfade from CesiumJS to panorama
     */
    async _crossfadeToPanorama() {
        return new Promise((resolve) => {
            // Show panorama container
            this._panoramaContainer.style.display = 'block';
            this._panoramaContainer.style.opacity = '0';

            // Fade out CesiumJS
            this._cesiumContainer.style.opacity = '0';

            // Small delay for CSS transition to register
            setTimeout(() => {
                this._panoramaContainer.style.opacity = '1';
            }, 50);

            // After transition, hide CesiumJS
            setTimeout(() => {
                this._cesiumContainer.style.display = 'none';
                resolve();
            }, 1500);
        });
    },

    /**
     * Crossfade from panorama to CesiumJS
     */
    async _crossfadeToCesium() {
        return new Promise((resolve) => {
            // Show CesiumJS container
            this._cesiumContainer.style.display = 'block';
            this._cesiumContainer.style.opacity = '0';

            // Fade out panorama
            this._panoramaContainer.style.opacity = '0';

            // Small delay for CSS transition
            setTimeout(() => {
                this._cesiumContainer.style.opacity = '1';
            }, 50);

            // After transition, hide panorama
            setTimeout(() => {
                this._panoramaContainer.style.display = 'none';
                resolve();
            }, 1500);
        });
    },

    /**
     * Check if currently in immersive mode
     */
    isImmersive() {
        return this._isImmersive;
    },

    /**
     * Get current view direction
     */
    getViewDirection() {
        if (!this._pannellumViewer) return null;
        return {
            pitch: this._pannellumViewer.getPitch(),
            yaw: this._pannellumViewer.getYaw(),
            hfov: this._pannellumViewer.getHfov()
        };
    },

    /**
     * Cleanup
     */
    destroy() {
        window.removeEventListener('deviceorientation', this._handleDeviceOrientation);
        this._destroyPannellum();
        this._isImmersive = false;
        this._gyroscopeEnabled = false;
    }
};

// Make globally available
window.ImmersiveViewer = ImmersiveViewer;
