import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ecolens/core/gis_theme.dart';

// ═══════════════════════════════════════════════════════════════
// UNITY SIMULATION SCREEN
// Embeds a Unity WebGL build for 3D environmental simulations
// (wildfire spread, flood inundation, drought, glacial retreat)
// ═══════════════════════════════════════════════════════════════

class UnitySimulationScreen extends StatefulWidget {
  /// One of: 'wildfire', 'flood', 'drought', 'glacialRetreat'
  final String simulationType;

  final String locationName;
  final double latitude;
  final double longitude;

  /// Optional URL to a DEM heightmap for terrain.
  final String? demUrl;

  /// Start of the simulation time range.
  final DateTime? timeStart;

  /// End of the simulation time range.
  final DateTime? timeEnd;

  /// Arbitrary event-specific metadata passed to Unity.
  final Map<String, dynamic>? metadata;

  /// Path to the Unity WebGL build index page.
  /// Defaults to a bundled asset; override to point at an external URL.
  final String? unityBuildPath;

  /// Geographic bounding box [west, south, east, north] for accurate terrain.
  final List<double>? bbox;

  /// Real-world terrain width in metres (E-W extent).
  final double? terrainWidthM;

  /// Real-world terrain height in metres (N-S extent).
  final double? terrainHeightM;

  /// Min/max elevation from DEM (metres above sea level).
  final double? minElevation;
  final double? maxElevation;

  const UnitySimulationScreen({
    super.key,
    required this.simulationType,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    this.demUrl,
    this.timeStart,
    this.timeEnd,
    this.metadata,
    this.unityBuildPath,
    this.bbox,
    this.terrainWidthM,
    this.terrainHeightM,
    this.minElevation,
    this.maxElevation,
  });

  @override
  State<UnitySimulationScreen> createState() => _UnitySimulationScreenState();
}

class _UnitySimulationScreenState extends State<UnitySimulationScreen> {
  InAppWebViewController? _webController;

  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────
  bool _isLoading = true;
  double _loadProgress = 0.0;
  bool _simulationReady = false;
  bool _isPlaying = false;
  double _timelineProgress = 0.0;
  String? _errorMessage;
  String _cameraMode = 'orbit';

  static const List<String> _cameraModes = [
    'orbit',
    'flyover',
    'firstPerson',
    'top',
  ];

  static const Map<String, String> _cameraModeLabels = {
    'orbit': 'Orbit',
    'flyover': 'Flyover',
    'firstPerson': 'First Person',
    'top': 'Top Down',
  };

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Immersive mode: hide system UI for full-screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore system UI when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Unity WebGL WebView
          _buildWebView(),

          // Loading overlay
          if (_isLoading) _buildLoadingOverlay(),

          // Error overlay
          if (_errorMessage != null) _buildErrorOverlay(),

