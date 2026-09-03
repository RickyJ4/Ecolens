import 'dart:async';

/// Narrator service that provides contextual storytelling throughout the AR experience.
/// The narrator explains what's happening, provides educational context, and
/// creates emotional connections to the environmental data.
class NarratorService {
  // Singleton
  static final NarratorService _instance = NarratorService._internal();
  factory NarratorService() => _instance;
  NarratorService._internal();

  final _narrationController = StreamController<NarrationEvent>.broadcast();
  Stream<NarrationEvent> get narrations => _narrationController.stream;

  // Current state
  NarrationEvent? _currentNarration;
  Timer? _autoAdvanceTimer;
  bool _isPaused = false;
  bool _waitingForTTSCompletion = false;

  // Queue of narrations to play
  final List<NarrationEvent> _queue = [];

  /// Called by TTS service when speech completes - advances to next narration
  void onTTSComplete() {
    if (_waitingForTTSCompletion && !_isPaused) {
      _waitingForTTSCompletion = false;
      _autoAdvanceTimer?.cancel();
      if (_queue.isNotEmpty) {
        // Small pause between narrations for natural pacing
        _autoAdvanceTimer = Timer(const Duration(milliseconds: 600), () {
          _playNext();
        });
      } else {
        _narrationController.add(NarrationEvent.empty());
      }
    }
  }

  /// Calculate estimated speech duration based on text length
  /// With our slow TTS rate (0.40-0.44), speech is approximately 1 word per second
  /// This ensures narration cards stay visible long enough for TTS to complete
  Duration _estimateSpeechDuration(String text) {
    final wordCount = text.split(RegExp(r'\s+')).length;
    // At rate 0.40-0.44, roughly 1 word per second
    // Add 3 second buffer for pauses and natural delivery
    final seconds = wordCount + 3;
    return Duration(seconds: seconds.clamp(5, 45));
  }

  /// Generate welcome narration when entering AR
  void narrateWelcome({
    required String regionName,
    required double hectares,
    required double riskScore,
    required int speciesCount,
    required String habitat,
  }) {
    final riskLevel = riskScore >= 80 ? 'critical' : (riskScore >= 60 ? 'high' : 'concerning');

    _queueNarration(NarrationEvent(
      id: 'welcome_1',
      text: 'Welcome to $regionName.',
      style: NarrationStyle.intro,
      duration: const Duration(seconds: 3),
      ssml: '<speak><prosody rate="slow">Welcome to <emphasis level="moderate">$regionName</emphasis>.</prosody></speak>',
    ));

    _queueNarration(NarrationEvent(
      id: 'welcome_2',
      text: 'You are standing in what was once a thriving ${habitat.toLowerCase()} ecosystem.',
      style: NarrationStyle.narrative,
      duration: const Duration(seconds: 4),
    ));

    _queueNarration(NarrationEvent(
      id: 'welcome_3',
      text: 'This region now faces $riskLevel environmental pressure.',
      style: NarrationStyle.warning,
      duration: const Duration(seconds: 3),
      emphasis: riskScore >= 70,
    ));

    _queueNarration(NarrationEvent(
      id: 'welcome_4',
      text: '${hectares.toInt()} hectares of forest. $speciesCount species at risk. Look around to discover the story of this land.',
      style: NarrationStyle.data,
      duration: const Duration(seconds: 5),
    ));

    _startNarration();
  }

  /// Narrate the transition to deforested view
  void narrateDeforestation({
    required double hectaresLost,
    required double carbonEmissions,
    required int peopleAffected,
  }) {
    _clearQueue();

    _queueNarration(NarrationEvent(
      id: 'deforest_1',
      text: 'This is what remains.',
      style: NarrationStyle.grave,
      duration: const Duration(seconds: 2),
      emphasis: true,
    ));

    _queueNarration(NarrationEvent(
      id: 'deforest_2',
      text: '${hectaresLost.toInt()} hectares cleared. The trees that took centuries to grow, gone in months.',
      style: NarrationStyle.narrative,
      duration: const Duration(seconds: 4),
    ));

    if (carbonEmissions > 0) {
      final co2K = (carbonEmissions / 1000).toStringAsFixed(1);
      _queueNarration(NarrationEvent(
        id: 'deforest_3',
        text: 'Every year, $co2K thousand tonnes of CO2 are released into our atmosphere from this area alone.',
        style: NarrationStyle.data,
        duration: const Duration(seconds: 4),
      ));
    }

    if (peopleAffected > 0) {
      _queueNarration(NarrationEvent(
        id: 'deforest_4',
        text: 'And behind these numbers are $peopleAffected people whose lives depend on this forest.',
        style: NarrationStyle.emotional,
        duration: const Duration(seconds: 4),
      ));
    }

    _startNarration();
  }

