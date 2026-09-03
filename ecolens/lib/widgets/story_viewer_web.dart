/// Web implementation of the story viewer using iframe and postMessage
/// This file is only imported on web platforms

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ecolens/model/location_model.dart';

/// Web-compatible story viewer using iframe
class WebStoryViewer extends StatefulWidget {
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
  State<WebStoryViewer> createState() => _WebStoryViewerState();
}

class _WebStoryViewerState extends State<WebStoryViewer> {
  static int _viewIdCounter = 0;
  late final String _viewId;
  html.IFrameElement? _iframe;
  bool _iframeReady = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'story-viewer-${_viewIdCounter++}';
    _registerView();
  }

  void _registerView() {
    // Create iframe element
    _iframe = html.IFrameElement()
      ..src = 'assets/assets/story_viewer/index.html'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture'
      ..allowFullscreen = true;

    // Listen for messages from iframe
    html.window.onMessage.listen(_handleMessage);

    // Register the view factory
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => _iframe!,
    );
  }

  void _handleMessage(html.MessageEvent event) {
    if (event.data == null) return;

    try {
      Map<String, dynamic> data;
      if (event.data is String) {
        data = jsonDecode(event.data as String);
      } else if (event.data is Map) {
        data = Map<String, dynamic>.from(event.data as Map);
      } else {
        return;
      }

      final type = data['type'] as String?;
      if (type == null) return;

      debugPrint('[WebStoryViewer] Received: $type');

      // Handle bridge ready
      if (type == 'bridgeReady') {
        setState(() => _iframeReady = true);
        // Send story config if available
        if (widget.storyConfig != null) {
          _sendToIframe('initStory', {'config': widget.storyConfig});
        }
      }

      // Forward to parent handler
      widget.onMessage?.call(data);
    } catch (e) {
      debugPrint('[WebStoryViewer] Error parsing message: $e');
    }
  }

  void _sendToIframe(String type, Map<String, dynamic> data) {
    if (_iframe?.contentWindow == null) return;

    final message = {'type': type, ...data};
    _iframe!.contentWindow!.postMessage(jsonEncode(message), '*');
    debugPrint('[WebStoryViewer] Sent: $type');
  }

  @override
  void didUpdateWidget(WebStoryViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Send new config if changed
    if (widget.storyConfig != null &&
        widget.storyConfig != oldWidget.storyConfig &&
        _iframeReady) {
      _sendToIframe('initStory', {'config': widget.storyConfig});
    }
  }

  /// Send a message to the story viewer
  void sendMessage(String type, Map<String, dynamic> data) {
    _sendToIframe(type, data);
  }

  /// Notify narrator finished
  void narratorFinished(int chapterIndex) {
    _sendToIframe('narratorFinished', {'chapter': chapterIndex});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Iframe viewer
        HtmlElementView(viewType: _viewId),

        // Loading overlay until iframe is ready
        if (!_iframeReady)
          Container(
            color: const Color(0xFF0D1117),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFF00D26A),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading immersive experience...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Check if running on web
bool get isWebPlatform => true;
