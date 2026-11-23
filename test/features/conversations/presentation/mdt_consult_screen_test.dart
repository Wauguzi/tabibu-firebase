import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
// TopBar / CircleIconButton come from material_ui via widgets.dart.
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/conversations/data/models/case_summary_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_model.dart';
import 'package:tabibu/features/conversations/data/models/message_model.dart';
import 'package:tabibu/features/conversations/presentation/mdt_consult_screen.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_pinned_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

PractitionerSession _session({String uid = 'me'}) {
  final base = RoleSessions.doctor();
  return PractitionerSession(
    doctor: base.doctor.copyWith(uid: uid),
    roles: base.roles,
  );
}

ConversationModel _consult({
  String myUid = 'me',
  String myStatus = 'Accepted',
  String createdByUid = 'lead',
  CaseSummaryModel summary = const CaseSummaryModel(
    caseRef: 'C-1',
    ageBand: '30-39',
  ),
}) => ConversationModel(
  uid: 'mdt-1',
  specialty: 'Haematology',
  description: 'Second opinion',
  createdByUid: createdByUid,
  linkedResourceUid: 'c1',
  participantUids: [myUid, 'lead', 'other'],
  members: {
    'lead': const ConversationMemberModel(
      uid: 'lead',
      title: 'Dr.',
      firstName: 'Lead',
      lastName: 'Person',
      status: 'Accepted',
    ),
    'other': const ConversationMemberModel(
      uid: 'other',
      title: 'Dr.',
      firstName: 'Other',
      lastName: 'Doc',
      status: 'Accepted',
    ),
    myUid: ConversationMemberModel(
      uid: myUid,
      firstName: 'Me',
      status: myStatus,
    ),
  },
  caseSummary: summary,
);

