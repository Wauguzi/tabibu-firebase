import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide LockState;
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_bloc.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/presentation/lock_after_screen.dart';
import 'package:tabibu/features/profile/presentation/widgets/settings_group.dart';

import '../../../helpers/feature_blocs.dart';
import '../../../helpers/pump_app.dart';

void main() {
  setUpAll(() => registerFallbackValue(const LockStatusRequested()));

  late MockLockBloc lock;

  setUp(() {
    lock = MockLockBloc();
    when(() => lock.isClosed).thenReturn(false);
    when(() => lock.add(any())).thenReturn(null);
    whenListen(
      lock,
      const Stream<LockState>.empty(),
      initialState: const LockLoadSuccess(enabled: true, lockAfterSeconds: 60),
    );
  });

  GoRouter router() {
    final routes = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Text('stub app lock'),
          routes: [
            GoRoute(
              path: 'after',
              builder: (_, _) => BlocProvider<LockBloc>.value(
                value: lock,
                child: const LockAfterScreen(),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(routes.dispose);
    return routes;
  }

  Future<void> open(WidgetTester tester) async {
    final routes = router();
    await tester.pumpRouterApp(routes);
    await tester.pumpAndSettle();
    unawaited(routes.push('/settings/after'));
    await tester.pumpAndSettle();
  }

  SettingsSwitchRow rowFor(WidgetTester tester, String title) => tester
      .widget<SettingsSwitchRow>(find.widgetWithText(SettingsSwitchRow, title));

  testWidgets('each delay is a switch, and only the chosen one is on', (
    tester,
  ) async {
    await open(tester);

    expect(
      find.byType(SettingsSwitchRow),
      findsNWidgets(LockBloc.lockAfterOptions.length),
    );
    expect(find.byType(SettingsRow), findsNothing, reason: 'no chevrons');
    expect(rowFor(tester, '1 minute').value, isTrue);
    final on = tester
        .widgetList<SettingsSwitchRow>(find.byType(SettingsSwitchRow))
        .where((row) => row.value);
    expect(on, hasLength(1));
  });

  testWidgets('turning another on chooses it and goes back', (tester) async {
    await open(tester);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SettingsSwitchRow, '5 minutes'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    verify(() => lock.add(const LockAfterChanged(seconds: 300))).called(1);
    expect(find.text('stub app lock'), findsOneWidget);
  });

  testWidgets('the chosen switch cannot be turned off', (tester) async {
    await open(tester);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SettingsSwitchRow, '1 minute'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    verifyNever(() => lock.add(any(that: isA<LockAfterChanged>())));
    expect(find.byType(LockAfterScreen), findsOneWidget);
  });
}
