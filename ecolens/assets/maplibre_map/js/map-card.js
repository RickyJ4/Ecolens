// ============================================================
// EcoLens MapCard — publication-quality shareable map exports
//
// One click → a framed 1200×630 PNG of the current view with title,
// legend swatches for the visible layers, and a provenance block
// (sources, time window, timestamp). The map is captured on a render
// frame (map.once('render') + triggerRepaint) so we never pay the
// steady-state cost of preserveDrawingBuffer; `?pdb=1` opts into the
// buffer-preserving fallback for GPUs where frame capture reads blank.
// ============================================================

const MapCard = (function () {
    'use strict';

    const CARD_W = 1200, CARD_H = 630;

    const LAYER_SOURCES = {
        fires: 'NASA FIRMS (VIIRS)',
        hotspots: 'Getis-Ord Gi* (computed in-browser)',
        bivariate: 'NASA FIRMS × US Drought Monitor',
        earthquakes: 'USGS',
        floods: 'NOAA / NWS',
        drought: 'US Drought Monitor',
        airquality: 'Open-Meteo',
        volcanoes: 'Smithsonian GVP / USGS',
        glaciers: 'Natural Earth',
        watershed: 'Natural Earth',
        ndvi: 'EOX Sentinel-2 cloudless',
        risk: 'EcoLens composite',
    };

    const LAYER_COLORS = {
        fires: '#F03B20', hotspots: '#B2182B', bivariate: '#804D7F',
        earthquakes: '#F59E0B', floods: '#3B82F6', drought: '#D97706',
        airquality: '#8B5CF6', volcanoes: '#EF4444', glaciers: '#67E8F9',
        watershed: '#38BDF8', ndvi: '#22C55E', risk: '#DC2626',
    };

    // ---------- Capture ----------

    function frameCapture() {
        return new Promise((resolve, reject) => {
            const map = window.ecoMap;
            if (!map) { reject(new Error('Map not ready')); return; }
            let done = false;
            map.once('render', () => {
                if (done) return;
                done = true;
                try {
                    resolve(map.getCanvas().toDataURL('image/png'));
                } catch (e) { reject(e); }
            });
            map.triggerRepaint();
            setTimeout(() => {
                if (!done) { done = true; reject(new Error('Render frame timeout')); }
            }, 3000);
        });
    }

    function looksBlank(img) {
        const c = document.createElement('canvas');
        c.width = 24; c.height = 24;
        const ctx = c.getContext('2d');
        ctx.drawImage(img, 0, 0, 24, 24);
        const px = ctx.getImageData(0, 0, 24, 24).data;
        let nonEmpty = 0;
        for (let i = 3; i < px.length; i += 4) {
            if (px[i] > 0) nonEmpty++;
        }
        return nonEmpty < 10;
    }

    function loadImage(dataUrl) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = reject;
            img.src = dataUrl;
        });
    }

    async function capture() {
        let img = await loadImage(await frameCapture());
        if (looksBlank(img)) {
            // one retry — the first frame after triggerRepaint can be partial
            img = await loadImage(await frameCapture());
        }
        if (looksBlank(img)) {
            throw new Error(
                'Screenshot came back blank on this GPU. Reload the map with ?pdb=1 ' +
                'appended to the URL to enable the compatibility capture mode.');
        }
        return img;
    }

    // ---------- Compose ----------

    function visibleLayers() {
        const out = [];
        document.querySelectorAll('#layer-toggles input[type="checkbox"]').forEach(cb => {
            if (cb.checked) out.push(cb.id.replace('toggle-', ''));
        });
        return out;
    }

    function windowLabel() {
        const hours = Number(window.EcoLensTimeWindowHours) || 168;
        if (hours <= 24) return 'Last 24 hours';
        if (hours <= 168) return 'Last ' + Math.round(hours / 24) + ' days';
        if (hours <= 720) return 'Last ' + Math.round(hours / 168) + ' weeks';
        return 'Last ' + Math.round(hours / 720) + ' months';
    }

    async function compose(options) {
        options = options || {};
        const mapImg = await capture();

        const canvas = document.createElement('canvas');
        canvas.width = CARD_W; canvas.height = CARD_H;
        const ctx = canvas.getContext('2d');

        // Map fills the card, cover-cropped, centered
        ctx.fillStyle = '#0d1117';
        ctx.fillRect(0, 0, CARD_W, CARD_H);
        const scale = Math.max(CARD_W / mapImg.width, CARD_H / mapImg.height);
        const dw = mapImg.width * scale, dh = mapImg.height * scale;
        ctx.drawImage(mapImg, (CARD_W - dw) / 2, (CARD_H - dh) / 2, dw, dh);

        // Title bar (top)
        const title = options.title || 'EcoLens — Global Hazard Monitor';
        ctx.fillStyle = 'rgba(13,17,23,0.88)';
        ctx.fillRect(0, 0, CARD_W, 64);
        ctx.fillStyle = '#ffffff';
        ctx.font = '700 26px Inter, system-ui, sans-serif';
        ctx.fillText(title, 28, 40);
        ctx.fillStyle = '#8b949e';
        ctx.font = '500 14px Inter, system-ui, sans-serif';
        const dateStr = new Date().toISOString().slice(0, 16).replace('T', ' ') + ' UTC';
        ctx.textAlign = 'right';
        ctx.fillText(dateStr + ' · ' + windowLabel(), CARD_W - 28, 40);
        ctx.textAlign = 'left';

        // Provenance / legend bar (bottom)
        const layers = visibleLayers();
        const barH = 78;
        ctx.fillStyle = 'rgba(13,17,23,0.9)';
        ctx.fillRect(0, CARD_H - barH, CARD_W, barH);

        let x = 28;
        const y = CARD_H - barH + 30;
        ctx.font = '600 13px Inter, system-ui, sans-serif';
        for (const type of layers.slice(0, 6)) {
            ctx.fillStyle = LAYER_COLORS[type] || '#8b949e';
            ctx.beginPath();
            ctx.arc(x + 5, y - 4, 5, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = '#e6edf3';
            const label = type.charAt(0).toUpperCase() + type.slice(1);
            ctx.fillText(label, x + 16, y);
            x += ctx.measureText(label).width + 40;
        }

        ctx.fillStyle = '#8b949e';
        ctx.font = '400 11px Inter, system-ui, sans-serif';
        const sources = layers.map(t => LAYER_SOURCES[t]).filter(Boolean);
        const provenance = 'Data: ' + (sources.length ? Array.from(new Set(sources)).join(' · ') : 'basemap only') +
            ' — every layer on this map can show how it was made. ecolens.app';
        ctx.fillText(provenance.slice(0, 160), 28, CARD_H - 18);

        return canvas;
    }

    async function download(options) {
        try {
            const canvas = await compose(options);
            const blob = await new Promise(res => canvas.toBlob(res, 'image/png'));
            const name = 'ecolens-map-' + new Date().toISOString().slice(0, 10) + '.png';
            // Mobile WebView: hand the image to Flutter's share sheet instead
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                const dataUrl = canvas.toDataURL('image/png');
                window.flutter_inappwebview.callHandler('onMapEvent',
                    JSON.stringify({ event: 'mapCard', data: { dataUrl, name } }));
                return;
            }
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = name;
            a.click();
            setTimeout(() => URL.revokeObjectURL(a.href), 5000);
        } catch (e) {
            console.warn('[MapCard]', e);
            alert(e.message);
        }
    }

    // ---------- Toolbar button (self-injected into the map rail) ----------

    function injectButton() {
        const rail = document.querySelector('.map-rail');
        if (!rail || document.getElementById('map-card-btn')) return;
        const btn = document.createElement('button');
        btn.id = 'map-card-btn';
        btn.setAttribute('data-tooltip', 'Export shareable map card');
        btn.innerHTML =
            '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            '<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>' +
            '<circle cx="12" cy="13" r="4"/></svg>';
        btn.addEventListener('click', () => download());
        rail.appendChild(btn);
    }

    function init() {
        injectButton();
        console.log('[MapCard] Ready');
    }

    return { init, capture, compose, download };
})();

window.MapCard = MapCard;
