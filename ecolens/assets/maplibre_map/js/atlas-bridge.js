// ============================================================
// EcoLens AtlasBridge — connection to the local AtlasAgent
// research workbench (http://127.0.0.1:8766).
//
// Atlas is the "peer reviewer" behind the map: it runs evidence-gated
// analyses (typed contract → deterministic GeoPandas → audit trail) and
// streams result layers back as NDJSON. This module:
//   - health-gates the whole feature (section hidden when Atlas is down;
//     mobile WebViews can't reach a desktop loopback, so it hides there)
//   - uploads live EcoLens layers to Atlas for rigorous statistics
//   - independently verifies our client-side hot-spot layer via Atlas's
//     global Moran's I ("peer-reviewed by a second engine")
//   - runs full /api/run → /api/execute investigations and adapts the
//     streamed layer contract onto the EcoLens map
//
// Requires: window.ecoMap. CORS must be allowed on the Atlas side
// (ATLAS_ALLOWED_ORIGINS env var — see atlas cli.py).
// ============================================================

const AtlasBridge = (function () {
    'use strict';

    let healthy = false;
    let currentPlan = null;
    let busy = false;
    // id → {layer, data} for re-adding after basemap style swaps
    const atlasLayers = new Map();
    let styleHookInstalled = false;

    // Endpoint discovery: an explicit override wins; otherwise prefer the
    // analyst's own local engine (full local-LLM interpreter, free), and
    // fall back to the Cloud Run service so any laptop, anywhere, works.
    const CANDIDATE_BASES = [
        window.ECOLENS_ATLAS_URL,
        'http://127.0.0.1:8766',
        window.ECOLENS_ATLAS_CLOUD_URL ||
            'https://atlas-analyst-104569501562.us-central1.run.app',
    ].filter(Boolean);
    let activeBase = CANDIDATE_BASES[0];

    const base = () => activeBase;

    const esc = (v) => String(v == null ? '' : v)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');

    const el = (id) => document.getElementById(id);

    // ---------- NDJSON stream reader (same contract as Atlas web/app.js) ----------

    async function readStream(response, onEvent) {
        if (!response.ok) {
            let message = 'Atlas request failed (' + response.status + ')';
            try { message = (await response.json()).error || message; } catch (e) { /* keep */ }
            throw new Error(message);
        }
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        while (true) {
            const { value, done } = await reader.read();
            buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
            const lines = buffer.split('\n');
            buffer = lines.pop();
            for (const line of lines) {
                if (line.trim()) onEvent(JSON.parse(line));
            }
            if (done) break;
        }
    }

    // ---------- Health ----------

    async function probeBase(candidate, timeoutMs) {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
            const resp = await fetch(candidate + '/api/health', { signal: controller.signal });
            return resp.ok;
        } catch (e) {
            return false;
        } finally {
            clearTimeout(timer);
        }
    }

    async function checkHealth() {
        for (const candidate of CANDIDATE_BASES) {
            // Cloud Run cold-starts need more grace than a loopback ping
            const timeoutMs = candidate.includes('127.0.0.1') ? 2500 : 10000;
            if (await probeBase(candidate, timeoutMs)) {
                activeBase = candidate;
                healthy = true;
                console.log('[AtlasBridge] Engine online at', candidate);
                return true;
            }
        }
        healthy = false;
        return false;
    }

    // ---------- Uploads & tools ----------

    async function uploadLayer(name, fc, planId) {
        const headers = {
            'Content-Type': 'application/geo+json',
            'X-Filename': encodeURIComponent(name + '.geojson'),
        };
        // Binding an upload to a plan attaches it as declared evidence,
        // so a paused investigation can resume with it.
        if (planId) headers['X-Plan-Id'] = planId;
        const resp = await fetch(base() + '/api/upload', {
            method: 'POST',
            headers,
            body: JSON.stringify(fc),
        });
        if (!resp.ok) {
            let msg = 'Upload failed (' + resp.status + ')';
            try { msg = (await resp.json()).error || msg; } catch (e) { /* keep */ }
            throw new Error(msg);
        }
        return resp.json();
    }

    async function runTool(tool, layerId, params) {
        const resp = await fetch(base() + '/api/tools/run', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ tool, layer_id: layerId, params: params || {} }),
        });
        if (!resp.ok) {
            let msg = 'Tool failed (' + resp.status + ')';
            try { msg = (await resp.json()).error || msg; } catch (e) { /* keep */ }
            throw new Error(msg);
        }
        return resp.json();
    }

    /**
     * Independent verification of the client-side hot-spot surface:
     * upload the hex polygons and ask Atlas for global Moran's I on the
     * detection counts. Two engines, one conclusion — or an honest
     * disagreement, which is also worth showing.
     */
    async function verifyHotspots() {
        if (!healthy || !window.ecoMap || !window.SpatialStats) return null;
        const chip = el('atlas-moran-chip');
        try {
            const source = window.ecoMap.getSource('hotspots-source');
            let fc = source && source._data;
            if (!fc || !fc.features || fc.features.length < 10) return null;

            // Atlas morans_i caps at 5000 polygons — coarsen until we fit.
            if (fc.features.length > 5000) {
                const firesSource = window.ecoMap.getSource('fires-source');
                const fires = firesSource && firesSource._data;
                if (!fires) return null;
                const S = window.SpatialStats;
                for (const cellKm of [50, 100, 200]) {
                    const cells = S.hexBin(fires.features || [], { cellKm });
                    if (cells.length <= 5000) {
                        fc = S.toGeoJSON(S.giStar(cells), { cellKm });
                        break;
                    }
                }
                if (fc.features.length > 5000) return null;
            }

            if (chip) chip.textContent = 'Atlas peer review: running…';
            const upload = await uploadLayer('ecolens_fire_hexes', fc);
            const verdict = await runTool('morans_i', upload.layer_id, { field: 'count' });
            const stat = verdict && verdict.result && verdict.result.statistic;
            if (typeof stat === 'number' && chip) {
                const reading = stat > 0.3 ? 'strongly clustered'
                    : stat > 0.1 ? 'clustered'
                    : stat > -0.1 ? 'random' : 'dispersed';
                chip.textContent =
                    'Atlas peer review: Moran’s I = ' + stat.toFixed(3) +
                    ' (' + reading + ', Queen contiguity, n=' +
                    verdict.result.features + ')';
                chip.title = 'Independently computed by the local AtlasAgent engine ' +
                    'from the same hex counts — a second opinion on the clustering signal.';
            }
            return verdict;
        } catch (e) {
            if (chip) chip.textContent = 'Atlas peer review unavailable: ' + e.message;
            console.warn('[AtlasBridge] verifyHotspots:', e);
            return null;
        }
    }

    // ---------- Investigations (plan → approve → execute) ----------

    function feedRow(event) {
        const feed = el('atlas-feed');
        if (!feed) return;
        const row = document.createElement('div');
        row.className = 'atlas-feed-row' +
            (event.status === 'failed' ? ' failed' : '');
        row.innerHTML =
            '<b>' + esc(event.worker || 'Atlas') + '</b> ' +
            '<span>' + esc(event.message || event.phase || '') + '</span>';
        feed.appendChild(row);
        feed.scrollTop = feed.scrollHeight;
    }

    function card(html, kind) {
        const cards = el('atlas-cards');
        if (!cards) return;
        const div = document.createElement('div');
        div.className = 'atlas-card' + (kind ? ' atlas-card-' + kind : '');
        div.innerHTML = html;
        cards.appendChild(div);
    }

    function setStatus(text) {
        const s = el('atlas-run-status');
        if (s) s.textContent = text;
        // Same status, mirrored to the Ask-the-Map panel so progress is
        // visible where the question was asked.
        if (text) {
            window.dispatchEvent(new CustomEvent('ecolens-atlas-progress',
                { detail: { message: String(text) } }));
        }
    }

    // Atlas (correctly) refuses to run without a named study area, and its
    // deterministic parser can't resolve "my area" / "near me" / "here".
    // EcoLens knows where the user is looking — so resolve the place on
    // this side and hand Atlas an explicit jurisdiction.
    async function resolveStudyArea(prompt) {
        // Substitute IN PLACE — a trailing "Study area: X" note still trips
        // Atlas's missing_study_area check when the sentence itself says
        // "my area" (verified 2026-07-28); "In Kamloops, BC show me…" runs.
        const vague = /\b(in my area|my area|near me|around me|around here|right here|here)\b/i;
        const m = prompt.match(vague);
        if (!m) return prompt;
        try {
            // "MY area" means the reader, not the camera: prefer the same
            // IP-derived home the map opens on (map-core caches it), and
            // only fall back to wherever the map happens to be panned.
            let c = null;
            try {
                const home = JSON.parse(localStorage.getItem('ecolens-home-view') || 'null');
                if (home && Array.isArray(home.center)) {
                    c = { lng: home.center[0], lat: home.center[1] };
                }
            } catch (e) { /* fall through to map center */ }
            if (!c) c = window.ecoMap && window.ecoMap.getCenter();
            if (!c) return prompt;
            const resp = await fetch(
                'https://nominatim.openstreetmap.org/reverse?format=jsonv2' +
                `&lat=${c.lat.toFixed(4)}&lon=${c.lng.toFixed(4)}&zoom=8&accept-language=en`,
                { headers: { 'Accept': 'application/json' } });
            const j = await resp.json();
            const a = j.address || {};
            const place = [a.city || a.town || a.county || a.municipality,
                a.state, a.country].filter(Boolean).join(', ');
            if (!place) return prompt;
            lastResolvedArea = place; // boundary can be fed before pass 1
            setStatus(`Study area resolved from the map: ${place}`);
            const replacement = /near|around/i.test(m[1]) ? `near ${place}` : `in ${place}`;
            return prompt.replace(vague, replacement);
        } catch (e) {
            return prompt; // Atlas will ask its own clarification
        }
    }

    let lastQuestion = '';
    let bcCauses = null; // BC Wildfire Service per-fire cause data, when fetched

    /**
     * What the engine actually reported for the current plan. The evidence
     * agent streams one `insights` event ({observed, hypotheses, cautions})
     * and repeats it on the final result: `observed` are measured
     * correlations, `hypotheses` are research leads. When both are empty and
     * no finding was built, the run has nothing to say — and the answer card
     * must not pretend otherwise.
     */
    let runTally = { correlations: 0, leads: 0, reported: false };

    function resetTally() {
        runTally = { correlations: 0, leads: 0, reported: false };
    }

    function tallyInsights(insights) {
        if (!insights || typeof insights !== 'object') return;
        runTally.correlations = Array.isArray(insights.observed) ? insights.observed.length : 0;
        runTally.leads = Array.isArray(insights.hypotheses) ? insights.hypotheses.length
            : Array.isArray(insights.leads) ? insights.leads.length : 0;
        runTally.reported = true;
    }

    // Belt and braces: the evidence agent also says it in words.
    const TALLY_RE = /Reported (\d+) measured correlations? and (\d+) research leads?/i;

    function tallyWorkerMessage(message) {
        if (runTally.reported) return;
        const m = TALLY_RE.exec(message || '');
        if (!m) return;
        runTally.correlations = Number(m[1]) || 0;
        runTally.leads = Number(m[2]) || 0;
        runTally.reported = true;
    }

    // "Worst / most active / hottest right now" — an intensity question, which
    // area burned cannot answer. Distinct from "biggest", which it can.
    const ACTIVITY_RE =
        /most active|worst|hottest|burning hardest|intens|right now|currently|which fire|what fire|priority|dangerous|severe/i;

    /**
     * The dataset that turns "what's causing wildfires" from a limitation
     * into an answer: BC Wildfire Service per-fire cause investigations
     * (lightning / person / undetermined), public ArcGIS service, no key.
     * Only meaningful when the study area is in British Columbia.
     */
    async function fetchBcFireCauses() {
        if (bcCauses) return bcCauses;
        const url = 'https://services6.arcgis.com/ubm4tcTYICKBpist/arcgis/rest/services/' +
            'BCWS_ActiveFires_PublicView/FeatureServer/0/query?where=1%3D1' +
            '&outFields=FIRE_NUMBER,FIRE_CAUSE,FIRE_STATUS,CURRENT_SIZE,IGNITION_DATE,' +
            'GEOGRAPHIC_DESCRIPTION,FIRE_URL&f=geojson';
        const resp = await fetch(url, { signal: AbortSignal.timeout(20000) });
        const fc = await resp.json();
        if (!fc || !fc.features || !fc.features.length) throw new Error('no BCWS features');
        bcCauses = fc;
        return fc;
    }

    async function feedBcCauses(planId) {
        if (!/british columbia/i.test(lastResolvedArea || '')) return 0;
        const key = planId + ':bccauses';
        if (fedKeys.has(key)) return 0;
        try {
            const fc = await fetchBcFireCauses();
            fedKeys.add(key);
            await uploadLayer('bc_wildfire_service_fire_causes', fc, planId);
            card('<b>EcoLens supplied cause evidence.</b><span>Attached the BC Wildfire ' +
                'Service per-fire cause investigations — ' + fc.features.length.toLocaleString() +
                ' fires this season, each with an investigated cause (lightning / person / ' +
                'undetermined). Source: BC Wildfire Service public feature service.</span>', 'done');
            return 1;
        } catch (e) {
            console.warn('[AtlasBridge] BCWS cause feed failed:', e.message);
            return 0;
        }
    }

    /**
     * Joins EcoLens's live satellite layer to the province's fire records:
     * how much energy is each recorded fire actually radiating right now?
     *
     * Area burned is cumulative — it counts ground that went cold weeks ago.
     * Fire radiative power is instantaneous. Ranking by one does not rank by
     * the other, and only the join can show that.
     *
     * Attribution is nearest-EDGE, not nearest-centre: a fire is approximated
     * as a circle of its published area plus a tolerance, because fires are
     * published as ignition points and a large fire's active flank can sit
     * tens of km from where it started. A 5 km tolerance leaves ~half the
     * detections falsely unattributed; swept 5→50 km the figure collapses,
     * which is how we know the tolerance — not the data — was driving it.
     */
    const FIRE_EDGE_TOLERANCE_KM = 15;

    function haversineKm(lo1, la1, lo2, la2) {
        const R = 6371, rad = Math.PI / 180;
        const p1 = la1 * rad, p2 = la2 * rad;
        const dp = p2 - p1, dl = (lo2 - lo1) * rad;
        const a = Math.sin(dp / 2) ** 2 +
            Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
        return 2 * R * Math.asin(Math.sqrt(a));
    }

    let fireActivity = null; // { ranked, geojson, matched, unmatched, totalFrp }

    async function computeFireActivity() {
        if (fireActivity) return fireActivity;
        const fires = await fetchBcFireCauses();

        // The live detections — from the map if loaded, else fetch them.
        let src = window.ecoMap && window.ecoMap.getSource('fires-source');
        let det = src && src._data;
        if ((!det || !det.features || !det.features.length) &&
            window.DataFetchers && window.DataFetchers.fetchActiveFires) {
            det = await window.DataFetchers.fetchActiveFires(null, 2);
        }
        if (!det || !det.features || !det.features.length) {
            throw new Error('no detections loaded');
        }

        // Fires carry geometry; derive each one's reach and a bbox to prefilter
        // 145k global detections down to the ones that could possibly match.
        const recs = [];
        let minX = 180, minY = 90, maxX = -180, maxY = -90;
        for (const f of fires.features) {
            if (!f.geometry || f.geometry.type !== 'Point') continue;
            const [x, y] = f.geometry.coordinates;
            if (!isFinite(x) || !isFinite(y)) continue;
            const p = f.properties || {};
            const ha = Number(p.CURRENT_SIZE) || 0;
            const reach = (ha > 0 ? Math.sqrt((ha / 100) / Math.PI) : 0) +
                FIRE_EDGE_TOLERANCE_KM;
            recs.push({ f, x, y, ha, reach, active: (p.FIRE_STATUS || '') !== 'Out',
                det: 0, frp: 0 });
            const pad = reach / 80; // ~deg, generous
            minX = Math.min(minX, x - pad); maxX = Math.max(maxX, x + pad);
            minY = Math.min(minY, y - pad); maxY = Math.max(maxY, y + pad);
        }
        if (!recs.length) throw new Error('no fire geometry');

        // Clip to the study area before matching. Without this, a fire near
        // the border becomes the nearest record for heat burning in the next
        // province and absorbs it — one 500 ha fire picked up 942 MW that way.
        const sb = await fetchStudyGeometry().catch(() => null);
        const near = [];
        let clipped = 0;
        for (const d of det.features) {
            if (!d.geometry || d.geometry.type !== 'Point') continue;
            const [x, y] = d.geometry.coordinates;
            if (x < minX || x > maxX || y < minY || y > maxY) continue;
            if (sb && !insideBoundary(x, y, sb.rings)) { clipped++; continue; }
            near.push([x, y, Number(d.properties && d.properties.frp) || 0]);
        }

        let matched = 0, unmatchedFrp = 0, totalFrp = 0;
        for (const [x, y, frp] of near) {
            totalFrp += frp;
            let best = null, bestEdge = Infinity;
            for (const r of recs) {
                if (Math.abs(r.x - x) > 4 || Math.abs(r.y - y) > 4) continue;
                const edge = haversineKm(x, y, r.x, r.y) - r.reach;
                if (edge <= 0 && edge < bestEdge) { bestEdge = edge; best = r; }
            }
            if (best) { best.det++; best.frp += frp; matched++; }
            else unmatchedFrp += frp;
        }

        const active = recs.filter(r => r.active);
        const byArea = [...active].sort((a, b) => b.ha - a.ha);
        const byHeat = [...active].sort((a, b) => b.frp - a.frp);
        byArea.forEach((r, i) => { r.rankArea = i + 1; });
        byHeat.forEach((r, i) => { r.rankHeat = i + 1; });

        const geojson = {
            type: 'FeatureCollection',
            features: active.map(r => ({
                type: 'Feature',
                geometry: r.f.geometry,
                properties: {
                    ...r.f.properties,
                    detections_48h: r.det,
                    frp_48h_mw: Math.round(r.frp * 10) / 10,
                    rank_by_area: r.rankArea,
                    rank_by_heat: r.rankHeat,
                    rank_shift: r.rankArea - r.rankHeat,
                },
            })),
        };

        fireActivity = {
            ranked: byHeat, byArea, geojson,
            matched, near: near.length, clipped, boundaryUsed: !!sb,
            unmatchedPct: near.length ? (near.length - matched) * 100 / near.length : 0,
            unmatchedFrpPct: totalFrp ? unmatchedFrp * 100 / totalFrp : 0,
            radiating: active.filter(r => r.det > 0).length,
            activeCount: active.length,
            totalFrp: byHeat.reduce((s, r) => s + r.frp, 0),
        };
        return fireActivity;
    }

    async function feedFireActivity(planId) {
        if (!/british columbia/i.test(lastResolvedArea || '')) return 0;
        const key = planId + ':fireactivity';
        if (fedKeys.has(key)) return 0;
        try {
            const a = await computeFireActivity();
            fedKeys.add(key);
            await uploadLayer('bc_fire_activity_satellite_join', a.geojson, planId);
            card('<b>EcoLens joined its own layers.</b><span>Matched ' +
                a.matched.toLocaleString() + ' of ' + a.near.toLocaleString() +
                ' satellite detections inside the study area to BC\'s fire records by ' +
                'nearest edge, giving every fire a measured radiative power for the last ' +
                '48 hours alongside its published area. ' +
                (a.boundaryUsed
                    ? a.clipped.toLocaleString() + ' detections outside the boundary were ' +
                      'excluded so border fires do not absorb another province\'s heat. '
                    : 'No study-area boundary was available, so detections were not clipped — ' +
                      'fires near the border may absorb heat from outside it. ') +
                a.unmatchedPct.toFixed(1) + '% of in-area detections matched no recorded fire.' +
                '</span>', 'done');
            return 1;
        } catch (e) {
            console.warn('[AtlasBridge] fire activity join failed:', e.message);
            return 0;
        }
    }

    /**
     * Ask Atlas a question. The question goes over as the question and
     * nothing else: the resolved jurisdiction travels in `study_area` and
     * the live map figures in `context`. Atlas compiles ONLY the question
     * into its evidence contract — appending "124 detections within 150 km"
     * to the sentence used to turn those figures into fake variables and
     * flip the goal to "accessibility" because of the word "nearest".
     *
     * @param {string} prompt   the reader's question, verbatim
     * @param {{studyArea?: string, context?: string}} [options]
     */
    async function ask(prompt, options) {
        if (!healthy || busy || !prompt || !prompt.trim()) return;
        const opts = options || {};
        busy = true;
        currentPlan = null;
        lastQuestion = prompt.trim();
        showAtlasTab();
        prompt = await resolveStudyArea(prompt.trim());
        // Ask-the-Map's geocode wins; "my area" resolution or an earlier
        // run's Place Resolver fills in otherwise.
        const studyArea = (opts.studyArea && String(opts.studyArea).trim()) || lastResolvedArea || null;
        if (studyArea) setStudyArea(studyArea);
        const mapContext = (opts.context && String(opts.context).trim()) || null;
        const feed = el('atlas-feed');
        const cards = el('atlas-cards');
        const planBox = el('atlas-plan');
        if (feed) feed.innerHTML = '';
        if (cards) cards.innerHTML = '';
        if (planBox) planBox.innerHTML = '';
        setStatus('Understanding the question…');
        try {
            const body = { prompt };
            if (studyArea) body.study_area = studyArea;
            if (mapContext) body.context = mapContext;
            const resp = await fetch(base() + '/api/run', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            });
            await readStream(resp, (event) => {
                if (event.type === 'worker') feedRow(event);
                if (event.type === 'map_view') applyMapView(event);
                if (event.type === 'plan') renderPlan(event.plan);
            });
            if (currentPlan && currentPlan.auto_execute) {
                await execute();
            }
        } catch (e) {
            setStatus('');
            card('<b>Atlas could not run this.</b><span>' + esc(e.message) + '</span>', 'gap');
        } finally {
            busy = false;
        }
    }

    function renderPlan(plan) {
        currentPlan = plan;
        const planBox = el('atlas-plan');
        if (!planBox) return;
        const blocked = Array.isArray(plan.blockers) && plan.blockers.length > 0;
        const sources = (plan.sources || plan.datasets || [])
            .slice(0, 4)
            .map(s => esc(s.name || s.title || s)).join(' · ');
        setStatus('');
        planBox.innerHTML =
            '<div class="atlas-plan-title">Proposed analysis' +
            (plan.executor ? ' <span>(' + esc(plan.executor) + ')</span>' : '') + '</div>' +
            '<div class="atlas-plan-body">' + esc(plan.summary || plan.question || '') + '</div>' +
            (sources ? '<div class="atlas-plan-sources">' + sources + '</div>' : '') +
            (blocked
                ? '<div class="atlas-plan-blocked">Needs clarification: ' +
                  esc(plan.blockers.map(b => b.message || b).join('; ')) + '</div>'
                : '<div class="atlas-plan-auto">Running — asking the question is the approval.</div>');
        // Asking IS approving: the reader typed the question; making them
        // click "Approve & run" was a second signature on the same cheque.
        // Blocked plans (missing clarification) still stop and say why.
        if (!blocked && !plan.execution_blocked && busy !== 'executing') {
            setTimeout(() => execute(), 50);
        }
    }

    // ------------------------------------------------------------------
    // EcoLens feeds Atlas. Atlas is the analyst; EcoLens holds the live
    // observatory. Every hazard layer in this tab is available to a plan
    // as declared, provenance-carrying evidence — attached up front when
    // the question mentions the hazard, and again as a rescue if a run
    // still pauses at a matching data gap.
    // ------------------------------------------------------------------
    const EVIDENCE_SOURCES = [
        // Name carries "wildfire" so Atlas's role-matcher can bind the
        // upload to the wildfire evidence slot (and skip its catalogue
        // sweep for it).
        { sourceId: 'fires-source', name: 'ecolens_wildfire_detections_nasa_firms',
          label: 'live NASA FIRMS fire detections (last 7 days)',
          re: /wild.?fire|\bfires?\b|firms|burn|smoke/i },
        { sourceId: 'earthquakes-source', name: 'ecolens_live_usgs_earthquakes',
          label: 'live USGS earthquakes', re: /earth.?quake|seismic|tremor|magnitude/i },
        { sourceId: 'floods-source', name: 'ecolens_live_noaa_flood_gauges',
          label: 'NOAA flood gauges (US)', re: /flood|river gauge|inundat/i },
        { sourceId: 'airquality-source', name: 'ecolens_live_air_quality_stations',
          label: 'live air-quality stations (PM2.5)',
          re: /air.?quality|pm2|aqi|smoke|particulate|caus|driver|factor/i },
        { sourceId: 'volcanoes-source', name: 'ecolens_volcano_catalogue',
          label: 'volcano catalogue with alert levels', re: /volcan|erupt|ash/i },
        { sourceId: 'drought-source', name: 'ecolens_drought_zones',
          label: 'USDM drought zones (US)',
          re: /drought|dry condition|caus|driver|factor/i },
        { sourceId: 'hotspots-source', name: 'ecolens_fire_cluster_hexes',
          label: 'statistically significant fire clusters (Gi*)', re: /cluster|hot.?spot|significan/i },
    ];
    const fedKeys = new Set(); // "<planId>:<sourceId>" — feed each once
    let lastResolvedArea = null; // from the run's own Place Resolver events

    /**
     * The boundary rescue: runs starve on the "common analysis geography"
     * slot when no catalogue hosts the study area's admin polygon (Metro
     * Vancouver, most regional districts). OpenStreetMap has every admin
     * boundary — fetch the resolved area's polygon from Nominatim and
     * attach it as declared evidence.
     */
    let studyBoundary = null; // { geom, hit } for the resolved area, cached

    async function fetchStudyGeometry() {
        if (studyBoundary !== null) return studyBoundary;
        if (!lastResolvedArea) return null;
        const resp = await fetch(
            'https://nominatim.openstreetmap.org/search?format=json&limit=1' +
            '&polygon_geojson=1&q=' + encodeURIComponent(lastResolvedArea),
            { headers: { 'Accept': 'application/json' } });
        const results = await resp.json();
        const hit = results && results[0];
        const geom = hit && hit.geojson;
        if (!geom || (geom.type !== 'Polygon' && geom.type !== 'MultiPolygon')) return null;
        studyBoundary = { geom, hit, rings: buildRings(geom) };
        return studyBoundary;
    }

    /** Flatten a (Multi)Polygon into bbox-indexed rings for fast containment. */
    function buildRings(geom) {
        const polys = geom.type === 'MultiPolygon' ? geom.coordinates : [geom.coordinates];
        return polys.map(p => {
            const outer = p[0];
            let x0 = 180, y0 = 90, x1 = -180, y1 = -90;
            for (const c of outer) {
                if (c[0] < x0) x0 = c[0]; if (c[0] > x1) x1 = c[0];
                if (c[1] < y0) y0 = c[1]; if (c[1] > y1) y1 = c[1];
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

    function insideBoundary(x, y, rings) {
        for (const r of rings) {
            if (x < r.x0 || x > r.x1 || y < r.y0 || y > r.y1) continue;
            if (ringContains(x, y, r.poly[0]) &&
                !r.poly.slice(1).some(h => ringContains(x, y, h))) return true;
        }
        return false;
    }

    async function feedBoundary(planId) {
        if (!lastResolvedArea) return 0;
        const key = planId + ':boundary';
        if (fedKeys.has(key)) return 0;
        try {
            const sb = await fetchStudyGeometry();
            if (!sb) return 0;
            const geom = sb.geom, hit = sb.hit;
            fedKeys.add(key);
            await uploadLayer('ecolens_study_area_boundary', {
                type: 'FeatureCollection',
                features: [{
                    type: 'Feature',
                    geometry: geom,
                    properties: {
                        name: hit.display_name || lastResolvedArea,
                        area_id: hit.osm_type + '/' + hit.osm_id,
                        source: 'OpenStreetMap administrative boundary via Nominatim',
                    },
                }],
            }, planId);
            card('<b>EcoLens supplied the study-area boundary.</b><span>Fetched the ' +
                'OpenStreetMap administrative polygon for ' + esc(lastResolvedArea) +
                ' and attached it as the analysis geography.</span>', 'done');
            return 1;
        } catch (e) {
            console.warn('[AtlasBridge] boundary feed failed:', e.message);
            return 0;
        }
    }

    async function feedEvidence(matchText, planId, reason) {
        let fed = 0;
        for (const ev of EVIDENCE_SOURCES) {
            if (!ev.re.test(matchText)) continue;
            const key = planId + ':' + ev.sourceId;
            if (fedKeys.has(key)) continue;
            const src = window.ecoMap && window.ecoMap.getSource(ev.sourceId);
            let fc = src && src._data;
            // Fires are the flagship: if the map hasn't loaded them yet
            // (fresh tab, layer toggled off), fetch them right now rather
            // than silently skipping the attach.
            if ((!fc || !fc.features || !fc.features.length) &&
                ev.sourceId === 'fires-source' &&
                window.DataFetchers && window.DataFetchers.fetchActiveFires) {
                try {
                    setStatus('Fetching the live fire layer to hand to Atlas…');
                    fc = await window.DataFetchers.fetchActiveFires(null, 7);
                } catch (e) { fc = null; }
            }
            if (!fc || !fc.features || !fc.features.length) {
                feedRow({ worker: 'EcoLens Bridge', phase: 'Evidence',
                    message: 'No loaded data for "' + ev.label + '" — skipped.' });
                continue;
            }
            let features = fc.features;
            if (features.length > 200000) {
                features = [...features]
                    .sort((a, b) => (b.properties?.frp || 0) - (a.properties?.frp || 0))
                    .slice(0, 200000);
            }
            try {
                fedKeys.add(key);
                await uploadLayer(ev.name, { type: 'FeatureCollection', features }, planId);
                fed++;
                card('<b>EcoLens supplied evidence' + (reason ? ' (' + reason + ')' : '') +
                    '.</b><span>Attached its ' + esc(ev.label) + ' — ' +
                    features.length.toLocaleString() + ' features, with source provenance.</span>',
                    'done');
            } catch (e) {
                console.warn('[AtlasBridge] evidence feed failed:', ev.name, e.message);
            }
        }
        return fed;
    }

    async function execute() {
        if (!currentPlan || !currentPlan.id || busy === 'executing') return;
        if (currentPlan.__started) return; // auto-run + button can't double-fire
        currentPlan.__started = true;
        resetTally(); // one plan, one tally — both passes report into it
        busy = 'executing';
        setStatus('Agents are working — layers stream in as they finish…');
        try {
            // Proactive: hand Atlas every EcoLens layer the question is
            // about BEFORE it burns time searching catalogues for data
            // that's already loaded in this tab — INCLUDING the study-area
            // boundary when we already resolved one. A second execution
            // pass costs a full 3-minute catalogue sweep; front-loading
            // the evidence makes one pass the normal case.
            const askText = (currentPlan.prompt || currentPlan.research_question || '') +
                ' ' + JSON.stringify(currentPlan.intent || '');
            await feedEvidence(askText, currentPlan.id, 'question matches loaded data');
            if (lastResolvedArea) await feedBoundary(currentPlan.id);
            // Causal fire question in BC → the cause data exists; attach it.
            if (/caus|why\b|driver|factor|reason/i.test(lastQuestion) &&
                /fire/i.test(lastQuestion)) {
                await feedBcCauses(currentPlan.id);
            }
            // "Which fire is worst / most active right now" is a different
            // question from "which is biggest", and only the satellite join
            // answers it. Attach the joined layer so the run can use it.
            if (ACTIVITY_RE.test(lastQuestion) && /fire/i.test(lastQuestion)) {
                await feedFireActivity(currentPlan.id);
            }

            for (let pass = 1; pass <= 2; pass++) {
                let gapText = '';
                let finalStatus = null;
                const resp = await fetch(base() + '/api/execute', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ plan_id: currentPlan.id }),
                });
                let layerQueue = Promise.resolve();
                await readStream(resp, (event) => {
                    if (event.type === 'worker') {
                        feedRow(event);
                        tallyWorkerMessage(event.message);
                        const m = /^Resolved (?:study area|public-source jurisdiction): (.+)$/
                            .exec(event.message || '');
                        if (m) lastResolvedArea = m[1].trim();
                    }
                    if (event.type === 'map_view') applyMapView(event);
                    if (event.type === 'layer') {
                        layerQueue = layerQueue
                            .then(() => addAtlasLayer(event.layer))
                            .catch(e => console.warn('[AtlasBridge] layer:', e));
                    }
                    if (event.type === 'data_gap') {
                        renderDataGap(event.data_gap);
                        gapText += ' ' + JSON.stringify(event.data_gap || '');
                    }
                    if (event.type === 'insights') {
                        tallyInsights(event.insights);
                        renderInsights(event.insights);
                    }
                    if (event.type === 'result') {
                        if (event.result && event.result.insights) tallyInsights(event.result.insights);
                        renderResult(event.result);
                    }
                    if (event.type === 'error') throw new Error(event.message);
                    if (event.type === 'done') {
                        finalStatus = event.status;
                        setStatus(event.status === 'complete'
                            ? 'Analysis complete — every layer carries its evidence trail.'
                            : 'Atlas is waiting for more data (see its workbench).');
                    }
                });
                await layerQueue;

                // Paused hungry for data EcoLens can supply? Hazard layers
                // from the live map, the analysis geography from OSM —
                // feed whatever matches and give the run its second wind.
                if (pass === 1 && gapText && finalStatus !== 'complete') {
                    setStatus('Atlas hit a data gap — checking EcoLens’s own layers…');
                    let fed = await feedEvidence(gapText, currentPlan.id, 'filling a data gap');
                    const boundaryGap = lastResolvedArea &&
                        (gapText.includes(lastResolvedArea) ||
                         /bounda|geograph|district|jurisdiction|analysis geography/i.test(gapText));
                    if (boundaryGap) fed += await feedBoundary(currentPlan.id);
                    if (fed > 0) continue;
                    setStatus('Atlas is waiting for more data (see its workbench).');
                }
                break;
            }
        } catch (e) {
            setStatus('');
            card('<b>Analysis failed.</b><span>' + esc(e.message) + '</span>', 'gap');
        } finally {
            busy = false;
        }
    }

    function applyMapView(event) {
        if (!window.ecoMap || !Array.isArray(event.bounds) || event.bounds.length !== 4) return;
        const [w, s, e, n] = event.bounds;
        window.ecoMap.fitBounds([[w, s], [e, n]], { padding: 80, maxZoom: 11, duration: 900 });
    }

    // ---------- Result layers (Atlas layer contract → MapLibre) ----------

    async function addAtlasLayer(layer) {
        if (!window.ecoMap) return;
        const map = window.ecoMap;
        const url = /^https?:/i.test(layer.url) ? layer.url : base() + layer.url;
        const resp = await fetch(url, { cache: 'no-store' });
        if (!resp.ok) throw new Error('Could not load ' + layer.name);
        const data = await resp.json();
        const id = 'atlas-' + layer.id;

        if (map.getLayer(id)) map.removeLayer(id);
        if (map.getSource(id)) map.removeSource(id);
        map.addSource(id, { type: 'geojson', data });

        const minimum = layer.minimum != null ? layer.minimum : 0;
        const maximum = layer.maximum != null ? layer.maximum : 100;
        const mid = (minimum + maximum) / 2;
        const metricColor = layer.property
            ? ['interpolate', ['linear'],
                ['coalesce', ['get', layer.property], minimum],
                minimum, '#d9eee6', mid, '#efbd69', maximum, '#d95f3c']
            : (layer.color || '#176b50');
        const visibility = layer.default_visible === false ? 'none' : 'visible';

        if (layer.kind === 'polygon') {
            map.addLayer({
                id, type: 'fill', source: id, layout: { visibility },
                paint: {
                    'fill-color': metricColor,
                    'fill-opacity': layer.opacity != null ? layer.opacity : 0.73,
                    'fill-outline-color': '#315f50',
                },
            });
        } else if (layer.kind === 'line') {
            map.addLayer({
                id, type: 'line', source: id, layout: { visibility },
                paint: {
                    'line-color': layer.color || '#176b50',
                    'line-width': layer.line_width || 3,
                    'line-opacity': layer.opacity != null ? layer.opacity : 0.85,
                },
            });
        } else {
            map.addLayer({
                id, type: 'circle', source: id, layout: { visibility },
                paint: {
                    'circle-radius': ['interpolate', ['linear'], ['zoom'], 2, 5, 8, 10],
                    'circle-color': metricColor,
                    'circle-opacity': layer.opacity != null ? layer.opacity : 0.95,
                    'circle-stroke-color': '#ffffff',
                    'circle-stroke-width': 1.4,
                },
            });
        }

        map.on('click', id, (e) => {
            if (!e.features || !e.features.length) return;
            const rows = Object.entries(e.features[0].properties || {})
                .filter(([, v]) => v !== null && v !== '')
                .slice(0, 8)
                .map(([k, v]) => '<b>' + esc(k.replace(/_/g, ' ')) + '</b>: ' + esc(v))
                .join('<br>');
            new maplibregl.Popup().setLngLat(e.lngLat)
                .setHTML(rows + '<br><small>Atlas evidence layer</small>')
                .addTo(map);
        });

        atlasLayers.set(id, { layer, data });
        renderLayerRow(id, layer, visibility !== 'none');
        installStyleHook();
    }

    function renderLayerRow(id, layer, visible) {
        const list = el('atlas-layers');
        if (!list) return;
        let row = list.querySelector('[data-atlas-layer="' + id + '"]');
        if (!row) {
            row = document.createElement('button');
            row.dataset.atlasLayer = id;
            row.className = 'atlas-layer-row';
            list.appendChild(row);
        }
        row.classList.toggle('active', visible);
        row.innerHTML = '<i></i><span>' + esc(layer.name) + '</span>' +
            '<b>' + (visible ? 'Visible' : 'Hidden') + '</b>';
        row.onclick = () => {
            const map = window.ecoMap;
            if (!map || !map.getLayer(id)) return;
            const isVisible = map.getLayoutProperty(id, 'visibility') !== 'none';
            map.setLayoutProperty(id, 'visibility', isVisible ? 'none' : 'visible');
            row.classList.toggle('active', !isVisible);
            row.querySelector('b').textContent = isVisible ? 'Hidden' : 'Visible';
        };
    }

    // Basemap switches rebuild the style; MapCore restores its own LAYER_DEFS
    // sources but knows nothing about Atlas layers — re-add ours afterwards.
    function installStyleHook() {
        if (styleHookInstalled || !window.ecoMap) return;
        styleHookInstalled = true;
        window.ecoMap.on('style.load', () => {
            setTimeout(() => {
                for (const [id, entry] of atlasLayers) {
                    const stillVisible = true;
                    addAtlasLayer(entry.layer).catch(() => {});
                    void id; void stillVisible;
                }
            }, 600);
        });
    }

    // ---------- Result cards ----------

    function renderDataGap(gap) {
        if (!gap) return;
        card('<b>Data gap (reported honestly).</b><span>' +
            esc(gap.message || gap.summary || JSON.stringify(gap).slice(0, 200)) +
            '</span>', 'gap');
    }

    function renderInsights(insights) {
        if (!insights) return;
        const observed = insights.observed || [];
        for (const item of observed.slice(0, 3)) {
            const r = Number(item.pearson_r);
            card('<b>' + (r >= 0 ? '+' : '') + r.toFixed(2) + ' Pearson r</b>' +
                '<span>' + esc(item.x_label || item.x) + ' vs ' + esc(item.y_label || item.y) +
                ' — ' + esc(item.strength || '') + ' ' + esc(item.direction || '') +
                ' exploratory association (n=' + esc(item.n) + ')</span>', 'insight');
        }
        for (const caution of (insights.cautions || []).slice(0, 2)) {
            card('<b>Caution.</b><span>' + esc(caution) + '</span>', 'gap');
        }
    }

    /**
     * THE ANSWER — a plain-language verdict at the top of the cards.
     * Composed only from numbers the run actually produced (the derived
     * area summary + result statistics) plus honest statements of what
     * the evidence cannot support. Nothing here is generated or guessed.
     */
    function renderAnswer(result) {
        const cards = el('atlas-cards');
        if (!cards) return;
        const q = lastQuestion || '';
        const causal = /caus|why\b|driver|factor|reason/i.test(q);
        const place = lastResolvedArea ||
            (result.statistics && result.statistics.study_area) || 'the study area';

        // Real in-area numbers live in the derived summary layer's polygon
        let summaryProps = null;
        for (const entry of atlasLayers.values()) {
            if (/derived area summary/i.test(entry.layer.name || '')) {
                summaryProps = (entry.data && entry.data.features &&
                    entry.data.features[0] && entry.data.features[0].properties) || null;
            }
        }
        const countRows = summaryProps
            ? Object.entries(summaryProps)
                .filter(([k, v]) => typeof v === 'number' && /count|features|total|n_/i.test(k))
                .slice(0, 5)
                .map(([k, v]) => '<div class="atlas-answer-row"><span>' +
                    esc(k.replace(/_/g, ' ').replace(/ecolens /i, '')) + '</span><b>' +
                    Number(v).toLocaleString() + '</b></div>')
                .join('')
            : '';

        const observed = ((result.insights || {}).observed || []).length;

        // The finding is decided first so the verdict can be honest about a
        // run that produced nothing: no finding, no correlation, no lead.
        let finding = null;
        try { finding = buildFinding(result); } catch (e) { finding = null; }
        const paused = !!result.data_gap || result.status === 'needs_data';
        const failed = result.status === 'failed';
        const emptyRun = !finding && runTally.correlations === 0 && runTally.leads === 0;

        let verdict;
        let substantive = false; // a verdict built from evidence, not the template
        if (ACTIVITY_RE.test(q) && /fire/i.test(q) && fireActivity) {
            // Ranked by measured energy, not by the cumulative scar.
            substantive = true;
            const a = fireActivity;
            const top = a.ranked.filter(r => r.frp > 0).slice(0, 3);
            const biggest = a.byArea[0];
            const nm = (r) => esc(((r.f.properties || {}).GEOGRAPHIC_DESCRIPTION || '')
                .trim() || (r.f.properties || {}).FIRE_NUMBER || 'unnamed');
            const mw = (r) => Math.round(r.frp).toLocaleString();
            const ha = (r) => Math.round(r.ha).toLocaleString();

            if (!top.length) {
                verdict = '<p>None of the ' + a.activeCount + ' fires BC lists as active ' +
                    'registered detectable heat in the last 48 hours of satellite passes. ' +
                    'That is a real reading, but a soft one — cloud, smoke and overpass ' +
                    'timing all suppress detections.</p>';
            } else {
                const lead = top[0];
                verdict =
                    '<p>Ranked by the energy they are actually radiating right now — not by ' +
                    'area burned — the most active fire in ' + esc(place) + ' is <b>' +
                    nm(lead) + '</b>, putting out <b>' + mw(lead) + ' MW</b> across ' +
                    lead.det.toLocaleString() + ' satellite detections in 48 hours. It is ' +
                    'only <b>#' + lead.rankArea + '</b> by size.</p>' +
                    '<p>' + top.map(r => nm(r) + ' — ' + mw(r) + ' MW (' + ha(r) +
                        ' ha, #' + r.rankArea + ' by area, #' + r.rankHeat + ' by heat)')
                        .join('<br>') + '</p>' +
                    (biggest && biggest.rankHeat > 1
                        ? '<p>BC\'s largest fire, <b>' + nm(biggest) + '</b> at ' +
                          ha(biggest) + ' ha, ranks <b>#' + biggest.rankHeat +
                          '</b> by heat — area burned is cumulative and counts ground that ' +
                          'went cold weeks ago.</p>'
                        : '') +
                    '<p>Of ' + a.activeCount + ' fires listed as active, <b>' + a.radiating +
                    '</b> radiated detectable heat in this window. That is a floor, not a ' +
                    'headcount — cloud and overpass timing hide fires.</p>' +
                    '<p style="opacity:0.7;">Radiative power measured by VIIRS aboard ' +
                    'NOAA-20 (NASA FIRMS), clipped to the study area and matched to BC ' +
                    'Wildfire Service fire records by nearest edge (fire area as a circle ' +
                    'plus ' + FIRE_EDGE_TOLERANCE_KM + ' km, since fires are published as ' +
                    'ignition points). ' + a.unmatchedPct.toFixed(1) + '% of in-area ' +
                    'detections matched no recorded fire.</p>';
            }
        } else if (causal && bcCauses) {
            // The real answer, from investigated causes — not from vibes.
            substantive = true;
            const tally = { Lightning: 0, Person: 0, Other: 0 };
            let active = 0;
            const activeTally = { Lightning: 0, Person: 0, Other: 0 };
            for (const f of bcCauses.features) {
                const c = f.properties.FIRE_CAUSE === 'Lightning' ? 'Lightning'
                    : f.properties.FIRE_CAUSE === 'Person' ? 'Person' : 'Other';
                tally[c]++;
                if ((f.properties.FIRE_STATUS || '') !== 'Out') { active++; activeTally[c]++; }
            }
            const total = bcCauses.features.length;
            const pct = (n) => total ? Math.round(n * 100 / total) : 0;
            verdict =
                '<p>Per-fire cause investigations answer this directly. Of the <b>' +
                total.toLocaleString() + ' wildfires</b> BC has recorded this season: <b>' +
                tally.Lightning.toLocaleString() + ' lightning-caused (' + pct(tally.Lightning) +
                '%)</b>, <b>' + tally.Person.toLocaleString() + ' human-caused (' +
                pct(tally.Person) + '%)</b>, ' + tally.Other.toLocaleString() +
                ' still undetermined.</p>' +
                '<p>Among the <b>' + active.toLocaleString() + ' fires currently active</b>: ' +
                activeTally.Lightning.toLocaleString() + ' lightning, ' +
                activeTally.Person.toLocaleString() + ' human, ' +
                activeTally.Other.toLocaleString() + ' undetermined.</p>' +
                '<p style="opacity:0.7;">Source: BC Wildfire Service per-fire investigations ' +
                '(live feature service). The satellite detections show where these burn; the ' +
                'investigations say why they started.</p>';
        } else if (causal) {
            substantive = true; // a stated limitation is an answer, not a template
            verdict =
                '<p>The attached observations show <b>where and how intensely</b> fires are ' +
                'burning in ' + esc(place) + ' — they cannot establish <b>why</b>. The ' +
                'correlation screen found ' + observed + ' measured relationship' +
                (observed === 1 ? '' : 's') + ' in this evidence, and detection points carry ' +
                'no ignition records.</p>' +
                '<p><b>What would answer it:</b> per-fire cause investigations — for BC, the ' +
                'BC Wildfire Service publishes lightning-vs-human cause per fire. Attach or ' +
                'ask for that layer and this question becomes answerable with evidence.</p>';
        } else if (emptyRun) {
            // No finding, zero measured correlations, zero leads. Say exactly
            // that — the template below would dress nothing up as an answer.
            verdict = paused
                ? '<p>Atlas paused for more data and has found no measurable ' +
                  'relationships in the attached evidence so far.</p>'
                : failed
                ? '<p>Atlas stopped before completing the investigation, so there is ' +
                  'no answer to report.</p>'
                : '<p>Atlas ran the full investigation and found no measurable ' +
                  'relationships in the attached evidence.</p>';
        } else {
            verdict = '<p>Mapped from the attached evidence over ' + esc(place) +
                '. Toggle the layers below to read the pattern; every figure traces to a source.</p>';
        }

        const div = document.createElement('div');
        div.className = 'atlas-card atlas-card-answer';
        div.innerHTML =
            '<div class="atlas-answer-kicker">The answer · from evidence only</div>' +
            verdict + countRows;
        cards.insertBefore(div, cards.firstChild);

        // Report back to whoever asked. Ask-the-Map listens for this so the
        // answer appears in the panel the question was typed into, instead of
        // stranding the reader between two surfaces. `hasSubstance` is false
        // when the run produced no finding AND the engine reported zero
        // correlations and zero leads — the mirror then shows one honest
        // line instead of a template card.
        const hasSubstance = !emptyRun || substantive;
        window.dispatchEvent(new CustomEvent('ecolens-atlas-answer', {
            detail: {
                html: verdict + countRows,
                hasFinding: !!finding,
                finding,
                hasSubstance,
                paused,
                failed,
                reported: runTally.reported,
                correlations: runTally.correlations,
                leads: runTally.leads,
            },
        }));
    }

    function announceProgress(message) {
        if (!message) return;
        window.dispatchEvent(new CustomEvent('ecolens-atlas-progress',
            { detail: { message: String(message) } }));
    }

    /**
     * The escalation payload. The map screen answers what the map can show;
     * anything that needs a ranked comparison, provenance and stated limits
     * belongs on Insights, laid out as a proper finding. This builds that
     * finding from the run's own numbers and hands it across the bridge.
     *
     * Returns null when the run produced nothing worth escalating — Insights
     * should never receive an empty card.
     */
    function buildFinding(result) {
        const q = lastQuestion || '';
        const place = lastResolvedArea ||
            (result && result.statistics && result.statistics.study_area) || 'the study area';
        const nowIso = new Date().toISOString();

        if (ACTIVITY_RE.test(q) && /fire/i.test(q) && fireActivity) {
            const a = fireActivity;
            const rows = a.ranked.filter(r => r.frp > 0).slice(0, 8).map(r => {
                const p = r.f.properties || {};
                return {
                    label: (p.GEOGRAPHIC_DESCRIPTION || '').trim() || p.FIRE_NUMBER || 'unnamed',
                    sublabel: p.FIRE_NUMBER || '',
                    primary: r.ha,
                    secondary: r.frp,
                    primaryText: Math.round(r.ha).toLocaleString() + ' ha',
                    secondaryText: Math.round(r.frp).toLocaleString() + ' MW',
                    rankPrimary: r.rankArea,
                    rankSecondary: r.rankHeat,
                };
            });
            if (!rows.length) return null;
            const biggest = a.byArea[0];
            const bp = (biggest && biggest.f.properties) || {};
            const bname = (bp.GEOGRAPHIC_DESCRIPTION || '').trim() || bp.FIRE_NUMBER || 'the largest fire';
            const lead = rows[0];

            return {
                id: 'fire-activity-' + nowIso,
                kicker: 'SATELLITE JOIN · ' + String(place).toUpperCase(),
                headline: biggest && biggest.rankHeat > 1
                    ? bname + ' is the largest fire here, and ranks #' +
                      biggest.rankHeat + ' by the heat it is actually radiating.'
                    : lead.label + ' is radiating more energy than any other fire here.',
                standfirst: 'Area burned is cumulative — it counts ground that went cold ' +
                    'weeks ago. Radiative power is measured tonight. Ranking by one does ' +
                    'not rank by the other.',
                question: q,
                primaryLabel: 'Area',
                secondaryLabel: 'Heat',
                rows,
                paragraphs: [
                    lead.label + ' is putting out ' + lead.secondaryText + ' across ' +
                    (a.ranked[0].det || 0).toLocaleString() + ' satellite detections in 48 ' +
                    'hours, from ' + lead.primaryText + ' — it ranks #' + lead.rankPrimary +
                    ' by size and #' + lead.rankSecondary + ' by heat.',
                    'Of ' + a.activeCount + ' fires listed as active, ' + a.radiating +
                    ' radiated detectable heat in this window. "Active" is a management ' +
                    'status; radiating heat is a physical measurement, and they are not ' +
                    'the same count.',
                ],
                readingTag: 'Reading — measured, not modelled',
                reading: 'A fire\'s size tells you what it has already done. Its radiative ' +
                    'power tells you what it is doing. These are different questions, and ' +
                    'the ranking that answers one does not answer the other.',
                provenance: [
                    'Detections: NASA FIRMS, VIIRS aboard NOAA-20, last 48 hours, clipped ' +
                        'to ' + place + '.',
                    'Fires: BC Wildfire Service public feature service — area, stage of ' +
                        'control and investigated cause as published.',
                    'Method: each detection matched to the nearest fire by edge distance ' +
                        '(published area as a circle plus ' + FIRE_EDGE_TOLERANCE_KM +
                        ' km, since fires are published as ignition points).',
                ],
                limitations: [
                    'A detection is a 375 m pixel, not a fire — one large fire produces ' +
                        'hundreds, a cloud-covered fire produces none.',
                    'Radiative power is a snapshot across two satellite passes, not total ' +
                        'energy released. A fire that ran hard between overpasses reads low.',
                    a.unmatchedPct.toFixed(1) + '% of in-area detections matched no recorded ' +
                        'fire and are excluded from every per-fire figure above.',
                ],
                generated: nowIso,
            };
        }

        if (/caus|why\b|driver|factor|reason/i.test(q) && bcCauses) {
            const t = { Lightning: 0, Person: 0, Other: 0 };
            const act = { Lightning: 0, Person: 0, Other: 0 };
            let active = 0;
            for (const f of bcCauses.features) {
                const c = f.properties.FIRE_CAUSE === 'Lightning' ? 'Lightning'
                    : f.properties.FIRE_CAUSE === 'Person' ? 'Person' : 'Other';
                t[c]++;
                if ((f.properties.FIRE_STATUS || '') !== 'Out') { active++; act[c]++; }
            }
            const total = bcCauses.features.length;
            if (!total) return null;
            const mk = (k, lbl) => ({
                label: lbl, sublabel: '',
                primary: t[k], secondary: act[k],
                primaryText: t[k].toLocaleString() + ' fires',
                secondaryText: act[k].toLocaleString() + ' burning',
                rankPrimary: null, rankSecondary: null,
            });
            return {
                id: 'fire-causes-' + nowIso,
                kicker: 'CAUSE INVESTIGATION · ' + String(place).toUpperCase(),
                headline: 'Lightning started ' + Math.round(t.Lightning * 100 / total) +
                    '% of the fires here, and is behind ' +
                    (active ? Math.round(act.Lightning * 100 / active) : 0) +
                    '% of the ones still burning.',
                standfirst: 'Every recorded fire carries an investigated cause. Joining ' +
                    'cause to outcome shows which ignitions get held and which escape.',
                question: q,
                primaryLabel: 'Started',
                secondaryLabel: 'Burning',
                rows: [mk('Lightning', 'Lightning'), mk('Person', 'Human-caused'),
                       mk('Other', 'Undetermined')],
                paragraphs: [
                    'Of ' + total.toLocaleString() + ' fires recorded this season: ' +
                    t.Lightning.toLocaleString() + ' lightning-caused, ' +
                    t.Person.toLocaleString() + ' human-caused, ' + t.Other.toLocaleString() +
                    ' still undetermined. Among the ' + active.toLocaleString() +
                    ' still burning: ' + act.Lightning.toLocaleString() + ' lightning, ' +
                    act.Person.toLocaleString() + ' human, ' + act.Other.toLocaleString() +
                    ' undetermined.',
                ],
                readingTag: 'Reading — hypothesis, not finding',
                reading: 'Human-caused fires start where people already are, near roads ' +
                    'and towns, where they are found early and reached quickly. Lightning ' +
                    'strikes remote terrain. Detection and access time is a plausible ' +
                    'explanation, but neither dataset measures either one — so this stays ' +
                    'a hypothesis the numbers are consistent with, not one they establish.',
                provenance: [
                    'BC Wildfire Service per-fire cause investigations, live public ' +
                        'feature service. Causes are revised as investigations conclude.',
                ],
                limitations: [
                    'Undetermined fires will move into other categories over time, so ' +
                        'both shares shift as the season closes.',
                    'Cause is assigned per fire regardless of size — this counts ignitions, ' +
                        'not hectares.',
                ],
                generated: nowIso,
            };
        }
        return null;
    }

    function escalateToInsights(result, { navigate } = {}) {
        let finding = null;
        try { finding = buildFinding(result); } catch (e) {
            console.warn('[AtlasBridge] finding build failed:', e.message);
        }
        if (!finding) return false;
        try {
            if (window.EcoLensBridge && window.EcoLensBridge.sendToFlutter) {
                window.EcoLensBridge.sendToFlutter('atlasFinding',
                    { finding, navigate: navigate !== false });
            }
        } catch (e) {
            console.warn('[AtlasBridge] escalation send failed:', e.message);
            return false;
        }
        lastFinding = finding;
        return true;
    }

    let lastFinding = null;

    /**
     * The hand-off. The answer card gives the verdict in two sentences; the
     * full ranked comparison, provenance and limitations are laid out on
     * Insights. One button, stated plainly, no badge or nag.
     */
    function offerInsightsJump() {
        const answer = document.querySelector('.atlas-card-answer');
        if (!answer || answer.querySelector('.atlas-jump')) return;
        const btn = document.createElement('button');
        btn.className = 'atlas-jump';
        btn.type = 'button';
        btn.textContent = 'Read the full finding in Environmental News →';
        btn.onclick = () => {
            if (window.EcoLensBridge && window.EcoLensBridge.sendToFlutter) {
                window.EcoLensBridge.sendToFlutter('atlasFinding',
                    { finding: lastFinding, navigate: true });
            }
        };
        answer.appendChild(btn);
    }

    function renderResult(result) {
        if (!result) return;
        renderAnswer(result);
        // The map answered what it can show; the full comparison, provenance
        // and limitations belong on Insights. Escalate without stealing the
        // screen — the answer card offers the jump.
        const escalated = escalateToInsights(result, { navigate: false });
        if (escalated) offerInsightsJump();
        const trace = (result.downloads || []).find(d => /agent run trace/i.test(d.name || ''));
        const gpkg = (result.downloads || []).find(d => /\.gpkg/i.test(d.url || ''));
        card('<b>' + esc(result.completion_message || 'Analysis complete.') + '</b>' +
            '<span class="atlas-downloads">' +
            (trace ? '<a href="' + esc(base() + trace.url) + '" target="_blank" rel="noopener">Audit trail</a>' : '') +
            (gpkg ? ' <a href="' + esc(base() + gpkg.url) + '" target="_blank" rel="noopener">GeoPackage</a>' : '') +
            '</span>', 'done');
    }

    // ---------- Init ----------

    /** Open the right panel on its Atlas tab (where the analyst lives). */
    function showAtlasTab() {
        if (window.ChromeShell && window.ChromeShell.toggleDrawer) {
            window.ChromeShell.toggleDrawer(true);
        }
        const tab = document.querySelector('.drawer-tab[data-tab="atlas"]');
        if (tab) tab.click();
    }

    async function init() {
        const section = el('atlas-section');
        const tab = el('drawer-tab-atlas');
        const ok = await checkHealth();
        if (section) section.style.display = ok ? '' : 'none';
        if (tab) tab.style.display = ok ? '' : 'none';
        if (!ok) {
            console.log('[AtlasBridge] Atlas offline — section hidden');
            return false;
        }
        const form = el('atlas-form');
        const input = el('atlas-prompt');
        if (form && input) {
            form.addEventListener('submit', (e) => {
                e.preventDefault();
                ask(input.value);
            });
        }
        // Version banner: if you can't see this row in the feed, the
        // browser is running a stale bridge — hard-refresh.
        const feed = el('atlas-feed');
        if (feed && !feed.textContent.includes('bridge g27')) {
            feedRow({ worker: 'EcoLens Bridge', phase: 'Ready',
                message: 'bridge g27 · evidence feeder + boundary + satellite/fire-record join active · engine: ' + base() });
        }
        // Give the first hotspot computation a moment, then peer-review it.
        setTimeout(verifyHotspots, 12000);
        console.log('[AtlasBridge] Connected to Atlas at ' + base());
        return true;
    }

    /**
     * Ask-the-Map has already geocoded the place before it hands the question
     * over. Without this, the bridge only learns the study area from Atlas's
     * own Place Resolver event — which arrives AFTER execute() has already
     * decided whether to attach the BC fire-activity join, so the join was
     * skipped and the answer fell back to the generic verdict even though
     * both sides had correctly resolved British Columbia.
     */
    function setStudyArea(name) {
        if (!name || typeof name !== 'string') return;
        const trimmed = name.trim();
        if (!trimmed) return;
        if (lastResolvedArea !== trimmed) {
            fireActivity = null; // different area → recompute the join
        }
        lastResolvedArea = trimmed;
    }

    return {
        init,
        checkHealth,
        ask,
        execute,
        uploadLayer,
        runTool,
        verifyHotspots,
        setStudyArea,
        isHealthy: () => healthy,
        getStudyArea: () => lastResolvedArea,
    };
})();

window.AtlasBridge = AtlasBridge;
