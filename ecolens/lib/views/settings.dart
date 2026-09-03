import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/views/blocked_users_screen.dart';
import 'package:ecolens/services/onboarding_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _dataSaver = false;
  bool _locationAccess = true;
  double _refreshRate = 15;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoPaper.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: EcoPaper.ink,
        iconTheme: const IconThemeData(color: EcoPaper.ink),
        title: Text(
          "SETTINGS",
          style: EcoPaper.label(size: 12, color: EcoPaper.inkSoft),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionHeader("GENERAL"),
          _buildSwitch(
            "Push Notifications",
            "Receive critical forensic alerts",
            _notifications,
            (v) => setState(() => _notifications = v),
          ),
          _buildSwitch(
            "Location Services",
            "Enable for local risk analysis",
            _locationAccess,
            (v) => setState(() => _locationAccess = v),
          ),

          const SizedBox(height: 32),
          _sectionHeader("DATA & SYNC"),
          _buildSwitch(
            "Data Saver Mode",
            "Reduce satellite imagery resolution",
            _dataSaver,
            (v) => setState(() => _dataSaver = v),
          ),
          const SizedBox(height: 16),
          Text(
            "Sync Frequency: ${_refreshRate.toInt()} min",
            style: EcoPaper.body(size: 12, color: EcoPaper.inkSoft),
          ),
          Slider(
            value: _refreshRate,
            min: 5,
            max: 60,
            divisions: 11,
            activeColor: EcoPaper.survey,
            inactiveColor: EcoPaper.rule,
            onChanged: (v) => setState(() => _refreshRate = v),
          ),

          const SizedBox(height: 32),
          _sectionHeader("COMMUNITY"),
          _buildActionTile(
            Icons.verified_user,
            "Community Guidelines",
            subtitle: "View our zero-tolerance policy",
            color: EcoPaper.survey,
            onTap: () => _showGuidelinesDialog(),
          ),
          _buildActionTile(
            Icons.block,
            "Blocked Users",
            subtitle: "Manage blocked accounts",
            color: EcoPaper.fire,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlockedUsersScreen(),
                ),
              );
            },
          ),
          _buildActionTile(
            Icons.flag_outlined,
            "Report a Problem",
            subtitle: "Contact hello@rickyj.io",
            color: EcoPaper.amber,
            onTap: () => _launchEmail(),
          ),

          const SizedBox(height: 32),
          _sectionHeader("ACCOUNTS"),
          _buildActionTile(
            Icons.person_outline,
            "Edit Profile",
            onTap: () => _showEditProfileDialog(),
          ),
          _buildActionTile(
            Icons.logout,
            "Log Out",
            color: EcoPaper.fire,
            onTap: () => _showLogOutConfirmation(),
          ),

          const SizedBox(height: 32),
          _sectionHeader("ABOUT"),
          _buildActionTile(
            Icons.refresh,
            "Replay Tutorial",
            onTap: () => _replayTutorial(),
          ),
          _buildActionTile(Icons.info_outline, "Version 1.0.0"),
        ],
      ),
    );
  }

  void _showGuidelinesDialog() {
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _guidelineItem(
                "🌍",
                "Purpose",
                "EcoLens is a platform for environmental reporting and conservation action.",
              ),
              const SizedBox(height: 16),
              _guidelineItem(
                "⛔",
                "Zero Tolerance",
                "We have ZERO tolerance for objectionable content, hate speech, harassment, or abuse.",
              ),
              const SizedBox(height: 16),
              _guidelineItem(
                "🚫",
                "Prohibited Content",
                "No spam, misleading information, explicit material, threats, or content that violates others' rights.",
              ),
              const SizedBox(height: 16),
              _guidelineItem(
                "🛡️",
                "Enforcement",
                "Violations result in immediate content removal and account suspension. We act on all reports within 24 hours.",
              ),
              const SizedBox(height: 16),
              _guidelineItem(
                "👤",
                "Age Requirement",
                "You must be 18 years or older to use features that allow anonymous posting.",
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: EcoPaper.well,
                child: Row(
                  children: const [
                    Icon(Icons.email, color: EcoPaper.survey, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Questions? Contact hello@rickyj.io",
                        style: TextStyle(
                          color: EcoPaper.survey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CLOSE",
              style: TextStyle(color: EcoPaper.survey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidelineItem(String emoji, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: EcoPaper.ink,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  color: EcoPaper.inkSoft,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'hello@rickyj.io',
      queryParameters: {'subject': 'EcoLens App - Report a Problem'},
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Email hello@rickyj.io"),
            backgroundColor: EcoPaper.okGreen,
          ),
        );
      }
    }
  }

  Future<void> _replayTutorial() async {
    await OnboardingService.resetOnboarding();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
    }
  }

  void _showEditProfileDialog() {
    final TextEditingController nameController = TextEditingController();

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
            const Icon(Icons.person, color: EcoPaper.survey),
            const SizedBox(width: 12),
            Text(
              "Edit Profile",
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
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: EcoPaper.ink),
              decoration: InputDecoration(
                hintText: "Display Name",
                hintStyle: const TextStyle(color: EcoPaper.inkFaint),
                filled: true,
                fillColor: EcoPaper.paperDeep,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: const BorderSide(color: EcoPaper.rule),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "More profile options coming soon!",
              style: TextStyle(color: EcoPaper.inkFaint, fontSize: 12),
            ),
          ],
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
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Profile updated successfully!"),
                  backgroundColor: EcoPaper.okGreen,
                ),
              );
            },
            child: const Text(
              "SAVE",
              style: TextStyle(color: EcoPaper.survey),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogOutConfirmation() {
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
            const Icon(Icons.logout, color: EcoPaper.fire),
            const SizedBox(width: 12),
            Text(
              "Log Out",
              style: GoogleFonts.lora(
                color: EcoPaper.ink,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          "Are you sure you want to log out? You'll need to sign in again to access your data.",
          style: TextStyle(color: EcoPaper.inkSoft, height: 1.5),
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
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to login/onboarding screen
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
            },
            child: const Text(
              "LOG OUT",
              style: TextStyle(color: EcoPaper.fire),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: EcoPaper.label(color: EcoPaper.inkFaint),
      ),
    );
  }

  Widget _buildSwitch(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: EcoPaper.flat,
      child: SwitchListTile(
        activeColor: EcoPaper.survey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(
            color: EcoPaper.ink,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: EcoPaper.inkFaint, fontSize: 10),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String title, {
    String? subtitle,
    Color color = EcoPaper.ink,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: EcoPaper.flat,
      child: ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(title, style: TextStyle(color: color, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(
                  color: EcoPaper.inkFaint,
                  fontSize: 10,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: EcoPaper.inkFaint,
          size: 14,
        ),
        onTap: onTap ?? () {},
      ),
    );
  }
}