void main() {
  late FeatureBlocs blocs;
  late MockAuthBloc authBloc;
  late FakeAudioRecorderService recorder;
  late FakeAudioPlayerService player;
  late FakeRecordingCueService cues;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const MdtReset());
  });

  setUp(() {
    blocs = FeatureBlocs();
    authBloc = MockAuthBloc();
    recorder = FakeAudioRecorderService(supported: false);
    player = FakeAudioPlayerService();
    cues = FakeRecordingCueService();
    when(() => authBloc.state).thenReturn(SignInSuccess(session: _session()));
    when(() => blocs.mdt.add(any())).thenReturn(null);
  });

  tearDown(() async {
    await player.dispose();
  });

  Future<void> settleSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpConsult(
    WidgetTester tester, {
    required MdtState state,
    String uid = 'me',
    Locale? locale,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(
      () => authBloc.state,
    ).thenReturn(SignInSuccess(session: _session(uid: uid)));
    when(() => blocs.mdt.state).thenReturn(state);
    final router = GoRouter(
      initialLocation: '/mdt/mdt-1',
      routes: [
        GoRoute(
          path: '/mdt/:id',
          builder: (_, _) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: authBloc),
                ...blocs.providers,
              ],
              child: MdtConsultScreen(
                role: .doctor,
                conversationUid: 'mdt-1',
                recorder: recorder,
                player: player,
                cues: cues,
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpRouterApp(router, locale: locale);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('MdtConsultScreen', () {
    testWidgets('an unsigned case shows Report in progress, never a '
        'draft or AI excerpt', (tester) async {
      final consult = _consult();
      await pumpConsult(
        tester,
        state: MdtLoadSuccess(
          active: consult,
          messages: const [
            MessageModel(
              uid: 'm1',
              conversationUid: 'mdt-1',
              senderUid: 'lead',
              text: 'Please review',
            ),
          ],
        ),
      );

      expect(find.byType(MdtPinnedCard), findsOneWidget);
      expect(find.text(l10n.mdtReportInProgress), findsOneWidget);
      expect(find.textContaining('AI'), findsNothing);
      expect(find.textContaining('draft'), findsNothing);
      expect(find.text('Please review'), findsOneWidget);
    });

    testWidgets('invite-only never shows the thread or pinned case', (
      tester,
    ) async {
      final invite = _consult(myStatus: 'Invited');
      await pumpConsult(
        tester,
        state: MdtLoadSuccess(active: invite, inviteOnly: true),
      );

      expect(find.byType(MdtPinnedCard), findsNothing);
      expect(find.text('Please review'), findsNothing);
      expect(find.text(l10n.mdtReportInProgress), findsNothing);
    });

    testWidgets('Leave names the cost and only leaves on confirm', (
      tester,
    ) async {
      // Not the owner: Leave is offered.
      final consult = _consult();
      await pumpConsult(tester, state: MdtLoadSuccess(active: consult));

      Finder inSheet(String text) => find.descendant(
        of: find.byType(TabibuBottomSheet),
        matching: find.text(text),
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(TopBar),
              matching: find.byType(CircleIconButton),
            )
            .last,
      );
      await settleSheet(tester);

      expect(inSheet(l10n.mdtLeaveAction), findsOneWidget);
      clearInteractions(blocs.mdt);
      await tester.tap(inSheet(l10n.mdtLeaveAction));
      // Members sheet settles, then the confirm sheet opens (lesson 12).
      await tester.pumpAndSettle();

      expect(inSheet(l10n.mdtLeaveTitle), findsOneWidget);
      expect(inSheet(l10n.mdtLeaveBody), findsOneWidget);

      verifyNever(() => blocs.mdt.add(any(that: isA<MdtLeaveRequested>())));

      await tester.tap(inSheet(l10n.mdtLeaveAction));
      await tester.pumpAndSettle();

      verify(
        () => blocs.mdt.add(
          any(
            that: isA<MdtLeaveRequested>().having(
              (e) => e.conversationUid,
              'id',
              'mdt-1',
            ),
          ),
        ),
      ).called(1);
    });

    testWidgets('Remove names who loses access and only removes on '
        'confirm', (tester) async {
      // Owner can remove.
      final consult = _consult(createdByUid: 'me');
      await pumpConsult(tester, state: MdtLoadSuccess(active: consult));

      Finder inSheet(String text) => find.descendant(
        of: find.byType(TabibuBottomSheet),
        matching: find.text(text),
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(TopBar),
              matching: find.byType(CircleIconButton),
            )
            .last,
      );
      await settleSheet(tester);

      clearInteractions(blocs.mdt);
      // Owner first; Remove on Dr. Other is the last row action.
      await tester.tap(inSheet(l10n.mdtRemoveAction).last);
      await tester.pumpAndSettle();

      expect(inSheet(l10n.mdtRemoveTitle('Dr. Other Doc')), findsOneWidget);
      verifyNever(() => blocs.mdt.add(any(that: isA<MdtRemoveRequested>())));

      await tester.tap(inSheet(l10n.mdtRemoveAction));
      await tester.pumpAndSettle();

      verify(
        () => blocs.mdt.add(
          any(
            that: isA<MdtRemoveRequested>().having(
              (e) => e.memberUid,
              'member',
              'other',
            ),
          ),
        ),
      ).called(1);
    });

    testWidgets('the header is the patient line, not the member names', (
      tester,
    ) async {
      await pumpConsult(
        tester,
        state: MdtLoadSuccess(
          active: _consult(
            summary: const CaseSummaryModel(
              caseRef: 'C-1',
              ageBand: '30-39',
              sex: 'Female',
            ),
          ),
        ),
      );

      expect(find.text('C-1'), findsOneWidget);
      expect(find.text('30-39 · ${l10n.sexFemale}'), findsOneWidget);
      expect(find.text(l10n.mdtYou), findsNothing);
      expect(find.textContaining('Dr. Person'), findsNothing);
    });

    testWidgets('a closed consult keeps the closed line in the header', (
      tester,
    ) async {
      await pumpConsult(
        tester,
        state: MdtLoadSuccess(active: _consult().copyWith(status: 'Closed')),
      );

      expect(find.text(l10n.mdtClosedSubtitle), findsWidgets);
      expect(find.text(l10n.mdtYou), findsNothing);
    });

    testWidgets('the header holds at 2.0x in Kiswahili', (tester) async {
      final sw = lookupAppLocalizations(const Locale('sw'));
      await pumpConsult(
        tester,
        locale: const Locale('sw'),
        textScale: 2,
        state: MdtLoadSuccess(
          active: _consult(
            summary: const CaseSummaryModel(
              caseRef: 'C-1',
              ageBand: '30-39',
              sex: 'Female',
            ),
          ),
        ),
      );

      expect(find.text('30-39 · ${sw.sexFemale}'), findsOneWidget);
      expect(find.text(sw.mdtYou), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
