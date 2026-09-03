/* ============================================================
   EcoLens - Flutter <-> MapLibre Communication Bridge
   Handles bidirectional messaging between Flutter WebView
   and the MapLibre map instance.
   ============================================================ */

const EcoLensBridge = (() => {
    'use strict';

    /** Whether we're running inside a Flutter InAppWebView */
    const isFlutterWebView = () => {
        return !!(window.flutter_inappwebview &&
                  typeof window.flutter_inappwebview.callHandler === 'function');
    };

    /** Pending event queue for events fired before Flutter is ready */
    const pendingEvents = [];
    let flutterReady = false;

    /**
     * Send an event from the map to Flutter.
     * Falls back to console logging when running standalone in a browser.
     *
     * @param {string} event  - Event name (e.g. 'mapReady', 'featureSelected')
     * @param {object} data   - Payload to send
     */
    const sendToFlutter = (event, data = {}) => {
        const payload = { event, data, timestamp: Date.now() };

        if (isFlutterWebView()) {
            if (!flutterReady && event !== 'mapReady') {
                pendingEvents.push(payload);
                return;
            }
            try {
                window.flutter_inappwebview.callHandler('onMapEvent', JSON.stringify(payload));
            } catch (err) {
                console.warn('[Bridge] Failed to send to Flutter:', err);
            }
        } else {
            // Standalone browser fallback - dispatch a CustomEvent
            console.log(`[Bridge -> Flutter] ${event}`, data);
            window.dispatchEvent(new CustomEvent('ecolens-event', { detail: payload }));
            if (window.parent && window.parent !== window) {
                window.parent.postMessage(JSON.stringify({
                    source: 'ecolens-map',
                    ...payload
                }), '*');
            }
        }
    };

    /**
     * Flush any events that were queued before Flutter signaled readiness.
     */
    const flushPendingEvents = () => {
        flutterReady = true;
        while (pendingEvents.length > 0) {
            const payload = pendingEvents.shift();
            try {
                window.flutter_inappwebview.callHandler('onMapEvent', JSON.stringify(payload));
            } catch (err) {
                console.warn('[Bridge] Failed to flush event:', err);
            }
        }
    };

    /**
     * Receive a command from Flutter and dispatch it to the appropriate handler.
     *
     * @param {string} action - Action name (e.g. 'setView', 'toggleLayer')
     * @param {object} params - Parameters for the action
     * @returns {*} Result of the action handler, if any
     */
    const receiveFromFlutter = (action, params = {}) => {
        console.log(`[Bridge <- Flutter] ${action}`, params);

        const handlers = {
            /**
             * Set the map camera to a specific position.
             * params: { center: [lng, lat], zoom, pitch, bearing, animate }
             */
            setView: (p) => {
                if (!window.ecoMap) return;
                const opts = {};
                if (p.center) opts.center = p.center;
                if (p.zoom !== undefined) opts.zoom = p.zoom;
                if (p.pitch !== undefined) opts.pitch = p.pitch;
                if (p.bearing !== undefined) opts.bearing = p.bearing;
                if (p.animate !== false) {
                    window.ecoMap.flyTo({ ...opts, duration: p.duration || 2000 });
                } else {
                    window.ecoMap.jumpTo(opts);
                }
            },

            /**
             * Toggle a hazard layer's visibility.
             * params: { layer: 'fires', visible: true }
             */
            toggleLayer: (p) => {
                if (window.HazardLayers) {
                    window.HazardLayers.setLayerVisibility(p.layer, p.visible);
                }
                // Also update the sidebar checkbox
                const checkbox = document.getElementById(`toggle-${p.layer}`);
                if (checkbox) checkbox.checked = p.visible;
            },

            /**
             * Apply a filter expression to a layer.
             * params: { layer: 'fires', filter: ['>=', 'confidence', 80] }
             */
            setFilter: (p) => {
                if (window.HazardLayers) {
                    window.HazardLayers.applyFilter(p.layer, p.filter);
                }
            },

            /**
             * Trigger data loading for a specific hazard type.
             * params: { type: 'fires', bbox: [-180,-90,180,90] }
             */
            loadData: async (p) => {
                if (window.DataFetchers) {
                    const fetcher = window.DataFetchers[`fetch${capitalize(p.type)}`];
                    if (fetcher) {
                        const geojson = await fetcher(p.bbox);
                        if (window.HazardLayers) {
                            window.HazardLayers.updateSource(p.type, geojson);
                        }
                        return { success: true, featureCount: geojson.features.length };
                    }
                }
                return { success: false, error: 'Unknown data type' };
            },

            /**
             * Capture a screenshot of the current map canvas.
             * Returns a base64-encoded PNG data URL.
             */
            getScreenshot: () => {
                if (!window.ecoMap) return null;
                const canvas = window.ecoMap.getCanvas();
                return canvas.toDataURL('image/png');
            },

            /**
             * Mark Flutter bridge as ready and flush queued events.
             */
            flutterReady: () => {
                flushPendingEvents();
            },

            /**
             * Get current view state.
             */
            getViewState: () => {
                if (!window.ecoMap) return null;
                const center = window.ecoMap.getCenter();
                return {
                    center: [center.lng, center.lat],
                    zoom: window.ecoMap.getZoom(),
                    pitch: window.ecoMap.getPitch(),
                    bearing: window.ecoMap.getBearing(),
                    bounds: window.ecoMap.getBounds().toArray()
                };
            },

            /**
             * Enable or disable 3D terrain.
             * params: { enabled: true, exaggeration: 1.5 }
             */
            setTerrain: (p) => {
                if (!window.ecoMap) return;
                if (p.enabled) {
                    window.ecoMap.setTerrain({
                        source: 'terrain-source',
                        exaggeration: p.exaggeration || 1.5
                    });
                } else {
                    window.ecoMap.setTerrain(null);
                }
            }
        };

        const handler = handlers[action];
        if (handler) {
            return handler(params);
        } else {
            console.warn(`[Bridge] Unknown action: ${action}`);
            return { error: `Unknown action: ${action}` };
        }
    };

    /**
     * Capitalize the first letter of a string.
     * @param {string} s
     * @returns {string}
     */
    const capitalize = (s) => s.charAt(0).toUpperCase() + s.slice(1);

    // ---------- Supported Events Reference ----------
    // mapReady        - Map finished initializing, layers ready
    // featureSelected - User clicked a hazard feature
    // layerToggled    - Layer visibility changed
    // viewChanged     - Camera position changed (debounced)
    // hazardAlert     - New high-severity hazard detected
    // dataLoaded      - Data fetch completed
    // error           - An error occurred

    /**
     * Show a toast notification on the map UI.
     * @param {string} message
     * @param {'info'|'success'|'error'} type
     * @param {number} duration - ms to display
     */
    const showToast = (message, type = 'info', duration = 4000) => {
        const toast = document.createElement('div');
        toast.className = `toast-notification ${type}`;
        toast.textContent = message;
        document.body.appendChild(toast);

        // Trigger reflow then show
        requestAnimationFrame(() => {
            toast.classList.add('visible');
        });

        setTimeout(() => {
            toast.classList.remove('visible');
            setTimeout(() => toast.remove(), 400);
        }, duration);
    };

    // Expose receiveFromFlutter globally so Flutter can call it
    window.receiveFromFlutter = receiveFromFlutter;

    // Also expose a convenience wrapper for Flutter JS evaluation
    window.callMapAction = (actionJson) => {
        try {
            const { action, params } = JSON.parse(actionJson);
            return receiveFromFlutter(action, params);
        } catch (e) {
            console.error('[Bridge] Invalid action JSON:', e);
            return { error: 'Invalid JSON' };
        }
    };

    return {
        sendToFlutter,
        receiveFromFlutter,
        showToast,
        isFlutterWebView,
        flushPendingEvents
    };
})();

// Make it globally accessible
window.EcoLensBridge = EcoLensBridge;
