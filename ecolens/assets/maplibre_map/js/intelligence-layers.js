/* ============================================================
   EcoLens — Intelligence Layers
   Adds the "why" + "who's responding" + "what conditions are
   driving this" layers on top of the existing real-time hazard
   feeds. All sources are free, no API keys required.

   Layer groups:
     WEATHER      — wind vectors, precipitation forecast, SST anomaly
     RESPONSE     — ReliefWeb situation reports, GDACS alerts,
                    NWS active warnings (all event types)
     CORRELATION  — fire-spread arrows (fire × wind), flood
                    escalation (flood × 48h precip), exposure (quake
                    × population proxy)

   Each layer is wired as <id="toggle-<key>"> in the sidebar. The
   pattern matches HazardLayers exactly so the existing pill UI
   logic in index.html picks up the .is-on / .expanded states.
   ============================================================ */

const IntelligenceLayers = (() => {
    'use strict';

    let map = null;
    const sourceState = new Map();   // sourceId -> last FeatureCollection
    const cache = new Map();         // url -> { data, ts }
    const lazyLoaded = new Set();    // layer keys whose lazy fetch has completed
    const lazyInFlight = new Map();  // layer key -> in-flight promise
    const boundPopupLayers = new Set(); // layer ids already wired for click
    let sharedPopup = null;          // one popup instance for every intel layer

    const TTL = {
        weather: 30 * 60 * 1000,   // 30 min
        response: 10 * 60 * 1000,  // 10 min
        alerts: 5 * 60 * 1000,     // 5 min
    };

    const cachedFetch = async (url, ttlMs, opts = {}) => {
        const entry = cache.get(url);
        if (entry && Date.now() - entry.ts < ttlMs) return entry.data;
        const controller = new AbortController();
        const t = setTimeout(() => controller.abort(), opts.timeoutMs || 25000);
        try {
            const r = await fetch(url, { ...opts, signal: controller.signal });
            clearTimeout(t);
            if (!r.ok) throw new Error(`HTTP ${r.status}`);
            const data = opts.asText ? await r.text() : await r.json();
            cache.set(url, { data, ts: Date.now() });
            return data;
        } catch (err) {
            clearTimeout(t);
            throw err;
        }
    };

    const emptyFC = () => ({ type: 'FeatureCollection', features: [] });

    /**
     * Attach a pill line to a FeatureCollection. `_meta` is an EcoLens-only
     * foreign member: updateSource reads it, strips it, and never lets it
     * reach MapLibre. It exists so a fetcher can state how complete its own
     * answer is instead of leaving the count span to infer completeness
     * from features.length — which is how a partial outage came to be
     * rendered as a whole, factual number.
     */
    const withMeta = (fc, meta) => Object.assign(fc, { _meta: meta });

    /** "1 published zone", "3 published zones". */
    const plural = (n, one, many) => n + ' ' + (n === 1 ? one : many);

    // ----------------------------------------------------------
    //  WEATHER — Open-Meteo grid samplers
    // ----------------------------------------------------------

    /**
     * Build a coarse global grid for sampling the Open-Meteo APIs.
     * Open-Meteo allows up to ~100 coordinate pairs per request.
     */
    const buildGlobalGrid = (latStep = 20, lonStep = 30) => {
        const pts = [];
        for (let lat = -60; lat <= 70; lat += latStep) {
            for (let lon = -170; lon <= 170; lon += lonStep) {
                pts.push({ lat, lon });
            }
        }
        return pts;
    };

    /** Fetch wind vectors from Open-Meteo forecast API (free, no key). */
    const fetchGlobalWind = async () => {
        const pts = buildGlobalGrid(20, 30);  // ~ 84 points
        const lats = pts.map(p => p.lat.toFixed(2)).join(',');
        const lons = pts.map(p => p.lon.toFixed(2)).join(',');
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}` +
            `&current=wind_speed_10m,wind_direction_10m,temperature_2m&timezone=UTC`;

        try {
            const data = await cachedFetch(url, TTL.weather, { timeoutMs: 30000 });
            const arr = Array.isArray(data) ? data : [data];
            const features = arr
                .map((entry, i) => {
                    const c = entry?.current;
                    const p = pts[i];
                    if (!c || !p || c.wind_speed_10m == null) return null;
                    return {
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
                        properties: {
                            wind_speed: c.wind_speed_10m,
                            wind_direction: c.wind_direction_10m,
                            temperature: c.temperature_2m,
                            // For symbol rotation MapLibre expects degrees clockwise from N.
                            // Met convention: wind_direction = where wind is COMING FROM.
                            // For an arrow pointing in the direction of travel, add 180.
                            arrow_rotation: (c.wind_direction_10m + 180) % 360,
                        },
                    };
                })
                .filter(Boolean);
            console.log(`[IntelLayers] Wind: ${features.length} grid points loaded`);
            return { type: 'FeatureCollection', features };
        } catch (err) {
            console.warn('[IntelLayers] Wind fetch failed:', err.message);
            return emptyFC();
        }
    };

    /** Fetch 48h cumulative precipitation forecast from Open-Meteo. */
    const fetchPrecipitationForecast = async () => {
        const pts = buildGlobalGrid(15, 25);  // ~ 130 points (slightly denser)
        // Open-Meteo caps coords per request; chunk in two if needed
        const chunks = [];
        for (let i = 0; i < pts.length; i += 80) chunks.push(pts.slice(i, i + 80));

        const features = [];
        for (const chunk of chunks) {
            const lats = chunk.map(p => p.lat.toFixed(2)).join(',');
            const lons = chunk.map(p => p.lon.toFixed(2)).join(',');
            const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}` +
                `&hourly=precipitation&forecast_days=2&timezone=UTC`;
            try {
                const data = await cachedFetch(url, TTL.weather, { timeoutMs: 30000 });
                const arr = Array.isArray(data) ? data : [data];
                arr.forEach((entry, i) => {
                    const hourly = entry?.hourly;
                    if (!hourly || !Array.isArray(hourly.precipitation)) return;
                    const total = hourly.precipitation.reduce((a, b) => a + (b || 0), 0);
                    if (total < 0.1) return;  // ignore dry grid cells
                    const p = chunk[i];
                    features.push({
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
                        properties: {
                            precip_mm_48h: Number(total.toFixed(1)),
                            severity: total > 100 ? 'extreme' : total > 50 ? 'heavy' : total > 20 ? 'moderate' : 'light',
                        },
                    });
                });
            } catch (err) {
                console.warn('[IntelLayers] Precip chunk failed:', err.message);
            }
        }
        console.log(`[IntelLayers] Precipitation forecast: ${features.length} wet grid cells`);
        return { type: 'FeatureCollection', features };
    };

    /**
     * Sea-surface temperature, as measured. No anomaly is shown.
     *
     * This layer used to subtract a seven-value hard-coded latitude table
     * from the live reading and print the difference at 22 px bold as "SST
     * Anomaly", sourced to a "zonal monthly climatology" the code did not
     * have. The table carried no month, no longitude and no basin, so a
     * February cell in the western Mediterranean read -2.0 °C against a
     * true OISST anomaly near zero, and was painted deep blue for it. A
     * constant is not a climatology and the distance from one is not an
     * anomaly, so the table and every figure derived from it are gone.
     *
     * The dataset that would answer "is this reading unusual?" is NOAA
     * OISST v2.1 1991-2020 daily climatology (NCEI / ERDDAP griddap),
     * gridded by day-of-year and by cell. Until that is wired in, EcoLens
     * shows the measurement and says plainly that it cannot answer.
     */
    const fetchSeaSurfaceTemperature = async () => {
        const pts = buildGlobalGrid(15, 25).filter(p => Math.abs(p.lat) <= 60);
        const chunks = [];
        for (let i = 0; i < pts.length; i += 80) chunks.push(pts.slice(i, i + 80));

        const features = [];
        for (const chunk of chunks) {
            const lats = chunk.map(p => p.lat.toFixed(2)).join(',');
            const lons = chunk.map(p => p.lon.toFixed(2)).join(',');
            const url = `https://marine-api.open-meteo.com/v1/marine?latitude=${lats}&longitude=${lons}` +
                `&current=sea_surface_temperature&timezone=UTC`;
            try {
                const data = await cachedFetch(url, TTL.weather, { timeoutMs: 30000 });
                const arr = Array.isArray(data) ? data : [data];
                arr.forEach((entry, i) => {
                    const sst = entry?.current?.sea_surface_temperature;
                    if (sst == null) return;
                    const p = chunk[i];
                    features.push({
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
                        properties: {
                            sst_c: Number(sst.toFixed(2)),
                        },
                    });
                });
            } catch (err) {
                console.warn('[IntelLayers] SST chunk failed:', err.message);
            }
        }
        console.log(`[IntelLayers] Sea surface temperature: ${features.length} marine grid cells`);
        return { type: 'FeatureCollection', features };
    };

    // ----------------------------------------------------------
    //  RESPONSE — ReliefWeb, GDACS, NWS active alerts
    // ----------------------------------------------------------

    /**
     * NASA EONET — Earth Observatory Natural Event Tracker. Free, no key,
     * CORS-friendly. Returns currently-open natural events worldwide with
     * categories (wildfires, severe storms, floods, volcanoes, etc.) and the
     * tracking source agency (USGS, FIRMS, IRWIN, JTWC, etc.). Replaces the
     * originally-spec'd ReliefWeb feed, which now requires registered appname.
     */
    const fetchEONETEvents = async () => {
        const url = 'https://eonet.gsfc.nasa.gov/api/v3/events?status=open&days=7&limit=200';
        try {
            const data = await cachedFetch(url, TTL.response);
            const items = data?.events || [];
            const features = items
                .map(item => {
                    // Take the most recent geometry point for the marker
                    const geoms = item.geometry || [];
                    const latest = geoms[geoms.length - 1];
                    if (!latest?.coordinates) return null;
                    const category = item.categories?.[0]?.title || 'Event';
                    const sources = (item.sources || []).map(s => s.id).join(', ');
                    return {
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: latest.coordinates },
                        properties: {
                            title: item.title || 'Open event',
                            category,
                            sources: sources || 'NASA EONET',
                            date: latest.date || '',
                            magnitude: latest.magnitudeValue || '',
                            magnitude_unit: latest.magnitudeUnit || '',
                            url: item.link || '',
                            country: '',  // EONET doesn't include country; left blank
                            disaster_type: category.toLowerCase(),
                        },
                    };
                })
                .filter(Boolean);
            console.log(`[IntelLayers] EONET: ${features.length} open natural events`);
            return { type: 'FeatureCollection', features };
        } catch (err) {
            console.warn('[IntelLayers] EONET fetch failed:', err.message);
            return emptyFC();
        }
    };

    /**
     * ReliefWeb humanitarian situation reports — kept as a stub for when
     * Laurence registers an appname. Returns empty until then.
     *   Register: https://apidoc.reliefweb.int/parameters#appname
     *   Once registered, set window.ECOLENS_RELIEFWEB_APPNAME and uncomment.
     */
    const fetchReliefWebReports = async () => {
        const appname = window.ECOLENS_RELIEFWEB_APPNAME;
        if (!appname) {
            console.log('[IntelLayers] ReliefWeb skipped: no appname configured. Set window.ECOLENS_RELIEFWEB_APPNAME after registering at https://apidoc.reliefweb.int/parameters#appname');
            return emptyFC();
        }
        const url = `https://api.reliefweb.int/v2/reports?appname=${encodeURIComponent(appname)}&limit=40` +
            '&query[value]=disaster%20OR%20emergency%20OR%20flood%20OR%20wildfire%20OR%20cyclone' +
            '&fields[include][]=title&fields[include][]=date&fields[include][]=country' +
            '&fields[include][]=primary_country&fields[include][]=source&fields[include][]=url' +
            '&fields[include][]=disaster' +
            '&sort[]=date.created:desc';
        try {
            const data = await cachedFetch(url, TTL.response);
            const items = data?.data || [];
            const features = items
                .map(item => {
                    const f = item.fields || {};
                    const country = f.primary_country || (Array.isArray(f.country) ? f.country[0] : null);
                    if (!country) return null;
                    const centroid = countryCentroid(country.iso3 || country.name);
                    if (!centroid) return null;
                    return {
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: centroid },
                        properties: {
                            title: f.title || 'Situation report',
                            country: country.name || '',
                            date: f.date?.created || '',
                            source: (Array.isArray(f.source) && f.source[0]?.shortname) || 'ReliefWeb',
                            url: f.url || '',
                            disaster_type: (Array.isArray(f.disaster) && f.disaster[0]?.type?.[0]?.name) || 'humanitarian',
                        },
                    };
                })
                .filter(Boolean);
            console.log(`[IntelLayers] ReliefWeb: ${features.length} active situation reports`);
            return { type: 'FeatureCollection', features };
        } catch (err) {
            console.warn('[IntelLayers] ReliefWeb fetch failed:', err.message);
            return emptyFC();
        }
    };

    /** Lightweight country-centroid table (ISO3 + name keys). */
    const COUNTRY_CENTROIDS = {
        // Asia
        AFG: [66.0, 33.9], BGD: [90.4, 23.7], CHN: [104.2, 35.9], IND: [78.7, 22.0],
        IDN: [113.9, -0.8], IRN: [53.7, 32.4], IRQ: [43.7, 33.2], JPN: [138.3, 36.2],
        MMR: [95.9, 21.9], NPL: [84.1, 28.4], PAK: [69.3, 30.4], PHL: [121.8, 12.9],
        SYR: [38.0, 34.8], THA: [101.0, 15.9], YEM: [48.5, 15.6], LKA: [80.8, 7.9],
        VNM: [108.3, 14.1], KOR: [127.8, 36.0], PRK: [127.5, 40.3],
        // Africa
        DZA: [1.7, 28.0], COD: [21.8, -4.0], EGY: [30.8, 26.8], ETH: [40.5, 9.1],
        KEN: [37.9, -0.0], MDG: [46.9, -18.8], MAR: [-7.1, 31.8], MOZ: [35.5, -18.7],
        NGA: [8.7, 9.1], SDN: [30.2, 16.0], SSD: [31.3, 6.9], SOM: [46.2, 5.2],
        TCD: [18.7, 15.5], TZA: [34.9, -6.4], UGA: [32.3, 1.4], ZWE: [29.2, -19.0],
        ZMB: [27.8, -13.1], MLI: [-3.5, 17.6], NER: [9.4, 17.6], BFA: [-1.6, 12.2],
        LBY: [17.2, 26.3], TUN: [9.6, 33.9], CAF: [20.9, 6.6],
        // Americas
        USA: [-95.7, 39.0], CAN: [-106.3, 56.1], MEX: [-102.5, 23.6], BRA: [-51.9, -10.8],
        ARG: [-63.6, -38.4], CHL: [-71.5, -35.7], COL: [-74.3, 4.6], CUB: [-79.0, 21.5],
        ECU: [-78.2, -1.8], HTI: [-72.3, 18.9], PER: [-75.0, -9.2], VEN: [-66.6, 6.4],
        BOL: [-63.6, -16.3], DOM: [-70.5, 18.7], GTM: [-90.2, 15.8], HND: [-86.2, 15.0],
        NIC: [-85.0, 12.9], PRY: [-58.4, -23.4], URY: [-55.8, -32.5], JAM: [-77.3, 18.1],
        // Europe
        UKR: [31.2, 49.0], TUR: [35.2, 39.0], GRC: [22.0, 39.1], ESP: [-3.7, 40.5],
        ITA: [12.6, 41.9], FRA: [2.2, 46.6], DEU: [10.5, 51.2], GBR: [-3.4, 55.4],
        POL: [19.1, 51.9], ROU: [25.0, 45.9], RUS: [105.3, 61.5], CHE: [8.2, 46.8],
        SRB: [21.0, 44.0], HRV: [15.2, 45.1], BIH: [17.7, 43.9], ALB: [20.0, 41.0],
        // Oceania
        AUS: [134.5, -25.7], NZL: [173.0, -41.8], PNG: [144.0, -6.5], FJI: [178.0, -17.7],
        VUT: [167.0, -16.0],
        // Caribbean / Central
        BHS: [-76.6, 24.7], TTO: [-61.3, 10.6], BRB: [-59.5, 13.2],
    };

    const countryCentroid = (key) => {
        if (!key) return null;
        const k = String(key).toUpperCase();
        return COUNTRY_CENTROIDS[k] || null;
    };

    // ─── REPORTED HUMAN IMPACT ────────────────────────────────
    //
    // The question a hazard map usually cannot answer: who was actually
    // affected? GDACS carries Sendai Framework indicator records — deaths,
    // missing, injured, displaced, rescued, buildings and infrastructure
    // damaged — each attached to a named region with its own report.
    //
    // THE TRAP, and why nothing here is summed:
    //   For the August 2026 China floods GDACS holds "54,000 evacuated in
    //   Guangxi Region" alongside "16,226 evacuated in Ningming County,
    //   Chongzuo, Guangxi" — the second sits INSIDE the first. For Nepal it
    //   holds fatalities of 359 and 165, which are successive counts of one
    //   rising toll, not 524 people. Adding these produces a bigger, more
    //   quotable and completely invented number. We report the largest single
    //   sourced report as a floor ("at least"), list every underlying report
    //   with its own wording, and say plainly that they may overlap.

    const IMPACT_ORDER = ['death', 'missing', 'injured', 'displaced', 'rescued',
        'affected', 'houses damaged', 'transport damaged'];
    const IMPACT_LABEL = {
        death: 'dead', missing: 'missing', injured: 'injured',
        displaced: 'displaced or evacuated', rescued: 'rescued',
        affected: 'affected', 'houses damaged': 'buildings damaged',
        'transport damaged': 'transport links damaged',
    };
    const GDACS_TYPES = { EQ: 'Earthquake', FL: 'Flood', TC: 'Tropical cyclone',
        WF: 'Wildfire', DR: 'Drought', VO: 'Volcano' };

    /** Largest single sourced report per indicator — never a sum. */
    const summariseImpacts = (records) => {
        const byName = {};
        for (const r of records) {
            const name = (r.sendainame || '').toLowerCase();
            const value = parseFloat(String(r.sendaivalue || '').replace(/,/g, ''));
            if (!name || !isFinite(value)) continue;
            (byName[name] = byName[name] || []).push({
                value,
                region: r.region || r.country || '',
                text: r.description || '',
            });
        }
        const out = [];
        for (const name of IMPACT_ORDER) {
            const rows = byName[name];
            if (!rows || !rows.length) continue;
            rows.sort((a, b) => b.value - a.value);
            out.push({ name, label: IMPACT_LABEL[name] || name,
                floor: rows[0].value, reports: rows });
        }
        // Anything GDACS adds that we have not named yet still gets through.
        for (const name of Object.keys(byName)) {
            if (IMPACT_ORDER.includes(name)) continue;
            const rows = byName[name].sort((a, b) => b.value - a.value);
            out.push({ name, label: name, floor: rows[0].value, reports: rows });
        }
        return out;
    };

    /** Severity weight of one indicator — people outrank property, always. */
    const indicatorWeight = (s) => {
        if (s.name === 'death') return s.floor * 1000;
        if (s.name === 'missing' || s.name === 'injured') return s.floor * 100;
        if (s.name === 'displaced' || s.name === 'affected') return s.floor;
        return s.floor * 0.1;
    };

    const impactWeight = (summary) =>
        summary.reduce((w, s) => w + indicatorWeight(s), 0);

    /**
     * The one line the marker carries. Not simply the most severe category:
     * a flood that killed one person and evacuated 54,000 is mislabelled by
     * "1 dead". The heaviest single indicator is the honest headline.
     */
    const headlineImpact = (summary) =>
        summary.reduce((best, s) =>
            (!best || indicatorWeight(s) > indicatorWeight(best)) ? s : best, null);

    /**
     * Escalated-event discovery — shared by the impact markers and by the
     * "Areas affected" footprints so both describe the same set of events.
     * One list call per hazard type, Orange and Red only, deduped by
     * eventid keeping the newest episode (episodes repeat heavily: GDACS
     * answers with 524 cyclone features for 12 distinct eventids over a
     * 7-day window).
     *
     * Returns { events, listsOk, listsFailed, failedTypes }. listsFailed
     * and failedTypes are the parts that matter for honesty: an empty or
     * shortened result because GDACS could not be reached must never be
     * rendered as "no escalated events". Both consumers read them and put
     * the shortfall on the pill — a run where the flood list 503'd is a
     * partial view, not a count.
     *
     * A result is cached only when at least one list answered. Caching a
     * total outage for the full TTL left ensureLoaded's deliberate retry
     * path issuing zero network requests, so a recovered GDACS could not
     * be picked up short of a page reload.
     */
    let escalatedCache = null;
    const ESCALATED_TTL = 10 * 60 * 1000;
    const GDACS_API = 'https://www.gdacs.org/gdacsapi/api/';

    /**
     * Strict numeric coercion. The global isFinite() runs ToNumber first,
     * so isFinite(null), isFinite(''), isFinite(false) and isFinite([]) are
     * all true — a feed with coordinates [null, null] would sail through
     * and plant a casualty marker at 0N 0E in the Gulf of Guinea.
     */
    const strictNum = (v) => {
        if (typeof v === 'number') return Number.isFinite(v) ? v : NaN;
        if (typeof v === 'string' && v.trim() !== '') {
            const n = Number(v);
            return Number.isFinite(n) ? n : NaN;
        }
        return NaN;
    };

    const discoverEscalatedEvents = async () => {
        if (escalatedCache && Date.now() - escalatedCache.ts < ESCALATED_TTL) {
            return escalatedCache.value;
        }
        const from = new Date(Date.now() - 7 * 86400000).toISOString().split('T')[0];
        const to = new Date().toISOString().split('T')[0];
        const seen = new Map();
        let listsOk = 0;
        let listsFailed = 0;
        const failedTypes = [];

        await Promise.allSettled(Object.keys(GDACS_TYPES).map(async (t) => {
            try {
                const resp = await fetch(GDACS_API + 'events/geteventlist/MAP?eventtype=' + t +
                    '&fromdate=' + from + '&todate=' + to,
                    { signal: AbortSignal.timeout(25000) });
                // eventtype=VO answers 404 with a body byte-identical to a
                // deliberately bogus eventtype, so it counts as a miss —
                // never as evidence of "no volcanic activity".
                if (!resp.ok) { listsFailed++; failedTypes.push(t); return; }
                const json = await resp.json();
                if (!json || !Array.isArray(json.features)) { listsFailed++; failedTypes.push(t); return; }
                listsOk++;
                for (const f of json.features) {
                    const p = (f && f.properties) || {};
                    if (p.alertlevel !== 'Orange' && p.alertlevel !== 'Red') continue;
                    const c = f.geometry && f.geometry.coordinates;
                    const lon = strictNum(Array.isArray(c) ? c[0] : undefined);
                    const lat = strictNum(Array.isArray(c) ? c[1] : undefined);
                    if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
                    if (Math.abs(lat) > 90 || Math.abs(lon) > 180) continue;
                    const key = t + ':' + p.eventid;
                    const ep = strictNum(p.episodeid);
                    const prev = seen.get(key);
                    if (prev && !(Number.isFinite(ep) && ep > prev.episodeid)) continue;
                    seen.set(key, {
                        type: t,
                        id: p.eventid,
                        episodeid: Number.isFinite(ep) ? ep : 1,
                        lon,
                        lat,
                        alertlevel: p.alertlevel,
                        country: p.country || '',
                        props: p,
                    });
                }
            } catch (err) {
                listsFailed++;
                failedTypes.push(t);
            }
        }));

        const value = { events: [...seen.values()], listsOk, listsFailed, failedTypes };
        // Only cache a result that actually reached GDACS. Caching a total
        // outage for the full 10-minute TTL made ensureLoaded's retry path
        // — lazyLoaded.delete, so "a later switch-on" can try again —
        // issue zero fetches: GDACS could recover, the user could toggle
        // the pill off and on, and the stale failure came straight back.
        if (listsOk > 0) escalatedCache = { value, ts: Date.now() };
        return value;
    };

    /**
     * The hazard types whose event list could not be reached, named. This
     * is what listsFailed was for: it was computed and then read by
     * nobody, so a partial GDACS outage silently shrank both layers and
     * the pills presented the remainder as the whole dataset.
     */
    const listOutageNames = (disc) => {
        if (!disc || !disc.listsFailed) return '';
        const names = (disc.failedTypes || []).map((t) => GDACS_TYPES[t] || t);
        return names.length ? names.join(', ') : disc.listsFailed + ' hazard type(s)';
    };

    const fetchDisasterImpacts = async () => {
        const disc = await discoverEscalatedEvents();
        if (!disc.listsOk) {
            // Every list call failed. Rendering "0 events with reported
            // impact" here would assert an absence of harm we have no
            // evidence for; the count stays blank instead.
            throw new Error('GDACS event list unreachable — impact count unknown');
        }

        // Detail call per escalated event — capped, because this is a
        // background overlay and must never dominate the load budget.
        const events = disc.events.slice(0, 24);
        const features = [];
        await Promise.allSettled(events.map(async (ev) => {
            const resp = await fetch(GDACS_API + 'events/geteventdata?eventtype=' + ev.type +
                '&eventid=' + encodeURIComponent(ev.id),
                { signal: AbortSignal.timeout(25000) });
            if (!resp.ok) throw new Error('HTTP ' + resp.status);
            const json = await resp.json();
            const p = (json && json.properties) || json || {};
            const summary = summariseImpacts(p.sendai || []);
            if (!summary.length) return; // no reported impact → no marker
            const headline = headlineImpact(summary);
            if (!headline) return;
            features.push({
                type: 'Feature',
                geometry: { type: 'Point', coordinates: [ev.lon, ev.lat] },
                properties: {
                    hazard: GDACS_TYPES[ev.type] || ev.type,
                    country: p.country || ev.country || '',
                    alertlevel: p.alertlevel || ev.alertlevel || '',
                    eventid: String(ev.id),
                    from: (p.fromdate || '').split('T')[0],
                    url: 'https://www.gdacs.org/report.aspx?eventtype=' + ev.type +
                        '&eventid=' + ev.id,
                    // PRESENTATION ONLY — a cross-indicator ordering rank
                    // built by adding records the header above says must
                    // never be added. It drives the marker radius and
                    // nothing else. It has no source and no unit, so it
                    // must never be printed as a figure.
                    severity_rank: impactWeight(summary),
                    // "at least" travels with the number. The on-map label
                    // is the surface that gets read, screenshotted and
                    // quoted without the popup ever being opened, so the
                    // floor qualifier cannot live in the popup alone.
                    badge: 'at least ' + Math.round(headline.floor).toLocaleString() +
                        ' ' + headline.label,
                    summary: JSON.stringify(summary),
                },
            });
        }));
        const missing = listOutageNames(disc);
        if (missing) {
            // The reader has to be able to tell "GDACS reports no impact
            // for these hazards" from "EcoLens never reached those lists".
            const note = 'Partial view: the GDACS event list for ' + missing +
                ' could not be reached on this load, so escalated events of ' +
                'that type are missing from this layer entirely.';
            for (const f of features) f.properties.coverageNote = note;
        }
        console.log('[IntelLayers] impact records for', features.length, 'escalated events',
            missing ? '(partial — lists missing: ' + missing + ')' : '');
        return withMeta({ type: 'FeatureCollection', features }, {
            line: plural(features.length, 'event', 'events') + ' with reported impact' +
                (missing ? ' · partial: ' + missing + ' unreachable' : ''),
        });
    };

    // ─── AREAS AFFECTED ───────────────────────────────────────
    //
    // Every hazard map is asked the same question: how far does it reach?
    // The only honest answer is the footprint the source itself published.
    // GDACS carries real ones — GloFAS flood extents, JTWC wind-threshold
    // buffers, ShakeMap intensity contours, burnt and drought areas — and
    // EcoLens renders those verbatim. It never draws a radius of its own.
    // Where a source publishes no footprint, nothing is drawn.
    //
    // This layer is LAZY, and deliberately absent from loadAll(). One flood
    // footprint is ~450 KB (the largest measured was 1.2 MB), the payload
    // is uncompressed, and the endpoint has been measured at 0.9-21 s per
    // event. Nothing is requested until the pill is switched on.

    // The &polygontype= filter is a case-sensitive prefix match on the
    // Class name with the Poly_/Point_ prefix stripped. It does the class
    // filtering server-side and, for cyclones, strips the dozens of
    // per-timestep WindRadii forecast footprints before they ever reach the
    // browser (342 KB down to 34 KB).
    const AFFECTED_POLYGONTYPE = {
        FL: 'Affected',                // GloFAS published flood extent
        WF: 'area',                    // wildfire affected area
        DR: 'area',                    // drought affected area
        TC: 'Green,Orange,Red,Cones',  // JTWC wind buffers + uncertainty cone
        EQ: 'SMPInt',                  // ShakeMap modelled intensity contours
    };

    // The classes we are willing to draw. Poly_Global is deliberately
    // absent: its bbox always contains Poly_Affected and on one sampled
    // flood the two were byte-identical, so drawing both double-paints the
    // same ground and makes the flood look larger and more certain than the
    // source says. Poly_Circle is absent too — it is a fixed 100 km ring
    // around the epicentre and would read as a measured damage footprint,
    // which it is not.
    const AFFECTED_CLASS = /^Poly_(?:Affected|area|Green|Orange|Red|Cones|SMPInt_[0-9]+(?:\.[0-9]+)?)$/;
    const WIND_THRESHOLD_LABEL = /^\s*([0-9]+(?:\.[0-9]+)?)\s*km\/h\s*$/i;
    const SMP_INTENSITY_CLASS = /^Poly_SMPInt_([0-9]+(?:\.[0-9]+)?)$/;
    const CYCLONE_BUFFER_CLASS = /^Poly_(?:Green|Orange|Red)$/;

    /**
     * Turn the source's own Class + polygonlabel into a human zone label,
     * a colour band, and a `basis` — what kind of thing the outline
     * actually is. Nothing here invents a threshold: the wind speeds and
     * shaking intensities are read straight off the published label.
     *
     * The basis is not decoration. Almost none of these footprints are
     * observed ground: the cyclone buffers are a forecast track's wind
     * radii, the GloFAS extent is model output, the MMI contours are
     * interpolated. Labelling a Poly_Red "Sustained winds over 120 km/h"
     * with no qualifier told a reader — or anyone looking at a
     * screenshot — that those winds had been measured on coastline a
     * Category 3 storm will not reach for three days. Only the earthquake
     * branch used to say "Modelled"; now every branch says what it is.
     */
    const describeZone = (klass, label, alertlevel) => {
        const alertBand = alertlevel === 'Red' ? 'red'
            : alertlevel === 'Orange' ? 'orange' : 'info';
        if (klass === 'Poly_Cones') {
            return {
                zoneLabel: 'Forecast track uncertainty cone',
                band: 'cone',
                windkmh: null,
                basis: 'Forecast.',
            };
        }
        const wind = CYCLONE_BUFFER_CLASS.test(klass) ? WIND_THRESHOLD_LABEL.exec(label) : null;
        if (wind) {
            const kmh = Number(wind[1]);
            return {
                zoneLabel: 'Forecast sustained winds over ' + wind[1] + ' km/h',
                band: kmh >= 120 ? 'red' : kmh >= 90 ? 'orange' : 'info',
                windkmh: kmh,
                basis: 'Forecast, not observed. This is the modelled wind-radius ' +
                    'buffer along the predicted track — where winds of this speed ' +
                    'are expected to reach, including ground the storm has not ' +
                    'yet crossed.',
            };
        }
        const smp = SMP_INTENSITY_CLASS.exec(klass);
        if (smp) {
            const mmi = Number(smp[1]);
            return {
                zoneLabel: 'Modelled shaking intensity ' + smp[1] + ' (MMI)',
                band: mmi >= 6 ? 'red' : mmi >= 5 ? 'orange' : 'info',
                windkmh: null,
                basis: 'Modelled, not observed. A ShakeMap contour interpolated ' +
                    'from seismic stations and ground-motion prediction — not a ' +
                    'measurement taken at every point inside it.',
            };
        }
        if (klass === 'Poly_Affected') {
            // FL only: AFFECTED_POLYGONTYPE.FL = 'Affected', which is the
            // GloFAS forecast extent, not surveyed inundation.
            return {
                zoneLabel: 'Modelled flood extent',
                band: alertBand,
                windkmh: null,
                basis: 'Modelled, not observed. The GloFAS hydrological model’s ' +
                    'flood extent for this event — not surveyed or satellite-' +
                    'confirmed inundation.',
            };
        }
        if (klass === 'Poly_area') {
            // WF and DR: derived by GDACS from satellite and index products.
            return {
                zoneLabel: 'Affected area, as published',
                band: alertBand,
                windkmh: null,
                basis: 'GDACS derives this outline from satellite and index ' +
                    'products and does not publish whether it is observed or ' +
                    'estimated, so EcoLens claims neither.',
            };
        }
        return { zoneLabel: label || klass, band: alertBand, windkmh: null, basis: '' };
    };

    /**
     * Rough bounding-box extent. Used ONLY to draw nested zones widest
     * first so the tighter contour stays readable on top. It is never
     * written onto a feature and never shown to anyone.
     */
    const geomExtent = (geom) => {
        let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
        const walk = (c) => {
            if (!Array.isArray(c)) return;
            if (typeof c[0] === 'number' && typeof c[1] === 'number') {
                if (c[0] < minx) minx = c[0];
                if (c[0] > maxx) maxx = c[0];
                if (c[1] < miny) miny = c[1];
                if (c[1] > maxy) maxy = c[1];
                return;
            }
            for (const child of c) walk(child);
        };
        walk(geom && geom.coordinates);
        if (!Number.isFinite(minx) || !Number.isFinite(miny)) return 0;
        return Math.max(0, maxx - minx) * Math.max(0, maxy - miny);
    };

    const gdacsGeometryOnce = async (url, timeoutMs) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
            const r = await fetch(url, { signal: controller.signal });
            // Three different error body shapes come out of this endpoint
            // (RFC9110 problem+json, {message}, ASP.NET validation), so the
            // body is parsed defensively and only ever read as GeoJSON.
            const body = await r.json().catch(() => null);
            return { ok: r.ok, status: r.status, body };
        } finally {
            clearTimeout(timer);
        }
    };

    /** Keep only the source-published summary polygons, and tag each one. */
    const buildFootprintFeatures = (ev, rawFeatures, episodeid) => {
        const out = [];
        for (const f of rawFeatures) {
            const p = (f && f.properties) || {};
            // Belt and braces in case &polygontype= is ever withdrawn: every
            // per-timestep forecast footprint (featuretype 'WindRadii') and
            // every PointRadii blob carries a featuretype key, and the
            // source's own summary polygons carry none. The PointRadii blobs
            // are Polygons despite the class name, so a geometry-type test
            // alone would not exclude them.
            if (Object.prototype.hasOwnProperty.call(p, 'featuretype')) continue;
            const klass = String(p.Class || '');
            if (!AFFECTED_CLASS.test(klass)) continue;
            const geom = f.geometry;
            if (!geom || (geom.type !== 'Polygon' && geom.type !== 'MultiPolygon')) continue;
            const label = String(p.polygonlabel == null ? '' : p.polygonlabel).trim();
            // Second, locale-independent guard on the cyclone classes: a
            // summary wind buffer is labelled '60 km/h', a per-timestep
            // forecast footprint '28/08 12:00'.
            if (CYCLONE_BUFFER_CLASS.test(klass) && !WIND_THRESHOLD_LABEL.test(label)) continue;
            const zone = describeZone(klass, label, ev.alertlevel);
            out.push({
                type: 'Feature',
                geometry: geom,
                properties: {
                    hazard: GDACS_TYPES[ev.type] || ev.type,
                    hazardtype: ev.type,
                    country: ev.country || p.country || '',
                    alertlevel: ev.alertlevel || '',
                    eventid: String(ev.id),
                    episodeid: String(episodeid),
                    polygonclass: klass,
                    polygonlabel: label,
                    zoneLabel: zone.zoneLabel,
                    band: zone.band,
                    windkmh: zone.windkmh,
                    // Forecast / modelled / as-published. Printed at the top
                    // of the popup's footer, ahead of the "drawn verbatim"
                    // line, so the qualifier is read before the assurance.
                    basis: zone.basis || '',
                    // The footprint's own timestamp — not the event start
                    // date — plus the agency that actually produced it.
                    polygondate: String(p.polygondate || '').replace('T', ' ').slice(0, 16),
                    geomsource: String(p.source || ''),
                    url: 'https://www.gdacs.org/report.aspx?eventtype=' + ev.type +
                        '&eventid=' + ev.id,
                },
            });
        }
        return out;
    };

    /**
     * Returns { features, reached }.
     *
     * `reached` is the whole point. [] on its own cannot tell "the source
     * published no footprint for this event" from "every attempt at the
     * geometry endpoint failed", and the caller was rendering the second
     * as the factual claim "0 published zones · GDACS" — asserting
     * that GDACS published nothing for five escalated disasters when the
     * endpoint was simply unreachable. It is the flakier of the two GDACS
     * endpoints, so this is the likelier outage, not the rarer one.
     *
     * `reached` goes true only when the endpoint answered with a parseable
     * FeatureCollection. A 200 carrying {message: "..."} is not an answer
     * about geometry, so it leaves the question open rather than closing
     * it with a zero.
     */
    const fetchEventFootprint = async (ev) => {
        const polygontype = AFFECTED_POLYGONTYPE[ev.type];
        // Nothing to ask for: not an outage.
        if (!polygontype) return { features: [], reached: true };
        let ep = Number.isFinite(ev.episodeid) && ev.episodeid >= 1 ? ev.episodeid : 1;
        let reached = false;

        // The newest episode can publish no geometry at all, and the event
        // list gives no warning (measured on 1 of 12 escalated events). Walk
        // the episode id downwards rather than showing nothing, and stamp
        // whatever we find with its own polygondate.
        for (let step = 0; step < 4 && ep >= 1; step++, ep--) {
            const url = GDACS_API + 'polygons/getgeometry?eventtype=' + ev.type +
                '&eventid=' + encodeURIComponent(ev.id) +
                '&episodeid=' + ep +
                '&polygontype=' + polygontype;
            let res = null;
            try {
                res = await gdacsGeometryOnce(url, 25000);
            } catch (err) {
                // Clean transient 0-byte stalls are real on this endpoint
                // and the identical request succeeds moments later. One
                // retry, then move on — never conclude "no geometry" from a
                // single failed attempt.
                try { res = await gdacsGeometryOnce(url, 25000); } catch (err2) { res = null; }
            }
            if (!res || !res.ok) continue;
            const fc = res.body;
            // HTTP 200 does not guarantee a FeatureCollection: several paths
            // answer 200 with a bare {message: "..."} object and no features.
            if (!fc || fc.type !== 'FeatureCollection' || !Array.isArray(fc.features)) continue;
            // The endpoint answered a question about geometry. Whatever it
            // says next — polygons or none — is evidence, not an outage.
            reached = true;
            const built = buildFootprintFeatures(ev, fc.features, ep);
            // Every response carries Point_Centroid whatever the filter, so a
            // wrong or wrongly-cased polygontype returns a structurally valid
            // 200 with no polygon at all. Only real geometry counts.
            if (built.length) return { features: built, reached: true };
        }
        return { features: [], reached };
    };

    /**
     * Lazy fetcher for the "Areas affected" layer. onProgress(done, total)
     * is called after every event settles so the pill can show progress.
     * Returns { data, meta } — meta.ok === false means the dataset could
     * not be reached, and the count must NOT then be rendered as 0. Two
     * separate outages can produce that: the event list, and the geometry
     * endpoint. Both are checked. A shortfall short of total — one list
     * down, or some footprints unreachable — rides on the pill line and
     * in every popup as a stated partial view.
     */
    const fetchAffectedAreas = async (onProgress) => {
        const disc = await discoverEscalatedEvents();
        if (!disc.listsOk) {
            return {
                data: withMeta(emptyFC(), {
                    line: 'unavailable · GDACS event list unreachable',
                }),
                meta: { ok: false, reason: 'GDACS event list unreachable' },
            };
        }
        const events = disc.events.filter((e) => AFFECTED_POLYGONTYPE[e.type]).slice(0, 20);
        if (onProgress) onProgress(0, events.length);

        const collected = [];
        let done = 0;
        let withGeometry = 0;
        let unreachable = 0;
        let cursor = 0;
        const worker = async () => {
            while (cursor < events.length) {
                const ev = events[cursor++];
                try {
                    const built = await fetchEventFootprint(ev);
                    if (built.features.length) {
                        withGeometry++;
                        for (const feat of built.features) {
                            collected.push({ feature: feat, extent: geomExtent(feat.geometry) });
                        }
                    } else if (!built.reached) {
                        unreachable++;
                    }
                } catch (err) {
                    // Fail soft. One unreachable footprint must never take
                    // the overlay — or the map — down with it. It is
                    // still counted: unreachable is not "no footprint".
                    unreachable++;
                    console.warn('[IntelLayers] footprint failed for',
                        ev.type, ev.id, err && err.message);
                }
                done++;
                if (onProgress) onProgress(done, events.length);
            }
        };
        // Four at a time: the endpoint is slow and this is a background
        // overlay, not the main map load.
        await Promise.all(Array.from(
            { length: Math.min(4, events.length) }, () => worker()));

        // Nested zones (the 60/90/120 km/h wind bands, the MMI contours)
        // draw in feature order, so the widest goes down first and the
        // tightest stays readable on top.
        collected.sort((a, b) => b.extent - a.extent);
        const features = collected.map((c) => c.feature);
        const missing = listOutageNames(disc);

        // Every geometry call failed. "0 published zones · GDACS" would
        // assert that GDACS published no footprint for any of these
        // escalated disasters, when in fact the endpoint was never reached.
        // Say unavailable, and let the pill try again.
        if (events.length > 0 && unreachable === events.length) {
            return {
                data: withMeta(emptyFC(), {
                    line: 'unavailable · GDACS geometry endpoint unreachable',
                }),
                meta: {
                    ok: false,
                    reason: 'GDACS geometry endpoint unreachable for all ' +
                        events.length + ' escalated events',
                },
            };
        }

        const notes = [];
        if (missing) notes.push('partial: ' + missing + ' unreachable');
        if (unreachable) {
            notes.push(unreachable + ' of ' + events.length +
                (unreachable === 1 ? ' footprint unreachable' : ' footprints unreachable'));
        }
        if (notes.length) {
            const note = 'Partial view. ' +
                (missing
                    ? 'The GDACS event list for ' + missing + ' could not be reached on ' +
                      'this load, so escalated events of that type are missing entirely. '
                    : '') +
                (unreachable
                    ? 'The geometry endpoint failed for ' + unreachable + ' of ' +
                      events.length + ' events, whose footprints are absent here but may ' +
                      'well have been published. '
                    : '') +
                'Blank ground on this layer is not evidence that nowhere else is affected.';
            for (const c of collected) c.feature.properties.coverageNote = note;
        }

        console.log('[IntelLayers] affected areas:', features.length, 'published zones from',
            withGeometry, 'of', events.length, 'escalated events;', unreachable,
            'unreachable;', missing ? 'lists missing: ' + missing : 'all lists ok');
        return {
            data: withMeta({ type: 'FeatureCollection', features }, {
                line: plural(features.length, 'published zone', 'published zones') +
                    ' · GDACS' + (notes.length ? ' · ' + notes.join(' · ') : ''),
            }),
            meta: {
                ok: true,
                events: events.length,
                withGeometry,
                zones: features.length,
                unreachable,
                listsFailed: disc.listsFailed,
                partial: notes.length > 0,
            },
        };
    };

    /**
     * GDACS active multi-hazard alerts.
     *
     * Read from the server-side mirror, not the GDACS API. The
     * geteventlist endpoint now rejects any call without exactly one
     * eventtype ("Please specify only 1 eventtype") and answers a single
     * type in 20-90 s, so the old direct call had been returning 400 and an
     * empty layer. refresh_environmental_news (Cloud Function, every 15
     * minutes) parses the GDACS RSS and writes this GeoJSON with the exact
     * property names the renderer below already reads.
     */
    const GDACS_MIRROR_URL =
        'https://storage.googleapis.com/ecolens-archive-ecolens-ad854/archive/v1/gdacs/current.geojson';
    const fetchGDACSAlerts = async () => {
        try {
            const data = await cachedFetch(GDACS_MIRROR_URL, TTL.response, { timeoutMs: 15000 });
            const features = (data?.features || [])
                .filter(f => Array.isArray(f?.geometry?.coordinates) && f.geometry.coordinates.length === 2)
                .map(f => {
                    const p = f.properties || {};
                    return {
                        type: 'Feature',
                        geometry: f.geometry,
                        properties: {
                            event_type: (p.event_type || '').toUpperCase(),
                            event_name: p.event_name || p.headline || 'GDACS event',
                            alert_level: p.alert_level || 'Green',
                            country: p.country || '',
                            score: p.score || 0,
                            affected: p.affected || '',
                            from_date: p.from_date || '',
                            to_date: p.to_date || '',
                            url: p.url || '',
                            severity: p.severity || '',
                            is_current: p.is_current === true,
                        },
                    };
                });
            console.log(`[IntelLayers] GDACS: ${features.length} alerts (mirror generated ${data?.generated_at || '?'})`);
            return { type: 'FeatureCollection', features };
        } catch (err) {
            console.warn('[IntelLayers] GDACS mirror fetch failed:', err.message);
            return emptyFC();
        }
    };

    /**
     * NWS (US) active alerts across all event types — extends beyond just
     * floods (which the existing floods layer already covers) to include
     * tornado, severe thunderstorm, winter storm, fire weather, etc.
     */
    const fetchNWSAlerts = async () => {
        const url = 'https://api.weather.gov/alerts/active?status=actual';
        try {
            const data = await cachedFetch(url, TTL.alerts, {
                headers: { 'Accept': 'application/geo+json' },
            });
            const features = (data?.features || [])
                .filter(a => a.geometry)
                .map(a => {
                    const p = a.properties || {};
                    const event = p.event || 'Weather alert';
                    // Skip flood/fire/quake events — already in dedicated layers
                    if (/Flood|Fire Weather|Tsunami|Earthquake/i.test(event)) return null;
                    return {
                        type: 'Feature',
                        geometry: a.geometry,
                        properties: {
                            event,
                            severity: p.severity || 'Unknown',
                            urgency: p.urgency || '',
                            headline: p.headline || '',
                            area: p.areaDesc || '',
                            effective: p.effective || '',
                            expires: p.expires || '',
                            sender: p.senderName || 'NWS',
                        },
                    };
                })
                .filter(Boolean);
            console.log(`[IntelLayers] NWS active alerts: ${features.length} non-flood warnings`);
            return { type: 'FeatureCollection', features };
        } catch (err) {
            console.warn('[IntelLayers] NWS alerts fetch failed:', err.message);
            return emptyFC();
        }
    };

    // ----------------------------------------------------------
    //  CORRELATION — derived from already-loaded sources
    // ----------------------------------------------------------

    /** Bilinear sample wind speed/dir from the wind grid at a given point. */
    const sampleWindAt = (lat, lon) => {
        const fc = sourceState.get('intel-wind-source');
        if (!fc?.features?.length) return null;
        // Nearest-neighbour is fine at 20deg resolution
        let best = null, bestDist = Infinity;
        for (const f of fc.features) {
            const [flon, flat] = f.geometry.coordinates;
            const d = Math.hypot(flat - lat, ((flon - lon + 540) % 360) - 180);
            if (d < bestDist) { bestDist = d; best = f.properties; }
        }
        return best;
    };

    /**
     * Nearest Open-Meteo grid node carrying measurable rain, and how far
     * away it is. Returns { mm, km } or null.
     *
     * This used to average precip_mm_48h over every node within 7 degrees
     * — up to ~780 km — and return 0 when it found none. Both halves
     * were wrong. fetchPrecipitationForecast has already discarded every
     * cell under 0.1 mm, so the mean was taken over wet nodes only and ran
     * high; and the 0 was not a dry forecast, it was the absence of one.
     *
     * So: the nearest node, never a mean; the distance travels with the
     * value so the reader can weigh it; and nothing in range returns null,
     * not zero. The grid is 15° x 25° — a synoptic sample, not a
     * catchment forecast — and past PRECIP_SAMPLE_MAX_KM it says nothing
     * about the point being asked about.
     */
    const PRECIP_SAMPLE_MAX_KM = 500;

    const samplePrecipDetail = (lat, lon) => {
        const fc = sourceState.get('intel-precip-source');
        if (!fc?.features?.length) return null;
        let best = null, bestKm = Infinity;
        for (const f of fc.features) {
            const [flon, flat] = f.geometry.coordinates;
            const dy = (flat - lat) * 110.57;
            const dx = (((((flon - lon) % 360) + 540) % 360) - 180) *
                111.32 * Math.cos(lat * Math.PI / 180);
            const km = Math.hypot(dx, dy);
            if (km < bestKm) { bestKm = km; best = f.properties; }
        }
        if (!best || bestKm > PRECIP_SAMPLE_MAX_KM) return null;
        const mm = Number(best.precip_mm_48h);
        if (!Number.isFinite(mm)) return null;
        return { mm, km: Math.round(bestKm) };
    };

    /**
     * Millimetres at the nearest node carrying measurable rain, or null
     * when no such node is in range. null, never 0: "we hold no forecast
     * for here" is a different claim from "no rain is forecast here".
     */
    const samplePrecipAt = (lat, lon) => {
        const d = samplePrecipDetail(lat, lon);
        return d ? d.mm : null;
    };

    /**
     * Generate fire-spread arrows: for each FIRMS hotspot, point an arrow
     * downwind. Built from the existing fires-source + intel-wind-source.
     */
    const generateFireSpreadArrows = () => {
        if (!map) return emptyFC();
        const fires = map.getSource('fires-source')?._data;
        if (!fires?.features?.length) return emptyFC();
        const features = [];
        // Subsample for performance — top-200 by FRP is plenty
        const top = [...fires.features]
            .filter(f => f.properties?.frp)
            .sort((a, b) => (b.properties.frp || 0) - (a.properties.frp || 0))
            .slice(0, 200);
        top.forEach(f => {
            const [lon, lat] = f.geometry.coordinates;
            const wind = sampleWindAt(lat, lon);
            if (!wind) return;
            features.push({
                type: 'Feature',
                geometry: { type: 'Point', coordinates: [lon, lat] },
                properties: {
                    frp: f.properties.frp,
                    wind_speed: wind.wind_speed,
                    wind_direction: wind.wind_direction,
                    arrow_rotation: (wind.wind_direction + 180) % 360,
                    spread_risk: wind.wind_speed > 30 ? 'high' : wind.wind_speed > 15 ? 'moderate' : 'low',
                },
            });
        });
        return { type: 'FeatureCollection', features };
    };

    /**
     * Annotate flood polygons with the nearest 48 h rainfall forecast node.
     * Properties added: forecast_mm_48h, forecast_node_km, escalation —
     * 'rising' | 'steady' | 'easing' | 'unknown'.
     *
     * 'unknown' is the one that matters. When no forecast node with
     * measurable rain lay in range, the old code scored 0 mm, classed the
     * catchment 'easing' and painted it green — an absence of evidence
     * rendered as the positive claim that a flood is subsiding. Missing
     * evidence is now visibly missing, and the distance to the node the
     * figure came from travels with the figure.
     */
    const generateFloodEscalation = () => {
        if (!map) return emptyFC();
        const floods = map.getSource('floods-source')?._data;
        if (!floods?.features?.length) return emptyFC();
        const features = floods.features.map(f => {
            const lat = f.properties?.point_lat;
            const lon = f.properties?.point_lng;
            const sample = (lat != null && lon != null) ? samplePrecipDetail(lat, lon) : null;
            const escalation = !sample ? 'unknown'
                : sample.mm > 30 ? 'rising'
                : sample.mm > 5 ? 'steady' : 'easing';
            return {
                ...f,
                properties: {
                    ...f.properties,
                    forecast_mm_48h: sample ? Number(sample.mm.toFixed(1)) : null,
                    forecast_node_km: sample ? sample.km : null,
                    escalation,
                },
            };
        });
        return { type: 'FeatureCollection', features };
    };

    // ----------------------------------------------------------
    //  LAYER DEFINITIONS
    // ----------------------------------------------------------

    /**
     * Same shape as HazardLayers.LAYER_DEFS: sourceId, source, layers[].
     * Layers are added with visibility:none — the toggle pills switch them on.
     */
    const LAYER_DEFS = {

        // ─── WEATHER ───────────────────────────────────────
        wind: {
            sourceId: 'intel-wind-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [{
                id: 'intel-wind-arrows',
                type: 'symbol',
                layout: {
                    'visibility': 'none',
                    'text-field': '↑',
                    'text-size': [
                        'interpolate', ['linear'], ['get', 'wind_speed'],
                        0, 14, 20, 22, 50, 32,
                    ],
                    'text-rotate': ['get', 'arrow_rotation'],
                    'text-allow-overlap': true,
                    'text-ignore-placement': true,
                    'text-font': ['Noto Sans Regular'],
                },
                paint: {
                    'text-color': [
                        'interpolate', ['linear'], ['get', 'wind_speed'],
                        0, '#7DD3FC', 15, '#38BDF8', 30, '#0284C7', 50, '#1E40AF',
                    ],
                    'text-halo-color': 'rgba(0,0,0,0.4)',
                    'text-halo-width': 1.5,
                    'text-opacity': 0.85,
                },
            }],
        },

        precipitation: {
            sourceId: 'intel-precip-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-precip-heat',
                    type: 'heatmap',
                    maxzoom: 6,
                    layout: { 'visibility': 'none' },
                    paint: {
                        'heatmap-weight': [
                            'interpolate', ['linear'], ['get', 'precip_mm_48h'],
                            0, 0, 20, 0.4, 50, 0.7, 100, 1,
                        ],
                        'heatmap-intensity': [
                            'interpolate', ['linear'], ['zoom'], 0, 0.6, 5, 1.4,
                        ],
                        'heatmap-color': [
                            'interpolate', ['linear'], ['heatmap-density'],
                            0, 'rgba(0,0,0,0)',
                            0.2, 'rgba(186,228,247,0.5)',
                            0.4, 'rgba(116,178,224,0.7)',
                            0.7, 'rgba(48,131,196,0.85)',
                            1, 'rgba(8,69,148,0.95)',
                        ],
                        'heatmap-radius': [
                            'interpolate', ['linear'], ['zoom'], 0, 12, 5, 50,
                        ],
                        'heatmap-opacity': 0.75,
                    },
                },
                {
                    id: 'intel-precip-points',
                    type: 'circle',
                    minzoom: 5,
                    layout: { 'visibility': 'none' },
                    paint: {
                        'circle-radius': [
                            'interpolate', ['linear'], ['get', 'precip_mm_48h'],
                            0, 4, 20, 8, 50, 14, 100, 22,
                        ],
                        'circle-color': [
                            'interpolate', ['linear'], ['get', 'precip_mm_48h'],
                            0, '#bae4f7', 20, '#74b2e0', 50, '#3083c4', 100, '#084594',
                        ],
                        'circle-opacity': 0.7,
                        'circle-stroke-width': 1,
                        'circle-stroke-color': 'rgba(255,255,255,0.4)',
                    },
                },
            ],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;min-width:200px;">
                    <div style="font-size:11px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">48 h Precipitation Forecast</div>
                    <div style="font-size:22px;font-weight:700;margin-top:4px;">${props.precip_mm_48h} mm</div>
                    <div style="font-size:11px;opacity:0.75;margin-top:4px;text-transform:capitalize;">${props.severity} rainfall</div>
                    <div style="font-size:10px;opacity:0.5;margin-top:6px;">Open-Meteo GFS · grid-sampled</div>
                </div>`,
        },

        sst: {
            sourceId: 'intel-sst-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [{
                id: 'intel-sst-circles',
                type: 'circle',
                layout: { 'visibility': 'none' },
                paint: {
                    'circle-radius': [
                        'interpolate', ['linear'], ['zoom'], 0, 6, 4, 14, 8, 26,
                    ],
                    // Ramped over the measured temperature itself. The old
                    // ramp was keyed to an "anomaly" computed against a
                    // hard-coded constant, so the colour itself asserted an
                    // unusualness no baseline supported.
                    'circle-color': [
                        'interpolate', ['linear'], ['get', 'sst_c'],
                        0, '#0c4a6e',
                        8, '#38bdf8',
                        15, '#cbd5e1',
                        22, '#fde68a',
                        28, '#f97316',
                        32, '#7f1d1d',
                    ],
                    'circle-opacity': 0.55,
                    'circle-blur': 0.4,
                    'circle-stroke-width': 0.8,
                    'circle-stroke-color': 'rgba(0,0,0,0.25)',
                },
            }],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;min-width:220px;max-width:300px;">
                    <div style="font-size:11px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">Sea surface temperature</div>
                    <div style="font-size:22px;font-weight:700;margin-top:4px;">${props.sst_c}°C</div>
                    <div style="font-size:10px;opacity:0.55;margin-top:6px;">Open-Meteo Marine · current reading at this grid node</div>
                    <div style="font-size:10px;opacity:0.55;line-height:1.45;margin-top:6px;">No anomaly is shown. EcoLens holds no climatology baseline, so it cannot say whether this reading is unusual. NOAA OISST v2.1 1991–2020 daily climatology is the dataset that would answer that.</div>
                </div>`,
        },

        // ─── REPORTED HUMAN IMPACT ─────────────────────────
        // Roughly a dozen markers worldwide, not thousands — only events
        // escalated to Orange or Red that carry a sourced impact report.
        // Deliberately quiet: a hollow ink ring, so it reads as annotation
        // over the hazard data rather than competing with it.
        impacts: {
            sourceId: 'intel-impacts-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-impacts-ring',
                    type: 'circle',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'circle-radius': [
                            'interpolate', ['linear'], ['sqrt', ['max', ['get', 'severity_rank'], 1]],
                            1, 7, 40, 13, 400, 20, 2000, 28,
                        ],
                        'circle-color': 'rgba(35,32,25,0.04)',
                        'circle-stroke-color': '#232019',
                        'circle-stroke-width': 1.6,
                        'circle-stroke-opacity': 0.8,
                    },
                },
                {
                    id: 'intel-impacts-core',
                    type: 'circle',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'circle-radius': 3.2,
                        'circle-color': '#232019',
                        'circle-opacity': 0.85,
                    },
                },
                {
                    id: 'intel-impacts-labels',
                    type: 'symbol',
                    minzoom: 2.6,
                    layout: {
                        'visibility': 'none',
                        'text-field': ['get', 'badge'],
                        'text-size': 11,
                        'text-offset': [0, 1.5],
                        'text-anchor': 'top',
                        'text-font': ['Noto Sans Bold'],
                        'text-allow-overlap': false,
                        'text-padding': 8,
                        'text-max-width': 12,
                    },
                    paint: {
                        'text-color': '#232019',
                        'text-halo-color': '#F6F3E9',
                        'text-halo-width': 2.4,
                    },
                },
            ],
            popup: (props) => {
                let summary = [];
                try { summary = JSON.parse(props.summary || '[]'); } catch (e) { summary = []; }
                // Quotes matter: this output is interpolated into an
                // href attribute below, and a feed-supplied value with a
                // double quote would otherwise break out of it.
                const esc = (v) => String(v == null ? '' : v)
                    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
                const rows = summary.map((s) => {
                    const detail = s.reports.slice(0, 4).map((r) =>
                        '<div style="font-size:10.5px;color:#8C8574;line-height:1.4;">' +
                        esc(r.text || (r.value.toLocaleString() + ' — ' + r.region)) + '</div>'
                    ).join('');
                    const more = s.reports.length > 4
                        ? '<div style="font-size:10.5px;color:#8C8574;">+ ' +
                          (s.reports.length - 4) + ' further report(s)</div>'
                        : '';
                    return '<div style="padding:6px 0;border-top:1px solid #D9D2BF;">' +
                        '<div style="display:flex;justify-content:space-between;gap:10px;">' +
                        '<span style="font-size:12px;color:#5B564A;">at least ' +
                        esc(s.label) + '</span>' +
                        '<b style="font-family:ui-monospace,monospace;font-size:12.5px;color:#232019;">' +
                        Math.round(s.floor).toLocaleString() + '</b></div>' +
                        detail + more + '</div>';
                }).join('');
                return '<div style="font-family:system-ui,sans-serif;max-width:330px;color:#232019;">' +
                    '<div style="font-size:9px;letter-spacing:1.3px;text-transform:uppercase;' +
                    'color:#2B5A73;font-weight:800;">Reported impact · ' + esc(props.alertlevel) +
                    ' alert</div>' +
                    '<div style="font-family:Georgia,serif;font-size:16px;font-weight:700;margin:5px 0 2px;">' +
                    esc(props.hazard) + ' · ' + esc(props.country) + '</div>' +
                    '<div style="font-size:10.5px;color:#8C8574;margin-bottom:6px;">Since ' +
                    esc(props.from) + '</div>' + rows +
                    '<div style="font-size:10px;color:#8C8574;line-height:1.45;margin-top:8px;' +
                    'padding-top:7px;border-top:1px solid #D9D2BF;">Each line is the largest ' +
                    'single sourced report, not a total. Reports can nest (a province figure ' +
                    'may already contain a county figure) or supersede one another as a toll ' +
                    'rises, so EcoLens does not add them together.</div>' +
                    (props.coverageNote
                        ? '<div style="font-size:10px;color:#8E1B12;line-height:1.45;' +
                          'margin-top:6px;">' + esc(props.coverageNote) + '</div>'
                        : '') +
                    '<div style="font-size:10px;color:#8C8574;margin-top:5px;">Source: GDACS ' +
                    'Sendai Framework indicator records, EC Joint Research Centre.</div>' +
                    (props.url ? '<a href="' + esc(props.url) + '" target="_blank" ' +
                        'style="display:inline-block;margin-top:7px;font-size:11px;color:#2B5A73;">' +
                        'Full GDACS report →</a>' : '') +
                    '</div>';
            },
        },

        // ─── AREAS AFFECTED ────────────────────────────────
        // The footprint the source published, drawn verbatim. A restrained
        // wash plus a crisper edge, slid in BELOW the hazard circles so it
        // reads as an annotation on the ground rather than a block of
        // colour over the fire and quake dots.
        affected: {
            sourceId: 'intel-affected-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-affected-fill',
                    type: 'fill',
                    // EcoLens-only hint, stripped before addLayer: the first
                    // of these that exists becomes the MapLibre beforeId, so
                    // the wash never buries the hazard points.
                    beforeId: ['fires-heatmap', 'fires-points', 'hotspots-fill',
                        'floods-fill', 'earthquakes-glow', 'earthquakes-circle'],
                    filter: ['!=', ['get', 'band'], 'cone'],
                    layout: { 'visibility': 'none' },
                    paint: {
                        'fill-color': [
                            'match', ['get', 'band'],
                            'red', '#8E1B12',
                            'orange', '#B07D2B',
                            '#2B5A73',
                        ],
                        'fill-opacity': [
                            'match', ['get', 'band'],
                            'red', 0.20,
                            'orange', 0.15,
                            0.11,
                        ],
                    },
                },
                {
                    id: 'intel-affected-outline',
                    type: 'line',
                    beforeId: ['fires-heatmap', 'fires-points', 'hotspots-fill',
                        'floods-fill', 'earthquakes-glow', 'earthquakes-circle'],
                    filter: ['!=', ['get', 'band'], 'cone'],
                    layout: { 'visibility': 'none', 'line-join': 'round' },
                    paint: {
                        'line-color': [
                            'match', ['get', 'band'],
                            'red', '#8E1B12',
                            'orange', '#B07D2B',
                            '#2B5A73',
                        ],
                        'line-width': [
                            'interpolate', ['linear'], ['zoom'], 2, 0.9, 6, 1.6, 10, 2.2,
                        ],
                        'line-opacity': 0.85,
                    },
                },
                {
                    // The uncertainty cone is where the storm centre MAY go,
                    // not ground already affected — dashed, unfilled, so it
                    // can never be misread as an affected area.
                    id: 'intel-affected-cone',
                    type: 'line',
                    beforeId: ['fires-heatmap', 'fires-points', 'hotspots-fill',
                        'floods-fill', 'earthquakes-glow', 'earthquakes-circle'],
                    filter: ['==', ['get', 'band'], 'cone'],
                    layout: { 'visibility': 'none', 'line-join': 'round' },
                    paint: {
                        'line-color': '#5B564A',
                        'line-width': 1.1,
                        'line-dasharray': [2, 2.5],
                        'line-opacity': 0.7,
                    },
                },
            ],
            popup: (props) => {
                const esc = (v) => String(v == null ? '' : v)
                    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
                const cone = props.band === 'cone';
                const agency = props.geomsource
                    ? 'GDACS, geometry produced by ' + esc(props.geomsource)
                    : 'GDACS';
                const row = (k, v) => (v
                    ? '<div style="display:flex;justify-content:space-between;gap:12px;' +
                      'font-size:11.5px;padding:3px 0;">' +
                      '<span style="color:#5B564A;">' + k + '</span>' +
                      '<span style="color:#232019;text-align:right;">' + esc(v) + '</span></div>'
                    : '');
                return '<div style="font-family:system-ui,sans-serif;max-width:330px;color:#232019;">' +
                    '<div style="font-size:9px;letter-spacing:1.3px;text-transform:uppercase;' +
                    'color:#2B5A73;font-weight:800;">Areas affected' +
                    (props.alertlevel ? ' · ' + esc(props.alertlevel) + ' alert' : '') + '</div>' +
                    '<div style="font-family:Georgia,serif;font-size:16px;font-weight:700;margin:5px 0 2px;">' +
                    esc(props.zoneLabel) + '</div>' +
                    '<div style="font-size:11px;color:#5B564A;margin-bottom:6px;">' +
                    esc(props.hazard) + (props.country ? ' · ' + esc(props.country) : '') + '</div>' +
                    '<div style="border-top:1px solid #D9D2BF;padding-top:5px;">' +
                    row('Footprint dated', props.polygondate) +
                    row('Source label', props.polygonlabel) +
                    row('Source class', props.polygonclass) +
                    row('GDACS event', props.eventid +
                        (props.episodeid ? ' · episode ' + props.episodeid : '')) +
                    '</div>' +
                    '<div style="font-size:10px;color:#8C8574;line-height:1.45;margin-top:8px;' +
                    'padding-top:7px;border-top:1px solid #D9D2BF;">' +
                    (props.basis
                        ? '<b style="color:#5B564A;">' + esc(props.basis) + '</b> '
                        : '') +
                    (cone
                        ? 'The published track-uncertainty cone: where the storm centre may ' +
                          'go, not ground already affected.'
                        : 'This outline is the one the source itself published for this ' +
                          'event. EcoLens draws it exactly as received and has not ' +
                          'buffered, smoothed or widened it — it is not a radius EcoLens ' +
                          'invented. Where a source publishes no footprint, nothing is drawn.') +
                    '</div>' +
                    (props.coverageNote
                        ? '<div style="font-size:10px;color:#8E1B12;line-height:1.45;' +
                          'margin-top:6px;">' + esc(props.coverageNote) + '</div>'
                        : '') +
                    '<div style="font-size:10px;color:#8C8574;margin-top:5px;">Source: ' +
                    agency + ' · EC Joint Research Centre.</div>' +
                    (props.url ? '<a href="' + esc(props.url) + '" target="_blank" ' +
                        'style="display:inline-block;margin-top:7px;font-size:11px;color:#2B5A73;">' +
                        'Full GDACS report →</a>' : '') +
                    '</div>';
            },
        },

        // ─── RESPONSE ──────────────────────────────────────
        eonet: {
            sourceId: 'intel-eonet-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-eonet-circles',
                    type: 'circle',
                    layout: { 'visibility': 'none' },
                    paint: {
                        // Survey-blue on paper, not electric cyan — these are
                        // context markers, they must not outshout fire data.
                        'circle-radius': 6,
                        'circle-color': '#2B5A73',
                        'circle-opacity': 0.45,
                        'circle-stroke-color': 'rgba(242,239,228,0.9)',
                        'circle-stroke-width': 1.2,
                    },
                },
                {
                    id: 'intel-eonet-labels',
                    type: 'symbol',
                    minzoom: 3,
                    layout: {
                        'visibility': 'none',
                        'text-field': ['get', 'category'],
                        'text-size': 11,
                        'text-offset': [0, 1.2],
                        'text-anchor': 'top',
                        'text-font': ['Noto Sans Regular'],
                    },
                    paint: {
                        'text-color': '#fff',
                        'text-halo-color': 'rgba(14,165,233,0.7)',
                        'text-halo-width': 1.5,
                    },
                },
            ],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;max-width:300px;">
                    <div style="font-size:10px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">NASA EONET · ${props.category}</div>
                    <div style="font-size:14px;font-weight:700;margin:4px 0;">${props.title}</div>
                    <div style="font-size:11px;opacity:0.7;">${(props.date || '').split('T')[0]}${props.magnitude ? ' · ' + props.magnitude + ' ' + props.magnitude_unit : ''}</div>
                    <div style="font-size:10px;opacity:0.55;margin-top:4px;">Tracking source: ${props.sources}</div>
                    ${props.url ? `<a href="${props.url}" target="_blank" style="display:inline-block;margin-top:8px;font-size:11px;color:#7dd3fc;">Event details →</a>` : ''}
                </div>`,
        },

        gdacs: {
            sourceId: 'intel-gdacs-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [{
                id: 'intel-gdacs-circles',
                type: 'circle',
                layout: { 'visibility': 'none' },
                paint: {
                    'circle-radius': [
                        'match', ['get', 'alert_level'],
                        'Red', 14, 'Orange', 11, 'Green', 8, 8,
                    ],
                    'circle-color': [
                        'match', ['get', 'alert_level'],
                        'Red', '#dc2626', 'Orange', '#f97316', 'Green', '#22c55e', '#94a3b8',
                    ],
                    'circle-opacity': 0.7,
                    'circle-stroke-color': '#fff',
                    'circle-stroke-width': 2,
                },
            }],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;max-width:300px;">
                    <div style="font-size:10px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">GDACS · ${props.event_type}</div>
                    <div style="font-size:14px;font-weight:700;margin:4px 0;">${props.event_name}</div>
                    <div style="font-size:11px;opacity:0.7;">${props.country}</div>
                    <div style="display:inline-block;margin-top:6px;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:700;
                        background:${props.alert_level === 'Red' ? '#dc2626' : props.alert_level === 'Orange' ? '#f97316' : '#22c55e'};">
                        ${props.alert_level} alert
                    </div>
                    <div style="font-size:10px;opacity:0.55;margin-top:6px;">${(props.from_date || '').split('T')[0]} → ${(props.to_date || '').split('T')[0]}</div>
                </div>`,
        },

        nwsalerts: {
            sourceId: 'intel-nws-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-nws-fill',
                    type: 'fill',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'fill-color': [
                            'match', ['get', 'severity'],
                            'Extreme', '#dc2626',
                            'Severe', '#f97316',
                            'Moderate', '#fbbf24',
                            '#a3a3a3',
                        ],
                        'fill-opacity': 0.25,
                    },
                },
                {
                    id: 'intel-nws-outline',
                    type: 'line',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'line-color': [
                            'match', ['get', 'severity'],
                            'Extreme', '#dc2626',
                            'Severe', '#f97316',
                            'Moderate', '#fbbf24',
                            '#a3a3a3',
                        ],
                        'line-width': 1.5,
                        'line-opacity': 0.85,
                    },
                },
            ],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;max-width:320px;">
                    <div style="font-size:10px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">NWS · ${props.severity}</div>
                    <div style="font-size:14px;font-weight:700;margin:4px 0;">${props.event}</div>
                    <div style="font-size:11px;opacity:0.7;">${props.area}</div>
                    <div style="font-size:11px;opacity:0.8;margin-top:6px;">${props.headline}</div>
                    <div style="font-size:10px;opacity:0.55;margin-top:6px;">Effective ${(props.effective || '').split('T')[0]} · ${props.sender}</div>
                </div>`,
        },

        // ─── CORRELATION ───────────────────────────────────
        firewind: {
            sourceId: 'intel-firewind-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [{
                id: 'intel-firewind-arrows',
                type: 'symbol',
                layout: {
                    'visibility': 'none',
                    'text-field': '↑',
                    'text-size': [
                        'interpolate', ['linear'], ['get', 'frp'],
                        0, 16, 100, 22, 300, 30,
                    ],
                    'text-rotate': ['get', 'arrow_rotation'],
                    'text-allow-overlap': true,
                    'text-ignore-placement': true,
                    'text-font': ['Noto Sans Regular'],
                },
                paint: {
                    'text-color': [
                        'match', ['get', 'spread_risk'],
                        'high', '#dc2626', 'moderate', '#f97316', '#fbbf24',
                    ],
                    'text-halo-color': 'rgba(0,0,0,0.55)',
                    'text-halo-width': 2,
                    'text-opacity': 0.95,
                },
            }],
            popup: (props) =>
                `<div style="font-family:Inter,sans-serif;color:#fff;min-width:220px;">
                    <div style="font-size:11px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">Fire-spread cue</div>
                    <div style="font-size:14px;font-weight:700;margin-top:4px;">Wind ${props.wind_speed?.toFixed?.(0) ?? props.wind_speed} km/h</div>
                    <div style="font-size:11px;opacity:0.75;">Direction ${props.wind_direction?.toFixed?.(0) ?? props.wind_direction}°</div>
                    <div style="font-size:11px;opacity:0.75;margin-top:4px;">FRP ${props.frp?.toFixed?.(0) ?? props.frp} MW · spread risk <b>${props.spread_risk}</b></div>
                    <div style="font-size:10px;opacity:0.5;margin-top:6px;">Arrow points downwind. Verify against local fuels + slope before forecasting spread.</div>
                </div>`,
        },

        floodescalation: {
            sourceId: 'intel-floodescalation-source',
            source: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
            layers: [
                {
                    id: 'intel-floodesc-fill',
                    type: 'fill',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'fill-color': [
                            'match', ['get', 'escalation'],
                            'rising', '#dc2626', 'steady', '#f97316',
                            'easing', '#22c55e',
                            // No forecast node in range. Ink-faint, never
                            // the green that read as "this flood is easing".
                            '#8C8574',
                        ],
                        'fill-opacity': 0.35,
                    },
                },
                {
                    id: 'intel-floodesc-outline',
                    type: 'line',
                    layout: { 'visibility': 'none' },
                    paint: {
                        'line-color': [
                            'match', ['get', 'escalation'],
                            'rising', '#dc2626', 'steady', '#f97316',
                            'easing', '#22c55e',
                            // No forecast node in range. Ink-faint, never
                            // the green that read as "this flood is easing".
                            '#8C8574',
                        ],
                        'line-width': 2,
                        'line-opacity': 0.9,
                    },
                },
            ],
            popup: (props) => {
                const known = props.escalation !== 'unknown' && props.forecast_mm_48h != null;
                const colour = props.escalation === 'rising' ? '#dc2626'
                    : props.escalation === 'steady' ? '#f97316'
                    : props.escalation === 'easing' ? '#22c55e' : '#8C8574';
                const body = known
                    ? `<div style="font-size:11px;opacity:0.8;">Nearest rainfall forecast node: <b>${props.forecast_mm_48h} mm</b> over 48 h</div>
                       <div style="font-size:10px;opacity:0.55;line-height:1.45;margin-top:4px;">Open-Meteo GFS · nearest grid node carrying measurable rain, ${props.forecast_node_km} km away on a 15°×25° global grid. A regional signal, not a catchment forecast for this river.</div>`
                    : `<div style="font-size:11px;opacity:0.8;">No rainfall forecast node within ${PRECIP_SAMPLE_MAX_KM} km.</div>
                       <div style="font-size:10px;opacity:0.55;line-height:1.45;margin-top:4px;">EcoLens cannot say whether this flood is rising or easing. That is missing evidence, not a sign the water is falling. GloFAS river discharge forecasts, or the national hydrological service for this basin, would answer it.</div>`;
                return `<div style="font-family:Inter,sans-serif;color:#fff;max-width:300px;">
                    <div style="font-size:10px;text-transform:uppercase;opacity:0.55;letter-spacing:0.5px;">Flood × rainfall forecast</div>
                    <div style="font-size:14px;font-weight:700;margin:4px 0;">${props.name || 'Flood zone'}</div>
                    ${body}
                    <div style="display:inline-block;margin-top:8px;padding:2px 8px;border-radius:4px;font-size:10px;font-weight:700;background:${colour};">
                        ${known ? String(props.escalation).toUpperCase() : 'NO FORECAST IN RANGE'}
                    </div>
                    ${known ? '<div style="font-size:10px;opacity:0.5;line-height:1.45;margin-top:6px;">That badge is an EcoLens classification of the node above. No forecaster issued it.</div>' : ''}
                </div>`;
            },
        },
    };

    // ----------------------------------------------------------
    //  WIRING
    // ----------------------------------------------------------

    /** Resolve an EcoLens beforeId hint to the first layer that exists. */
    const resolveBeforeId = (beforeId) => {
        if (!beforeId) return undefined;
        const list = Array.isArray(beforeId) ? beforeId : [beforeId];
        return list.find((id) => map.getLayer(id)) || undefined;
    };

    const init = (mapInstance) => {
        map = mapInstance;
        Object.entries(LAYER_DEFS).forEach(([key, def]) => {
            if (!map.getSource(def.sourceId)) {
                map.addSource(def.sourceId, def.source);
            }
            def.layers.forEach(layerDef => {
                if (map.getLayer(layerDef.id)) return;
                // beforeId is an EcoLens-only hint (a candidate list), not a
                // MapLibre layer property — it must not reach addLayer.
                const { beforeId, ...spec } = layerDef;
                map.addLayer({ ...spec, source: def.sourceId }, resolveBeforeId(beforeId));
            });
            // Wire popup handlers for any layer with a popup spec. Delegated
            // listeners outlive setStyle(), so each layer id is bound once
            // and never rebound when a basemap switch re-adds the layers.
            if (def.popup) {
                def.layers.forEach(layerDef => {
                    if (layerDef.type === 'heatmap' || layerDef.type === 'symbol') return;
                    if (boundPopupLayers.has(layerDef.id)) return;
                    boundPopupLayers.add(layerDef.id);
                    map.on('click', layerDef.id, (e) => {
                        if (!e.features?.[0]) return;
                        const feature = e.features[0];
                        // ONE popup instance for every intelligence layer.
                        // Overlapping layers inside a group all satisfy the
                        // hit test — the impacts ring and its core dot are
                        // exactly co-located, and MapLibre hit-tests geometry
                        // regardless of alpha — so separate Popup instances
                        // stacked two identical popups on every click.
                        if (!sharedPopup) {
                            sharedPopup = new maplibregl.Popup({
                                closeButton: true, offset: 12, maxWidth: '340px',
                            });
                        }
                        sharedPopup
                            .setLngLat(e.lngLat)
                            .setHTML(def.popup(feature.properties))
                            .addTo(map);
                    });
                    map.on('mouseenter', layerDef.id, () => { map.getCanvas().style.cursor = 'pointer'; });
                    map.on('mouseleave', layerDef.id, () => { map.getCanvas().style.cursor = ''; });
                });
            }
        });
        console.log('[IntelLayers] Initialized', Object.keys(LAYER_DEFS).length, 'layer groups');
    };

    /**
     * Rebuild every intelligence layer after a basemap switch and replay the
     * data already fetched. setStyle() wipes all sources and layers; without
     * this the overlays vanish for the rest of the session while their pills
     * stay switched on and their counts keep showing stale numbers — a pill
     * claiming N events while zero markers exist.
     */
    const rehydrate = (mapInstance) => {
        if (mapInstance) map = mapInstance;
        if (!map) return;
        init(map);
        sourceState.forEach((data, sourceId) => {
            const src = map.getSource(sourceId);
            if (src && data) {
                try { src.setData(data); } catch (err) { /* fail soft */ }
            }
        });
        Object.keys(LAYER_DEFS).forEach((key) => {
            const cb = document.getElementById('toggle-' + key);
            if (cb) setLayerVisibility(key, cb.checked);
        });
    };

    /**
     * Write a pill's whole subtitle line.
     *
     * A status word has to replace the noun phrase, never prefix it:
     * dropping "unavailable" into the count span of "<n> published zones
     * · GDACS" reads back as "unavailable published zones · GDACS",
     * which is a count. The count span is rebuilt inside the line so later
     * updates still find it.
     */
    const setPillLine = (key, text) => {
        const line = document.getElementById('subtitle-' + key);
        if (!line) {
            const c = document.getElementById('count-' + key);
            if (c) c.textContent = text;
            return;
        }
        line.textContent = '';
        const span = document.createElement('span');
        span.id = 'count-' + key;
        span.textContent = text;
        line.appendChild(span);
    };

    const updateSource = (key, data) => {
        const def = LAYER_DEFS[key];
        if (!def || !map) return;
        // _meta is an EcoLens-only foreign member saying how complete this
        // fetch was. It is stripped here and never reaches MapLibre.
        const meta = data && data._meta;
        const clean = meta ? { type: data.type, features: data.features || [] } : data;
        const src = map.getSource(def.sourceId);
        if (src) src.setData(clean);
        sourceState.set(def.sourceId, clean);
        // Update count badges
        const countEl = document.getElementById(`count-${key}`);
        if (countEl) countEl.textContent = clean?.features?.length ?? 0;
        // A fetcher that knows its answer is partial, or unavailable, gets
        // the last word over the bare number.
        if (meta && meta.line) setPillLine(key, meta.line);
        // Honour a pill that is already switched on. Toggles bind before the
        // layers exist, so a default-on layer would otherwise stay hidden
        // until someone clicked it off and on again.
        const cb = document.getElementById(`toggle-${key}`);
        if (cb && cb.checked) setLayerVisibility(key, true);
    };

    const setLayerVisibility = (key, visible) => {
        const def = LAYER_DEFS[key];
        if (!def || !map) return;
        def.layers.forEach(layerDef => {
            if (map.getLayer(layerDef.id)) {
                map.setLayoutProperty(layerDef.id, 'visibility', visible ? 'visible' : 'none');
            }
        });
    };

    const setLayerOpacity = (key, opacity) => {
        const def = LAYER_DEFS[key];
        if (!def || !map) return;
        def.layers.forEach(layerDef => {
            if (!map.getLayer(layerDef.id)) return;
            const type = layerDef.type;
            const prop = type === 'fill' ? 'fill-opacity' :
                         type === 'line' ? 'line-opacity' :
                         type === 'circle' ? 'circle-opacity' :
                         type === 'heatmap' ? 'heatmap-opacity' :
                         type === 'symbol' ? 'text-opacity' : null;
            if (prop) map.setPaintProperty(layerDef.id, prop, opacity);
        });
    };

    // ----------------------------------------------------------
    //  LAZY LAYERS
    // ----------------------------------------------------------
    //
    // Some sources are far too heavy to pull on page load. "Areas affected"
    // is one: a single flood footprint can be 450 KB, the payload is
    // uncompressed, and the GDACS geometry endpoint has been measured at up
    // to 21 s for one event. These fetch on the FIRST switch-on only, report
    // progress into the pill's own count span, and are cached for the rest
    // of the session — a second switch-on never re-fetches. They are
    // deliberately absent from the loadAll() task list.

    const LAZY_FETCHERS = { affected: fetchAffectedAreas };

    const setLazyStatus = (key, text) => setPillLine(key, text);

    const ensureLoaded = (key) => {
        if (!LAZY_FETCHERS[key]) return Promise.resolve(null);
        if (lazyLoaded.has(key)) return Promise.resolve(null);      // session cache
        if (lazyInFlight.has(key)) return lazyInFlight.get(key);    // already running

        setLazyStatus(key, 'loading…');
        const run = (async () => {
            try {
                const result = await LAZY_FETCHERS[key]((done, total) => {
                    setLazyStatus(key, total ? done + ' / ' + total + ' events' : 'loading…');
                });
                lazyLoaded.add(key);
                updateSource(key, result.data);   // this also refreshes the count
                if (result.meta && result.meta.ok === false) {
                    // A failed fetch must never be rendered as the factual
                    // claim "0". Say the dataset is unavailable, and allow a
                    // later switch-on to try again — discoverEscalatedEvents
                    // no longer caches a total outage, so that retry really
                    // does go back to the network.
                    lazyLoaded.delete(key);
                    setLazyStatus(key, 'unavailable · ' +
                        (result.meta.reason || 'source unreachable'));
                    console.warn('[IntelLayers]', key, 'unavailable:', result.meta.reason);
                }
            } catch (err) {
                setLazyStatus(key, 'unavailable');
                console.warn('[IntelLayers] lazy load failed for', key, err && err.message);
            } finally {
                lazyInFlight.delete(key);
            }
            return null;
        })();
        lazyInFlight.set(key, run);
        return run;
    };

    /**
     * Load all intelligence data. Called from map-core after the base
     * hazard layers are ready. Each fetcher is independently resilient.
     */
    const loadAll = async () => {
        console.log('[IntelLayers] Loading intelligence data…');
        const tasks = [
            ['wind', fetchGlobalWind],
            ['precipitation', fetchPrecipitationForecast],
            ['sst', fetchSeaSurfaceTemperature],
            ['eonet', fetchEONETEvents],
            ['gdacs', fetchGDACSAlerts],
            ['impacts', fetchDisasterImpacts],
            ['nwsalerts', fetchNWSAlerts],
        ];
        await Promise.allSettled(tasks.map(async ([key, fn]) => {
            try {
                const data = await fn();
                updateSource(key, data);
            } catch (err) {
                console.warn(`[IntelLayers] ${key} load failed:`, err.message);
            }
        }));
        // Correlations depend on wind + precip + the hazard layers being loaded.
        refreshCorrelations();
        // Refresh weather every 30 min
        setInterval(async () => {
            const w = await fetchGlobalWind();
            updateSource('wind', w);
            refreshCorrelations();
        }, 30 * 60 * 1000);
        setInterval(async () => {
            const p = await fetchPrecipitationForecast();
            updateSource('precipitation', p);
            refreshCorrelations();
        }, 30 * 60 * 1000);
        console.log('[IntelLayers] Intelligence data ready');
    };

    /** Rebuild fire-wind arrows and flood-escalation polygons. */
    const refreshCorrelations = () => {
        try { updateSource('firewind', generateFireSpreadArrows()); } catch (e) {}
        try { updateSource('floodescalation', generateFloodEscalation()); } catch (e) {}
    };

    return {
        init,
        rehydrate,
        loadAll,
        ensureLoaded,
        updateSource,
        setLayerVisibility,
        setLayerOpacity,
        refreshCorrelations,
        sampleWindAt,
        samplePrecipAt,
        LAYER_DEFS,
    };
})();

window.IntelligenceLayers = IntelligenceLayers;
