import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// ─────────────────────────────────────────────────────────────────
/// Atlas finding — an editorial analytical result from the Atlas GIS
/// agent, set as a printed research bulletin: kicker, headline, the
/// question that produced it, a two-series comparison chart, plain
/// language, and an honest provenance footer.
/// ─────────────────────────────────────────────────────────────────

// ── Defensive coercion ───────────────────────────────────────────
// Field values arrive from an agent over the wire. Every one of them
// may be absent, null, or the wrong type. Nothing here throws.

String _str(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

double _dbl(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : 0;
  }
  if (v is String) {
    final cleaned = v.trim().replaceAll(',', '').replaceAll(' ', '');
    final parsed = double.tryParse(cleaned);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return 0;
}

int? _intOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d.round() : null;
  }
  if (v is String) {
    final cleaned = v.trim().replaceAll(',', '').replaceAll('#', '');
    if (cleaned.isEmpty) return null;
    final asInt = int.tryParse(cleaned);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(cleaned);
    if (asDouble != null && asDouble.isFinite) return asDouble.round();
  }
  return null;
}

List<String> _strList(dynamic v) {
  if (v is String) {
    final one = v.trim();
    return one.isEmpty ? const <String>[] : <String>[one];
  }
  if (v is Iterable) {
    final out = <String>[];
    for (final e in v) {
      final s = _str(e);
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }
  return const <String>[];
}

/// Returns null when the agent supplied no usable timestamp. Never falls
/// back to DateTime.now(): stamping render time onto a finding would date
/// the analysis to the moment the reader opened the page.
DateTime? _dateOrNull(dynamic v) {
  if (v is DateTime) return v;
  if (v is num) {
    final ms = v.toDouble();
    if (ms.isFinite && ms > 0) {
      // Seconds or milliseconds — both are seen in the wild.
      final asMs = ms < 100000000000 ? ms * 1000 : ms;
      return DateTime.fromMillisecondsSinceEpoch(asMs.round());
    }
  }
  if (v is String) {
    final parsed = DateTime.tryParse(v.trim());
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), e));
  return const <String, dynamic>{};
}

/// One compared subject — a fire, a watershed, a district — carrying
/// its value in both series plus its rank in each.
class AtlasFindingRow {
  final String label;
  final String sublabel;
  final double primary;
  final double secondary;
  final String primaryText;
  final String secondaryText;
  final int? rankPrimary;
  final int? rankSecondary;

  const AtlasFindingRow({
    this.label = '',
    this.sublabel = '',
    this.primary = 0,
    this.secondary = 0,
    this.primaryText = '',
    this.secondaryText = '',
    this.rankPrimary,
    this.rankSecondary,
  });

  factory AtlasFindingRow.fromJson(Map<String, dynamic> json) {
    return AtlasFindingRow(
      label: _str(json['label']),
      sublabel: _str(json['sublabel']),
      primary: _dbl(json['primary']),
      secondary: _dbl(json['secondary']),
      primaryText: _str(json['primaryText']),
      secondaryText: _str(json['secondaryText']),
      rankPrimary: _intOrNull(json['rankPrimary']),
      rankSecondary: _intOrNull(json['rankSecondary']),
    );
  }
}

/// A complete finding: the judgment, the evidence, and its limits.
class AtlasFinding {
  final String id;
  final String kicker;
  final String headline;
  final String standfirst;
  final String question;
  final String primaryLabel;
  final String secondaryLabel;
  final List<AtlasFindingRow> rows;
  final List<String> paragraphs;
  final String reading;
  final String readingTag;
  final List<String> provenance;
  final List<String> limitations;
  /// When the agent produced this finding, or null when it did not say.
  final DateTime? generated;

  const AtlasFinding({
    this.generated,
    this.id = '',
    this.kicker = '',
    this.headline = '',
    this.standfirst = '',
    this.question = '',
    this.primaryLabel = '',
    this.secondaryLabel = '',
    this.rows = const <AtlasFindingRow>[],
    this.paragraphs = const <String>[],
    this.reading = '',
    this.readingTag = '',
    this.provenance = const <String>[],
    this.limitations = const <String>[],
  });

  factory AtlasFinding.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rows = <AtlasFindingRow>[];
    if (rawRows is Iterable) {
      for (final entry in rawRows) {
        if (entry is Map) {
          rows.add(AtlasFindingRow.fromJson(_asMap(entry)));
        }
      }
    }

