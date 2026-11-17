import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/data/biometric_authenticator.dart';
import 'package:tabibu/features/lock/data/lock_storage.dart';

/// The app lock: one method at a time, off, a four-digit PIN, or
/// fingerprint/face. Five wrong PINs sign the person out. That allowance
/// belongs to the PIN; the phone's own passcode limits fingerprint/face.
///
/// A PIN is only ever an argument: it is hashed in [LockStorage], never
/// held, emitted or logged. Only setting outcomes reach analytics, never a
/// PIN or an attempt count.
class LockBloc extends Bloc<LockEvent, LockState> {
  LockBloc({
    LockStorage? storage,
    BiometricAuthenticator? biometrics,
    AnalyticsService? analytics,
    DateTime Function()? now,
  }) : _storage = storage ?? getIt<LockStorage>(),
       _biometrics = biometrics ?? getIt<BiometricAuthenticator>(),
       _analytics = analytics ?? getIt<AnalyticsService>(),
       _now = now ?? DateTime.now,
       super(const LockInitial()) {
    on<LockStatusRequested>(_onStatusRequested, transformer: sequential());
    on<LockColdStart>(_onColdStart, transformer: sequential());
    on<LockPinCreateRequested>(_onPinCreate, transformer: sequential());
    on<LockPinVerifyRequested>(_onPinVerify, transformer: sequential());
    on<LockBiometricEnableRequested>(
      _onBiometricEnable,
      transformer: sequential(),
    );
    on<LockBiometricDisableRequested>(
      _onBiometricDisable,
      transformer: sequential(),
    );
    on<LockBiometricReplaceRequested>(
      _onBiometricReplace,
      transformer: sequential(),
    );
    on<LockDisableRequested>(_onDisable, transformer: sequential());
    on<LockAfterChanged>(_onAfterChanged, transformer: sequential());
    on<LockAppBackgrounded>(_onBackgrounded, transformer: sequential());
    on<LockPinCreateLeft>(_onPinCreateLeft, transformer: sequential());
    on<LockAppResumed>(_onResumed, transformer: sequential());
    on<LockBiometricUnlockRequested>(
      _onBiometricUnlock,
      transformer: sequential(),
    );
    on<LockReset>(_onReset, transformer: sequential());
    on<LockStorageCleared>(_onStorageCleared, transformer: sequential());
  }

  final LockStorage _storage;
  final BiometricAuthenticator _biometrics;
  final AnalyticsService _analytics;
  final DateTime Function() _now;

  /// Straight away, 1 minute, 5 minutes, 15 minutes.
  static const lockAfterOptions = [0, 60, 300, 900];

  /// How long tries are refused once the allowance is spent.
  static const lockoutDuration = Duration(minutes: 5);

  DateTime? _backgroundedAt;

  /// Set when the fingerprint/face prompt has allowed a PIN to replace it.
  /// A mismatch keeps it, so the person can re-enter the PIN; saving,
  /// leaving the create-PIN screen, the app going to the background or a
  /// reset ends it, so the permission never outlives that one screen.
  bool _pinReplacesBiometric = false;

  Future<void> _onStatusRequested(
    LockStatusRequested event,
    Emitter<LockState> emit,
  ) async {
    try {
      emit(await _status(locked: state.locked));
    } on Object catch (_) {
      // Keep the cover if we already had one (cold-start fail-closed).
      emit(_loadFailure(locked: state.locked));
    }
  }

  /// Covers the app first, then reads: no frame shows content before the
  /// answer is known.
  Future<void> _onColdStart(
    LockColdStart event,
    Emitter<LockState> emit,
  ) async {
    emit(
      LockLoadInProgress(
        method: state.method,
        enabled: state.enabled,
        biometricsEnabled: state.biometricsEnabled,
        lockAfterSeconds: state.lockAfterSeconds,
        attemptsRemaining: state.attemptsRemaining,
        lockoutUntil: state.lockoutUntil,
        signOutRequired: state.signOutRequired,
      ),
    );
    try {
      emit(await _status(locked: true));
    } on Object catch (_) {
      // Fail closed: a storage fault must not uncover the app. Retry and
      // sign-out on the overlay are the way out.
      emit(_loadFailure(locked: true));
    }
  }

