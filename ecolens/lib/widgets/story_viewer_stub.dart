/// Stub implementation for non-web platforms
/// This file is imported on mobile platforms

import 'package:flutter/material.dart';
import 'package:ecolens/model/location_model.dart';

/// Stub widget - on mobile, we use InAppWebView directly in premium_ar_screen.dart
class WebStoryViewer extends StatelessWidget {
  final IntelligenceNode? node;
  final Map<String, dynamic>? storyConfig;
  final Function(Map<String, dynamic>)? onMessage;

  const WebStoryViewer({
    super.key,
    this.node,
    this.storyConfig,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    // This should never be called on mobile - we use InAppWebView
    return const Center(
      child: Text('Story viewer not available'),
    );
  }
}

/// Check if running on web - always false for stub
bool get isWebPlatform => false;
