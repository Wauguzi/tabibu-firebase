import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/services/recording_cue_service.dart';
import 'package:tabibu/gen/assets.gen.dart';

import '../../helpers/fake_audio_services.dart';

void main() {
  late FakeAudioPlayerService player;
  late List<String> vibrateCalls;
  late DeviceRecordingCueService cues;
  var quiet = false;
  var vibrateThrows = false;
  var loadThrows = false;

  setUp(() {
    player = FakeAudioPlayerService();
    vibrateCalls = [];
    quiet = false;
    vibrateThrows = false;
    loadThrows = false;
    cues = DeviceRecordingCueService(
      player,
      vibrate: () async {
        vibrateCalls.add('v');
        if (vibrateThrows) throw StateError('no motor');
      },
      loadAsset: (asset) async {
        if (loadThrows) throw StateError('missing asset');
        return Uint8List.fromList([1, 2, 3]);
      },
      cuesDisabled: () => quiet,
      beepHold: Duration.zero,
    );
  });

  /// Lets the beep report its end, then waits for the cue to stop it.
  Future<void> letCueFinish(Future<void> pending) async {
    await Future<void>.delayed(Duration.zero);
    player.completeCurrent();
    await pending;
  }

  tearDown(() async {
    await player.dispose();
  });

  test('started vibrates and plays the start asset then stops', () async {
    await letCueFinish(cues.started());
    expect(vibrateCalls, ['v']);
    expect(player.playedIds, [DeviceRecordingCueService.cueId]);
    expect(player.playBytesCalls, hasLength(1));
    expect(player.stopCount, 1);
  });

  test('finished vibrates and plays the stop asset', () async {
    await letCueFinish(cues.finished());
    expect(vibrateCalls, ['v']);
    expect(player.playedIds, [DeviceRecordingCueService.cueId]);
    expect(player.stopCount, 1);
  });

  test('never throws when the vibrator or player fails', () async {
    vibrateThrows = true;
    loadThrows = true;
    await expectLater(cues.started(), completes);
    await expectLater(cues.finished(), completes);
  });

  test('started and finished load the generated sound paths', () async {
    final loaded = <String>[];
    final probe = DeviceRecordingCueService(
      player,
      vibrate: () async {},
      loadAsset: (asset) async {
        loaded.add(asset);
        return Uint8List.fromList([1, 2, 3]);
      },
      cuesDisabled: () => false,
      beepHold: Duration.zero,
    );
    await letCueFinish(probe.started());
    await letCueFinish(probe.finished());
    expect(loaded, [Assets.sounds.recordStart, Assets.sounds.recordStop]);
  });

  test('started returns only after the cue completion event', () async {
    final held = DeviceRecordingCueService(
      player,
      vibrate: () async {},
      loadAsset: (_) async => Uint8List.fromList([1, 2, 3]),
      cuesDisabled: () => false,
      beepHold: const Duration(milliseconds: 80),
    );
    final pending = held.started();
    // Longer than the hold: a cue that waits from play-start would have
    // stopped already. This one is still waiting for completion.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(player.playedIds, [DeviceRecordingCueService.cueId]);
    expect(player.stopCount, 0);

    player.completeCurrent();
    await pending;
    expect(player.stopCount, 1);
    expect(DeviceRecordingCueService.cueEndTimeout, const Duration(seconds: 1));
  });

  test('a cue that never ends still stops so the mic can open', () async {
    final quick = DeviceRecordingCueService(
      player,
      vibrate: () async {},
      loadAsset: (_) async => Uint8List.fromList([1, 2, 3]),
      cuesDisabled: () => false,
      beepHold: Duration.zero,
      endTimeout: const Duration(milliseconds: 20),
    );
    await quick.started().timeout(const Duration(milliseconds: 500));
    expect(player.stopCount, 1);
  });

  test('a beep that fails to play stops at once, without the wait', () async {
    final pending = cues.started().timeout(const Duration(milliseconds: 500));
    await Future<void>.delayed(Duration.zero);
    player.failClip(DeviceRecordingCueService.cueId);
    await pending;
    expect(player.stopCount, 1);
  });

  test('skips cues when reduce-motion quiet check is on', () async {
    quiet = true;
    await cues.started();
    await cues.finished();
    expect(vibrateCalls, isEmpty);
    expect(player.playedIds, isEmpty);
  });

  test('bundled cue assets are valid short mono WAVs under 8 KB', () {
    for (final name in [
      DeviceRecordingCueService.startAsset,
      DeviceRecordingCueService.stopAsset,
    ]) {
      final file = File(name);
      expect(file.existsSync(), isTrue, reason: name);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, lessThan(8 * 1024));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      // fmt chunk: PCM (1), mono (1), 22050 Hz
      final audioFormat = bytes[20] | (bytes[21] << 8);
      final channels = bytes[22] | (bytes[23] << 8);
      final rate =
          bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24);
      expect(audioFormat, 1);
      expect(channels, 1);
      expect(rate, 22050);
    }
  });
}
