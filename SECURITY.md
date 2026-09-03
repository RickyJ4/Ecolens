# Security

Please do not open a public issue for a vulnerability.

Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"). If that is unavailable, contact the maintainer privately through the GitHub profile of the repository owner.

What matters most:

- Any path that lets a client write to Firestore collections that should be function-only.
- Leaked credentials in the tree or in built assets.
- Abuse of the public HTTP functions. They are closed by default without `ADMIN_TRIGGER_TOKEN`.

Public by design, and not vulnerabilities: the Firebase web API key in `lib/firebase_options.dart` and the reCAPTCHA v3 site key in `lib/main.dart`.
