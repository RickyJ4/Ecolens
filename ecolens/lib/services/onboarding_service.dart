import 'package:shared_preferences/shared_preferences.dart';

/// Service to track onboarding and EULA acceptance status
class OnboardingService {
  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _eulaAcceptedKey = 'eula_accepted';
  static const String _eulaVersionKey = 'eula_version';

  // Current EULA version - increment when terms change
  static const String currentEulaVersion = '1.0';

  /// Check if user has completed onboarding
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_onboardingCompleteKey) ?? false;
    final acceptedVersion = prefs.getString(_eulaVersionKey) ?? '';

    // If EULA version changed, require re-acceptance
    if (acceptedVersion != currentEulaVersion) {
      return false;
    }

    return completed;
  }

  /// Mark onboarding as complete and record EULA acceptance
  static Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
    await prefs.setBool(_eulaAcceptedKey, true);
    await prefs.setString(_eulaVersionKey, currentEulaVersion);
  }

  /// Reset onboarding (for testing or re-showing tutorial)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingCompleteKey);
    await prefs.remove(_eulaAcceptedKey);
    await prefs.remove(_eulaVersionKey);
  }

  /// Check if EULA is accepted
  static Future<bool> hasAcceptedEula() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_eulaAcceptedKey) ?? false;
    final version = prefs.getString(_eulaVersionKey) ?? '';
    return accepted && version == currentEulaVersion;
  }
}
