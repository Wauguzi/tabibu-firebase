import 'package:tabibu/features/lock/data/biometric_authenticator.dart';

/// What the next prompt does. Failed and cancelled both come back as false;
/// the platform does not say which.
enum FakeBiometricOutcome { success, failed, cancelled }

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({
    this.available = true,
    this.outcome = FakeBiometricOutcome.success,
  });

  bool available;
  FakeBiometricOutcome outcome;
  int authenticateCalls = 0;
  bool? lastBiometricOnly;
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    authenticateCalls += 1;
    lastReason = reason;
    lastBiometricOnly = biometricOnly;
    return outcome == FakeBiometricOutcome.success;
  }
}
