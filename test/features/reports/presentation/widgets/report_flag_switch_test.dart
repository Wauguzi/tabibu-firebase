import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_flag_switch.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('ReportFlagSwitch', () {
    testWidgets('the switch sits on the right and announces its value', (
      tester,
    ) async {
      final values = <bool>[];
      await tester.pumpApp(
        ReportFlagSwitch(
          label: 'Critical finding',
          value: true,
          onChanged: values.add,
        ),
      );

      final label = tester.getCenter(find.text('Critical finding'));
      final toggle = tester.getCenter(find.byType(Switch));
      expect(toggle.dx, greaterThan(label.dx));
      expect(
        tester.getSemantics(find.text('Critical finding')),
        matchesSemantics(
          label: 'Critical finding',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.tap(find.text('Critical finding'));
      await tester.pump();
      expect(values, [false]);
    });

    testWidgets('a disabled switch keeps its value and stays quiet', (
      tester,
    ) async {
      final values = <bool>[];
      await tester.pumpApp(
        const ReportFlagSwitch(
          label: 'Positive for Cholera',
          value: false,
          onChanged: null,
        ),
      );

      expect(
        tester.getSemantics(find.text('Positive for Cholera')),
        matchesSemantics(
          label: 'Positive for Cholera',
          hasToggledState: true,
          hasEnabledState: true,
        ),
      );
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(values, isEmpty);
    });

    testWidgets('fits at 2.0x Swahili on a narrow and a large phone', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      // cspell:ignore Manjano
      const label = 'Chanya kwa Homa ya Manjano';
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final width in [360.0, 840.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 400);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpApp(
              ReportFlagSwitch(label: label, value: true, onChanged: (_) {}),
              themeMode: mode,
              locale: scale == 2 ? const Locale('sw') : const Locale('en'),
            );

            expect(tester.takeException(), isNull);
            final text = tester.getRect(find.text(label));
            final toggle = tester.getRect(find.byType(Switch));
            expect(toggle.left, greaterThan(text.left));
            expect(toggle.right, lessThanOrEqualTo(width + 1));
          }
        }
      }
    });
  });
}
