import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/ai_draft_frame.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_sheet.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The Ask AI answer under the slide. A guide before the first ask; after
/// one, the read in the AI frame with what produced it behind the arrow.
/// Display only: it never saves, copies or reports anything.
class RegionReadPanel extends StatelessWidget {
  const RegionReadPanel({
    required this.answer,
    required this.model,
    required this.templateId,
    this.stain = '',
    super.key,
  });

  /// Null before the first ask; the workspace overwrites it on every ask.
  final RegionReadAnswer? answer;
  final String model;
  final String templateId;
  final String stain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answer = this.answer;
    if (answer == null) {
      return Text(
        l10n.regionReadGuide,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final result = answer.result;
    final detail = [
      model,
      templateId,
      if (stain.isNotEmpty) stain,
      if (answer.question.isNotEmpty) answer.question,
    ].join('\n');
    return AiDraftFrame(
      // Stable across answers, so a new read does not reopen a closed list.
      key: const PageStorageKey('region-read'),
      label: l10n.regionReadDraftLabel,
      detail: detail,
      initiallyExpanded: true,
      footer: Text(l10n.regionReadDisclaimer, style: textTheme.bodySmall),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(result.impression, style: textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.regionFeatures, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          for (final feature in result.features)
            Text('• $feature', style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${l10n.regionUncertainty}: '
            '${_uncertainty(l10n, result.uncertainty)}',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.regionCaveat, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(result.caveat, style: textTheme.bodyMedium),
        ],
      ),
    );
  }

  String _uncertainty(AppLocalizations l10n, RegionUncertainty value) {
    return switch (value) {
      .low => l10n.regionUncertaintyLow,
      .medium => l10n.regionUncertaintyMedium,
      .high => l10n.regionUncertaintyHigh,
    };
  }
}
