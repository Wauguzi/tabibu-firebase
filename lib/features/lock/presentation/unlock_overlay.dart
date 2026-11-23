import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide LockState;
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_bloc.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_event.dart';
import 'package:tabibu/features/lock/blocs/lock_bloc/lock_state.dart';
import 'package:tabibu/features/lock/presentation/widgets/pin_pad.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// Covers every route while the app is locked. Opaque so content behind it
/// never flashes. Fingerprint/face opens the phone's prompt, with the
/// phone's own passcode as the fallback. A PIN lock keeps the keypad.
class UnlockOverlay extends StatefulWidget {
  const UnlockOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<UnlockOverlay> createState() => _UnlockOverlayState();
}

class _UnlockOverlayState extends State<UnlockOverlay> {
  var _prompted = false;

  /// Once per lock, after the frame, so the prompt is not started during
  /// build and not before the method is known.
  void _schedulePrompt(LockState state) {
    if (_prompted || state is! LockLoadSuccess) return;
    if (state.method != .biometric || !state.locked) return;
    _prompted = true;
    final reason = context.l10n.appLockToOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LockBloc>().add(
        LockBiometricUnlockRequested(reason: reason),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LockBloc, LockState>(
      listenWhen: (previous, current) =>
          current.signOutRequired && !previous.signOutRequired,
      listener: (context, state) {
        // Five wrong PINs: wipe the session.
        context.read<AuthBloc>().add(const SignOutRequested());
      },
      builder: (context, state) {
        final locked = state.locked || state is LockLoadInProgress;
        if (!locked) _prompted = false;
        if (locked) _schedulePrompt(state);
        return Stack(
          fit: .expand,
          children: [
            widget.child,
            if (locked)
              Positioned.fill(
                child: Material(
                  // Solid cover: no transparency, no peek at the app.
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(child: _UnlockBody(state: state)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UnlockBody extends StatefulWidget {
  const _UnlockBody({required this.state});

  final LockState state;

  @override
  State<_UnlockBody> createState() => _UnlockBodyState();
}

class _UnlockBodyState extends State<_UnlockBody> {
  /// "Forgot PIN?" asks here, in the cover itself: a sheet on the app's
  /// navigator would open behind it, out of reach.
  var _forgot = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final tooMany = state.signOutRequired || state is LockSignOutRequired;
    final biometric = state.method == .biometric;
    final wrong = state is LockPinWrong ? state.attemptsRemaining : null;
    if (_forgot && !tooMany && !biometric) return _forgotBody(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xlg),
          AssetIcon(Assets.icons.shieldIcon, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            tooMany
                ? l10n.appLockTooMany
                : state is LockLoadFailure
                ? l10n.appLockLoadFailed
                : l10n.appLockToOpen,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: .center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tooMany
                ? l10n.appLockWait
                : state is LockLoadFailure
                ? l10n.appLockLoadFailedBody
                : biometric
                ? l10n.appLockUnlockFinger
                : l10n.appLockEnterPin,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: .center,
          ),
          const Spacer(),
          if (tooMany)
            TabibuButton.primary(
              label: l10n.appLockSignInAgain,
              onTap: () =>
                  context.read<AuthBloc>().add(const SignOutRequested()),
            )
          else if (state is LockLoadFailure) ...[
            TabibuButton.primary(
              label: l10n.commonRetry,
              onTap: () =>
                  context.read<LockBloc>().add(const LockStatusRequested()),
            ),
            const SizedBox(height: AppSpacing.sm),
            TabibuButton.secondary(
              label: l10n.appLockSignInAgain,
              onTap: () =>
                  context.read<AuthBloc>().add(const SignOutRequested()),
            ),
          ] else if (biometric)
            TabibuButton.primary(
              label: l10n.commonRetry,
              onTap: () => context.read<LockBloc>().add(
                LockBiometricUnlockRequested(reason: l10n.appLockToOpen),
              ),
            )
          else
            PinEntry(
              enabled: state is! LockWriteInProgress && state is! LockOutActive,
              hasError: wrong != null || state is LockPinWrong,
              errorLabel: wrong == null ? null : l10n.appLockWrongPin(wrong),
              onComplete: (pin) => context.read<LockBloc>().add(
                LockPinVerifyRequested(pin: pin),
              ),
            ),
          if (!tooMany && state is! LockLoadFailure && !biometric) ...[
            const SizedBox(height: AppSpacing.md),
            Tappable(
              onTap: () => setState(() => _forgot = true),
              semanticLabel: l10n.appLockForgot,
              child: Text(
                l10n.appLockForgot,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _forgotBody(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xlg),
          AssetIcon(Assets.icons.shieldIcon, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.appLockForgotTitle,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: .center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.appLockForgotBody,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: .center,
          ),
          const Spacer(),
          TabibuButton.primary(
            label: l10n.appLockSignInAgain,
            onTap: () => context.read<AuthBloc>().add(const SignOutRequested()),
          ),
          const SizedBox(height: AppSpacing.sm),
          TabibuButton.secondary(
            label: l10n.commonBack,
            onTap: () => setState(() => _forgot = false),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
