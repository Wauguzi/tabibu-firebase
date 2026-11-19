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
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/conversations/data/models/case_summary_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_model.dart';
import 'package:tabibu/features/conversations/data/models/message_preview_model.dart';
import 'package:tabibu/features/conversations/presentation/mdt_screen.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_invite_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

PractitionerSession _session({Role role = .doctor}) {
  final base = role == .pathologist
      ? RoleSessions.pathologist
      : RoleSessions.doctor();
  return PractitionerSession(
    doctor: base.doctor.copyWith(uid: 'me'),
    roles: base.roles,
  );
}

ConversationModel _consult({
  required String myStatus,
  String uid = 'mdt-1',
  CaseSummaryModel summary = const CaseSummaryModel(
    caseRef: 'C-1',
    signedDiagnosisExcerpt: 'secret',
  ),
  String lastSenderUid = '',
  String lastText = 'secret thread',
}) => ConversationModel(
  uid: uid,
  specialty: 'Haematology',
  description: 'Second opinion',
  createdByUid: 'lead',
  participantUids: const ['me', 'lead'],
  members: {
    'lead': const ConversationMemberModel(
      uid: 'lead',
      title: 'Dr.',
      firstName: 'Lead',
      lastName: 'Person',
      status: 'Accepted',
    ),
    'me': ConversationMemberModel(
      uid: 'me',
      firstName: 'Me',
      status: myStatus,
      invitedByUid: 'lead',
    ),
  },
  lastMessage: MessagePreviewModel(text: lastText, senderUid: lastSenderUid),
  caseSummary: summary,
  linkedResourceUid: 'c1',
);

