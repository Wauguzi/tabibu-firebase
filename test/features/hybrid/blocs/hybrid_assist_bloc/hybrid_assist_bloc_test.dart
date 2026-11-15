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

const _ready = HybridAssistContextChanged(
  text: _notes,
  englishLocale: true,
  online: true,
);

void main() {
  late FakeHybridAiService fake;
  late _MockAnalytics analytics;

  setUp(() {
    fake = FakeHybridAiService();
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
