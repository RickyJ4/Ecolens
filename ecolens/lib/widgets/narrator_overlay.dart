import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/services/narrator_service.dart';
import 'package:ecolens/services/tts_narrator_service.dart';
import 'package:ecolens/services/immersive_audio_service.dart';

/// Narrator overlay that displays contextual storytelling text
/// with typewriter effect, style-appropriate visuals, and
/// David Attenborough-style TTS narration.
class NarratorOverlay extends StatefulWidget {
  final NarratorService narratorService;
  final bool isVisible;
  final VoidCallback? onTap;
  final bool enableTTS; // Enable text-to-speech narration

  const NarratorOverlay({
    super.key,
    required this.narratorService,
    this.isVisible = true,
    this.onTap,
    this.enableTTS = true, // TTS enabled by default for David Attenborough experience
  });

  @override
  State<NarratorOverlay> createState() => _NarratorOverlayState();
}

class _NarratorOverlayState extends State<NarratorOverlay>
    with SingleTickerProviderStateMixin {
  NarrationEvent? _currentNarration;
  StreamSubscription? _subscription;

  // TTS narrator for David Attenborough-style voice
  final TTSNarratorService _ttsService = TTSNarratorService();

  // Background music service for sentimental atmosphere
  final ImmersiveAudioService _audioService = ImmersiveAudioService();

  // Typewriter effect
  String _displayedText = '';
  Timer? _typewriterTimer;
  int _charIndex = 0;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // TTS state subscription
  StreamSubscription? _ttsStateSubscription;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _subscription = widget.narratorService.narrations.listen(_onNarration);

    // Initialize TTS for David Attenborough-style narration
    if (widget.enableTTS) {
      _ttsService.initialize().then((_) {
        // Listen for TTS completion to notify narrator service
        // Only notify when TTS transitions FROM speaking TO idle (not on initial idle)
        bool wasSpeaking = false;
        _ttsStateSubscription = _ttsService.stateStream.listen((state) {
          if (state == TTSState.speaking) {
            wasSpeaking = true;
          } else if (state == TTSState.idle && wasSpeaking && mounted) {
            // TTS finished speaking - notify narrator service to advance
            wasSpeaking = false;
            widget.narratorService.onTTSComplete();
          }
        });
      });
    }
  }

  void _onNarration(NarrationEvent event) {
    if (!mounted) return;

    _typewriterTimer?.cancel();

    if (event.isEmpty) {
      // Stop TTS and background music when narration is empty/dismissed
      if (widget.enableTTS) {
        _ttsService.stop();
      }
      _audioService.stopNarratorMusic();
      _fadeController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentNarration = null;
            _displayedText = '';
          });
        }
      });
    } else {
      setState(() {
        _currentNarration = event;
        _displayedText = '';
        _charIndex = 0;
      });
      _fadeController.forward();
      _startTypewriter();

      // Start soft background music for emotional atmosphere
      _audioService.startNarratorMusic();

      // Speak the narration with David Attenborough-style TTS
      if (widget.enableTTS) {
        _ttsService.speakNarration(event);
      }
    }
  }

  void _startTypewriter() {
    if (_currentNarration == null) return;

    final text = _currentNarration!.text;
    final style = _currentNarration!.style;

    // Adjust typing speed based on style
    int msPerChar;
    switch (style) {
      case NarrationStyle.whisper:
        msPerChar = 60; // Slower, more suspenseful
        break;
      case NarrationStyle.grave:
        msPerChar = 50; // Deliberate pacing
        break;
      case NarrationStyle.data:
        msPerChar = 25; // Faster for stats
        break;
      default:
        msPerChar = 35; // Normal pace
    }

    _typewriterTimer = Timer.periodic(Duration(milliseconds: msPerChar), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_charIndex < text.length) {
        setState(() {
          _charIndex++;
          _displayedText = text.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _subscription?.cancel();
    _ttsStateSubscription?.cancel();
    _fadeController.dispose();
    // Stop TTS when overlay is disposed
    if (widget.enableTTS) {
      _ttsService.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || _currentNarration == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 200,
      left: 24,
      right: 24,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: GestureDetector(
          onTap: () {
            widget.onTap?.call();
            widget.narratorService.skip();
          },
          child: _buildNarrationBox(),
        ),
      ),
    );
  }

  Widget _buildNarrationBox() {
    final narration = _currentNarration!;
    final color = Color(narration.styleColorValue);
    final isWhisper = narration.style == NarrationStyle.whisper;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(isWhisper ? 180 : 220),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withAlpha(isWhisper ? 50 : 100),
          width: 1,
        ),
        boxShadow: [
          if (narration.emphasis)
            BoxShadow(
              color: color.withAlpha(50),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Style indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getStyleIcon(narration.style),
                color: color.withAlpha(180),
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _getStyleLabel(narration.style),
                style: GoogleFonts.orbitron(
                  color: color.withAlpha(180),
                  fontSize: 9,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Narration text with typewriter effect
          Text(
            _displayedText,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 15 * narration.fontSizeMultiplier,
              fontStyle: narration.isItalic ? FontStyle.italic : FontStyle.normal,
              fontWeight: narration.emphasis ? FontWeight.w600 : FontWeight.normal,
              height: 1.5,
              letterSpacing: isWhisper ? 0.5 : 0,
            ),
          ),

          // Cursor blink effect while typing
          if (_charIndex < (narration.text.length))
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 500),
              child: Container(
                width: 2,
                height: 18,
                margin: const EdgeInsets.only(top: 2),
                color: color,
              ),
            ),

          // Tap hint
          if (_charIndex >= narration.text.length) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, color: Colors.white24, size: 12),
                const SizedBox(width: 6),
                Text(
                  widget.narratorService.hasQueue ? 'Tap to continue' : 'Tap to dismiss',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _getStyleIcon(NarrationStyle style) {
    switch (style) {
      case NarrationStyle.intro:
        return Icons.play_circle_outline;
      case NarrationStyle.narrative:
        return Icons.auto_stories;
      case NarrationStyle.data:
        return Icons.analytics;
      case NarrationStyle.warning:
        return Icons.warning_amber;
      case NarrationStyle.grave:
        return Icons.error_outline;
      case NarrationStyle.emotional:
        return Icons.favorite;
      case NarrationStyle.hopeful:
        return Icons.wb_sunny;
      case NarrationStyle.inspiring:
        return Icons.rocket_launch;
      case NarrationStyle.whisper:
        return Icons.volume_down;
      case NarrationStyle.atmospheric:
        return Icons.forest;
      case NarrationStyle.philosophical:
        return Icons.psychology;
      case NarrationStyle.guide:
        return Icons.school;
    }
  }

  String _getStyleLabel(NarrationStyle style) {
    switch (style) {
      case NarrationStyle.intro:
        return 'WELCOME';
      case NarrationStyle.narrative:
        return 'THE STORY';
      case NarrationStyle.data:
        return 'THE FACTS';
      case NarrationStyle.warning:
        return 'ALERT';
      case NarrationStyle.grave:
        return 'THE TRUTH';
      case NarrationStyle.emotional:
        return 'THE HEART';
      case NarrationStyle.hopeful:
        return 'HOPE';
      case NarrationStyle.inspiring:
        return 'TAKE ACTION';
      case NarrationStyle.whisper:
        return 'LISTEN';
      case NarrationStyle.atmospheric:
        return 'THE ENVIRONMENT';
      case NarrationStyle.philosophical:
        return 'REFLECTION';
      case NarrationStyle.guide:
        return 'GUIDE';
    }
  }
}

/// Compact narrator controls for the AR screen
class NarratorControls extends StatelessWidget {
  final NarratorService narratorService;
  final VoidCallback? onNarratorToggle;
  final bool isEnabled;

  const NarratorControls({
    super.key,
    required this.narratorService,
    this.onNarratorToggle,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Narrator toggle
          GestureDetector(
            onTap: onNarratorToggle,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isEnabled ? Colors.white12 : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEnabled ? Icons.record_voice_over : Icons.voice_over_off,
                color: isEnabled ? Colors.white : Colors.white38,
                size: 18,
              ),
            ),
          ),

          if (narratorService.isPlaying) ...[
            const SizedBox(width: 8),

            // Skip button
            GestureDetector(
              onTap: () => narratorService.skip(),
              child: const Icon(
                Icons.skip_next,
                color: Colors.white54,
                size: 18,
              ),
            ),

            const SizedBox(width: 8),

            // Stop button
            GestureDetector(
              onTap: () => narratorService.stop(),
              child: const Icon(
                Icons.stop,
                color: Colors.white54,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
