import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';
import 'package:tabibu/features/hybrid/presentation/hybrid_assist.dart';
import 'package:tabibu/features/hybrid/presentation/hybrid_copy.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('the badge names where a tidy ran, and nothing applies '
      'until Use this', (tester) async {
    final fake = FakeHybridAiService(
      result: const HybridResult(
        text: 'Headache for two days.',
        source: .inCloud,
      ),
    );
    final controller = TextEditingController(text: 'head ache 2 days');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      Column(
        children: [
          TextField(controller: controller),
          HybridAssist(
            task: .symptomTidy,
            controller: controller,
            online: true,
            writesBack: true,
            service: fake,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HybridCopy.tidyNotes));
    await tester.pumpAndSettle();

    expect(controller.text, 'head ache 2 days');
    expect(find.text('Headache for two days.'), findsOneWidget);
    expect(find.text(HybridCopy.inTheCloud), findsOneWidget);
    expect(fake.requests.single.mode, HybridMode.preferOnDevice);

    await tester.tap(find.text(HybridCopy.useThis));
    await tester.pumpAndSettle();

    expect(controller.text, 'Headache for two days.');
    expect(find.text(HybridCopy.inTheCloud), findsNothing);
  });

  testWidgets('an on-device summary is badged and never written back', (
    tester,
  ) async {
    final fake = FakeHybridAiService();
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .notesSummary,
        controller: controller,
        online: true,
        service: fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HybridCopy.summariseNotes));
    await tester.pumpAndSettle();

    expect(find.text(HybridCopy.onThisPhone), findsOneWidget);
    expect(find.text('- Headache\n- Two days\n- No fever'), findsOneWidget);

    await tester.tap(find.text(HybridCopy.useThis));
    await tester.pumpAndSettle();

    expect(controller.text, 'Headache for two days.');
    expect(fake.requests.single.mode, HybridMode.onlyOnDevice);
  });

  testWidgets('the tidy action hides in Kiswahili', (tester) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: FakeHybridAiService(),
      ),
      locale: const Locale('sw'),
    );
    await tester.pumpAndSettle();
    expect(find.text(HybridCopy.tidyNotes), findsNothing);
  });

  testWidgets('a switched-off tidy stays hidden', (tester) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .symptomTidy,
        controller: controller,
        online: true,
        writesBack: true,
        service: FakeHybridAiService(),
        settings: const HybridSettings(symptomTidyEnabled: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(HybridCopy.tidyNotes), findsNothing);
  });

  testWidgets('a summary hides offline when the model is unavailable', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Headache for two days.');
    addTearDown(controller.dispose);

    await tester.pumpApp(
      HybridAssist(
        task: .notesSummary,
        controller: controller,
        online: false,
        service: FakeHybridAiService(statusResult: .unavailable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(HybridCopy.summariseNotes), findsNothing);
    expect(find.text(HybridCopy.offline), findsOneWidget);
  });
}
