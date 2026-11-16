import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_gating.dart';

/// Red on the left half, blue on the right.
Future<ui.Image> _twoColourImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = const Color(0xFFFF0000),
    )
    ..drawRect(
      const Rect.fromLTWH(100, 0, 100, 100),
      Paint()..color = const Color(0xFF0000FF),
    );
  return recorder.endRecording().toImage(200, 100);
}

Future<ui.Image> _decode(Uint8List png) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromList(png, done.complete);
  return done.future;
}

Future<ByteData> _rgba(Uint8List png) async {
  final image = await _decode(png);
  try {
    return (await image.toByteData())!;
  } finally {
    image.dispose();
  }
}

Future<RenderRepaintBoundary> _pumpBoundary(
  WidgetTester tester,
  ui.Image source,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: RawImage(image: source, width: 200, height: 100),
      ),
    ),
  );
  return key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
}

int _redCount(ByteData rgba) {
  var red = 0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    if (rgba.getUint8(i) > 200 && rgba.getUint8(i + 2) < 60) red++;
  }
  return red;
}

void main() {
  group('visibleRegionRect', () {
    test('identity shows the whole viewport', () {
      expect(
        visibleRegionRect(
          transform: Matrix4.identity(),
          viewportSize: const Size(200, 100),
        ),
        const Rect.fromLTWH(0, 0, 200, 100),
      );
    });

    test('a 2x zoom shows a quarter', () {
      expect(
        visibleRegionRect(
          transform: Matrix4.diagonal3Values(2, 2, 1),
          viewportSize: const Size(200, 200),
        ),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });
  });

  group('regionCapturePixelRatio', () {
    test('renders the visible side at most 1024', () {
      expect(regionCapturePixelRatio(2048), 0.5);
      expect(regionCapturePixelRatio(1024), 1);
    });

    test('caps deep zooms for memory', () {
      expect(regionCapturePixelRatio(100), 3);
    });

    test('renders a zero size at 1', () {
      expect(regionCapturePixelRatio(0), 1);
    });
  });

  group('captureVisibleRegion', () {
    testWidgets('a zoomed half captures only that colour', (tester) async {
      final source = await _twoColourImage();
      addTearDown(source.dispose);
      final boundary = await _pumpBoundary(tester, source);

      // Capture and byte reads run on the live binding, not the test zone.
      final rgba = await tester.runAsync(() async {
        final bytes = await captureVisibleRegion(
          boundary: boundary,
          transform: Matrix4.diagonal3Values(2, 2, 1),
          viewportSize: const Size(200, 200),
        );
        if (bytes == null) return null;
        return await _rgba(bytes);
      });

      expect(rgba, isNotNull);
      final pixels = rgba!.lengthInBytes ~/ 4;
      expect(_redCount(rgba) / pixels, greaterThan(0.9));
    });

    testWidgets('no zoom captures both colours', (tester) async {
      final source = await _twoColourImage();
      addTearDown(source.dispose);
      final boundary = await _pumpBoundary(tester, source);

      // Capture and byte reads run on the live binding, not the test zone.
      final rgba = await tester.runAsync(() async {
        final bytes = await captureVisibleRegion(
          boundary: boundary,
          transform: Matrix4.identity(),
          viewportSize: const Size(200, 100),
        );
        if (bytes == null) return null;
        return await _rgba(bytes);
      });

      expect(rgba, isNotNull);
      final pixels = rgba!.lengthInBytes ~/ 4;
      final red = _redCount(rgba);
      expect(red, greaterThan(0));
      expect(red, lessThan(pixels));
    });
  });

  group('RegionCaptureController', () {
    test('unbound captures return null', () async {
      expect(await RegionCaptureController().captureRegion(), isNull);
    });
  });

  group('showRegionAsk', () {
    test('needs the pathologist, an accepted case and the switch', () {
      for (var mask = 0; mask < 8; mask++) {
        final pathologist = mask & 1 != 0;
        final accepted = mask & 2 != 0;
        final enabled = mask & 4 != 0;
        expect(
          showRegionAsk(
            isPathologist: pathologist,
            accepted: accepted,
            enabled: enabled,
          ),
          pathologist && accepted && enabled,
          reason: 'mask $mask',
        );
      }
    });
  });
}
