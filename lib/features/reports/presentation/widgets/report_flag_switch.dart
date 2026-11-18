import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';

/// A report flag with its switch on the right: critical finding, or
/// "Positive for …". [onChanged] null disables it. The row is the target,
/// so the switch is not a second one.
class ReportFlagSwitch extends StatelessWidget {
  const ReportFlagSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    void toggle() => onChanged?.call(!value);
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : toggle,
        child: Tappable(
          onTap: onChanged == null ? null : toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(fontWeight: .w500),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ExcludeSemantics(
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      materialTapTargetSize: .shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
