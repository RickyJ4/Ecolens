import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ecolens/services/silent_hunt_service.dart';

/// Service to fetch and parse immersive story data from the backend.
/// Connects the frontend Silent Hunt and Narrator systems with backend-generated content.
class StoryDataService {
  // Singleton
  static final StoryDataService _instance = StoryDataService._internal();
  factory StoryDataService() => _instance;
  StoryDataService._internal();

  // Backend URL - Firebase Cloud Functions
  // Note: Use ecolens-ad854 project ID (matches firebase.json)
  static const String _baseUrl = 'https://us-central1-ecolens-ad854.cloudfunctions.net';

  // Cached data
  Map<String, dynamic>? _cachedStoryData;
  String? _cachedNodeId;

  /// Fetch story data for a specific intelligence node
  Future<StoryData?> fetchStoryData(String nodeId) async {
    // Return cached if same node
    if (_cachedNodeId == nodeId && _cachedStoryData != null) {
      return StoryData.fromJson(_cachedStoryData!);
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/getStory?nodeId=$nodeId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _cachedStoryData = data;
        _cachedNodeId = nodeId;
        return StoryData.fromJson(data);
      }
    } catch (e) {
      // Log error but don't crash - fallback to local generation
      print('Failed to fetch story data: $e');
    }

    return null;
  }

  /// Fetch story configuration for CesiumJS viewer
  /// Returns a storyConfig map suitable for the 3D story viewer
  /// Calls the get_story Firebase callable function
  Future<Map<String, dynamic>?> fetchStoryConfig({
    String? nodeId,
    required double lat,
    required double lng,
  }) async {
    // Check cache first
    final cacheKey = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
    if (_cachedNodeId == cacheKey && _cachedStoryData != null) {
      return _cachedStoryData;
    }

    try {
      // Firebase callable functions expect {data: {...}} format
      final response = await http.post(
        Uri.parse('$_baseUrl/get_story'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'data': {
            'lat': lat,
            'lng': lng,
            'nodeId': nodeId,
          }
        }),
      ).timeout(const Duration(seconds: 60)); // Longer timeout for story generation

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body) as Map<String, dynamic>;
        // Firebase callable returns {result: {...}}
        final data = responseData['result'] as Map<String, dynamic>? ?? responseData;
        _cachedStoryData = data;
        _cachedNodeId = cacheKey;
        return data;
      } else {
        print('Story config request failed with status: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Failed to fetch story config: $e');
    }

    // Return null to trigger local fallback generation
    return null;
  }

  /// Parse Silent Hunt species from backend data
  List<HuntableSpecies> parseHuntableSpecies(Map<String, dynamic> silentHuntData) {
    final species = silentHuntData['species'] as List<dynamic>? ?? [];

    return species.map((s) {
      final json = s as Map<String, dynamic>;
      return HuntableSpecies.fromJson(json);
    }).toList();
  }

  /// Parse proximity zones from backend
  Map<String, ProximityZoneConfig> parseProximityZones(Map<String, dynamic> data) {
    final zones = data['proximityZones'] as Map<String, dynamic>? ?? {};
    final result = <String, ProximityZoneConfig>{};

    zones.forEach((key, value) {
      final config = value as Map<String, dynamic>;
      result[key] = ProximityZoneConfig(
        minDistance: (config['minDistance'] ?? 0).toDouble(),
        maxDistance: (config['maxDistance'] ?? 100).toDouble(),
        ambientVolume: (config['ambientVolume'] ?? 1.0).toDouble(),
        animalVolume: (config['animalVolume'] ?? 0.0).toDouble(),
        narrationStyle: config['narrationStyle'] ?? 'narrative',
      );
    });

    return result;
  }

  /// Parse narration scripts from backend
  Map<String, NarrationScript> parseNarrationScripts(Map<String, dynamic> data) {
    final narration = data['narration'] as Map<String, dynamic>? ?? {};
    final result = <String, NarrationScript>{};

    narration.forEach((key, value) {
      final script = value as Map<String, dynamic>;
      result[key] = NarrationScript(
        text: script['text'] ?? '',
        ssml: script['ssml'],
        style: script['narrator_style'] ?? 'narrative',
        durationSeconds: script['duration_seconds'] ?? 5,
      );
    });

    return result;
  }

  /// Parse ecosystem simulation data
  EcosystemSimulation? parseEcosystemSimulation(Map<String, dynamic>? data) {
    if (data == null) return null;

    return EcosystemSimulation(
      foodWeb: _parseFoodWeb(data['foodWeb']),
      chainReactions: _parseChainReactions(data['chainReactions']),
      symbioticRelationships: _parseSymbiosis(data['symbioticRelationships']),
    );
  }

  List<FoodWebNode> _parseFoodWeb(Map<String, dynamic>? data) {
    if (data == null) return [];
    final nodes = data['nodes'] as List<dynamic>? ?? [];

    return nodes.map((n) {
      final node = n as Map<String, dynamic>;
      return FoodWebNode(
        id: node['id'] ?? '',
        name: node['name'] ?? '',
        level: node['level'] ?? 'producer',
        dependencies: List<String>.from(node['dependencies'] ?? []),
        dependents: List<String>.from(node['dependents'] ?? []),
      );
    }).toList();
  }

  List<ChainReaction> _parseChainReactions(List<dynamic>? data) {
    if (data == null) return [];

    return data.map((r) {
      final reaction = r as Map<String, dynamic>;
      return ChainReaction(
        triggerSpecies: reaction['triggerSpecies'] ?? '',
        triggerEvent: reaction['triggerEvent'] ?? 'extinction',
        effects: (reaction['effects'] as List<dynamic>? ?? []).map((e) {
          final effect = e as Map<String, dynamic>;
          return ChainEffect(
            speciesId: effect['speciesId'] ?? '',
            impactType: effect['impactType'] ?? 'decline',
            severity: (effect['severity'] ?? 0.5).toDouble(),
            narration: effect['narration'] ?? '',
          );
        }).toList(),
        narration: reaction['narration'] ?? '',
      );
    }).toList();
  }

  List<SymbioticRelation> _parseSymbiosis(List<dynamic>? data) {
    if (data == null) return [];

    return data.map((s) {
      final relation = s as Map<String, dynamic>;
      return SymbioticRelation(
        species1: relation['species1'] ?? '',
        species2: relation['species2'] ?? '',
        type: relation['type'] ?? 'mutualism',
        description: relation['description'] ?? '',
        discoveryNarration: relation['discoveryNarration'] ?? '',
      );
    }).toList();
  }

  /// Parse immersive systems (time, weather, etc.)
  ImmersiveSystems? parseImmersiveSystems(Map<String, dynamic>? data) {
    if (data == null) return null;

    return ImmersiveSystems(
      timeOfDayEffects: _parseTimeEffects(data['timeBasedWildlife']),
      weatherImpacts: _parseWeatherImpacts(data['weatherImpacts']),
      discoveries: _parseDiscoveries(data['discoverableSecrets']),
    );
  }

  Map<String, TimeOfDayEffect> _parseTimeEffects(Map<String, dynamic>? data) {
    if (data == null) return {};
    final result = <String, TimeOfDayEffect>{};

    data.forEach((key, value) {
      final effect = value as Map<String, dynamic>;
      result[key] = TimeOfDayEffect(
        soundscape: effect['soundscape'] ?? '',
        visualFilter: effect['visualFilter'] ?? '',
        activeSpecies: List<String>.from(effect['activeSpecies'] ?? []),
        atmosphereDescription: effect['atmosphereDescription'] ?? '',
      );
    });

    return result;
  }

  Map<String, WeatherImpact> _parseWeatherImpacts(Map<String, dynamic>? data) {
    if (data == null) return {};
    final result = <String, WeatherImpact>{};

    data.forEach((key, value) {
      final impact = value as Map<String, dynamic>;
      result[key] = WeatherImpact(
        soundModifier: impact['soundModifier'] ?? '',
        visibilityFactor: (impact['visibilityFactor'] ?? 1.0).toDouble(),
        animalBehaviorChange: impact['animalBehaviorChange'] ?? '',
        narration: impact['narration'] ?? '',
      );
    });

    return result;
  }

  List<Discoverable> _parseDiscoveries(List<dynamic>? data) {
    if (data == null) return [];

    return data.map((d) {
      final disc = d as Map<String, dynamic>;
      return Discoverable(
        id: disc['id'] ?? '',
        name: disc['name'] ?? '',
        type: disc['type'] ?? 'hidden_species',
        triggerCondition: disc['triggerCondition'] ?? '',
        narration: disc['narration'] ?? '',
        reward: disc['reward'],
      );
    }).toList();
  }

  void clearCache() {
    _cachedStoryData = null;
    _cachedNodeId = null;
  }
}