  /// Narrate returning to healthy forest view
  void narrateRestoration() {
    _clearQueue();

    _queueNarration(NarrationEvent(
      id: 'restore_1',
      text: 'But it doesn\'t have to end this way.',
      style: NarrationStyle.hopeful,
      duration: const Duration(seconds: 3),
    ));

    _queueNarration(NarrationEvent(
      id: 'restore_2',
      text: 'This is what we\'re fighting to protect. What we can still save.',
      style: NarrationStyle.inspiring,
      duration: const Duration(seconds: 4),
    ));

    _startNarration();
  }

  /// Narrate species information
  void narrateSpecies({
    required String speciesName,
    required String status,
    required bool isFauna,
    required double habitatLossHectares,
  }) {
    _clearQueue();

    final statusNarration = _getStatusNarration(status);

    _queueNarration(NarrationEvent(
      id: 'species_1',
      text: 'The $speciesName.',
      style: NarrationStyle.intro,
      duration: const Duration(seconds: 2),
    ));

    _queueNarration(NarrationEvent(
      id: 'species_2',
      text: statusNarration,
      style: NarrationStyle.warning,
      duration: const Duration(seconds: 3),
    ));

    final impactText = isFauna
        ? 'With ${habitatLossHectares.toInt()} hectares of habitat destroyed, it has fewer places to hunt, shelter, and raise young.'
        : 'As the forest shrinks, this species loses the ecosystem it depends on for survival.';

    _queueNarration(NarrationEvent(
      id: 'species_3',
      text: impactText,
      style: NarrationStyle.narrative,
      duration: const Duration(seconds: 5),
    ));

    _startNarration();
  }

  /// Narrate Silent Hunt proximity events
  void narrateSilentHunt({
    required String speciesName,
    required SilentHuntPhase phase,
    required bool habitatFragmented,
  }) {
    _clearQueue();

    switch (phase) {
      case SilentHuntPhase.approaching:
        _queueNarration(NarrationEvent(
          id: 'hunt_approach',
          text: 'A $speciesName. It knows you\'re here. Move slowly.',
          style: NarrationStyle.whisper,
          duration: const Duration(seconds: 3),
        ));
        break;

      case SilentHuntPhase.close:
        _queueNarration(NarrationEvent(
          id: 'hunt_close',
          text: 'You can hear it breathing now. Be still.',
          style: NarrationStyle.whisper,
          duration: const Duration(seconds: 3),
        ));
        break;

      case SilentHuntPhase.connection:
        _queueNarration(NarrationEvent(
          id: 'hunt_connect',
          text: 'For a moment, you exist in its world. This is what we\'re fighting to protect.',
          style: NarrationStyle.emotional,
          duration: const Duration(seconds: 5),
          emphasis: true,
        ));
        break;

      case SilentHuntPhase.fled:
        _queueNarration(NarrationEvent(
          id: 'hunt_fled',
          text: 'It\'s gone. In the wild, they have endless forest to disappear into.',
          style: NarrationStyle.narrative,
          duration: const Duration(seconds: 4),
        ));
        break;

      case SilentHuntPhase.vanished:
        _queueNarration(NarrationEvent(
          id: 'hunt_vanish_1',
          text: 'It tried to flee...',
          style: NarrationStyle.grave,
          duration: const Duration(seconds: 2),
        ));
        _queueNarration(NarrationEvent(
          id: 'hunt_vanish_2',
          text: 'But there\'s nowhere left to go.',
          style: NarrationStyle.grave,
          duration: const Duration(seconds: 3),
          emphasis: true,
        ));
        _queueNarration(NarrationEvent(
          id: 'hunt_vanish_3',
          text: 'This is what habitat fragmentation looks like. This is extinction in real-time.',
          style: NarrationStyle.grave,
          duration: const Duration(seconds: 5),
        ));
        break;
    }

    _startNarration();
  }

