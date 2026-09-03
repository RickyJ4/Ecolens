/// Web implementation for story viewer
/// This file is only used on web platforms where dart:html is available
/// On web, we navigate directly to the story viewer HTML page (no iframe)

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';

/// Launch the story viewer as a standalone page on web
/// This navigates directly to the story viewer HTML, avoiding iframe issues
void launchWebStoryViewer(Map<String, dynamic> storyConfig) {
  debugPrint('[WebStoryViewer] Launching story viewer...');

  // Store config in localStorage for the story viewer to pick up
  final configJson = jsonEncode(storyConfig);
  html.window.localStorage['ecolens_story_config'] = configJson;
  debugPrint('[WebStoryViewer] Config stored in localStorage');
  debugPrint('[WebStoryViewer] Config length: ${configJson.length}');

  // Also store in sessionStorage as backup
  html.window.sessionStorage['ecolens_story_config'] = configJson;
  debugPrint('[WebStoryViewer] Also stored in sessionStorage');

  // Verify storage worked
  final verify = html.window.localStorage['ecolens_story_config'];
  debugPrint('[WebStoryViewer] Verification read: ${verify != null ? "OK" : "FAILED"}');

  // Small delay to ensure storage is committed before navigation
  Future.delayed(const Duration(milliseconds: 200), () {
    debugPrint('[WebStoryViewer] Navigating to story viewer...');
    final currentUrl = html.window.location.href;
    debugPrint('[WebStoryViewer] Current URL: $currentUrl');

    // Also pass a minimal flag via URL hash as backup indicator
    // The full config is too large for URL, but we can signal that localStorage has data
    html.window.location.href = 'assets/assets/story_viewer/index.html#hasConfig=true';
  });
}

/// Check if we're returning from the story viewer
bool checkReturnFromStoryViewer() {
  return html.window.localStorage.containsKey('ecolens_story_complete');
}

/// Clear return flag
void clearReturnFlag() {
  html.window.localStorage.remove('ecolens_story_complete');
}

// Legacy functions for compatibility (keep signatures but simplified)
Widget createWebIframeViewer({
  required String assetPath,
  required Function(Map<String, dynamic>) onMessage,
  required Function() onReady,
  String? viewId,
}) {
  // Not used anymore - we navigate directly
  return const SizedBox.shrink();
}

void registerIframeViewFactory(String viewId) {}

void sendMessageToIframe(String viewId, Map<String, dynamic> message) {}
