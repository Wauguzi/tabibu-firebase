import 'dart:typed_data';

/// Generated explanation audio, in memory only: keyed by the request's
/// cache key, never written anywhere. The owning card drops it
/// with its state, so a sign-out — which always leaves the screen — drops it.
class ExplanationAudioCache {
  final _entries = <String, Uint8List>{};

  Uint8List? get(String key) => _entries[key];

  void put(String key, Uint8List bytes) => _entries[key] = bytes;

  void clear() => _entries.clear();
}
