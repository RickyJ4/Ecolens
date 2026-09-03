import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';
import 'package:ecolens/widgets/data_freshness_indicator.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD CHIP BAR
// Horizontal scrollable chip bar for toggling hazard layers
// Sits on top of the map — primary filter interface on all platforms
// ═══════════════════════════════════════════════════════════════

/// Official hazard colors based on research standards.
class HazardColors {
  static const Color wildfire = Color(0xFFFF4500); // NIFC OrangeRed
  static const Color flood = Color(0xFF1E90FF); // NWS DodgerBlue
  static const Color drought = Color(0xFFCC8400); // USDM D2 Golden
  static const Color glacier = Color(0xFF87CEEB); // SkyBlue
  static const Color ndvi = Color(0xFF228B22); // ForestGreen
  static const Color watershed = Color(0xFF4169E1); // RoyalBlue
  static const Color risk = Color(0xFFDC143C); // Crimson

  static Color forType(HazardType type) {
    switch (type) {
      case HazardType.wildfire:
        return wildfire;
      case HazardType.flood:
        return flood;
      case HazardType.drought:
        return drought;
      case HazardType.glacier:
        return glacier;
      case HazardType.ndvi:
        return ndvi;
      case HazardType.watershed:
        return watershed;
      case HazardType.riskSurface:
        return risk;
    }
  }
}

class HazardChipBar extends StatelessWidget {
  /// Called when the leading "Layers" button is tapped to open the full filter panel.
  final VoidCallback onOpenFilterPanel;

  /// Called when a chip is long-pressed to show detailed filter for that hazard.
  final void Function(HazardType type)? onFilterDetails;

  const HazardChipBar({
    super.key,
    required this.onOpenFilterPanel,
    this.onFilterDetails,
  });

  /// Platform-adaptive chip height: slightly taller on iOS for Cupertino feel.
  double get _chipHeight {
    if (kIsWeb) return 32.0;
    try {
      if (Platform.isIOS) return 34.0;
    } catch (_) {
      // Platform not available (web fallback already handled above).
    }
    return 32.0;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: GISTheme.backgroundDark.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: GISTheme.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            height: _chipHeight + 8, // chip + vertical breathing room
            child: Row(
              children: [
                // Leading "Layers" icon button
                _LayersButton(onTap: onOpenFilterPanel),

                // Divider
                Container(
                  width: 1,
                  height: _chipHeight - 4,
                  color: GISTheme.border.withValues(alpha: 0.5),
                ),

                // Scrollable chip list
                Expanded(
                  child: _ChipList(
                    chipHeight: _chipHeight,
                    onFilterDetails: onFilterDetails,
                  ),
                ),

                // Divider
                Container(
                  width: 1,
                  height: _chipHeight - 4,
                  color: GISTheme.border.withValues(alpha: 0.5),
                ),

                // Freshness indicator on the right
                Padding(
                  padding: const EdgeInsets.only(right: 12, left: 8),
                  child: DataFreshnessIndicator(compact: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Layers icon button
// ─────────────────────────────────────────────────────────────

class _LayersButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LayersButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: 'Open layer panel',
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: GISTheme.surfaceHover.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.layers,
              color: GISTheme.accentBlue,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Scrollable chip list
// ─────────────────────────────────────────────────────────────

class _ChipList extends StatelessWidget {
  final double chipHeight;
  final void Function(HazardType type)? onFilterDetails;

  const _ChipList({
    required this.chipHeight,
    this.onFilterDetails,
  });

  static const List<HazardType> _orderedTypes = [
    HazardType.wildfire,
    HazardType.flood,
    HazardType.drought,
    HazardType.glacier,
    HazardType.ndvi,
    HazardType.watershed,
    HazardType.riskSurface,
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HazardViewModel>();

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16, right: 16),
      itemCount: _orderedTypes.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final type = _orderedTypes[index];
        final isActive = vm.layerVisibility[type] ?? false;
        final count = vm.getFeatureCount(type);

        return _HazardChip(
          type: type,
          isActive: isActive,
          count: count,
          chipHeight: chipHeight,
          onTap: () => vm.toggleLayer(type),
          onLongPress: onFilterDetails != null
              ? () => onFilterDetails!(type)
              : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual hazard chip with selection animation
// ─────────────────────────────────────────────────────────────

class _HazardChip extends StatefulWidget {
  final HazardType type;
  final bool isActive;
  final int count;
  final double chipHeight;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HazardChip({
    required this.type,
    required this.isActive,
    required this.count,
    required this.chipHeight,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_HazardChip> createState() => _HazardChipState();
}

class _HazardChipState extends State<_HazardChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _colorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _HazardChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hazardColor = HazardColors.forType(widget.type);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _colorAnimation.value;

        final bgColor = Color.lerp(
          GISTheme.surfaceHover.withValues(alpha: 0.5),
          hazardColor.withValues(alpha: 0.85),
          t,
        )!;

        final borderColor = Color.lerp(
          GISTheme.border,
          hazardColor,
          t,
        )!;

        final textColor = Color.lerp(
          GISTheme.textSecondary,
          Colors.white,
          t,
        )!;

        final iconColor = Color.lerp(
          hazardColor.withValues(alpha: 0.7),
          Colors.white,
          t,
        )!;

        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: widget.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Leading icon
                  Icon(widget.type.icon, size: 16, color: iconColor),
                  const SizedBox(width: 6),

                  // Label
                  Text(
                    widget.type.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w400,
                      color: textColor,
                    ),
                  ),

                  // Badge count (only when > 0)
                  if (widget.count > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(
                      count: widget.count,
                      color: widget.isActive ? Colors.white : hazardColor,
                      bgColor: widget.isActive
                          ? Colors.white.withValues(alpha: 0.2)
                          : hazardColor.withValues(alpha: 0.15),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Count badge
// ─────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final Color bgColor;

  const _CountBadge({
    required this.count,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
