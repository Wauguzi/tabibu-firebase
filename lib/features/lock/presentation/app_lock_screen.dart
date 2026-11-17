import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide LockState;
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/routing/app_routes.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_bloc.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/presentation/widgets/pin_pad.dart';
import 'package:tabibu/features/profile/presentation/widgets/settings_group.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// App lock settings: PIN on/off, biometrics, lock-after.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({required this.role, super.key});

  final Role role;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LockBloc>().add(const LockStatusRequested());
  }

  String _afterLabel(AppLocalizations l10n, int seconds) => switch (seconds) {
    0 => l10n.appLockDelayNow,
    60 => l10n.appLockDelayOne,
    300 => l10n.appLockDelayFive,
    900 => l10n.appLockDelayFifteen,
    _ => l10n.appLockAway('$seconds'),
  };

  Future<String?> _askPin(BuildContext context, {required String title}) {
    return TabibuBottomSheet.show<String>(
      context,
      title: title,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: PinEntry(onComplete: (pin) => Navigator.of(sheet).pop(pin)),
      ),
    );
  }

  Future<void> _openCreatePin() {
    return switch (widget.role) {
      .patient => const PatientCreatePinRoute().push<void>(context),
      .pathologist => const PathologistCreatePinRoute().push<void>(context),
      _ => const DoctorCreatePinRoute().push<void>(context),
    };
  }

  Future<void> _togglePin(LockState state) async {
    switch (state.method) {
      case .pin:
        final pin = await _askPin(context, title: context.l10n.appLockEnterPin);
        if (pin == null || !mounted) return;
        context.read<LockBloc>().add(LockDisableRequested(pin: pin));
      case .biometric:
        context.read<LockBloc>().add(
          LockBiometricReplaceRequested(reason: context.l10n.appLockToOpen),
        );
      case .none:
        await _openCreatePin();
    }
  }

  Future<void> _toggleBio(LockState state, {required bool enable}) async {
    final l10n = context.l10n;
    if (!enable) {
      context.read<LockBloc>().add(
        LockBiometricDisableRequested(reason: l10n.appLockToOpen),
      );
      return;
    }
    var pin = '';
    if (state.method == .pin) {
      final entered = await _askPin(context, title: l10n.appLockEnterPin);
      if (entered == null || entered.isEmpty || !mounted) return;
      pin = entered;
    }
    if (!mounted) return;
    context.read<LockBloc>().add(
      LockBiometricEnableRequested(reason: l10n.appLockToOpen, pin: pin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<LockBloc>().state;
    return BlocListener<LockBloc, LockState>(
      listenWhen: (_, current) =>
          current is LockBiometricUnavailable ||
          current is LockPinWrong ||
          current is LockWriteFailure ||
          current is LockDisableSuccess ||
          current is LockPinCreateAllowed,
      listener: (context, state) {
        if (state is LockPinCreateAllowed) {
          unawaited(_openCreatePin());
          return;
        }
        final message = switch (state) {
          LockBiometricUnavailable() => l10n.appLockNoBioShort,
          LockPinWrong(:final attemptsRemaining) => l10n.appLockWrongPin(
            attemptsRemaining,
          ),
          LockWriteFailure(:final error) => error?.description(l10n),
          LockDisableSuccess() => l10n.appLockOff,
          _ => null,
        };
        if (message == null) return;
        unawaited(
          showTabibuNotification(
            context,
            message: message,
            isError:
                state is LockPinWrong ||
                state is LockWriteFailure ||
                state is LockBiometricUnavailable,
            dismissLabel: l10n.commonDismiss,
          ),
        );
      },
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenMargin,
                  AppSpacing.md,
                  AppSpacing.screenMargin,
                  AppSpacing.md,
                ),
                sliver: SliverList.list(
                  children: [
                    TopBar(
                      title: l10n.appLockTitle,
                      backLabel: l10n.commonBack,
                      onBack: context.pop,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsGroup(
                      title: l10n.appLockLockWith,
                      children: [
                        SettingsSwitchRow(
                          icon: Assets.icons.shieldIcon,
                          title: l10n.appLockPin,
                          value: state.method == .pin,
                          onChanged: state.locked
                              ? null
                              : (_) => unawaited(_togglePin(state)),
                        ),
                        // The browser has no biometric prompt: a line, not
                        // a switch that can never turn on.
                        if (kIsWeb)
                          SettingsRow(
                            icon: Assets.icons.fingerprintIcon,
                            title: l10n.appLockBio,
                            supporting: l10n.appLockWebBiometrics,
                            chevron: false,
                          )
                        else
                          SettingsSwitchRow(
                            icon: Assets.icons.fingerprintIcon,
                            title: l10n.appLockBio,
                            value: state.method == .biometric,
                            onChanged: state.locked
                                ? null
                                : (value) => unawaited(
                                    _toggleBio(state, enable: value),
                                  ),
                          ),
                      ],
                    ),
                    if (state.enabled) ...[
                      const SizedBox(height: AppSpacing.md),
                      SettingsGroup(
                        title: l10n.appLockWhen,
                        children: [
                          SettingsRow(
                            icon: Assets.icons.clockIcon,
                            title: l10n.appLockAfter,
                            supporting: _afterLabel(
                              l10n,
                              state.lockAfterSeconds,
                            ),
                            onTap: () => unawaited(switch (widget.role) {
                              .patient =>
                                const PatientLockAfterRoute().push<void>(
                                  context,
                                ),
                              .pathologist =>
                                const PathologistLockAfterRoute().push<void>(
                                  context,
                                ),
                              _ => const DoctorLockAfterRoute().push<void>(
                                context,
                              ),
                            }),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.appLockStaysOnPhone,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