void main() {
  late FeatureBlocs blocs;
  late MockAuthBloc authBloc;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const MdtReset());
  });

  setUp(() {
    blocs = FeatureBlocs();
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(SignInSuccess(session: _session()));
    when(() => blocs.mdt.add(any())).thenReturn(null);
  });

  Future<void> settleSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    required MdtState state,
    Role role = .doctor,
    Locale? locale,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(
      () => authBloc.state,
    ).thenReturn(SignInSuccess(session: _session(role: role)));
    when(() => blocs.mdt.state).thenReturn(state);
    final router = GoRouter(
      initialLocation: '/mdt',
      routes: [
        GoRoute(
          path: '/mdt',
          builder: (_, _) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: authBloc),
                ...blocs.providers,
              ],
              child: MdtScreen(role: role),
            ),
          ),
        ),
      ],
    );
    await tester.pumpRouterApp(router, locale: locale);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('MdtScreen', () {
    testWidgets('an invite shows the invite card and never the '
        'summary or last message', (tester) async {
      final invite = _consult(myStatus: 'Invited');
      await pumpTab(
        tester,
        state: MdtLoadSuccess(conversations: [invite], invites: [invite]),
      );

      expect(find.byType(MdtInviteCard), findsOneWidget);
      expect(find.textContaining('Dr. Lead'), findsWidgets);
      expect(find.text('secret'), findsNothing);
      expect(find.text('secret thread'), findsNothing);
      expect(find.text(l10n.mdtReportInProgress), findsNothing);
    });

    testWidgets('Decline asks first and only then responds', (tester) async {
      final invite = _consult(myStatus: 'Invited');
      await pumpTab(
        tester,
        state: MdtLoadSuccess(conversations: [invite], invites: [invite]),
      );

      Finder inSheet(String text) => find.descendant(
        of: find.byType(TabibuBottomSheet),
        matching: find.text(text),
      );

      clearInteractions(blocs.mdt);
      await tester.tap(find.text(l10n.mdtDecline));
      await settleSheet(tester);

      expect(inSheet(l10n.mdtDeclineInvite), findsOneWidget);
      // No reason chips — confirm only.
      expect(find.textContaining('Too busy'), findsNothing);
      expect(find.textContaining('Undo'), findsNothing);

      verifyNever(() => blocs.mdt.add(any(that: isA<MdtRespondRequested>())));

      await tester.tap(inSheet(l10n.mdtDeclineInvite));
      await tester.pumpAndSettle();

      verify(
        () => blocs.mdt.add(
          any(
            that: isA<MdtRespondRequested>()
                .having((e) => e.conversationUid, 'id', 'mdt-1')
                .having((e) => e.accept, 'accept', isFalse),
          ),
        ),
      ).called(1);
    });

    testWidgets('cancelling the decline sheet changes nothing', (tester) async {
      final invite = _consult(myStatus: 'Invited');
      await pumpTab(
        tester,
        state: MdtLoadSuccess(conversations: [invite], invites: [invite]),
      );

      await tester.tap(find.text(l10n.mdtDecline));
      await settleSheet(tester);
      await tester.tap(find.text(l10n.commonCancel));
      await settleSheet(tester);

      verifyNever(() => blocs.mdt.add(any(that: isA<MdtRespondRequested>())));
    });

    testWidgets('a pathologist starts a consult from an empty list', (
      tester,
    ) async {
      await pumpTab(tester, role: .pathologist, state: const MdtLoadSuccess());

      expect(find.text(l10n.mdtStartConsult), findsOneWidget);
      expect(find.text('Go to my desk'), findsNothing);
    });

    testWidgets('a pathologist starts a consult from the list', (tester) async {
      await pumpTab(
        tester,
        role: .pathologist,
        state: MdtLoadSuccess(conversations: [_consult(myStatus: 'Accepted')]),
      );

      expect(find.byType(Fab), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.mdtStartConsult), findsOneWidget);
    });

    testWidgets('a doctor still starts a consult from an empty list', (
      tester,
    ) async {
      await pumpTab(tester, state: const MdtLoadSuccess());

      expect(find.text(l10n.mdtStartConsult), findsOneWidget);
      expect(find.byType(Fab), findsNothing);
    });

    testWidgets('the consult number and the patient line are separate', (
      tester,
    ) async {
      await pumpTab(
        tester,
        state: MdtLoadSuccess(
          conversations: [
            _consult(
              myStatus: 'Accepted',
              summary: const CaseSummaryModel(
                caseRef: 'C-1',
                ageBand: '30-39',
                sex: 'Female',
              ),
              lastSenderUid: 'me',
            ),
          ],
        ),
      );

      expect(find.text('C-1'), findsOneWidget);
      expect(find.text('30-39 · ${l10n.sexFemale}'), findsOneWidget);
      expect(find.text('C-1 · 30-39 · ${l10n.sexFemale}'), findsNothing);
      expect(find.textContaining('${l10n.mdtYou}:'), findsOneWidget);
    });

    testWidgets('a consult with no age or sex has no empty patient line', (
      tester,
    ) async {
      await pumpTab(
        tester,
        state: MdtLoadSuccess(
          conversations: [
            _consult(
              myStatus: 'Accepted',
              summary: const CaseSummaryModel(caseRef: 'C-1'),
              lastText: '',
            ),
          ],
        ),
      );

      expect(find.text('C-1'), findsOneWidget);
      expect(find.text(' · '), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.trim().isEmpty ?? false),
        ),
        findsNothing,
      );
    });

    testWidgets('the list holds at 2.0x in Kiswahili', (tester) async {
      final sw = lookupAppLocalizations(const Locale('sw'));
      await pumpTab(
        tester,
        state: MdtLoadSuccess(
          conversations: [
            _consult(
              myStatus: 'Accepted',
              summary: const CaseSummaryModel(
                caseRef: 'C-1',
                ageBand: '30-39',
                sex: 'Female',
              ),
            ),
          ],
        ),
        locale: const Locale('sw'),
        textScale: 2,
      );

      expect(find.text(sw.mdtTitle), findsOneWidget);
      expect(find.text('30-39 · ${sw.sexFemale}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
