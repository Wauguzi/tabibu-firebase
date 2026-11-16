import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.0.0 exposes the template, audio and speech symbols', () {
    expect(() async {
      final backend = FirebaseAI.agentPlatform(
        location: 'global',
        useLimitedUseAppCheckTokens: false,
      );
      // Server templates are still preview in this SDK.
      // ignore: experimental_member_use
      final model = backend.templateGenerativeModel();
      // The call is the same preview API.
      // ignore: experimental_member_use
      await model.generateContent(
        'symptom-transcribe-v1-0-0',
        inputs: const {'audioMime': 'audio/wav', 'audioData': ''},
      );
    }, throwsA(isA<Object>()));
    expect(InlineDataPart('audio/wav', Uint8List(0)).mimeType, 'audio/wav');
    expect(SpeechConfig(languageCode: 'en-US').languageCode, 'en-US');
  });

  test('4.0.0 exposes the plain audio call shape', () {
    final config = GenerationConfig(
      responseModalities: [ResponseModalities.audio],
      speechConfig: SpeechConfig(voiceName: 'Achernar', languageCode: 'sw'),
    );
    expect(config.responseModalities, [ResponseModalities.audio]);
    expect(config.speechConfig?.voiceName, 'Achernar');
    expect(Content.text('Hi').parts.single, isA<TextPart>());
  });
}
