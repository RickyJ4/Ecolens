import 'package:flutter/material.dart';
import 'package:ecolens/core/gis_theme.dart';

/// Professional GIS-style compact data table
class GISDataTable extends StatelessWidget {
  final List<GISDataRow> rows;
  final String? title;
  final Widget? trailing;

  const GISDataTable({
    super.key,
    required this.rows,
    this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: GISTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: GISTheme.tableHeaderDecoration,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: GISTheme.labelSmall.copyWith(
                        color: GISTheme.textLabel,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ...rows.asMap().entries.map((entry) {
            final isLast = entry.key == rows.length - 1;
            return Container(
              padding: GISTheme.tableCellPadding,
              decoration: isLast
                  ? null
                  : GISTheme.tableRowDecoration,
              child: entry.value,
            );
          }),
        ],
      ),
    );
  }
}

/// Individual row in GIS data table
class GISDataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Widget? trailing;

  const GISDataRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: GISTheme.textTertiary),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: GISTheme.bodySmall.copyWith(
              color: GISTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: GISTheme.bodyMedium.copyWith(
                    color: valueColor ?? GISTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact metric card for GIS interface
class GISMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? subtitle;

  const GISMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: GISTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: color ?? GISTheme.accentBlue,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GISTheme.labelSmall.copyWith(
                    color: GISTheme.textLabel,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GISTheme.headingMedium.copyWith(
              color: color ?? GISTheme.textPrimary,
              fontSize: 16,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GISTheme.bodySmall.copyWith(
                color: GISTheme.textTertiary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Section header for GIS panels
class GISSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  const GISSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: GISTheme.accentBlue),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: GISTheme.headingSmall.copyWith(
                color: GISTheme.textPrimary,
                letterSpacing: 1,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Status badge for risk levels, availability, etc.
class GISStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;

  const GISStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: (compact ? GISTheme.labelSmall : GISTheme.label).copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Grid layout for compact metric cards
class GISMetricGrid extends StatelessWidget {
  final List<GISMetricCard> metrics;
  final int crossAxisCount;

  const GISMetricGrid({
    super.key,
    required this.metrics,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.5,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) => metrics[index],
    );
  }
}

/// Two-column layout for data tables
class GISTwoColumnLayout extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double spacing;

  const GISTwoColumnLayout({
    super.key,
    required this.left,
    required this.right,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: spacing),
        Expanded(child: right),
      ],
    );
  }
}

/// Professional empty state for GIS panels
class GISEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const GISEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: GISTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GISTheme.headingMedium.copyWith(
                color: GISTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GISTheme.bodySmall.copyWith(
                color: GISTheme.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
