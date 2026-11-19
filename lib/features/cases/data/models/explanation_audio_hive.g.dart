// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explanation_audio_hive.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExplanationAudioHiveAdapter extends TypeAdapter<ExplanationAudioHive> {
  @override
  final typeId = 12;

  @override
  ExplanationAudioHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExplanationAudioHive(
      key: fields[0] as String,
      bytes: fields[1] as Uint8List,
      playedSeq: (fields[2] as num).toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, ExplanationAudioHive obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.bytes)
      ..writeByte(2)
      ..write(obj.playedSeq);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExplanationAudioHiveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
