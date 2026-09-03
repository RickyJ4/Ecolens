/* ============================================================
   EcoLens - Filter Controls & UI Interactions
   Manages sidebar toggles, filters, opacity sliders, search,
   basemap switching, time slider, and export functionality.
   ============================================================ */

const FilterControls = (() => {
    'use strict';

    /** Debounce timers */
    let geocodeTimer = null;
    let timeAnimationId = null;
    let timeAnimationPlaying = false;

    // ==========================================================
    //  INITIALIZATION
    // ==========================================================

    /**
     * Initialize all UI controls and event listeners.
     * Call after DOM is ready.
     */
    const init = () => {
        setupSidebarToggle();
        setupLayerToggles();
        setupSeverityFilters();
        setupOpacitySliders();
        setupGeocoder();
        setupBasemapSwitcher();
        setupTimeSlider();
        setupInfoPanel();
        setupExportButton();
        applyTimeWindow(168, { hydrate: false });

        console.log('[FilterControls] All controls initialized');
    };

    // ==========================================================
    //  SIDEBAR TOGGLE
    // ==========================================================

    const setupSidebarToggle = () => {
        const toggleBtn = document.getElementById('sidebar-toggle');
        const sidebar = document.getElementById('sidebar');
        if (!toggleBtn || !sidebar) return;

        // Toggle button (hamburger menu) opens/closes the sidebar
        toggleBtn.addEventListener('click', () => {
            sidebar.classList.toggle('collapsed');
            toggleBtn.classList.toggle('shifted');
        });

        // Close button (X) inside the sidebar header
        const closeBtn = document.getElementById('sidebar-close');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                sidebar.classList.add('collapsed');
                toggleBtn.classList.remove('shifted');
            });
        }
    };

    // ==========================================================
    //  HAZARD LAYER TOGGLES
    // ==========================================================

    const setupLayerToggles = () => {
        const layerTypes = ['fires', 'hotspots', 'bivariate', 'floods', 'drought', 'glaciers', 'ndvi', 'earthquakes', 'airquality', 'volcanoes', 'watershed', 'risk'];

        layerTypes.forEach(type => {
            const checkbox = document.getElementById(`toggle-${type}`);
            if (!checkbox) return;

            checkbox.addEventListener('change', () => {
                const visible = checkbox.checked;

                // HazardLayers.map may not be ready yet if map is still loading.
                // Retry after a short delay if the map isn't initialized.
                const applyToggle = () => {
                    if (typeof HazardLayers !== 'undefined' && HazardLayers.isReady && HazardLayers.isReady()) {
                        HazardLayers.setLayerVisibility(type, visible);
                    } else if (window.ecoMap) {
                        // Fallback: directly toggle via the global map reference
                        try {
                            const layerIds = {
                                fires: ['fire-hotspots-layer', 'fire-hotspots-glow'],
                                floods: ['floods-fill', 'floods-outline', 'floods-gauges', 'floods-depth'],
                                drought: ['drought-fill', 'drought-labels'],
                                glaciers: ['glaciers-fill', 'glaciers-extrusion', 'glaciers-outline', 'glaciers-labels'],
                                ndvi: ['ndvi-layer'],
                                earthquakes: ['earthquakes-glow', 'earthquakes-circle', 'earthquakes-labels'],
                                airquality: ['airquality-glow', 'airquality-circle', 'airquality-labels'],
                                volcanoes: ['volcanoes-glow', 'volcanoes-circle', 'volcanoes-symbol', 'volcanoes-labels'],
                                watershed: ['watershed-fill', 'watershed-outline', 'watershed-streams', 'watershed-labels'],
                                risk: ['risk-heatmap']
                            };
                            const ids = layerIds[type] || [];
                            ids.forEach(id => {
                                if (window.ecoMap.getLayer(id)) {
                                    window.ecoMap.setLayoutProperty(id, 'visibility', visible ? 'visible' : 'none');
                                }
                            });
                        } catch (e) {
                            console.warn(`[FilterControls] Could not toggle ${type}:`, e.message);
                        }
                    } else {
                        // Map not ready yet — retry in 500ms
                        setTimeout(applyToggle, 500);
                    }
                };
                applyToggle();

                // Update legend visibility
                const legendItem = document.querySelector(`.legend-item[data-legend="${type}"]`);
                if (legendItem) {
                    legendItem.style.display = visible ? 'block' : 'none';
                }
            });
        });
    };

    // ==========================================================
    //  SEVERITY FILTERS
    // ==========================================================

    const setupSeverityFilters = () => {
        // Fire confidence filter
        const fireFilter = document.getElementById('filter-fire-confidence');
        if (fireFilter) {
            fireFilter.addEventListener('change', () => {
                const value = fireFilter.value;
                let filter = null;

                switch (value) {
                    case 'high':
                        filter = ['==', ['get', 'confidence'], 'high'];
                        break;
                    case 'nominal':
                        filter = ['in', ['get', 'confidence'], ['literal', ['high', 'nominal']]];
                        break;
                    case 'low':
                        // Show all (low and above) - no filter needed
                        filter = null;
                        break;
                    default:
                        filter = null;
                }

                HazardLayers.applyFilter('fires', filter);
                updateFilteredCount('fires');
            });
        }

        // Flood severity filter
        const floodFilter = document.getElementById('filter-flood-severity');
        if (floodFilter) {
            floodFilter.addEventListener('change', () => {
                const value = floodFilter.value;
                let filter = null;

                switch (value) {
                    case 'major':
                        filter = ['==', ['get', 'status'], 'major'];
                        break;
                    case 'moderate':
                        filter = ['in', ['get', 'status'], ['literal', ['major', 'moderate']]];
                        break;
                    case 'minor':
                        filter = ['in', ['get', 'status'], ['literal', ['major', 'moderate', 'minor']]];
                        break;
                    default:
                        filter = null;
                }

                HazardLayers.applyFilter('floods', filter);
                updateFilteredCount('floods');
            });
        }

        // Drought level filter
        const droughtFilter = document.getElementById('filter-drought-level');
        if (droughtFilter) {
            droughtFilter.addEventListener('change', () => {
                const value = droughtFilter.value;
                let filter = null;

                switch (value) {
                    case 'D4':
                        filter = ['==', ['get', 'max_severity'], 'D4'];
                        break;
                    case 'D3':
                        filter = ['in', ['get', 'max_severity'], ['literal', ['D3', 'D4']]];
                        break;
                    case 'D2':
                        filter = ['in', ['get', 'max_severity'], ['literal', ['D2', 'D3', 'D4']]];
                        break;
                    case 'D1':
                        filter = ['in', ['get', 'max_severity'], ['literal', ['D1', 'D2', 'D3', 'D4']]];
                        break;
                    default:
                        filter = null;
                }

                HazardLayers.applyFilter('drought', filter);
                updateFilteredCount('drought');
            });
        }
    };

    /**
     * Update the feature count badge after a filter is applied.
     * Queries the map for visible features in the layer.
     *
     * @param {string} hazardType
     */
    const updateFilteredCount = (hazardType) => {
        const map = window.ecoMap;
        if (!map) return;

        // Small delay to let the filter take effect
        setTimeout(() => {
            const def = HazardLayers.LAYER_DEFS[hazardType];
            if (!def) return;

            // Query rendered features across all layers for this hazard
            let totalCount = 0;
            def.layers.forEach(layerDef => {
                if (map.getLayer(layerDef.id)) {
                    try {
                        const features = map.queryRenderedFeatures({ layers: [layerDef.id] });
                        totalCount += features.length;
                    } catch (e) {
                        // Some layers may not support querying
                    }
                }
            });

            const countEl = document.getElementById(`count-${hazardType}`);
            if (countEl && totalCount > 0) {
                countEl.textContent = totalCount;
            }
        }, 100);
    };

    // ==========================================================
    //  OPACITY SLIDERS
    // ==========================================================

    const setupOpacitySliders = () => {
        const sliderTypes = ['fires', 'hotspots', 'bivariate', 'floods', 'drought', 'glaciers', 'risk'];

        sliderTypes.forEach(type => {
            const slider = document.getElementById(`opacity-${type}`);
            const valueLabel = document.getElementById(`opacity-val-${type}`);
            if (!slider) return;

            slider.addEventListener('input', () => {
                const opacity = parseInt(slider.value) / 100;
                if (valueLabel) {
                    valueLabel.textContent = `${slider.value}%`;
                }
                HazardLayers.setLayerOpacity(type, opacity);
            });
        });
    };

    // ==========================================================
    //  GEOCODER / SEARCH
    // ==========================================================

    const setupGeocoder = () => {
        const input = document.getElementById('geocode-input');
        const btn = document.getElementById('geocode-btn');
        const resultsContainer = document.getElementById('geocode-results');
        if (!input || !resultsContainer) return;

        // Debounced input search
        input.addEventListener('input', () => {
            clearTimeout(geocodeTimer);
            const query = input.value.trim();

            if (query.length < 3) {
                resultsContainer.classList.remove('visible');
                return;
            }

            geocodeTimer = setTimeout(async () => {
                const results = await MapCore.geocode(query);
                displayGeocodeResults(results, resultsContainer);
            }, 400);
        });

        // Search button click
        if (btn) {
            btn.addEventListener('click', async () => {
                const query = input.value.trim();
                if (query.length < 2) return;

                const results = await MapCore.geocode(query);
                if (results.length > 0) {
                    MapCore.flyToResult(results[0]);
                    resultsContainer.classList.remove('visible');
                }
            });
        }

        // Enter key
        input.addEventListener('keydown', async (e) => {
            if (e.key === 'Enter') {
                const query = input.value.trim();
                if (query.length < 2) return;

                const results = await MapCore.geocode(query);
                if (results.length > 0) {
                    MapCore.flyToResult(results[0]);
                    resultsContainer.classList.remove('visible');
                }
            }
        });

        // Close results when clicking outside
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.search-container')) {
                resultsContainer.classList.remove('visible');
            }
        });
    };

    /**
     * Display geocode search results in the dropdown.
     *
     * @param {Array} results
     * @param {HTMLElement} container
     */
    const displayGeocodeResults = (results, container) => {
        container.innerHTML = '';

        if (results.length === 0) {
            container.innerHTML = '<div class="geocode-result-item">No results found</div>';
            container.classList.add('visible');
            return;
        }

        results.forEach(result => {
            const item = document.createElement('div');
            item.className = 'geocode-result-item';
            item.textContent = result.name.length > 80
                ? result.name.substring(0, 80) + '...'
                : result.name;

            item.addEventListener('click', () => {
                MapCore.flyToResult(result);
                container.classList.remove('visible');
                document.getElementById('geocode-input').value = result.name.split(',')[0];
            });

            container.appendChild(item);
        });

        container.classList.add('visible');
    };

    // ==========================================================
    //  BASEMAP SWITCHER
    // ==========================================================

    const setupBasemapSwitcher = () => {
        const buttons = document.querySelectorAll('.basemap-btn');

        buttons.forEach(btn => {
            btn.addEventListener('click', () => {
                const styleName = btn.dataset.style;
                if (!styleName) return;

                // Update active state
                buttons.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');

                // Switch basemap
                MapCore.switchBasemap(styleName);
            });
        });
    };

    // ==========================================================
    //  TIME SLIDER
    // ==========================================================

    const setupTimeSlider = () => {
        const slider = document.getElementById('time-slider');
        const playBtn = document.getElementById('time-play-btn');
        if (!slider) return;

        document.querySelectorAll('.time-window-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const hours = parseInt(btn.dataset.hours || '168', 10);
                document.querySelectorAll('.time-window-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                slider.value = String(hours);
                applyTimeWindow(hours, { hydrate: true });
            });
        });

        slider.addEventListener('input', () => {
            const hours = parseInt(slider.value, 10);
            setActiveWindowButton(hours);
            applyTimeWindow(hours, { hydrate: false });
        });

        slider.addEventListener('change', () => {
            const hours = parseInt(slider.value, 10);
            applyTimeWindow(hours, { hydrate: true });
        });

        if (playBtn) {
            playBtn.addEventListener('click', () => {
                if (timeAnimationPlaying) {
                    stopTimeAnimation();
                } else {
                    startTimeAnimation();
                }
            });
        }
    };

    /**
     * Update the time label display.
     * @param {number} hoursValue - Number of hours back from now
     */
    const updateTimeLabel = (hoursValue) => {
        const currentLabel = document.getElementById('time-current');
        const startLabel = document.getElementById('time-label-start');
        if (!currentLabel) return;

        const hours = Math.max(1, Number(hoursValue) || 168);
        const targetDate = new Date(Date.now() - hours * 3600 * 1000);
        const label = formatWindowLabel(hours);

        currentLabel.textContent = label;
        if (startLabel) {
            const options = hours > 720
                ? { month: 'short', year: 'numeric' }
                : { month: 'short', day: 'numeric' };
            startLabel.textContent = targetDate.toLocaleDateString('en-US', options);
        }
    };

    const formatWindowLabel = (hours) => {
        if (hours <= 24) return 'Last 24 hours';
        if (hours <= 168) return 'Last 7 days';
        if (hours <= 720) return 'Last 30 days';
        return 'Last 12 months';
    };

    const setActiveWindowButton = (hours) => {
        const presets = [24, 168, 720, 8760];
        const match = presets.find(p => Math.abs(p - hours) <= (p === 24 ? 4 : p * 0.04));
        document.querySelectorAll('.time-window-btn').forEach(btn => {
            btn.classList.toggle('active', match != null && parseInt(btn.dataset.hours || '0', 10) === match);
        });
    };

    const hydrateWindowData = async (hours) => {
        if (typeof DataFetchers === 'undefined' || typeof HazardLayers === 'undefined') return;
        const days = Math.ceil(hours / 24);
        const tasks = [
            DataFetchers.fetchEarthquakes(hours)
                .then(data => HazardLayers.updateSource('earthquakes', data)),
            DataFetchers.fetchActiveFires(null, Math.min(days, 10))
                .then(data => HazardLayers.updateSource('fires', data)),
        ];
        await Promise.allSettled(tasks);
    };

    const applyTimeWindow = async (hours, { hydrate = false } = {}) => {
        const safeHours = Math.max(1, Number(hours) || 168);
        window.EcoLensTimeWindowHours = safeHours;
        updateTimeLabel(safeHours);

        if (typeof HazardLayers !== 'undefined' && HazardLayers.applyTimeWindow) {
            HazardLayers.applyTimeWindow(safeHours);
        }

        if (hydrate) {
            await hydrateWindowData(safeHours);
            if (typeof HazardLayers !== 'undefined' && HazardLayers.applyTimeWindow) {
                HazardLayers.applyTimeWindow(safeHours);
            }
        }

        if (window.EcoLensEventIntelligence?.refresh) {
            window.EcoLensEventIntelligence.refresh();
        }
    };

    /**
     * Start time animation - automatically advances the slider.
     */
    const startTimeAnimation = () => {
        // Honest playback: the live feeds are only days deep, so sweeping a
        // synthetic 12-month window animated nothing (verified 2026-07-28).
        // Play now replays REAL archived days when the hazard archive has
        // them; the window sweep survives only as a fallback for a fresh
        // install, and only across the range live data actually covers.
        if (window.TimePlayback && window.HistoryArchive &&
            window.HistoryArchive.archiveDays &&
            window.HistoryArchive.archiveDays('fires').length > 1) {
            window.TimePlayback.enterAndPlay();
            return;
        }

        const slider = document.getElementById('time-slider');
        const playIcon = document.getElementById('play-icon');
        const pauseIcon = document.getElementById('pause-icon');
        if (!slider) return;

        timeAnimationPlaying = true;
        if (playIcon) playIcon.style.display = 'none';
        if (pauseIcon) pauseIcon.style.display = 'block';

        slider.value = 24;
        applyTimeWindow(24, { hydrate: false });

        const step = () => {
            if (!timeAnimationPlaying) return;

            let val = parseInt(slider.value);
            if (val >= 168) { // live fires data never exceeds 7 days
                stopTimeAnimation();
                return;
            }

            val = Math.min(168, Math.ceil(val * 1.22 + 12));
            slider.value = val;
            setActiveWindowButton(val);
            applyTimeWindow(val, { hydrate: false });

            timeAnimationId = setTimeout(step, 220);
        };

        step();
    };

    /**
     * Stop time animation.
     */
    const stopTimeAnimation = () => {
        timeAnimationPlaying = false;
        if (timeAnimationId) {
            clearTimeout(timeAnimationId);
            timeAnimationId = null;
        }

        const playIcon = document.getElementById('play-icon');
        const pauseIcon = document.getElementById('pause-icon');
        if (playIcon) playIcon.style.display = 'block';
        if (pauseIcon) pauseIcon.style.display = 'none';
    };

    // ==========================================================
    //  INFO PANEL
    // ==========================================================

    const setupInfoPanel = () => {
        const closeBtn = document.getElementById('info-panel-close');
        const panel = document.getElementById('info-panel');
        if (!closeBtn || !panel) return;

        closeBtn.addEventListener('click', () => {
            panel.classList.add('hidden');
        });
    };

    // ==========================================================
    //  EXPORT / SCREENSHOT
    // ==========================================================

    const setupExportButton = () => {
        const exportBtn = document.getElementById('export-btn');
        if (!exportBtn) return;

        exportBtn.addEventListener('click', () => {
            MapCore.downloadScreenshot();
        });
    };

    // ==========================================================
    //  LEGEND MANAGEMENT
    // ==========================================================

    /**
     * Update legend visibility based on which layers are active.
     * Called when layer toggles change.
     */
    const updateLegend = () => {
        const layerTypes = ['fires', 'floods', 'drought', 'ndvi'];
        layerTypes.forEach(type => {
            const checkbox = document.getElementById(`toggle-${type}`);
            const legendItem = document.querySelector(`.legend-item[data-legend="${type}"]`);
            if (checkbox && legendItem) {
                legendItem.style.display = checkbox.checked ? 'block' : 'none';
            }
        });
    };

    // ==========================================================
    //  Public API
    // ==========================================================

    return {
        init,
        updateLegend,
        stopTimeAnimation,
        applyTimeWindow,
        updateFilteredCount
    };
})();

// Global access
window.FilterControls = FilterControls;

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    FilterControls.init();
});
