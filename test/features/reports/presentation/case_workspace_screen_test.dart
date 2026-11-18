import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/app/view/app.dart' show tabibuLocalizationsDelegates;
import 'package:tabibu/core/constants/app_status_colors.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/constants/theme_builder.dart';
import 'package:tabibu/core/helpers/reference_data_helper.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/alerts/data/models/notifiable_disease_model.dart';
import 'package:tabibu/features/alerts/data/models/notifiable_lab_test_model.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_event.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/cases/data/models/ordered_test_model.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_state.dart';
import 'package:tabibu/features/notifications/data/models/notification_model.dart';
import 'package:tabibu/features/preread/data/datasources/preread_storage.dart';
import 'package:tabibu/features/preread/data/models/preread_draft_model.dart';
import 'package:tabibu/features/preread/data/models/preread_finding_model.dart';
import 'package:tabibu/features/preread/data/models/preread_model.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/data/region_read_client.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_panel.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_sheet.dart';
import 'package:tabibu/features/reports/blocs/case_workspace_bloc/case_workspace_event.dart';
import 'package:tabibu/features/reports/blocs/case_workspace_bloc/case_workspace_state.dart';
import 'package:tabibu/features/reports/data/models/notifiable_finding_model.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/preread_score_model.dart';
import 'package:tabibu/features/reports/data/models/report_draft_model.dart';
import 'package:tabibu/features/reports/data/models/report_response_model.dart';
import 'package:tabibu/features/reports/data/models/report_template_model.dart';
import 'package:tabibu/features/reports/data/models/report_template_question_model.dart';
import 'package:tabibu/features/reports/data/models/report_template_section_model.dart';
import 'package:tabibu/features/reports/presentation/case_workspace_screen.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_flag_switch.dart';
import 'package:tabibu/features/reports/presentation/widgets/signature_pad.dart';
import 'package:tabibu/features/reports/presentation/widgets/signed_case_view.dart';
import 'package:tabibu/features/reports/presentation/widgets/verdict_selector.dart';
import 'package:tabibu/features/reports/presentation/widgets/workspace_score_card.dart';
import 'package:tabibu/features/worklist/presentation/widgets/ai_mark.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

class MockReferenceDataHelper extends Mock implements ReferenceDataHelper {}

class MockPrereadStorage extends Mock implements PrereadStorage {}

