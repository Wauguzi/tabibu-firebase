import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/reports/presentation/widgets/verdict_selector.dart';
import 'package:tabibu/features/reports/presentation/widgets/workspace_score_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Widget card({
    required bool saving,
    VoidCallback? onSave,
    String? missingAnswers,
  }) {
    final comment = TextEditingController();
    return WorkspaceScoreCard(
      findings: 'Accepted',
      impression: 'Accepted',
      urgency: 'Good',
      measurements: 'Accepted',
      tiles: 'Accepted',
      overall: 4,
      comment: comment,
      onFindings: (_) {},
      onImpression: (_) {},
      onUrgency: (_) {},
      onMeasurements: (_) {},
      onTiles: (_) {},
      onOverall: (_) {},
      onSave: onSave,
      saving: saving,
      missingAnswers: missingAnswers,
    );
  }

  Finder saveButton() => find.byWidgetPredicate(
    (w) => w is TabibuButton && w.label == en.scoreSave,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1170, 8000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpApp(child);
    await tester.pump();
  }

  testWidgets('a complete score can be saved', (tester) async {
    var saves = 0;
    await pump(tester, card(saving: false, onSave: () => saves++));

    expect(tester.widget<TabibuButton>(saveButton()).isLoading, isFalse);
    await tester.tap(saveButton());
    expect(saves, 1);
  });

  testWidgets('while the score is on its way the button spins and waits', (
    tester,
  ) async {
    var saves = 0;
    await pump(tester, card(saving: true, onSave: () => saves++));

    final button = tester.widget<TabibuButton>(saveButton());
    expect(button.isLoading, isTrue);
    expect(button.onTap, isNull);
    expect(saves, 0);
  });

  testWidgets('the six questions are marked and the missing line shows', (
    tester,
  ) async {
    final comment = TextEditingController();
    addTearDown(comment.dispose);
    await pump(
      tester,
      WorkspaceScoreCard(
        findings: null,
        impression: 'Agree',
        urgency: null,
        measurements: null,
        tiles: null,
        overall: null,
        comment: comment,
        onFindings: (_) {},
        onImpression: (_) {},
        onUrgency: (_) {},
        onMeasurements: (_) {},
        onTiles: (_) {},
        onOverall: (_) {},
        onSave: () {},
        missingAnswers: 'Answer every * question to save',
      ),
    );

    expect(find.byWidgetPredicate(_requiredMark), findsNWidgets(6));
    expect(find.text(en.scoreComment), findsOneWidget);
    expect(find.text('Answer every * question to save'), findsOneWidget);
    expect(tester.widget<TabibuButton>(saveButton()).onTap, isNull);
  });

  testWidgets('a complete score hides the missing line', (tester) async {
    await pump(
      tester,
      card(
        saving: false,
        onSave: () {},
        missingAnswers: 'Answer every * question to save',
      ),
    );

    expect(find.byWidgetPredicate(_requiredMark), findsNWidgets(6));
    expect(find.text('Answer every * question to save'), findsNothing);
    expect(tester.widget<TabibuButton>(saveButton()).onTap, isNotNull);
  });

  testWidgets('a disabled card does not ask for answers', (tester) async {
    final comment = TextEditingController();
    addTearDown(comment.dispose);
    await pump(
      tester,
      WorkspaceScoreCard(
        findings: null,
        impression: null,
        urgency: null,
        measurements: null,
        tiles: null,
        overall: null,
        comment: comment,
        onFindings: (_) {},
        onImpression: (_) {},
        onUrgency: (_) {},
        onMeasurements: (_) {},
        onTiles: (_) {},
        onOverall: (_) {},
        onSave: () {},
        enabled: false,
        missingAnswers: 'Answer every * question to save',
      ),
    );

    expect(find.text('Answer every * question to save'), findsNothing);
  });

  testWidgets('the saved summary is a done mark and one line', (tester) async {
    const label = 'Saved · overall 4 of 5';
    await tester.pumpApp(const WorkspaceScoreSummary(label: label));

    expect(find.text(label), findsOneWidget);
    expect(find.byType(StatusMark), findsOneWidget);
    final mark = tester.getRect(find.byType(StatusMark));
    final text = tester.getRect(find.text(label));
    expect(mark.right, lessThan(text.left));
  });

  testWidgets('fits at 2.0x Swahili on a narrow and a large phone', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    // cspell:ignore Jibu swali lenye nyota kuhifadhi
    const missing = 'Jibu kila swali lenye nyota ili kuhifadhi';
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [360.0, 840.0]) {
        tester.view.physicalSize = Size(width, 8000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        final comment = TextEditingController();
        addTearDown(comment.dispose);
        await tester.pumpApp(
          WorkspaceScoreCard(
            findings: null,
            impression: null,
            urgency: null,
            measurements: null,
            tiles: null,
            overall: null,
            comment: comment,
            onFindings: (_) {},
            onImpression: (_) {},
            onUrgency: (_) {},
            onMeasurements: (_) {},
            onTiles: (_) {},
            onOverall: (_) {},
            onSave: () {},
            missingAnswers: missing,
          ),
          themeMode: mode,
          locale: const Locale('sw'),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(missing), findsOneWidget);
        final chips = find.descendant(
          of: find.byType(VerdictSelector<String>).at(4),
          matching: find.byType(TabibuFilterChip),
        );
        expect(chips, findsNWidgets(4));
        final line = tester.getCenter(chips.at(0)).dy;
        for (var i = 1; i < 4; i++) {
          expect(tester.getCenter(chips.at(i)).dy, line);
        }
      }
    }
  });
}

bool _requiredMark(Widget widget) {
  final span = widget is Text ? widget.textSpan : null;
  if (span is! TextSpan) return false;
  final children = span.children;
  if (children == null) return false;
  return children.any((child) => child is TextSpan && child.text == ' *');
}
