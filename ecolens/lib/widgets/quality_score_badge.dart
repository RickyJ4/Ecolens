import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:ecolens/core/gis_theme.dart';
import 'package:ecolens/model/cartographic_intelligence_models.dart';

/// Compact quality score badge that expands to show dimension breakdown.
class QualityScoreBadge extends StatefulWidget {
  final CartographicQualityReport report;
  final bool compact;

  const QualityScoreBadge({
    super.key,
    required this.report,
    this.compact = true,
  });

  @override
  State<QualityScoreBadge> createState() => _QualityScoreBadgeState();
}

class _QualityScoreBadgeState extends State<QualityScoreBadge> {
  bool _expanded = false;

  Color get _scoreColor {
    final score = widget.report.overallScore;
    if (score >= 90) return GISTheme.accentGreen;
    if (score >= 70) return GISTheme.accentYellow;
    if (score >= 50) return GISTheme.accentOrange;
    return GISTheme.accentRed;
  }

  String get _scoreLabel {
    final score = widget.report.overallScore;
    if (score >= 90) return 'Excellent';
    if (score >= 80) return 'Good';
    if (score >= 70) return 'Acceptable';
    if (score >= 50) return 'Needs Work';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactBadge();
    }
    return _buildExpandedCard();
  }

  Widget _buildCompactBadge() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: GISTheme.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _scoreColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildScoreCircle(36),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _scoreLabel,
                        style: GISTheme.headingSmall.copyWith(
                          color: _scoreColor,
                        ),
                      ),
                      Text(
                        widget.report.passed ? 'Publication-ready' : 'Review needed',
                        style: GISTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: GISTheme.textTertiary,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_expanded) _buildDimensionBreakdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard() {
    return Container(
      decoration: GISTheme.panelDecoration,
      padding: GISTheme.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildScoreCircle(56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cartographic Quality', style: GISTheme.headingMedium),
                    const SizedBox(height: 4),
                    Text(
                      _scoreLabel,
                      style: GISTheme.bodyMedium.copyWith(color: _scoreColor),
                    ),
                    if (widget.report.violationCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${widget.report.violationCount} issue${widget.report.violationCount == 1 ? '' : 's'} detected',
                        style: GISTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDimensionBreakdown(),
        ],
      ),
    );
  }

  Widget _buildScoreCircle(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          score: widget.report.overallScore,
          color: _scoreColor,
          backgroundColor: GISTheme.border,
        ),
        child: Center(
          child: Text(
            '${widget.report.overallScore.round()}',
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: _scoreColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDimensionBreakdown() {
    final dimensions = widget.report.dimensions;
    if (dimensions.isEmpty) return const SizedBox.shrink();

    final dimNames = {
      'visual_hierarchy': 'Visual Hierarchy',
      'color_theory': 'Color Theory',
      'typography': 'Typography',
      'layout': 'Layout',
      'generalization': 'Generalization',
      'data_integrity': 'Data Integrity',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: dimensions.entries.map((entry) {
          final label = dimNames[entry.key] ?? entry.key;
          final score = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    label,
                    style: GISTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: score / 100.0,
                      backgroundColor: GISTheme.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _colorForScore(score),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${score.round()}',
                    style: GISTheme.labelSmall.copyWith(
                      color: _colorForScore(score),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _colorForScore(double score) {
    if (score >= 90) return GISTheme.accentGreen;
    if (score >= 70) return GISTheme.accentYellow;
    if (score >= 50) return GISTheme.accentOrange;
    return GISTheme.accentRed;
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double score;
  final Color color;
  final Color backgroundColor;

  _ScoreRingPainter({
    required this.score,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 3;
    const strokeWidth = 4.0;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Score arc
    final scorePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (score / 100.0) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) {
    return old.score != score || old.color != color;
  }
}
