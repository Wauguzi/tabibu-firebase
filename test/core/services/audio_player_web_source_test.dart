import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/services/audio_player_service.dart';

void main() {
  test('web byte source is a data URI, not a file path', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final uri = JustAudioPlayerPlatform.webByteUri(bytes);
    expect(uri.scheme, 'data');
    expect(uri.toString(), contains('audio/mp4'));
    expect(uri.toString(), isNot(contains('/tmp/')));
    expect(uri.toString(), isNot(contains(r'\')));
  });

  group('byteFormatOf', () {
    Uint8List wav() => Uint8List.fromList([
      ...'RIFF'.codeUnits,
      36,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...'fmt '.codeUnits,
    ]);

    test('speech audio (RIFF WAVE) is named and typed as WAV', () {
      final format = JustAudioPlayerPlatform.byteFormatOf(wav());
      expect(format.extension, 'wav');
      expect(format.mimeType, 'audio/wav');
      expect(
        JustAudioPlayerPlatform.webByteUri(
          wav(),
          mimeType: format.mimeType,
        ).toString(),
        contains('audio/wav'),
      );
    });

    test('anything else keeps the recorder format', () {
      for (final bytes in [
        Uint8List.fromList([0, 0, 0, 24, ...'ftypM4A '.codeUnits]),
        Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0]),
        Uint8List(0),
      ]) {
        final format = JustAudioPlayerPlatform.byteFormatOf(bytes);
        expect(format.extension, 'm4a');
        expect(format.mimeType, 'audio/mp4');
      }
    });
  });
}
