import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/data/country_data.dart';
import 'package:ecolens/model/country_models.dart';
import 'package:ecolens/services/country_intelligence_service.dart';

// ═══════════════════════════════════════════════════════════════
// COUNTRY INTELLIGENCE SCREEN
// Comprehensive environmental intelligence for any country
// ═══════════════════════════════════════════════════════════════

class CountryIntelligenceScreen extends StatefulWidget {
  final String? initialCountryCode;
  const CountryIntelligenceScreen({super.key, this.initialCountryCode});

  @override
  State<CountryIntelligenceScreen> createState() =>
      _CountryIntelligenceScreenState();
}

class _CountryIntelligenceScreenState extends State<CountryIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CountryProfile? _profile;
  bool _loading = false;
  String? _selectedCode;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _service = CountryIntelligenceService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    if (widget.initialCountryCode != null) {
      _selectedCode = widget.initialCountryCode;
      _loadProfile(widget.initialCountryCode!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile(String code) async {
    setState(() { _loading = true; _selectedCode = code; });
    try {
      final profile = await _service.fetchCountryProfile(code);
      if (mounted) setState(() { _profile = profile; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GISTheme.backgroundDark,
      body: _selectedCode == null ? _buildCountryPicker() : _buildIntelligence(),
    );
  }

  // ── Country Picker ──────────────────────────────────────
  Widget _buildCountryPicker() {
    final countries = searchCountries(_searchQuery);
    // Group by region
    final grouped = <String, List<CountryInfo>>{};
    for (final c in countries) {
      grouped.putIfAbsent(c.region, () => []).add(c);
    }
    final regions = grouped.keys.toList()..sort();

    return Column(
      children: [
        _buildPickerHeader(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: TextField(
            controller: _searchController,
            style: GISTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Search countries...',
              hintStyle: GISTheme.bodyMedium,
              prefixIcon: const Icon(Icons.search, color: GISTheme.textSecondary, size: 20),
              filled: true,
              fillColor: GISTheme.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: GISTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: GISTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: GISTheme.accentBlue),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: regions.length,
            itemBuilder: (ctx, ri) {
              final region = regions[ri];
              final list = grouped[region]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                    child: Text(region, style: GISTheme.label.copyWith(
                      color: GISTheme.accentBlue, fontSize: 12, letterSpacing: 1,
                    )),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: list.map((c) => _countryChip(c)).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPickerHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 24, right: 24, bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: GISTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: GISTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: GISTheme.accentBlue, size: 28),
          const SizedBox(width: 12),
          Text('Country Intelligence',
            style: GoogleFonts.inter(
              fontSize: 22, fontWeight: FontWeight.w700, color: GISTheme.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: GISTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _countryChip(CountryInfo c) {
    return ActionChip(
      avatar: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: CachedNetworkImage(
          imageUrl: 'https://flagcdn.com/w40/${c.code}.png',
          width: 24, height: 16, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.flag, size: 16),
        ),
      ),
      label: Text(c.name, style: GISTheme.bodySmall.copyWith(color: GISTheme.textPrimary)),
      backgroundColor: GISTheme.surfaceLight,
      side: const BorderSide(color: GISTheme.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onPressed: () => _loadProfile(c.code),
    );
  }

  // ── Intelligence View ───────────────────────────────────
  Widget _buildIntelligence() {
    return Column(
      children: [
        _buildHeader(),
        if (_loading) _buildLoadingBar(),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: GISTheme.accentBlue,
          unselectedLabelColor: GISTheme.textSecondary,
          labelStyle: GISTheme.headingSmall,
          unselectedLabelStyle: GISTheme.bodySmall,
          indicatorColor: GISTheme.accentBlue,
          indicatorWeight: 2,
          dividerColor: GISTheme.border,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Climate'),
            Tab(text: 'Disasters'),
            Tab(text: 'Environment'),
            Tab(text: 'Demographics'),
          ],
        ),
        Expanded(
          child: _loading
              ? _buildShimmer()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildClimateTab(),
                    _buildDisastersTab(),
                    _buildEnvironmentTab(),
                    _buildDemographicsTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildLoadingBar() {
    return const LinearProgressIndicator(
      backgroundColor: GISTheme.surfaceDark,
      valueColor: AlwaysStoppedAnimation<Color>(GISTheme.accentBlue),
      minHeight: 2,
    );
  }

  Widget _buildShimmer() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: GISTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text('Loading intelligence data...', style: GISTheme.bodyMedium),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────
  Widget _buildHeader() {
    final info = countryByCode(_selectedCode ?? '');
    final p = _profile;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 20, right: 20, bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: GISTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: GISTheme.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: GISTheme.textSecondary, size: 20),
                onPressed: () => setState(() {
                  _selectedCode = null; _profile = null; _searchQuery = '';
                  _searchController.clear();
                }),
                tooltip: 'Back to countries',
              ),
              const SizedBox(width: 8),
              // Flag
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: 'https://flagcdn.com/w80/${_selectedCode}.png',
                  width: 48, height: 32, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 48, height: 32, color: GISTheme.surfaceHover,
                    child: const Icon(Icons.flag, size: 20, color: GISTheme.textTertiary),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info?.name ?? _selectedCode ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: GISTheme.textPrimary,
                      ),
                    ),
                    if (info != null)
                      Text(
                        '${info.iso3}  |  ${info.region}  |  ${info.lat.toStringAsFixed(1)}, ${info.lon.toStringAsFixed(1)}',
                        style: GISTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: GISTheme.textSecondary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (p != null && !_loading) ...[
            const SizedBox(height: 12),
            _buildStatRow(p),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(CountryProfile p) {
    final pop = p.latestIndicator('SP.POP.TOTL');
    final gdp = p.latestIndicator('NY.GDP.PCAP.CD');
    final forest = p.latestIndicator('AG.LND.FRST.ZS');
    final co2 = p.latestIndicator('EN.ATM.CO2E.PC');

    return Row(
      children: [
        _headerStat('Population', pop != null ? _formatNumber(pop) : '--', Icons.people_outline),
        _headerStat('GDP/capita', gdp != null ? '\$${_formatNumber(gdp)}' : '--', Icons.attach_money),
        _headerStat('Forest', forest != null ? '${forest.toStringAsFixed(1)}%' : '--', Icons.park_outlined),
        _headerStat('CO2/cap', co2 != null ? '${co2.toStringAsFixed(1)}t' : '--', Icons.cloud_outlined),
      ],
    );
  }

  Widget _headerStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: GISTheme.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: GISTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: GISTheme.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: GISTheme.headingSmall.copyWith(fontSize: 13)),
                  Text(label, style: GISTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Risk Profile'),
        const SizedBox(height: 8),
        _buildRiskRadar(p),
        const SizedBox(height: 24),
        _sectionTitle('Recent Disasters'),
        const SizedBox(height: 8),
        if (p.recentDisasters.isEmpty)
          _emptyState('No recent disasters recorded')
        else
          ...p.recentDisasters.take(10).map(_buildDisasterTile),
        const SizedBox(height: 24),
        _sectionTitle('Key Indicators'),
        const SizedBox(height: 8),
        _buildIndicatorCards(p),
      ],
    );
  }

  Widget _buildRiskRadar(CountryProfile p) {
    // Compute risk scores 0-1 based on available data
    final double seismicRisk = p.earthquakes.isEmpty
        ? 0.1
        : (p.earthquakes.map((e) => e.magnitude).reduce(max) / 9.0).clamp(0.0, 1.0).toDouble();
    final floodRisk = _disasterTypeRatio(p, 'Flood');
    final droughtRisk = _disasterTypeRatio(p, 'Drought');
    final fireRisk = _disasterTypeRatioMulti(p, ['Wild Fire', 'Fire', 'Wildfire', 'Forest Fire']);
    final double climateRisk = p.projection != null && p.projection!.yearly.length >= 2
        ? ((p.projection!.yearly.last.tempMax - p.projection!.yearly.first.tempMax).abs() / 5.0).clamp(0.0, 1.0).toDouble()
        : 0.3;

    final List<double> values = [seismicRisk, floodRisk, droughtRisk, fireRisk, climateRisk];

    return Container(
      height: 280,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.all(16),
      child: RadarChart(
        RadarChartData(
          dataSets: [
            RadarDataSet(
              dataEntries: values.map((v) => RadarEntry(value: v * 100)).toList(),
              fillColor: GISTheme.accentBlue.withValues(alpha: 0.2),
              borderColor: GISTheme.accentBlue,
              borderWidth: 2,
              entryRadius: 3,
            ),
          ],
          radarBackgroundColor: Colors.transparent,
          borderData: FlBorderData(show: false),
          radarBorderData: const BorderSide(color: GISTheme.border, width: 1),
          tickBorderData: const BorderSide(color: GISTheme.border, width: 0.5),
          gridBorderData: const BorderSide(color: GISTheme.border, width: 0.5),
          tickCount: 4,
          ticksTextStyle: const TextStyle(fontSize: 0, color: Colors.transparent),
          titleTextStyle: GISTheme.labelSmall.copyWith(color: GISTheme.textSecondary),
          getTitle: (i, _) {
            const titles = ['Seismic', 'Flood', 'Drought', 'Fire', 'Climate\nChange'];
            return RadarChartTitle(text: titles[i]);
          },
          titlePositionPercentageOffset: 0.2,
        ),
      ),
    );
  }

  double _disasterTypeRatio(CountryProfile p, String type) {
    if (p.recentDisasters.isEmpty) return 0.1;
    final count = p.recentDisasters.where(
      (d) => d.type.toLowerCase().contains(type.toLowerCase()),
    ).length;
    return (count / p.recentDisasters.length * 2).clamp(0.0, 1.0);
  }

  double _disasterTypeRatioMulti(CountryProfile p, List<String> types) {
    if (p.recentDisasters.isEmpty) return 0.1;
    final count = p.recentDisasters.where(
      (d) => types.any((t) => d.type.toLowerCase().contains(t.toLowerCase())),
    ).length;
    return (count / p.recentDisasters.length * 2).clamp(0.0, 1.0);
  }

  Widget _buildDisasterTile(DisasterEvent d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: GISTheme.panelDecoration,
      child: ListTile(
        dense: true,
        leading: Icon(_disasterIcon(d.type), color: _disasterColor(d.type), size: 22),
        title: Text(d.name, style: GISTheme.bodySmall.copyWith(color: GISTheme.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${d.type}  |  ${DateFormat.yMMMd().format(d.date)}', style: GISTheme.labelSmall),
        trailing: d.url != null
            ? const Icon(Icons.open_in_new, size: 14, color: GISTheme.textTertiary)
            : null,
      ),
    );
  }

  Widget _buildIndicatorCards(CountryProfile p) {
    final cards = <Widget>[];
    for (final entry in p.indicators.entries) {
      final label = _indicatorLabel(entry.key);
      final values = entry.value.where((v) => v.value != null).toList();
      if (values.isEmpty) continue;
      final latest = values.last;
      cards.add(_indicatorCard(label, latest, values, entry.key));
    }
    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }

  Widget _indicatorCard(String label, YearValue latest, List<YearValue> series, String key) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: GISTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GISTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            _formatIndicatorValue(key, latest.value ?? 0),
            style: GISTheme.headingLarge.copyWith(fontSize: 20),
          ),
          Text('${latest.year}', style: GISTheme.labelSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: _sparkline(series),
          ),
          // Source
          const SizedBox(height: 6),
          Text('Source: World Bank', style: GISTheme.labelSmall.copyWith(fontSize: 9, color: GISTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _sparkline(List<YearValue> series) {
    final filtered = series.where((v) => v.value != null).toList();
    if (filtered.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < filtered.length; i++) {
      spots.add(FlSpot(i.toDouble(), filtered[i].value!));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: GISTheme.accentGreen,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: GISTheme.accentGreen.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: CLIMATE
  // ═══════════════════════════════════════════════════════
  Widget _buildClimateTab() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    final climate = p.climate;
    final proj = p.projection;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Monthly Temperature'),
        const SizedBox(height: 8),
        _buildTempChart(climate),
        const SizedBox(height: 24),
        _sectionTitle('Monthly Precipitation'),
        const SizedBox(height: 8),
        _buildPrecipChart(climate),
        const SizedBox(height: 24),
        _sectionTitle('Climate Projection to 2050 (SSP2-4.5)'),
        const SizedBox(height: 8),
        _buildProjectionChart(proj),
        const SizedBox(height: 24),
        _sectionTitle('Climate Summary'),
        const SizedBox(height: 8),
        _buildClimateSummaryTable(climate, proj),
        _sourceAttribution('Open-Meteo Archive & Climate API'),
      ],
    );
  }

  Widget _buildTempChart(ClimateData? climate) {
    if (climate == null || climate.monthly.isEmpty) return _emptyState('No climate data available');

    return Container(
      height: 260,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (_) => FlLine(color: GISTheme.border, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 40, interval: 10,
                getTitlesWidget: (v, _) => Text('${v.toInt()}°', style: GISTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= climate.monthly.length) return const SizedBox.shrink();
                  return Text(climate.monthly[i].monthName, style: GISTheme.labelSmall);
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: climate.monthly.asMap().entries.map((e) =>
                FlSpot(e.key.toDouble(), e.value.avgTempMax),
              ).toList(),
              isCurved: true, color: GISTheme.accentRed, barWidth: 2,
              dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
                FlDotCirclePainter(radius: 3, color: GISTheme.accentRed, strokeWidth: 0)),
              belowBarData: BarAreaData(show: true, color: GISTheme.accentRed.withValues(alpha: 0.08)),
            ),
            LineChartBarData(
              spots: climate.monthly.asMap().entries.map((e) =>
                FlSpot(e.key.toDouble(), e.value.avgTempMin),
              ).toList(),
              isCurved: true, color: GISTheme.accentBlue, barWidth: 2,
              dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
                FlDotCirclePainter(radius: 3, color: GISTheme.accentBlue, strokeWidth: 0)),
              belowBarData: BarAreaData(show: true, color: GISTheme.accentBlue.withValues(alpha: 0.08)),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => GISTheme.surfaceDark,
              getTooltipItems: (spots) => spots.map((s) =>
                LineTooltipItem(
                  '${s.y.toStringAsFixed(1)}°C',
                  GISTheme.bodySmall.copyWith(color: s.bar.color),
                ),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrecipChart(ClimateData? climate) {
    if (climate == null || climate.monthly.isEmpty) return _emptyState('No precipitation data');

    return Container(
      height: 220,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: GISTheme.border, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, _) => Text('${v.toInt()} mm', style: GISTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= climate.monthly.length) return const SizedBox.shrink();
                  return Text(climate.monthly[i].monthName, style: GISTheme.labelSmall);
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: climate.monthly.asMap().entries.map((e) =>
            BarChartGroupData(x: e.key, barRods: [
              BarChartRodData(
                toY: e.value.precipMm,
                color: GISTheme.accentBlue,
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ]),
          ).toList(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => GISTheme.surfaceDark,
              getTooltipItem: (group, _, rod, __) =>
                BarTooltipItem('${rod.toY.toStringAsFixed(0)} mm', GISTheme.bodySmall.copyWith(color: GISTheme.accentBlue)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectionChart(ClimateProjection? proj) {
    if (proj == null || proj.yearly.isEmpty) return _emptyState('No projection data available');

    return Container(
      height: 260,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: GISTheme.border, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 40, interval: 2,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}°', style: GISTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28, interval: 5,
                getTitlesWidget: (v, _) {
                  final year = v.toInt();
                  return Text('$year', style: GISTheme.labelSmall);
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: proj.yearly.map((y) => FlSpot(y.year.toDouble(), y.tempMax)).toList(),
              isCurved: true, color: GISTheme.accentOrange, barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: GISTheme.accentOrange.withValues(alpha: 0.12),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => GISTheme.surfaceDark,
              getTooltipItems: (spots) => spots.map((s) =>
                LineTooltipItem(
                  '${s.x.toInt()}: ${s.y.toStringAsFixed(1)}°C',
                  GISTheme.bodySmall.copyWith(color: GISTheme.accentOrange),
                ),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClimateSummaryTable(ClimateData? climate, ClimateProjection? proj) {
    final rows = <List<String>>[];
    if (climate != null) {
      rows.add(['Current Avg Temp', '${climate.avgTempC.toStringAsFixed(1)} °C']);
      rows.add(['Annual Precipitation', '${climate.totalPrecipMm.toStringAsFixed(0)} mm']);
    }
    if (proj != null && proj.yearly.length >= 2) {
      rows.add(['Projected 2050 Temp (max)', '${proj.yearly.last.tempMax.toStringAsFixed(1)} °C']);
      final change = proj.yearly.last.tempMax - proj.yearly.first.tempMax;
      rows.add(['Temp Change (2025-2050)', '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} °C']);
    }
    return _dataTable(rows);
  }

  // ═══════════════════════════════════════════════════════
  // TAB 3: DISASTERS
  // ═══════════════════════════════════════════════════════
  Widget _buildDisastersTab() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Disaster Type Distribution'),
        const SizedBox(height: 8),
        _buildDisasterDonut(p),
        const SizedBox(height: 24),
        _sectionTitle('Earthquake Activity'),
        const SizedBox(height: 8),
        _buildEarthquakeList(p),
        const SizedBox(height: 24),
        _sectionTitle('Disaster Timeline'),
        const SizedBox(height: 8),
        _buildDisasterTimeline(p),
        const SizedBox(height: 24),
        _sectionTitle('Disaster Statistics'),
        const SizedBox(height: 8),
        _buildDisasterStatsTable(p),
        _sourceAttribution('ReliefWeb API & USGS Earthquake Hazards'),
      ],
    );
  }

  Widget _buildDisasterDonut(CountryProfile p) {
    if (p.recentDisasters.isEmpty) return _emptyState('No disaster data');

    final typeCounts = <String, int>{};
    for (final d in p.recentDisasters) {
      typeCounts[d.type] = (typeCounts[d.type] ?? 0) + 1;
    }
    final entries = typeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      GISTheme.accentBlue, GISTheme.accentOrange, GISTheme.accentRed,
      GISTheme.accentGreen, GISTheme.accentPurple, GISTheme.accentYellow,
      GISTheme.dataViz3, GISTheme.dataViz4,
    ];

    return Container(
      height: 240,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: entries.asMap().entries.map((e) {
                  final pct = e.value.value / p.recentDisasters.length * 100;
                  return PieChartSectionData(
                    value: e.value.value.toDouble(),
                    title: '${pct.toStringAsFixed(0)}%',
                    color: colors[e.key % colors.length],
                    radius: 50,
                    titleStyle: GISTheme.labelSmall.copyWith(color: Colors.white, fontSize: 10),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.take(6).map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: colors[e.key % colors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${e.value.key} (${e.value.value})', style: GISTheme.labelSmall),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEarthquakeList(CountryProfile p) {
    if (p.earthquakes.isEmpty) return _emptyState('No recent earthquakes in 500km radius');

    final sorted = List<EarthquakeEvent>.from(p.earthquakes)
      ..sort((a, b) => b.magnitude.compareTo(a.magnitude));

    return Container(
      decoration: GISTheme.panelDecoration,
      child: Column(
        children: sorted.take(15).map((eq) {
          final magColor = eq.magnitude >= 6.0
              ? GISTheme.accentRed
              : eq.magnitude >= 4.0
                  ? GISTheme.accentOrange
                  : GISTheme.accentYellow;
          return ListTile(
            dense: true,
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: magColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(eq.magnitude.toStringAsFixed(1),
                style: GISTheme.headingSmall.copyWith(color: magColor, fontSize: 14)),
            ),
            title: Text(eq.place, style: GISTheme.bodySmall.copyWith(color: GISTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Depth: ${eq.depth.toStringAsFixed(0)} km  |  ${DateFormat.yMMMd().format(eq.time)}',
              style: GISTheme.labelSmall),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDisasterTimeline(CountryProfile p) {
    if (p.recentDisasters.isEmpty) return _emptyState('No disaster history');

    // Group by year
    final byYear = <int, List<DisasterEvent>>{};
    for (final d in p.recentDisasters) {
      byYear.putIfAbsent(d.date.year, () => []).add(d);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: years.take(10).map((year) {
          final events = byYear[year]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: GISTheme.accentBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$year', style: GISTheme.headingSmall.copyWith(color: GISTheme.accentBlue)),
                  const SizedBox(width: 8),
                  Text('${events.length} event${events.length > 1 ? 's' : ''}',
                    style: GISTheme.labelSmall),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: events.map((e) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(_disasterIcon(e.type), size: 14, color: _disasterColor(e.type)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(e.name, style: GISTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDisasterStatsTable(CountryProfile p) {
    final total = p.recentDisasters.length;
    final typeCounts = <String, int>{};
    for (final d in p.recentDisasters) {
      typeCounts[d.type] = (typeCounts[d.type] ?? 0) + 1;
    }
    final mostCommon = typeCounts.entries.isEmpty
        ? '--'
        : (typeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final mostRecent = p.recentDisasters.isEmpty ? '--' : DateFormat.yMMMd().format(p.recentDisasters.first.date);
    final eqCount = p.earthquakes.length;
    final maxMag = p.earthquakes.isEmpty ? '--' : p.earthquakes.map((e) => e.magnitude).reduce(max).toStringAsFixed(1);

    return _dataTable([
      ['Total Disasters', '$total'],
      ['Most Common Type', mostCommon],
      ['Most Recent', mostRecent],
      ['Earthquakes (1yr, 500km)', '$eqCount'],
      ['Max Magnitude', '$maxMag'],
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // TAB 4: ENVIRONMENT
  // ═══════════════════════════════════════════════════════
  Widget _buildEnvironmentTab() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Forest Cover Trend'),
        const SizedBox(height: 8),
        _buildIndicatorLineChart(p, 'AG.LND.FRST.ZS', 'Forest Area (%)', GISTheme.accentGreen),
        const SizedBox(height: 24),
        _sectionTitle('CO2 Emissions Trend'),
        const SizedBox(height: 8),
        _buildIndicatorLineChart(p, 'EN.ATM.CO2E.PC', 'CO2 (metric tons/capita)', GISTheme.accentOrange),
        const SizedBox(height: 24),
        _sectionTitle('Access to Electricity'),
        const SizedBox(height: 8),
        _buildIndicatorLineChart(p, 'EG.ELC.ACCS.ZS', 'Electricity Access (%)', GISTheme.accentYellow),
        const SizedBox(height: 24),
        _sectionTitle('Environment Summary'),
        const SizedBox(height: 8),
        _buildEnvironmentTable(p),
        _sourceAttribution('World Bank Open Data'),
      ],
    );
  }

  Widget _buildIndicatorLineChart(CountryProfile p, String key, String label, Color color) {
    final series = p.indicators[key]?.where((v) => v.value != null).toList() ?? [];
    if (series.length < 2) return _emptyState('Insufficient data for $label');

    return Container(
      height: 220,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: GISTheme.border, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 50,
                getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: GISTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toInt()}', style: GISTheme.labelSmall),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: series.map((v) => FlSpot(v.year.toDouble(), v.value!)).toList(),
              isCurved: true, color: color, barWidth: 2.5,
              dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
                FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0)),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => GISTheme.surfaceDark,
              getTooltipItems: (spots) => spots.map((s) =>
                LineTooltipItem('${s.x.toInt()}: ${s.y.toStringAsFixed(2)}', GISTheme.bodySmall.copyWith(color: color)),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnvironmentTable(CountryProfile p) {
    final rows = <List<String>>[];
    void addTrend(String key, String label, String unit) {
      final series = p.indicators[key]?.where((v) => v.value != null).toList() ?? [];
      if (series.length >= 2) {
        final latest = series.last;
        final prev = series[series.length - 2];
        final change = latest.value! - prev.value!;
        rows.add([label, '${latest.value!.toStringAsFixed(2)} $unit (${latest.year})']);
        rows.add(['  YoY Change', '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} $unit']);
      } else if (series.isNotEmpty) {
        rows.add([label, '${series.last.value!.toStringAsFixed(2)} $unit (${series.last.year})']);
      }
    }
    addTrend('AG.LND.FRST.ZS', 'Forest Cover', '%');
    addTrend('EN.ATM.CO2E.PC', 'CO2 per Capita', 't');
    addTrend('EG.ELC.ACCS.ZS', 'Electricity Access', '%');
    return _dataTable(rows);
  }

  // ═══════════════════════════════════════════════════════
  // TAB 5: DEMOGRAPHICS
  // ═══════════════════════════════════════════════════════
  Widget _buildDemographicsTab() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Population Trend'),
        const SizedBox(height: 8),
        _buildPopulationChart(p),
        const SizedBox(height: 24),
        _sectionTitle('GDP per Capita Trend'),
        const SizedBox(height: 8),
        _buildIndicatorLineChart(p, 'NY.GDP.PCAP.CD', 'GDP per Capita (USD)', GISTheme.accentPurple),
        const SizedBox(height: 24),
        _sectionTitle('Demographics Summary'),
        const SizedBox(height: 8),
        _buildDemographicsTable(p),
        const SizedBox(height: 16),
        _buildExportButton(p),
        _sourceAttribution('World Bank Open Data'),
      ],
    );
  }

  Widget _buildPopulationChart(CountryProfile p) {
    final series = p.indicators['SP.POP.TOTL']?.where((v) => v.value != null).toList() ?? [];
    if (series.length < 2) return _emptyState('No population data');

    return Container(
      height: 220,
      decoration: GISTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: GISTheme.border, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 55,
                getTitlesWidget: (v, _) => Text(_formatNumber(v), style: GISTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= series.length) return const SizedBox.shrink();
                  return Text('${series[i].year}', style: GISTheme.labelSmall);
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: series.asMap().entries.map((e) =>
            BarChartGroupData(x: e.key, barRods: [
              BarChartRodData(
                toY: e.value.value!,
                color: GISTheme.accentPurple,
                width: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ]),
          ).toList(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => GISTheme.surfaceDark,
              getTooltipItem: (group, _, rod, __) {
                final i = group.x;
                final year = i < series.length ? series[i].year : 0;
                return BarTooltipItem(
                  '$year: ${_formatNumber(rod.toY)}',
                  GISTheme.bodySmall.copyWith(color: GISTheme.accentPurple),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDemographicsTable(CountryProfile p) {
    final rows = <List<String>>[];
    final pop = p.indicators['SP.POP.TOTL']?.where((v) => v.value != null).toList() ?? [];
    if (pop.isNotEmpty) {
      rows.add(['Population', _formatNumber(pop.last.value!) + ' (${pop.last.year})']);
      if (pop.length >= 2) {
        final growth = (pop.last.value! - pop[pop.length - 2].value!) / pop[pop.length - 2].value! * 100;
        rows.add(['Annual Growth', '${growth.toStringAsFixed(2)}%']);
      }
    }
    final gdp = p.indicators['NY.GDP.PCAP.CD']?.where((v) => v.value != null).toList() ?? [];
    if (gdp.isNotEmpty) {
      rows.add(['GDP per Capita', '\$${_formatNumber(gdp.last.value!)} (${gdp.last.year})']);
    }
    final elec = p.indicators['EG.ELC.ACCS.ZS']?.where((v) => v.value != null).toList() ?? [];
    if (elec.isNotEmpty) {
      rows.add(['Electricity Access', '${elec.last.value!.toStringAsFixed(1)}% (${elec.last.year})']);
    }
    return _dataTable(rows);
  }

  Widget _buildExportButton(CountryProfile p) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.copy, size: 16),
        label: const Text('Copy as CSV'),
        style: OutlinedButton.styleFrom(
          foregroundColor: GISTheme.textSecondary,
          side: const BorderSide(color: GISTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onPressed: () {
          final buffer = StringBuffer();
          buffer.writeln('Indicator,Year,Value');
          for (final entry in p.indicators.entries) {
            for (final yv in entry.value.where((v) => v.value != null)) {
              buffer.writeln('${_indicatorLabel(entry.key)},${yv.year},${yv.value}');
            }
          }
          Clipboard.setData(ClipboardData(text: buffer.toString()));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Data copied to clipboard', style: GISTheme.bodySmall.copyWith(color: Colors.white)),
                backgroundColor: GISTheme.surfaceDark,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _sectionTitle(String title) {
    return Text(title, style: GISTheme.headingMedium);
  }

  Widget _emptyState(String message) {
    return Container(
      height: 120,
      decoration: GISTheme.panelDecoration,
      alignment: Alignment.center,
      child: Text(message, style: GISTheme.bodyMedium),
    );
  }

  Widget _dataTable(List<List<String>> rows) {
    return Container(
      decoration: GISTheme.panelDecoration,
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: isLast ? null : const BoxDecoration(
              border: Border(bottom: BorderSide(color: GISTheme.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(e.value[0], style: GISTheme.bodySmall)),
                Text(e.value[1], style: GISTheme.bodySmall.copyWith(color: GISTheme.textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sourceAttribution(String source) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text('Data source: $source', style: GISTheme.labelSmall.copyWith(fontSize: 9, color: GISTheme.textTertiary)),
    );
  }

  // ── Helpers ─────────────────────────────────────────────
  String _formatNumber(double n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(n < 100 ? 1 : 0);
  }

  String _indicatorLabel(String key) {
    const labels = {
      'SP.POP.TOTL': 'Population',
      'NY.GDP.PCAP.CD': 'GDP per Capita (USD)',
      'EN.ATM.CO2E.PC': 'CO2 per Capita (tons)',
      'AG.LND.FRST.ZS': 'Forest Area (%)',
      'EG.ELC.ACCS.ZS': 'Electricity Access (%)',
    };
    return labels[key] ?? key;
  }

  String _formatIndicatorValue(String key, double v) {
    if (key == 'SP.POP.TOTL') return _formatNumber(v);
    if (key == 'NY.GDP.PCAP.CD') return '\$${_formatNumber(v)}';
    if (key.endsWith('.ZS') || key.endsWith('.PC')) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  IconData _disasterIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('flood')) return Icons.water;
    if (t.contains('cyclone') || t.contains('storm') || t.contains('hurricane') || t.contains('typhoon')) return Icons.tornado;
    if (t.contains('drought')) return Icons.wb_sunny;
    if (t.contains('earthquake')) return Icons.vibration;
    if (t.contains('fire')) return Icons.local_fire_department;
    if (t.contains('volcano')) return Icons.terrain;
    if (t.contains('landslide') || t.contains('mudslide')) return Icons.landscape;
    if (t.contains('epidemic') || t.contains('pandemic')) return Icons.coronavirus;
    if (t.contains('tsunami')) return Icons.waves;
    return Icons.warning_amber;
  }

  Color _disasterColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('flood') || t.contains('tsunami')) return GISTheme.accentBlue;
    if (t.contains('cyclone') || t.contains('storm') || t.contains('hurricane')) return GISTheme.accentPurple;
    if (t.contains('drought')) return GISTheme.accentYellow;
    if (t.contains('earthquake')) return GISTheme.accentOrange;
    if (t.contains('fire')) return GISTheme.accentRed;
    if (t.contains('volcano')) return GISTheme.accentOrange;
    return GISTheme.textTertiary;
  }
}
