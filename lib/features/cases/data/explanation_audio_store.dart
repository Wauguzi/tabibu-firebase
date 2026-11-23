import 'dart:convert';
import 'dart:typed_data';

// Transitive only; no new dependency. Resolved by pubspec.lock.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:tabibu/core/helpers/db_helper.dart';
import 'package:tabibu/core/helpers/hive_helper.dart';
import 'package:tabibu/features/cases/data/models/explanation_audio_hive.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

/// Storage key: SHA-256 hex over what [SpeechRequest.cacheKey] joins (text,
/// language, voice, model). The text itself never touches the disk.
String explanationAudioKey(SpeechRequest request) =>
    sha256.convert(utf8.encode(request.cacheKey)).toString();

/// Narrations the patient played, kept encrypted on the phone until
/// sign-out: at most [maxBytes], oldest-played evicted first. The card
/// reads through here after its memory cache; a replay refreshes the
/// clip's age. Sign-out deletes the boxes (see `DBHelper.deleteAll`).
class ExplanationAudioStore {
  ExplanationAudioStore(this._db);

  static const int maxBytes = 20 * 1024 * 1024;

  static const _totalKey = 'totalBytes';
  static const _seqKey = 'seq';

  final DBHelper _db;

  Future<Uint8List?> get(SpeechRequest request) async {
    final row = await _db.get<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      explanationAudioKey(request),
    );
    return row?.bytes;
  }

  /// Stores [bytes] under [request], evicting oldest-played clips until it
  /// fits strictly under budget. A clip over the whole budget is refused:
  /// it plays but is never stored. An overwrite counts once.
  Future<void> put(SpeechRequest request, Uint8List bytes) async {
    final size = bytes.lengthInBytes;
    if (size > maxBytes) return;
    final key = explanationAudioKey(request);
    await _remove(key);
    var total = await _total();
    while (total + size >= maxBytes) {
      final freed = await _evictOldest();
      if (freed == null) break;
      total -= freed;
    }
    final seq = await _nextSeq();
    await _setTotal(total + size);
    await _db.put<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      key,
      ExplanationAudioHive(key: key, bytes: bytes, playedSeq: seq),
    );
  }

  /// Marks [request] just played. Silent when nothing is stored.
  Future<void> played(SpeechRequest request) async {
    final key = explanationAudioKey(request);
    final row = await _db.get<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      key,
    );
    if (row == null) return;
    final seq = await _nextSeq();
    await _db.put<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      key,
      ExplanationAudioHive(key: key, bytes: row.bytes, playedSeq: seq),
    );
  }

  Future<int> _total() async =>
      await _db.get<int>(HiveHelperImpl.explanationAudioMetaBox, _totalKey) ??
      0;

  Future<void> _setTotal(int total) =>
      _db.put<int>(HiveHelperImpl.explanationAudioMetaBox, _totalKey, total);

  Future<int> _nextSeq() async {
    final seq =
        (await _db.get<int>(HiveHelperImpl.explanationAudioMetaBox, _seqKey) ??
            0) +
        1;
    await _db.put<int>(HiveHelperImpl.explanationAudioMetaBox, _seqKey, seq);
    return seq;
  }

  Future<void> _remove(String key) async {
    final row = await _db.get<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      key,
    );
    if (row == null) return;
    await _db.delete<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      key,
    );
    final total = await _total();
    await _setTotal(total - row.bytes.lengthInBytes);
  }

  /// Deletes the oldest-played clip. Returns its bytes, or null when empty.
  Future<int?> _evictOldest() async {
    final rows = await _db.getAll<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
    );
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.playedSeq.compareTo(b.playedSeq));
    final oldest = rows.first;
    await _db.delete<ExplanationAudioHive>(
      HiveHelperImpl.explanationAudioBox,
      oldest.key,
    );
    final total = await _total();
    await _setTotal(total - oldest.bytes.lengthInBytes);
    return oldest.bytes.lengthInBytes;
  }
}
