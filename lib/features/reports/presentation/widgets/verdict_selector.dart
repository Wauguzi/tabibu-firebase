import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';

/// One labelled row of mutually exclusive chips (Agree / Partly / …).
/// Nothing is preselected.
class VerdictSelector<T> extends StatelessWidget {
  const VerdictSelector({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.required = false,
    super.key,
  });

  final String label;
  final List<(T value, String text)> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  /// Required questions take the field asterisk. The comment does not.
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _QuestionLabel(label: label, required: required),
        const SizedBox(height: AppSpacing.xs),
        // A wrap puts Swahili and large text on a second line.
        SingleChildScrollView(
          scrollDirection: .horizontal,
          child: Row(
            children: [
              for (final (index, (value, text)) in options.indexed) ...[
                if (index > 0) const SizedBox(width: AppSpacing.sm),
                TabibuFilterChip(
                  label: text,
                  selected: selected == value,
                  onTap: selected == value ? null : () => onSelected(value),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Overall 1–5 score circles. Nothing is preselected.
class OverallScore extends StatelessWidget {
  const OverallScore({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.semanticLabelFor,
    this.required = false,
    super.key,
  });

  final int? value;
  final ValueChanged<int> onChanged;
  final String label;
  final String Function(int) semanticLabelFor;

  /// The field asterisk. Overall is required; the comment is not.
  final bool required;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = this.value;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _QuestionLabel(label: label, required: required),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                button: true,
                label: semanticLabelFor(i),
                onTap: () => onChanged(i),
                child: Tappable(
                  onTap: () => onChanged(i),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: value != null && i <= value
                              ? scheme.primary
                              : AppColors.transparent,
                          border: Border.all(
                            color: value != null && i <= value
                                ? scheme.primary
                                : scheme.outline,
                            width: 2,
                          ),
                        ),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: Text(
                              '$i',
                              style: textTheme.labelLarge?.copyWith(
                                color: value != null && i <= value
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                fontWeight: .w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The question title. Required questions take the same red asterisk as a
/// required field; the style is only the colour so it matches that mark.
class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel({required this.label, required this.required});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    if (!required) return Text(label, style: style);
    return Text.rich(
      TextSpan(
        text: label,
        style: style,
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}
