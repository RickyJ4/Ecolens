import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';

/// World-first proximity-driven species interaction system.
/// "The Silent Hunt" - approach wildlife carefully or they flee.
class SilentHuntService {
  // Singleton
  static final SilentHuntService _instance = SilentHuntService._internal();
  factory SilentHuntService() => _instance;
  SilentHuntService._internal();

  // State
  final Map<String, SpeciesHuntState> _speciesStates = {};
  final _stateController = StreamController<SilentHuntEvent>.broadcast();

  Stream<SilentHuntEvent> get events => _stateController.stream;

  // Audio mixing state
  double _ambientVolume = 1.0;
  double _animalVolume = 0.0;
  String? _activeAnimalSound;

  // User movement tracking
  double _lastUserSpeed = 0;
  double _lastNoiseLevel = 0;
  DateTime _lastMovementTime = DateTime.now();

  /// Initialize species for hunting in the current scene
  void initializeSpecies(List<HuntableSpecies> species, double forestHectares, double riskScore) {
    _speciesStates.clear();

    for (final s in species) {
      // Calculate habitat fragmentation effect
      final habitatIntact = forestHectares >= s.habitatRequirement;
      final fragmentationSeverity = (riskScore / 100).clamp(0.0, 1.0);

      _speciesStates[s.id] = SpeciesHuntState(
        species: s,
        currentZone: ProximityZone.distant,
        alertLevel: 0,
        habitatIntact: habitatIntact,
        fragmentationSeverity: fragmentationSeverity,
        hasFled: false,
        hasVanished: false,
      );
    }

    _stateController.add(SilentHuntEvent.initialized(species.length));
  }

  /// Update user's position relative to species
  /// Returns the hunt state for UI updates
  HuntUpdate updateUserPosition({
    required String speciesId,
    required double distanceMeters,
    required double userSpeedMps,
    required double noiseLevel,
  }) {
    final state = _speciesStates[speciesId];
    if (state == null || state.hasFled || state.hasVanished) {
      return HuntUpdate.noChange();
    }

    final species = state.species;
    _lastUserSpeed = userSpeedMps;
    _lastNoiseLevel = noiseLevel;
    _lastMovementTime = DateTime.now();

    // Determine proximity zone
    final zone = _calculateZone(distanceMeters, species.flightDistanceM);
    final zoneChanged = zone != state.currentZone;

    // Check for flee conditions
    final shouldFlee = _checkFleeCondition(species, userSpeedMps, noiseLevel);

    if (shouldFlee && zone != ProximityZone.distant) {
      return _handleFlee(speciesId, state);
    }

    // Update zone if changed
    if (zoneChanged) {
      _speciesStates[speciesId] = state.copyWith(
        currentZone: zone,
        alertLevel: _calculateAlertLevel(zone, species),
      );

      // Calculate audio mix
      final audioMix = _calculateAudioMix(zone);
      _ambientVolume = audioMix.ambientVolume;
      _animalVolume = audioMix.animalVolume;
      _activeAnimalSound = species.sounds[_getSoundForZone(zone)];

      // Fire haptic feedback
      _triggerHaptic(zone);

      _stateController.add(SilentHuntEvent.zoneChanged(
        speciesId: speciesId,
        newZone: zone,
        audioMix: audioMix,
      ));

      // Check for connection achievement
      if (zone == ProximityZone.connection) {
        _stateController.add(SilentHuntEvent.connectionAchieved(speciesId));
      }

      return HuntUpdate(
        zoneChanged: true,
        newZone: zone,
        audioMix: audioMix,
        narration: _getNarrationForZone(zone),
        hapticPattern: _getHapticForZone(zone),
      );
    }

    return HuntUpdate.noChange();
  }

