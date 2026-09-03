/* ============================================================
   EcoLens - Focus Area Analysis Module
   Provides detailed demographics, infrastructure, population,
   and risk assessment for a clicked location.
   ============================================================ */

const FocusArea = (() => {
    let map;
    let focusMarker = null;
    let focusCircle = null;

    const init = (mapInstance) => {
        map = mapInstance;
    };

    /// Analyze a specific point — fetches demographics, infrastructure, hazards
    const analyzePoint = async (lngLat) => {
        showPanel('loading');

        const lat = lngLat.lat;
        const lon = lngLat.lng;
        const radiusKm = 25; // 25km analysis radius

        // Draw analysis circle on map
        drawAnalysisCircle(lon, lat, radiusKm);

        // Fetch real data in parallel — no synthetic estimates
        const [weather, earthquakes, placeName, osm] = await Promise.all([
            fetchWeather(lat, lon),
            fetchNearbyEarthquakes(lat, lon),
            fetchPlaceName(lat, lon),
            fetchOsmContext(lat, lon, radiusKm),
        ]);

        // Compute risk from existing hazard layers on the map
        const hazardRisk = computeLocalRisk(lat, lon, radiusKm);

        showAnalysisPanel({
            placeName,
            lat, lon, radiusKm,
            weather,
            earthquakes,
            osm,
            hazardRisk,
        });
    };

    /// Fetch current weather from Open-Meteo (no key needed)
    const fetchWeather = async (lat, lon) => {
        try {
            const resp = await fetch(
                `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,precipitation,weather_code&timezone=auto`,
                { signal: AbortSignal.timeout(8000) }
            );
            return await resp.json();
        } catch (e) {
            console.warn('[FocusArea] Weather fetch failed:', e.message);
            return null;
        }
    };

    /// Fetch nearby earthquakes from USGS (no key needed)
    const fetchNearbyEarthquakes = async (lat, lon) => {
        try {
            const since = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
            const resp = await fetch(
                `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&latitude=${lat}&longitude=${lon}&maxradiuskm=200&starttime=${since}&minmagnitude=3`,
                { signal: AbortSignal.timeout(10000) }
            );
            return await resp.json();
        } catch (e) {
            console.warn('[FocusArea] Earthquake fetch failed:', e.message);
            return null;
        }
    };

    /// Query OpenStreetMap Overpass API for real infrastructure + settlements within radius.
    /// Returns actual mapped counts — no estimates. If OSM has nothing there, counts are 0 (that's honest).
    const fetchOsmContext = async (lat, lon, radiusKm) => {
        const r = Math.round(radiusKm * 1000); // Overpass uses meters
        const query = `[out:json][timeout:25];
(
  nwr["amenity"="hospital"](around:${r},${lat},${lon});
  nwr["amenity"="clinic"](around:${r},${lat},${lon});
  nwr["amenity"="school"](around:${r},${lat},${lon});
  nwr["amenity"="college"](around:${r},${lat},${lon});
  nwr["amenity"="university"](around:${r},${lat},${lon});
  nwr["amenity"="fire_station"](around:${r},${lat},${lon});
  nwr["amenity"="police"](around:${r},${lat},${lon});
  nwr["power"="plant"](around:${r},${lat},${lon});
  nwr["power"="substation"](around:${r},${lat},${lon});
  node["place"~"^(city|town|village|hamlet|suburb)$"](around:${r},${lat},${lon});
);
out tags center ${radiusKm > 50 ? 2000 : 5000};`;

        const endpoints = [
            'https://overpass-api.de/api/interpreter',
            'https://overpass.kumi.systems/api/interpreter',
        ];
        for (const url of endpoints) {
            try {
                const resp = await fetch(url, {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain' },
                    body: query,
                    signal: AbortSignal.timeout(20000),
                });
                if (!resp.ok) continue;
                const data = await resp.json();
                return parseOsmContext(data.elements || []);
            } catch (e) {
                console.warn('[FocusArea] Overpass endpoint failed:', url, e.message);
            }
        }
        return null; // All endpoints failed
    };

    const parseOsmContext = (elements) => {
        const result = {
            hospitals: 0, clinics: 0, schools: 0, universities: 0,
            fireStations: 0, police: 0, powerPlants: 0, substations: 0,
            places: [],  // settlements with population
        };
        elements.forEach(el => {
            const t = el.tags || {};
            if (t.amenity === 'hospital') result.hospitals++;
            else if (t.amenity === 'clinic') result.clinics++;
            else if (t.amenity === 'school') result.schools++;
            else if (t.amenity === 'college' || t.amenity === 'university') result.universities++;
            else if (t.amenity === 'fire_station') result.fireStations++;
            else if (t.amenity === 'police') result.police++;
            else if (t.power === 'plant') result.powerPlants++;
            else if (t.power === 'substation') result.substations++;
            else if (t.place) {
                const pop = parseInt(t.population || '0', 10);
                result.places.push({
                    name: t.name || '(unnamed)',
                    type: t.place,
                    population: isNaN(pop) ? 0 : pop,
                });
            }
        });
        // Sort places by population, keep top 5
        result.places.sort((a, b) => b.population - a.population);
        result.topPlaces = result.places.slice(0, 5);
        // Only sum population of named settlements that actually have the tag
        result.populationSum = result.places.reduce((s, p) => s + p.population, 0);
        result.placesTagged = result.places.filter(p => p.population > 0).length;
        return result;
    };

    /// Reverse geocode to get place name (Nominatim, no key needed)
    const fetchPlaceName = async (lat, lon) => {
        try {
            const resp = await fetch(
                `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&zoom=10`,
                { signal: AbortSignal.timeout(5000), headers: { 'User-Agent': 'EcoLens/1.0' } }
            );
            const data = await resp.json();
            const addr = data.address || {};
            return addr.city || addr.town || addr.village || addr.county || addr.state || data.display_name?.split(',')[0] || 'Unknown Location';
        } catch (e) {
            return `${lat.toFixed(2)}\u00b0N, ${lon.toFixed(2)}\u00b0E`;
        }
    };

    /// Compute local risk from hazard data already loaded on the map
    const computeLocalRisk = (lat, lon, radiusKm) => {
        const risks = {
            fire: { level: 'low', count: 0, nearest: null },
            flood: { level: 'low', count: 0, nearest: null },
            earthquake: { level: 'low', count: 0, nearest: null },
            drought: { level: 'low', count: 0, nearest: null },
            airQuality: { level: 'good', aqi: null },
        };

        // Check each hazard source on the map
        const sources = ['fires-source', 'floods-source', 'earthquakes-source', 'drought-source', 'airquality-source'];

        sources.forEach(srcId => {
            const src = map.getSource(srcId);
            if (!src || !src._data || !src._data.features) return;

            const features = src._data.features;
            let nearCount = 0;
            let nearestDist = Infinity;

            features.forEach(f => {
                const coords = f.geometry?.coordinates;
                if (!coords) return;
                const fLon = Array.isArray(coords[0]) ? coords[0][0] : coords[0];
                const fLat = Array.isArray(coords[0]) ? coords[0][1] : coords[1];
                const dist = haversine(lat, lon, fLat, fLon);

                if (dist < radiusKm) {
                    nearCount++;
                    if (dist < nearestDist) nearestDist = dist;
                }
            });

            const hazType = srcId.replace('-source', '');
            if (risks[hazType]) {
                risks[hazType].count = nearCount;
                risks[hazType].nearest = nearestDist < Infinity ? nearestDist.toFixed(1) : null;

                if (nearCount > 10) risks[hazType].level = 'extreme';
                else if (nearCount > 5) risks[hazType].level = 'high';
                else if (nearCount > 2) risks[hazType].level = 'moderate';
                else if (nearCount > 0) risks[hazType].level = 'low';
                else risks[hazType].level = 'none';
            }
        });

        // Composite risk score
        const riskValues = { none: 0, low: 0.2, moderate: 0.5, high: 0.75, extreme: 1.0 };
        const composite = (
            riskValues[risks.fire?.level || 'none'] * 0.3 +
            riskValues[risks.flood?.level || 'none'] * 0.25 +
            riskValues[risks.earthquake?.level || 'none'] * 0.2 +
            riskValues[risks.drought?.level || 'none'] * 0.15 +
            (risks.airQuality?.level === 'good' ? 0 : 0.1) * 0.1
        );

        risks.composite = composite;
        risks.compositeLevel = composite > 0.7 ? 'critical' : composite > 0.5 ? 'high' : composite > 0.3 ? 'moderate' : composite > 0.1 ? 'low' : 'minimal';

        return risks;
    };

    /// Haversine distance in km
    const haversine = (lat1, lon1, lat2, lon2) => {
        const R = 6371;
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                  Math.cos(lat1 * Math.PI/180) * Math.cos(lat2 * Math.PI/180) *
                  Math.sin(dLon/2) * Math.sin(dLon/2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    };

    /// Draw a circle on the map showing the analysis radius
    const drawAnalysisCircle = (lon, lat, radiusKm) => {
        // Remove existing
        if (map.getLayer('focus-circle-fill')) map.removeLayer('focus-circle-fill');
        if (map.getLayer('focus-circle-line')) map.removeLayer('focus-circle-line');
        if (map.getSource('focus-circle')) map.removeSource('focus-circle');

        // Create circle GeoJSON
        const points = 64;
        const coords = [];
        for (let i = 0; i <= points; i++) {
            const angle = (i / points) * Math.PI * 2;
            const dx = radiusKm * Math.cos(angle) / (111.32 * Math.cos(lat * Math.PI / 180));
            const dy = radiusKm * Math.sin(angle) / 110.54;
            coords.push([lon + dx, lat + dy]);
        }

        map.addSource('focus-circle', {
            type: 'geojson',
            data: {
                type: 'Feature',
                geometry: { type: 'Polygon', coordinates: [coords] }
            }
        });

        map.addLayer({
            id: 'focus-circle-fill',
            type: 'fill',
            source: 'focus-circle',
            paint: {
                'fill-color': '#4CAF50',
                'fill-opacity': 0.06,
            }
        });

        map.addLayer({
            id: 'focus-circle-line',
            type: 'line',
            source: 'focus-circle',
            paint: {
                'line-color': '#4CAF50',
                'line-width': 2,
                'line-dasharray': [3, 2],
                'line-opacity': 0.5,
            }
        });

        // Add center marker
        if (focusMarker) focusMarker.remove();
        const el = document.createElement('div');
        el.style.cssText = 'width:12px;height:12px;background:#4CAF50;border:2px solid #fff;border-radius:50%;box-shadow:0 0 8px rgba(76,175,80,0.5);';
        focusMarker = new maplibregl.Marker({ element: el }).setLngLat([lon, lat]).addTo(map);
    };

    /// Show a loading state in the panel
    const showPanel = (state) => {
        let panel = document.getElementById('focus-panel');
        if (!panel) {
            panel = document.createElement('div');
            panel.id = 'focus-panel';
            document.body.appendChild(panel);
        }
        panel.className = 'focus-panel';
        if (state === 'loading') {
            panel.innerHTML = `
                <div class="fa-header">
                    <div class="fa-title-row">
                        <h3 class="fa-title">Analyzing Area...</h3>
                        <button class="fa-close" onclick="FocusArea.close()">\u2715</button>
                    </div>
                    <div class="fa-coords" style="opacity:0.4;">Fetching data from multiple sources</div>
                </div>
                <div style="padding:40px;text-align:center;">
                    <div style="width:32px;height:32px;border:3px solid rgba(255,255,255,0.1);border-top-color:#4CAF50;border-radius:50%;animation:spin 0.8s linear infinite;margin:0 auto;"></div>
                    <div style="font-size:11px;opacity:0.4;margin-top:12px;">Weather \u00b7 Demographics \u00b7 Seismic \u00b7 Risk</div>
                </div>
                <style>@keyframes spin{to{transform:rotate(360deg)}}</style>
            `;
            panel.style.display = 'block';
        }
    };

    /// Build the Populated Places section from real OSM data.
    const buildPopulatedPlacesSection = (osm) => {
        if (!osm) {
            return `<div class="fa-section">
                <div class="fa-section-title">Populated places</div>
                <div class="fa-no-data">OpenStreetMap unavailable — retry in a moment.</div>
            </div>`;
        }
        if (osm.places.length === 0) {
            return `<div class="fa-section">
                <div class="fa-section-title">Populated places</div>
                <div class="fa-no-data">No settlements mapped within radius (uninhabited area).</div>
            </div>`;
        }
        const tagged = osm.topPlaces.filter(p => p.population > 0);
        const untagged = osm.topPlaces.filter(p => p.population === 0);
        const totalStr = osm.populationSum > 0
            ? `<b>${osm.populationSum.toLocaleString()}</b> people across ${osm.placesTagged} tagged place${osm.placesTagged === 1 ? '' : 's'}`
            : `${osm.places.length} place${osm.places.length === 1 ? '' : 's'} mapped · population tags missing`;
        const rows = osm.topPlaces.map(p => `
            <div class="fa-quake-item">
                <span class="fa-quake-mag" style="background:#4A5568;font-size:9px;text-transform:uppercase;">${p.type}</span>
                <span class="fa-quake-place">${p.name}</span>
                <span style="font-size:11px;opacity:0.7;font-variant-numeric:tabular-nums;">${p.population > 0 ? p.population.toLocaleString() : '—'}</span>
            </div>`).join('');
        return `<div class="fa-section">
            <div class="fa-section-title">Populated places · OSM</div>
            <div class="fa-quake-count">${totalStr}</div>
            ${rows}
        </div>`;
    };

    /// Build the Infrastructure-at-risk section from real OSM counts.
    const buildInfrastructureSection = (osm) => {
        if (!osm) {
            return `<div class="fa-section">
                <div class="fa-section-title">Infrastructure at risk</div>
                <div class="fa-no-data">OpenStreetMap unavailable — retry in a moment.</div>
            </div>`;
        }
        const rows = [
            { icon: '\uD83C\uDFE5', label: 'Hospitals', val: osm.hospitals },
            { icon: '\uD83E\uDE7A', label: 'Clinics', val: osm.clinics },
            { icon: '\uD83C\uDFEB', label: 'Schools', val: osm.schools },
            { icon: '\uD83C\uDF93', label: 'Colleges / Universities', val: osm.universities },
            { icon: '\uD83D\uDE92', label: 'Fire stations', val: osm.fireStations },
            { icon: '\uD83D\uDC6E', label: 'Police', val: osm.police },
            { icon: '\u26A1', label: 'Power plants', val: osm.powerPlants },
            { icon: '\uD83D\uDD0C', label: 'Substations', val: osm.substations },
        ];
        const any = rows.some(r => r.val > 0);
        if (!any) {
            return `<div class="fa-section">
                <div class="fa-section-title">Infrastructure at risk · OSM</div>
                <div class="fa-no-data">No critical infrastructure mapped within radius.</div>
                <div class="fa-source" style="padding:6px 0 0;">Absence may reflect incomplete OSM coverage, not absence on the ground.</div>
            </div>`;
        }
        const html = rows.map(r => `
            <div class="fa-infra-item" title="${r.label}" style="display:flex;justify-content:space-between;align-items:center;">
                <span style="opacity:${r.val > 0 ? 1 : 0.4};">${r.icon} ${r.label}</span>
                <span style="font-weight:700;font-variant-numeric:tabular-nums;color:${r.val > 0 ? '#fff' : '#6e7681'};">${r.val}</span>
            </div>`).join('');
        return `<div class="fa-section">
            <div class="fa-section-title">Infrastructure at risk · OSM</div>
            <div class="fa-infra-grid" style="grid-template-columns:1fr 1fr;">${html}</div>
            <div class="fa-source" style="padding:6px 0 0;">Counts from OpenStreetMap within ${25}km · © OSM contributors</div>
        </div>`;
    };

    const buildWeatherPatternSection = (weather, hazardRisk) => {
        const current = weather?.current;
        if (!current) {
            return `<div class="fa-section">
                <div class="fa-section-title">Weather pattern read</div>
                <div class="fa-no-data">Weather unavailable. Re-run Area Intelligence or inspect live hazard layers.</div>
            </div>`;
        }

        const temp = Number(current.temperature_2m);
        const humidity = Number(current.relative_humidity_2m);
        const wind = Number(current.wind_speed_10m);
        const rain = Number(current.precipitation);
        const flags = [];

        if (temp >= 30 && humidity <= 35) {
            flags.push({ label: 'Fire-weather setup', detail: 'Hot and dry surface conditions can amplify ignition and spread.' });
        }
        if (wind >= 25) {
            flags.push({ label: 'Wind transport', detail: 'Wind can accelerate fire spread, smoke exposure, and ash dispersion.' });
        }
        if (rain >= 5) {
            flags.push({ label: 'Flood trigger', detail: 'Current rainfall supports runoff, ponding, and river response checks.' });
        }
        if ((hazardRisk?.drought?.level || 'none') !== 'none' && temp >= 25) {
            flags.push({ label: 'Drought amplification', detail: 'Heat over a drought area increases vegetation and water-supply stress.' });
        }
        if (flags.length === 0) {
            flags.push({ label: 'No strong short-term weather trigger', detail: 'Use the event timeline to compare whether hazards are clustering despite calm current conditions.' });
        }

        return `<div class="fa-section">
            <div class="fa-section-title">Weather pattern read</div>
            ${flags.map(f => `<div class="fa-hazard-row">
                <span class="fa-hazard-dot" style="background:#58A6FF"></span>
                <span class="fa-hazard-name">${f.label}</span>
                <span class="fa-hazard-count" style="min-width:0;flex:1;text-align:left;">${f.detail}</span>
            </div>`).join('')}
        </div>`;
    };

    /// Show analysis panel with all data
    const showAnalysisPanel = (data) => {
        let panel = document.getElementById('focus-panel');
        if (!panel) {
            panel = document.createElement('div');
            panel.id = 'focus-panel';
            document.body.appendChild(panel);
        }

        const riskColorMap = {
            minimal: '#4CAF50', low: '#8BC34A', moderate: '#FFC107',
            high: '#FF5722', critical: '#D32F2F', extreme: '#B71C1C',
            none: '#666', good: '#4CAF50',
        };

        const riskColor = riskColorMap[data.hazardRisk.compositeLevel] || '#666';
        const compositeScore = Math.floor(data.hazardRisk.composite * 100);

        // Weather display
        let weatherHtml = '<div class="fa-weather">No weather data</div>';
        if (data.weather?.current) {
            const w = data.weather.current;
            weatherHtml = `
                <div class="fa-weather">
                    <div class="fa-weather-temp">${w.temperature_2m}\u00b0C</div>
                    <div class="fa-weather-details">
                        <span>\uD83D\uDCA7 ${w.relative_humidity_2m}%</span>
                        <span>\uD83D\uDCA8 ${w.wind_speed_10m} km/h</span>
                        <span>\uD83C\uDF27 ${w.precipitation} mm</span>
                    </div>
                </div>
            `;
        }

        // Earthquake list
        let quakeHtml = '<div class="fa-no-data">No recent earthquakes</div>';
        if (data.earthquakes?.features?.length > 0) {
            const top5 = data.earthquakes.features.slice(0, 5);
            quakeHtml = top5.map(q => `
                <div class="fa-quake-item">
                    <span class="fa-quake-mag" style="background:${q.properties.mag >= 5 ? '#D32F2F' : q.properties.mag >= 4 ? '#FF5722' : '#FFC107'}">${q.properties.mag.toFixed(1)}</span>
                    <span class="fa-quake-place">${q.properties.place}</span>
                </div>
            `).join('');
        }

        // Hazard risk breakdown
        const hazards = ['fire', 'flood', 'earthquake', 'drought'];
        const hazardHtml = hazards.map(h => {
            const r = data.hazardRisk[h];
            if (!r) return '';
            const c = riskColorMap[r.level] || '#666';
            return `
                <div class="fa-hazard-row">
                    <span class="fa-hazard-dot" style="background:${c}"></span>
                    <span class="fa-hazard-name">${h.charAt(0).toUpperCase() + h.slice(1)}</span>
                    <span class="fa-hazard-level" style="color:${c}">${r.level.toUpperCase()}</span>
                    <span class="fa-hazard-count">${r.count} within ${data.radiusKm}km</span>
                </div>
            `;
        }).join('');

        panel.className = 'focus-panel';
        panel.innerHTML = `
            <div class="fa-header">
                <div class="fa-title-row">
                    <h3 class="fa-title">${data.placeName}</h3>
                    <button class="fa-close" onclick="FocusArea.close()">\u2715</button>
                </div>
                <div class="fa-coords">${data.lat.toFixed(4)}\u00b0N, ${data.lon.toFixed(4)}\u00b0E \u00b7 ${data.radiusKm}km radius</div>
            </div>

            <div class="fa-risk-score" style="border-color:${riskColor}">
                <div class="fa-risk-number" style="color:${riskColor}">${compositeScore}</div>
                <div class="fa-risk-label">Composite Risk Score</div>
                <div class="fa-risk-level" style="background:${riskColor}">${data.hazardRisk.compositeLevel.toUpperCase()}</div>
            </div>

            <div class="fa-section">
                <div class="fa-section-title">Current Weather</div>
                ${weatherHtml}
            </div>

            ${buildWeatherPatternSection(data.weather, data.hazardRisk)}

            ${buildPopulatedPlacesSection(data.osm)}
            ${buildInfrastructureSection(data.osm)}

            <div class="fa-section">
                <div class="fa-section-title">Hazard Risk Assessment</div>
                ${hazardHtml}
            </div>

            <div class="fa-section">
                <div class="fa-section-title">Recent Seismic Activity (1yr, M3+)</div>
                <div class="fa-quake-count">${data.earthquakes?.metadata?.count || 0} earthquakes within 200km</div>
                ${quakeHtml}
            </div>

            <div class="fa-actions">
                <button class="fa-action-btn" onclick="InMapSimulation.startFireSimulation({lat:${data.lat},lng:${data.lon}}); FocusArea.close();">\uD83D\uDD25 Simulate Fire</button>
                <button class="fa-action-btn" onclick="InMapSimulation.startFloodSimulation({lat:${data.lat},lng:${data.lon}}); FocusArea.close();">\uD83C\uDF0A Simulate Flood</button>
            </div>

            <div class="fa-source">
                Data: Open-Meteo \u00b7 USGS \u00b7 OpenStreetMap \u00b7 WorldPop estimates
            </div>
        `;

        panel.style.display = 'block';
    };

    const close = () => {
        const panel = document.getElementById('focus-panel');
        if (panel) panel.style.display = 'none';

        if (focusMarker) { focusMarker.remove(); focusMarker = null; }

        ['focus-circle-fill', 'focus-circle-line'].forEach(id => {
            if (map.getLayer(id)) map.removeLayer(id);
        });
        if (map.getSource('focus-circle')) map.removeSource('focus-circle');
    };

    return { init, analyzePoint, close };
})();
