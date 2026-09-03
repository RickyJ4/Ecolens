/* ============================================================
   EcoLens - In-Map Hazard Simulation Engine
   Runs wildfire and flood simulations directly on the MapLibre
   GL JS map using cellular automata and GeoJSON visualization.
   ============================================================ */

const InMapSimulation = (() => {
    let map;
    let simRunning = false;
    let simProgress = 0;
    let simSpeed = 1;
    let simInterval = null;
    let ignitionPoint = null;

    // Simplified Rothermel spread
    const FUEL_RATES = { grass: 2.0, brush: 0.8, timber: 0.5, urban: 0.3 };
    const SIM_META = {
        wildfire: {
            label: 'Wildfire Spread Simulation',
            color: '#FF4500',
            statLabel: 'Burn Area',
            subtitle: 'Spread model based on fuels, humidity, and wind exposure.'
        },
        flood: {
            label: 'Flood Inundation Simulation',
            color: '#00B4D8',
            statLabel: 'Inundation Area',
            subtitle: 'Inundation expands through low-lying exposure zones.'
        },
        drought: {
            label: 'Drought Stress Simulation',
            color: '#D97706',
            statLabel: 'Stress Zone',
            subtitle: 'Slow-onset water stress expands across vegetation and supply systems.'
        },
        airquality: {
            label: 'Air Quality Exposure Simulation',
            color: '#10B981',
            statLabel: 'Exposure Zone',
            subtitle: 'Smoke and PM2.5 exposure follows wind transport and stagnation.'
        },
        quake: {
            label: 'Earthquake Impact Simulation',
            color: '#A855F7',
            statLabel: 'Shake Zone',
            subtitle: 'Impact decays outward from the epicentre with local site amplification.'
        },
        volcano: {
            label: 'Volcanic Ash Simulation',
            color: '#EF4444',
            statLabel: 'Ash Watch Zone',
            subtitle: 'Ash exposure expands downwind from the volcano alert area.'
        },
        environmental: {
            label: 'Environmental Impact Simulation',
            color: '#58A6FF',
            statLabel: 'Impact Zone',
            subtitle: 'Generic exposure radius for triage and field validation.'
        }
    };

    const startFireSimulation = (lngLat, options = {}) => {
        // Stop any existing simulation first
        stop();

        ignitionPoint = lngLat;
        const windSpeed = options.windSpeed || 30; // km/h
        const windDir = options.windDir || 225; // degrees
        const humidity = options.humidity || 20; // percent
        const fuelType = options.fuelType || 'brush';

        // Add fire source
        map.addSource('sim-fire-area', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features: [] }
        });

        // Burned area (dark, semi-transparent)
        map.addLayer({
            id: 'sim-fire-burned',
            type: 'fill',
            source: 'sim-fire-area',
            paint: {
                'fill-color': '#1a0800',
                'fill-opacity': 0.6,
            }
        });

        // Active fire front (bright orange outline, pulsing)
        map.addLayer({
            id: 'sim-fire-front',
            type: 'line',
            source: 'sim-fire-area',
            paint: {
                'line-color': '#FF4500',
                'line-width': 4,
                'line-blur': 3,
                'line-opacity': 0.9,
            }
        });

        // Fire glow heatmap
        map.addSource('sim-fire-points', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features: [] }
        });
        map.addLayer({
            id: 'sim-fire-heat',
            type: 'heatmap',
            source: 'sim-fire-points',
            paint: {
                'heatmap-intensity': 2,
                'heatmap-color': [
                    'interpolate', ['linear'], ['heatmap-density'],
                    0, 'rgba(0,0,0,0)',
                    0.2, 'rgba(255,100,0,0.3)',
                    0.5, 'rgba(255,50,0,0.5)',
                    0.8, 'rgba(255,0,0,0.7)',
                    1, 'rgba(200,0,0,0.9)'
                ],
                'heatmap-radius': 30,
                'heatmap-opacity': 0.8,
            }
        });

        // Show control panel
        showSimPanel('wildfire', lngLat, options);

        // Start simulation loop
        simRunning = true;
        simProgress = 0;

        // Pre-compute fire spread using cellular automata
        const gridSize = 100;
        const cellSizeM = 50;
        const grid = new Array(gridSize).fill(null).map(() => new Array(gridSize).fill(0));
        // 0=unburned, 1=burning, 2=burned

        // Set ignition point at center
        const cx = Math.floor(gridSize / 2);
        const cy = Math.floor(gridSize / 2);
        grid[cy][cx] = 1;

        const baseRate = FUEL_RATES[fuelType] || 0.5;
        const windRad = windDir * Math.PI / 180;

        let hour = 0;
        const maxHours = 72;

        simInterval = setInterval(() => {
            if (!simRunning) return;

            hour += simSpeed;
            simProgress = Math.min(hour / maxHours, 1);

            // Spread fire (one step per interval)
            const newGrid = grid.map(r => [...r]);
            for (let y = 1; y < gridSize - 1; y++) {
                for (let x = 1; x < gridSize - 1; x++) {
                    if (grid[y][x] === 1) {
                        // This cell is burning - try to spread to neighbors
                        newGrid[y][x] = 2; // becomes burned

                        for (let dy = -1; dy <= 1; dy++) {
                            for (let dx = -1; dx <= 1; dx++) {
                                if (dx === 0 && dy === 0) continue;
                                if (grid[y+dy][x+dx] !== 0) continue;

                                // Wind factor: spread faster in wind direction
                                const angle = Math.atan2(dy, dx);
                                const windAlignment = Math.cos(angle - windRad);
                                const windFactor = 1 + windAlignment * windSpeed * 0.02;

                                // Humidity factor
                                const humidFactor = Math.max(0.1, 1 - humidity / 100);

                                // Spread probability — coefficient raised
                                // 0.3 → 0.7: at 0.3 a 72 h run burned a
                                // handful of cells, so the drawn hull and
                                // the area figure told different stories.
                                const prob = baseRate * windFactor * humidFactor * 0.7;

                                if (Math.random() < prob) {
                                    newGrid[y+dy][x+dx] = 1;
                                }
                            }
                        }
                    }
                }
            }

            // Copy back
            for (let y = 0; y < gridSize; y++) {
                for (let x = 0; x < gridSize; x++) {
                    grid[y][x] = newGrid[y][x];
                }
            }

            // Convert grid to GeoJSON polygon
            const burnedCoords = [];
            const firePoints = [];
            const mPerDegLon = 111320 * Math.cos(lngLat.lat * Math.PI / 180);
            const mPerDegLat = 110540;

            for (let y = 0; y < gridSize; y++) {
                for (let x = 0; x < gridSize; x++) {
                    if (grid[y][x] >= 1) {
                        const lon = lngLat.lng + ((x - cx) * cellSizeM) / mPerDegLon;
                        const lat = lngLat.lat + ((y - cy) * cellSizeM) / mPerDegLat;
                        burnedCoords.push([lon, lat]);
                        if (grid[y][x] === 1) {
                            firePoints.push({
                                type: 'Feature',
                                geometry: { type: 'Point', coordinates: [lon, lat] },
                                properties: { intensity: 1 }
                            });
                        }
                    }
                }
            }

            // Create convex hull from burned points (simplified)
            if (burnedCoords.length > 2) {
                const hull = convexHull(burnedCoords);
                const areaKm2 = (burnedCoords.length * cellSizeM * cellSizeM) / 1e6;

                map.getSource('sim-fire-area').setData({
                    type: 'FeatureCollection',
                    features: [{
                        type: 'Feature',
                        geometry: { type: 'Polygon', coordinates: [hull] },
                        properties: { area_km2: areaKm2 }
                    }]
                });

                map.getSource('sim-fire-points').setData({
                    type: 'FeatureCollection',
                    features: firePoints
                });

                // Update stats panel
                updateSimStats({
                    type: 'wildfire',
                    hour: Math.floor(hour),
                    areaKm2: areaKm2,
                    perimeterKm: Math.sqrt(areaKm2) * 4,
                    firePoints: firePoints.length,
                    progress: simProgress,
                });
            }

            if (simProgress >= 1) {
                simRunning = false;
                clearInterval(simInterval);
            }
        }, 200); // Update every 200ms
    };

    // Convex hull (Graham scan simplified)
    const convexHull = (points) => {
        if (points.length < 3) return points.concat([points[0]]);

        const cx = points.reduce((s, p) => s + p[0], 0) / points.length;
        const cy = points.reduce((s, p) => s + p[1], 0) / points.length;

        const sorted = points.slice().sort((a, b) => {
            return Math.atan2(a[1] - cy, a[0] - cx) - Math.atan2(b[1] - cy, b[0] - cx);
        });

        // Take every Nth point to simplify
        const step = Math.max(1, Math.floor(sorted.length / 64));
        const simplified = [];
        for (let i = 0; i < sorted.length; i += step) {
            simplified.push(sorted[i]);
        }
        simplified.push(simplified[0]); // close ring
        return simplified;
    };

    // Flood simulation
    const startFloodSimulation = (lngLat, options = {}) => {
        // Stop any existing simulation first
        stop();

        const waterRise = options.waterRise || 3; // meters
        const maxHours = 48;

        map.addSource('sim-flood-area', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features: [] }
        });

        map.addLayer({
            id: 'sim-flood-fill',
            type: 'fill',
            source: 'sim-flood-area',
            paint: {
                'fill-color': '#0077B6',
                'fill-opacity': 0.45,
            }
        });

        map.addLayer({
            id: 'sim-flood-outline',
            type: 'line',
            source: 'sim-flood-area',
            paint: {
                'line-color': '#00B4D8',
                'line-width': 2,
                'line-opacity': 0.8,
            }
        });

        showSimPanel('flood', lngLat, options);
        simRunning = true;
        simProgress = 0;

        let hour = 0;
        let currentRadius = 0.001; // degrees
        const maxRadius = waterRise * 0.005; // rough conversion

        simInterval = setInterval(() => {
            if (!simRunning) return;

            hour += simSpeed;
            simProgress = Math.min(hour / maxHours, 1);
            currentRadius = maxRadius * simProgress;

            // Create elliptical flood zone (wider along river direction)
            const pts = [];
            for (let a = 0; a < Math.PI * 2; a += 0.1) {
                const rx = currentRadius * (1 + 0.5 * Math.cos(a * 2)); // irregular shape
                const ry = currentRadius * (1 + 0.3 * Math.sin(a * 3));
                pts.push([
                    lngLat.lng + rx * Math.cos(a),
                    lngLat.lat + ry * Math.sin(a)
                ]);
            }
            pts.push(pts[0]);

            const areaKm2 = Math.PI * (currentRadius * 111) * (currentRadius * 111);

            map.getSource('sim-flood-area').setData({
                type: 'FeatureCollection',
                features: [{
                    type: 'Feature',
                    geometry: { type: 'Polygon', coordinates: [pts] },
                    properties: {}
                }]
            });

            updateSimStats({
                type: 'flood',
                hour: Math.floor(hour),
                areaKm2: areaKm2,
                waterDepthM: waterRise * simProgress,
                progress: simProgress,
            });

            if (simProgress >= 1) {
                simRunning = false;
                clearInterval(simInterval);
            }
        }, 200);
    };

    const circlePolygon = (lngLat, radiusKm, points = 96, windDir = 245, stretch = 1) => {
        const coords = [];
        const dirRad = (windDir || 0) * Math.PI / 180;
        const cosLat = Math.max(0.2, Math.cos(lngLat.lat * Math.PI / 180));
        for (let i = 0; i <= points; i++) {
            const angle = (i / points) * Math.PI * 2;
            const alignment = Math.cos(angle - dirRad);
            const irregular = 1 + 0.12 * Math.sin(angle * 3) + 0.08 * Math.cos(angle * 5);
            const directional = 1 + Math.max(0, alignment) * (stretch - 1);
            const r = Math.max(0.2, radiusKm * irregular * directional);
            const dx = (r * Math.cos(angle)) / (111.32 * cosLat);
            const dy = (r * Math.sin(angle)) / 110.54;
            coords.push([lngLat.lng + dx, lngLat.lat + dy]);
        }
        return coords;
    };

    const startImpactSimulation = (lngLat, options = {}) => {
        stop();

        const type = options.type || 'environmental';
        const meta = SIM_META[type] || SIM_META.environmental;
        const radiusKm = Math.max(3, options.radiusKm || 25);
        const maxHours = options.durationHours || (
            type === 'drought' ? 168 :
            type === 'airquality' ? 36 :
            type === 'quake' ? 24 :
            type === 'volcano' ? 48 :
            72
        );
        const windDir = options.windDir || 245;
        const stretch = type === 'airquality' || type === 'volcano' ? 1.8 : 1.1;

        map.addSource('sim-impact-area', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features: [] }
        });

        map.addLayer({
            id: 'sim-impact-fill',
            type: 'fill',
            source: 'sim-impact-area',
            paint: {
                'fill-color': meta.color,
                'fill-opacity': type === 'quake' ? 0.12 : 0.18,
            }
        });

        map.addLayer({
            id: 'sim-impact-outline',
            type: 'line',
            source: 'sim-impact-area',
            paint: {
                'line-color': meta.color,
                'line-width': 3,
                'line-dasharray': [2, 1],
                'line-opacity': 0.85,
            }
        });

        showSimPanel(type, lngLat, options);
        simRunning = true;
        simProgress = 0;

        let hour = 0;
        simInterval = setInterval(() => {
            if (!simRunning) return;

            hour += simSpeed;
            simProgress = Math.min(hour / maxHours, 1);
            const eased = 1 - Math.pow(1 - simProgress, 2);
            const currentRadius = Math.max(0.2, radiusKm * eased);
            const coords = circlePolygon(lngLat, currentRadius, 96, windDir, stretch);
            const areaKm2 = Math.PI * currentRadius * currentRadius * (type === 'airquality' || type === 'volcano' ? stretch : 1);

            map.getSource('sim-impact-area').setData({
                type: 'FeatureCollection',
                features: [{
                    type: 'Feature',
                    geometry: { type: 'Polygon', coordinates: [coords] },
                    properties: { type, radius_km: currentRadius, area_km2: areaKm2 }
                }]
            });

            updateSimStats({
                type,
                hour: Math.floor(hour),
                areaKm2,
                radiusKm: currentRadius,
                progress: simProgress,
            });

            if (simProgress >= 1) {
                simRunning = false;
                clearInterval(simInterval);
            }
        }, 200);
    };

    const startDroughtSimulation = (lngLat, options = {}) =>
        startImpactSimulation(lngLat, { ...options, type: 'drought', durationHours: 168 });
    const startAirQualitySimulation = (lngLat, options = {}) =>
        startImpactSimulation(lngLat, { ...options, type: 'airquality', durationHours: 36 });
    const startEarthquakeSimulation = (lngLat, options = {}) =>
        startImpactSimulation(lngLat, { ...options, type: 'quake', durationHours: 24 });
    const startVolcanoSimulation = (lngLat, options = {}) =>
        startImpactSimulation(lngLat, { ...options, type: 'volcano', durationHours: 48 });

    // UI: Show simulation control panel
    const showSimPanel = (type, lngLat, options = {}) => {
        let panel = document.getElementById('sim-panel');
        if (!panel) {
            panel = document.createElement('div');
            panel.id = 'sim-panel';
            panel.className = 'sim-panel';
            document.body.appendChild(panel);
        }

        const meta = SIM_META[type] || SIM_META.environmental;
        const typeLabel = options.title || meta.label;
        const typeColor = meta.color;
        const subtitle = options.pattern || options.forecast || meta.subtitle;

        panel.innerHTML = `
            <div class="sim-panel-header" style="border-left: 3px solid ${typeColor};">
                <span class="sim-panel-title">${typeLabel}</span>
                <button class="sim-panel-close" onclick="InMapSimulation.stop()">\u2715</button>
            </div>
            <div class="sim-panel-location">
                \uD83D\uDCCD ${lngLat.lat.toFixed(4)}\u00B0N, ${lngLat.lng.toFixed(4)}\u00B0E
            </div>
            <div class="sim-panel-location">${subtitle}</div>
            <div class="sim-panel-progress">
                <div class="sim-progress-bar">
                    <div class="sim-progress-fill" id="sim-progress-fill" style="width:0%; background:${typeColor};"></div>
                </div>
                <span id="sim-progress-text">0%</span>
            </div>
            <div class="sim-panel-stats" id="sim-stats">
                <div class="sim-stat"><span>Hour</span><span id="sim-hour">0</span></div>
                <div class="sim-stat"><span>${meta.statLabel}</span><span id="sim-area">0</span></div>
            </div>
            <div class="sim-panel-location" style="font-size:10px; opacity:0.75;">
                Illustrative model, not a forecast \u2014 population and damage
                figures are deliberately not shown (EcoLens does not invent
                numbers it cannot source).
            </div>
            <div class="sim-panel-controls">
                <button class="sim-btn" onclick="InMapSimulation.setSpeed(1)">1x</button>
                <button class="sim-btn sim-btn-active" onclick="InMapSimulation.setSpeed(2)">2x</button>
                <button class="sim-btn" onclick="InMapSimulation.setSpeed(5)">5x</button>
                <button class="sim-btn" onclick="InMapSimulation.togglePause()">\u23F8</button>
            </div>
            <div class="sim-panel-impacts" id="sim-impacts">
                <div class="sim-impact-title">Cascading Impacts</div>
                <div id="sim-cascade-list"></div>
            </div>
        `;
        panel.style.display = 'block';
    };

    const updateSimStats = (stats) => {
        const fill = document.getElementById('sim-progress-fill');
        const text = document.getElementById('sim-progress-text');
        if (fill) fill.style.width = (stats.progress * 100) + '%';
        if (text) text.textContent = Math.floor(stats.progress * 100) + '%';

        const hourEl = document.getElementById('sim-hour');
        const areaEl = document.getElementById('sim-area');

        if (hourEl) hourEl.textContent = stats.hour;
        // Honest units: hectares below 1 km\u00B2 so a small model burn never
        // reads as an absurd "0.0 km\u00B2". (The fabricated population /
        // structures / loss figures were removed 2026-07-28 \u2014 they were
        // area \u00D7 flat ratios, exactly what the data-integrity policy bans.)
        if (areaEl) {
            areaEl.textContent = stats.areaKm2 >= 1
                ? stats.areaKm2.toFixed(1) + ' km\u00B2'
                : Math.max(1, Math.round(stats.areaKm2 * 100)) + ' ha';
        }

        // Show cascading impacts at thresholds
        if (stats.progress > 0.3) showCascades(stats.type || 'wildfire', stats);
    };

    const showCascades = (type, stats) => {
        const list = document.getElementById('sim-cascade-list');
        if (!list || list.children.length > 0) return;

        const catalog = {
            wildfire: [
                { name: 'Post-fire debris flow', prob: '60-80%', time: '1-3 days after rain', cite: 'Cannon et al. (2010), USGS', severity: 'high' },
                { name: 'Water quality degradation', prob: '90%+', time: '1-8 years', cite: 'EPA / USGS post-fire watershed guidance', severity: 'extreme' },
                { name: 'Air quality PM2.5', prob: '95%+', time: 'Immediate', cite: 'EPA AirNow', severity: 'high' },
                { name: 'Habitat fragmentation', prob: '70%', time: 'Months-years', cite: 'USFS Research', severity: 'moderate' },
            ],
            flood: [
                { name: 'Road and bridge disruption', prob: 'High', time: '0-24 hours', cite: 'NOAA flood impact guidance', severity: 'high' },
                { name: 'Drinking water contamination', prob: 'Moderate-high', time: '1-7 days', cite: 'CDC flood guidance', severity: 'high' },
                { name: 'Mold and indoor exposure', prob: 'Moderate', time: '1-4 weeks', cite: 'CDC / FEMA', severity: 'moderate' },
            ],
            drought: [
                { name: 'Wildfire amplification', prob: 'Rising', time: 'Weeks-months', cite: 'Drought-fire correlation research', severity: 'high' },
                { name: 'Crop and forage stress', prob: 'High', time: 'Weeks', cite: 'USDM / USDA indicators', severity: 'high' },
                { name: 'Water supply pressure', prob: 'Moderate-high', time: 'Months', cite: 'USDM impact categories', severity: 'moderate' },
            ],
            airquality: [
                { name: 'Respiratory health exposure', prob: 'High', time: 'Immediate', cite: 'EPA AirNow health guidance', severity: 'high' },
                { name: 'Outdoor work interruption', prob: 'Moderate-high', time: 'Same day', cite: 'AQI activity guidance', severity: 'moderate' },
                { name: 'School and shelter demand', prob: 'Moderate', time: 'Same day', cite: 'Public health smoke guidance', severity: 'moderate' },
            ],
            quake: [
                { name: 'Aftershock sequence', prob: 'Likely', time: 'Hours-weeks', cite: 'USGS aftershock guidance', severity: 'high' },
                { name: 'Lifeline disruption', prob: 'Varies', time: 'Immediate', cite: 'FEMA HAZUS concepts', severity: 'high' },
                { name: 'Landslide susceptibility', prob: 'Local', time: 'Immediate-days', cite: 'USGS earthquake hazards', severity: 'moderate' },
            ],
            volcano: [
                { name: 'Ash inhalation exposure', prob: 'Wind-dependent', time: 'Hours', cite: 'USGS volcano ash guidance', severity: 'high' },
                { name: 'Aviation disruption', prob: 'Possible', time: 'Hours-days', cite: 'VAAC / aviation color codes', severity: 'high' },
                { name: 'Lahar pathway risk', prob: 'Drainage-dependent', time: 'Rainfall-triggered', cite: 'USGS volcano hazards', severity: 'moderate' },
            ],
            environmental: [
                { name: 'Community exposure', prob: 'Screening', time: 'Now', cite: 'EcoLens triage', severity: 'moderate' },
                { name: 'Infrastructure exposure', prob: 'Screening', time: 'Now', cite: 'EcoLens triage', severity: 'moderate' },
            ],
        };
        const cascades = catalog[type] || catalog.environmental;

        list.innerHTML = cascades.map(c => `
            <div class="sim-cascade-item">
                <div class="sim-cascade-header">
                    <span class="sim-cascade-badge sim-sev-${c.severity}">${c.severity.toUpperCase()}</span>
                    <span class="sim-cascade-name">${c.name}</span>
                    <span class="sim-cascade-prob">${c.prob}</span>
                </div>
                <div class="sim-cascade-meta">
                    <span>\u23F1 ${c.time}</span>
                    <span class="sim-cascade-cite">\uD83D\uDCC4 ${c.cite}</span>
                </div>
            </div>
        `).join('');
    };

    const stop = () => {
        simRunning = false;
        if (simInterval) clearInterval(simInterval);

        // Remove layers
        ['sim-fire-burned', 'sim-fire-front', 'sim-fire-heat', 'sim-flood-fill', 'sim-flood-outline', 'sim-impact-fill', 'sim-impact-outline'].forEach(id => {
            if (map.getLayer(id)) map.removeLayer(id);
        });
        ['sim-fire-area', 'sim-fire-points', 'sim-flood-area', 'sim-impact-area'].forEach(id => {
            if (map.getSource(id)) map.removeSource(id);
        });

        const panel = document.getElementById('sim-panel');
        if (panel) panel.style.display = 'none';
    };

    const togglePause = () => {
        simRunning = !simRunning;
    };

    const setSpeed = (s) => {
        simSpeed = s;
    };

    const init = (mapInstance) => {
        map = mapInstance;
    };

    return {
        init,
        startFireSimulation,
        startFloodSimulation,
        startImpactSimulation,
        startDroughtSimulation,
        startAirQualitySimulation,
        startEarthquakeSimulation,
        startVolcanoSimulation,
        stop,
        togglePause,
        setSpeed
    };
})();

window.InMapSimulation = InMapSimulation;
