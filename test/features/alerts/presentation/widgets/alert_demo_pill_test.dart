import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_status_colors.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/alerts/presentation/widgets/alert_demo_pill.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('AlertDemoPill', () {
    testWidgets('reads Demo and says it is not a real alert', (tester) async {
      final en = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(const AlertDemoPill());

      expect(find.text(en.alertDemoPill), findsOneWidget);
      expect(find.bySemanticsLabel(en.alertDemoPillSemantics), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Demo$')), findsNothing);
      expect(
        tester.widget<StatusChip>(find.byType(StatusChip)).tone,
        StatusTone.attention,
      );

      final sw = lookupAppLocalizations(const Locale('sw'));
      await tester.pumpApp(const AlertDemoPill(), locale: const Locale('sw'));
      expect(find.text(sw.alertDemoPill), findsOneWidget);
      expect(find.bySemanticsLabel(sw.alertDemoPillSemantics), findsOneWidget);
    });

    testWidgets('stays the width of its label, at the start', (tester) async {
      await tester.pumpApp(const SizedBox(width: 400, child: AlertDemoPill()));

      final chip = find.byType(StatusChip);
      expect(tester.getSize(chip).width, lessThan(200));
      expect(
        tester.getTopLeft(chip).dx,
        tester.getTopLeft(find.byType(AlertDemoPill)).dx,
      );
    });

    testWidgets('uses the attention tone in dark mode', (tester) async {
      await tester.pumpApp(const AlertDemoPill(), themeMode: ThemeMode.dark);

      final status = Theme.of(
        tester.element(find.byType(AlertDemoPill)),
      ).extension<AppStatusColors>()!;
      final text = tester.widget<Text>(find.text('Demo'));
      expect(text.style?.color, status.attentionText);
    });

    testWidgets('Kiswahili at 2.0x on 360 dp does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(const AlertDemoPill(), locale: const Locale('sw'));

      expect(find.text('Majaribio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
