// cspell:ignore maelezo Maelezo
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_status_colors.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/reports/presentation/widgets/explanation_draft_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('ExplanationDraftCard', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    ExplanationDraftCard card({
      bool busy = false,
      bool approving = false,
      List<String> segments = const ['First segment', 'Second segment'],
      VoidCallback? onApprove,
      VoidCallback? onEdit,
      VoidCallback? onMore,
      String title = 'Explanation for Amina · English',
    }) => ExplanationDraftCard(
      title: title,
      segments: segments,
      busy: busy,
      approving: approving,
      onApprove: onApprove ?? () {},
      onEdit: onEdit ?? () {},
      onMore: onMore ?? () {},
    );

    testWidgets('puts the title and every segment inside the AI frame', (
      tester,
    ) async {
      await tester.pumpApp(card());

      for (final text in [
        'Explanation for Amina · English',
        'First segment',
        'Second segment',
        l10n.alertReviewAiDraftNotSent,
      ]) {
        expect(
          find.descendant(
            of: find.byType(AiDraftFrame),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('Approve, Edit and the options button each call their own '
        'callback', (tester) async {
      final taps = <String>[];
      await tester.pumpApp(
        card(
          onApprove: () => taps.add('approve'),
          onEdit: () => taps.add('edit'),
          onMore: () => taps.add('more'),
        ),
      );

      await tester.tap(find.text(l10n.alertReviewApproveAsIs));
      await tester.tap(find.text(l10n.reviewEdit));
      await tester.tap(find.byType(MoreButton));

      expect(taps, ['approve', 'edit', 'more']);
    });

    testWidgets('the controls sit outside the AI frame', (tester) async {
      await tester.pumpApp(card());

      for (final finder in [
        find.text(l10n.alertReviewApproveAsIs),
        find.text(l10n.reviewEdit),
        find.byType(MoreButton),
      ]) {
        expect(
          find.ancestor(of: finder, matching: find.byType(AiDraftFrame)),
          findsNothing,
        );
      }
    });

    testWidgets('has no Reject button of its own', (tester) async {
      await tester.pumpApp(card());

      expect(find.text(l10n.alertReviewReject), findsNothing);
    });

    testWidgets('approving keeps the primary colour, shows the dots, and '
        'does not take a second tap', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        card(
          approving: true,
          onApprove: () => taps++,
          onEdit: () => taps++,
          onMore: () => taps++,
        ),
      );

      final approve = tester.widget<TabibuButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TabibuButton &&
              widget.label == l10n.alertReviewApproveAsIs,
        ),
      );
      final edit = tester.widget<TabibuButton>(
        find.byWidgetPredicate(
          (widget) => widget is TabibuButton && widget.label == l10n.reviewEdit,
        ),
      );
      final theme = Theme.of(tester.element(find.byType(ExplanationDraftCard)));
      final fill = tester.widget<Material>(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is TabibuButton && widget.isLoading,
          ),
          matching: find.byType(Material),
        ),
      );

      expect(approve.isLoading, isTrue);
      expect(fill.color, theme.extension<AppStatusColors>()!.ink);
      expect(find.byType(SpinKitCircle), findsOneWidget);
      expect(edit.onTap, isNull);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is TabibuButton && widget.isLoading,
        ),
      );
      await tester.tap(find.text(l10n.reviewEdit));
      await tester.tap(find.byType(MoreButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('busy turns all three controls off', (tester) async {
      final taps = <String>[];
      await tester.pumpApp(
        card(
          busy: true,
          onApprove: () => taps.add('approve'),
          onEdit: () => taps.add('edit'),
          onMore: () => taps.add('more'),
        ),
      );

      await tester.tap(find.text(l10n.alertReviewApproveAsIs));
      await tester.tap(find.text(l10n.reviewEdit));
      await tester.tap(find.byType(MoreButton), warnIfMissed: false);

      expect(taps, isEmpty);
    });

    testWidgets('announces the options button and the frame label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(card());

      expect(
        find.bySemanticsLabel(l10n.notificationsMoreLabel),
        findsOneWidget,
      );
      // The frame's node reads its label first, then the draft inside it.
      expect(
        find.bySemanticsLabel(
          RegExp('^${RegExp.escape(l10n.alertReviewAiDraftNotSent)}'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('renders in light and dark', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpApp(card(), themeMode: mode);
        expect(find.byType(ExplanationDraftCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    for (final scale in const [1.3, 2.0]) {
      testWidgets('Swahili at ${scale}x with a long title and text does not '
          'overflow at 390 dp', (tester) async {
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final long = List.filled(120, 'maelezo').join(' ');

        await tester.pumpApp(
          SingleChildScrollView(
            child: card(
              segments: [long],
              title: 'Maelezo kwa Wanjiru Mwangi-Kamau · Kiswahili',
            ),
          ),
          locale: const Locale('sw'),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(long), findsOneWidget);
      });
    }
  });
}
