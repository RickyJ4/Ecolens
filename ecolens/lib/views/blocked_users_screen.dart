import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ecolens/core/theme.dart';
import 'package:ecolens/viewmodels/community_viewmodel.dart';
import 'package:ecolens/services/moderation_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<String> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    final users = await ModerationService.getBlockedUsers();
    setState(() {
      _blockedUsers = users;
      _isLoading = false;
    });
  }

  Future<void> _unblockUser(String userId) async {
    HapticFeedback.mediumImpact();

    final vm = Provider.of<CommunityViewModel>(context, listen: false);
    await vm.unblockUser(userId);

    setState(() {
      _blockedUsers.remove(userId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User unblocked"),
          backgroundColor: EcoTheme.neonEmerald,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "BLOCKED USERS",
          style: GoogleFonts.orbitron(fontSize: 14, letterSpacing: 2),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: EcoTheme.neonEmerald),
            )
          : _blockedUsers.isEmpty
          ? _buildEmptyState()
          : _buildBlockedList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EcoTheme.neonEmerald.withOpacity(0.1),
                border: Border.all(
                  color: EcoTheme.neonEmerald.withOpacity(0.3),
                ),
              ),
              child: const Icon(
                Icons.people_outline,
                size: 48,
                color: EcoTheme.neonEmerald,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No Blocked Users",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Users you block will appear here. Their posts will be hidden from your feed.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _blockedUsers.length,
      itemBuilder: (context, index) {
        final userId = _blockedUsers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_off,
                color: Colors.redAccent,
                size: 20,
              ),
            ),
            title: Text(
              "Blocked User",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              "ID: ${userId.substring(0, userId.length > 12 ? 12 : userId.length)}...",
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _showUnblockConfirmation(userId),
              child: const Text(
                "UNBLOCK",
                style: TextStyle(
                  color: EcoTheme.neonEmerald,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showUnblockConfirmation(String userId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person_add, color: EcoTheme.neonEmerald),
            SizedBox(width: 12),
            Text("Unblock User", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          "Unblock this user? You'll see their posts in your feed again.",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _unblockUser(userId);
            },
            child: const Text(
              "UNBLOCK",
              style: TextStyle(color: EcoTheme.neonEmerald),
            ),
          ),
        ],
      ),
    );
  }
}
