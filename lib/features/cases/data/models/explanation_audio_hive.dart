import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

part 'explanation_audio_hive.g.dart';

/// One stored narration: the clip key, its WAV bytes, and a play counter
/// that orders eviction (oldest first). Device-local only: no Freezed
/// mirror, nothing ever syncs.
@HiveType(typeId: 12)
class ExplanationAudioHive {
  ExplanationAudioHive({
    required this.key,
    required this.bytes,
    required this.playedSeq,
  });

  @HiveField(0)
  final String key;

  @HiveField(1)
  final Uint8List bytes;

  @HiveField(2)
  final int playedSeq;
}