  /// Narrate ecosystem chain reactions
  void narrateEcosystemImpact({
    required String triggerSpecies,
    required List<String> affectedSpecies,
  }) {
    _clearQueue();

    _queueNarration(NarrationEvent(
      id: 'ecosystem_1',
      text: 'When the $triggerSpecies disappears, it doesn\'t end there.',
      style: NarrationStyle.narrative,
      duration: const Duration(seconds: 3),
    ));

    if (affectedSpecies.isNotEmpty) {
      final affected = affectedSpecies.take(3).join(', ');
      _queueNarration(NarrationEvent(
        id: 'ecosystem_2',
        text: 'The $affected - they all depend on this delicate balance.',
        style: NarrationStyle.data,
        duration: const Duration(seconds: 4),
      ));
    }

    _queueNarration(NarrationEvent(
      id: 'ecosystem_3',
      text: 'In nature, everything is connected. Remove one thread, and the tapestry unravels.',
      style: NarrationStyle.philosophical,
      duration: const Duration(seconds: 5),
    ));

    _startNarration();
  }

  /// Narrate tour step
  void narrateTourStep(int step, int totalSteps, String content) {
    _clearQueue();

    _queueNarration(NarrationEvent(
      id: 'tour_$step',
      text: content,
      style: NarrationStyle.guide,
      duration: const Duration(seconds: 5),
    ));

    _startNarration();
  }

  /// Narrate time-of-day context
  void narrateTimeContext(TimeOfDay time) {
    String narration;
    NarrationStyle style;

    switch (time) {
      case TimeOfDay.dawn:
        narration = 'Dawn breaks. The forest awakens with the calls of birds and the rustle of nocturnal creatures returning to their dens.';
        style = NarrationStyle.atmospheric;
        break;
      case TimeOfDay.day:
        narration = 'Under the midday sun, the forest canopy filters light into dancing shadows. Life teems at every level.';
        style = NarrationStyle.atmospheric;
        break;
      case TimeOfDay.dusk:
        narration = 'As twilight descends, the forest transforms. Day creatures settle while night hunters begin to stir.';
        style = NarrationStyle.atmospheric;
        break;
      case TimeOfDay.night:
        narration = 'Night falls. In the darkness, a different world emerges - one few humans ever witness.';
        style = NarrationStyle.atmospheric;
        break;
    }

    _clearQueue();
    _queueNarration(NarrationEvent(
      id: 'time_${time.name}',
      text: narration,
      style: style,
      duration: const Duration(seconds: 5),
    ));
    _startNarration();
  }

  // Helper methods

