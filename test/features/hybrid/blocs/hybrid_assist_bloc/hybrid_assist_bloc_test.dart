import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_bloc.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_event.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_state.dart';

const _notes = 'Headache for two days, no fever.';

class _MockAnalytics extends Mock implements AnalyticsService {}

class _HeldHybrid extends FakeHybridAiService {
  final gate = Completer<void>();

  @override
  Future<HybridResult> generate(HybridRequest request) async {
    requests.add(request);
    await gate.future;
    return const HybridResult(
      text: '- Headache\n- Two days\n- No fever',
      source: .onDevice,
    );
  }
}

const _ready = HybridAssistContextChanged(
  text: _notes,
  englishLocale: true,
  online: true,
);

void main() {
  late FakeHybridAiService fake;
  late _HeldHybrid held;
  late _MockAnalytics analytics;

  setUp(() {
    fake = FakeHybridAiService();
    held = _HeldHybrid();
    analytics = _MockAnalytics();
    when(
      () => analytics.logHybridInference(
        task: any(named: 'task'),
        outcome: any(named: 'outcome'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => analytics.logHybridProposal(
        task: any(named: 'task'),
        action: any(named: 'action'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<void> generateWhenReady(HybridAssistBloc bloc) async {
    bloc.add(_ready);
    await bloc.stream.firstWhere((state) => state.showAction);
    bloc.add(const HybridAssistGenerateRequested());
  }

  blocTest<HybridAssistBloc, HybridAssistState>(
    'notes summary never asks for the cloud',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .notesSummary,
      analytics: analytics,
    ),
    act: (bloc) async {
      bloc.add(
        const HybridAssistContextChanged(
          text: _notes,
          englishLocale: true,
          online: false,
        ),
      );
      await bloc.stream.firstWhere((state) => state.showAction);
      bloc.add(const HybridAssistGenerateRequested());
    },
    expect: () => [
      const HybridAssistState(task: .notesSummary, phase: .ready),
      const HybridAssistState(task: .notesSummary, phase: .running),
      const HybridAssistState(
        task: .notesSummary,
        phase: .proposed,
        proposal: '- Headache\n- Two days\n- No fever',
        source: .onDevice,
      ),
    ],
    verify: (_) {
      expect(fake.requests.single.mode, HybridMode.onlyOnDevice);
      expect(fake.requests.single.task, HybridTask.notesSummary);
      verify(
        () => analytics.logHybridInference(
          task: 'notes_summary',
          outcome: 'on_device',
        ),
      ).called(1);
    },
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a summary hides when the model is unavailable',
    build: () => HybridAssistBloc(
      hybrid: FakeHybridAiService(statusResult: .unavailable),
      task: .notesSummary,
      analytics: analytics,
    ),
    act: (bloc) => bloc.add(
      const HybridAssistContextChanged(
        text: _notes,
        englishLocale: true,
        online: true,
      ),
    ),
    expect: () => [
      const HybridAssistState(
        task: .notesSummary,
        phase: .hidden,
        reason: .unavailable,
      ),
    ],
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a tidy hides offline when the model is unavailable',
    build: () => HybridAssistBloc(
      hybrid: FakeHybridAiService(statusResult: .unavailable),
      task: .symptomTidy,
      analytics: analytics,
    ),
    act: (bloc) => bloc.add(
      const HybridAssistContextChanged(
        text: _notes,
        englishLocale: true,
        online: false,
      ),
    ),
    expect: () => [
      const HybridAssistState(
        task: .symptomTidy,
        phase: .hidden,
        reason: .offline,
      ),
    ],
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a switched-off tidy stays hidden',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .symptomTidy,
      settings: const HybridSettings(symptomTidyEnabled: false),
      analytics: analytics,
    ),
    act: (bloc) => bloc.add(
      const HybridAssistContextChanged(
        text: _notes,
        englishLocale: true,
        online: true,
      ),
    ),
    expect: () => [
      const HybridAssistState(
        task: .symptomTidy,
        phase: .hidden,
        reason: .switchedOff,
      ),
    ],
    verify: (_) => expect(fake.requests, isEmpty),
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'Kiswahili hides the action',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .symptomTidy,
      analytics: analytics,
    ),
    act: (bloc) => bloc.add(
      const HybridAssistContextChanged(
        text: _notes,
        englishLocale: false,
        online: true,
      ),
    ),
    expect: () => [
      const HybridAssistState(
        task: .symptomTidy,
        phase: .hidden,
        reason: .kiswahili,
      ),
    ],
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a failed generate logs its failure and can be tried again',
    build: () {
      fake.error = const HybridAiException(.busy);
      return HybridAssistBloc(
        hybrid: fake,
        task: .symptomTidy,
        analytics: analytics,
      );
    },
    act: (bloc) async {
      await generateWhenReady(bloc);
      await bloc.stream.firstWhere((state) => state.phase == .failed);
      fake.error = null;
      bloc.add(const HybridAssistGenerateRequested());
    },
    verify: (bloc) {
      expect(bloc.state.phase, HybridAssistPhase.proposed);
      expect(fake.requests, hasLength(2));
      verify(
        () =>
            analytics.logHybridInference(task: 'symptom_tidy', outcome: 'busy'),
      ).called(1);
      verify(
        () => analytics.logHybridInference(
          task: 'symptom_tidy',
          outcome: 'on_device',
        ),
      ).called(1);
    },
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a selection change keeps a shown proposal',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .symptomTidy,
      analytics: analytics,
    ),
    act: (bloc) async {
      await generateWhenReady(bloc);
      await bloc.stream.firstWhere((state) => state.showProposal);
      bloc.add(_ready);
    },
    skip: 2,
    expect: () => [
      const HybridAssistState(
        task: .symptomTidy,
        phase: .proposed,
        proposal: 'Headache for two days.',
        source: .onDevice,
      ),
    ],
    verify: (bloc) {
      expect(bloc.state.phase, HybridAssistPhase.proposed);
      expect(bloc.state.proposal, 'Headache for two days.');
    },
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a refresh shows the summary once the model is available',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .notesSummary,
      settings: const HybridSettings(modelOption: 'preview'),
      analytics: analytics,
    ),
    act: (bloc) async {
      fake.statusResult = .unavailable;
      bloc.add(_ready);
      await bloc.stream.firstWhere((state) => state.phase == .hidden);
      fake.statusResult = .available;
      bloc.add(const HybridAssistStatusRefreshed());
    },
    expect: () => [
      const HybridAssistState(
        task: .notesSummary,
        phase: .hidden,
        reason: .unavailable,
      ),
      const HybridAssistState(task: .notesSummary, phase: .ready),
    ],
    verify: (_) => expect(fake.statusOptions, ['preview', 'preview']),
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a refresh leaves a running assist as it is',
    build: () => HybridAssistBloc(
      hybrid: held,
      task: .notesSummary,
      analytics: analytics,
    ),
    act: (bloc) async {
      bloc.add(_ready);
      await bloc.stream.firstWhere((state) => state.showAction);
      bloc.add(const HybridAssistGenerateRequested());
      await bloc.stream.firstWhere((state) => state.phase == .running);
      held.statusResult = .unavailable;
      bloc.add(const HybridAssistStatusRefreshed());
      while (held.statusOptions.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      held.gate.complete();
      await bloc.stream.firstWhere((state) => state.phase == .proposed);
    },
    expect: () => [
      const HybridAssistState(task: .notesSummary, phase: .ready),
      const HybridAssistState(task: .notesSummary, phase: .running),
      const HybridAssistState(
        task: .notesSummary,
        phase: .proposed,
        proposal: '- Headache\n- Two days\n- No fever',
        source: .onDevice,
      ),
    ],
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a refresh leaves a proposal in place',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .notesSummary,
      analytics: analytics,
    ),
    act: (bloc) async {
      await generateWhenReady(bloc);
      await bloc.stream.firstWhere((state) => state.showProposal);
      fake.statusResult = .unavailable;
      bloc.add(const HybridAssistStatusRefreshed());
      while (fake.statusOptions.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
    },
    skip: 2,
    expect: () => [
      const HybridAssistState(
        task: .notesSummary,
        phase: .proposed,
        proposal: '- Headache\n- Two days\n- No fever',
        source: .onDevice,
      ),
    ],
    verify: (bloc) => expect(bloc.state.showProposal, isTrue),
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a used tidy logs once, and a dismiss with nothing shown logs nothing',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .symptomTidy,
      analytics: analytics,
    ),
    act: (bloc) async {
      await generateWhenReady(bloc);
      await bloc.stream.firstWhere((state) => state.showProposal);
      bloc.add(const HybridAssistProposalDismissed(applied: true));
      await bloc.stream.firstWhere((state) => state.phase == .ready);
      bloc.add(const HybridAssistProposalDismissed());
    },
    verify: (_) {
      verify(
        () => analytics.logHybridProposal(task: 'symptom_tidy', action: 'used'),
      ).called(1);
      verifyNever(
        () => analytics.logHybridProposal(
          task: any(named: 'task'),
          action: 'dismissed',
        ),
      );
    },
  );
}
