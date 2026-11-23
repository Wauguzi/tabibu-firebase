// cspell:ignore Ongezeko kila mwenye homa chandarua
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_bloc.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_event.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_state.dart';
import 'package:tabibu/features/alerts/data/models/alert_model.dart';
import 'package:tabibu/features/alerts/data/models/alert_text_model.dart';
import 'package:tabibu/features/alerts/presentation/alert_sent_screen.dart';
import 'package:tabibu/features/alerts/presentation/widgets/alert_demo_pill.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

const _approved = {
  'clinician_en': AlertTextModel(
    headline: 'Malaria rise in Embakasi',
    body: 'Test every febrile patient.',
  ),
  'patient_en': AlertTextModel(
    headline: 'More malaria than usual',
    body: 'Sleep under a treated net.',
  ),
  'clinician_sw': AlertTextModel(
    headline: 'Ongezeko la malaria Embakasi',
    body: 'Pima kila mgonjwa mwenye homa.',
  ),
  'patient_sw': AlertTextModel(
    headline: 'Malaria zaidi ya kawaida',
    body: 'Lala chini ya chandarua.',
  ),
};

AlertModel _alert({
  String uid = 'a1',
  bool synthetic = false,
  Map<String, AlertTextModel> approvedText = _approved,
}) => AlertModel(
  uid: uid,
  diseaseId: 'malaria',
  countyName: 'Embakasi',
  status: 'Approved',
  synthetic: synthetic,
  decidedAt: '2026-11-02T09:30:00Z',
  approvedText: approvedText,
  machineText: const {
    'patient_en': AlertTextModel(
      headline: 'Machine draft nobody approved',
      body: 'Never shown here.',
    ),
  },
);

