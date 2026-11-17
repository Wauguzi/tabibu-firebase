import 'package:equatable/equatable.dart';

sealed class LockEvent extends Equatable {
  const LockEvent();

  @override
  List<Object?> get props => [];
}

/// The settings and the lock as they stand; never changes whether the app
/// is locked.
final class LockStatusRequested extends LockEvent {
  const LockStatusRequested();
}

/// Dispatched by `App` before the first frame: locks when a PIN is set.
final class LockColdStart extends LockEvent {
  const LockColdStart();
}

/// Turns the lock on. Refused while one is already on: changing the PIN is
/// turning the lock off with the old one, then on again.
final class LockPinCreateRequested extends LockEvent {
  const LockPinCreateRequested({required this.pin, required this.confirmPin});

  final String pin;
  final String confirmPin;

  /// An event's `toString` reaches logs and bloc tooling; the digits must not.
  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [pin, confirmPin];
}

final class LockPinVerifyRequested extends LockEvent {
  const LockPinVerifyRequested({required this.pin});

  final String pin;

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [pin];
}

/// Turns fingerprint/face on. [pin] is the current PIN when that is the
/// method, and empty when the lock is off. The digits must not reach a log.
final class LockBiometricEnableRequested extends LockEvent {
  const LockBiometricEnableRequested({required this.reason, this.pin = ''});

  final String reason;
  final String pin;

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [reason, pin];
}

/// Turns fingerprint/face off. Only a successful prompt changes the method.
final class LockBiometricDisableRequested extends LockEvent {
  const LockBiometricDisableRequested({required this.reason});

  final String reason;

  @override
  List<Object?> get props => [reason];
}

/// Starts a switch from fingerprint/face to a PIN. The prompt comes first;
/// the PIN is saved by [LockPinCreateRequested] afterwards.
final class LockBiometricReplaceRequested extends LockEvent {
  const LockBiometricReplaceRequested({required this.reason});

  final String reason;

  @override
  List<Object?> get props => [reason];
}

final class LockDisableRequested extends LockEvent {
  const LockDisableRequested({required this.pin});

  final String pin;

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [pin];
}

/// One of `LockBloc.lockAfterOptions`: 0, 60, 300 or 900.
final class LockAfterChanged extends LockEvent {
  const LockAfterChanged({required this.seconds});

  final int seconds;

  @override
  List<Object?> get props => [seconds];
}

final class LockAppBackgrounded extends LockEvent {
  const LockAppBackgrounded();
}

/// The create-PIN screen closed, saved or not: a fingerprint/face prompt's
/// permission to replace it with a PIN ends with the screen.
final class LockPinCreateLeft extends LockEvent {
  const LockPinCreateLeft();
}

final class LockAppResumed extends LockEvent {
  const LockAppResumed();
}

/// [reason] is the system prompt's text; the screen owns the strings.
final class LockBiometricUnlockRequested extends LockEvent {
  const LockBiometricUnlockRequested({required this.reason});

  final String reason;

  @override
  List<Object?> get props => [reason];
}

/// In-memory only: back to the initial state.
final class LockReset extends LockEvent {
  const LockReset();
}

/// Sign-out: the stored PIN, biometrics choice and failure count go, then
/// the bloc resets.
final class LockStorageCleared extends LockEvent {
  const LockStorageCleared();
}
