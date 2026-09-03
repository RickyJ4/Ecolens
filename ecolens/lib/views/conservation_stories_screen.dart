import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecolens/core/gis_theme.dart';

/// Conservation Stories Feed
///
/// A modern, engaging feed of conservation stories with:
/// - Full-width hero images
/// - Location badges + verification status
/// - Impact metrics (trees planted, carbon, etc.)
/// - Engagement (likes, shares, saves)
/// - Expandable full story content
class ConservationStoriesScreen extends StatefulWidget {
  const ConservationStoriesScreen({super.key});

  @override
  State<ConservationStoriesScreen> createState() => _ConservationStoriesScreenState();
}

class _ConservationStoriesScreenState extends State<ConservationStoriesScreen> {
  final ScrollController _scrollController = ScrollController();
  List<ConservationStory> _stories = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  final List<Map<String, dynamic>> _filters = [
    {'id': 'all', 'label': 'All Stories', 'icon': Icons.auto_stories},
    {'id': 'restoration', 'label': 'Restoration', 'icon': Icons.forest},
    {'id': 'wildlife', 'label': 'Wildlife', 'icon': Icons.pets},
    {'id': 'community', 'label': 'Community', 'icon': Icons.people},
    {'id': 'research', 'label': 'Research', 'icon': Icons.science},
  ];

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() => _isLoading = true);

    try {
      // Load from Firestore
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('conservation_stories')
          .orderBy('created_at', descending: true)
          .limit(20)
          .get();

      if (snapshot.docs.isEmpty) {
        // Use sample data if no stories exist
        _stories = _getSampleStories();
      } else {
        _stories = snapshot.docs
            .map((doc) => ConservationStory.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading stories: $e');
      _stories = _getSampleStories();
    }

    setState(() => _isLoading = false);
  }

  List<ConservationStory> _getSampleStories() {
    return [
      ConservationStory(
        id: '1',
        title: 'Amazon Reforestation: 50,000 Trees Milestone',
        summary: 'Local community achieves major milestone in restoring degraded pastureland to native forest.',
        fullContent: '''After three years of dedicated effort, the community of São Félix do Xingu has achieved a remarkable milestone: 50,000 native trees now grow where cattle pastures once dominated the landscape.

The project, supported by local NGOs and international funding, has not only restored forest cover but created sustainable livelihoods for over 200 families through agroforestry systems.

"We're not just planting trees," says Maria Santos, project coordinator. "We're rebuilding an entire ecosystem while providing food security for our community."

The restored areas now show signs of wildlife return, including jaguar tracks spotted for the first time in decades.''',
        imageUrl: 'https://images.unsplash.com/photo-1516026672322-bc52d61a55d5?w=800',
        category: 'restoration',
        location: 'Pará, Brazil',
        author: 'EcoLens Team',
        isVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        metrics: {
          'trees_planted': 50000,
          'carbon_tonnes': 2500,
          'hectares': 120,
          'families': 200,
        },
        engagement: {'likes': 1234, 'shares': 89, 'saves': 456},
      ),
      ConservationStory(
        id: '2',
        title: 'Endangered Jaguar Population Recovery',
        summary: 'Camera traps reveal growing jaguar population in protected corridor connecting two national parks.',
        fullContent: '''New data from wildlife monitoring cameras has confirmed what conservationists hoped: jaguar populations are rebounding in the Atlantic Forest corridor.

Twelve individual jaguars have been identified in the past year, up from just three confirmed individuals in 2020. This remarkable recovery is attributed to habitat restoration efforts and community-based protection programs.

The corridor, which connects Iguaçu National Park to coastal reserves, represents one of the last viable habitats for jaguars in this critically endangered ecosystem.''',
        imageUrl: 'https://images.unsplash.com/photo-1546182990-dffeafbe841d?w=800',
        category: 'wildlife',
        location: 'Paraná, Brazil',
        author: 'Panthera Brasil',
        isVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        metrics: {
          'jaguars_identified': 12,
          'camera_locations': 45,
          'corridor_km': 150,
        },
        engagement: {'likes': 2341, 'shares': 234, 'saves': 567},
      ),
      ConservationStory(
        id: '3',
        title: 'Indigenous Rangers Lead Fire Prevention Success',
        summary: 'Traditional fire management techniques reduce wildfire incidence by 80% in protected territory.',
        fullContent: '''The Kayapó Indigenous Territory has seen an 80% reduction in destructive wildfires thanks to a program that combines traditional knowledge with modern monitoring technology.

Indigenous rangers use satellite alerts from EcoLens combined with generations of fire management wisdom to conduct controlled burns that prevent catastrophic fires.

"Our ancestors managed these forests for thousands of years," explains Chief Raoni Metuktire. "Now we use new tools to continue this ancient responsibility."

The success has attracted international attention, with similar programs being planned across the Amazon basin.''',
        imageUrl: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800',
        category: 'community',
        location: 'Mato Grosso, Brazil',
        author: 'Instituto Raoni',
        isVerified: true,
        createdAt: DateTime.now().subtract(const Duration(days: 8)),
        metrics: {
          'fire_reduction_percent': 80,
          'rangers_trained': 45,
          'hectares_protected': 3000000,
        },
        engagement: {'likes': 3456, 'shares': 567, 'saves': 890},
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GISTheme.backgroundDark,
      body: RefreshIndicator(
        onRefresh: _loadStories,
        color: GISTheme.accentGreen,
        backgroundColor: GISTheme.surfaceLight,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // App bar
            _buildAppBar(),

            // Filter chips
            SliverToBoxAdapter(child: _buildFilterChips()),

            // Impact summary
            SliverToBoxAdapter(child: _buildImpactSummary()),

            // Stories list
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: GISTheme.accentGreen),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final story = _filteredStories[index];
                    return _buildStoryCard(story);
                  },
                  childCount: _filteredStories.length,
                ),
              ),

            // Bottom padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showStoryBuilder,
        backgroundColor: GISTheme.accentGreen,
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text('Share Story'),
      ),
    );
  }

  List<ConservationStory> get _filteredStories {
    if (_selectedFilter == 'all') return _stories;
    return _stories.where((s) => s.category == _selectedFilter).toList();
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: GISTheme.backgroundDark,
      title: Text(
        'Conservation Stories',
        style: GISTheme.headingLarge,
      ),
      // Search and notifications were removed: both were icons with empty
      // callbacks. An app bar with no actions is honest; one with two inert
      // icons is not.
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter['id'];

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              onSelected: (selected) {
                HapticFeedback.selectionClick();
                setState(() => _selectedFilter = filter['id']);
              },
              avatar: Icon(
                filter['icon'] as IconData,
                size: 16,
                color: isSelected ? GISTheme.backgroundDark : GISTheme.textSecondary,
              ),
              label: Text(filter['label']),
              labelStyle: TextStyle(
                color: isSelected ? GISTheme.backgroundDark : GISTheme.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              backgroundColor: GISTheme.surfaceLight,
              selectedColor: GISTheme.accentGreen,
              side: BorderSide(
                color: isSelected ? GISTheme.accentGreen : GISTheme.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImpactSummary() {
    // Calculate totals from stories
    int totalTrees = 0;
    int totalCarbon = 0;
    int totalHectares = 0;

    for (final story in _stories) {
      totalTrees += (story.metrics['trees_planted'] as int?) ?? 0;
      totalCarbon += (story.metrics['carbon_tonnes'] as int?) ?? 0;
      totalHectares += (story.metrics['hectares'] as int?) ?? 0;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: GISTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco, color: GISTheme.accentGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                'COMMUNITY IMPACT',
                style: GISTheme.labelSmall.copyWith(
                  color: GISTheme.textLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _impactMetric(
                  Icons.forest,
                  '${_formatNumber(totalTrees)}',
                  'Trees Planted',
                  GISTheme.accentGreen,
                ),
              ),
              Expanded(
                child: _impactMetric(
                  Icons.cloud,
                  '${_formatNumber(totalCarbon)}t',
                  'Carbon Stored',
                  GISTheme.accentBlue,
                ),
              ),
              Expanded(
                child: _impactMetric(
                  Icons.landscape,
                  '${_formatNumber(totalHectares)}',
                  'Hectares Restored',
                  GISTheme.accentOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _impactMetric(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GISTheme.headingMedium.copyWith(fontSize: 18),
        ),
        Text(
          label,
          style: GISTheme.labelSmall.copyWith(color: GISTheme.textTertiary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStoryCard(ConservationStory story) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: GISTheme.panelDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  story.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: GISTheme.surfaceDark,
                    child: const Center(
                      child: Icon(Icons.image_not_supported, color: GISTheme.textTertiary),
                    ),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: GISTheme.surfaceDark,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: GISTheme.accentGreen,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Category badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(story.category).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getCategoryIcon(story.category),
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        story.category.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Verified badge
              if (story.isVerified)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: GISTheme.accentGreen.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.verified,
                      color: Colors.white,
                      size: 16,
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
                // Location and author
                Row(
                  children: [
                    Icon(Icons.location_on, color: GISTheme.textTertiary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      story.location,
                      style: GISTheme.labelSmall.copyWith(color: GISTheme.textTertiary),
                    ),
                    const Spacer(),
                    Text(
                      story.author,
                      style: GISTheme.labelSmall.copyWith(color: GISTheme.accentBlue),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Title
                Text(
                  story.title,
                  style: GISTheme.headingMedium.copyWith(fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Summary
                Text(
                  story.summary,
                  style: GISTheme.bodySmall.copyWith(
                    color: GISTheme.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 16),

                // Impact metrics
                _buildStoryMetrics(story),

                const SizedBox(height: 16),

                // Engagement and actions
                Row(
                  children: [
                    _engagementButton(
                      Icons.favorite_border,
                      _formatNumber(story.engagement['likes'] ?? 0),
                      GISTheme.accentRed,
                    ),
                    const SizedBox(width: 16),
                    _engagementButton(
                      Icons.share_outlined,
                      _formatNumber(story.engagement['shares'] ?? 0),
                      GISTheme.accentBlue,
                    ),
                    const SizedBox(width: 16),
                    _engagementButton(
                      Icons.bookmark_border,
                      _formatNumber(story.engagement['saves'] ?? 0),
                      GISTheme.accentOrange,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _showFullStory(story),
                      child: Row(
                        children: [
                          Text(
                            'Read More',
                            style: TextStyle(
                              color: GISTheme.accentGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward,
                            color: GISTheme.accentGreen,
                            size: 16,
                          ),
                        ],
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

  Widget _buildStoryMetrics(ConservationStory story) {
    final metrics = story.metrics;
    if (metrics.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics.entries.take(3).map((entry) {
        final label = _formatMetricLabel(entry.key);
        final value = _formatMetricValue(entry.key, entry.value);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: GISTheme.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: GISTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GISTheme.labelSmall.copyWith(
                  color: GISTheme.accentGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GISTheme.labelSmall.copyWith(color: GISTheme.textTertiary),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Plain counts, not controls. There is no engagement action behind these
  /// yet, so they do not invite or acknowledge a tap.
  Widget _engagementButton(IconData icon, String count, Color color) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          Text(
            count,
            style: GISTheme.labelSmall.copyWith(color: GISTheme.textSecondary),
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
            color: GISTheme.backgroundDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: GISTheme.border,
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
                      // Hero image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
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
                        style: GISTheme.headingLarge.copyWith(fontSize: 22),
                      ),

                      const SizedBox(height: 12),

                      // Meta
                      Row(
                        children: [
                          if (story.isVerified) ...[
                            const Icon(
                              Icons.verified,
                              color: GISTheme.accentGreen,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            story.author,
                            style: GISTheme.bodySmall.copyWith(color: GISTheme.accentBlue),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.location_on, color: GISTheme.textTertiary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            story.location,
                            style: GISTheme.bodySmall.copyWith(color: GISTheme.textTertiary),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Full content
                      Text(
                        story.fullContent,
                        style: GISTheme.bodyLarge.copyWith(
                          height: 1.7,
                          color: GISTheme.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Impact metrics
                      if (story.metrics.isNotEmpty) ...[
                        Text(
                          'IMPACT',
                          style: GISTheme.labelSmall.copyWith(
                            color: GISTheme.textLabel,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStoryMetrics(story),
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

  void _showStoryBuilder() {
    // TODO: Implement story builder form
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Story builder coming soon!'),
        backgroundColor: GISTheme.surfaceLight,
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'restoration':
        return GISTheme.accentGreen;
      case 'wildlife':
        return GISTheme.accentOrange;
      case 'community':
        return GISTheme.accentPurple;
      case 'research':
        return GISTheme.accentBlue;
      default:
        return GISTheme.textTertiary;
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

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatMetricLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
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
  final Map<String, int> engagement;

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
    required this.engagement,
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
      author: map['author'] ?? 'Anonymous',
      isVerified: map['is_verified'] ?? false,
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metrics: Map<String, dynamic>.from(map['metrics'] ?? {}),
      engagement: Map<String, int>.from(map['engagement'] ?? {}),
    );
  }
}
