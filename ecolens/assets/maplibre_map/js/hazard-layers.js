/* ============================================================
   EcoLens - Hazard Layer Definitions & Management
   Manages all hazard visualization layers on the MapLibre map:
   fires, floods, drought, glaciers, NDVI, watersheds, risk.
   ============================================================ */

const HazardLayers = (() => {
    'use strict';

    /** Reference to the MapLibre map instance (set during init) */
    let map = null;

    /** Track which layers are currently added to the map */
    const activeLayers = new Map();

    /** Animation frame IDs for pulsing effects */
    let fireAnimationId = null;

    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (ch) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[ch]));

    const confidenceLabel = (value) => {
        const v = String(value || '').toLowerCase();
        if (v === 'h' || v.startsWith('high')) return 'High confidence';
        if (v === 'n' || v.startsWith('nominal')) return 'Nominal confidence';
        if (v === 'l' || v.startsWith('low')) return 'Low confidence';
        return value ? `${value} confidence` : 'Confidence not supplied';
    };

    const fireOperationalRead = (props) => {
        const frp = Number(props.frp) || 0;
        const brightness = Number(props.brightness_temp || props.brightness) || 0;
        const severity = frp >= 300 ? 'Extreme heat signal'
            : frp >= 120 ? 'High-intensity fire signal'
            : frp >= 40 ? 'Active fire signal'
            : 'Low-intensity thermal signal';
        const radiusKm = frp >= 300 ? 30 : frp >= 120 ? 18 : frp >= 40 ? 10 : 5;
        const driver = brightness >= 360 || frp >= 120
            ? 'Potential rapid spread if wind, slope, or dry fuels align.'
            : 'Verify against local fuels, wind, and containment reports.';
        return { frp, brightness, severity, radiusKm, driver };
    };

    /**
     * Read live wind + precip context for a given lat/lon, if the
     * IntelligenceLayers module has loaded its data. Returns HTML snippet
     * suitable for appending to a popup, or empty string if no data yet.
     */
    const correlationContext = (lat, lon) => {
        if (!window.IntelligenceLayers || lat == null || lon == null) return '';
        const wind = window.IntelligenceLayers.sampleWindAt(lat, lon);
        const precip = window.IntelligenceLayers.samplePrecipAt(lat, lon);
        if (!wind && !precip) return '';
        const windHtml = wind
            ? `<div class="popup-row"><span class="popup-key">Live wind</span><span class="popup-value">${wind.wind_speed?.toFixed?.(0)} km/h @ ${wind.wind_direction?.toFixed?.(0)}°</span></div>`
            : '';
        const precipHtml = precip > 0.5
            ? `<div class="popup-row"><span class="popup-key">48 h rain forecast</span><span class="popup-value">${precip.toFixed(1)} mm</span></div>`
            : '';
        return windHtml + precipHtml;
    };

    // ==========================================================
    //  LAYER DEFINITIONS
    // ==========================================================

    /**
     * Source and layer definitions for each hazard type.
     * Each entry contains the source config, one or more layer configs,
     * and popup configuration.
     */
    const LAYER_DEFS = {

        // ----------------------------------------------------------
        //  FIRE HOTSPOTS
        // ----------------------------------------------------------
        fires: {
            sourceId: 'fires-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] },
                // Clustering disabled — was silently swallowing point rendering
                // after setData under some MapLibre versions. Direct point render
                // is more reliable and still performant for ~5k features.
            },
            layers: [
                // ─── LOW-ZOOM: Heatmap surface (density field) ───
                // Renders from zoom 0-7: a smooth red/orange density surface.
                // Handles ~40k features cleanly without visual clutter.
                {
                    id: 'fires-heatmap',
                    type: 'heatmap',
                    maxzoom: 8,
                    paint: {
                        // Weight each pixel by FRP — strong fires pull the surface harder
                        'heatmap-weight': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'frp'], 1],
                            0, 0.2,
                            50, 0.5,
                            150, 0.8,
                            300, 1,
                        ],
                        // Restrained at global zoom — the significance layer
                        // carries the "meaning" story there; raw density
                        // strengthens as you approach (meaning → data policy).
                        // Kept LOW below z4: at world zoom, agricultural-burning
                        // belts (Central Africa in July) were rendering as one
                        // solid crimson slab with zero interior structure.
                        'heatmap-intensity': [
                            'interpolate', ['linear'], ['zoom'],
                            0, 0.18,
                            3, 0.35,
                            5, 0.9,
                            7, 2.0,
                        ],
                        // YlOrRd character, capped at the theme's fire tokens.
                        // The bottom stop starts at 0.28 density so isolated
                        // single detections don't speckle the whole planet
                        // with straw-yellow halos at world zoom.
                        'heatmap-color': [
                            'interpolate', ['linear'], ['heatmap-density'],
                            0,    'rgba(0, 0, 0, 0)',
                            0.28, 'rgba(255, 237, 160, 0.45)',
                            0.50, 'rgba(254, 178, 76, 0.60)',
                            0.70, 'rgba(253, 141, 60, 0.70)',
                            0.88, 'rgba(217, 95, 60, 0.78)',
                            1.00, 'rgba(179, 54, 43, 0.85)',
                        ],
                        // Radius scales with zoom so hotspot clusters stay visible
                        'heatmap-radius': [
                            'interpolate', ['linear'], ['zoom'],
                            0, 2.5,
                            3, 6,
                            7, 20,
                        ],
                        // Quieter at global zoom, full by regional, out at points
                        'heatmap-opacity': [
                            'interpolate', ['linear'], ['zoom'],
                            0, 0.45,
                            4, 0.7,
                            6, 0.9,
                            8, 0,
                        ],
                    },
                },

                // ─── MID/HIGH-ZOOM: Individual fire points ───
                // Only visible from zoom 6+. Color by confidence, size by FRP.
                {
                    id: 'fires-points',
                    type: 'circle',
                    minzoom: 6,
                    paint: {
                        'circle-color': [
                            'match',
                            ['get', 'confidence'],
                            'low', '#FCD34D',
                            'nominal', '#F97316',
                            'high', '#DC2626',
                            '#F97316',
                        ],
                        'circle-radius': [
                            'interpolate', ['linear'], ['zoom'],
                            6, ['interpolate', ['linear'], ['coalesce', ['get', 'frp'], 0], 0, 2, 300, 5],
                            10, ['interpolate', ['linear'], ['coalesce', ['get', 'frp'], 0], 0, 4, 300, 12],
                            14, ['interpolate', ['linear'], ['coalesce', ['get', 'frp'], 0], 0, 8, 300, 24],
                        ],
                        // Dots stay whisper-quiet until the heatmap has fully
                        // handed over (~z8) — mid-zoom was drowning the map
                        // in solid orange at continental fire densities.
                        'circle-opacity': [
                            'interpolate', ['linear'], ['zoom'],
                            6, 0.12,
                            7, 0.45,
                            8, 0.9,
                        ],
                        'circle-stroke-color': '#FFFFFF',
                        'circle-stroke-width': [
                            'interpolate', ['linear'], ['zoom'],
                            6, 0,
                            9, 0.8,
                        ],
                        'circle-stroke-opacity': 0.7,
                    },
                },

                // Kept as empty-filter stubs so existing moveLayer/popup code doesn't error.
                { id: 'fires-clusters',      type: 'circle', filter: ['==', 'never', 'true'], paint: { 'circle-opacity': 0 } },
                { id: 'fires-cluster-count', type: 'circle', filter: ['==', 'never', 'true'], paint: { 'circle-opacity': 0 } },
                { id: 'fires-glow',          type: 'circle', filter: ['==', 'never', 'true'], paint: { 'circle-opacity': 0 } },
            ],
            popup: (props) => {
                const read = fireOperationalRead(props);
                const detected = [props.acq_date, props.acq_time].filter(Boolean).join(' ');
                const name = props.fire_name ? escapeHtml(props.fire_name) : 'Unnamed detection';
                return `
                    <div class="popup-title">Wildfire Detection - ${read.severity}</div>
                    <div class="popup-note">
                        ${name}. NASA FIRMS detected an active thermal anomaly here; treat this as a verification queue item, not a final incident boundary.
                    </div>
                    <div class="popup-row"><span class="popup-key">Operational priority</span><span class="popup-value">${read.frp >= 120 ? 'Verify now' : 'Monitor'}</span></div>
                    <div class="popup-row"><span class="popup-key">Impact radius</span><span class="popup-value">${read.radiusKm} km watch zone</span></div>
                    <div class="popup-row"><span class="popup-key">Weather concern</span><span class="popup-value">${read.driver}</span></div>
                    <div class="popup-row"><span class="popup-key">Fire power</span><span class="popup-value">${read.frp.toFixed(1)} MW FRP</span></div>
                    <div class="popup-row"><span class="popup-key">Brightness</span><span class="popup-value">${Math.round(read.brightness || 0)}K</span></div>
                    <div class="popup-row"><span class="popup-key">Confidence</span><span class="popup-value">${confidenceLabel(props.confidence)}</span></div>
                    <div class="popup-row"><span class="popup-key">Satellite</span><span class="popup-value">${escapeHtml(props.satellite || 'Unknown')}</span></div>
                    <div class="popup-row"><span class="popup-key">Detected</span><span class="popup-value">${escapeHtml(detected || 'Unknown')}</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  FIRE HOT-SPOT SIGNIFICANCE (client-side Getis-Ord Gi*)
        //  Computed by SpatialStats from whatever is in fires-source;
        //  answers "do these detections mean anything?" rather than
        //  re-drawing them.
        // ----------------------------------------------------------
        hotspots: {
            sourceId: 'hotspots-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                {
                    id: 'hotspots-fill',
                    type: 'fill',
                    paint: {
                        'fill-color': [
                            'match', ['get', 'p_bucket'],
                            'hot99', '#B2182B',
                            'hot95', '#EF8A62',
                            'cold95', '#67A9CF',
                            'rgba(255,255,255,0.04)'  // ns: barely-there context
                        ],
                        // The hexes are a LOW-zoom reading aid. Up close they
                        // were giant opaque slabs burying the town they were
                        // about — so the fill hands over to the raw detections
                        // as you approach, leaving only the outline.
                        'fill-opacity': [
                            'interpolate', ['linear'], ['zoom'],
                            5, ['match', ['get', 'p_bucket'],
                                'hot99', 0.5, 'hot95', 0.38, 'cold95', 0.32, 0.08],
                            7.5, ['match', ['get', 'p_bucket'],
                                'hot99', 0.22, 'hot95', 0.16, 'cold95', 0.12, 0.03],
                            9, 0,
                        ],
                    },
                },
                {
                    id: 'hotspots-outline',
                    type: 'line',
                    filter: ['!=', ['get', 'p_bucket'], 'ns'],
                    paint: {
                        'line-color': [
                            'match', ['get', 'p_bucket'],
                            'hot99', '#B2182B',
                            'hot95', '#EF8A62',
                            'cold95', '#67A9CF',
                            '#999999'
                        ],
                        'line-width': 1,
                        'line-opacity': 0.8,
                    },
                },
            ],
            popup: (props) => {
                // Plain language first: what a reader should take away,
                // then the numbers, then the method as fine print.
                const z = Number(props.gi_z);
                const count = Number(props.count) || 0;
                const mw = Math.round(Number(props.sum_frp) || 0);
                let headline, meaning;
                if (props.p_bucket === 'hot99' || props.p_bucket === 'hot95') {
                    headline = 'This area is burning hard';
                    meaning = `${count} separate fires were detected in this one ` +
                        `25&nbsp;km patch this week — far more than the land around it. ` +
                        `A concentration like this is real fire behaviour, not chance` +
                        (props.p_bucket === 'hot99' ? ' (better than 99% certainty).' : ' (better than 95% certainty).');
                } else if (props.p_bucket === 'cold95') {
                    headline = 'Unusually quiet here';
                    meaning = 'Noticeably fewer fires than the surrounding region — a genuine gap, not missing data.';
                } else {
                    headline = 'Nothing unusual here';
                    meaning = 'Fire activity in this patch is within the normal range for its surroundings.';
                }
                return `
                    <div class="popup-title">${headline}</div>
                    <div class="popup-note">${meaning}</div>
                    <div class="popup-row"><span class="popup-key">Fires detected</span><span class="popup-value">${count.toLocaleString()}</span></div>
                    <div class="popup-row"><span class="popup-key">Heat output</span><span class="popup-value">${mw.toLocaleString()} MW — roughly ${Math.max(1, Math.round(mw / 750))}× a power station</span></div>
                    <div class="popup-row"><span class="popup-key">How sure</span><span class="popup-value">${isFinite(z) ? (z >= 2.58 ? 'Very (z=' + z.toFixed(1) + ')' : z >= 1.96 ? 'Confident (z=' + z.toFixed(1) + ')' : 'Not significant') : '--'}</span></div>
                    <div class="popup-row popup-fineprint"><span class="popup-key">Method</span><span class="popup-value">Getis-Ord Gi* on 25 km hexes, computed in your browser from live NASA FIRMS data</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  BIVARIATE: FIRE DENSITY × DROUGHT (CONUS, computed by Bivariate)
        // ----------------------------------------------------------
        bivariate: {
            sourceId: 'bivariate-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                {
                    id: 'bivariate-fill',
                    type: 'fill',
                    paint: {
                        'fill-color': ['coalesce', ['get', 'bi_color'], '#e8e8e8'],
                        'fill-opacity': 0.62,
                    },
                },
                {
                    id: 'bivariate-outline',
                    type: 'line',
                    paint: {
                        'line-color': 'rgba(255,255,255,0.25)',
                        'line-width': 0.5,
                    },
                },
            ],
            popup: (props) => `
                <div class="popup-title">Fire × Drought</div>
                <div class="popup-note">Two variables, one cell — where fire activity and drought stress overlap.</div>
                <div class="popup-row"><span class="popup-key">Fire density</span><span class="popup-value">${props.fire_label || '--'} tercile (${props.count} detections)</span></div>
                <div class="popup-row"><span class="popup-key">Drought</span><span class="popup-value">${props.drought_label || 'None–D1'}${props.drought_area ? ' (' + props.drought_area + ')' : ''}</span></div>
                <div class="popup-row"><span class="popup-key">Scope</span><span class="popup-value">Contiguous US · USDM + FIRMS</span></div>
                <div class="popup-row"><span class="popup-key">Cell</span><span class="popup-value">50 km hex</span></div>
            `
        },

        // ----------------------------------------------------------
        //  FLOOD ZONES
        // ----------------------------------------------------------
        floods: {
            sourceId: 'floods-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Flood zone fill (NWS flood severity colors)
                {
                    id: 'floods-fill',
                    type: 'fill',
                    paint: {
                        'fill-color': [
                            'match',
                            ['get', 'status'],
                            'record', '#8B008B',    // Dark magenta
                            'major', '#CC00CC',     // Purple
                            'moderate', '#FF0000',  // Red
                            'minor', '#FFA500',     // Orange
                            'action', '#FFFF00',    // Yellow
                            'none', '#00FF00',      // Green
                            '#00FF00'               // Default: green
                        ],
                        'fill-opacity': 0.4
                    }
                },
                // Flood depth polygon gradient (blue)
                {
                    id: 'floods-depth',
                    type: 'fill',
                    filter: ['has', 'depth_m'],
                    paint: {
                        'fill-color': [
                            'interpolate', ['linear'],
                            ['get', 'depth_m'],
                            0, '#C6E2FF',     // Lightest blue
                            0.5, '#6BAED6',
                            1, '#3182BD',
                            2, '#08519C',
                            5, '#042A60'      // Darkest blue
                        ],
                        'fill-opacity': 0.5
                    }
                },
                // Flood zone outline (dashed)
                {
                    id: 'floods-outline',
                    type: 'line',
                    paint: {
                        'line-color': [
                            'match',
                            ['get', 'status'],
                            'record', '#8B008B',
                            'major', '#CC00CC',
                            'moderate', '#FF0000',
                            'minor', '#FFA500',
                            'action', '#FFFF00',
                            '#00FF00'
                        ],
                        'line-width': 2,
                        'line-dasharray': [3, 2],
                        'line-opacity': 0.8
                    }
                },
                // Gauge point markers (NWS severity)
                {
                    id: 'floods-gauges',
                    type: 'circle',
                    paint: {
                        'circle-color': [
                            'match',
                            ['get', 'status'],
                            'record', '#8B008B',
                            'major', '#CC00CC',
                            'moderate', '#FF0000',
                            'minor', '#FFA500',
                            'action', '#FFFF00',
                            'none', '#00FF00',
                            '#00FF00'
                        ],
                        'circle-radius': 6,
                        'circle-stroke-width': 2,
                        'circle-stroke-color': '#ffffff'
                    }
                }
            ],
            // Override source for gauge points (derived from flood features)
            gaugeSourceId: 'floods-gauge-source',
            popup: (props) => {
                const statusColors = {
                    record: '#8B008B', major: '#CC00CC', moderate: '#FF0000', minor: '#FFA500', action: '#FFFF00', none: '#00FF00'
                };
                return `
                    <div class="popup-title">Flood Zone</div>
                    <div class="popup-row"><span class="popup-key">Gauge</span><span class="popup-value">${props.name}</span></div>
                    <div class="popup-row"><span class="popup-key">Status</span><span class="popup-value" style="color:${statusColors[props.status] || '#fff'};font-weight:700;">${(props.status || '').toUpperCase()}</span></div>
                    <div class="popup-row"><span class="popup-key">Stage</span><span class="popup-value">${props.stage} ft</span></div>
                    <div class="popup-row"><span class="popup-key">Flow</span><span class="popup-value">${props.flow ? props.flow.toLocaleString() : '--'} cfs</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  DROUGHT
        // ----------------------------------------------------------
        drought: {
            sourceId: 'drought-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Drought fill (Official US Drought Monitor D0-D4)
                {
                    id: 'drought-fill',
                    type: 'fill',
                    paint: {
                        'fill-color': [
                            'match',
                            ['get', 'max_severity'],
                            'D0', '#FFFF00',    // Abnormally Dry
                            'D1', '#FCD37F',    // Moderate Drought
                            'D2', '#FFAA00',    // Severe Drought
                            'D3', '#E60000',    // Extreme Drought
                            'D4', '#730000',    // Exceptional Drought
                            '#FFFF00'           // Fallback
                        ],
                        'fill-opacity': 0.35
                    }
                },
                {
                    id: 'drought-outline',
                    type: 'line',
                    paint: {
                        'line-color': [
                            'match',
                            ['get', 'max_severity'],
                            'D0', '#FFFF00',
                            'D1', '#FCD37F',
                            'D2', '#FFAA00',
                            'D3', '#E60000',
                            'D4', '#730000',
                            '#FFFF00'
                        ],
                        'line-width': 1,
                        'line-opacity': 0.7
                    }
                },
                // Drought severity labels
                {
                    id: 'drought-labels',
                    type: 'symbol',
                    minzoom: 5,
                    layout: {
                        'text-field': ['get', 'max_severity'],
                        'text-font': ['Open Sans Bold'],
                        'text-size': 11,
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#ffffff',
                        'text-halo-color': 'rgba(0,0,0,0.7)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                return `
                    <div class="popup-title">Drought - ${props.max_severity}</div>
                    ${props.county ? `<div class="popup-row"><span class="popup-key">Area</span><span class="popup-value">${props.county}${props.state ? ', ' + props.state : ''}</span></div>` : ''}
                    <div class="popup-row"><span class="popup-key">D0 (Abnormal)</span><span class="popup-value">${Math.round(props.d0)}%</span></div>
                    <div class="popup-row"><span class="popup-key">D1 (Moderate)</span><span class="popup-value">${Math.round(props.d1)}%</span></div>
                    <div class="popup-row"><span class="popup-key">D2 (Severe)</span><span class="popup-value">${Math.round(props.d2)}%</span></div>
                    <div class="popup-row"><span class="popup-key">D3 (Extreme)</span><span class="popup-value">${Math.round(props.d3)}%</span></div>
                    <div class="popup-row"><span class="popup-key">D4 (Exceptional)</span><span class="popup-value">${Math.round(props.d4)}%</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  GLACIERS
        // ----------------------------------------------------------
        glaciers: {
            sourceId: 'glaciers-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Glacier extent fill (research conventions — powder blue)
                {
                    id: 'glaciers-fill',
                    type: 'fill',
                    paint: {
                        'fill-color': '#B0E0E6',
                        'fill-opacity': 0.3
                    }
                },
                // 3D fill-extrusion for glacier extent (elevation change: diverging blue-white-red)
                {
                    id: 'glaciers-extrusion',
                    type: 'fill-extrusion',
                    paint: {
                        'fill-extrusion-color': [
                            'interpolate', ['linear'],
                            ['get', 'retreat_rate'],
                            0, '#0571B0',    // Gain (blue)
                            20, '#FFFFFF',   // Stable (white)
                            40, '#CA0020',   // Loss (red)
                            60, '#CA0020'    // Heavy loss (red)
                        ],
                        'fill-extrusion-height': [
                            'interpolate', ['linear'],
                            ['get', 'area_km2'],
                            0, 200,
                            100, 1000,
                            1000, 3000,
                            10000, 8000
                        ],
                        'fill-extrusion-base': 0,
                        'fill-extrusion-opacity': 0.7
                    }
                },
                // Glacier boundary line (steel blue)
                {
                    id: 'glaciers-boundary',
                    type: 'line',
                    paint: {
                        'line-color': '#4682B4',
                        'line-width': 2,
                        'line-opacity': 0.8
                    }
                },
                // Glacier labels
                {
                    id: 'glaciers-labels',
                    type: 'symbol',
                    minzoom: 6,
                    layout: {
                        'text-field': ['get', 'glacier_name'],
                        'text-font': ['Open Sans Semibold'],
                        'text-size': 11,
                        'text-offset': [0, -1.5],
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#B0E0E6',
                        'text-halo-color': 'rgba(0,0,0,0.8)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                return `
                    <div class="popup-title">${props.glacier_name || 'Glacier'}</div>
                    <div class="popup-row"><span class="popup-key">Area</span><span class="popup-value">${props.area_km2} km&sup2;</span></div>
                    <div class="popup-row"><span class="popup-key">Retreat Rate</span><span class="popup-value">${Math.round(props.retreat_rate)} m/yr</span></div>
                    <div class="popup-row"><span class="popup-key">Elevation</span><span class="popup-value">${props.elevation_min} - ${props.elevation_max} m</span></div>
                    <div class="popup-row"><span class="popup-key">Source Date</span><span class="popup-value">${props.source_date}</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  NDVI / VEGETATION
        // ----------------------------------------------------------
        // NDVI / VEGETATION — Sentinel Hub standard perceptually correct ramp:
        // < -0.2 (water/cloud): '#000080' (navy)
        // -0.2 to 0:           '#A52A2A' (brown, bare soil)
        // 0 to 0.1:            '#D2B48C' (tan, rock/sand)
        // 0.1 to 0.2:          '#FFD700' (gold, sparse vegetation)
        // 0.2 to 0.3:          '#ADFF2F' (green-yellow)
        // 0.3 to 0.5:          '#228B22' (forest green)
        // 0.5 to 0.7:          '#006400' (dark green)
        // > 0.7:               '#004D00' (very dark green, dense canopy)
        // Note: raster tiles are pre-rendered; the ramp above applies when
        // using GeoJSON/vector NDVI data. Raster paint is tuned to approximate
        // the standard palette.
        ndvi: {
            sourceId: 'ndvi-source',
            source: {
                type: 'raster',
                tiles: [
                    'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg'
                ],
                tileSize: 256,
                maxzoom: 14
            },
            layers: [
                {
                    id: 'ndvi-raster',
                    type: 'raster',
                    paint: {
                        'raster-opacity': 0.7,
                        'raster-saturation': 0.4,
                        'raster-contrast': 0.15,
                        'raster-hue-rotate': 60  // Shift toward green for NDVI-like appearance
                    }
                }
            ],
            // NDVI color ramp for vector/GeoJSON NDVI features (if available)
            ndviColorRamp: [
                { stop: -0.2, color: '#000080' },  // Navy (water/cloud)
                { stop: 0,    color: '#A52A2A' },   // Brown (bare soil)
                { stop: 0.1,  color: '#D2B48C' },   // Tan (rock/sand)
                { stop: 0.2,  color: '#FFD700' },    // Gold (sparse vegetation)
                { stop: 0.3,  color: '#ADFF2F' },    // Green-yellow
                { stop: 0.5,  color: '#228B22' },    // Forest green
                { stop: 0.7,  color: '#006400' },    // Dark green
                { stop: 1.0,  color: '#004D00' }     // Very dark green (dense canopy)
            ],
            popup: null // Raster layers don't have feature popups
        },

        // ----------------------------------------------------------
        //  WATERSHEDS
        // ----------------------------------------------------------
        watershed: {
            sourceId: 'watershed-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Watershed boundary fill (steel blue at 0.15 opacity)
                {
                    id: 'watershed-fill',
                    type: 'fill',
                    filter: ['==', ['get', 'feature_type'], 'watershed_boundary'],
                    paint: {
                        'fill-color': '#4682B4',
                        'fill-opacity': 0.15
                    }
                },
                // Watershed boundary outline (steel blue, dashed)
                {
                    id: 'watershed-boundary',
                    type: 'line',
                    filter: ['==', ['get', 'feature_type'], 'watershed_boundary'],
                    paint: {
                        'line-color': '#4682B4',
                        'line-width': 1.5,
                        'line-dasharray': [4, 2],
                        'line-opacity': 0.6
                    }
                },
                // Stream network lines (royal blue, width varies by stream order)
                {
                    id: 'watershed-streams',
                    type: 'line',
                    filter: ['==', ['get', 'feature_type'], 'stream'],
                    paint: {
                        'line-color': '#4169E1',
                        'line-width': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'stream_order'], 1],
                            1, 1,
                            2, 2,
                            3, 3,
                            4, 4,
                            5, 5,
                            6, 6
                        ],
                        'line-opacity': 0.7
                    }
                },
                // Watershed labels
                {
                    id: 'watershed-labels',
                    type: 'symbol',
                    filter: ['==', ['get', 'feature_type'], 'watershed_boundary'],
                    minzoom: 5,
                    layout: {
                        'text-field': ['get', 'name'],
                        'text-font': ['Open Sans Semibold'],
                        'text-size': 12,
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#4682B4',
                        'text-halo-color': 'rgba(0,0,0,0.7)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                return `
                    <div class="popup-title">${props.name || 'Watershed'}</div>
                    ${props.feature_type === 'watershed_boundary' ? `
                        <div class="popup-row"><span class="popup-key">HUC</span><span class="popup-value">${props.huc || '--'}</span></div>
                        <div class="popup-row"><span class="popup-key">Area</span><span class="popup-value">${props.area_acres ? props.area_acres.toLocaleString() + ' acres' : '--'}</span></div>
                        <div class="popup-row"><span class="popup-key">States</span><span class="popup-value">${props.states || '--'}</span></div>
                    ` : `
                        <div class="popup-row"><span class="popup-key">Type</span><span class="popup-value">Stream</span></div>
                    `}
                `;
            }
        },

        // ----------------------------------------------------------
        //  EARTHQUAKES (USGS)
        // ----------------------------------------------------------
        earthquakes: {
            sourceId: 'earthquakes-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Earthquake glow (outer ring)
                {
                    id: 'earthquakes-glow',
                    type: 'circle',
                    paint: {
                        // Zoom-scaled: a fixed-pixel glow made every M5+ ridge
                        // quake a giant red blob in the ocean at world view.
                        'circle-radius': [
                            'interpolate', ['linear'], ['zoom'],
                            2, ['interpolate', ['linear'], ['get', 'magnitude'],
                                2.5, 3, 5, 7, 7, 13],
                            6, ['interpolate', ['linear'], ['get', 'magnitude'],
                                2.5, 8, 5, 20, 7, 36],
                        ],
                        'circle-color': [
                            'interpolate', ['linear'],
                            ['get', 'depth_km'],
                            0, '#FF0000',      // Shallow (<70km) — red
                            70, '#FFA500',      // Intermediate (70-300km) — orange
                            300, '#800080'      // Deep (>300km) — purple
                        ],
                        'circle-opacity': 0.25,
                        'circle-blur': 1
                    }
                },
                // Earthquake core circle
                {
                    id: 'earthquakes-circle',
                    type: 'circle',
                    paint: {
                        'circle-radius': [
                            'interpolate', ['linear'], ['zoom'],
                            2, ['interpolate', ['linear'], ['get', 'magnitude'],
                                2.5, 1.5, 5, 4, 7, 8],
                            6, ['interpolate', ['linear'], ['get', 'magnitude'],
                                2.5, 4, 5, 12, 7, 25],
                        ],
                        'circle-color': [
                            'interpolate', ['linear'],
                            ['get', 'depth_km'],
                            0, '#FF0000',
                            70, '#FFA500',
                            300, '#800080'
                        ],
                        'circle-opacity': 0.85,
                        'circle-stroke-width': 1,
                        'circle-stroke-color': 'rgba(255,255,255,0.6)'
                    }
                },
                // Earthquake magnitude labels
                {
                    id: 'earthquakes-labels',
                    type: 'symbol',
                    minzoom: 3,
                    layout: {
                        'text-field': ['concat', 'M', ['to-string', ['get', 'magnitude']]],
                        'text-font': ['Open Sans Bold'],
                        'text-size': 10,
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#ffffff',
                        'text-halo-color': 'rgba(0,0,0,0.8)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                const depthClass = props.depth_km < 70 ? 'Shallow' : props.depth_km < 300 ? 'Intermediate' : 'Deep';
                return `
                    <div class="popup-title">Earthquake — M${props.magnitude}</div>
                    <div class="popup-row"><span class="popup-key">Location</span><span class="popup-value">${props.place}</span></div>
                    <div class="popup-row"><span class="popup-key">Depth</span><span class="popup-value">${Math.round(props.depth_km)} km (${depthClass})</span></div>
                    <div class="popup-row"><span class="popup-key">Time</span><span class="popup-value">${props.time_str}</span></div>
                `;
            }
        },

        // ----------------------------------------------------------
        //  AIR QUALITY (Open-Meteo)
        // ----------------------------------------------------------
        airquality: {
            sourceId: 'airquality-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // AQ glow (outer halo)
                {
                    id: 'airquality-glow',
                    type: 'circle',
                    paint: {
                        'circle-radius': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'aqi'], 0],
                            0, 12,
                            50, 16,
                            100, 22,
                            200, 30,
                            300, 38
                        ],
                        'circle-color': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'aqi'], 0],
                            0,   '#00E400',   // Good
                            50,  '#FFFF00',   // Moderate
                            100, '#FF7E00',   // Unhealthy for Sensitive
                            150, '#FF0000',   // Unhealthy
                            200, '#8F3F97',   // Very Unhealthy
                            300, '#7E0023'    // Hazardous
                        ],
                        'circle-opacity': 0.2,
                        'circle-blur': 1
                    }
                },
                // AQ core circle
                {
                    id: 'airquality-circle',
                    type: 'circle',
                    paint: {
                        'circle-radius': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'aqi'], 0],
                            0, 6,
                            50, 9,
                            100, 12,
                            200, 16,
                            300, 20
                        ],
                        'circle-color': [
                            'interpolate', ['linear'],
                            ['coalesce', ['get', 'aqi'], 0],
                            0,   '#00E400',
                            50,  '#FFFF00',
                            100, '#FF7E00',
                            150, '#FF0000',
                            200, '#8F3F97',
                            300, '#7E0023'
                        ],
                        'circle-opacity': 0.8,
                        'circle-stroke-width': 1,
                        'circle-stroke-color': 'rgba(255,255,255,0.5)'
                    }
                },
                // AQ AQI value labels
                {
                    id: 'airquality-labels',
                    type: 'symbol',
                    minzoom: 2,
                    layout: {
                        'text-field': ['to-string', ['coalesce', ['get', 'aqi'], '--']],
                        'text-font': ['Open Sans Bold'],
                        'text-size': 10,
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#ffffff',
                        'text-halo-color': 'rgba(0,0,0,0.8)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                const aqiVal = props.aqi || 0;
                let aqiLabel = 'Good';
                if (aqiVal > 300) aqiLabel = 'Hazardous';
                else if (aqiVal > 200) aqiLabel = 'Very Unhealthy';
                else if (aqiVal > 150) aqiLabel = 'Unhealthy';
                else if (aqiVal > 100) aqiLabel = 'Unhealthy for Sensitive Groups';
                else if (aqiVal > 50) aqiLabel = 'Moderate';
                return `
                    <div class="popup-title">Air Quality — ${aqiLabel}</div>
                    <div class="popup-row"><span class="popup-key">US AQI</span><span class="popup-value">${aqiVal}</span></div>
                    <div class="popup-row"><span class="popup-key">PM2.5</span><span class="popup-value">${props.pm25 != null ? props.pm25 + ' µg/m³' : '--'}</span></div>
                    <div class="popup-row"><span class="popup-key">PM10</span><span class="popup-value">${props.pm10 != null ? props.pm10 + ' µg/m³' : '--'}</span></div>
                    ${props.uv_index != null ? `<div class="popup-row"><span class="popup-key">UV Index</span><span class="popup-value">${props.uv_index}</span></div>` : ''}
                `;
            }
        },

        // ----------------------------------------------------------
        //  VOLCANOES (USGS)
        // ----------------------------------------------------------
        volcanoes: {
            sourceId: 'volcanoes-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                // Volcano glow
                {
                    id: 'volcanoes-glow',
                    type: 'circle',
                    paint: {
                        'circle-radius': 14,
                        'circle-color': [
                            'match', ['get', 'alert_level'],
                            'WARNING', '#FF0000',
                            'WATCH', '#FFA500',
                            'ADVISORY', '#FFFF00',
                            'NORMAL', '#00AA00',
                            '#888888'   // UNASSIGNED / default
                        ],
                        'circle-opacity': 0.25,
                        'circle-blur': 1
                    }
                },
                // Volcano core circle
                {
                    id: 'volcanoes-circle',
                    type: 'circle',
                    paint: {
                        'circle-radius': 7,
                        'circle-color': [
                            'match', ['get', 'alert_level'],
                            'WARNING', '#FF0000',
                            'WATCH', '#FFA500',
                            'ADVISORY', '#FFFF00',
                            'NORMAL', '#00AA00',
                            '#888888'
                        ],
                        'circle-opacity': 0.9,
                        'circle-stroke-width': 2,
                        'circle-stroke-color': 'rgba(255,255,255,0.7)'
                    }
                },
                // Volcano triangle symbol (using text)
                {
                    id: 'volcanoes-symbol',
                    type: 'symbol',
                    minzoom: 3,
                    layout: {
                        'text-field': '\u25B2',   // Unicode filled triangle
                        'text-size': 14,
                        'text-allow-overlap': true,
                        'text-offset': [0, -0.1]
                    },
                    paint: {
                        'text-color': '#ffffff',
                        'text-halo-color': 'rgba(0,0,0,0.6)',
                        'text-halo-width': 1
                    }
                },
                // Volcano name labels
                {
                    id: 'volcanoes-labels',
                    type: 'symbol',
                    minzoom: 5,
                    layout: {
                        'text-field': ['get', 'name'],
                        'text-font': ['Open Sans Semibold'],
                        'text-size': 11,
                        'text-offset': [0, 1.5],
                        'text-allow-overlap': false
                    },
                    paint: {
                        'text-color': '#FF6D00',
                        'text-halo-color': 'rgba(0,0,0,0.8)',
                        'text-halo-width': 1
                    }
                }
            ],
            popup: (props) => {
                const alertColors = { WARNING: '#FF0000', WATCH: '#FFA500', ADVISORY: '#FFFF00', NORMAL: '#00AA00' };
                const alertColor = alertColors[props.alert_level] || '#888';
                return `
                    <div class="popup-title">${props.name || 'Volcano'}</div>
                    <div class="popup-row"><span class="popup-key">Alert Level</span><span class="popup-value" style="color:${alertColor}; font-weight:bold;">${props.alert_level}</span></div>
                    <div class="popup-row"><span class="popup-key">Aviation Color</span><span class="popup-value">${props.aviation_color}</span></div>
                    ${props.observatory ? `<div class="popup-row"><span class="popup-key">Observatory</span><span class="popup-value">${props.observatory}</span></div>` : ''}
                `;
            }
        },

        // ----------------------------------------------------------
        //  RISK HEATMAP (composite)
        // ----------------------------------------------------------
        risk: {
            sourceId: 'risk-source',
            source: {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            },
            layers: [
                {
                    id: 'risk-heatmap',
                    type: 'heatmap',
                    paint: {
                        // Weight based on risk score
                        'heatmap-weight': [
                            'interpolate', ['linear'],
                            ['get', 'risk_score'],
                            0, 0,
                            0.5, 0.5,
                            1, 1
                        ],
                        // Intensity by zoom level
                        'heatmap-intensity': [
                            'interpolate', ['linear'], ['zoom'],
                            0, 0.5,
                            5, 1,
                            10, 2
                        ],
                        // Color ramp: Inferno colormap
                        'heatmap-color': [
                            'interpolate', ['linear'],
                            ['heatmap-density'],
                            0,    'rgba(0, 0, 4, 0)',
                            0.1,  '#1B0C41',
                            0.2,  '#4A0C6B',
                            0.3,  '#781C6D',
                            0.4,  '#A52C60',
                            0.5,  '#CF4446',
                            0.6,  '#ED6925',
                            0.7,  '#FB9B06',
                            0.85, '#F7D13D',
                            1,    '#FCFFA4'
                        ],
                        // Radius
                        'heatmap-radius': [
                            'interpolate', ['linear'], ['zoom'],
                            0, 20,
                            5, 40,
                            10, 60
                        ],
                        'heatmap-opacity': 0.6
                    }
                }
            ],
            popup: null // Heatmap layers don't support feature clicks
        }
    };

    // ==========================================================
    //  INITIALIZATION
    // ==========================================================

    /**
     * Initialize all hazard layer sources and layers on the map.
     * Call this after the map style has loaded.
     *
     * @param {maplibregl.Map} mapInstance
     */
    const init = (mapInstance) => {
        map = mapInstance;

        // Add all sources and layers
        Object.entries(LAYER_DEFS).forEach(([hazardType, def]) => {
            addHazardSource(hazardType, def);
            addHazardLayers(hazardType, def);
        });

        // Set up click handlers for popups
        setupPopupHandlers();

        // Start fire pulsing animation
        startFirePulse();

        // Data-presentation policy: volcanoes default to alert-level only.
        // All 1,196 Holocene volcanoes as equal-weight dots is catalogue
        // noise, not news — the full inventory stays available by clearing
        // this filter (applyFilter('volcanoes', null)).
        applyFilter('volcanoes', [
            'in', ['get', 'alert_level'], ['literal', ['Warning', 'Watch', 'Advisory']],
        ]);

        console.log('[HazardLayers] All layers initialized');
    };

    /**
     * Add a GeoJSON or raster source to the map.
     */
    const addHazardSource = (hazardType, def) => {
        if (map.getSource(def.sourceId)) return;

        map.addSource(def.sourceId, def.source);

        // For floods, add a separate point source for gauge markers
        if (hazardType === 'floods' && def.gaugeSourceId) {
            map.addSource(def.gaugeSourceId, {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
            });
        }
    };

    /**
     * Add all layers for a hazard type to the map.
     */
    const addHazardLayers = (hazardType, def) => {
        def.layers.forEach(layerDef => {
            if (map.getLayer(layerDef.id)) return;

            const layerConfig = {
                id: layerDef.id,
                type: layerDef.type,
                source: (hazardType === 'floods' && layerDef.id === 'floods-gauges' && def.gaugeSourceId)
                    ? def.gaugeSourceId
                    : def.sourceId,
                paint: layerDef.paint || {},
                layout: layerDef.layout || {}
            };

            if (layerDef.filter) {
                layerConfig.filter = layerDef.filter;
            }
            if (layerDef.minzoom) {
                layerConfig.minzoom = layerDef.minzoom;
            }
            if (layerDef.maxzoom) {
                layerConfig.maxzoom = layerDef.maxzoom;
            }

            map.addLayer(layerConfig);
            activeLayers.set(layerDef.id, { hazardType, visible: true });
        });
    };

    // ==========================================================
    //  DATA UPDATES
    // ==========================================================

    /**
     * Update the source data for a hazard type.
     *
     * @param {string} hazardType - e.g. 'fires', 'floods'
     * @param {object} geojson - GeoJSON FeatureCollection
     */
    const updateSource = (hazardType, geojson) => {
        const def = LAYER_DEFS[hazardType];
        if (!def || !map) return;

        const source = map.getSource(def.sourceId);
        if (source && source.setData) {
            source.setData(geojson);
        }

        // For floods, also update gauge point source
        if (hazardType === 'floods' && def.gaugeSourceId) {
            const gaugeSource = map.getSource(def.gaugeSourceId);
            if (gaugeSource && gaugeSource.setData) {
                const gaugePoints = {
                    type: 'FeatureCollection',
                    features: (geojson.features || [])
                        .filter(f => f.properties.point_lng && f.properties.point_lat)
                        .map(f => ({
                            type: 'Feature',
                            geometry: {
                                type: 'Point',
                                coordinates: [f.properties.point_lng, f.properties.point_lat]
                            },
                            properties: f.properties
                        }))
                };
                gaugeSource.setData(gaugePoints);
            }
        }

        // Update feature count in the sidebar
        const count = geojson.features ? geojson.features.length : 0;
        const countEl = document.getElementById(`count-${hazardType}`);
        if (countEl) countEl.textContent = count;

        const statEl = document.getElementById(`stat-${hazardType}`);
        if (statEl) statEl.textContent = count;

        // New fire data invalidates the significance surface
        if (hazardType === 'fires') scheduleHotspotRecompute();

        console.log(`[HazardLayers] Updated ${hazardType}: ${count} features`);
    };

    // ==========================================================
    //  HOT-SPOT SIGNIFICANCE RECOMPUTE
    // ==========================================================

    let hotspotTimer = null;
    const HOTSPOT_CELL_KM = 25;

    /**
     * Rebuild the hotspots layer from fires-source, honoring the active
     * time window (the slider applies a layer *filter*, so the source may
     * hold more days than are visible — bin only what the user sees).
     */
    const recomputeHotspots = () => {
        if (!window.SpatialStats || !map) return;
        const source = map.getSource('fires-source');
        const data = source && source._data;
        if (!data || !Array.isArray(data.features)) return;

        const hours = Math.max(1, Number(window.EcoLensTimeWindowHours) || 168);
        const cutoffDay = new Date(Date.now() - hours * 3600 * 1000)
            .toISOString().split('T')[0];
        const features = data.features.filter(f => {
            const d = f.properties && f.properties.acq_date;
            return !d || d >= cutoffDay;
        });

        const S = window.SpatialStats;
        const cells = S.giStar(S.hexBin(features, { cellKm: HOTSPOT_CELL_KM }));
        const fc = S.toGeoJSON(cells, { cellKm: HOTSPOT_CELL_KM });
        fc.metadata = {
            method: 'Getis-Ord Gi*, binary weights, self-included, 7-cell neighborhood',
            cell_km: HOTSPOT_CELL_KM,
            input_points: features.length,
            window_hours: hours,
            computed_at: new Date().toISOString(),
        };
        updateSource('hotspots', fc);

        const significant = cells.filter(c => c.p_bucket === 'hot99' || c.p_bucket === 'hot95').length;
        const countEl = document.getElementById('count-hotspots');
        if (countEl) countEl.textContent = significant;
    };

    const scheduleHotspotRecompute = () => {
        clearTimeout(hotspotTimer);
        hotspotTimer = setTimeout(recomputeHotspots, 250);
    };

    // ==========================================================
    //  VISIBILITY
    // ==========================================================

    /**
     * Set visibility of all layers for a hazard type.
     *
     * @param {string} hazardType
     * @param {boolean} visible
     */
    const setLayerVisibility = (hazardType, visible) => {
        const def = LAYER_DEFS[hazardType];
        if (!def || !map) return;

        const visibility = visible ? 'visible' : 'none';
        def.layers.forEach(layerDef => {
            if (map.getLayer(layerDef.id)) {
                map.setLayoutProperty(layerDef.id, 'visibility', visibility);
            }
        });

        // Notify Flutter
        if (window.EcoLensBridge) {
            window.EcoLensBridge.sendToFlutter('layerToggled', { layer: hazardType, visible });
        }
    };

    /**
     * Set opacity for paint properties of a hazard type.
     *
     * @param {string} hazardType
     * @param {number} opacity - 0 to 1
     */
    const setLayerOpacity = (hazardType, opacity) => {
        const def = LAYER_DEFS[hazardType];
        if (!def || !map) return;

        def.layers.forEach(layerDef => {
            if (!map.getLayer(layerDef.id)) return;

            switch (layerDef.type) {
                case 'fill':
                    map.setPaintProperty(layerDef.id, 'fill-opacity', opacity);
                    break;
                case 'line':
                    map.setPaintProperty(layerDef.id, 'line-opacity', opacity);
                    break;
                case 'circle':
                    map.setPaintProperty(layerDef.id, 'circle-opacity', opacity);
                    break;
                case 'fill-extrusion':
                    map.setPaintProperty(layerDef.id, 'fill-extrusion-opacity', opacity);
                    break;
                case 'raster':
                    map.setPaintProperty(layerDef.id, 'raster-opacity', opacity);
                    break;
                case 'heatmap':
                    map.setPaintProperty(layerDef.id, 'heatmap-opacity', opacity);
                    break;
                // symbol opacity: text-opacity
                case 'symbol':
                    map.setPaintProperty(layerDef.id, 'text-opacity', opacity);
                    break;
            }
        });
    };

    // ==========================================================
    //  FILTERS
    // ==========================================================

    /**
     * Apply a MapLibre filter expression to a hazard type's layers.
     *
     * @param {string} hazardType
     * @param {Array} filterExpr - MapLibre filter expression or null to clear
     */
    const applyFilter = (hazardType, filterExpr) => {
        const def = LAYER_DEFS[hazardType];
        if (!def || !map) return;

        def.layers.forEach(layerDef => {
            if (!map.getLayer(layerDef.id)) return;

            // Preserve existing structural filters (like cluster filters)
            if (filterExpr) {
                if (layerDef.filter) {
                    // Combine with existing layer filter
                    map.setFilter(layerDef.id, ['all', layerDef.filter, filterExpr]);
                } else {
                    map.setFilter(layerDef.id, filterExpr);
                }
            } else {
                // Reset to original filter
                map.setFilter(layerDef.id, layerDef.filter || null);
            }
        });
    };

    /**
     * Apply time-based filters to source layers that expose comparable timestamps.
     * Static products such as drought polygons and volcano inventories are left
     * visible because they describe current conditions rather than event time.
     *
     * @param {number} hoursBack - Number of hours back from now
     */
    const applyTimeWindow = (hoursBack) => {
        const hours = Math.max(1, Number(hoursBack) || 168);
        const cutoffDate = new Date(Date.now() - hours * 3600 * 1000);
        const cutoffIso = cutoffDate.toISOString();
        const cutoffDay = cutoffIso.split('T')[0];
        const cutoffMs = cutoffDate.getTime();

        // Fires are capped at 7 days regardless of the selected preset —
        // beyond that the map over-shows (and FIRMS NRT doesn't reliably
        // serve longer world ranges anyway). Month/Year presets still
        // widen the other hazard types.
        const fireHours = Math.min(hours, 168);
        const fireCutoffDay = new Date(Date.now() - fireHours * 3600 * 1000)
            .toISOString().split('T')[0];
        applyFilter('fires', ['>=', ['get', 'acq_date'], fireCutoffDay]);
        applyFilter('earthquakes', ['>=', ['to-number', ['get', 'time']], cutoffMs]);
        applyFilter('floods', ['>=', ['coalesce', ['get', 'effective'], '9999-12-31T00:00:00Z'], cutoffIso]);
        // hotspots is not filtered — it recomputes from the visible window
        scheduleHotspotRecompute();
    };

    const applyTimeFilter = (hazardType, hoursAgo) => {
        const hours = Math.max(1, Number(hoursAgo) || 168);
        if (hazardType === 'fires') {
            const cutoffStr = new Date(Date.now() - Math.min(hours, 168) * 3600 * 1000)
                .toISOString()
                .split('T')[0];
            applyFilter('fires', ['>=', ['get', 'acq_date'], cutoffStr]);
        } else {
            applyTimeWindow(hours);
        }
    };

    // ==========================================================
    //  POPUP / CLICK HANDLERS
    // ==========================================================

    /**
     * Set up click handlers for all hazard layers that have popups defined.
     */
    const setupPopupHandlers = () => {
        Object.entries(LAYER_DEFS).forEach(([hazardType, def]) => {
            if (!def.popup) return;

            // Determine which layers are clickable (not clusters, labels, glow, or heatmaps)
            const clickableLayers = def.layers
                .filter(l => !l.id.includes('cluster-count') && !l.id.includes('glow') &&
                             !l.id.includes('label') && l.type !== 'heatmap' && l.type !== 'symbol')
                .map(l => l.id);

            clickableLayers.forEach(layerId => {
                // Pointer cursor on hover
                map.on('mouseenter', layerId, () => {
                    map.getCanvas().style.cursor = 'pointer';
                });
                map.on('mouseleave', layerId, () => {
                    map.getCanvas().style.cursor = '';
                });

                // Click handler
                map.on('click', layerId, (e) => {
                    if (!e.features || e.features.length === 0) return;

                    const feature = e.features[0];
                    const props = feature.properties;

                    // Handle cluster clicks - zoom in
                    if (props.cluster_id || props.point_count) {
                        const source = map.getSource(def.sourceId);
                        if (source && source.getClusterExpansionZoom) {
                            source.getClusterExpansionZoom(props.cluster_id, (err, zoom) => {
                                if (!err) {
                                    map.flyTo({
                                        center: e.lngLat,
                                        zoom: zoom + 1,
                                        duration: 1000
                                    });
                                }
                            });
                        }
                        return;
                    }

                    // Parse stringified JSON properties (MapLibre serializes nested objects)
                    const parsedProps = {};
                    Object.entries(props).forEach(([k, v]) => {
                        try {
                            parsedProps[k] = JSON.parse(v);
                        } catch {
                            parsedProps[k] = v;
                        }
                    });

                    // Show structured intelligence brief in the right drawer
                    // (Selected tab). For hazards EventIntelligence supports,
                    // this replaces the floating popup with a docked, full-
                    // height brief that doesn't compete with the Event Queue.
                    const briefSupported = ['fires', 'floods', 'earthquakes', 'drought', 'volcanoes', 'airquality'];
                    if (window.EventIntelligence?.showBriefInDrawer && briefSupported.includes(hazardType)) {
                        window.EventIntelligence.showBriefInDrawer(hazardType, parsedProps, e.lngLat);
                    } else {
                        let popupHtml = def.popup(parsedProps);
                        if (hazardType === 'fires' || hazardType === 'floods' || hazardType === 'drought') {
                            const ctx = correlationContext(e.lngLat.lat, e.lngLat.lng);
                            if (ctx) popupHtml += `<div style="margin-top:8px;padding-top:8px;border-top:1px solid rgba(0,0,0,0.08);font-size:11px;opacity:0.85;">${ctx}<div style="font-size:9px;opacity:0.5;margin-top:4px;">Correlation: Open-Meteo</div></div>`;
                        }
                        new maplibregl.Popup({ closeButton: true, maxWidth: '300px' })
                            .setLngLat(e.lngLat)
                            .setHTML(popupHtml)
                            .addTo(map);
                    }

                    // Send to Flutter
                    if (window.EcoLensBridge) {
                        window.EcoLensBridge.sendToFlutter('featureSelected', {
                            hazardType,
                            properties: parsedProps,
                            coordinates: [e.lngLat.lng, e.lngLat.lat]
                        });
                    }
                });
            });
        });
    };

    /**
     * Display feature details in the side info panel.
     *
     * @param {string} hazardType
     * @param {object} props
     */
    const showInfoPanel = (hazardType, props) => {
        const panel = document.getElementById('info-panel');
        const title = document.getElementById('info-panel-title');
        const body = document.getElementById('info-panel-body');
        if (!panel || !title || !body) return;

        const typeNames = {
            fire: 'Wildfire Detection',
            flood: 'Flood Zone',
            drought: 'Drought Area',
            glacier: 'Glacier',
            watershed: 'Watershed'
        };

        title.textContent = typeNames[hazardType] || 'Feature Details';

        // Build property rows
        const excludeKeys = ['hazard_type', 'point_lng', 'point_lat', 'feature_type'];
        let html = '';
        Object.entries(props).forEach(([key, value]) => {
            if (excludeKeys.includes(key)) return;
            if (value === null || value === undefined || value === '') return;
            const label = key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
            html += `<div class="info-row">
                <span class="info-key">${label}</span>
                <span class="info-value">${typeof value === 'number' ? (Number.isInteger(value) ? value.toLocaleString() : value.toFixed(2)) : value}</span>
            </div>`;
        });

        body.innerHTML = html;
        panel.classList.remove('hidden');
    };

    // ==========================================================
    //  FIRE PULSE ANIMATION
    // ==========================================================

    /**
     * Animate fire glow layer to create a pulsing effect for active fires.
     */
    const startFirePulse = () => {
        let phase = 0;
        const animate = () => {
            phase = (phase + 0.02) % (2 * Math.PI);
            const pulseOpacity = 0.08 + Math.sin(phase) * 0.08;
            const pulseRadius = 1 + Math.sin(phase) * 0.15;

            if (map.getLayer('fires-glow')) {
                map.setPaintProperty('fires-glow', 'circle-opacity', pulseOpacity);
            }

            fireAnimationId = requestAnimationFrame(animate);
        };
        animate();
    };

    /** Stop fire pulse animation */
    const stopFirePulse = () => {
        if (fireAnimationId) {
            cancelAnimationFrame(fireAnimationId);
            fireAnimationId = null;
        }
    };

    // ==========================================================
    //  CLEANUP
    // ==========================================================

    /**
     * Remove all hazard layers and sources from the map.
     */
    const cleanup = () => {
        stopFirePulse();

        Object.entries(LAYER_DEFS).forEach(([_, def]) => {
            def.layers.forEach(layerDef => {
                if (map && map.getLayer(layerDef.id)) {
                    map.removeLayer(layerDef.id);
                }
            });
            if (map && map.getSource(def.sourceId)) {
                map.removeSource(def.sourceId);
            }
            if (def.gaugeSourceId && map && map.getSource(def.gaugeSourceId)) {
                map.removeSource(def.gaugeSourceId);
            }
        });

        activeLayers.clear();
        console.log('[HazardLayers] Cleanup complete');
    };

    // ==========================================================
    //  Public API
    // ==========================================================

    /** Returns true if the map instance has been set via init(). */
    const isReady = () => !!map;

    return {
        init,
        isReady,
        updateSource,
        setLayerVisibility,
        setLayerOpacity,
        applyFilter,
        applyTimeWindow,
        applyTimeFilter,
        recomputeHotspots,
        showInfoPanel,
        cleanup,
        LAYER_DEFS
    };
})();

// Global access
window.HazardLayers = HazardLayers;