  HuntUpdate _handleFlee(String speciesId, SpeciesHuntState state) {
    // Determine outcome based on habitat fragmentation
    if (!state.habitatIntact || state.fragmentationSeverity > 0.7) {
      // VANISH - no habitat to flee to (the lesson!)
      _speciesStates[speciesId] = state.copyWith(hasVanished: true);

      // Dramatic pause, then silence
      _ambientVolume = 0.0;
      _animalVolume = 0.0;

      // Strong haptic for emotional impact
      HapticFeedback.heavyImpact();

      _stateController.add(SilentHuntEvent.speciesVanished(
        speciesId: speciesId,
        reason: 'No habitat remaining - nowhere to flee',
      ));

      return HuntUpdate(
        fled: true,
        vanished: true,
        narration: HuntNarration(
          text: "It tried to flee... but there's nowhere left to go. This is what habitat fragmentation looks like.",
          style: NarrationStyle.grave,
          duration: const Duration(seconds: 6),
        ),
        hapticPattern: HapticPattern.prolongedVibration,
        lesson: "When habitat shrinks below critical thresholds, there's nowhere left to go. This is extinction in real-time.",
      );
    } else {
      // Normal flee
      _speciesStates[speciesId] = state.copyWith(hasFled: true);

      _ambientVolume = 1.0;
      _animalVolume = 0.0;

      HapticFeedback.mediumImpact();

      _stateController.add(SilentHuntEvent.speciesFled(speciesId));

      return HuntUpdate(
        fled: true,
        vanished: false,
        narration: HuntNarration(
          text: "It's gone. In the wild, they have endless forest to disappear into.",
          style: NarrationStyle.measured,
          duration: const Duration(seconds: 4),
        ),
        hapticPattern: HapticPattern.sharpPulse,
        lesson: "In intact forests, animals have escape routes. Connectivity is survival.",
      );
    }
  }

  ProximityZone _calculateZone(double distanceM, double flightDistanceM) {
    final ratio = distanceM / flightDistanceM;

    if (ratio > 2.0) return ProximityZone.distant;
    if (ratio > 1.0) return ProximityZone.aware;
    if (ratio > 0.5) return ProximityZone.close;
    if (ratio > 0.2) return ProximityZone.intimate;
    return ProximityZone.connection;
  }

  bool _checkFleeCondition(HuntableSpecies species, double speedMps, double noiseLevel) {
    // Speed check
    final speedThreshold = 3.0 * (1 - species.speedSensitivity);
    if (speedMps > speedThreshold) return true;

    // Noise check (sudden tap = noise spike)
    final noiseThreshold = 0.8 * (1 - species.noiseSensitivity);
    if (noiseLevel > noiseThreshold) return true;

    // Curiosity factor - chance to stay even when scared
    if (speedMps > speedThreshold * 0.7 || noiseLevel > noiseThreshold * 0.7) {
      return Random().nextDouble() > species.curiosityFactor;
    }

    return false;
  }

  double _calculateAlertLevel(ProximityZone zone, HuntableSpecies species) {
    switch (zone) {
      case ProximityZone.distant:
        return 0.0;
      case ProximityZone.aware:
        return 0.3;
      case ProximityZone.close:
        return 0.6;
      case ProximityZone.intimate:
        return 0.4; // Less alert if you got this close without scaring
      case ProximityZone.connection:
        return 0.2; // Calm connection
    }
  }

