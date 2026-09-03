import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class CommunityReport {
  final String id;
  final String userName;
  final String userId;
  final String locationName;
  final String description;
  final String imageUrl;
  final List<String> photoUrls;
  final String tag;
  final int verificationCount;
  final LatLng mapLocation;
  final DateTime timestamp;

  // Report type and status
  final String type; // 'planting' or 'alert'
  final String status; // 'verified', 'pending'
  final int treeCount;

  // Moderation fields
  final bool isHidden;
  final int reportCount;
  final List<String> reportedBy;

  CommunityReport({
    this.id = '',
    required this.userName,
    this.userId = 'unknown',
    required this.locationName,
    required this.description,
    required this.imageUrl,
    this.photoUrls = const [],
    required this.tag,
    required this.verificationCount,
    required this.mapLocation,
    required this.timestamp,
    this.type = 'alert',
    this.status = 'verified',
    this.treeCount = 0,
    this.isHidden = false,
    this.reportCount = 0,
    this.reportedBy = const [],
  });

  factory CommunityReport.fromFirestore(Map<String, dynamic> data, String id) {
    return CommunityReport(
      id: id,
      userName: data['userName'] ?? 'Anonymous',
      userId: data['userId'] ?? 'unknown',
      locationName: data['locationName'] ?? 'Unknown Sector',
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      tag: data['tag'] ?? 'General',
      verificationCount: data['verifications'] ?? 0,
      mapLocation: LatLng(
        data['lat']?.toDouble() ?? 0.0,
        data['lng']?.toDouble() ?? 0.0,
      ),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: data['type'] ?? 'alert',
      status: data['status'] ?? 'verified',
      treeCount: data['treeCount'] ?? 0,
      isHidden: data['isHidden'] ?? false,
      reportCount: data['reportCount'] ?? 0,
      reportedBy: List<String>.from(data['reportedBy'] ?? []),
    );
  }
}
