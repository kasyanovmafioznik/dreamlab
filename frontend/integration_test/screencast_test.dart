// Drives the real app on a device/simulator and is used to record the demo
// screencast required by the task:
//
//   generation → error and recovery → paywall → settings → history after restart
//
// Run it while recording the simulator screen:
//
//   xcrun simctl io booted recordVideo demo.mp4 &
//   flutter test integration_test/screencast_test.dart -d <device-id>
//
// The test is intentionally slow (explicit pauses) so that every step is
// readable in the recording.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:test_app_ai/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Wait for the app to settle (animations, network round-trips).
  Future<void> settle(WidgetTester tester, {int seconds = 2}) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration(seconds: seconds));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  /// Type a prompt into the prompt field.
  Future<void> typePrompt(WidgetTester tester, String prompt) async {
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, prompt);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps a chip by its label. The chips live in horizontal scroll lists, so
  /// the label itself can be scrolled under a neighbour — tapping the chip
  /// widget hits the right target.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(ChoiceChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('demo: generate → fail → recover → paywall → settings → history', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---------------------------------------------------------------- 1. Generate
    await typePrompt(tester, 'a cat and a dog in a sunny meadow');
    await settle(tester, seconds: 1);
    await tapText(tester, 'Generate');
    // The backend sleeps 3–8 s before rendering.
    await settle(tester, seconds: 9);
    await binding.takeScreenshot('01_generated');

    // ------------------------------------------------------- 2. Error + recovery
    await typePrompt(tester, 'please fail now');
    await settle(tester, seconds: 1);
    await tapText(tester, 'Generate');
    await settle(tester, seconds: 9);
    await binding.takeScreenshot('02_error');

    // Recovery: fix the prompt and retry — no app restart needed.
    await typePrompt(tester, 'a cat and a dog in a sunny meadow');
    await settle(tester, seconds: 1);
    await tapText(tester, 'Try again');
    await settle(tester, seconds: 9);
    await binding.takeScreenshot('03_recovered');

    // ------------------------------------------------------------- 3. Paywall
    // Pick a premium option → the paywall opens before the request is sent.
    // '4K' is used because it is visible without horizontal scrolling
    // (the style chips live in a horizontal list and 'Cyberpunk' is off-screen).
    await tapChip(tester, '4K');
    await settle(tester, seconds: 1);
    await tapText(tester, 'Generate');
    await settle(tester, seconds: 2);
    await binding.takeScreenshot('04_paywall');

    // Mock purchase — the pending generation resumes automatically.
    await tapText(tester, 'Upgrade — \$4.99 / month');
    await settle(tester, seconds: 9);
    await binding.takeScreenshot('05_after_upgrade');

    // ------------------------------------------------------------ 4. Settings
    await tapText(tester, 'Settings');
    await settle(tester, seconds: 2);
    await binding.takeScreenshot('06_settings');

    // ------------------------------------------- 5. History (survives restart)
    await tapText(tester, 'History');
    await settle(tester, seconds: 2);
    await binding.takeScreenshot('07_history');
  });
}
