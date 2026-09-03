import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD FILTER PANEL
// Slide-out panel for toggling hazard layers and setting filters
// ═══════════════════════════════════════════════════════════════

class HazardFilterPanel extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback? onRefresh;

  const HazardFilterPanel({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.onRefresh,
  });

  @override
  State<HazardFilterPanel> createState() => _HazardFilterPanelState();
}

class _HazardFilterPanelState extends State<HazardFilterPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    if (widget.isOpen) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant HazardFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _animationController.forward();
    } else if (!widget.isOpen && oldWidget.isOpen) {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        if (_animationController.isDismissed) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // Scrim
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3 * _fadeAnimation.value),
              ),
            ),

            // Panel
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Transform.translate(
                offset: Offset(320 * _slideAnimation.value, 0),
                child: _buildPanel(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    final vm = context.watch<HazardViewModel>();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: GISTheme.surfaceDark,
        border: Border(
          left: BorderSide(color: GISTheme.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Scrollable content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Quick actions
                _buildQuickActions(vm),
                const SizedBox(height: 12),

                // Hazard layer sections
                for (final type in [
                  HazardType.wildfire,
                  HazardType.flood,
                  HazardType.drought,
                  HazardType.glacier,
                  HazardType.ndvi,
                  HazardType.riskSurface,
                ])
                  _buildHazardSection(context, vm, type),

                const SizedBox(height: 16),

                // Refresh button
                _buildRefreshButton(vm),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: GISTheme.surfaceLight,
        border: Border(
          bottom: BorderSide(color: GISTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.layers, color: GISTheme.accentBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hazard Layers',
              style: GISTheme.headingMedium,
            ),
          ),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                color: GISTheme.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(HazardViewModel vm) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Select All',
            icon: Icons.check_box_outlined,
            onTap: () => vm.setAllLayersVisible(true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            label: 'Clear All',
            icon: Icons.check_box_outline_blank,
            onTap: () => vm.setAllLayersVisible(false),
          ),
        ),
      ],
    );
  }

  Widget _buildHazardSection(
    BuildContext context,
    HazardViewModel vm,
    HazardType type,
  ) {
    final isVisible = vm.layerVisibility[type] ?? false;
    final filter = vm.getFilter(type);
    final count = vm.getFeatureCount(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: GISTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVisible
              ? type.color.withValues(alpha: 0.4)
              : GISTheme.border,
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Icon(type.icon, color: type.color, size: 22),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  type.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: GISTheme.textPrimary,
                  ),
                ),
              ),
              if (count > 0 && isVisible)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: type.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: type.color,
                    ),
                  ),
                ),
            ],
          ),
          trailing: Switch(
            value: isVisible,
            activeThumbColor: type.color,
            activeTrackColor: type.color.withValues(alpha: 0.4),
            onChanged: (_) => vm.toggleLayer(type),
          ),
          children: [
            // Severity filter chips
            _buildSeverityChips(vm, type, filter),
            const SizedBox(height: 10),

            // Opacity slider
            _buildOpacitySlider(vm, type, filter),

            // Date range selector
            _buildDateRangeSelector(context, vm, type, filter),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityChips(
    HazardViewModel vm,
    HazardType type,
    FilterState filter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Min Severity', style: GISTheme.labelSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: Severity.values.map((severity) {
            final isSelected = filter.minSeverity == severity;
            return FilterChip(
              label: Text(
                severity.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isSelected ? Colors.white : GISTheme.textSecondary,
                ),
              ),
              selected: isSelected,
              selectedColor: severity.color.withValues(alpha: 0.7),
              backgroundColor: GISTheme.surfaceHover,
              side: BorderSide(
                color: isSelected ? severity.color : GISTheme.border,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                final newFilter = filter.copyWith(
                  minSeverity: isSelected ? null : severity,
                );
                vm.setFilter(type, newFilter);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOpacitySlider(
    HazardViewModel vm,
    HazardType type,
    FilterState filter,
  ) {
    return Row(
      children: [
        Text('Opacity', style: GISTheme.labelSmall),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: type.color,
              inactiveTrackColor: GISTheme.border,
              thumbColor: type.color,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: filter.opacity,
              min: 0.1,
              max: 1.0,
              onChanged: (value) {
                final newFilter = filter.copyWith(opacity: value);
                vm.setFilter(type, newFilter);
              },
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(filter.opacity * 100).round()}%',
            style: GISTheme.labelSmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeSelector(
    BuildContext context,
    HazardViewModel vm,
    HazardType type,
    FilterState filter,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now(),
            initialDateRange: filter.dateRange,
            builder: (context, child) {
              return Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: type.color,
                    surface: GISTheme.surfaceDark,
                  ),
                ),
                child: child!,
              );
            },
          );

          if (range != null) {
            final newFilter = filter.copyWith(dateRange: range);
            vm.setFilter(type, newFilter);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: GISTheme.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.date_range, size: 14, color: GISTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                filter.dateRange != null
                    ? '${_formatDate(filter.dateRange!.start)} - ${_formatDate(filter.dateRange!.end)}'
                    : 'All dates',
                style: GISTheme.labelSmall,
              ),
              const Spacer(),
              if (filter.dateRange != null)
                InkWell(
                  onTap: () {
                    final newFilter = FilterState(
                      minSeverity: filter.minSeverity,
                      opacity: filter.opacity,
                      visible: filter.visible,
                    );
                    vm.setFilter(type, newFilter);
                  },
                  child: Icon(
                    Icons.clear,
                    size: 14,
                    color: GISTheme.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton(HazardViewModel vm) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: vm.isLoading
            ? null
            : () {
                widget.onRefresh?.call();
              },
        icon: vm.isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 18),
        label: Text(
          vm.isLoading ? 'Refreshing...' : 'Refresh Data',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: GISTheme.accentBlue.withValues(alpha: 0.15),
          foregroundColor: GISTheme.accentBlue,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: GISTheme.accentBlue.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

// ─────────────────────────────────────────────────────────────
// Small action button used in quick-actions row
// ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: GISTheme.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: GISTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: GISTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
