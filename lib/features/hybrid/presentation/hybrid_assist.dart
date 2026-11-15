import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_bloc.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_event.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_state.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The tidy or summary control under a notes field.
///
/// The tidy proposal stays in the AI frame until "Use this" writes it into
/// [controller]. A notes summary's button reads "Done" and only dismisses
/// the proposal: those notes are what the order stores, and the summary
/// can identify the patient.
class HybridAssist extends StatefulWidget {
  const HybridAssist({
    required this.task,
    required this.controller,
    required this.online,
    this.service,
    this.settings = const HybridSettings(),
    this.analytics,
    this.writesBack = false,
    super.key,
  });

  final HybridTask task;
  final TextEditingController controller;
  final bool online;
  final HybridAiService? service;
  final HybridSettings settings;
  final AnalyticsService? analytics;

  /// Patient tidy only. A notes summary must not enter the stored field.
  final bool writesBack;

  @override
  State<HybridAssist> createState() => _HybridAssistState();
}

class _HybridAssistState extends State<HybridAssist> {
  HybridAssistBloc? _bloc;

  @override
  void initState() {
    super.initState();
    final service = widget.service ?? _registeredService();
    if (service == null) return;
    _bloc = HybridAssistBloc(
      hybrid: service,
      task: widget.task,
      settings: widget.settings,
      analytics: widget.analytics ?? _registeredAnalytics(),
    );
    widget.controller.addListener(_publish);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publish();
    });
  }

  HybridAiService? _registeredService() {
    if (!getIt.isRegistered<HybridAiService>()) return null;
    return getIt<HybridAiService>();
  }

  AnalyticsService? _registeredAnalytics() {
    if (!getIt.isRegistered<AnalyticsService>()) return null;
    return getIt<AnalyticsService>();
  }

  @override
  void didUpdateWidget(HybridAssist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online != widget.online) _publish();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_publish);
    final bloc = _bloc;
    if (bloc != null) unawaited(bloc.close());
    super.dispose();
  }

  void _publish() {
    final bloc = _bloc;
    if (bloc == null || !mounted) return;
    bloc.add(
      HybridAssistContextChanged(
        text: widget.controller.text,
        englishLocale: Localizations.localeOf(context).languageCode != 'sw',
        online: widget.online,
      ),
    );
  }

  void _useThis(HybridAssistState state) {
    if (widget.writesBack && state.proposal.isNotEmpty) {
      widget.controller.text = state.proposal;
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
    _bloc?.add(const HybridAssistProposalDismissed());
  }

  @override
  Widget build(BuildContext context) {
    final bloc = _bloc;
    if (bloc == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return BlocBuilder<HybridAssistBloc, HybridAssistState>(
      bloc: bloc,
      builder: (context, state) {
        final reason = _reason(l10n, state);
        if (!state.showAction && !state.showProposal && reason == null) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            if (state.showAction) ...[
              const SizedBox(height: AppSpacing.sm),
              TabibuButton.ghost(
                label: widget.task == .symptomTidy
                    ? l10n.hybridTidyNotes
                    : l10n.hybridSummariseNotes,
                isLoading: state.phase == .running,
                onTap: state.phase == .running
                    ? null
                    : () => bloc.add(const HybridAssistGenerateRequested()),
              ),
            ],
            if (state.showProposal) ...[
              const SizedBox(height: AppSpacing.sm),
              AiDraftFrame(
                label: l10n.workspaceAiDraft,
                footer: Row(
                  children: [
                    StatusChip(
                      label: state.source == .inCloud
                          ? l10n.hybridInTheCloud
                          : l10n.hybridOnThisPhone,
                      tone: .aiDraft,
                    ),
                    const Spacer(),
                    TabibuButton.secondary(
                      label: widget.writesBack
                          ? l10n.hybridUseThis
                          : l10n.hybridDone,
                      minHeight: 48,
                      onTap: () => _useThis(state),
                    ),
                  ],
                ),
                child: Text(state.proposal),
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(reason, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        );
      },
    );
  }

  String? _reason(AppLocalizations l10n, HybridAssistState state) {
    if (state.phase == .failed) return l10n.hybridFailed;
    if (!state.showReason) return null;
    return switch (state.reason) {
      .unavailable => l10n.hybridUnavailable,
      .offline => l10n.hybridOffline,
      _ => null,
    };
  }
}
