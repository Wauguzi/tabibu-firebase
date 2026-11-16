import 'package:equatable/equatable.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';

enum HybridAssistPhase { checking, hidden, ready, running, proposed, failed }

/// The proposal is held so the screen can show it. [toString] is only the
/// task and phase, so a log of the state never carries the text.
class HybridAssistState extends Equatable {
  const HybridAssistState({
    required this.task,
    this.phase = .checking,
    this.reason,
    this.proposal = '',
    this.source,
    this.failure,
  });

  final HybridTask task;
  final HybridAssistPhase phase;
  final HybridHiddenReason? reason;
  final String proposal;
  final HybridSource? source;
  final HybridFailure? failure;

  bool get showAction =>
      phase == .ready || phase == .running || phase == .failed;

  bool get showProposal => phase == .proposed && proposal.isNotEmpty;

  bool get showReason =>
      !showAction &&
      !showProposal &&
      (reason == .unavailable || reason == .offline);

  HybridAssistState copy({
    HybridAssistPhase? phase,
    HybridHiddenReason? reason,
    bool clearReason = false,
    String? proposal,
    HybridSource? source,
    bool clearSource = false,
    HybridFailure? failure,
    bool clearFailure = false,
  }) => HybridAssistState(
    task: task,
    phase: phase ?? this.phase,
    reason: clearReason ? null : reason ?? this.reason,
    proposal: proposal ?? this.proposal,
    source: clearSource ? null : source ?? this.source,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  @override
  List<Object?> get props => [task, phase, reason, proposal, source, failure];

  @override
  String toString() => 'HybridAssistState(${task.wire}, ${phase.name})';
}
