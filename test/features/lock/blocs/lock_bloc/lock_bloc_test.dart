import 'dart:async';
import 'dart:math';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_bloc.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/data/biometric_authenticator.dart';
import 'package:tabibu/features/lock/data/lock_storage.dart';

import '../../fake_biometric_authenticator.dart';

class _MockStorage extends Mock implements LockStorage {}

class _MockSecure extends Mock implements FlutterSecureStorage {}

class _MockBio extends Mock implements BiometricAuthenticator {}

class _MockAnalytics extends Mock implements AnalyticsService {}

void main() {
  setUpAll(() => registerFallbackValue(LockMethod.none));

  late _MockStorage storage;
  late _MockBio bio;
  late _MockAnalytics analytics;
  late DateTime clock;

  LockBloc build() => LockBloc(
    storage: storage,
    biometrics: bio,
    analytics: analytics,
    now: () => clock,
  );

  const secret = '4829';

  setUp(() {
    storage = _MockStorage();
    bio = _MockBio();
    analytics = _MockAnalytics();
    clock = DateTime.utc(2026, 11, 3, 12);
    when(() => analytics.logLockEnabled()).thenAnswer((_) async {});
    when(() => analytics.logLockDisabled()).thenAnswer((_) async {});
    when(
      () => analytics.logLockBiometricsChanged(enabled: any(named: 'enabled')),
    ).thenAnswer((_) async {});
    when(
      () => analytics.logLockTimeoutChanged(seconds: any(named: 'seconds')),
    ).thenAnswer((_) async {});
    when(() => storage.method()).thenAnswer((_) async => LockMethod.none);
    when(() => storage.setMethod(any())).thenAnswer((_) async {});
    when(() => storage.lockAfterSeconds()).thenAnswer((_) async => 0);
    when(() => storage.failedAttempts()).thenAnswer((_) async => 0);
    when(() => storage.lockoutUntil()).thenAnswer((_) async => null);
    when(() => storage.verifyPin(any())).thenAnswer((_) async => false);
    when(() => storage.setPin(any())).thenAnswer((_) async {});
    when(() => storage.setLockAfter(any())).thenAnswer((_) async {});
    when(() => storage.clearAll()).thenAnswer((_) async {});
    when(() => storage.resetFailures()).thenAnswer((_) async {});
    when(
      () => storage.recordFailure(lockoutUntil: any(named: 'lockoutUntil')),
    ).thenAnswer((_) async => 1);
    when(() => bio.isAvailable()).thenAnswer((_) async => true);
    when(
      () => bio.authenticate(
        reason: any(named: 'reason'),
        biometricOnly: any(named: 'biometricOnly'),
      ),
    ).thenAnswer((_) async => true);
  });

  group('LockBloc', () {
    test('starts unlocked and empty', () {
      expect(build().state, const LockInitial());
      expect(build().state.locked, isFalse);
    });

    group('cold start and background timeout', () {
      blocTest<LockBloc, LockState>(
        'cold start covers the app while reading, then locks when a PIN is set',
        build: build,
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
        },
        act: (bloc) => bloc.add(const LockColdStart()),
        expect: () => [
          isA<LockLoadInProgress>().having((s) => s.locked, 'locked', isTrue),
          isA<LockLoadSuccess>()
              .having((s) => s.enabled, 'enabled', isTrue)
              .having((s) => s.locked, 'locked', isTrue),
        ],
      );

      blocTest<LockBloc, LockState>(
        'resuming after the chosen delay locks; sooner does not',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
          when(() => storage.lockAfterSeconds()).thenAnswer((_) async => 60);
        },
        act: (bloc) async {
          // Stamp background time, then advance the clock before resume.
          bloc.add(const LockAppBackgrounded());
          await Future<void>.delayed(Duration.zero);
          clock = clock.add(const Duration(seconds: 30));
          bloc.add(const LockAppResumed());
          await Future<void>.delayed(Duration.zero);
          expect(bloc.state.locked, isFalse);

          bloc.add(const LockAppBackgrounded());
          await Future<void>.delayed(Duration.zero);
          clock = clock.add(const Duration(seconds: 61));
          final locked = bloc.stream.firstWhere((s) => s.locked);
          bloc.add(const LockAppResumed());
          await locked;
        },
        verify: (bloc) {
          expect(bloc.state.locked, isTrue);
        },
      );

      blocTest<LockBloc, LockState>(
        'lock-after 0 locks on any return from the background',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
          when(() => storage.lockAfterSeconds()).thenAnswer((_) async => 0);
        },
        act: (bloc) {
          bloc
            ..add(const LockAppBackgrounded())
            ..add(const LockAppResumed());
        },
        verify: (bloc) => expect(bloc.state.locked, isTrue),
      );

      blocTest<LockBloc, LockState>(
        'cold-start storage fault stays locked (fail closed)',
        build: build,
        setUp: () {
          when(() => storage.method()).thenThrow(Exception('secure'));
        },
        act: (bloc) => bloc.add(const LockColdStart()),
        expect: () => [
          isA<LockLoadInProgress>().having((s) => s.locked, 'locked', isTrue),
          isA<LockLoadFailure>().having((s) => s.locked, 'locked', isTrue),
        ],
      );

      blocTest<LockBloc, LockState>(
        'retry after cold-start fault unlocks when no PIN exists',
        build: build,
        setUp: () {
          var calls = 0;
          when(() => storage.method()).thenAnswer((_) async {
            calls += 1;
            if (calls == 1) throw Exception('secure');
            return LockMethod.none;
          });
        },
        act: (bloc) async {
          bloc.add(const LockColdStart());
          await bloc.stream.firstWhere((s) => s is LockLoadFailure);
          bloc.add(const LockStatusRequested());
        },
        verify: (bloc) {
          expect(bloc.state, isA<LockLoadSuccess>());
          expect(bloc.state.locked, isFalse);
          expect(bloc.state.enabled, isFalse);
        },
      );

      blocTest<LockBloc, LockState>(
        'retry after cold-start fault keeps the cover when a PIN exists',
        build: build,
        setUp: () {
          var calls = 0;
          when(() => storage.method()).thenAnswer((_) async {
            calls += 1;
            if (calls == 1) throw Exception('secure');
            return LockMethod.pin;
          });
        },
        act: (bloc) async {
          bloc.add(const LockColdStart());
          await bloc.stream.firstWhere((s) => s is LockLoadFailure);
          bloc.add(const LockStatusRequested());
        },
        verify: (bloc) {
          expect(bloc.state, isA<LockLoadSuccess>());
          expect(bloc.state.enabled, isTrue);
          expect(bloc.state.locked, isTrue);
        },
      );

      blocTest<LockBloc, LockState>(
        'resume still fails closed when the lock was on and storage throws',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        setUp: () {
          when(() => storage.method()).thenThrow(Exception('secure'));
          when(() => storage.lockAfterSeconds()).thenAnswer((_) async => 0);
        },
        act: (bloc) {
          bloc
            ..add(const LockAppBackgrounded())
            ..add(const LockAppResumed());
        },
        verify: (bloc) {
          expect(bloc.state, isA<LockLoadFailure>());
          expect(bloc.state.locked, isTrue);
        },
      );
    });

    group('wrong PIN limit then sign-out', () {
      blocTest<LockBloc, LockState>(
        'four wrong PINs leave attempts; the fifth requires sign-out',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true, locked: true),
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
          var failures = 0;
          when(
            () => storage.failedAttempts(),
          ).thenAnswer((_) async => failures);
          when(
            () =>
                storage.recordFailure(lockoutUntil: any(named: 'lockoutUntil')),
          ).thenAnswer((_) async {
            return failures += 1;
          });
        },
        act: (bloc) async {
          for (var i = 0; i < 5; i++) {
            bloc.add(const LockPinVerifyRequested(pin: '0000'));
            await bloc.stream.first;
          }
        },
        verify: (bloc) {
          expect(bloc.state, isA<LockSignOutRequired>());
          expect(bloc.state.signOutRequired, isTrue);
          expect(bloc.state.locked, isTrue);
          // Attempts never reach analytics, however they end.
          verifyNever(() => analytics.logLockEnabled());
          verifyNever(() => analytics.logLockDisabled());
          verifyNever(
            () => analytics.logLockBiometricsChanged(
              enabled: any(named: 'enabled'),
            ),
          );
          verifyNever(
            () =>
                analytics.logLockTimeoutChanged(seconds: any(named: 'seconds')),
          );
        },
      );
    });

    group('disable and sign-out clear the PIN', () {
      blocTest<LockBloc, LockState>(
        'turning the lock off needs the PIN then clears storage',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
          when(() => storage.verifyPin(secret)).thenAnswer((_) async => true);
        },
        act: (bloc) => bloc.add(const LockDisableRequested(pin: secret)),
        expect: () => [isA<LockWriteInProgress>(), const LockDisableSuccess()],
        verify: (_) {
          verify(() => storage.verifyPin(secret)).called(1);
          verify(() => storage.clearAll()).called(1);
          verify(() => analytics.logLockDisabled()).called(1);
        },
      );

      blocTest<LockBloc, LockState>(
        'LockStorageCleared wipes the store and resets',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true, locked: true),
        act: (bloc) => bloc.add(const LockStorageCleared()),
        expect: () => [const LockInitial()],
        verify: (_) => verify(() => storage.clearAll()).called(1),
      );
    });

    group('creating a PIN', () {
      blocTest<LockBloc, LockState>(
        'matching four digits turns the lock on',
        build: build,
        act: (bloc) => bloc.add(
          const LockPinCreateRequested(pin: secret, confirmPin: secret),
        ),
        expect: () => [
          isA<LockWriteInProgress>(),
          isA<LockPinCreateSuccess>().having((s) => s.enabled, 'on', isTrue),
        ],
        verify: (_) {
          verify(() => storage.setPin(secret)).called(1);
          verify(() => analytics.logLockEnabled()).called(1);
        },
      );

      blocTest<LockBloc, LockState>(
        'a mismatch is refused without writing',
        build: build,
        act: (bloc) => bloc.add(
          const LockPinCreateRequested(pin: secret, confirmPin: '0000'),
        ),
        expect: () => [isA<LockPinMismatch>()],
        verify: (_) {
          verifyNever(() => storage.setPin(any()));
          verifyNever(() => analytics.logLockEnabled());
        },
      );

      blocTest<LockBloc, LockState>(
        'a new auto-lock delay is saved',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        setUp: () {
          when(() => storage.method()).thenAnswer((_) async => LockMethod.pin);
          when(() => storage.lockAfterSeconds()).thenAnswer((_) async => 60);
        },
        act: (bloc) => bloc.add(const LockAfterChanged(seconds: 60)),
        verify: (_) {
          verify(() => storage.setLockAfter(60)).called(1);
          verify(() => analytics.logLockTimeoutChanged(seconds: 60)).called(1);
        },
      );

      blocTest<LockBloc, LockState>(
        'an unknown delay is refused without writing',
        build: build,
        seed: () => const LockLoadSuccess(enabled: true),
        act: (bloc) => bloc.add(const LockAfterChanged(seconds: 45)),
        verify: (_) {
          verifyNever(() => storage.setLockAfter(any()));
          verifyNever(
            () =>
                analytics.logLockTimeoutChanged(seconds: any(named: 'seconds')),
          );
        },
      );
    });

    group('no PIN in logs', () {
      late List<String> logged;
      late DebugPrintCallback original;

      setUp(() {
        logged = [];
        original = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        Logger.addOutputListener((event) => logged.addAll(event.lines));
      });

      tearDown(() {
        debugPrint = original;
      });

      test('create and verify never put the digits in a log line', () async {
        var method = LockMethod.none;
        when(() => storage.method()).thenAnswer((_) async => method);
        when(() => storage.setPin(any())).thenAnswer((_) async {
          method = LockMethod.pin;
        });
        when(() => storage.verifyPin(secret)).thenAnswer((_) async => true);
        final bloc = build();
        addTearDown(bloc.close);

        await runZoned(
          () async {
            final created = bloc.stream.firstWhere(
              (s) => s is LockPinCreateSuccess,
            );
            bloc.add(
              const LockPinCreateRequested(pin: secret, confirmPin: secret),
            );
            await created;
            final unlocked = bloc.stream.firstWhere(
              (s) => s is LockLoadSuccess && !s.locked,
            );
            bloc.add(const LockPinVerifyRequested(pin: secret));
            await unlocked;
            // Event toString must not leak either.
            expect(
              const LockPinVerifyRequested(pin: secret).toString(),
              isNot(contains(secret)),
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => logged.add(line),
          ),
        );

        expect(logged.where((line) => line.contains(secret)), isEmpty);
      });
    });

    group('one method at a time', () {
      late Map<String, String> store;
      late LockStorage real;
      late FakeBiometricAuthenticator fake;

      setUp(() {
        store = {};
        final secure = _MockSecure();
        when(
          () => secure.read(key: any(named: 'key')),
        ).thenAnswer((inv) async => store[inv.namedArguments[#key] as String]);
        when(
          () => secure.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((inv) async {
          store[inv.namedArguments[#key] as String] =
              inv.namedArguments[#value] as String;
        });
        when(() => secure.delete(key: any(named: 'key'))).thenAnswer((
          inv,
        ) async {
          store.remove(inv.namedArguments[#key] as String);
        });
        real = LockStorage(
          secureStorage: secure,
          random: Random(1),
          iterations: 1000,
        );
        fake = FakeBiometricAuthenticator();
      });

      LockBloc realBloc() => LockBloc(
        storage: real,
        biometrics: fake,
        analytics: analytics,
        now: () => clock,
      );

      blocTest<LockBloc, LockState>(
        'none to biometric stores no PIN hash after the prompt succeeds',
        build: realBloc,
        act: (bloc) =>
            bloc.add(const LockBiometricEnableRequested(reason: 'open')),
        verify: (bloc) {
          expect(bloc.state.method, LockMethod.biometric);
          expect(bloc.state.enabled, isTrue);
          expect(bloc.state.biometricsEnabled, isTrue);
          expect(store['tabibu.lock.pinHash'], isNull);
          expect(fake.authenticateCalls, 1);
          expect(fake.lastBiometricOnly, isTrue);
          expect(fake.outcome, FakeBiometricOutcome.success);
          verify(
            () => analytics.logLockBiometricsChanged(enabled: true),
          ).called(1);
        },
      );

      blocTest<LockBloc, LockState>(
        'unavailable biometrics are refused and the method stays',
        build: realBloc,
        setUp: () => fake.available = false,
        act: (bloc) =>
            bloc.add(const LockBiometricEnableRequested(reason: 'open')),
        expect: () => [isA<LockBiometricUnavailable>()],
        verify: (bloc) async {
          expect(bloc.state.method, LockMethod.none);
          expect(await real.method(), LockMethod.none);
          expect(fake.authenticateCalls, 0);
          verifyNever(
            () => analytics.logLockBiometricsChanged(
              enabled: any(named: 'enabled'),
            ),
          );
        },
      );

      for (final outcome in [
        FakeBiometricOutcome.cancelled,
        FakeBiometricOutcome.failed,
      ]) {
        blocTest<LockBloc, LockState>(
          'a ${outcome.name} prompt leaves the method unchanged and raises '
          'no error',
          build: realBloc,
          setUp: () => fake.outcome = outcome,
          act: (bloc) =>
              bloc.add(const LockBiometricEnableRequested(reason: 'open')),
          expect: () => [isA<LockLoadSuccess>()],
          verify: (bloc) {
            expect(bloc.state.method, LockMethod.none);
            expect(bloc.state.error, isNull);
            expect(bloc.state, isNot(isA<LockWriteFailure>()));
            expect(fake.authenticateCalls, 1);
            expect(fake.lastBiometricOnly, isTrue);
          },
        );
      }

      blocTest<LockBloc, LockState>(
        'turning fingerprint off needs a successful prompt',
        build: realBloc,
        setUp: () => real.setMethod(LockMethod.biometric),
        act: (bloc) =>
            bloc.add(const LockBiometricDisableRequested(reason: 'open')),
        expect: () => [isA<LockWriteInProgress>(), const LockDisableSuccess()],
        verify: (bloc) async {
          expect(await real.method(), LockMethod.none);
          verify(
            () => analytics.logLockBiometricsChanged(enabled: false),
          ).called(1);
          verify(() => analytics.logLockDisabled()).called(1);
        },
      );

      blocTest<LockBloc, LockState>(
        'a failed prompt leaves fingerprint on',
        build: realBloc,
        setUp: () async {
          await real.setMethod(LockMethod.biometric);
          fake.outcome = FakeBiometricOutcome.failed;
        },
        act: (bloc) =>
            bloc.add(const LockBiometricDisableRequested(reason: 'open')),
        expect: () => [isA<LockLoadSuccess>()],
        verify: (bloc) async {
          expect(bloc.state.method, LockMethod.biometric);
          expect(bloc.state.enabled, isTrue);
          expect(bloc.state.error, isNull);
          expect(await real.method(), LockMethod.biometric);
        },
      );

      blocTest<LockBloc, LockState>(
        'PIN to fingerprint needs the PIN, then the prompt',
        build: realBloc,
        setUp: () => real.setPin(secret),
        act: (bloc) => bloc.add(
          const LockBiometricEnableRequested(reason: 'open', pin: secret),
        ),
        verify: (bloc) async {
          expect(bloc.state.method, LockMethod.biometric);
          expect(store['tabibu.lock.pinHash'], isNull);
          expect(fake.lastBiometricOnly, isTrue);
        },
      );

      blocTest<LockBloc, LockState>(
        'a wrong PIN leaves the PIN lock and does not prompt',
        build: realBloc,
        seed: () =>
            const LockLoadSuccess(method: LockMethod.pin, enabled: true),
        setUp: () => real.setPin(secret),
        act: (bloc) => bloc.add(
          const LockBiometricEnableRequested(reason: 'open', pin: '0000'),
        ),
        expect: () => [isA<LockPinWrong>()],
        verify: (bloc) async {
          expect(bloc.state.method, LockMethod.pin);
          expect(await real.method(), LockMethod.pin);
          expect(store['tabibu.lock.pinHash'], isNotNull);
          expect(fake.authenticateCalls, 0);
        },
      );

      blocTest<LockBloc, LockState>(
        'a failed prompt after the right PIN leaves the PIN lock',
        build: realBloc,
        setUp: () async {
          await real.setPin(secret);
          fake.outcome = FakeBiometricOutcome.failed;
        },
        act: (bloc) => bloc.add(
          const LockBiometricEnableRequested(reason: 'open', pin: secret),
        ),
        expect: () => [isA<LockLoadSuccess>()],
        verify: (bloc) async {
          expect(bloc.state.method, LockMethod.pin);
          expect(store['tabibu.lock.pinHash'], isNotNull);
          expect(fake.authenticateCalls, 1);
          expect(fake.lastBiometricOnly, isTrue);
        },
      );

      blocTest<LockBloc, LockState>(
        'fingerprint to PIN turns fingerprint off only after the PIN is saved',
        build: realBloc,
        setUp: () => real.setMethod(LockMethod.biometric),
        act: (bloc) async {
          bloc.add(const LockBiometricReplaceRequested(reason: 'open'));
          await bloc.stream.firstWhere((s) => s is LockPinCreateAllowed);
          expect(store['tabibu.lock.method'], 'biometric');
          expect(store['tabibu.lock.pinHash'], isNull);
          bloc.add(
            const LockPinCreateRequested(pin: secret, confirmPin: secret),
          );
        },
        verify: (bloc) async {
          expect(bloc.state, isA<LockPinCreateSuccess>());
          expect(bloc.state.method, LockMethod.pin);
          expect(await real.method(), LockMethod.pin);
          expect(store['tabibu.lock.pinHash'], isNotNull);
          expect(store.containsKey('tabibu.lock.biometricsEnabled'), isFalse);
        },
      );

      blocTest<LockBloc, LockState>(
        'a failed switch prompt never saves a PIN',
        build: realBloc,
        setUp: () async {
          await real.setMethod(LockMethod.biometric);
          fake.outcome = FakeBiometricOutcome.cancelled;
        },
        act: (bloc) async {
          bloc.add(const LockBiometricReplaceRequested(reason: 'open'));
          await bloc.stream.firstWhere((s) => s is LockLoadSuccess);
          bloc.add(
            const LockPinCreateRequested(pin: secret, confirmPin: secret),
          );
        },
        verify: (bloc) async {
          expect(bloc.state, isA<LockWriteFailure>());
          expect(await real.method(), LockMethod.biometric);
          expect(store['tabibu.lock.pinHash'], isNull);
        },
      );

      for (final (why, leave) in [
        ('leaving the create-PIN screen', const LockPinCreateLeft()),
        ('the app going to the background', const LockAppBackgrounded()),
      ]) {
        blocTest<LockBloc, LockState>(
          "the prompt's permission to set a PIN ends with $why",
          build: realBloc,
          setUp: () => real.setMethod(LockMethod.biometric),
          act: (bloc) async {
            bloc.add(const LockBiometricReplaceRequested(reason: 'open'));
            await bloc.stream.firstWhere((s) => s is LockPinCreateAllowed);
            bloc
              ..add(leave)
              ..add(
                const LockPinCreateRequested(pin: secret, confirmPin: secret),
              );
          },
          verify: (bloc) async {
            expect(bloc.state, isA<LockWriteFailure>());
            expect(await real.method(), LockMethod.biometric);
            expect(store['tabibu.lock.pinHash'], isNull);
          },
        );
      }

      blocTest<LockBloc, LockState>(
        'an older PIN plus the biometrics flag reads as the PIN',
        build: realBloc,
        setUp: () {
          store['tabibu.lock.enabled'] = 'true';
          store['tabibu.lock.pinHash'] = 'legacy-hash';
          store['tabibu.lock.biometricsEnabled'] = 'true';
        },
        act: (bloc) => bloc.add(const LockStatusRequested()),
        verify: (bloc) {
          expect(bloc.state.method, LockMethod.pin);
          expect(bloc.state.enabled, isTrue);
          expect(bloc.state.biometricsEnabled, isFalse);
          expect(store['tabibu.lock.biometricsEnabled'], 'true');
        },
      );

      blocTest<LockBloc, LockState>(
        'unlocking with fingerprint allows the device passcode',
        build: realBloc,
        setUp: () => real.setMethod(LockMethod.biometric),
        act: (bloc) =>
            bloc.add(const LockBiometricUnlockRequested(reason: 'open')),
        verify: (bloc) async {
          expect(fake.lastBiometricOnly, isFalse);
          expect(fake.authenticateCalls, 1);
          expect(bloc.state.locked, isFalse);
          expect(bloc.state.method, LockMethod.biometric);
          expect(await real.failedAttempts(), 0);
          expect(bloc.state, isNot(isA<LockSignOutRequired>()));
        },
      );

      blocTest<LockBloc, LockState>(
        'a failed fingerprint unlock stays locked and does not count a PIN try',
        build: realBloc,
        setUp: () async {
          await real.setMethod(LockMethod.biometric);
          fake.outcome = FakeBiometricOutcome.cancelled;
        },
        act: (bloc) =>
            bloc.add(const LockBiometricUnlockRequested(reason: 'open')),
        verify: (bloc) async {
          expect(fake.lastBiometricOnly, isFalse);
          expect(bloc.state, isA<LockLoadSuccess>());
          expect(bloc.state.locked, isTrue);
          expect(bloc.state.error, isNull);
          expect(await real.failedAttempts(), 0);
          expect(bloc.state.signOutRequired, isFalse);
        },
      );

      blocTest<LockBloc, LockState>(
        'a PIN entry cannot spend the allowance while fingerprint is the lock',
        build: realBloc,
        setUp: () => real.setMethod(LockMethod.biometric),
        act: (bloc) => bloc.add(const LockPinVerifyRequested(pin: '0000')),
        verify: (bloc) async {
          expect(bloc.state, isA<LockInitial>());
          expect(await real.failedAttempts(), 0);
          expect(fake.authenticateCalls, 0);
        },
      );
    });
  });
}
