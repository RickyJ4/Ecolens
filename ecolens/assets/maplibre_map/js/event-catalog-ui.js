/* ============================================================
   EcoLens - Event Catalog UI
   Browse and select historical environmental events for
   timeline simulation playback.
   ============================================================ */

const EventCatalogUI = (() => {
    'use strict';

    let isOpen = false;
    let currentFilter = 'all';
    let currentSort = 'date-desc';

    // Category metadata for display
    const CATEGORY_META = {
        wildfire:      { label: 'Wildfires',      icon: '\uD83D\uDD25', gradient: 'linear-gradient(135deg, #8B0000, #FF4500, #FF8C00)' },
        flood:         { label: 'Floods',          icon: '\uD83C\uDF0A', gradient: 'linear-gradient(135deg, #00008B, #1E90FF, #87CEEB)' },
        drought:       { label: 'Drought',         icon: '\u2600\uFE0F',  gradient: 'linear-gradient(135deg, #8B4513, #DAA520, #FFD700)' },
        glacier:       { label: 'Glacial Retreat', icon: '\uD83C\uDFD4\uFE0F',  gradient: 'linear-gradient(135deg, #4682B4, #87CEEB, #E0F7FA)' },
        deforestation: { label: 'Deforestation',   icon: '\uD83C\uDF33', gradient: 'linear-gradient(135deg, #006400, #228B22, #8B4513)' }
    };

    const esc = (value) => String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');

    /** Open the catalog panel */
    const open = () => {
        const panel = document.getElementById('event-catalog-panel');
        if (panel) {
            panel.classList.remove('hidden');
            isOpen = true;
            renderCatalog();
        }
    };

    /** Close the catalog panel */
    const close = () => {
        const panel = document.getElementById('event-catalog-panel');
        if (panel) {
            panel.classList.add('hidden');
            isOpen = false;
        }
    };

    /** Toggle open/close */
    const toggle = () => {
        if (isOpen) close(); else open();
    };

    /** Render the catalog cards */
    const renderCatalog = () => {
        const container = document.getElementById('event-catalog-grid');
        if (!container) return;

        let events = EventSimulations.getEventCatalog();

        // Filter
        if (currentFilter !== 'all') {
            events = events.filter(e => e.category === currentFilter);
        }

        // Sort
        switch (currentSort) {
            case 'date-desc':
                events.sort((a, b) => new Date(b.startDate) - new Date(a.startDate));
                break;
            case 'date-asc':
                events.sort((a, b) => new Date(a.startDate) - new Date(b.startDate));
                break;
            case 'severity':
                events.sort((a, b) => (b.areaHectares || 0) - (a.areaHectares || 0));
                break;
            case 'name':
                events.sort((a, b) => a.name.localeCompare(b.name));
                break;
        }

        container.innerHTML = '';

        if (events.length === 0) {
            container.innerHTML = '<div class="ec-empty">No events match the current filter.</div>';
            return;
        }

        events.forEach(evt => {
            const meta = CATEGORY_META[evt.category] || CATEGORY_META.wildfire;
            console.log(`[CatalogUI] Event: ${evt.name}, has3D: ${evt.has3D}, scene3D: ${evt.scene3D}`);
            const card = document.createElement('div');
            card.className = 'ec-card';
            card.dataset.eventId = evt.id;

            const areaStr = evt.areaHectares >= 1000000
                ? `${(evt.areaHectares / 1000000).toFixed(1)}M ha`
                : `${evt.areaHectares.toLocaleString()} ha`;
            const evidenceBadge = evt.evidenceLabel
                ? `<span class="ec-evidence-badge" title="${esc(evt.evidenceNote || evt.evidenceLabel)}">${esc(evt.evidenceLabel)}</span>`
                : '';

            card.innerHTML = `
                <div class="ec-card-thumb" style="background: ${meta.gradient};">
                    <span class="ec-card-icon">${meta.icon}</span>
                </div>
                <div class="ec-card-body">
                    <div class="ec-card-header">
                        <span class="ec-cat-badge ec-cat-${evt.category}">${meta.label}</span>
                        <span class="ec-card-country">${esc(evt.country)}</span>
                    </div>
                    <h4 class="ec-card-title">${esc(evt.name)}</h4>
                    <p class="ec-card-desc">${esc(evt.description)}</p>
                    ${evidenceBadge}
                    <div class="ec-card-meta">
                        <span>${evt.startDate} &mdash; ${evt.endDate}</span>
                        <span>${areaStr}</span>
                    </div>
                    ${evt.has3D ? `<button class="ec-3d-btn" data-scene="${evt.scene3D}" title="Launch immersive 3D simulation">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
                        View in 3D
                    </button>` : ''}
                </div>
            `;

            // Satellite before/after (default click)
            card.addEventListener('click', (e) => {
                if (e.target.closest('.ec-3d-btn')) return; // Don't trigger if 3D button clicked
                EventSimulations.loadEvent(evt.id);
            });

            // 3D simulation button
            if (evt.has3D) {
                const btn3d = card.querySelector('.ec-3d-btn');
                if (btn3d) {
                    btn3d.addEventListener('click', (e) => {
                        e.stopPropagation();
                        launch3DSimulation(evt.scene3D, evt);
                    });
                }
            }

            container.appendChild(card);
        });
    };

    /** Launch the Three.js 3D simulation in a full-screen overlay */
    const launch3DSimulation = (sceneId, evt) => {
        // Close catalog
        close();

        // Create full-screen overlay
        let overlay = document.getElementById('sim-3d-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'sim-3d-overlay';
            overlay.style.cssText = `
                position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                z-index: 10000; background: #000;
            `;
            document.body.appendChild(overlay);
        }

        // Three.js simulation path
        const cacheBust = Date.now();
        const simPath = window.location.href.includes('/assets/')
            ? `../3d_simulations/index.html?v=${cacheBust}#scene=${sceneId}`
            : `/assets/3d_simulations/index.html?v=${cacheBust}#scene=${sceneId}`;

        console.log('[3D] Loading Three.js simulation from:', simPath);

        overlay.innerHTML = `
            <iframe id="sim-3d-iframe"
                src="${simPath}"
                style="width:100%; height:100%; border:none;"
                allow="autoplay"
            ></iframe>
            <button id="sim-3d-exit" style="
                position: fixed; top: 16px; right: 16px; z-index: 10001;
                background: rgba(220,40,40,0.85); color: #fff; border: none;
                padding: 10px 20px; border-radius: 8px; cursor: pointer;
                font-family: Inter, sans-serif; font-size: 13px; font-weight: 600;
                backdrop-filter: blur(8px);
            ">✕ Exit 3D</button>
        `;

        document.getElementById('sim-3d-exit').addEventListener('click', () => {
            overlay.remove();
        });

        console.log(`[EventCatalogUI] Launched 3D simulation: ${sceneId}`);
    };

    /** Bind UI event listeners */
    const bindControls = () => {
        // Open button (sidebar)
        const openBtn = document.getElementById('historical-events-btn');
        if (openBtn) openBtn.addEventListener('click', toggle);

        // Country Intelligence button
        const countryIntelBtn = document.getElementById('country-intelligence-btn');
        if (countryIntelBtn) countryIntelBtn.addEventListener('click', () => {
            EcoLensBridge.sendToFlutter('navigateCountryIntelligence', {});
        });

        // Direct 3D launch buttons — bind all available
        const directLaunchMap = {
            'launch-3d-campfire': 'camp-fire',
            'launch-3d-glacier': 'jakobshavn-glacier',
            'launch-3d-blacksummer': 'black-summer-2019',
            'launch-3d-maui': 'maui-lahaina-2023',
            'launch-3d-canada': 'canada-wildfires-2023',
            'launch-3d-pakistan': 'pakistan-floods-2022',
            'launch-3d-ahr': 'ahr-valley-2021',
            'launch-3d-gangotri': 'gangotri-glacier',
            'launch-3d-amazon': 'amazon-deforestation-2019',
            'launch-3d-drought': 'us-megadrought-2020',
        };
        Object.entries(directLaunchMap).forEach(([btnId, sceneId]) => {
            const btn = document.getElementById(btnId);
            if (btn) btn.addEventListener('click', () => launch3DSimulation(sceneId, null));
        });

        // Close button
        const closeBtn = document.getElementById('ec-close-btn');
        if (closeBtn) closeBtn.addEventListener('click', close);

        // Filter tabs
        const filterBtns = document.querySelectorAll('.ec-filter-btn');
        filterBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                filterBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentFilter = btn.dataset.filter;
                renderCatalog();
            });
        });

        // Sort dropdown
        const sortSelect = document.getElementById('ec-sort');
        if (sortSelect) {
            sortSelect.addEventListener('change', (e) => {
                currentSort = e.target.value;
                renderCatalog();
            });
        }
    };

    /** Initialize — called after DOM ready */
    const init = () => {
        bindControls();
        console.log('[EventCatalogUI] Initialized');
    };

    return { init, open, close, toggle };
})();

window.EventCatalogUI = EventCatalogUI;

// Auto-init when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    EventCatalogUI.init();
});
