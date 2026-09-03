/// Stub implementation for non-web platforms
/// This file is used on mobile platforms where dart:html is not available

import 'package:flutter/material.dart';

/// Launch web story viewer - no-op on mobile (uses InAppWebView instead)
void launchWebStoryViewer(Map<String, dynamic> storyConfig) {
  // No-op on mobile - InAppWebView is used directly in premium_ar_screen.dart
}

/// Check return from story viewer - always false on mobile
bool checkReturnFromStoryViewer() => false;

/// Clear return flag - no-op on mobile
void clearReturnFlag() {}

/// Creates a web iframe viewer - stub returns empty container on mobile
Widget createWebIframeViewer({
  required String assetPath,
  required Function(Map<String, dynamic>) onMessage,
  required Function() onReady,
  String? viewId,
}) {
  // On mobile, we don't use iframe - return empty container
  // The InAppWebView is used instead
  return const SizedBox.shrink();
}

/// Register the iframe view factory - no-op on mobile
void registerIframeViewFactory(String viewId) {
  // No-op on mobile
}

/// Send message to iframe - no-op on mobile
void sendMessageToIframe(String viewId, Map<String, dynamic> message) {
  // No-op on mobile
}
