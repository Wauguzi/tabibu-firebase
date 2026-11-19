import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/internet_service.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_bloc.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_state.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/reports/blocs/report_reader_bloc/report_reader_bloc.dart';
import 'package:tabibu/features/reports/blocs/report_reader_bloc/report_reader_state.dart';
import 'package:tabibu/features/reports/data/cache/report_cache_helper.dart';
import 'package:tabibu/features/reports/data/datasources/report_firebase.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_text_model.dart';
import 'package:tabibu/features/reports/presentation/doctor_report_screen.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

class _MockReports extends Mock implements ReportCacheHelper {}

class _MockRemote extends Mock implements ReportFirebase {}

class _MockInternet extends Mock implements InternetService {}

class _MockAnalytics extends Mock implements AnalyticsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const caseUid = 'case-1';
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('Mark as discussed keeps loading until the write finishes', (
    tester,
  ) async {
    final reports = _MockReports();
    final remote = _MockRemote();
    final internet = _MockInternet();
    final analytics = _MockAnalytics();
    final sync = Completer<List<PathologyReportModel>>();
    final release = Completer<Map<String, dynamic>>();
    final report = PathologyReportModel.empty().copyWith(
      uid: 'v1',
      caseUid: caseUid,
      version: 1,
      status: ReportStatus.signed.value,
    );

    when(
      () => reports.getReports('doctor-1', role: Role.doctor),
    ).thenAnswer((_) async => [report]);
    when(
      () => reports.syncReports('doctor-1', role: Role.doctor),
    ).thenAnswer((_) => sync.future);
    when(
      () => remote.markDiscussed(caseUid: caseUid, reportUid: 'v1'),
    ).thenAnswer((_) => release.future);
    when(
      () => remote.fetchReportText(
        caseUid: any(named: 'caseUid'),
        textUid: any(named: 'textUid'),
      ),
    ).thenAnswer(
      (invocation) async => ReportTextModel.empty().copyWith(
        uid: invocation.namedArguments[#textUid] as String,
        status: 'Ready',
        machineText: const {'found': 'Ready.'},
      ),
    );
    when(internet.check).thenAnswer((_) async => true);
    when(analytics.logReportDiscussed).thenAnswer((_) async {});

    final reader = ReportReaderBloc(
      reports: reports,
      remote: remote,
      internet: internet,
      analytics: analytics,
      delay: (_) async {},
    );
    // Subscription cancel inside close() completes on the real event loop.
    // Awaiting it here deadlocks the widget binding's fake clock, so the
    // bloc test is what waits for close(). This still closes the bloc.
    addTearDown(() => unawaited(reader.close()));

    final auth = MockAuthBloc();
    final base = RoleSessions.doctor();
    when(() => auth.state).thenReturn(
      SignInSuccess(
        session: PractitionerSession(
          doctor: base.doctor.copyWith(uid: 'doctor-1'),
          roles: base.roles,
        ),
      ),
    );
    final cases = MockCasesBloc();
    when(() => cases.state).thenReturn(
      const CasesLoadSuccess(
        cases: [
          CaseModel(
            uid: caseUid,
            orderNumber: 'ODR-1',
            patientName: 'Amina Wambui',
          ),
        ],
      ),
    );

    final router = GoRouter(
      initialLocation: '/report',
      routes: [
        GoRoute(
          path: '/report',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<CasesBloc>.value(value: cases),
              BlocProvider<ReportReaderBloc>.value(value: reader),
            ],
            child: const DoctorReportScreen(caseUid: caseUid),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpRouterApp(router);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.explanationMarkButton), findsOneWidget);

    await tester.tap(find.text(l10n.explanationMarkButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text(l10n.explanationConfirm));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(reader.state, isA<ReportReaderWriteInProgress>());
    expect(
      find.byWidgetPredicate((w) => w is TabibuButton && w.isLoading),
      findsOneWidget,
    );

    sync.complete([report]);
    await tester.pump();

    expect(reader.state, isA<ReportReaderWriteInProgress>());
    expect(
      find.byWidgetPredicate((w) => w is TabibuButton && w.isLoading),
      findsOneWidget,
    );

    release.complete({'status': 'ok'});
    await tester.pump();
    await tester.pump();

    expect(reader.state.report?.releasedToPatient, isTrue);
    expect(find.text(l10n.explanationMarkButton), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is TabibuButton && w.isLoading),
      findsNothing,
    );
  });
}