// ═══════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════

class StoryData {
  final Map<String, dynamic> silentHunt;
  final Map<String, dynamic>? ecosystemSimulation;
  final Map<String, dynamic>? immersiveSystems;
  final Map<String, dynamic>? narrator;
  final Map<String, dynamic>? chapters;
  final Map<String, dynamic>? soundscapes;
  final Map<String, dynamic>? visualFilters;

  StoryData({
    required this.silentHunt,
    this.ecosystemSimulation,
    this.immersiveSystems,
    this.narrator,
    this.chapters,
    this.soundscapes,
    this.visualFilters,
  });

  factory StoryData.fromJson(Map<String, dynamic> json) {
    return StoryData(
      silentHunt: json['silentHunt'] as Map<String, dynamic>? ?? {},
      ecosystemSimulation: json['ecosystemSimulation'] as Map<String, dynamic>?,
      immersiveSystems: json['immersiveSystems'] as Map<String, dynamic>?,
      narrator: json['narrator'] as Map<String, dynamic>?,
      chapters: json['chapters'] as Map<String, dynamic>?,
      soundscapes: json['soundscapes'] as Map<String, dynamic>?,
      visualFilters: json['visualFilters'] as Map<String, dynamic>?,
    );
  }
}

class ProximityZoneConfig {
  final double minDistance;
  final double maxDistance;
  final double ambientVolume;
  final double animalVolume;
  final String narrationStyle;

