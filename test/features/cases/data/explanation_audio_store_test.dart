import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/helpers/hive_helper.dart';
import 'package:tabibu/features/cases/data/explanation_audio_store.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

import '../../../helpers/helpers.dart';

const int _mb = 1024 * 1024;

Uint8List _bytes(int size) => Uint8List(size);

SpeechRequest _request(String text) => SpeechRequest(
  text: text,
  language: 'en',
  voice: 'Achernar',
  model: 'gemini-3.8-flash-tts',
);

Object? _meta(FakeDbHelper db, String key) =>
    db.boxes[HiveHelperImpl.explanationAudioMetaBox]?[key];

void main() {
  group('explanationAudioKey', () {
    test('is SHA-256 hex over text, language, voice and model', () {
      final key = explanationAudioKey(_request('Your test found no cancer.'));

      expect(key, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      expect(key, isNot(contains('cancer')));
    });

    test('matches the known digest', () {
      expect(
        explanationAudioKey(_request('x')),
        '9c32baa62f26af3c8a8e3d0ebff8fb12cfdc9e0c15c03a2983acec03554da1d0',
      );
    });

    test('differs across voice and model', () {
      const base = SpeechRequest(
        text: 'Your test found no cancer.',
        language: 'en',
        voice: 'Achernar',
        model: 'gemini-3.8-flash-tts',
      );
      const otherVoice = SpeechRequest(
        text: 'Your test found no cancer.',
        language: 'en',
        voice: 'Kore',
        model: 'gemini-3.8-flash-tts',
      );
      const otherModel = SpeechRequest(
        text: 'Your test found no cancer.',
        language: 'en',
        voice: 'Achernar',
        model: 'other-model',
      );

      expect(explanationAudioKey(otherVoice), isNot(explanationAudioKey(base)));
      expect(explanationAudioKey(otherModel), isNot(explanationAudioKey(base)));
    });
  });

  group('ExplanationAudioStore', () {
    late FakeDbHelper db;
    late ExplanationAudioStore store;

    setUp(() {
      db = FakeDbHelper();
      store = ExplanationAudioStore(db);
    });

    test('stores and returns bytes by request', () async {
      final bytes = _bytes(10);

      expect(await store.get(_request('a')), isNull);
      await store.put(_request('a'), bytes);
      expect(await store.get(_request('a')), same(bytes));
      expect(await store.get(_request('b')), isNull);
    });

    test('fits inside budget without evicting or scanning', () async {
      await store.put(_request('a'), _bytes(8 * _mb));
      await store.put(_request('b'), _bytes(8 * _mb));

      expect(await store.get(_request('a')), isNotNull);
      expect(await store.get(_request('b')), isNotNull);
      expect(db.getAllCalls, 0);
      expect(_meta(db, 'totalBytes'), 16 * _mb);
    });

    test(
      'reaching the budget evicts oldest first, only as many as needed',
      () async {
        await store.put(_request('a'), _bytes(8 * _mb));
        await store.put(_request('b'), _bytes(8 * _mb));

        await store.put(_request('c'), _bytes(4 * _mb));

        expect(await store.get(_request('a')), isNull);
        expect(await store.get(_request('b')), isNotNull);
        expect(await store.get(_request('c')), isNotNull);
        expect(_meta(db, 'totalBytes'), 12 * _mb);
      },
    );

    test('eviction cascades while over budget', () async {
      await store.put(_request('a'), _bytes(8 * _mb));
      await store.put(_request('b'), _bytes(8 * _mb));

      await store.put(_request('c'), _bytes(14 * _mb));

      expect(await store.get(_request('a')), isNull);
      expect(await store.get(_request('b')), isNull);
      expect(await store.get(_request('c')), isNotNull);
      expect(_meta(db, 'totalBytes'), 14 * _mb);
    });

    test('a clip over the whole budget is refused, nothing evicted', () async {
      await store.put(_request('a'), _bytes(8 * _mb));

      await store.put(_request('big'), _bytes(21 * _mb));

      expect(await store.get(_request('big')), isNull);
      expect(await store.get(_request('a')), isNotNull);
      expect(db.getAllCalls, 0);
      expect(_meta(db, 'totalBytes'), 8 * _mb);
    });

    test('a replay refreshes a clip age', () async {
      await store.put(_request('a'), _bytes(8 * _mb));
      await store.put(_request('b'), _bytes(8 * _mb));
      await store.played(_request('a'));

      await store.put(_request('c'), _bytes(10 * _mb));

      expect(await store.get(_request('b')), isNull);
      expect(await store.get(_request('a')), isNotNull);
      expect(await store.get(_request('c')), isNotNull);
    });

    test('played on a missing clip is silent', () async {
      await store.played(_request('ghost'));

      expect(_meta(db, 'totalBytes'), isNull);
    });

    test('an overwrite counts once', () async {
      await store.put(_request('a'), _bytes(8 * _mb));

      await store.put(_request('a'), _bytes(8 * _mb));

      expect(_meta(db, 'totalBytes'), 8 * _mb);
      expect(await store.get(_request('a')), isNotNull);
    });
  });
}
