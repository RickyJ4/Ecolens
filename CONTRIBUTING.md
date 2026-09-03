# Contributing to EcoLens

Thanks for looking. EcoLens is small and opinionated; the rules below are what keep it trustworthy.

## The data-integrity gate

A pull request is declined, regardless of code quality, if it:

- shows a number that is not a measurement or a source-published figure (no ratio-derived populations, no severity-to-percentage tables, no default risk scores);
- sums GDACS impact reports (they nest and supersede each other);
- draws a buffer, zone or route the source did not publish;
- adds points, streaks, badges, progress counters or any engagement mechanic.

If a figure cannot be sourced, remove the section. Do not caveat it.

## Setup

See the README for prerequisites, secrets and deploy commands. Secrets are never committed: use `firebase functions:secrets:set` for functions and `--dart-define` for the Flutter build.

## Working on the map (`ecolens/assets/maplibre_map/`)

- Modules are plain IIFEs on `window.*`, MapLibre GL JS 5.1, no bundler.
- Run `node --check` on every file you touch.
- Bump the `?v=` cache stamp in `index.html` and the bridge banner in `js/atlas-bridge.js` on every change. Hosting caches for up to an hour.
- Labels, colours and type follow the Paper & Ink system in `lib/core/theme.dart` (`EcoPaper`): one accent colour, Lora for judgement, Inter for controls, JetBrains Mono for numbers.

## Working on the Flutter shell (`ecolens/lib/`)

- MVVM with `provider`. Views read view-models; view-models own network and state.
- `flutter analyze` must report no errors in the files you touch.
- Branding is exactly "EcoLens · Environmental Intelligence".

## Working on functions (`ecolens/functions/`)

- Python on Firebase Functions Gen 2.
- Keep scheduled jobs idempotent and cheap: read one metadata document, write only what changed.
- Any HTTP trigger that mutates data stays closed unless `ADMIN_TRIGGER_TOKEN` is bound.

## Pull requests

1. One change per PR, with the reason in the description.
2. State the data source and time window for anything new that is displayed.
3. Say what you verified and how: a curl, a screenshot, a Node run.

## Licensing

The code is under the Apache License, Version 2.0. By opening a pull request you agree that your contribution is licensed the same way, as section 5 of the licence describes. No separate contributor agreement is needed.

Do not add story media (photographs, video, interview material) in a pull request. That content is consent-based and is handled outside the code licence.
