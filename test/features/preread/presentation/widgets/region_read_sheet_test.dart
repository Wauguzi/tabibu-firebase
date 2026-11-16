import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/widgets/tabibu_button.dart';
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

  Future<void> ask(WidgetTester tester, {String question = ''}) async {
    if (question.isNotEmpty) {
      await tester.enterText(find.byType(TextField), question);
    }
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
  }

  group('RegionReadSheet', () {
    testWidgets('opens with the action title', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRegionReadSheet(
                context: context,
                client: FakeRegionReadClient(result: _read),
                captureController: RegionCaptureController(),
                analytics: analytics,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Ask AI about this region'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);
    });

    testWidgets('shows the read with its AI label and caveat', (tester) async {
      await tester.pumpApp(body(client: FakeRegionReadClient(result: _read)));
      await ask(tester);

      expect(find.text('Calm lymphocytes.'), findsOneWidget);
      expect(find.text('• Even spacing'), findsOneWidget);
      expect(find.text('Uncertainty: Medium'), findsOneWidget);
      expect(find.text('One region, not a diagnosis.'), findsOneWidget);
      expect(find.text('AI draft'), findsWidgets);
      verify(() => analytics.logRegionRead(outcome: 'shown')).called(1);
    });

    testWidgets('a second ask while asking is ignored', (tester) async {
      final gate = Completer<RegionReadResult>();
      final client = _GatedClient(gate.future);
      await tester.pumpApp(body(client: client));

      await tester.tap(find.text('Ask'));
      await tester.tap(find.text('Ask'));
      gate.complete(_read);
      await tester.pumpAndSettle();

      expect(client.calls, 1);
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

    testWidgets('the result carries no action at all', (tester) async {
      await tester.pumpApp(body(client: FakeRegionReadClient(result: _read)));
      await ask(tester);

      expect(find.byType(TabibuButton), findsNothing);
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

    testWidgets('a failed read shows its error and retries', (tester) async {
      final client = _ScriptedClient([null, _read]);
      await tester.pumpApp(body(client: client));
      await ask(tester);

      expect(find.text("Couldn't read that region just now."), findsOneWidget);
      verify(() => analytics.logRegionRead(outcome: 'failed')).called(1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Calm lymphocytes.'), findsOneWidget);
      expect(client.calls, 2);
    });

    testWidgets('sends the cleaned question with the capture', (tester) async {
      final client = FakeRegionReadClient(result: _read);
      await tester.pumpApp(body(client: client));
      await ask(tester, question: '  Malignant?  ');

      final sent = client.lastRequest;
      expect(sent, isNotNull);
      expect(sent!.question, 'Malignant?');
      expect(sent.imageBytes, _bytes);
      expect(sent.stain, isEmpty);
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
