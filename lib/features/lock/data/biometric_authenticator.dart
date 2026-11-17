import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';

/// The device's biometric prompt, behind an interface so the bloc, which
/// never imports Flutter, can be tested. A result never leaves this layer
/// as anything but a bool, and is never logged.
abstract interface class BiometricAuthenticator {
  /// Biometrics are enrolled and usable on this device.
  Future<bool> isAvailable();

  /// True only when the person was recognised. [reason] is the system
  /// prompt's text, supplied by the screen, which owns the strings.
  /// [biometricOnly] false lets the phone's own passcode finish an unlock.
  /// Turning the method on or off keeps it true, so a passcode alone cannot
  /// change the setting.
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = true,
  });
}

@LazySingleton(as: BiometricAuthenticator)
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator({@ignoreParam LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
    } on Object catch (_) {
      return false;
    }
  }
}
