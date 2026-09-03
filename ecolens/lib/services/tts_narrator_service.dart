import 'dart:async';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ecolens/services/narrator_service.dart';

/// Text-to-speech narrator service providing David Attenborough-style narration.
///
/// Configures TTS with:
/// - Deep, calm voice (prioritizing neural/high-quality voices)
/// - Slow, deliberate speech rate for gravitas
/// - British English accent when available
/// - Proper completion handling to prevent cutoff
class TTSNarratorService {
  // Singleton
  static final TTSNarratorService _instance = TTSNarratorService._internal();
  factory TTSNarratorService() => _instance;
  TTSNarratorService._internal();

  FlutterTts? _tts;
  bool _isInitialized = false;
  bool _isEnabled = true;
  bool _isSpeaking = false;

  // Completer for tracking speech completion
  Completer<void>? _speechCompleter;

  // Voice configuration for David Attenborough style
  // Natural pace - not too slow, with warm British delivery
  static const double _speechRate = 0.42; // Slow, deliberate narration pace
  static const double _pitch = 0.85; // Deeper, warmer tone like Attenborough
  static const double _volume = 1.0;

  // Preferred voice names - prioritize neural/high-quality voices
  // Order matters: first match wins
  static const List<String> _preferredVoicePatterns = [
    // iOS high-quality voices (Enhanced/Premium)
    'Daniel', // British English male - best quality on iOS
    'Oliver', // British English male
    'Arthur', // British English male
    // Android Neural/Wavenet voices (Google Cloud)
    'en-GB-Wavenet-B', // High quality British male
    'en-GB-Wavenet-D', // High quality British male
    'en-GB-Neural2-B', // Neural British male
    'en-GB-Neural2-D', // Neural British male
    'en-GB-Standard-B', // Standard British male
    'en-GB-Standard-D', // Standard British male
    // Samsung/local voices
    'English United Kingdom', // Samsung British
    'en-gb-x-gba-network', // Network British voice
    'en-gb-x-gba-local', // Local British voice
    // Fallback patterns
    'en-GB', // Any British voice
    'en_GB', // Alternative locale format
  ];

  final _stateController = StreamController<TTSState>.broadcast();
  Stream<TTSState> get stateStream => _stateController.stream;

  /// Initialize the TTS engine with Attenborough-style configuration
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _tts = FlutterTts();

      // Platform-specific configuration
      if (Platform.isIOS) {
        await _tts!.setSharedInstance(true);
        await _tts!.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }

      // Configure for documentary-style narration
      await _tts!.setSpeechRate(_speechRate);
      await _tts!.setPitch(_pitch);
      await _tts!.setVolume(_volume);

      // Try to set best available British English voice
      await _setBestVoice();

      // Set up completion handlers
      _tts!.setStartHandler(() {
        _isSpeaking = true;
        _stateController.add(TTSState.speaking);
      });

      _tts!.setCompletionHandler(() {
        _isSpeaking = false;
        _stateController.add(TTSState.idle);
        // Add a delay to ensure audio buffer has fully played
        // Android TTS can fire completion slightly before audio output finishes
        Future.delayed(const Duration(milliseconds: 800), () {
          _speechCompleter?.complete();
          _speechCompleter = null;
        });
      });

      _tts!.setErrorHandler((message) {
        _isSpeaking = false;
        _stateController.add(TTSState.error);
        print('TTS Error: $message');
        // Complete with error to prevent hanging
        _speechCompleter?.complete();
        _speechCompleter = null;
      });

      _tts!.setCancelHandler(() {
        _isSpeaking = false;
        _stateController.add(TTSState.idle);
        _speechCompleter?.complete();
        _speechCompleter = null;
      });

      // Progress handler for debugging
      _tts!.setProgressHandler((text, start, end, word) {
        // Can be used for word-by-word highlighting if needed
      });

      _isInitialized = true;
      _stateController.add(TTSState.idle);