          // Flutter overlay controls (on top of WebView)
          if (_simulationReady && _errorMessage == null) ...[
            // Back button (top-left)
            _buildBackButton(),

            // Info card (top-right)
            _buildInfoCard(),

            // Camera mode selector (top-center-right)
            _buildCameraModeSelector(),

            // Play/Pause FAB (bottom-right)
            _buildPlayPauseButton(),

            // Timeline slider (bottom)
            _buildTimelineSlider(),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WEBVIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWebView() {
    final buildPath = widget.unityBuildPath ?? 'assets/3d_simulations/index.html';

    // On web, resolve the asset path to a full URL so the iframe loads correctly
    final isLocalAsset = !buildPath.startsWith('http');
    final useUrl = kIsWeb && isLocalAsset;
    final resolvedUrl = useUrl
        ? Uri.base.resolve(buildPath).toString()
        : buildPath;

    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        useWideViewPort: true,
        supportZoom: false,
      ),
      initialUrlRequest: (buildPath.startsWith('http') || useUrl)
          ? URLRequest(url: WebUri(useUrl ? resolvedUrl : buildPath))
          : null,
      initialFile: (buildPath.startsWith('http') || useUrl) ? null : buildPath,
      onWebViewCreated: (controller) {
        _webController = controller;
        _registerJavaScriptHandlers(controller);
      },
      onLoadStart: (controller, url) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      },
      onProgressChanged: (controller, progress) {
        setState(() => _loadProgress = progress / 100.0);
      },
      onLoadStop: (controller, url) {
        // WebView loaded; Unity itself will signal 'simulationReady'
        debugPrint('Unity WebGL page loaded');
      },
      onReceivedError: (controller, request, error) {
        setState(() {
          _errorMessage =
              'Failed to load Unity simulation: ${error.description}';
          _isLoading = false;
        });
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('Unity console: ${consoleMessage.message}');
        // Detect WebGL not supported
        if (consoleMessage.message.contains('WebGL') &&
            consoleMessage.message.toLowerCase().contains('not supported')) {
          setState(() {
            _errorMessage =
                'WebGL is not supported on this device. '
                'Please use a modern browser with hardware acceleration enabled.';
            _isLoading = false;
          });
        }
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // JAVASCRIPT BRIDGE
  // ═══════════════════════════════════════════════════════════════

  void _registerJavaScriptHandlers(InAppWebViewController controller) {
    // Unity signals it is ready to receive simulation parameters
    controller.addJavaScriptHandler(
      handlerName: 'simulationReady',
      callback: (args) {
        debugPrint('Unity simulation ready');
        setState(() {
          _simulationReady = true;
          _isLoading = false;
        });
        _sendSimulationParams();
        return null;
      },
    );

    // Unity reports timeline progress (0.0 - 1.0)
    controller.addJavaScriptHandler(
      handlerName: 'simulationProgress',
      callback: (args) {
        if (args.isNotEmpty) {
          final progress = (args[0] as num?)?.toDouble() ?? 0.0;
          setState(() => _timelineProgress = progress.clamp(0.0, 1.0));
        }
        return null;
      },
    );

    // Simulation has finished playing
    controller.addJavaScriptHandler(
      handlerName: 'simulationComplete',
      callback: (args) {
        setState(() {
          _isPlaying = false;
          _timelineProgress = 1.0;
        });
        return null;
      },
    );

    // Camera position changed inside Unity
    controller.addJavaScriptHandler(
      handlerName: 'cameraChanged',
      callback: (args) {
        // Can be used to sync Flutter UI if needed
        return null;
      },
    );
  }

  /// Push simulation configuration into the Unity runtime.
  Future<void> _sendSimulationParams() async {
    final params = {
      'simulationType': widget.simulationType,
      'location': {
        'lat': widget.latitude,
        'lon': widget.longitude,
        'name': widget.locationName,
      },
      if (widget.demUrl != null) 'demUrl': widget.demUrl,
      'timeRange': {
        'start': (widget.timeStart ?? DateTime.now().subtract(const Duration(days: 30)))
            .toIso8601String(),
        'end': (widget.timeEnd ?? DateTime.now()).toIso8601String(),
      },
      if (widget.metadata != null) 'metadata': widget.metadata,
      // Geographic accuracy data for precise terrain placement
      'originLat': widget.latitude,
      'originLon': widget.longitude,
      if (widget.terrainWidthM != null) 'terrainWidthM': widget.terrainWidthM,
      if (widget.terrainHeightM != null) 'terrainHeightM': widget.terrainHeightM,
      if (widget.minElevation != null) 'minElevation': widget.minElevation,
      if (widget.maxElevation != null) 'maxElevation': widget.maxElevation,
      if (widget.bbox != null) 'bbox': widget.bbox,
    };

    final json = jsonEncode(params);
    await _webController?.evaluateJavascript(
      source: 'window.initSimulation($json);',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTROLS → Unity commands
  // ═══════════════════════════════════════════════════════════════

  Future<void> _togglePlayPause() async {
    setState(() => _isPlaying = !_isPlaying);
    await _webController?.evaluateJavascript(
      source: _isPlaying
          ? 'window.playSimulation();'
          : 'window.pauseSimulation();',
    );
  }

  Future<void> _seekTimeline(double value) async {
    setState(() => _timelineProgress = value);
    await _webController?.evaluateJavascript(
      source: 'window.seekSimulation($value);',
    );
  }

  Future<void> _setCameraMode(String mode) async {
    setState(() => _cameraMode = mode);
    await _webController?.evaluateJavascript(
      source: 'window.setCameraMode("$mode");',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OVERLAY WIDGETS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(seconds: 2),
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 6.28,
                  child: child,
                );
              },
              onEnd: () {},
              child: Icon(
                _simulationIcon,
                color: _simulationColor,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Loading ${widget.simulationType} simulation...',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: GISTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Progress bar
            SizedBox(
              width: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _loadProgress > 0 ? _loadProgress : null,
                  backgroundColor: GISTheme.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(_simulationColor),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loadProgress > 0)
              Text(
                '${(_loadProgress * 100).round()}%',
                style: GISTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: GISTheme.accentRed,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Simulation Error',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: GISTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'An unknown error occurred.',
                textAlign: TextAlign.center,
                style: GISTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GISTheme.surfaceLight,
                  foregroundColor: GISTheme.textPrimary,
                ),
                child: const Text('Return to Map'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _simulationColor.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_simulationIcon, color: _simulationColor, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _simulationLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.locationName,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white70,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.latitude.toStringAsFixed(4)}, '
              '${widget.longitude.toStringAsFixed(4)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraModeSelector() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      right: 12,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GISTheme.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _cameraMode,
            dropdownColor: GISTheme.surfaceDark,
            icon: const Icon(Icons.videocam, color: Colors.white70, size: 16),
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
            items: _cameraModes.map((mode) {
              return DropdownMenuItem(
                value: mode,
                child: Text(_cameraModeLabels[mode] ?? mode),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) _setCameraMode(value);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Positioned(
      bottom: 80,
      right: 16,
      child: FloatingActionButton(
        onPressed: _togglePlayPause,
        backgroundColor: _simulationColor.withValues(alpha: 0.85),
        child: Icon(
          _isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildTimelineSlider() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GISTheme.border),
        ),
        child: Row(
          children: [
            Text(
              '${(_timelineProgress * 100).round()}%',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: _simulationColor,
                  inactiveTrackColor: GISTheme.border,
                  thumbColor: _simulationColor,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: _timelineProgress,
                  onChanged: _seekTimeline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  IconData get _simulationIcon {
    switch (widget.simulationType) {
      case 'wildfire':
        return Icons.local_fire_department;
      case 'flood':
        return Icons.water;
      case 'drought':
        return Icons.wb_sunny;
      case 'glacialRetreat':
        return Icons.ac_unit;
      default:
        return Icons.terrain;
    }
  }

  Color get _simulationColor {
    switch (widget.simulationType) {
      case 'wildfire':
        return const Color(0xFFFF4500);
      case 'flood':
        return const Color(0xFF1E90FF);
      case 'drought':
        return const Color(0xFFDAA520);
      case 'glacialRetreat':
        return const Color(0xFF87CEEB);
      default:
        return GISTheme.accentBlue;
    }
  }

  String get _simulationLabel {
    switch (widget.simulationType) {
      case 'wildfire':
        return 'Wildfire Simulation';
      case 'flood':
        return 'Flood Simulation';
      case 'drought':
        return 'Drought Simulation';
      case 'glacialRetreat':
        return 'Glacial Retreat';
      default:
        return 'Simulation';
    }
  }
}
