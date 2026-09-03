import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/services/immersive_audio_service.dart';
import 'package:ecolens/services/narrator_service.dart';
import 'package:ecolens/services/story_data_service.dart';
import 'package:ecolens/widgets/narrator_overlay.dart';
import 'package:ecolens/widgets/video_intro_overlay.dart';
import 'package:google_fonts/google_fonts.dart';

/// Immersive satellite story experience using Leaflet.js.
/// Loads assets/story_viewer/index.html and passes storyConfig via JavaScript.
class CesiumStoryScreen extends StatefulWidget {
  final IntelligenceNode? node;
  final double? lat;
  final double? lng;
  final String? nodeId;

  const CesiumStoryScreen({
    super.key,
    this.node,
    this.lat,
    this.lng,
    this.nodeId,
  });

  @override
  State<CesiumStoryScreen> createState() => _CesiumStoryScreenState();
}

class _CesiumStoryScreenState extends State<CesiumStoryScreen> {
  InAppWebViewController? _webController;
  final ImmersiveAudioService _audioService = ImmersiveAudioService();
  final NarratorService _narratorService = NarratorService();
  final StoryDataService _storyDataService = StoryDataService();

  bool _isLoading = true;
  bool _webViewReady = false;
  int _currentChapter = 0;
  int _totalChapters = 5;
  String _currentChapterTitle = 'Loading...';
  Map<String, dynamic>? _storyConfig;

  // Video intro state - shows scenery with narrator before chapters
  bool _showVideoIntro = true;
  bool _introCompleted = false;

  // Coordinates from node or direct params
  double get _lat => widget.node?.lat ?? widget.lat ?? -3.4653;
  double get _lng => widget.node?.lng ?? widget.lng ?? -62.2159;
  String get _locationName => widget.node?.region ?? widget.node?.headline ?? 'Environmental Zone';

  @override
  void initState() {
    super.initState();
    _initServices();
    _loadStoryConfig();
  }

  Future<void> _initServices() async {
    await _audioService.initialize();
  }

  /// Load story config - try backend first, then fall back to local generation
  Future<void> _loadStoryConfig() async {
    // Try to fetch from backend first (includes real Sentinel imagery)
    try {
      debugPrint('Fetching story config from backend...');
      final backendConfig = await _storyDataService.fetchStoryConfig(
        nodeId: widget.nodeId ?? widget.node?.id,
        lat: _lat,
        lng: _lng,
      );

      if (backendConfig != null) {
        debugPrint('Using backend story config with Sentinel imagery');
        _storyConfig = backendConfig;

        // Update total chapters from backend config
        final chapters = backendConfig['chapters'] as List<dynamic>?;
        if (chapters != null) {
          _totalChapters = chapters.length;
        }

        setState(() => _isLoading = false);
        _sendStoryConfig();
        return;
      }
    } catch (e) {
      debugPrint('Backend story fetch failed: $e');
    }

    // Fall back to local generation
    debugPrint('Using locally generated story config');
    _buildLocalStoryConfig();
  }

