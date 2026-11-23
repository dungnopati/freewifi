import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_cracker/main.dart';
import 'package:wifi_cracker/services/brute_force_engine.dart';

void main() {
  group('BruteForceEngine unit tests', () {
    test('finds short password deterministically with O(1) RAM', () {
      final result = BruteForceEngine.runSync(
        target: 'ab',
        charset: CharsetPreset.lowerAndDigits.chars,
        maxLength: 4,
      );

      expect(result.isDone, isTrue);
      expect(result.found, isTrue);
      expect(result.foundPassword, 'ab');
      expect(result.attempts, greaterThan(36));
    });

    test('detects characters outside chosen charset', () {
      final missing = BruteForceEngine.findUnsupportedCharacters(
        '12a!',
        CharsetPreset.digits.chars,
      );
      expect(missing, containsAll(['a', '!']));
    });
  });

  group('WiFiCrackerApp widget tests', () {
    testWidgets('prompts YouTube subscription before running demo',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const WiFiCrackerApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('password_input_field')),
        'a1',
      );
      await tester.tap(find.byKey(const Key('start_crack_button')));
      await tester.pumpAndSettle();

      expect(find.text('Đăng ký kênh YouTube'), findsOneWidget);
      expect(find.byKey(const Key('confirm_subscribed_button')), findsOneWidget);
    });

    testWidgets(
      'runs background isolate demo cleanly on iPhone 7 screen size (375x667)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          WiFiCrackerPage.subscribedKey: true,
        });

        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const WiFiCrackerApp());
        await tester.pumpAndSettle();

        await tester.tap(find.text(CharsetPreset.digits.label));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('password_input_field')),
          '42',
        );
        await tester.tap(find.byKey(const Key('start_crack_button')));

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pumpAndSettle();

        expect(find.textContaining('Đã khớp mật khẩu "42"'), findsOneWidget);
      },
    );
  });
}
