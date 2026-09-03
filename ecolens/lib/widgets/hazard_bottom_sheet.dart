import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';

// ═══════════════════════════════════════════════════════════════
// HAZARD BOTTOM SHEET
// DraggableScrollableSheet-based filter panel for mobile
// 3 snap points: peek (0.12), half (0.45), full (0.85)
// ═══════════════════════════════════════════════════════════════

class HazardBottomSheet extends StatefulWidget {
  /// Called when the user taps "Refresh" inside the sheet.
  final VoidCallback? onRefresh;

  const HazardBottomSheet({super.key, this.onRefresh});

  @override
  State<HazardBottomSheet> createState() => _HazardBottomSheetState();
}

class _HazardBottomSheetState extends State<HazardBottomSheet> {
  static const double _peekExtent = 0.12;
  static const double _halfExtent = 0.45;
  static const double _fullExtent = 0.85;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  _SheetLevel _level = _SheetLevel.peek;

  // Track which per-hazard section is expanded (full level only).
  final Set<HazardType> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetChanged);
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _onSheetChanged() {
    if (!_sheetController.isAttached) return;
    final extent = _sheetController.size;

    final newLevel = _levelForExtent(extent);
    if (newLevel != _level) {
      HapticFeedback.selectionClick();
      setState(() => _level = newLevel);
    }
  }

  _SheetLevel _levelForExtent(double extent) {
    if (extent < (_peekExtent + _halfExtent) / 2) return _SheetLevel.peek;
    if (extent < (_halfExtent + _fullExtent) / 2) return _SheetLevel.half;
    return _SheetLevel.full;
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  int _activeLayerCount(HazardViewModel vm) {
    return vm.layerVisibility.values.where((v) => v).length;
  }

  List<HazardType> _activeLayers(HazardViewModel vm) {
    return vm.layerVisibility.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
  }

  String _freshnessLabel(DateTime? lastRefresh) {
    if (lastRefresh == null) return 'No data';
    final diff = DateTime.now().difference(lastRefresh);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${diff.inHours}h ago';
  }

  String _dataSourceForType(HazardType type) {
    switch (type) {
      case HazardType.wildfire:
        return 'NASA FIRMS';
      case HazardType.flood:
        return 'NWS AHPS';
      case HazardType.drought:
        return 'USDM';
      case HazardType.glacier:
        return 'GLIMS / RGI';
      case HazardType.ndvi:
        return 'MODIS / Sentinel-2';
      case HazardType.watershed:
        return 'USGS NHD';
      case HazardType.riskSurface:
        return 'Multi-source composite';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _peekExtent,
      minChildSize: _peekExtent,
      maxChildSize: _fullExtent,
      snap: true,
      snapSizes: const [_peekExtent, _halfExtent, _fullExtent],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: GISTheme.backgroundDark.withValues(alpha: 0.88),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: GISTheme.border.withValues(alpha: 0.6),
                    width: 1,
                  ),
                  left: BorderSide(
                    color: GISTheme.border.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  right: BorderSide(
                    color: GISTheme.border.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Consumer<HazardViewModel>(
                builder: (context, vm, _) {
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Drag handle
                      SliverToBoxAdapter(child: _buildDragHandle()),

                      // Peek content: always visible
                      SliverToBoxAdapter(child: _buildPeekContent(vm)),

                      // Half + Full content
                      if (_level != _SheetLevel.peek) ...[
                        SliverToBoxAdapter(child: const SizedBox(height: 12)),
                        SliverToBoxAdapter(child: _buildHazardGrid(vm)),
                        SliverToBoxAdapter(child: const SizedBox(height: 16)),
                        SliverToBoxAdapter(child: _buildActiveAlerts(vm)),
                      ],

                      // Full-only content
                      if (_level == _SheetLevel.full) ...[
                        SliverToBoxAdapter(child: const SizedBox(height: 16)),
                        SliverToBoxAdapter(
                            child: _buildPerHazardFilters(vm)),
                        SliverToBoxAdapter(child: const SizedBox(height: 16)),
                        SliverToBoxAdapter(child: _buildLegendSection(vm)),
                        SliverToBoxAdapter(child: const SizedBox(height: 16)),
                        SliverToBoxAdapter(
                            child: _buildAutoRefreshSection(vm)),
                        SliverToBoxAdapter(child: const SizedBox(height: 16)),
                        SliverToBoxAdapter(
                            child: _buildDataSourcesSection()),
                        SliverToBoxAdapter(child: const SizedBox(height: 40)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DRAG HANDLE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDragHandle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: GISTheme.textTertiary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PEEK CONTENT
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPeekContent(HazardViewModel vm) {
    final count = _activeLayerCount(vm);
    final active = _activeLayers(vm);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '$count active layer${count == 1 ? '' : 's'}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: GISTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          // Colored dots for each active hazard
          ...active.take(5).map((type) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: type.color,
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              )),
          if (active.length > 5)
            Text(
              '+${active.length - 5}',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: GISTheme.textTertiary,
              ),
            ),
          const Spacer(),
          Text(
            _freshnessLabel(vm.lastRefresh),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: GISTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HAZARD TOGGLE GRID (half level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildHazardGrid(HazardViewModel vm) {
    final types = HazardType.values;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HAZARD LAYERS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GISTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: types.length,
            itemBuilder: (context, index) {
              final type = types[index];
              final isActive = vm.layerVisibility[type] ?? false;
              final count = vm.getFeatureCount(type);

              return _HazardToggleCard(
                type: type,
                isActive: isActive,
                featureCount: count,
                onToggle: () => vm.toggleLayer(type),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIVE ALERTS (half level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActiveAlerts(HazardViewModel vm) {
    // Collect all hazard features across active layers
    final alerts = <HazardFeature>[];
    for (final type in HazardType.values) {
      if (vm.layerVisibility[type] != true) continue;
      final data = vm.hazardData[type] ?? [];
      for (final item in data) {
        if (item is HazardFeature &&
            (item.severity == Severity.high ||
                item.severity == Severity.extreme)) {
          alerts.add(item);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: GISTheme.accentOrange),
              const SizedBox(width: 6),
              Text(
                'ACTIVE ALERTS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: GISTheme.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${alerts.length} alert${alerts.length == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: GISTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GISTheme.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GISTheme.border.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  'No high-severity alerts in view',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: GISTheme.textTertiary,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: alerts.length.clamp(0, 10),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  return _AlertCard(alert: alert);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PER-HAZARD EXPANDABLE FILTERS (full level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPerHazardFilters(HazardViewModel vm) {
    final activeTypes = vm.layerVisibility.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAYER SETTINGS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GISTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (activeTypes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Enable layers above to configure settings',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: GISTheme.textTertiary,
                ),
              ),
            )
          else
            ...activeTypes.map((type) => _buildHazardExpansionTile(vm, type)),
        ],
      ),
    );
  }

  Widget _buildHazardExpansionTile(HazardViewModel vm, HazardType type) {
    final isExpanded = _expandedSections.contains(type);
    final filter = vm.getFilter(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: GISTheme.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpanded
              ? type.color.withValues(alpha: 0.4)
              : GISTheme.border.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isExpanded) {
                  _expandedSections.remove(type);
                } else {
                  _expandedSections.add(type);
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(type.icon, size: 18, color: type.color),
                  const SizedBox(width: 8),
                  Text(
                    type.label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GISTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: type.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _dataSourceForType(type),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: type.color.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: GISTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded body
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildFilterBody(vm, type, filter),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBody(
      HazardViewModel vm, HazardType type, FilterState filter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: GISTheme.border, height: 1),
          const SizedBox(height: 10),

          // Severity filter chips
          Text(
            'Min severity',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: GISTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: Severity.values.map((severity) {
              final isSelected = filter.minSeverity == severity;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  final newFilter = filter.copyWith(
                    minSeverity: isSelected ? null : severity,
                  );
                  vm.setFilter(type, newFilter);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? severity.color.withValues(alpha: 0.2)
                        : GISTheme.surfaceDark.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? severity.color.withValues(alpha: 0.6)
                          : GISTheme.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    severity.label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? severity.color
                          : GISTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Opacity slider
          Row(
            children: [
              Text(
                'Opacity',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: GISTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(filter.opacity * 100).round()}%',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GISTheme.textPrimary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: type.color,
              inactiveTrackColor: GISTheme.surfaceDark,
              thumbColor: type.color,
              overlayColor: type.color.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: filter.opacity,
              onChanged: (v) {
                final newFilter = filter.copyWith(opacity: v);
                vm.setFilter(type, newFilter);
              },
            ),
          ),

          const SizedBox(height: 6),

          // Date range selector
          InkWell(
            onTap: () => _selectDateRange(context, vm, type, filter),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: GISTheme.surfaceDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: GISTheme.border.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.date_range,
                      size: 14, color: GISTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filter.dateRange != null
                          ? '${_formatDate(filter.dateRange!.start)} - ${_formatDate(filter.dateRange!.end)}'
                          : 'All time (tap to set range)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: filter.dateRange != null
                            ? GISTheme.textPrimary
                            : GISTheme.textTertiary,
                      ),
                    ),
                  ),
                  if (filter.dateRange != null)
                    GestureDetector(
                      onTap: () {
                        vm.setFilter(
                          type,
                          FilterState(
                            minSeverity: filter.minSeverity,
                            opacity: filter.opacity,
                            visible: filter.visible,
                          ),
                        );
                      },
                      child: Icon(Icons.close,
                          size: 14, color: GISTheme.textTertiary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange(BuildContext context, HazardViewModel vm,
      HazardType type, FilterState filter) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: filter.dateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: type.color,
              onPrimary: Colors.white,
              surface: GISTheme.surfaceDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      vm.setFilter(type, filter.copyWith(dateRange: picked));
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  // ═══════════════════════════════════════════════════════════════
  // LEGEND SECTION (full level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLegendSection(HazardViewModel vm) {
    final active = _activeLayers(vm);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEGEND',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GISTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GISTheme.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: GISTheme.border.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                // Active layer legend items
                ...active.map((type) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 4,
                            decoration: BoxDecoration(
                              color: type.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type.label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: GISTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${vm.getFeatureCount(type)} features',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: GISTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    )),

                if (active.isEmpty)
                  Text(
                    'No active layers',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: GISTheme.textTertiary,
                    ),
                  ),

                const Divider(color: GISTheme.border, height: 16),

                // Severity legend
                Text(
                  'SEVERITY',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: GISTheme.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: Severity.values.map((s) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.color,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          s.label,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: GISTheme.textSecondary,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO-REFRESH SECTION (full level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAutoRefreshSection(HazardViewModel vm) {
    final isActive = vm.isAutoRefreshActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUTO-REFRESH',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: GISTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: GISTheme.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: GISTheme.border.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.sync,
                      size: 16,
                      color: isActive
                          ? GISTheme.accentGreen
                          : GISTheme.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Auto-refresh data',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: GISTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 24,
                      child: Switch.adaptive(
                        value: isActive,
                        activeTrackColor: GISTheme.accentGreen.withValues(alpha: 0.5),
                        activeThumbColor: GISTheme.accentGreen,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          if (v) {
                            vm.startAutoRefresh();
                          } else {
                            vm.stopAutoRefresh();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Interval',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: GISTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      _IntervalChip(
                        label: '1m',
                        selected: vm.autoRefreshInterval.inMinutes == 1,
                        onTap: () => vm.startAutoRefresh(
                            interval: const Duration(minutes: 1)),
                      ),
                      const SizedBox(width: 6),
                      _IntervalChip(
                        label: '5m',
                        selected: vm.autoRefreshInterval.inMinutes == 5,
                        onTap: () => vm.startAutoRefresh(
                            interval: const Duration(minutes: 5)),
                      ),
                      const SizedBox(width: 6),
                      _IntervalChip(
                        label: '15m',
                        selected: vm.autoRefreshInterval.inMinutes == 15,
                        onTap: () => vm.startAutoRefresh(
                            interval: const Duration(minutes: 15)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Manual refresh button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                widget.onRefresh?.call();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'Refresh Now',
                style: GoogleFonts.inter(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: GISTheme.accentBlue,
                side: BorderSide(
                    color: GISTheme.accentBlue.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA SOURCES SECTION (full level)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataSourcesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _ExpandableInfoSection(
        title: 'ABOUT DATA SOURCES',
        children: [
          _dataSourceTile(HazardType.wildfire, 'NASA FIRMS',
              'Near-real-time fire detections from MODIS and VIIRS satellites. ~375m resolution, updated every 3 hours.'),
          _dataSourceTile(HazardType.flood, 'NWS AHPS',
              'National Weather Service Advanced Hydrologic Prediction Service. River gauge data and flood forecasts.'),
          _dataSourceTile(HazardType.drought, 'USDM',
              'US Drought Monitor. Weekly composite of multiple drought indicators.'),
          _dataSourceTile(HazardType.glacier, 'GLIMS / RGI',
              'Global Land Ice Measurements from Space. Glacier outlines and change detection.'),
          _dataSourceTile(HazardType.ndvi, 'MODIS / Sentinel-2',
              'Vegetation health indices from multi-spectral satellite imagery. 10-250m resolution.'),
        ],
      ),
    );
  }

  Widget _dataSourceTile(HazardType type, String source, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: type.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.label} - $source',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GISTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: GISTheme.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════

enum _SheetLevel { peek, half, full }

// ─────────────────────────────────────────────────────────────
// Hazard toggle card (2-column grid item)
// ─────────────────────────────────────────────────────────────

class _HazardToggleCard extends StatelessWidget {
  final HazardType type;
  final bool isActive;
  final int featureCount;
  final VoidCallback onToggle;

  const _HazardToggleCard({
    required this.type,
    required this.isActive,
    required this.featureCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? type.color.withValues(alpha: 0.08)
              : GISTheme.surfaceLight.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isActive ? type.color : Colors.transparent,
              width: 3,
            ),
            top: BorderSide(
              color: GISTheme.border.withValues(alpha: isActive ? 0.4 : 0.2),
            ),
            right: BorderSide(
              color: GISTheme.border.withValues(alpha: isActive ? 0.4 : 0.2),
            ),
            bottom: BorderSide(
              color: GISTheme.border.withValues(alpha: isActive ? 0.4 : 0.2),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              type.icon,
              size: 18,
              color: isActive ? type.color : GISTheme.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    type.label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? GISTheme.textPrimary
                          : GISTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isActive && featureCount > 0)
                    Text(
                      '$featureCount',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: type.color.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 32,
              height: 18,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch.adaptive(
                  value: isActive,
                  activeTrackColor: type.color.withValues(alpha: 0.5),
                  activeThumbColor: type.color,
                  onChanged: (_) {
                    HapticFeedback.selectionClick();
                    onToggle();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Alert card (horizontal scrollable)
// ─────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final HazardFeature alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GISTheme.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert.severity.color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(alert.type.icon, size: 14, color: alert.type.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  alert.type.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GISTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: alert.severity.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.severity.label,
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: alert.severity.color,
                  ),
                ),
              ),
            ],
          ),
          Text(
            alert.properties['description'] as String? ??
                '${alert.latitude.toStringAsFixed(2)}, ${alert.longitude.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: GISTheme.textSecondary,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Interval chip for auto-refresh
// ─────────────────────────────────────────────────────────────

class _IntervalChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntervalChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? GISTheme.accentBlue.withValues(alpha: 0.15)
              : GISTheme.surfaceDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? GISTheme.accentBlue.withValues(alpha: 0.5)
                : GISTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? GISTheme.accentBlue : GISTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Expandable info section (About Data Sources)
// ─────────────────────────────────────────────────────────────

class _ExpandableInfoSection extends StatefulWidget {
  final String title;
  final List<Widget> children;

  const _ExpandableInfoSection({
    required this.title,
    required this.children,
  });

  @override
  State<_ExpandableInfoSection> createState() => _ExpandableInfoSectionState();
}

class _ExpandableInfoSectionState extends State<_ExpandableInfoSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 12, color: GISTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                widget.title,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: GISTheme.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: GISTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GISTheme.surfaceLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: GISTheme.border.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}
