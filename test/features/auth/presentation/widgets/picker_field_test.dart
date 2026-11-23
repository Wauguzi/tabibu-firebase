import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/features/auth/presentation/widgets/picker_field.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('PickerField', () {
    Future<Border?> borderOf(
      WidgetTester tester, {
      bool bordered = false,
      String? errorText,
    }) async {
      await tester.pumpApp(
        PickerField(
          label: 'Opens',
          value: '8:00 AM',
          bordered: bordered,
          errorText: errorText,
          onTap: () {},
        ),
      );
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('8:00 AM'),
              matching: find.byType(Container),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).border as Border?;
    }

    ColorScheme schemeOf(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(PickerField))).colorScheme;

    testWidgets('has no border by default', (tester) async {
      expect(await borderOf(tester), isNull);
    });

    testWidgets('bordered draws the field hairline', (tester) async {
      final border = await borderOf(tester, bordered: true);
      expect(border?.top.color, schemeOf(tester).outline);
    });

    testWidgets('an error outlines in the error colour, bordered or not', (
      tester,
    ) async {
      final border = await borderOf(
        tester,
        bordered: true,
        errorText: 'Pick a time',
      );
      expect(border?.top.color, schemeOf(tester).error);
    });
  });
}