  ProximityZoneConfig({
    required this.minDistance,
    required this.maxDistance,
    required this.ambientVolume,
    required this.animalVolume,
    required this.narrationStyle,
  });
}

class NarrationScript {
  final String text;
  final String? ssml;
  final String style;
  final int durationSeconds;

  NarrationScript({
    required this.text,
    this.ssml,
    required this.style,
    required this.durationSeconds,
  });
}

class EcosystemSimulation {
  final List<FoodWebNode> foodWeb;
  final List<ChainReaction> chainReactions;
  final List<SymbioticRelation> symbioticRelationships;

  EcosystemSimulation({
    required this.foodWeb,
    required this.chainReactions,
    required this.symbioticRelationships,
  });
}

class FoodWebNode {
  final String id;
  final String name;
  final String level; // producer, primary_consumer, secondary_consumer, apex_predator
  final List<String> dependencies;
  final List<String> dependents;

  FoodWebNode({
    required this.id,
    required this.name,
    required this.level,
    required this.dependencies,
    required this.dependents,
  });
}

class ChainReaction {
  final String triggerSpecies;
  final String triggerEvent;
  final List<ChainEffect> effects;
  final String narration;

  ChainReaction({
    required this.triggerSpecies,
    required this.triggerEvent,
    required this.effects,
    required this.narration,
  });
}

class ChainEffect {
  final String speciesId;
  final String impactType;
  final double severity;
  final String narration;

  ChainEffect({
    required this.speciesId,
    required this.impactType,
    required this.severity,
    required this.narration,
  });
}

class SymbioticRelation {
  final String species1;
  final String species2;
  final String type; // mutualism, commensalism, parasitism
  final String description;
  final String discoveryNarration;

  SymbioticRelation({
    required this.species1,
    required this.species2,
    required this.type,
    required this.description,
    required this.discoveryNarration,
  });
}

class ImmersiveSystems {
  final Map<String, TimeOfDayEffect> timeOfDayEffects;
  final Map<String, WeatherImpact> weatherImpacts;
  final List<Discoverable> discoveries;

  ImmersiveSystems({
    required this.timeOfDayEffects,
    required this.weatherImpacts,
    required this.discoveries,
  });
}

class TimeOfDayEffect {
  final String soundscape;
  final String visualFilter;
  final List<String> activeSpecies;
  final String atmosphereDescription;

  TimeOfDayEffect({
    required this.soundscape,
    required this.visualFilter,
    required this.activeSpecies,
    required this.atmosphereDescription,
  });
}

class WeatherImpact {
  final String soundModifier;
  final double visibilityFactor;
  final String animalBehaviorChange;
  final String narration;

  WeatherImpact({
    required this.soundModifier,
    required this.visibilityFactor,
    required this.animalBehaviorChange,
    required this.narration,
  });
}

class Discoverable {
  final String id;
  final String name;
  final String type;
  final String triggerCondition;
  final String narration;
  final dynamic reward;

  Discoverable({
    required this.id,
    required this.name,
    required this.type,
    required this.triggerCondition,
    required this.narration,
    this.reward,
  });
}