// 1x1 PNG, served as the slide image: NetworkImage reads the status,
// length, compression state and bytes.
final Uint8List _slideBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  // cspell:disable-next-line
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _SlideHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _SlideHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlideHttpRequest implements HttpClientRequest {
  final _headers = _SlideHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _SlideHttpResponse(_slideBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlideHttpHeaders implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => []).add('$value');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlideHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _SlideHttpResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers region reads from a script, holding the last request.
class _ScriptedRegionClient implements RegionReadClient {
  _ScriptedRegionClient(this._script);

  final List<RegionReadResult> _script;
  RegionReadRequest? lastRequest;
  var _calls = 0;

  @override
  Future<RegionReadResult> readRegion(RegionReadRequest request) async {
    lastRequest = request;
    final next =
        _script[_calls < _script.length ? _calls++ : _script.length - 1];
    return next;
  }
}

final _regionBytes = Uint8List.fromList([9, 9, 9]);

const _regionRead = RegionReadResult(
  impression: 'Calm lymphocytes.',
  features: ['Even spacing', 'Round nuclei'],
  uncertainty: .medium,
  caveat: 'One region, not a diagnosis.',
);

const _regionReadB = RegionReadResult(
  impression: 'Crowded glands.',
  features: ['Stacked nuclei'],
  uncertainty: .high,
  caveat: 'Still one region, not a diagnosis.',
);

const _caseUid = 'case-1';
const _runUid = 'run-1';
const _smear = '9f7bb988-7068-4bc4-a7c5-08c690da9482';
const _histology = 'histology-lab-test';

const _aiImpression = 'Malaria parasites are seen on the smear.';
const _aiFinding = 'Ring forms are present in the thin film.';
const _aiNextStep = 'Repeat the smear in six hours.';
const _ownDiagnosis = 'Plasmodium infection confirmed on microscopy.';
const _ownComments = 'Discuss treatment with the doctor.';

const _malaria = NotifiableDiseaseModel(
  diseaseId: 'malaria',
  nameEn: 'Malaria',
  nameSw: 'Malaria',
  reportingCategory: 'Weekly',
  labTests: [NotifiableLabTestModel(labTestId: _smear, strength: 'Confirms')],
);

// Only presumptive on this smear: never offered for a tick.
const _dengue = NotifiableDiseaseModel(
  diseaseId: 'dengue',
  nameEn: 'Dengue',
  nameSw: 'Dengue',
  reportingCategory: 'Weekly',
  labTests: [
    NotifiableLabTestModel(labTestId: _smear, strength: 'Presumptive'),
  ],
);

// Confirmed by this smear but not on the register.
const _unlisted = NotifiableDiseaseModel(
  diseaseId: 'unlisted',
  nameEn: 'Unlisted fever',
  nameSw: 'Unlisted fever',
  labTests: [NotifiableLabTestModel(labTestId: _smear, strength: 'Confirms')],
);

const List<NotifiableDiseaseModel> _register = [_malaria, _dengue, _unlisted];

CaseModel _case({String testId = _smear}) => CaseModel(
  uid: _caseUid,
  orderNumber: 'TB-0231',
  patientName: 'Amina Wambui',
  patientSex: 'Female',
  patientAgeYears: 46,
  doctorName: 'Dr. Wanjiru Kamau',
  tests: [OrderedTestModel(labTestId: testId, name: 'Malaria smear')],
);

ReportDraftModel _draft({
  String diagnosis = '',
  String comments = '',
  String run = _runUid,
  bool fromPreread = false,
  List<NotifiableFindingModel> findings = const [],
}) => ReportDraftModel(
  uid: 'draft-1',
  caseUid: _caseUid,
  prereadRunUid: run,
  diagnosis: diagnosis,
  comments: comments,
  startedFromPreread: fromPreread,
  notifiableFindings: findings,
);

PrereadModel _preread({String status = 'Ready'}) => PrereadModel(
  uid: _runUid,
  caseUid: _caseUid,
  profile: 'Malaria',
  status: status,
  imagePaths: const ['slides/smear.png'],
  micronsPerPixel: 0.25,
  measurements: const {'density': 2.5},
  models: const {'segmentation': 'seg-model-v1'},
  draft: const PrereadDraftModel(
    impression: _aiImpression,
    findings: [PrereadFindingModel(text: _aiFinding)],
    confidence: 0.87,
    confidenceBand: 'High',
    urgency: 'Priority',
    nextSteps: [_aiNextStep],
  ),
);

const _score = PrereadScoreModel(uid: _runUid, runUid: _runUid, overall: 4);

CaseWorkspaceLoadSuccess _loaded({
  ReportDraftModel? draft,
  PrereadModel? preread,
  PrereadScoreModel? score,
  CaseModel? caseModel,
  bool offline = false,
}) => CaseWorkspaceLoadSuccess(
  caseUid: _caseUid,
  caseModel: caseModel ?? _case(),
  draft: draft ?? _draft(),
  preread: preread,
  score: score,
  offline: offline,
);

CaseWorkspaceWriteFailure _failed(CaseWorkspaceState from) =>
    CaseWorkspaceWriteFailure(
      error: AppError.unknown,
      caseUid: from.caseUid,
      caseModel: from.caseModel,
      draft: from.draft,
      preread: from.preread,
      score: from.score,
    );

// A report the pathologist can sign: own text, no AI pre-read to score.
CaseWorkspaceLoadSuccess _signable({
  List<NotifiableFindingModel> findings = const [],
  bool offline = false,
}) => _loaded(
  draft: _draft(
    diagnosis: _ownDiagnosis,
    comments: _ownComments,
    run: '',
    findings: findings,
  ),
  offline: offline,
);

// A ready pre-read, not yet scored: the report is locked.
CaseWorkspaceLoadSuccess _locked({
  String diagnosis = '',
  bool fromPreread = false,
}) => _loaded(
  draft: _draft(diagnosis: diagnosis, fromPreread: fromPreread),
  preread: _preread(),
);

// A ready pre-read, scored: the AI draft can be adopted or set aside.
CaseWorkspaceLoadSuccess _chooser() =>
    _loaded(draft: _draft(), preread: _preread(), score: _score);

CaseWorkspaceLoadSuccess _adopted({
  String diagnosis = _aiImpression,
  String comments = _aiFinding,
}) => _loaded(
  draft: _draft(diagnosis: diagnosis, comments: comments, fromPreread: true),
  preread: _preread(),
  score: _score,
);

const _signedReport = PathologyReportModel(
  uid: 'report-1',
  caseUid: _caseUid,
  orderNumber: 'TB-0231',
  diagnosis: _ownDiagnosis,
  comments: _ownComments,
  signedByName: 'Achieng Odhiambo',
  signedAt: '2026-10-27T07:42:00Z',
);

void main() {
  group('CaseWorkspaceScreen', () {
    late FeatureBlocs blocs;
    late MockAuthBloc authBloc;
    late MockReferenceDataHelper reference;
    late MockPrereadStorage storage;
    late StreamController<CaseWorkspaceState> states;
    late AppLocalizations l10n;
    late AppLocalizations swL10n;

    setUpAll(() async {
      registerFallbackValue(const CaseWorkspaceReset());
      registerFallbackValue(const CasesRequested(uid: '', role: .pathologist));
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
      swL10n = await AppLocalizations.delegate.load(const Locale('sw'));
    });

    setUp(() {
      blocs = FeatureBlocs();
      authBloc = MockAuthBloc();
      reference = MockReferenceDataHelper();
      storage = MockPrereadStorage();
      when(
        () => authBloc.state,
      ).thenReturn(SignInSuccess(session: RoleSessions.pathologist));
      when(reference.notifiableDiseases).thenAnswer((_) async => _register);
      when(() => storage.downloadUrl(any())).thenAnswer((_) async => null);
    });

    // The blocs sit above the app, as in the real tree: the sign sheet is
    // pushed on the root navigator and must still reach the workspace bloc.
    Future<void> pumpScreen(
      WidgetTester tester,
      CaseWorkspaceState state, {
      ThemeMode themeMode = .light,
      Locale? locale,
      Size surface = const Size(1170, 12000),
      double textScale = 1,
      bool Function()? regionReadEnabled,
      RegionReadClient? regionClient,
      Future<Uint8List?> Function()? regionCapture,
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      states = StreamController<CaseWorkspaceState>.broadcast();
      addTearDown(states.close);
      whenListen(blocs.caseWorkspace, states.stream, initialState: state);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => CaseWorkspaceScreen(
              caseUid: _caseUid,
              reference: reference,
              storage: storage,
              regionReadEnabled: regionReadEnabled,
              regionClient: regionClient,
              regionCapture: regionCapture,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      // Clear the last pump so the screen's initState runs again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            ...blocs.providers,
          ],
          child: MaterialApp.router(
            key: ValueKey(themeMode),
            theme: buildTheme(.light),
            darkTheme: buildTheme(.dark),
            themeMode: themeMode,
            localizationsDelegates: tabibuLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> emit(WidgetTester tester, CaseWorkspaceState state) async {
      states.add(state);
      // One pump delivers the state, the next draws it.
      await tester.pump();
      await tester.pump();
    }

    Future<void> settleSheet(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> openSignSheet(WidgetTester tester) async {
      await tester.tap(find.text(l10n.workspaceSignReport));
      await settleSheet(tester);
    }

    Future<void> drawStroke(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SignaturePad)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await gesture.moveBy(const Offset(40, 20));
      await gesture.up();
      await tester.pump();
    }

    Future<void> tickAttestation(WidgetTester tester) async {
      await tester.tap(find.text(l10n.signSheetAttestation));
      await tester.pump();
    }

    bool attested(WidgetTester tester) => tester
        .widget<CheckRow>(
          find.widgetWithText(CheckRow, l10n.signSheetAttestation),
        )
        .value;

    TabibuButton button(WidgetTester tester, String label) =>
        tester.widget<TabibuButton>(find.widgetWithText(TabibuButton, label));

    bool enabled(WidgetTester tester, String label) =>
        button(tester, label).onTap != null;

    TabibuTextField field(WidgetTester tester, String label) =>
        tester.widget<TabibuTextField>(
          find.byWidgetPredicate(
            (w) => w is TabibuTextField && w.label == label,
          ),
        );

    Finder inFrame(Finder of) =>
        find.ancestor(of: of, matching: find.byType(AiDraftFrame));

    Finder aiDraftFrames() => find.byWidgetPredicate(
      (w) => w is AiDraftFrame && w.label == l10n.workspaceAiDraft,
    );

    Finder scoreChips() => find.descendant(
      of: find.byType(WorkspaceScoreCard),
      matching: find.byType(TabibuFilterChip),
    );

    Finder scoreOption(String text, {int at = 0}) => find
        .descendant(
          of: find.byType(WorkspaceScoreCard),
          matching: find.text(text),
        )
        .at(at);

    /// A pill can sit past the edge of its row; bring it on screen first.
    Future<void> chooseScore(WidgetTester tester, Finder option) async {
      await tester.ensureVisible(option);
      await tester.tap(option);
    }

    // Every explicit colour painted under [root].
    List<Color> colours(WidgetTester tester, Finder root) {
      Iterable<Widget> under(Type type) => find
          .descendant(of: root, matching: find.byType(type))
          .evaluate()
          .map((e) => e.widget);
      final painted = <Color>[];
      for (final w in under(DecoratedBox).cast<DecoratedBox>()) {
        final decoration = w.decoration;
        final color = decoration is BoxDecoration ? decoration.color : null;
        if (color != null) painted.add(color);
      }
      for (final w in under(Text).cast<Text>()) {
        final color = w.style?.color;
        if (color != null) painted.add(color);
      }
      for (final w in under(AssetIcon).cast<AssetIcon>()) {
        final color = w.color;
        if (color != null) painted.add(color);
      }
      for (final w in under(DashedBorder).cast<DashedBorder>()) {
        painted.add(w.color);
      }
      return painted;
    }

    void expectNoSignedColour(WidgetTester tester, Finder root) {
      final status = Theme.of(
        tester.element(find.byType(CaseWorkspaceScreen)),
      ).extension<AppStatusColors>()!;
      final painted = colours(tester, root);
      expect(painted, isNotEmpty);
      expect(
        painted,
        everyElement(
          isNot(anyOf(status.signed, status.signedDot, status.signedContainer)),
        ),
      );
    }

    group('a case asked of this pathologist', () {
      CaseWorkspaceLoadSuccess asked() => CaseWorkspaceLoadSuccess(
        caseUid: _caseUid,
        caseModel: CaseModel(
          uid: _caseUid,
          orderNumber: 'TB-0231',
          currentStage: 'PathologistRequested',
          requestedPathologistUid: RoleSessions.pathologist.doctor.uid,
          priority: 'Urgent',
          sampleNotes: 'Left axilla',
          clinicalNotes: 'Invasive ductal carcinoma on biopsy.',
          requiresSlides: true,
          tests: const [OrderedTestModel(name: 'Histopathology examination')],
        ),
      );

      testWidgets('shows the order with Accept and Decline, nothing of the '
          'workspace', (tester) async {
        await pumpScreen(tester, asked());

        expect(find.text(l10n.workspaceRequestTitle), findsOneWidget);
        expect(find.text('Histopathology examination'), findsWidgets);
        expect(find.text('Left axilla'), findsOneWidget);
        expect(find.text(l10n.doctorCaseUrgent), findsOneWidget);
        expect(find.text(l10n.workspaceRequestAccept), findsOneWidget);
        expect(find.text(l10n.workspaceRequestDecline), findsOneWidget);
        expect(find.byType(WorkspaceScoreCard), findsNothing);
      });

      testWidgets('Accept keeps its spinner through the reload that follows', (
        tester,
      ) async {
        // After the write the case reloads; an idle button there reads as a
        // frozen screen.
        await pumpScreen(
          tester,
          CaseWorkspaceLoadInProgress(
            caseUid: _caseUid,
            caseModel: asked().caseModel,
          ),
        );

        // A loading button shows its spinner in place of the label text.
        final accept = tester.widget<TabibuButton>(
          find.byWidgetPredicate(
            (w) => w is TabibuButton && w.label == l10n.workspaceRequestAccept,
          ),
        );
        expect(accept.isLoading, isTrue);
        expect(accept.onTap, isNull);
      });

      testWidgets('Accept sends the acceptance', (tester) async {
        await pumpScreen(tester, asked());

        await tester.tap(find.text(l10n.workspaceRequestAccept));
        await tester.pump();

        verify(
          () => blocs.caseWorkspace.add(const CaseRequestAccepted()),
        ).called(1);
      });

      testWidgets('a failed answer to a lapsed request reads as the lapse', (
        tester,
      ) async {
        CaseWorkspaceLoadSuccess lapsed() => CaseWorkspaceLoadSuccess(
          caseUid: _caseUid,
          caseModel: CaseModel(
            uid: _caseUid,
            orderNumber: 'TB-0231',
            currentStage: 'PathologistRequested',
            requestedPathologistUid: RoleSessions.pathologist.doctor.uid,
            pathologistRequestExpiresAt: '2020-06-01T09:00:00Z',
          ),
        );

        for (final scale in [1.0, 2.0]) {
          for (final entry in [
            (const Locale('en'), l10n),
            (const Locale('sw'), swL10n),
          ]) {
            final start = lapsed();
            await pumpScreen(tester, start, locale: entry.$1, textScale: scale);

            await tester.tap(find.text(entry.$2.workspaceRequestAccept));
            await tester.pump();
            await emit(tester, _failed(start));
            await tester.pump(const Duration(milliseconds: 400));

            // The request line and the failure banner share the copy.
            expect(
              find.text(entry.$2.workspaceRequestLapsed),
              findsNWidgets(2),
            );
            await tester.pump(const Duration(seconds: 5));
          }
        }
      });

      testWidgets('Decline needs a reason, then sends it trimmed', (
        tester,
      ) async {
        await pumpScreen(tester, asked());

        await tester.tap(find.text(l10n.workspaceRequestDecline));
        await settleSheet(tester);
        expect(find.text(l10n.workspaceRequestDeclineTitle), findsOneWidget);

        // Empty: said, and nothing is sent.
        await tester.tap(
          find.descendant(
            of: find.byType(TabibuBottomSheet),
            matching: find.text(l10n.workspaceRequestDecline),
          ),
        );
        await tester.pump();
        expect(find.text(l10n.workspaceRequestReasonRequired), findsOneWidget);
        verifyNever(() => blocs.caseWorkspace.add(any()));

        await tester.enterText(
          find.descendant(
            of: find.byType(TabibuBottomSheet),
            matching: find.byType(TextField),
          ),
          '  On leave this week  ',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(TabibuBottomSheet),
            matching: find.text(l10n.workspaceRequestDecline),
          ),
        );
        await settleSheet(tester);

        verify(
          () => blocs.caseWorkspace.add(
            const CaseRequestDeclined(reason: 'On leave this week'),
          ),
        ).called(1);
      });
    });

    group('an accepted case with no sample recorded', () {
      testWidgets('opens on the accession, starting from a made-up number', (
        tester,
      ) async {
        final base = RoleSessions.pathologist;
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: base.doctor.copyWith(
                uid: 'path-1',
                firstName: 'Wanjiru',
                lastName: 'Kamau',
              ),
              roles: base.roles,
            ),
          ),
        );
        await pumpScreen(
          tester,
          const CaseWorkspaceLoadSuccess(
            caseUid: _caseUid,
            caseModel: CaseModel(
              uid: _caseUid,
              orderNumber: 'ODR-AO-AO-03112026-005',
              currentStage: 'PrereadReady',
              pathologistUid: 'path-1',
            ),
          ),
        );

        expect(find.text(l10n.workspaceSampleTitle), findsOneWidget);
        // Today's date is in the number, so it is read by its shape.
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byType(TabibuTextField),
            matching: find.byType(TextField),
          ),
        );
        expect(field.controller?.text, matches(RegExp(r'^LAB-WK-\d{8}-005$')));
      });

      testWidgets(
        'a pre-read row already in the inbox when the load lands reopens it',
        (tester) async {
          final base = RoleSessions.pathologist;
          when(() => authBloc.state).thenReturn(
            SignInSuccess(
              session: PractitionerSession(
                doctor: base.doctor.copyWith(uid: 'path-1'),
                roles: base.roles,
              ),
            ),
          );
          const ready = NotificationModel(
            uid: 'n-early',
            templateKey: 'prereadReady',
            resourceType: 'Case',
            resourceUid: _caseUid,
          );
          whenListen(
            blocs.notifications,
            const Stream<NotificationsState>.empty(),
            initialState: const NotificationsLoadSuccess(items: [ready]),
          );
          await pumpScreen(
            tester,
            const CaseWorkspaceLoadInProgress(caseUid: _caseUid),
          );

          await emit(
            tester,
            const CaseWorkspaceLoadSuccess(
              caseUid: _caseUid,
              pathologistUid: 'path-1',
              caseModel: CaseModel(
                uid: _caseUid,
                orderNumber: 'ODR-AO-AO-03112026-005',
                currentStage: 'PrereadQueued',
                pathologistUid: 'path-1',
              ),
            ),
          );

          verify(
            () => blocs.caseWorkspace.add(
              const CasePrereadSettled(caseUid: _caseUid),
            ),
          ).called(1);
        },
      );

      testWidgets(
        "waits for the pre-read, and the pre-read's inbox row reopens it",
        (tester) async {
          final base = RoleSessions.pathologist;
          when(() => authBloc.state).thenReturn(
            SignInSuccess(
              session: PractitionerSession(
                doctor: base.doctor.copyWith(uid: 'path-1'),
                roles: base.roles,
              ),
            ),
          );
          final inbox = StreamController<NotificationsState>.broadcast();
          addTearDown(inbox.close);
          whenListen(
            blocs.notifications,
            inbox.stream,
            initialState: const NotificationsLoadSuccess(),
          );
          await pumpScreen(
            tester,
            const CaseWorkspaceLoadSuccess(
              caseUid: _caseUid,
              pathologistUid: 'path-1',
              caseModel: CaseModel(
                uid: _caseUid,
                orderNumber: 'ODR-AO-AO-03112026-005',
                currentStage: 'PrereadQueued',
                pathologistUid: 'path-1',
              ),
            ),
          );

          expect(find.text(l10n.workspaceAwaitingPreread), findsOneWidget);
          expect(find.text(l10n.doctorCaseSampleReceived), findsNothing);

          const ready = NotificationModel(
            uid: 'n-1',
            templateKey: 'prereadReady',
            resourceType: 'Case',
            resourceUid: _caseUid,
          );
          inbox.add(const NotificationsLoadSuccess(items: [ready]));
          await tester.pump();
          // The same row again, as the live inbox resends it, reopens once.
          inbox.add(const NotificationsLoadSuccess(items: [ready]));
          await tester.pump();

          verify(
            () => blocs.caseWorkspace.add(
              const CasePrereadSettled(caseUid: _caseUid),
            ),
          ).called(1);
        },
      );
    });

    group('the template questions', () {
      const cancer = ReportTemplateModel(
        templateKey: 'Cancer',
        sections: [
          ReportTemplateSectionModel(
            sectionKey: 'Macroscopic',
            order: 1,
            questions: [
              ReportTemplateQuestionModel(
                questionKey: 'specimenDescription',
                order: 1,
                required: true,
              ),
              ReportTemplateQuestionModel(
                questionKey: 'specimenSize',
                order: 2,
              ),
            ],
          ),
          ReportTemplateSectionModel(
            sectionKey: 'Microscopic',
            order: 2,
            questions: [
              ReportTemplateQuestionModel(
                questionKey: 'microscopicDescription',
                order: 1,
                required: true,
              ),
            ],
          ),
        ],
      );

      ReportDraftModel draft({
        List<ReportResponseModel> responses = const [],
      }) => ReportDraftModel(
        uid: 'draft-1',
        caseUid: _caseUid,
        diagnosis: _ownDiagnosis,
        comments: _ownComments,
        templateKey: 'Cancer',
        responses: responses,
      );

      CaseWorkspaceLoadSuccess loaded(ReportDraftModel d) =>
          CaseWorkspaceLoadSuccess(
            caseUid: _caseUid,
            caseModel: _case(),
            draft: d,
          );

      setUp(
        () => when(reference.reportTemplates).thenAnswer((_) async => [cancer]),
      );

      Finder questionField(String label) => find.byWidgetPredicate(
        (w) => w is TabibuTextField && w.label == label,
      );

      testWidgets('each question is a field, the required ones starred', (
        tester,
      ) async {
        await pumpScreen(tester, loaded(draft()));

        final specimen = tester.widget<TabibuTextField>(
          questionField(l10n.reportQuestionSpecimenDescription),
        );
        final size = tester.widget<TabibuTextField>(
          questionField(l10n.reportQuestionSpecimenSize),
        );
        final microscopic = tester.widget<TabibuTextField>(
          questionField(l10n.reportQuestionMicroscopicDescription),
        );
        expect(specimen.required, isTrue);
        expect(size.required, isFalse);
        expect(microscopic.required, isTrue);
        expect(find.text(l10n.reportSectionMacroscopic), findsWidgets);
        expect(find.text(l10n.reportSectionMicroscopic), findsWidgets);
      });

      Finder answerField(String label) => find.descendant(
        of: questionField(label),
        matching: find.byType(TextField),
      );

      TabibuButton signButton(WidgetTester tester) =>
          tester.widget<TabibuButton>(
            find.widgetWithText(TabibuButton, l10n.workspaceSignReport),
          );

      testWidgets('Sign stays closed, with its reason, until they are typed', (
        tester,
      ) async {
        await pumpScreen(tester, loaded(draft()));

        expect(find.text(l10n.workspaceRequiredBeforeSign), findsOneWidget);
        expect(signButton(tester).onTap, isNull);

        await tester.enterText(
          answerField(l10n.reportQuestionSpecimenDescription),
          'One lymph node, 6 mm.',
        );
        await tester.pump();
        // One of the two required ones is still empty.
        expect(signButton(tester).onTap, isNull);
      });

      testWidgets('Sign opens as soon as the required ones are typed, and '
          'saves them first', (tester) async {
        await pumpScreen(tester, loaded(draft()));

        await tester.enterText(
          answerField(l10n.reportQuestionSpecimenDescription),
          'One lymph node, 6 mm.',
        );
        await tester.enterText(
          answerField(l10n.reportQuestionMicroscopicDescription),
          'A focus of carcinoma cells.',
        );
        await tester.pump();

        expect(find.text(l10n.workspaceRequiredBeforeSign), findsNothing);
        expect(signButton(tester).onTap, isNotNull);

        await tester.tap(find.text(l10n.workspaceSignReport));
        await tester.pump();

        final sent = verify(
          () => blocs.caseWorkspace.add(captureAny()),
        ).captured.whereType<CaseDraftEdited>().single;
        expect((sent.fields['responses'] as List<dynamic>).length, 2);
      });

      testWidgets('a tap outside the fields drops the keyboard', (
        tester,
      ) async {
        await pumpScreen(tester, loaded(draft()));

        final field = answerField(l10n.reportQuestionSpecimenSize);
        await tester.tap(field);
        await tester.pump();
        expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);

        await tester.tap(find.text(l10n.reportSectionMicroscopic).first);
        await tester.pump();
        expect(tester.widget<TextField>(field).focusNode?.hasFocus, isFalse);
      });

      testWidgets('saved answers fill the fields and open Sign', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          loaded(
            draft(
              responses: const [
                ReportResponseModel(
                  section: 'Macroscopic',
                  question: 'specimenDescription',
                  answer: 'One lymph node, 6 mm.',
                  order: 1,
                ),
                ReportResponseModel(
                  section: 'Microscopic',
                  question: 'microscopicDescription',
                  answer: 'A focus of carcinoma cells.',
                  order: 1,
                ),
              ],
            ),
          ),
        );

        expect(find.text('One lymph node, 6 mm.'), findsOneWidget);
        expect(find.text(l10n.workspaceRequiredBeforeSign), findsNothing);
        final sign = tester.widget<TabibuButton>(
          find.widgetWithText(TabibuButton, l10n.workspaceSignReport),
        );
        expect(sign.onTap, isNotNull);
      });

      testWidgets('Save draft sends the answers under their keys', (
        tester,
      ) async {
        await pumpScreen(tester, loaded(draft()));

        await tester.enterText(
          find.descendant(
            of: questionField(l10n.reportQuestionSpecimenDescription),
            matching: find.byType(TextField),
          ),
          '  One lymph node, 6 mm.  ',
        );
        await tester.enterText(
          find.descendant(
            of: questionField(l10n.reportQuestionMicroscopicDescription),
            matching: find.byType(TextField),
          ),
          'A focus of carcinoma cells.',
        );
        await tester.tap(find.text(l10n.workspaceSaveDraft));
        await tester.pump();

        final sent = verify(
          () => blocs.caseWorkspace.add(captureAny()),
        ).captured.whereType<CaseDraftEdited>().single;
        final responses = sent.fields['responses'] as List<dynamic>;
        expect(responses, [
          {
            'section': 'Macroscopic',
            'question': 'specimenDescription',
            'answer': 'One lymph node, 6 mm.',
            'order': 1,
          },
          {
            'section': 'Microscopic',
            'question': 'microscopicDescription',
            'answer': 'A focus of carcinoma cells.',
            'order': 1,
          },
        ]);
      });
    });

    group('rules', () {
      testWidgets('every AI value of the pre-read sits in the AI draft '
          'frame, and the ready chip is the AI mark', (tester) async {
        await pumpScreen(tester, _chooser());

        final frame = find.byType(AiDraftFrame);
        expect(frame, findsOneWidget);
        expect(
          tester.widget<AiDraftFrame>(frame).label,
          l10n.workspaceAiPreread,
        );
        for (final value in [
          _aiImpression,
          _aiFinding,
          _aiNextStep,
          l10n.deskBandRow(l10n.deskBandHigh, '87%'),
          l10n.urgencyPriority,
          'density · 2.5',
        ]) {
          expect(inFrame(find.text(value)), findsOneWidget, reason: value);
        }

        final mark = find.byType(AiMark);
        expect(mark, findsOneWidget);
        expect(tester.widget<AiMark>(mark).label, l10n.deskAiDraftReady);
        expect(inFrame(mark), findsNothing);
      });

      testWidgets('the pre-read models stay shown after scrolling off', (
        tester,
      ) async {
        await pumpScreen(tester, _chooser(), surface: const Size(1170, 1800));
        expect(find.text('seg-model-v1'), findsOneWidget);

        final list = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
        final position = tester.state<ScrollableState>(list).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        if (position.pixels < position.maxScrollExtent) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
        }
        expect(find.text('seg-model-v1'), findsNothing);

        position.jumpTo(0);
        await tester.pump();
        expect(find.text('seg-model-v1'), findsOneWidget);
      });

      testWidgets('the AI draft in the fields is framed too', (tester) async {
        await pumpScreen(tester, _adopted());

        expect(aiDraftFrames(), findsNWidgets(2));
        for (final label in [
          l10n.reportSectionDiagnosis,
          l10n.reportSectionComments,
        ]) {
          expect(
            find.descendant(
              of: aiDraftFrames(),
              matching: find.byWidgetPredicate(
                (w) => w is TabibuTextField && w.label == label,
              ),
            ),
            findsOneWidget,
            reason: label,
          );
        }
      });

      testWidgets('nothing AI-derived uses the signed colour, in '
          'light and dark', (tester) async {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await pumpScreen(tester, _adopted(), themeMode: mode);

          expectNoSignedColour(
            tester,
            find.byWidgetPredicate((w) => w is AiDraftFrame || w is AiMark),
          );
          final status = Theme.of(
            tester.element(find.byType(CaseWorkspaceScreen)),
          ).extension<AppStatusColors>()!;
          expect(
            colours(tester, find.byType(AiMark)),
            contains(status.aiDraftContainer),
          );
          expect(
            colours(tester, find.byType(AiDraftFrame)),
            contains(status.draftBorder),
          );
        }
      });

      testWidgets('with a ready pre-read not yet scored, the report '
          'is locked and the score card leads', (tester) async {
        await pumpScreen(
          tester,
          _locked(diagnosis: _ownDiagnosis, fromPreread: true),
        );

        expect(find.text('1 · ${l10n.workspaceStepAiScore}'), findsOneWidget);
        expect(find.text(l10n.workspaceStepToDo), findsOneWidget);
        expect(find.byType(WorkspaceScoreCard), findsOneWidget);
        expect(find.text(l10n.scoreLockLine), findsOneWidget);
        expect(find.text(l10n.scoreAnswerEveryQuestion), findsOneWidget);
        expect(find.text('2 · ${l10n.reportSectionDiagnosis}'), findsOneWidget);
        expect(find.text(l10n.workspaceStepWaiting), findsOneWidget);
        expect(find.text(l10n.workspaceDiagnosisWaiting), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is TabibuTextField && w.label == l10n.reportSectionDiagnosis,
          ),
          findsNothing,
        );
        // Before a score the AI draft is never put in.
        verifyNever(
          () => blocs.caseWorkspace.add(const CaseDraftStartedFromPreread()),
        );
        expect(enabled(tester, l10n.workspaceSignReport), isFalse);
        expect(enabled(tester, l10n.workspaceSaveDraft), isFalse);

        await tester.tap(find.text('2 · ${l10n.reportSectionDiagnosis}'));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is TabibuTextField && w.label == l10n.reportSectionDiagnosis,
          ),
          findsNothing,
        );
        verifyNever(() => blocs.caseWorkspace.add(any()));
      });

      testWidgets('scoring unlocks the report', (tester) async {
        await pumpScreen(
          tester,
          _locked(diagnosis: _ownDiagnosis, fromPreread: true),
        );

        await emit(
          tester,
          _loaded(
            draft: _draft(diagnosis: _ownDiagnosis, fromPreread: true),
            preread: _preread(),
            score: _score,
          ),
        );

        expect(find.byType(WorkspaceScoreCard), findsNothing);
        expect(find.text(l10n.scoreLockLine), findsNothing);
        // Folded once saved: the one line waits behind the arrow.
        expect(find.text(l10n.scoreSavedSummary(4)), findsNothing);
        expect(find.text(l10n.workspaceStepDone), findsOneWidget);
        expect(enabled(tester, l10n.workspaceSignReport), isTrue);
        expect(enabled(tester, l10n.workspaceSaveDraft), isTrue);
        expect(field(tester, l10n.reportSectionDiagnosis).readOnly, isFalse);
      });

      testWidgets('saving the score scrolls the diagnosis into view', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          _locked(diagnosis: _ownDiagnosis, fromPreread: true),
          surface: const Size(1170, 1800),
        );

        final heading = find.text('2 · ${l10n.reportSectionDiagnosis}');
        final list = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
        await tester.scrollUntilVisible(heading, 400, scrollable: list);
        // Parked at the bottom of the short screen. Saving brings it up.
        expect(tester.getTopLeft(heading).dy, greaterThan(200));

        await emit(
          tester,
          CaseScoreSuccess(
            caseUid: _caseUid,
            caseModel: _case(),
            draft: _draft(diagnosis: _ownDiagnosis, fromPreread: true),
            preread: _preread(),
            score: _score,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final top = tester.getTopLeft(heading).dy;
        expect(top, inInclusiveRange(0, 160));
      });

      testWidgets('a scored case reopens on the diagnosis', (tester) async {
        await pumpScreen(tester, _chooser());

        expect(find.byType(WorkspaceScoreCard), findsNothing);
        expect(find.text('2 · ${l10n.reportSectionDiagnosis}'), findsOneWidget);
        // The score's one line is behind its arrow: shut, then shown.
        expect(find.text(l10n.scoreSavedSummary(4)), findsNothing);
        await tester.tap(find.text('1 · ${l10n.workspaceStepAiScore}'));
        await tester.pump();
        expect(find.text(l10n.scoreSavedSummary(4)), findsOneWidget);
        await tester.tap(find.text('1 · ${l10n.workspaceStepAiScore}'));
        await tester.pump();
        expect(find.text(l10n.scoreSavedSummary(4)), findsNothing);
      });

      testWidgets('the critical switch sends the flag', (tester) async {
        await pumpScreen(tester, _signable());

        await tester.tap(find.text(l10n.workspaceCriticalFinding));
        await tester.pump();

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          const CaseDraftEdited(fields: {'isCritical': true}),
        ]);
      });

      testWidgets('a pre-read that is not ready never locks the '
          'report', (tester) async {
        await pumpScreen(
          tester,
          _loaded(
            draft: _draft(diagnosis: _ownDiagnosis),
            preread: _preread(status: 'Failed'),
          ),
        );

        expect(find.byType(WorkspaceScoreCard), findsNothing);
        expect(find.text(l10n.scoreLockLine), findsNothing);
        expect(find.byType(AiDraftFrame), findsNothing);
        expect(find.byType(AiMark), findsNothing);
        expect(enabled(tester, l10n.workspaceSignReport), isTrue);
      });

      testWidgets('nothing is preselected on the score card', (tester) async {
        await pumpScreen(tester, _locked());

        expect(scoreChips(), findsNWidgets(16));
        expect(
          scoreChips().evaluate().map(
            (e) => (e.widget as TabibuFilterChip).selected,
          ),
          everyElement(isFalse),
        );
        expect(
          tester.widget<OverallScore>(find.byType(OverallScore)).value,
          isNull,
        );
        expect(enabled(tester, l10n.scoreSave), isFalse);
      });

      testWidgets('Save score stays disabled until every verdict and '
          'the overall score are chosen, then sends exactly those', (
        tester,
      ) async {
        await pumpScreen(tester, _locked());

        await chooseScore(tester, scoreOption(l10n.scoreAgree));
        await chooseScore(tester, scoreOption(l10n.scorePartlyAgree, at: 1));
        await chooseScore(tester, scoreOption(l10n.scoreDisagree, at: 2));
        await chooseScore(tester, scoreOption(l10n.scoreCorrected));
        await chooseScore(tester, scoreOption(l10n.scorePoor));
        await tester.pump();
        expect(enabled(tester, l10n.scoreSave), isFalse);
        expect(
          tester.widget<OverallScore>(find.byType(OverallScore)).value,
          isNull,
        );

        final overall = find.descendant(
          of: find.byType(OverallScore),
          matching: find.text('4'),
        );
        await tester.ensureVisible(overall);
        await tester.tap(overall);
        await tester.pump();
        expect(enabled(tester, l10n.scoreSave), isTrue);
        expect(
          scoreChips()
              .evaluate()
              .where((e) => (e.widget as TabibuFilterChip).selected)
              .length,
          5,
        );

        await tester.tap(find.text(l10n.scoreSave));
        await tester.pump();

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          const CasePrereadScored(
            overall: 4,
            findingsVerdict: 'Agree',
            impressionVerdict: 'PartlyAgree',
            urgencyVerdict: 'Disagree',
            measurementsVerdict: 'Corrected',
            segmentationVerdict: 'Poor',
          ),
        ]);
      });

      testWidgets('a scored, untouched draft takes the AI draft by itself, '
          'once', (tester) async {
        await pumpScreen(tester, _chooser());
        // The ask goes after the frame; a rebuild must not ask again.
        await tester.pump();
        await tester.pump();

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          const CaseDraftStartedFromPreread(),
        ]);
        expect(find.text(l10n.workspaceAiFilledHint), findsNothing);
      });

      testWidgets("the pathologist's own diagnosis is never replaced", (
        tester,
      ) async {
        await pumpScreen(
          tester,
          _loaded(
            draft: _draft(diagnosis: _ownDiagnosis),
            preread: _preread(),
            score: _score,
          ),
        );
        await tester.pump();

        verifyNever(
          () => blocs.caseWorkspace.add(const CaseDraftStartedFromPreread()),
        );
      });

      testWidgets('AI-filled fields say they are there to be edited', (
        tester,
      ) async {
        await pumpScreen(tester, _adopted());

        expect(find.text(l10n.workspaceAiFilledHint), findsOneWidget);
      });

      testWidgets('once both are the pathologist own words, the hint goes', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          _adopted(diagnosis: _ownDiagnosis, comments: _ownComments),
        );

        expect(find.text(l10n.workspaceAiFilledHint), findsNothing);
      });

      testWidgets('text equal to the AI draft is framed as an AI '
          'draft, not as the pathologist own text', (tester) async {
        await pumpScreen(tester, _adopted());

        expect(aiDraftFrames(), findsNWidgets(2));
        expect(find.text(l10n.workspaceYourEdit), findsNothing);
      });

      testWidgets('edited text shows Your edit and leaves the AI '
          'frame', (tester) async {
        await pumpScreen(tester, _adopted(comments: _ownComments));

        expect(aiDraftFrames(), findsOneWidget);
        expect(
          find.descendant(
            of: aiDraftFrames(),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is TabibuTextField &&
                  w.label == l10n.reportSectionDiagnosis,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(l10n.workspaceYourEdit), findsOneWidget);

        await pumpScreen(
          tester,
          _adopted(diagnosis: _ownDiagnosis, comments: _ownComments),
        );

        expect(aiDraftFrames(), findsNothing);
        expect(find.text(l10n.workspaceYourEdit), findsNWidgets(2));
      });

      testWidgets('the frame gives way to Your edit on the first '
          'change the bloc reports', (tester) async {
        await pumpScreen(tester, _adopted());
        expect(aiDraftFrames(), findsNWidgets(2));

        await emit(tester, _adopted(diagnosis: '$_aiImpression Edited.'));

        expect(aiDraftFrames(), findsOneWidget);
        expect(find.text(l10n.workspaceYourEdit), findsOneWidget);
      });

      testWidgets('the frame gives way to Your edit on the first '
          'keystroke', (tester) async {
        await pumpScreen(tester, _adopted());
        expect(aiDraftFrames(), findsNWidgets(2));

        await tester.enterText(
          find.descendant(
            of: aiDraftFrames().first,
            matching: find.byType(EditableText),
          ),
          '$_aiImpression!',
        );
        await tester.pump();

        expect(aiDraftFrames(), findsOneWidget);
        expect(find.text(l10n.workspaceYourEdit), findsOneWidget);
      });

      testWidgets('a report not started from the AI draft is never '
          'labelled either way', (tester) async {
        await pumpScreen(
          tester,
          _loaded(
            draft: _draft(diagnosis: _aiImpression, comments: _ownComments),
            preread: _preread(),
            score: _score,
          ),
        );

        expect(aiDraftFrames(), findsNothing);
        expect(find.text(l10n.workspaceYourEdit), findsNothing);
      });

      testWidgets('notifiable boxes start unticked and only the '
          'confirmable disease is offered', (tester) async {
        await pumpScreen(tester, _signable());

        final row = find.widgetWithText(
          ReportFlagSwitch,
          l10n.workspacePositiveFor('Malaria'),
        );
        expect(row, findsOneWidget);
        expect(tester.widget<ReportFlagSwitch>(row).value, isFalse);
        expect(find.text(l10n.workspaceNotifiableExplainer), findsOneWidget);
        expect(
          find.textContaining(l10n.workspacePositiveFor('Dengue')),
          findsNothing,
        );
        expect(
          find.textContaining(l10n.workspacePositiveFor('Unlisted fever')),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ReportFlagSwitch &&
                w.label.startsWith(l10n.workspacePositiveFor('')),
          ),
          findsOneWidget,
        );
        verifyNever(() => blocs.caseWorkspace.add(any()));
      });

      testWidgets('a case with no confirming test offers nothing to '
          'tick', (tester) async {
        await pumpScreen(
          tester,
          _loaded(
            draft: _draft(diagnosis: _ownDiagnosis, run: ''),
            caseModel: _case(testId: _histology),
          ),
        );

        expect(find.text(l10n.workspaceNotifiableExplainer), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ReportFlagSwitch &&
                w.label.startsWith(l10n.workspacePositiveFor('')),
          ),
          findsNothing,
        );
        expect(
          find.widgetWithText(ReportFlagSwitch, l10n.workspaceCriticalFinding),
          findsOneWidget,
        );
      });

      testWidgets('typing not yet saved survives a later draft change', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());

        await tester.enterText(
          find.widgetWithText(TextField, _ownDiagnosis),
          'Typed, not saved yet',
        );
        await tester.pump();

        // A tick or a pre-read arriving changes the draft, not the diagnosis.
        states.add(
          _loaded(
            draft: _draft(
              diagnosis: _ownDiagnosis,
              comments: _ownComments,
              run: '',
            ).copyWith(isCritical: true),
          ),
        );
        await tester.pump();

        expect(find.text('Typed, not saved yet'), findsOneWidget);
        expect(find.text(_ownDiagnosis), findsNothing);
      });

      testWidgets('a field nobody typed in follows the saved draft', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());

        states.add(
          _loaded(
            draft: _draft(
              diagnosis: 'Saved elsewhere',
              comments: _ownComments,
              run: '',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Saved elsewhere'), findsOneWidget);
        expect(find.text(_ownDiagnosis), findsNothing);
      });

      testWidgets('ticking sends the disease with alertRequested '
          'false', (tester) async {
        await pumpScreen(tester, _signable());

        await tester.tap(find.text(l10n.workspacePositiveFor('Malaria')));
        await tester.pump();

        final captured = verify(
          () => blocs.caseWorkspace.add(captureAny()),
        ).captured;
        expect(captured, [
          const CaseDraftEdited(
            fields: {
              'notifiableFindings': [
                {'diseaseId': 'malaria', 'alertRequested': false},
              ],
            },
          ),
        ]);
      });

      testWidgets('a ticked disease reads ticked from the draft, and '
          'unticking removes it', (tester) async {
        await pumpScreen(
          tester,
          _signable(
            findings: [const NotifiableFindingModel(diseaseId: 'malaria')],
          ),
        );

        final row = find.widgetWithText(
          ReportFlagSwitch,
          l10n.workspacePositiveFor('Malaria'),
        );
        expect(tester.widget<ReportFlagSwitch>(row).value, isTrue);

        await tester.tap(find.text(l10n.workspacePositiveFor('Malaria')));
        await tester.pump();

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          const CaseDraftEdited(fields: {'notifiableFindings': <Object>[]}),
        ]);
      });

      testWidgets('the attestation starts unticked on every open', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());

        await openSignSheet(tester);
        expect(find.text(l10n.signSheetTitle), findsOneWidget);
        expect(attested(tester), isFalse);

        await tickAttestation(tester);
        expect(attested(tester), isTrue);

        await tester.tap(find.text(l10n.commonCancel));
        await settleSheet(tester);
        expect(find.text(l10n.signSheetTitle), findsNothing);

        await openSignSheet(tester);
        expect(find.text(l10n.signSheetTitle), findsOneWidget);
        expect(attested(tester), isFalse);
        verifyNever(() => blocs.caseWorkspace.add(any()));
      });

      testWidgets('Sign needs the tick and a stroke, and neither '
          'alone is enough', (tester) async {
        await pumpScreen(tester, _signable());
        await openSignSheet(tester);

        expect(enabled(tester, l10n.signSheetSignAndSend), isFalse);

        await tickAttestation(tester);
        expect(enabled(tester, l10n.signSheetSignAndSend), isFalse);

        await tickAttestation(tester);
        expect(attested(tester), isFalse);
        await drawStroke(tester);
        expect(enabled(tester, l10n.signSheetSignAndSend), isFalse);

        await tickAttestation(tester);
        expect(enabled(tester, l10n.signSheetSignAndSend), isTrue);

        await tickAttestation(tester);
        expect(enabled(tester, l10n.signSheetSignAndSend), isFalse);
        verifyNever(() => blocs.caseWorkspace.add(any()));
      });

      testWidgets('Sign is disabled while offline, even with the '
          'tick and a stroke', (tester) async {
        await pumpScreen(tester, _signable());
        await openSignSheet(tester);
        await tickAttestation(tester);
        await drawStroke(tester);
        expect(enabled(tester, l10n.signSheetSignAndSend), isTrue);

        await emit(tester, _signable(offline: true));

        expect(find.text(l10n.signSheetOfflineTitle), findsOneWidget);
        expect(find.text(l10n.signSheetSignAndSend), findsNothing);
        expect(enabled(tester, l10n.signSheetSignWhenOnline), isFalse);

        await emit(tester, _signable());
        expect(enabled(tester, l10n.signSheetSignAndSend), isTrue);
      });

      testWidgets('signing sends the attested signature once', (tester) async {
        await pumpScreen(tester, _signable());
        await openSignSheet(tester);
        await tickAttestation(tester);
        await drawStroke(tester);

        await tester.tap(find.text(l10n.signSheetSignAndSend));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        final sent = verify(
          () => blocs.caseWorkspace.add(captureAny()),
        ).captured.whereType<CaseSignRequested>().single;
        expect(sent.attested, isTrue);
        expect(
          utf8.decode(base64Decode(sent.signaturePng).sublist(1, 4)),
          'PNG',
        );
      });

      testWidgets('a failed sign keeps the sheet and the draft, '
          'shows the error and never shows signed', (tester) async {
        final start = _signable();
        await pumpScreen(tester, start);
        await openSignSheet(tester);
        await tickAttestation(tester);
        await drawStroke(tester);
        await tester.tap(find.text(l10n.signSheetSignAndSend));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        await emit(tester, _failed(start));
        await tester.pump(const Duration(milliseconds: 400));

        final message = AppError.unknown.description(l10n);
        expect(find.text(l10n.signSheetTitle), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is NoticeCard &&
                w.variant == NoticeVariant.error &&
                w.body == message,
          ),
          findsOneWidget,
        );
        expect(find.byType(SignedCaseView), findsNothing);
        expect(find.text(l10n.signedCaseSignedByYou), findsNothing);
        expect(find.text(_ownDiagnosis), findsOneWidget);
        expect(find.text(_ownComments), findsOneWidget);
        expect(attested(tester), isTrue);
        expect(find.text(l10n.signSheetClear), findsOneWidget);
        expect(enabled(tester, l10n.signSheetSignAndSend), isTrue);

        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('only a successful sign closes the sheet and shows '
          'the signed report', (tester) async {
        final start = _signable();
        await pumpScreen(tester, start);
        await openSignSheet(tester);

        await emit(
          tester,
          CaseSignSuccess(
            caseUid: _caseUid,
            caseModel: start.caseModel,
            draft: start.draft,
            signed: _signedReport,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text(l10n.signSheetTitle), findsNothing);
        expect(find.byType(SignedCaseView), findsOneWidget);
        expect(find.text(l10n.signedCaseSignedByYou), findsOneWidget);
      });

      test('every workspace string has a Swahili one that is not '
          'the English', () {
        Map<String, dynamic> read(String name) =>
            jsonDecode(File('lib/l10n/arb/$name.arb').readAsStringSync())
                as Map<String, dynamic>;
        final en = read('app_en');
        final sw = read('app_sw');
        final keys = [
          for (final key in en.keys)
            if (!key.startsWith('@') &&
                RegExp(
                  '^(workspace|score|signSheet|signedCase)[A-Z]',
                ).hasMatch(key))
              key,
        ];

        expect(keys, isNotEmpty);
        for (final key in keys) {
          expect(sw[key], isA<String>(), reason: 'sw is missing $key');
          expect(sw[key], isNot(en[key]), reason: 'sw repeats English: $key');
        }
      });

      test('the workspace code holds no string literal of its own', () {
        final literal = RegExp(
          r'''(Text\(|label:|title:|body:|hint:|message:|semanticLabel:)\s*'[A-Za-z]''',
        );
        for (final path in [
          'lib/features/reports/presentation/case_workspace_screen.dart',
          'lib/features/reports/presentation/widgets/workspace_score_card.dart',
          'lib/features/reports/presentation/widgets/workspace_sign_sheet.dart',
          'lib/features/reports/presentation/widgets/signed_case_view.dart',
          'lib/features/reports/presentation/widgets/revision_sheet.dart',
          'lib/features/reports/presentation/widgets/verdict_selector.dart',
        ]) {
          expect(
            literal.hasMatch(File(path).readAsStringSync()),
            isFalse,
            reason: '$path draws an English literal',
          );
        }
      });

      testWidgets('Swahili replaces the English on the workspace', (
        tester,
      ) async {
        await pumpScreen(tester, _locked(), locale: const Locale('sw'));

        for (final (en, sw) in [
          (l10n.scoreTitle, swL10n.scoreTitle),
          (l10n.scoreLockLine, swL10n.scoreLockLine),
          (l10n.scoreSave, swL10n.scoreSave),
          (l10n.workspaceSaveDraft, swL10n.workspaceSaveDraft),
          (l10n.workspaceSignReport, swL10n.workspaceSignReport),
          (l10n.workspaceAiPreread, swL10n.workspaceAiPreread),
        ]) {
          expect(find.text(en), findsNothing, reason: en);
          expect(find.text(sw), findsOneWidget, reason: sw);
        }
      });

      testWidgets('dark mode draws the locked workspace and the '
          'sign sheet', (tester) async {
        await pumpScreen(tester, _locked(), themeMode: .dark);

        expect(
          Theme.of(tester.element(find.byType(CaseWorkspaceScreen))).brightness,
          Brightness.dark,
        );
        expect(find.byType(AiDraftFrame), findsOneWidget);
        expect(find.byType(WorkspaceScoreCard), findsOneWidget);
        expect(tester.takeException(), isNull);

        await pumpScreen(tester, _signable(), themeMode: .dark);
        await openSignSheet(tester);

        expect(find.text(l10n.signSheetTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Swahili at 1.3x text on a 390 dp screen does not '
          'overflow', (tester) async {
        // The default surface is already 390 dp wide.
        await pumpScreen(
          tester,
          _locked(),
          locale: const Locale('sw'),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(swL10n.scoreTitle), findsOneWidget);

        await pumpScreen(
          tester,
          _signable(
            findings: [const NotifiableFindingModel(diseaseId: 'malaria')],
          ),
          locale: const Locale('sw'),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(swL10n.workspaceSignReport));
        await settleSheet(tester);

        expect(find.text(swL10n.signSheetTitle), findsOneWidget);
        expect(
          find.text(swL10n.signSheetNotifiableNotice('Malaria')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a tablet width draws the workspace and the sign '
          'sheet', (tester) async {
        const tablet = Size(820 * 3, 12000);
        await pumpScreen(tester, _locked(), surface: tablet);
        expect(find.byType(WorkspaceScoreCard), findsOneWidget);
        expect(tester.takeException(), isNull);

        await pumpScreen(tester, _signable(), surface: tablet);
        await openSignSheet(tester);

        expect(find.text(l10n.signSheetTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('data', () {
      testWidgets('opens the case as the pathologist when the bloc holds '
          'another', (tester) async {
        await pumpScreen(tester, const CaseWorkspaceInitial());

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          CaseWorkspaceOpened(
            caseUid: _caseUid,
            pathologistUid: RoleSessions.pathologist.doctor.uid,
          ),
        ]);
      });

      testWidgets('does not reopen a case the bloc already holds', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());

        verifyNever(() => blocs.caseWorkspace.add(any()));
      });

      testWidgets('the top bar names the order, the test and the patient', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());

        expect(find.text('TB-0231'), findsOneWidget);
        expect(find.text('Malaria smear · Amina W., 46'), findsOneWidget);
      });

      testWidgets('reads the register once and offers its confirmable '
          'diseases', (tester) async {
        await pumpScreen(tester, _signable());

        verify(reference.notifiableDiseases).called(1);
      });

      testWidgets('asks storage for the slide, and draws no viewer when it '
          'has none', (tester) async {
        await pumpScreen(tester, _chooser());

        verify(() => storage.downloadUrl('slides/smear.png')).called(1);
        expect(find.byType(AiDraftFrame), findsOneWidget);
      });

      testWidgets('the pre-read card carries the disclaimer, not a row', (
        tester,
      ) async {
        when(
          () => storage.downloadUrl('slides/smear.png'),
        ).thenAnswer((_) async => 'https://example.test/slide.png');
        when(
          () => storage.downloadUrl('heat/seg.png'),
        ).thenAnswer((_) async => 'https://example.test/heat.png');
        await pumpScreen(
          tester,
          _loaded(
            draft: _draft(),
            preread: _preread().copyWith(segmentationPath: 'heat/seg.png'),
            score: _score,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text(l10n.workspaceAiPrereadDisclaimer), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text(l10n.workspaceAiPrereadDisclaimer),
            matching: find.byType(AiDraftFrame),
          ),
          findsOneWidget,
        );
      });

      testWidgets('Save draft sends only what changed', (tester) async {
        await pumpScreen(tester, _signable());

        await tester.enterText(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is TabibuTextField && w.label == l10n.reportSectionComments,
            ),
            matching: find.byType(EditableText),
          ),
          'A new comment.',
        );
        await tester.tap(find.text(l10n.workspaceSaveDraft));
        await tester.pump();

        expect(verify(() => blocs.caseWorkspace.add(captureAny())).captured, [
          const CaseDraftEdited(fields: {'comments': 'A new comment.'}),
        ]);
      });

      testWidgets('a pasted long diagnosis produces one draft write', (
        tester,
      ) async {
        await pumpScreen(tester, _signable());
        clearInteractions(blocs.caseWorkspace);

        final pasted = 'D' * 500;
        await tester.enterText(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is TabibuTextField &&
                  w.label == l10n.reportSectionDiagnosis,
            ),
            matching: find.byType(EditableText),
          ),
          pasted,
        );
        await tester.pump();
        await tester.tap(find.text(l10n.workspaceSaveDraft));
        await tester.pump();

        final edits = verify(
          () => blocs.caseWorkspace.add(captureAny()),
        ).captured.whereType<CaseDraftEdited>();
        expect(edits.length, 1);
        expect(edits.single.fields['diagnosis'], pasted);
      });

      testWidgets('a write failure shows the error notification', (
        tester,
      ) async {
        final start = _signable();
        await pumpScreen(tester, start);

        await emit(tester, _failed(start));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(AppError.unknown.description(l10n)), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('the list ends in the history row', (tester) async {
        await pumpScreen(tester, _loaded());

        expect(find.text(l10n.accessLogTitle), findsOneWidget);
      });

      testWidgets('an amendment draft shows the reason and no AI controls', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          CaseWorkspaceLoadSuccess(
            caseUid: _caseUid,
            caseModel: _case().copyWith(
              currentStage: 'ReportSigned',
              currentReportUid: 'report-1',
            ),
            draft: const ReportDraftModel(
              uid: 'draft-1',
              caseUid: _caseUid,
              kind: 'Amendment',
              diagnosis: _ownDiagnosis,
              comments: _ownComments,
              amendmentReason: 'Typo in site',
            ),
            preread: _preread(),
            signed: _signedReport,
          ),
        );

        expect(find.text('1 · ${l10n.reportSectionDiagnosis}'), findsOneWidget);
        expect(find.text(l10n.workspaceStepAiScore), findsNothing);
        expect(find.text(l10n.workspaceAmendmentReason), findsOneWidget);
        expect(find.text('Typo in site'), findsOneWidget);
        expect(find.text(_ownDiagnosis), findsOneWidget);
        verifyNever(
          () => blocs.caseWorkspace.add(const CaseDraftStartedFromPreread()),
        );
        expect(find.text(l10n.workspaceAiDraft), findsNothing);
        expect(find.byType(AiMark), findsNothing);
        expect(find.text(l10n.scoreTitle), findsNothing);
      });

      testWidgets('an addendum draft locks diagnosis and shows the text', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          CaseWorkspaceLoadSuccess(
            caseUid: _caseUid,
            caseModel: _case().copyWith(
              currentStage: 'ReportSigned',
              currentReportUid: 'report-1',
            ),
            draft: const ReportDraftModel(
              uid: 'draft-1',
              caseUid: _caseUid,
              kind: 'Addendum',
              diagnosis: _ownDiagnosis,
              comments: _ownComments,
              addendumText: 'Additional IHC pending.',
            ),
            signed: _signedReport,
          ),
        );

        expect(find.text('1 · ${l10n.reportSectionDiagnosis}'), findsOneWidget);
        expect(find.text(l10n.workspaceStepAiScore), findsNothing);
        expect(
          tester
              .widget<ReportFlagSwitch>(
                find.widgetWithText(
                  ReportFlagSwitch,
                  l10n.workspaceCriticalFinding,
                ),
              )
              .onChanged,
          isNull,
        );
        expect(find.textContaining(l10n.workspaceAddendumText), findsOneWidget);
        expect(find.text('Additional IHC pending.'), findsOneWidget);
        verifyNever(
          () => blocs.caseWorkspace.add(const CaseDraftStartedFromPreread()),
        );
        expect(find.text(_ownDiagnosis), findsOneWidget);
      });
    });

    group('large text', () {
      // The revision editor with its reason notice fits at 1.0x and 2.0x
      // text, in English and Swahili, light and dark.
      testWidgets('the amendment editor fits', (tester) async {
        final state = CaseWorkspaceLoadSuccess(
          caseUid: _caseUid,
          caseModel: _case().copyWith(
            currentStage: 'ReportSigned',
            currentReportUid: 'report-1',
          ),
          draft: const ReportDraftModel(
            uid: 'draft-1',
            caseUid: _caseUid,
            kind: 'Amendment',
            diagnosis: _ownDiagnosis,
            comments: _ownComments,
            amendmentReason: 'Typo in site',
          ),
          signed: _signedReport,
        );
        for (final scale in [1.0, 2.0]) {
          for (final locale in [const Locale('en'), const Locale('sw')]) {
            for (final mode in [ThemeMode.light, ThemeMode.dark]) {
              final l10n = lookupAppLocalizations(locale);
              await pumpScreen(
                tester,
                state,
                locale: locale,
                themeMode: mode,
                textScale: scale,
              );

              expect(find.text(l10n.workspaceAmendmentReason), findsOneWidget);
              expect(find.text('Typo in site'), findsOneWidget);
              expect(find.text(l10n.workspaceDiscardRevision), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    });

    group('discard revision', () {
      CaseModel signedCase() => _case().copyWith(
        currentStage: 'ReportSigned',
        currentReportUid: 'report-1',
      );

      ReportDraftModel amendment({String status = 'Editing'}) =>
          const ReportDraftModel(
            uid: 'draft-1',
            caseUid: _caseUid,
            kind: 'Amendment',
            diagnosis: _ownDiagnosis,
            comments: _ownComments,
            amendmentReason: 'Typo in site',
          ).copyWith(status: status);

      CaseWorkspaceLoadSuccess openAmendment() => CaseWorkspaceLoadSuccess(
        caseUid: _caseUid,
        caseModel: signedCase(),
        draft: amendment(),
        signed: _signedReport,
      );

      CaseWorkspaceLoadSuccess afterDiscard() => CaseWorkspaceLoadSuccess(
        caseUid: _caseUid,
        caseModel: signedCase(),
        draft: amendment(status: 'Closed'),
        signed: _signedReport.copyWith(pathologistUid: 'path-1'),
      );

      void asSigner() {
        final session = RoleSessions.pathologist;
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: session.doctor.copyWith(uid: 'path-1'),
              roles: session.roles,
            ),
          ),
        );
      }

      testWidgets('absent on an Initial draft', (tester) async {
        await pumpScreen(tester, _signable());

        expect(find.text(l10n.workspaceDiscardRevision), findsNothing);
      });

      testWidgets('absent when the revision draft is closed', (tester) async {
        asSigner();
        await pumpScreen(tester, afterDiscard());

        expect(find.byType(SignedCaseView), findsOneWidget);
        expect(find.text(l10n.workspaceDiscardRevision), findsNothing);
      });

      testWidgets('an open amendment offers discard, and confirm sends it', (
        tester,
      ) async {
        await pumpScreen(tester, openAmendment());

        await tester.tap(find.text(l10n.workspaceDiscardRevision));
        await settleSheet(tester);

        expect(find.text(l10n.workspaceDiscardSheetTitle), findsOneWidget);
        expect(find.text(l10n.workspaceDiscardSheetBody), findsOneWidget);
        expect(find.text(l10n.workspaceDiscardSheetConfirm), findsOneWidget);
        expect(find.text(l10n.commonCancel), findsOneWidget);

        await tester.tap(find.text(l10n.workspaceDiscardSheetConfirm));
        await settleSheet(tester);

        verify(
          () => blocs.caseWorkspace.add(const CaseRevisionDiscarded()),
        ).called(1);
      });

      testWidgets('cancel leaves the draft untouched', (tester) async {
        await pumpScreen(tester, openAmendment());

        await tester.tap(find.text(l10n.workspaceDiscardRevision));
        await settleSheet(tester);
        await tester.tap(find.text(l10n.commonCancel));
        await settleSheet(tester);

        verifyNever(() => blocs.caseWorkspace.add(any()));
        expect(find.text('Typo in site'), findsOneWidget);
      });

      testWidgets('after discard the signed view returns with Amend and '
          'Addendum', (tester) async {
        asSigner();
        await pumpScreen(tester, openAmendment());

        await emit(tester, afterDiscard());

        expect(find.byType(SignedCaseView), findsOneWidget);
        expect(find.text(l10n.signedCaseAmend), findsOneWidget);
        expect(find.text(l10n.signedCaseAddendum), findsOneWidget);
        expect(find.text(l10n.workspaceDiscardRevision), findsNothing);
      });

      testWidgets('a failed discard keeps the draft', (tester) async {
        final start = openAmendment();
        await pumpScreen(tester, start);

        await emit(tester, _failed(start));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Typo in site'), findsOneWidget);
        expect(find.text(l10n.workspaceDiscardRevision), findsOneWidget);
        expect(find.text(AppError.unknown.description(l10n)), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });
    });

    group('region read', () {
      CaseWorkspaceLoadSuccess accepted({required String pathologistUid}) =>
          _loaded(
            caseModel: _case().copyWith(pathologistUid: pathologistUid),
            preread: _preread(),
          );

      void usePathologistSession(String uid) {
        final base = RoleSessions.pathologist;
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: base.doctor.copyWith(uid: uid),
              roles: base.roles,
            ),
          ),
        );
      }

      Future<void> pumpReady(
        WidgetTester tester, {
        bool Function()? regionReadEnabled,
        RegionReadClient? regionClient,
        Future<Uint8List?> Function()? regionCapture,
      }) async {
        // Before the first pump: a failed load never retries, so the
        // slide client must be in place before NetworkImage reads.
        // The ask pill waits for the slide's first frame.
        debugNetworkImageHttpClientProvider = _SlideHttpClient.new;
        addTearDown(() => debugNetworkImageHttpClientProvider = null);
        when(
          () => storage.downloadUrl('slides/smear.png'),
        ).thenAnswer((_) async => 'https://example.test/slide.png');
        await pumpScreen(
          tester,
          accepted(pathologistUid: 'path-1'),
          regionReadEnabled: regionReadEnabled,
          regionClient: regionClient ?? FakeRegionReadClient(),
          regionCapture: regionCapture ?? () async => _regionBytes,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
      }

      /// Taps the pill, asks with [question] through the open sheet, and
      /// settles with the answer in the panel.
      Future<void> ask(WidgetTester tester, {String question = ''}) async {
        await tester.ensureVisible(find.text(l10n.regionAskButton));
        await tester.tap(find.text(l10n.regionAskButton));
        await tester.pumpAndSettle();
        if (question.isNotEmpty) {
          await tester.enterText(
            find.descendant(
              of: find.byType(RegionReadSheetBody),
              matching: find.byType(TextField),
            ),
            question,
          );
        }
        await tester.tap(find.text(l10n.regionAskSubmit));
        await tester.pumpAndSettle();
      }

      testWidgets('shows the ask pill when on', (tester) async {
        usePathologistSession('path-1');
        await pumpReady(tester, regionReadEnabled: () => true);

        expect(find.text(l10n.regionAskButton), findsOneWidget);
      });

      testWidgets('hides the ask pill when the switch is off', (tester) async {
        usePathologistSession('path-1');
        await pumpReady(tester, regionReadEnabled: () => false);

        expect(find.text(l10n.regionAskButton), findsNothing);
      });

      testWidgets('a doctor never sees the ask pill', (tester) async {
        final base = RoleSessions.doctor();
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: base.doctor.copyWith(uid: 'doc-1'),
              roles: base.roles,
            ),
          ),
        );
        when(
          () => storage.downloadUrl('slides/smear.png'),
        ).thenAnswer((_) async => 'https://example.test/slide.png');
        await pumpScreen(
          tester,
          accepted(pathologistUid: 'path-1'),
          regionReadEnabled: () => true,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text(l10n.regionAskButton), findsNothing);
      });

      testWidgets('tapping the pill opens the read sheet', (tester) async {
        usePathologistSession('path-1');
        await pumpReady(tester, regionReadEnabled: () => true);

        await tester.ensureVisible(find.text(l10n.regionAskButton));
        await tester.tap(find.text(l10n.regionAskButton));
        await tester.pumpAndSettle();

        expect(find.text(l10n.regionAskSubmit), findsOneWidget);
      });

      testWidgets('the guide shows before any ask', (tester) async {
        usePathologistSession('path-1');
        await pumpReady(tester, regionReadEnabled: () => true);

        expect(find.byType(RegionReadPanel), findsOneWidget);
        expect(find.text(l10n.regionReadGuide), findsOneWidget);
      });

      testWidgets('an ask shows the answer with the model arrow', (
        tester,
      ) async {
        usePathologistSession('path-1');
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: FakeRegionReadClient(result: _regionRead),
        );
        await ask(tester, question: 'Malignant?');

        expect(find.text('Calm lymphocytes.'), findsOneWidget);
        expect(find.text('• Even spacing'), findsOneWidget);
        expect(
          find.textContaining(AiLogicService.regionReadModel),
          findsOneWidget,
        );
        expect(
          find.textContaining(AiLogicService.defaultRegionTemplateId),
          findsOneWidget,
        );
        expect(find.textContaining('Malignant?'), findsOneWidget);
        expect(find.text(l10n.regionReadDraftLabel), findsOneWidget);
        expect(find.text(l10n.regionReadDisclaimer), findsOneWidget);
      });

      testWidgets('a second ask overwrites the first', (tester) async {
        usePathologistSession('path-1');
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: _ScriptedRegionClient([_regionRead, _regionReadB]),
        );
        await ask(tester);
        expect(find.text('Calm lymphocytes.'), findsOneWidget);

        await ask(tester);

        expect(find.text('Crowded glands.'), findsOneWidget);
        expect(find.text('Calm lymphocytes.'), findsNothing);
      });

      testWidgets('an ask sends no answer text to the bloc', (tester) async {
        final added = <String>[];
        when(() => blocs.cases.add(any())).thenAnswer((invocation) {
          added.add('${invocation.positionalArguments.single}');
        });
        usePathologistSession('path-1');
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: FakeRegionReadClient(result: _regionRead),
        );
        await ask(tester, question: 'Malignant?');

        final sent = added.join(' ');
        expect(sent, isNot(contains('Calm lymphocytes.')));
        expect(sent, isNot(contains('Even spacing')));
        expect(sent, isNot(contains('Malignant?')));
        expect(sent, isNot(contains('One region, not a diagnosis.')));
      });

      testWidgets('leaving and reopening shows the guide again', (
        tester,
      ) async {
        usePathologistSession('path-1');
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: FakeRegionReadClient(result: _regionRead),
        );
        await ask(tester);
        expect(find.text('Calm lymphocytes.'), findsOneWidget);

        await tester.pumpWidget(Container());
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: FakeRegionReadClient(result: _regionRead),
        );

        expect(find.text(l10n.regionReadGuide), findsOneWidget);
        expect(find.text('Calm lymphocytes.'), findsNothing);
      });

      testWidgets('changing case clears the answer', (tester) async {
        usePathologistSession('path-1');
        tester.view.physicalSize = const Size(1170, 12000);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        debugNetworkImageHttpClientProvider = _SlideHttpClient.new;
        addTearDown(() => debugNetworkImageHttpClientProvider = null);
        when(
          () => storage.downloadUrl('slides/smear.png'),
        ).thenAnswer((_) async => 'https://example.test/slide.png');
        states = StreamController<CaseWorkspaceState>.broadcast();
        addTearDown(states.close);
        whenListen(
          blocs.caseWorkspace,
          states.stream,
          initialState: accepted(pathologistUid: 'path-1'),
        );
        // One route with the case in its path: going case to case
        // updates the screen in place, as in production.
        final router = GoRouter(
          initialLocation: '/case/case-1',
          routes: [
            GoRoute(
              path: '/case/:caseUid',
              builder: (_, state) => CaseWorkspaceScreen(
                caseUid: state.pathParameters['caseUid']!,
                reference: reference,
                storage: storage,
                regionReadEnabled: () => true,
                regionClient: FakeRegionReadClient(result: _regionRead),
                regionCapture: () async => _regionBytes,
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              ...blocs.providers,
            ],
            child: MaterialApp.router(
              theme: buildTheme(.light),
              darkTheme: buildTheme(.dark),
              localizationsDelegates: tabibuLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        await ask(tester);
        expect(find.text('Calm lymphocytes.'), findsOneWidget);

        router.go('/case/case-2');
        await tester.pumpAndSettle();

        expect(find.text(l10n.regionReadGuide), findsOneWidget);
        expect(find.text('Calm lymphocytes.'), findsNothing);
      });

      testWidgets('a doctor never sees the panel', (tester) async {
        final base = RoleSessions.doctor();
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: base.doctor.copyWith(uid: 'doc-1'),
              roles: base.roles,
            ),
          ),
        );
        await pumpReady(tester, regionReadEnabled: () => true);

        expect(find.byType(RegionReadPanel), findsNothing);
        expect(find.text(l10n.regionReadGuide), findsNothing);
      });

      testWidgets('dismissing the sheet keeps the previous answer', (
        tester,
      ) async {
        usePathologistSession('path-1');
        await pumpReady(
          tester,
          regionReadEnabled: () => true,
          regionClient: FakeRegionReadClient(result: _regionRead),
        );
        await ask(tester);
        expect(find.text('Calm lymphocytes.'), findsOneWidget);

        await tester.ensureVisible(find.text(l10n.regionAskButton));
        await tester.tap(find.text(l10n.regionAskButton));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.text(l10n.regionAskSubmit))).pop();
        await tester.pumpAndSettle();

        expect(find.text('Calm lymphocytes.'), findsOneWidget);
      });
    });
  });
}
