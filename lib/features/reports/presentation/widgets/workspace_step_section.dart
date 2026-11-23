import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/gen/assets.gen.dart';

/// Where a reporting step sits. The screen decides which step is open.
enum WorkspaceStepStatus { waiting, toDo, done }

/// One collapsible step: a numbered heading, its state, and an arrow.
///
/// [locked] keeps the body shut. The reason sits on the heading, because this
/// widget holds no state of its own and a tap must not open the step.
class WorkspaceStepSection extends StatelessWidget {
  const WorkspaceStepSection({
    required this.number,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.locked = false,
    this.lockedReason,
    super.key,
  });

  final int number;
  final String title;
  final WorkspaceStepStatus status;
  final String statusLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final bool locked;

  /// Why the step stays shut, already localized.
  final String? lockedReason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final open = expanded && !locked;
    final reason = locked ? lockedReason : null;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            button: true,
            enabled: !locked,
            expanded: open,
            onTap: locked ? null : onToggle,
            child: Tappable(
              onTap: locked ? null : onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            '$number · $title',
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: .w500,
                              color: locked ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          _StatusLine(status: status, label: statusLabel),
                          if (reason != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              reason,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: ExcludeSemantics(
                        child: AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: AssetIcon(
                            Assets.icons.dropDownIcon,
                            size: 22,
                            scaleUp: false,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) ...[const SizedBox(height: AppSpacing.sm), child],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.label});

  final WorkspaceStepStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Words only: a finished step's check sits on its own summary, once.
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
