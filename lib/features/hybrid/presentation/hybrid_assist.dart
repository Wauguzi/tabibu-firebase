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
    this.settings,
    this.analytics,
    this.writesBack = false,
    super.key,
  });

  final HybridTask task;
  final TextEditingController controller;
  final bool online;
  final HybridAiService? service;

  /// Read from Remote Config when null.
  final HybridSettings? settings;
  final AnalyticsService? analytics;

  /// Patient tidy only. A notes summary must not enter the stored field.
  final bool writesBack;

  @override
  State<HybridAssist> createState() => _HybridAssistState();
}

class _HybridAssistState extends State<HybridAssist>
    with WidgetsBindingObserver {
  HybridAssistBloc? _bloc;

  @override
  void initState() {
    super.initState();
    final service = widget.service ?? _registeredService();
    if (service == null) return;
    _bloc = HybridAssistBloc(
      hybrid: service,
      task: widget.task,
      settings: widget.settings ?? HybridSettings.resolve(_registeredLookup()),
      analytics: widget.analytics,
    );
    // The model can become ready while this screen is open.
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_publish);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != .resumed) return;
    _bloc?.add(const HybridAssistStatusRefreshed());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first context, and every locale change after it.
    _publish();
  }

  HybridAiService? _registeredService() {
    if (!getIt.isRegistered<HybridAiService>()) return null;
    return getIt<HybridAiService>();
  }

  HybridConfigLookup? _registeredLookup() {
    if (!getIt.isRegistered<HybridConfigLookup>()) return null;
    return getIt<HybridConfigLookup>();
  }

  @override
  void didUpdateWidget(HybridAssist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_publish);
      widget.controller.addListener(_publish);
      _publish();
    } else if (oldWidget.online != widget.online) {
      _publish();
    }
  }

  @override
  void dispose() {
    if (_bloc != null) WidgetsBinding.instance.removeObserver(this);
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
    final applies = widget.writesBack && state.proposal.isNotEmpty;
    // Before the write: the field's listener settles the bloc.
    _bloc?.add(HybridAssistProposalDismissed(applied: applies));
    if (applies) {
      widget.controller.text = state.proposal;
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
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
