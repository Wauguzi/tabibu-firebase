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
import 'package:tabibu/features/lock/presentation/app_lock_screen.dart';
import 'package:tabibu/features/lock/presentation/create_pin_screen.dart';

import '../../../helpers/feature_blocs.dart';
import '../../../helpers/pump_app.dart';

void main() {
  setUpAll(() => registerFallbackValue(const LockStatusRequested()));

  late MockLockBloc lock;
  late StreamController<LockState> states;

  setUp(() {
    lock = MockLockBloc();
    states = StreamController<LockState>.broadcast();
    when(() => lock.isClosed).thenReturn(false);
    when(() => lock.add(any())).thenReturn(null);
    whenListen(lock, states.stream, initialState: const LockLoadSuccess());
  });

  tearDown(() => states.close());

  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget provided(Widget screen) =>
      BlocProvider<LockBloc>.value(value: lock, child: screen);

  testWidgets('a saved PIN closes the screen onto App lock, with the notice', (
    tester,
  ) async {
    phoneView(tester);
    // App lock listens underneath, as in the app: its notice must not be the
    // route Create PIN's pop closes.
    final routes = GoRouter(
      initialLocation: '/lock',
      routes: [
        GoRoute(
          path: '/lock',
          builder: (_, _) => provided(const AppLockScreen(role: .patient)),
          routes: [
            GoRoute(
              path: 'create',
              builder: (_, _) =>
                  provided(const CreatePinScreen(role: .patient)),
            ),
          ],
        ),
      ],
    );
    addTearDown(routes.dispose);
    await tester.pumpRouterApp(routes);
    await tester.pumpAndSettle();
    unawaited(routes.push('/lock/create'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePinScreen), findsOneWidget);

    states.add(const LockPinCreateSuccess());
    await tester.pumpAndSettle();

    expect(find.byType(CreatePinScreen), findsNothing);
    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(
      find.text('PIN set. Tabibu will ask for it on this phone.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('leaving the screen ends its permission to replace a lock', (
    tester,
  ) async {
    phoneView(tester);
    final routes = GoRouter(
      initialLocation: '/create',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('stub')),
        GoRoute(
          path: '/create',
          builder: (_, _) => provided(const CreatePinScreen(role: .patient)),
        ),
      ],
    );
    addTearDown(routes.dispose);
    await tester.pumpRouterApp(routes);
    await tester.pumpAndSettle();

    routes.go('/');
    await tester.pumpAndSettle();

    verify(() => lock.add(const LockPinCreateLeft())).called(1);
  });
}
