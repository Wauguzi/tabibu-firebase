import 'dart:async';

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/tappable.dart';

/// An error or info notification, shown near the top of the screen. It
/// enters with a fade-and-scale transition, dismisses on tap or after a few
/// seconds, and reverses the same transition on exit. The future completes
/// once it has gone.
///
/// It sits on the app's root overlay, not on a route: only the notice itself
/// takes a tap, so the screen under it keeps scrolling, and a navigator pop
/// can never close it in place of a screen.
Future<void> showTabibuNotification(
  BuildContext context, {
  required String message,
  required bool isError,
  required String dismissLabel,
  Duration duration = const Duration(seconds: 4),
}) {
  // A navigator's own context sits above its overlay: callers that show a
  // notice after popping their screen pass the root navigator's.
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true) ??
      Navigator.of(context, rootNavigator: true).overlay!;
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotificationHost(
      message: message,
      isError: isError,
      dismissLabel: dismissLabel,
      duration: duration,
      onGone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _NotificationHost extends StatefulWidget {
  const _NotificationHost({
    required this.message,
    required this.isError,
    required this.dismissLabel,
    required this.duration,
    required this.onGone,
  });

  final String message;
  final bool isError;
  final String dismissLabel;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<_NotificationHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  Timer? _timer;
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    _transition.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transition.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    await _transition.reverse();
    widget.onGone();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == .dark;
    // Align and SafeArea take no taps of their own: everything around the
    // notice reaches the screen below.
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FadeScaleTransition(
            animation: _transition,
            child: Semantics(
              label: widget.message,
              hint: widget.dismissLabel,
              button: true,
              liveRegion: true,
              onTap: _dismiss,
              excludeSemantics: true,
              child: Tappable(
                onTap: _dismiss,
                child: Material(
                  color: widget.isError
                      ? AppColors.errorLight
                      : isDark
                      ? AppColors.notificationInfoDark
                      : AppColors.notificationInfoLight,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      widget.message,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.white,
                      ),
                      textAlign: .center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
