import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/widgets/ai_draft_frame.dart';
import 'package:tabibu/core/widgets/tabibu_bottom_sheet.dart';
import 'package:tabibu/core/widgets/tabibu_button.dart';
import 'package:tabibu/core/widgets/tabibu_text_field.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/data/region_read_client.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/l10n/l10n.dart';

/// Opens the region read sheet: an optional question, then the AI read in a
/// draft frame. The read is never saved and never copied anywhere; closing
/// the sheet discards it.
Future<void> showRegionReadSheet({
  required BuildContext context,
  required RegionReadClient client,
  required RegionCaptureController captureController,
  String stain = '',
  AnalyticsService? analytics,
}) {
  final l10n = context.l10n;
  return TabibuBottomSheet.show<void>(
    context,
    title: l10n.regionAskAction,
    builder: (_) => RegionReadSheetBody(
      client: client,
      captureController: captureController,
      stain: stain,
      analytics: analytics,
    ),
  );
}

@visibleForTesting
class RegionReadSheetBody extends StatefulWidget {
  const RegionReadSheetBody({
    required this.client,
    required this.captureController,
    this.stain = '',
    this.analytics,
    this.capture,
    super.key,
  });

  final RegionReadClient client;
  final RegionCaptureController captureController;
  final String stain;
  final AnalyticsService? analytics;

  /// Captures the region bytes. Tests inject bytes; production captures the
  /// boundary, which never completes under a test pump.
  final Future<Uint8List?> Function()? capture;

  @override
  State<RegionReadSheetBody> createState() => _RegionReadSheetBodyState();
}

enum _Phase { question, asking, result, error }

class _RegionReadSheetBodyState extends State<RegionReadSheetBody> {
  final _question = TextEditingController();
  _Phase _phase = .question;
  RegionReadResult? _result;

  AnalyticsService? _analyticsOrNull;

  AnalyticsService? get _analytics {
    final cached = _analyticsOrNull;
    if (cached != null) return cached;
    if (widget.analytics != null) return widget.analytics;
    if (getIt.isRegistered<AnalyticsService>()) {
      return _analyticsOrNull = getIt<AnalyticsService>();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_analytics?.logRegionRead(outcome: 'opened'));
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_phase == .asking) return;
    setState(() => _phase = .asking);
    final analytics = _analytics;
    try {
      // Drawing or encoding can throw. Outside this try the spinner stays.
      final capture = widget.capture;
      final bytes = await (capture != null
          ? capture()
          : widget.captureController.captureRegion());
      if (!mounted) return;
      if (bytes == null) {
        unawaited(_failed(analytics));
        return;
      }
      final result = await widget.client.readRegion(
        RegionReadRequest(
          imageBytes: bytes,
          question: RegionReadRequest.cleanQuestion(_question.text),
          stain: widget.stain,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = .result;
      });
      await analytics?.logRegionRead(outcome: 'shown');
    } on Object catch (_) {
      if (!mounted) return;
      unawaited(_failed(analytics));
    }
  }

  Future<void> _failed(AnalyticsService? analytics) async {
    setState(() => _phase = .error);
    await analytics?.logRegionRead(outcome: 'failed');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    switch (_phase) {
      case .question:
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            TabibuTextField(
              label: l10n.regionQuestionHint,
              controller: _question,
              maxLines: 3,
              maxLength: RegionReadRequest.maxQuestionLength,
              sanitizePaste: true,
              textInputAction: .go,
              onSubmitted: (_) => _ask(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TabibuButton.primary(label: l10n.regionAskSubmit, onTap: _ask),
          ],
        );
      case .asking:
        return const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        );
      case .result:
        final result = _result;
        if (result == null) return const SizedBox.shrink();
        return AiDraftFrame(
          label: l10n.workspaceAiDraft,
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
      case .error:
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text(l10n.regionFailed, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            TabibuButton.primary(label: l10n.commonRetry, onTap: _ask),
          ],
        );
    }
  }

  String _uncertainty(AppLocalizations l10n, RegionUncertainty value) {
    return switch (value) {
      .low => l10n.regionUncertaintyLow,
      .medium => l10n.regionUncertaintyMedium,
      .high => l10n.regionUncertaintyHigh,
    };
  }
}
