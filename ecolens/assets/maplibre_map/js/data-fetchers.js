/* ============================================================
   EcoLens - Real-time Environmental Data Fetchers
   Fetches live data from NASA FIRMS, NOAA, USDM, GLIMS, etc.
   Each fetcher returns a GeoJSON FeatureCollection.
   ============================================================ */

const DataFetchers = (() => {
    'use strict';

    // ---------- Cache Layer ----------
    const cache = new Map();

    /**
     * Get cached data if still valid.
     * @param {string} key
     * @param {number} ttlMs - Time-to-live in milliseconds
     * @returns {object|null}
     */
    const getCached = (key, ttlMs) => {
        const entry = cache.get(key);
        if (entry && (Date.now() - entry.timestamp) < ttlMs) {
            console.log(`[DataFetchers] Cache hit: ${key}`);
            return entry.data;
        }
        return null;
    };

    /**
     * Store data in cache.
     * @param {string} key
     * @param {object} data
     */
    const setCache = (key, data) => {
        cache.set(key, { data, timestamp: Date.now() });
    };

    /**
     * Build an empty GeoJSON FeatureCollection.
     * @returns {object}
     */
    const emptyFC = () => ({ type: 'FeatureCollection', features: [] });

    /**
     * Parse CSV text to an array of objects using the header row.
     * @param {string} csvText
     * @returns {Array<object>}
     */
    const parseCSV = (csvText) => {
        const lines = csvText.trim().split('\n');
        if (lines.length < 2) return [];
        const headers = lines[0].split(',').map(h => h.trim());
        const rows = [];
        for (let i = 1; i < lines.length; i++) {
            const values = lines[i].split(',');
            if (values.length < headers.length) continue;
            const obj = {};
            headers.forEach((h, idx) => {
                obj[h] = values[idx] ? values[idx].trim() : '';
            });
            rows.push(obj);
        }
        return rows;
    };

    /**
     * Compute centroid of a GeoJSON Polygon / MultiPolygon (area-weighted).
     * Returns [lng, lat] or null if geometry is degenerate.
     * ArcGIS flat-coord polygons arrive as [[[lng,lat],[lng,lat],...]].
     */
    const polygonCentroid = (geom) => {
        if (!geom) return null;
        // Collect all rings from Polygon or MultiPolygon
        let rings = [];
        if (geom.type === 'Polygon') rings = geom.coordinates || [];
        else if (geom.type === 'MultiPolygon') {
            geom.coordinates?.forEach(poly => poly?.forEach(r => rings.push(r)));
        } else if (geom.type === 'Point') {
            return geom.coordinates;
        } else {
            return null;
        }
        // Use the outer ring of the first polygon; area-weighted centroid
        const ring = rings[0];
        if (!ring || ring.length < 3) return null;
        let x = 0, y = 0, area2 = 0;
        for (let i = 0; i < ring.length - 1; i++) {
            const [x0, y0] = ring[i];
            const [x1, y1] = ring[i + 1];
            const cross = x0 * y1 - x1 * y0;
            area2 += cross;
            x += (x0 + x1) * cross;
            y += (y0 + y1) * cross;
        }
        if (area2 === 0) {
            // Degenerate ring — fall back to simple mean of vertices
            let sx = 0, sy = 0, n = 0;
            ring.forEach(([px, py]) => { sx += px; sy += py; n++; });
            return n > 0 ? [sx / n, sy / n] : null;
        }
        const a = area2 * 3; // 6 * (area2 / 2) for centroid formula
        return [x / a, y / a];
    };

    /**
     * Safe fetch wrapper with timeout.
     * @param {string} url
     * @param {object} options
     * @param {number} timeoutMs
     * @returns {Promise<Response>}
     */
    const safeFetch = async (url, options = {}, timeoutMs = 30000) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
            const response = await fetch(url, { ...options, signal: controller.signal });
            clearTimeout(timer);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            return response;
        } catch (err) {
            clearTimeout(timer);
            throw err;
        }
    };

    // ==========================================================
    //  FIRE HOTSPOTS
    // ==========================================================

    /** TTL for fire data cache: 5 minutes */
    const FIRE_CACHE_TTL = 5 * 60 * 1000;

    /**
     * Fetch active fire hotspots from NASA FIRMS (VIIRS) or NIFC fallback.
     *
     * Primary: NASA FIRMS CSV API for VIIRS SNPP near-real-time data (last 24h).
     * Fallback: NIFC WFIGS Interagency Fire Perimeters (ArcGIS FeatureServer).
     *
     * @param {Array<number>} bbox - Optional [west, south, east, north]
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchActiveFires = async (bbox, days = 2) => {
        console.log('[DataFetchers] fetchActiveFires: START');
        const requestedDays = Math.max(1, Math.min(10, Math.ceil(Number(days) || 2)));
        const cacheKey = `fires_${bbox ? bbox.join(',') : 'world'}_${requestedDays}d`;
        const cached = getCached(cacheKey, FIRE_CACHE_TTL);
        if (cached) {
            console.log('[DataFetchers] fetchActiveFires: cache hit');
            return cached;
        }

        // --- Try EcoLens FIRMS proxy (Cloud Function calls FIRMS server-side) ---
        // The proxy holds the API key in Secret Manager and returns CORS-friendly
        // GeoJSON shaped exactly like the FIRMS branch used to produce. It tries
        // VIIRS-NOAA20 → SNPP → MODIS internally and returns the first non-empty.
        //
        // IMPORTANT: global FIRMS queries are clamped to 2 days. Verified
        // behavior of the FIRMS area API: a 2-day world query returns ~37k
        // hotspots; longer ranges (e.g. 7 days) silently return 0 rows.
        // The UI's day/week window still filters what's *displayed* — this
        // only bounds the fetch, and metadata.coverage_days is honest about it.
        const proxyDays = Math.min(requestedDays, 2);
        const proxyUrl = window.ECOLENS_FIRMS_PROXY_URL
            || 'https://us-central1-ecolens-ad854.cloudfunctions.net/firms_proxy';
        try {
            const url = `${proxyUrl}?days=${proxyDays}&sat=auto&area=world`;
            console.log('[DataFetchers] FIRMS proxy: requesting', url);
            const response = await safeFetch(url, {}, 60000);
            const fc = await response.json();
            const features = (fc && fc.features) || [];
            if (features.length > 0) {
                fc.metadata = { ...(fc.metadata || {}), coverage_days: proxyDays };
                setCache(cacheKey, fc);
                const meta = fc.metadata || {};
                console.log(`[DataFetchers] FIRMS proxy: ${features.length} hotspots (sat=${meta.satellite || '?'})`);
                return fc;
            }
            console.warn('[DataFetchers] FIRMS proxy returned 0 features:', fc.metadata);
        } catch (err) {
            console.warn('[DataFetchers] FIRMS proxy fetch failed:', err.message);
        }

        // --- Fallback: NIFC WFIGS ArcGIS FeatureServer ---
        // NIFC returns polygon perimeters — the fires-source is configured for POINT
        // clustering, so we must reduce each polygon to its centroid before emitting.
        try {
            let nifsUrl = 'https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson&resultRecordCount=2000';
            if (bbox) {
                nifsUrl += `&geometry=${bbox[0]},${bbox[1]},${bbox[2]},${bbox[3]}&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects`;
            }
            console.log('[DataFetchers] fetchActiveFires: calling NIFC fallback...');
            const response = await safeFetch(nifsUrl, {}, 25000);
            const geojson = await response.json();
            console.log('[DataFetchers] NIFC raw features:', geojson.features?.length || 0);

            // Reduce polygons → centroid points, and normalize properties.
            const pointFeatures = (geojson.features || [])
                .map(f => {
                    const centroid = polygonCentroid(f.geometry);
                    if (!centroid) return null;
                    const p = f.properties || {};
                    return {
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: centroid },
                        properties: {
                            brightness: 350,
                            brightness_temp: 350,
                            confidence: 'high',
                            satellite: 'NIFC',
                            acq_date: p.FireDiscoveryDateTime
                                ? new Date(p.FireDiscoveryDateTime).toISOString().split('T')[0]
                                : '',
                            frp: p.DailyAcres ? p.DailyAcres * 0.5 : 50,
                            fire_name: p.IncidentName || 'Unknown',
                            acres: p.GISAcres || p.DailyAcres || 0,
                            cause: p.FireCause || 'Unknown',
                            hazard_type: 'fire',
                        },
                    };
                })
                .filter(Boolean);

            // NIFC is USA-only. We do NOT pad with synthetic global fires —
            // honest partial coverage is better than fabricated hotspots.
            const fc = {
                type: 'FeatureCollection',
                features: pointFeatures,
                metadata: { source: 'NIFC WFIGS', coverage_days: requestedDays, coverage_note: 'USA current fire perimeters' },
            };
            setCache(cacheKey, fc);
            console.log(`[DataFetchers] NIFC: ${pointFeatures.length} US fire centroids (USA-only — FIRMS needed for global)`);
            return fc;
        } catch (err) {
            console.warn('[DataFetchers] NIFC fallback failed:', err.message);
        }

        // --- Last resort: global demo samples only ---
        const sampleFires = generateSampleFires();
        setCache(cacheKey, sampleFires);
        console.log(`[DataFetchers] Using ${sampleFires.features.length} demo fire samples (no live source available)`);
        return sampleFires;
    };

    /**
     * Empty fire FeatureCollection used only when no verified source is reachable.
     * We intentionally do NOT fabricate synthetic "indicative" fires — empty is
     * the honest answer. Global coverage requires a working FIRMS API key.
     */
    const generateSampleFires = () => {
        return { type: 'FeatureCollection', features: [] };
    };

    // ==========================================================
    //  FLOOD ALERTS
    // ==========================================================

    /** TTL for flood data cache: 15 minutes */
    const FLOOD_CACHE_TTL = 15 * 60 * 1000;

    /**
     * Fetch flood alert data from NOAA National Water Prediction Service gauges.
     *
     * @param {Array<number>} bbox - Optional [west, south, east, north]
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchFloodAlerts = async (bbox) => {
        const bboxStr = bbox ? bbox.join(',') : '-125,24,-66,50';
        const cacheKey = `floods_${bboxStr}`;
        const cached = getCached(cacheKey, FLOOD_CACHE_TTL);
        if (cached) return cached;

        // NOAA NWPS gauge API changed its bbox signature (HTTP 400). Use the
        // modern NOAA NWS Alerts feed which returns real flood/surge warnings
        // with full polygon geometries + severity + a text description.
        try {
            const nwsUrl = 'https://api.weather.gov/alerts/active?event=Flood%20Warning,Flash%20Flood%20Warning,Coastal%20Flood%20Warning,Flood%20Advisory,Flash%20Flood%20Watch';
            const response = await safeFetch(nwsUrl, {
                headers: { 'Accept': 'application/geo+json' },
            }, 25000);
            const data = await response.json();
            const alerts = data.features || [];
            const features = alerts
                .filter(a => a.geometry)  // Some alerts lack geometry
                .map(a => {
                    const p = a.properties || {};
                    const event = (p.event || '').toLowerCase();
                    const sev = (p.severity || '').toLowerCase();
                    const status = event.includes('flash') ? 'major'
                                 : sev === 'extreme' ? 'major'
                                 : sev === 'severe' ? 'moderate'
                                 : sev === 'moderate' ? 'minor'
                                 : 'action';
                    const coords = a.geometry.type === 'Polygon'
                        ? a.geometry.coordinates[0][0]
                        : a.geometry.type === 'MultiPolygon'
                        ? a.geometry.coordinates[0][0][0]
                        : [0, 0];
                    return {
                        type: 'Feature',
                        geometry: a.geometry,
                        properties: {
                            gauge_id: p.id || '',
                            name: p.event || 'Flood alert',
                            status,
                            severity: p.severity || 'Unknown',
                            certainty: p.certainty || '',
                            urgency: p.urgency || '',
                            headline: p.headline || '',
                            area: p.areaDesc || '',
                            effective: p.effective || '',
                            expires: p.expires || '',
                            sender: p.senderName || 'NWS',
                            risk_level: floodStatusToRisk(status),
                            hazard_type: 'flood',
                            point_lng: coords[0],
                            point_lat: coords[1],
                        },
                    };
                });

            if (features.length > 0) {
                const fc = { type: 'FeatureCollection', features };
                setCache(cacheKey, fc);
                console.log(`[DataFetchers] NOAA NWS: ${features.length} active flood warnings loaded (USA)`);
                return fc;
            }
        } catch (err) {
            console.warn('[DataFetchers] NOAA NWS flood alerts fetch failed:', err.message);
        }

        // --- Generate sample flood data ---
        const sampleFloods = generateSampleFloods();
        setCache(cacheKey, sampleFloods);
        return sampleFloods;
    };

    /** Map flood status string to a normalized value */
    const normalizeFloodStatus = (status) => {
        const s = String(status).toLowerCase();
        if (s.includes('major')) return 'major';
        if (s.includes('moderate')) return 'moderate';
        if (s.includes('minor') || s.includes('flood')) return 'minor';
        if (s.includes('action')) return 'action';
        return 'normal';
    };

    /** Map flood status to numeric risk level 0-3 */
    const floodStatusToRisk = (status) => {
        const s = normalizeFloodStatus(status);
        return { major: 3, moderate: 2, minor: 1, action: 0.5, normal: 0 }[s] || 0;
    };

    /** Get buffer radius in degrees based on flood severity */
    const getFloodBufferRadius = (status) => {
        const s = normalizeFloodStatus(status);
        return { major: 0.15, moderate: 0.1, minor: 0.06, action: 0.04, normal: 0.02 }[s] || 0.03;
    };

    /**
     * Create a rough circular polygon (12 sides) around a point.
     * @param {number} lng
     * @param {number} lat
     * @param {number} radiusDeg - Radius in degrees
     * @returns {object} GeoJSON Polygon geometry
     */
    const createBufferPolygon = (lng, lat, radiusDeg) => {
        const sides = 12;
        const coords = [];
        for (let i = 0; i <= sides; i++) {
            const angle = (i / sides) * 2 * Math.PI;
            coords.push([
                lng + radiusDeg * Math.cos(angle) / Math.cos(lat * Math.PI / 180),
                lat + radiusDeg * Math.sin(angle)
            ]);
        }
        return { type: 'Polygon', coordinates: [coords] };
    };

    /** Generate sample flood zones for demo */
    const generateSampleFloods = () => {
        // Global flood-prone locations across all continents
        const locations = [
            // Asia
            { lng: 90.40, lat: 23.81, name: 'Dhaka Meghna River, Bangladesh', status: 'major', stage: 19.5 },
            { lng: 67.99, lat: 27.20, name: 'Sindh Indus River, Pakistan', status: 'major', stage: 22.1 },
            { lng: 85.32, lat: 27.72, name: 'Kathmandu Bagmati, Nepal', status: 'moderate', stage: 11.3 },
            // Europe
            { lng: 7.10, lat: 50.53, name: 'Ahr Valley, Germany', status: 'moderate', stage: 14.8 },
            { lng: -0.47, lat: 39.47, name: 'Valencia Turia, Spain', status: 'minor', stage: 8.2 },
            // Africa
            { lng: 32.58, lat: 15.60, name: 'Khartoum Blue Nile, Sudan', status: 'major', stage: 17.6 },
            { lng: 27.50, lat: -11.68, name: 'Lubumbashi River, DRC', status: 'moderate', stage: 10.4 },
            // Americas
            { lng: -90.07, lat: 29.95, name: 'New Orleans Mississippi, USA', status: 'moderate', stage: 17.2 },
            { lng: -95.37, lat: 29.76, name: 'Houston Bayou, USA', status: 'minor', stage: 12.8 },
            { lng: -43.17, lat: -22.91, name: 'Rio de Janeiro, Brazil', status: 'minor', stage: 9.1 },
            // Oceania
            { lng: 152.95, lat: -27.56, name: 'Brisbane River, Australia', status: 'action', stage: 7.5 },
        ];

        const features = locations.map(loc => {
            const radius = getFloodBufferRadius(loc.status);
            return {
                type: 'Feature',
                geometry: createBufferPolygon(loc.lng, loc.lat, radius),
                properties: {
                    gauge_id: `SAMPLE_${loc.name.replace(/\s+/g, '_')}`,
                    name: loc.name,
                    status: loc.status,
                    stage: loc.stage,
                    flow: Math.round(Math.random() * 50000 + 5000),
                    risk_level: floodStatusToRisk(loc.status),
                    hazard_type: 'flood',
                    point_lng: loc.lng,
                    point_lat: loc.lat
                }
            };
        });

        return { type: 'FeatureCollection', features };
    };

    // ==========================================================
    //  DROUGHT DATA
    // ==========================================================

    /** TTL for drought data cache: 1 hour */
    const DROUGHT_CACHE_TTL = 60 * 60 * 1000;

    /**
     * Fetch drought data from the US Drought Monitor API.
     *
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchDroughtData = async () => {
        const cacheKey = 'drought_us';
        const cached = getCached(cacheKey, DROUGHT_CACHE_TTL);
        if (cached) return cached;

        const now = new Date();
        const endDate = now.toISOString().split('T')[0].replace(/-/g, '');
        const startDate = new Date(now - 7 * 86400000).toISOString().split('T')[0].replace(/-/g, '');

        // --- Try USDM County Statistics ---
        try {
            const usdmUrl = `https://usdmdataservices.unl.edu/api/CountyStatistics/GetDroughtSeverityStatisticsByAreaPercent?aoi=us&startdate=${startDate}&enddate=${endDate}&statisticsType=1`;
            const response = await safeFetch(usdmUrl, {
                headers: { 'Accept': 'application/json' }
            }, 25000);
            const data = await response.json();

            if (data && data.length > 0) {
                // Group by FIPS and create point-based features (county centroids)
                const features = data
                    .filter(d => d.FIPS && (d.D0 > 0 || d.D1 > 0 || d.D2 > 0 || d.D3 > 0 || d.D4 > 0))
                    .slice(0, 1000)
                    .map(d => {
                        // Approximate centroid from FIPS (real app would use a FIPS->centroid lookup)
                        const coords = fipsToCentroid(d.FIPS);
                        const maxSeverity = d.D4 > 0 ? 'D4' : d.D3 > 0 ? 'D3' : d.D2 > 0 ? 'D2' : d.D1 > 0 ? 'D1' : 'D0';
                        return {
                            type: 'Feature',
                            geometry: createBufferPolygon(coords[0], coords[1], 0.2),
                            properties: {
                                fips: d.FIPS,
                                county: d.County || '',
                                state: d.State || '',
                                d0: parseFloat(d.D0) || 0,
                                d1: parseFloat(d.D1) || 0,
                                d2: parseFloat(d.D2) || 0,
                                d3: parseFloat(d.D3) || 0,
                                d4: parseFloat(d.D4) || 0,
                                none: parseFloat(d.None) || 0,
                                max_severity: maxSeverity,
                                severity_index: { D0: 1, D1: 2, D2: 3, D3: 4, D4: 5 }[maxSeverity] || 0,
                                valid_date: d.MapDate || d.ValidStart || '',
                                hazard_type: 'drought'
                            }
                        };
                    });

                const fc = { type: 'FeatureCollection', features };
                setCache(cacheKey, fc);
                console.log(`[DataFetchers] USDM: ${features.length} drought areas loaded`);
                return fc;
            }
        } catch (err) {
            console.warn('[DataFetchers] USDM drought fetch failed:', err.message);
        }

        // --- Sample drought data ---
        const sampleDrought = generateSampleDrought();
        setCache(cacheKey, sampleDrought);
        return sampleDrought;
    };

    /**
     * Approximate county centroid from FIPS code.
     * Uses a simple hash-based approximation for the continental US.
     */
    const fipsToCentroid = (fips) => {
        const code = parseInt(fips) || 0;
        const stateFips = Math.floor(code / 1000);
        // Simple approximation: spread across CONUS bounds
        const lng = -125 + ((code * 7) % 5900) / 100;
        const lat = 25 + ((stateFips * 13 + code * 3) % 2400) / 100;
        return [Math.max(-125, Math.min(-66, lng)), Math.max(25, Math.min(49, lat))];
    };

    /** Generate sample drought data for demo */
    const generateSampleDrought = () => {
        // Global drought regions — real drought-affected areas worldwide
        const droughtRegions = [
            // North America
            { lng: -119.5, lat: 36.5, severity: 'D4', name: 'Central California, USA' },
            { lng: -111.5, lat: 33.5, severity: 'D3', name: 'Central Arizona, USA' },
            { lng: -100.0, lat: 31.5, severity: 'D2', name: 'West Texas, USA' },
            // Africa — Sahel & Horn
            { lng: 2.0, lat: 14.0, severity: 'D4', name: 'Sahel Region, Niger' },
            { lng: 38.75, lat: 9.0, severity: 'D4', name: 'Ethiopian Highlands' },
            { lng: 45.0, lat: 2.0, severity: 'D3', name: 'Horn of Africa, Somalia' },
            { lng: 36.0, lat: -1.0, severity: 'D2', name: 'East Africa, Kenya' },
            // Asia
            { lng: 78.0, lat: 26.0, severity: 'D3', name: 'Rajasthan, India' },
            { lng: 68.0, lat: 25.0, severity: 'D3', name: 'Sindh, Pakistan' },
            { lng: 110.0, lat: 35.0, severity: 'D2', name: 'North China Plain' },
            // South America
            { lng: -64.0, lat: -31.5, severity: 'D3', name: 'Córdoba, Argentina' },
            { lng: -49.0, lat: -23.5, severity: 'D2', name: 'São Paulo State, Brazil' },
            // Europe / Mediterranean
            { lng: -3.7, lat: 37.0, severity: 'D2', name: 'Andalusia, Spain' },
            { lng: 12.5, lat: 42.0, severity: 'D1', name: 'Central Italy' },
            // Oceania
            { lng: 145.0, lat: -33.0, severity: 'D2', name: 'New South Wales, Australia' },
        ];

        const severityMap = { D0: 1, D1: 2, D2: 3, D3: 4, D4: 5 };

        const features = droughtRegions.map(r => ({
            type: 'Feature',
            geometry: createBufferPolygon(r.lng, r.lat, 1.5 + Math.random() * 0.5),
            properties: {
                county: r.name,
                state: '',
                d0: r.severity === 'D0' ? 80 : 100,
                d1: severityMap[r.severity] >= 2 ? 70 + Math.random() * 20 : 0,
                d2: severityMap[r.severity] >= 3 ? 50 + Math.random() * 20 : 0,
                d3: severityMap[r.severity] >= 4 ? 30 + Math.random() * 20 : 0,
                d4: severityMap[r.severity] >= 5 ? 10 + Math.random() * 15 : 0,
                max_severity: r.severity,
                severity_index: severityMap[r.severity],
                hazard_type: 'drought'
            }
        }));

        return { type: 'FeatureCollection', features };
    };

    // ==========================================================
    //  GLACIER DATA
    // ==========================================================

    /** TTL for glacier data cache: 1 hour */
    const GLACIER_CACHE_TTL = 60 * 60 * 1000;

    /**
     * Fetch glacier outlines from GLIMS (Global Land Ice Measurements from Space).
     *
     * @param {Array<number>} bbox - Optional [west, south, east, north]
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchGlacierData = async () => {
        const cacheKey = 'glaciers_global_ne';
        const cached = getCached(cacheKey, GLACIER_CACHE_TTL);
        if (cached) return cached;

        // GLIMS WFS endpoint (glims.org) is 404 dead. Use Natural Earth
        // 1:10m Glaciated Areas — 1,886 real glacier polygons worldwide.
        // CC0 public domain, curated by NACIS.
        const url = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_glaciated_areas.geojson';
        try {
            console.log('[DataFetchers] Glaciers: fetching Natural Earth global...');
            const response = await safeFetch(url, {}, 30000);
            const geojson = await response.json();

            if (geojson.features && geojson.features.length > 0) {
                geojson.features.forEach(f => {
                    const p = f.properties || {};
                    f.properties = {
                        glacier_name: p.name || 'Glaciated area',
                        featurecla: p.featurecla || 'Glacier',
                        scalerank: p.scalerank,
                        source_date: 'Natural Earth 1:10m',
                        hazard_type: 'glacier',
                        data_source: 'Natural Earth 1:10m',
                    };
                });
                setCache(cacheKey, geojson);
                console.log(`[DataFetchers] Natural Earth: ${geojson.features.length} glacier polygons loaded (global)`);
                return geojson;
            }
        } catch (err) {
            console.warn('[DataFetchers] Natural Earth glacier fetch failed:', err.message);
        }

        // Fallback to small curated named-glacier sample only if CDN is unreachable
        const sampleGlaciers = generateSampleGlaciers();
        setCache(cacheKey, sampleGlaciers);
        return sampleGlaciers;
    };

    /** Generate sample glacier data for demo */
    const generateSampleGlaciers = () => {
        const glaciers = [
            { lng: 86.925, lat: 27.988, name: 'Khumbu Glacier', area: 12.5 },
            { lng: 79.089, lat: 30.727, name: 'Gangotri Glacier', area: 27.8 },
            { lng: 76.532, lat: 32.372, name: 'Bara Shigri Glacier', area: 15.2 },
            { lng: 6.862, lat: 45.832, name: 'Mer de Glace', area: 30.4 },
            { lng: 10.983, lat: 46.828, name: 'Gepatschferner', area: 16.7 },
            { lng: -148.893, lat: 61.058, name: 'Columbia Glacier', area: 405.0 },
            { lng: -121.757, lat: 46.852, name: 'Emmons Glacier', area: 11.2 },
            { lng: -73.0, lat: -49.0, name: 'Perito Moreno', area: 250.0 },
            { lng: 77.6, lat: 35.4, name: 'Siachen Glacier', area: 700.0 },
            { lng: -19.0, lat: 64.1, name: 'Vatnajokull', area: 7900.0 },
        ];

        const features = glaciers.map(g => {
            const sizeFactor = Math.sqrt(g.area) * 0.005;
            return {
                type: 'Feature',
                geometry: createBufferPolygon(g.lng, g.lat, Math.max(0.02, sizeFactor)),
                properties: {
                    glacier_name: g.name,
                    area_km2: g.area,
                    source_date: '2023-01-01',
                    retreat_rate: Math.round(Math.random() * 40 + 5),
                    elevation_max: Math.round(3000 + Math.random() * 5000),
                    elevation_min: Math.round(1000 + Math.random() * 3000),
                    hazard_type: 'glacier'
                }
            };
        });

        return { type: 'FeatureCollection', features };
    };

    // ==========================================================
    //  NDVI / VEGETATION
    // ==========================================================

    /** TTL for NDVI cache: 6 hours */
    const NDVI_CACHE_TTL = 6 * 60 * 60 * 1000;

    /**
     * Return NDVI raster tile configuration.
     * In a production setup, this would provide COG URLs from Copernicus/Sentinel Hub.
     *
     * @returns {Promise<object>} Configuration object with tile URLs
     */
    const fetchNDVIData = async () => {
        const cacheKey = 'ndvi_config';
        const cached = getCached(cacheKey, NDVI_CACHE_TTL);
        if (cached) return cached;

        // NDVI raster tiles configuration
        // Using sample Sentinel-2 NDVI COG or tile endpoint
        const config = {
            type: 'raster',
            tiles: [
                // Placeholder: In production, replace with actual Copernicus Data Space Ecosystem endpoint
                // or a pre-processed NDVI tile server
                'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg'
            ],
            tileSize: 256,
            attribution: 'Sentinel-2 Cloudless by EOX',
            maxzoom: 14,
            // Color ramp for NDVI interpretation
            colorRamp: {
                '-0.2': '#8B0000',  // Bare / water
                '0.0': '#FF4500',   // Bare soil
                '0.15': '#FF8C00',  // Sparse vegetation
                '0.3': '#FFD700',   // Light vegetation
                '0.5': '#ADFF2F',   // Moderate vegetation
                '0.7': '#32CD32',   // Dense vegetation
                '0.9': '#006400'    // Very dense vegetation
            }
        };

        setCache(cacheKey, config);
        console.log('[DataFetchers] NDVI config prepared');
        return config;
    };

    // ==========================================================
    //  WATERSHED DATA
    // ==========================================================

    /** TTL for watershed cache: 1 hour */
    const WATERSHED_CACHE_TTL = 60 * 60 * 1000;

    /**
     * Fetch watershed boundaries and stream networks from USGS WBD and HydroSHEDS.
     *
     * @param {Array<number>} bbox - Optional [west, south, east, north]
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchWatershedData = async (bbox) => {
        const cacheKey = 'watershed_global_ne';
        const cached = getCached(cacheKey, WATERSHED_CACHE_TTL);
        if (cached) return cached;

        // Primary source: Natural Earth 1:50m global rivers + lake centerlines.
        // Natural Earth is CC0 public domain, curated by cartographers at the
        // North American Cartographic Information Society (NACIS). It is the
        // standard verified base hydrography dataset used by governments and
        // publications worldwide. Mirror hosted on GitHub raw CDN.
        const url = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_rivers_lake_centerlines.geojson';
        try {
            console.log('[DataFetchers] Watersheds: fetching Natural Earth global rivers...');
            const response = await safeFetch(url, {}, 25000);
            const geojson = await response.json();

            if (geojson.features && geojson.features.length > 0) {
                // Normalize properties to match the layer style expectations.
                // Natural Earth gives: name, name_alt, scalerank, featurecla
                geojson.features.forEach(f => {
                    const p = f.properties || {};
                    f.properties = {
                        name: p.name || p.name_alt || 'Unnamed river',
                        feature_type: 'stream',  // Rendered as line by watershed-streams layer
                        scalerank: p.scalerank,
                        featurecla: p.featurecla,
                        hazard_type: 'watershed',
                        data_source: 'Natural Earth 1:50m',
                    };
                });
                setCache(cacheKey, geojson);
                console.log(`[DataFetchers] Natural Earth: ${geojson.features.length} global river/lake features loaded`);
                return geojson;
            }
        } catch (err) {
            console.warn('[DataFetchers] Natural Earth fetch failed:', err.message);
        }

        // If Natural Earth is unreachable, return empty — no fabrication.
        const empty = { type: 'FeatureCollection', features: [] };
        setCache(cacheKey, empty);
        return empty;
    };

    /** Unused — kept only to not break any ArcGIS-buffer helper callers. */
    const generateSampleWatersheds = () => {
        const watersheds = [];

        // Boundaries (polygons)
        const boundaryFeatures = watersheds.map(w => ({
            type: 'Feature',
            geometry: createBufferPolygon(w.lng, w.lat, w.size),
            properties: {
                name: w.name,
                feature_type: 'watershed_boundary',
                area_acres: Math.round(w.size * w.size * 50000),
                hazard_type: 'watershed'
            }
        }));

        // Stream network lines (simplified)
        const streamFeatures = watersheds.map(w => {
            const points = [];
            let x = w.lng - w.size * 0.8;
            let y = w.lat + w.size * 0.5;
            for (let i = 0; i < 8; i++) {
                points.push([x, y]);
                x += w.size * 0.2 + (Math.random() - 0.5) * 0.3;
                y -= w.size * 0.12 + (Math.random() - 0.5) * 0.1;
            }
            return {
                type: 'Feature',
                geometry: { type: 'LineString', coordinates: points },
                properties: {
                    name: w.name + ' Main Stem',
                    feature_type: 'stream',
                    hazard_type: 'watershed'
                }
            };
        });

        return { type: 'FeatureCollection', features: [...boundaryFeatures, ...streamFeatures] };
    };

    // ==========================================================
    //  MULTI-HAZARD RISK INDEX (Composite)
    // ==========================================================

    /**
     * Generate a combined multi-hazard risk surface from loaded data.
     * Produces a point grid with composite risk scores.
     *
     * @param {object} allData - { fires, floods, drought } GeoJSON collections
     * @returns {object} GeoJSON FeatureCollection of risk points
     */
    const generateRiskSurface = (allData = {}) => {
        const riskPoints = [];

        // Add risk from fire hotspots
        if (allData.fires && allData.fires.features) {
            allData.fires.features.forEach(f => {
                const coords = f.geometry.type === 'Point'
                    ? f.geometry.coordinates
                    : null;
                if (!coords) return;
                riskPoints.push({
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: coords },
                    properties: {
                        risk_score: Math.min(1, (f.properties.brightness_temp - 300) / 80),
                        risk_type: 'fire',
                        hazard_type: 'risk'
                    }
                });
            });
        }

        // Add risk from flood zones
        if (allData.floods && allData.floods.features) {
            allData.floods.features.forEach(f => {
                const lng = f.properties.point_lng || 0;
                const lat = f.properties.point_lat || 0;
                if (!lng || !lat) return;
                riskPoints.push({
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: [lng, lat] },
                    properties: {
                        risk_score: f.properties.risk_level / 3,
                        risk_type: 'flood',
                        hazard_type: 'risk'
                    }
                });
            });
        }

        // Add risk from drought
        if (allData.drought && allData.drought.features) {
            allData.drought.features.forEach(f => {
                const geom = f.geometry;
                // Use centroid of polygon
                let lng = 0, lat = 0;
                if (geom.type === 'Polygon' && geom.coordinates[0]) {
                    const ring = geom.coordinates[0];
                    ring.forEach(c => { lng += c[0]; lat += c[1]; });
                    lng /= ring.length;
                    lat /= ring.length;
                }
                if (!lng || !lat) return;
                riskPoints.push({
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: [lng, lat] },
                    properties: {
                        risk_score: (f.properties.severity_index || 0) / 5,
                        risk_type: 'drought',
                        hazard_type: 'risk'
                    }
                });
            });
        }

        return { type: 'FeatureCollection', features: riskPoints };
    };

    // ==========================================================
    //  AUTO-REFRESH MANAGER
    // ==========================================================

    const refreshIntervals = new Map();

    /**
     * Start auto-refreshing data for a hazard type.
     * @param {string} type - 'fires', 'floods', etc.
     * @param {Function} fetcher - The fetch function to call
     * @param {number} intervalMs - Refresh interval in milliseconds
     * @param {Function} onData - Callback with new data
     */
    const startAutoRefresh = (type, fetcher, intervalMs, onData) => {
        stopAutoRefresh(type);
        console.log(`[DataFetchers] Auto-refresh started for ${type} every ${intervalMs / 1000}s`);

        const run = async () => {
            try {
                // Clear cache to force refresh
                const keysToDelete = [];
                cache.forEach((_, key) => {
                    if (key.startsWith(type)) keysToDelete.push(key);
                });
                keysToDelete.forEach(k => cache.delete(k));

                const data = await fetcher();
                if (onData) onData(data);
            } catch (err) {
                console.warn(`[DataFetchers] Auto-refresh error for ${type}:`, err.message);
            }
        };

        const intervalId = setInterval(run, intervalMs);
        refreshIntervals.set(type, intervalId);
    };

    /**
     * Stop auto-refreshing for a hazard type.
     * @param {string} type
     */
    const stopAutoRefresh = (type) => {
        if (refreshIntervals.has(type)) {
            clearInterval(refreshIntervals.get(type));
            refreshIntervals.delete(type);
            console.log(`[DataFetchers] Auto-refresh stopped for ${type}`);
        }
    };

    /** Stop all auto-refreshes */
    const stopAllRefresh = () => {
        refreshIntervals.forEach((id, type) => {
            clearInterval(id);
            console.log(`[DataFetchers] Auto-refresh stopped for ${type}`);
        });
        refreshIntervals.clear();
    };

    // ==========================================================
    //  Public API
    // ==========================================================

    // ==========================================================
    //  EARTHQUAKE DATA (USGS)
    // ==========================================================

    /** TTL for earthquake cache: 5 minutes */
    const EARTHQUAKE_CACHE_TTL = 5 * 60 * 1000;

    /**
     * Fetch earthquakes for a requested time window via USGS.
     * Day/week/month use summary feeds. Longer windows use the query API with
     * M4.5+ to keep the response usable for a web map.
     *
     * @param {number} hoursBack - Requested window size in hours
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchEarthquakes = async (hoursBack = 24) => {
        const hours = Math.max(24, Number(hoursBack) || 24);
        const days = Math.ceil(hours / 24);
        const cacheKey = `earthquakes_${days}d`;
        const cached = getCached(cacheKey, EARTHQUAKE_CACHE_TTL);
        if (cached) return cached;

        try {
            const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
                .toISOString()
                .split('T')[0];
            const url = days <= 1
                ? 'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson'
                : days <= 7
                    ? 'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson'
                    : days <= 30
                        ? 'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_month.geojson'
                        : `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=${start}&minmagnitude=4.5&orderby=time&limit=2000`;
            const resp = await safeFetch(
                url,
                {},
                days > 30 ? 25000 : 15000
            );
            const geojson = await resp.json();

            // Add hazard_type property to each feature
            geojson.features.forEach(f => {
                f.properties.hazard_type = 'earthquake';
                f.properties.magnitude = f.properties.mag;
                f.properties.depth_km = f.geometry.coordinates[2];
                f.properties.place = f.properties.place || 'Unknown';
                f.properties.time_str = new Date(f.properties.time).toISOString();
            });
            geojson.metadata = { ...(geojson.metadata || {}), coverage_days: days };

            setCache(cacheKey, geojson);
            console.log(`[DataFetchers] USGS: ${geojson.features.length} earthquakes loaded (${days}d window)`);
            return geojson;
        } catch (err) {
            console.warn('[DataFetchers] USGS earthquake fetch failed:', err.message);
            return emptyFC();
        }
    };

    // ==========================================================
    //  AIR QUALITY DATA (Open-Meteo)
    // ==========================================================

    /** TTL for air quality cache: 30 minutes */
    const AQ_CACHE_TTL = 30 * 60 * 1000;

    /**
     * Fetch global air quality data from Open-Meteo Air Quality API.
     * Zero auth, no API key required. Creates a grid of sample points.
     *
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchAirQuality = async () => {
        const cacheKey = 'airquality';
        const cached = getCached(cacheKey, AQ_CACHE_TTL);
        if (cached) return cached;

        try {
            // Build a grid of points covering the globe
            const gridPoints = [];
            for (let lat = -60; lat <= 70; lat += 15) {
                for (let lon = -170; lon <= 170; lon += 15) {
                    gridPoints.push({ lat, lon });
                }
            }

            // Open-Meteo supports comma-separated coordinates
            const lats = gridPoints.map(p => p.lat).join(',');
            const lons = gridPoints.map(p => p.lon).join(',');

            const resp = await safeFetch(
                `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lats}&longitude=${lons}&current=pm2_5,pm10,us_aqi,uv_index&timezone=auto`,
                {},
                20000
            );
            const data = await resp.json();

            // Convert to GeoJSON
            const features = [];
            if (Array.isArray(data)) {
                data.forEach((station, i) => {
                    if (station.current && station.current.pm2_5 != null) {
                        features.push({
                            type: 'Feature',
                            geometry: { type: 'Point', coordinates: [gridPoints[i].lon, gridPoints[i].lat] },
                            properties: {
                                hazard_type: 'airquality',
                                pm25: station.current.pm2_5,
                                pm10: station.current.pm10,
                                aqi: station.current.us_aqi,
                                uv_index: station.current.uv_index,
                            }
                        });
                    }
                });
            }

            const geojson = { type: 'FeatureCollection', features };
            setCache(cacheKey, geojson);
            console.log(`[DataFetchers] Open-Meteo AQ: ${features.length} points loaded`);
            return geojson;
        } catch (err) {
            console.warn('[DataFetchers] Air quality fetch failed:', err.message);
            return emptyFC();
        }
    };

    // ==========================================================
    //  VOLCANO DATA (USGS)
    // ==========================================================

    /** TTL for volcano cache: 1 hour */
    const VOLCANO_CACHE_TTL = 60 * 60 * 1000;

    /**
     * Fetch volcano data from the USGS Volcano Hazards Program.
     * Zero auth, JSON response.
     *
     * @returns {Promise<object>} GeoJSON FeatureCollection
     */
    const fetchVolcanoes = async () => {
        const cacheKey = 'volcanoes';
        const cached = getCached(cacheKey, VOLCANO_CACHE_TTL);
        if (cached) return cached;

        // Primary: same-origin snapshot of the Smithsonian GVP Holocene catalog
        // (1,196 volcanoes, retrieved 2026-07-21). The GVP GeoServer sends no
        // CORS headers, so browsers cannot fetch it directly — that failure
        // showed up as "0 active" in production. The catalog changes rarely;
        // the snapshot carries its retrieval date in metadata.
        // Fallback: the live GVP WFS (works in non-browser contexts).
        try {
            let data = null;
            try {
                const snapResp = await safeFetch('data/gvp_volcanoes.json', {}, 15000);
                data = await snapResp.json();
                console.log(`[DataFetchers] GVP snapshot: ${(data.features || []).length} volcanoes (retrieved ${data.metadata?.retrieved || '?'})`);
            } catch (snapErr) {
                console.warn('[DataFetchers] GVP snapshot unavailable, trying live WFS:', snapErr.message);
                const gvpUrl = 'https://webservices.volcano.si.edu/geoserver/GVP-VOTW/ows?service=WFS&version=2.0.0&request=GetFeature&typeName=GVP-VOTW:Smithsonian_VOTW_Holocene_Volcanoes&outputFormat=application/json&count=2000';
                const resp = await safeFetch(gvpUrl, {}, 30000);
                data = await resp.json();
            }

            const features = (data.features || [])
                .filter(f => f.geometry?.coordinates?.length === 2)
                .map(f => {
                    const p = f.properties || {};
                    const lastYear = parseInt(p.Last_Eruption_Year, 10);
                    // Derive an alert level from recency of last eruption
                    const yearsAgo = isNaN(lastYear) ? 9999 : (new Date().getFullYear() - lastYear);
                    const alertLevel = yearsAgo <= 1 ? 'Warning'
                                     : yearsAgo <= 5 ? 'Watch'
                                     : yearsAgo <= 20 ? 'Advisory'
                                     : 'Normal';
                    return {
                        type: 'Feature',
                        geometry: f.geometry,
                        properties: {
                            hazard_type: 'volcano',
                            name: p.Volcano_Name || 'Unknown',
                            country: p.Country || '',
                            region: p.Region || '',
                            volcano_type: p.Primary_Volcano_Type || '',
                            last_eruption: lastYear || null,
                            alert_level: alertLevel,
                            elevation_m: p.Elevation || 0,
                            data_source: 'Smithsonian GVP',
                        },
                    };
                });

            const geojson = { type: 'FeatureCollection', features };
            setCache(cacheKey, geojson);
            console.log(`[DataFetchers] Smithsonian GVP: ${features.length} volcanoes loaded (global)`);
            return geojson;
        } catch (err) {
            console.warn('[DataFetchers] GVP volcano fetch failed:', err.message);
        }

        // Fallback: USGS HANS (USA only — Alaska, Hawaii, Lower 48)
        try {
            const resp = await safeFetch(
                'https://volcanoes.usgs.gov/hans-public/api/volcano/getVolcanoes', {}, 15000
            );
            const data = await resp.json();
            const features = (Array.isArray(data) ? data : [])
                .filter(v => v.latitude && v.longitude)
                .map(v => ({
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: [parseFloat(v.longitude), parseFloat(v.latitude)] },
                    properties: {
                        hazard_type: 'volcano',
                        name: v.volcanoName || 'Unknown',
                        alert_level: v.alertLevel || 'Normal',
                        aviation_color: v.aviationColorCode || 'UNASSIGNED',
                        observatory: v.observatory || '',
                        data_source: 'USGS HANS',
                    },
                }));
            const geojson = { type: 'FeatureCollection', features };
            setCache(cacheKey, geojson);
            console.log(`[DataFetchers] USGS HANS (USA fallback): ${features.length} volcanoes loaded`);
            return geojson;
        } catch (err) {
            console.warn('[DataFetchers] USGS volcano fallback failed:', err.message);
        }

        return emptyFC();
    };

    return {
        fetchActiveFires,
        fetchFloodAlerts,
        fetchDroughtData,
        fetchGlacierData,
        fetchNDVIData,
        fetchWatershedData,
        fetchEarthquakes,
        fetchAirQuality,
        fetchVolcanoes,
        generateRiskSurface,
        startAutoRefresh,
        stopAutoRefresh,
        stopAllRefresh
    };
})();

// Global access
window.DataFetchers = DataFetchers;
