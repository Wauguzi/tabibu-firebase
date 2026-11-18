import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/reports/presentation/widgets/workspace_step_section.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('WorkspaceStepSection', () {
    testWidgets('an open step shows its body and announces expanded', (
      tester,
    ) async {
      var toggles = 0;
      var expanded = true;
      await tester.pumpApp(
        StatefulBuilder(
          builder: (context, setState) => WorkspaceStepSection(
            number: 1,
            title: 'AI score',
            status: .toDo,
            statusLabel: 'To do',
            expanded: expanded,
            onToggle: () {
              toggles++;
              setState(() => expanded = !expanded);
            },
            child: const Text('Score body'),
          ),
        ),
      );

      expect(find.text('1 · AI score'), findsOneWidget);
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('Score body'), findsOneWidget);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0.5,
      );
      expect(
        tester.getSemantics(find.text('1 · AI score')),
        matchesSemantics(
          label: '1 · AI score\nTo do',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.tap(find.text('1 · AI score'));
      await tester.pump();
      expect(toggles, 1);
      expect(find.text('Score body'), findsNothing);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0,
      );
    });

    testWidgets('a locked step stays shut and says why', (tester) async {
      var toggles = 0;
      await tester.pumpApp(
        WorkspaceStepSection(
          number: 2,
          title: 'Diagnosis',
          status: .waiting,
          statusLabel: 'Waiting',
          expanded: true,
          locked: true,
          lockedReason: 'Save the AI score to start the diagnosis',
          onToggle: () => toggles++,
          child: const Text('Diagnosis body'),
        ),
      );

      expect(find.text('Diagnosis body'), findsNothing);
      expect(
        find.text('Save the AI score to start the diagnosis'),
        findsOneWidget,
      );
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0,
      );
      expect(
        tester.getSemantics(find.text('2 · Diagnosis')),
        matchesSemantics(
          label:
              '2 · Diagnosis\n'
              'Waiting\n'
              'Save the AI score to start the diagnosis',
          isButton: true,
          hasExpandedState: true,
          hasEnabledState: true,
        ),
      );

      await tester.tap(find.text('2 · Diagnosis'));
      await tester.pump();
      expect(toggles, 0);
      expect(find.text('Diagnosis body'), findsNothing);
    });

    testWidgets('the state is words only: the check is on the summary', (
      tester,
    ) async {
      await tester.pumpApp(
        const Column(
          children: [
            WorkspaceStepSection(
              number: 1,
              title: 'AI score',
              status: .done,
              statusLabel: 'Done',
              expanded: false,
              onToggle: _noop,
              child: SizedBox.shrink(),
            ),
            WorkspaceStepSection(
              number: 2,
              title: 'Diagnosis',
              status: .waiting,
              statusLabel: 'Waiting',
              expanded: false,
              onToggle: _noop,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      );

      expect(find.byType(StatusMark), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
    });

    testWidgets('fits at 2.0x Swahili on a narrow and a large phone', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      // cspell:ignore Hifadhi utambuzi Inasubiri Mwili
      const reason = 'Hifadhi alama ya AI ili uanze utambuzi';
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final width in [360.0, 840.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpApp(
              const WorkspaceStepSection(
                number: 2,
                title: 'Utambuzi',
                status: .waiting,
                statusLabel: 'Inasubiri',
                expanded: false,
                locked: true,
                lockedReason: reason,
                onToggle: _noop,
                child: Text('Mwili'),
              ),
              themeMode: mode,
              locale: scale == 2 ? const Locale('sw') : const Locale('en'),
            );
            expect(tester.takeException(), isNull);
            expect(find.text(reason), findsOneWidget);
            expect(find.text('Mwili'), findsNothing);
          }
        }
      }
    });
  });
}

void _noop() {}