  /// Build story config locally from node data (fallback)
  void _buildLocalStoryConfig() {
    final node = widget.node;

    // Build species POIs from node data
    List<Map<String, dynamic>> speciesPOIs = [];
    if (node != null) {
      // Add fauna
      for (final species in node.faunaAtRisk) {
        speciesPOIs.add({
          'name': species.commonName,
          'scientific_name': species.scientificName,
          'conservation_status': species.status,
          'category': 'fauna',
          'endemic': species.endemic,
          'latitude': species.locationLat != 0 ? species.locationLat : null,
          'longitude': species.locationLng != 0 ? species.locationLng : null,
        });
      }
      // Add flora
      for (final species in node.floraAtRisk) {
        speciesPOIs.add({
          'name': species.commonName,
          'scientific_name': species.scientificName,
          'conservation_status': species.status,
          'category': 'flora',
          'endemic': species.endemic,
        });
      }
    }

    // Build storyConfig
    _storyConfig = {
      'location': {
        'lat': _lat,
        'lng': _lng,
        'name': _locationName,
        'country': node?.country ?? '',
        'region': node?.region ?? '',
      },
      'metrics': {
        'riskScore': node?.riskScore.toInt() ?? 65,
        'hectares': node?.hectares.toInt() ?? 500,
        'population': node?.population ?? 10000,
        'carbonStock': node?.carbonData.carbonStockTonnes.toInt() ?? 25000,
        'restorationCost': node?.reforestZone.costEstimateUsd ?? 1000000,
        'lossRate': '${((node?.riskScore ?? 50) / 20).toStringAsFixed(1)}%/yr',
      },
      'speciesPOIs': speciesPOIs,
      'sentinelImagery': {
        'available': node?.sentinelVerification['available'] == true,
        'beforeRgbUrl': node?.sentinelVerification['imagery']?['before_rgb_url'],
        'afterRgbUrl': node?.sentinelVerification['imagery']?['after_rgb_url'],
        'ndviChangeUrl': node?.sentinelVerification['imagery']?['ndvi_change_url'],
      },
      'chapters': _buildChapters(node),
    };

    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> _buildChapters(IntelligenceNode? node) {
    return [
      {
        'id': 'introduction',
        'title': 'Arrival',
        'narrative': 'Welcome to ${_locationName}. This ${node?.type ?? "ecosystem"} faces a ${_getRiskLevel(node?.riskScore ?? 50)} risk of deforestation.',
        'cameraPath': {'type': 'flyTo', 'altitude': 50000, 'pitch': -45, 'duration': 4},
        'dataCards': [
          {'label': 'Location', 'value': _locationName.split(',').first},
          {'label': 'Risk Level', 'value': '${node?.riskScore.toInt() ?? 65}%', 'class': 'risk-high'},
        ],
      },
      {
        'id': 'discovery',
        'title': 'The Species',
        'narrative': 'This region supports ${(node?.faunaAtRisk.length ?? 0) + (node?.floraAtRisk.length ?? 0)} documented species at risk, including several that exist nowhere else on Earth.',
        'cameraPath': {'type': 'hover', 'altitude': 8000, 'pitch': -20, 'duration': 2},
        'showSpecies': true,
        'dataCards': [
          {'label': 'Species at Risk', 'value': '${(node?.faunaAtRisk.length ?? 0) + (node?.floraAtRisk.length ?? 0)}', 'class': 'risk-high'},
        ],
      },
      {
        'id': 'temporal',
        'title': 'What Happened',
        'narrative': 'Satellite imagery reveals the pattern of deforestation advancing through this region. ${node?.hectares.toInt() ?? 500} hectares have been affected.',
        'cameraPath': {'type': 'topDown', 'altitude': 20000, 'duration': 2},
        'showTimelapse': true,
        'dataCards': [
          {'label': 'Area Affected', 'value': '${node?.hectares.toInt() ?? 500} ha'},
          {'label': 'CO2 Released', 'value': '${((node?.carbonData.annualEmissionsTonnes ?? 10000) / 1000).toStringAsFixed(0)}k t/yr', 'class': 'risk-medium'},
        ],
      },
      {
        'id': 'impact',
        'title': 'The Impact',
        'narrative': 'An estimated ${node?.population ?? 10000} people depend on this ecosystem for water, food, and livelihood.',
        'cameraPath': {'type': 'pullback', 'altitude': 100000, 'duration': 3},
        'dataCards': [
          {'label': 'People Affected', 'value': '${node?.population ?? 10000}'},
          {'label': 'Settlements', 'value': '${node?.settlementsCount ?? 5}'},
        ],
      },
      {
        'id': 'restoration',
        'title': 'The Hope',
        'narrative': 'With intervention costing approximately \$${((node?.reforestZone.costEstimateUsd ?? 1000000) / 1000000).toStringAsFixed(1)}M, this area could begin recovery within ${node?.reforestZone.timeToRecoveryYears ?? 10} years.',
        'cameraPath': {'type': 'approach', 'altitude': 5000, 'duration': 3},
        'dataCards': [
          {'label': 'Recovery Cost', 'value': '\$${((node?.reforestZone.costEstimateUsd ?? 1000000) / 1000000).toStringAsFixed(1)}M'},
          {'label': 'Recovery Time', 'value': '${node?.reforestZone.timeToRecoveryYears ?? 10} years', 'class': 'positive'},
        ],
      },
    ];
  }

  String _getRiskLevel(double score) {
    if (score >= 80) return 'critical';
    if (score >= 60) return 'high';
    if (score >= 40) return 'moderate';
    return 'low';
  }

  void _sendStoryConfig() {
    if (!_webViewReady || _storyConfig == null || _webController == null) return;

    final configJson = jsonEncode(_storyConfig);
    _webController!.evaluateJavascript(source: 'window.initStory($configJson);');

    // NOTE: Audio disabled by default - user can enable via audio control
    // Previously auto-played ambient sound which was intrusive
  }

  void _handleWebMessage(Map<String, dynamic> data) {
    try {
      final type = data['type'] as String?;

      switch (type) {
        case 'bridgeReady':
          _sendStoryConfig();
          break;

        case 'chapterChanged':
          _onChapterChanged(data);
          break;

        case 'storyComplete':
          _onStoryComplete();
          break;

        case 'closeStory':
          _closeStory();
          break;

        case 'userInteracted':
          _narratorService.pause();
          break;

        case 'loadingState':
          setState(() {
            _isLoading = data['isLoading'] == true;
          });
          break;

        case 'speciesSelected':
          _onSpeciesSelected(data);
          break;

        case 'error':
          debugPrint('WebView error: ${data['message']}');
          break;
      }
    } catch (e) {
      debugPrint('Failed to parse WebView message: $e');
    }
  }

  void _onChapterChanged(Map<String, dynamic> data) {
    final chapterIndex = data['chapter'] as int? ?? 0;
    final chapterTitle = data['title'] as String? ?? 'Chapter ${chapterIndex + 1}';

    debugPrint('CesiumStory: Chapter changed to $chapterIndex - $chapterTitle');

    setState(() {
      _currentChapter = chapterIndex;
      _currentChapterTitle = chapterTitle;
    });

    // Get chapter data and narrate
    final chapters = _storyConfig?['chapters'] as List<dynamic>?;
    if (chapters != null && chapterIndex < chapters.length) {
      final chapter = chapters[chapterIndex] as Map<String, dynamic>;

      // Trigger narration with TTS - this will speak the chapter narrative
      final narrative = chapter['narrative'] as String?;
      debugPrint('CesiumStory: Chapter $chapterIndex narrative: $narrative');

      if (narrative != null && narrative.isNotEmpty) {
        // Stop any current narration first
        _narratorService.stop();

        // Delay for natural pacing - longer delay for better TTS synchronization
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            debugPrint('CesiumStory: Starting narration for chapter ${chapterIndex + 1}');
            _narratorService.narrateTourStep(
              chapterIndex + 1,
              chapters.length,
              narrative,
            );
          }
        });
      }