  Future<void> _onPinCreate(
    LockPinCreateRequested event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    if (!LockStorage.isValidPin(event.pin) ||
        !LockStorage.isValidPin(event.confirmPin)) {
      emit(
        LockPinMalformed(
          method: state.method,
          enabled: state.enabled,
          locked: state.locked,
        ),
      );
      return;
    }
    if (event.pin != event.confirmPin) {
      emit(
        LockPinMismatch(
          method: state.method,
          enabled: state.enabled,
          locked: state.locked,
        ),
      );
      return;
    }
    try {
      final current = await _storage.method();
      final replacing = current == .biometric && _pinReplacesBiometric;
      // Replacing a PIN without the old one, or dropping fingerprint/face
      // without the prompt, would be a way around the lock.
      if (current != .none && !replacing) {
        emit(_writeFailure(AppError.unknown));
        return;
      }
      emit(_inProgress());
      await _storage.setPin(event.pin);
      _pinReplacesBiometric = false;
      unawaited(_analytics.logLockEnabled());
      if (replacing) {
        unawaited(_analytics.logLockBiometricsChanged(enabled: false));
      }
      emit(
        LockPinCreateSuccess(
          lockAfterSeconds: await _storage.lockAfterSeconds(),
        ),
      );
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onPinVerify(
    LockPinVerifyRequested event,
    Emitter<LockState> emit,
  ) async {
    try {
      if (await _storage.method() != .pin) return;
      if (!await _checkPin(event.pin, emit)) return;
      emit(await _status(locked: false));
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onBiometricEnable(
    LockBiometricEnableRequested event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    try {
      final current = await _storage.method();
      if (current == .biometric) {
        emit(await _status(locked: false));
        return;
      }
      if (current == .pin && !await _checkPin(event.pin, emit)) return;
      if (!await _biometrics.isAvailable()) {
        emit(
          LockBiometricUnavailable(
            method: current,
            enabled: current != .none,
            locked: state.locked,
            lockAfterSeconds: state.lockAfterSeconds,
          ),
        );
        return;
      }
      // The default keeps this biometric-only, so a passcode cannot turn it on.
      final recognised = await _biometrics.authenticate(reason: event.reason);
      if (!recognised) {
        emit(await _status(locked: state.locked));
        return;
      }
      emit(_inProgress());
      await _storage.setMethod(.biometric);
      _pinReplacesBiometric = false;
      unawaited(_analytics.logLockBiometricsChanged(enabled: true));
      if (current == .none) unawaited(_analytics.logLockEnabled());
      emit(await _status(locked: false));
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onBiometricDisable(
    LockBiometricDisableRequested event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    try {
      if (await _storage.method() != .biometric) return;
      final recognised = await _biometrics.authenticate(reason: event.reason);
      if (!recognised) {
        emit(await _status(locked: false));
        return;
      }
      emit(_inProgress());
      await _storage.clearAll();
      _pinReplacesBiometric = false;
      unawaited(_analytics.logLockBiometricsChanged(enabled: false));
      unawaited(_analytics.logLockDisabled());
      emit(const LockDisableSuccess());
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onBiometricReplace(
    LockBiometricReplaceRequested event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    try {
      if (await _storage.method() != .biometric) return;
      final recognised = await _biometrics.authenticate(reason: event.reason);
      if (!recognised) {
        emit(await _status(locked: false));
        return;
      }
      _pinReplacesBiometric = true;
      emit(
        LockPinCreateAllowed(
          lockAfterSeconds: await _storage.lockAfterSeconds(),
        ),
      );
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onDisable(
    LockDisableRequested event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    try {
      if (await _storage.method() != .pin) return;
      if (!await _checkPin(event.pin, emit)) return;
      emit(_inProgress());
      await _storage.clearAll();
      _pinReplacesBiometric = false;
      unawaited(_analytics.logLockDisabled());
      emit(const LockDisableSuccess());
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  Future<void> _onAfterChanged(
    LockAfterChanged event,
    Emitter<LockState> emit,
  ) async {
    if (state.locked) return;
    if (!lockAfterOptions.contains(event.seconds)) {
      emit(_writeFailure(AppError.unknown));
      return;
    }
    try {
      await _storage.setLockAfter(event.seconds);
      unawaited(_analytics.logLockTimeoutChanged(seconds: event.seconds));
      emit(await _status(locked: false));
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  void _onBackgrounded(LockAppBackgrounded event, Emitter<LockState> emit) {
    _backgroundedAt = _now();
    _pinReplacesBiometric = false;
  }

  void _onPinCreateLeft(LockPinCreateLeft event, Emitter<LockState> emit) {
    _pinReplacesBiometric = false;
  }

  /// Locks once the time away reaches the chosen delay; 0 locks on any
  /// return. A failed read locks when a lock was on: the safe side.
  Future<void> _onResumed(LockAppResumed event, Emitter<LockState> emit) async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || state.locked) return;
    try {
      if (await _storage.method() == .none) return;
      final after = Duration(seconds: await _storage.lockAfterSeconds());
      if (_now().difference(since) < after) return;
      emit(await _status(locked: true));
    } on Object catch (_) {
      if (state.enabled) emit(_loadFailure(locked: true));
    }
  }

  Future<void> _onBiometricUnlock(
    LockBiometricUnlockRequested event,
    Emitter<LockState> emit,
  ) async {
    try {
      if (await _storage.method() != .biometric) return;
      // The phone's passcode is the fallback, and the phone counts the
      // tries. The PIN's five-attempt sign-out does not apply here.
      final recognised = await _biometrics.authenticate(
        reason: event.reason,
        biometricOnly: false,
      );
      if (!recognised) {
        emit(await _status(locked: true));
        return;
      }
      await _storage.resetFailures();
      emit(await _status(locked: false));
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  void _onReset(LockReset event, Emitter<LockState> emit) {
    _backgroundedAt = null;
    _pinReplacesBiometric = false;
    emit(const LockInitial());
  }

  Future<void> _onStorageCleared(
    LockStorageCleared event,
    Emitter<LockState> emit,
  ) async {
    _backgroundedAt = null;
    _pinReplacesBiometric = false;
    try {
      await _storage.clearAll();
      emit(const LockInitial());
    } on Object catch (_) {
      emit(_writeFailure(AppError.unknown));
    }
  }

  /// True when [pin] is right. Otherwise it has emitted why: refused during
  /// a lockout or after the allowance, or a counted wrong PIN. The fifth
  /// starts the lockout and asks for a sign-out.
  Future<bool> _checkPin(String pin, Emitter<LockState> emit) async {
    final now = _now().toUtc();
    final failures = await _storage.failedAttempts();
    final until = await _storage.lockoutUntil();
    final spent = failures >= lockMaxAttempts;
    if (until != null && until.isAfter(now)) {
      emit(
        LockOutActive(
          lockoutUntil: until,
          method: state.method,
          enabled: state.enabled,
          locked: state.locked,
          biometricsEnabled: state.biometricsEnabled,
          lockAfterSeconds: state.lockAfterSeconds,
          attemptsRemaining: max(0, lockMaxAttempts - failures),
          signOutRequired: spent,
        ),
      );
      return false;
    }
    if (spent) {
      emit(_signOutRequired(until: until));
      return false;
    }
    if (await _storage.verifyPin(pin)) {
      if (failures > 0) await _storage.resetFailures();
      return true;
    }
    final last = failures + 1 >= lockMaxAttempts;
    final lockout = now.add(lockoutDuration);
    final count = await _storage.recordFailure(
      lockoutUntil: last ? lockout : null,
    );
    if (count >= lockMaxAttempts) {
      emit(_signOutRequired(until: lockout));
    } else {
      emit(
        LockPinWrong(
          attemptsRemaining: lockMaxAttempts - count,
          method: state.method,
          enabled: state.enabled,
          locked: state.locked,
          biometricsEnabled: state.biometricsEnabled,
          lockAfterSeconds: state.lockAfterSeconds,
        ),
      );
    }
    return false;
  }

  Future<LockState> _status({required bool locked}) async {
    final method = await _storage.method();
    final enabled = method != .none;
    final after = await _storage.lockAfterSeconds();
    final failures = await _storage.failedAttempts();
    final stored = await _storage.lockoutUntil();
    final until = stored != null && stored.isAfter(_now().toUtc())
        ? stored
        : null;
    if (method == .pin && failures >= lockMaxAttempts) {
      return LockSignOutRequired(
        lockoutUntil: until,
        method: method,
        lockAfterSeconds: after,
      );
    }
    return LockLoadSuccess(
      method: method,
      enabled: enabled,
      locked: enabled && locked,
      biometricsEnabled: method == .biometric,
      lockAfterSeconds: after,
      attemptsRemaining: max(0, lockMaxAttempts - failures),
      lockoutUntil: until,
    );
  }

  LockSignOutRequired _signOutRequired({DateTime? until}) =>
      LockSignOutRequired(
        lockoutUntil: until,
        method: .pin,
        lockAfterSeconds: state.lockAfterSeconds,
      );

  LockWriteInProgress _inProgress() => LockWriteInProgress(
    method: state.method,
    enabled: state.enabled,
    locked: state.locked,
    biometricsEnabled: state.biometricsEnabled,
    lockAfterSeconds: state.lockAfterSeconds,
    attemptsRemaining: state.attemptsRemaining,
    lockoutUntil: state.lockoutUntil,
    signOutRequired: state.signOutRequired,
  );

  LockWriteFailure _writeFailure(AppError error) => LockWriteFailure(
    error: error,
    method: state.method,
    enabled: state.enabled,
    locked: state.locked,
    biometricsEnabled: state.biometricsEnabled,
    lockAfterSeconds: state.lockAfterSeconds,
    attemptsRemaining: state.attemptsRemaining,
    lockoutUntil: state.lockoutUntil,
    signOutRequired: state.signOutRequired,
  );

  LockLoadFailure _loadFailure({bool locked = false}) => LockLoadFailure(
    error: AppError.unknown,
    method: state.method,
    enabled: state.enabled,
    locked: locked,
    biometricsEnabled: state.biometricsEnabled,
    lockAfterSeconds: state.lockAfterSeconds,
    attemptsRemaining: state.attemptsRemaining,
    lockoutUntil: state.lockoutUntil,
    signOutRequired: state.signOutRequired,
  );
}
