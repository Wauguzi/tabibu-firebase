import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/cases/data/explanation_audio_cache.dart';

void main() {
  group('ExplanationAudioCache', () {
    test('keeps bytes per key until cleared', () {
      final cache = ExplanationAudioCache();
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(cache.get('k'), isNull);
      cache.put('k', bytes);
      expect(cache.get('k'), same(bytes));
      cache.clear();
      expect(cache.get('k'), isNull);
    });
  });
}