    return AtlasFinding(
      id: _str(json['id']),
      kicker: _str(json['kicker']),
      headline: _str(json['headline']),
      standfirst: _str(json['standfirst']),
      question: _str(json['question']),
      primaryLabel: _str(json['primaryLabel']),
      secondaryLabel: _str(json['secondaryLabel']),
      rows: rows,
      paragraphs: _strList(json['paragraphs']),
      reading: _str(json['reading']),
      readingTag: _str(json['readingTag']),
      provenance: _strList(json['provenance']),
      limitations: _strList(json['limitations']),
      generated: _dateOrNull(json['generated']),
    );
  }
}

/// The bulletin itself.
class AtlasFindingCard extends StatelessWidget {
  final AtlasFinding finding;
  final VoidCallback? onDismiss;

  const AtlasFindingCard({super.key, required this.finding, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    // Series maxima, computed once — the bars are read against the
    // largest value in their own column, never across columns.
    double maxPrimary = 0;
    double maxSecondary = 0;
    for (final row in finding.rows) {
      if (row.primary > maxPrimary) maxPrimary = row.primary;
      if (row.secondary > maxSecondary) maxSecondary = row.secondary;
    }

    // The footer always renders. When the agent supplied no provenance the
    // card says so in as many words — an unsourced chart sitting silently
    // beside sourced material reads as sourced.

    return Container(
      decoration: EcoPaper.card,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 13, 15, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kickerRow(),
                if (finding.headline.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    finding.headline,
                    style: EcoPaper.headline(size: 24),
                    softWrap: true,
                  ),
                ],
                if (finding.standfirst.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    finding.standfirst,
                    style: EcoPaper.deck(
                      size: 15,
                    ).copyWith(fontStyle: FontStyle.italic),
                    softWrap: true,
                  ),
                ],
                if (finding.question.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  _questionWell(),
                ],
                if (finding.rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _chart(maxPrimary, maxSecondary),
                ],
                if (finding.paragraphs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _paragraphs(),
                ],
                if (finding.reading.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  _readingBlock(),
                ],
                const SizedBox(height: 15),
                _footer(),
              ],
            ),
          ),
          // The rule down the spine — a fire-deep margin mark.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: EcoPaper.fireDeep),
          ),
        ],
      ),
    );
  }

  // ── 1. Kicker ──────────────────────────────────────────────────
  Widget _kickerRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            finding.kicker.toUpperCase(),
            style: EcoPaper.label(
              color: EcoPaper.survey,
            ).copyWith(letterSpacing: 1.5),
            softWrap: true,
          ),
        ),
        if (finding.generated != null) ...[
          const SizedBox(width: 10),
          Text(
            _stamp(finding.generated!),
            style: EcoPaper.data(size: 10, color: EcoPaper.inkFaint),
            maxLines: 1,
          ),
        ],
        if (onDismiss != null)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 15),
              color: EcoPaper.inkFaint,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: 'Dismiss',
            ),
          ),
      ],
    );
  }

  // ── 4. The question that produced it ───────────────────────────
  Widget _questionWell() {
    return Container(
      decoration: EcoPaper.well,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('YOU ASKED', style: EcoPaper.label(size: 9)),
          const SizedBox(height: 5),
          Text(
            finding.question,
            style: EcoPaper.body(
              size: 12.5,
              color: EcoPaper.inkSoft,
            ).copyWith(fontStyle: FontStyle.italic),
            softWrap: true,
          ),
        ],
      ),
    );
  }

  // ── 5. The comparison chart ────────────────────────────────────
  Widget _chart(double maxPrimary, double maxSecondary) {
    final blocks = <Widget>[];
    for (var i = 0; i < finding.rows.length; i++) {
      if (i > 0) blocks.add(const SizedBox(height: 15));
      blocks.add(_chartRow(finding.rows[i], maxPrimary, maxSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _chartRow(AtlasFindingRow row, double maxPrimary, double maxSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _rowHeader(row),
        const SizedBox(height: 7),
        _bar(
          miniLabel: finding.primaryLabel,
          value: row.primary,
          max: maxPrimary,
          valueText: row.primaryText,
          fill: EcoPaper.inkFaint,
        ),
        const SizedBox(height: 4),
        _bar(
          miniLabel: finding.secondaryLabel,
          value: row.secondary,
          max: maxSecondary,
          valueText: row.secondaryText,
          fill: EcoPaper.fireDeep,
        ),
      ],
    );
  }

  Widget _rowHeader(AtlasFindingRow row) {
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            row.label,
            style: EcoPaper.body(
              size: 13.5,
            ).copyWith(fontWeight: FontWeight.w600),
            softWrap: true,
          ),
        ),
        if (row.sublabel.isNotEmpty) ...[
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              row.sublabel,
              style: EcoPaper.data(size: 11, color: EcoPaper.inkFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final shift = _rankShift(row);
    if (shift == null) return name;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow columns let the rank shift drop below the name
        // rather than fight it for the line.
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [name, const SizedBox(height: 3), shift],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: name),
            const SizedBox(width: 12),
            Flexible(child: shift),
          ],
        );
      },
    );
  }

  /// `Area #5 → Heat #1` — the whole point of the chart, in one line.
  /// Null on either side and the claim cannot be made, so it is not.
  Widget? _rankShift(AtlasFindingRow row) {
    final from = row.rankPrimary;
    final to = row.rankSecondary;
    if (from == null || to == null) return null;
    if (finding.primaryLabel.isEmpty && finding.secondaryLabel.isEmpty) {
      return null;
    }

    final climbed = to < from;
    final fell = to > from;
    final Color arrivalColor = climbed
        ? EcoPaper.fireDeep
        : fell
        ? EcoPaper.survey
        : EcoPaper.inkFaint;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${finding.primaryLabel} #$from',
            style: EcoPaper.data(size: 11, color: EcoPaper.inkSoft),
          ),
          TextSpan(
            text: '  →  ',
            style: EcoPaper.data(size: 11, color: EcoPaper.inkFaint),
          ),
          TextSpan(
            text: '${finding.secondaryLabel} #$to',
            style: EcoPaper.data(size: 11, color: arrivalColor).copyWith(
              fontWeight: climbed ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
      softWrap: true,
    );
  }

  Widget _bar({
    required String miniLabel,
    required double value,
    required double max,
    required String valueText,
    required Color fill,
  }) {
    final factor = (max <= 0 || value <= 0)
        ? 0.0
        : (value / max).clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 260;
        final labelWidth = tight ? 34.0 : 46.0;
        final valueWidth = tight ? 66.0 : 92.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(
                miniLabel.toUpperCase(),
                style: EcoPaper.label(size: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Container(
                height: 13,
                decoration: BoxDecoration(
                  color: EcoPaper.paperDeep,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: EcoPaper.rule),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: factor,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: valueWidth,
              child: Text(
                valueText,
                textAlign: TextAlign.right,
                style: EcoPaper.data(size: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  // ── 6. Body ────────────────────────────────────────────────────
  Widget _paragraphs() {
    final blocks = <Widget>[];
    for (var i = 0; i < finding.paragraphs.length; i++) {
      if (i > 0) blocks.add(const SizedBox(height: 10));
      blocks.add(
        Text(
          finding.paragraphs[i],
          style: EcoPaper.body(size: 14, color: EcoPaper.inkSoft),
          softWrap: true,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  // ── 7. Reading — marked as hypothesis, never as finding ────────
  Widget _readingBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EcoPaper.hairline,
        const SizedBox(height: 11),
        if (finding.readingTag.isNotEmpty) ...[
          Text(
            finding.readingTag,
            style: EcoPaper.label(
              color: EcoPaper.amber,
            ).copyWith(letterSpacing: 1.4),
            softWrap: true,
          ),
          const SizedBox(height: 6),
        ],
        Text(
          finding.reading,
          style: EcoPaper.deck(
            size: 14.5,
          ).copyWith(fontStyle: FontStyle.italic),
          softWrap: true,
        ),
      ],
    );
  }

  // ── 8. Provenance and limitations ──────────────────────────────
  Widget _footer() {
    final children = <Widget>[];

    children.add(Text('PROVENANCE', style: EcoPaper.label(size: 9)));
    children.add(const SizedBox(height: 5));
    if (finding.provenance.isEmpty) {
      children.add(
        Text(
          'Sources not supplied by the agent.',
          style: EcoPaper.body(size: 12, color: EcoPaper.amber),
          softWrap: true,
        ),
      );
    } else {
      for (var i = 0; i < finding.provenance.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 3));
        children.add(
          Text(
            finding.provenance[i],
            style: EcoPaper.body(size: 12, color: EcoPaper.inkSoft),
            softWrap: true,
          ),
        );
      }
    }

    if (finding.limitations.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 11));
      children.add(Text('LIMITATIONS', style: EcoPaper.label(size: 9)));
      children.add(const SizedBox(height: 5));
      for (var i = 0; i < finding.limitations.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 3));
        children.add(
          Text(
            '— ${finding.limitations[i]}',
            style: EcoPaper.body(size: 12, color: EcoPaper.inkSoft),
            softWrap: true,
          ),
        );
      }
    }

    return Container(
      decoration: EcoPaper.well,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  String _stamp(DateTime when) {
    final local = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
