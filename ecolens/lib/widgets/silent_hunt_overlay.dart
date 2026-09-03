import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/services/silent_hunt_service.dart';

/// "The Silent Hunt" - World-first proximity-driven wildlife interaction overlay
///
/// This overlay transforms the AR experience into an immersive wildlife encounter
/// where users must approach virtual species carefully, learning about habitat
/// fragmentation when animals vanish with nowhere to flee.
class SilentHuntOverlay extends StatefulWidget {
  final SilentHuntService huntService;
  final String? activeSpeciesId;
  final VoidCallback? onClose;
  final VoidCallback? onSpeciesTap;

  const SilentHuntOverlay({
    super.key,
    required this.huntService,
    this.activeSpeciesId,
    this.onClose,
    this.onSpeciesTap,
  });

  @override
  State<SilentHuntOverlay> createState() => _SilentHuntOverlayState();
}

class _SilentHuntOverlayState extends State<SilentHuntOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _breathController;
  late Animation<double> _pulseAnim;
  late Animation<double> _breathAnim;

  // Current state
  SpeciesHuntState? _currentState;
  HuntNarration? _activeNarration;
  bool _showLesson = false;
  String? _lessonText;

  @override
  void initState() {
    super.initState();

    // Pulse animation for proximity indicator
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Breathing animation for heartbeat effect
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _breathAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    // Listen to hunt events
    widget.huntService.events.listen(_handleHuntEvent);

    // Get initial state
    if (widget.activeSpeciesId != null) {
      _currentState = widget.huntService.getState(widget.activeSpeciesId!);
    }
  }

  void _handleHuntEvent(SilentHuntEvent event) {
    if (!mounted) return;

    if (event is SilentHuntZoneChanged) {
      setState(() {
        _currentState = widget.huntService.getState(event.speciesId);
      });

      // Start heartbeat if in intimate/connection zone
      if (event.newZone == ProximityZone.intimate ||
          event.newZone == ProximityZone.connection) {
        _breathController.repeat(reverse: true);
      } else {
        _breathController.stop();
        _breathController.reset();
      }
    } else if (event is SilentHuntSpeciesVanished) {
      _showVanishSequence(event.speciesId, event.reason);
    } else if (event is SilentHuntSpeciesFled) {
      _showFleeSequence(event.speciesId);
    } else if (event is SilentHuntConnectionAchieved) {
      _showConnectionCelebration(event.speciesId);
    }
  }

  void _showVanishSequence(String speciesId, String reason) {
    HapticFeedback.heavyImpact();

    setState(() {
      _currentState = widget.huntService.getState(speciesId);
      _showLesson = true;
      _lessonText = "When habitat shrinks below critical thresholds, there's nowhere left to go. This is extinction in real-time.";
    });

    // Auto-hide lesson after delay
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _showLesson = false);
      }
    });
  }

  void _showFleeSequence(String speciesId) {
    HapticFeedback.mediumImpact();

    setState(() {
      _currentState = widget.huntService.getState(speciesId);
    });
  }

  void _showConnectionCelebration(String speciesId) {
    HapticFeedback.heavyImpact();

    setState(() {
      _activeNarration = HuntNarration(
        text: "Connection achieved. You've experienced what we're fighting to protect.",
        style: NarrationStyle.emotional,
        duration: const Duration(seconds: 5),
      );
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _activeNarration = null);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentState == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Proximity indicator (top right)
        _buildProximityIndicator(),

        // Audio visualization (bottom left)
        _buildAudioVisualization(),

        // Narration overlay (center bottom)
        if (_activeNarration != null && !_activeNarration!.isEmpty)
          _buildNarrationOverlay(),

        // Lesson overlay (full screen for vanish)
        if (_showLesson) _buildLessonOverlay(),

        // Species approach hint
        _buildApproachHint(),

        // Vanished/Fled state overlay
        if (_currentState!.hasVanished) _buildVanishedOverlay(),
        if (_currentState!.hasFled && !_currentState!.hasVanished)
          _buildFledOverlay(),
      ],
    );
  }

  Widget _buildProximityIndicator() {
    final zone = _currentState!.currentZone;
    final color = _getZoneColor(zone);
    final label = _getZoneLabel(zone);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 120,
      right: 16,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3 * _pulseAnim.value),
                blurRadius: 20 * _pulseAnim.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Species icon with pulse
              Transform.scale(
                scale: zone == ProximityZone.connection ? _breathAnim.value : 1.0,
                child: Icon(
                  Icons.pets,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),

              // Zone indicator dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: ProximityZone.values.map((z) {
                  final isActive = z.index <= zone.index;
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? color : Colors.white24,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Zone label
              Text(
                label,
                style: GoogleFonts.orbitron(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),

              // Alert level
              const SizedBox(height: 4),
              Container(
                width: 50,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _currentState!.alertLevel,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getAlertColor(_currentState!.alertLevel),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioVisualization() {
    final ambientVol = widget.huntService.ambientVolume;
    final animalVol = widget.huntService.animalVolume;

    return Positioned(
      bottom: 100,
      left: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AUDIO',
              style: GoogleFonts.orbitron(
                color: Colors.white38,
                fontSize: 8,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),

            // Forest ambient bar
            _buildAudioBar('Forest', ambientVol, EcoTheme.neonEmerald),
            const SizedBox(height: 6),

            // Animal sound bar
            _buildAudioBar('Animal', animalVol, EcoTheme.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioBar(String label, double level, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ),
        Container(
          width: 60,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: level.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrationOverlay() {
    final style = _activeNarration!.style;
    final color = _getNarrationColor(style);

    return Positioned(
      bottom: 180,
      left: 40,
      right: 40,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getNarrationIcon(style),
                color: color,
                size: 24,
              ),
              const SizedBox(height: 12),
              Text(
                _activeNarration!.text,
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: style == NarrationStyle.whisper ? 13 : 15,
                  fontStyle: style == NarrationStyle.whisper
                      ? FontStyle.italic
                      : FontStyle.normal,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApproachHint() {
    if (_currentState!.hasFled || _currentState!.hasVanished) {
      return const SizedBox.shrink();
    }

    final zone = _currentState!.currentZone;
    String hint;
    IconData icon;

    switch (zone) {
      case ProximityZone.distant:
        hint = 'Move closer slowly...';
        icon = Icons.directions_walk;
        break;
      case ProximityZone.aware:
        hint = 'It senses you. Be still.';
        icon = Icons.visibility;
        break;
      case ProximityZone.close:
        hint = 'Gentle movements only.';
        icon = Icons.pan_tool;
        break;
      case ProximityZone.intimate:
        hint = 'Almost there...';
        icon = Icons.favorite_border;
        break;
      case ProximityZone.connection:
        hint = 'Connected.';
        icon = Icons.favorite;
        break;
    }

    return Positioned(
      bottom: 140,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text(
                hint,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVanishedOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.9),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ghost icon animation
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: 0.0),
                  duration: const Duration(seconds: 3),
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 1 + (1 - value) * 0.5,
                      child: Icon(
                        Icons.pets,
                        size: 80,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'VANISHED',
                  style: GoogleFonts.orbitron(
                    color: EcoTheme.hazardRed,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'No habitat remaining.',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nowhere to flee.',
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 40),

                // Lesson container
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: EcoTheme.hazardRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EcoTheme.hazardRed.withOpacity(0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.school, color: EcoTheme.hazardRed, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'THE LESSON',
                            style: GoogleFonts.orbitron(
                              color: EcoTheme.hazardRed,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This is what habitat fragmentation looks like. When forests are reduced below critical thresholds, wildlife has nowhere left to escape. This is extinction in real-time.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                ElevatedButton.icon(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.replay),
                  label: const Text('TRY AGAIN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EcoTheme.neonEmerald,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFledOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 180,
      left: 40,
      right: 40,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EcoTheme.amber.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_run,
              color: EcoTheme.amber,
              size: 36,
            ),
            const SizedBox(height: 12),

            Text(
              'It fled.',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'In the wild, they have endless forest to disappear into.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EcoTheme.neonEmerald.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.eco, color: EcoTheme.neonEmerald, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connectivity is survival.',
                      style: TextStyle(
                        color: EcoTheme.neonEmerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Try Again'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _showLesson ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: EcoTheme.hazardRed.withOpacity(0.5), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: EcoTheme.hazardRed,
                    size: 48,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'HABITAT FRAGMENTATION',
                    style: GoogleFonts.orbitron(
                      color: EcoTheme.hazardRed,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _lessonText ?? '',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app, color: Colors.white38, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Tap anywhere to continue',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods
  Color _getZoneColor(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return Colors.grey;
      case ProximityZone.aware:
        return Colors.blue;
      case ProximityZone.close:
        return EcoTheme.amber;
      case ProximityZone.intimate:
        return Colors.orange;
      case ProximityZone.connection:
        return EcoTheme.neonEmerald;
    }
  }

  String _getZoneLabel(ProximityZone zone) {
    switch (zone) {
      case ProximityZone.distant:
        return 'DISTANT';
      case ProximityZone.aware:
        return 'AWARE';
      case ProximityZone.close:
        return 'CLOSE';
      case ProximityZone.intimate:
        return 'INTIMATE';
      case ProximityZone.connection:
        return 'CONNECTED';
    }
  }

  Color _getAlertColor(double level) {
    if (level > 0.7) return EcoTheme.hazardRed;
    if (level > 0.4) return EcoTheme.amber;
    return EcoTheme.neonEmerald;
  }

  Color _getNarrationColor(NarrationStyle style) {
    switch (style) {
      case NarrationStyle.whisper:
        return Colors.white70;
      case NarrationStyle.reverent:
        return EcoTheme.amber;
      case NarrationStyle.emotional:
        return EcoTheme.neonEmerald;
      case NarrationStyle.measured:
        return Colors.blue;
      case NarrationStyle.grave:
        return EcoTheme.hazardRed;
    }
  }

  IconData _getNarrationIcon(NarrationStyle style) {
    switch (style) {
      case NarrationStyle.whisper:
        return Icons.volume_down;
      case NarrationStyle.reverent:
        return Icons.auto_awesome;
      case NarrationStyle.emotional:
        return Icons.favorite;
      case NarrationStyle.measured:
        return Icons.info_outline;
      case NarrationStyle.grave:
        return Icons.warning;
    }
  }
}

/// Species selection panel for Silent Hunt mode
class SilentHuntSpeciesPanel extends StatelessWidget {
  final List<HuntableSpecies> species;
  final String? selectedSpeciesId;
  final Function(HuntableSpecies) onSpeciesSelected;
  final VoidCallback onClose;

  const SilentHuntSpeciesPanel({
    super.key,
    required this.species,
    required this.onSpeciesSelected,
    required this.onClose,
    this.selectedSpeciesId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 70,
        left: 16,
        right: 16,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EcoTheme.amber.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.pets, color: EcoTheme.amber, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THE SILENT HUNT',
                      style: GoogleFonts.orbitron(
                        color: EcoTheme.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Choose a species to approach',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: onClose,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white38, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Move slowly. Make no sudden movements. If the habitat is fragmented, animals have nowhere to flee...',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Species list
          ...species.map((s) => _buildSpeciesCard(s)),
        ],
      ),
    );
  }

  Widget _buildSpeciesCard(HuntableSpecies species) {
    final isSelected = species.id == selectedSpeciesId;
    final difficultyColor = _getDifficultyColor(species);

    return GestureDetector(
      onTap: () => onSpeciesSelected(species),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? EcoTheme.amber.withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? EcoTheme.amber : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Species icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EcoTheme.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getSpeciesIcon(species.category),
                color: EcoTheme.amber,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // Species info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    species.name,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (species.scientificName.isNotEmpty)
                    Text(
                      species.scientificName,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildStatusBadge(species.conservationStatus),
                      const SizedBox(width: 8),
                      _buildDifficultyIndicator(species, difficultyColor),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow
            Icon(
              Icons.chevron_right,
              color: isSelected ? EcoTheme.amber : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    if (status.toLowerCase().contains('endangered')) {
      color = EcoTheme.hazardRed;
    } else if (status.toLowerCase().contains('vulnerable')) {
      color = Colors.orange;
    } else {
      color = EcoTheme.amber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDifficultyIndicator(HuntableSpecies species, Color color) {
    final difficulty = _calculateDifficulty(species);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Difficulty: ',
          style: TextStyle(color: Colors.white38, fontSize: 9),
        ),
        ...List.generate(5, (i) => Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < difficulty ? color : Colors.white12,
          ),
        )),
      ],
    );
  }

  int _calculateDifficulty(HuntableSpecies species) {
    // Based on sensitivity and low curiosity
    final avgSensitivity = (species.speedSensitivity + species.noiseSensitivity) / 2;
    final curiosityBonus = (1 - species.curiosityFactor) * 0.5;
    final difficulty = ((avgSensitivity + curiosityBonus) * 5).round();
    return difficulty.clamp(1, 5);
  }

  Color _getDifficultyColor(HuntableSpecies species) {
    final difficulty = _calculateDifficulty(species);
    if (difficulty >= 4) return EcoTheme.hazardRed;
    if (difficulty >= 3) return Colors.orange;
    return EcoTheme.neonEmerald;
  }

  IconData _getSpeciesIcon(String category) {
    switch (category.toLowerCase()) {
      case 'apex_predator':
        return Icons.pets;
      case 'bird':
        return Icons.flutter_dash;
      case 'arboreal':
        return Icons.nature;
      case 'primate':
        return Icons.face;
      case 'amphibian':
        return Icons.water;
      default:
        return Icons.pets;
    }
  }
}

/// Floating button to activate Silent Hunt mode
class SilentHuntActivator extends StatelessWidget {
  final VoidCallback onActivate;
  final bool isActive;

  const SilentHuntActivator({
    super.key,
    required this.onActivate,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onActivate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? EcoTheme.amber
              : Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: EcoTheme.amber,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: EcoTheme.amber.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets,
              color: isActive ? Colors.black : EcoTheme.amber,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'SILENT HUNT',
              style: GoogleFonts.orbitron(
                color: isActive ? Colors.black : EcoTheme.amber,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
