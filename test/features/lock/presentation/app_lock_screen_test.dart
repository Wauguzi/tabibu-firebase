import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide LockState;
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_bloc.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/presentation/app_lock_screen.dart';
import 'package:tabibu/l10n/l10n.dart';

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
      initialState: const LockLoadSuccess(),
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Locale? locale,
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return tester.pumpApp(
      BlocProvider<LockBloc>.value(
        value: lock,
        child: const AppLockScreen(role: .patient),
      ),
      locale: locale,
      themeMode: themeMode,
    );
  }

  testWidgets('both lock switches stay tappable while the lock is off', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.pump();

    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches, hasLength(2));
    expect(switches.every((row) => row.onChanged != null), isTrue);
    expect(find.text('4-digit PIN'), findsOneWidget);
    expect(find.text('Fingerprint or face'), findsOneWidget);
  });

  testWidgets('no enrolled biometrics shows the short notice', (tester) async {
    final states = StreamController<LockState>.broadcast();
    addTearDown(states.close);
    whenListen(lock, states.stream, initialState: const LockLoadSuccess());
    await pumpScreen(tester);
    await tester.pump();

    states.add(const LockBiometricUnavailable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final notice = lookupAppLocalizations(const Locale('en')).appLockNoBioShort;
    expect(find.text(notice), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('settings fit at 2.0x Swahili, light and dark', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final l10n = lookupAppLocalizations(const Locale('sw'));
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [360.0, 840.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await pumpScreen(
          tester,
          locale: const Locale('sw'),
          themeMode: themeMode,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.appLockPin), findsOneWidget);
        expect(find.text(l10n.appLockBio), findsOneWidget);
      }
    }
  });
}