void main() {
  late MockAuthBloc authBloc;
  late MockAlertReviewBloc bloc;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const AlertReviewReset());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(
      SignInSuccess(session: RoleSessions.doctor(isAlertApprover: true)),
    );
    bloc = MockAlertReviewBloc();
    when(() => bloc.add(any())).thenReturn(null);
  });

  void mockState(AlertReviewState state) =>
      when(() => bloc.state).thenReturn(state);

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
    Locale? locale,
    Size? surface,
    String alertUid = 'a1',
  }) async {
    tester.view.physicalSize = surface ?? const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final routes = GoRouter(
      initialLocation: '/doctor/alert/$alertUid/sent',
      routes: [
        GoRoute(path: '/doctor', builder: (_, _) => const Text('stub home')),
        GoRoute(
          path: '/doctor/alert/:alertUid/sent',
          builder: (_, state) => MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<AlertReviewBloc>.value(value: bloc),
            ],
            child: AlertSentScreen(alertUid: alertUid),
          ),
        ),
      ],
    );
    addTearDown(routes.dispose);
    await tester.pumpRouterApp(routes, themeMode: themeMode, locale: locale);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String allText(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join('\n');

  group('AlertSentScreen', () {
    testWidgets('shows what was approved, for where and when', (tester) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      expect(find.text(l10n.alertReviewApprovedSent), findsOneWidget);
      expect(find.text(l10n.alertReviewSentTitle), findsOneWidget);
      // 09:30 UTC is 12:30 in Nairobi.
      expect(
        find.text(l10n.healthNoticePublished('2 Nov, 12:30 PM', 'Embakasi')),
        findsOneWidget,
      );
      expect(find.text('Malaria rise in Embakasi'), findsOneWidget);
      expect(find.text('Test every febrile patient.'), findsOneWidget);
      expect(find.text('More malaria than usual'), findsOneWidget);
      expect(find.text('Sleep under a treated net.'), findsOneWidget);
    });

    testWidgets('shows the approved text only, never the machine draft', (
      tester,
    ) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      expect(find.text('Machine draft nobody approved'), findsNothing);
      expect(find.text('Never shown here.'), findsNothing);
    });

    testWidgets('falls back to English when the language was not approved', (
      tester,
    ) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester, locale: const Locale('sw'));

      expect(find.text('Malaria zaidi ya kawaida'), findsOneWidget);

      mockState(
        AlertReviewLoadSuccess(
          current: _alert(
            approvedText: {
              for (final key in ['clinician_en', 'patient_en'])
                key: _approved[key]!,
            },
          ),
        ),
      );
      await pumpScreen(tester, locale: const Locale('sw'));
      expect(find.text('More malaria than usual'), findsOneWidget);
    });

    testWidgets('carries no AI frame: this text is approved', (tester) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      expect(find.byType(AiDraftFrame), findsNothing);
      expect(find.text(l10n.alertReviewAiDraftNotSent), findsNothing);
    });

    testWidgets('a synthetic alert shows the pill and the headline as stored', (
      tester,
    ) async {
      mockState(
        AlertReviewLoadSuccess(
          current: _alert(
            synthetic: true,
            approvedText: {
              ..._approved,
              'clinician_en': const AlertTextModel(
                headline: 'Demo: Malaria rise in Embakasi',
                body: 'Test every febrile patient.',
              ),
            },
          ),
        ),
      );
      await pumpScreen(tester);

      expect(find.byType(AlertDemoPill), findsOneWidget);
      expect(
        find.bySemanticsLabel(l10n.alertDemoPillSemantics),
        findsOneWidget,
      );
      // Stored as the server wrote it. A headline without the prefix
      // stays without one.
      expect(find.text('Demo: Malaria rise in Embakasi'), findsOneWidget);
      expect(find.text('More malaria than usual'), findsOneWidget);
      expect(find.text('Demo: More malaria than usual'), findsNothing);
    });

    testWidgets('a real alert has no pill', (tester) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      expect(find.byType(AlertDemoPill), findsNothing);
      expect(find.text(l10n.alertDemoPill), findsNothing);
    });

    testWidgets('a synthetic alert at 2.0x in Kiswahili on 360 dp does not '
        'overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      mockState(AlertReviewLoadSuccess(current: _alert(synthetic: true)));
      final sw = lookupAppLocalizations(const Locale('sw'));
      await pumpScreen(
        tester,
        locale: const Locale('sw'),
        surface: const Size(360 * 3, 6000),
      );

      expect(find.byType(AlertDemoPill), findsOneWidget);
      expect(find.text(sw.alertDemoPill), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Back to today goes to the doctor home', (tester) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      await tester.tap(find.text(l10n.alertReviewBackToToday));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stub home'), findsOneWidget);
      expect(find.byType(AlertSentScreen), findsNothing);
    });

    testWidgets('system back goes to the doctor home too', (tester) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stub home'), findsOneWidget);
    });

    testWidgets('without the approver claim it shows nothing', (tester) async {
      when(
        () => authBloc.state,
      ).thenReturn(SignInSuccess(session: RoleSessions.doctor()));
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      expect(find.text(l10n.alertReviewApprovedSent), findsNothing);
      expect(find.byType(TabibuButton), findsNothing);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('loads the alert when the bloc holds another one', (
      tester,
    ) async {
      mockState(AlertReviewLoadSuccess(current: _alert(uid: 'other')));
      await pumpScreen(tester);

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text('Malaria rise in Embakasi'), findsNothing);
      verify(() => bloc.add(const AlertReviewOpened(alertUid: 'a1'))).called(1);
    });

    testWidgets('does not reload an alert the bloc already holds', (
      tester,
    ) async {
      mockState(AlertReviewLoadSuccess(current: _alert()));
      await pumpScreen(tester);

      verifyNever(() => bloc.add(any()));
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'Kiswahili at 1.3x on a 390 dp screen (${mode.name}) does not '
        'overflow and shows no English',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          mockState(AlertReviewLoadSuccess(current: _alert(synthetic: true)));
          await pumpScreen(
            tester,
            locale: const Locale('sw'),
            themeMode: mode,
            surface: const Size(390 * 3, 6000),
          );
          final sw = lookupAppLocalizations(const Locale('sw'));

          expect(find.text(sw.alertReviewApprovedSent), findsOneWidget);
          expect(find.text(sw.alertReviewBackToToday), findsOneWidget);
          final text = allText(tester);
          for (final english in [
            l10n.alertReviewApprovedSent,
            l10n.alertReviewSentBody,
            l10n.alertReviewSentTitle,
            l10n.alertReviewBackToToday,
            l10n.alertDemoPill,
          ]) {
            expect(text, isNot(contains(english)));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
