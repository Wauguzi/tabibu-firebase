import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(HybridAiService.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ChannelHybridAiService service() => ChannelHybridAiService(channel: channel);

  test('status maps the four channel values', () async {
    for (final pair in const [
      ('available', HybridStatus.available),
      ('downloadable', HybridStatus.downloadable),
      ('downloading', HybridStatus.downloading),
      ('something-else', HybridStatus.unavailable),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => pair.$1);
      expect(await service().status(), pair.$2);
    }
  });

  test(
    'a missing plugin is unsupported, so the web tidy does not run',
    () async {
      expect(await service().status(), HybridStatus.unsupported);
    },
  );

  test('status, download and warmUp send the model option', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'status' ? 'available' : null;
        });

    final hybrid = service();
    expect(await hybrid.status(modelOption: 'preview'), HybridStatus.available);
    await hybrid.download(modelOption: 'preview');
    await hybrid.warmUp(modelOption: 'preview');

    expect(calls.map((call) => call.method).toList(), [
      'status',
      'download',
      'warmUp',
    ]);
    for (final call in calls) {
      expect(call.arguments, {'modelOption': 'preview'});
    }
  });

  test('generate maps text and source and keeps the task id', () async {
    Map<Object?, Object?>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          args = call.arguments as Map<Object?, Object?>?;
          return {'text': 'Headache for two days.', 'source': 'in_cloud'};
        });

    final result = await service().generate(
      const HybridRequest(
        task: .symptomTidy,
        input: 'head ache',
        mode: .preferOnDevice,
        modelOption: 'stable',
        cloudModel: 'gemini-3.5-flash-lite',
      ),
    );

    expect(result.text, 'Headache for two days.');
    expect(result.source, HybridSource.inCloud);
    expect(args?['task'], 'symptom_tidy');
    expect(args?['mode'], 'PREFER_ON_DEVICE');
    expect(args?.containsKey('input'), isTrue);
  });

  test('channel errors become the failure enum and drop the message', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(
            code: 'busy',
            message: 'patient note that must not surface',
          ),
        );

    expect(
      () => service().generate(
        const HybridRequest(
          task: .notesSummary,
          input: 'notes',
          mode: .onlyOnDevice,
          modelOption: 'stable',
          cloudModel: 'gemini-3.5-flash-lite',
        ),
      ),
      throwsA(
        isA<HybridAiException>()
            .having((error) => error.failure, 'failure', HybridFailure.busy)
            .having(
              (error) => error.toString(),
              'toString',
              isNot(contains('patient note')),
            ),
      ),
    );
  });

  test('input past the token stand-in never reaches the channel', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return {'text': 'no', 'source': 'on_device'};
        });

    expect(
      () => service().generate(
        HybridRequest(
          task: .symptomTidy,
          input: 'a' * (hybridMaxInputChars + 1),
          mode: .preferOnDevice,
          modelOption: 'stable',
          cloudModel: 'gemini-3.5-flash-lite',
        ),
      ),
      throwsA(
        isA<HybridAiException>().having(
          (error) => error.failure,
          'failure',
          HybridFailure.tooLong,
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('an unset config keeps the hybrid defaults', () {
    const lookup = _UnsetLookup();
    final settings = HybridSettings.resolve(lookup);
    expect(settings.symptomTidyEnabled, isTrue);
    expect(settings.notesSummaryEnabled, isTrue);
    expect(settings.modelOption, 'stable');
    expect(settings.cloudModel, 'gemini-3.5-flash-lite');
  });

  test('preview is the only model option besides stable', () {
    final settings = HybridSettings.resolve(const _PreviewLookup());
    expect(settings.modelOption, 'preview');
    expect(settings.symptomTidyEnabled, isFalse);
  });

  group('contact details', () {
    HybridRequest request(HybridTask task, String input) => HybridRequest(
      task: task,
      input: input,
      mode: HybridMode.forTask(task),
      modelOption: 'stable',
      cloudModel: 'gemini-3.5-flash-lite',
    );

    test('a tidy leaves without phone numbers or email addresses', () {
      final wire = request(
        .symptomTidy,
        'Fever since Monday. Call 0712 345 678 or +254 733-123-456, '
        'office 020 1234567, or write to amina.otieno@example.com.',
      ).toMap();

      expect(
        wire['input'],
        'Fever since Monday. Call [PHONE] or [PHONE], '
        'office [PHONE], or write to [EMAIL].',
      );
    });

    test('symptom numbers that are not contact details stay', () {
      const text = 'Temperature 38.5 for 3 days, 2 tablets every 8 hours.';

      expect(request(.symptomTidy, text).toMap()['input'], text);
    });

    test(
      'a notes summary keeps its text, since it never leaves the device',
      () {
        const text = 'Seen with 0712 345 678 on file.';

        expect(request(.notesSummary, text).toMap()['input'], text);
      },
    );

    test('a zero-width or bidi character is removed from both tasks, '
        'and only a tidy loses its contacts', () {
      const dirty = 'Head\u200Bache\u202E. Call 0712 345 678.';

      expect(
        request(.symptomTidy, dirty).toMap()['input'],
        'Headache. Call [PHONE].',
      );
      expect(
        request(.notesSummary, dirty).toMap()['input'],
        'Headache. Call 0712 345 678.',
      );
    });
  });

  group('english heuristic', () {
    test('plain English passes', () {
      expect(looksLikeEnglish('Headache for two days'), isTrue);
    });

    test('a Swahili marker word does not', () {
      expect(looksLikeEnglish('Nina maumivu ya kichwa'), isFalse);
    });

    test('empty text and letters outside basic Latin do not', () {
      expect(looksLikeEnglish('   '), isFalse);
      expect(looksLikeEnglish('Café'), isFalse);
    });
  });

  group('when the action is offered', () {
    const english = 'Headache for two days, no fever.';

    test('a summary hides when the on-device model is unavailable', () {
      final offer = decideHybridOffer(
        task: .notesSummary,
        settings: const HybridSettings(),
        status: .unavailable,
        englishLocale: true,
        online: true,
        text: english,
      );
      expect(offer.visible, isFalse);
      expect(offer.reason, HybridHiddenReason.unavailable);
    });

    test('a tidy hides when offline and the model is unavailable', () {
      final offer = decideHybridOffer(
        task: .symptomTidy,
        settings: const HybridSettings(),
        status: .unavailable,
        englishLocale: true,
        online: false,
        text: english,
      );
      expect(offer.visible, isFalse);
      expect(offer.reason, HybridHiddenReason.offline);
    });

    test('a tidy stays when online even if the model is unavailable', () {
      final offer = decideHybridOffer(
        task: .symptomTidy,
        settings: const HybridSettings(),
        status: .downloadable,
        englishLocale: true,
        online: true,
        text: english,
      );
      expect(offer.visible, isTrue);
    });

    test('no bridge hides both tasks', () {
      for (final task in HybridTask.values) {
        final offer = decideHybridOffer(
          task: task,
          settings: const HybridSettings(),
          status: .unsupported,
          englishLocale: true,
          online: true,
          text: english,
        );
        expect(offer.visible, isFalse);
        expect(offer.reason, HybridHiddenReason.unsupported);
      }
    });

    test('a switched-off task and Kiswahili hide the action', () {
      expect(
        decideHybridOffer(
          task: .symptomTidy,
          settings: const HybridSettings(symptomTidyEnabled: false),
          status: .available,
          englishLocale: true,
          online: true,
          text: english,
        ).reason,
        HybridHiddenReason.switchedOff,
      );
      expect(
        decideHybridOffer(
          task: .notesSummary,
          settings: const HybridSettings(),
          status: .available,
          englishLocale: false,
          online: true,
          text: english,
        ).reason,
        HybridHiddenReason.kiswahili,
      );
    });
  });
}

class _UnsetLookup implements HybridConfigLookup {
  const _UnsetLookup();

  @override
  bool? optionalBool(String key) => null;

  @override
  String? optionalString(String key) => null;
}

class _PreviewLookup implements HybridConfigLookup {
  const _PreviewLookup();

  @override
  bool? optionalBool(String key) =>
      key == HybridSettings.symptomTidyKey ? false : null;

  @override
  String? optionalString(String key) =>
      key == HybridSettings.modelOptionKey ? 'preview' : null;
}
