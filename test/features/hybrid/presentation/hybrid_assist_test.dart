import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/features/hybrid/presentation/hybrid_assist.dart';

import '../../../helpers/helpers.dart';

class _MockAnalytics extends Mock implements AnalyticsService {}

class _SwitchedOffLookup implements HybridConfigLookup {
  @override
  bool? optionalBool(String key) =>
      key == HybridSettings.symptomTidyKey ? false : null;

  @override
  String? optionalString(String key) => null;
}

void main() {
  late _MockAnalytics analytics;

  setUp(() {
    analytics = _MockAnalytics();
    when(
      () => analytics.logHybridInference(
        task: any(named: 'task'),
        outcome: any(named: 'outcome'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => analytics.logHybridProposal(
        task: any(named: 'task'),
        action: any(named: 'action'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets('the badge names where a tidy ran, and nothing applies '
      'until Use this', (tester) async {
    final fake = FakeHybridAiService(
      result: const HybridResult(
        text: 'Headache for two days.',
        source: .inCloud,
      ),
    );
    final controller = TextEditingController(text: 'head ache 2 days');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      Column(
        children: [
          TextField(controller: controller),
          HybridAssist(
            task: .symptomTidy,
            controller: controller,
            online: true,
            writesBack: true,
            service: fake,
            analytics: analytics,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tidy my notes'));
    await tester.pumpAndSettle();

    expect(controller.text, 'head ache 2 days');
    expect(find.text('Headache for two days.'), findsOneWidget);
    expect(find.text('In the cloud'), findsOneWidget);
    expect(fake.requests.single.mode, HybridMode.preferOnDevice);

    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();

    expect(controller.text, 'Headache for two days.');
    expect(find.text('In the cloud'), findsNothing);
    verify(
      () => analytics.logHybridProposal(task: 'symptom_tidy', action: 'used'),
    ).called(1);
  });

  testWidgets('an on-device summary is badged and never written back', (
    tester,
  ) async {
    final fake = FakeHybridAiService();
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .notesSummary,
        controller: controller,
        online: true,
        service: fake,
        analytics: analytics,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarise my notes'));
    await tester.pumpAndSettle();

    expect(find.text('On this phone'), findsOneWidget);
    expect(find.text('- Headache\n- Two days\n- No fever'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Use this'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(controller.text, 'Headache for two days.');
    expect(fake.requests.single.mode, HybridMode.onlyOnDevice);
    verify(
      () => analytics.logHybridProposal(
        task: 'notes_summary',
        action: 'dismissed',
      ),
    ).called(1);
  });

  testWidgets('the tidy action hides in Kiswahili', (tester) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: FakeHybridAiService(),
        analytics: analytics,
      ),
      locale: const Locale('sw'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tidy my notes'), findsNothing);
  });

  testWidgets('a switched-off tidy stays hidden', (tester) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: FakeHybridAiService(),
        settings: const HybridSettings(symptomTidyEnabled: false),
        analytics: analytics,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tidy my notes'), findsNothing);
  });

  testWidgets('a summary hides offline when the model is unavailable', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .notesSummary,
        controller: controller,
        online: false,
        service: FakeHybridAiService(statusResult: .unavailable),
        analytics: analytics,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Summarise my notes'), findsNothing);
    expect(
      find.text('This needs a connection, or the on-device model.'),
      findsOneWidget,
    );
  });

  testWidgets('Remote Config can switch the tidy off', (tester) async {
    getIt.registerSingleton<HybridConfigLookup>(_SwitchedOffLookup());
    addTearDown(() => getIt.unregister<HybridConfigLookup>());
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: FakeHybridAiService(),
        analytics: analytics,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tidy my notes'), findsNothing);
  });

  testWidgets('a failed run says so and offers the action again', (
    tester,
  ) async {
    final fake = FakeHybridAiService(error: const HybridAiException(.network));
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: fake,
        analytics: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tidy my notes'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't do that just now."), findsOneWidget);
    fake.error = null;
    await tester.tap(find.text('Tidy my notes'));
    await tester.pumpAndSettle();

    expect(find.text('Use this'), findsOneWidget);
    expect(fake.requests, hasLength(2));
  });

  for (final locale in const [Locale('en'), Locale('sw')]) {
    testWidgets('fits at 2.0x text in ${locale.languageCode}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = TextEditingController(text: 'Headache for two days.');
      addTearDown(controller.dispose);

      await tester.pumpApp(
        SingleChildScrollView(
          child: HybridAssist(
            task: .notesSummary,
            controller: controller,
            online: locale.languageCode == 'en',
            service: FakeHybridAiService(
              statusResult: locale.languageCode == 'en'
                  ? .available
                  : .unavailable,
            ),
            analytics: analytics,
          ),
        ),
        locale: locale,
      );
      await tester.pumpAndSettle();
      if (locale.languageCode == 'en') {
        await tester.tap(find.text('Summarise my notes'));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsOneWidget);
      }

      expect(tester.takeException(), isNull);
    });
  }
}
