import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_event.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/profile/presentation/profile_screen.dart';
import 'package:tabibu/features/profile/presentation/widgets/profile_identity_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

Widget _identityCards({AppLocalizations? l10n}) {
  return Column(
    children: [
      PatientIdentityCard(
        firstName: 'Amina',
        lastName: 'Wambui',
        phoneNumber: '+254712345678',
        editLabel: l10n?.profileEdit ?? 'Edit profile',
        onEdit: () {},
      ),
      PractitionerIdentityCard(
        name: 'Dr. Wanjiru Kamau',
        subtitle: l10n == null
            ? 'General surgery · Aga Khan University Hospital'
            : l10n.profileRoleAtFacility(
                l10n.profilePathologist,
                'Aga Khan University Hospital',
              ),
        verifiedLabel: l10n?.doctorProfileVerified ?? 'KMPDC verified',
        editLabel: l10n?.profileEdit ?? 'Edit profile',
        onEdit: () {},
      ),
    ],
  );
}

void main() {
  group('ProfileScreen', () {
    setUpAll(() => registerFallbackValue(const SignOutRequested()));

    // Tall enough that the lazy list builds every row.
    void tallView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    // Cupertino sheet routes never settle.
    Future<void> settleSheet(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets("shows a patient's card and settings", (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(RoleSessions.patient, '/patient/profile');
      await tester.pumpAndSettle();

      for (final text in [
        'Your profile',
        'Amina W.',
        '+254 712 *** ***',
        'Preferences',
        'English',
        'Embakasi, Nairobi',
        'Light, dark or device theme',
        'Alerts and security',
        'Notification settings',
        'Health notices for my area',
        'Help and account',
        'Privacy and data',
        'Help and support',
        'Sign out',
        'v1.0.02',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // Hidden while the demo accounts are shared.
      expect(find.text('Delete account'), findsNothing);
    });

    testWidgets('a doctor who approves alerts is told so', (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.doctor(isAlertApprover: true),
        '/doctor/profile',
      );
      await tester.pumpAndSettle();

      expect(find.text('My profile'), findsOneWidget);
      expect(find.text('Dr. Wanjiru Kamau'), findsOneWidget);
      expect(
        find.text('General surgery · Aga Khan University Hospital'),
        findsOneWidget,
      );
      // The tab's card shows the status, never the licence number.
      expect(find.text('KMPDC verified'), findsOneWidget);
      expect(find.text('KMPDC verified · A 12345'), findsNothing);
      expect(
        find.text('You can approve area alerts for Nairobi.'),
        findsOneWidget,
      );
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('only Biometrics stays hidden; its neighbours lead', (
      tester,
    ) async {
      tallView(tester);

      await tester.pumpRoleApp(RoleSessions.patient, '/patient/profile');
      await tester.pumpAndSettle();
      expect(find.text('Biometrics'), findsNothing);
      expect(find.text('Notification settings'), findsOneWidget);

      await tester.pumpRoleApp(RoleSessions.doctor(), '/doctor/profile');
      await tester.pumpAndSettle();
      expect(find.text('Biometrics'), findsNothing);
      expect(find.text('Notification settings'), findsOneWidget);
      expect(find.text('Clinic hours'), findsOneWidget);

      await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
      );
      await tester.pumpAndSettle();
      expect(find.text('Biometrics'), findsNothing);
      expect(find.text('Notification settings'), findsOneWidget);
      expect(find.text('Clinic hours'), findsNothing);
      expect(find.text('Alerts and security'), findsOneWidget);
    });

    testWidgets('a doctor who does not approve alerts sees no notice', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpRoleApp(RoleSessions.doctor(), '/doctor/profile');
      await tester.pumpAndSettle();

      expect(find.byType(NoticeCard), findsNothing);
    });

    testWidgets("shows a pathologist's areas and lab", (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
      );
      await tester.pumpAndSettle();

      expect(find.text('Me'), findsOneWidget);
      expect(
        find.text('Pathologist · Lancet Kenya, Upper Hill'),
        findsOneWidget,
      );
      expect(find.text('Areas you report on'), findsOneWidget);
      expect(find.text('Histopathology'), findsOneWidget);
      expect(find.text('Cytology'), findsOneWidget);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.text('Accept new cases'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Health notices for my area'), findsOneWidget);
    });

    testWidgets('areas read in Kiswahili', (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('sw')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
      );
      await tester.pumpAndSettle();

      expect(find.text('Histopatholojia'), findsOneWidget);
      expect(find.text('Saitolojia'), findsOneWidget);
    });

    testWidgets('Health notices dispatches its flips', (tester) async {
      tallView(tester);
      final bloc = await tester.pumpRoleApp(
        RoleSessions.patient,
        '/patient/profile',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health notices for my area'));
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(
          const ProfileSettingChanged(
            setting: ProfileSetting.healthNotices,
            value: false,
          ),
        ),
      ).called(1);
    });

    testWidgets('Accept cases dispatches its flips', (tester) async {
      tallView(tester);
      final bloc = await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept new cases'));
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(
          const ProfileSettingChanged(
            setting: ProfileSetting.acceptCases,
            value: false,
          ),
        ),
      ).called(1);
    });

    testWidgets('the switches hold still while saving', (tester) async {
      tallView(tester);
      final bloc = await tester.pumpRoleApp(
        RoleSessions.patient,
        '/patient/profile',
        states: [ProfileSettingChangeInProgress(session: RoleSessions.patient)],
      );
      await tester.pumpAndSettle();

      final row = find.descendant(
        of: find
            .ancestor(
              of: find.text('Health notices for my area'),
              matching: find.byType(GestureDetector),
            )
            .first,
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(row).onChanged, isNull);

      await tester.tap(find.text('Health notices for my area'));
      await tester.pumpAndSettle();
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('a failed save says why', (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.patient,
        '/patient/profile',
        states: [
          ProfileSettingChangeFailure(
            session: RoleSessions.patient,
            error: AppError.noInternet,
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No internet access.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Sign out asks first, then signs out', (tester) async {
      tallView(tester);
      final bloc = await tester.pumpRoleApp(
        RoleSessions.patient,
        '/patient/profile',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await settleSheet(tester);
      expect(find.text('Sign out of Tabibu?'), findsOneWidget);
      verifyNever(() => bloc.add(any()));

      await tester.tap(
        find.descendant(
          of: find.byType(TabibuBottomSheet),
          matching: find.text('Sign out'),
        ),
      );
      await settleSheet(tester);

      verify(() => bloc.add(const SignOutRequested())).called(1);
    });

    testWidgets('Cancel keeps the person signed in', (tester) async {
      tallView(tester);
      final bloc = await tester.pumpRoleApp(
        RoleSessions.doctor(),
        '/doctor/profile',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await settleSheet(tester);
      expect(
        find.text(
          'Your cases and reports stay safe. Sign back in any time with '
          'your email or Google.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await settleSheet(tester);

      expect(find.text('Sign out of Tabibu?'), findsNothing);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('a failed sign-out says why', (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.patient,
        '/patient/profile',
        states: [
          SignOutFailure(
            session: RoleSessions.patient,
            error: AppError.noInternet,
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No internet access.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the patient rows open their screens', (tester) async {
      tallView(tester);
      const rows = {
        'Language':
            'Choose the language for the app, your results and health notices.',
        'My area':
            'We use your area to show doctors nearby and health notices. '
            'We never track your location.',
        'Theme': 'Same as my phone',
        'Notification settings': 'All notifications',
      };
      for (final entry in rows.entries) {
        await tester.pumpRoleApp(RoleSessions.patient, '/patient/profile');
        await tester.pumpAndSettle();

        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('privacy and help rows open their screens', (tester) async {
      tallView(tester);
      final sessions = {
        '/patient/profile': RoleSessions.patient,
        '/doctor/profile': RoleSessions.doctor(),
        '/pathologist/profile': RoleSessions.pathologist,
      };
      final privacyMarkers = {
        '/patient/profile':
            'You decide who sees your health information. '
            'Tabibu never sells it or tracks where you are.',
        '/doctor/profile': 'Lock Tabibu with a PIN or Face ID',
        '/pathologist/profile':
            'Only your cases open for you. Patient data never leaves '
            'Tabibu without consent or a legal duty.',
      };
      final helpMarkers = {
        '/patient/profile': 'Talk to us',
        '/doctor/profile': 'Clinician support',
        '/pathologist/profile': 'Clinician support',
      };
      for (final entry in sessions.entries) {
        await tester.pumpRoleApp(entry.value, entry.key);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Privacy and data'));
        await tester.pumpAndSettle();
        expect(
          find.text(privacyMarkers[entry.key]!),
          findsOneWidget,
          reason: entry.key,
        );

        await tester.pumpRoleApp(entry.value, entry.key);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Help and support'));
        await tester.pumpAndSettle();
        expect(
          find.text(helpMarkers[entry.key]!),
          findsOneWidget,
          reason: entry.key,
        );
      }
    });

    testWidgets('the patient pencil opens edit profile in one push', (
      tester,
    ) async {
      tallView(tester);
      PackageInfo.setMockInitialValues(
        appName: 'Tabibu',
        packageName: 'com.tabibukenya.tabibu',
        version: '1.0.02',
        buildNumber: '1002',
        buildSignature: '',
      );
      final auth = MockAuthBloc();
      when(
        () => auth.state,
      ).thenReturn(SignInSuccess(session: RoleSessions.patient));
      final blocs = FeatureBlocs();
      final router = GoRouter(
        initialLocation: '/patient/profile',
        routes: [
          GoRoute(
            path: '/patient/profile',
            builder: (_, _) => MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: auth),
                ...blocs.providers,
              ],
              child: const ProfileScreen(role: .patient),
            ),
          ),
          GoRoute(
            path: '/patient/profile/edit',
            builder: (_, _) => const Text('stub edit profile'),
          ),
          GoRoute(
            path: '/patient/profile/details',
            builder: (_, _) => const Text('stub my profile'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRouterApp(router);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CircleIconButton));
      await tester.pumpAndSettle();

      expect(find.text('stub edit profile'), findsOneWidget);
      expect(find.text('stub my profile'), findsNothing);
    });

    testWidgets('back from a settings screen returns to the tab', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpRoleApp(RoleSessions.patient, '/patient/profile');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(find.text('Kiswahili'), findsOneWidget);

      await tester.tap(find.byType(CircleIconButton));
      await tester.pumpAndSettle();
      expect(find.text('Your profile'), findsOneWidget);
    });

    testWidgets('the doctor rows open hours and details', (tester) async {
      tallView(tester);
      await tester.pumpRoleApp(RoleSessions.doctor(), '/doctor/profile');
      await tester.pumpAndSettle();

      expect(find.text('Mon–Fri · 8:00 AM–5:00 PM'), findsOneWidget);

      await tester.tap(find.text('Clinic hours'));
      await tester.pumpAndSettle();
      expect(find.text('Accepting new patients'), findsOneWidget);

      await tester.pumpRoleApp(RoleSessions.doctor(), '/doctor/profile');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CircleIconButton));
      await tester.pumpAndSettle();
      expect(find.text('Only for Tabibu'), findsOneWidget);
    });

    testWidgets('the pathologist pencil opens the profile details', (
      tester,
    ) async {
      tallView(tester);
      await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CircleIconButton));
      await tester.pumpAndSettle();

      expect(find.text('Shown to doctors'), findsOneWidget);
    });

    testWidgets('identity cards draw on the pattern in light and dark', (
      tester,
    ) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpApp(_identityCards(), themeMode: mode);
        await tester.pump();

        expect(find.byType(PatternCard), findsNWidgets(2));
        expect(
          tester.widget<Text>(find.text('Amina W.')).style?.color,
          AppColors.white,
        );
        expect(
          tester.widget<Text>(find.text('+254 712 *** ***')).style?.color,
          AppColors.white.withValues(alpha: 0.8),
        );
        expect(
          tester.widget<Text>(find.text('Dr. Wanjiru Kamau')).style?.color,
          AppColors.white,
        );
        expect(
          tester
              .widget<Text>(
                find.text('General surgery · Aga Khan University Hospital'),
              )
              .style
              ?.color,
          AppColors.white.withValues(alpha: 0.8),
        );

        final scheme = Theme.of(
          tester.element(find.byType(PatientIdentityCard)),
        ).colorScheme;
        final buttons = find.byType(CircleIconButton);
        expect(tester.widget<CircleIconButton>(buttons.at(0)).onCard, isTrue);
        expect(tester.widget<CircleIconButton>(buttons.at(1)).onCard, isFalse);
        expect(
          tester
              .widget<Material>(
                find.descendant(
                  of: buttons.at(0),
                  matching: find.byType(Material),
                ),
              )
              .color,
          scheme.surfaceContainerLow,
        );
        expect(
          tester
              .widget<Material>(
                find.descendant(
                  of: buttons.at(1),
                  matching: find.byType(Material),
                ),
              )
              .color,
          scheme.surfaceContainerLowest,
        );
        for (final index in [0, 1]) {
          expect(
            tester
                .widget<AssetIcon>(
                  find.descendant(
                    of: buttons.at(index),
                    matching: find.byType(AssetIcon),
                  ),
                )
                .color,
            scheme.onSurface,
          );
        }
      }
    });

    testWidgets('identity cards fit at 2.0x Swahili on narrow and large', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final l10n = lookupAppLocalizations(const Locale('sw'));
      for (final width in [360.0, 840.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpApp(
          _identityCards(l10n: l10n),
          locale: const Locale('sw'),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('renders in Swahili in dark mode at 2.0x text', (tester) async {
      tallView(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.localesTestValue = [const Locale('sw')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpRoleApp(
        RoleSessions.pathologist,
        '/pathologist/profile',
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();

      expect(find.text('Mimi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PatientIdentityCard.maskPhone', () {
    test('hides the last six digits of a Kenyan number', () {
      expect(
        PatientIdentityCard.maskPhone('+254712345678'),
        '+254 712 *** ***',
      );
    });

    test('leaves any other value as it is', () {
      expect(PatientIdentityCard.maskPhone(''), '');
      expect(PatientIdentityCard.maskPhone('0712345678'), '0712345678');
    });
  });

  group('PatientIdentityCard.shortName', () {
    test('keeps the first name with the last initial', () {
      expect(PatientIdentityCard.shortName('Amina', 'Wambui'), 'Amina W.');
    });

    test('without a last name shows the first alone', () {
      expect(PatientIdentityCard.shortName('Amina', ''), 'Amina');
    });
  });
}
