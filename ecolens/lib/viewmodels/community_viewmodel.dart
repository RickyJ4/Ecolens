import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ecolens/data/community_data.dart';
import 'package:ecolens/services/photo_upload_service.dart';
import 'package:ecolens/services/moderation_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:firebase_storage/firebase_storage.dart';

class CommunityViewModel extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PhotoUploadService _photoService = PhotoUploadService();
  final ImagePicker _picker = ImagePicker();

  List<CommunityReport> _allReports = [];
  List<String> _blockedUserIds = [];

  // Exposed reports (filtered for blocked users and hidden posts)
  List<CommunityReport> get reports => _allReports
      .where((r) => !r.isHidden)
      .where((r) => !_blockedUserIds.contains(r.userId))
      .toList();

  // 📸 Photo Upload State
  List<File> _selectedPhotos = [];
  List<File> get selectedPhotos => _selectedPhotos;
  bool _isUploading = false;
  bool get isUploading => _isUploading;
  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  // 📊 LIVE STATS
  int get totalTreesPlanted => reports
      .where((r) => r.type == 'planting')
      .fold(0, (sum, item) => sum + item.treeCount);

  String get topPlantingRegion {
    if (reports.isEmpty) return "N/A";
    final map = <String, int>{};
    for (var r in reports.where((r) => r.type == 'planting')) {
      map[r.locationName] = (map[r.locationName] ?? 0) + r.treeCount;
    }
    if (map.isEmpty) return "None";
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  CommunityViewModel() {
    _initLiveFeed();
    _loadBlockedUsers();
  }

  void _initLiveFeed() {
    _db
        .collection('community_reports')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
          _allReports = snapshot.docs
              .map((doc) => CommunityReport.fromFirestore(doc.data(), doc.id))
              .toList();
          notifyListeners();
        });
  }

  Future<void> _loadBlockedUsers() async {
    _blockedUserIds = await ModerationService.getBlockedUsers();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // MODERATION METHODS
  // ═══════════════════════════════════════════════════════════════

  /// Report a post for review
  Future<void> reportPost(
    String postId,
    String reason, {
    String? details,
  }) async {
    await ModerationService.reportPost(
      postId: postId,
      reason: reason,
      additionalDetails: details,
    );
    notifyListeners();
  }

  /// Block a user - their posts will be hidden from feed
  Future<void> blockUser(String userId) async {
    await ModerationService.blockUser(userId);
    _blockedUserIds.add(userId);
    notifyListeners();
  }

  /// Unblock a user
  Future<void> unblockUser(String userId) async {
    await ModerationService.unblockUser(userId);
    _blockedUserIds.remove(userId);
    notifyListeners();
  }

  /// Get list of blocked user IDs
  List<String> get blockedUserIds => List.unmodifiable(_blockedUserIds);

  /// Delete own post (soft-delete for immediate removal)
  Future<void> deleteOwnPost(String postId) async {
    await ModerationService.deletePost(postId);
    // Immediately remove from local list for instant UI update
    _allReports.removeWhere((r) => r.id == postId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // PHOTO PICKING
  // ═══════════════════════════════════════════════════════════════

  Future<void> pickPhotos() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 80,
        limit: 5 - _selectedPhotos.length,
      );

      if (images.isNotEmpty) {
        _selectedPhotos.addAll(images.map((x) => File(x.path)));
        notifyListeners();
      }
    } catch (e) {
      print("Error picking photos: $e");
    }
  }

  void removePhoto(int index) {
    if (index >= 0 && index < _selectedPhotos.length) {
      _selectedPhotos.removeAt(index);
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ORGANIZATION UPLOAD PORTAL
  // ═══════════════════════════════════════════════════════════════

  Future<void> uploadOrganizationData() async {
    try {
      _isUploading = true;
      notifyListeners();

      // 1. Pick File (Any size)
      fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['csv', 'json', 'geojson', 'zip'],
      );

      if (result != null) {
        final platformFile = result.files.single;
        final file = File(platformFile.path!);
        final fileName = platformFile.name;

        debugPrint("📂 Selecting file: $fileName (${platformFile.size} bytes)");

        // 2. Upload to Firebase Storage
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('restoration_data')
            .child('${DateTime.now().millisecondsSinceEpoch}_$fileName');

        final uploadTask = storageRef.putFile(file);

        uploadTask.snapshotEvents.listen((event) {
          _uploadProgress = event.bytesTransferred / event.totalBytes;
          notifyListeners();
        });

        await uploadTask;
        final downloadUrl = await storageRef.getDownloadURL();

        // 3. Register Upload in Firestore
        await _db.collection('organization_uploads').add({
          'fileName': fileName,
          'url': downloadUrl,
          'size': platformFile.size,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'processing', // Backend agent will pick this up
          'uploadedBy': 'Current Org User', // Replace with Auth ID
        });

        debugPrint("✅ Upload Complete: $downloadUrl");
      }
    } catch (e) {
      debugPrint("❌ Upload Error: $e");
    } finally {
      _isUploading = false;
      _uploadProgress = 0.0;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SUBMISSION
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitReport(CommunityReport report) async {
    _isUploading = true;
    _uploadProgress = 0;
    notifyListeners();

    try {
      List<String> photoUrls = [];
      String mainImageUrl = report.imageUrl;

      if (_selectedPhotos.isNotEmpty) {
        String tempId = DateTime.now().millisecondsSinceEpoch.toString();

        photoUrls = await _photoService.uploadPhotos(
          _selectedPhotos,
          tempId,
          onProgress: (index, percent) {},
        );

        if (photoUrls.isNotEmpty) {
          mainImageUrl = photoUrls.first;
        }
      }

      final initialStatus = report.type == 'alert' ? 'pending' : 'verified';

      await _db.collection('community_reports').add({
        'userName': report.userName,
        'userId': report.userId,
        'locationName': report.locationName,
        'description': report.description,
        'imageUrl': mainImageUrl,
        'photoUrls': photoUrls,
        'tag': report.tag,
        'lat': report.mapLocation.latitude,
        'lng': report.mapLocation.longitude,
        'verifications': 0,
        'timestamp': FieldValue.serverTimestamp(),
        'type': report.type,
        'status': initialStatus,
        'treeCount': report.treeCount,
        'isHidden': false,
        'reportCount': 0,
        'reportedBy': [],
      });

      _selectedPhotos.clear();
    } catch (e) {
      print("Submission Error: $e");
      rethrow;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }
}