      print('TTS initialized successfully');
    } catch (e) {
      print('Failed to initialize TTS: $e');
      _stateController.add(TTSState.error);
    }
  }

  /// Set the best available voice for documentary narration
  Future<void> _setBestVoice() async {
    if (_tts == null) return;

    try {
      // Get available voices
      final dynamic voicesResult = await _tts!.getVoices;
      if (voicesResult == null) {
        await _tts!.setLanguage('en-GB');
        print('TTS: Using default en-GB language');
        return;
      }

      final List<dynamic> voices = voicesResult is List ? voicesResult : [];
      if (voices.isEmpty) {
        await _tts!.setLanguage('en-GB');
        print('TTS: No voices available, using en-GB');
        return;
      }

      // Print available voices for debugging
      print('TTS: Available voices: ${voices.length}');
      for (final voice in voices.take(10)) {
        print('  - ${voice['name']} (${voice['locale']})');
      }

      // Try to find a preferred voice
      for (final pattern in _preferredVoicePatterns) {
        for (final voice in voices) {
          final voiceName = voice['name']?.toString() ?? '';
          final voiceLang = voice['locale']?.toString() ?? '';

          // Match by name or locale containing the pattern
          if (voiceName.toLowerCase().contains(pattern.toLowerCase()) ||
              voiceLang.toLowerCase().contains(pattern.toLowerCase())) {
            try {
              await _tts!.setVoice({'name': voiceName, 'locale': voiceLang});
              print('TTS: Selected voice: $voiceName ($voiceLang)');
              return;
            } catch (e) {
              print('TTS: Failed to set voice $voiceName: $e');
              continue;
            }
          }
        }
      }

      // Fallback: find any British English voice
      for (final voice in voices) {
        final voiceLang = voice['locale']?.toString().toLowerCase() ?? '';

        // Prefer British English
        if (voiceLang.contains('en-gb') || voiceLang.contains('en_gb')) {
          try {
            await _tts!.setVoice({
              'name': voice['name']?.toString() ?? '',
              'locale': voice['locale']?.toString() ?? '',
            });
            print('TTS: Using British voice: ${voice['name']}');
            return;
          } catch (e) {
            continue;
          }
        }
      }

      // Final fallback - set language only
      await _tts!.setLanguage('en-GB');
      print('TTS: Fallback to en-GB language setting');
    } catch (e) {
      print('Failed to set voice: $e');
      try {
        await _tts!.setLanguage('en-GB');
      } catch (_) {
        await _tts!.setLanguage('en-US');
      }
    }
  }

  /// Speak text and wait for completion
  /// Returns a Future that completes when speech finishes
  Future<void> speak(String text, {NarrationStyle? style}) async {
    if (!_isInitialized || !_isEnabled || _tts == null) return;
    if (text.isEmpty) return;

    // Stop any current speech
    await stop();

    // Adjust parameters based on narration style
    if (style != null) {
      await _adjustForStyle(style);
    }

    // Clean text for speech (remove markdown, emojis, etc.)
    final cleanText = _cleanTextForSpeech(text);

    // Create completer to track completion
    _speechCompleter = Completer<void>();

    try {
      final result = await _tts!.speak(cleanText);
      if (result != 1) {
        print('TTS speak returned: $result');
        _speechCompleter?.complete();
        _speechCompleter = null;
      }
    } catch (e) {
      print('TTS speak error: $e');
      _speechCompleter?.complete();
      _speechCompleter = null;
    }
  }

  /// Speak and wait for completion
  Future<void> speakAndWait(String text, {NarrationStyle? style}) async {
    await speak(text, style: style);
    // Wait for speech to complete
    if (_speechCompleter != null) {
      await _speechCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('TTS: Speech timeout');
          _speechCompleter?.complete();
        },
      );
    }
  }

  /// Speak a narration event from the narrator service
  Future<void> speakNarration(NarrationEvent event) async {
    if (event.isEmpty) return;
    await speak(event.text, style: event.style);
  }

  /// Adjust TTS parameters based on narration style
  /// Tuned for natural British documentary narration
  Future<void> _adjustForStyle(NarrationStyle style) async {
    if (_tts == null) return;

    double rate = _speechRate;
    double pitch = _pitch;

    switch (style) {
      case NarrationStyle.whisper:
        rate = 0.38; // Slower, intimate delivery
        pitch = 0.80; // Deeper, hushed tone
        break;
      case NarrationStyle.grave:
        rate = 0.40; // Slow, somber pacing
        pitch = 0.78; // Deep, serious tone
        break;
      case NarrationStyle.emotional:
        rate = 0.40; // Deliberate, heartfelt
        pitch = 0.82;
        break;
      case NarrationStyle.warning:
        rate = 0.44; // Slightly more urgent
        pitch = 0.88;
        break;
      case NarrationStyle.hopeful:
        rate = 0.43;
        pitch = 0.90; // Warmer, uplifting
        break;
      case NarrationStyle.inspiring:
        rate = 0.44;
        pitch = 0.92; // Energetic but still measured
        break;
      case NarrationStyle.data:
        rate = 0.44; // Clear, informative
        pitch = 0.85;
        break;
      case NarrationStyle.intro:
        rate = 0.40; // Slow, dramatic opening
        pitch = 0.82;
        break;
      case NarrationStyle.narrative:
        rate = 0.42; // Natural storytelling pace
        pitch = 0.85;
        break;
      case NarrationStyle.atmospheric:
        rate = 0.40; // Slow, immersive
        pitch = 0.83;
        break;
      case NarrationStyle.philosophical:
        rate = 0.40; // Thoughtful, reflective
        pitch = 0.80;
        break;
      case NarrationStyle.guide:
        rate = 0.44; // Clear instructional
        pitch = 0.88;
        break;
    }

    await _tts!.setSpeechRate(rate);
    await _tts!.setPitch(pitch);
  }

  /// Clean text for speech synthesis with natural British pacing
  String _cleanTextForSpeech(String text) {
    String cleaned = text
        // Remove markdown formatting
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'\1')
        .replaceAll(RegExp(r'_([^_]+)_'), r'\1')
        .replaceAll(RegExp(r'`([^`]+)`'), r'\1')
        // Remove emojis
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F6FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F5FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F900}-\u{1F9FF}]', unicode: true), '')
        // Add natural pauses for punctuation (British documentary style)
        .replaceAll('...', ', , ,') // Thoughtful pause for ellipsis
        .replaceAll(' - ', ', ') // Brief pause for dashes
        .replaceAll('—', ', ') // Em dash pause
        .replaceAll(';', ',') // Semicolon as comma pause
        // Clean up numbers for better pronunciation
        .replaceAllMapped(RegExp(r'(\d+),(\d+)'), (m) => '${m[1]} ${m[2]}')
        // Improve percentage pronunciation
        .replaceAll('%', ' percent')
        // Improve abbreviations
        .replaceAll('CO2', 'C O 2')
        .replaceAll('km', ' kilometers')
        .replaceAll(' ha', ' hectares')
        .replaceAll(' yr', ' year')
        .replaceAll(' t/', ' tonnes per ')
        .trim();

    // Ensure text ends with punctuation for complete sentence
    if (!cleaned.endsWith('.') &&
        !cleaned.endsWith('!') &&
        !cleaned.endsWith('?')) {
      cleaned += '.';
    }

    return cleaned;
  }

  /// Stop current speech
  Future<void> stop() async {
    if (_tts != null) {
      await _tts!.stop();
      _isSpeaking = false;
      _speechCompleter?.complete();
      _speechCompleter = null;
      _stateController.add(TTSState.idle);
    }
  }

  /// Pause speech (iOS only fully supports this)
  Future<void> pause() async {
    if (_tts != null && _isSpeaking) {
      await _tts!.pause();
      _stateController.add(TTSState.paused);
    }
  }

  /// Toggle TTS enabled state
  void toggleEnabled() {
    _isEnabled = !_isEnabled;
    if (!_isEnabled) {
      stop();
    }
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!_isEnabled) {
      stop();
    }
  }

  bool get isEnabled => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;

  /// Get list of available voices (for debugging/settings)
  Future<List<Map<String, String>>> getAvailableVoices() async {
    if (_tts == null) return [];

    try {
      final dynamic result = await _tts!.getVoices;
      if (result == null) return [];

      final List<dynamic> voices = result is List ? result : [];
      return voices.map((v) => {
        'name': v['name']?.toString() ?? '',
        'locale': v['locale']?.toString() ?? '',
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _tts?.stop();
    _tts = null;
    _isInitialized = false;
    _stateController.close();
  }
}

/// TTS playback state
enum TTSState {
  idle,
  speaking,
  paused,
  error,
}
