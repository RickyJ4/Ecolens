import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ecolens/model/simulation_models.dart';
import 'package:ecolens/services/simulation_engine.dart';
import 'package:ecolens/widgets/impact_report_viewer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SIMULATION SCREEN
// Configure, run, and visualize environmental hazard simulations
// ═══════════════════════════════════════════════════════════════════════════

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────
  SimulationType _selectedType = SimulationType.wildfire;
  bool _isRunning = false;
  SimulationResult? _result;
  ImpactReport? _report;
  int _currentFrameIndex = 0;

  // ── Location ────────────────────────────────────────────────
  final _latController = TextEditingController(text: '37.7749');
  final _lonController = TextEditingController(text: '-122.4194');

  // ── Wildfire parameters ─────────────────────────────────────
  double _windSpeed = 15;
  double _windDirection = 270;
  double _humidity = 30;
  double _temperature = 32;
  int _fuelTypeIndex = 0;

  // ── Flood parameters ────────────────────────────────────────
  double _waterLevelRise = 2.0;
  double _floodRadius = 10.0;

  // ── Sea level parameters ────────────────────────────────────
  double _seaLevelRise = 1.0;
  double _seaLevelRadius = 20.0;

  // ── Drought parameters ──────────────────────────────────────
  double _currentNDVI = 0.4;
  double _precipDeficit = 30;
  double _monthsForward = 6;

  // ── Duration ────────────────────────────────────────────────
  int _durationHours = 24;

  // ── Palette ─────────────────────────────────────────────────
  static const _bg = Color(0xFF0A0E14);
  static const _cardBg = Color(0xFF1A1A2E);
  static const _accent = Color(0xFF00D26A);
  static const _fire = Color(0xFFFF4500);
  static const _flood = Color(0xFF1E90FF);
  static const _drought = Color(0xFFCC8400);

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color get _typeColor {
    switch (_selectedType) {
      case SimulationType.wildfire:
        return _fire;
      case SimulationType.flood:
      case SimulationType.seaLevelRise:
        return _flood;
      case SimulationType.drought:
        return _drought;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Hazard Simulation',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.description_outlined, color: Colors.white70),
              tooltip: 'View Full Report',
              onPressed: _openReport,
            ),
        ],
      ),
      body: _result != null ? _buildResultsView() : _buildConfigView(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIGURATION VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildConfigView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('Step 1: Choose Simulation Type'),
          const SizedBox(height: 12),
          _buildTypeSelector(),
          const SizedBox(height: 24),
          _buildSectionLabel('Step 2: Set Parameters'),
          const SizedBox(height: 12),
          _buildParameterCard(),
          const SizedBox(height: 24),
          _buildSectionLabel('Step 3: Set Location'),
          const SizedBox(height: 12),
          _buildLocationCard(),
          const SizedBox(height: 24),
          _buildSectionLabel('Step 4: Duration'),
          const SizedBox(height: 12),
          _buildDurationCard(),
          const SizedBox(height: 32),
          _buildRunButton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _accent,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── Type Selector ──────────────────────────────────────────

  Widget _buildTypeSelector() {
    return Row(
      children: SimulationType.values.map((type) {
        final selected = type == _selectedType;
        Color typeColor;
        IconData typeIcon;
        switch (type) {
          case SimulationType.wildfire:
            typeColor = _fire;
            typeIcon = Icons.local_fire_department;
            break;
          case SimulationType.flood:
            typeColor = _flood;
            typeIcon = Icons.water;
            break;
          case SimulationType.seaLevelRise:
            typeColor = const Color(0xFF4682B4);
            typeIcon = Icons.waves;
            break;
          case SimulationType.drought:
            typeColor = _drought;
            typeIcon = Icons.wb_sunny;
            break;
        }

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedType = type;
              _result = null;
              _report = null;
            }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? typeColor.withValues(alpha: 0.2)
                    : _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? typeColor : Colors.white12,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(typeIcon, color: selected ? typeColor : Colors.white38, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    type.label.split(' ').first,
                    style: TextStyle(
                      color: selected ? typeColor : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Parameter Card ─────────────────────────────────────────

  Widget _buildParameterCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: _buildParameterSliders(),
      ),
    );
  }

  List<Widget> _buildParameterSliders() {
    switch (_selectedType) {
      case SimulationType.wildfire:
        return [
          _buildSlider('Wind Speed', '${_windSpeed.round()} km/h', _windSpeed, 0, 100,
              (v) => setState(() => _windSpeed = v)),
          _buildSlider('Wind Direction', '${_windDirection.round()}\u00B0', _windDirection, 0, 360,
              (v) => setState(() => _windDirection = v)),
          _buildSlider('Humidity', '${_humidity.round()}%', _humidity, 0, 100,
              (v) => setState(() => _humidity = v)),
          _buildSlider('Temperature', '${_temperature.round()}\u00B0C', _temperature, 0, 50,
              (v) => setState(() => _temperature = v)),
          const SizedBox(height: 8),
          _buildFuelTypeSelector(),
        ];
      case SimulationType.flood:
        return [
          _buildSlider('Water Level Rise', '${_waterLevelRise.toStringAsFixed(1)} m',
              _waterLevelRise, 0.5, 10,
              (v) => setState(() => _waterLevelRise = v)),
          _buildSlider('Radius', '${_floodRadius.round()} km', _floodRadius, 1, 50,
              (v) => setState(() => _floodRadius = v)),
        ];
      case SimulationType.seaLevelRise:
        return [
          _buildSlider('Sea Level Rise', '${_seaLevelRise.toStringAsFixed(1)} m',
              _seaLevelRise, 0.5, 5,
              (v) => setState(() => _seaLevelRise = v)),
          _buildSlider('Radius', '${_seaLevelRadius.round()} km', _seaLevelRadius, 5, 100,
              (v) => setState(() => _seaLevelRadius = v)),
        ];
      case SimulationType.drought:
        return [
          _buildSlider('Current NDVI', _currentNDVI.toStringAsFixed(2), _currentNDVI, 0.1, 0.8,
              (v) => setState(() => _currentNDVI = v)),
          _buildSlider('Precip. Deficit', '${_precipDeficit.round()}%', _precipDeficit, 0, 80,
              (v) => setState(() => _precipDeficit = v)),
          _buildSlider('Months Forward', '${_monthsForward.round()}', _monthsForward, 1, 24,
              (v) => setState(() => _monthsForward = v)),
        ];
    }
  }

  Widget _buildSlider(
    String label,
    String valueText,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(valueText,
                  style: TextStyle(color: _typeColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _typeColor,
              thumbColor: _typeColor,
              inactiveTrackColor: Colors.white12,
              overlayColor: _typeColor.withValues(alpha: 0.1),
              trackHeight: 3,
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelTypeSelector() {
    final fuelLabels = FuelType.values.map((f) => f.label).toList();
    return Row(
      children: [
        const Text('Fuel Type', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        ...List.generate(fuelLabels.length, (i) {
          final selected = i == _fuelTypeIndex;
          return GestureDetector(
            onTap: () => setState(() => _fuelTypeIndex = i),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _fire.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? _fire : Colors.white12),
              ),
              child: Text(
                fuelLabels[i],
                style: TextStyle(
                  color: selected ? _fire : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Location Card ──────────────────────────────────────────

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTextField('Latitude', _latController),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField('Longitude', _lonController),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white24, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enter coordinates or use map center from the Map tab.',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _typeColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ── Duration Card ──────────────────────────────────────────

  Widget _buildDurationCard() {
    final isDrought = _selectedType == SimulationType.drought;
    final isSeaLevel = _selectedType == SimulationType.seaLevelRise;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: isSeaLevel
          ? const Text(
              'Sea level rise is a static scenario (no time progression).',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          : isDrought
              ? Text(
                  'Duration set by "Months Forward" parameter above.',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                )
              : _buildSlider(
                  'Duration',
                  '$_durationHours hours',
                  _durationHours.toDouble(),
                  1,
                  72,
                  (v) => setState(() => _durationHours = v.round()),
                ),
    );
  }

  // ── Run Button ─────────────────────────────────────────────

  Widget _buildRunButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return ElevatedButton(
            onPressed: _isRunning ? null : _runSimulation,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRunning
                  ? Colors.white10
                  : _typeColor.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isRunning
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _typeColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Computing...',
                          style: TextStyle(color: _typeColor, fontSize: 16)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Run Simulation',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SIMULATION EXECUTION
  // ═══════════════════════════════════════════════════════════════

  Future<void> _runSimulation() async {
    final lat = double.tryParse(_latController.text) ?? 37.7749;
    final lon = double.tryParse(_lonController.text) ?? -122.4194;

    setState(() => _isRunning = true);

    // Build config based on selected type
    Map<String, double> params;
    int duration;

    switch (_selectedType) {
      case SimulationType.wildfire:
        params = {
          'windSpeedKmh': _windSpeed,
          'windDirectionDeg': _windDirection,
          'humidity': _humidity,
          'temperature': _temperature,
          'fuelType': _fuelTypeIndex.toDouble(),
        };
        duration = _durationHours;
        break;
      case SimulationType.flood:
        params = {
          'waterLevelRise': _waterLevelRise,
          'radiusKm': _floodRadius,
        };
        duration = _durationHours;
        break;
      case SimulationType.seaLevelRise:
        params = {
          'seaLevelRiseM': _seaLevelRise,
          'radiusKm': _seaLevelRadius,
        };
        duration = 1;
        break;
      case SimulationType.drought:
        params = {
          'currentNDVI': _currentNDVI,
          'precipitationDeficitPercent': _precipDeficit,
          'monthsForward': _monthsForward,
          'radiusKm': 50.0,
        };
        duration = (_monthsForward * 30 * 24).round();
        break;
    }

    final config = SimulationConfig(
      type: _selectedType,
      lat: lat,
      lon: lon,
      parameters: params,
      durationHours: duration,
    );

    // Run in a microtask to allow UI to update
    await Future.delayed(const Duration(milliseconds: 100));

    final result = SimulationEngine.runSimulation(config);
    final report = SimulationEngine.generateReport(result);

    if (mounted) {
      setState(() {
        _result = result;
        _report = report;
        _isRunning = false;
        _currentFrameIndex = result.frames.isNotEmpty
            ? result.frames.length - 1
            : 0;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RESULTS VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildResultsView() {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back to config button
          GestureDetector(
            onTap: () => setState(() {
              _result = null;
              _report = null;
            }),
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios, color: _accent, size: 14),
                const SizedBox(width: 4),
                Text('New Simulation',
                    style: TextStyle(color: _accent, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            '${result.config.type.label} Results',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Computed at ${_formatTime(result.computedAt)}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Timeline scrubber
          if (result.frames.length > 1) ...[
            _buildTimelineScrubber(result),
            const SizedBox(height: 20),
          ],

          // Area expansion chart
          if (result.frames.length > 1) ...[
            _buildAreaChart(result),
            const SizedBox(height: 20),
          ],

          // Impact stats
          _buildImpactCards(result.impact),
          const SizedBox(height: 20),

          // Cascading impacts
          _buildSectionLabel('Cascading Impacts'),
          const SizedBox(height: 12),
          ...result.cascades.map(_buildCascadeCard),
          const SizedBox(height: 20),

          // Generate Report button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openReport,
              icon: const Icon(Icons.description, color: Colors.white),
              label: Text(
                'View Full Impact Report',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Timeline Scrubber ──────────────────────────────────────

  Widget _buildTimelineScrubber(SimulationResult result) {
    final frame = result.frames[_currentFrameIndex];
    final isDrought = result.config.type == SimulationType.drought;
    final timeLabel = isDrought
        ? 'Month ${(frame.hour / (24 * 30)).round()}'
        : 'Hour ${frame.hour}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(timeLabel,
                  style: TextStyle(color: _typeColor, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('${frame.areaKm2.toStringAsFixed(2)} km\u00B2',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _typeColor,
              thumbColor: _typeColor,
              inactiveTrackColor: Colors.white12,
              trackHeight: 4,
            ),
            child: Slider(
              value: _currentFrameIndex.toDouble(),
              min: 0,
              max: (result.frames.length - 1).toDouble(),
              divisions: result.frames.length - 1,
              onChanged: (v) => setState(() => _currentFrameIndex = v.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isDrought ? 'Month 0' : 'Hour 0',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              Text(
                isDrought
                    ? 'Month ${(result.frames.last.hour / (24 * 30)).round()}'
                    : 'Hour ${result.frames.last.hour}',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Area Expansion Chart ───────────────────────────────────

  Widget _buildAreaChart(SimulationResult result) {
    final spots = result.frames.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.areaKm2);
    }).toList();

    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Area Expansion',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: _typeColor,
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _typeColor.withValues(alpha: 0.15),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _cardBg,
                    getTooltipItems: (spots) => spots.map((s) {
                      return LineTooltipItem(
                        '${s.y.toStringAsFixed(2)} km\u00B2',
                        TextStyle(color: _typeColor, fontSize: 11),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Impact Stats Cards ─────────────────────────────────────

  Widget _buildImpactCards(ImpactAssessment impact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Impact Assessment'),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard(Icons.area_chart, 'Area',
                '${impact.areaAffectedKm2.toStringAsFixed(1)} km\u00B2', _typeColor),
            const SizedBox(width: 10),
            _buildStatCard(Icons.people, 'Population',
                SimulationEngine.generateReport(_result!).sections.first.stats[1].value, Colors.white),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildStatCard(Icons.local_hospital, 'Hospitals',
                '${impact.hospitalsAtRisk}', Colors.redAccent),
            const SizedBox(width: 10),
            _buildStatCard(Icons.school, 'Schools',
                '${impact.schoolsAtRisk}', Colors.amberAccent),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildStatCard(Icons.home, 'Structures',
                _formatCompact(impact.structuresAtRisk), Colors.white70),
            const SizedBox(width: 10),
            _buildStatCard(Icons.attach_money, 'Est. Loss',
                _formatCurrencyShort(impact.estimatedLossUSD), _accent),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cascade Card ───────────────────────────────────────────

  Widget _buildCascadeCard(CascadeEffect cascade) {
    Color severityColor;
    switch (cascade.severity) {
      case 'extreme':
        severityColor = const Color(0xFFDA3633);
        break;
      case 'high':
        severityColor = const Color(0xFFDB6D28);
        break;
      case 'moderate':
        severityColor = const Color(0xFFD29922);
        break;
      default:
        severityColor = const Color(0xFF56D364);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: severityColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  cascade.severity.toUpperCase(),
                  style: TextStyle(
                      color: severityColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(cascade.probability * 100).round()}% probability',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
              const Spacer(),
              Text(cascade.timeframe,
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Text(cascade.name,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(cascade.description,
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
          if (cascade.additionalLossUSD > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Additional loss: ${_formatCurrencyShort(cascade.additionalLossUSD)}',
              style: TextStyle(color: _typeColor, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.verified, color: _accent, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  cascade.citation,
                  style: TextStyle(
                    color: _accent.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // REPORT NAVIGATION
  // ═══════════════════════════════════════════════════════════════

  void _openReport() {
    if (_report == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactReportViewer(report: _report!),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FORMATTERS
  // ═══════════════════════════════════════════════════════════════

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} '
        '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatCompact(int n) {
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1e9) return '\$${(amount / 1e9).toStringAsFixed(1)}B';
    if (amount >= 1e6) return '\$${(amount / 1e6).toStringAsFixed(1)}M';
    if (amount >= 1e3) return '\$${(amount / 1e3).toStringAsFixed(1)}K';
    return '\$${amount.toStringAsFixed(0)}';
  }
}
