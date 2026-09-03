// ============================================================
// EcoLens AnomalyDesk — "what is statistically unusual today"
//
// Compares the live fire pattern against a rolling baseline built from
// the hazard archive (per-day 100 km hex aggregates, cached in
// IndexedDB). Departures are z-scores of today's daily detection rate
// per hex against that hex's 30-day mean/σ — the front page is chosen
// by statistics, not by an editor or an engagement metric.
//
// Honesty rules: no baseline (archive too young) → say so, never
// improvise one; a clean day renders "within normal range", never
// silence.
// ============================================================

const AnomalyDesk = (function () {
    'use strict';

    const CELL_KM = 100;
    const BASELINE_DAYS = 30;
    const MIN_BASELINE_DAYS = 7;
    const Z_THRESHOLD = 2;
    const MIN_COUNT = 10;

    let lastReport = null;

    const esc = (v) => String(v == null ? '' : v)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    // Compact reference list for honest "near X" labels — nearest match
    // wins; beyond 400 km we fall back to plain coordinates.
    const REGIONS = [
        // Global coverage. The list was Americas-heavy, so the three places
        // the planet actually burns hardest — Siberia, the Congo/Angola belt
        // and northern Australia — reported as raw coordinates. A worldwide
        // product has to be able to name where the fire is.
        // --- Russia / Siberia
        // Gap-fill driven by real archived data: the top statistical departures
        // on 2026-08-27 included hexes in interior Evenkia and the US Great
        // Basin that had no centroid within 400 km and so reported as bare
        // coordinates. These are the places that actually burn.
        [64.28, 100.22, 'Tura, Evenkia'], [69.35, 88.19, 'Norilsk, Russia'],
        [60.34, 102.28, 'Vanavara, Evenkia'], [58.45, 92.17, 'Yeniseysk, Russia'],
        [56.15, 101.63, 'Bratsk, Russia'], [52.03, 113.50, 'Chita, Russia'],
        [51.83, 107.58, 'Ulan-Ude, Russia'], [51.72, 94.45, 'Kyzyl, Tuva'],
        [60.94, 76.55, 'Nizhnevartovsk, Russia'], [61.00, 69.02, 'Khanty-Mansiysk, Russia'],
        [66.53, 66.61, 'Salekhard, Yamal'], [67.50, 64.03, 'Vorkuta, Russia'],
        [64.73, 177.51, 'Anadyr, Chukotka'], [53.04, 158.65, 'Petropavlovsk-Kamchatsky'],
        [48.48, 135.08, 'Khabarovsk, Russia'], [53.20, 63.62, 'Kostanay, Kazakhstan'],
        [49.80, 73.10, 'Karaganda, Kazakhstan'],
        // --- US interior west / Great Basin
        [40.97, -117.74, 'Winnemucca, Nevada'], [40.83, -115.76, 'Elko, Nevada'],
        [39.53, -119.81, 'Reno, Nevada'], [36.17, -115.14, 'Las Vegas, US'],
        [43.62, -116.20, 'Boise, Idaho'], [46.87, -113.99, 'Missoula, Montana'],
        [45.78, -108.50, 'Billings, Montana'], [44.06, -121.31, 'Bend, Oregon'],
        [40.59, -122.39, 'Redding, California'], [40.76, -111.89, 'Salt Lake City, US'],
        [33.45, -112.07, 'Phoenix, US'], [31.76, -106.49, 'El Paso, US'],
        [44.37, -100.35, 'Pierre, South Dakota'], [46.81, -100.78, 'Bismarck, North Dakota'],
        [62.03, 129.73, 'Yakutsk, Russia'], [66.42, 112.40, 'Mirny, Sakha'],
        [64.56, 143.23, 'Ust-Nera, Sakha'], [61.25, 73.40, 'Surgut, Russia'],
        [58.60, 125.40, 'Aldan, Sakha'], [56.01, 92.87, 'Krasnoyarsk, Russia'],
        [67.47, 86.57, 'Igarka, Krasnoyarsk'], [65.28, 82.47, 'Tazovsky, Yamal'],
        [52.29, 104.30, 'Irkutsk, Russia'], [55.03, 82.92, 'Novosibirsk, Russia'],
        [53.75, 87.12, 'Novokuznetsk, Russia'], [50.28, 127.53, 'Blagoveshchensk, Russia'],
        [59.57, 150.80, 'Magadan, Russia'], [43.12, 131.89, 'Vladivostok, Russia'],
        [55.75, 37.62, 'Moscow, Russia'],
        // --- Africa
        [-4.44, 15.27, 'Kinshasa, DR Congo'], [-11.66, 27.48, 'Kolwezi, DR Congo'],
        [-6.16, 23.60, 'Kananga, DR Congo'], [-8.90, 13.24, 'Luanda, Angola'],
        [-12.58, 17.48, 'Huambo, Angola'], [-14.66, 17.69, 'Menongue, Angola'],
        [-15.42, 28.28, 'Lusaka, Zambia'], [-17.83, 31.05, 'Harare, Zimbabwe'],
        [-19.05, 17.08, 'Grootfontein, Namibia'], [-25.75, 28.19, 'Pretoria, South Africa'],
        [-33.92, 18.42, 'Cape Town, South Africa'], [-18.88, 47.51, 'Antananarivo, Madagascar'],
        [-6.79, 39.21, 'Dar es Salaam, Tanzania'], [-1.29, 36.82, 'Nairobi, Kenya'],
        [9.02, 38.75, 'Addis Ababa, Ethiopia'], [15.59, 32.53, 'Khartoum, Sudan'],
        [12.65, -8.00, 'Bamako, Mali'], [12.37, -1.53, 'Ouagadougou, Burkina Faso'],
        [9.06, 7.49, 'Abuja, Nigeria'], [5.60, -0.19, 'Accra, Ghana'],
        [14.72, -17.47, 'Dakar, Senegal'], [30.04, 31.24, 'Cairo, Egypt'],
        [36.81, 10.18, 'Tunis, Tunisia'], [33.57, -7.59, 'Casablanca, Morocco'],
        // --- Asia
        [39.90, 116.41, 'Beijing, China'], [31.23, 121.47, 'Shanghai, China'],
        [23.13, 113.26, 'Guangzhou, China'], [30.57, 104.07, 'Chengdu, China'],
        [43.83, 87.62, 'Urumqi, China'], [28.61, 77.21, 'Delhi, India'],
        [19.08, 72.88, 'Mumbai, India'], [22.57, 88.36, 'Kolkata, India'],
        [23.81, 90.41, 'Dhaka, Bangladesh'], [27.72, 85.32, 'Kathmandu, Nepal'],
        [24.86, 67.01, 'Karachi, Pakistan'], [13.76, 100.50, 'Bangkok, Thailand'],
        [21.03, 105.85, 'Hanoi, Vietnam'], [-6.21, 106.85, 'Jakarta, Indonesia'],
        [-2.99, 104.76, 'Palembang, Sumatra'], [-0.02, 109.34, 'Pontianak, Borneo'],
        [-2.20, 113.92, 'Palangkaraya, Borneo'], [14.60, 120.98, 'Manila, Philippines'],
        [35.68, 139.69, 'Tokyo, Japan'], [37.57, 126.98, 'Seoul, South Korea'],
        [47.89, 106.91, 'Ulaanbaatar, Mongolia'], [41.01, 28.98, 'Istanbul, Turkey'],
        [35.69, 51.39, 'Tehran, Iran'], [24.71, 46.68, 'Riyadh, Saudi Arabia'],
        [43.24, 76.89, 'Almaty, Kazakhstan'],
        // --- South America
        [-3.12, -60.02, 'Manaus, Brazil'], [-15.60, -56.10, 'Cuiaba, Brazil'],
        [-23.55, -46.63, 'Sao Paulo, Brazil'], [-8.05, -34.88, 'Recife, Brazil'],
        [-16.50, -68.15, 'La Paz, Bolivia'], [-17.78, -63.18, 'Santa Cruz, Bolivia'],
        [-25.26, -57.58, 'Asuncion, Paraguay'], [-34.60, -58.38, 'Buenos Aires, Argentina'],
        [-33.45, -70.67, 'Santiago, Chile'], [-12.05, -77.04, 'Lima, Peru'],
        [4.71, -74.07, 'Bogota, Colombia'], [10.49, -66.88, 'Caracas, Venezuela'],
        // --- Oceania + Europe
        [-12.46, 130.84, 'Darwin, Australia'], [-16.92, 145.77, 'Cairns, Australia'],
        [-31.95, 115.86, 'Perth, Australia'], [-33.87, 151.21, 'Sydney, Australia'],
        [-37.81, 144.96, 'Melbourne, Australia'], [-19.02, 146.82, 'Townsville, Australia'],
        [-36.85, 174.76, 'Auckland, New Zealand'], [-9.44, 147.18, 'Port Moresby, PNG'],
        [51.51, -0.13, 'London, UK'], [48.86, 2.35, 'Paris, France'],
        [40.42, -3.70, 'Madrid, Spain'], [38.72, -9.14, 'Lisbon, Portugal'],
        [41.90, 12.50, 'Rome, Italy'], [37.98, 23.73, 'Athens, Greece'],
        [52.52, 13.40, 'Berlin, Germany'], [59.33, 18.07, 'Stockholm, Sweden'],
        [64.15, -21.94, 'Reykjavik, Iceland'], [50.45, 30.52, 'Kyiv, Ukraine'],
        // Western + northern Canada. Sparse coverage here was why fires in
        // the BC interior and the territories fell back to raw coordinates
        // ("71 detections at 63.6°, -118.7°") instead of naming a place —
        // this is a Canadian product and the boreal is where it burns.
        [53.92, -122.75, 'Prince George, BC'], [54.78, -127.17, 'Smithers, BC'],
        [54.52, -128.60, 'Terrace, BC'], [54.32, -130.32, 'Prince Rupert, BC'],
        [58.81, -122.70, 'Fort Nelson, BC'], [56.25, -120.85, 'Fort St. John, BC'],
        [55.76, -120.24, 'Dawson Creek, BC'], [52.14, -122.14, 'Williams Lake, BC'],
        [50.69, -121.94, 'Lillooet, BC'], [49.89, -119.50, 'Kelowna, BC'],
        [49.50, -119.59, 'Penticton, BC'], [49.49, -117.29, 'Nelson, BC'],
        [51.00, -118.20, 'Revelstoke, BC'], [49.51, -115.77, 'Cranbrook, BC'],
        [48.43, -123.365, 'Victoria, BC'], [50.03, -125.25, 'Campbell River, BC'],
        [56.73, -111.38, 'Fort McMurray, AB'], [55.17, -118.80, 'Grande Prairie, AB'],
        [49.69, -112.84, 'Lethbridge, AB'],
        [62.45, -114.37, 'Yellowknife, NWT'], [60.82, -115.80, 'Hay River, NWT'],
        [60.00, -111.89, 'Fort Smith, NWT'], [65.28, -126.83, 'Norman Wells, NWT'],
        [68.36, -133.72, 'Inuvik, NWT'], [60.72, -135.05, 'Whitehorse, Yukon'],
        [63.75, -68.52, 'Iqaluit, Nunavut'],
        [52.13, -106.67, 'Saskatoon, Canada'], [50.45, -104.62, 'Regina, Canada'],
        [49.90, -97.14, 'Winnipeg, Canada'], [55.74, -97.86, 'Thompson, Manitoba'],
        [48.38, -89.25, 'Thunder Bay, Canada'], [46.49, -80.99, 'Sudbury, Canada'],
        [46.81, -71.21, 'Quebec City, Canada'], [44.65, -63.58, 'Halifax, Canada'],
        [47.56, -52.71, "St. John's, Canada"],
        [64.84, -147.72, 'Fairbanks, Alaska'], [61.22, -149.90, 'Anchorage, Alaska'],
        [49.3, -123.1, 'Vancouver, Canada'], [50.7, -120.3, 'Kamloops, BC'],
        [53.5, -113.5, 'Edmonton, Canada'], [51.0, -114.1, 'Calgary, Canada'],
        [45.5, -73.6, 'Montreal, Canada'], [43.7, -79.4, 'Toronto, Canada'],
        [34.1, -118.2, 'Los Angeles, US'], [37.8, -122.4, 'San Francisco, US'],
        [45.5, -122.7, 'Portland, US'], [47.6, -122.3, 'Seattle, US'],
        [39.7, -105.0, 'Denver, US'], [35.1, -106.6, 'Albuquerque, US'],
        [30.3, -97.7, 'Austin, US'], [25.8, -80.2, 'Miami, US'],
        [19.4, -99.1, 'Mexico City'], [4.7, -74.1, 'Bogotá, Colombia'],
        [-3.1, -60.0, 'Manaus, Amazon'], [-15.8, -47.9, 'Brasília, Brazil'],
        [-23.5, -46.6, 'São Paulo, Brazil'], [-34.6, -58.4, 'Buenos Aires'],
        [-33.9, 18.4, 'Cape Town, SA'], [-26.2, 28.0, 'Johannesburg, SA'],
        [-1.3, 36.8, 'Nairobi, Kenya'], [9.0, 38.7, 'Addis Ababa'],
        [6.5, 3.4, 'Lagos, Nigeria'], [14.7, -17.5, 'Dakar, Senegal'],
        [36.8, 10.2, 'Tunis'], [30.0, 31.2, 'Cairo, Egypt'],
        [40.4, -3.7, 'Madrid, Spain'], [38.7, -9.1, 'Lisbon, Portugal'],
        [41.9, 12.5, 'Rome, Italy'], [37.9, 23.7, 'Athens, Greece'],
        [48.9, 2.3, 'Paris, France'], [52.5, 13.4, 'Berlin, Germany'],
        [55.8, 37.6, 'Moscow, Russia'], [39.9, 32.9, 'Ankara, Türkiye'],
        [28.6, 77.2, 'Delhi, India'], [19.1, 72.9, 'Mumbai, India'],
        [13.8, 100.5, 'Bangkok, Thailand'], [-6.2, 106.8, 'Jakarta, Indonesia'],
        [1.4, 103.8, 'Singapore'], [14.6, 121.0, 'Manila, Philippines'],
        [39.9, 116.4, 'Beijing, China'], [31.2, 121.5, 'Shanghai, China'],
        [35.7, 139.7, 'Tokyo, Japan'], [37.6, 126.9, 'Seoul, Korea'],
        [-33.9, 151.2, 'Sydney, Australia'], [-37.8, 145.0, 'Melbourne, Australia'],
        [-31.9, 115.9, 'Perth, Australia'], [-41.3, 174.8, 'Wellington, NZ'],
        [64.1, -21.9, 'Reykjavík, Iceland'], [61.2, -149.9, 'Anchorage, Alaska'],
    ];

    function haversineKm(lat1, lon1, lat2, lon2) {
        const rad = Math.PI / 180;
        const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
        const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function regionLabel(lat, lon) {
        let best = null, bestKm = Infinity;
        for (const [rlat, rlon, name] of REGIONS) {
            const km = haversineKm(lat, lon, rlat, rlon);
            if (km < bestKm) { bestKm = km; best = name; }
        }
        if (best && bestKm <= 400) {
            return (bestKm < 60 ? 'near ' : Math.round(bestKm) + ' km from ') + best;
        }
        return 'at ' + lat.toFixed(1) + '°, ' + lon.toFixed(1) + '°';
    }

    function hexCenterLatLon(q, r) {
        const S = window.SpatialStats;
        const size = S._sizeFor(CELL_KM);
        const c = S._centerOf(q, r, size);
        const ll = S._unproject(c[0], c[1]);
        return { lon: ll[0], lat: ll[1] };
    }

    // ---------- Core computation ----------

    async function getDepartures() {
        if (!window.SpatialStats || !window.HistoryArchive || !window.ecoMap) {
            return { status: 'unavailable', departures: [] };
        }
        const baseline = await window.HistoryArchive.getBaseline('fires', BASELINE_DAYS, CELL_KM);
        if (baseline.length < MIN_BASELINE_DAYS) {
            return {
                status: 'building',
                baselineDays: baseline.length,
                needed: MIN_BASELINE_DAYS,
                departures: [],
            };
        }

        // Per-hex daily-count series across the baseline
        const series = new Map(); // "q,r" -> number[]
        for (const day of baseline) {
            const seen = new Set();
            for (const cell of day.cells) {
                const key = cell.q + ',' + cell.r;
                if (!series.has(key)) series.set(key, []);
                series.get(key).push(cell.count);
                seen.add(key);
            }
            // Hexes absent on a day count as zero for that day
            for (const [key, arr] of series) {
                if (!seen.has(key) && arr.length < baseline.indexOf(day) + 1) arr.push(0);
            }
        }

        // Current live pattern, normalized to a per-day rate
        const src = window.ecoMap.getSource('fires-source');
        const data = src && src._data;
        if (!data || !data.features) return { status: 'nodata', departures: [] };
        const coverageDays = (data.metadata && data.metadata.coverage_days) || 2;
        const current = window.SpatialStats.hexBin(data.features, { cellKm: CELL_KM });

        const departures = [];
        for (const cell of current) {
            if (cell.count < MIN_COUNT) continue;
            const arr = series.get(cell.q + ',' + cell.r);
            const n = baseline.length;
            let mean = 0, sd = 0;
            if (arr && arr.length) {
                const padded = arr.concat(Array(Math.max(0, n - arr.length)).fill(0));
                mean = padded.reduce((a, b) => a + b, 0) / n;
                const varc = padded.reduce((a, b) => a + (b - mean) * (b - mean), 0) / n;
                sd = Math.sqrt(varc);
            }
            const rate = cell.count / coverageDays;
            // A hex with no history: any activity is "new", flag if large.
            const z = sd > 0 ? (rate - mean) / sd : (mean === 0 && rate >= MIN_COUNT ? 3 : 0);
            if (z >= Z_THRESHOLD) {
                const center = hexCenterLatLon(cell.q, cell.r);
                departures.push({
                    hexId: cell.q + ',' + cell.r,
                    center,
                    label: regionLabel(center.lat, center.lon),
                    current: cell.count,
                    dailyRate: Math.round(rate * 10) / 10,
                    mean: Math.round(mean * 10) / 10,
                    sigma: Math.round(sd * 10) / 10,
                    z: Math.round(z * 10) / 10,
                });
            }
        }
        departures.sort((a, b) => b.z - a.z);
        return {
            status: 'ok',
            baselineDays: baseline.length,
            coverageDays,
            generated: new Date().toISOString(),
            departures: departures.slice(0, 8),
        };
    }

    // ---------- Alerts-panel section ----------

    function renderSection(report) {
        const host = document.getElementById('alerts-summary');
        if (!host || !host.parentElement) return;
        let section = document.getElementById('anomaly-section');
        if (!section) {
            section = document.createElement('div');
            section.id = 'anomaly-section';
            section.style.cssText = 'margin:0 12px 10px;padding:10px;border:1px solid ' +
                'var(--rule,#D9D2BF);border-left:2px solid var(--fire-deep,#8E1B12);' +
                'border-radius:2px;background:var(--paper-raised,#FBF9F1);' +
                'font-size:11px;color:var(--ink-soft,#5B564A);line-height:1.5;';
            host.parentElement.insertBefore(section, host.nextSibling);
        }
        const title = '<div style="font-size:8.5px;font-weight:800;letter-spacing:1.3px;' +
            'text-transform:uppercase;color:var(--fire-deep,#8E1B12);margin-bottom:5px;">30-day baseline check</div>';

        if (report.status === 'building') {
            section.innerHTML = title +
                'Baseline is still accruing: ' + report.baselineDays + '/' + report.needed +
                ' archived days. Departure detection starts when enough history exists — ' +
                'no guesses before then.';
            return;
        }
        if (report.status !== 'ok') {
            section.innerHTML = title + 'Baseline unavailable (archive offline or no data).';
            return;
        }
        if (!report.departures.length) {
            section.innerHTML = title +
                'Fire activity is within its normal range everywhere we checked ' +
                '(vs ' + report.baselineDays + '-day per-hex baseline).';
            return;
        }
        // Plain language, place first: "Extreme fire surge near Yellowknife —
        // 167 fires a day where 2 is normal". The σ ships as fine print;
        // it's evidence, not the message.
        section.innerHTML = title + report.departures.map(d => {
            const rate = Number(d.dailyRate) || 0;
            const mean = Math.max(0.1, Number(d.mean) || 0.1);
            const ratio = Math.round(rate / mean);
            const tier = d.z >= 20 ? 'Extreme fire surge'
                : d.z >= 8 ? 'Major fire surge'
                : 'Unusual fire activity';
            const rateTxt = Math.round(rate).toLocaleString() + ' fires a day where ' +
                (mean < 1 ? 'almost none' : Math.round(mean).toLocaleString()) +
                (mean < 1 ? ' are' : ' is') + ' normal';
            return '<div style="padding:4px 0;cursor:pointer;" data-fly="' +
                d.center.lon + ',' + d.center.lat + '" data-place="' +
                d.center.lat.toFixed(2) + ',' + d.center.lon.toFixed(2) + '">' +
                '<b style="color:var(--fire-deep,#8E1B12);font-family:var(--serif,Georgia,serif);">' +
                tier + '</b> <span class="anomaly-place">' + esc(d.label) + '</span><br>' +
                rateTxt + (ratio >= 3 ? ' — ' + ratio.toLocaleString() + '× the usual rate' : '') +
                ' <span style="opacity:0.5;">(' + d.z.toFixed(0) + 'σ)</span></div>';
        }).join('') +
            '<div style="margin-top:5px;opacity:0.55;">Click a row to fly there. Method: daily ' +
            'detections per 100 km area vs its own ' + report.baselineDays + '-day normal, from the EcoLens archive.</div>';
        section.querySelectorAll('[data-fly]').forEach(row => {
            row.addEventListener('click', () => {
                const [lon, lat] = row.dataset.fly.split(',').map(Number);
                if (window.ecolensFlyTo) window.ecolensFlyTo(lat, lon, 7, 'Anomaly');
                else if (window.ecoMap) window.ecoMap.flyTo({ center: [lon, lat], zoom: 7 });
            });
        });
        enrichPlaceNames(section);
    }

    // Swap raw "at 64.2°, 108.5°" fallbacks for real place names, politely
    // (sequential Nominatim reverse lookups, cached forever per hex).
    async function enrichPlaceNames(section) {
        const rows = [...section.querySelectorAll('[data-place]')]
            .filter(r => /^at -?\d/.test(r.querySelector('.anomaly-place')?.textContent || ''));
        for (const row of rows) {
            const key = 'ecolens-place-' + row.dataset.place;
            let name = null;
            try { name = localStorage.getItem(key); } catch (e) {}
            if (!name) {
                try {
                    const [lat, lon] = row.dataset.place.split(',');
                    const resp = await fetch('https://nominatim.openstreetmap.org/reverse?format=jsonv2' +
                        '&lat=' + lat + '&lon=' + lon + '&zoom=5&accept-language=en');
                    const j = await resp.json();
                    const a = j.address || {};
                    name = [a.state || a.county, a.country].filter(Boolean).join(', ') || null;
                    if (name) try { localStorage.setItem(key, name); } catch (e) {}
                    await new Promise(r => setTimeout(r, 1100)); // Nominatim rate courtesy
                } catch (e) { break; }
            }
            const span = row.querySelector('.anomaly-place');
            if (name && span) span.textContent = 'in ' + name;
        }
    }

    // ---------- Daily front page ----------

    function maybeShowFrontPage(report) {
        if (report.status !== 'ok' || !report.departures.length) return;
        const todayKey = 'ecolens-frontpage-' + new Date().toISOString().slice(0, 10);
        try {
            if (localStorage.getItem(todayKey)) return;
            localStorage.setItem(todayKey, '1');
        } catch (e) { return; }

        const lead = report.departures[0];
        const overlay = document.createElement('div');
        overlay.id = 'frontpage-card';
        overlay.style.cssText = 'position:fixed;inset:0;z-index:600;display:flex;' +
            'align-items:center;justify-content:center;background:rgba(35,32,25,0.45);' +
            'font-family:system-ui,sans-serif;';
        overlay.innerHTML =
            '<div style="width:min(460px,calc(100vw - 48px));background:var(--paper,#F2EFE4);' +
            'border:1px solid var(--ink,#232019);border-radius:3px;padding:22px 24px;' +
            'color:var(--ink,#232019);box-shadow:5px 5px 0 rgba(35,32,25,0.2);">' +
            '<div style="font-size:9px;font-weight:800;letter-spacing:1.5px;text-transform:uppercase;' +
            'color:var(--fire-deep,#8E1B12);margin-bottom:8px;">Today’s lead · chosen by statistics</div>' +
            '<div style="font-family:var(--serif,Georgia,serif);font-size:20px;font-weight:700;' +
            'line-height:1.25;margin-bottom:10px;text-wrap:balance;">' +
            'Fire activity ' + esc(lead.label) + ' is running <span style="color:var(--fire-deep,#8E1B12);">' +
            lead.z.toFixed(1) + 'σ</span> above its ' + report.baselineDays + '-day normal</div>' +
            '<div style="font-size:12.5px;color:var(--ink-soft,#5B564A);line-height:1.5;margin-bottom:12px;">' +
            lead.dailyRate + ' detections per day in this area vs a baseline of ' + lead.mean +
            ' (σ = ' + lead.sigma + '). ' +
            (report.departures.length > 1
                ? (report.departures.length - 1) + ' other area(s) are also above threshold — listed in the Event Queue.'
                : 'No other area is above threshold today.') + '</div>' +
            '<div style="font-size:10px;color:var(--ink-faint,#8C8574);line-height:1.5;margin-bottom:14px;' +
            'border-top:1px solid var(--rule,#D9D2BF);padding-top:8px;">' +
            'Provenance: NASA FIRMS detections vs the EcoLens hazard archive (' +
            report.baselineDays + ' days, per-100 km-hex mean/σ), computed in your browser at ' +
            new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) +
            '. Statistical departure ≠ confirmed emergency — verify with official sources.</div>' +
            '<div style="display:flex;gap:8px;">' +
            '<button id="fp-view" style="flex:1;background:var(--ink,#232019);color:var(--paper,#F2EFE4);' +
            'border:1px solid var(--ink,#232019);border-radius:3px;padding:9px;font-weight:700;' +
            'font-size:12px;cursor:pointer;">View on map</button>' +
            '<button id="fp-close" style="background:none;border:1px solid var(--ink-faint,#8C8574);' +
            'color:var(--ink-soft,#5B564A);border-radius:3px;padding:9px 14px;font-size:12px;cursor:pointer;">Dismiss</button>' +
            '</div></div>';
        document.body.appendChild(overlay);
        overlay.querySelector('#fp-close').onclick = () => overlay.remove();
        overlay.querySelector('#fp-view').onclick = () => {
            overlay.remove();
            if (window.ecoMap) {
                window.ecoMap.flyTo({ center: [lead.center.lon, lead.center.lat], zoom: 7, duration: 1500 });
            }
            if (window.HazardLayers) {
                window.HazardLayers.setLayerVisibility('fires', true);
                window.HazardLayers.setLayerVisibility('hotspots', true);
            }
        };
    }

    // ---------- Init ----------

    async function refresh() {
        try {
            lastReport = await getDepartures();
            renderSection(lastReport);
            maybeShowFrontPage(lastReport);
        } catch (e) {
            console.warn('[AnomalyDesk]', e);
        }
    }

    function init() {
        // Baselines involve archive fetches — wait for quiet time, well after
        // the initial data load.
        const kick = () => setTimeout(refresh, 15000);
        if ('requestIdleCallback' in window) requestIdleCallback(kick);
        else kick();
        // Re-check hourly (cheap once aggregates are cached)
        setInterval(refresh, 60 * 60 * 1000);
        console.log('[AnomalyDesk] Ready');
    }

    return { init, refresh, getDepartures, regionLabel, getLastReport: () => lastReport };
})();

window.AnomalyDesk = AnomalyDesk;
