class WebMapBridgeSubscription {
  const WebMapBridgeSubscription();

  void dispose() {}
}

WebMapBridgeSubscription listenToWebMapBridge(
  void Function(Map<String, dynamic> payload) onEvent,
) {
  return const WebMapBridgeSubscription();
}

/// No-op off the web: the native WebView delivers fly-to requests through
/// `InAppWebViewController.evaluateJavascript` instead.
bool postToWebMap(Map<String, dynamic> message) => false;
