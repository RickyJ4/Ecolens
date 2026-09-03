import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';

// ═══════════════════════════════════════════════════════════════
// DATA FRESHNESS INDICATOR
// Shows when data was last refreshed + auto-refresh controls
// ═══════════════════════════════════════════════════════════════

class DataFreshnessIndicator extends StatefulWidget {
  /// If true, renders a minimal layout suitable for embedding in the chip bar.
  final bool compact;

  /// Called when the user taps to trigger a manual refresh.
  final VoidCallback? onManualRefresh;

  const DataFreshnessIndicator({
    super.key,
    this.compact = false,
    this.onManualRefresh,
  });

  @override
  State<DataFreshnessIndicator> createState() =>
      _DataFreshnessIndicatorState();
}

class _DataFreshnessIndicatorState extends State<DataFreshnessIndicator>
    with SingleTickerProviderStateMixin {
  Timer? _updateTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the dot when auto-refresh is active
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Tick every 30 seconds to update the "X min ago" label
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    final vm = context.read<HazardViewModel>();
    if (vm.isAutoRefreshActive) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Freshness logic
  // ─────────────────────────────────────────────────────────────

  _FreshnessInfo _computeFreshness(DateTime? lastRefresh) {
    if (lastRefresh == null) {
      return _FreshnessInfo(
        label: 'No data',
        dotColor: GISTheme.textTertiary,
        tooltip: 'Data has not been loaded yet',
      );
    }

    final elapsed = DateTime.now().difference(lastRefresh);
    final minutes = elapsed.inMinutes;

    if (minutes < 1) {
      return _FreshnessInfo(
        label: 'just now',
        dotColor: const Color(0xFF56D364),
        tooltip: 'Updated ${_formatTime(lastRefresh)}',
      );
    }
    if (minutes < 5) {
      return _FreshnessInfo(
        label: '$minutes min ago',
        dotColor: const Color(0xFF56D364),
        tooltip: 'Updated ${_formatTime(lastRefresh)}',
      );
    }
    if (minutes < 15) {
      return _FreshnessInfo(
        label: '$minutes min ago',
        dotColor: const Color(0xFFD29922),
        tooltip: 'Updated ${_formatTime(lastRefresh)}',
      );
    }
    if (minutes < 30) {
      return _FreshnessInfo(
        label: '$minutes min ago',
        dotColor: const Color(0xFFDB6D28),
        tooltip: 'Updated ${_formatTime(lastRefresh)}',
      );
    }

    return _FreshnessInfo(
      label: 'over 30 min ago',
      dotColor: const Color(0xFFDA3633),
      tooltip: 'Updated ${_formatTime(lastRefresh)}',
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HazardViewModel>();
    final info = _computeFreshness(vm.lastRefresh);

    // Keep pulse in sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (vm.isAutoRefreshActive && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      } else if (!vm.isAutoRefreshActive && _pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    });

    return Tooltip(
      message: info.tooltip,
      child: GestureDetector(
        onTap: () {
          widget.onManualRefresh?.call();
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          if (vm.isAutoRefreshActive) {
            vm.stopAutoRefresh();
          } else {
            vm.startAutoRefresh();
          }
          if (mounted) setState(() {});
        },
        child: widget.compact ? _buildCompact(vm, info) : _buildFull(vm, info),
      ),
    );
  }

  Widget _buildCompact(HazardViewModel vm, _FreshnessInfo info) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulsingDot(
          color: info.dotColor,
          animation: _pulseAnimation,
          isAnimating: vm.isAutoRefreshActive,
          size: 8,
        ),
        const SizedBox(width: 5),
        Text(
          info.label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: GISTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildFull(HazardViewModel vm, _FreshnessInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: GISTheme.surfaceLight.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GISTheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(
            color: info.dotColor,
            animation: _pulseAnimation,
            isAnimating: vm.isAutoRefreshActive,
            size: 10,
          ),
          const SizedBox(width: 6),
          Text(
            'Updated ${info.label}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: GISTheme.textSecondary,
            ),
          ),
          if (vm.isAutoRefreshActive) ...[
            const SizedBox(width: 4),
            Icon(Icons.sync, size: 12, color: GISTheme.textTertiary),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pulsing dot
// ─────────────────────────────────────────────────────────────

class _PulsingDot extends StatelessWidget {
  final Color color;
  final Animation<double> animation;
  final bool isAnimating;
  final double size;

  const _PulsingDot({
    required this.color,
    required this.animation,
    required this.isAnimating,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAnimating) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: animation.value),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4 * animation.value),
                blurRadius: size * animation.value,
                spreadRadius: size * 0.2 * animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Internal freshness data holder
// ─────────────────────────────────────────────────────────────

class _FreshnessInfo {
  final String label;
  final Color dotColor;
  final String tooltip;

  const _FreshnessInfo({
    required this.label,
    required this.dotColor,
    required this.tooltip,
  });
}
