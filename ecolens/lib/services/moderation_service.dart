import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for content moderation: reporting, blocking, and post management
class ModerationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _blockedUsersKey = 'blocked_user_ids';

  // ═══════════════════════════════════════════════════════════════
  // REPORT CONTENT
  // ═══════════════════════════════════════════════════════════════

  /// Submit a report for a post
  static Future<void> reportPost({
    required String postId,
    required String reason,
    String? reporterId,
    String? additionalDetails,
  }) async {
    await _db.collection('content_reports').add({
      'postId': postId,
      'reporterId': reporterId ?? 'anonymous',
      'reason': reason,
      'additionalDetails': additionalDetails ?? '',
      'status': 'pending', // pending, reviewed, resolved, dismissed
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Increment report count on the post
    await _db.collection('community_reports').doc(postId).update({
      'reportCount': FieldValue.increment(1),
      'reportedBy': FieldValue.arrayUnion([reporterId ?? 'anonymous']),
    });
  }

  /// Get all reports (for admin purposes)
  static Stream<QuerySnapshot> getReports() {
    return _db
        .collection('content_reports')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ═══════════════════════════════════════════════════════════════
  // BLOCK USERS
  // ═══════════════════════════════════════════════════════════════

  /// Block a user (stored locally in SharedPreferences)
  static Future<void> blockUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList(_blockedUsersKey) ?? [];
    if (!blockedList.contains(userId)) {
      blockedList.add(userId);
      await prefs.setStringList(_blockedUsersKey, blockedList);
    }
  }

  /// Unblock a user
  static Future<void> unblockUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList(_blockedUsersKey) ?? [];
    blockedList.remove(userId);
    await prefs.setStringList(_blockedUsersKey, blockedList);
  }

  /// Get list of blocked user IDs
  static Future<List<String>> getBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_blockedUsersKey) ?? [];
  }

  /// Check if a user is blocked
  static Future<bool> isUserBlocked(String userId) async {
    final blockedList = await getBlockedUsers();
    return blockedList.contains(userId);
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE/HIDE POSTS
  // ═══════════════════════════════════════════════════════════════

  /// Soft-delete a post (sets isHidden = true for immediate removal from feed)
  static Future<void> deletePost(String postId) async {
    await _db.collection('community_reports').doc(postId).update({
      'isHidden': true,
      'hiddenAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently delete a post (admin only)
  static Future<void> permanentlyDeletePost(String postId) async {
    await _db.collection('community_reports').doc(postId).delete();
  }

  // ═══════════════════════════════════════════════════════════════
  // REPORT REASONS
  // ═══════════════════════════════════════════════════════════════

  /// Standard report reasons for UI dropdown
  static List<String> get reportReasons => [
    'Spam or misleading',
    'Harassment or hate speech',
    'Inappropriate content',
    'False information',
    'Violates guidelines',
    'Other',
  ];
}
