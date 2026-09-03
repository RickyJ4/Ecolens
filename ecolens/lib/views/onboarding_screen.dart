import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/services/onboarding_service.dart';
import 'package:ecolens/views/main_layout.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late AnimationController _pulseController;
  late AnimationController _floatController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatAnimation;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: "Welcome to EcoLens",
      subtitle: "Environmental Intelligence",
      description:
          "EcoLens transforms satellite data into actionable environmental intelligence. Track deforestation in real-time, monitor carbon emissions, and discover endangered species — all from your pocket.",
      icon: Icons.public,
      color: EcoPaper.survey,
      gradient: const [EcoPaper.survey, EcoPaper.survey],
      tutorialSteps: [
        "Swipe through tabs to explore different features",
        "Tap markers on the map to view detailed hotspot data",
        "Use the AR Experience for immersive 3D storytelling",
      ],
    ),
    OnboardingPage(
      title: "Stories & Community",
      subtitle: "Investigations, Grounded in Place",
      description:
          "EcoLens is a visual environmental publication. Every investigation — from Vancouver's buried streams to the Pakistan 2022 floods — lives as a pin on the map and a full story-map you can read.",
      icon: Icons.auto_stories_rounded,
      color: EcoPaper.survey,
      gradient: const [EcoPaper.survey, EcoPaper.survey],
      tutorialSteps: [
        "Open the Community tab to browse published investigations",
        "Tap a story pin on the map to read it in place",
        "Follow partnership stories as they develop",
      ],
    ),
    OnboardingPage(
      title: "Interactive Map",
      subtitle: "Explore & Analyze",
      description:
          "Our satellite map shows environmental hotspots worldwide. Each marker represents verified deforestation, fire events, or biodiversity zones. Zoom in for 3D terrain and detailed analysis.",
      icon: Icons.satellite_alt,
      color: EcoPaper.survey,
      gradient: const [EcoPaper.survey, EcoPaper.survey],
      tutorialSteps: [
        "Tap any marker to see species, carbon data & restoration cost",
        "Use the Analysis Toolbar for spatial calculations",
        "Tap 'EXPERIENCE' on a card for immersive AR storytelling",
        "Open 'ENVIRONMENTAL NEWS' for the live GDACS alert wire",
      ],
    ),
    OnboardingPage(
      title: "Environmental News",
      subtitle: "The live alert wire",
      description:
          "Every alert on the GDACS wire, refreshed every 15 minutes: earthquakes, floods, cyclones, wildfires, droughts and volcanoes, each with its published alert level, severity and report. Questions the map cannot settle on its own land here as full findings.",
      icon: Icons.auto_graph,
      color: EcoPaper.survey,
      gradient: const [EcoPaper.survey, EcoPaper.survey],
      tutorialSteps: [
        "Select a hotspot from the map, then visit Insights tab",
        "View historical deforestation trends with charts",
        "See AI predictions for future forest loss",
        "Explore restoration scenarios and carbon projections",
      ],
    ),
    OnboardingPage(
      title: "AR Experience",
      subtitle: "Immersive Storytelling",
      description:
          "Step inside environmental stories with our AR Experience. Fly over 3D terrain, explore 360° panoramas of forests, and witness the impact of deforestation through cinematic narratives.",
      icon: Icons.view_in_ar,
      color: EcoPaper.survey,
      gradient: const [EcoPaper.survey, EcoPaper.survey],
      tutorialSteps: [
        "Tap 'EXPERIENCE' on any map card to launch AR mode",
        "Swipe to navigate between story chapters",
        "Listen to AI narration explaining the ecosystem",
        "Explore 360° immersive views of real locations",
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.heavyImpact();
    await OnboardingService.completeOnboarding();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainLayout(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLastPage = _currentPage == _pages.length - 1;
    final progress = (_currentPage + 1) / _pages.length;

    return Scaffold(
      backgroundColor: EcoPaper.paper,
      body: Stack(
        children: [
          // Plain paper background — no gradients, no particles.
          _buildAnimatedBackground(page),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Header with progress
                _buildHeader(progress, isLastPage),

                // Page Content
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (index) {
                      HapticFeedback.selectionClick();
                      setState(() => _currentPage = index);
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return _buildPage(_pages[index]);
                    },
                  ),
                ),

                // Bottom Controls
                _buildBottomControls(isLastPage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground(OnboardingPage page) {
    return Container(color: EcoPaper.paper);
  }

  Widget _buildHeader(double progress, bool isLastPage) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: EcoPaper.well,
            child: Text(
              "${(_currentPage + 1)}/${_pages.length}",
              style: EcoPaper.data(size: 12, color: EcoPaper.inkSoft),
            ),
          ),

          // Progress bar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: EcoPaper.rule,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    EcoPaper.survey,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
          ),

          // Skip button (hidden on last page)
          SizedBox(
            width: 60,
            child: isLastPage
                ? const SizedBox()
                : TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _controller.animateToPage(
                        _pages.length - 1,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Text(
                      "SKIP",
                      style: GoogleFonts.inter(
                        color: EcoPaper.inkFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          // Animated Icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _floatAnimation.value),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EcoPaper.paperRaised,
                          border: Border.all(color: EcoPaper.rule),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A232019),
                              offset: Offset(3, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Icon(page.icon, size: 56, color: page.color),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Subtitle — serif standfirst, editorial deck style
          Text(
            page.subtitle,
            style: EcoPaper.deck(color: EcoPaper.survey),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Title
          Text(
            page.title,
            style: EcoPaper.headline(size: 26),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            page.description,
            style: EcoPaper.body(size: 14, color: EcoPaper.inkSoft),
            textAlign: TextAlign.center,
          ),

          // Tutorial Steps
          if (page.tutorialSteps.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: EcoPaper.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                           color: EcoPaper.survey, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'How to use',
                        style: GoogleFonts.inter(
                          color: EcoPaper.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...page.tutorialSteps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: EcoPaper.paperDeep,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: EcoPaper.rule),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: EcoPaper.data(
                                  size: 11,
                                  color: EcoPaper.inkSoft,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step,
                              style: EcoPaper.body(
                                size: 13,
                                color: EcoPaper.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isLastPage) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: _currentPage == index ? 28 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? EcoPaper.survey
                      : EcoPaper.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EcoPaper.survey,
                foregroundColor: EcoPaper.paperRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
                elevation: 0,
              ),
              onPressed: _nextPage,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLastPage ? "GET STARTED" : "CONTINUE",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLastPage ? Icons.rocket_launch : Icons.arrow_forward,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final List<String> tutorialSteps;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.gradient,
    this.tutorialSteps = const [],
  });
}
