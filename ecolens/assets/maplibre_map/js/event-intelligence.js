/* ============================================================
   EcoLens — Event Intelligence Engine
   Turns a hazard feature into a structured intelligence brief
   instead of a key/value dump.

   For every clicked event we answer:
       SO WHAT  — single-sentence headline + comparative rank
       WHY      — drivers from IntelligenceLayers (wind, precip, drought)
       NEXT     — forecast projection (wind vector, downstream propagation)
       WHO      — population + infrastructure inside the projected zone
                  via OSM Overpass
       RESPONSE — nearest GDACS / NASA-EONET tracking
       CONFIDENCE — source, freshness, validation

   Synchronous data renders immediately; OSM + response context
   load async with skeleton placeholders that fill in.
   ============================================================ */

const EventIntelligence = (() => {
    'use strict';

    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, ch => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[ch]));

    const haversineKm = (lat1, lon1, lat2, lon2) => {
        const R = 6371;
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) ** 2;
        return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    };

    /** Compass bearing from a degrees value: 0 = N, 90 = E. */
    const compass = (deg) => {
        const dirs = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'];
        const i = Math.round(((deg % 360 + 360) % 360) / 22.5) % 16;
        return dirs[i];
    };

    const timeAgo = (date) => {
        if (!date) return 'unknown';
        const d = (date instanceof Date) ? date : new Date(date);
        if (isNaN(d.getTime())) return 'unknown';
        const sec = Math.floor((Date.now() - d.getTime()) / 1000);
        if (sec < 60) return sec + ' s ago';
        if (sec < 3600) return Math.floor(sec / 60) + ' min ago';
        if (sec < 86400) return Math.floor(sec / 3600) + ' h ago';
        return Math.floor(sec / 86400) + ' d ago';
    };

    // ----------------------------------------------------------
    //  CORRELATION CONTEXT — pull from already-loaded sources
    // ----------------------------------------------------------

    /** Sample the live wind + precip grids at lat/lon. */
    const correlationContext = (lat, lon) => {
        if (!window.IntelligenceLayers) return { wind: null, precip: 0 };
        return {
            wind: window.IntelligenceLayers.sampleWindAt(lat, lon),
            precip: window.IntelligenceLayers.samplePrecipAt(lat, lon),
        };
    };

    /** Is this point inside a drought polygon currently rendered? */
    const droughtAt = (lat, lon) => {
        const map = window.ecoMap;
        const src = map?.getSource('drought-source');
        const features = src?._data?.features || [];
        for (const f of features) {
            const p = f.properties;
            const c = f.geometry?.coordinates?.[0];
            if (!c || !Array.isArray(c)) continue;
            // Quick bbox check (drought polygons are buffer circles)
            let minLat = Infinity, maxLat = -Infinity, minLon = Infinity, maxLon = -Infinity;
            c.forEach(([x, y]) => {
                if (y < minLat) minLat = y;
                if (y > maxLat) maxLat = y;
                if (x < minLon) minLon = x;
                if (x > maxLon) maxLon = x;
            });
            if (lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon) {
                return {
                    severity: p.max_severity || `D${p.severity_index || 0}`,
                    index: p.severity_index || 0,
                    county: p.county || '',
                };
            }
        }
        return null;
    };

    /** Rank a numeric property across all features in a source.
     *  Returns { rank, total, percentile } or null if not enough data.
     *  rank = 1 is the largest. percentile 99 = top 1%. */
    const percentileFor = (sourceId, propName, value) => {
        const map = window.ecoMap;
        const src = map?.getSource(sourceId);
        const features = src?._data?.features || [];
        if (!features.length) return null;
        const values = features
            .map(f => Number(f.properties?.[propName]))
            .filter(v => Number.isFinite(v));
        if (values.length < 5) return null;
        const greater = values.filter(v => v > value).length;
        return {
            rank: greater + 1,
            total: values.length,
            percentile: Math.round((1 - greater / values.length) * 100),
        };
    };

    /** Format a rank object into a human-readable chip.
     *  Picks the most impactful framing: "Largest", "#3 of N", "Top 1% (#178 of N)". */
    const formatRankChip = (rank, unit) => {
        if (!rank) return '';
        const total = rank.total.toLocaleString();
        if (rank.rank === 1) return `Largest of ${total} ${unit}`;
        if (rank.rank <= 5) return `#${rank.rank} of ${total} ${unit}`;
        if (rank.percentile >= 99) return `Top 1% (#${rank.rank} of ${total})`;
        if (rank.percentile >= 95) return `Top 5% (#${rank.rank} of ${total})`;
        if (rank.percentile >= 90) return `Top 10% (#${rank.rank} of ${total})`;
        const pct = Math.max(1, 100 - rank.percentile);
        return `Top ${pct}% by ${unit}`;
    };

    /** Find nearest active response event (GDACS + EONET) within 800 km. */
    const nearestResponse = (lat, lon) => {
        const map = window.ecoMap;
        const candidates = [];
        const collect = (sourceId, label, getTitle) => {
            const src = map?.getSource(sourceId);
            const feats = src?._data?.features || [];
            for (const f of feats) {
                // Descend to the first numeric position — GDACS/EONET mix
                // Point, Polygon and MultiPolygon geometries, and grabbing
                // c[0] blindly hands haversine an array (NaN distances that
                // then slipped past the range check below).
                let pos = f.geometry?.coordinates;
                while (Array.isArray(pos) && Array.isArray(pos[0])) pos = pos[0];
                if (!Array.isArray(pos) || pos.length < 2) continue;
                const d = haversineKm(lat, lon, pos[1], pos[0]);
                if (!isFinite(d) || d > 800) continue;
                candidates.push({
                    distKm: d,
                    label,
                    title: getTitle(f.properties),
                    url: f.properties?.url || '',
                });
            }
        };
        collect('intel-gdacs-source', 'GDACS',
            p => `${p.event_name} [${p.alert_level}]`);
        collect('intel-eonet-source', 'NASA EONET',
            p => `${p.title} · ${p.category}`);
        candidates.sort((a, b) => a.distKm - b.distKm);
        return candidates.slice(0, 3);
    };

    // ----------------------------------------------------------
    //  IMPACT ZONE — Overpass query for population + infrastructure
    // ----------------------------------------------------------

    const osmCache = new Map();   // key=lat,lon,radius -> result

    // ----------------------------------------------------------
    //  WRI GLOBAL POWER PLANT DATABASE — cross-validation
    //  Lazy-loaded JSON (~30k plants, 800 KB gzipped). Reference
    //  source: World Resources Institute, v1.3.0 (2021), CC BY 4.0.
    //  Bundled at /assets/wri_power_plants.json so we have it
    //  cached at the edge and can query offline.
    // ----------------------------------------------------------

    let _wriData = null;
    let _wriPromise = null;
    const loadWri = async () => {
        if (_wriData) return _wriData;
        if (_wriPromise) return _wriPromise;
        _wriPromise = (async () => {
            try {
                // Root-relative path so it works whether the map is loaded
                // standalone at /index.html or embedded via the Flutter app.
                const url = window.ECOLENS_WRI_URL || '/assets/wri_power_plants.json';
                const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
                if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
                const data = await resp.json();
                // Expected shape: [{name, lat, lon, capacity_mw, country, fuel}, ...]
                _wriData = Array.isArray(data) ? data : (data.plants || []);
                console.log(`[EventIntel] WRI loaded: ${_wriData.length} plants`);
                return _wriData;
            } catch (e) {
                console.warn('[EventIntel] WRI fetch failed:', e.message);
                _wriData = [];
                return _wriData;
            }
        })();
        return _wriPromise;
    };

    /** Count WRI-listed plants within radiusKm of (lat,lon). */
    const wriCrossValidate = async (lat, lon, radiusKm) => {
        const plants = await loadWri();
        if (!plants.length) {
            return { available: false, count: 0, plants: [] };
        }
        const nearby = plants
            .filter(p => Number.isFinite(p.lat) && Number.isFinite(p.lon))
            .filter(p => haversineKm(lat, lon, p.lat, p.lon) <= radiusKm)
            .sort((a, b) => (b.capacity_mw || 0) - (a.capacity_mw || 0));
        return {
            available: true,
            count: nearby.length,
            plants: nearby.slice(0, 3).map(p => ({
                name: p.name,
                capacity: p.capacity_mw,
                fuel: p.fuel,
            })),
        };
    };

    const fetchImpactZone = async (lat, lon, radiusKm) => {
        const key = `${lat.toFixed(2)},${lon.toFixed(2)},${radiusKm}`;
        if (osmCache.has(key)) return osmCache.get(key);
        const r = Math.round(radiusKm * 1000);
        // 'out meta' (instead of 'out tags') returns user + timestamp on
        // each element — needed for the OSM coverage indicator.
        const query = `[out:json][timeout:25];
(
  nwr["amenity"="hospital"](around:${r},${lat},${lon});
  nwr["amenity"="clinic"](around:${r},${lat},${lon});
  nwr["amenity"="school"](around:${r},${lat},${lon});
  nwr["amenity"="fire_station"](around:${r},${lat},${lon});
  nwr["power"="plant"](around:${r},${lat},${lon});
  node["place"~"^(city|town|village|hamlet|suburb)$"](around:${r},${lat},${lon});
);
out meta center ${radiusKm > 50 ? 1000 : 3000};`;
        // Store query on result for Verify-on-OSM deep links
        const overpassTurboQuery = query;

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
                const parsed = parseImpact(data.elements || []);
                parsed.lat = lat;
                parsed.lon = lon;
                parsed.radiusKm = radiusKm;
                parsed.overpassQuery = overpassTurboQuery;
                // Run WRI cross-validation in the background; promise stored
                // on the parsed object so the renderer can await it.
                parsed.wriCrossValidation = wriCrossValidate(lat, lon, radiusKm);
                osmCache.set(key, parsed);
                return parsed;
            } catch (e) {
                console.warn('[EventIntel] Overpass fail:', e.message);
            }
        }
        return null;
    };

    const parseImpact = (elements) => {
        const result = {
            // Counts
            hospitals: 0, clinics: 0, schools: 0, fireStations: 0, powerPlants: 0,
            // Named examples (top-3 per category) — built so the user can audit
            // exactly which features are being counted.
            hospitalNames: [], clinicNames: [], schoolNames: [],
            fireStationNames: [], powerPlantNames: [],
            // Settlements
            places: [], populationSum: 0, placesTagged: 0,
            largestPlace: null,
            // Metadata for coverage indicator
            allTimestamps: [],
            uniqueUsers: new Set(),
        };
        elements.forEach(el => {
            const t = el.tags || {};
            const name = t.name || t['name:en'] || null;
            if (el.timestamp) result.allTimestamps.push(el.timestamp);
            if (el.user) result.uniqueUsers.add(el.user);

            if (t.amenity === 'hospital') {
                result.hospitals++;
                if (name) result.hospitalNames.push(name);
            } else if (t.amenity === 'clinic') {
                result.clinics++;
                if (name) result.clinicNames.push(name);
            } else if (t.amenity === 'school') {
                result.schools++;
                if (name) result.schoolNames.push(name);
            } else if (t.amenity === 'fire_station') {
                result.fireStations++;
                if (name) result.fireStationNames.push(name);
            } else if (t.power === 'plant') {
                result.powerPlants++;
                if (name) result.powerPlantNames.push(name);
            } else if (t.place) {
                const pop = parseInt(t.population || '0', 10);
                result.places.push({
                    name: t.name || '(unnamed)',
                    type: t.place,
                    population: isNaN(pop) ? 0 : pop,
                });
            }
        });
        // Keep only top-3 named examples per category
        const top3 = (arr) => arr.slice(0, 3);
        result.hospitalNames = top3(result.hospitalNames);
        result.clinicNames = top3(result.clinicNames);
        result.schoolNames = top3(result.schoolNames);
        result.fireStationNames = top3(result.fireStationNames);
        result.powerPlantNames = top3(result.powerPlantNames);

        result.places.sort((a, b) => b.population - a.population);
        result.populationSum = result.places.reduce((s, p) => s + p.population, 0);
        result.placesTagged = result.places.filter(p => p.population > 0).length;
        result.largestPlace = result.places[0] || null;

        // Coverage indicator from OSM metadata
        const now = Date.now();
        const ageDays = result.allTimestamps
            .map(ts => (now - new Date(ts).getTime()) / 86400000)
            .filter(d => !isNaN(d))
            .sort((a, b) => a - b);
        const medianAge = ageDays.length ? ageDays[Math.floor(ageDays.length / 2)] : null;
        const userCount = result.uniqueUsers.size;
        // HIGH = recent edits + many mappers
        // MEDIUM = either recent OR many mappers
        // LOW = stale + few mappers
        let coverageLevel = 'LOW';
        let coverageReason = '';
        if (medianAge != null) {
            if (medianAge < 365 && userCount >= 30) {
                coverageLevel = 'HIGH';
                coverageReason = `Active community · median edit ${Math.round(medianAge)} d · ${userCount} contributors`;
            } else if (medianAge < 730 && userCount >= 10) {
                coverageLevel = 'MEDIUM';
                coverageReason = `Moderate activity · median edit ${Math.round(medianAge)} d · ${userCount} contributors`;
            } else {
                coverageReason = `Sparse · median edit ${Math.round(medianAge)} d · ${userCount} contributors`;
            }
        } else {
            coverageReason = 'No metadata returned';
        }
        result.coverage = { level: coverageLevel, reason: coverageReason };

        return result;
    };

    // ----------------------------------------------------------
    //  HAZARD-SPECIFIC BRIEFS
    // ----------------------------------------------------------

    /** Pick an impact-zone radius based on event severity. */
    const impactRadiusKm = (hazardType, props) => {
        if (hazardType === 'fires') {
            const frp = Number(props.frp) || 0;
            return frp >= 300 ? 35 : frp >= 120 ? 22 : frp >= 40 ? 12 : 7;
        }
        if (hazardType === 'floods') return 25;
        if (hazardType === 'earthquakes') {
            const m = Number(props.mag || props.magnitude) || 0;
            return m >= 7 ? 200 : m >= 6 ? 120 : m >= 5 ? 60 : 30;
        }
        if (hazardType === 'drought') return 75;
        if (hazardType === 'volcanoes') return 60;
        if (hazardType === 'airquality') return 50;
        return 25;
    };

    const fireBrief = (props, lat, lon) => {
        const frp = Number(props.frp) || 0;
        const brightness = Number(props.brightness_temp || props.brightness) || 0;
        const { wind, precip } = correlationContext(lat, lon);
        const drought = droughtAt(lat, lon);
        const rank = percentileFor('fires-source', 'frp', frp);
        const radiusKm = impactRadiusKm('fires', props);

        // Headline
        const intensity = frp >= 300 ? 'Extreme' : frp >= 120 ? 'High-intensity' : frp >= 40 ? 'Active' : 'Low-intensity';
        const title = `${intensity} wildfire detection`;
        const rankChip = formatRankChip(rank, 'hotspots');

        // Drivers — only include factors actually amplifying the fire.
        // Light wind, calm conditions, and rainfall are NOT drivers.
        const drivers = [];
        if (drought) drivers.push(`drought ${drought.severity} active in this zone`);
        if (brightness >= 360) drivers.push('brightness ≥ 360 K — sustained intense burn');
        if (wind && wind.wind_speed >= 25) drivers.push(`${wind.wind_speed.toFixed(0)} km/h ${compass(wind.wind_direction)} wind amplifying spread`);
        else if (wind && wind.wind_speed >= 15) drivers.push(`${wind.wind_speed.toFixed(0)} km/h ${compass(wind.wind_direction)} wind contributing to spread`);
        if (precip < 0.5) drivers.push('no measurable rainfall in 48 h forecast');
        if (!drivers.length) drivers.push('Localised thermal anomaly; no dominant driver from available correlations');

        // Forecast
        const forecast = [];
        if (wind && wind.wind_speed >= 5) {
            const dir = compass(wind.wind_direction);
            const advanceKm = Math.max(1, Math.round(wind.wind_speed * 0.4)); // 24 h rule of thumb
            const intensifier = wind.wind_speed >= 25 ? 'Strong' : wind.wind_speed >= 15 ? 'Moderate' : 'Light';
            forecast.push(`${intensifier} ${dir} wind — smoke + spread risk ~${advanceKm} km in 24 h`);
        } else if (wind) {
            forecast.push('Wind near-calm — limited spread, smoke pools locally');
        }
        if (precip > 10) {
            forecast.push(`${precip.toFixed(0)} mm rain forecast 48 h — could moderate this fire`);
        } else {
            forecast.push('No rainfall relief in 48 h forecast');
        }

        // Confidence
        const conf = props.confidence || 'n';
        const confLabel = String(conf).toLowerCase().startsWith('h') ? 'high'
            : String(conf).toLowerCase().startsWith('l') ? 'low' : 'nominal';
        const detectedAt = props.acq_date
            ? new Date(`${props.acq_date}T${props.acq_time || '0000'}`.replace(/(\d{2})(\d{2})$/, '$1:$2:00Z'))
            : null;

        // So-what sentence: combine rank chip with the strongest substantive driver.
        // Strip generic stub drivers from the headline.
        const headlineDriver = drivers.find(d => !d.startsWith('Localised'));
        const soWhat = (() => {
            const parts = [];
            if (rankChip) parts.push(rankChip + '.');
            else parts.push(`${frp.toFixed(0)} MW thermal anomaly.`);
            if (headlineDriver) {
                // Capitalise first letter so the sentence reads naturally
                const d = headlineDriver.charAt(0).toUpperCase() + headlineDriver.slice(1);
                parts.push(d + '.');
            } else {
                parts.push('Verify against local fuels, slope and containment status.');
            }
            return parts.join(' ');
        })();

        return {
            title,
            badges: [
                { label: intensity, color: frp >= 300 ? '#7f1d1d' : frp >= 120 ? '#dc2626' : '#f97316' },
                rankChip ? { label: rankChip, color: '#0c4a6e' } : null,
            ].filter(Boolean),
            soWhat,
            why: drivers,
            forecast: forecast.length ? forecast : ['Insufficient correlation data for projection'],
            confidence: {
                source: `NASA FIRMS ${props.satellite || 'VIIRS'}`,
                level: confLabel,
                detected: detectedAt,
                fetched: timeAgo(detectedAt) || 'unknown',
            },
            radiusKm,
            colorAccent: '#f97316',
        };
    };

    const floodBrief = (props, lat, lon) => {
        const { wind, precip } = correlationContext(lat, lon);
        const status = (props.status || '').toLowerCase();
        const severity = (props.severity || '').toLowerCase();
        const intensity = status.includes('major') || severity === 'extreme' ? 'Major'
            : severity === 'severe' ? 'Moderate' : 'Active';

        const drivers = [];
        if (precip > 30) drivers.push(`${precip.toFixed(0)} mm rain forecast 48 h sustaining flooding`);
        else if (precip > 5) drivers.push(`${precip.toFixed(0)} mm forecast — water levels likely steady`);
        else drivers.push('Forecast is dry — peak may already be passing');
        if (props.urgency) drivers.push(`urgency rated ${props.urgency.toLowerCase()}`);

        const forecast = [];
        if (precip > 30) forecast.push('Rising — additional flooding expected within 48 h');
        else if (precip > 5) forecast.push('Steady — current footprint likely persists');
        else forecast.push('Easing — without new rainfall, levels should fall');

        return {
            title: `${intensity} flood ${props.event || 'alert'}`.trim(),
            badges: [
                { label: intensity, color: intensity === 'Major' ? '#1d4ed8' : '#3b82f6' },
                { label: severity || 'active', color: '#0c4a6e' },
            ],
            soWhat: `${props.headline || props.area || 'Flood zone activated.'} ${forecast[0]}.`,
            why: drivers,
            forecast,
            confidence: {
                source: props.sender || 'NOAA / NWS',
                level: (props.certainty || 'observed').toLowerCase(),
                detected: props.effective ? new Date(props.effective) : null,
                fetched: timeAgo(props.effective),
            },
            radiusKm: impactRadiusKm('floods', props),
            colorAccent: '#3b82f6',
        };
    };

    const quakeBrief = (props, lat, lon) => {
        const mag = Number(props.mag || props.magnitude) || 0;
        const depth = Number(props.depth_km) || 0;
        const intensity = mag >= 7 ? 'Major' : mag >= 6 ? 'Strong' : mag >= 5 ? 'Moderate' : mag >= 4 ? 'Light' : 'Minor';
        const rank = percentileFor('earthquakes-source', 'mag', mag);
        const rankChip = mag >= 4 ? formatRankChip(rank, 'quakes this week') : '';

        const drivers = [
            `Focal depth ${depth.toFixed(0)} km (${depth < 70 ? 'shallow — strong surface shaking' : depth < 300 ? 'intermediate' : 'deep — less surface impact'})`,
            'Tectonic-driven; not weather-correlated',
        ];

        const forecast = [];
        if (mag >= 6) forecast.push('Aftershocks likely within 24–72 h — expect M ≥ 5');
        if (mag >= 7) forecast.push('Tsunami risk if epicentre offshore — check coastal alerts');
        if (depth < 70 && mag >= 5) forecast.push('Landslide risk on steep slopes within ~50 km');
        if (!forecast.length) forecast.push('Aftershock probability low');

        return {
            title: `M${mag.toFixed(1)} earthquake`,
            badges: [
                { label: intensity, color: mag >= 6 ? '#7f1d1d' : mag >= 5 ? '#dc2626' : '#a855f7' },
                rankChip ? { label: rankChip, color: '#0c4a6e' } : null,
            ].filter(Boolean),
            soWhat: `${props.place || `Lat ${lat.toFixed(2)}, Lon ${lon.toFixed(2)}`}. ${mag >= 5 ? 'Felt strongly across the region.' : 'Likely weakly felt.'}`,
            why: drivers,
            forecast,
            confidence: {
                source: 'USGS Earthquake Hazards',
                level: props.status || 'reviewed',
                detected: props.time ? new Date(Number(props.time)) : null,
                fetched: timeAgo(props.time ? Number(props.time) : null),
            },
            radiusKm: impactRadiusKm('earthquakes', props),
            colorAccent: '#a855f7',
        };
    };

    const droughtBrief = (props, lat, lon) => {
        const sev = props.max_severity || 'D0';
        const intensity = sev === 'D4' ? 'Exceptional' : sev === 'D3' ? 'Extreme' : sev === 'D2' ? 'Severe' : sev === 'D1' ? 'Moderate' : 'Abnormally dry';
        const { precip } = correlationContext(lat, lon);

        const drivers = [
            'Persistent precipitation deficit',
            precip < 5 ? 'Forecast dry — no relief in 48 h' : `${precip.toFixed(0)} mm rain forecast — limited relief`,
        ];

        const forecast = [];
        if (sev === 'D3' || sev === 'D4') forecast.push('Wildfire ignition probability elevated for weeks');
        forecast.push('Crop and pasture stress; water-supply pressure mounting');

        return {
            title: `${intensity} drought (${sev})`,
            badges: [{ label: sev, color: sev === 'D4' ? '#7f1d1d' : sev === 'D3' ? '#dc2626' : '#f97316' }],
            soWhat: `${props.county || 'Region'} ${props.state ? ', ' + props.state : ''} in ${intensity.toLowerCase()} drought. ${forecast[0] || ''}`,
            why: drivers,
            forecast,
            confidence: {
                source: 'US Drought Monitor',
                level: 'weekly composite',
                detected: props.valid_date ? new Date(props.valid_date) : null,
                fetched: timeAgo(props.valid_date),
            },
            radiusKm: 75,
            colorAccent: '#d97706',
        };
    };

    const volcanoBrief = (props, lat, lon) => {
        const { wind } = correlationContext(lat, lon);
        const alert = (props.alert_level || 'Normal');
        const drivers = [`Last eruption: ${props.last_eruption || 'unknown'}`];
        if (wind) drivers.push(`Wind ${wind.wind_speed.toFixed(0)} km/h ${compass(wind.wind_direction)} — ash would drift ${compass((wind.wind_direction + 180) % 360)}`);
        const forecast = [];
        if (alert === 'Warning') forecast.push('Eruption ongoing or imminent — check aviation colour code');
        else if (alert === 'Watch') forecast.push('Heightened unrest — monitor seismicity');
        else forecast.push('Background activity — long-term watch');

        return {
            title: `${props.name || 'Volcano'} · ${alert}`,
            badges: [
                { label: alert, color: alert === 'Warning' ? '#dc2626' : alert === 'Watch' ? '#f97316' : '#22c55e' },
                { label: props.volcano_type || 'volcano', color: '#7f1d1d' },
            ],
            soWhat: `${props.country || 'Volcano'} at ${alert.toLowerCase()} level. ${forecast[0] || ''}`,
            why: drivers,
            forecast,
            confidence: {
                source: 'Smithsonian GVP',
                level: 'inventory',
                detected: null,
                fetched: 'static',
            },
            radiusKm: 60,
            colorAccent: '#ef4444',
        };
    };

    const aqBrief = (props, lat, lon) => {
        const aqi = props.aqi || props.us_aqi || 0;
        const pm25 = props.pm25 || 0;
        const intensity = aqi > 300 ? 'Hazardous' : aqi > 200 ? 'Very unhealthy' : aqi > 150 ? 'Unhealthy' : aqi > 100 ? 'Sensitive groups' : aqi > 50 ? 'Moderate' : 'Good';
        const { wind } = correlationContext(lat, lon);
        const drivers = [];
        if (pm25 > 35) drivers.push(`PM2.5 at ${pm25.toFixed(0)} µg/m³ — likely smoke or industrial`);
        if (wind && wind.wind_speed < 8) drivers.push('Light wind — pollutants trapped, stagnation likely');
        if (wind && wind.wind_speed >= 8) drivers.push(`${wind.wind_speed.toFixed(0)} km/h ${compass(wind.wind_direction)} — transport from upwind sources`);

        return {
            title: `AQI ${aqi} · ${intensity}`,
            badges: [{ label: intensity, color: aqi > 200 ? '#7f1d1d' : aqi > 100 ? '#dc2626' : '#f97316' }],
            soWhat: `Vulnerable groups should reduce outdoor activity. UV ${props.uv_index?.toFixed?.(1) || '--'}.`,
            why: drivers.length ? drivers : ['Local conditions trapping pollutants'],
            forecast: [(wind && wind.wind_speed < 8) ? 'Stagnant air — expect persistence' : 'Wind may clear or transport plume'],
            confidence: {
                source: 'Open-Meteo Air Quality',
                level: 'model grid',
                detected: new Date(),
                fetched: 'live',
            },
            radiusKm: 50,
            colorAccent: '#10b981',
        };
    };

    const briefBuilders = {
        fires: fireBrief,
        floods: floodBrief,
        earthquakes: quakeBrief,
        drought: droughtBrief,
        volcanoes: volcanoBrief,
        airquality: aqBrief,
    };

    // ----------------------------------------------------------
    //  HTML COMPOSITION
    // ----------------------------------------------------------

    const renderBriefShell = (brief, lat, lon, hazardType) => {
        const badges = brief.badges.map(b =>
            `<span class="ei-badge" style="background:${b.color};">${esc(b.label)}</span>`
        ).join('');
        const why = brief.why.map(w => `<li>${esc(w)}</li>`).join('');
        const forecast = brief.forecast.map(f => `<li>${esc(f)}</li>`).join('');
        const conf = brief.confidence;

        return `
        <div class="ei-brief" style="--ei-accent:${brief.colorAccent};">
            <div class="ei-header">
                <div class="ei-eyebrow">${esc(hazardType.toUpperCase())} · ${lat.toFixed(2)}°, ${lon.toFixed(2)}°</div>
                <div class="ei-title">${esc(brief.title)}</div>
                <div class="ei-badges">${badges}</div>
            </div>
            <div class="ei-sowhat"><b>So what.</b> ${esc(brief.soWhat)}</div>

            <div class="ei-section">
                <div class="ei-section-label">Why it's happening</div>
                <ul class="ei-list">${why}</ul>
            </div>

            <div class="ei-section">
                <div class="ei-section-label">Where it's going (24–48 h)</div>
                <ul class="ei-list">${forecast}</ul>
            </div>

            <div class="ei-section" data-impact-section>
                <div class="ei-section-label">Who's affected · ${brief.radiusKm} km projected zone</div>
                <div class="ei-impact-loading">Querying OpenStreetMap…</div>
            </div>

            <div class="ei-section" data-response-section>
                <div class="ei-section-label">Active response context</div>
                <div class="ei-response-loading">Searching nearest tracking events…</div>
            </div>

            <div class="ei-confidence">
                <div><b>Source.</b> ${esc(conf.source)}</div>
                <div><b>Confidence.</b> ${esc(conf.level)}</div>
                <div><b>Observed.</b> ${conf.detected ? conf.detected.toISOString().replace('T', ' ').slice(0, 16) + ' UTC' : 'unknown'} · ${esc(conf.fetched)}</div>
            </div>
        </div>`;
    };

    /** Build an Overpass-turbo URL preloaded with a given query (for Verify links). */
    const overpassTurboUrl = (query) =>
        `https://overpass-turbo.eu/?Q=${encodeURIComponent(query)}&R=`;

    /** Build a category-specific Overpass query for the Verify link per infra type. */
    const categoryVerifyUrl = (category, lat, lon, radiusKm) => {
        const r = Math.round(radiusKm * 1000);
        const filters = {
            hospital: `nwr["amenity"="hospital"](around:${r},${lat},${lon});`,
            clinic: `nwr["amenity"="clinic"](around:${r},${lat},${lon});`,
            school: `nwr["amenity"="school"](around:${r},${lat},${lon});`,
            fire_station: `nwr["amenity"="fire_station"](around:${r},${lat},${lon});`,
            power_plant: `nwr["power"="plant"](around:${r},${lat},${lon});`,
            place: `node["place"~"^(city|town|village|hamlet|suburb)$"](around:${r},${lat},${lon});`,
        };
        const query = `[out:json][timeout:25];(${filters[category]});out tags center 200;`;
        return overpassTurboUrl(query);
    };

    /** Render one auditable infrastructure row.
     *  @param sourceNote — optional honest note about the data source
     *    (e.g. "OSM only · no authoritative global registry available"
     *    for hospitals/clinics where we don't have cross-validation).
     */
    const renderInfraRow = (label, count, names, verifyUrl, crossValidation, sourceNote) => {
        if (count === 0) {
            return `
                <div class="ei-audit-row ei-audit-zero">
                    <span class="ei-audit-count">0</span>
                    <span class="ei-audit-label">${esc(label)}</span>
                    <a class="ei-audit-verify" href="${verifyUrl}" target="_blank" rel="noopener">OSM ↗</a>
                </div>`;
        }
        const examples = names && names.length
            ? `<div class="ei-audit-examples">e.g. ${names.map(esc).join(' · ')}${count > names.length ? ' · …' : ''}</div>`
            : `<div class="ei-audit-examples ei-audit-unnamed">none with name tag</div>`;
        const crossHtml = crossValidation || '';
        const noteHtml = sourceNote
            ? `<div class="ei-audit-source-note">${esc(sourceNote)}</div>`
            : '';
        return `
            <div class="ei-audit-row">
                <span class="ei-audit-count">${count}</span>
                <span class="ei-audit-label">${esc(label)}</span>
                <a class="ei-audit-verify" href="${verifyUrl}" target="_blank" rel="noopener">OSM ↗</a>
                ${examples}
                ${noteHtml}
                ${crossHtml}
            </div>`;
    };

    /** Render the WRI cross-validation chip for power plants. */
    const renderWriChip = async (impact) => {
        if (!impact.wriCrossValidation) return '';
        try {
            const wri = await impact.wriCrossValidation;
            if (!wri.available) return '';
            const osm = impact.powerPlants;
            const wriN = wri.count;
            // Consider validated if within 50% of each other (counts always differ
            // because OSM and WRI use different definitions of 'plant').
            const ratio = osm > 0 && wriN > 0 ? Math.min(osm, wriN) / Math.max(osm, wriN) : 0;
            const status = (osm > 0 && wriN > 0 && ratio >= 0.5) ? 'agree'
                : (osm > 0 && wriN > 0) ? 'partial'
                : (osm > 0 || wriN > 0) ? 'one-source'
                : 'none';
            const statusLabel = {
                'agree': '✓ cross-validated',
                'partial': '⚠ partial overlap',
                'one-source': '⚠ one source only',
                'none': '— no plants',
            }[status];
            const statusColor = {
                'agree': '#22c55e',
                'partial': '#f97316',
                'one-source': '#fbbf24',
                'none': 'rgba(255,255,255,0.4)',
            }[status];
            const examples = wri.plants.length
                ? `<div class="ei-wri-plants">e.g. ${wri.plants.map(p =>
                    `${esc(p.name)}${p.capacity ? ' (' + Math.round(p.capacity) + ' MW)' : ''}`
                  ).join(' · ')}</div>`
                : '';
            return `
                <div class="ei-wri-chip" style="--cv-color:${statusColor};">
                    <span class="ei-wri-source">OSM ${osm}</span>
                    <span class="ei-wri-sep">·</span>
                    <span class="ei-wri-source">WRI ${wriN}</span>
                    <span class="ei-wri-status">${statusLabel}</span>
                    ${examples}
                </div>`;
        } catch (e) {
            return '';
        }
    };

    const renderImpact = async (impact, radiusKm) => {
        if (!impact) {
            return '<div class="ei-impact-error">OSM query failed — try again or widen your zoom.</div>';
        }

        // Place names + population
        const places = impact.places.slice(0, 4).map(p => `
            <div class="ei-place">
                <span class="ei-place-type">${esc(p.type)}</span>
                <span class="ei-place-name">${esc(p.name)}</span>
                <span class="ei-place-pop">${p.population > 0 ? p.population.toLocaleString() : '—'}</span>
            </div>`).join('');

        const popLine = impact.populationSum > 0
            ? `<b>${impact.populationSum.toLocaleString()}</b> people · ${impact.placesTagged} of ${impact.places.length} settlements tagged with <code>population=*</code>`
            : impact.places.length > 0
                ? `${impact.places.length} settlement${impact.places.length === 1 ? '' : 's'} mapped · no population tags`
                : 'No mapped settlements in zone';

        // Pre-compute cross-validation HTML for power plants
        const wriChip = await renderWriChip(impact);

        const placeVerify = categoryVerifyUrl('place', impact.lat, impact.lon, radiusKm);

        // Honest source-coverage notes: for hospitals/clinics we surface
        // that no independent global registry is available (Healthsites.io
        // exists but is an OSM-derived re-publication, so not independent).
        // Schools + fire stations get no note since we never promised
        // cross-validation. Power plants get the WRI cross-validation chip.
        const osmOnlyNote = 'OSM only · no independent global registry';
        const infra = `
            ${renderInfraRow('Hospitals', impact.hospitals, impact.hospitalNames,
                categoryVerifyUrl('hospital', impact.lat, impact.lon, radiusKm), null, osmOnlyNote)}
            ${renderInfraRow('Clinics', impact.clinics, impact.clinicNames,
                categoryVerifyUrl('clinic', impact.lat, impact.lon, radiusKm), null, osmOnlyNote)}
            ${renderInfraRow('Schools', impact.schools, impact.schoolNames,
                categoryVerifyUrl('school', impact.lat, impact.lon, radiusKm), null, null)}
            ${renderInfraRow('Fire stations', impact.fireStations, impact.fireStationNames,
                categoryVerifyUrl('fire_station', impact.lat, impact.lon, radiusKm), null, null)}
            ${renderInfraRow('Power plants', impact.powerPlants, impact.powerPlantNames,
                categoryVerifyUrl('power_plant', impact.lat, impact.lon, radiusKm), wriChip, null)}
        `;

        // Coverage indicator
        const cov = impact.coverage || { level: 'UNKNOWN', reason: '' };
        const covColor = cov.level === 'HIGH' ? '#22c55e' : cov.level === 'MEDIUM' ? '#fbbf24' : '#a3a3a3';

        return `
            <div class="ei-pop-block">
                <div class="ei-pop-summary">${popLine}</div>
                ${places ? `<div class="ei-places">${places}</div>` : ''}
                <div class="ei-pop-verify">
                    <a class="ei-audit-verify" href="${placeVerify}" target="_blank" rel="noopener">Verify settlements on OSM ↗</a>
                </div>
            </div>

            <div class="ei-audit-block">
                <div class="ei-audit-block-label">Infrastructure · OpenStreetMap (community-mapped)</div>
                ${infra}
            </div>

            <div class="ei-coverage-row" style="--cov-color:${covColor};">
                <span class="ei-coverage-dot"></span>
                <span class="ei-coverage-level">OSM coverage: ${cov.level}</span>
                <span class="ei-coverage-reason">${esc(cov.reason)}</span>
            </div>
        `;
    };

    const renderResponse = (events) => {
        if (!events.length) return '<div class="ei-impact-error">No GDACS or EONET tracking within 800 km</div>';
        return events.map(e => `
            <div class="ei-response-row">
                <span class="ei-response-tag">${esc(e.label)}</span>
                <span class="ei-response-title">${esc(e.title)}</span>
                <span class="ei-response-dist">${e.distKm.toFixed(0)} km</span>
            </div>`).join('');
    };

    // ----------------------------------------------------------
    //  PUBLIC API
    // ----------------------------------------------------------

    /**
     * Drop / update a marker on the map at the clicked feature so the user
     * keeps a visual handle on what the Selected drawer is reading.
     */
    const dropSelectedMarker = (lat, lon, accent) => {
        if (!window.ecoMap) return;
        if (window._eiSelectedMarker) window._eiSelectedMarker.remove();
        const el = document.createElement('div');
        el.style.cssText = `
            width: 18px; height: 18px; border-radius: 50%;
            background: ${accent || '#58A6FF'};
            border: 3px solid #fff;
            box-shadow: 0 0 0 6px ${accent || '#58A6FF'}33,
                        0 0 16px ${accent || '#58A6FF'};
            cursor: pointer;
        `;
        window._eiSelectedMarker = new maplibregl.Marker({ element: el })
            .setLngLat([lon, lat])
            .addTo(window.ecoMap);
    };

    /**
     * Render the brief into the right-side drawer's Selected pane instead
     * of a floating MapLibre popup. This is the preferred surface — the
     * popup version (showBrief) is kept for fallback / hover use.
     */
    const showBriefInDrawer = async (hazardType, props, lngLat) => {
        const map = window.ecoMap;
        if (!map) return;
        const builder = briefBuilders[hazardType];
        const lat = lngLat.lat;
        const lon = lngLat.lng;

        // Fallback to popup if no builder exists or drawer isn't ready
        if (!builder || !window.EcoLensDrawer?.renderSelected) {
            return showBrief(hazardType, props, lngLat);
        }

        const brief = builder(props, lat, lon);
        const html = renderBriefShell(brief, lat, lon, hazardType);

        // Push into drawer + drop marker
        window.EcoLensDrawer.renderSelected(html, {
            lat, lon, lng: lon, zoom: 10,
        });
        dropSelectedMarker(lat, lon, brief.colorAccent);

        // Centre the map on the clicked feature so the user can actually
        // see what they tapped. Offset to the LEFT so the feature isn't
        // hidden behind the right drawer.
        try {
            const rect = map.getCanvas().getBoundingClientRect();
            const currentZoom = map.getZoom();
            // Keep current zoom if it's already reasonable, otherwise zoom in.
            const targetZoom = currentZoom < 6 ? 8 : currentZoom < 9 ? currentZoom + 1 : currentZoom;
            // Push the centre rightward by ~160px so the feature sits in the
            // left-of-centre visible area (drawer takes ~320px on the right).
            map.easeTo({
                center: [lon, lat],
                zoom: targetZoom,
                offset: [-160, 0],
                duration: 900,
                essential: true,
            });
        } catch (e) { /* non-critical */ }

        // Async fills — same logic as popup version, just targeting drawer DOM
        const root = document.getElementById('drawer-selected-content');
        if (!root) return;
        const impactSection = root.querySelector('[data-impact-section]');
        const responseSection = root.querySelector('[data-response-section]');

        fetchImpactZone(lat, lon, brief.radiusKm).then(async impact => {
            if (!impactSection || !root.isConnected) return;
            const loading = impactSection.querySelector('.ei-impact-loading');
            if (loading) loading.remove();
            const html = await renderImpact(impact, brief.radiusKm);
            if (!root.isConnected) return;
            impactSection.insertAdjacentHTML('beforeend', html);
        });

        setTimeout(() => {
            if (!responseSection || !root.isConnected) return;
            const events = nearestResponse(lat, lon);
            const loading = responseSection.querySelector('.ei-response-loading');
            if (loading) loading.remove();
            responseSection.insertAdjacentHTML('beforeend', renderResponse(events));
        }, 50);
    };

    /**
     * Build the intelligence brief for a clicked feature and show it as a
     * MapLibre popup. Returns a Promise that resolves when async data has
     * populated (caller doesn't have to await — popup updates in place).
     */
    const showBrief = async (hazardType, props, lngLat) => {
        const map = window.ecoMap;
        if (!map) return;
        const builder = briefBuilders[hazardType];
        const lat = lngLat.lat;
        const lon = lngLat.lng;
        if (!builder) {
            // Fall back to a minimal brief
            new maplibregl.Popup({ closeButton: true, maxWidth: '380px' })
                .setLngLat(lngLat)
                .setHTML(`<div class="ei-brief"><div class="ei-title">${esc(hazardType)}</div><pre style="font-size:11px;">${esc(JSON.stringify(props, null, 2))}</pre></div>`)
                .addTo(map);
            return;
        }

        const brief = builder(props, lat, lon);
        const html = renderBriefShell(brief, lat, lon, hazardType);

        // Anchor 'auto' lets MapLibre flip the popup if the default position
        // would clip; offset keeps the popup off the click marker so the
        // user can still see the feature underneath.
        const popup = new maplibregl.Popup({
            closeButton: true,
            maxWidth: '380px',
            className: 'ei-popup',
            anchor: 'auto',
            offset: 16,
            focusAfterOpen: false,
        })
            .setLngLat(lngLat)
            .setHTML(html)
            .addTo(map);

        // If the click is in the lower portion of the visible map (i.e. would
        // collide with the bottom stats bar / time slider), gently pan up so
        // the popup has room to anchor above the feature.
        try {
            const rect = map.getCanvas().getBoundingClientRect();
            const pt = map.project([lon, lat]);
            const lowerThreshold = rect.height * 0.55;
            if (pt.y > lowerThreshold) {
                map.easeTo({
                    center: [lon, lat],
                    offset: [0, (rect.height * 0.25)],
                    duration: 500,
                });
            }
        } catch (e) { /* non-critical */ }

        // Async fills
        const popupEl = popup.getElement();
        const impactSection = popupEl?.querySelector('[data-impact-section]');
        const responseSection = popupEl?.querySelector('[data-response-section]');

        // 1) Impact zone via Overpass
        fetchImpactZone(lat, lon, brief.radiusKm).then(async impact => {
            if (!impactSection || !popupEl.isConnected) return;
            const loading = impactSection.querySelector('.ei-impact-loading');
            if (loading) loading.remove();
            const html = await renderImpact(impact, brief.radiusKm);
            if (!popupEl.isConnected) return;
            impactSection.insertAdjacentHTML('beforeend', html);
        });

        // 2) Response context (sync, just delay so layout settles)
        setTimeout(() => {
            if (!responseSection || !popupEl.isConnected) return;
            const events = nearestResponse(lat, lon);
            const loading = responseSection.querySelector('.ei-response-loading');
            if (loading) loading.remove();
            responseSection.insertAdjacentHTML('beforeend', renderResponse(events));
        }, 50);
    };

    return {
        showBrief,
        showBriefInDrawer,
        dropSelectedMarker,
        // Expose internals for testing
        _internal: { fireBrief, floodBrief, quakeBrief, percentileFor, nearestResponse, correlationContext, droughtAt, impactRadiusKm, fetchImpactZone },
    };
})();

window.EventIntelligence = EventIntelligence;
