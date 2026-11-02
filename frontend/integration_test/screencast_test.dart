// Drives the real app on a device/simulator and is used to record the demo
// screencast required by the task:
//
//   generation → error and recovery → paywall → settings → history
//
// Run it while recording the simulator screen:
//
//   xcrun simctl io booted recordVideo --codec=h264 demo.mp4 &
//   cd frontend && flutter test integration_test/screencast_test.dart -d <device-id>
//
// The test is *event driven*: it waits for the UI to reach the expected state
// instead of sleeping for a fixed amount of time, so the recording has no dead
// air and stays inside the 1.5 minute limit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:test_app_ai/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Wait until [finder] matches something, pumping the app meanwhile.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int timeoutSeconds = 40,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      if (finder.evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    fail('Timed out waiting for $finder');
  }

  /// Small, deliberate pause so a beat is readable in the recording.
  Future<void> beat(WidgetTester tester, {int milliseconds = 700}) async {
    await tester.pump(Duration(milliseconds: milliseconds));
    await tester.pumpAndSettle();
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

  /// The success card shows this caption once the image is on screen.
  final savedToHistory = find.text('Saved to History');
  final generationFailed = find.text('Generation failed');
  final paywall = find.text('Unlock DreamLab Pro');
  final proBadge = find.text('PRO');

  testWidgets('demo: generate → fail → recover → paywall → settings → history', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---------------------------------------------------------------- 1. Generate
    await typePrompt(tester, 'a cat and a dog in a sunny meadow');
    await beat(tester);
    await tapText(tester, 'Generate');
    await waitFor(tester, savedToHistory);
    await beat(tester, milliseconds: 1200);
    await binding.takeScreenshot('01_generated');

    // ------------------------------------------------------- 2. Error + recovery
    await typePrompt(tester, 'please fail now');
    await beat(tester);
    await tapText(tester, 'Generate');
    await waitFor(tester, generationFailed);
    await beat(tester, milliseconds: 1200);
    await binding.takeScreenshot('02_error');

    // Recovery: fix the prompt and retry — no app restart needed.
    await typePrompt(tester, 'a cat and a dog in a sunny meadow');
    await beat(tester);
    await tapText(tester, 'Try again');
    await waitFor(tester, savedToHistory);
    await beat(tester, milliseconds: 1200);
    await binding.takeScreenshot('03_recovered');

    // ------------------------------------------------------------- 3. Paywall
    // A premium option → the paywall opens before the request is sent.
    // '4K' is used because it is visible without horizontal scrolling
    // (the style chips live in a horizontal list and 'Cyberpunk' is off-screen).
    await tapChip(tester, '4K');
    await beat(tester);
    await tapText(tester, 'Generate');
    await waitFor(tester, paywall);
    await beat(tester, milliseconds: 1200);
    await binding.takeScreenshot('04_paywall');

    // Mock purchase — the pending generation resumes automatically.
    await tapText(tester, 'Upgrade — \$4.99 / month');
    await waitFor(tester, proBadge);
    await waitFor(tester, savedToHistory);
    await beat(tester, milliseconds: 1200);
    await binding.takeScreenshot('05_after_upgrade');

    // ------------------------------------------------------------ 4. Settings
    await tapText(tester, 'Settings');
    await waitFor(tester, find.text('Server URL'));
    await beat(tester, milliseconds: 1500);
    await binding.takeScreenshot('06_settings');

    // ------------------------------------------- 5. History (survives restart)
    await tapText(tester, 'History');
    await waitFor(tester, find.text('a cat and a dog in a sunny meadow'));
    await beat(tester, milliseconds: 1500);
    await binding.takeScreenshot('07_history');

    // ------------------------------------------------ 6. Restart (host driven)
    // The host script restarts the app while we wait here:
    //
    //   xcrun simctl terminate booted com.example.testAppAi
    //   xcrun simctl launch   booted com.example.testAppAi
    //
    // The relaunched app reopens on the History tab (the last visited tab is
    // remembered) and the entries are still there — that is the beat the
    // screencast needs. The Flutter engine disconnects when the app is
    // killed, so the failure below is expected and swallowed.
    try {
      await Future<void>.delayed(const Duration(seconds: 25));
      await tester.pump();
    } catch (_) {
      // The app was restarted underneath the test — expected.
    }
  });
}
