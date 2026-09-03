import 'dart:io';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/data/community_data.dart';
import 'package:ecolens/viewmodels/community_viewmodel.dart';
import 'package:ecolens/services/moderation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<ConservationStory> _stories = [];
  bool _loadingStories = false;

  @override
  void initState() {
    super.initState();
    _loadConservationStories();
  }

  Future<void> _loadConservationStories() async {
    setState(() => _loadingStories = true);

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('conservation_stories')
          .orderBy('created_at', descending: true)
          .limit(20)
          .get();

      if (snapshot.docs.isEmpty) {
        // Honest empty state — no fabricated stories.
        _stories = [];
      } else {
        _stories = snapshot.docs
            .map(
              (doc) => ConservationStory.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading stories: $e');
      _stories = _getSampleStories();
    }

    setState(() => _loadingStories = false);
  }

  List<ConservationStory> _getSampleStories() {
    return [
      ConservationStory(
        id: '1',
        title: 'Amazon Reforestation: 50,000 Trees Milestone',
        summary:
            'Local community achieves major milestone in restoring degraded pastureland to native forest.',
        fullContent:
            '''After three years of dedicated effort, the community of São Félix do Xingu has achieved a remarkable milestone: 50,000 native trees now grow where cattle pastures once dominated the landscape.\n\nThe project, supported by local NGOs and international funding, has not only restored forest cover but created sustainable livelihoods for over 200 families through agroforestry systems.\n\n"We're not just planting trees," says Maria Santos, project coordinator. "We're rebuilding an entire ecosystem while providing food security for our community."''',
        imageUrl:
            'https://images.unsplash.com/photo-1516026672322-bc52d61a55d5?w=800',
        category: 'restoration',
        location: 'Pará, Brazil',
        author: 'EcoLens Team',
        isVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        metrics: {
          'trees_planted': 50000,
          'carbon_tonnes': 2500,
          'hectares': 120,
        },
      ),
      ConservationStory(
        id: '2',
        title: 'Endangered Jaguar Population Recovery',
        summary:
            'Camera traps reveal growing jaguar population in protected corridor.',
        fullContent:
            '''New data from wildlife monitoring cameras has confirmed what conservationists hoped: jaguar populations are rebounding in the Atlantic Forest corridor.\n\nTwelve individual jaguars have been identified in the past year, up from just three confirmed individuals in 2020.''',
        imageUrl:
            'https://images.unsplash.com/photo-1546182990-dffeafbe841d?w=800',
        category: 'wildlife',
        location: 'Paraná, Brazil',
        author: 'Panthera Brasil',
        isVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        metrics: {'jaguars_identified': 12, 'corridor_km': 150},
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: EcoPaper.paper,
        body: SafeArea(
          child: Column(
            children: [
              _buildSectionHeader(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildClimateEventsTab(),
                    _buildCommunityStoriesTabV2(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION HEADER + TAB BAR
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMMUNITY',
            style: EcoPaper.label(color: EcoPaper.inkFaint),
          ),
          const SizedBox(height: 4),
          Text(
            'Climate stories from the field',
            style: EcoPaper.deck(size: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: TabBar(
        labelColor: EcoPaper.ink,
        unselectedLabelColor: EcoPaper.inkFaint,
        indicatorColor: EcoPaper.survey,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: EcoPaper.rule,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        tabAlignment: TabAlignment.start,
        isScrollable: true,
        tabs: const [
          Tab(text: 'Climate Events'),
          Tab(text: 'Community Stories'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CLIMATE EVENTS TAB
  // Evidence-driven, research-led stories built from secondary
  // sources (UNOSAT, peer-reviewed, government data). First entry:
  // Pakistan 2022 Floods.
  // ═══════════════════════════════════════════════════════════════

  Widget _buildClimateEventsTab() {
    // Cap the column to a readable max-width so on desktop the featured
    // card doesn't stretch full-bleed (which made its 16:9 hero ~950px
    // tall and pushed all the content below the fold).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildSubsectionLabel('FEATURED', 'Latest event brief'),
            const SizedBox(height: 12),
            _buildPakistanFeaturedCard(),
            const SizedBox(height: 28),
            _buildSubsectionLabel('ALL CLIMATE EVENTS', null),
            const SizedBox(height: 8),
            _buildClimateEventListRow(
              title: 'Pakistan 2022 Floods',
              dateLabel: 'Jun 2026 · Updated weekly',
              chapters: 19,
              storymapUrl: '/stories/pakistan-2022/',
              documentaryUrl: '/stories/pakistan-2022/documentary/',
              documentaryReady: false,
            ),
            const SizedBox(height: 8),
            _buildComingSoonRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildPakistanFeaturedCard() {
    return Container(
      decoration: EcoPaper.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image — uses the NASA Landsat 'during' frame from the storymap.
          // Fixed height instead of AspectRatio so it doesn't balloon to
          // ~950px tall on desktop when the parent is full-bleed.
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  '/stories/pakistan-2022/assets/hero_during.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: EcoPaper.paperDeep,
                  ),
                ),
                // Dark scrim over the photograph for caption legibility
                // (photo treatment, not UI decoration).
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.black.withOpacity(0.05),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: EcoPaper.paper.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: EcoPaper.rule),
                    ),
                    child: Text(
                      'CLIMATE EVENT',
                      style: EcoPaper.label(size: 9, color: EcoPaper.ink),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 14,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pakistan 2022 Floods',
                        style: GoogleFonts.lora(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'One-third under water · 33 M affected · recovery unfinished',
                        style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: const [
                    _MetaChip(text: '19 chapters'),
                    _MetaChip(text: '3D flood simulation'),
                    _MetaChip(text: 'UNOSAT · WorldPop · IOM'),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'In summer 2022, monsoon rains and accelerated glacial melt put a third of Pakistan beneath water. Four years on, only 800 climate-resilient homes have replaced the 2.1 million destroyed.',
                  style: EcoPaper.body(color: EcoPaper.inkSoft),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _FormatButton(
                        icon: Icons.map_outlined,
                        label: 'Story-map',
                        sublabel: 'Interactive',
                        primary: true,
                        onTap: () =>
                            _openStoryUrl('/stories/pakistan-2022/'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FormatButton(
                        icon: Icons.play_circle_outline,
                        label: 'Documentary',
                        sublabel: 'Short film',
                        primary: false,
                        onTap: () => _openStoryUrl(
                          '/stories/pakistan-2022/documentary/',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClimateEventListRow({
    required String title,
    required String dateLabel,
    required int chapters,
    required String storymapUrl,
    required String documentaryUrl,
    required bool documentaryReady,
  }) {
    return InkWell(
      onTap: () => _openStoryUrl(storymapUrl),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: EcoPaper.flat,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: EcoPaper.paperDeep,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: EcoPaper.rule),
              ),
              child: const Icon(
                Icons.public,
                color: EcoPaper.survey,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.lora(
                      color: EcoPaper.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateLabel · $chapters chapters',
                    style: GoogleFonts.inter(
                      color: EcoPaper.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: EcoPaper.inkFaint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: EcoPaper.rule,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.more_horiz,
            color: EcoPaper.inkFaint,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'More climate events coming as EcoLens partners with research and journalism teams.',
              style: GoogleFonts.inter(
                color: EcoPaper.inkFaint,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // COMMUNITY STORIES TAB (V2)
  // Primary-source, partnership-led stories. First slot reserved
  // for Homegrown Pigeon (New Westminster buried streams).
  // Existing Firestore conservation_stories shown below as
  // "Recent community submissions" so legacy content isn't lost.
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCommunityStoriesTabV2() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _buildCommunityStoriesList(),
      ),
    );
  }

  Widget _buildCommunityStoriesList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSubsectionLabel('PUBLISHED', 'Local investigations'),
        const SizedBox(height: 12),
        _buildLeadInvestigationCard(),
        const SizedBox(height: 28),
        _buildSubsectionLabel('UPCOMING', 'In partnership development'),
        const SizedBox(height: 12),
        _buildPartnershipPlaceholderCard(),
        const SizedBox(height: 28),
        if (_stories.isNotEmpty) ...[
          _buildSubsectionLabel('RECENT SUBMISSIONS', null),
          const SizedBox(height: 8),
          ..._stories.map(_buildStoryCard),
        ] else if (!_loadingStories) ...[
          _buildSubsectionLabel('RECENT SUBMISSIONS', null),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No community submissions yet.',
              style: GoogleFonts.inter(
                color: EcoPaper.inkFaint,
                fontSize: 12,
              ),
            ),
          ),
        ] else
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: EcoPaper.survey),
            ),
          ),
      ],
    );
  }

  /// The lead published investigation gets front-page treatment: a full
  /// editorial feature card, not a list row. Serif headline, standfirst,
  /// meta line, and one strong action — like the paper it is.
  Widget _buildLeadInvestigationCard() {
    return InkWell(
      onTap: () => _openStoryUrl('/stories/daylighting-vancouver-2026/'),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        decoration: EcoPaper.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Masthead band — deep paper with a survey rule, standing in
            // for cover art until the story has its own photograph.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              decoration: const BoxDecoration(
                color: EcoPaper.paperDeep,
                border: Border(
                  bottom: BorderSide(color: EcoPaper.survey, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INVESTIGATION · VANCOUVER',
                    style: EcoPaper.label(size: 9.5, color: EcoPaper.survey),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Coming Back — Daylighting Vancouver’s Buried Streams',
                    style: GoogleFonts.lora(
                      color: EcoPaper.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The creeks that built this city still run beneath it — '
                    'piped, culverted, and forgotten. An eight-chapter '
                    'investigation into where they went, and what it would '
                    'take to bring them back to the surface.',
                    style: GoogleFonts.lora(
                      color: EcoPaper.inkSoft,
                      fontSize: 14.5,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'JUL 2026 · 8 CHAPTERS · STORYMAP',
                        style: EcoPaper.label(size: 9, color: EcoPaper.inkFaint),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: EcoPaper.survey,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Read the investigation',
                          style: GoogleFonts.inter(
                            color: EcoPaper.paperRaised,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  Widget _buildPartnershipPlaceholderCard() {
    return Container(
      decoration: EcoPaper.card,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: EcoPaper.paperDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: EcoPaper.rule),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  color: EcoPaper.survey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buried Streams of New Westminster',
                      style: GoogleFonts.lora(
                        color: EcoPaper.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'with Homegrown Pigeon Society',
                      style: GoogleFonts.inter(
                        color: EcoPaper.survey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: EcoPaper.paperDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: EcoPaper.rule),
                ),
                child: Text(
                  'IN DEV',
                  style: EcoPaper.label(size: 9, color: EcoPaper.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Tracing the surface streams that ran through what is now '
            'New Westminster, what got piped underground over the last '
            'century, and the daylighting work that could bring some of '
            'them back. Built with Homegrown Pigeon Society as the first '
            'EcoLens community partnership.',
            style: EcoPaper.body(size: 12.5, color: EcoPaper.inkSoft),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: EcoPaper.well,
            child: Row(
              children: [
                const Icon(
                  Icons.schedule,
                  color: EcoPaper.inkFaint,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meeting scheduled · launch target Aug 2026',
                    style: GoogleFonts.inter(
                      color: EcoPaper.inkSoft,
                      fontSize: 11,
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

  // ═══════════════════════════════════════════════════════════════
  // SHARED UTILITIES
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSubsectionLabel(String label, String? sublabel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: EcoPaper.label(size: 9, color: EcoPaper.inkFaint),
        ),
        if (sublabel != null) ...[
          const SizedBox(width: 8),
          Text(
            sublabel,
            style: GoogleFonts.inter(
              color: EcoPaper.inkFaint,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openStoryUrl(String path) async {
    // Resolve the relative path against the current page URL so we get an
    // absolute URI. canLaunchUrl returns false for scheme-less paths, which
    // is why the button was silently failing before. On web we navigate in
    // the same tab; on mobile we open externally.
    final uri = Uri.base.resolve(path);
    try {
      await launchUrl(uri, webOnlyWindowName: '_self');
    } catch (e) {
      debugPrint('[CommunityScreen] launchUrl failed for $uri: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // COMMUNITY REPORTS TAB
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCommunityReportsTab() {
    return Consumer<CommunityViewModel>(
      builder: (context, vm, child) {
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildGuidelinesBanner(context),
            _buildStatsHeader(vm),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildReportCard(context, vm.reports[index], vm),
                childCount: vm.reports.length,
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONSERVATION STORIES TAB
  // ═══════════════════════════════════════════════════════════════

  Widget _buildConservationStoriesTab() {
    if (_loadingStories) {
      return const Center(
        child: CircularProgressIndicator(color: EcoPaper.survey),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConservationStories,
      color: EcoPaper.survey,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                'CURATED CONSERVATION STORIES',
                style: EcoPaper.label(color: EcoPaper.inkFaint),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildStoryCard(_stories[index]),
              childCount: _stories.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildStoryCard(ConservationStory story) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: EcoPaper.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Image
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  story.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: EcoPaper.paperDeep,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: EcoPaper.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
              // Category Badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(story.category).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getCategoryIcon(story.category),
                        color: EcoPaper.paperRaised,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        story.category.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: EcoPaper.paperRaised,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Verified Badge
              if (story.isVerified)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: EcoPaper.survey.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(
                      Icons.verified,
                      color: EcoPaper.paperRaised,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location and Author
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: EcoPaper.inkFaint,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      story.location,
                      style: GoogleFonts.inter(
                        color: EcoPaper.inkFaint,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      story.author,
                      style: GoogleFonts.inter(
                        color: EcoPaper.inkFaint,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  story.title,
                  style: EcoPaper.headline(size: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Summary
                Text(
                  story.summary,
                  style: EcoPaper.body(size: 12, color: EcoPaper.inkSoft),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                // Impact Metrics
                if (story.metrics.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: story.metrics.entries.take(3).map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: EcoPaper.well,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatMetricValue(entry.key, entry.value),
                              style: EcoPaper.data(size: 11),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatMetricLabel(entry.key),
                              style: GoogleFonts.inter(
                                color: EcoPaper.inkFaint,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                // Read More Button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _showFullStory(story),
                    style: TextButton.styleFrom(
                      backgroundColor: EcoPaper.paperRaised,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                        side: const BorderSide(color: EcoPaper.ink),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'READ FULL STORY',
                          style: EcoPaper.label(size: 11, color: EcoPaper.ink),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward,
                          color: EcoPaper.ink,
                          size: 14,
                        ),
                      ],
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

  void _showFullStory(ConservationStory story) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: EcoPaper.paper,
            border: Border(top: BorderSide(color: EcoPaper.rule)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EcoPaper.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hero Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            story.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Title
                      Text(
                        story.title,
                        style: EcoPaper.headline(size: 22),
                      ),
                      const SizedBox(height: 12),
                      // Meta
                      Row(
                        children: [
                          if (story.isVerified) ...[
                            const Icon(
                              Icons.verified,
                              color: EcoPaper.survey,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            story.author,
                            style: GoogleFonts.inter(
                              color: EcoPaper.inkFaint,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.location_on,
                            color: EcoPaper.inkFaint,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            story.location,
                            style: GoogleFonts.inter(
                              color: EcoPaper.inkSoft,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Full Content
                      Text(
                        story.fullContent,
                        style: EcoPaper.body(size: 14),
                      ),
                      const SizedBox(height: 24),
                      // Impact Metrics
                      if (story.metrics.isNotEmpty) ...[
                        Text(
                          'IMPACT METRICS',
                          style: EcoPaper.label(
                            size: 11,
                            color: EcoPaper.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: story.metrics.entries.map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: EcoPaper.well,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatMetricValue(entry.key, entry.value),
                                    style: EcoPaper.data(size: 18),
                                  ),
                                  Text(
                                    _formatMetricLabel(entry.key),
                                    style: GoogleFonts.inter(
                                      color: EcoPaper.inkFaint,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'restoration':
        return EcoPaper.okGreen;
      case 'wildlife':
        return EcoPaper.amber;
      case 'community':
        return EcoPaper.survey;
      case 'research':
        return EcoPaper.survey;
      default:
        return EcoPaper.inkSoft;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'restoration':
        return Icons.forest;
      case 'wildlife':
        return Icons.pets;
      case 'community':
        return Icons.people;
      case 'research':
        return Icons.science;
      default:
        return Icons.auto_stories;
    }
  }

  String _formatMetricLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '',
        )
        .join(' ');
  }

  String _formatMetricValue(String key, dynamic value) {
    if (key.contains('percent')) {
      return '$value%';
    } else if (key.contains('tonnes') || key.contains('carbon')) {
      return '${_formatNumber(value as int)}t';
    } else if (key.contains('hectares') || key.contains('km')) {
      return _formatNumber(value as int);
    }
    return _formatNumber(value as int);
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // ORIGINAL COMMUNITY REPORTS WIDGETS (unchanged)
  // ═══════════════════════════════════════════════════════════════

  // --- 📋 GUIDELINES BANNER (Apple Requirement) ---
  Widget _buildGuidelinesBanner(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: EcoPaper.flat,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EcoPaper.paperDeep,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: EcoPaper.rule),
              ),
              child: const Icon(
                Icons.verified_user,
                color: EcoPaper.survey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Community Guidelines",
                    style: GoogleFonts.inter(
                      color: EcoPaper.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Zero tolerance for abuse. Report issues to:",
                    style: GoogleFonts.inter(
                      color: EcoPaper.inkSoft,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "hello@rickyj.io",
                    style: GoogleFonts.inter(
                      color: EcoPaper.survey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.info_outline,
                color: EcoPaper.inkFaint,
                size: 20,
              ),
              onPressed: () => _showGuidelinesDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showGuidelinesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoPaper.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: EcoPaper.rule),
        ),
        title: Row(
          children: [
            const Icon(Icons.verified_user, color: EcoPaper.survey),
            const SizedBox(width: 12),
            Text(
              "Community Guidelines",
              style: GoogleFonts.lora(
                color: EcoPaper.ink,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _guidelineItem("🌍", "Purpose", "Environmental reporting & action"),
            const SizedBox(height: 12),
            _guidelineItem(
              "⛔",
              "Zero Tolerance",
              "No hate speech, harassment, or abuse",
            ),
            const SizedBox(height: 12),
            _guidelineItem(
              "🚫",
              "Prohibited",
              "No spam, explicit content, or false info",
            ),
            const SizedBox(height: 12),
            _guidelineItem(
              "🛡️",
              "Enforcement",
              "Violations = immediate removal",
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: EcoPaper.well,
              child: Row(
                children: const [
                  Icon(Icons.email, color: EcoPaper.survey, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "hello@rickyj.io",
                    style: TextStyle(
                      color: EcoPaper.survey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "GOT IT",
              style: TextStyle(color: EcoPaper.survey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidelineItem(String emoji, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "$title: ",
                  style: const TextStyle(
                    color: EcoPaper.ink,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                TextSpan(
                  text: desc,
                  style: const TextStyle(
                    color: EcoPaper.inkSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- 📊 STATS HEADER ---
  Widget _buildStatsHeader(CommunityViewModel vm) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: EcoPaper.card,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                "TREES PLANTED",
                "${vm.totalTreesPlanted}",
                EcoPaper.okGreen,
                Icons.forest,
              ),
              _verticalDivider(),
              _statItem(
                "TOP REGION",
                vm.topPlantingRegion.toUpperCase(),
                EcoPaper.survey,
                Icons.public,
              ),
              _verticalDivider(),
              // 📂 ORG UPLOAD BUTTON
              GestureDetector(
                onTap: vm.isUploading
                    ? null
                    : () => vm.uploadOrganizationData(),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: EcoPaper.paperDeep,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: EcoPaper.rule),
                      ),
                      child: vm.isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: EcoPaper.survey,
                              ),
                            )
                          : const Icon(
                              Icons.cloud_upload,
                              color: EcoPaper.survey,
                              size: 20,
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "UPLOAD DATA",
                      style: EcoPaper.label(color: EcoPaper.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: EcoPaper.data(size: 18),
        ),
        Text(
          label,
          style: EcoPaper.label(color: EcoPaper.inkFaint),
        ),
      ],
    );
  }

  Widget _verticalDivider() =>
      Container(height: 40, width: 1, color: EcoPaper.rule);

  // --- 📦 REPORT CARD (With Moderation Menu) ---
  Widget _buildReportCard(
    BuildContext context,
    CommunityReport report,
    CommunityViewModel vm,
  ) {
    final isPlanting = report.type == 'planting';
    final isPending = report.status == 'pending';
    // This app has no sign-in, so no post can be proven to belong to the
    // reader. Ownership stays false and the delete item is withheld; the
    // previous check compared against a shared literal, which offered Delete
    // on every in-app post to every user. Wire this to a real uid when
    // authentication lands.

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: EcoPaper.paperRaised,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isPending ? EcoPaper.amber : EcoPaper.rule,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A232019),
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCardImage(report.imageUrl, report.tag, isPending),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPlanting ? Icons.park : Icons.warning_amber,
                      color: isPlanting ? EcoPaper.okGreen : EcoPaper.fire,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report.userName,
                        style: const TextStyle(
                          color: EcoPaper.ink,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 3-DOT MENU (Report / Block / Delete)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: EcoPaper.inkFaint,
                        size: 20,
                      ),
                      color: EcoPaper.paperRaised,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                        side: const BorderSide(color: EcoPaper.rule),
                      ),
                      onSelected: (value) =>
                          _handleMenuAction(context, value, report, vm),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                color: EcoPaper.amber,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Report Post",
                                style: TextStyle(color: EcoPaper.ink),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'block',
                          child: Row(
                            children: [
                              Icon(
                                Icons.block,
                                color: EcoPaper.fire,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Block User",
                                style: TextStyle(color: EcoPaper.ink),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  report.locationName,
                  style: const TextStyle(
                    color: EcoPaper.inkFaint,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  report.description,
                  style: const TextStyle(
                    color: EcoPaper.inkSoft,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (isPlanting)
                  Text(
                    "🌱 +${report.treeCount} Trees Added to Canopy",
                    style: const TextStyle(
                      color: EcoPaper.okGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                if (isPending)
                  const Text(
                    "⚠️ Pending Agent Verification",
                    style: TextStyle(
                      color: EcoPaper.amber,
                      fontStyle: FontStyle.italic,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    CommunityReport report,
    CommunityViewModel vm,
  ) {
    HapticFeedback.mediumImpact();

    switch (action) {
      case 'report':
        _showReportDialog(context, report, vm);
        break;
      case 'block':
        _showBlockConfirmation(context, report, vm);
        break;
      case 'delete':
        _showDeleteConfirmation(context, report, vm);
        break;
    }
  }

  void _showReportDialog(
    BuildContext context,
    CommunityReport report,
    CommunityViewModel vm,
  ) {
    String? selectedReason;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: EcoPaper.paper,
            border: Border(top: BorderSide(color: EcoPaper.rule)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag, color: EcoPaper.amber),
                  const SizedBox(width: 12),
                  Text(
                    "Report Post",
                    style: GoogleFonts.lora(
                      color: EcoPaper.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Why are you reporting this post?",
                style: GoogleFonts.inter(
                  color: EcoPaper.inkSoft,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ...ModerationService.reportReasons.map(
                (reason) => GestureDetector(
                  onTap: () => setState(() => selectedReason = reason),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectedReason == reason
                          ? EcoPaper.paperDeep
                          : EcoPaper.paperRaised,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: selectedReason == reason
                            ? EcoPaper.amber
                            : EcoPaper.rule,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedReason == reason
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selectedReason == reason
                              ? EcoPaper.amber
                              : EcoPaper.inkFaint,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          reason,
                          style: const TextStyle(
                            color: EcoPaper.ink,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EcoPaper.amber,
                    foregroundColor: EcoPaper.paperRaised,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  onPressed: selectedReason == null
                      ? null
                      : () async {
                          await vm.reportPost(report.id, selectedReason!);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Report submitted. Thank you!"),
                                backgroundColor: EcoPaper.okGreen,
                              ),
                            );
                          }
                        },
                  child: const Text(
                    "SUBMIT REPORT",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockConfirmation(
    BuildContext context,
    CommunityReport report,
    CommunityViewModel vm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoPaper.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: EcoPaper.rule),
        ),
        title: const Row(
          children: [
            Icon(Icons.block, color: EcoPaper.fire),
            SizedBox(width: 12),
            Text("Block User", style: TextStyle(color: EcoPaper.ink)),
          ],
        ),
        content: Text(
          "Block ${report.userName}? You won't see their posts anymore.",
          style: const TextStyle(color: EcoPaper.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: EcoPaper.inkFaint),
            ),
          ),
          TextButton(
            onPressed: () async {
              await vm.blockUser(report.userId);
              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("User blocked"),
                    backgroundColor: EcoPaper.fire,
                  ),
                );
              }
            },
            child: const Text(
              "BLOCK",
              style: TextStyle(color: EcoPaper.fire),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    CommunityReport report,
    CommunityViewModel vm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoPaper.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: EcoPaper.rule),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete, color: EcoPaper.fire),
            SizedBox(width: 12),
            Text("Delete Post", style: TextStyle(color: EcoPaper.ink)),
          ],
        ),
        content: const Text(
          "Delete this post? This action cannot be undone.",
          style: TextStyle(color: EcoPaper.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: EcoPaper.inkFaint),
            ),
          ),
          TextButton(
            onPressed: () async {
              await vm.deleteOwnPost(report.id);
              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Post deleted"),
                    backgroundColor: EcoPaper.fire,
                  ),
                );
              }
            },
            child: const Text(
              "DELETE",
              style: TextStyle(color: EcoPaper.fire),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardImage(String imageUrl, String tag, bool isPending) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: imageUrl.trim().isEmpty
                ? Container(
                    color: EcoPaper.paperDeep,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: EcoPaper.inkFaint,
                      size: 40,
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: EcoPaper.paperDeep,
                        child: const Icon(
                          Icons.image_not_supported,
                          color: EcoPaper.inkFaint,
                          size: 40,
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (isPending)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EcoPaper.amber,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Row(
                children: [
                  Icon(Icons.pending, color: EcoPaper.paperRaised, size: 12),
                  SizedBox(width: 4),
                  Text(
                    "PENDING",
                    style: TextStyle(
                      color: EcoPaper.paperRaised,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- 🛠️ SUBMISSION FLOW ---
  Widget _buildReportButton(BuildContext context) {
    return Consumer<CommunityViewModel>(
      builder: (context, vm, child) {
        return FloatingActionButton.extended(
          onPressed: () => _triggerSubmissionFlow(context, vm),
          backgroundColor: EcoPaper.survey,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
          icon: const Icon(Icons.add, color: EcoPaper.paperRaised),
          label: Text(
            "NEW REPORT",
            style: GoogleFonts.inter(
              color: EcoPaper.paperRaised,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        );
      },
    );
  }

  void _triggerSubmissionFlow(BuildContext context, CommunityViewModel vm) {
    String reportType = 'planting';
    final descController = TextEditingController();
    final treeController = TextEditingController();
    final locationController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: EcoPaper.paper,
            border: Border(top: BorderSide(color: EcoPaper.rule)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "NEW REPORT",
                style: EcoPaper.label(size: 12, color: EcoPaper.ink),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _typeButton(
                      "PLANT TREES",
                      Icons.park,
                      reportType == 'planting',
                      () => setState(() => reportType = 'planting'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _typeButton(
                      "REPORT LOSS",
                      Icons.warning,
                      reportType == 'alert',
                      () => setState(() => reportType = 'alert'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: locationController,
                style: const TextStyle(color: EcoPaper.ink),
                decoration: InputDecoration(
                  labelText: "Location",
                  labelStyle: const TextStyle(color: EcoPaper.inkSoft),
                  filled: true,
                  fillColor: EcoPaper.paperRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: const BorderSide(color: EcoPaper.rule),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 3,
                style: const TextStyle(color: EcoPaper.ink),
                decoration: InputDecoration(
                  labelText: "Description",
                  labelStyle: const TextStyle(color: EcoPaper.inkSoft),
                  filled: true,
                  fillColor: EcoPaper.paperRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: const BorderSide(color: EcoPaper.rule),
                  ),
                ),
              ),
              if (reportType == 'planting') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: treeController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: EcoPaper.ink),
                  decoration: InputDecoration(
                    labelText: "Number of Trees",
                    labelStyle: const TextStyle(color: EcoPaper.inkSoft),
                    filled: true,
                    fillColor: EcoPaper.paperRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: const BorderSide(color: EcoPaper.rule),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: reportType == 'planting'
                        ? EcoPaper.survey
                        : EcoPaper.fire,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  onPressed: vm.isUploading
                      ? null
                      : () async {
                          if (locationController.text.isEmpty) return;
                          final newReport = CommunityReport(
                            userName: "Community member",
                            // No sign-in, so no identity to record. The model
                            // default ('unknown') is used rather than a
                            // literal that pretends to name the reader.
                            locationName: locationController.text,
                            // No stand-in image. An empty url renders the
                            // neutral placeholder block instead of fetching a
                            // third-party host.
                            imageUrl: "",
                            description: descController.text,
                            tag: reportType == 'planting'
                                ? "Reforestation"
                                : "Deforestation",
                            verificationCount: 0,
                            mapLocation: const LatLng(-3.4653, -62.2159),
                            type: reportType,
                            treeCount: int.tryParse(treeController.text) ?? 0,
                            timestamp: DateTime.now(),
                          );
                          await vm.submitReport(newReport);
                          if (context.mounted) Navigator.pop(ctx);
                        },
                  child: vm.isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EcoPaper.paperRaised,
                          ),
                        )
                      : Text(
                          reportType == 'planting'
                              ? "LOG PLANTING"
                              : "SUBMIT ALERT",
                          style: const TextStyle(
                            color: EcoPaper.paperRaised,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? EcoPaper.paperDeep : EcoPaper.paperRaised,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? EcoPaper.survey : EcoPaper.rule,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? EcoPaper.survey : EcoPaper.inkFaint,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? EcoPaper.survey : EcoPaper.inkFaint,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conservation Story Model
class ConservationStory {
  final String id;
  final String title;
  final String summary;
  final String fullContent;
  final String imageUrl;
  final String category;
  final String location;
  final String author;
  final bool isVerified;
  final DateTime createdAt;
  final Map<String, dynamic> metrics;

  ConservationStory({
    required this.id,
    required this.title,
    required this.summary,
    required this.fullContent,
    required this.imageUrl,
    required this.category,
    required this.location,
    required this.author,
    required this.isVerified,
    required this.createdAt,
    required this.metrics,
  });

  factory ConservationStory.fromMap(Map<String, dynamic> map, String docId) {
    return ConservationStory(
      id: docId,
      title: map['title'] ?? 'Untitled',
      summary: map['summary'] ?? '',
      fullContent: map['full_content'] ?? map['summary'] ?? '',
      imageUrl: map['image_url'] ?? '',
      category: map['category'] ?? 'general',
      location: map['location'] ?? 'Unknown',
      author: map['author'] ?? 'EcoLens Team',
      isVerified: map['is_verified'] ?? true,
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metrics: Map<String, dynamic>.from(map['metrics'] ?? {}),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Climate-Event card helper widgets
// Small tag chip used in the Pakistan featured card and the
// dual-CTA button for picking between story-map / documentary.
// ═══════════════════════════════════════════════════════════════

class _MetaChip extends StatelessWidget {
  final String text;
  const _MetaChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EcoPaper.paperDeep,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: EcoPaper.rule),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: EcoPaper.inkSoft,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool primary;
  final VoidCallback onTap;

  const _FormatButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: EcoPaper.paperRaised,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: primary ? EcoPaper.survey : EcoPaper.rule,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: primary ? EcoPaper.survey : EcoPaper.inkSoft,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        color: primary ? EcoPaper.survey : EcoPaper.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sublabel,
                      style: GoogleFonts.inter(
                        color: EcoPaper.inkFaint,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
