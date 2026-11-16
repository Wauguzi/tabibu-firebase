import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/cases/data/ai_logic_speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

void main() {
  group('AiLogicSpeechClient', () {
    test('speaks with the mapped language code', () async {
      final service = FakeAiLogicService()
        ..speechResult = Uint8List.fromList([7, 7]);
      final client = AiLogicSpeechClient(service);

      final bytes = await client.speak(
        const SpeechRequest(
          text: 'Habari.',
          language: 'sw',
          voice: 'Achernar',
          model: 'gemini-3.8-flash-tts',
        ),
      );

      expect(bytes, [7, 7]);
      expect(service.speechCalls.single.languageCode, 'sw');
    });

    test('an unknown language fails closed', () async {
      final service = FakeAiLogicService()
        ..speechResult = Uint8List.fromList([7, 7]);
      final client = AiLogicSpeechClient(service);

      await expectLater(
        client.speak(
          const SpeechRequest(
            text: 'Bonjour.',
            language: 'fr',
            voice: 'Achernar',
            model: 'gemini-3.8-flash-tts',
          ),
        ),
        throwsA(AppError.unknown),
      );
      expect(service.speechCalls, isEmpty);
    });
  });
}
