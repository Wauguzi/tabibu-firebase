import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/features/auth/presentation/widgets/picker_field.dart';
import 'package:tabibu/features/profile/presentation/widgets/hours_sheet.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('showHoursSheet', () {
    late HoursDraft? result;

    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      result = null;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showHoursSheet(
              context: context,
              title: 'Monday to Friday',
              open: true,
              startMinute: 8 * 60,
              endMinute: 17 * 60,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Opens shows the Cupertino time wheel in half hours', (
      tester,
    ) async {
      await openSheet(tester);

      // Opens and Closes read as outlined fields on the white sheet.
      final fields = tester.widgetList<PickerField>(find.byType(PickerField));
      expect(fields.map((f) => f.label), ['Opens', 'Closes']);
      expect(fields.every((f) => f.bordered), isTrue);

      await tester.tap(find.text('8:00 AM'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      final wheel = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(wheel.mode, CupertinoDatePickerMode.time);
      expect(wheel.minuteInterval, 30);
      expect(wheel.initialDateTime.hour, 8);
      expect(wheel.initialDateTime.minute, 0);
    });

    testWidgets('a turn of the wheel is the time that is saved', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.text('5:00 PM'));
      await tester.pumpAndSettle();
      final wheel = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      wheel.onDateTimeChanged(DateTime(2026, 11, 17, 18, 30));
      await tester.pump();
      // Dismiss the wheel by tapping above it.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('6:30 PM'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, (open: true, startMinute: 480, endMinute: 1110));
    });
  });
}