  String _getStatusNarration(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('critically endangered')) {
      return 'Critically endangered. On the very edge of extinction.';
    } else if (lower.contains('endangered')) {
      return 'Endangered. Without intervention, it may not survive another generation.';
    } else if (lower.contains('vulnerable')) {
      return 'Vulnerable. Its numbers are declining faster than it can adapt.';
    } else if (lower.contains('near threatened')) {
      return 'Near threatened. The warning signs are already appearing.';
    }
    return 'Its future hangs in the balance.';
  }

  void _queueNarration(NarrationEvent event) {
    _queue.add(event);
  }

  void _clearQueue() {
    _queue.clear();
    _autoAdvanceTimer?.cancel();
  }

  void _startNarration() {
    if (_queue.isEmpty || _isPaused) return;

    _playNext();
  }

  void _playNext() {
    if (_queue.isEmpty) {
      _currentNarration = null;
      return;
    }

    _currentNarration = _queue.removeAt(0);
    _narrationController.add(_currentNarration!);

    // Mark that we're waiting for TTS to complete
    _waitingForTTSCompletion = true;

    // Calculate realistic speech duration based on text length
    // This is used as a FALLBACK only - primary advancement is via TTS completion callback
    final speechDuration = _estimateSpeechDuration(_currentNarration!.text);

    // Fallback auto-advance timer in case TTS callback doesn't fire
    // Add extra buffer time (1.5x calculated) to ensure TTS has time to complete
    _autoAdvanceTimer?.cancel();
    final fallbackDuration = Duration(
      milliseconds: (speechDuration.inMilliseconds * 1.5).round(),
    );
    _autoAdvanceTimer = Timer(fallbackDuration, () {
      if (!_isPaused && _waitingForTTSCompletion) {
        // Only advance if we're still waiting (TTS callback didn't fire)
        _waitingForTTSCompletion = false;
        if (_queue.isNotEmpty) {
          _playNext();
        } else {
          _narrationController.add(NarrationEvent.empty());
        }
      }
    });
  }

  void pause() {
    _isPaused = true;
    _autoAdvanceTimer?.cancel();
  }

  void resume() {
    _isPaused = false;
    if (_queue.isNotEmpty) {
      _playNext();
    }
  }

  void skip() {
    _autoAdvanceTimer?.cancel();
    if (_queue.isNotEmpty) {
      _playNext();
    } else {
      _narrationController.add(NarrationEvent.empty());
    }
  }

  void stop() {
    _clearQueue();
    _currentNarration = null;
    _narrationController.add(NarrationEvent.empty());
  }

  NarrationEvent? get current => _currentNarration;
  bool get isPlaying => _currentNarration != null && !_isPaused;
  bool get hasQueue => _queue.isNotEmpty;

  void dispose() {
    _autoAdvanceTimer?.cancel();
    _narrationController.close();
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════

enum NarrationStyle {
  intro,          // Opening statements
  narrative,      // Story-like descriptions
  data,           // Statistical information
  warning,        // Alert-level information
  grave,          // Serious, somber tone
  emotional,      // Heart-touching content
  hopeful,        // Optimistic messaging
  inspiring,      // Call-to-action
  whisper,        // Quiet, tension-building
  atmospheric,    // Environmental description
  philosophical,  // Deeper meaning
  guide,          // Tutorial/instructional
}

enum SilentHuntPhase {
  approaching,
  close,
  connection,
  fled,
  vanished,
}

enum TimeOfDay {
  dawn,
  day,
  dusk,
  night,
}

class NarrationEvent {
  final String id;
  final String text;
  final NarrationStyle style;
  final Duration duration;
  final String? ssml;
  final bool emphasis;

  const NarrationEvent({
    required this.id,
    required this.text,
    required this.style,
    required this.duration,
    this.ssml,
    this.emphasis = false,
  });

  factory NarrationEvent.empty() => const NarrationEvent(
    id: '',
    text: '',
    style: NarrationStyle.narrative,
    duration: Duration.zero,
  );

  bool get isEmpty => text.isEmpty;

  /// Get the appropriate text color for this narration style
  int get styleColorValue {
    switch (style) {
      case NarrationStyle.intro:
        return 0xFFFFFFFF; // White
      case NarrationStyle.narrative:
        return 0xFFB0BEC5; // Blue grey
      case NarrationStyle.data:
        return 0xFF64FFDA; // Cyan
      case NarrationStyle.warning:
        return 0xFFFFAB40; // Orange
      case NarrationStyle.grave:
        return 0xFFFF5252; // Red
      case NarrationStyle.emotional:
        return 0xFFE040FB; // Purple
      case NarrationStyle.hopeful:
        return 0xFF00E676; // Green
      case NarrationStyle.inspiring:
        return 0xFF40C4FF; // Light blue
      case NarrationStyle.whisper:
        return 0x99FFFFFF; // Semi-transparent white
      case NarrationStyle.atmospheric:
        return 0xFF80CBC4; // Teal
      case NarrationStyle.philosophical:
        return 0xFFCE93D8; // Light purple
      case NarrationStyle.guide:
        return 0xFFFFFFFF; // White
    }
  }

  /// Get font size multiplier for this style
  double get fontSizeMultiplier {
    switch (style) {
      case NarrationStyle.whisper:
        return 0.9;
      case NarrationStyle.grave:
      case NarrationStyle.emotional:
        return emphasis ? 1.2 : 1.1;
      default:
        return 1.0;
    }
  }

  /// Should this narration use italic text?
  bool get isItalic {
    return style == NarrationStyle.whisper ||
           style == NarrationStyle.philosophical ||
           style == NarrationStyle.atmospheric;
  }
}
