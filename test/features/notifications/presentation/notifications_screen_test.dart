import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_bloc.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_event.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_state.dart';
import 'package:tabibu/features/appointments/data/models/appointment_model.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_bloc.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_bloc.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_event.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_state.dart';
import 'package:tabibu/features/notifications/data/models/notification_metadata_model.dart';
import 'package:tabibu/features/notifications/data/models/notification_model.dart';
import 'package:tabibu/features/notifications/presentation/notifications_screen.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

const _nairobiOffset = Duration(hours: 3);

/// Noon in Nairobi on the given day, as an instant. Midday keeps the row
/// inside its bucket wherever the device zone is.
DateTime _nairobiNoon(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day, 12).subtract(_nairobiOffset);

NotificationModel _row({
  required String uid,
  required DateTime at,
  String templateKey = '',
  String category = 'Appointment',
  String status = 'Unread',
  String title = '',
  String message = '',
  String deepLink = '',
}) => NotificationModel(
  uid: uid,
  creationDate: at.toIso8601String(),
  templateKey: templateKey,
  category: category,
  status: status,
  title: title,
  message: message,
  metadata: NotificationMetadataModel(deepLink: deepLink),
);

PatientSession _patientSession() => PatientSession(
  patient: RoleSessions.patient.patient.copyWith(uid: 'patient-1'),
  roles: RoleSessions.patient.roles,
);

