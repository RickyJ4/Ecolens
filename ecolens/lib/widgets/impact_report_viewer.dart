import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/model/simulation_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// IMPACT REPORT VIEWER
// Displays structured simulation impact reports with cascading effects,
// data tables, risk badges, and citation verification.
// ═══════════════════════════════════════════════════════════════════════════

class ImpactReportViewer extends StatelessWidget {
  final ImpactReport report;

  const ImpactReportViewer({super.key, required this.report});

  // ── Palette ─────────────────────────────────────────────────
  static const _bg = Color(0xFF0A0E14);
  static const _cardBg = Color(0xFF1A1A2E);
  static const _accent = Color(0xFF00D26A);
  static const _citationGreen = Color(0xFF2EA043);

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
          report.title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70),
            tooltip: 'Copy to Clipboard',
            onPressed: () => _copyToClipboard(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Report header
          _buildReportHeader(),
          const SizedBox(height: 20),

          // Cascade chain visualization
          if (report.simulation.cascades.isNotEmpty) ...[
            _buildCascadeChainVisualization(),
            const SizedBox(height: 20),
          ],

          // Report sections
          ...report.sections.map(_buildSection),

          const SizedBox(height: 24),

          // Methodology note
          _buildMethodologyNote(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // REPORT HEADER
  // ═══════════════════════════════════════════════════════════════

  Widget _buildReportHeader() {
    final sim = report.simulation;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.assessment, color: _accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Generated ${_formatDateTime(report.generatedAt)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),
          _buildHeaderRow('Location',
              '${sim.config.lat.toStringAsFixed(4)}, ${sim.config.lon.toStringAsFixed(4)}'),
          _buildHeaderRow('Type', sim.config.type.label),
          _buildHeaderRow('Duration', '${sim.config.durationHours} hours'),
          _buildHeaderRow('Frames', '${sim.frames.length}'),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CASCADE CHAIN VISUALIZATION
  // Flow chart: Primary -> Secondary -> Tertiary
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCascadeChainVisualization() {
    final cascades = report.simulation.cascades;
    final primaryLabel = report.simulation.config.type.label;

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
          Text(
            'Cascade Chain',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Primary event node
          _buildChainNode(
            primaryLabel,
            'PRIMARY EVENT',
            _getPrimaryColor(),
            isRoot: true,
          ),

          // Secondary effects (directly caused by primary)
          ...cascades.asMap().entries.map((entry) {
            final cascade = entry.value;

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

            return Column(
              children: [
                // Connector line
                Row(
                  children: [
                    const SizedBox(width: 24),
                    Container(
                      width: 2,
                      height: 24,
                      color: Colors.white12,
                    ),
                  ],
                ),
                // Arrow indicator
                Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(Icons.subdirectory_arrow_right,
                        color: Colors.white24, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildChainNode(
                        cascade.name,
                        '${(cascade.probability * 100).round()}% | ${cascade.severity.toUpperCase()} | ${cascade.timeframe}',
                        severityColor,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChainNode(String title, String subtitle, Color color,
      {bool isRoot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isRoot ? 0.5 : 0.25),
          width: isRoot ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: isRoot ? 14 : 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: color, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getPrimaryColor() {
    switch (report.simulation.config.type) {
      case SimulationType.wildfire:
        return const Color(0xFFFF4500);
      case SimulationType.flood:
      case SimulationType.seaLevelRise:
        return const Color(0xFF1E90FF);
      case SimulationType.drought:
        return const Color(0xFFCC8400);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REPORT SECTIONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSection(ReportSection section) {
    final isCascade = section.heading.startsWith('Cascade:');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading with optional risk badge
          Row(
            children: [
              if (isCascade) ...[
                _buildRiskBadge(section),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  section.heading,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Body text
          Text(
            section.body,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          // Stats table
          if (section.stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildStatsTable(section.stats),
          ],

          // Citation
          if (section.citation != null) ...[
            const SizedBox(height: 12),
            _buildCitation(section.citation!),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskBadge(ReportSection section) {
    // Extract severity from cascade stats
    final severityStat = section.stats
        .where((s) => s.label == 'Severity')
        .toList();
    final severity = severityStat.isNotEmpty
        ? severityStat.first.value.toLowerCase()
        : 'low';

    Color badgeColor;
    switch (severity) {
      case 'extreme':
        badgeColor = const Color(0xFFDA3633);
        break;
      case 'high':
        badgeColor = const Color(0xFFDB6D28);
        break;
      case 'moderate':
        badgeColor = const Color(0xFFD29922);
        break;
      default:
        badgeColor = const Color(0xFF56D364);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: badgeColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Stats Table ────────────────────────────────────────────

  Widget _buildStatsTable(List<StatRow> stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: stats.asMap().entries.map((entry) {
          final stat = entry.value;
          final isLast = entry.key == stats.length - 1;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(
                      bottom: BorderSide(color: Colors.white10, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    stat.label,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        stat.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (stat.unit != null) ...[
                        const SizedBox(width: 4),
                        Text(stat.unit!,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                      ],
                      if (stat.change != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: stat.change!.startsWith('+')
                                ? const Color(0xFFDA3633).withValues(alpha: 0.15)
                                : _accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stat.change!,
                            style: TextStyle(
                              color: stat.change!.startsWith('+')
                                  ? const Color(0xFFDA3633)
                                  : _accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Citation Badge ─────────────────────────────────────────

  Widget _buildCitation(String citation) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _citationGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _citationGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: _citationGreen, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              citation,
              style: TextStyle(
                color: _citationGreen.withValues(alpha: 0.9),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // METHODOLOGY NOTE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMethodologyNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(
                'Methodology & Limitations',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'This simulation uses simplified models for rapid scenario '
            'assessment. Results are estimates intended for planning purposes '
            'and should be validated against local data, high-resolution DEMs, '
            'and ground-truth observations before operational use.\n\n'
            'Fire spread: Simplified Rothermel (1972) with cellular automata '
            'on a 50m grid. Fuel models from Anderson (1982).\n'
            'Flood: Simplified HAND model with synthetic terrain.\n'
            'Sea level rise: Bathtub model without hydrological connectivity.\n'
            'Drought: NDVI-precipitation deficit regression.\n'
            'Population: Distance-decay model from urban centers.\n'
            'Economic loss: World Bank GRADE methodology (2024).\n'
            'Cascading impacts: Probabilities from cited peer-reviewed literature.',
            style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════

  void _copyToClipboard(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('=== ${report.title} ===');
    buffer.writeln('Generated: ${_formatDateTime(report.generatedAt)}');
    buffer.writeln();

    for (final section in report.sections) {
      buffer.writeln('--- ${section.heading} ---');
      buffer.writeln(section.body);
      buffer.writeln();
      for (final stat in section.stats) {
        buffer.write('  ${stat.label}: ${stat.value}');
        if (stat.unit != null) buffer.write(' ${stat.unit}');
        if (stat.change != null) buffer.write(' (${stat.change})');
        buffer.writeln();
      }
      if (section.citation != null) {
        buffer.writeln('  Source: ${section.citation}');
      }
      buffer.writeln();
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Report copied to clipboard'),
        backgroundColor: _accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FORMATTERS
  // ═══════════════════════════════════════════════════════════════

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
