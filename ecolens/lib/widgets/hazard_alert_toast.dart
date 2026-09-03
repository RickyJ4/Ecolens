import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/widgets/hazard_chip_bar.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD ALERT TOAST
// Animated slide-down toast for new hazard alerts
// Uses OverlayEntry so it floats above all other widgets
// ═══════════════════════════════════════════════════════════════

/// Data class describing a single alert to be shown as a toast.
class HazardAlert {
  final String id;
  final HazardType type;
  final Severity severity;
  final String message;
  final String locationName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const HazardAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

/// Controller that manages a queue of hazard alert toasts shown via
/// [OverlayEntry]. Attach it to a [NavigatorState] or use the static
/// helper [HazardAlertToastController.of] with a BuildContext.
///
/// Usage:
/// ```dart
/// final controller = HazardAlertToastController(overlayState: Overlay.of(context));
/// controller.showAlert(alert, onFlyTo: (lat, lng) { ... });
/// ```
class HazardAlertToastController {
  final OverlayState overlayState;

  HazardAlertToastController({required this.overlayState});

  final Queue<_QueuedAlert> _queue = Queue();
  bool _isShowing = false;

  /// Enqueue an alert. If nothing is currently showing it will appear
  /// immediately; otherwise it waits its turn.
  void showAlert(
    HazardAlert alert, {
    required void Function(double lat, double lng) onFlyTo,
  }) {
    _queue.add(_QueuedAlert(alert: alert, onFlyTo: onFlyTo));
    _processQueue();
  }

  void _processQueue() {
    if (_isShowing || _queue.isEmpty) return;
    _isShowing = true;

    final queued = _queue.removeFirst();
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _HazardAlertToastOverlay(
        alert: queued.alert,
        onDismissed: () {
          entry.remove();
          _isShowing = false;
          _processQueue();
        },
        onTap: () {
          queued.onFlyTo(queued.alert.latitude, queued.alert.longitude);
          entry.remove();
          _isShowing = false;
          _processQueue();
        },
      ),
    );

    overlayState.insert(entry);
  }

  /// Remove all pending alerts.
  void clearQueue() {
    _queue.clear();
  }
}

class _QueuedAlert {
  final HazardAlert alert;
  final void Function(double lat, double lng) onFlyTo;
  const _QueuedAlert({required this.alert, required this.onFlyTo});
}

// ─────────────────────────────────────────────────────────────
// Toast overlay widget (the actual animated card)
// ─────────────────────────────────────────────────────────────

class _HazardAlertToastOverlay extends StatefulWidget {
  final HazardAlert alert;
  final VoidCallback onDismissed;
  final VoidCallback onTap;

  const _HazardAlertToastOverlay({
    required this.alert,
    required this.onDismissed,
    required this.onTap,
  });

  @override
  State<_HazardAlertToastOverlay> createState() =>
      _HazardAlertToastOverlayState();
}

class _HazardAlertToastOverlayState extends State<_HazardAlertToastOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Pulsing border for extreme severity
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    // Slide animation
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeIn),
    );

    // Pulse for extreme
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.alert.severity == Severity.extreme) {
      _pulseController.repeat(reverse: true);
    }

    // Haptic feedback
    _triggerHaptic();

    // Slide in
    _slideController.forward();

    // Auto-dismiss after 5 seconds
    _autoDismissTimer = Timer(const Duration(seconds: 5), _dismiss);
  }

  void _triggerHaptic() {
    switch (widget.alert.severity) {
      case Severity.extreme:
        HapticFeedback.heavyImpact();
        break;
      case Severity.high:
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.lightImpact();
        break;
    }
  }

  Future<void> _dismiss() async {
    _autoDismissTimer?.cancel();
    await _slideController.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _severityBorderColor(Severity severity) {
    switch (severity) {
      case Severity.low:
        return const Color(0xFFD29922); // Yellow
      case Severity.moderate:
        return const Color(0xFFDB6D28); // Orange
      case Severity.high:
        return const Color(0xFFDA3633); // Red
      case Severity.extreme:
        return const Color(0xFF8B0000); // Dark red
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final alert = widget.alert;
    final borderColor = _severityBorderColor(alert.severity);

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragEnd: (details) {
              // Swipe up to dismiss
              if (details.velocity.pixelsPerSecond.dy < -100) {
                _dismiss();
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final borderAlpha = alert.severity == Severity.extreme
                        ? _pulseAnimation.value
                        : 1.0;

                    return Container(
                      constraints: const BoxConstraints(maxHeight: 80),
                      decoration: BoxDecoration(
                        color: GISTheme.backgroundDark.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor.withValues(alpha: borderAlpha * 0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Severity color bar on left
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 5,
                            decoration: BoxDecoration(
                              color: borderColor.withValues(alpha: borderAlpha),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                          ),

                          // Content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // Hazard icon
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: HazardColors.forType(alert.type)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      alert.type.icon,
                                      size: 20,
                                      color: HazardColors.forType(alert.type),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Message + location
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          alert.message,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: GISTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 11,
                                              color: GISTheme.textTertiary,
                                            ),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(
                                                alert.locationName,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  color:
                                                      GISTheme.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Dismiss hint
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.keyboard_arrow_up,
                                    size: 16,
                                    color:
                                        GISTheme.textTertiary.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
