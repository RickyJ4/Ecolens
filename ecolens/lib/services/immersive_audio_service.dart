import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Real audio service for immersive AR storytelling.
/// Plays actual ambient forest sounds, animal calls, and manages
/// volume mixing based on proximity for the Silent Hunt feature.
class ImmersiveAudioService {
  // Singleton
  static final ImmersiveAudioService _instance = ImmersiveAudioService._internal();
  factory ImmersiveAudioService() => _instance;
  ImmersiveAudioService._internal();

  // Audio players for different layers
  AudioPlayer? _ambientPlayer;
  AudioPlayer? _animalPlayer;
  AudioPlayer? _narrationPlayer;

  bool _isInitialized = false;
  bool _isMuted = true; // Start muted by default - user can enable

  // Current volume levels
  double _ambientVolume = 0.7;
  double _animalVolume = 0.0;

  // Free, high-quality ambient sound URLs from Mixkit (allows hotlinking, CC0 license)
  // These URLs are direct download links that work without authentication
  static const Map<String, String> _soundUrls = {
    // Forest ambient sounds - from Mixkit free sound effects
    'forest_day': 'https://assets.mixkit.co/active_storage/sfx/212/212-preview.mp3', // Forest birds ambience
    'forest_night': 'https://assets.mixkit.co/active_storage/sfx/2515/2515-preview.mp3', // Night crickets
    'rain_forest': 'https://assets.mixkit.co/active_storage/sfx/2514/2514-preview.mp3', // Rain sounds
    'birds_morning': 'https://assets.mixkit.co/active_storage/sfx/2461/2461-preview.mp3', // Morning birds

    // Animal sounds
    'jaguar_growl': 'https://assets.mixkit.co/active_storage/sfx/2870/2870-preview.mp3', // Big cat growl
    'monkey_call': 'https://assets.mixkit.co/active_storage/sfx/2502/2502-preview.mp3', // Jungle ambience with monkeys
    'bird_call': 'https://assets.mixkit.co/active_storage/sfx/2460/2460-preview.mp3', // Tropical bird call
    'frog_chorus': 'https://assets.mixkit.co/active_storage/sfx/2517/2517-preview.mp3', // Frogs at night
    'insect_night': 'https://assets.mixkit.co/active_storage/sfx/2515/2515-preview.mp3', // Night insects/cicadas

    // Deforestation sounds
    'chainsaw': 'https://assets.mixkit.co/active_storage/sfx/2782/2782-preview.mp3', // Construction/cutting
    'fire_crackle': 'https://assets.mixkit.co/active_storage/sfx/2579/2579-preview.mp3', // Fire crackling
    'wind_barren': 'https://assets.mixkit.co/active_storage/sfx/2430/2430-preview.mp3', // Wind blowing

    // Emotional moments
    'heartbeat': 'https://assets.mixkit.co/active_storage/sfx/2872/2872-preview.mp3', // Heartbeat
    'silence': '', // Empty for dramatic pause

    // Sentimental background music for narrator - soft piano/strings
    'narrator_music': 'https://assets.mixkit.co/active_storage/sfx/123/123-preview.mp3', // Soft ambient
    'emotional_piano': 'https://assets.mixkit.co/active_storage/sfx/2858/2858-preview.mp3', // Emotional piano
    'nature_ambient': 'https://assets.mixkit.co/active_storage/sfx/2512/2512-preview.mp3', // Calm nature
  };

  // Background music player for narrator
  AudioPlayer? _musicPlayer;
  bool _musicPlaying = false;

