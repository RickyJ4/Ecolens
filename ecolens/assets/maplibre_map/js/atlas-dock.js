/**
 * Atlas dock — the conversation surface at the bottom of the map.
 *
 * One pipeline, one place. Ask-the-Map already answers from the live layers
 * and hands questions it cannot settle to the Atlas engine; it renders into
 * #atm-panel. This dock re-parents that panel into a transcript so each
 * answer stacks under the question that produced it, and adds a compact
 * stats line that counts what is inside the current view rather than the
 * planet (the old bar said "141,975 fires" while the reader looked at BC).
 *
 * Nothing here computes an answer. It moves DOM, counts features against
 * map.getBounds(), and calls AskTheMap.answer().
 */
(function () {
    'use strict';

    const SOURCES = [
        { key: 'fires',  label: 'fires',       source: 'fires-source',       color: '#C3402B' },
        { key: 'quakes', label: 'quakes',      source: 'earthquakes-source', color: '#8E1B12' },
        { key: 'floods', label: 'gauges',      source: 'floods-source',      color: '#2B5A73' },
        { key: 'aq',     label: 'AQ stations', source: 'airquality-source',  color: '#3E7A4C' },
        { key: 'volc',   label: 'volcanoes',   source: 'volcanoes-source',   color: '#B07D2B' },
    ];
    const MAX_TURNS = 12;

    const esc = (v) => String(v == null ? '' : v)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    const fmt = (n) => n.toLocaleString('en-US');

    let dock, stats, transcript, form, input, toggle, status;
    let open = false;
    let statsTimer = null;

    // ---------- in-view counts ----------

    function firstPoint(coords) {
        // Point -> [lng,lat]; Line/Polygon -> first vertex; anything deeper -> descend.
        let c = coords;
        while (Array.isArray(c) && Array.isArray(c[0])) c = c[0];
        return Array.isArray(c) && c.length >= 2 && typeof c[0] === 'number' ? c : null;
    }

    function countInView() {
        const map = window.ecoMap;
        if (!map || !map.getBounds) return null;
        const bounds = map.getBounds();
        const out = [];
        for (const s of SOURCES) {
            const src = map.getSource(s.source);
            const feats = src && src._data && src._data.features;
            if (!feats) continue;
            let n = 0;
            for (const f of feats) {
                const p = f && f.geometry && firstPoint(f.geometry.coordinates);
                if (p && bounds.contains(p)) n++;
            }
            out.push({ ...s, inView: n, total: feats.length });
        }
        return out;
    }

    function renderStats() {
        if (!stats) return;
        const rows = countInView();
        if (!rows || !rows.length) {
            stats.innerHTML = '<span class="dock-stats-label">In view</span><span class="dock-stat muted">layers loading…</span>';
            return;
        }
        stats.innerHTML =
            '<span class="dock-stats-label" title="Counted inside the current map view, from the loaded layers">In view</span>' +
            rows.map(r =>
                `<span class="dock-stat" title="${fmt(r.total)} loaded in total">` +
                `<i style="background:${r.color}"></i>${fmt(r.inView)} <em>${esc(r.label)}</em></span>`
            ).join('');
    }

    function scheduleStats() {
        clearTimeout(statsTimer);
        statsTimer = setTimeout(renderStats, 250);
    }

    // ---------- transcript ----------

    function setOpen(next) {
        open = !!next;
        transcript.hidden = !open;
        document.body.classList.toggle('dock-open', open);
        toggle.textContent = open ? '▾' : '▴';
        toggle.title = open ? 'Hide the conversation' : 'Show the conversation';
        if (open) transcript.scrollTop = transcript.scrollHeight;
    }

    /** Move the last answer out of the live panel into the history. */
    function archiveLiveAnswer() {
        const content = document.getElementById('atm-content');
        if (!content || !content.childNodes.length) return;
        const turn = document.createElement('div');
        turn.className = 'dock-turn answer';
        while (content.firstChild) turn.appendChild(content.firstChild);
        // Ids must not survive the move: the mirror dedupes on #atm-answer and
        // the live-progress hook writes to #atm-live-step.
        turn.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'));
        turn.querySelectorAll('button').forEach(b => { if (!b.classList.contains('atm-jump')) b.disabled = true; });
        const panel = document.getElementById('atm-panel');
        transcript.insertBefore(turn, panel || null);
        const turns = transcript.querySelectorAll('.dock-turn');
        for (let i = 0; i < turns.length - MAX_TURNS * 2; i++) turns[i].remove();
    }

    function addQuestion(text) {
        const q = document.createElement('div');
        q.className = 'dock-turn user';
        q.textContent = text;
        const panel = document.getElementById('atm-panel');
        transcript.insertBefore(q, panel || null);
    }

    function submit(text) {
        const q = (text || '').trim();
        if (!q || !window.AskTheMap || !window.AskTheMap.answer) return;
        archiveLiveAnswer();
        addQuestion(q);
        setOpen(true);
        input.value = '';
        window.AskTheMap.answer(q);
    }

    // ---------- engine status ----------

    function renderStatus() {
        if (!status) return;
        const up = !!(window.AtlasBridge && window.AtlasBridge.isHealthy && window.AtlasBridge.isHealthy());
        status.className = 'dock-status ' + (up ? 'up' : 'down');
        status.textContent = up ? 'Atlas online' : 'Atlas offline · map answers only';
        status.title = up
            ? 'Questions the map cannot settle go to the Atlas engine.'
            : 'The Atlas engine is not reachable; the map still answers from its live layers.';
    }

    // ---------- build ----------

    function build() {
        if (document.getElementById('atlas-dock')) return;
        dock = document.createElement('div');
        dock.id = 'atlas-dock';
        dock.innerHTML =
            '<div class="dock-stats" id="dock-stats"></div>' +
            '<div class="dock-transcript" id="dock-transcript" hidden></div>' +
            '<form class="dock-form" id="dock-form" autocomplete="off">' +
            '  <span class="dock-kicker">Ask</span>' +
            '  <input id="dock-input" type="text" ' +
            '    placeholder="Ask about what is on the map: which fires in BC are burning hardest right now?" />' +
            '  <span class="dock-status" id="dock-status"></span>' +
            '  <button type="submit" class="dock-go">Ask</button>' +
            '  <button type="button" class="dock-toggle" id="dock-toggle" title="Show the conversation">▴</button>' +
            '</form>';
        document.body.appendChild(dock);
        stats = dock.querySelector('#dock-stats');
        transcript = dock.querySelector('#dock-transcript');
        form = dock.querySelector('#dock-form');
        input = dock.querySelector('#dock-input');
        toggle = dock.querySelector('#dock-toggle');
        status = dock.querySelector('#dock-status');

        form.addEventListener('submit', (e) => { e.preventDefault(); submit(input.value); });
        toggle.addEventListener('click', () => setOpen(!open));
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && open && document.activeElement !== input) setOpen(false);
        });
        // Keep the newest content in view as answers stream in.
        new MutationObserver(() => { if (open) transcript.scrollTop = transcript.scrollHeight; })
            .observe(transcript, { childList: true, subtree: true, characterData: true });
    }

    /** Ask-the-Map injects its panel on init; adopt it once it exists. */
    function adoptPanel() {
        const panel = document.getElementById('atm-panel');
        if (!panel || panel.parentElement === transcript) return !!panel;
        transcript.appendChild(panel);
        const close = panel.querySelector('#atm-close');
        if (close) close.style.display = 'none';
        // The answer pipeline shows the panel itself; open the transcript with it.
        new MutationObserver(() => {
            if (panel.style.display === 'block' && !open) setOpen(true);
        }).observe(panel, { attributes: true, attributeFilter: ['style'] });
        return true;
    }

    function bindMap() {
        const map = window.ecoMap;
        if (!map || !map.on) return false;
        map.on('moveend', scheduleStats);
        map.on('sourcedata', (e) => { if (e && e.isSourceLoaded) scheduleStats(); });
        scheduleStats();
        return true;
    }

    function init() {
        build();
        let tries = 0;
        const tick = setInterval(() => {
            tries++;
            const a = adoptPanel();
            const b = bindMap();
            renderStatus();
            if ((a && b) || tries > 120) clearInterval(tick);
        }, 500);
        setInterval(renderStatus, 10000);
        setInterval(renderStats, 60000);
        console.log('[AtlasDock] Ready');
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();

    window.AtlasDock = { submit, setOpen, renderStats };
})();
