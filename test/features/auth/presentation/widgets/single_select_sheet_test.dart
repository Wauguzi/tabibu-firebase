import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/presentation/widgets/single_select_sheet.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('showSingleSelectSheet', () {
    // Cupertino sheet routes never settle.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<List<String?>> openSheet(
      WidgetTester tester, {
      String? selected,
      List<String> items = const ['Nairobi', 'Mombasa', 'Kisumu'],
      ThemeMode themeMode = ThemeMode.light,
      Locale? locale,
      String title = 'Choose one',
      String searchHint = 'Search',
    }) async {
      final results = <String?>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSingleSelectSheet<String>(
              context: context,
              title: title,
              searchHint: searchHint,
              items: items,
              label: (item) => item,
              selected: selected,
            ).then(results.add),
            child: const Text('Open'),
          ),
        ),
        themeMode: themeMode,
        locale: locale,
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      return results;
    }

    testWidgets('searching filters the list', (tester) async {
      await openSheet(tester);

      expect(find.text('Nairobi'), findsOneWidget);
      expect(find.text('Mombasa'), findsOneWidget);
      expect(find.text('Kisumu'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'MB');
      await tester.pump();

      expect(find.text('Mombasa'), findsOneWidget);
      expect(find.text('Nairobi'), findsNothing);
      expect(find.text('Kisumu'), findsNothing);
    });

    testWidgets('on a tall phone the list reaches the sheet bottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await openSheet(tester);

      final list = tester.getRect(find.byType(ListView));
      final sheet = tester.getRect(find.byType(TabibuBottomSheet));
      final gap = sheet.bottom - list.bottom;
      expect(list.bottom, lessThanOrEqualTo(sheet.bottom + 1));
      expect(gap, inInclusiveRange(0, AppSpacing.screenMargin + 8));
    });

    testWidgets('rows sit on the sheet, no card, with the profile hairline', (
      tester,
    ) async {
      await openSheet(tester);

      // A shadowed card cannot sit on a sheet.
      final shadowed = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((box) {
            final decoration = box.decoration;
            return decoration is BoxDecoration &&
                (decoration.boxShadow?.isNotEmpty ?? false);
          });
      expect(shadowed, isEmpty);

      final dividers = tester.widgetList<Divider>(find.byType(Divider));
      expect(dividers, hasLength(2));
      for (final divider in dividers) {
        expect(divider.height, 1);
        expect(divider.indent, AppSpacing.md);
        expect(divider.endIndent, AppSpacing.md);
      }
    });

    testWidgets('the selected row is announced, and a tap pops with it', (
      tester,
    ) async {
      final results = await openSheet(tester, selected: 'Nairobi');

      expect(
        tester.getSemantics(find.text('Nairobi')),
        matchesSemantics(
          label: 'Nairobi',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      // The check marks the choice; the row has no fill.
      final row = find.ancestor(
        of: find.text('Nairobi'),
        matching: find.byType(Tappable),
      );
      expect(
        find.descendant(of: row, matching: find.byType(ColoredBox)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(StatusMark)),
        findsOneWidget,
      );

      await tester.tap(find.text('Mombasa'));
      await settle(tester);

      expect(results, ['Mombasa']);
      expect(find.text('Choose one'), findsNothing);
    });

    testWidgets('dragging the list down from the top dismisses', (
      tester,
    ) async {
      final results = await openSheet(tester);

      await tester.fling(find.text('Nairobi'), const Offset(0, 500), 1500);
      await settle(tester);

      expect(find.text('Choose one'), findsNothing);
      expect(results, [null]);
    });

    testWidgets('fits at 2.0x Swahili on a narrow and a large phone', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      // cspell:ignore Mkoa Pwani Wilaya Jimbo
      const items = [
        'Kaunti ya Mkoa wa Pwani',
        'Kaunti ndogo ya Wilaya',
        'Jimbo la Kati',
      ];
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        for (final width in [360.0, 840.0]) {
          tester.view.physicalSize = Size(width, 2400);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await openSheet(
            tester,
            items: items,
            themeMode: themeMode,
            locale: const Locale('sw'),
            title: 'Chagua kaunti',
            searchHint: 'Tafuta kaunti',
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Chagua kaunti'), findsOneWidget);
          expect(find.text(items.first), findsOneWidget);
          Navigator.of(tester.element(find.byType(TabibuBottomSheet))).pop();
          await settle(tester);
        }
      }
    });
  });
}