  /// Initialize the audio system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Configure audio session for proper mixing
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: false,
      ));

      // Create audio players
      _ambientPlayer = AudioPlayer();
      _animalPlayer = AudioPlayer();
      _narrationPlayer = AudioPlayer();
      _musicPlayer = AudioPlayer();

      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize audio: $e');
    }
  }

  /// Start playing ambient forest sounds based on environment
  /// Only plays if not muted - respects user preference
  Future<void> startAmbient({
    required bool isDeforested,
    String timeOfDay = 'day',
  }) async {
    if (!_isInitialized || _ambientPlayer == null) return;

    // Don't auto-play if muted - respect user preference
    if (_isMuted) return;

    try {
      String soundKey;
      if (isDeforested) {
        soundKey = 'wind_barren';
      } else if (timeOfDay == 'night') {
        soundKey = 'forest_night';
      } else {
        soundKey = 'forest_day';
      }

      final url = _soundUrls[soundKey];
      if (url != null && url.isNotEmpty) {
        await _ambientPlayer!.setUrl(url);
        await _ambientPlayer!.setLoopMode(LoopMode.one);
        await _ambientPlayer!.setVolume(_ambientVolume);
        _ambientPlayer!.play();
      }
    } catch (e) {
      print('Failed to start ambient audio: $e');
    }
  }

  /// Play animal sound for species interaction
  /// Only plays if not muted - respects user preference
  Future<void> playAnimalSound(String speciesType) async {
    if (!_isInitialized || _animalPlayer == null || _isMuted) return;

    try {
      String soundKey;
      switch (speciesType.toLowerCase()) {
        case 'jaguar':
        case 'panther':
        case 'leopard':
          soundKey = 'jaguar_growl';
          break;
        case 'monkey':
        case 'primate':
        case 'howler':
          soundKey = 'monkey_call';
          break;
        case 'frog':
        case 'amphibian':
          soundKey = 'frog_chorus';
          break;
        case 'bird':
        case 'macaw':
        case 'parrot':
          soundKey = 'bird_call';
          break;
        default:
          soundKey = 'bird_call';
      }

      final url = _soundUrls[soundKey];
      if (url != null && url.isNotEmpty) {
        await _animalPlayer!.setUrl(url);
        await _animalPlayer!.setVolume(_animalVolume);
        _animalPlayer!.play();
      }
    } catch (e) {
      print('Failed to play animal sound: $e');
    }
  }

  /// Update audio mix based on Silent Hunt proximity
  /// As user gets closer to animal, ambient quiets down, animal gets louder
  void updateProximityMix(double proximityFactor) {
    if (!_isInitialized) return;

    // proximityFactor: 0.0 = far away, 1.0 = very close
    final clampedFactor = proximityFactor.clamp(0.0, 1.0);

    // Ambient gets quieter as you get closer
    _ambientVolume = 0.7 * (1.0 - clampedFactor * 0.8);
    // Animal gets louder as you get closer
    _animalVolume = clampedFactor;

    _ambientPlayer?.setVolume(_isMuted ? 0.0 : _ambientVolume);
    _animalPlayer?.setVolume(_isMuted ? 0.0 : _animalVolume);
  }

  /// Play heartbeat effect for intimate proximity zone
  /// Only plays if not muted - respects user preference
  Future<void> playHeartbeat() async {
    if (!_isInitialized || _animalPlayer == null || _isMuted) return;

    try {
      final url = _soundUrls['heartbeat'];
      if (url != null && url.isNotEmpty) {
        await _animalPlayer!.setUrl(url);
        await _animalPlayer!.setLoopMode(LoopMode.one);
        await _animalPlayer!.setVolume(0.4);
        _animalPlayer!.play();
      }
    } catch (e) {
      print('Failed to play heartbeat: $e');
    }
  }

  /// Play deforestation sounds (chainsaw, fire)
  /// Only plays if not muted - respects user preference
  Future<void> playDeforestationSound(String type) async {
    if (!_isInitialized || _animalPlayer == null || _isMuted) return;

    try {
      String soundKey;
      switch (type.toLowerCase()) {
        case 'fire':
        case 'burning':
          soundKey = 'fire_crackle';
          break;
        case 'logging':
        case 'chainsaw':
          soundKey = 'chainsaw';
          break;
        default:
          soundKey = 'wind_barren';
      }

      final url = _soundUrls[soundKey];
      if (url != null && url.isNotEmpty) {
        await _animalPlayer!.setUrl(url);
        await _animalPlayer!.setVolume(0.6);
        _animalPlayer!.play();
      }
    } catch (e) {
      print('Failed to play deforestation sound: $e');
    }
  }

  /// Dramatic silence for vanish moment
  Future<void> dramaticSilence() async {
    // Fade out all audio quickly
    for (double v = _ambientVolume; v > 0; v -= 0.1) {
      _ambientPlayer?.setVolume(v);
      _animalPlayer?.setVolume(v * 0.5);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await _ambientPlayer?.pause();
    await _animalPlayer?.pause();
  }

  /// Resume ambient after dramatic moment
  Future<void> resumeAmbient() async {
    if (!_isInitialized) return;

    _ambientPlayer?.setVolume(_ambientVolume);
    _ambientPlayer?.play();
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    _ambientPlayer?.setVolume(_isMuted ? 0.0 : _ambientVolume);
    _animalPlayer?.setVolume(_isMuted ? 0.0 : _animalVolume);
  }

  bool get isMuted => _isMuted;
  bool get isInitialized => _isInitialized;
  bool get isMusicPlaying => _musicPlaying;

  /// Play soft sentimental background music during narration
  /// Uses SoundHelix free music (allows hotlinking)
  Future<void> startNarratorMusic() async {
    if (!_isInitialized || _musicPlayer == null || _isMuted) return;
    if (_musicPlaying) return; // Already playing

    try {
      // SoundHelix provides royalty-free ambient music that allows hotlinking
      // Song 1 is a soft, contemplative piano piece perfect for narration
      const musicUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

      await _musicPlayer!.setUrl(musicUrl);
      await _musicPlayer!.setLoopMode(LoopMode.one);
      await _musicPlayer!.setVolume(0.15); // Very soft - doesn't overpower TTS
      _musicPlayer!.play();
      _musicPlaying = true;
      print('Started narrator background music');
    } catch (e) {
      print('Failed to start narrator music: $e');
      _musicPlaying = false;
    }
  }

  /// Stop narrator background music with fade out
  Future<void> stopNarratorMusic() async {
    if (!_musicPlaying || _musicPlayer == null) return;

    try {
      // Quick fade out
      for (double v = 0.15; v > 0; v -= 0.03) {
        await _musicPlayer!.setVolume(v);
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await _musicPlayer!.stop();
    } catch (e) {
      print('Error stopping narrator music: $e');
    }
    _musicPlaying = false;
  }

  /// Stop all audio
  Future<void> stopAll() async {
    await _ambientPlayer?.stop();
    await _animalPlayer?.stop();
    await _narrationPlayer?.stop();
    await _musicPlayer?.stop();
    _musicPlaying = false;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _ambientPlayer?.dispose();
    await _animalPlayer?.dispose();
    await _narrationPlayer?.dispose();
    await _musicPlayer?.dispose();
    _ambientPlayer = null;
    _animalPlayer = null;
    _narrationPlayer = null;
    _musicPlayer = null;
    _isInitialized = false;
    _musicPlaying = false;
  }
}
