import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/core/responsive_layout.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';
import 'package:ecolens/viewmodels/InsightsViewModel.dart';
import 'package:ecolens/viewmodels/navigation_viewmodel.dart';
import 'package:ecolens/widgets/hazard_chip_bar.dart';
import 'package:ecolens/widgets/hazard_detail_card.dart';
import 'package:ecolens/widgets/hazard_filter_panel.dart';
import 'package:ecolens/widgets/hazard_legend.dart';
import 'package:ecolens/views/generate_map_screen.dart';
import 'package:ecolens/views/widgets/atlas_finding_card.dart';
import 'package:ecolens/widgets/generate_map_dialog.dart';

import 'maplibre_web_bridge_stub.dart'
    if (dart.library.html) 'maplibre_web_bridge_web.dart' as web_bridge;

// ═══════════════════════════════════════════════════════════════
// MAPLIBRE MAP SCREEN
// Web map using MapLibre GL JS embedded via InAppWebView
// Replaces the legacy web_map_screen for the web platform
// ═══════════════════════════════════════════════════════════════

/// Route-observer key shared across the app (register in MaterialApp).
final RouteObserver<ModalRoute<void>> mapRouteObserver =
    RouteObserver<ModalRoute<void>>();

class MapLibreMapScreen extends StatefulWidget {
  const MapLibreMapScreen({super.key});

  @override
  State<MapLibreMapScreen> createState() => _MapLibreMapScreenState();
}

