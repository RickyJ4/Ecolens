import 'dart:async';
import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

class WebMapBridgeSubscription {
  final StreamSubscription<html.MessageEvent> _subscription;

  const WebMapBridgeSubscription._(this._subscription);

  void dispose() {
    _subscription.cancel();
  }
}

WebMapBridgeSubscription listenToWebMapBridge(
  void Function(Map<String, dynamic> payload) onEvent,
) {
  final subscription = html.window.onMessage.listen((event) {
    final payload = _decodePayload(event.data);
    if (payload == null || payload['source'] != 'ecolens-map') return;
    onEvent(payload);
  });

  return WebMapBridgeSubscription._(subscription);
}

/// Parent → iframe delivery for the embedded MapLibre page.
///
/// flutter_inappwebview's web implementation runs `evaluateJavascript` as
/// `iframe.contentWindow.eval(...)` with every error swallowed, so a script
/// evaluated before the map document has loaded lands on the initial
/// about:blank window and is lost on navigation. `postMessage` reaches
/// whatever document the frame holds when it arrives, and the map page
/// listens for it (index.html, `ecolens_fly_to`). Callers that need
/// certainty repeat the post until the page acknowledges.
///
/// [message] is handed to the browser as a structured object, so the page
/// reads `event.data` fields directly. Returns false when no map iframe is
/// in the document yet.
bool postToWebMap(Map<String, dynamic> message) {
  final target = _findMapFrame()?.contentWindow;
  if (target == null) return false;
  try {
    target.postMessage(message, '*');
    return true;
  } catch (e) {
    debugPrint('[MapLibreWebBridge] postMessage failed: $e');
    return false;
  }
}

/// The InAppWebView iframe hosting the map: an `<iframe>` whose src points at
/// the bundled `maplibre_map` page. Flutter keeps platform-view content in
/// the light DOM, so a plain document query finds it; the shadow-root walk
/// is a fallback for embedders that slot it differently.
html.IFrameElement? _findMapFrame() {
  html.IFrameElement? match(Iterable<html.Element> candidates) {
    for (final el in candidates) {
      if (el is html.IFrameElement &&
          (el.src ?? '').contains('maplibre_map')) {
        return el;
      }
    }
    return null;
  }

  final direct = match(html.document.querySelectorAll('iframe'));
  if (direct != null) return direct;
  for (final host
      in html.document.querySelectorAll('flutter-view, flt-glass-pane')) {
    final root = host.shadowRoot;
    if (root == null) continue;
    final nested = match(root.querySelectorAll('iframe'));
    if (nested != null) return nested;
  }
  return null;
}

Map<String, dynamic>? _decodePayload(dynamic data) {
  try {
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
  } catch (e) {
    debugPrint('[MapLibreWebBridge] Message parse error: $e');
  }
  return null;
}
