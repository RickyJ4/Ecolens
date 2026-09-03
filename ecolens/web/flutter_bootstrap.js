{{flutter_js}}
{{flutter_build_config}}

// Only register service worker in secure contexts (HTTPS or localhost).
// Prevents "InvalidStateError" in VS Code webviews and embedded browsers.
const canUseServiceWorker =
  window.isSecureContext &&
  'serviceWorker' in navigator &&
  (location.protocol === 'https:' || location.hostname === 'localhost');

_flutter.loader.load({
  serviceWorkerSettings: canUseServiceWorker
    ? { serviceWorkerVersion: {{flutter_service_worker_version}} }
    : null,
});
