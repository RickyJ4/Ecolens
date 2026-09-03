import 'package:flutter_test/flutter_test.dart';

import 'package:ecolens/main.dart';

void main() {
  testWidgets('shows onboarding when onboarding is required', (tester) async {
    await tester.pumpWidget(const EcoLensApp(showOnboarding: true));

    expect(find.text('Welcome to EcoLens'), findsOneWidget);
    expect(find.text('Environmental Intelligence'), findsOneWidget);
  });
}