      // Update audio based on chapter mood
      if (chapter['id'] == 'temporal' || chapter['id'] == 'impact') {
        _audioService.playDeforestationSound('wind');
      } else if (chapter['id'] == 'restoration') {
        _audioService.startAmbient(isDeforested: false);
      }
    } else {
      debugPrint('CesiumStory: No chapters found or invalid index: $chapterIndex');
    }
  }

  void _onStoryComplete() {
    // Could show a completion dialog or return to map
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Story complete! Share to raise awareness.'),
        backgroundColor: EcoTheme.neonEmerald,
        action: SnackBarAction(
          label: 'Share',
          textColor: Colors.black,
          onPressed: _shareStory,
        ),
      ),
    );
  }

  void _onSpeciesSelected(Map<String, dynamic> data) {
    final speciesName = data['name'] as String? ?? 'Species';
    final status = data['status'] as String? ?? 'Unknown';

    _narratorService.narrateSpecies(
      speciesName: speciesName,
      status: status,
      isFauna: true,
      habitatLossHectares: widget.node?.hectares ?? 500,
    );
  }

  void _closeStory() {
    _audioService.stopAll();
    Navigator.of(context).pop();
  }

  void _shareStory() {
    // TODO: Implement sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing coming soon!')),
    );
  }

  @override
  void dispose() {
    _audioService.stopAll();
    super.dispose();
  }

  /// Get region type for video intro based on coordinates
  String get _regionType {
    if (_lat >= -20 && _lat <= 10 && _lng >= -80 && _lng <= -34) {
      return 'amazon';
    }
    if (_lat >= -10 && _lat <= 10 && _lng >= 10 && _lng <= 35) {
      return 'africa';
    }
    if (_lat >= -10 && _lat <= 25 && _lng >= 90 && _lng <= 150) {
      return 'asia';
    }
    return 'default';
  }

  /// Get species count from node or story config
  int get _speciesCount {
    if (widget.node != null) {
      return widget.node!.faunaAtRisk.length + widget.node!.floraAtRisk.length;
    }
    final speciesPOIs = _storyConfig?['speciesPOIs'] as List?;
    return speciesPOIs?.length ?? 0;
  }

  /// Complete video intro and start the story
  void _onIntroComplete() {
    setState(() {
      _showVideoIntro = false;
      _introCompleted = true;
    });

    // Start narrating the first chapter after a brief pause
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _narrateCurrentChapter();
      }
    });
  }

  /// Narrate the current chapter with TTS
  void _narrateCurrentChapter() {
    final chapters = _storyConfig?['chapters'] as List<dynamic>?;
    if (chapters != null && _currentChapter < chapters.length) {
      final chapter = chapters[_currentChapter] as Map<String, dynamic>;
      final narrative = chapter['narrative'] as String?;
      final title = chapter['title'] as String?;

      if (narrative != null && narrative.isNotEmpty) {
        // Use narrateTourStep which integrates with TTS
        _narratorService.narrateTourStep(
          _currentChapter + 1,
          chapters.length,
          narrative,
        );
      }

      // Update the chapter title display
      if (title != null) {
        setState(() {
          _currentChapterTitle = title;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: kIsWeb
                ? URLRequest(url: WebUri(Uri.base.resolve('assets/story_viewer/index.html').toString()))
                : null,
            initialFile: kIsWeb ? null : 'assets/story_viewer/index.html',
            initialSettings: InAppWebViewSettings(
              // JavaScript and media settings
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,

              // File access settings for CesiumJS workers
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              allowFileAccess: true,
              allowContentAccess: true,

              // Performance settings
              hardwareAcceleration: true,
              useHybridComposition: true,

              // Background color
              transparentBackground: false,
            ),
            onWebViewCreated: (controller) {
              _webController = controller;

              // Add JavaScript handler for Flutter bridge
              controller.addJavaScriptHandler(
                handlerName: 'FlutterBridge',
                callback: (args) {
                  if (args.isNotEmpty && args[0] is Map) {
                    _handleWebMessage(Map<String, dynamic>.from(args[0]));
                  } else if (args.isNotEmpty && args[0] is String) {
                    try {
                      final data = jsonDecode(args[0]) as Map<String, dynamic>;
                      _handleWebMessage(data);
                    } catch (e) {
                      debugPrint('Failed to parse JS message: $e');
                    }
                  }
                  return null;
                },
              );
            },
            onLoadStop: (controller, url) {
              setState(() => _webViewReady = true);
              _sendStoryConfig();
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint('[WebView] ${consoleMessage.message}');
            },
            onReceivedError: (controller, request, error) {
              debugPrint('WebView error: ${error.description}');
            },
          ),

          // Loading overlay
          if (_isLoading && !_showVideoIntro) _buildLoadingOverlay(),

          // Top bar with back button and chapter progress
          if (!_showVideoIntro) _buildTopBar(),

          // Narrator overlay (already returns Positioned internally)
          if (!_showVideoIntro)
            NarratorOverlay(
              narratorService: _narratorService,
              isVisible: !_isLoading,
            ),

          // Audio controls
          if (!_showVideoIntro)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: _buildAudioControl(),
            ),

          // Video intro overlay - shows before chapters
          if (_showVideoIntro && !_introCompleted)
            VideoIntroOverlay(
              locationName: _locationName,
              regionType: _regionType,
              hectares: widget.node?.hectares ?? 500,
              speciesCount: _speciesCount,
              riskScore: widget.node?.riskScore ?? 65,
              onComplete: _onIntroComplete,
              onSkip: _onIntroComplete,
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A1628),
            const Color(0xFF0D1117),
            const Color(0xFF061018),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated globe icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: EcoTheme.neonEmerald.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: EcoTheme.neonEmerald.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.satellite_alt,
                size: 48,
                color: EcoTheme.neonEmerald,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _locationName,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(EcoTheme.neonEmerald),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Preparing immersive story experience...',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading satellite imagery and environmental data',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 60, // Leave room for audio control
          right: 16,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Chapter progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CHAPTER ${_currentChapter + 1} OF $_totalChapters',
                    style: GoogleFonts.orbitron(
                      color: EcoTheme.neonEmerald,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentChapterTitle,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Progress indicator
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                value: (_currentChapter + 1) / _totalChapters,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(EcoTheme.neonEmerald),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioControl() {
    return GestureDetector(
      onTap: () {
        _audioService.toggleMute();
        setState(() {});
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(
          _audioService.isMuted ? Icons.volume_off : Icons.volume_up,
          color: Colors.white70,
          size: 20,
        ),
      ),
    );
  }
}
