// ============================================================
// EcoLens ChromeShell — the structural chrome of the map screen
//
// Implements the approved editorial layout:
//   - one masthead (brand · omnibox slot · live status · actions)
//     replacing both the floating map-header card and (on the Map
//     tab) the Flutter AppBar, which Dart hides
//   - a 46px icon rail; the old 360px sidebar becomes a summoned
//     flyout (closed by default — the map owns the pixels)
//   - the Event Queue as a summoned drawer: closed until the user
//     asks for it or clicks a feature (selection auto-opens it)
//
// All existing DOM/services stay: this module adds a shell around
// them and mirrors live values (status text, event count) via
// MutationObserver, so the legacy update paths keep working.
// ============================================================

const ChromeShell = (function () {
    'use strict';

    let flyoutOpen = false;
    let drawerOpen = false;

    const el = (id) => document.getElementById(id);

    function sendToFlutter(event, data) {
        try {
            if (window.EcoLensBridge && window.EcoLensBridge.sendToFlutter) {
                window.EcoLensBridge.sendToFlutter(event, data || {});
            } else if (window.parent && window.parent !== window) {
                window.parent.postMessage(
                    { source: 'ecolens-map', event, data: data || {} }, '*');
            }
        } catch (e) { /* no shell to talk to */ }
    }

    // ---------- Masthead ----------

    function buildMasthead() {
        if (el('masthead')) return;
        const bar = document.createElement('header');
        bar.id = 'masthead';
        bar.innerHTML =
            '<button id="mh-menu" title="Menu" aria-label="Open menu">☰</button>' +
            '<div class="mh-brand">' +
                '<span class="mh-name">EcoLens</span>' +
                '<span class="mh-ed">Environmental Intelligence</span>' +
            '</div>' +
            '<div id="masthead-center"></div>' +
            '<div class="mh-right">' +
                '<span class="mh-live"><i></i><span id="mh-status">Live</span></span>' +
                '<button id="mh-events" title="Event queue">Events <b id="mh-events-count">0</b></button>' +
                '<button id="mh-card" title="Export a shareable map card">Map card</button>' +
                '<button id="mh-generate" title="Generate cartographic map">Generate map</button>' +
            '</div>';
        document.body.appendChild(bar);

        el('mh-menu').addEventListener('click', () => sendToFlutter('openDrawer'));
        el('mh-generate').addEventListener('click', () => sendToFlutter('openGenerateMap'));
        el('mh-card').addEventListener('click', () => {
            if (window.MapCard) window.MapCard.download();
        });
        el('mh-events').addEventListener('click', toggleDrawer);

        // Mirror the legacy live-status line and event count wherever the
        // existing code writes them.
        mirrorText('map-header-meta', 'mh-status', v => v || 'Live');
        mirrorText('alerts-count', 'mh-events-count', v => v || '0');
    }

    function mirrorText(sourceId, targetId, transform) {
        const source = el(sourceId), target = el(targetId);
        if (!source || !target) return;
        const sync = () => { target.textContent = transform(source.textContent.trim()); };
        sync();
        new MutationObserver(sync).observe(source, {
            childList: true, characterData: true, subtree: true,
        });
    }

    // ---------- Icon rail ----------

    const RAIL_BUTTONS = [
        { id: 'rail-layers', label: 'Layers & data', glyph: '▤', action: toggleFlyout },
        { id: 'rail-events', label: 'Event queue & anomalies', glyph: 'σ', action: toggleDrawer },
        { id: 'rail-atlas', label: 'Atlas analyst', glyph: '◈', action: openAtlas },
        { id: 'rail-history', label: 'Replay the archive', glyph: '⏱', action: toggleHistory },
        { id: 'rail-compare', label: 'Compare with last week', glyph: '⇔', action: toggleCompare },
    ];

    function buildRail() {
        if (el('icon-rail')) return;
        const rail = document.createElement('nav');
        rail.id = 'icon-rail';
        rail.setAttribute('aria-label', 'Map tools');
        rail.innerHTML = RAIL_BUTTONS.map(b =>
            '<button id="' + b.id + '" data-tip="' + b.label + '" aria-label="' + b.label + '">' +
            b.glyph + '</button>'
        ).join('') + '<span class="rail-foot" id="rail-archive">Archive</span>';
        document.body.appendChild(rail);
        for (const b of RAIL_BUTTONS) {
            el(b.id).addEventListener('click', b.action);
        }
        // Compact archive-day count in the rail foot
        const badge = el('archive-badge');
        if (badge) {
            const sync = () => {
                const m = badge.textContent.match(/(\d+)\s*day/);
                el('rail-archive').textContent = m ? 'Day ' + m[1] : 'Archive';
            };
            sync();
            new MutationObserver(sync).observe(badge, {
                childList: true, characterData: true, subtree: true,
            });
        }
    }

    // ---------- Panel state ----------

    function toggleFlyout(force) {
        flyoutOpen = typeof force === 'boolean' ? force : !flyoutOpen;
        document.body.classList.toggle('flyout-open', flyoutOpen);
        const btn = el('rail-layers');
        if (btn) btn.classList.toggle('on', flyoutOpen);
    }

    function toggleDrawer(force) {
        drawerOpen = typeof force === 'boolean' ? force : !drawerOpen;
        document.body.classList.toggle('drawer-open', drawerOpen);
        const btn = el('rail-events');
        if (btn) btn.classList.toggle('on', drawerOpen);
    }

    function openAtlas() {
        const section = el('atlas-section');
        if (!section || section.style.display === 'none') {
            alert('The Atlas analyst engine is offline. Start it locally with: atlas-agent serve');
            return;
        }
        toggleFlyout(true);
        section.scrollIntoView({ behavior: 'smooth', block: 'start' });
        const input = el('atlas-prompt');
        if (input) input.focus();
    }

    function toggleHistory() {
        if (!window.TimePlayback) return;
        if (window.TimePlayback.isActive()) window.TimePlayback.exit();
        else window.TimePlayback.enter();
        el('rail-history').classList.toggle('on', window.TimePlayback.isActive());
    }

    function toggleCompare() {
        if (!window.SwipeCompare) return;
        if (window.SwipeCompare.isActive()) {
            window.SwipeCompare.stop();
        } else {
            window.SwipeCompare.compareFiresWithLastWeek();
        }
        el('rail-compare').classList.toggle('on', window.SwipeCompare.isActive());
    }

    // Selection summons the drawer: wrap the legacy drawer API so a feature
    // click opens the Event Queue on its "Selected" tab automatically.
    function hookSelectionSummon() {
        const drawer = window.EcoLensDrawer;
        if (!drawer || drawer.__shellWrapped) return;
        drawer.__shellWrapped = true;
        const originalRender = drawer.renderSelected;
        if (typeof originalRender === 'function') {
            drawer.renderSelected = function () {
                toggleDrawer(true);
                return originalRender.apply(this, arguments);
            };
        }
    }

    // ---------- Init ----------

    function init() {
        document.body.classList.add('rail-mode');
        buildMasthead();
        buildRail();
        hookSelectionSummon();
        // On desktop the Event Queue is a docked fixture, not a summoned
        // overlay — the map, bottom bar and rail cede its 320px. Users can
        // still dismiss it with the Events button; phones start closed.
        if (window.innerWidth > 1100) toggleDrawer(true);
        // The legacy floating pieces the masthead replaces
        const legacyHeader = el('map-header');
        if (legacyHeader) legacyHeader.style.display = 'none';
        const legacyToggle = el('sidebar-toggle');
        if (legacyToggle) legacyToggle.style.display = 'none';
        // Atlas rail button greys out until the engine responds
        setTimeout(() => {
            const section = el('atlas-section');
            const btn = el('rail-atlas');
            if (btn && (!section || section.style.display === 'none')) {
                btn.classList.add('disabled');
            }
        }, 5000);
        console.log('[ChromeShell] Masthead + rail active');
    }

    return { init, toggleFlyout, toggleDrawer, isDrawerOpen: () => drawerOpen };
})();

window.ChromeShell = ChromeShell;
