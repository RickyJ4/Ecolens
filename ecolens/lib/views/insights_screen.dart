import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ecolens/core/theme.dart';
import 'package:ecolens/core/responsive_layout.dart';
import 'package:ecolens/model/location_model.dart';
import 'package:ecolens/viewmodels/dashboard_viewmodel.dart';
import 'package:ecolens/viewmodels/InsightsViewModel.dart';
import 'package:ecolens/viewmodels/hazard_viewmodel.dart';
import 'package:ecolens/viewmodels/navigation_viewmodel.dart';
import 'package:ecolens/model/hazard_models.dart';
import 'package:ecolens/views/widgets/atlas_finding_card.dart';

/// ─────────────────────────────────────────────────────────
/// INSIGHTS — one newsletter over the whole feed.
/// ─────────────────────────────────────────────────────────

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _isGeneratingShare = false;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  Widget build(BuildContext context) {
    return Consumer<InsightsViewModel>(
      builder: (context, vm, child) {
        if (vm.activeAlert != null) {
          return _buildDetailedReport(context, vm);
        }
        final hazardVm = context.watch<HazardViewModel>();
        final dashboardVm = context.watch<DashboardViewModel>();
        return _buildInsightsDashboard(vm, hazardVm, dashboardVm);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ENVIRONMENTAL INTELLIGENCE DASHBOARD
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // DATA INTEGRITY POLICY
  //
  // Every insight MUST satisfy one of these criteria:
  //   1. OBSERVED — derived directly from loaded hazard data (count, sum, mean)
  //   2. PEER-REVIEWED — a published scientific finding with citation
  //   3. PROJECTION — clearly labeled, with methodology stated
  //   4. UNAVAILABLE — data not loaded; show "No data" instead of guessing
  //
  // NEVER fabricate numbers. NEVER present simulated values as real.
  // ═══════════════════════════════════════════════════════════════

  /// Generates a situation summary ONLY from actual loaded hazard data.
  /// Returns 'noData: true' when insufficient data is available.
  Map<String, dynamic> _generateSituationSummary(HazardViewModel hazardVm) {
    final fireData = hazardVm.hazardData[HazardType.wildfire] ?? [];
    final floodData = hazardVm.hazardData[HazardType.flood] ?? [];
    final droughtData = hazardVm.hazardData[HazardType.drought] ?? [];
    final glacierData = hazardVm.hazardData[HazardType.glacier] ?? [];
    final ndviData = hazardVm.hazardData[HazardType.ndvi] ?? [];

    final int activeFires = fireData.length;
    final int activeFloods = floodData.length;
    final int glacierCount = glacierData.length;
    final bool hasDrought = droughtData.isNotEmpty;
    final bool hasNdvi = ndviData.isNotEmpty;
    final bool hasAnyData =
        activeFires > 0 ||
        activeFloods > 0 ||
        hasDrought ||
        hasNdvi ||
        glacierCount > 0;

    if (!hasAnyData) {
      return {
        'summary':
            'No hazard data loaded. Open the map and enable hazard layers '
            'to populate the intelligence feed with verified real-time data.',
        'riskLevel': 'UNKNOWN',
        'activeFires': 0,
        'activeFloods': 0,
        'glacierCount': 0,
        'hasDrought': false,
        'hasNdvi': false,
        'noData': true,
        'sources': <String>[],
      };
    }

    // Risk level derived ONLY from actual counts
    String riskLevel = 'LOW';
    if (activeFires > 100 || activeFloods > 2) riskLevel = 'MODERATE';
    if (activeFires > 500 || activeFloods > 5) riskLevel = 'ELEVATED';
    if (activeFires > 1000 || activeFloods > 10) riskLevel = 'HIGH';

    // Build summary from ONLY what we actually have
    final parts = <String>[];
    final sources = <String>[];

    if (activeFires > 0) {
      parts.add('$activeFires active fire detections');
      sources.add('NASA FIRMS / NIFC');
    }
    if (activeFloods > 0) {
      parts.add('$activeFloods flood gauge alerts');
      sources.add('NOAA NWPS');
    }
    if (hasDrought) {
      parts.add('Drought conditions detected');
      sources.add('US Drought Monitor');
    }
    if (glacierCount > 0) {
      parts.add('$glacierCount glaciers monitored');
      sources.add('GLIMS');
    }
    if (hasNdvi) {
      parts.add('Vegetation monitoring active');
      sources.add('MODIS / Sentinel-2');
    }

    final summary =
        'Current conditions: ${parts.join('. ')}. '
        'Overall assessed risk: $riskLevel.';

    return {
      'summary': summary,
      'riskLevel': riskLevel,
      'activeFires': activeFires,
      'activeFloods': activeFloods,
      'glacierCount': glacierCount,
      'hasDrought': hasDrought,
      'hasNdvi': hasNdvi,
      'noData': false,
      'sources': sources,
    };
  }



  Widget _buildInsightsDashboard(
    InsightsViewModel vm,
    HazardViewModel hazardVm,
    DashboardViewModel dashboardVm,
  ) {
    final situationData = _generateSituationSummary(hazardVm);
    final scopedNodes = _scopedInsightNodes(vm);
    final hasAnyLoadedData =
        scopedNodes.isNotEmpty || (situationData['noData'] != true);

    return Scaffold(
      backgroundColor: EcoPaper.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: EcoPaper.ink,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.newspaper, color: EcoPaper.survey, size: 18),
            const SizedBox(width: 8),
            Text(
              "ENVIRONMENTAL NEWS",
              style: EcoPaper.label(size: 12, color: EcoPaper.ink),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: vm.isLoading && !hasAnyLoadedData
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: EcoPaper.survey),
                  const SizedBox(height: 16),
                  Text(
                    'Loading the feed…',
                    style: EcoPaper.body(
                      color: EcoPaper.inkSoft,
                      size: 13,
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return WebConstrainedBox(
                  maxWidth: 1180,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // System notice first, then the masthead, then the page.
                      if (vm.isAnalysisSlow || vm.analysisError != null)
                        _buildAnalysisStatusBanner(vm),
                      _buildInsightsHero(scopedNodes, vm),
                      const SizedBox(height: 18),
                      if (dashboardVm.scopedPlaceId != null)
                        _buildPlaceScopeBanner(dashboardVm),
                      // A reader sent here by Ask-the-Map came for one answer.
                      // It leads the page, directly under the masthead.
                      ..._buildAtlasFindings(vm),
                      _buildNewsFeed(scopedNodes, vm),
                      const SizedBox(height: 18),
                      _buildAreaContext(scopedNodes, hazardVm),
                      const SizedBox(height: 18),
                      _buildEvidenceAndCoverage(situationData, vm),
                      const SizedBox(height: 18),
                      _buildNextSteps(scopedNodes, hazardVm),
                      const SizedBox(height: 36),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Findings escalated from Ask-the-Map. The map answers what it can show;
  /// questions needing a ranked comparison, its sources and its limits land
  /// here, laid out properly. Renders nothing when none have been asked.
  List<Widget> _buildAtlasFindings(InsightsViewModel vm) {
    if (vm.atlasFindings.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.travel_explore, size: 15, color: EcoPaper.survey),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'ANSWERED FROM THE MAP',
                style: EcoPaper.label(
                  size: 10,
                  color: EcoPaper.survey,
                ).copyWith(letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
      for (final finding in vm.atlasFindings) ...[
        AtlasFindingCard(
          finding: finding,
          onDismiss: () => vm.dismissAtlasFinding(finding.id),
        ),
        const SizedBox(height: 14),
      ],
      const SizedBox(height: 6),
    ];
  }

  /// The feed is the live GDACS mirror only. The Dashboard view-model's
  /// hotspot archive is never used here: it is a static, model-written
  /// collection whose oldest entries date from February, and it used to take
  /// precedence over the live feed whenever it was non-empty.
  List<IntelligenceNode> _scopedInsightNodes(InsightsViewModel vm) {
    return vm.allAlerts;
  }

  /// Banner shown when the reader arrived from a documented place
  /// (story pin → "See the numbers" deep link). It names the investigation
  /// and links back to it. It does NOT scope the feed below: the page is one
  /// newsletter over everything EcoLens is tracking.
  Widget _buildPlaceScopeBanner(DashboardViewModel dashboardVm) {
    final name = dashboardVm.scopedPlaceName ?? 'Documented place';
    final dek = dashboardVm.scopedPlaceDek;
    final storyUrl = dashboardVm.scopedPlaceStoryUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: EcoPaper.survey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: EcoPaper.survey.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.push_pin,
                  color: EcoPaper.survey, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FROM A STORY',
                    style: EcoPaper.label(
                      size: 9,
                      color: EcoPaper.survey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: EcoPaper.headline(
                      size: 14.5,
                      color: EcoPaper.ink,
                    ),
                  ),
                  if (dek != null && dek.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      dek,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EcoPaper.body(
                        color: EcoPaper.inkSoft,
                        size: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'You arrived from this investigation. The feed below '
                    'covers every case EcoLens is tracking, not just this '
                    'place.',
                    style: EcoPaper.body(
                      color: EcoPaper.inkFaint,
                      size: 11.5,
                    ),
                  ),
                  if (storyUrl != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        // Same-tab navigation on web (mirrors CommunityScreen).
                        final uri = Uri.base.resolve(storyUrl);
                        try {
                          await launchUrl(uri, webOnlyWindowName: '_self');
                        } catch (e) {
                          debugPrint('[Insights] launchUrl failed: $e');
                        }
                      },
                      child: Text(
                        'Read the investigation →',
                        style: EcoPaper.body(
                          color: EcoPaper.survey,
                          size: 12,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close,
                  color: EcoPaper.inkFaint, size: 18),
              onPressed: () => dashboardVm.clearPlaceScope(),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a status banner when deep analysis is slow or has errored.
  /// Driven by InsightsViewModel.isAnalysisSlow (set after 8s) and
  /// InsightsViewModel.analysisError (set on timeout/failure).
  Widget _buildAnalysisStatusBanner(InsightsViewModel vm) {
    final isError = vm.analysisError != null;
    final color = isError ? EcoPaper.amber : EcoPaper.survey;
    final icon = isError ? Icons.warning_amber_rounded : Icons.hourglass_top;
    final message = vm.analysisError ??
        'Analysis taking longer than usual — the server is warming up. Hang tight.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: isError ? vm.dismissAnalysisError : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: EcoPaper.body(
                      color: EcoPaper.ink,
                      size: 13,
                    ),
                  ),
                ),
                if (isError)
                  const Icon(Icons.close, color: EcoPaper.inkSoft, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightsHero(
    List<IntelligenceNode> scopedNodes,
    InsightsViewModel vm,
  ) {
    final topNode = _leadNode(scopedNodes);
    final String summary;
    if (topNode == null) {
      summary = vm.newsError != null
          ? 'The live feed is unavailable right now. ${vm.newsError}'
          : 'Waiting for the first refresh of the GDACS alert wire. '
              'Alerts appear here as soon as the server mirror runs.';
    } else {
      summary = 'Leading the wire: ${topNode.headline}. ${_feedScopeSentence(vm)}';
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: EcoPaper.paperDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: EcoPaper.rule),
                ),
                child: const Icon(Icons.newspaper, color: EcoPaper.survey),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Environmental News',
                      style: EcoPaper.headline(size: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The GDACS alert wire, refreshed every 15 minutes, and answers carried over from the map.',
                      style: EcoPaper.body(
                        color: EcoPaper.inkSoft,
                        size: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            summary,
            style: EcoPaper.deck(size: 14),
          ),
        ],
      ),
    );
  }


  /// Replaces the previous "Who can use this" marketing cards with real
  /// area context derived from the loaded hazard data + scoped nodes.
  /// Every number on this panel is computed from data, not hardcoded.
  Widget _buildAreaContext(
    List<IntelligenceNode> scopedNodes,
    HazardViewModel hazardVm,
  ) {
    // Hazard activity (counts per type currently loaded)
    final fireCount = (hazardVm.hazardData[HazardType.wildfire] ?? []).length;
    final floodCount = (hazardVm.hazardData[HazardType.flood] ?? []).length;
    final droughtCount = (hazardVm.hazardData[HazardType.drought] ?? []).length;
    final glacierCount = (hazardVm.hazardData[HazardType.glacier] ?? []).length;
    final ndviCount = (hazardVm.hazardData[HazardType.ndvi] ?? []).length;
    final totalHazards = fireCount + floodCount + droughtCount + glacierCount + ndviCount;

    // Dominant hazard type in this scope
    final hazardCounts = <String, int>{
      'wildfire': fireCount,
      'flood': floodCount,
      'drought': droughtCount,
      'glacier': glacierCount,
      'vegetation stress': ndviCount,
    };
    final dominantEntry = hazardCounts.entries
        .where((e) => e.value > 0)
        .fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        );

    // Only surface counts of live, source-attached hazard layers. Synthetic
    // stats (population aggregated from nearest-place estimates, largest
    // hectares, geographic spread) reach the user as if they were ground
    // truth and they are not.
    final factCards = <_AreaContextFact>[
      _AreaContextFact(
        icon: Icons.sensors,
        label: 'Live hazard signals',
        value: '$totalHazards',
        sub: totalHazards == 0
            ? 'No live hazard layers loaded. Open the map and enable layers.'
            : [
                if (fireCount > 0) '$fireCount fire',
                if (floodCount > 0) '$floodCount flood',
                if (droughtCount > 0) '$droughtCount drought',
                if (glacierCount > 0) '$glacierCount glacier',
                if (ndviCount > 0) '$ndviCount NDVI',
              ].join(' · '),
        color: EcoPaper.survey,
      ),
      if (dominantEntry != null)
        _AreaContextFact(
          icon: Icons.trending_up,
          label: 'Dominant signal',
          value: dominantEntry.key,
          sub:
              '${dominantEntry.value} of $totalHazards loaded signals are ${dominantEntry.key} events.',
          color: EcoPaper.amber,
        ),
    ];

    if (factCards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          Icons.layers_outlined,
          'Loaded on the map',
          'Counted from the hazard layers currently loaded on the map.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 820 && factCards.length > 1;
            if (isWide) {
              final cellWidth = (constraints.maxWidth - 10) / factCards.length;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: factCards
                    .map((f) => SizedBox(
                          width: cellWidth,
                          child: _areaContextCard(f),
                        ))
                    .toList(),
              );
            }
            return Column(
              children: [
                for (final f in factCards) ...[
                  _areaContextCard(f),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _areaContextCard(_AreaContextFact f) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(f.icon, color: f.color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.label.toUpperCase(),
                  style: EcoPaper.label(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            f.value,
            style: EcoPaper.data(size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            f.sub,
            style: EcoPaper.body(
              color: EcoPaper.inkSoft,
              size: 12,
            ),
          ),
        ],
      ),
    );
  }


  /// The wire. Items arrive pre-ordered from Firestore (Red, Orange, Green;
  /// newest activity first within each level), so the order here is the
  /// order the feed delivered.
  Widget _buildNewsFeed(
    List<IntelligenceNode> nodes,
    InsightsViewModel vm,
  ) {
    final sorted = _orderedCases(nodes);
    final visible = sorted.take(10).toList();
    // The stream is capped at 120 documents; the meta document carries the
    // true total so the "more" line never under-counts.
    final total = vm.newsCount > sorted.length ? vm.newsCount : sorted.length;
    final updated = vm.newsUpdatedAt;

    return _insightsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.rss_feed,
            'Latest alerts',
            'Red, then orange, then green; the most recently updated first. '
                'Tap an item for the published report.',
          ),
          if (updated != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 27),
              child: Text(
                'Refreshed ${_timeAgo(updated)} · '
                '${DateFormat('d MMM, HH:mm').format(updated.toLocal())} local',
                style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
              ),
            ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            _emptyState(
              icon: Icons.notifications_none,
              title: vm.newsError != null
                  ? 'The wire could not be read'
                  : 'Nothing on the wire yet',
              body: vm.newsError ??
                  'The server mirrors the GDACS alert feed every 15 minutes. '
                      'If this persists, the refresh job has not run.',
            )
          else ...[
            // Stories lead; alerts the server has not composed a story for
            // yet (mostly green wildfires) keep the compact card.
            for (var i = 0; i < visible.length; i++)
              _article(visible[i]) == null
                  ? _newsItemCard(visible[i], vm)
                  : (i == 0
                      ? _newsLead(visible[i], vm)
                      : _newsTeaser(visible[i], vm)),
          ],
          if (total > visible.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${total - visible.length} more on the wire.',
                style: GoogleFonts.inter(color: EcoPaper.inkFaint, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// One wire item. Everything on it is a field GDACS published: the alert
  /// level, the event type, the headline assembled from its own name and
  /// country, its severity statement, and when it was last updated.
  Widget _newsItemCard(IntelligenceNode node, InsightsViewModel vm) {
    final c = node.causeData;
    final level = (c['alert_level'] ?? '').toString();
    final typeLabel = (c['type_label'] ?? node.type).toString();
    final severity = _publishedSeverity(node);
    final lastActivity =
        DateTime.tryParse((c['last_activity'] ?? '').toString());
    final isCurrent = c['is_current'] == true;
    final metaBits = <String>[
      if (node.country.isNotEmpty) node.country,
      if (severity.isNotEmpty) severity,
    ];
    final String when;
    if (lastActivity == null) {
      when = '';
    } else if (isCurrent) {
      when = 'Active · updated ${_timeAgo(lastActivity)}';
    } else {
      when = 'Closed · last update ${_timeAgo(lastActivity)}';
    }
    final who = _whoIsAffectedLine(node);
    final facts = _factsLine(node);

    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        vm.openNewsItem(node);
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: EcoPaper.well,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: EcoPaper.paperRaised,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: EcoPaper.rule),
              ),
              child: Icon(_nodeIcon(node), color: _alertColor(level), size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (level.isNotEmpty)
                        _tinyBadge(
                          '${level.toUpperCase()} ALERT',
                          _alertColor(level),
                        ),
                      _tinyBadge(typeLabel.toUpperCase(), EcoPaper.survey),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    node.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: EcoPaper.headline(size: 14),
                  ),
                  if (metaBits.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      metaBits.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EcoPaper.body(
                        color: EcoPaper.inkSoft,
                        size: 12,
                      ),
                    ),
                  ],
                  if (when.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      when,
                      style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
                    ),
                  ],
                  if (who.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      'WHO IS AFFECTED',
                      style: EcoPaper.label(size: 9, color: EcoPaper.inkFaint),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      who,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EcoPaper.body(color: EcoPaper.ink, size: 12.5),
                    ),
                  ],
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      facts,
                      style: EcoPaper.data(size: 11, color: EcoPaper.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _cardButton(
                        Icons.article_outlined,
                        'Full report',
                        () => vm.openNewsItem(node),
                      ),
                      _cardButton(
                        Icons.map_outlined,
                        'View on map',
                        () => _viewOnMap(node),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// GDACS alert-level colour. Red and Orange are GDACS's own scale.
  Color _alertColor(String level) {
    switch (level.toLowerCase()) {
      case 'red':
        return EcoPaper.fire;
      case 'orange':
        return EcoPaper.amber;
      case 'green':
        return EcoPaper.okGreen;
      default:
        return EcoPaper.survey;
    }
  }

  bool _isNewsItem(IntelligenceNode node) =>
      node.causeData['source'] == 'GDACS';

  /// "3 min ago" / "2 h ago" / "4 d ago", then an absolute date. Never a
  /// month name on its own, so a stale item can never read as current.
  String _timeAgo(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return DateFormat('d MMM yyyy').format(t.toLocal());
  }

  /// Honest scope line: how many events, how many at the two higher levels,
  /// and when the mirror last ran. Every number comes from news_meta/latest.
  String _feedScopeSentence(InsightsViewModel vm) {
    if (vm.newsCount == 0) return '';
    final red = vm.newsByLevel['Red'] ?? 0;
    final orange = vm.newsByLevel['Orange'] ?? 0;
    final parts = <String>['${vm.newsCount} GDACS alerts on the wire'];
    if (red > 0 || orange > 0) parts.add('$red red and $orange orange');
    final updated = vm.newsUpdatedAt;
    if (updated != null) parts.add('refreshed ${_timeAgo(updated)}');
    return '${parts.join(', ')}.';
  }

  String _byLevelSentence(InsightsViewModel vm) {
    if (vm.newsByLevel.isEmpty) return 'Alert levels as published by GDACS.';
    final order = ['Red', 'Orange', 'Green'];
    final bits = [
      for (final k in order)
        if ((vm.newsByLevel[k] ?? 0) > 0) '${vm.newsByLevel[k]} ${k.toLowerCase()}',
    ];
    return '${bits.join(', ')}. Levels as published by GDACS.';
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Insights] launchUrl failed: $e');
    }
  }

  Widget _buildEvidenceAndCoverage(
    Map<String, dynamic> situationData,
    InsightsViewModel vm,
  ) {
    // Counts only the layers this tally actually sums. Drought and NDVI
    // reach situationData as booleans, so they are named in neither.
    final liveSignalCount =
        (situationData['activeFires'] as int? ?? 0) +
        (situationData['activeFloods'] as int? ?? 0) +
        (situationData['glacierCount'] as int? ?? 0);

    return _insightsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.dataset,
            'Where these numbers come from',
            'What is loaded, and what it is drawn from.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              final cards = [
                _coverageItem(
                  Icons.sensors,
                  'Live hazard layers',
                  NumberFormat.compact().format(liveSignalCount),
                  'Fire, flood and glacier signals currently loaded.',
                ),
                _coverageItem(
                  Icons.newspaper,
                  'GDACS alerts on the wire',
                  NumberFormat.compact().format(
                    vm.newsCount > 0 ? vm.newsCount : vm.allAlerts.length,
                  ),
                  _byLevelSentence(vm),
                ),
                _coverageItem(
                  Icons.update,
                  'Wire refreshed',
                  vm.newsUpdatedAt == null
                      ? 'Pending'
                      : _timeAgo(vm.newsUpdatedAt!),
                  'A scheduled job mirrors the GDACS RSS feed every 15 minutes; '
                      'this page updates the moment it writes.',
                ),
              ];

              if (isWide) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              }

              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNextSteps(
    List<IntelligenceNode> nodes,
    HazardViewModel hazardVm,
  ) {
    final recommendations = _recommendations(nodes, hazardVm);

    return _insightsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.route,
            'What to do next',
            'Three suggestions, based on what is loaded.',
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < recommendations.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == recommendations.length - 1 ? 0 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: EcoPaper.paperDeep,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: EcoPaper.rule),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: EcoPaper.data(
                        size: 12,
                        color: EcoPaper.survey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      recommendations[i],
                      style: EcoPaper.body(
                        color: EcoPaper.inkSoft,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _recommendations(
    List<IntelligenceNode> nodes,
    HazardViewModel hazardVm,
  ) {
    final recs = <String>[];
    final fireData = hazardVm.hazardData[HazardType.wildfire] ?? [];
    final floodData = hazardVm.hazardData[HazardType.flood] ?? [];
    final droughtData = hazardVm.hazardData[HazardType.drought] ?? [];
    final topNode = _leadNode(nodes);

    if (topNode != null) {
      recs.add(
        'Open "${topNode.headline}" for the GDACS report: alert level, severity and the published population statement.',
      );
    }

    recs.add(
      'On the map, turn on "Who is affected" and "Areas affected" to see the published impact figures and source geometry for the same events.',
    );

    if (fireData.isNotEmpty || floodData.isNotEmpty || droughtData.isNotEmpty) {
      recs.add(
        'The hazard layers you have loaded stay attached, so what is observed now sits beside what GDACS has reported.',
      );
    } else {
      recs.add(
        'Load fire, flood or drought layers on the map to put live detections beside these reports.',
      );
    }

    return recs.take(3).toList();
  }

  Widget _sectionHeader(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: EcoPaper.survey, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: EcoPaper.headline(size: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(color: EcoPaper.inkFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _insightsPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: EcoPaper.card,
      child: child,
    );
  }


  Widget _coverageItem(IconData icon, String label, String value, String body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: EcoPaper.well,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EcoPaper.survey, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EcoPaper.data(size: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: EcoPaper.survey,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  style: EcoPaper.body(
                    color: EcoPaper.inkSoft,
                    size: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: EcoPaper.well,
      child: Column(
        children: [
          Icon(icon, color: EcoPaper.inkFaint, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: EcoPaper.headline(size: 14),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: EcoPaper.body(
              color: EcoPaper.inkSoft,
              size: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Feed order for the case list. Cases whose source actually supplied a
  /// score sort first, highest first; everything else keeps the order the
  /// feed delivered it in. An absent score never sorts as if it were a
  /// middling one.
  List<IntelligenceNode> _orderedCases(List<IntelligenceNode> nodes) {
    final indexed = <MapEntry<int, IntelligenceNode>>[
      for (var i = 0; i < nodes.length; i++) MapEntry(i, nodes[i]),
    ];
    indexed.sort((a, b) {
      final aScored = a.value.riskScored;
      final bScored = b.value.riskScored;
      if (aScored != bScored) return aScored ? -1 : 1;
      if (aScored && bScored) {
        final byScore = b.value.riskScore.compareTo(a.value.riskScore);
        if (byScore != 0) return byScore;
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  IntelligenceNode? _leadNode(List<IntelligenceNode> nodes) {
    if (nodes.isEmpty) return null;
    return _orderedCases(nodes).first;
  }

  IconData _nodeIcon(IntelligenceNode node) {
    final value = '${node.type} ${node.headline}'.toLowerCase();
    if (value.contains('fire') || value.contains('burn')) {
      return Icons.local_fire_department;
    }
    if (value.contains('flood') || value.contains('water')) {
      return Icons.water_drop;
    }
    if (value.contains('drought')) return Icons.wb_sunny;
    if (value.contains('cyclone') || value.contains('hurricane') ||
        value.contains('typhoon')) {
      return Icons.cyclone;
    }
    if (value.contains('quake') || value.contains('seism')) {
      return Icons.vibration;
    }
    if (value.contains('volcan')) return Icons.volcano;
    if (value.contains('tsunami')) return Icons.tsunami;
    if (value.contains('glacier') || value.contains('ice')) {
      return Icons.ac_unit;
    }
    if (value.contains('forest') || value.contains('deforest')) {
      return Icons.forest;
    }
    return Icons.eco;
  }

  String _nodeLocation(IntelligenceNode node) {
    final parts = [
      node.region,
      node.provinceState,
      node.country,
    ].where((value) => value.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.first;
    return '${node.lat.toStringAsFixed(2)}, ${node.lng.toStringAsFixed(2)}';
  }













  // ═══════════════════════════════════════════════════════════════
  // DETAILED REPORT (Tabbed View)
  // ═══════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════
  // DETAILED REPORT — single-page intelligence brief
  // ───────────────────────────────────────────────────────────────
  // Replaces the legacy 12-tab structure (OVERVIEW · SENTINEL · RISK ·
  // SPATIAL · SOIL · TERRAIN · HYDROLOGY · FIRE · TRENDS · IMPACTS ·
  // SPECIES · ACTION). Most of those tabs rendered synthetic data with
  // no auditable source — replaced with one scrollable brief that
  // only shows verifiable fields and routes deeper analysis to the
  // map's intelligence drawer (OSM-verified, WRI cross-validated).
  // ═══════════════════════════════════════════════════════════════
  Widget _buildDetailedReport(BuildContext context, InsightsViewModel vm) {
    final node = vm.activeAlert!;
    // Wire items with a composed story read as an article; everything else
    // keeps the report layout.
    final story = _isNewsItem(node) ? _article(node) : null;
    if (story != null) return _buildStoryView(context, vm, node, story);
    final accent = _accentForType(node.type);

    return Scaffold(
      backgroundColor: EcoPaper.paper,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Hero header (back + share + title) ───
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: EcoPaper.paper,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              color: EcoPaper.ink,
              onPressed: vm.clearActiveAlert,
            ),
            actions: [
              IconButton(
                icon: _isGeneratingShare
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: EcoPaper.ink,
                        ),
                      )
                    : const Icon(Icons.share_outlined, color: EcoPaper.ink),
                onPressed: () => _shareInsight(node),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildBriefHero(node, accent),
            ),
          ),

          // ─── Body sections ───
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _briefSoWhat(node),
                const SizedBox(height: 22),
                if (_isNewsItem(node)) ...[
                  _briefNewsFacts(node),
                  const SizedBox(height: 22),
                  _briefWhoIsAffected(node),
                  const SizedBox(height: 22),
                  _briefMapsAndProducts(node),
                  const SizedBox(height: 22),
                ],
                if (_briefAtRiskHasContent(node)) ...[
                  _briefAtRisk(node),
                  const SizedBox(height: 22),
                ],
                if (node.recommendedActions.isNotEmpty) ...[
                  _briefRecommendedActions(node),
                  const SizedBox(height: 22),
                ],
                // Wire items carry their facts in the block above; the
                // detection block would only say "no metadata".
                if (!_isNewsItem(node)) ...[
                  _briefDetectionFacts(node),
                  const SizedBox(height: 22),
                ],
                _briefLocationContext(node),
                const SizedBox(height: 22),
                _briefFullIntelligenceCta(context, node),
                const SizedBox(height: 22),
                _briefSourcesAndMethod(node),
                const SizedBox(height: 22),
                _briefHonestNote(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Hero — type chip + title + location, no fabricated metrics
  // ──────────────────────────────────────────────────────────
  Widget _buildBriefHero(IntelligenceNode node, Color accent) {
    return Container(
      decoration: const BoxDecoration(
        color: EcoPaper.paperDeep,
        border: Border(
          bottom: BorderSide(color: EcoPaper.rule),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: EcoPaper.paperRaised,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: accent.withValues(alpha: 0.6)),
                ),
                child: Text(
                  '${node.type.toUpperCase()} · ${node.country.isNotEmpty ? node.country.toUpperCase() : 'UNKNOWN REGION'}',
                  style: EcoPaper.label(
                    size: 9.5,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                node.headline.isNotEmpty ? node.headline : _fallbackTitle(node),
                style: EcoPaper.headline(size: 22),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                _formatCoords(node.lat, node.lng),
                style: EcoPaper.data(
                  size: 11.5,
                  color: EcoPaper.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // SO WHAT — one sentence, computed honestly
  // ──────────────────────────────────────────────────────────
  Widget _briefSoWhat(IntelligenceNode node) {
    // Use the real narrative on the node when present, fall back to a
    // type-aware single sentence. The previous "Environmental signal detected
    // over X. Open the map brief..." copy was content-free boilerplate.
    final hasNarrative = node.backgroundInfo.trim().isNotEmpty;
    final body = hasNarrative
        ? node.backgroundInfo.trim()
        : _composeSoWhat(node);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(hasNarrative ? 'Background' : 'So what'),
          const SizedBox(height: 8),
          Text(
            body,
            style: EcoPaper.deck(size: 14, color: EcoPaper.ink),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // WIRE FACTS — the fields GDACS published for this alert, verbatim
  // ──────────────────────────────────────────────────────────
  Widget _briefNewsFacts(IntelligenceNode node) {
    final c = node.causeData;
    String s(String k) => (c[k] ?? '').toString().trim();
    String when(String k) {
      final t = DateTime.tryParse(s(k));
      return t == null
          ? ''
          : '${DateFormat('d MMM yyyy, HH:mm').format(t.toUtc())} UTC';
    }

    final rows = <Widget>[];
    if (s('alert_level').isNotEmpty) {
      rows.add(_factRow('Alert level', '${s('alert_level')} (GDACS scale)'));
    }
    if (s('type_label').isNotEmpty) rows.add(_factRow('Event', s('type_label')));
    if (s('event_name').isNotEmpty) rows.add(_factRow('Name', s('event_name')));
    final countries = c['affected_countries'];
    if (countries is List && countries.isNotEmpty) {
      final names = countries.map((e) => e.toString()).toList();
      final shown = names.length > 8
          ? '${names.take(8).join(', ')} and ${names.length - 8} more'
          : names.join(', ');
      rows.add(_factRow(
        names.length == 1 ? 'Country' : 'Countries (${names.length})',
        shown,
      ));
    }
    final days = c['duration_days'];
    if (days is int && days > 0) {
      rows.add(_factRow(
        'Duration',
        '$days day${days == 1 ? '' : 's'}, from the published dates',
      ));
    }
    final statement = _impactStatement(node);
    if (statement.isNotEmpty) {
      rows.add(_factRow('Impact, as published', statement));
    }
    final km2 = c['affected_area_km2'];
    if (km2 is num && km2 > 0) {
      final basis = s('affected_area_basis');
      rows.add(_factRow(
        'Affected area',
        basis.isEmpty ? _fmtKm2(km2) : '${_fmtKm2(km2)} ($basis)',
      ));
      final zones = c['affected_zones'];
      if (zones is List && zones.length > 1) {
        for (final z in zones) {
          if (z is Map && z['km2'] is num) {
            rows.add(_factRow('    ${z['label']}', _fmtKm2(z['km2'] as num)));
          }
        }
      }
    }
    final severity = _publishedSeverity(node);
    if (severity.isNotEmpty) {
      rows.add(_factRow('Severity, as published', severity));
    }
    if (s('glide').isNotEmpty) rows.add(_factRow('GLIDE number', s('glide')));
    if (s('population_text').isNotEmpty) {
      rows.add(_factRow('Population, as published', s('population_text')));
    }
    if (when('from_date').isNotEmpty) rows.add(_factRow('From', when('from_date')));
    if (when('to_date').isNotEmpty) rows.add(_factRow('To', when('to_date')));
    if (when('last_activity').isNotEmpty) {
      rows.add(_factRow('Last update', when('last_activity')));
    }
    rows.add(_factRow('Status', c['is_current'] == true ? 'Current' : 'Closed'));

    final url = s('url');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('From the wire'),
          const SizedBox(height: 10),
          ...rows,
          if (url.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _openExternal(url),
              child: Text(
                'Open the GDACS report →',
                style: EcoPaper.body(
                  color: EcoPaper.survey,
                  size: 12.5,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Every line above is copied from the GDACS alert. EcoLens adds '
            'nothing to it and does not combine it with other alerts.',
            style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // STORIES — the wire as readable articles. Composed server-side by
  // refresh_environmental_news from published fields only; each
  // paragraph carries the source it was assembled from.
  // ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _article(IntelligenceNode node) {
    final a = node.causeData['article'];
    if (a is Map && (a['headline'] ?? '').toString().trim().isNotEmpty) {
      return Map<String, dynamic>.from(a);
    }
    return null;
  }

  String _kicker(IntelligenceNode node) {
    final c = node.causeData;
    final level = (c['alert_level'] ?? '').toString();
    final type = (c['type_label'] ?? node.type).toString();
    return [
      if (level.isNotEmpty) '$level alert',
      type,
      if (node.country.isNotEmpty) node.country,
    ].join(' · ').toUpperCase();
  }

  String _readTime(Map<String, dynamic> a) {
    final w = a['word_count'];
    final words = w is num ? w.toInt() : 0;
    if (words <= 0) return '';
    return '${(words / 200).ceil()} min read';
  }

  String? _heroImage(IntelligenceNode node) {
    final c = node.causeData;
    for (final key in ['map_images', 'products']) {
      final list = c[key];
      if (list is! List) continue;
      for (final e in list) {
        if (e is Map) {
          final u = (e['url'] ?? e['image'] ?? '').toString();
          if (u.isNotEmpty) return u;
        }
      }
    }
    return null;
  }

  String _fmtStamp(dynamic iso) {
    final t = DateTime.tryParse((iso ?? '').toString());
    return t == null ? '' : '${DateFormat('d MMM HH:mm').format(t.toUtc())} UTC';
  }

  Widget _storyMeta(IntelligenceNode node, Map<String, dynamic> a,
      {double size = 10.5}) {
    final asOf = DateTime.tryParse((a['as_of'] ?? '').toString());
    final bits = <String>[
      if ((a['dateline'] ?? '').toString().isNotEmpty) a['dateline'].toString(),
      if (asOf != null) 'as of ${_timeAgo(asOf)}',
      if (_readTime(a).isNotEmpty) _readTime(a),
    ];
    return Text(
      bits.join(' · '),
      style: EcoPaper.data(size: size, color: EcoPaper.inkFaint),
    );
  }

  /// The lead story: map, kicker, headline, standfirst, meta, actions.
  Widget _newsLead(IntelligenceNode node, InsightsViewModel vm) {
    final a = _article(node)!;
    final hero = _heroImage(node);
    final level = (node.causeData['alert_level'] ?? '').toString();
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        vm.openNewsItem(node);
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: EcoPaper.well,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hero != null)
              _publishedImage(hero, 'Event map', 'GDACS', maxHeight: 260),
            Text(_kicker(node),
                style: EcoPaper.label(size: 9.5, color: _alertColor(level))),
            const SizedBox(height: 6),
            Text(a['headline'].toString(), style: EcoPaper.headline(size: 22)),
            const SizedBox(height: 8),
            Text((a['standfirst'] ?? '').toString(),
                style: EcoPaper.deck(size: 14.5)),
            _ecolensSummaryLine(a),
            const SizedBox(height: 8),
            _storyMeta(node, a),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _cardButton(Icons.article_outlined, 'Read the story',
                    () => vm.openNewsItem(node)),
                _cardButton(Icons.map_outlined, 'View on map',
                    () => _viewOnMap(node)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Every other story: kicker, headline, standfirst, meta.
  Widget _newsTeaser(IntelligenceNode node, InsightsViewModel vm) {
    final a = _article(node)!;
    final level = (node.causeData['alert_level'] ?? '').toString();
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        vm.openNewsItem(node);
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: EcoPaper.well,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_kicker(node),
                style: EcoPaper.label(size: 9, color: _alertColor(level))),
            const SizedBox(height: 5),
            Text(
              a['headline'].toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EcoPaper.headline(size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              (a['standfirst'] ?? '').toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: EcoPaper.body(color: EcoPaper.inkSoft, size: 13),
            ),
            _ecolensSummaryLine(a),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _storyMeta(node, a, size: 10)),
                TextButton(
                  onPressed: () => _viewOnMap(node),
                  child: Text(
                    'View on map',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: EcoPaper.survey,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The full article.
  Widget _buildStoryView(
    BuildContext context,
    InsightsViewModel vm,
    IntelligenceNode node,
    Map<String, dynamic> a,
  ) {
    final hero = _heroImage(node);
    final level = (node.causeData['alert_level'] ?? '').toString();
    final paragraphs = (a['paragraphs'] is List)
        ? (a['paragraphs'] as List).whereType<Map>().toList()
        : const <Map>[];

    return Scaffold(
      backgroundColor: EcoPaper.paper,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: EcoPaper.paper,
            foregroundColor: EcoPaper.ink,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              color: EcoPaper.ink,
              onPressed: vm.clearActiveAlert,
            ),
            title: Text('ENVIRONMENTAL NEWS',
                style: EcoPaper.label(size: 11, color: EcoPaper.ink)),
            actions: [
              IconButton(
                icon: _isGeneratingShare
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: EcoPaper.ink),
                      )
                    : const Icon(Icons.share_outlined, color: EcoPaper.ink),
                onPressed: () => _shareInsight(node),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                WebConstrainedBox(
                  maxWidth: 760,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_kicker(node),
                          style: EcoPaper.label(
                              size: 10, color: _alertColor(level))),
                      const SizedBox(height: 8),
                      Text(a['headline'].toString(),
                          style: EcoPaper.headline(size: 28)),
                      const SizedBox(height: 10),
                      Text((a['standfirst'] ?? '').toString(),
                          style: EcoPaper.deck(size: 16)),
                      const SizedBox(height: 10),
                      _storyMeta(node, a, size: 11),
                      const SizedBox(height: 4),
                      Text(
                        'Written from published GDACS records. Every paragraph '
                        'names the record it was assembled from.',
                        style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
                      ),
                      const SizedBox(height: 18),
                      if (hero != null) _publishedImage(hero, 'Event map', 'GDACS'),
                      for (final p in paragraphs) _storyParagraph(p),
                      // What EcoLens's own layers show around the event;
                      // nothing at all until the server has computed it.
                      _briefEcolensReading(node, vm),
                      const SizedBox(height: 10),
                      _briefNewsFacts(node),
                      const SizedBox(height: 22),
                      _briefWhoIsAffected(node),
                      const SizedBox(height: 22),
                      _briefTimeline(a),
                      const SizedBox(height: 22),
                      _briefPress(a),
                      const SizedBox(height: 22),
                      _briefMapsAndProducts(node),
                      const SizedBox(height: 22),
                      _briefFullIntelligenceCta(context, node),
                      const SizedBox(height: 22),
                      _briefSourcesAndMethod(node),
                      const SizedBox(height: 22),
                      _briefHonestNote(),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storyParagraph(Map p) {
    final text = (p['text'] ?? '').toString();
    final source = (p['source'] ?? '').toString();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: GoogleFonts.lora(
              fontSize: 15.5,
              height: 1.6,
              color: EcoPaper.ink,
            ),
          ),
          if (source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Source: $source',
                  style: EcoPaper.data(size: 10, color: EcoPaper.inkFaint)),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // ECOLENS'S READING — what EcoLens's own layers show around the
  // event: FIRMS fire detections, USGS quakes, the Open-Meteo air model,
  // the gazetteer and the wire itself. Computed and written server-side.
  // Every figure names its source; the editorial exists only when every
  // check against those figures passed. None of it is a GDACS figure.
  // ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _ecolensReading(IntelligenceNode node) {
    final r = node.causeData['ecolens_reading'];
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  /// The card line: the one sentence the server wrote from the reading.
  /// Nothing when there is no reading.
  Widget _ecolensSummaryLine(Map<String, dynamic> a) {
    final text = (a['ecolens_summary'] ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: Text(
              'ECOLENS',
              style: EcoPaper.label(size: 9, color: EcoPaper.inkFaint),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: EcoPaper.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _briefEcolensReading(IntelligenceNode node, InsightsViewModel vm) {
    final r = _ecolensReading(node);
    if (r == null) return const SizedBox.shrink();

    final stats = _readingStats(node, r, vm);
    final paragraphs = (r['paragraphs'] is List)
        ? (r['paragraphs'] as List).whereType<Map>().toList()
        : const <Map>[];
    final editorial = _readingEditorial(r);
    if (stats.isEmpty && paragraphs.isEmpty && editorial == null) {
      return const SizedBox.shrink();
    }

    final computedAt = DateTime.tryParse((r['computed_at'] ?? '').toString());
    final scope = r['scope_km'];
    final centroid = r['centroid'];
    final scopeBits = <String>[
      if (computedAt != null) 'computed ${_timeAgo(computedAt)}',
      if (scope is num && scope > 0) '${_fmtNum(scope)} km around the event',
      if (centroid is Map && centroid['lat'] is num && centroid['lon'] is num)
        _formatCoords(
          (centroid['lat'] as num).toDouble(),
          (centroid['lon'] as num).toDouble(),
        ),
    ];
    final model =
        editorial == null ? '' : (editorial['model'] ?? '').toString().trim();
    final modelNote = model.isEmpty ? '' : ' (model: $model)';

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: EcoPaper.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel("EcoLens's reading"),
            if (scopeBits.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                scopeBits.join(' · '),
                style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
              ),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 12),
              _readingGrid(stats),
              const SizedBox(height: 8),
              Text(
                'Computed by EcoLens from its own layers around the event; '
                'the GDACS figures above are the published record.',
                style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
              ),
              for (final m in _readingMethods(r))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    m,
                    style: EcoPaper.body(color: EcoPaper.inkFaint, size: 10.5),
                  ),
                ),
            ],
            if (paragraphs.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final p in paragraphs) _storyParagraph(p),
            ],
            if (editorial != null) ...[
              if (paragraphs.isEmpty) const SizedBox(height: 14),
              Text(
                'EcoLens reading · written from the figures above and checked '
                'against them$modelNote',
                style: EcoPaper.body(color: EcoPaper.inkFaint, size: 10.5)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                (editorial['text'] ?? '').toString(),
                style: EcoPaper.deck(size: 15, color: EcoPaper.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The editorial, only when it has text and no check is marked false.
  /// The server publishes one only when every check passed; a failed
  /// check that slipped through is still not shown.
  Map<String, dynamic>? _readingEditorial(Map<String, dynamic> r) {
    final e = r['editorial'];
    if (e is! Map) return null;
    if ((e['text'] ?? '').toString().trim().isEmpty) return null;
    final checks = e['checks'];
    if (checks is Map && checks.values.any((v) => v == false)) return null;
    return Map<String, dynamic>.from(e);
  }

  /// The one-sentence method each block carries, so a reader can check
  /// the figure it produced.
  List<String> _readingMethods(Map<String, dynamic> r) {
    const blocks = {
      'fires': 'Fires',
      'quakes': 'Earthquakes',
      'air': 'Air',
      'wire': 'Wire',
    };
    final out = <String>[];
    for (final e in blocks.entries) {
      final b = r[e.key];
      if (b is! Map) continue;
      final m = (b['method'] ?? '').toString().trim();
      if (m.isNotEmpty) out.add('${e.value}: $m');
    }
    return out;
  }

  /// The figures that exist in the reading, each tile with its source.
  List<Widget> _readingStats(
    IntelligenceNode node,
    Map<String, dynamic> r,
    InsightsViewModel vm,
  ) {
    final tiles = <Widget>[];
    final scope = r['scope_km'];

    final fires = r['fires'];
    if (fires is Map) {
      final n = fires['detections'];
      final src = (fires['source'] ?? '').toString().trim();
      final firms = src.isEmpty ? 'NASA FIRMS' : src;
      if (n is num) {
        final hours = fires['window_h'];
        final inside = fires['in_footprint'];
        tiles.add(_readingStat(
          _fmtInt(n),
          'fire detection${n == 1 ? '' : 's'} in '
          '${hours is num ? _fmtInt(hours) : '48'} h',
          [
            if (scope is num && scope > 0) 'within ${_fmtNum(scope)} km',
            if (inside is num) '${_fmtInt(inside)} inside the published polygon',
            firms,
          ].join(' · '),
        ));
      }
      final frp = fires['frp_mw_total'];
      if (frp is num && frp > 0) {
        final peak = fires['frp_mw_max'];
        tiles.add(_readingStat(
          '${_fmtNum(frp)} MW',
          'combined fire radiative power',
          [
            if (peak is num && peak > 0) 'strongest ${_fmtNum(peak)} MW',
            firms,
          ].join(' · '),
        ));
      }
      final pct = fires['change_pct'];
      final before = fires['previous_detections'];
      if (pct is num) {
        final String arrow;
        final String word;
        if (pct > 0) {
          arrow = '↑';
          word = 'up';
        } else if (pct < 0) {
          arrow = '↓';
          word = 'down';
        } else {
          arrow = '→';
          word = 'unchanged';
        }
        tiles.add(_readingStat(
          '$arrow ${_fmtNum(pct.abs())}%',
          '$word on the two days before',
          [
            if (before is num)
              '${_fmtInt(before)} detection${before == 1 ? '' : 's'} then',
            'same box, FIRMS archive',
          ].join(' · '),
        ));
      } else if (before is num) {
        tiles.add(_readingStat(
          _fmtInt(before),
          'detection${before == 1 ? '' : 's'} the two days before',
          'same box, FIRMS archive',
        ));
      }
    }

    final q = r['quakes'];
    if (q is Map && q['count'] is num) {
      final count = q['count'] as num;
      final days = q['window_days'];
      final radius = q['radius_km'];
      final minMag = q['min_magnitude'];
      final since = q['since_event'];
      final largest = q['largest'];
      final src = (q['source'] ?? '').toString().trim();
      final largestBits = <String>[];
      if (largest is Map && largest['mag'] is num) {
        largestBits.add('largest M${_fmtMag(largest['mag'] as num)}');
        if (largest['km'] is num) {
          largestBits.add('${_fmtNum(largest['km'] as num)} km away');
        }
        final day = _fmtDay(largest['date']);
        if (day.isNotEmpty) largestBits.add(day);
      }
      tiles.add(_readingStat(
        _fmtInt(count),
        [
          'M${minMag is num ? _fmtMag(minMag) : '4.0'}+ '
              'quake${count == 1 ? '' : 's'}',
          if (days is num) 'in ${_fmtInt(days)} days',
          if (radius is num) 'within ${_fmtNum(radius)} km',
        ].join(' '),
        [
          if (since is num) '${_fmtInt(since)} since the event',
          if (largestBits.isNotEmpty) largestBits.join(', '),
          src.isEmpty ? 'USGS earthquake catalog' : src,
        ].join(' · '),
      ));
    }

    final air = r['air'];
    if (air is Map) {
      final pm25 = air['pm25'];
      final pm10 = air['pm10'];
      final src = (air['source'] ?? '').toString().trim();
      final airSrc = src.isEmpty ? 'Open-Meteo air-quality model' : src;
      if (pm25 is num) {
        tiles.add(_readingStat(
          '${pm25.toStringAsFixed(1)} µg/m³',
          'PM2.5, modelled at the centroid',
          [
            if (pm10 is num) 'PM10 ${pm10.toStringAsFixed(1)} µg/m³',
            airSrc,
          ].join(' · '),
        ));
      } else if (pm10 is num) {
        tiles.add(_readingStat(
          '${pm10.toStringAsFixed(1)} µg/m³',
          'PM10, modelled at the centroid',
          airSrc,
        ));
      }
    }

    final place = r['nearest_place'];
    if (place is Map) {
      final name = (place['name'] ?? '').toString().trim();
      final km = place['km'];
      final bearing = (place['bearing'] ?? '').toString().trim();
      if (name.isNotEmpty && km is num) {
        tiles.add(_readingStat(
          '${_fmtNum(km)} km${bearing.isEmpty ? '' : ' $bearing'}',
          '$name, the nearest place',
          'EcoLens gazetteer',
        ));
      }
    }

    final wire = r['wire'];
    if (wire is Map && wire['same_type_total'] is num) {
      final total = wire['same_type_total'] as num;
      final active = wire['same_type_active'];
      final higher = wire['higher_alerts_on_wire'];
      final deadliest = wire['deadliest_report_on_wire'];
      final level = (node.causeData['alert_level'] ?? '').toString().trim();
      final typeLabel = (node.causeData['type_label'] ?? node.type).toString();
      // Published with each refresh in news_meta/latest; "the only Red
      // alert" is true exactly when that count is one.
      final atLevel = level.isEmpty ? null : vm.newsByLevel[level];
      tiles.add(_readingStat(
        '1 of ${_fmtInt(total)}',
        '${_typeNoun(typeLabel, total)} on the wire',
        [
          if (active is num) '${_fmtInt(active)} active',
          if (atLevel == 1) 'the only $level alert',
          if (higher is num && higher > 0)
            '${_fmtInt(higher)} alert${higher == 1 ? '' : 's'} '
                'outrank${higher == 1 ? 's' : ''} it',
          if (higher is num && higher == 0 && level.toLowerCase() != 'red')
            'none outranks it',
          if (deadliest == true) 'the deadliest report on the wire',
          'EcoLens wire',
        ].join(' · '),
      ));
    }

    return tiles;
  }

  /// One figure in the strip: the value in mono, what it is, and where it
  /// came from. A tile is never built without its source line.
  Widget _readingStat(String value, String label, String source) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: EcoPaper.well,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: EcoPaper.data(size: 18)),
              const SizedBox(height: 3),
              Text(
                label,
                style: EcoPaper.body(color: EcoPaper.inkSoft, size: 11.5)
                    .copyWith(height: 1.3),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              source,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: EcoPaper.inkFaint,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tiles in rows of two (three when wide), stretched to equal height so
  /// the strip reads as one table rather than a ragged wrap.
  Widget _readingGrid(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += cols) {
          final cells = <Widget>[];
          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(const SizedBox(width: 10));
            cells.add(Expanded(
              child: i + j < tiles.length ? tiles[i + j] : const SizedBox(),
            ));
          }
          rows.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }

  /// "flood" / "floods", "volcano" / "volcanoes", from the published type
  /// label, for the wire tile.
  String _typeNoun(String label, num count) {
    final s = label.trim().toLowerCase();
    if (s.isEmpty) return count == 1 ? 'alert' : 'alerts';
    if (count == 1 || s.endsWith('s')) return s;
    if (s.endsWith('o')) return '${s}es';
    return '${s}s';
  }

  String _fmtInt(num n) => NumberFormat.decimalPattern().format(n.round());

  /// Whole numbers, and anything from 100 up, as integers with thousands
  /// separators; smaller fractions keep one decimal so a tile never
  /// disagrees with the sentence built from the same figure.
  String _fmtNum(num v) {
    if (v == v.roundToDouble() || v.abs() >= 100) return _fmtInt(v);
    return v.toStringAsFixed(1);
  }

  String _fmtMag(num m) => m.toStringAsFixed(1);

  String _fmtDay(dynamic iso) {
    final t = DateTime.tryParse((iso ?? '').toString());
    return t == null ? '' : DateFormat('d MMM').format(t.toUtc());
  }

  Widget _briefTimeline(Map<String, dynamic> a) {
    final items = (a['timeline'] is List)
        ? (a['timeline'] as List).whereType<Map>().toList()
        : const <Map>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Timeline'),
          const SizedBox(height: 10),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(_fmtStamp(e['date']),
                        style: EcoPaper.data(size: 11, color: EcoPaper.inkSoft)),
                  ),
                  Expanded(
                    child: Text((e['text'] ?? '').toString(),
                        style: EcoPaper.body(size: 12.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _briefPress(Map<String, dynamic> a) {
    final items = (a['press'] is List)
        ? (a['press'] as List).whereType<Map>().toList()
        : const <Map>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('In the press'),
          const SizedBox(height: 4),
          Text(
            'Headlines the Europe Media Monitor has indexed for this alert. '
            'EcoLens has not read or verified these articles.',
            style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
          ),
          const SizedBox(height: 8),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: InkWell(
                onTap: () => _openExternal((p['link'] ?? '').toString()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (p['title'] ?? '').toString(),
                      style: EcoPaper.body(size: 13, color: EcoPaper.survey)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        (p['source'] ?? '').toString(),
                        _fmtStamp(p['date']),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // WIRE HELPERS — every value below is copied from the GDACS record
  // ──────────────────────────────────────────────────────────

  /// Severity text as published, minus the "Magnitude 0" placeholder GDACS
  /// emits for floods and droughts.
  String _publishedSeverity(IntelligenceNode node) {
    final s = (node.causeData['severity_text'] ?? '').toString().trim();
    return RegExp(r'^Magnitude 0(\.0+)?\s*$').hasMatch(s) ? '' : s;
  }

  /// The published impact statement, minus the same placeholder.
  String _impactStatement(IntelligenceNode node) {
    final s = (node.causeData['impact_statement'] ?? '').toString().trim();
    return RegExp(r'^Magnitude 0(\.0+)?\s*$').hasMatch(s) ? '' : s;
  }

  /// One line for the card: the single heaviest published impact report,
  /// else the published exposure statement. Never a sum of reports.
  String _whoIsAffectedLine(IntelligenceNode node) {
    final c = node.causeData;
    final head = c['impact_headline'];
    if (head is Map) {
      final d = (head['description'] ?? '').toString().trim();
      if (d.isNotEmpty) return d;
    }
    final exposure = c['exposure'];
    if (exposure is Map) {
      final shake = (exposure['shakepop_text'] ?? '').toString().trim();
      if (shake.isNotEmpty) return '$shake (USGS exposure model)';
    }
    final pop = (c['population_text'] ?? '').toString().trim();
    if (pop.isNotEmpty) return pop;
    return _impactStatement(node);
  }

  /// "25 countries · 223 days · 1,412,468 km² affected", from what exists.
  String _factsLine(IntelligenceNode node) {
    final c = node.causeData;
    final bits = <String>[];
    final countries = c['affected_countries'];
    if (countries is List && countries.length > 1) {
      bits.add('${countries.length} countries');
    }
    final days = c['duration_days'];
    if (days is int && days > 0) bits.add('$days day${days == 1 ? '' : 's'}');
    final km2 = c['affected_area_km2'];
    if (km2 is num && km2 > 0) {
      // A cyclone's published polygon is the swath inside a wind threshold
      // along the whole track, not ground that was hit. Say so.
      final basis = (c['affected_area_basis'] ?? '').toString();
      bits.add(basis.contains('wind')
          ? '${_fmtKm2(km2)} inside the published wind buffer'
          : '${_fmtKm2(km2)} affected');
    }
    return bits.join(' · ');
  }

  String _fmtKm2(num km2) =>
      '${NumberFormat.decimalPattern().format(km2.round())} km²';

  /// Fly the map to the alert with the published impact markers and
  /// affected-area zones switched on.
  void _viewOnMap(IntelligenceNode node) {
    HapticFeedback.mediumImpact();
    final label =
        node.headline.isNotEmpty ? node.headline : _fallbackTitle(node);
    context.read<NavigationViewModel>().goToMapAt(
          node.lat,
          node.lng,
          zoom: 6,
          label: label,
          layers: const ['impacts', 'affected'],
        );
  }

  Widget _cardButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: EcoPaper.survey,
        side: const BorderSide(color: EcoPaper.rule),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // WHO IS AFFECTED — each Sendai report as published, never summed
  // ──────────────────────────────────────────────────────────
  Widget _briefWhoIsAffected(IntelligenceNode node) {
    final c = node.causeData;
    final reports = (c['impact_reports'] is List)
        ? (c['impact_reports'] as List).whereType<Map>().toList()
        : const <Map>[];
    final exposure = c['exposure'] is Map ? c['exposure'] as Map : null;
    final enriched = (c['enriched_at'] ?? '').toString().isNotEmpty;
    final children = <Widget>[];

    for (final r in reports.take(12)) {
      final desc = (r['description'] ?? '').toString().trim();
      if (desc.isEmpty) continue;
      final where = [r['region'], r['country']]
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .map((v) => v.toString().trim())
          .toList();
      final date = DateTime.tryParse((r['date'] ?? '').toString());
      final meta = [
        if (where.isNotEmpty) where.join(', '),
        if (date != null) DateFormat('d MMM').format(date.toUtc()),
      ].join(' · ');
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(top: 8, right: 8),
              decoration: BoxDecoration(
                color: EcoPaper.survey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc, style: EcoPaper.body(size: 13)),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
                    ),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    if (exposure != null) {
      final mag = exposure['magnitude'];
      final depth = exposure['depth_km'];
      if (mag is num) children.add(_factRow('Magnitude', mag.toStringAsFixed(1)));
      if (depth is num) {
        children.add(_factRow('Depth', '${depth.toStringAsFixed(0)} km'));
      }
      final shake = (exposure['shakepop_text'] ?? '').toString().trim();
      if (shake.isNotEmpty) {
        children.add(_factRow('Exposed to shaking', '$shake (USGS ShakeMap)'));
      }
      final rapid = (exposure['rapidpop_text'] ?? '').toString().trim();
      if (rapid.isNotEmpty) {
        children.add(_factRow('Rapid estimate', '$rapid (USGS)'));
      }
    }

    if (children.isEmpty) {
      children.add(Text(
        enriched
            ? 'GDACS has published no impact reports for this alert yet.'
            : 'Impact reports load with the next refresh.',
        style: GoogleFonts.inter(
          color: EcoPaper.inkFaint,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Who is affected'),
          const SizedBox(height: 8),
          ...children,
          if (reports.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${reports.length - 12} more reports in the GDACS record.',
                style: GoogleFonts.inter(color: EcoPaper.inkFaint, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Each line is one report as GDACS published it. They are never '
            'added together: reports nest inside one another and later ones '
            'supersede earlier ones.',
            style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // MAPS AND PRODUCTS — GDACS event maps, Copernicus EMS, documents
  // ──────────────────────────────────────────────────────────
  Widget _briefMapsAndProducts(IntelligenceNode node) {
    final c = node.causeData;
    List<Map> maps(String k) =>
        (c[k] is List) ? (c[k] as List).whereType<Map>().toList() : const [];
    final images = maps('map_images');
    final products = maps('products');
    final documents = maps('documents');
    if (images.isEmpty && products.isEmpty && documents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Maps and products'),
          const SizedBox(height: 10),
          for (final img in images.take(2))
            _publishedImage(
              (img['url'] ?? '').toString(),
              (img['label'] ?? '').toString(),
              'GDACS',
            ),
          for (final p in products.take(6)) ...[
            if ((p['image'] ?? '').toString().isNotEmpty)
              _publishedImage(
                p['image'].toString(),
                (p['title'] ?? '').toString(),
                (p['kind'] ?? '').toString() == 'copernicus'
                    ? 'Copernicus Emergency Management Service'
                    : 'GDACS',
              ),
            if ((p['link'] ?? '').toString().isNotEmpty)
              _linkRow('${p['title']} →', p['link'].toString()),
          ],
          for (final d in documents.take(4))
            _linkRow('${d['name']} →', (d['url'] ?? '').toString()),
          const SizedBox(height: 6),
          Text(
            'Images and products are shown as published by their source; '
            'EcoLens does not redraw or reinterpret them.',
            style: EcoPaper.body(color: EcoPaper.inkFaint, size: 11),
          ),
        ],
      ),
    );
  }

  Widget _publishedImage(String url, String caption, String credit,
      {double? maxHeight}) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: EcoPaper.rule),
              borderRadius: BorderRadius.circular(3),
            ),
            clipBehavior: Clip.antiAlias,
            constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
            child: Image.network(
              url,
              fit: maxHeight == null ? BoxFit.contain : BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Image could not be loaded from the source.',
                  style: GoogleFonts.inter(
                    color: EcoPaper.inkFaint,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [if (caption.isNotEmpty) caption, credit].join(' · '),
            style: EcoPaper.data(size: 10.5, color: EcoPaper.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(String label, String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _openExternal(url),
        child: Text(
          label,
          style: EcoPaper.body(color: EcoPaper.survey, size: 12.5)
              .copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // WHAT'S AT RISK — species + livelihoods + health from the node
  // ──────────────────────────────────────────────────────────
  bool _briefAtRiskHasContent(IntelligenceNode node) {
    return node.faunaAtRisk.isNotEmpty ||
        node.floraAtRisk.isNotEmpty ||
        node.livelihoodsAtRisk.isNotEmpty ||
        node.healthImpacts.isNotEmpty;
  }

  Widget _briefAtRisk(IntelligenceNode node) {
    if (!_briefAtRiskHasContent(node)) return const SizedBox.shrink();

    final groups = <Widget>[];
    if (node.faunaAtRisk.isNotEmpty) {
      groups.add(_atRiskGroup(
        'Fauna at risk',
        node.faunaAtRisk.map((s) => s.commonName).toList(),
      ));
    }
    if (node.floraAtRisk.isNotEmpty) {
      groups.add(_atRiskGroup(
        'Flora at risk',
        node.floraAtRisk.map((s) => s.commonName).toList(),
      ));
    }
    if (node.livelihoodsAtRisk.isNotEmpty) {
      groups.add(_atRiskGroup('Livelihoods at risk', node.livelihoodsAtRisk));
    }
    if (node.healthImpacts.isNotEmpty) {
      groups.add(_atRiskGroup('Health impacts', node.healthImpacts));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel("What's at risk"),
          const SizedBox(height: 12),
          for (int i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            groups[i],
          ],
        ],
      ),
    );
  }

  Widget _atRiskGroup(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: EcoPaper.inkSoft,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .where((s) => s.trim().isNotEmpty)
              .map((s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: EcoPaper.paperDeep,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: EcoPaper.rule),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.inter(
                        color: EcoPaper.ink,
                        fontSize: 11.5,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────
  // RECOMMENDED ACTIONS — straight from the node, no synthesis
  // ──────────────────────────────────────────────────────────
  Widget _briefRecommendedActions(IntelligenceNode node) {
    if (node.recommendedActions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Recommended actions'),
          const SizedBox(height: 10),
          for (final a in node.recommendedActions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _priorityColor(a.priority).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color:
                            _priorityColor(a.priority).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      a.priority.replaceAll('_', ' '),
                      style: GoogleFonts.inter(
                        color: _priorityColor(a.priority),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.action,
                          style: EcoPaper.body(size: 13),
                        ),
                        if (a.responsibleEntity.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Lead: ${a.responsibleEntity}',
                              style: GoogleFonts.inter(
                                color: EcoPaper.inkFaint,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _priorityColor(String priority) {
    final p = priority.toUpperCase();
    if (p.contains('IMMEDIATE') || p.contains('URGENT')) {
      return EcoPaper.fire;
    }
    if (p.contains('SHORT')) return EcoPaper.fireDeep;
    if (p.contains('MEDIUM')) return EcoPaper.amber;
    if (p.contains('LONG')) return EcoPaper.survey;
    return EcoPaper.okGreen;
  }

  // ──────────────────────────────────────────────────────────
  // DETECTION FACTS — real fields only
  // ──────────────────────────────────────────────────────────
  Widget _briefDetectionFacts(IntelligenceNode node) {
    final rows = <Widget>[];
    rows.add(_factRow('Type', _humanType(node.type)));

    // Fire-specific real fields from FIRMS
    if (node.fireData.fireRadiativePower > 0) {
      rows.add(_factRow(
        'Fire radiative power',
        '${node.fireData.fireRadiativePower.toStringAsFixed(1)} MW',
      ));
    }
    // "Active fires in zone" and "Fire risk level" were removed: for
    // map-sourced events the first was the constant 1 for anything tagged
    // wildfire, and the second was the feed's severity word converted to a
    // number and back, presented as an EcoLens fire rating.
    if (node.fireData.lastFireDate.isNotEmpty) {
      rows.add(_factRow('Last fire detection', node.fireData.lastFireDate));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Detection facts'),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'No detection metadata available for this event type.',
              style: GoogleFonts.inter(
                color: EcoPaper.inkFaint,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // LOCATION CONTEXT — real reverse-geocoded fields
  // ──────────────────────────────────────────────────────────
  Widget _briefLocationContext(IntelligenceNode node) {
    final fields = <Widget>[];
    if (node.continent.isNotEmpty) fields.add(_factRow('Continent', node.continent));
    if (node.country.isNotEmpty) fields.add(_factRow('Country', node.country));
    if (node.provinceState.isNotEmpty) fields.add(_factRow('Province / State', node.provinceState));
    if (node.region.isNotEmpty && node.region != node.country) {
      fields.add(_factRow('Region', node.region));
    }
    fields.add(_factRow('Coordinates', _formatCoords(node.lat, node.lng)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Location'),
          const SizedBox(height: 10),
          ...fields,
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // CTA — Open full intelligence brief on the map drawer
  // The map has the WRI cross-validation + OSM verify + correlations
  // ──────────────────────────────────────────────────────────
  Widget _briefFullIntelligenceCta(BuildContext context, IntelligenceNode node) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EcoPaper.survey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: EcoPaper.survey.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isNewsItem(node) ? Icons.map_outlined : Icons.insights_outlined,
                  color: EcoPaper.survey, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: _sectionLabel(
                  _isNewsItem(node) ? 'On the map' : 'Full intelligence brief',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isNewsItem(node)) ...[
            Text(
              'Fly to this alert with the published impact markers and '
              'affected-area zones switched on. The same layers show every '
              'other escalated event on the wire.',
              style: EcoPaper.body(color: EcoPaper.inkSoft, size: 12.5),
            ),
          ] else ...[
            Text(
              'Open the live brief on the map for:',
              style: EcoPaper.body(
                color: EcoPaper.inkSoft,
                size: 12.5,
              ),
            ),
            const SizedBox(height: 8),
            _bullet('Drivers from live wind + drought + precipitation grids'),
            _bullet('24–48 h modelled spread/escalation scenario'),
            _bullet('OpenStreetMap-verified hospitals, schools, population in the impact zone'),
            _bullet('WRI Global Power Plant Database cross-validation'),
            _bullet('Nearest GDACS + NASA EONET response context'),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openOnMapDrawer(context, node),
              style: ElevatedButton.styleFrom(
                backgroundColor: EcoPaper.survey,
                foregroundColor: EcoPaper.paperRaised,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(
                _isNewsItem(node) ? 'View on map' : 'Open on map',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // SOURCES & METHOD — show every data origin
  // ──────────────────────────────────────────────────────────
  Widget _briefSourcesAndMethod(IntelligenceNode node) {
    final sources = node.dataSources;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EcoPaper.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Sources'),
          const SizedBox(height: 10),
          if (sources.isEmpty)
            Text(
              'No data sources attached to this signal.',
              style: GoogleFonts.inter(
                color: EcoPaper.inkFaint,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...sources.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: EcoPaper.survey,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: s.url.trim().isNotEmpty
                            ? InkWell(
                                onTap: () => _openExternal(s.url.trim()),
                                child: Text(
                                  '${s.name} →',
                                  style: EcoPaper.body(
                                    color: EcoPaper.survey,
                                    size: 12,
                                  ).copyWith(fontWeight: FontWeight.w700),
                                ),
                              )
                            : Text(
                                s.name,
                                style: EcoPaper.body(
                                  color: EcoPaper.inkSoft,
                                  size: 12,
                                ),
                              ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // HONEST NOTE — explain what we don't show and why
  // ──────────────────────────────────────────────────────────
  Widget _briefHonestNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: EcoPaper.amber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: EcoPaper.amber,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hectares burned, carbon loss, risk score and derived '
              'population are not shown anywhere in EcoLens — not on this '
              'report, not on the case list, and not on the card this page '
              'shares. For events picked up from the map they were computed '
              'from the watch circle EcoLens draws and from the severity word '
              'in the feed, not from anything measured. Verified counts '
              '(OpenStreetMap-tagged people and infrastructure, WRI power '
              'plants) are surfaced inside the on-map brief instead.',
              style: EcoPaper.body(
                color: EcoPaper.inkSoft,
                size: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: EcoPaper.label(),
      );

  Widget _factRow(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                key,
                style: GoogleFonts.inter(
                  color: EcoPaper.inkFaint,
                  fontSize: 11.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: EcoPaper.data(size: 12.5),
              ),
            ),
          ],
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(top: 8, right: 8),
              decoration: BoxDecoration(
                color: EcoPaper.survey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: EcoPaper.body(
                  color: EcoPaper.ink,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      );

  Color _accentForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('fire') || t.contains('wild')) return EcoPaper.fire;
    if (t.contains('flood')) return EcoPaper.survey;
    if (t.contains('quake') || t.contains('seism')) return EcoPaper.fireDeep;
    if (t.contains('drought')) return EcoPaper.amber;
    if (t.contains('volcano')) return EcoPaper.fireDeep;
    if (t.contains('air')) return EcoPaper.okGreen;
    return EcoPaper.okGreen;
  }

  String _humanType(String type) {
    final t = type.toLowerCase();
    if (t.contains('wild') || t.contains('fire')) return 'Wildfire detection';
    if (t.contains('flood')) return 'Flood signal';
    if (t.contains('quake')) return 'Earthquake';
    if (t.contains('drought')) return 'Drought zone';
    if (t.contains('volcano')) return 'Volcano alert';
    if (t.contains('air')) return 'Air-quality reading';
    return type;
  }

  String _fallbackTitle(IntelligenceNode node) {
    final h = _humanType(node.type);
    return node.country.isNotEmpty ? '$h · ${node.country}' : h;
  }

  String _formatCoords(double lat, double lng) =>
      '${lat.toStringAsFixed(3)}°, ${lng.toStringAsFixed(3)}°';

  String _composeSoWhat(IntelligenceNode node) {
    final loc = node.country.isNotEmpty
        ? node.country
        : 'unknown region';
    final t = node.type.toLowerCase();

    if (t.contains('fire') || t.contains('wild')) {
      final frp = node.fireData.fireRadiativePower;
      if (frp >= 300) {
        return 'Extreme thermal anomaly detected over $loc. '
            'Verify wind, drought conditions, and nearby communities '
            'on the map brief before any operational response.';
      } else if (frp >= 120) {
        return 'High-intensity fire signal over $loc. '
            'Open the map brief for live wind, drought, and population data.';
      }
      return 'Active fire detection over $loc. '
          'Treat as a verification queue item; check the map brief for context.';
    }
    if (t.contains('flood')) {
      return 'Flood signal detected for $loc. The map brief shows '
          'live precipitation forecast and downstream population at risk.';
    }
    if (t.contains('quake')) {
      return 'Seismic event recorded near $loc. The map brief shows '
          'depth, magnitude rank, and infrastructure within the felt radius.';
    }
    if (t.contains('drought')) {
      return 'Drought conditions reported across $loc. The map brief '
          'shows live precipitation forecast and verified water-stress proxies.';
    }
    return 'Environmental signal detected over $loc. '
        'Open the map brief for live correlations and verified impact context.';
  }

  void _openOnMapDrawer(BuildContext context, IntelligenceNode node) {
    final label = node.headline.isNotEmpty ? node.headline : _fallbackTitle(node);
    // Queue the fly target, switch the bottom-nav to Map. The map screen
    // consumes pendingFlyTarget on its next build and calls window.ecolensFlyTo
    // (or stashes window.__pendingFly until the bridge is ready).
    final navVm = context.read<NavigationViewModel>();
    final news = _isNewsItem(node);
    navVm.goToMapAt(
      node.lat,
      node.lng,
      zoom: news ? 6 : 10,
      label: label,
      // Wire items arrive with the published impact markers and
      // affected-area zones switched on.
      layers: news ? const ['impacts', 'affected'] : const [],
    );
    // Drop the detail sheet so the user lands on the map cleanly.
    final vm = context.read<InsightsViewModel>();
    vm.clearActiveAlert();
  }

  // --- NEW TABS: SENTINEL, RISK, SPATIAL ---



































  // ═══════════════════════════════════════════════════════════════
  // SOCIAL SHARING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _shareInsight(IntelligenceNode node) async {
    setState(() => _isGeneratingShare = true);
    HapticFeedback.mediumImpact();

    try {
      final shareCard = _buildShareCard(node);
      final image = await _screenshotController.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Material(child: shareCard),
        ),
        pixelRatio: 3.0,
      );

      // Bytes only — path_provider has no web implementation, and web is
      // the platform this app ships on.
      final fileName =
          'ecolens_share_${DateTime.now().millisecondsSinceEpoch}.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(image, mimeType: 'image/png', name: fileName),
          ],
          fileNameOverrides: [fileName],
          text:
              '${node.headline} — ${_nodeLocation(node)}. '
              'EcoLens · Environmental Intelligence',
        ),
      );
    } catch (e) {
      debugPrint('Share error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: EcoPaper.ink,
          content: Text(
            'Could not share this case card.',
            style: EcoPaper.body(color: EcoPaper.paper, size: 13),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingShare = false);
    }
  }

  /// Shareable case card. Headline, place, coordinates, detection time and
  /// named sources only. The risk badge, the hectares/species/population stat
  /// row and the "WHY IT MATTERS" claim were removed: none of them traced to
  /// a measured input, and this image leaves the app over the EcoLens name.
  Widget _buildShareCard(IntelligenceNode node) {
    final detectedAt = node.fireData.lastFireDate.trim();
    final sources = node.dataSources
        .map((d) => d.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    return Container(
      width: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EcoPaper.paperRaised,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: EcoPaper.rule),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EcoPaper.paperDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: EcoPaper.rule),
                ),
                child: const Icon(
                  Icons.eco,
                  color: EcoPaper.okGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "ECOLENS · ENVIRONMENTAL INTELLIGENCE",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EcoPaper.label(size: 10, color: EcoPaper.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Place
          Text(
            [node.region, node.country]
                .where((v) => v.trim().isNotEmpty)
                .join(', ')
                .toUpperCase(),
            style: EcoPaper.label(size: 10),
          ),
          const SizedBox(height: 6),

          // Headline
          Text(
            node.headline.isNotEmpty ? node.headline : _fallbackTitle(node),
            style: EcoPaper.headline(size: 16),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),

          // Coordinates + detection time — both carried on the event itself
          Text(
            _formatCoords(node.lat, node.lng),
            style: EcoPaper.data(size: 10, color: EcoPaper.inkSoft),
          ),
          if (detectedAt.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Detected $detectedAt',
              style: EcoPaper.data(size: 10, color: EcoPaper.inkSoft),
            ),
          ],
          const SizedBox(height: 12),

          // Named sources, or an explicit statement that there are none
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EcoPaper.paperDeep,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EcoPaper.rule),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SOURCES",
                  style: EcoPaper.label(size: 9),
                ),
                const SizedBox(height: 6),
                Text(
                  sources.isEmpty
                      ? 'No data sources attached to this signal.'
                      : sources.join(' · '),
                  style: EcoPaper.body(color: EcoPaper.inkSoft, size: 11),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Footer
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "ecolens.app",
              style: GoogleFonts.inter(
                  color: EcoPaper.inkFaint, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }






}

/// Single fact rendered in the area-context grid. All values are derived
/// from live data at call time — never hardcoded.
class _AreaContextFact {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _AreaContextFact({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });
}
