import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/features/lock/data/lock_storage.dart';

class _MockSecure extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecure secure;
  late Map<String, String> store;
  late LockStorage storage;

  setUp(() {
    secure = _MockSecure();
    store = {};
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
    when(() => secure.delete(key: any(named: 'key'))).thenAnswer((inv) async {
      store.remove(inv.namedArguments[#key] as String);
    });
    // Fixed bytes so hashes are stable across runs.
    storage = LockStorage(
      secureStorage: secure,
      random: Random(1),
      iterations: 1000,
    );
  });

  group('LockStorage', () {
    test('setPin stores only salt and hash, never the PIN', () async {
      await storage.setPin('4829');
      expect(store.values.any((v) => v.contains('4829')), isFalse);
      expect(store['tabibu.lock.pinHash'], isNotNull);
      expect(store['tabibu.lock.pinSalt'], isNotNull);
      expect(store['tabibu.lock.enabled'], 'true');
      expect(store['tabibu.lock.method'], 'pin');
      expect(store.containsKey('tabibu.lock.biometricsEnabled'), isFalse);
      expect(await storage.isEnabled(), isTrue);
      expect(await storage.method(), LockMethod.pin);
      expect(await storage.verifyPin('4829'), isTrue);
      expect(await storage.verifyPin('0000'), isFalse);
    });

    test('clearAll removes only the lock keys', () async {
      await storage.setPin('4829');
      store['tabibu.lock.biometricsEnabled'] = 'true';
      await storage.clearAll();
      expect(store.keys.where((k) => k.startsWith('tabibu.lock.')), isEmpty);
      expect(await storage.isEnabled(), isFalse);
      expect(await storage.method(), LockMethod.none);
    });

    test('an older PIN plus the biometrics flag reads as pin', () async {
      store['tabibu.lock.enabled'] = 'true';
      store['tabibu.lock.pinHash'] = 'legacy-hash';
      store['tabibu.lock.biometricsEnabled'] = 'true';
      expect(await storage.method(), LockMethod.pin);
      expect(store['tabibu.lock.biometricsEnabled'], 'true');
      await storage.setPin('4829');
      expect(store.containsKey('tabibu.lock.biometricsEnabled'), isFalse);
      expect(await storage.method(), LockMethod.pin);
      expect(store['tabibu.lock.method'], 'pin');
    });

    test('fingerprint replaces the PIN hash', () async {
      await storage.setPin('4829');
      await storage.setMethod(LockMethod.biometric);
      expect(store['tabibu.lock.pinHash'], isNull);
      expect(store['tabibu.lock.pinSalt'], isNull);
      expect(store.containsKey('tabibu.lock.biometricsEnabled'), isFalse);
      expect(await storage.method(), LockMethod.biometric);
      expect(await storage.isEnabled(), isTrue);
    });

    test(
      'a switch to fingerprint that fails part-way still leaves a lock',
      () async {
        for (final failing in [
          'tabibu.lock.method',
          'tabibu.lock.pinHash',
          'tabibu.lock.pinSalt',
          'tabibu.lock.enabled',
        ]) {
          store.clear();
          await storage.setPin('4829');
          await storage.setMethod(LockMethod.pin);
          when(
            () => secure.write(
              key: failing,
              value: any(named: 'value'),
            ),
          ).thenThrow(Exception('write failed'));
          when(
            () => secure.delete(key: failing),
          ).thenThrow(Exception('delete failed'));

          await expectLater(
            storage.setMethod(LockMethod.biometric),
            throwsException,
            reason: failing,
          );
          expect(await storage.isEnabled(), isTrue, reason: failing);

          when(
            () => secure.write(
              key: failing,
              value: any(named: 'value'),
            ),
          ).thenAnswer((inv) async {
            store[failing] = inv.namedArguments[#value] as String;
          });
          when(() => secure.delete(key: failing)).thenAnswer((_) async {
            store.remove(failing);
          });
        }
      },
    );

    test('refuses a PIN that is not four digits', () async {
      expect(() => storage.setPin('12'), throwsArgumentError);
      expect(() => storage.setPin('abcd'), throwsArgumentError);
      expect(await storage.isEnabled(), isFalse);
    });
  });
}
