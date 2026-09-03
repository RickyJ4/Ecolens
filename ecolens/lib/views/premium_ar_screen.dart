import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/services/tts_narrator_service.dart';
import 'package:ecolens/services/story_data_service.dart';

// Conditional import for web iframe support
import 'premium_ar_screen_stub.dart'
    if (dart.library.html) 'premium_ar_screen_web.dart' as web_viewer;

/// Premium AR Experience - Immersive 3D Story Viewer with Community Tab
///
/// This screen IS the story experience. No intermediate screens, no Mapbox.
/// The 3D story starts immediately when the user enters.
/// Includes a Community tab for social content.
class PremiumARScreen extends StatefulWidget {
  final IntelligenceNode? node;
  final String? hotspotId;

  const PremiumARScreen({super.key, this.node, this.hotspotId});

  @override
  State<PremiumARScreen> createState() => _PremiumARScreenState();
}

class _PremiumARScreenState extends State<PremiumARScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // Tab controller
  late TabController _tabController;

  // WebView controller
  InAppWebViewController? _webController;
  final TTSNarratorService _ttsService = TTSNarratorService();
  final StoryDataService _storyDataService = StoryDataService();

  bool _webViewReady = false;
  bool _configSent = false;
  bool _webViewCreated = false;
  int _currentChapter = 0;
  Map<String, dynamic>? _storyConfig;

  // Immersive 360° mode state
  bool _isImmersiveMode = false;
  Map<String, dynamic>? _selectedSpecies;

  @override
  bool get wantKeepAlive => true;

  double get _lat => widget.node?.lat ?? -3.4653;
  double get _lng => widget.node?.lng ?? -62.2159;
  String get _locationName =>
      widget.node?.region ?? widget.node?.headline ?? 'Environmental Zone';

  @override
  void initState() {
    super.initState();

    // Initialize tab controller
    _tabController = TabController(length: 2, vsync: this);

    // Pause CesiumJS when switching to Community tab
    _tabController.addListener(_onTabChanged);

    _initTTS();
    _fetchStoryConfig();
  }

  void _onTabChanged() {
    if (_webController == null) return;

    if (_tabController.index == 0) {
      // Story tab active — resume CesiumJS
      _webController!.evaluateJavascript(
        source: 'if(window.ChapterManager) ChapterManager.resume()',
      );
    } else {
      // Community tab active — pause to save GPU
      _webController!.evaluateJavascript(
        source: 'if(window.ChapterManager) ChapterManager.pause()',
      );
      _ttsService.stop(); // Stop narration when switching away
    }
  }

  Future<void> _initTTS() async {
    await _ttsService.initialize();
  }

  Future<void> _fetchStoryConfig() async {
    // Build the nodeId in the same format as the pipeline saves it
    // Pipeline uses: node_{lat}_{lng} with dots replaced by underscores
    final nodeId = widget.hotspotId ?? widget.node?.id ?? _buildNodeId(_lat, _lng);

    debugPrint('🎬 Calling get_story with nodeId: $nodeId');
    debugPrint('   lat: $_lat, lng: $_lng');
    debugPrint('   widget.hotspotId: ${widget.hotspotId}');
    debugPrint('   widget.node?.id: ${widget.node?.id}');

    try {
      final config = await _storyDataService.fetchStoryConfig(
        nodeId: nodeId,
        lat: _lat,
        lng: _lng,
      );
      if (config != null) {
        debugPrint('✅ Got story config from backend (REAL DATA)');
        debugPrint('   📍 Location: ${config['location']?['name'] ?? 'MISSING'}');
        debugPrint('   📊 Metrics: riskScore=${config['metrics']?['riskScore']}, hectares=${config['metrics']?['hectares']}, population=${config['metrics']?['population']}');
        debugPrint('   🦎 Species POIs: ${(config['speciesPOIs'] as List?)?.length ?? 0}');
        debugPrint('   📖 Chapters: ${(config['chapters'] as List?)?.length ?? 0}');
        debugPrint('   🛰️ Sentinel available: ${config['sentinelImagery']?['available'] ?? false}');
        setState(() {
          _storyConfig = config;
        });
        if (kIsWeb) {
          // On web, the UI will auto-navigate when config is ready
          debugPrint('[Web] Config ready, UI will navigate to story viewer');
        } else if (_webViewReady) {
          _sendStoryConfig();
        }
        return;
      }
    } catch (e) {
      debugPrint('❌ Backend story fetch failed: $e');
    }
    debugPrint('⚠️ Using local fallback config');
    _buildLocalStoryConfig();
  }

  /// Build node ID in the same format as the pipeline
  String _buildNodeId(double lat, double lng) {
    final latId = lat.toString().replaceAll('.', '_').replaceAll('-', 'neg');
    final lngId = lng.toString().replaceAll('.', '_').replaceAll('-', 'neg');
    return 'node_${latId}_$lngId';
  }

  void _buildLocalStoryConfig() {
    final node = widget.node;
    final hasNodeData = node != null;

    debugPrint('⚠️ Building LOCAL fallback config (backend unavailable)');
    debugPrint('   Node data available: $hasNodeData');

    _storyConfig = {
      'location': {'lat': _lat, 'lng': _lng, 'name': _locationName},
      'metrics': {
        'riskScore': node?.riskScore.toInt() ?? 65,
        'hectares': node?.hectares.toInt() ?? 500,
        'population': node?.population ?? 10000,
        'carbonStock': node?.carbonData.carbonStockTonnes.toInt() ?? 25000,
        'restorationCost': node?.reforestZone.costEstimateUsd ?? 1000000,
      },
      'speciesPOIs': _buildSpeciesPOIs(node),
      'chapters': _buildChapters(node),
      // Panorama configuration for immersive 360° chapter
      'panorama': {
        // Dense forest 360° panorama (equirectangular from Poly Haven)
        'imageUrl': 'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/forest_path.jpg',
        // Rainforest ambience audio (Pixabay CDN - CORS-friendly)
        'ambientUrl': 'https://cdn.pixabay.com/audio/2022/01/18/audio_d0c6ff1c1c.mp3',
      },
    };

    if (hasNodeData) {
      debugPrint('   📊 Using REAL metrics from node: riskScore=${node.riskScore.toInt()}, hectares=${node.hectares.toInt()}');
      debugPrint('   🦎 Species: ${node.faunaAtRisk.length} fauna, ${node.floraAtRisk.length} flora');
    } else {
      debugPrint('   ❌ No node data - using HARDCODED defaults');
    }

    setState(() {});
    if (kIsWeb) {
      debugPrint('[Web] Local config ready, UI will navigate to story viewer');
    } else if (_webViewReady) {
      _sendStoryConfig();
    }
  }

  List<Map<String, dynamic>> _buildSpeciesPOIs(IntelligenceNode? node) {
    if (node == null) return [];
    return [
      ...node.faunaAtRisk.map((s) => <String, dynamic>{
        'name': s.commonName,
        'conservation_status': s.status,
        'category': 'fauna',
      }),
      ...node.floraAtRisk.map((s) => <String, dynamic>{
        'name': s.commonName,
        'conservation_status': s.status,
        'category': 'flora',
      }),
    ];
  }

  List<Map<String, dynamic>> _buildChapters(IntelligenceNode? node) {
    final speciesCount = (node?.faunaAtRisk.length ?? 0) + (node?.floraAtRisk.length ?? 0);

    return [
      // IMMERSIVE: Arrival at the forest edge
      {
        'id': 'introduction',
        'title': 'Arrival',
        'narrative':
            'Welcome to $_locationName. You stand at the edge of one of Earth\'s most critical ecosystems.',
        'renderer': 'pannellum',
        'gyroscope': true,
      },
      // IMMERSIVE: Deep in the forest discovering species
      {
        'id': 'discovery',
        'title': 'The Species',
        'narrative':
            'Look around you. $speciesCount species at risk call this place home, depending on every tree and stream.',
        'renderer': 'pannellum',
        'gyroscope': true,
        'showSpecies': true,
      },
      // IMMERSIVE: Heart of the rainforest
      {
        'id': 'immersive',
        'title': 'Into the Forest',
        'narrative':
            'Step into the heart of the rainforest. Listen to the sounds of life that fill this ancient woodland.',
        'renderer': 'pannellum',
        'gyroscope': true,
      },
      // SATELLITE: Show deforestation data - needs CesiumJS
      {
        'id': 'temporal',
        'title': 'What Happened',
        'narrative':
            'From above, satellite imagery reveals the scars of deforestation. ${node?.hectares.toInt() ?? 500} hectares affected.',
        'renderer': 'cesium',
        'cameraPath': {'type': 'topDown', 'altitude': 5000, 'duration': 2},
        'showTimelapse': true,
      },
      // SATELLITE: Impact data visualization - needs CesiumJS
      {
        'id': 'impact',
        'title': 'The Impact',
        'narrative':
            'An estimated ${node?.population ?? 10000} people depend on this ecosystem for water, food, and livelihood.',
        'renderer': 'cesium',
        'cameraPath': {'type': 'pullback', 'altitude': 3000, 'duration': 3},
      },
      // IMMERSIVE: Hope and restoration - back in the forest
      {
        'id': 'restoration',
        'title': 'The Hope',
        'narrative':
            'But there is hope. With intervention, recovery can begin within ${node?.reforestZone.timeToRecoveryYears ?? 10} years.',
        'renderer': 'pannellum',
        'gyroscope': true,
      },
    ];
  }

  void _sendStoryConfig() {
    if (_configSent || !_webViewReady || _storyConfig == null || _webController == null) return;
    _configSent = true;
    final json = jsonEncode(_storyConfig);
    _webController!.evaluateJavascript(source: 'window.initStory($json);');
  }

  void _handleJSMessage(Map<String, dynamic> data) {
    try {
      switch (data['type']) {
        case 'closeStory':
          Navigator.pop(context);
          break;
        case 'chapterChanged':
          setState(() => _currentChapter = data['chapter'] ?? 0);
          break;
        case 'narrateChapter':
          _narrateChapter(data['chapter'] ?? 0, data['text'] ?? '');
          break;
        case 'storyComplete':
          _onStoryComplete();
          break;
        case 'userInteracted':
          _ttsService.stop();
          break;

        // Immersive 360° mode events
        case 'haptic':
          _triggerHaptic(data['type'] as String? ?? 'light');
          break;
        case 'immersiveModeChanged':
          setState(() => _isImmersiveMode = data['active'] == true);
          break;
        case 'speciesSelected':
        case 'showSpeciesCard':
          _showSpeciesCard(data);
          break;
        case 'gyroscopePermission':
          debugPrint('[PremiumAR] Gyroscope permission: ${data['granted']}');
          break;
        case 'hotspotInteraction':
          _triggerHaptic(data['action'] == 'click' ? 'light' : 'selection');
          break;
      }
    } catch (e) {
      debugPrint('JS message parse error: $e');
    }
  }

  /// Trigger haptic feedback based on type
  void _triggerHaptic(String type) {
    switch (type) {
      case 'light':
        HapticFeedback.lightImpact();
        break;
      case 'medium':
        HapticFeedback.mediumImpact();
        break;
      case 'heavy':
        HapticFeedback.heavyImpact();
        break;
      case 'selection':
        HapticFeedback.selectionClick();
        break;
      case 'success':
      case 'warning':
      case 'error':
        HapticFeedback.vibrate();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  /// Show species detail card as bottom sheet
  void _showSpeciesCard(Map<String, dynamic> data) {
    setState(() => _selectedSpecies = data);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSpeciesBottomSheet(data),
    );
  }

  Widget _buildSpeciesBottomSheet(Map<String, dynamic> species) {
    final name = species['name'] ?? 'Unknown Species';
    final status = species['status'] ?? '';
    final icon = species['icon'] ?? '🌿';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Species icon
          Text(icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),

          // Species name
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Conservation status badge
          if (status.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D26A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Continue Exploring'),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('critically') || s.contains('endangered')) {
      return Colors.red;
    } else if (s.contains('vulnerable')) {
      return Colors.orange;
    }
    return const Color(0xFF00D26A);
  }

  Future<void> _narrateChapter(int chapterIndex, String text) async {
    if (text.isEmpty) {
      _notifyNarratorFinished(chapterIndex);
      return;
    }
    try {
      await _ttsService.speakAndWait(text);
      _notifyNarratorFinished(chapterIndex);
    } catch (e) {
      debugPrint('TTS error: $e');
      _notifyNarratorFinished(chapterIndex);
    }
  }

  void _notifyNarratorFinished(int chapterIndex) {
    _webController?.evaluateJavascript(
      source: 'ChapterManager.narratorFinished($chapterIndex)',
    );
  }

  void _onStoryComplete() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Story complete!')),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              // Status bar padding
              SizedBox(height: MediaQuery.of(context).padding.top),

              // Tab bar
              Container(
                color: const Color(0xFF0D1117),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF00D26A),
                  indicatorWeight: 3,
                  labelColor: const Color(0xFF00D26A),
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.public, size: 20),
                      text: 'Story',
                    ),
                    Tab(
                      icon: Icon(Icons.people, size: 20),
                      text: 'Community',
                    ),
                  ],
                ),
              ),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  // Disable swipe — prevents conflict with CesiumJS touch
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // Tab 1: 3D Story (WebView)
                    _buildStoryTab(),

                    // Tab 2: Community Feed
                    _buildCommunityTab(),
                  ],
                ),
              ),
            ],
          ),

          // Back button (floating, top-left, over tabs)
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryTab() {
    // Web platform - navigate directly to story viewer HTML page
    if (kIsWeb) {
      return _buildWebLaunchScreen();
    }

    // Mobile platform - use InAppWebView with full features
    return InAppWebView(
      initialFile: 'assets/story_viewer/index.html',
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
              _handleJSMessage(Map<String, dynamic>.from(args[0]));
            } else if (args.isNotEmpty && args[0] is String) {
              try {
                final data = jsonDecode(args[0]) as Map<String, dynamic>;
                _handleJSMessage(data);
              } catch (e) {
                debugPrint('Failed to parse JS message: $e');
              }
            }
            return null;
          },
        );
      },
      onLoadStop: (controller, url) {
        _webViewReady = true;
        _sendStoryConfig();
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('[WebView] ${consoleMessage.message}');
      },
    );
  }

  /// Web launch screen - shows loading then navigates directly to story viewer HTML
  Widget _buildWebLaunchScreen() {
    // If config is ready, navigate to story viewer
    if (_storyConfig != null) {
      // Use post-frame callback to navigate after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _launchWebStoryViewer();
      });
    }

    return Container(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Loading indicator
            const CircularProgressIndicator(
              color: Color(0xFF00D26A),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              _storyConfig != null
                  ? 'Launching Immersive Experience...'
                  : 'Preparing Story Data...',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _locationName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            // Manual launch button as fallback
            if (_storyConfig != null)
              ElevatedButton.icon(
                onPressed: _launchWebStoryViewer,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Enter Story'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D26A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _webLaunched = false;

  void _launchWebStoryViewer() {
    if (_webLaunched || _storyConfig == null) return;
    _webLaunched = true;

    debugPrint('[Web] Launching story viewer as standalone page...');
    web_viewer.launchWebStoryViewer(_storyConfig!);
  }

  Widget _buildWebMetricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesChip(String name, String emoji) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Color _getRiskColor(double risk) {
    if (risk >= 80) return Colors.red;
    if (risk >= 60) return Colors.orange;
    if (risk >= 40) return Colors.yellow;
    return const Color(0xFF00D26A);
  }

  Widget _buildCommunityTab() {
    return Container(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D26A).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Color(0xFF00D26A),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              const Text(
                'Community Stories',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              // Coming soon badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D26A).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: Color(0xFF00D26A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Description
              const Text(
                'Discover how organizations and communities around the world are addressing environmental impacts and building sustainable futures.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Feature preview cards
              _buildFeaturePreview(
                Icons.groups,
                'Local Initiatives',
                'Stories from communities protecting their ecosystems',
              ),
              const SizedBox(height: 12),
              _buildFeaturePreview(
                Icons.eco,
                'Conservation Efforts',
                'How organizations are restoring damaged habitats',
              ),
              const SizedBox(height: 12),
              _buildFeaturePreview(
                Icons.lightbulb_outline,
                'Sustainable Solutions',
                'Innovative approaches to environmental challenges',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturePreview(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00D26A), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