void main() {
  group('NotificationsScreen', () {
    setUpAll(() => registerFallbackValue(const AppointmentsReset()));

    late FeatureBlocs blocs;
    late MockAuthBloc authBloc;

    setUp(() {
      blocs = FeatureBlocs();
      authBloc = MockAuthBloc();
      when(
        () => authBloc.state,
      ).thenReturn(SignInSuccess(session: _patientSession()));
      whenListen(
        blocs.mdt,
        const Stream<MdtState>.empty(),
        initialState: const MdtInitial(),
      );
    });

    Widget screen(Role role) => MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: authBloc),
        BlocProvider<NotificationsBloc>.value(value: blocs.notifications),
        BlocProvider<MdtBloc>.value(value: blocs.mdt),
        BlocProvider<AppointmentsBloc>.value(value: blocs.appointments),
      ],
      child: NotificationsScreen(role: role),
    );

    /// One row per group: a known template with its own title, an unknown
    /// template keeping the server copy, and a known template falling back
    /// to the server title.
    List<NotificationModel> groupedRows() {
      final now = DateTime.now().toUtc().add(_nairobiOffset);
      final today = _nairobiNoon(now);
      return [
        _row(
          uid: 'n-today',
          at: today,
          templateKey: NotificationTemplate.appointmentAccepted.value,
          deepLink: '/appointments/a1',
        ),
        _row(
          uid: 'n-yesterday',
          at: today.subtract(const Duration(days: 1)),
          category: 'Report',
          status: 'Read',
          title: 'Server title',
          message: 'Server message',
          deepLink: '/conversations/x1',
        ),
        _row(
          uid: 'n-earlier',
          at: today.subtract(const Duration(days: 10)),
          templateKey: NotificationTemplate.reportSigned.value,
          category: 'Result',
          title: 'Signed report ready',
          deepLink: '/cases/c1/reports/r1',
        ),
      ];
    }

    Future<void> pumpLoaded(WidgetTester tester, Role role) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: groupedRows()));
      await tester.pumpApp(screen(role));
      await tester.pumpAndSettle();
    }

    testWidgets('requests the inbox on open', (tester) async {
      await tester.pumpApp(screen(.patient));
      // No settle: the loading spinner never stops.
      await tester.pump();

      verify(
        () => blocs.notifications.add(
          const NotificationsRequested(uid: 'patient-1'),
        ),
      ).called(1);
    });

    testWidgets('shows a spinner while loading with no rows', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(const NotificationsLoadInProgress());
      await tester.pumpApp(screen(.patient));
      // No settle: the loading spinner never stops.
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(MoreButton), findsOneWidget);
    });

    testWidgets('groups rows under Today, Yesterday and Earlier', (
      tester,
    ) async {
      await pumpLoaded(tester, .patient);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      // Known template: the inbox re-renders in the current language.
      expect(find.text('Appointment confirmed'), findsOneWidget);
      expect(
        find.text('Your appointment request was accepted.'),
        findsOneWidget,
      );
      // Unknown template: the server copy.
      expect(find.text('Server title'), findsOneWidget);
      expect(find.text('Server message'), findsOneWidget);
      // Known template without a title: the server title, template body.
      expect(find.text('Signed report ready'), findsOneWidget);
      expect(find.text('A signed report is ready.'), findsOneWidget);
    });

    testWidgets('renders the groups in dark mode', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: groupedRows()));
      await tester.pumpApp(screen(.doctor), themeMode: ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
    });

    testWidgets('each role gets its own empty sentence', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(const NotificationsLoadSuccess());

      await tester.pumpApp(screen(.patient));
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up"), findsOneWidget);
      expect(
        find.text('Appointments, results and health notices will show here.'),
        findsOneWidget,
      );

      await tester.pumpApp(screen(.doctor));
      await tester.pumpAndSettle();
      expect(
        find.text('Bookings, signed reports and area alerts will show here.'),
        findsOneWidget,
      );

      await tester.pumpApp(screen(.pathologist));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'New cases, questions from doctors and MDT invites will show here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides the menu when empty and loaded', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(const NotificationsLoadSuccess());
      await tester.pumpApp(screen(.doctor));
      await tester.pumpAndSettle();

      expect(find.byType(MoreButton), findsNothing);
    });

    testWidgets('shows the offline banner above the list', (tester) async {
      when(() => blocs.notifications.state).thenReturn(
        NotificationsLoadSuccess(items: groupedRows(), offline: true),
      );
      await tester.pumpApp(screen(.patient));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text("Showing what's saved on this phone."), findsOneWidget);
      expect(find.text('Appointment confirmed'), findsOneWidget);
    });

    testWidgets('shows the failure as a toast', (tester) async {
      whenListen(
        blocs.notifications,
        Stream.fromIterable([
          const NotificationsLoadFailure(error: AppError.noInternet),
        ]),
        initialState: const NotificationsInitial(),
      );
      await tester.pumpApp(screen(.patient));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationsScreen)),
      );
      expect(find.text(AppError.noInternet.description(l10n)), findsOneWidget);
      // Let the toast's auto-dismiss fire; a settle alone never advances to it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a row marks itself read and opens its target', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: groupedRows()));
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(path: '/notifications', builder: (_, _) => screen(.patient)),
          GoRoute(
            path: '/patient/appointment/:appointmentUid',
            builder: (_, _) => const Text('stub appointment'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpRouterApp(router);
      await tester.pumpAndSettle();

      final row = find.text('Appointment confirmed');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      verify(
        () => blocs.notifications.add(
          const NotificationReadRequested(
            uid: 'patient-1',
            notificationUid: 'n-today',
          ),
        ),
      ).called(1);
      expect(find.text('stub appointment'), findsOneWidget);
    });

    testWidgets(
      'T-18: a share row opens the enter-code screen by share id, never with '
      'the code in the route',
      (tester) async {
        final doctor = RoleSessions.doctor();
        when(() => authBloc.state).thenReturn(
          SignInSuccess(
            session: PractitionerSession(
              doctor: doctor.doctor.copyWith(uid: 'doc-1'),
              roles: doctor.roles,
            ),
          ),
        );
        when(() => blocs.notifications.state).thenReturn(
          NotificationsLoadSuccess(
            items: [
              NotificationModel(
                uid: 'caseShared:s1:doc-1',
                creationDate: DateTime.now().toUtc().toIso8601String(),
                category: 'PatientCase',
                title: 'A case was shared',
                metadata: const NotificationMetadataModel(
                  deepLink: '/cases/c1',
                  shareCode: '4821',
                ),
              ),
            ],
          ),
        );
        final router = GoRouter(
          initialLocation: '/notifications',
          routes: [
            GoRoute(path: '/notifications', builder: (_, _) => screen(.doctor)),
            GoRoute(
              path: '/doctor/share/:shareUid',
              builder: (_, state) => Text('stub share ${state.uri}'),
            ),
            GoRoute(
              path: '/doctor/case/:caseUid',
              builder: (_, _) => const Text('stub case'),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpRouterApp(router);
        await tester.pumpAndSettle();

        await tester.tap(find.text('A case was shared'));
        await tester.pumpAndSettle();

        verify(
          () => blocs.notifications.add(
            const NotificationReadRequested(
              uid: 'doc-1',
              notificationUid: 'caseShared:s1:doc-1',
            ),
          ),
        ).called(1);
        expect(find.text('stub share /doctor/share/s1'), findsOneWidget);
        expect(find.text('stub case'), findsNothing);
        expect(find.textContaining('4821'), findsNothing);
      },
    );

    testWidgets('a row that carries an access code shows it to its reader, and '
        'a row without one shows nothing', (tester) async {
      final en = lookupAppLocalizations(const Locale('en'));
      final doctor = RoleSessions.doctor();
      when(() => authBloc.state).thenReturn(
        SignInSuccess(
          session: PractitionerSession(
            doctor: doctor.doctor.copyWith(uid: 'doc-1'),
            roles: doctor.roles,
          ),
        ),
      );
      final now = DateTime.now().toUtc().toIso8601String();
      when(() => blocs.notifications.state).thenReturn(
        NotificationsLoadSuccess(
          items: [
            NotificationModel(
              uid: 'reportSigned:c1_v1:doc-1',
              creationDate: now,
              category: 'Report',
              title: 'Signed report ready',
              metadata: const NotificationMetadataModel(
                deepLink: '/cases/c1/reports/v1',
                shareCode: '4821',
              ),
            ),
            NotificationModel(
              uid: 'resultsWithDoctor:c1:doc-1',
              creationDate: now,
              title: 'Plain row',
            ),
          ],
        ),
      );
      tester.view.physicalSize = const Size(1170, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpApp(screen(.doctor));
      await tester.pumpAndSettle();

      expect(find.text(en.notificationAccessCode('4821')), findsOneWidget);
      // Only the row that carries a code shows one.
      expect(find.textContaining('Code '), findsOneWidget);
    });

    testWidgets('the code row fits at 1.0x and 2.0x, both languages, both '
        'modes', (tester) async {
      final doctor = RoleSessions.doctor();
      when(() => authBloc.state).thenReturn(
        SignInSuccess(
          session: PractitionerSession(
            doctor: doctor.doctor.copyWith(uid: 'doc-1'),
            roles: doctor.roles,
          ),
        ),
      );
      final now = DateTime.now().toUtc().toIso8601String();
      when(() => blocs.notifications.state).thenReturn(
        NotificationsLoadSuccess(
          items: [
            NotificationModel(
              uid: 'reportSigned:c1_v1:doc-1',
              creationDate: now,
              category: 'Report',
              title: 'Signed report ready',
              metadata: const NotificationMetadataModel(
                deepLink: '/cases/c1/reports/v1',
                shareCode: '4821',
              ),
            ),
          ],
        ),
      );

      for (final scale in [1.0, 2.0]) {
        for (final locale in [const Locale('en'), const Locale('sw')]) {
          for (final mode in [ThemeMode.light, ThemeMode.dark]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            tester.view.physicalSize = const Size(1170, 4000);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);
            final l10n = lookupAppLocalizations(locale);
            await tester.pumpApp(
              screen(.doctor),
              locale: locale,
              themeMode: mode,
            );
            await tester.pumpAndSettle();

            expect(
              find.text(l10n.notificationAccessCode('4821')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    });

    testWidgets('a Tier 2 link only marks the row read', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: groupedRows()));
      await tester.pumpApp(screen(.patient));
      await tester.pumpAndSettle();

      final row = find.text('Server title');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      verify(
        () => blocs.notifications.add(
          const NotificationReadRequested(
            uid: 'patient-1',
            notificationUid: 'n-yesterday',
          ),
        ),
      ).called(1);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('the menu marks all as read', (tester) async {
      await pumpLoaded(tester, .patient);

      await tester.tap(find.byType(MoreButton));
      await tester.pumpAndSettle();
      expect(find.text('Mark all as read'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      verify(
        () => blocs.notifications.add(
          const NotificationsAllReadRequested(uid: 'patient-1'),
        ),
      ).called(1);
    });

    testWidgets('the menu refreshes', (tester) async {
      await pumpLoaded(tester, .patient);

      await tester.tap(find.byType(MoreButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      verify(
        () => blocs.notifications.add(
          const NotificationsRefreshed(uid: 'patient-1'),
        ),
      ).called(1);
    });

    testWidgets('groups by the Nairobi day across midnight', (tester) async {
      final nairobiNow = DateTime.now().toUtc().add(_nairobiOffset);
      final midnight = DateTime.utc(
        nairobiNow.year,
        nairobiNow.month,
        nairobiNow.day,
      ).subtract(_nairobiOffset);
      // 00:30 in Nairobi is still yesterday in UTC: UTC grouping would put
      // this row under Yesterday.
      final afterMidnight = midnight.add(const Duration(minutes: 30));
      final beforeMidnight = midnight.subtract(const Duration(minutes: 30));
      when(() => blocs.notifications.state).thenReturn(
        NotificationsLoadSuccess(
          items: [
            _row(uid: 'n-after', at: afterMidnight, title: 'After midnight'),
            _row(uid: 'n-before', at: beforeMidnight, title: 'Before midnight'),
          ],
        ),
      );
      await tester.pumpApp(screen(.patient));
      await tester.pumpAndSettle();

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(top('Today') < top('After midnight'), isTrue);
      expect(top('After midnight') < top('Yesterday'), isTrue);
      expect(top('Yesterday') < top('Before midnight'), isTrue);
      // Today shows the time, yesterday the weekday, in Nairobi time.
      expect(
        find.text(
          DateFormat('h:mm a', 'en').format(afterMidnight.add(_nairobiOffset)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          DateFormat('EEE', 'en').format(beforeMidnight.add(_nairobiOffset)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders in Swahili', (tester) async {
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: groupedRows()));
      await tester.pumpApp(screen(.patient), locale: const Locale('sw'));
      await tester.pumpAndSettle();

      // New Kiswahili words would fail the spell gate (this test does not
      // extend the dictionary), so these come from l10n itself.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationsScreen)),
      );
      expect(find.text(l10n.notificationsTitle), findsOneWidget);
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Jana'), findsOneWidget);
      expect(find.text(l10n.notificationsEarlier), findsOneWidget);
      expect(find.text('Miadi imethibitishwa'), findsOneWidget);
      expect(
        find.text(l10n.notificationAppointmentAcceptedBody),
        findsOneWidget,
      );
    });

    testWidgets('lays out at 1.3x text without overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpLoaded(tester, .pathologist);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Appointment confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    void asDoctor() {
      final doctor = RoleSessions.doctor();
      when(() => authBloc.state).thenReturn(
        SignInSuccess(
          session: PractitionerSession(
            doctor: doctor.doctor.copyWith(uid: 'doc-1'),
            roles: doctor.roles,
          ),
        ),
      );
    }

    NotificationModel invite({
      String uid = 'invite-1',
      String actionStatus = 'Pending',
      String recipientUid = 'doc-1',
      String? expiresAt,
      String resourceUid = 'conv-1',
    }) {
      final at = DateTime.now().toUtc();
      return NotificationModel(
        uid: uid,
        creationDate: at.toIso8601String(),
        recipientUid: recipientUid,
        templateKey: NotificationTemplate.mdtInvited.value,
        category: 'Mdt',
        title: 'Consult invitation',
        resourceUid: resourceUid,
        metadata: NotificationMetadataModel(
          actionType: 'Approval',
          actionStatus: actionStatus,
          expiresAt:
              expiresAt ?? at.add(const Duration(days: 2)).toIso8601String(),
        ),
      );
    }

    Future<StreamController<MdtState>> pumpInvite(
      WidgetTester tester, {
      required List<NotificationModel> items,
      Role role = .doctor,
      bool router = false,
    }) async {
      final states = StreamController<MdtState>.broadcast();
      addTearDown(states.close);
      whenListen(blocs.mdt, states.stream, initialState: const MdtInitial());
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: items));
      if (router) {
        final go = GoRouter(
          initialLocation: '/notifications',
          routes: [
            GoRoute(path: '/notifications', builder: (_, _) => screen(role)),
            GoRoute(
              path: '/doctor/mdt/:conversationUid',
              builder: (_, state) =>
                  Text('consult ${state.pathParameters['conversationUid']}'),
            ),
          ],
        );
        addTearDown(go.dispose);
        await tester.pumpRouterApp(go);
      } else {
        await tester.pumpApp(screen(role));
      }
      await tester.pump();
      return states;
    }

    testWidgets('a pending invite shows Accept and Decline', (tester) async {
      asDoctor();
      await pumpInvite(tester, items: [invite()]);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('Accept loads only that button, ignores a second tap, '
        'then refreshes and opens', (tester) async {
      asDoctor();
      final states = await pumpInvite(tester, items: [invite()], router: true);
      await tester.tap(find.byKey(const ValueKey('mdt-accept-invite-1')));
      await tester.pump();

      final buttons = tester
          .widgetList<TabibuButton>(find.byType(TabibuButton))
          .toList();
      expect(buttons.singleWhere((b) => b.label == 'Accept').isLoading, isTrue);
      expect(
        buttons.singleWhere((b) => b.label == 'Decline').isLoading,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('mdt-accept-invite-1')));
      await tester.tap(find.byKey(const ValueKey('mdt-decline-invite-1')));
      await tester.pump();
      verify(
        () => blocs.mdt.add(
          const MdtRespondRequested(
            uid: 'doc-1',
            conversationUid: 'conv-1',
            accept: true,
          ),
        ),
      ).called(1);
      verifyNever(
        () => blocs.mdt.add(
          const MdtRespondRequested(
            uid: 'doc-1',
            conversationUid: 'conv-1',
            accept: false,
          ),
        ),
      );

      states.add(const MdtWriteSuccess());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      verify(
        () => blocs.mdt.add(const MdtRefreshed(uid: 'doc-1', role: .doctor)),
      ).called(1);
      expect(find.text('consult conv-1'), findsOneWidget);
    });

    testWidgets('Decline loads only that button and the row reads declined', (
      tester,
    ) async {
      asDoctor();
      final states = await pumpInvite(tester, items: [invite()]);
      await tester.tap(find.byKey(const ValueKey('mdt-decline-invite-1')));
      await tester.pump();

      final buttons = tester
          .widgetList<TabibuButton>(find.byType(TabibuButton))
          .toList();
      expect(
        buttons.singleWhere((b) => b.label == 'Decline').isLoading,
        isTrue,
      );
      expect(
        buttons.singleWhere((b) => b.label == 'Accept').isLoading,
        isFalse,
      );
      verify(
        () => blocs.mdt.add(
          const MdtRespondRequested(
            uid: 'doc-1',
            conversationUid: 'conv-1',
            accept: false,
          ),
        ),
      ).called(1);

      states.add(const MdtWriteSuccess());
      await tester.pump();
      expect(find.text('Declined'), findsOneWidget);
      expect(find.byType(TabibuButton), findsNothing);
    });

    testWidgets('a refusal clears the loading and leaves the plain row', (
      tester,
    ) async {
      asDoctor();
      final states = await pumpInvite(tester, items: [invite()]);
      await tester.tap(find.byKey(const ValueKey('mdt-accept-invite-1')));
      await tester.pump();
      states.add(const MdtWriteFailure(error: AppError.permissionDenied));
      await tester.pump();
      expect(find.byType(TabibuButton), findsNothing);
      expect(find.text('Consult invitation'), findsOneWidget);
    });

    testWidgets('an answered, expired or replaced invite has no buttons', (
      tester,
    ) async {
      asDoctor();
      final past = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await pumpInvite(
        tester,
        items: [
          invite(uid: 'expired', expiresAt: past),
          invite(uid: 'answered', actionStatus: 'Accepted'),
          invite(uid: 'declined', actionStatus: 'Declined'),
          invite(uid: 'replaced', actionStatus: 'Cancelled'),
          invite(uid: 'other', recipientUid: 'someone-else'),
        ],
      );
      expect(find.byType(TabibuButton), findsNothing);

      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: [invite()]));
      await tester.pumpApp(screen(.patient));
      await tester.pump();
      expect(find.byType(TabibuButton), findsNothing);
    });

    testWidgets('Accept and Decline fit at 2.0x text in Swahili at 360 dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      asDoctor();
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: [invite()]));
      await tester.pumpApp(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: screen(.doctor),
        ),
        locale: const Locale('sw'),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationsScreen)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.mdtAccept), findsOneWidget);
      expect(find.text(l10n.mdtDecline), findsOneWidget);
    });

    NotificationModel booking({String uid = 'booking-1'}) {
      final at = DateTime.now().toUtc();
      return NotificationModel(
        uid: uid,
        creationDate: at.toIso8601String(),
        recipientUid: 'doc-1',
        templateKey: NotificationTemplate.appointmentRequested.value,
        category: 'Appointment',
        title: 'New appointment request',
        resourceUid: 'appt-1',
        metadata: NotificationMetadataModel(
          actionType: 'Approval',
          actionStatus: 'Pending',
          expiresAt: at.add(const Duration(days: 1)).toIso8601String(),
        ),
      );
    }

    Future<StreamController<AppointmentsState>> pumpBooking(
      WidgetTester tester, {
      Role role = .doctor,
    }) async {
      final states = StreamController<AppointmentsState>.broadcast();
      addTearDown(states.close);
      whenListen(
        blocs.appointments,
        states.stream,
        initialState: const AppointmentsLoadSuccess(
          appointments: [
            AppointmentModel(uid: 'appt-1', patientName: 'Amina Otieno'),
          ],
        ),
      );
      when(
        () => blocs.notifications.state,
      ).thenReturn(NotificationsLoadSuccess(items: [booking()]));
      await tester.pumpApp(screen(role));
      await tester.pump();
      return states;
    }

    testWidgets('a pending booking request shows Accept and Decline', (
      tester,
    ) async {
      asDoctor();
      await pumpBooking(tester);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('Accept on a booking request loads only that button, sends '
        'the decision once, then settles and refreshes', (tester) async {
      asDoctor();
      final states = await pumpBooking(tester);
      await tester.tap(find.byKey(const ValueKey('mdt-accept-booking-1')));
      await tester.pump();

      final buttons = tester
          .widgetList<TabibuButton>(find.byType(TabibuButton))
          .toList();
      expect(buttons.singleWhere((b) => b.label == 'Accept').isLoading, isTrue);
      expect(
        buttons.singleWhere((b) => b.label == 'Decline').isLoading,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('mdt-accept-booking-1')));
      await tester.pump();
      verify(
        () => blocs.appointments.add(
          const AppointmentDecisionRequested(
            appointmentUid: 'appt-1',
            accept: true,
          ),
        ),
      ).called(1);

      states.add(
        const AppointmentDecisionSuccess(
          appointment: AppointmentModel(uid: 'appt-1', status: 'Accepted'),
        ),
      );
      await tester.pump();
      expect(find.text('Accept'), findsNothing);
      verify(
        () => blocs.appointments.add(
          const AppointmentsRefreshed(uid: 'doc-1', role: .doctor),
        ),
      ).called(1);
    });

    testWidgets('Decline on a booking request asks for a reason first', (
      tester,
    ) async {
      asDoctor();
      await pumpBooking(tester);
      await tester.tap(find.byKey(const ValueKey('mdt-decline-booking-1')));
      // A zero-duration pump does not return while a sheet route is up.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(l10n.bookingRequestsDeclineTitle('Amina Otieno')),
        findsOneWidget,
      );
      verifyNever(
        () => blocs.appointments.add(
          any(that: isA<AppointmentDecisionRequested>()),
        ),
      );
    });
  });
}
