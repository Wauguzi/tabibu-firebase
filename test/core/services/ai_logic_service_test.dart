import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';

class _MockLogger extends Mock implements Logger {}

// RIFF-headed bytes, like a TTS response.
Uint8List _wav(List<int> body) =>
    Uint8List.fromList([0x52, 0x49, 0x46, 0x46, ...body]);

class _Config implements AiLogicConfig {
  _Config([this.values = const {}]);

  final Map<String, Object> values;

  @override
  bool? optionalBool(String key) {
    final value = values[key];
    return value is bool ? value : null;
  }

  @override
  String? optionalString(String key) {
    final value = values[key];
    return value is String ? value : null;
  }
}

class ClientException implements Exception {}

void main() {
  test('the template response becomes a transcript', () async {
    TemplateRequest? sent;
    final service = FirebaseAiLogicService(
      config: _Config(),
      transcribe: (request) async {
        sent = request;
        return jsonEncode({
          'transcript': '  Fever since yesterday  ',
          'language': 'en',
          'unclear': false,
          'extra': 'ignored',
        });
      },
    );

    final spoken = await service.transcribeSymptoms(
      Uint8List.fromList([9, 8, 7]),
      mimeType: 'audio/wav',
    );

    expect(spoken.transcript, 'Fever since yesterday');
    expect(spoken.language, 'en');
    expect(sent!.templateId, AiLogicService.defaultTemplateId);
    expect(sent!.location, AiLogicService.defaultLocation);
    expect(sent!.limitedUseTokens, isFalse);
    expect(base64Decode(sent!.inputs['audioData']! as String), [9, 8, 7]);
    expect(sent!.inputs['audioMime'], 'audio/wav');
  });

  test(
    'a configured template id and limited-use flag are what is sent',
    () async {
      TemplateRequest? sent;
      final service = FirebaseAiLogicService(
        config: _Config({
          AiLogicService.templateKey: 'symptom-transcribe-v9',
          AiLogicService.locationKey: 'europe-west1',
          AiLogicService.limitedUseKey: true,
        }),
        transcribe: (request) async {
          sent = request;
          return '{"transcript":"Cough","language":"sw","unclear":false}';
        },
      );

      final spoken = await service.transcribeSymptoms(
        Uint8List.fromList([1]),
        mimeType: 'audio/wav',
      );

      expect(spoken.language, 'sw');
      expect(sent!.templateId, 'symptom-transcribe-v9');
      expect(sent!.location, 'europe-west1');
      expect(sent!.limitedUseTokens, isTrue);
    },
  );

  test('bad JSON and an empty transcript fail closed', () {
    expect(() => parseSymptomTranscript('not json'), throwsA(AppError.unknown));
    expect(
      () => parseSymptomTranscript(
        '{"transcript":"","language":"en","unclear":true}',
      ),
      throwsA(AppError.unknown),
    );
    expect(
      () => parseSymptomTranscript(
        '{"transcript":"   ","language":"en","unclear":false}',
      ),
      throwsA(AppError.unknown),
    );
    expect(() => parseSymptomTranscript('[]'), throwsA(AppError.unknown));
    expect(
      () => parseSymptomTranscript(
        '{"transcript":"Hi","language":"en","unclear":"no"}',
      ),
      throwsA(AppError.unknown),
    );
    expect(
      () => parseSymptomTranscript(
        '{"transcript":"maybe a cough","language":"en","unclear":true}',
      ),
      throwsA(AppError.unknown),
    );
  });

  test('a recognised language label cannot drop the words', () {
    final spoken = parseSymptomTranscript(
      '{"transcript":"Nina homa","language":"Kiswahili","unclear":false}',
    );
    expect(spoken.transcript, 'Nina homa');
    expect(spoken.language, 'sw');
  });

  test('an SDK failure carries no transcript', () async {
    final service = FirebaseAiLogicService(
      config: _Config(),
      transcribe: (_) async =>
          throw FirebaseAIException('blocked: patient said a phone number'),
    );

    final error = await service
        .transcribeSymptoms(Uint8List.fromList([1]), mimeType: 'audio/wav')
        .then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, AppError.serviceUnavailable);
    expect('$error'.contains('phone'), isFalse);
  });

  test('transcribe keeps no reference to the audio after a call', () async {
    final sentAudio = <String>[];
    final service = FirebaseAiLogicService(
      config: _Config(),
      transcribe: (request) async {
        sentAudio.add(request.inputs['audioData']! as String);
        return '{"transcript":"Cough","language":"en","unclear":false}';
      },
    );

    await service.transcribeSymptoms(
      Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/wav',
    );
    await service.transcribeSymptoms(
      Uint8List.fromList([4, 5]),
      mimeType: 'audio/wav',
    );

    // Each call sends only its own audio, exactly once: nothing from the
    // first call survives into the second (T-24).
    expect(sentAudio.map(base64Decode).toList(), [
      [1, 2, 3],
      [4, 5],
    ]);
  });

  test(
    'a socket failure is offline and a renamed transport failure is unknown',
    () {
      expect(
        aiLogicFailure(const SocketException('failed host')),
        AppError.noInternet,
      );
      // The name matches the HTTP client, and a release build would rename it.
      expect(aiLogicFailure(ClientException()), AppError.unknown);
      expect(
        aiLogicFailure(FirebaseAISdkException('could not parse')),
        AppError.serviceUnavailable,
      );
    },
  );

  test('the fake keeps the length, not the bytes', () async {
    final fake = FakeAiLogicService(
      result: const SymptomTranscript(transcript: 'Cough', language: 'en'),
    );
    await fake.transcribeSymptoms(
      Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'audio/wav',
    );
    expect(fake.calls, [(byteLength: 4, mimeType: 'audio/wav')]);
  });

  test('a region read sends the template id, settings and pixels', () async {
    TemplateRequest? sent;
    final service = FirebaseAiLogicService(
      config: _Config({
        'ai_template_slide_region': 'custom-region-v9',
        'ai_location': 'europe-west1',
        'ai_limited_use_tokens': true,
      }),
      readRegionCall: (request) async {
        sent = request;
        return '{"impression":"Calm."}';
      },
    );

    final json = await service.readRegion(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageMime: 'image/png',
      question: 'Malignant?',
      stain: 'H&E',
    );

    expect(json, {'impression': 'Calm.'});
    expect(sent!.templateId, 'custom-region-v9');
    expect(sent!.location, 'europe-west1');
    expect(sent!.limitedUseTokens, isTrue);
    expect(sent!.inputs, {
      'imageMime': 'image/png',
      // cspell:disable-next-line
      'imageData': 'AQID',
      'question': 'Malignant?',
      'stain': 'H&E',
    });
    // Pixels and short text only: no case id, uid, name or order number.
    expect(sent!.inputs.keys.toSet(), {
      'imageMime',
      'imageData',
      'question',
      'stain',
    });
  });

  test('a region read omits an empty question and stain', () async {
    TemplateRequest? sent;
    final service = FirebaseAiLogicService(
      config: _Config(),
      readRegionCall: (request) async {
        sent = request;
        return '{}';
      },
    );

    await service.readRegion(
      imageBytes: Uint8List.fromList([1]),
      imageMime: 'image/png',
    );

    expect(sent!.templateId, AiLogicService.defaultRegionTemplateId);
    expect(sent!.inputs.keys.toSet(), {'imageMime', 'imageData'});
  });

  test('bad region JSON and empty images fail closed', () async {
    final service = FirebaseAiLogicService(
      config: _Config(),
      readRegionCall: (_) async => 'not json',
    );

    await expectLater(
      service.readRegion(
        imageBytes: Uint8List.fromList([1]),
        imageMime: 'image/png',
      ),
      throwsA(AppError.unknown),
    );
    await expectLater(
      service.readRegion(
        imageBytes: Uint8List.fromList([]),
        imageMime: 'image/png',
      ),
      throwsA(AppError.unknown),
    );
    await expectLater(
      service.readRegion(imageBytes: Uint8List.fromList([1]), imageMime: '  '),
      throwsA(AppError.unknown),
    );
    expect(() => parseRegionJson('[]'), throwsA(AppError.unknown));
    expect(() => parseRegionJson('  '), throwsA(AppError.unknown));
  });

  test('a region failure carries no question', () async {
    final service = FirebaseAiLogicService(
      config: _Config(),
      readRegionCall: (_) async =>
          throw FirebaseAIException('blocked: is it malignant?'),
    );

    final error = await service
        .readRegion(
          imageBytes: Uint8List.fromList([1]),
          imageMime: 'image/png',
          question: 'is it malignant?',
        )
        .then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, AppError.serviceUnavailable);
    expect('$error'.contains('malignant'), isFalse);
  });

  test('narration sends the text verbatim with voice and model', () async {
    SpeakRequest? sent;
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (request) async {
        sent = request;
        return _wav([7, 7]);
      },
    );

    final bytes = await service.speakExplanation(
      text: '  Your test found no cancer.  ',
      languageCode: 'en-US',
      voice: 'Achernar',
      model: 'gemini-3.8-flash-tts',
    );

    expect(bytes, _wav([7, 7]));
    expect(sent!.text, '  Your test found no cancer.  ');
    expect(sent!.languageCode, 'en-US');
    expect(sent!.voice, 'Achernar');
    expect(sent!.model, 'gemini-3.8-flash-tts');
    expect(sent!.location, 'global');
    expect(sent!.limitedUseTokens, isFalse);
  });

  test('a Swahili narration sends sw verbatim with voice and model', () async {
    SpeakRequest? sent;
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (request) async {
        sent = request;
        return _wav([9]);
      },
    );

    final bytes = await service.speakExplanation(
      text: 'Habari.',
      languageCode: 'sw',
      voice: 'Achernar',
      model: 'gemini-3.8-flash-tts',
    );

    expect(bytes, _wav([9]));
    expect(sent!.text, 'Habari.');
    expect(sent!.languageCode, 'sw');
    expect(sent!.voice, 'Achernar');
    expect(sent!.model, 'gemini-3.8-flash-tts');
  });

  test('blank narration inputs and empty audio fail closed', () async {
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (_) async => Uint8List(0),
      logger: _MockLogger(),
    );

    await expectLater(
      service.speakExplanation(
        text: 'Hi',
        languageCode: 'en-US',
        voice: 'Achernar',
        model: 'gemini-3.8-flash-tts',
      ),
      throwsA(AppError.unknown),
    );
    await expectLater(
      service.speakExplanation(
        text: '   ',
        languageCode: 'en-US',
        voice: 'Achernar',
        model: 'gemini-3.8-flash-tts',
      ),
      throwsA(AppError.unknown),
    );
  });

  test('a non-WAV response fails closed', () async {
    final logger = _MockLogger();
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (_) async => Uint8List.fromList([1, 2, 3, 4]),
      logger: logger,
    );

    await expectLater(
      service.speakExplanation(
        text: 'Hi',
        languageCode: 'en-US',
        voice: 'Achernar',
        model: 'gemini-3.8-flash-tts',
      ),
      throwsA(AppError.unknown),
    );

    final messages = verify(() => logger.e(captureAny<String>())).captured;
    final logged = messages.join(' ');
    expect(logged, contains('non-WAV'));
  });

  group('isWavAudio', () {
    test('accepts RIFF bytes', () {
      expect(isWavAudio(_wav([1])), isTrue);
    });

    test('rejects short and non-RIFF bytes', () {
      expect(isWavAudio(Uint8List(0)), isFalse);
      expect(isWavAudio(Uint8List.fromList([1, 2, 3])), isFalse);
      expect(isWavAudio(Uint8List.fromList([1, 2, 3, 4])), isFalse);
    });
  });

  test('a narration failure carries no text', () async {
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (_) async =>
          throw FirebaseAIException('blocked: no cancer here'),
      logger: _MockLogger(),
    );

    final error = await service
        .speakExplanation(
          text: 'Your test found no cancer.',
          languageCode: 'en-US',
          voice: 'Achernar',
          model: 'gemini-3.8-flash-tts',
        )
        .then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, AppError.serviceUnavailable);
    expect('$error'.contains('cancer'), isFalse);
  });

  test('a narration failure is logged without text or audio', () async {
    final logger = _MockLogger();
    final service = FirebaseAiLogicService(
      config: _Config(),
      speakCall: (_) async =>
          throw FirebaseAIException('blocked: no cancer here'),
      logger: logger,
    );

    await expectLater(
      service.speakExplanation(
        text: 'Your test found no cancer.',
        languageCode: 'sw',
        voice: 'Achernar',
        model: 'gemini-3.8-flash-tts',
      ),
      throwsA(AppError.serviceUnavailable),
    );

    final messages = verify(() => logger.e(captureAny<String>())).captured;
    final logged = messages.join(' ');
    expect(logged, contains('FirebaseAIException'));
    expect(logged, contains('sw'));
    expect(logged, isNot(contains('cancer')));
    expect(logged, isNot(contains('Your test')));
  });

  test('the fake logs region and speech calls without content', () async {
    final fake = FakeAiLogicService()
      ..regionResult = {'impression': 'Calm.'}
      ..speechResult = Uint8List.fromList([7]);
    await fake.readRegion(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageMime: 'image/png',
      question: 'Malignant?',
    );
    await fake.speakExplanation(
      text: 'Your test found no cancer.',
      languageCode: 'en-US',
      voice: 'Achernar',
      model: 'gemini-3.8-flash-tts',
    );

    expect(fake.regionCalls, [
      {
        'byteLength': 3,
        'imageMime': 'image/png',
        'hasQuestion': true,
        'hasStain': false,
      },
    ]);
    expect(fake.speechCalls, [
      (languageCode: 'en-US', voice: 'Achernar', model: 'gemini-3.8-flash-tts'),
    ]);
  });
}
