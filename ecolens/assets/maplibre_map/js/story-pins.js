/* ============================================================
   EcoLens — Story Pins (the Places spine)
   Renders every geography EcoLens has reported on as a
   first-class editorial pin on the map. Clicking a pin opens a
   story card that deep-links into the storymap, Insights, and
   (later) Community — making the map the front page of the
   publication rather than a bare data viewer.

   Also provides the "Near you" locator: geolocate the visitor
   and surface the closest documented place.

   Self-contained: injects its own CSS, loads places.json,
   exposes window.StoryPins.init(map).
   ============================================================ */

const StoryPins = (() => {
    'use strict';

    let map = null;
    let places = [];
    let openPopup = null;
    let userMarker = null;

    const STATUS_META = {
        published:      { color: '#00D26A', label: 'PUBLISHED' },
        coming_soon:    { color: '#00BCD4', label: 'COMING SOON' },
        in_development: { color: '#FBBF24', label: 'IN DEVELOPMENT' }
    };

    const escapeHtml = (v) => String(v ?? '').replace(/[&<>"']/g, (ch) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[ch]));

    /* ── Navigation: the map runs inside an iframe on web, so links
       must drive the parent frame (same origin). ── */
    function navigateTop(url) {
        try { window.top.location.href = url; }
        catch (e) { window.location.href = url; }
    }

    /* ── CSS (injected so the module stays drop-in) ── */
    function injectStyles() {
        if (document.getElementById('story-pins-css')) return;
        const css = `
        .sp-popup .maplibregl-popup-content {
            background: rgba(13, 17, 23, 0.96);
            border: 1px solid rgba(255,255,255,0.12);
            border-radius: 12px;
            padding: 0;
            width: 320px;
            max-width: 86vw;
            box-shadow: 0 22px 60px rgba(0,0,0,0.55);
            font-family: Inter, -apple-system, "Segoe UI", sans-serif;
            overflow: hidden;
        }
        .sp-popup .maplibregl-popup-close-button {
            color: rgba(255,255,255,0.55);
            font-size: 18px; right: 6px; top: 4px; z-index: 2;
        }
        .sp-popup .maplibregl-popup-tip { border-top-color: rgba(13,17,23,0.96); }
        .sp-card { padding: 16px 16px 14px; }
        .sp-kicker {
            font-size: 9.5px; font-weight: 800; letter-spacing: 1.6px;
            text-transform: uppercase; margin-bottom: 7px;
        }
        .sp-title {
            color: #fff; font-size: 16.5px; font-weight: 800;
            letter-spacing: -0.2px; line-height: 1.2; margin-bottom: 7px;
        }
        .sp-dek {
            color: rgba(255,255,255,0.68); font-size: 12px;
            line-height: 1.5; margin-bottom: 11px;
        }
        .sp-near {
            color: #7ec4e8; font-size: 11.5px; font-weight: 700;
            margin-bottom: 9px; display: flex; align-items: center; gap: 6px;
        }
        .sp-facts { margin: 0 0 12px; padding: 0; list-style: none; }
        .sp-facts li {
            color: rgba(255,255,255,0.55); font-size: 10.8px;
            line-height: 1.45; padding-left: 14px; position: relative;
            margin-bottom: 4px;
        }
        .sp-facts li::before {
            content: ""; position: absolute; left: 0; top: 6px;
            width: 5px; height: 5px; border-radius: 50%;
            background: rgba(0, 210, 106, 0.7);
        }
        .sp-actions { display: grid; gap: 7px; }
        .sp-btn {
            display: block; width: 100%; text-align: center;
            padding: 9px 12px; border-radius: 8px; cursor: pointer;
            font-size: 12px; font-weight: 700; letter-spacing: 0.2px;
            border: 1px solid transparent; transition: filter 140ms;
        }
        .sp-btn:hover { filter: brightness(1.15); }
        .sp-btn.primary { background: #00D26A; color: #06130b; }
        .sp-btn.secondary {
            background: rgba(0, 188, 212, 0.12); color: #00BCD4;
            border-color: rgba(0, 188, 212, 0.35);
        }
        .sp-btn.muted {
            background: rgba(255,255,255,0.06); color: rgba(255,255,255,0.5);
            border-color: rgba(255,255,255,0.1); cursor: default;
        }
        .sp-nearyou-ctrl {
            background: rgba(13, 17, 23, 0.88) !important;
            border: 1px solid rgba(255,255,255,0.14);
            border-radius: 8px !important;
            overflow: hidden;
        }
        .sp-nearyou-btn {
            display: flex; align-items: center; gap: 7px;
            background: none; border: none; cursor: pointer;
            padding: 8px 12px;
            color: #e8f2fa; font-size: 11.5px; font-weight: 700;
            font-family: Inter, sans-serif; letter-spacing: 0.3px;
            white-space: nowrap;
        }
        .sp-nearyou-btn:hover { background: rgba(255,255,255,0.07); }
        .sp-nearyou-btn .dot {
            width: 8px; height: 8px; border-radius: 50%;
            background: #00D26A; box-shadow: 0 0 8px rgba(0,210,106,0.8);
        }
        .sp-nearyou-btn.busy { opacity: 0.6; pointer-events: none; }
        .sp-toast {
            position: absolute; left: 50%; bottom: 26px; z-index: 30;
            transform: translateX(-50%);
            background: rgba(13, 17, 23, 0.94); color: #e8f2fa;
            border: 1px solid rgba(255,255,255,0.14);
            padding: 10px 16px; border-radius: 8px;
            font-family: Inter, sans-serif; font-size: 12px; font-weight: 600;
            pointer-events: none; opacity: 0;
            transition: opacity 240ms ease;
        }
        .sp-toast.show { opacity: 1; }
        .sp-user-marker {
            width: 14px; height: 14px; border-radius: 50%;
            background: #7ec4e8; border: 2.5px solid #fff;
            box-shadow: 0 0 0 4px rgba(126, 196, 232, 0.35), 0 2px 8px rgba(0,0,0,0.5);
        }`;
        const el = document.createElement('style');
        el.id = 'story-pins-css';
        el.textContent = css;
        document.head.appendChild(el);
    }

    /* ── Toast ── */
    let toastEl = null, toastTimer = null;
    function toast(msg, ms = 3200) {
        if (!toastEl) {
            toastEl = document.createElement('div');
            toastEl.className = 'sp-toast';
            (map.getContainer() || document.body).appendChild(toastEl);
        }
        toastEl.textContent = msg;
        toastEl.classList.add('show');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => toastEl.classList.remove('show'), ms);
    }

    /* ── Layers ── */
    function addLayers() {
        const features = places.map((p) => ({
            type: 'Feature',
            properties: { id: p.id, status: p.status },
            geometry: { type: 'Point', coordinates: [p.lon, p.lat] }
        }));
        map.addSource('story-pins', {
            type: 'geojson',
            data: { type: 'FeatureCollection', features }
        });

        map.addLayer({
            id: 'story-pins-halo', type: 'circle', source: 'story-pins',
            paint: {
                'circle-radius': ['interpolate', ['linear'], ['zoom'], 2, 14, 8, 20],
                'circle-color': ['match', ['get', 'status'],
                    'published', '#00D26A',
                    'coming_soon', '#00BCD4',
                    'in_development', '#FBBF24', '#888'],
                'circle-opacity': 0.18,
                'circle-blur': 0.4
            }
        });
        map.addLayer({
            id: 'story-pins-core', type: 'circle', source: 'story-pins',
            paint: {
                'circle-radius': ['interpolate', ['linear'], ['zoom'], 2, 6, 8, 9],
                'circle-color': ['match', ['get', 'status'],
                    'published', '#00D26A',
                    'coming_soon', '#00BCD4',
                    'in_development', '#FBBF24', '#888'],
                'circle-stroke-color': '#0d1117',
                'circle-stroke-width': 2.5,
                'circle-opacity': ['match', ['get', 'status'], 'published', 1, 0.85]
            }
        });

        map.on('click', 'story-pins-core', (e) => {
            const f = e.features && e.features[0];
            if (!f) return;
            const place = places.find((p) => p.id === f.properties.id);
            if (place) openCard(place);
        });
        map.on('mouseenter', 'story-pins-core', () => { map.getCanvas().style.cursor = 'pointer'; });
        map.on('mouseleave', 'story-pins-core', () => { map.getCanvas().style.cursor = ''; });
    }

    /* ── Editorial card ── */
    function openCard(place, nearLine) {
        if (openPopup) { openPopup.remove(); openPopup = null; }
        const meta = STATUS_META[place.status] || STATUS_META.in_development;

        const facts = (place.facts || [])
            .map((f) => `<li>${escapeHtml(f)}</li>`).join('');

        const actions = [];
        if (place.status === 'published' && place.storyUrl) {
            actions.push(`<button class="sp-btn primary" data-nav="${escapeHtml(place.storyUrl)}">${escapeHtml(place.storyLabel || 'Read the investigation')}</button>`);
        }
        if (place.insightsRoute) {
            actions.push(`<button class="sp-btn secondary" data-nav="${escapeHtml(place.insightsRoute)}">See the numbers · Insights</button>`);
        }
        if (place.status !== 'published') {
            actions.push(`<div class="sp-btn muted">${meta.label === 'COMING SOON' ? 'Story coming soon' : 'In development — launching soon'}</div>`);
        }

        const html = `
        <div class="sp-card">
            <div class="sp-kicker" style="color:${meta.color};">${escapeHtml(place.kicker || meta.label)}</div>
            <div class="sp-title">${escapeHtml(place.name)}</div>
            ${nearLine ? `<div class="sp-near">📍 ${escapeHtml(nearLine)}</div>` : ''}
            <div class="sp-dek">${escapeHtml(place.dek || '')}</div>
            ${facts ? `<ul class="sp-facts">${facts}</ul>` : ''}
            <div class="sp-actions">${actions.join('')}</div>
        </div>`;

        openPopup = new maplibregl.Popup({
            className: 'sp-popup',
            closeButton: true,
            maxWidth: 'none',
            offset: 14
        }).setLngLat([place.lon, place.lat]).setHTML(html).addTo(map);

        // Wire buttons (popup content is plain HTML — no inline handlers)
        const node = openPopup.getElement();
        node.querySelectorAll('[data-nav]').forEach((btn) => {
            btn.addEventListener('click', () => navigateTop(btn.getAttribute('data-nav')));
        });
    }

    /* ── Near you ── */
    function haversineKm(a, b) {
        const R = 6371;
        const dLat = (b.lat - a.lat) * Math.PI / 180;
        const dLon = (b.lon - a.lon) * Math.PI / 180;
        const la1 = a.lat * Math.PI / 180, la2 = b.lat * Math.PI / 180;
        const h = Math.sin(dLat / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) ** 2;
        return 2 * R * Math.asin(Math.sqrt(h));
    }

    function locateNearest(btn) {
        if (!navigator.geolocation) { toast('Location is not available in this browser.'); return; }
        btn.classList.add('busy');
        navigator.geolocation.getCurrentPosition((pos) => {
            btn.classList.remove('busy');
            const user = { lon: pos.coords.longitude, lat: pos.coords.latitude };

            if (userMarker) userMarker.remove();
            const el = document.createElement('div');
            el.className = 'sp-user-marker';
            userMarker = new maplibregl.Marker({ element: el })
                .setLngLat([user.lon, user.lat]).addTo(map);

            let best = null;
            for (const p of places) {
                const d = haversineKm(user, p);
                if (!best || d < best.d) best = { p, d };
            }
            if (!best) { toast('No documented places loaded.'); return; }

            const distLabel = best.d < 1
                ? `${Math.round(best.d * 1000)} m`
                : `${best.d < 20 ? best.d.toFixed(1) : Math.round(best.d)} km`;

            // Frame both the user and the place
            const bounds = new maplibregl.LngLatBounds();
            bounds.extend([user.lon, user.lat]);
            bounds.extend([best.p.lon, best.p.lat]);
            map.fitBounds(bounds, { padding: 120, maxZoom: 11, duration: 1600 });

            setTimeout(() => {
                openCard(best.p, `You're ${distLabel} from this story`);
            }, 1700);
        }, (err) => {
            btn.classList.remove('busy');
            toast(err.code === 1
                ? 'Location permission declined — that\'s fine, explore the pins instead.'
                : 'Could not get your location.');
        }, { enableHighAccuracy: false, timeout: 12000, maximumAge: 300000 });
    }

    /* ── Map control ── */
    class NearYouControl {
        onAdd(m) {
            this._container = document.createElement('div');
            this._container.className = 'maplibregl-ctrl sp-nearyou-ctrl';
            const btn = document.createElement('button');
            btn.className = 'sp-nearyou-btn';
            btn.type = 'button';
            btn.title = 'Find the documented place nearest to you';
            btn.innerHTML = '<span class="dot"></span>Stories near you';
            btn.addEventListener('click', () => locateNearest(btn));
            this._container.appendChild(btn);
            return this._container;
        }
        onRemove() { this._container.remove(); }
    }

    /* ── Init ── */
    async function init(mapInstance) {
        map = mapInstance;
        injectStyles();
        try {
            const res = await fetch('places.json');
            if (!res.ok) throw new Error('HTTP ' + res.status);
            const data = await res.json();
            places = Array.isArray(data.places) ? data.places : [];
        } catch (e) {
            console.warn('[story-pins] places.json unavailable:', e);
            return;
        }
        if (!places.length) return;
        addLayers();
        map.addControl(new NearYouControl(), 'top-right');
        console.log(`[story-pins] ${places.length} places loaded`);
    }

    return { init, openCard, get places() { return places; } };
})();

window.StoryPins = StoryPins;
