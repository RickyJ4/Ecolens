/**
 * EcoLens Story Viewer - Sentinel-2 Imagery Layer
 * Handles real satellite imagery overlays including before/after comparison
 */

const SentinelLayer = {
    viewer: null,
    beforeLayer: null,
    afterLayer: null,
    ndviLayer: null,
    temporalPosition: 0, // 0 = before, 1 = after
    bounds: null,

    /**
     * Initialize Sentinel layer manager
     */
    init(viewer) {
        this.viewer = viewer;
    },

    /**
     * Check if viewer is available (null guard)
     */
    _requireViewer() {
        if (!this.viewer) {
            console.warn('[SentinelLayer] Viewer not initialized');
            return false;
        }
        return true;
    },

    /**
     * Add Sentinel-2 imagery from storyConfig
     * @param {Object} sentinelData - Contains beforeRgbUrl, afterRgbUrl, ndviChangeUrl
     * @param {Object} location - { lat, lng }
     * @param {number} radiusKm - Radius in kilometers for imagery extent
     */
    addImagery(sentinelData, location, radiusKm = 5) {
        if (!this._requireViewer()) return;
        if (!sentinelData || !sentinelData.available) {
            console.log('[SentinelLayer] No Sentinel imagery available');
            return;
        }

        // Calculate bounds (approximate)
        const latOffset = radiusKm / 111; // ~111km per degree latitude
        const lngOffset = radiusKm / (111 * Math.cos(location.lat * Math.PI / 180));

        this.bounds = {
            west: location.lng - lngOffset,
            east: location.lng + lngOffset,
            south: location.lat - latOffset,
            north: location.lat + latOffset
        };

        const rectangle = Cesium.Rectangle.fromDegrees(
            this.bounds.west,
            this.bounds.south,
            this.bounds.east,
            this.bounds.north
        );

        // Add before imagery (Earth Engine URL)
        if (sentinelData.beforeRgbUrl) {
            this._addImageryLayer('before', sentinelData.beforeRgbUrl, rectangle);
        }

        // Add after imagery (initially hidden)
        if (sentinelData.afterRgbUrl) {
            this._addImageryLayer('after', sentinelData.afterRgbUrl, rectangle, 0);
        }

        // Add NDVI change layer (initially hidden)
        if (sentinelData.ndviChangeUrl) {
            this._addImageryLayer('ndvi', sentinelData.ndviChangeUrl, rectangle, 0);
        }

        console.log('[SentinelLayer] Added imagery layers for', location);
    },

    /**
     * Add a single imagery layer
     */
    _addImageryLayer(name, url, rectangle, alpha = 1.0) {
        if (!this._requireViewer()) return;
        try {
            const provider = new Cesium.SingleTileImageryProvider({
                url: url,
                rectangle: rectangle
            });

            const layer = this.viewer.imageryLayers.addImageryProvider(provider);
            layer.alpha = alpha;

            switch (name) {
                case 'before':
                    this.beforeLayer = layer;
                    break;
                case 'after':
                    this.afterLayer = layer;
                    break;
                case 'ndvi':
                    this.ndviLayer = layer;
                    break;
            }
        } catch (error) {
            console.error(`[SentinelLayer] Failed to add ${name} layer:`, error);
        }
    },

    /**
     * Set temporal position (0 = before, 1 = after)
     * Used for slider-based before/after comparison
     */
    setTemporalPosition(position) {
        this.temporalPosition = Math.max(0, Math.min(1, position));

        if (this.beforeLayer) {
            this.beforeLayer.alpha = 1.0 - this.temporalPosition;
        }
        if (this.afterLayer) {
            this.afterLayer.alpha = this.temporalPosition;
        }
    },

    /**
     * Animate transition from before to after
     */
    animateTimelapse(duration = 5000) {
        return new Promise((resolve) => {
            const startTime = Date.now();
            const startPosition = this.temporalPosition;
            const targetPosition = 1.0;

            const animate = () => {
                const elapsed = Date.now() - startTime;
                const progress = Math.min(elapsed / duration, 1);

                // Ease-in-out
                const eased = progress < 0.5
                    ? 2 * progress * progress
                    : 1 - Math.pow(-2 * progress + 2, 2) / 2;

                this.setTemporalPosition(startPosition + (targetPosition - startPosition) * eased);

                if (progress < 1) {
                    requestAnimationFrame(animate);
                } else {
                    resolve();
                }
            };

            animate();
        });
    },

    /**
     * Show/hide NDVI overlay
     */
    showNDVI(visible, animated = true) {
        if (!this.ndviLayer) return;

        if (animated) {
            this._fadeLayer(this.ndviLayer, visible ? 0.7 : 0);
        } else {
            this.ndviLayer.alpha = visible ? 0.7 : 0;
        }
    },

    /**
     * Fade a layer's alpha
     */
    _fadeLayer(layer, targetAlpha, duration = 500) {
        const startAlpha = layer.alpha;
        const startTime = Date.now();

        const animate = () => {
            const elapsed = Date.now() - startTime;
            const progress = Math.min(elapsed / duration, 1);

            layer.alpha = startAlpha + (targetAlpha - startAlpha) * progress;

            if (progress < 1) {
                requestAnimationFrame(animate);
            }
        };

        animate();
    },

    /**
     * Show before view
     */
    showBefore() {
        this.setTemporalPosition(0);
    },

    /**
     * Show after view
     */
    showAfter() {
        this.setTemporalPosition(1);
    },

    /**
     * Reset to initial state
     */
    reset() {
        this.setTemporalPosition(0);
        this.showNDVI(false, false);
    },

    /**
     * Remove all imagery layers
     */
    removeAll() {
        if (!this._requireViewer()) return;
        if (this.beforeLayer) {
            this.viewer.imageryLayers.remove(this.beforeLayer);
            this.beforeLayer = null;
        }
        if (this.afterLayer) {
            this.viewer.imageryLayers.remove(this.afterLayer);
            this.afterLayer = null;
        }
        if (this.ndviLayer) {
            this.viewer.imageryLayers.remove(this.ndviLayer);
            this.ndviLayer = null;
        }
    },

    /**
     * Get imagery metadata
     */
    getMetadata() {
        return {
            hasBefore: !!this.beforeLayer,
            hasAfter: !!this.afterLayer,
            hasNDVI: !!this.ndviLayer,
            bounds: this.bounds,
            temporalPosition: this.temporalPosition
        };
    }
};

// Make globally available
window.SentinelLayer = SentinelLayer;
