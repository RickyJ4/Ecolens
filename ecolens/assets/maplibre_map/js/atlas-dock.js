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

    let dock, stats, transcript, form, input, toggle, status, timeTab;
    const BASE_HINT = 'Ask about what is on the map: which fires in BC are burning hardest right now?';
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

    /** The in-view counts ride in the input's placeholder: one bar, no
     *  second row. The hover title carries the loaded totals. */
    function renderStats() {
        if (!input) return;
        const rows = countInView();
        if (!rows || !rows.length) { input.placeholder = BASE_HINT; return; }
        const inView = rows.filter(r => r.inView > 0).map(r => `${fmt(r.inView)} ${r.label}`);
        input.placeholder = inView.length
            ? `Ask about what is on the map · in view: ${inView.join(', ')}`
            : BASE_HINT;
        input.title = 'Counted inside the current map view: ' +
            rows.map(r => `${fmt(r.inView)} ${r.label} (${fmt(r.total)} loaded)`).join(' · ');
    }

    // ---------- time window tab ----------
    // The slider (day / week / month / year) sits behind a tab on the bar so
    // the bottom of the map is the Ask bar alone until the window matters.

    function timeLabel() {
        const el = document.getElementById('time-current');
        return (el && el.textContent.trim()) || 'Time window';
    }

    function renderTimeTab() {
        if (!timeTab) return;
        const open = document.body.classList.contains('time-open');
        timeTab.textContent = (open ? '▾ ' : '▴ ') + timeLabel();
        timeTab.classList.toggle('open', open);
        timeTab.title = open ? 'Hide the event time window' : 'Event time window: ' + timeLabel() + '. Click to change it.';
    }

    function setTimeOpen(next) {
        document.body.classList.toggle('time-open', !!next);
        renderTimeTab();
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
        turn.className = 'dock-turn answer atm-scope';
        while (content.firstChild) turn.appendChild(content.firstChild);
        // Ids must not survive the move: the mirror dedupes on #atm-answer and
        // the live-progress hook writes to #atm-live-step.
        turn.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'));
        // Progress chrome belongs to the live turn only; story and jump
        // buttons keep working from the history.
        turn.querySelectorAll('.atm-live, .atm-deep').forEach(el => el.remove());
        turn.querySelectorAll('button').forEach(b => {
            if (!b.classList.contains('atm-jump') && !b.classList.contains('atm-story')) b.disabled = true;
        });
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
            '<div class="dock-transcript" id="dock-transcript" hidden></div>' +
            '<form class="dock-form" id="dock-form" autocomplete="off">' +
            '  <button type="button" class="dock-time" id="dock-time">▴ Last 7 days</button>' +
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
        timeTab = dock.querySelector('#dock-time');

        form.addEventListener('submit', (e) => { e.preventDefault(); submit(input.value); });
        toggle.addEventListener('click', () => setOpen(!open));
        timeTab.addEventListener('click', () => setTimeOpen(!document.body.classList.contains('time-open')));
        document.addEventListener('input', (e) => { if (e.target && e.target.id === 'time-slider') renderTimeTab(); });
        document.addEventListener('click', (e) => {
            if (e.target && e.target.closest && e.target.closest('.time-window-btn')) setTimeout(renderTimeTab, 0);
        });
        renderTimeTab();
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
        setInterval(() => { renderStatus(); renderTimeTab(); }, 10000);
        setInterval(renderStats, 60000);
        console.log('[AtlasDock] Ready');
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();

    window.AtlasDock = { submit, setOpen, renderStats, setTimeOpen };
})();
