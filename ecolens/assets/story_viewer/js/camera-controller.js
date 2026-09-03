/**
 * EcoLens Story Viewer - Camera Controller
 * Handles scripted camera paths, free-look interrupt, and camera utilities
 *
 * IMMERSIVE CAMERA PHILOSOPHY:
 * - Pitch angle matters MORE than altitude
 * - Pitch -90° = looking straight down (satellite view) - AVOID
 * - Pitch -10° = looking toward horizon (immersive, like BBC Planet Earth drone)
 * - Most chapters should use pitch between -5° and -30°
 * - Low altitude (100-500m) + horizontal pitch = "flying through the forest" feel
 */

const CameraController = {
    viewer: null,
    isScripted: true,
    isPaused: false,
    currentPath: null,
    resumeTimeout: null,
    orbitHandler: null,
    descentHandler: null,

    /**
     * Initialize camera controller with Cesium viewer
     */
    init(viewer) {
        this.viewer = viewer;
        this._setupInteractionHandlers();
    },

    /**
     * Setup handlers for free-look interrupt
     */
    _setupInteractionHandlers() {
        const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas);

        // Pause scripted camera on any user interaction
        const pauseEvents = [
            Cesium.ScreenSpaceEventType.LEFT_DOWN,
            Cesium.ScreenSpaceEventType.RIGHT_DOWN,
            Cesium.ScreenSpaceEventType.MIDDLE_DOWN,
            Cesium.ScreenSpaceEventType.WHEEL
        ];

        pauseEvents.forEach(eventType => {
            handler.setInputAction(() => {
                if (this.isScripted && !this.isPaused) {
                    this._pauseScriptedCamera();
                }
            }, eventType);
        });

        // Touch support
        handler.setInputAction(() => {
            if (this.isScripted && !this.isPaused) {
                this._pauseScriptedCamera();
            }
        }, Cesium.ScreenSpaceEventType.PINCH_START);
    },

    /**
     * Pause scripted camera for free-look
     */
    _pauseScriptedCamera() {
        this.isPaused = true;

        // Stop any active camera flight
        this.viewer.camera.cancelFlight();

        // Stop orbit animation if running
        if (this.orbitHandler) {
            this.viewer.clock.onTick.removeEventListener(this.orbitHandler);
            this.orbitHandler = null;
        }

        // Stop descent animation if running
        if (this.descentHandler) {
            this.viewer.clock.onTick.removeEventListener(this.descentHandler);
            this.descentHandler = null;
        }

        // Notify Flutter
        if (window.FlutterBridge) {
            FlutterBridge.onUserInteraction();
        }

        // Clear existing resume timeout
        if (this.resumeTimeout) {
            clearTimeout(this.resumeTimeout);
        }

        // Resume after configured delay
        const delay = window.EcoLensConfig?.camera?.freeLookResumeDelay || 5000;
        this.resumeTimeout = setTimeout(() => {
            this._resumeScriptedCamera();
        }, delay);
    },

    /**
     * Resume scripted camera
     */
    _resumeScriptedCamera() {
        this.isPaused = false;

        // Re-execute current path if we have one
        if (this.currentPath) {
            this.executePath(this.currentPath);
        }
    },

    /**
     * Force resume (called from UI)
     */
    forceResume() {
        if (this.resumeTimeout) {
            clearTimeout(this.resumeTimeout);
        }
        this._resumeScriptedCamera();
    },

    /**
     * Execute a camera path based on chapter data
     *
     * @param {Object} pathConfig - Camera path configuration
     * @param {string} pathConfig.type - Camera movement type (flyTo, orbit, hover, topDown, pullback, approach, descent)
     * @param {Object} pathConfig.location - Target location {lat, lng}
     * @param {number} [pathConfig.altitude] - Target altitude in meters
     * @param {number} [pathConfig.pitch] - Camera pitch in degrees (use -5 to -30 for immersive views)
     * @param {number} [pathConfig.heading] - Camera heading in degrees
     * @param {number} [pathConfig.duration] - Animation duration in seconds
     */
    executePath(pathConfig) {
        if (this.isPaused) return;

        this.currentPath = pathConfig;

        // Use rest spread to capture all remaining props as options
        const { type, location, ...options } = pathConfig;

        // Guard against missing location
        if (!location || !location.lat || !location.lng) {
            console.warn('[CameraController] executePath: No valid location provided');
            return;
        }

        switch (type || 'flyTo') {
            case 'flyTo':
                this._flyTo(location, options);
                break;
            case 'orbit':
                this._orbit(location, options);
                break;
            case 'hover':
                this._hover(location, options);
                break;
            case 'topDown':
                this._topDown(location, options);
                break;
            case 'pullback':
                this._pullback(location, options);
                break;
            case 'approach':
                this._approach(location, options);
                break;
            case 'descent':
                this._descent(location, options);
                break;
            default:
                this._flyTo(location, options);
        }
    },

    /**
     * Fly to a location - basic flyTo with immersive defaults
     */
    _flyTo(location, options) {
        const duration = options.duration || 4;
        // Default to low altitude and near-horizontal pitch for immersive feel
        const altitude = options.altitude || 500;
        const pitch = options.pitch || -15;
        const heading = options.heading || 0;

        this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                location.lng,
                location.lat,
                altitude
            ),
            orientation: {
                heading: Cesium.Math.toRadians(heading),
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            },
            duration: duration,
            complete: () => {
                if (options.onComplete) options.onComplete();
            }
        });
    },

    /**
     * Cinematic descent - starts high and descends to low altitude
     * Perfect for "Arrival" chapter - like a drone descending into the forest
     */
    _descent(location, options) {
        const startAltitude = options.startAltitude || 5000;
        const endAltitude = options.endAltitude || 200;
        const startPitch = options.pitch || -45;
        const endPitch = options.endPitch || -15;
        const duration = options.duration || 6;
        const heading = options.heading || 0;

        // Stop any existing descent
        if (this.descentHandler) {
            this.viewer.clock.onTick.removeEventListener(this.descentHandler);
            this.descentHandler = null;
        }

        const startTime = Date.now();
        const durationMs = duration * 1000;

        // Set initial position
        this.viewer.camera.setView({
            destination: Cesium.Cartesian3.fromDegrees(location.lng, location.lat, startAltitude),
            orientation: {
                heading: Cesium.Math.toRadians(heading),
                pitch: Cesium.Math.toRadians(startPitch),
                roll: 0
            }
        });

        // Animate descent
        this.descentHandler = () => {
            if (this.isPaused) return;

            const elapsed = Date.now() - startTime;
            const progress = Math.min(elapsed / durationMs, 1);

            // Ease-out cubic for smooth deceleration
            const eased = 1 - Math.pow(1 - progress, 3);

            // Interpolate altitude and pitch
            const currentAltitude = startAltitude + (endAltitude - startAltitude) * eased;
            const currentPitch = startPitch + (endPitch - startPitch) * eased;

            // Slight heading rotation during descent for cinematic effect
            const currentHeading = heading + (30 * eased);

            this.viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(location.lng, location.lat, currentAltitude),
                orientation: {
                    heading: Cesium.Math.toRadians(currentHeading),
                    pitch: Cesium.Math.toRadians(currentPitch),
                    roll: 0
                }
            });

            if (progress >= 1) {
                this.viewer.clock.onTick.removeEventListener(this.descentHandler);
                this.descentHandler = null;
                if (options.onComplete) options.onComplete();
            }
        };

        this.viewer.clock.onTick.addEventListener(this.descentHandler);
    },

    /**
     * Orbit around a point - immersive canopy-level orbit
     * Like a drone slowly circling over the treetops
     */
    _orbit(location, options) {
        // LOW altitude for immersive feel
        const radius = options.radius || 500; // Much smaller radius
        const altitude = options.altitude || 150; // Low altitude - just above canopy
        const duration = options.duration || 8;
        const pitch = options.pitch || -10; // Nearly horizontal - looking across canopy

        // Stop existing orbit
        if (this.orbitHandler) {
            this.viewer.clock.onTick.removeEventListener(this.orbitHandler);
            this.orbitHandler = null;
        }

        let angle = 0;
        const angularSpeed = (2 * Math.PI) / duration;

        // Position camera at starting point
        this._updateOrbitPosition(location, radius, altitude, angle, pitch);

        // Start orbit animation
        const startTime = Date.now();
        this.orbitHandler = () => {
            if (this.isPaused) return;

            const elapsed = (Date.now() - startTime) / 1000;
            if (elapsed > duration) {
                this.viewer.clock.onTick.removeEventListener(this.orbitHandler);
                this.orbitHandler = null;
                if (options.onComplete) options.onComplete();
                return;
            }

            angle = elapsed * angularSpeed;
            this._updateOrbitPosition(location, radius, altitude, angle, pitch);
        };

        this.viewer.clock.onTick.addEventListener(this.orbitHandler);
    },

    /**
     * Update camera position during orbit
     */
    _updateOrbitPosition(center, radius, altitude, angle, pitch) {
        // Convert radius from meters to degrees (approximate)
        const radiusDegrees = radius / 111000;
        const offsetLng = radiusDegrees * Math.cos(angle);
        const offsetLat = radiusDegrees * Math.sin(angle);

        const position = Cesium.Cartesian3.fromDegrees(
            center.lng + offsetLng,
            center.lat + offsetLat,
            altitude
        );

        // Calculate heading to look at center
        const headingToCenter = Math.atan2(offsetLng, offsetLat) * (180 / Math.PI) + 180;

        this.viewer.camera.setView({
            destination: position,
            orientation: {
                heading: Cesium.Math.toRadians(headingToCenter),
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            }
        });
    },

    /**
     * Hover - immersive low-altitude glide over canopy
     * Like a BBC Planet Earth drone shot drifting over the forest
     */
    _hover(location, options) {
        // Low altitude and nearly horizontal pitch for immersive feel
        const altitude = options.altitude || 150;
        const pitch = options.pitch || -10; // Nearly horizontal
        const heading = options.heading || -30;
        const duration = options.duration || 2;

        // Slight lateral offset for movement feel
        const offsetLng = 0.002; // Small offset in degrees

        this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                location.lng + offsetLng,
                location.lat,
                altitude
            ),
            orientation: {
                heading: Cesium.Math.toRadians(heading),
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            },
            duration: duration,
            complete: () => {
                if (options.onComplete) options.onComplete();
            }
        });
    },

    /**
     * Top-down view (for timelapse/NDVI visualization)
     * This is the only view that should be looking straight down
     */
    _topDown(location, options) {
        // For timelapse, we need to see the area from above
        // But not too high - keep it relatively close
        const altitude = options.altitude || 500;
        const pitch = options.pitch || -75; // Not quite straight down, slight angle

        this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                location.lng,
                location.lat,
                altitude
            ),
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            },
            duration: options.duration || 2,
            complete: () => {
                if (options.onComplete) options.onComplete();
            }
        });
    },

    /**
     * Pull back to show scale of damage
     * Higher altitude but still with perspective angle
     */
    _pullback(location, options) {
        const altitude = options.altitude || 800;
        const pitch = options.pitch || -30; // Angled, not straight down

        this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                location.lng,
                location.lat - 0.01, // Slight offset south
                altitude
            ),
            orientation: {
                heading: 0,
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            },
            duration: options.duration || 3,
            complete: () => {
                if (options.onComplete) options.onComplete();
            }
        });
    },

    /**
     * Approach - hopeful forward-looking view toward the horizon
     * Low altitude, nearly horizontal, like looking across the landscape toward the future
     */
    _approach(location, options) {
        // Very low altitude for immersive ground-level feel
        const altitude = options.altitude || 100;
        const pitch = options.pitch || -5; // Nearly horizontal - looking toward horizon
        const heading = options.heading || 90; // Looking east (toward sunrise/hope)

        this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(
                location.lng,
                location.lat,
                altitude
            ),
            orientation: {
                heading: Cesium.Math.toRadians(heading),
                pitch: Cesium.Math.toRadians(pitch),
                roll: 0
            },
            duration: options.duration || 3,
            complete: () => {
                if (options.onComplete) options.onComplete();
            }
        });
    },

    /**
     * Get current camera position
     */
    getCurrentPosition() {
        const cartographic = this.viewer.camera.positionCartographic;
        return {
            lat: Cesium.Math.toDegrees(cartographic.latitude),
            lng: Cesium.Math.toDegrees(cartographic.longitude),
            altitude: cartographic.height,
            heading: Cesium.Math.toDegrees(this.viewer.camera.heading),
            pitch: Cesium.Math.toDegrees(this.viewer.camera.pitch)
        };
    },

    /**
     * Cleanup
     */
    destroy() {
        if (this.resumeTimeout) {
            clearTimeout(this.resumeTimeout);
        }
        if (this.orbitHandler) {
            this.viewer.clock.onTick.removeEventListener(this.orbitHandler);
        }
        if (this.descentHandler) {
            this.viewer.clock.onTick.removeEventListener(this.descentHandler);
        }
    }
};

// Make globally available
window.CameraController = CameraController;
