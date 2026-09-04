// ============================================================
// EcoLens AskTheMap — natural-language questions on the map screen
//
// "In my area, show me the regions with wildfires, where smoke is
//  thickest, evacuation routes that can be used, and current measures
//  being implemented."
//
// Tiered answering:
//   Tier 1 (always, instant, client-side): a rule-based parser detects
//     hazard topics + area scope, switches the right layers on, flies
//     to the area, and composes an editorial answer card from the data
//     already in the map's sources — with per-claim provenance and
//     honest "no data" statements.
//   Tier 2 (when the local Atlas engine is up): one tap forwards an
//     enriched, viewport-scoped prompt to AtlasBridge for the
//     evidence-gated deep analysis.
//
// Honesty notes baked into answers:
//   - "Smoke" is answered with PM2.5 (Open-Meteo) as a proxy — thick
//     smoke shows up as high PM2.5, but the grid is coarse.
//   - Evacuation info is extracted from *official alerts* (NWS/GDACS
//     text). Neither EcoLens nor Atlas computes road routing; we never
//     invent routes. [GEMINI SEAM] If richer narrative synthesis is
//     wanted later, composeAnswer() is the single place a Gemini call
//     would slot in — the structured `findings` object is its input.
// ============================================================

const AskTheMap = (function () {
    'use strict';

    const DEFAULT_RADIUS_KM = 150;

    const esc = (v) => String(v == null ? '' : v)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    function haversineKm(lat1, lon1, lat2, lon2) {
        const rad = Math.PI / 180;
        const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
        const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function bearingLabel(lat1, lon1, lat2, lon2) {
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const y = Math.sin(dLon) * Math.cos(lat2 * Math.PI / 180);
        const x = Math.cos(lat1 * Math.PI / 180) * Math.sin(lat2 * Math.PI / 180) -
            Math.sin(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.cos(dLon);
        const deg = (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
        return ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][Math.round(deg / 45) % 8];
    }

    // ---------- Intent parsing (rule-based, hazard vocabulary) ----------

    const TOPIC_PATTERNS = {
        fires: /\b(wild)?fires?\b|\bburn(ing|s)?\b|\bblaze/i,
        smoke: /\bsmoke\b|\bair quality\b|\bhaze\b|\bpm2\.?5\b|\bbreath/i,
        evacuation: /\bevacuat|\bescape route|\bget out\b|\bsafe(ty)? route|\bshelter/i,
        measures: /\bmeasures?\b|\bresponse\b|\bofficial|\balerts?\b|\bwarnings?\b|\borders?\b|being (done|implemented)/i,
        earthquakes: /\bearthquakes?\b|\bquakes?\b|\bseismic|\btremor/i,
        floods: /\bfloods?(ing)?\b|\binundat/i,
        drought: /\bdroughts?\b|\bdry (conditions|spell)/i,
        cyclone: /\bcyclones?\b|\btyphoons?\b|\bhurricanes?\b|\btropical storms?\b/i,
        volcano: /\bvolcano(es)?\b|\beruptions?\b|\bvolcanic\b/i,
        tsunami: /\btsunamis?\b/i,
        // "What is going on" questions are answered from the GDACS wire.
        wire: /\blatest\b|\bmost recent\b|\brecent\b|\bhappening\b|\bgoing on\b|\bon the wire\b|\bright now\b|\btoday\b|\bthis week\b/i,
    };

    // Hazards whose bare question (no place, no "near me") is answered
    // from the whole wire rather than the current view.
    const WORLD_BY_DEFAULT = ['floods', 'drought', 'cyclone', 'volcano', 'tsunami', 'earthquakes'];

    const DEEP_PATTERNS = /\bwhy\b|\bcorrelat|\bcompare|\bcluster|\bstatistic|\btrend\b|\bdriv(ing|er)|\bexposure\b|\brisk analysis\b/i;
    const NEAR_ME_PATTERNS = /\bmy area\b|\bnear me\b|\baround me\b|\bmy region\b|\bhere\b|\bnearby\b/i;

    // A wire question with one of these and no place is answered for the
    // whole feed, not for whatever the camera happens to be pointing at.
    const GLOBAL_CUES = /\bworld(wide)?\b|\bglobal(ly)?\b|\bglobe\b|\bplanet\b|\banywhere\b|\beverywhere\b|\bon the wire\b|\bmost recent\b|\blatest\b|\brecent(ly)?\b/i;
    // "in the world" / "across the globe" name the planet, not a place.
    const GLOBAL_WORDS = /^(the\s+)?(world|globe|planet|earth|anywhere|everywhere)$/i;

    /**
     * Pull the place phrase out of the question: the LAST
     * "in/near/around/at/for/across <place>" clause wins.
     * "wildfires and evacuations in BC" → "BC". No alias tables —
     * disambiguation is the geocoder ranking's job (see rankGeocode).
     */
    /**
     * Words that cannot be part of a place name, and therefore end one.
     *
     * The old extractor assumed the place ended the sentence, so "what areas
     * in BC are experiencing the worst fires" geocoded "BC are experiencing
     * the worst fires", found nothing, silently dropped the study area, and
     * took the whole investigation down with it. A place phrase actually runs
     * from the preposition to the first word that cannot belong to a name.
     */
    const STOP_WORDS = new Set([
        'are', 'is', 'was', 'were', 'be', 'been', 'being', 'am',
        'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'can',
        'could', 'should', 'may', 'might', 'must', 'shall',
        'experiencing', 'experience', 'experienced', 'showing', 'show', 'shows',
        'burning', 'burn', 'happening', 'happen', 'going', 'seeing', 'see',
        'get', 'getting', 'spreading', 'spread',
        'right', 'now', 'today', 'tonight', 'currently', 'recently', 'lately',
        'presently',
        'that', 'which', 'what', 'where', 'when', 'who', 'why', 'how', 'whose',
        'and', 'but', 'or', 'so', 'because', 'if', 'then', 'than', 'though',
        'although',
        'during', 'over', 'under', 'with', 'without', 'since', 'until', 'while',
        'after', 'before',
        'this', 'these', 'those', 'there', 'their', 'they', 'it', 'its',
        'worst', 'best', 'most', 'least', 'biggest', 'largest', 'smallest',
        'highest', 'lowest',
        'active', 'recent', 'latest', 'current', 'ongoing', 'live',
        'fire', 'fires', 'wildfire', 'wildfires', 'flood', 'floods', 'quake',
        'quakes', 'earthquake', 'earthquakes', 'drought', 'smoke', 'hazard',
        'hazards', 'risk', 'risks',
        'season', 'year', 'week', 'month', 'day', 'days', 'weeks', 'months',
        'years',
        'please', 'thanks', 'thank', 'me', 'us', 'you', 'them',
    ]);

    // Lowercase words that legitimately sit inside a place name — but only
    // when a capitalised word follows: "Isle of Man", "Rio de Janeiro".
    const CONNECTORS = new Set(['of', 'de', 'del', 'da', 'du', 'la', 'le',
        'los', 'las', 'upon', 'on', 'the', 'and', 'di', 'van', 'von']);
    const ARTICLES = new Set(['the', 'a', 'an']);

    const looksCapitalised = (w) => /^[A-ZÀ-Þ]/.test(w) || /^[A-Z]{2,}$/.test(w);

    function walkPlace(words) {
        const out = [];
        for (let i = 0; i < words.length && out.length < 6; i++) {
            const bare = words[i].replace(/[^A-Za-zÀ-ÿ'.-]/g, '');
            if (!bare) break;
            const lower = bare.toLowerCase();
            if (out.length === 0 && ARTICLES.has(lower)) continue; // "in the Okanagan"
            if (CONNECTORS.has(lower)) {
                const nextRaw = words[i + 1];
                const next = nextRaw && nextRaw.replace(/[^A-Za-zÀ-ÿ'.-]/g, '');
                if (out.length && next && looksCapitalised(next) &&
                    !STOP_WORDS.has(next.toLowerCase())) {
                    out.push(words[i]);
                    continue;
                }
                break;
            }
            if (STOP_WORDS.has(lower)) break;
            out.push(words[i]);
        }
        return out.join(' ').replace(/[\s,.\-]+$/, '').trim();
    }

    /**
     * Province and territory abbreviations, expanded before geocoding.
     * Nominatim does not reliably resolve a bare "BC" to the province — it
     * returned a point in the Fraser Valley, which then got scanned as a
     * 150 km circle around Vancouver for a question about the whole province.
     */
    const ADMIN_ABBREV = {
        bc: 'British Columbia, Canada', ab: 'Alberta, Canada',
        sk: 'Saskatchewan, Canada', mb: 'Manitoba, Canada',
        on: 'Ontario, Canada', qc: 'Quebec, Canada',
        ns: 'Nova Scotia, Canada', nb: 'New Brunswick, Canada',
        nl: 'Newfoundland and Labrador, Canada',
        pe: 'Prince Edward Island, Canada', pei: 'Prince Edward Island, Canada',
        yt: 'Yukon, Canada', nt: 'Northwest Territories, Canada',
        nwt: 'Northwest Territories, Canada', nu: 'Nunavut, Canada',
    };

    function expandAbbrev(place) {
        const key = place.toLowerCase().replace(/[.\s]/g, '');
        return ADMIN_ABBREV[key] || place;
    }

    function extractPlace(text) {
        const cleaned = text.replace(/[?.!]+\s*$/, '');
        if (NEAR_ME_PATTERNS.test(cleaned)) return null; // "near me" is not a place
        const re = /\b(?:in|near|around|across|throughout|within|for|at|of)\s+(.{2,80})/gi;
        let best = null, m;
        while ((m = re.exec(cleaned)) !== null) {
            const place = walkPlace(m[1].trim().split(/\s+/));
            if (place.length >= 2 && !STOP_WORDS.has(place.toLowerCase())) best = place;
        }
        if (!best || NEAR_ME_PATTERNS.test(best)) return null;
        if (GLOBAL_WORDS.test(best)) return null; // the planet is not a place
        return { raw: best, query: expandAbbrev(best) };
    }

    /**
     * Pick the best geocode candidate without any hardcoded knowledge:
     * - administrative regions beat POIs (someone asking a hazard
     *   question about "BC" means the province, not a bar named BC)
     * - Nominatim's own importance score carries most of the weight
     * - mild bias toward candidates nearer the current view, so
     *   ambiguous names resolve to the user's part of the world
     */
    function rankGeocode(results, viewCenter) {
        if (!results || !results.length) return null;
        let best = null, bestScore = -Infinity;
        for (const r of results) {
            let score = (r.importance || 0) * 10;
            if (r.cls === 'boundary' || r.type === 'administrative' ||
                r.type === 'state' || r.type === 'province') score += 5;
            if (viewCenter) {
                const km = haversineKm(viewCenter.lat, viewCenter.lon, r.lat, r.lng);
                score += Math.max(0, 3 - km / 3000); // ≤3 pts, fading over ~9000 km
            }
            if (score > bestScore) { bestScore = score; best = r; }
        }
        return best;
    }

    function parseIntent(text) {
        const topics = Object.keys(TOPIC_PATTERNS)
            .filter(k => TOPIC_PATTERNS[k].test(text));
        // A bare "what's happening" style question gets the full sweep:
        // fires, official measures, and the whole GDACS wire for the view.
        const sweep = topics.length === 0;
        if (sweep) topics.push('fires', 'measures', 'wire');
        const place = extractPlace(text);
        const nearMe = NEAR_ME_PATTERNS.test(text);
        return {
            topics,
            sweep,
            deep: DEEP_PATTERNS.test(text),
            nearMe,
            place,
            // Only the wire can be answered for the whole planet. A named
            // place (even one that fails to geocode) or "near me" pins the
            // question to somewhere.
            worldwide: !place && !nearMe &&
                (GLOBAL_CUES.test(text) || topics.some(k => WORLD_BY_DEFAULT.includes(k))),
            raw: text,
        };
    }

    // ---------- Area resolution ----------

    function viewportCenter() {
        const map = window.ecoMap;
        if (!map) return null;
        const c = map.getCenter();
        return { lat: c.lat, lon: c.lng, label: 'the current map view', radiusKm: DEFAULT_RADIUS_KM };
    }

    function havKm(lat1, lon1, lat2, lon2) { return haversineKm(lat1, lon1, lat2, lon2); }

    /**
     * The place named in the question ALWAYS wins. Priority:
     * 1. geocoded place ("…in BC" → British Columbia, scan sized to its
     *    bounding box, capped at 700 km)
     * 2. "near me" → browser geolocation
     * 3. current viewport — and the answer says so explicitly.
     * A place that fails to geocode falls back to the viewport WITH a
     * visible warning; it must never silently answer the wrong place.
     */
    async function resolveArea(intent) {
        if (intent.place && window.MapCore && window.MapCore.geocode) {
            try {
                const results = await window.MapCore.geocode(intent.place.query);
                const hit = rankGeocode(results, viewportCenter());
                if (hit) {
                    let radiusKm = DEFAULT_RADIUS_KM;
                    if (hit.bbox) {
                        const [w, s, e, n] = hit.bbox;
                        radiusKm = Math.min(700, Math.max(DEFAULT_RADIUS_KM,
                            Math.round(havKm(s, w, n, e) / 2)));
                    }
                    const area = {
                        lat: hit.lat, lon: hit.lng,
                        label: (hit.name || intent.place.raw).split(',')[0],
                        // The full name is what Atlas matches jurisdictions
                        // against ("British Columbia, Canada"); the short
                        // label is only for display.
                        fullName: hit.name || intent.place.raw,
                        bbox: hit.bbox, radiusKm,
                    };
                    // Administrative areas get scanned by their real shape.
                    const isAdmin = hit.cls === 'boundary' ||
                        hit.type === 'administrative' || hit.type === 'state' ||
                        hit.type === 'province' || hit.type === 'city' ||
                        hit.type === 'town' || hit.type === 'county' ||
                        hit.type === 'region';
                    if (isAdmin) {
                        const poly = await fetchAreaPolygon(intent.place.query);
                        if (poly) {
                            area.rings = poly.rings;
                            area.boundaryName = poly.name;
                        }
                    }
                    return area;
                }
                const fallback = viewportCenter();
                if (fallback) fallback.warning = 'No match for “' + intent.place.raw +
                    '” in the place index, so these figures cover the area you are ' +
                    'currently looking at. Naming a town, region or province gets a ' +
                    'tighter answer.';
                return fallback;
            } catch (e) {
                const fallback = viewportCenter();
                if (fallback) fallback.warning = 'Place lookup failed (' + (e.message || 'network') + ') — answering for the current map view.';
                return fallback;
            }
        }
        return new Promise((resolve) => {
            if (intent.nearMe && navigator.geolocation) {
                const fallback = setTimeout(() => resolve(viewportCenter()), 6000);
                navigator.geolocation.getCurrentPosition(
                    (pos) => {
                        clearTimeout(fallback);
                        resolve({
                            lat: pos.coords.latitude,
                            lon: pos.coords.longitude,
                            label: 'your location',
                            radiusKm: DEFAULT_RADIUS_KM,
                        });
                    },
                    () => { clearTimeout(fallback); resolve(viewportCenter()); },
                    { timeout: 5000, maximumAge: 300000 }
                );
            } else {
                resolve(viewportCenter());
            }
        });
    }

    // ---------- Data gathering (from sources already on the map) ----------

    function sourceFeatures(sourceId) {
        const map = window.ecoMap;
        const src = map && map.getSource(sourceId);
        const data = src && src._data;
        return (data && data.features) || [];
    }

    /**
     * How the scan describes itself. Saying "within 150 km" when the scan
     * actually covered a whole province is a lie about the method, and it is
     * the sentence a reader uses to judge whether the answer covers what
     * they asked about.
     */
    function scopePhrase(area, radiusKm) {
        return (area && area.rings)
            ? 'across ' + (area.label || 'the study area')
            : 'within ' + radiusKm + ' km';
    }

    function scanLabel(area, radiusKm) {
        return (area && area.rings)
            ? 'full boundary scan'
            : radiusKm + ' km scan';
    }

    function atlasScope(area, radiusKm) {
        return (area && area.rings)
            ? 'the administrative area of ' + (area.fullName || area.label) + ', centred on'
            : 'within ' + radiusKm + ' km of';
    }

    // ---------- Boundary containment ----------
    //
    // A province is not a circle. Scanning "British Columbia" as a radius
    // around a centroid both misses the north and reaches into Washington
    // and Alberta. When the resolved place is an administrative area we
    // fetch its actual polygon and test containment against it — for EVERY
    // hazard, since `within` is the single choke point all sections use.

    function buildRings(geom) {
        const polys = geom.type === 'MultiPolygon' ? geom.coordinates : [geom.coordinates];
        return polys.map(p => {
            const outer = p[0];
            let x0 = 180, y0 = 90, x1 = -180, y1 = -90;
            for (const c of outer) {
                if (c[0] < x0) x0 = c[0];
                if (c[0] > x1) x1 = c[0];
                if (c[1] < y0) y0 = c[1];
                if (c[1] > y1) y1 = c[1];
            }
            return { x0, y0, x1, y1, poly: p };
        });
    }

    function ringContains(x, y, ring) {
        let inside = false;
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
            const xi = ring[i][0], yi = ring[i][1];
            const xj = ring[j][0], yj = ring[j][1];
            if ((yi > y) !== (yj > y) &&
                x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
        }
        return inside;
    }

    function insideRings(x, y, rings) {
        for (const r of rings) {
            if (x < r.x0 || x > r.x1 || y < r.y0 || y > r.y1) continue;
            if (ringContains(x, y, r.poly[0]) &&
                !r.poly.slice(1).some(h => ringContains(x, y, h))) return true;
        }
        return false;
    }

    /**
     * Fetch the administrative polygon for a resolved place. Returns null for
     * anything that isn't a boundary (a POI, a street) so those keep the
     * radius behaviour, which is the right shape for a point of interest.
     */
    async function fetchAreaPolygon(query) {
        try {
            const resp = await fetch(
                'https://nominatim.openstreetmap.org/search?format=json&limit=1' +
                '&polygon_geojson=1&q=' + encodeURIComponent(query),
                { headers: { 'Accept': 'application/json' } });
            const results = await resp.json();
            const hit = results && results[0];
            const geom = hit && hit.geojson;
            if (!geom || (geom.type !== 'Polygon' && geom.type !== 'MultiPolygon')) return null;
            return { geom, rings: buildRings(geom), name: hit.display_name };
        } catch (e) {
            console.warn('[AskTheMap] boundary fetch failed:', e.message);
            return null;
        }
    }

    function within(features, area, radiusKm) {
        const out = [];
        const rings = area && area.rings;
        for (const f of features) {
            const g = f.geometry;
            if (!g) continue;
            let lon, lat;
            if (g.type === 'Point') { [lon, lat] = g.coordinates; }
            else if (f.properties && f.properties.point_lat != null) {
                lon = f.properties.point_lng; lat = f.properties.point_lat;
            } else { continue; }
            if (rings) {
                if (!insideRings(lon, lat, rings)) continue;
                out.push({ f, km: haversineKm(area.lat, area.lon, lat, lon), lat, lon });
            } else {
                const km = haversineKm(area.lat, area.lon, lat, lon);
                if (km <= radiusKm) out.push({ f, km, lat, lon });
            }
        }
        return out;
    }

    /**
     * For sparse networks (air-quality grids, official alert polygons) a
     * boundary scan of a single town can legitimately return nothing. Widen
     * to a radius when that happens — but record it on the area so the answer
     * can SAY it widened, rather than quietly reporting a different scope
     * than the one it claims.
     */
    function withinWider(features, area, radiusKm, floorKm) {
        const hits = within(features, area, Math.max(radiusKm, floorKm));
        if (hits.length || !area || !area.rings) return hits;
        const widened = [];
        for (const f of features) {
            const g = f.geometry;
            if (!g) continue;
            let lon, lat;
            if (g.type === 'Point') { [lon, lat] = g.coordinates; }
            else if (f.properties && f.properties.point_lat != null) {
                lon = f.properties.point_lng; lat = f.properties.point_lat;
            } else { continue; }
            const km = haversineKm(area.lat, area.lon, lat, lon);
            if (km <= floorKm) widened.push({ f, km, lat, lon });
        }
        if (widened.length) area.widenedKm = floorKm;
        return widened;
    }

    // ---------- The GDACS wire ----------
    //
    // The map already carries the GDACS feed as 'intel-gdacs-source', but the
    // layer keeps only what it draws (no impact line, no headline, no story
    // id). The mirror itself is public and ~200 KB, so the wire section reads
    // it directly, keeps it for five minutes, and falls back to the map
    // source only when the mirror cannot be reached.

    const WIRE_MIRROR_URL =
        'https://storage.googleapis.com/ecolens-archive-ecolens-ad854/archive/v1/gdacs/current.geojson';
    const WIRE_TTL_MS = 5 * 60 * 1000;
    const WIRE_FETCH_TIMEOUT_MS = 8000;
    const WIRE_LIMIT = 5;

    // Topic → GDACS event type. The bare wire topic means every type.
    const WIRE_TYPES = {
        floods: 'FL', drought: 'DR', cyclone: 'TC', volcano: 'VO',
        tsunami: 'TS', earthquakes: 'EQ', fires: 'WF',
    };
    // Listing topics the wire answers on its own (fires keep their FIRMS
    // section and their existing escalation rules).
    const WIRE_LISTING_TOPICS = ['floods', 'drought', 'cyclone', 'volcano', 'tsunami', 'earthquakes', 'wire'];
    const WIRE_TYPE_NOUNS = {
        EQ: ['earthquake', 'earthquakes'], TC: ['tropical cyclone', 'tropical cyclones'],
        FL: ['flood', 'floods'], VO: ['volcanic eruption', 'volcanic eruptions'],
        DR: ['drought', 'droughts'], WF: ['wildfire alert', 'wildfire alerts'],
        TS: ['tsunami', 'tsunamis'],
    };
    const WIRE_LEVEL_RANK = { Red: 0, Orange: 1, Green: 2 };
    const WIRE_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    let wireCache = { at: 0, features: null, generatedAt: null };
    let wireInFlight = null;

    function normaliseWire(data) {
        return ((data && data.features) || [])
            .filter(f => f && f.geometry && f.geometry.type === 'Point' &&
                Array.isArray(f.geometry.coordinates) && f.geometry.coordinates.length === 2)
            .map(f => ({
                type: 'Feature',
                geometry: f.geometry,
                properties: Object.assign({}, f.properties || {}, {
                    event_type: String((f.properties || {}).event_type || '').toUpperCase(),
                }),
            }));
    }

    /** Whatever the wire holds right now: the fresh mirror, else the map source. */
    function wireFeatures() {
        if (wireCache.features && Date.now() - wireCache.at < WIRE_TTL_MS) return wireCache.features;
        return sourceFeatures('intel-gdacs-source');
    }

    /** Read the mirror once per five minutes; never throws. */
    function ensureWire() {
        if (wireCache.features && Date.now() - wireCache.at < WIRE_TTL_MS) {
            return Promise.resolve(wireCache.features);
        }
        if (wireInFlight) return wireInFlight;
        wireInFlight = (async () => {
            const ctrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
            const timer = ctrl ? setTimeout(() => ctrl.abort(), WIRE_FETCH_TIMEOUT_MS) : null;
            try {
                const resp = await fetch(WIRE_MIRROR_URL, ctrl ? { signal: ctrl.signal } : undefined);
                if (!resp.ok) throw new Error('mirror responded ' + resp.status);
                const data = await resp.json();
                const features = normaliseWire(data);
                if (features.length) {
                    wireCache = { at: Date.now(), features, generatedAt: data.generated_at || null };
                }
                return wireFeatures();
            } catch (e) {
                console.warn('[AskTheMap] GDACS mirror unreachable, using the map source:', e.message);
                return wireFeatures();
            } finally {
                if (timer) clearTimeout(timer);
                wireInFlight = null;
            }
        })();
        return wireInFlight;
    }

    /** "1 Sep 2026" from a published ISO stamp, in UTC to match the stamp. */
    function wireDate(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        if (isNaN(d.getTime())) return String(iso);
        return d.getUTCDate() + ' ' + WIRE_MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear();
    }

    function wireStamp(p) {
        const t = Date.parse(p.to_date || p.from_date || '');
        return isNaN(t) ? 0 : t;
    }

    function wireTypesFor(intent) {
        if (intent.sweep) return null; // the whole wire for the view
        const types = [];
        for (const k of intent.topics) {
            if (WIRE_TYPES[k] && !types.includes(WIRE_TYPES[k])) types.push(WIRE_TYPES[k]);
        }
        return types.length ? types : null; // bare "latest" → every type
    }

    /**
     * The wire section. Pure: features in, section out. Every figure in it
     * is either a count of the listed events or a value GDACS published
     * (alert level, population statement, impact report, dates).
     *
     * opts: { types: string[]|null, area, radiusKm, worldwide: bool }
     */
    function buildWireSection(features, opts) {
        const types = opts.types || null;
        const worldwide = !!opts.worldwide;
        const area = opts.area;
        const radiusKm = opts.radiusKm || DEFAULT_RADIUS_KM;
        const nounFor = (n) => {
            if (types && types.length === 1) return WIRE_TYPE_NOUNS[types[0]][n === 1 ? 0 : 1];
            return n === 1 ? 'event' : 'events';
        };
        const title = (types && types.length === 1)
            ? WIRE_TYPE_NOUNS[types[0]][1].replace(/^./, c => c.toUpperCase()) + ' on the wire'
            : 'On the wire';
        const scopeLabel = worldwide ? 'the GDACS wire, worldwide' : scopePhrase(area, radiusKm);
        const scopeText = worldwide ? 'worldwide' : scopePhrase(area, radiusKm);
        const section = {
            key: 'wire', title, scopeLabel, worldwide, items: [], count: 0,
            answered: false,
            source: 'GDACS alert wire, mirrored server-side every 15 minutes',
            layers: [], intelLayers: ['gdacs'],
        };

        if (!features || !features.length) {
            section.body = 'The GDACS wire could not be read just now, so this is unknown, ' +
                'not clear. Retry in a minute.';
            return section;
        }

        const typed = types
            ? features.filter(f => types.includes(((f.properties || {}).event_type || '').toUpperCase()))
            : features;
        const hits = worldwide
            ? typed.map(f => ({ f }))
            : within(typed, area, radiusKm);

        hits.sort((a, b) => {
            const pa = a.f.properties || {}, pb = b.f.properties || {};
            const ra = WIRE_LEVEL_RANK[pa.alert_level] != null ? WIRE_LEVEL_RANK[pa.alert_level] : 3;
            const rb = WIRE_LEVEL_RANK[pb.alert_level] != null ? WIRE_LEVEL_RANK[pb.alert_level] : 3;
            if (ra !== rb) return ra - rb;
            return wireStamp(pb) - wireStamp(pa);
        });

        section.count = hits.length;
        section.answered = true;
        if (!hits.length) {
            section.body = 'No ' + nounFor(2) + ' on the GDACS wire ' + scopeText +
                ' at the moment. The wire lists events GDACS has issued an alert for, so ' +
                'a small local event may not appear on it.';
            return section;
        }

        const levels = { Red: 0, Orange: 0, Green: 0 };
        const byType = {};
        let closed = 0;
        for (const h of hits) {
            const p = h.f.properties || {};
            if (levels[p.alert_level] != null) levels[p.alert_level]++;
            byType[p.event_type] = (byType[p.event_type] || 0) + 1;
            if (p.is_current === false) closed++;
        }
        const n = hits.length;
        let body = n + ' ' + nounFor(n) + ' on the GDACS wire ' + scopeText;
        if (!(types && types.length === 1)) {
            const parts = Object.keys(byType)
                .sort((a, b) => byType[b] - byType[a])
                .map(t => byType[t] + ' ' + (WIRE_TYPE_NOUNS[t]
                    ? WIRE_TYPE_NOUNS[t][byType[t] === 1 ? 0 : 1] : t));
            body += ' (' + parts.join(', ') + ')';
        }
        // "all green" is only true when every listed event carries that
        // level; an event without a published level is said to be one.
        const unrated = n - levels.Red - levels.Orange - levels.Green;
        const levelBits = [];
        if (levels.Red) levelBits.push(levels.Red + ' red');
        if (levels.Orange) levelBits.push(levels.Orange + ' orange');
        if (!levelBits.length && levels.Green === n) levelBits.push('all green');
        if (unrated) levelBits.push(unrated + ' with no published level');
        body += (levelBits.length ? ', ' + levelBits.join(', ') : '') + '.';
        if (closed) body += ' ' + (n - closed) + ' current, ' + closed + ' closed.';
        if (n > WIRE_LIMIT) {
            body += ' Showing the ' + WIRE_LIMIT + ' highest-level, most recent.';
        }
        body += ' Alert levels, population and impact figures are as published by GDACS; ' +
            'EcoLens adds nothing to them.';
        section.body = body;

        section.items = hits.slice(0, WIRE_LIMIT).map(h => {
            const p = h.f.properties || {};
            const impact = (p.impact || '').trim();
            const affected = (p.affected || '').trim();
            return {
                id: p.id || null,
                url: p.url || '',
                type: p.event_type || '',
                headline: p.headline || p.event_name || 'GDACS event',
                level: p.alert_level || '',
                country: p.country || '',
                detail: impact || affected || '',
                detailKind: impact ? 'Impact' : (affected ? 'Affected' : ''),
                // "updated" is the published to_date; an event that only
                // carries a from_date is dated from it, and labelled so.
                updated: wireDate(p.to_date),
                from: wireDate(p.from_date),
                status: p.is_current === false ? 'closed' : 'current',
            };
        });
        return section;
    }

    /**
     * Group in-range detections into spatial concentrations and name each one.
     *
     * Greedy: seed on the strongest remaining detection, absorb everything
     * within CLUSTER_KM, repeat. Coarse on purpose — the point is to say
     * "near Prince George" and "near Fort Nelson" rather than to produce a
     * defensible cluster boundary, which is what the Gi* layer is for.
     */
    const CLUSTER_KM = 120;

    function namedConcentrations(hits, limit) {
        if (!hits || !hits.length) return [];
        const pool = hits.slice().sort((a, b) =>
            (b.f.properties.frp || 0) - (a.f.properties.frp || 0));
        const used = new Array(pool.length).fill(false);
        const out = [];
        for (let i = 0; i < pool.length && out.length < (limit || 4); i++) {
            if (used[i]) continue;
            const seed = pool[i];
            let count = 0, frp = 0, latSum = 0, lonSum = 0;
            for (let j = i; j < pool.length; j++) {
                if (used[j]) continue;
                if (havKm(seed.lat, seed.lon, pool[j].lat, pool[j].lon) <= CLUSTER_KM) {
                    used[j] = true;
                    count++;
                    frp += pool[j].f.properties.frp || 0;
                    latSum += pool[j].lat;
                    lonSum += pool[j].lon;
                }
            }
            if (count < 2) continue; // a lone pixel is not a concentration
            const lat = latSum / count, lon = lonSum / count;
            const label = (window.AnomalyDesk && window.AnomalyDesk.regionLabel)
                ? window.AnomalyDesk.regionLabel(lat, lon)
                : lat.toFixed(1) + '°, ' + lon.toFixed(1) + '°';
            out.push({ label, count, frp, lat, lon });
        }
        return out.sort((a, b) => b.count - a.count);
    }

    function gatherFindings(intent, area) {
        const radiusKm = area.radiusKm || DEFAULT_RADIUS_KM;
        const findings = { area, radiusKm, generated: new Date(), sections: [] };

        // --- Wildfires + significance ---
        if (intent.topics.includes('fires') || intent.topics.includes('smoke') ||
            intent.topics.includes('evacuation')) {
            const fires = within(sourceFeatures('fires-source'), area, radiusKm);
            const hotCells = within(
                sourceFeatures('hotspots-source').filter(f =>
                    f.properties && (f.properties.p_bucket === 'hot99' || f.properties.p_bucket === 'hot95')
                ).map(f => {
                    // use polygon's first vertex as an anchor point
                    const ring = f.geometry && f.geometry.coordinates && f.geometry.coordinates[0];
                    return ring && ring.length ? {
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: ring[0] },
                        properties: f.properties,
                    } : null;
                }).filter(Boolean),
                area, radiusKm
            );
            let body;
            if (!fires.length) {
                body = 'No satellite fire detections ' + scopePhrase(area, radiusKm) +
                    ' in the current data window.';
            } else {
                fires.sort((a, b) => a.km - b.km);
                const nearest = fires[0];
                const strongest = fires.reduce((m, x) =>
                    ((x.f.properties.frp || 0) > (m.f.properties.frp || 0) ? x : m), fires[0]);
                body = fires.length + ' active detection' + (fires.length === 1 ? '' : 's') +
                    ' ' + scopePhrase(area, radiusKm) + '. Nearest is ' + Math.round(nearest.km) +
                    ' km ' + bearingLabel(area.lat, area.lon, nearest.lat, nearest.lon) +
                    '; strongest is ' + (strongest.f.properties.frp || 0).toFixed(0) +
                    ' MW fire power.';
                // "Which areas are worst" is a question about PLACES. A count
                // and a bearing does not answer it — name the concentrations.
                const named = namedConcentrations(fires, 4);
                if (named.length) {
                    body += ' The heaviest concentrations are ' +
                        named.map(c => c.label + ' (' + c.count +
                            (c.count === 1 ? ' detection' : ' detections') +
                            (c.frp ? ', ' + Math.round(c.frp) + ' MW' : '') + ')')
                            .join(', ') + '.';
                }
                if (hotCells.length) {
                    body += ' ' + hotCells.length + ' zone' + (hotCells.length === 1 ? '' : 's') +
                        ' in range are statistically significant clusters (Getis-Ord Gi*), not scattered noise.';
                } else if (sourceFeatures('hotspots-source').length) {
                    body += ' None of the in-range activity forms a statistically significant cluster.';
                }
            }
            findings.sections.push({
                key: 'fires', title: 'Wildfires', body,
                source: 'NASA FIRMS (VIIRS) + client-side Gi* statistics',
                layers: ['fires', 'hotspots'],
                count: fires.length,
            });
        }

        // --- Smoke (PM2.5 proxy) ---
        if (intent.topics.includes('smoke')) {
            const aq = withinWider(sourceFeatures('airquality-source'), area, radiusKm, 300);
            let body;
            if (!aq.length) {
                body = 'No air-quality grid points loaded for this area yet — toggle the ' +
                    'Air Quality layer and retry, or treat this as unknown, not as "clear".';
            } else {
                const worst = aq.reduce((m, x) =>
                    ((x.f.properties.pm25 || 0) > (m.f.properties.pm25 || 0) ? x : m), aq[0]);
                const pm = worst.f.properties.pm25;
                const sev = pm > 150 ? 'hazardous' : pm > 55 ? 'unhealthy' :
                    pm > 35 ? 'unhealthy for sensitive groups' : pm > 12 ? 'moderate' : 'good';
                body = 'Densest smoke signal is ' + Math.round(worst.km) + ' km ' +
                    bearingLabel(area.lat, area.lon, worst.lat, worst.lon) +
                    ': PM2.5 ' + Math.round(pm) + ' µg/m³ (' + sev + '). ' +
                    'PM2.5 is a proxy for smoke — the grid is coarse, so between-point ' +
                    'conditions are interpolated by eye, not measured.';
            }
            findings.sections.push({
                key: 'smoke', title: 'Smoke / air quality', body,
                source: 'Open-Meteo air-quality grid (PM2.5 as smoke proxy)',
                layers: ['airquality'],
                count: aq.length,
            });
        }

        // --- Evacuations & official measures (from official alert text) ---
        if (intent.topics.includes('evacuation') || intent.topics.includes('measures')) {
            const alertSources = ['intel-nwsalerts-source', 'intel-gdacs-source'];
            let alerts = [];
            for (const sid of alertSources) {
                alerts = alerts.concat(withinWider(sourceFeatures(sid), area, radiusKm, 250));
            }
            const texts = alerts.map(a => {
                const p = a.f.properties || {};
                return {
                    km: a.km,
                    title: p.headline || p.event || p.title || p.name || 'Official alert',
                    text: [p.headline, p.description, p.instruction, p.summary]
                        .filter(Boolean).join(' '),
                };
            });
            const evac = texts.filter(t => /evacuat|shelter in place|leave the area/i.test(t.text));
            let body;
            if (!texts.length) {
                body = 'No official alerts (NWS/GDACS) active within range right now. ' +
                    'That covers agencies these feeds monitor — always confirm with local authorities.';
            } else {
                body = texts.length + ' official alert' + (texts.length === 1 ? '' : 's') +
                    ' in range.';
                if (evac.length) {
                    const first = evac[0];
                    body += ' ' + evac.length + ' mention evacuation or shelter instructions — nearest: “' +
                        first.title.slice(0, 90) + '” (' + Math.round(first.km) + ' km away). ' +
                        'Open the alert on the map for the full official instructions.';
                } else {
                    body += ' None currently carries an evacuation order.';
                }
                body += ' EcoLens does not compute road routes — evacuation directions ' +
                    'must come from the official instructions themselves.';
            }
            findings.sections.push({
                key: 'measures', title: 'Evacuations & official measures', body,
                source: 'NWS alerts + GDACS (official text, quoted not paraphrased)',
                layers: [],
                intelLayers: ['nwsalerts', 'gdacs'],
                count: texts.length,
            });
        }

        // --- Other hazards on request ---
        if (intent.topics.includes('earthquakes')) {
            const q = within(sourceFeatures('earthquakes-source'), area, radiusKm);
            const maxMag = q.reduce((m, x) => Math.max(m, x.f.properties.magnitude || 0), 0);
            findings.sections.push({
                key: 'earthquakes', title: 'Earthquakes',
                body: q.length
                    ? q.length + ' event(s) ' + scopePhrase(area, radiusKm) + ' in window; strongest M' + maxMag.toFixed(1) + '.'
                    : 'No M2.5+ earthquakes ' + scopePhrase(area, radiusKm) + ' in the current window.',
                source: 'USGS', layers: ['earthquakes'], count: q.length,
            });
        }

        // --- The GDACS wire: floods, drought, cyclones, volcanoes, tsunamis,
        //     earthquakes, and "what is going on" ---
        if (intent.topics.some(k => WIRE_LISTING_TOPICS.includes(k))) {
            findings.sections.push(buildWireSection(wireFeatures(), {
                types: wireTypesFor(intent),
                area, radiusKm,
                worldwide: !!intent.worldwide,
            }));
        }

        // A worldwide wire answer is about the feed, not about the view —
        // the head line and the camera both need to know.
        findings.worldwide = findings.sections.length > 0 &&
            findings.sections.every(s => s.key === 'wire' && s.worldwide);

        return findings;
    }

    // ---------- Acting on the map ----------

    function activateLayers(findings) {
        for (const s of findings.sections) {
            for (const l of (s.layers || [])) {
                if (window.HazardLayers) {
                    window.HazardLayers.setLayerVisibility(l, true);
                    const cb = document.getElementById('toggle-' + l);
                    if (cb) cb.checked = true;
                    const wrap = document.querySelector('.layer-toggle-wrap[data-layer="' + l + '"]');
                    if (wrap) wrap.classList.add('is-on');
                }
            }
            for (const l of (s.intelLayers || [])) {
                if (window.IntelligenceLayers) {
                    window.IntelligenceLayers.setLayerVisibility(l, true);
                    // Sync the pill: a layer the answer turned on must show
                    // as ON, or the reader can neither explain nor kill it.
                    const cb = document.getElementById('toggle-' + l);
                    if (cb) cb.checked = true;
                    const wrap = document.querySelector('.layer-toggle-wrap[data-intel="' + l + '"]');
                    if (wrap) wrap.classList.add('is-on');
                }
            }
        }
        // A worldwide wire answer leaves the camera alone: zooming in on
        // wherever the map happened to be would contradict the head line.
        if (window.ecoMap && findings.area && !findings.worldwide) {
            if (findings.area.bbox) {
                // Frame the whole named region, not an arbitrary zoom on its centroid
                const [w, s, e, n] = findings.area.bbox;
                window.ecoMap.fitBounds([[w, s], [e, n]], { padding: 90, duration: 1200, maxZoom: 9 });
            } else {
                window.ecoMap.flyTo({
                    center: [findings.area.lon, findings.area.lat],
                    zoom: Math.max(window.ecoMap.getZoom(), 6.5),
                    duration: 1200,
                });
            }
        }
    }

    // ---------- Answer composition ----------
    // [GEMINI SEAM] `findings` is fully structured: if narrative synthesis
    // via Gemini is added later, it replaces ONLY this template, receiving
    // `findings` as input and returning prose — the data gathering and
    // provenance lines above stay deterministic either way.

    /** A published country list, tidied for one line: blanks and repeats
     *  dropped, four or more names folded into a count. */
    function foldCountries(text) {
        const names = [];
        String(text || '').split(',').forEach(part => {
            const t = part.trim();
            if (t && !names.includes(t)) names.push(t);
        });
        if (!names.length) return '';
        return names.length >= 4 ? names.length + ' countries' : names.join(', ');
    }

    /** "Drought in A, B, C, D, E: fact" reads as "Drought across 5 countries: fact". */
    function foldHeadline(text) {
        const h = String(text || '');
        const inAt = h.indexOf(' in ');
        if (inAt < 0) return h;
        const colon = h.indexOf(':', inAt);
        const list = colon < 0 ? h.slice(inAt + 4) : h.slice(inAt + 4, colon);
        const names = list.split(',').map(t => t.trim()).filter(Boolean);
        if (names.length < 4) return h;
        return h.slice(0, inAt) + ' across ' + names.length + ' countries' + (colon < 0 ? '' : h.slice(colon));
    }

    function wireItemsHtml(section, sectionIndex) {
        let html = '';
        (section.items || []).forEach((it, i) => {
            // The plain wire headline is "Type: event name, country list";
            // fold the list the same way the meta line does.
            const country = String(it.country || '');
            let headline = String(it.headline || '');
            if (country && headline.endsWith(', ' + country)) {
                headline = headline.slice(0, headline.length - country.length) + foldCountries(country);
            }
            headline = foldHeadline(headline);
            html += '<div class="atm-wire-item">' +
                '<div class="atm-wire-head">' +
                (it.level ? '<span class="atm-wire-level">' + esc(it.level) + ' alert</span> ' : '') +
                '<span class="atm-wire-headline">' + esc(headline) + '</span></div>' +
                '<div class="atm-wire-meta">' +
                esc([foldCountries(it.country), it.status,
                    it.updated ? 'updated ' + it.updated : (it.from ? 'from ' + it.from : '')]
                    .filter(Boolean).join(' · ')) + '</div>' +
                (it.detail
                    ? '<div class="atm-wire-detail">' + esc(it.detailKind) + ': ' + esc(it.detail) + '</div>'
                    : '') +
                '<button type="button" class="atm-story" data-wire="' + sectionIndex + ':' + i + '">' +
                'Read the story →</button>' +
                '</div>';
        });
        return html;
    }

    function composeAnswer(findings, intent) {
        const when = findings.generated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        let html = findings.worldwide
            ? '<div class="atm-head">On the GDACS wire · worldwide</div>'
            : '<div class="atm-head">Around ' + esc(findings.area.label) +
              ' · ' + scanLabel(findings.area, findings.radiusKm) + '</div>';
        if (findings.area.warning) {
            // Falling back to the map view is a normal outcome, not a fault.
            // Red reads as "something broke" and makes a working answer look
            // like an error report.
            html += '<div class="atm-note">' + esc(findings.area.warning) + '</div>';
        }
        findings.sections.forEach((s, si) => {
            html += '<div class="atm-section">' +
                '<div class="atm-title">' + esc(s.title) +
                // A worldwide wire listing inside a view-scoped answer (e.g.
                // "latest earthquakes" also gets the USGS section) says so
                // in its title, since the head line describes the view.
                (s.key === 'wire' && s.worldwide && !findings.worldwide ? ' · worldwide' : '') +
                '</div>' +
                '<div class="atm-body">' + esc(s.body) + '</div>' +
                (s.key === 'wire' ? wireItemsHtml(s, si) : '') +
                '<div class="atm-source">Source: ' + esc(s.source) + '</div>' +
                '</div>';
        });
        if (findings.area.widenedKm) {
            html += '<div class="atm-note">Some networks (air quality, official ' +
                'alerts) have no station or polygon inside ' +
                esc(findings.area.label) + ' itself, so those figures come from a ' +
                findings.area.widenedKm + ' km radius instead. Fire and earthquake ' +
                'counts are scanned against the real boundary.</div>';
        }
        html += '<div class="atm-prov">Computed in your browser at ' + when +
            ' from the live data window. Nothing here is modeled or generated — ' +
            'counts and distances come straight from the mapped features' +
            (findings.sections.some(s => s.key === 'wire')
                ? ', and wire figures are quoted from GDACS as published' : '') + '.</div>';
        if (window.AtlasBridge && window.AtlasBridge.isHealthy && window.AtlasBridge.isHealthy()) {
            html += '<button class="atm-deep" id="atm-deep-btn">Run deeper Atlas analysis</button>';
        } else if (intent.deep) {
            html += '<div class="atm-source">Deeper statistical analysis needs the local ' +
                'Atlas engine (currently offline).</div>';
        }
        return html;
    }

    /**
     * What Atlas receives. The question stays the question; the resolved
     * place and the live figures ride alongside as structured fields so the
     * interpreter never has to parse "124 detections within 150 km" out of
     * the sentence. Only a geocoded place carries a name Atlas can resolve —
     * "the current map view" and "your location" are labels, not places.
     */
    function atlasPrompt(findings, intent) {
        const a = findings.area;
        return {
            prompt: intent.raw,
            studyArea: a.fullName || null,
            context: 'Scope: ' + atlasScope(findings.area, findings.radiusKm) + ' latitude ' +
                a.lat.toFixed(3) + ', longitude ' + a.lon.toFixed(3) + '. ' +
                findings.sections.map(s => s.title + ': ' + s.body).join(' | '),
        };
    }

    function askAtlas(findings, intent) {
        const q = atlasPrompt(findings, intent);
        return window.AtlasBridge.ask(q.prompt, { studyArea: q.studyArea, context: q.context });
    }

    /**
     * "Read the story →" hands the wire item to the Flutter shell, which opens
     * it in Environmental News. Items are looked up by index, never by
     * attribute text, so nothing published ends up inside markup.
     */
    function bindStoryButtons(content, findings) {
        content.querySelectorAll('.atm-story').forEach((btn) => {
            btn.onclick = () => {
                const ref = String(btn.getAttribute('data-wire') || '').split(':');
                const section = findings.sections[Number(ref[0])];
                const item = section && section.items && section.items[Number(ref[1])];
                if (!item) return;
                if (window.EcoLensBridge && window.EcoLensBridge.sendToFlutter) {
                    window.EcoLensBridge.sendToFlutter('openNewsStory',
                        { id: item.id || null, url: item.url });
                } else if (item.url) {
                    window.open(item.url, '_blank', 'noopener'); // standalone browser
                }
            };
        });
    }

    // ---------- UI (self-injected: one omnibox + one answer panel) ----------

    function injectUI() {
        if (document.getElementById('atm-bar')) return;
        const style = document.createElement('style');
        style.textContent = `
            /* Floating over the map, top-left beside the icon rail — where a
               map search belongs; the masthead keeps brand + status only. */
            #atm-bar { position: fixed;
                top: calc(var(--masthead-h, 48px) + 12px);
                left: calc(var(--rail-w, 46px) + 14px);
                z-index: 260; width: min(460px, calc(100vw - 140px)); display: flex; gap: 8px;
                background: var(--paper, #F2EFE4);
                border: 1px solid var(--ink, #232019); border-radius: 3px; padding: 5px 5px 5px 8px;
                box-shadow: 3px 3px 0 rgba(35,32,25,0.14); font-family: system-ui, sans-serif; }
            #atm-bar:focus-within { border-color: var(--survey, #2B5A73); }
            /* The layers flyout slides over this spot — hide the bar while open */
            body.flyout-open #atm-bar, body.flyout-open #atm-panel { display: none; }
            #atm-input { flex: 1; background: transparent; border: none; outline: none;
                color: var(--ink, #232019); font-size: 13px; padding: 6px 8px; }
            #atm-input::placeholder { color: var(--ink-faint, #8C8574);
                font-family: var(--serif, Georgia, serif); font-style: italic; }
            #atm-go { background: var(--ink, #232019); color: var(--paper, #F2EFE4);
                border: 1px solid var(--ink, #232019);
                border-radius: 3px; padding: 6px 16px; font-size: 12px; font-weight: 700; cursor: pointer; }
            #atm-go:hover { background: var(--survey, #2B5A73); border-color: var(--survey, #2B5A73); }
            #atm-panel { position: fixed;
                top: calc(var(--masthead-h, 48px) + 62px);
                left: calc(var(--rail-w, 46px) + 14px);
                z-index: 259; width: min(460px, calc(100vw - 140px)); max-height: 55vh; overflow-y: auto;
                background: var(--paper, #F2EFE4);
                border: 1px solid var(--ink, #232019); border-radius: 3px; padding: 14px 16px;
                box-shadow: 4px 4px 0 rgba(35,32,25,0.14); color: var(--ink, #232019); display: none;
                font-family: system-ui, sans-serif; }
            .atm-scope .atm-live { margin-top: 11px; padding: 9px 11px;
                background: var(--paper-deep, #EAE6D6);
                border-left: 3px solid var(--survey, #2B5A73); border-radius: 3px; }
            .atm-scope .atm-live-head { font-size: 11px; font-weight: 700;
                text-transform: uppercase; letter-spacing: 1.1px;
                color: var(--survey, #2B5A73); display: flex; align-items: center; gap: 7px; }
            .atm-scope .atm-live-step { font-size: 11.5px; line-height: 1.45;
                color: var(--ink-soft, #5B564A); margin-top: 5px; }
            .atm-scope .atm-spin { width: 9px; height: 9px; border-radius: 50%;
                border: 2px solid var(--survey, #2B5A73); border-top-color: transparent;
                display: inline-block; animation: atm-spin 0.9s linear infinite; }
            @keyframes atm-spin { to { transform: rotate(360deg); } }
            @media (prefers-reduced-motion: reduce) {
                .atm-scope .atm-spin { animation: none; }
            }
            .atm-scope .atm-answer { margin-top: 12px; padding: 12px 13px;
                background: var(--paper-raised, #FBF9F1);
                border: 1px solid var(--rule, #D9D2BF);
                border-left: 3px solid var(--survey, #2B5A73); border-radius: 3px; }
            .atm-scope .atm-answer-kicker { font-size: 8.5px; font-weight: 800;
                letter-spacing: 1.4px; text-transform: uppercase;
                color: var(--survey, #2B5A73); margin-bottom: 7px; }
            .atm-scope .atm-answer p { font-family: var(--serif, Georgia, serif);
                font-size: 13px; line-height: 1.55; color: var(--ink, #232019);
                margin: 0 0 8px; }
            .atm-scope .atm-answer .atlas-answer-row { display: flex;
                justify-content: space-between; padding: 3px 0;
                border-top: 1px solid var(--rule, #D9D2BF); font-size: 11.5px;
                color: var(--ink-soft, #5B564A); }
            .atm-scope .atm-jump { display: block; width: 100%; margin-top: 10px;
                padding: 8px 11px; background: var(--survey, #2B5A73);
                color: var(--paper-raised, #FBF9F1); border: none; border-radius: 3px;
                cursor: pointer; font-size: 11.5px; font-weight: 600; text-align: left; }
            .atm-scope .atm-jump:hover { background: var(--ink, #232019); }
            .atm-scope .atm-note { font-size: 11.5px; line-height: 1.45;
                color: var(--ink-soft, #5B564A); background: var(--paper-deep, #EAE6D6);
                border-left: 2px solid var(--ink-faint, #8C8574); border-radius: 2px;
                padding: 7px 9px; margin-bottom: 11px; }
            .atm-scope .atm-head { font-size: 9px; font-weight: 700; text-transform: uppercase;
                letter-spacing: 1.4px; color: var(--ink-faint, #8C8574); margin-bottom: 10px; }
            .atm-scope .atm-section { margin-bottom: 12px; }
            .atm-scope .atm-title { font-size: 14px; font-weight: 700; margin-bottom: 3px;
                font-family: var(--serif, Georgia, serif); }
            .atm-scope .atm-body { font-size: 12.5px; line-height: 1.5; color: var(--ink-soft, #5B564A); }
            .atm-scope .atm-source { font-size: 10px; color: var(--ink-faint, #8C8574); margin-top: 3px; }
            .atm-scope .atm-prov { font-size: 10.5px; color: var(--ink-soft, #5B564A);
                border-top: 1px solid var(--rule, #D9D2BF);
                padding-top: 8px; margin-top: 4px; line-height: 1.45; }
            .atm-scope .atm-deep { margin-top: 10px; width: auto; display: inline-block; background: var(--survey-wash, #E3EAEA);
                color: var(--survey, #2B5A73); border: 1px solid var(--survey, #2B5A73); border-radius: 3px;
                padding: 6px 12px; font-size: 11px; font-weight: 700; cursor: pointer; }
            .atm-scope .atm-deep:hover { background: var(--survey, #2B5A73); color: var(--paper, #F2EFE4); }
            .atm-scope .atm-wire-item { border-top: 1px solid var(--rule, #D9D2BF);
                padding: 7px 0 8px; margin-top: 6px; }
            .atm-scope .atm-wire-head { font-size: 12.5px; line-height: 1.4; color: var(--ink, #232019); }
            .atm-scope .atm-wire-level { font-size: 9px; font-weight: 700; text-transform: uppercase;
                letter-spacing: 1.1px; color: var(--survey, #2B5A73); margin-right: 4px; }
            .atm-scope .atm-wire-headline { font-family: var(--serif, Georgia, serif); font-weight: 700; }
            .atm-scope .atm-wire-meta { font-family: var(--mono-data, Consolas, monospace);
                font-size: 10.5px; color: var(--ink-faint, #8C8574); margin-top: 2px; }
            .atm-scope .atm-wire-detail { font-size: 12px; line-height: 1.45;
                color: var(--ink-soft, #5B564A); margin-top: 3px; }
            .atm-scope .atm-story { margin-top: 5px; background: transparent;
                color: var(--survey, #2B5A73); border: 1px solid var(--survey, #2B5A73);
                border-radius: 3px; padding: 3px 9px; font-size: 11px; font-weight: 600; cursor: pointer; }
            .atm-scope .atm-story:hover { background: var(--survey, #2B5A73); color: var(--paper, #F2EFE4); }
            .atm-scope .atm-answer-plain { margin-top: 12px; padding: 10px 13px;
                font-family: var(--serif, Georgia, serif); font-size: 13px; line-height: 1.5;
                color: var(--ink, #232019); background: var(--paper-raised, #FBF9F1);
                border: 1px solid var(--rule, #D9D2BF); border-radius: 3px; }
            #atm-close { position: absolute; top: 8px; right: 10px; background: none; border: none;
                color: var(--ink-faint, #8C8574); font-size: 15px; cursor: pointer; }
            #atm-close:hover { color: var(--ink, #232019); }
        `;
        document.head.appendChild(style);

        const bar = document.createElement('form');
        bar.id = 'atm-bar';
        bar.innerHTML =
            '<input id="atm-input" type="text" autocomplete="off" ' +
            'placeholder="Ask the map — e.g. wildfires, smoke and evacuations near me" />' +
            '<button id="atm-go" type="submit">Ask</button>';
        // Always floats over the map (top-left, beside the rail) — moved out
        // of the masthead 2026-07-28 for reach + to give live status room.
        document.body.appendChild(bar);

        const panel = document.createElement('div');
        panel.id = 'atm-panel';
        panel.className = 'atm-scope';
        panel.innerHTML = '<button id="atm-close" type="button">✕</button><div id="atm-content"></div>';
        document.body.appendChild(panel);

        bar.addEventListener('submit', (e) => {
            e.preventDefault();
            const q = document.getElementById('atm-input').value;
            if (q && q.trim()) answer(q.trim());
        });
        panel.querySelector('#atm-close').addEventListener('click', () => {
            panel.style.display = 'none';
        });
    }

    // ---------- Main flow ----------

    /**
     * What the map can answer itself, and what it cannot.
     *
     * The map is authoritative on presence and place: what is here, how many,
     * how far, in which direction. It cannot rank one measure against another,
     * establish a cause, or state its own limitations — those need the full
     * investigation, and they belong on Insights where there is room to show
     * the comparison, the sources and the caveats.
     */
    const ESCALATE_PATTERNS = [
        /\bwhy\b|caus|driver|reason|because|behind\b/i,           // causal
        /most active|worst|hottest|burning hardest|intens|severe|priority|dangerous/i,
        /compare|versus|\bvs\b|rank|which .*(worst|biggest|most)|relative/i,
        /trend|over time|since|getting worse|compared to (last|previous)/i,
        /how bad|how serious|what does (this|it) mean|so what/i,
    ];

    // A listing question the wire has answered stays on the map unless it
    // also asks for a cause, a comparison, a ranking or a trend.
    const CAUSAL_OR_RANKING = /\bwhy\b|caus|compare|versus|\bvs\b|rank|trend/i;

    function needsDeepAnswer(intent, findings) {
        const t = intent.raw || '';
        const sections = findings.sections || [];
        const wireAnswered = sections.some(s => s.key === 'wire' && s.answered);
        const listing = !intent.sweep && !intent.topics.includes('fires') &&
            intent.topics.some(k => WIRE_LISTING_TOPICS.includes(k));
        if (wireAnswered && listing && !CAUSAL_OR_RANKING.test(t)) return false;
        // parseIntent already flags statistical asks; honour that too.
        if (intent.deep) return true;
        if (ESCALATE_PATTERNS.some(re => re.test(t))) return true;
        // The map found nothing to show — escalating beats an empty panel.
        if (!findings.sections || !findings.sections.length) return true;
        return false;
    }

    async function answer(text) {
        const intent = parseIntent(text);
        // The wire read runs alongside the geocode; it never throws and
        // gives up after a few seconds in favour of the map source.
        const wantsWire = intent.topics.some(k => WIRE_LISTING_TOPICS.includes(k));
        const [area] = await Promise.all([
            resolveArea(intent),
            wantsWire ? ensureWire() : Promise.resolve(null),
        ]);
        if (!area) return;
        const findings = gatherFindings(intent, area);
        activateLayers(findings);
        // Give the fly-to + hotspot recompute a beat, then re-gather so the
        // answer reflects what's actually on screen now.
        setTimeout(() => {
            const fresh = gatherFindings(intent, area);
            const panel = document.getElementById('atm-panel');
            const content = document.getElementById('atm-content');
            if (!panel || !content) return;
            content.innerHTML = composeAnswer(fresh, intent);
            bindStoryButtons(content, fresh);
            panel.style.display = 'block';

            const atlasUp = window.AtlasBridge && window.AtlasBridge.isHealthy &&
                window.AtlasBridge.isHealthy();
            const deep = needsDeepAnswer(intent, fresh);

            const deepBtn = document.getElementById('atm-deep-btn');
            if (deepBtn) {
                deepBtn.onclick = () => {
                    deepBtn.disabled = true;
                    deepBtn.textContent = 'Atlas is working — see the Atlas tab in the right panel';
                    askAtlas(fresh, intent);
                };
            }

            // Escalation: the map has said what it can. If the question needs
            // a ranking, a cause or a stated limitation, start the full
            // investigation now rather than making the reader find a button.
            if (deep && atlasUp) {
                // One conversation, one place. The reader asked here, so the
                // investigation reports back here — the right-hand tab keeps
                // the full audit trail for anyone who wants to inspect it.
                const live = document.createElement('div');
                live.className = 'atm-live';
                live.id = 'atm-live';
                live.innerHTML =
                    '<div class="atm-live-head"><span class="atm-spin"></span>' +
                    'Running the full investigation…</div>' +
                    '<div class="atm-live-step" id="atm-live-step">' +
                    (fresh.sections && fresh.sections.length
                        ? 'That needs more than the map can show.'
                        : 'Nothing on the map answers that directly.') +
                    '</div>';
                content.appendChild(live);
                if (deepBtn) deepBtn.remove();

                // Hand the resolved place over BEFORE asking, so the engine
                // knows the jurisdiction while it decides what evidence to
                // attach rather than discovering it half-way through.
                if (window.AtlasBridge.setStudyArea && fresh.area.fullName) {
                    window.AtlasBridge.setStudyArea(fresh.area.fullName);
                }
                askAtlas(fresh, intent);
            } else if (deep && !atlasUp) {
                const note = document.createElement('div');
                note.className = 'atm-escalate';
                note.textContent = 'That question needs the full investigation engine, ' +
                    'which is offline right now. The map figures above are still live.';
                content.appendChild(note);
            }
        }, 1400);
    }

    /**
     * Mirror the investigation back into the panel the question was asked in.
     *
     * The bridge emits these as DOM events so the two surfaces stay decoupled:
     * the right-hand Atlas tab remains the full audit trail, while the reader
     * who typed a question never has to look somewhere else to get the answer.
     */
    function bindAtlasMirror() {
        window.addEventListener('ecolens-atlas-progress', (e) => {
            const step = document.getElementById('atm-live-step');
            if (step && e.detail && e.detail.message) step.textContent = e.detail.message;
        });

        window.addEventListener('ecolens-atlas-answer', (e) => {
            const content = document.getElementById('atm-content');
            const panel = document.getElementById('atm-panel');
            if (!content || !e.detail) return;
            const live = document.getElementById('atm-live');
            if (live) live.remove();
            const existing = document.getElementById('atm-answer');
            if (existing) {
                // A line written while the run was paused for data gives way
                // to the answer the resumed run produces; a final answer stays.
                if (existing.getAttribute('data-provisional') !== '1') return;
                existing.remove();
            }

            // The engine ran and reported nothing: no finding, no measured
            // correlation, no lead. Say so in one line — a template card
            // dressed as an answer would be a lie about what was found.
            if (e.detail.hasSubstance === false) {
                const line = document.createElement('div');
                line.className = 'atm-answer-plain';
                line.id = 'atm-answer';
                if (e.detail.paused) line.setAttribute('data-provisional', '1');
                line.textContent = e.detail.paused
                    ? 'Atlas paused for more data and has found no measurable relationships ' +
                      'in the attached evidence so far.'
                    : e.detail.failed
                    ? 'Atlas stopped before completing the investigation, so there is no ' +
                      'answer to report.'
                    : 'Atlas ran the full investigation and found no measurable relationships ' +
                      'in the attached evidence.';
                content.appendChild(line);
                if (panel) panel.style.display = 'block';
                return;
            }

            const card = document.createElement('div');
            card.className = 'atm-answer';
            card.id = 'atm-answer';
            card.innerHTML =
                '<div class="atm-answer-kicker">The answer · from evidence only</div>' +
                (e.detail.html || '');
            if (e.detail.hasFinding) {
                const jump = document.createElement('button');
                jump.type = 'button';
                jump.className = 'atm-jump';
                jump.textContent = 'Read the full finding in Environmental News →';
                jump.onclick = () => {
                    if (window.EcoLensBridge && window.EcoLensBridge.sendToFlutter) {
                        window.EcoLensBridge.sendToFlutter('atlasFinding',
                            { finding: e.detail.finding, navigate: true });
                    }
                };
                card.appendChild(jump);
            }
            content.appendChild(card);
            if (panel) panel.style.display = 'block';
        });
    }

    function init() {
        injectUI();
        bindAtlasMirror();
        console.log('[AskTheMap] Ready');
    }

    return { init, answer, parseIntent };
})();

window.AskTheMap = AskTheMap;