class _MapLibreMapScreenState extends State<MapLibreMapScreen>
    with RouteAware, TickerProviderStateMixin {
  InAppWebViewController? _webController;
  web_bridge.WebMapBridgeSubscription? _webBridgeSubscription;

  // Web fly-to delivery: the request is posted to the map iframe and
  // repeated until the page acknowledges its nonce (see
  // _deliverFlyTargetWeb). A null nonce means nothing is in flight.
  Timer? _flyRetryTimer;
  String? _flyPendingNonce;
  int _flySequence = 0;

  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────
  bool _mapReady = false;
  bool _isLoading = true;
  bool _showFilterPanel = false;
  bool _terrain3DEnabled = false;

  // Coordinate display from 'viewChanged'
  double _lat = 0.0;
  double _lon = 0.0;
  double _zoom = 3.0;

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webBridgeSubscription =
          web_bridge.listenToWebMapBridge(_handleBridgePayload);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      mapRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _stopWebFlyDelivery();
    _webBridgeSubscription?.dispose();
    mapRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returned to this screen – refresh if stale
    _refreshIfNeeded();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isMobile(context);

    // Listen for pending fly-to requests from other screens (dashboard pins, etc.)
    final navVm = context.watch<NavigationViewModel>();
    final target = navVm.pendingFlyTarget;
    if (target != null && _webController != null && kIsWeb) {
      // Web: evaluateJavascript is an eval on the iframe window with errors
      // swallowed, and it lands on about:blank until the map document has
      // loaded, so the request is also posted to the frame and repeated until
      // the page acknowledges it. Take the target off the view-model now, not
      // in the callback: a rebuild before the next frame would otherwise
      // schedule the same target twice.
      navVm.clearFlyTarget();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deliverFlyTargetWeb(target);
      });
    } else if (target != null && _webController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final safeLabel = (target.label ?? '').replaceAll("'", "\\'").replaceAll('\n', ' ');
        // Pill keys only: letters, digits, dash. Anything else is dropped
        // rather than interpolated into script.
        final layersJs = '[${target.layers.where((l) => RegExp(r'^[a-z0-9-]+$').hasMatch(l)).map((l) => "'$l'").join(',')}]';
        // The JS side polls for the map to be ready and will retry internally,
        // so we can fire as soon as the controller exists — no need to wait for _mapReady.
        try {
          await _webController?.evaluateJavascript(
            source:
                "console.log('[bridge] ecolensFlyTo called'); "
                "if (window.ecolensFlyTo) { "
                "  window.ecolensFlyTo(${target.lat}, ${target.lng}, ${target.zoom}, '$safeLabel', { layers: $layersJs }); "
                "} else { "
                "  window.__pendingFly = { lat: ${target.lat}, lng: ${target.lng}, zoom: ${target.zoom}, label: '$safeLabel', layers: $layersJs }; "
                "}",
          );
        } catch (e) {
          debugPrint('[MapLibreMapScreen] evaluateJavascript failed: $e');
        }
        navVm.clearFlyTarget();
      });
    }

    // No Scaffold — this widget is embedded inside MainLayout which
    // already provides AppBar and navigation chrome.
    //
    // On WEB: the MapLibre HTML has its own complete UI (sidebar with
    // layer toggles, search, basemap switcher, time slider, legend,
    // historical events catalog). Flutter overlays can't communicate
    // with the iframe, so we only show the map and loading overlay.
    //
    // On MOBILE: full Flutter overlay UI (chip bar, filter panel,
    // legend, detail cards) communicates via JS bridge.
    return Container(
      color: GISTheme.backgroundDark,
      child: Stack(
        children: [
          // Map WebView (full screen on web, with optional sidebar on mobile tablet)
          if (kIsWeb)
            _buildMapWebView()
          else
            isWide ? _buildDesktopLayout() : _buildMobileLayout(),

          // Loading overlay (all platforms)
          if (_isLoading) _buildLoadingOverlay(),

          // ── Mobile-only overlays (JS bridge works) ──
          if (!kIsWeb) ...[
            // Hazard chip bar (top of map)
            if (_mapReady)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: HazardChipBar(
                  onOpenFilterPanel: () =>
                      setState(() => _showFilterPanel = !_showFilterPanel),
                  onFilterDetails: (type) {
                    setState(() => _showFilterPanel = true);
                  },
                ),
              ),

            // Interactive legend (bottom-left)
            if (_mapReady)
              const Positioned(
                bottom: 32,
                left: 12,
                child: HazardLegend(),
              ),

            // Filter panel (slides over map)
            HazardFilterPanel(
              isOpen: _showFilterPanel,
              onClose: () => setState(() => _showFilterPanel = false),
              onRefresh: _handleRefresh,
            ),

            // Selected feature detail card
            _buildDetailCard(),

            // Map controls (right side)
            if (_mapReady) _buildMapControls(),

            // Coordinate display
            if (_mapReady) _buildCoordinateBar(),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUTS
  // ═══════════════════════════════════════════════════════════════

  /// Desktop / tablet: map with a docked sidebar for quick info.
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: GISTheme.surfaceDark,
            border: Border(
              right: BorderSide(color: GISTheme.border),
            ),
          ),
          child: _buildSidebar(),
        ),

        // Map
        Expanded(child: _buildMapWebView()),
      ],
    );
  }

  /// Mobile: full-screen map only.
  Widget _buildMobileLayout() {
    return _buildMapWebView();
  }

  /// Sidebar shown on tablet / desktop.
  Widget _buildSidebar() {
    final vm = context.watch<HazardViewModel>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Active Layers', style: GISTheme.headingMedium),
        const SizedBox(height: 12),

        for (final type in HazardType.values)
          if (vm.layerVisibility[type] == true)
            _SidebarLayerTile(
              type: type,
              count: vm.getFeatureCount(type),
              onTap: () => vm.toggleLayer(type),
            ),

        if (vm.layerVisibility.values.every((v) => !v))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No layers active.\nOpen the filter panel to enable layers.',
              textAlign: TextAlign.center,
              style: GISTheme.bodySmall,
            ),
          ),

        const SizedBox(height: 16),

        if (vm.lastRefresh != null)
          Text(
            'Last refresh: ${_formatTime(vm.lastRefresh!)}',
            style: GISTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WEBVIEW – MapLibre GL JS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMapWebView() {
    final useUrl = kIsWeb;
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    // Shared-link support: a ?mapstate=<permalink-hash> on the outer app URL
    // is forwarded to the map as its own #hash, which permalink.js applies
    // (camera, layers, time window, basemap).
    final mapState = Uri.base.queryParameters['mapstate'];
    final stateHash = (mapState != null && mapState.isNotEmpty)
        ? '#${Uri.decodeComponent(mapState)}'
        : '';
    final assetUrl = useUrl
        // Flutter bundles pubspec assets under /assets/<original-path>, so the
        // real URL is /assets/assets/maplibre_map/index.html. The previous path
        // was falling through Firebase's wildcard rewrite and serving the
        // Flutter app inside its own iframe.
        ? Uri.base
            .resolve('assets/assets/maplibre_map/index.html?v=$cacheBust$stateHash')
            .toString()
        : null;

    return InAppWebView(
      initialUrlRequest: useUrl ? URLRequest(url: WebUri(assetUrl!)) : null,
      initialFile: useUrl ? null : 'assets/maplibre_map/index.html',
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: false,
        useWideViewPort: true,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) {
        _webController = controller;
        _registerHandlers(controller);
      },
      onLoadStop: (controller, url) {
        debugPrint('MapLibre page loaded');
      },
      onReceivedError: (controller, request, error) {
        debugPrint('MapLibre load error: ${error.description}');
        setState(() => _isLoading = false);
      },
      onProgressChanged: (controller, progress) {
        // optional progress tracking
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // JAVASCRIPT BRIDGE
  // ═══════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────
  // Web fly-to delivery (parent → iframe)
  // ─────────────────────────────────────────────────────────────

  /// Deliver [target] to the map page on Flutter Web.
  ///
  /// Two routes carry the same nonce-stamped request. postMessage is the
  /// reliable one: the browser hands it to whichever document the iframe
  /// holds, so it is repeated every 700 ms until the page answers with a
  /// `flyAck` for this nonce, or 15 s pass. evaluateJavascript is kept as
  /// the immediate route for an already-loaded frame; it hands the request
  /// to the same page handler, which ignores a nonce it has already flown,
  /// so a request never flies twice however many copies arrive.
  void _deliverFlyTargetWeb(MapFlyTarget target) {
    _stopWebFlyDelivery();
    // requestedAt alone is unique in practice; the sequence keeps two
    // targets created in the same millisecond apart.
    final nonce =
        '${target.requestedAt.millisecondsSinceEpoch}-${_flySequence++}';
    final message = <String, dynamic>{
      'type': 'ecolens_fly_to',
      'lat': target.lat,
      'lng': target.lng,
      'zoom': target.zoom,
      'label': target.label,
      'layers': List<String>.from(target.layers),
      'nonce': nonce,
    };
    _flyPendingNonce = nonce;

    // Immediate route. jsonEncode yields a valid JS object literal, so the
    // label needs no hand escaping here. Not awaited: the retry loop below
    // must start whether or not the eval reaches a loaded document.
    unawaited(_evalFlyRequest(jsonEncode(message)));

    // Reliable route, repeated until acknowledged.
    final startedAt = DateTime.now();
    void post() {
      if (!web_bridge.postToWebMap(message)) {
        debugPrint('[MapLibreMapScreen] fly $nonce: map iframe not found yet');
      }
    }

    post();
    _flyRetryTimer =
        Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted || _flyPendingNonce != nonce) {
        timer.cancel();
        return;
      }
      if (DateTime.now().difference(startedAt) >=
          const Duration(seconds: 15)) {
        debugPrint(
          '[MapLibreMapScreen] fly $nonce: no flyAck after 15 s, giving up',
        );
        _stopWebFlyDelivery();
        return;
      }
      post();
    });
  }

  Future<void> _evalFlyRequest(String messageJs) async {
    try {
      await _webController?.evaluateJavascript(
        source: 'if (window.__ecolensHandleFly) { '
            'window.__ecolensHandleFly($messageJs); '
            '} else { window.__pendingFly = $messageJs; }',
      );
    } catch (e) {
      debugPrint('[MapLibreMapScreen] evaluateJavascript failed: $e');
    }
  }

  /// Stop the retry loop; called on ack, on a newer target, and on dispose.
  void _stopWebFlyDelivery() {
    _flyRetryTimer?.cancel();
    _flyRetryTimer = null;
    _flyPendingNonce = null;
  }

  void _handleBridgePayload(Map<String, dynamic> payload) {
    if (!mounted) return;

    final event = payload['event'] as String? ?? '';
    final data = payload['data'];

    switch (event) {
      case 'mapReady':
        final wasReady = _mapReady;
        setState(() {
          _mapReady = true;
          _isLoading = false;
        });
        if (!kIsWeb && !wasReady) {
          _initializeMapData();
        }
        break;
      case 'viewChanged':
        if (data is Map) {
          final view = Map<String, dynamic>.from(data);
          setState(() {
            _lat = (view['lat'] as num?)?.toDouble() ?? _lat;
            _lon = (view['lon'] as num?)?.toDouble() ?? _lon;
            _zoom = (view['zoom'] as num?)?.toDouble() ?? _zoom;
          });
        }
        break;
      case 'featureSelected':
        if (data is Map) {
          try {
            final raw = Map<String, dynamic>.from(data);
            final feature = HazardFeature.fromJson(raw);
            context.read<HazardViewModel>().selectFeature(feature);
          } catch (e) {
            debugPrint('[MapLibreMapScreen] featureSelected parse error: $e');
          }
        }
        break;
      case 'hazardAlert':
        if (data is Map) {
          _showHazardNotification(Map<String, dynamic>.from(data));
        }
        break;
      case 'eventSelected':
        if (data is Map) {
          final selected = Map<String, dynamic>.from(data);
          context.read<InsightsViewModel>().selectMapEvent(selected);
          debugPrint(
            '[MapLibreMapScreen] Event selected: '
            '${selected['id'] ?? selected['title'] ?? 'unknown'}',
          );
        }
        break;
      case 'openEventInsights':
      case 'openHistoricalEventInsights':
        if (data is Map) {
          final selected = Map<String, dynamic>.from(data);
          context.read<InsightsViewModel>().selectMapEvent(selected);
          context.read<NavigationViewModel>().setIndex(2);
        }
        break;
      // Ask-the-Map escalation: the map answered what it can show, and Atlas
      // produced the full comparison. Store it either way; only jump to
      // Insights when the reader asked for it, so a background run never
      // yanks the screen out from under them.
      case 'atlasFinding':
        if (data is Map) {
          final payload = Map<String, dynamic>.from(data);
          final raw = payload['finding'];
          if (raw is Map) {
            try {
              final finding = AtlasFinding.fromJson(
                Map<String, dynamic>.from(raw),
              );
              context.read<InsightsViewModel>().addAtlasFinding(finding);
              if (payload['navigate'] == true) {
                context.read<NavigationViewModel>().setIndex(2);
              }
            } catch (e) {
              debugPrint('[MapLibreMapScreen] atlasFinding parse error: $e');
            }
          }
        }
        break;
      // The map page handled a fly-to request delivered by postMessage;
      // stop repeating that request (see _deliverFlyTargetWeb).
      case 'flyAck':
        if (data is Map && '${data['nonce']}' == _flyPendingNonce) {
          _stopWebFlyDelivery();
        }
        break;
      // A story link on the map (event brief, pin) carries the GDACS guid of
      // the news item; Insights resolves and opens it.
      case 'openNewsStory':
        if (data is Map) {
          var id = (data['id'] ?? '').toString().trim();
          // The wire mirror may predate the id property: derive the GDACS guid
          // (eventtype + eventid) from the report URL instead of doing nothing.
          if (id.isEmpty) {
            final uri = Uri.tryParse((data['url'] ?? '').toString());
            final type = (uri?.queryParameters['eventtype'] ?? '').trim();
            final eventId = (uri?.queryParameters['eventid'] ?? '').trim();
            if (type.isNotEmpty && eventId.isNotEmpty) id = '$type$eventId';
          }
          if (id.isNotEmpty) {
            context.read<InsightsViewModel>().openNewsById(id);
            context.read<NavigationViewModel>().setIndex(2);
          }
        }
        break;
      case 'navigateCountryIntelligence':
        Navigator.of(context).pushNamed('/country');
        break;
      // The map's masthead (ChromeShell) replaces the AppBar on this tab,
      // so its menu / generate buttons round-trip through the bridge.
      case 'openDrawer':
        Scaffold.maybeOf(context)?.openDrawer();
        break;
      case 'openGenerateMap':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GenerateMapScreen()),
        );
        break;
      // The map composed a shareable 1200×630 card (map-card.js) — hand
      // the PNG to the native share sheet. Mobile WebView only; on web
      // the JS side downloads the file itself and never sends this.
      case 'mapCard':
        if (data is Map) {
          _shareMapCard(Map<String, dynamic>.from(data));
        }
        break;
      case 'error':
        setState(() => _isLoading = false);
        debugPrint('[MapLibreMapScreen] map error: $data');
        break;
    }
  }

  /// Decode the PNG data URL from map-card.js and open the share sheet.
  Future<void> _shareMapCard(Map<String, dynamic> data) async {
    try {
      final dataUrl = data['dataUrl'] as String? ?? '';
      final name = data['name'] as String? ?? 'ecolens-map.png';
      final comma = dataUrl.indexOf(',');
      if (comma < 0) return;
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
        subject: 'EcoLens map card',
      ));
    } catch (e) {
      debugPrint('[MapLibreMapScreen] mapCard share failed: $e');
    }
  }

  void _registerHandlers(InAppWebViewController controller) {
    // On Flutter Web, addJavaScriptHandler is NOT supported by
    // flutter_inappwebview (the web InAppWebView uses an iframe).
    // The MapLibre map has its own complete UI (sidebar, filters,
    // time slider, popups) so it works standalone. We just need to
    // mark the map as ready after a short delay on web.
    if (kIsWeb) {
      // The map's JS posts a `mapReady` event the moment MapLibre's first
      // frame paints (see flutter-bridge.js → window.parent.postMessage).
      // That signal lands in [_handleBridgePayload] via web_bridge and flips
      // both flags then. The timer below is a safety floor in case the
      // postMessage path is blocked (sandboxed iframe, etc.) — short and
      // guarded so a working bridge always wins.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _isLoading) {
          setState(() => _isLoading = false);
        }
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && !_mapReady) {
          setState(() => _mapReady = true);
        }
      });
      return;
    }

    // ── Mobile (Android/iOS): full bidirectional JS bridge ──

    // Map finished initializing
    controller.addJavaScriptHandler(
      handlerName: 'mapReady',
      callback: (args) {
        debugPrint('MapLibre mapReady');
        setState(() {
          _mapReady = true;
          _isLoading = false;
        });
        _initializeMapData();
        return null;
      },
    );

    // User clicked on a hazard feature
    controller.addJavaScriptHandler(
      handlerName: 'featureSelected',
      callback: (args) {
        if (args.isNotEmpty && args[0] is Map) {
          final raw = Map<String, dynamic>.from(args[0] as Map);
          final feature = HazardFeature.fromJson(raw);
          context.read<HazardViewModel>().selectFeature(feature);
        }
        return null;
      },
    );

    // A new hazard alert came in (from map real-time layer)
    controller.addJavaScriptHandler(
      handlerName: 'hazardAlert',
      callback: (args) {
        if (args.isNotEmpty && args[0] is Map) {
          final raw = Map<String, dynamic>.from(args[0] as Map);
          _showHazardNotification(raw);
        }
        return null;
      },
    );

    // Camera moved – update coordinate display
    controller.addJavaScriptHandler(
      handlerName: 'viewChanged',
      callback: (args) {
        if (args.isNotEmpty && args[0] is Map) {
          final data = Map<String, dynamic>.from(args[0] as Map);
          setState(() {
            _lat = (data['lat'] as num?)?.toDouble() ?? _lat;
            _lon = (data['lon'] as num?)?.toDouble() ?? _lon;
            _zoom = (data['zoom'] as num?)?.toDouble() ?? _zoom;
          });
        }
        return null;
      },
    );

    // Unified event dispatcher from JS bridge (onMapEvent)
    controller.addJavaScriptHandler(
      handlerName: 'onMapEvent',
      callback: (args) {
        if (args.isNotEmpty) {
          try {
            final payload = args[0] is String
                ? jsonDecode(args[0] as String) as Map<String, dynamic>
                : Map<String, dynamic>.from(args[0] as Map);
            _handleBridgePayload(payload);
          } catch (e) {
            debugPrint('onMapEvent parse error: $e');
          }
        }
        return null;
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Commands → JavaScript
  // ─────────────────────────────────────────────────────────────

  /// Toggle a named layer on the map.
  Future<void> toggleLayer(String layerName, bool visible) async {
    await _webController?.evaluateJavascript(
      source: 'window.toggleLayer("$layerName", $visible);',
    );
  }

  /// Apply a filter expression to a named layer.
  Future<void> setFilter(
      String layerName, Map<String, dynamic> filter) async {
    final json = jsonEncode(filter);
    await _webController?.evaluateJavascript(
      source: 'window.setLayerFilter("$layerName", $json);',
    );
  }

  /// Fly the camera to a coordinate.
  Future<void> flyTo(double lat, double lon, double zoom) async {
    await _webController?.evaluateJavascript(
      source: 'window.flyTo($lat, $lon, $zoom);',
    );
  }

  /// Load GeoJSON data for a hazard type onto the map.
  Future<void> loadHazardData(
      String hazardType, Map<String, dynamic> geojson) async {
    final json = jsonEncode(geojson);
    await _webController?.evaluateJavascript(
      source: 'window.loadHazardData("$hazardType", $json);',
    );
  }

  /// Toggle 3D terrain on/off.
  Future<void> _toggle3DTerrain() async {
    setState(() => _terrain3DEnabled = !_terrain3DEnabled);
    await _webController?.evaluateJavascript(
      source: 'window.toggle3DTerrain($_terrain3DEnabled);',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA INIT & REFRESH
  // ═══════════════════════════════════════════════════════════════

  /// Push all visible layer data into the map after it loads.
  void _initializeMapData() {
    final vm = context.read<HazardViewModel>();

    // Provide a default world bounding box for the initial load
    const defaultBounds = LatLngBounds(
      south: -60,
      west: -180,
      north: 75,
      east: 180,
    );

    vm.refreshAllData(defaultBounds).then((_) {
      _pushAllLayersToMap(vm);
    });

    vm.startAutoRefresh();
  }

  void _pushAllLayersToMap(HazardViewModel vm) {
    for (final type in HazardType.values) {
      if (vm.layerVisibility[type] == true) {
        final geojson = vm.getHazardGeoJSON(type);
        loadHazardData(type.name, geojson);
      }
    }
  }

  Future<void> _handleRefresh() async {
    final vm = context.read<HazardViewModel>();

    // Use current view bounds if available, else default
    final bounds = LatLngBounds(
      south: _lat - 10,
      west: _lon - 10,
      north: _lat + 10,
      east: _lon + 10,
    );

    await vm.refreshAllData(bounds);
    _pushAllLayersToMap(vm);
  }

  void _refreshIfNeeded() {
    final vm = context.read<HazardViewModel>();
    if (vm.lastRefresh == null) return;
    final elapsed = DateTime.now().difference(vm.lastRefresh!);
    if (elapsed > const Duration(minutes: 5)) {
      _handleRefresh();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // NOTIFICATION
  // ═══════════════════════════════════════════════════════════════

  void _showHazardNotification(Map<String, dynamic> alertData) {
    if (!mounted) return;

    final type = alertData['type'] as String? ?? 'unknown';
    final msg = alertData['message'] as String? ?? 'New hazard alert';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '[$type] $msg',
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: GISTheme.surfaceLight,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OVERLAY WIDGETS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLoadingOverlay() {
    return Container(
      color: GISTheme.backgroundDark,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: GISTheme.accentBlue),
            SizedBox(height: 16),
            Text(
              'Initializing map...',
              style: TextStyle(color: GISTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard() {
    final vm = context.watch<HazardViewModel>();
    final feature = vm.selectedFeature;

    if (feature == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: HazardDetailCard(
        feature: feature,
        onDismiss: () => vm.clearSelection(),
        // Monitor and share are not wired yet, so the card omits both
        // buttons rather than offering controls that do nothing.
      ),
    );
  }

  Widget _buildCoordinateBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: GISTheme.surfaceDark.withValues(alpha: 0.8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Lat ${_lat.toStringAsFixed(4)}  '
                'Lon ${_lon.toStringAsFixed(4)}  '
                'Zoom ${_zoom.toStringAsFixed(1)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: GISTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MAP CONTROL BUTTONS (right side, vertical stack)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMapControls() {
    return Positioned(
      right: 12,
      bottom: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 3D terrain toggle
          _MapControlButton(
            icon: Icons.terrain,
            tooltip: '3D Terrain',
            active: _terrain3DEnabled,
            onTap: _toggle3DTerrain,
          ),
          const SizedBox(height: 8),

          // Refresh data
          _MapControlButton(
            icon: Icons.refresh,
            tooltip: 'Refresh data',
            onTap: _handleRefresh,
          ),
          const SizedBox(height: 8),

          // Generate Cartographic Map
          _MapControlButton(
            icon: Icons.auto_awesome,
            tooltip: 'Generate Map',
            onTap: () {
              // Use current map view as bbox
              final bbox = [
                _lon - 10.0, _lat - 8.0,
                _lon + 10.0, _lat + 8.0,
              ];
              GenerateMapDialog.show(
                context,
                bbox: bbox,
                theme: 'multi_hazard',
                title: 'Environmental Analysis',
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────
// Sidebar layer tile (desktop only)
// ─────────────────────────────────────────────────────────────

class _SidebarLayerTile extends StatelessWidget {
  final HazardType type;
  final int count;
  final VoidCallback onTap;

  const _SidebarLayerTile({
    required this.type,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: type.color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(type.icon, color: type.color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                type.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: GISTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: type.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: type.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small circular map control button (terrain, refresh, etc.)
// ─────────────────────────────────────────────────────────────

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? GISTheme.accentBlue.withValues(alpha: 0.25)
            : GISTheme.surfaceDark.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: active ? GISTheme.accentBlue : GISTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
