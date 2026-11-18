import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/widgets/tabibu_button.dart';
import 'package:tabibu/core/widgets/tabibu_text_field.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/data/region_read_client.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_sheet.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

class _MockAnalytics extends Mock implements AnalyticsService {}

/// Holds every read open on the gated answer, so a second ask lands
/// mid-flight.
class _GatedClient implements RegionReadClient {
  _GatedClient(this._answer);

  final Future<RegionReadResult> _answer;
  int calls = 0;

  @override
  Future<RegionReadResult> readRegion(RegionReadRequest request) {
    calls++;
    return _answer;
  }
}

class _ScriptedClient implements RegionReadClient {
  _ScriptedClient(this._script);

  final List<RegionReadResult?> _script;
  int calls = 0;

  @override
  Future<RegionReadResult> readRegion(RegionReadRequest request) async {
    final next = _script[calls < _script.length ? calls++ : _script.length - 1];
    final result = next;
    if (result == null) throw StateError('down');
    return result;
  }
}

const _read = RegionReadResult(
  impression: 'Calm lymphocytes.',
  features: ['Even spacing', 'Round nuclei'],
  uncertainty: .medium,
  caveat: 'One region, not a diagnosis.',
);

final _bytes = Uint8List.fromList([9, 9, 9]);

void main() {
  late _MockAnalytics analytics;

  setUp(() {
    analytics = _MockAnalytics();
    when(
      () => analytics.logRegionRead(outcome: any(named: 'outcome')),
    ).thenAnswer((_) async {});
  });

  Widget body({
    required RegionReadClient client,
    Future<Uint8List?> Function()? capture,
  }) {
    return RegionReadSheetBody(
      client: client,
      captureController: RegionCaptureController(),
      capture: capture ?? () async => _bytes,
      analytics: analytics,
    );
  }

  /// Opens the real sheet, handing its future to [onOpen]: success pops
  /// the answer, a dismiss pops null.
  Future<void> openSheet(
    WidgetTester tester, {
    required RegionReadClient client,
    required void Function(Future<RegionReadAnswer?> asked) onOpen,
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onOpen(
              showRegionReadSheet(
                context: context,
                client: client,
                captureController: RegionCaptureController(),
                capture: () async => _bytes,
                analytics: analytics,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('RegionReadSheet', () {
    testWidgets('opens with the action title', (tester) async {
      await openSheet(
        tester,
        client: FakeRegionReadClient(result: _read),
        onOpen: (_) {},
      );

      expect(find.text('Ask AI about this region'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);
    });

    testWidgets('only the Ask button loads while asking', (tester) async {
      final gate = Completer<RegionReadResult>();
      late final Future<RegionReadAnswer?> asked;
      await openSheet(
        tester,
        client: _GatedClient(gate.future),
        onOpen: (future) => asked = future,
      );

      await tester.tap(find.text('Ask'));
      await tester.pump();

      expect(find.text('Ask AI about this region'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TabibuButton>(find.byType(TabibuButton)).isLoading,
        isTrue,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete(_read);
      await tester.pumpAndSettle();
      expect(await asked, isNotNull);
    });

    testWidgets('a second ask while asking is ignored', (tester) async {
      final gate = Completer<RegionReadResult>();
      final client = _GatedClient(gate.future);
      late final Future<RegionReadAnswer?> asked;
      await openSheet(
        tester,
        client: client,
        onOpen: (future) => asked = future,
      );

      await tester.tap(find.text('Ask'));
      await tester.tap(find.text('Ask'));
      gate.complete(_read);
      await tester.pumpAndSettle();

      expect(client.calls, 1);
      expect(await asked, isNotNull);
    });

    testWidgets('the field is labelled Question with the new hint', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(body(client: FakeRegionReadClient(result: _read)));
      await tester.pumpAndSettle();

      final field = tester.widget<TabibuTextField>(
        find.byType(TabibuTextField),
      );
      expect(field.label, l10n.regionQuestionLabel);
      expect(field.hint, l10n.regionQuestionHint);
      expect(field.required, isFalse);
      expect(find.text(l10n.regionQuestionLabel), findsOneWidget);
    });

    testWidgets('the question field cleans pasted text', (tester) async {
      await tester.pumpApp(body(client: FakeRegionReadClient(result: _read)));

      await tester.enterText(find.byType(TextField), 'Malignant?\u200b');
      await tester.pump();

      expect(find.text('Malignant?'), findsOneWidget);
    });

    testWidgets('opening the sheet logs it', (tester) async {
      await tester.pumpApp(body(client: FakeRegionReadClient(result: _read)));
      await tester.pumpAndSettle();

      verify(() => analytics.logRegionRead(outcome: 'opened')).called(1);
    });

    testWidgets('a capture that throws ends in the error state', (
      tester,
    ) async {
      final client = FakeRegionReadClient(result: _read);
      await tester.pumpApp(
        body(
          client: client,
          capture: () => Future<Uint8List?>.error(StateError('capture')),
        ),
      );

      await tester.tap(find.text('Ask'));
      // Two pumps: the throw arrives as a microtask, then the error frame.
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't read that region just now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      verify(() => analytics.logRegionRead(outcome: 'failed')).called(1);
      expect(client.calls, 0);
    });

    testWidgets('success closes the sheet and returns the answer', (
      tester,
    ) async {
      late final Future<RegionReadAnswer?> asked;
      await openSheet(
        tester,
        client: FakeRegionReadClient(result: _read),
        onOpen: (future) => asked = future,
      );

      await tester.enterText(find.byType(TextField), 'Malignant?');
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      final answer = await asked;
      expect(answer?.result, _read);
      expect(answer?.question, 'Malignant?');
      expect(find.text('Ask AI about this region'), findsNothing);
      verify(() => analytics.logRegionRead(outcome: 'shown')).called(1);
    });

    testWidgets('a failed read shows its error and retries', (tester) async {
      final client = _ScriptedClient([null, _read]);
      late final Future<RegionReadAnswer?> asked;
      await openSheet(
        tester,
        client: client,
        onOpen: (future) => asked = future,
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't read that region just now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      verify(() => analytics.logRegionRead(outcome: 'failed')).called(1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(client.calls, 2);
      expect((await asked)?.result, _read);
      expect(find.text('Ask AI about this region'), findsNothing);
    });

    testWidgets('sends the cleaned question with the capture', (tester) async {
      final client = FakeRegionReadClient(result: _read);
      late final Future<RegionReadAnswer?> asked;
      await openSheet(
        tester,
        client: client,
        onOpen: (future) => asked = future,
      );

      await tester.enterText(find.byType(TextField), '  Malignant?  ');
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      final sent = client.lastRequest;
      expect(sent, isNotNull);
      expect(sent!.question, 'Malignant?');
      expect(sent.imageBytes, _bytes);
      expect(sent.stain, isEmpty);
      expect(await asked, isNotNull);
    });

    for (final locale in const [Locale('en'), Locale('sw')]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at ${scale}x text in ${locale.languageCode}', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpApp(
            body(client: FakeRegionReadClient(result: _read)),
            locale: locale,
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(RegionReadSheetBody)),
          );
          expect(find.text(l10n.regionAskSubmit), findsOneWidget);
        });
      }
    }
  });
}
