import 'dart:typed_data';

import 'package:tabibu/features/cases/data/speech_request.dart';

/// Narrates approved text. The live implementation will delegate to
/// `AiLogicService`; the UI only ever sees this seam.
abstract class SpeechClient {
  /// Complete WAV bytes for [request].
  Future<Uint8List> speak(SpeechRequest request);
}

/// In-memory fake: returns [audio] (or throws [error]) and records calls.
class FakeSpeechClient implements SpeechClient {
  FakeSpeechClient({Uint8List? audio, this.error})
    : audio = audio ?? Uint8List.fromList([9, 9, 9]);

  final Uint8List audio;
  final Exception? error;
  final List<SpeechRequest> requests = [];

  @override
  Future<Uint8List> speak(SpeechRequest request) async {
    requests.add(request);
    final failure = error;
    if (failure != null) throw failure;
    return audio;
  }
}
