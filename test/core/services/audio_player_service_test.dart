import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tabibu/core/services/audio_player_service.dart';
import 'package:tabibu/core/services/audio_service_contract.dart';

class _FakePlayerPlatform implements AudioPlayerPlatform {
  final stateController = StreamController<PlayerState>.broadcast();
  final positionController = StreamController<Duration>.broadcast();
  final durationController = StreamController<Duration?>.broadcast();
  final interruptionController = StreamController<void>.broadcast();

  final played = <String>[];
  int pauseCount = 0;
  int stopCount = 0;
  bool disposed = false;
  bool playing = false;

  /// just_audio's play() completes only when playback pauses, stops or ends;
  /// the fake does the same, so a caller that awaits it is caught waiting.
  Completer<void>? _playing;

  void _endPlay() {
    final current = _playing;
    _playing = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  @override
  Stream<PlayerState> get playerStateStream => stateController.stream;

  @override
  Stream<Duration> get positionStream => positionController.stream;

  @override
  Stream<Duration?> get durationStream => durationController.stream;

  @override
  Stream<void> get interruptionStream => interruptionController.stream;

  @override
  Future<Duration?> setBytes(Uint8List bytes) async {
    played.add('bytes:${bytes.length}');
    return const Duration(seconds: 2);
  }

  @override
  Future<Duration?> setUrl(String url) async {
    played.add('url:$url');
    return const Duration(seconds: 3);
  }

  @override
  Future<void> play() {
    playing = true;
    stateController.add(PlayerState(true, ProcessingState.ready));
    return (_playing ??= Completer<void>()).future;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
    stateController.add(PlayerState(false, ProcessingState.ready));
    _endPlay();
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    playing = false;
    _endPlay();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stateController.close();
    await positionController.close();
    await durationController.close();
    await interruptionController.close();
  }
}

void main() {
  late _FakePlayerPlatform platform;
  late DeviceAudioPlayerService service;

  setUp(() {
    platform = _FakePlayerPlatform();
    service = DeviceAudioPlayerService(platform: platform);
  });

  tearDown(() async {
    await service.dispose();
  });

  test('playBytes and resume return while the clip is still playing', () async {
    // With the real player, awaiting play() would wait out the whole clip and
    // a pause tapped meanwhile would be ignored or the icon would lag.
    await service
        .playBytes(Uint8List(4), id: 'a')
        .timeout(const Duration(seconds: 1));
    expect(platform.playing, isTrue);
    await service.pause();
    expect(
      await service.resume('a').timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(platform.playing, isTrue);
  });

  test('starting B reports A not playing', () async {
    final events = <AudioPlayback>[];
    final sub = service.playback.listen(events.add);

    await service.playBytes(Uint8List(4), id: 'A');
    await service.playUrl(Uri.parse('https://example.test/b.m4a'), id: 'B');
    await Future<void>.delayed(Duration.zero);

    expect(
      events.where((e) => e.id == 'A' && !e.playing),
      isNotEmpty,
      reason: 'A must be reported idle when B starts',
    );
    expect(events.where((e) => e.id == 'B' && e.playing), isNotEmpty);
    await sub.cancel();
  });

  test('interruption pauses the current clip', () async {
    final events = <AudioPlayback>[];
    final sub = service.playback.listen(events.add);

    await service.playBytes(Uint8List(8), id: 'clip');
    platform.interruptionController.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(platform.pauseCount, greaterThan(0));
    expect(events.where((e) => e.id == 'clip' && !e.playing), isNotEmpty);
    await sub.cancel();
  });

  test('resume continues without a second load', () async {
    final events = <AudioPlayback>[];
    final sub = service.playback.listen(events.add);

    await service.playBytes(Uint8List(8), id: 'clip');
    platform.positionController.add(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    await service.pause();
    final loadsBefore = platform.played.length;
    expect(await service.resume('clip'), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(platform.played.length, loadsBefore);
    expect(
      events.where(
        (e) => e.id == 'clip' && e.playing && e.position.inSeconds == 3,
      ),
      isNotEmpty,
    );
    await sub.cancel();
  });

  test('resume of another id fails so the caller must reload', () async {
    await service.playBytes(Uint8List(4), id: 'A');
    await service.pause();
    await service.playBytes(Uint8List(8), id: 'B');
    await service.pause();

    expect(await service.resume('A'), isFalse);
    expect(await service.resume('B'), isTrue);
  });
}