  AudioMix _calculateAudioMix(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return AudioMix(ambientVolume: 1.0, animalVolume: 0.1);
      case ProximityZone.aware:
        return AudioMix(ambientVolume: 0.8, animalVolume: 0.3);
      case ProximityZone.close:
        return AudioMix(ambientVolume: 0.5, animalVolume: 0.6);
      case ProximityZone.intimate:
        return AudioMix(ambientVolume: 0.2, animalVolume: 0.9);
      case ProximityZone.connection:
        return AudioMix(ambientVolume: 0.05, animalVolume: 1.0, heartbeatEnabled: true);
    }
  }

  String _getSoundForZone(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return 'distant';
      case ProximityZone.aware:
        return 'alert';
      case ProximityZone.close:
      case ProximityZone.intimate:
      case ProximityZone.connection:
        return 'breathing';
    }
  }

  void _triggerHaptic(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        break;
      case ProximityZone.aware:
        HapticFeedback.lightImpact();
        break;
      case ProximityZone.close:
        HapticFeedback.mediumImpact();
        break;
      case ProximityZone.intimate:
        HapticFeedback.selectionClick();
        break;
      case ProximityZone.connection:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  HuntNarration _getNarrationForZone(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return HuntNarration.none();
      case ProximityZone.aware:
        return HuntNarration(
          text: "It knows you're here. Move slowly.",
          style: NarrationStyle.whisper,
          duration: const Duration(seconds: 3),
        );
      case ProximityZone.close:
        return HuntNarration(
          text: "You can hear it breathing now. Be still.",
          style: NarrationStyle.whisper,
          duration: const Duration(seconds: 3),
        );
      case ProximityZone.intimate:
        return HuntNarration(
          text: "Remarkable. Most humans never get this close.",
          style: NarrationStyle.reverent,
          duration: const Duration(seconds: 4),
        );
      case ProximityZone.connection:
        return HuntNarration(
          text: "For a moment, you exist in its world. This is what we're fighting to protect.",
          style: NarrationStyle.emotional,
          duration: const Duration(seconds: 5),
        );
    }
  }

  HapticPattern _getHapticForZone(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return HapticPattern.none;
      case ProximityZone.aware:
        return HapticPattern.lightTap;
      case ProximityZone.close:
        return HapticPattern.gentlePulse;
      case ProximityZone.intimate:
        return HapticPattern.heartbeatSlow;
      case ProximityZone.connection:
        return HapticPattern.heartbeatFast;
    }
  }

  /// Simulate a sudden noise (e.g., user tapped screen loudly)
  void triggerNoise(double intensity) {
    _lastNoiseLevel = intensity;

    // Check all nearby species for flee response
    for (final entry in _speciesStates.entries) {
      final state = entry.value;
      if (state.hasFled || state.hasVanished) continue;
      if (state.currentZone == ProximityZone.distant) continue;

      if (_checkFleeCondition(state.species, 0, intensity)) {
        _handleFlee(entry.key, state);
      }
    }
  }

  /// Get current state for UI display
  SpeciesHuntState? getState(String speciesId) => _speciesStates[speciesId];

  List<SpeciesHuntState> get allStates => _speciesStates.values.toList();

  /// Current audio levels for audio player
  double get ambientVolume => _ambientVolume;
  double get animalVolume => _animalVolume;
  String? get activeAnimalSound => _activeAnimalSound;

  void dispose() {
    _stateController.close();
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════

enum ProximityZone {
  distant,   // > 2x flight distance
  aware,     // 1-2x flight distance
  close,     // 0.5-1x flight distance
  intimate,  // 0.2-0.5x flight distance
  connection // < 0.2x flight distance
}

enum NarrationStyle { whisper, reverent, emotional, measured, grave }
enum HapticPattern { none, lightTap, gentlePulse, heartbeatSlow, heartbeatFast, sharpPulse, prolongedVibration }

class HuntableSpecies {
  final String id;
  final String name;
  final String scientificName;
  final String conservationStatus;
  final String category;
  final double flightDistanceM;
  final double panicDistanceM;
  final double speedSensitivity;
  final double noiseSensitivity;
  final double curiosityFactor;
  final double habitatRequirement; // hectares
  final Map<String, String> sounds;
  final Map<String, String> animations;

  const HuntableSpecies({
    required this.id,
    required this.name,
    this.scientificName = '',
    this.conservationStatus = 'Vulnerable',
    this.category = 'generic',
    this.flightDistanceM = 50,
    this.panicDistanceM = 15,
    this.speedSensitivity = 0.6,
    this.noiseSensitivity = 0.6,
    this.curiosityFactor = 0.5,
    this.habitatRequirement = 100,
    this.sounds = const {},
    this.animations = const {},
  });

  /// Create from backend silent hunt data
  factory HuntableSpecies.fromJson(Map<String, dynamic> json) {
    final behavior = json['behavior'] as Map<String, dynamic>? ?? {};
    return HuntableSpecies(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      scientificName: json['scientificName'] ?? '',
      conservationStatus: json['conservationStatus'] ?? 'Vulnerable',
      category: behavior['category'] ?? 'generic',
      flightDistanceM: (behavior['flightDistanceM'] ?? 50).toDouble(),
      panicDistanceM: (behavior['panicDistanceM'] ?? 15).toDouble(),
      speedSensitivity: (behavior['speedSensitivity'] ?? 0.6).toDouble(),
      noiseSensitivity: (behavior['noiseSensitivity'] ?? 0.6).toDouble(),
      curiosityFactor: (behavior['curiosityFactor'] ?? 0.5).toDouble(),
      habitatRequirement: (json['habitatStatus']?['requiredHectares'] ?? 100).toDouble(),
      sounds: Map<String, String>.from(json['sounds'] ?? {}),
      animations: Map<String, String>.from(json['animations'] ?? {}),
    );
  }
}

class SpeciesHuntState {
  final HuntableSpecies species;
  final ProximityZone currentZone;
  final double alertLevel;
  final bool habitatIntact;
  final double fragmentationSeverity;
  final bool hasFled;
  final bool hasVanished;

  const SpeciesHuntState({
    required this.species,
    required this.currentZone,
    required this.alertLevel,
    required this.habitatIntact,
    required this.fragmentationSeverity,
    required this.hasFled,
    required this.hasVanished,
  });

  SpeciesHuntState copyWith({
    ProximityZone? currentZone,
    double? alertLevel,
    bool? hasFled,
    bool? hasVanished,
  }) {
    return SpeciesHuntState(
      species: species,
      currentZone: currentZone ?? this.currentZone,
      alertLevel: alertLevel ?? this.alertLevel,
      habitatIntact: habitatIntact,
      fragmentationSeverity: fragmentationSeverity,
      hasFled: hasFled ?? this.hasFled,
      hasVanished: hasVanished ?? this.hasVanished,
    );
  }
}

class AudioMix {
  final double ambientVolume;
  final double animalVolume;
  final bool heartbeatEnabled;

  const AudioMix({
    required this.ambientVolume,
    required this.animalVolume,
    this.heartbeatEnabled = false,
  });
}

class HuntNarration {
  final String text;
  final NarrationStyle style;
  final Duration duration;

  const HuntNarration({
    required this.text,
    required this.style,
    required this.duration,
  });

  factory HuntNarration.none() => const HuntNarration(
    text: '',
    style: NarrationStyle.whisper,
    duration: Duration.zero,
  );

  bool get isEmpty => text.isEmpty;
}

class HuntUpdate {
  final bool zoneChanged;
  final bool fled;
  final bool vanished;
  final ProximityZone? newZone;
  final AudioMix? audioMix;
  final HuntNarration? narration;
  final HapticPattern hapticPattern;
  final String? lesson;

  const HuntUpdate({
    this.zoneChanged = false,
    this.fled = false,
    this.vanished = false,
    this.newZone,
    this.audioMix,
    this.narration,
    this.hapticPattern = HapticPattern.none,
    this.lesson,
  });

  factory HuntUpdate.noChange() => const HuntUpdate();
}

// ═══════════════════════════════════════════════════════════════
// EVENTS
// ═══════════════════════════════════════════════════════════════

abstract class SilentHuntEvent {
  factory SilentHuntEvent.initialized(int speciesCount) = SilentHuntInitialized;
  factory SilentHuntEvent.zoneChanged({
    required String speciesId,
    required ProximityZone newZone,
    required AudioMix audioMix,
  }) = SilentHuntZoneChanged;
  factory SilentHuntEvent.speciesFled(String speciesId) = SilentHuntSpeciesFled;
  factory SilentHuntEvent.speciesVanished({
    required String speciesId,
    required String reason,
  }) = SilentHuntSpeciesVanished;
  factory SilentHuntEvent.connectionAchieved(String speciesId) = SilentHuntConnectionAchieved;
}

class SilentHuntInitialized implements SilentHuntEvent {
  final int speciesCount;
  SilentHuntInitialized(this.speciesCount);
}

class SilentHuntZoneChanged implements SilentHuntEvent {
  final String speciesId;
  final ProximityZone newZone;
  final AudioMix audioMix;
  SilentHuntZoneChanged({
    required this.speciesId,
    required this.newZone,
    required this.audioMix,
  });
}

class SilentHuntSpeciesFled implements SilentHuntEvent {
  final String speciesId;
  SilentHuntSpeciesFled(this.speciesId);
}

class SilentHuntSpeciesVanished implements SilentHuntEvent {
  final String speciesId;
  final String reason;
  SilentHuntSpeciesVanished({required this.speciesId, required this.reason});
}

class SilentHuntConnectionAchieved implements SilentHuntEvent {
  final String speciesId;
  SilentHuntConnectionAchieved(this.speciesId);
}
