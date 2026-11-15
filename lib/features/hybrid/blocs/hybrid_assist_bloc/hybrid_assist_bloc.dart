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
    void Function(String task, String source)? logInference,
  }) : _hybrid = hybrid ?? getIt<HybridAiService>(),
       _settings = settings ?? const HybridSettings(),
       _logInference = logInference ?? _logFrom(analytics),
       super(HybridAssistState(task: task)) {
    on<HybridAssistContextChanged>(_onContext, transformer: restartable());
    on<HybridAssistGenerateRequested>(_onGenerate, transformer: droppable());
    on<HybridAssistProposalDismissed>(_onDismissed);
  }

  final HybridAiService _hybrid;
  final HybridSettings _settings;
  final void Function(String task, String source) _logInference;

  static void Function(String task, String source) _logFrom(
    AnalyticsService? analytics,
  ) {
    if (analytics == null) return (_, _) {};
    return (task, source) {
      unawaited(analytics.logHybridInference(task: task, source: source));
    };
  }

  var _text = '';
  var _englishLocale = true;
  var _online = true;
  HybridStatus? _status;

  Future<void> _onContext(
    HybridAssistContextChanged event,
    Emitter<HybridAssistState> emit,
  ) async {
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
    if (state.phase != .ready) return;
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
      _log(result.source);
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

  Future<HybridStatus> _readStatus() async {
    try {
      return await _hybrid.status();
    } on HybridAiException {
      return .unavailable;
    }
  }

  void _log(HybridSource source) {
    _logInference(state.task.wire, source.wire);
  }
}
