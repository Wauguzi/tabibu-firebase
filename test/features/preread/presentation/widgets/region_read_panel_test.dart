import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/ai_draft_frame.dart';
import 'package:tabibu/core/widgets/asset_icon.dart';
import 'package:tabibu/core/widgets/tabibu_button.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_panel.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_sheet.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

const _read = RegionReadResult(
  impression: 'Calm lymphocytes.',
  features: ['Even spacing', 'Round nuclei'],
  uncertainty: .medium,
  caveat: 'One region, not a diagnosis.',
);

const RegionReadAnswer _answer = (result: _read, question: 'Malignant?');

void _useNarrowSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Finder _detailArrow() => find.byWidgetPredicate(
  (w) => w is AssetIcon && w.asset == Assets.icons.dropDownIcon,
);

void main() {
  Widget panel({
    RegionReadAnswer? answer = _answer,
    String model = 'test-model',
    String templateId = 'test-template-v1',
    String stain = '',
  }) {
    return RegionReadPanel(
      answer: answer,
      model: model,
      templateId: templateId,
      stain: stain,
    );
  }

  group('RegionReadPanel', () {
    testWidgets('shows the guide before any ask', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(panel(answer: null));
      await tester.pumpAndSettle();

      expect(find.text(l10n.regionReadGuide), findsOneWidget);
      expect(find.byType(AiDraftFrame), findsNothing);
      expect(find.text(l10n.regionReadDisclaimer), findsNothing);
    });

    testWidgets('shows the answer in the AI frame', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(panel());
      await tester.pumpAndSettle();

      expect(find.text('Calm lymphocytes.'), findsOneWidget);
      expect(find.text('• Even spacing'), findsOneWidget);
      expect(find.text('Uncertainty: Medium'), findsOneWidget);
      expect(find.text('One region, not a diagnosis.'), findsOneWidget);
      expect(find.text(l10n.regionReadDraftLabel), findsOneWidget);
      expect(find.text(l10n.workspaceAiDraft), findsNothing);
      expect(find.text(l10n.regionReadDisclaimer), findsOneWidget);
      expect(find.textContaining('test-model'), findsOneWidget);
    });

    testWidgets('the detail arrow lists model, template, stain and question', (
      tester,
    ) async {
      await tester.pumpApp(panel(stain: 'H&E'));
      await tester.pumpAndSettle();

      expect(
        find.text('test-model\ntest-template-v1\nH&E\nMalignant?'),
        findsOneWidget,
      );
    });

    testWidgets('the detail omits an empty stain and question', (tester) async {
      const answer = (result: _read, question: '');
      await tester.pumpApp(panel(answer: answer));
      await tester.pumpAndSettle();

      expect(find.text('test-model\ntest-template-v1'), findsOneWidget);
    });

    testWidgets('carries no copy action', (tester) async {
      await tester.pumpApp(panel());
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(TabibuButton), findsNothing);
    });

    testWidgets('a second answer replaces the first', (tester) async {
      const second = RegionReadResult(
        impression: 'Crowded glands.',
        features: ['Stacked nuclei'],
        uncertainty: .high,
        caveat: 'Still one region, not a diagnosis.',
      );
      await tester.pumpApp(panel());
      await tester.pumpAndSettle();
      await tester.pumpApp(
        panel(answer: (result: second, question: 'Second look?')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crowded glands.'), findsOneWidget);
      expect(find.text('Calm lymphocytes.'), findsNothing);
    });

    testWidgets('a new answer keeps a closed model list closed', (
      tester,
    ) async {
      const second = RegionReadResult(
        impression: 'Crowded glands.',
        features: ['Stacked nuclei'],
        uncertainty: .high,
        caveat: 'Still one region, not a diagnosis.',
      );
      final bucket = PageStorageBucket();
      Widget built(RegionReadAnswer answer) {
        return PageStorage(
          bucket: bucket,
          child: RegionReadPanel(
            answer: answer,
            model: 'test-model',
            templateId: 'test-template-v1',
          ),
        );
      }

      await tester.pumpApp(built(_answer));
      await tester.pumpAndSettle();
      expect(find.textContaining('test-model'), findsOneWidget);

      await tester.tap(_detailArrow());
      await tester.pumpAndSettle();
      expect(find.textContaining('test-model'), findsNothing);

      await tester.pumpApp(const SizedBox());
      await tester.pumpApp(built((result: second, question: 'Second look?')));
      await tester.pumpAndSettle();

      expect(find.text('Crowded glands.'), findsOneWidget);
      expect(find.textContaining('test-model'), findsNothing);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('fits at 2.0x $mode in sw on a narrow screen', (
        tester,
      ) async {
        _useNarrowSurface(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const long = RegionReadResult(
          impression:
              'A calm field of lymphocytes with even spacing and round nuclei '
              'throughout the visible region and no crowding anywhere.',
          features: [
            'Even spacing across the whole visible region without crowding',
            'Round nuclei with smooth membranes and open chromatin',
          ],
          uncertainty: .high,
          caveat:
              'A read of one small region only, never a diagnosis on its own.',
        );
        await tester.pumpApp(
          panel(answer: (result: long, question: 'Malignant?'), stain: 'H&E'),
          themeMode: mode,
          locale: const Locale('sw'),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
