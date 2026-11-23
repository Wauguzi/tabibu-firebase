// cspell:ignore Aminá
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_event.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_state.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/conversations/presentation/new_mdt_screen.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_invite_picker.dart';
import 'package:tabibu/features/practitioners/blocs/directory_bloc/directory_event.dart';
import 'package:tabibu/features/practitioners/blocs/directory_bloc/directory_state.dart';
import 'package:tabibu/features/practitioners/data/models/practitioner_model.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

PractitionerSession _session() {
  final base = RoleSessions.doctor();
  return PractitionerSession(
    doctor: base.doctor.copyWith(
      uid: 'me',
      specialties: const ['General Practice'],
    ),
    roles: base.roles,
  );
}

PractitionerModel _doc(String uid, String first, String last) =>
    PractitionerModel.empty().copyWith(
      uid: uid,
      title: 'Dr.',
      firstName: first,
      lastName: last,
      specialties: const ['Haematology'],
      isAvailable: true,
    );

void main() {
  late FeatureBlocs blocs;
  late MockAuthBloc authBloc;
  final l10n = lookupAppLocalizations(const Locale('en'));

  final colleague = _doc('dr-2', 'Mary', 'Njeri');
  final meInDirectory = _doc('me', 'Self', 'Self');

  setUpAll(() {
    registerFallbackValue(const MdtReset());
    registerFallbackValue(const DirectoryRequested());
    registerFallbackValue(const CasesRequested(uid: '', role: Role.doctor));
  });

  setUp(() {
    blocs = FeatureBlocs();
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(SignInSuccess(session: _session()));
    when(() => blocs.mdt.add(any())).thenReturn(null);
    when(() => blocs.mdt.state).thenReturn(const MdtInitial());
    when(() => blocs.cases.state).thenReturn(
      const CasesLoadSuccess(
        cases: [
          CaseModel(
            uid: 'c1',
            orderNumber: 'TB-0224',
            doctorUid: 'me',
            pathologistUid: 'path-1',
            pathologistName: 'Dr Path',
            patientName: 'Amina',
          ),
        ],
      ),
    );
    when(() => blocs.directory.state).thenReturn(
      DirectoryLoadSuccess(
        all: [colleague, meInDirectory],
        visible: [colleague, meInDirectory],
      ),
    );
  });

  Future<void> pumpNew(
    WidgetTester tester, {
    String caseUid = 'c1',
    Role role = .doctor,
    Locale? locale,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1170, 5000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (role == .pathologist) {
      final base = RoleSessions.pathologist;
      when(() => authBloc.state).thenReturn(
        SignInSuccess(
          session: PractitionerSession(
            doctor: base.doctor.copyWith(uid: 'me'),
            roles: base.roles,
          ),
        ),
      );
    }
    final router = GoRouter(
      initialLocation: '/mdt/new',
      routes: [
        GoRoute(
          path: '/mdt/new',
          builder: (_, _) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: authBloc),
                ...blocs.providers,
              ],
              child: NewMdtScreen(role: role, caseUid: caseUid),
            ),
          ),
        ),
      ],
    );
    await tester.pumpRouterApp(router, locale: locale);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('NewMdtScreen', () {
    testWidgets('the invite list is the directory minus me', (tester) async {
      await pumpNew(tester);

      expect(find.byType(MdtInvitePicker), findsOneWidget);
      expect(find.textContaining('Mary Njeri'), findsOneWidget);
      expect(find.textContaining('Self Self'), findsNothing);
    });

    testWidgets('a blank subject is refused and open is never sent', (
      tester,
    ) async {
      await pumpNew(tester);

      // Pick the colleague.
      await tester.tap(find.textContaining('Mary Njeri'));
      await tester.pump();

      // Primary without a subject.
      await tester.ensureVisible(find.byType(TabibuButton).last);
      await tester.tap(find.byType(TabibuButton).last);
      await tester.pump();

      expect(find.text(l10n.mdtAboutRequired), findsOneWidget);
      verifyNever(() => blocs.mdt.add(any(that: isA<MdtOpenRequested>())));
    });

    testWidgets('a subject is required and is sent as description', (
      tester,
    ) async {
      await pumpNew(tester);

      await tester.enterText(find.byType(TextField).first, 'Second opinion');
      await tester.tap(find.textContaining('Mary Njeri'));
      await tester.pump();

      await tester.ensureVisible(find.byType(TabibuButton).last);
      await tester.tap(find.byType(TabibuButton).last);
      await tester.pump();

      final open = verify(
        () => blocs.mdt.add(captureAny()),
      ).captured.whereType<MdtOpenRequested>().single;
      expect(open.caseUid, 'c1');
      expect(open.description, 'Second opinion');
      expect(open.inviteeUids, ['dr-2']);
    });

    testWidgets('a case that already has a consult is not offered', (
      tester,
    ) async {
      when(() => blocs.cases.state).thenReturn(
        const CasesLoadSuccess(
          cases: [
            CaseModel(
              uid: 'c1',
              orderNumber: 'TB-0224',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Amina',
            ),
            CaseModel(
              uid: 'c2',
              orderNumber: 'TB-HIDDEN',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Other',
              openMdtUid: 'mdt-9',
            ),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '');

      expect(find.textContaining('TB-0224'), findsWidgets);
      expect(find.textContaining('TB-HIDDEN'), findsNothing);
    });

    testWidgets('a pathologist is offered only their own open cases', (
      tester,
    ) async {
      when(() => blocs.cases.state).thenReturn(
        const CasesLoadSuccess(
          cases: [
            CaseModel(
              uid: 'mine',
              orderNumber: 'TB-MINE',
              doctorUid: 'dr-2',
              pathologistUid: 'me',
              patientName: 'Amina',
            ),
            CaseModel(
              uid: 'theirs',
              orderNumber: 'TB-THEIRS',
              doctorUid: 'dr-2',
              pathologistUid: 'other-path',
              patientName: 'Other',
            ),
            CaseModel(
              uid: 'busy',
              orderNumber: 'TB-BUSY',
              doctorUid: 'dr-2',
              pathologistUid: 'me',
              patientName: 'Busy',
              openMdtUid: 'mdt-9',
            ),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '', role: .pathologist);

      expect(find.textContaining('TB-MINE'), findsWidgets);
      expect(find.textContaining('TB-THEIRS'), findsNothing);
      expect(find.textContaining('TB-BUSY'), findsNothing);
    });

    testWidgets('picking a case collapses the step and the header reopens it', (
      tester,
    ) async {
      when(() => blocs.cases.state).thenReturn(
        const CasesLoadSuccess(
          cases: [
            CaseModel(
              uid: 'c1',
              orderNumber: 'TB-0224',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Amina',
            ),
            CaseModel(
              uid: 'c2',
              orderNumber: 'TB-0999',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Other',
            ),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '');

      expect(find.textContaining('TB-0224'), findsOneWidget);
      expect(find.textContaining('TB-0999'), findsOneWidget);

      await tester.tap(find.textContaining('TB-0999'));
      await tester.pump();

      expect(find.textContaining('TB-0224'), findsNothing);
      expect(find.textContaining('TB-0999'), findsOneWidget);

      await tester.tap(find.text(l10n.mdtPickCase));
      await tester.pump();

      expect(find.textContaining('TB-0224'), findsOneWidget);
      expect(find.textContaining('TB-0999'), findsWidgets);
    });

    testWidgets('the case search folds accents', (tester) async {
      when(() => blocs.cases.state).thenReturn(
        const CasesLoadSuccess(
          cases: [
            CaseModel(
              uid: 'c1',
              orderNumber: 'TB-0224',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Aminá',
            ),
            CaseModel(
              uid: 'c2',
              orderNumber: 'TB-0999',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Zawadi',
            ),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '');

      await tester.enterText(find.byType(TextField).first, 'amina');
      await tester.pump();

      expect(find.textContaining('Aminá'), findsOneWidget);
      expect(find.textContaining('Zawadi'), findsNothing);
    });

    testWidgets('both lists scroll inside a capped height', (tester) async {
      when(() => blocs.cases.state).thenReturn(
        CasesLoadSuccess(
          cases: [
            for (var i = 0; i < 8; i++)
              CaseModel(
                uid: 'c$i',
                orderNumber: 'TB-100$i',
                doctorUid: 'me',
                pathologistUid: 'path-1',
                patientName: 'Person $i',
              ),
          ],
        ),
      );
      when(() => blocs.directory.state).thenReturn(
        DirectoryLoadSuccess(
          all: [
            for (var i = 0; i < 8; i++) _doc('dr-$i', 'Colleague', 'Number$i'),
            meInDirectory,
          ],
          visible: [
            for (var i = 0; i < 8; i++) _doc('dr-$i', 'Colleague', 'Number$i'),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '');

      final cases = tester.getSize(find.byKey(const Key('mdt-case-list')));
      final invite = tester.getSize(find.byKey(const Key('mdt-invite-list')));
      expect(cases.height, mdtPickerListHeight);
      expect(invite.height, mdtPickerListHeight);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const Key('mdt-case-list')),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const Key('mdt-invite-list')),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
    });

    testWidgets('send stays off until the case, a colleague and the question '
        'are set', (tester) async {
      when(() => blocs.cases.state).thenReturn(
        const CasesLoadSuccess(
          cases: [
            CaseModel(
              uid: 'c1',
              orderNumber: 'TB-0224',
              doctorUid: 'me',
              pathologistUid: 'path-1',
              patientName: 'Amina',
            ),
          ],
        ),
      );
      await pumpNew(tester, caseUid: '');

      await tester.enterText(find.byType(TextField).at(1), 'Second opinion');
      await tester.tap(find.textContaining('Mary Njeri'));
      await tester.pump();
      await tester.ensureVisible(find.byType(TabibuButton).last);
      await tester.tap(find.byType(TabibuButton).last);
      await tester.pump();
      verifyNever(() => blocs.mdt.add(any(that: isA<MdtOpenRequested>())));

      await tester.tap(find.textContaining('TB-0224'));
      await tester.pump();
      await tester.ensureVisible(find.byType(TabibuButton).last);
      await tester.tap(find.byType(TabibuButton).last);
      await tester.pump();

      verify(() => blocs.mdt.add(any(that: isA<MdtOpenRequested>()))).called(1);
    });

    testWidgets('the form holds at 2.0x in Kiswahili', (tester) async {
      final sw = lookupAppLocalizations(const Locale('sw'));
      await pumpNew(tester, locale: const Locale('sw'), textScale: 2);

      expect(find.text(sw.mdtNewTitle), findsOneWidget);
      expect(find.text(sw.mdtPickCase), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
