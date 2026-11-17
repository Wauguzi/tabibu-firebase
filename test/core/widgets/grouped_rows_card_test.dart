import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/app_styles.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/gen/assets.gen.dart';

import '../../helpers/helpers.dart';

void main() {
  group('GroupedRowsCard', () {
    GroupedRowsCard card({String? title = 'From this appointment'}) {
      return GroupedRowsCard(
        title: title,
        children: const [Text('One'), Text('Two'), Text('Three')],
      );
    }

    ColorScheme schemeOf(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(GroupedRowsCard))).colorScheme;

    testWidgets('renders the title above a divided card', (tester) async {
      await tester.pumpApp(card());
      await tester.pumpAndSettle();

      expect(find.text('From this appointment'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);

      final scheme = schemeOf(tester);
      final title = tester.widget<Text>(find.text('From this appointment'));
      expect(title.style?.fontSize, 16);
      expect(title.style?.color, scheme.onSurfaceVariant);
      expect(
        tester.getBottomLeft(find.text('From this appointment')).dy,
        lessThan(tester.getTopLeft(find.text('One')).dy),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.header == true,
        ),
        findsOneWidget,
      );

      final dividers = tester.widgetList<Divider>(find.byType(Divider));
      expect(dividers.length, 2);
      for (final divider in dividers) {
        expect(divider.height, 1);
        expect(divider.color, scheme.outlineVariant);
        expect(divider.indent, AppSpacing.md);
        expect(divider.endIndent, AppSpacing.md);
      }
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GroupedRowsCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, scheme.surfaceContainerLowest);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.card));
    });

    testWidgets('renders rows without a title', (tester) async {
      await tester.pumpApp(card(title: null));
      await tester.pumpAndSettle();

      expect(find.text('One'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.header == true,
        ),
        findsNothing,
      );
    });

    testWidgets('renders in dark', (tester) async {
      await tester.pumpApp(card(), themeMode: ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(find.text('From this appointment'), findsOneWidget);
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GroupedRowsCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        schemeOf(tester).surfaceContainerHigh,
      );
    });

    testWidgets('renders in Swahili', (tester) async {
      await tester.pumpApp(
        const GroupedRowsCard(
          title: 'Matokeo yako',
          children: [Text('Moja'), Text('Ripoti'), Text('Tayari')],
        ),
        locale: const Locale('sw'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Matokeo yako'), findsOneWidget);
      expect(find.text('Moja'), findsOneWidget);
    });

    testWidgets('grows at 1.3x text without overflow at 390 dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(
        const GroupedRowsCard(
          title: 'A very long section title that must wrap across lines',
          children: [
            Text('A very long first row that must wrap across lines'),
            Text('A very long second row that must wrap across lines'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('GroupedRow', () {
    testWidgets('keeps its icon off the card edge', (tester) async {
      await tester.pumpApp(
        GroupedRowsCard(
          children: [
            GroupedRow(
              icon: Assets.icons.calendarIcon,
              tone: .sky,
              title: 'Mon 2 Nov · 11:15 AM',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.getTopLeft(find.byType(GroupedRowsCard));
      final tile = tester.getTopLeft(find.byType(IconTile));
      expect(tile.dx - card.dx, AppStyles.cardPadding.left);
      expect(find.byType(AssetIcon), findsOneWidget, reason: 'no chevron');
    });

    testWidgets('a tap makes it a button with a chevron', (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpApp(
        GroupedRowsCard(
          children: [
            GroupedRow(
              icon: Assets.icons.testTubeIcon,
              tone: .butter,
              title: 'See results',
              onTap: () => taps++,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is AssetIcon && w.asset == Assets.icons.forwardIcon,
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(GroupedRow)),
        isSemantics(label: 'See results', isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('See results'));
      expect(taps, 1);
      handle.dispose();
    });

    GroupedRowsCard disabledChat({VoidCallback? onTap}) => GroupedRowsCard(
      children: [
        GroupedRow(
          icon: Assets.icons.chatIcon,
          tone: .mint,
          title: 'Appointment chat',
          supporting: 'Opens once Dr. Achieng Odhiambo accepts',
          enabled: false,
          onTap: onTap,
        ),
      ],
    );

    testWidgets('a disabled row is muted, says why, and does not tap', (
      tester,
    ) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpApp(disabledChat(onTap: () => taps++));
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byType(GroupedRow)),
      ).colorScheme;
      expect(
        tester.widget<Text>(find.text('Appointment chat')).style?.color,
        scheme.onSurfaceVariant,
      );
      expect(
        tester.widget<IconTile>(find.byType(IconTile)).tone,
        IconTone.neutral,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is AssetIcon && w.asset == Assets.icons.forwardIcon,
        ),
        findsNothing,
      );
      expect(
        tester.getSemantics(find.byType(GroupedRow)),
        isSemantics(
          label: 'Appointment chat\nOpens once Dr. Achieng Odhiambo accepts',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      await tester.tap(find.text('Appointment chat'), warnIfMissed: false);
      expect(taps, 0);
      handle.dispose();
    });

    testWidgets('an enabled row reads its caption after the title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpApp(
        GroupedRowsCard(
          children: [
            GroupedRow(
              icon: Assets.icons.chatIcon,
              tone: .mint,
              title: 'Appointment chat',
              supporting: 'Open until 5 PM',
              onTap: () {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(GroupedRow)),
        isSemantics(
          label: 'Appointment chat\nOpen until 5 PM',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    // cspell:ignore Mazungumzo Hufunguka akikubali
    testWidgets('a disabled caption wraps at 2.0x text in Swahili at 360 dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: GroupedRowsCard(
            children: [
              GroupedRow(
                icon: Assets.icons.chatIcon,
                tone: .mint,
                title: 'Mazungumzo ya miadi',
                supporting: 'Hufunguka Dkt. Achieng Odhiambo akikubali',
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Hufunguka Dkt. Achieng Odhiambo akikubali'),
        findsOneWidget,
      );
    });
  });

  group('DashedDivider', () {
    testWidgets('spans the width in the theme hairline', (tester) async {
      await tester.pumpApp(const SizedBox(width: 200, child: DashedDivider()));
      expect(tester.getSize(find.byType(DashedDivider)).width, 200);
      expect(tester.takeException(), isNull);
    });
  });
}
