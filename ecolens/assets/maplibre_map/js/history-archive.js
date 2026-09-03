// ============================================================
// EcoLens History Archive — client for the daily hazard archive
// ("the map that remembers")
//
// Reads the public GCS archive written by the archive_hazards_daily
// Cloud Function:
//   {base}/index.json
//   {base}/{type}/daily/{YYYY}/{YYYY-MM-DD}.geojson
//   {base}/{type}/weekly/{YYYY}-W{WW}.geojson
//
// Day files are immutable, so IndexedDB-cached entries never revalidate.
// Per-day hex aggregates (tiny) are cached separately so 30-day baselines
// never require keeping 30 raw day files resident.
// ============================================================

const HistoryArchive = (function () {
    'use strict';

    const DEFAULT_BASE =
        'https://storage.googleapis.com/ecolens-archive-ecolens-ad854/archive/v1/';
    const DB_NAME = 'ecolens-archive';
    const DB_VERSION = 1;
    const BUDGET_BYTES = 150 * 1024 * 1024;   // LRU eviction threshold
    const MAX_INFLIGHT = 3;                    // getRange fetch throttle

    let db = null;
    let index = null;
    let indexFetchedAt = 0;
    let persistRequested = false;

    function baseUrl() {
        return window.ECOLENS_ARCHIVE_URL || DEFAULT_BASE;
    }

    // ---------- IndexedDB plumbing ----------

    function openDb() {
        if (db) return Promise.resolve(db);
        return new Promise((resolve, reject) => {
            const req = indexedDB.open(DB_NAME, DB_VERSION);
            req.onupgradeneeded = () => {
                const d = req.result;
                if (!d.objectStoreNames.contains('days')) {
                    d.createObjectStore('days');       // key: "{type}:{date}"
                }
                if (!d.objectStoreNames.contains('aggregates')) {
                    d.createObjectStore('aggregates'); // key: "{type}:{date}:{cellKm}"
                }
                if (!d.objectStoreNames.contains('meta')) {
                    d.createObjectStore('meta');
                }
            };
            req.onsuccess = () => { db = req.result; resolve(db); };
            req.onerror = () => reject(req.error);
        });
    }

    function idbGet(store, key) {
        return openDb().then(d => new Promise((resolve, reject) => {
            const req = d.transaction(store, 'readonly').objectStore(store).get(key);
            req.onsuccess = () => resolve(req.result);
            req.onerror = () => reject(req.error);
        })).catch(() => undefined); // cache failures degrade to network
    }

    function idbPut(store, key, value) {
        return openDb().then(d => new Promise((resolve, reject) => {
            const req = d.transaction(store, 'readwrite').objectStore(store).put(value, key);
            req.onsuccess = () => resolve();
            req.onerror = () => reject(req.error);
        })).catch(() => undefined);
    }

    function idbDelete(store, key) {
        return openDb().then(d => new Promise((resolve) => {
            const req = d.transaction(store, 'readwrite').objectStore(store).delete(key);
            req.onsuccess = () => resolve();
            req.onerror = () => resolve();
        })).catch(() => undefined);
    }

    function idbEntries(store) {
        return openDb().then(d => new Promise((resolve, reject) => {
            const out = [];
            const req = d.transaction(store, 'readonly').objectStore(store).openCursor();
            req.onsuccess = () => {
                const cursor = req.result;
                if (!cursor) { resolve(out); return; }
                out.push({ key: cursor.key, value: cursor.value });
                cursor.continue();
            };
            req.onerror = () => reject(req.error);
        })).catch(() => []);
    }

    async function evictIfNeeded() {
        try {
            if (navigator.storage && navigator.storage.estimate) {
                const est = await navigator.storage.estimate();
                // Only bother when we're actually pressuring the origin quota.
                if (est.usage && est.quota && est.usage < est.quota * 0.8 &&
                    est.usage < BUDGET_BYTES) return;
            }
            const entries = await idbEntries('days');
            let total = 0;
            for (const e of entries) total += (e.value && e.value.bytes) || 0;
            if (total <= BUDGET_BYTES) return;
            entries.sort((a, b) => (a.value.fetchedAt || 0) - (b.value.fetchedAt || 0));
            for (const e of entries) {
                if (total <= BUDGET_BYTES * 0.7) break;
                total -= (e.value && e.value.bytes) || 0;
                await idbDelete('days', e.key);
            }
        } catch (e) {
            console.warn('Archive eviction skipped:', e);
        }
    }

    // ---------- Index ----------

    async function getIndex(force) {
        const stale = Date.now() - indexFetchedAt > 5 * 60 * 1000;
        if (index && !force && !stale) return index;
        try {
            const resp = await fetch(baseUrl() + 'index.json', { cache: 'no-cache' });
            if (!resp.ok) throw new Error('HTTP ' + resp.status);
            index = await resp.json();
            indexFetchedAt = Date.now();
            idbPut('meta', 'index', index);
        } catch (e) {
            // Offline / not yet provisioned: last known index from IDB.
            const cached = await idbGet('meta', 'index');
            if (cached) { index = cached; indexFetchedAt = Date.now(); }
            else console.warn('Hazard archive unavailable:', e.message || e);
        }
        return index;
    }

    function dayEntry(type, dateISO) {
        const section = index && index.types && index.types[type];
        if (!section) return null;
        return (section.days || []).find(d => d.date === dateISO) || null;
    }

    // ---------- Day / range fetch ----------

    async function getDay(type, dateISO) {
        const key = type + ':' + dateISO;
        const cached = await idbGet('days', key);
        if (cached && cached.geojson) return cached.geojson;

        await getIndex();
        const entry = dayEntry(type, dateISO);
        // Fall back to the layout convention even if the index is missing
        // the entry (e.g. index fetch failed but the object exists).
        const path = entry ? entry.path
            : type + '/daily/' + dateISO.slice(0, 4) + '/' + dateISO + '.geojson';

        const resp = await fetch(baseUrl() + path);
        if (!resp.ok) {
            throw new Error('Archive day ' + type + '/' + dateISO + ': HTTP ' + resp.status);
        }
        const geojson = await resp.json();
        const bytes = (entry && entry.bytes) ||
            (resp.headers.get('content-length') | 0) || 1024 * 1024;
        idbPut('days', key, { geojson, fetchedAt: Date.now(), bytes })
            .then(evictIfNeeded);
        return geojson;
    }

    async function getRange(type, startISO, endISO) {
        await getIndex();
        const section = index && index.types && index.types[type];
        const dates = ((section && section.days) || [])
            .map(d => d.date)
            .filter(d => d >= startISO && d <= endISO);

        const results = new Map();
        let cursor = 0;
        async function worker() {
            while (cursor < dates.length) {
                const date = dates[cursor++];
                try {
                    results.set(date, await getDay(type, date));
                } catch (e) {
                    console.warn('Archive range miss', type, date, e.message || e);
                    results.set(date, null);
                }
            }
        }
        await Promise.all(
            Array.from({ length: Math.min(MAX_INFLIGHT, dates.length) }, worker)
        );
        // Ordered [{date, geojson}] with misses dropped.
        return dates
            .map(date => ({ date, geojson: results.get(date) }))
            .filter(r => r.geojson);
    }

    // ---------- Baselines (per-day hex aggregates) ----------

    async function getDayAggregate(type, dateISO, cellKm) {
        const key = type + ':' + dateISO + ':' + cellKm;
        const cached = await idbGet('aggregates', key);
        if (cached) return cached;
        if (!window.SpatialStats) {
            throw new Error('SpatialStats not loaded; cannot aggregate');
        }
        const fc = await getDay(type, dateISO);
        const cells = window.SpatialStats.hexBin(fc.features || [], { cellKm });
        const slim = {
            date: dateISO,
            cellKm,
            cells: cells.map(c => ({ q: c.q, r: c.r, count: c.count, sum: c.sum })),
        };
        idbPut('aggregates', key, slim);
        return slim;
    }

    // Per-day aggregate series for the trailing `days` archived days.
    // Missing/failed days are skipped — callers must check .length before
    // treating the series as a valid baseline.
    async function getBaseline(type, days, cellKm) {
        cellKm = cellKm || 100;
        const idx = await getIndex();
        const section = idx && idx.types && idx.types[type];
        if (!section || !(section.days || []).length) return [];
        const available = section.days.map(d => d.date).slice(-days);
        const out = [];
        for (const date of available) {
            try {
                out.push(await getDayAggregate(type, date, cellKm));
            } catch (e) {
                console.warn('Baseline day skipped', type, date, e.message || e);
            }
        }
        return out;
    }

    // ---------- Init ----------

    async function init() {
        if (!persistRequested && navigator.storage && navigator.storage.persist) {
            persistRequested = true;
            navigator.storage.persist().catch(() => {});
        }
        const idx = await getIndex();
        const badge = document.getElementById('archive-badge');
        if (badge) {
            const fires = idx && idx.types && idx.types.fires;
            const n = fires && fires.days ? fires.days.length : 0;
            badge.textContent = n > 0
                ? 'Archive: ' + n + ' day' + (n === 1 ? '' : 's') +
                  ' (' + fires.earliest + ' → ' + fires.latest + ')'
                : 'Archive: accruing…';
        }
        return idx;
    }

    function archiveDays(type) {
        const section = index && index.types && index.types[type || 'fires'];
        return (section && section.days) ? section.days.map(d => d.date) : [];
    }

    return {
        init,
        getIndex,
        getDay,
        getRange,
        getBaseline,
        getDayAggregate,
        archiveDays,
    };
})();

window.HistoryArchive = HistoryArchive;
