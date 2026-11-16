import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_event.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_state.dart';

/// One assist for a single field: tidy the patient's own words, or
/// summarise the doctor's notes on device only.
///
/// The field text is remembered only long enough to send, and never emitted.
class HybridAssistBloc extends Bloc<HybridAssistEvent, HybridAssistState> {
  HybridAssistBloc({
    required HybridTask task,
    HybridAiService? hybrid,
    HybridSettings? settings,
    AnalyticsService? analytics,
  }) : _hybrid = hybrid ?? getIt<HybridAiService>(),
       _settings = settings ?? const HybridSettings(),
       _analytics = analytics ?? getIt<AnalyticsService>(),
       super(HybridAssistState(task: task)) {
    on<HybridAssistContextChanged>(_onContext, transformer: restartable());
    // A refresh while one is reading adds nothing.
    on<HybridAssistStatusRefreshed>(_onRefresh, transformer: droppable());
    on<HybridAssistGenerateRequested>(_onGenerate, transformer: droppable());
    on<HybridAssistProposalDismissed>(_onDismissed);
  }

  final HybridAiService _hybrid;
  final HybridSettings _settings;
  final AnalyticsService _analytics;

  var _text = '';
  var _englishLocale = true;
  var _online = true;
  HybridStatus? _status;

  Future<void> _onContext(
    HybridAssistContextChanged event,
    Emitter<HybridAssistState> emit,
  ) async {
    // A cursor move or a selection reaches here too; it must not discard a
    // proposal the person is comparing with their own words.
    final unchanged =
        _status != null &&
        event.text == _text &&
        event.englishLocale == _englishLocale &&
        event.online == _online;
    if (unchanged) return;
    _text = event.text;
    _englishLocale = event.englishLocale;
    _online = event.online;
    _status ??= await _readStatus();
    if (state.phase == .running) return;
    emit(_settled());
  }

  Future<void> _onGenerate(
    HybridAssistGenerateRequested event,
    Emitter<HybridAssistState> emit,
  ) async {
    // A failed run can be tried again without editing the text.
    if (state.phase != .ready && state.phase != .failed) return;
    final offer = _offer();
    if (!offer.visible) {
      emit(_settled());
      return;
    }
    emit(
      state.copy(
        phase: .running,
        clearReason: true,
        proposal: '',
        clearSource: true,
        clearFailure: true,
      ),
    );
    final sent = _text;
    try {
      final result = await _hybrid.generate(
        HybridRequest(
          task: state.task,
          input: sent,
          mode: HybridMode.forTask(state.task),
          modelOption: _settings.modelOption,
          cloudModel: _settings.cloudModel,
        ),
      );
      if (sent != _text) {
        emit(_settled());
        return;
      }
      _logRun(result.source.wire);
      emit(
        state.copy(
          phase: .proposed,
          proposal: result.text,
          source: result.source,
          clearReason: true,
          clearFailure: true,
        ),
      );
    } on HybridAiException catch (error) {
      _logRun(error.failure.name);
      emit(
        state.copy(
          phase: .failed,
          failure: error.failure,
          proposal: '',
          clearSource: true,
          clearReason: true,
        ),
      );
    }
  }

  void _onDismissed(
    HybridAssistProposalDismissed event,
    Emitter<HybridAssistState> emit,
  ) {
    if (state.phase == .proposed) {
      unawaited(
        _analytics.logHybridProposal(
          task: state.task.wire,
          action: event.applied ? 'used' : 'dismissed',
        ),
      );
    }
    emit(_settled());
  }

  HybridAssistState _settled() {
    final offer = _offer();
    return state.copy(
      phase: offer.visible ? .ready : .hidden,
      reason: offer.reason,
      clearReason: offer.reason == null,
      proposal: '',
      clearSource: true,
      clearFailure: true,
    );
  }

  HybridOffer _offer() => decideHybridOffer(
    task: state.task,
    settings: _settings,
    status: _status ?? .unavailable,
    englishLocale: _englishLocale,
    online: _online,
    text: _text,
  );

  /// The model can become ready while the screen is open (a download ends,
  /// Apple Intelligence is switched on), so the status is read again.
  Future<void> _onRefresh(
    HybridAssistStatusRefreshed event,
    Emitter<HybridAssistState> emit,
  ) async {
    _status = await _readStatus();
    if (state.phase == .running || state.phase == .proposed) return;
    emit(_settled());
  }

  Future<HybridStatus> _readStatus() async {
    try {
      return await _hybrid.status(modelOption: _settings.modelOption);
    } on HybridAiException {
      return .unavailable;
    }
  }

  void _logRun(String outcome) {
    unawaited(
      _analytics.logHybridInference(task: state.task.wire, outcome: outcome),
    );
  }
}
