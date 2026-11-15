import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_bloc.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_event.dart';
import 'package:tabibu/features/hybrid/blocs/hybrid_assist_bloc/hybrid_assist_state.dart';

const _notes = 'Headache for two days, no fever.';

void main() {
  late FakeHybridAiService fake;
  late List<(String, String)> logged;

  setUp(() {
    fake = FakeHybridAiService();
    logged = [];
  });

  blocTest<HybridAssistBloc, HybridAssistState>(
    'notes summary never asks for the cloud',
    build: () => HybridAssistBloc(
      hybrid: fake,
      task: .notesSummary,
      logInference: (task, source) => logged.add((task, source)),
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
      expect(logged, [('notes_summary', 'on_device')]);
    },
  );

  blocTest<HybridAssistBloc, HybridAssistState>(
    'a summary hides when the model is unavailable',
    build: () => HybridAssistBloc(
      hybrid: FakeHybridAiService(statusResult: .unavailable),
      task: .notesSummary,
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
    build: () => HybridAssistBloc(hybrid: fake, task: .symptomTidy),
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
    'a failed generate does not log an inference',
    build: () {
      fake.error = const HybridAiException(.busy);
      return HybridAssistBloc(
        hybrid: fake,
        task: .symptomTidy,
        logInference: (task, source) => logged.add((task, source)),
      );
    },
    act: (bloc) async {
      bloc.add(
        const HybridAssistContextChanged(
          text: _notes,
          englishLocale: true,
          online: true,
        ),
      );
      await bloc.stream.firstWhere((state) => state.showAction);
      bloc.add(const HybridAssistGenerateRequested());
    },
    verify: (bloc) {
      expect(bloc.state.failure, HybridFailure.busy);
      expect(logged, isEmpty);
    },
  );
}
