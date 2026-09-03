import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/services/tts_narrator_service.dart';
import 'package:ecolens/services/narrator_service.dart';
import 'package:ecolens/services/immersive_audio_service.dart';

/// Video intro overlay that plays before the story chapters begin.
/// Shows nature footage with David Attenborough-style narration
/// providing brief history about the area.
class VideoIntroOverlay extends StatefulWidget {
  final String locationName;
  final String regionType; // amazon, africa, asia, etc.
  final double hectares;
  final int speciesCount;
  final double riskScore;
  final VoidCallback onComplete;
  final VoidCallback? onSkip;

  const VideoIntroOverlay({
    super.key,
    required this.locationName,
    required this.regionType,
    required this.hectares,
    required this.speciesCount,
    required this.riskScore,
    required this.onComplete,
    this.onSkip,
  });

  @override
  State<VideoIntroOverlay> createState() => _VideoIntroOverlayState();
}

class _VideoIntroOverlayState extends State<VideoIntroOverlay>
    with TickerProviderStateMixin {
  final TTSNarratorService _ttsService = TTSNarratorService();
  final ImmersiveAudioService _audioService = ImmersiveAudioService();

  late AnimationController _fadeController;
  late AnimationController _textController;
  late Animation<double> _fadeAnim;
  late Animation<double> _textAnim;

  // Video player
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  int _currentNarrationIndex = 0;
  String _displayedText = '';
  Timer? _typewriterTimer;
  bool _isComplete = false;
  bool _isWaitingForTTS = false;

  // Free forest/nature videos - using Pexels CDN (more reliable than Pixabay)
  // These are CC0 licensed FOREST and WILDLIFE videos
  static const Map<String, List<String>> _regionVideos = {
    'amazon': [
      // Tropical rainforest
      'https://videos.pexels.com/video-files/3571264/3571264-uhd_2560_1440_30fps.mp4',
      'https://videos.pexels.com/video-files/857195/857195-hd_1920_1080_25fps.mp4',
    ],
    'africa': [
      // African savanna and wildlife
      'https://videos.pexels.com/video-files/1448735/1448735-uhd_2560_1440_24fps.mp4',
      'https://videos.pexels.com/video-files/855282/855282-hd_1920_1080_24fps.mp4',
    ],
    'asia': [
      // Asian forest - bamboo and rainforest
      'https://videos.pexels.com/video-files/3214448/3214448-uhd_2560_1440_25fps.mp4',
      'https://videos.pexels.com/video-files/2098989/2098989-hd_1920_1080_30fps.mp4',
    ],
    'default': [
      // General forest and woodland
      'https://videos.pexels.com/video-files/857195/857195-hd_1920_1080_25fps.mp4',
      'https://videos.pexels.com/video-files/3571264/3571264-uhd_2560_1440_30fps.mp4',
    ],
  };

  // Note: External image URLs removed - using beautiful animated gradients instead
  // This ensures the intro always works regardless of network/hotlink restrictions

  // Narration scripts based on region - David Attenborough style
  List<String> get _narrationScript {
    switch (widget.regionType.toLowerCase()) {
      case 'amazon':
        return [
          'The Amazon. The greatest rainforest on Earth.',
          'For millions of years, this vast wilderness has been a cradle of life, nurturing one in ten of all species known to science.',
          '${widget.locationName} represents ${widget.hectares.toInt()} hectares of irreplaceable ecosystem.',
          'Today, ${widget.speciesCount} species in this region face an uncertain future.',
          'What happens here will echo through generations.',
        ];
      case 'africa':
        return [
          'The heart of Africa. A forest older than human memory.',
          'These ancient trees have witnessed the rise and fall of empires, sheltering creatures found nowhere else on Earth.',
          '${widget.locationName} spans ${widget.hectares.toInt()} hectares of this precious wilderness.',
          '${widget.speciesCount} species depend on these trees for survival.',
          'The story of this place is also our story.',
        ];
      case 'asia':
        return [
          'The rainforests of Southeast Asia. Among the most biodiverse places on our planet.',
          'From towering dipterocarps to the smallest orchids, life here exists in extraordinary abundance.',
          '${widget.locationName} encompasses ${widget.hectares.toInt()} hectares of this rich tapestry.',
          '${widget.speciesCount} species call this forest home.',
          'Their fate now rests in human hands.',
        ];
      default:
        return [
          '${widget.locationName}. A landscape shaped by time and nature.',
          'Every forest tells a story written in rings of ancient trees and the paths of countless creatures.',
          'This region spans ${widget.hectares.toInt()} hectares of living wilderness.',
          '${widget.speciesCount} species depend on these lands for their survival.',
          'Understanding their story is the first step to protecting it.',
        ];
    }
  }

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textAnim = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOut,
    );

    // Initialize video and TTS
    _initializeVideo();
    _ttsService.initialize().then((_) {
      // Listen for TTS completion to advance narration
      // Only advance when TTS transitions FROM speaking TO idle
      bool wasSpeaking = false;
      _ttsService.stateStream.listen((state) {
        if (state == TTSState.speaking) {
          wasSpeaking = true;
        } else if (state == TTSState.idle && wasSpeaking && _isWaitingForTTS && mounted) {
          // TTS finished speaking - advance narration
          wasSpeaking = false;
          _isWaitingForTTS = false;
          _advanceNarration();
        }
      });
    });
  }

  Future<void> _initializeVideo() async {
    final region = widget.regionType.toLowerCase();
    final videos = _regionVideos[region] ?? _regionVideos['default']!;
    final videoUrl = videos[0]; // Use first video

    // Start showing the fallback image immediately while video loads
    // This ensures the user sees something beautiful right away
    _fadeController.forward();

    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      // Add a timeout - if video doesn't load in 5 seconds, use fallback
      await _videoController!.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Video loading timed out');
        },
      );

      await _videoController!.setLooping(true);
      await _videoController!.setVolume(0); // Mute video, we use TTS for audio
      await _videoController!.play();

      if (mounted) {
        setState(() {
          _videoInitialized = true;
        });

        // Start narration after video is playing
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _startNarration();
        });
      }
    } catch (e) {
      print('Video initialization error (using image fallback): $e');
      if (mounted) {
        setState(() {
          _videoError = true;
        });
        // Start narration with beautiful fallback image
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _startNarration();
        });
      }
    }
  }

  // Fallback timer for TTS
  Timer? _ttsFallbackTimer;

  void _startNarration() {
    if (_currentNarrationIndex >= _narrationScript.length) {
      _completeIntro();
      return;
    }

    final text = _narrationScript[_currentNarrationIndex];
    _displayedText = '';
    _textController.forward(from: 0);

    // Start sentimental background music
    _audioService.startNarratorMusic();

    // Speak with TTS - wait for completion before advancing
    _isWaitingForTTS = true;
    _ttsService.speak(text, style: NarrationStyle.intro);

    // Calculate expected speech duration (approx 1 word per second at slow rate + buffer)
    final wordCount = text.split(RegExp(r'\s+')).length;
    final estimatedDurationMs = (wordCount * 1000) + 3000; // 1 sec per word + 3 sec buffer

    // Fallback timer in case TTS completion callback doesn't fire
    _ttsFallbackTimer?.cancel();
    _ttsFallbackTimer = Timer(Duration(milliseconds: (estimatedDurationMs * 1.5).round()), () {
      if (mounted && _isWaitingForTTS) {
        // TTS callback didn't fire - advance manually
        _isWaitingForTTS = false;
        _advanceNarration();
      }
    });

    // Typewriter effect
    int charIndex = 0;
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 45), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (charIndex < text.length) {
        setState(() {
          charIndex++;
          _displayedText = text.substring(0, charIndex);
        });
      } else {
        timer.cancel();
        // Don't auto-advance here - wait for TTS to complete via listener or fallback timer
      }
    });
  }

  void _advanceNarration() {
    if (!mounted || _isComplete) return;

    // Cancel fallback timer since we're advancing
    _ttsFallbackTimer?.cancel();

    // Small delay between narrations for natural pacing
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;

      _textController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentNarrationIndex++;
          });
          _startNarration();
        }
      });
    });
  }

  void _completeIntro() {
    if (_isComplete) return;
    _isComplete = true;

    _ttsService.stop();
    _audioService.stopNarratorMusic();
    _videoController?.pause();

    _fadeController.reverse().then((_) {
      widget.onComplete();
    });
  }

  void _skipIntro() {
    _typewriterTimer?.cancel();
    _ttsFallbackTimer?.cancel();
    _ttsService.stop();
    _audioService.stopNarratorMusic();
    _videoController?.pause();
    widget.onSkip?.call();
    widget.onComplete();
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _ttsFallbackTimer?.cancel();
    _fadeController.dispose();
    _textController.dispose();
    _videoController?.dispose();
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background video or fallback
            _buildBackgroundMedia(),

            // Cinematic overlay gradients
            _buildCinematicOverlay(),

            // Loading indicator while video initializes
            if (!_videoInitialized && !_videoError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: EcoTheme.neonEmerald,
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading nature footage...',
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // Location badge
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              child: _buildLocationBadge(),
            ),

            // Skip button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: _buildSkipButton(),
            ),

            // Narration text
            Positioned(
              bottom: 100,
              left: 24,
              right: 24,
              child: FadeTransition(
                opacity: _textAnim,
                child: _buildNarrationText(),
              ),
            ),

            // Progress indicator
            Positioned(
              bottom: 50,
              left: 32,
              right: 32,
              child: _buildProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundMedia() {
    if (_videoInitialized && _videoController != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    // Beautiful animated forest gradient background (no external URLs needed)
    // This always works and looks professional
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient - forest colors
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getRegionColor(),
                const Color(0xFF0D2818), // Dark forest green
                const Color(0xFF0A1628), // Deep blue-black
                const Color(0xFF061018), // Near black
              ],
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
        ),

        // Radial glow for depth - simulates light through canopy
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.5),
              radius: 1.2,
              colors: [
                _getRegionColor().withValues(alpha: 0.4),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Second radial glow
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.5, 0.3),
              radius: 0.8,
              colors: [
                const Color(0xFF1a4a2a).withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Subtle texture overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.4),
              ],
              stops: const [0.0, 0.2, 0.8, 1.0],
            ),
          ),
        ),

        // Forest icon watermark
        Center(
          child: Icon(
            _getRegionIcon(),
            size: 200,
            color: Colors.white.withValues(alpha: 0.03),
          ),
        ),
      ],
    );
  }

  Color _getRegionColor() {
    switch (widget.regionType.toLowerCase()) {
      case 'amazon':
        return const Color(0xFF1a4a1a);
      case 'africa':
        return const Color(0xFF4a3a1a);
      case 'asia':
        return const Color(0xFF1a3a4a);
      default:
        return const Color(0xFF1a3a1a);
    }
  }

  IconData _getRegionIcon() {
    switch (widget.regionType.toLowerCase()) {
      case 'amazon':
        return Icons.forest;
      case 'africa':
        return Icons.terrain;
      case 'asia':
        return Icons.park;
      default:
        return Icons.eco;
    }
  }

  Widget _buildCinematicOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.25, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildLocationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EcoTheme.neonEmerald.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: EcoTheme.neonEmerald, size: 16),
          const SizedBox(width: 8),
          Text(
            widget.locationName.length > 25
                ? '${widget.locationName.substring(0, 25)}...'
                : widget.locationName,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipButton() {
    return GestureDetector(
      onTap: _skipIntro,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Skip Intro',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.skip_next, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrationText() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: EcoTheme.neonEmerald.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: EcoTheme.neonEmerald.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Narrator indicator with voice wave animation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildVoiceWave(),
              const SizedBox(width: 10),
              Text(
                'NARRATOR',
                style: GoogleFonts.orbitron(
                  color: EcoTheme.neonEmerald.withValues(alpha: 0.9),
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              _buildVoiceWave(),
            ],
          ),
          const SizedBox(height: 20),
          // Narration text
          Text(
            _displayedText,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              height: 1.7,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceWave() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 300 + index * 100),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 3,
          height: _isWaitingForTTS ? (8 + index * 4).toDouble() : 4,
          decoration: BoxDecoration(
            color: EcoTheme.neonEmerald.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        // Progress dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_narrationScript.length, (index) {
            final isActive = index == _currentNarrationIndex;
            final isPast = index < _currentNarrationIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 28 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: isPast
                    ? EcoTheme.neonEmerald
                    : isActive
                        ? EcoTheme.neonEmerald.withValues(alpha: 0.8)
                        : Colors.white24,
                borderRadius: BorderRadius.circular(5),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: EcoTheme.neonEmerald.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          '${_currentNarrationIndex + 1} of ${_narrationScript.length}',
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
