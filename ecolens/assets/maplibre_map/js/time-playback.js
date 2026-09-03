// ============================================================
// EcoLens TimePlayback — replay archived hazard days on the map
//
// "History mode": the time slider becomes a date scrubber across the
// hazard archive; play advances one real archived day per frame
// (data-driven — a frame renders only when its day file has loaded).
// The existing live window-sweep (FilterControls) is untouched.
//
// While active, window.EcoLensHistoryMode = true and the live
// auto-refresh must not clobber fires-source (checked in MapCore /
// EventIntelligence refresh paths). On exit the pre-history live data
// snapshot is restored and refresh resumes.
// ============================================================

const TimePlayback = (function () {
    'use strict';

    let active = false;
    let playing = false;
    let dates = [];
    let cursor = 0;
    let liveSnapshot = null;    // fires FC before history mode entered
    let playTimer = null;
    const MIN_FRAME_MS = 600;
    const PREFETCH_AHEAD = 3;

    const el = (id) => document.getElementById(id);

    // ---------- UI ----------

    function injectUI() {
        if (el('hist-playback')) return;
        const style = document.createElement('style');
        style.textContent = `
            #hist-toggle-btn { margin-left: 8px; }
            #hist-playback { position: fixed; bottom: 96px; left: 50%; transform: translateX(-50%);
                z-index: 220; display: none; align-items: center; gap: 10px;
                background: var(--paper, #F2EFE4);
                border: 1px solid var(--ink, #232019); border-radius: 3px; padding: 10px 14px;
                box-shadow: 4px 4px 0 rgba(35,32,25,0.14); font-family: system-ui, sans-serif;
                width: min(520px, calc(100vw - 40px)); }
            #hist-playback.active { display: flex; }
            #hist-play { width: 32px; height: 32px; border-radius: 50%;
                border: 1px solid var(--ink, #232019);
                background: var(--paper-raised, #FBF9F1); color: var(--ink, #232019); cursor: pointer;
                font-size: 13px; flex-shrink: 0; }
            #hist-play:hover { background: var(--paper-deep, #EAE6D6); }
            #hist-scrubber { flex: 1; height: 3px; appearance: none;
                background: var(--rule, #D9D2BF); border-radius: 2px; outline: none; }
            #hist-scrubber::-webkit-slider-thumb { appearance: none; width: 13px; height: 13px;
                border-radius: 50%; background: var(--survey, #2B5A73); cursor: pointer;
                border: 2px solid var(--paper, #F2EFE4); }
            #hist-date { font-size: 11.5px; font-weight: 700; color: var(--ink, #232019);
                font-family: var(--mono-data, monospace);
                font-variant-numeric: tabular-nums; min-width: 86px; text-align: center; }
            #hist-exit { background: none; border: 1px solid var(--ink-faint, #8C8574);
                color: var(--ink-soft, #5B564A); border-radius: 3px; padding: 4px 10px; font-size: 11px;
                cursor: pointer; flex-shrink: 0; }
            #hist-exit:hover { color: var(--paper, #F2EFE4); background: var(--ink, #232019); }
            #hist-badge { font-size: 8.5px; font-weight: 800; letter-spacing: 1.2px;
                color: var(--fire-deep, #8E1B12); text-transform: uppercase; flex-shrink: 0; }
        `;
        document.head.appendChild(style);

        const bar = document.createElement('div');
        bar.id = 'hist-playback';
        bar.innerHTML =
            '<span id="hist-badge">Archive</span>' +
            '<button id="hist-play" type="button" title="Play day by day">▶</button>' +
            '<input id="hist-scrubber" type="range" min="0" max="0" value="0" step="1"/>' +
            '<span id="hist-date">—</span>' +
            '<button id="hist-exit" type="button">Exit history</button>';
        document.body.appendChild(bar);

        el('hist-play').addEventListener('click', () => (playing ? pause() : play()));
        el('hist-exit').addEventListener('click', exit);
        el('hist-scrubber').addEventListener('input', (e) => {
            pause();
            showFrame(Number(e.target.value));
        });

        // "History" toggle next to the time presets (legacy bar or shell ticker)
        const presetHost = document.querySelector('#time-slider-container .time-window-btn') ||
            document.querySelector('#tick-time .time-window-btn');
        if (presetHost && presetHost.parentElement && !el('hist-toggle-btn')) {
            const btn = document.createElement('button');
            btn.id = 'hist-toggle-btn';
            btn.className = 'time-window-btn';
            btn.type = 'button';
            btn.textContent = 'History';
            btn.title = 'Replay archived days (EcoLens hazard archive)';
            btn.addEventListener('click', enter);
            presetHost.parentElement.appendChild(btn);
        }
    }

    // ---------- Mode transitions ----------

    async function enter() {
        if (active || !window.HistoryArchive) return;
        const archiveDates = window.HistoryArchive.archiveDays('fires');
        if (!archiveDates.length) {
            alert('The hazard archive has no days yet — it accrues one per day once ' +
                'the archive function is deployed.');
            return;
        }
        active = true;
        window.EcoLensHistoryMode = true;
        dates = archiveDates;
        cursor = dates.length - 1;

        // Snapshot live fires so exit can restore without a refetch
        const src = window.ecoMap && window.ecoMap.getSource('fires-source');
        liveSnapshot = (src && src._data) || null;

        // Pause live refresh so it can't overwrite archive frames
        if (window.DataFetchers && window.DataFetchers.stopAutoRefresh) {
            window.DataFetchers.stopAutoRefresh('fires');
        }
        if (window.FilterControls && window.FilterControls.stopTimeAnimation) {
            window.FilterControls.stopTimeAnimation();
        }

        const scrub = el('hist-scrubber');
        scrub.max = String(dates.length - 1);
        scrub.value = String(cursor);
        el('hist-playback').classList.add('active');
        const histBtn = el('hist-toggle-btn');
        if (histBtn) histBtn.classList.add('active');

        // Widen the fire time filter — archive frames carry old acq_dates
        if (window.HazardLayers) window.HazardLayers.applyFilter('fires', null);
        await showFrame(cursor);
    }

    function exit() {
        if (!active) return;
        pause();
        active = false;
        window.EcoLensHistoryMode = false;
        el('hist-playback').classList.remove('active');
        const histBtn = el('hist-toggle-btn');
        if (histBtn) histBtn.classList.remove('active');

        if (liveSnapshot && window.HazardLayers) {
            window.HazardLayers.updateSource('fires', liveSnapshot);
        }
        // Restore the live window filter + refresh cadence
        const hours = Number(window.EcoLensTimeWindowHours) || 168;
        if (window.HazardLayers) window.HazardLayers.applyTimeWindow(hours);
        if (window.DataFetchers && window.DataFetchers.startAutoRefresh &&
            window.DataFetchers.fetchActiveFires) {
            window.DataFetchers.startAutoRefresh('fires',
                () => window.DataFetchers.fetchActiveFires(null, 2),
                5 * 60 * 1000,
                (data) => window.HazardLayers.updateSource('fires', data));
        }
    }

    // ---------- Frames ----------

    async function showFrame(i) {
        if (!active || i < 0 || i >= dates.length) return;
        cursor = i;
        const date = dates[i];
        el('hist-date').textContent = date;
        el('hist-scrubber').value = String(i);
        try {
            const fc = await window.HistoryArchive.getDay('fires', date);
            if (!active) return; // user exited while loading
            window.HazardLayers.updateSource('fires', fc);
            // Prefetch upcoming frames so playback never stalls visibly
            for (let ahead = 1; ahead <= PREFETCH_AHEAD; ahead++) {
                const next = dates[i + ahead];
                if (next) window.HistoryArchive.getDay('fires', next).catch(() => {});
            }
        } catch (e) {
            console.warn('[TimePlayback] frame', date, e.message || e);
            el('hist-date').textContent = date + ' (missing)';
        }
    }

    function play() {
        if (!active) return;
        playing = true;
        el('hist-play').textContent = '❚❚';
        if (cursor >= dates.length - 1) cursor = 0;
        const step = async () => {
            if (!playing || !active) return;
            const started = Date.now();
            await showFrame(cursor);
            if (cursor >= dates.length - 1) { pause(); return; }
            cursor += 1;
            const wait = Math.max(0, MIN_FRAME_MS - (Date.now() - started));
            playTimer = setTimeout(step, wait);
        };
        step();
    }

    function pause() {
        playing = false;
        clearTimeout(playTimer);
        const btn = el('hist-play');
        if (btn) btn.textContent = '▶';
    }

    function init() {
        injectUI();
        console.log('[TimePlayback] Ready');
    }

    /** Enter history mode (if possible) and start playing immediately. */
    async function enterAndPlay() {
        if (!active) await enter();
        if (active && !playing) play();
        return active;
    }

    return { init, enter, exit, play, pause, enterAndPlay, isActive: () => active };
})();

window.TimePlayback = TimePlayback;
