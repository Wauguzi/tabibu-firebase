import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/asset_icon.dart';
import 'package:tabibu/core/widgets/circle_icon_button.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/features/preread/presentation/widgets/slide_viewer.dart';
import 'package:tabibu/gen/assets.gen.dart';

import '../../../../helpers/helpers.dart';

/// An image that never resolves a frame.
class _HangingImage extends ImageProvider<_HangingImage> {
  @override
  Future<_HangingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_HangingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _HangingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

void main() {
  // 1x1 PNG.
  final okBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    // cspell:disable-next-line
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );
  final okImage = MemoryImage(Uint8List.fromList(okBytes));
  final badImage = MemoryImage(Uint8List.fromList([1, 2, 3]));

  testWidgets('withholds the ask pill until a frame paints', (tester) async {
    await tester.pumpApp(
      SizedBox(
        width: 390,
        child: SlideViewer(
          image: _HangingImage(),
          heatmapOn: false,
          onHeatmapChanged: (_) {},
          heatmapLabel: 'Heat map',
          tilesLabel: 'Tiles',
          scaleLabel: '1x',
          legendLow: 'Low',
          legendHigh: 'High',
          zoomInLabel: 'Zoom in',
          zoomOutLabel: 'Zoom out',
          askRegionLabel: 'Ask AI about this region',
          onAskRegion: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask AI about this region'), findsNothing);
  });

  testWidgets('refuses the capture on the error fallback', (tester) async {
    final controller = RegionCaptureController();
    await tester.pumpApp(
      SizedBox(
        width: 390,
        child: SlideViewer(
          image: badImage,
          heatmapOn: false,
          onHeatmapChanged: (_) {},
          heatmapLabel: 'Heat map',
          tilesLabel: 'Tiles',
          scaleLabel: '1x',
          legendLow: 'Low',
          legendHigh: 'High',
          zoomInLabel: 'Zoom in',
          zoomOutLabel: 'Zoom out',
          askRegionLabel: 'Ask AI about this region',
          onAskRegion: () {},
          regionCaptureController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask AI about this region'), findsNothing);
    expect(await controller.captureRegion(), isNull);
  });

  Widget viewer({
    required bool heatmapOn,
    required ValueChanged<bool> onHeatmapChanged,
    VoidCallback? onTiles,
    VoidCallback? onAskRegion,
    ImageProvider? image,
    ImageProvider? heatmap,
    RegionCaptureController? regionCaptureController,
  }) {
    return SizedBox(
      width: 390,
      child: SlideViewer(
        image: image ?? okImage,
        heatmap: heatmap,
        heatmapOn: heatmapOn,
        onHeatmapChanged: onHeatmapChanged,
        heatmapLabel: 'Heat map',
        tilesLabel: 'Tiles',
        onTiles: onTiles,
        askRegionLabel: 'Ask AI about this region',
        onAskRegion: onAskRegion,
        regionCaptureController: regionCaptureController,
        scaleLabel: 'x20 · 1 mm',
        legendLow: 'Normal',
        legendHigh: 'Likely tumour',
        zoomInLabel: 'Zoom in',
        zoomOutLabel: 'Zoom out',
      ),
    );
  }

  group('SlideViewer', () {
    testWidgets('toggle calls back', (tester) async {
      var on = true;
      await tester.pumpApp(
        StatefulBuilder(
          builder: (context, setState) {
            return viewer(
              heatmapOn: on,
              onHeatmapChanged: (v) => setState(() => on = v),
            );
          },
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(on, isFalse);
    });

    testWidgets('tiles tap fires', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        viewer(
          heatmapOn: false,
          onHeatmapChanged: (_) {},
          onTiles: () => taps++,
        ),
      );
      await tester.tap(find.text('Tiles'));
      expect(taps, 1);
    });

    testWidgets('null onTiles hides the Tiles control', (tester) async {
      await tester.pumpApp(viewer(heatmapOn: false, onHeatmapChanged: (_) {}));
      expect(find.text('Tiles'), findsNothing);
      expect(find.text('Heat map'), findsOneWidget);
    });

    testWidgets('ask tap fires', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        viewer(
          heatmapOn: false,
          onHeatmapChanged: (_) {},
          onAskRegion: () => taps++,
        ),
      );
      // The pill waits for the first frame, which decodes asynchronously.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask AI about this region'));
      expect(taps, 1);
    });

    testWidgets('null onAskRegion hides the ask control', (tester) async {
      await tester.pumpApp(viewer(heatmapOn: false, onHeatmapChanged: (_) {}));
      expect(find.text('Ask AI about this region'), findsNothing);
      expect(find.text('Heat map'), findsOneWidget);
    });

    testWidgets('zoom is two round buttons at the right edge, with a gap', (
      tester,
    ) async {
      await tester.pumpApp(viewer(heatmapOn: true, onHeatmapChanged: (_) {}));
      await tester.pump();

      final zoomIn = tester.getRect(find.bySemanticsLabel('Zoom in'));
      final zoomOut = tester.getRect(find.bySemanticsLabel('Zoom out'));
      final image = tester.getRect(
        find
            .descendant(
              of: find.byType(SlideViewer),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      // Each its own circle, 48 dp to tap, with air between them.
      expect(find.byType(CircleIconButton), findsNWidgets(2));
      expect(zoomIn.width, 48);
      expect(zoomOut.top - zoomIn.bottom, AppSpacing.xs);
      expect(find.byType(Divider), findsNothing);
      expect(image.right - zoomIn.right, AppSpacing.xs);
    });

    testWidgets('Ask AI sits at the slide bottom right, after the AI star', (
      tester,
    ) async {
      await tester.pumpApp(
        SizedBox(
          width: 390,
          child: SlideViewer(
            image: okImage,
            heatmapOn: true,
            onHeatmapChanged: (_) {},
            heatmapLabel: 'Heat map',
            tilesLabel: 'Tiles',
            askRegionLabel: 'Ask AI',
            askRegionSemanticLabel: 'Ask AI about this region',
            onAskRegion: () {},
            scaleLabel: 'x20 · 1 mm',
            legendLow: 'Normal',
            legendHigh: 'Likely tumour',
            zoomInLabel: 'Zoom in',
            zoomOutLabel: 'Zoom out',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ask = tester.getRect(
        find.bySemanticsLabel('Ask AI about this region'),
      );
      final image = tester.getRect(
        find
            .descendant(
              of: find.byType(SlideViewer),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(image.right - ask.right, AppSpacing.xs);
      expect(image.bottom - ask.bottom, AppSpacing.xs);
      // Not in the top row with the heat map toggle.
      expect(
        ask.top,
        greaterThan(tester.getRect(find.text('Heat map')).bottom),
      );
      final star = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is AssetIcon && w.asset == Assets.icons.sparkleIcon,
        ),
      );
      expect(
        star.right,
        lessThanOrEqualTo(tester.getRect(find.text('Ask AI')).left),
      );
    });

    testWidgets('zoom buttons change scale and stop at the bounds', (
      tester,
    ) async {
      await tester.pumpApp(viewer(heatmapOn: false, onHeatmapChanged: (_) {}));
      await tester.pumpAndSettle();

      final viewerWidget = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = viewerWidget.transformationController!;
      expect(controller.value.getMaxScaleOnAxis(), 1);

      for (var i = 0; i < 20; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom in'));
        await tester.pump();
      }
      expect(controller.value.getMaxScaleOnAxis(), SlideViewer.maxScale);

      for (var i = 0; i < 30; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom out'));
        await tester.pump();
      }
      expect(controller.value.getMaxScaleOnAxis(), SlideViewer.minScale);
    });

    testWidgets('failing image shows the photo fallback', (tester) async {
      await tester.pumpApp(
        viewer(heatmapOn: false, onHeatmapChanged: (_) {}, image: badImage),
      );
      await tester.pump();
      // Image resolves asynchronously; give the errorBuilder a beat.
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester
            .widgetList<AssetIcon>(find.byType(AssetIcon))
            .any((icon) => icon.asset == Assets.icons.photoIcon),
        isTrue,
      );
    });

    testWidgets('renders in light and dark', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpApp(
          viewer(heatmapOn: true, onHeatmapChanged: (_) {}, heatmap: okImage),
          themeMode: mode,
        );
        expect(find.byType(SlideViewer), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(find.text('Likely tumour'), findsOneWidget);
      }
    });

    testWidgets('grows at 1.3x text without overflow at 390 dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(
        SizedBox(
          width: 390,
          child: viewer(heatmapOn: false, onHeatmapChanged: (_) {}),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    TransformationController transformOf(WidgetTester tester) {
      return tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
    }

    Future<void> doubleTapAt(WidgetTester tester, Offset global) async {
      await tester.tapAt(global);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(global);
      await tester.pump();
      await tester.pump(SlideViewer.zoomDuration);
    }

    testWidgets('zoom buttons keep the viewport centre fixed', (tester) async {
      await tester.pumpApp(viewer(heatmapOn: false, onHeatmapChanged: (_) {}));
      await tester.pumpAndSettle();

      final controller = transformOf(tester);
      final size = tester.getSize(find.byType(InteractiveViewer));
      final centre = Offset(size.width / 2, size.height / 2);
      final before = controller.toScene(centre);

      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pump();
      final zoomed = controller.toScene(centre);
      expect(zoomed.dx, closeTo(before.dx, 0.01));
      expect(zoomed.dy, closeTo(before.dy, 0.01));
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

      await tester.tap(find.bySemanticsLabel('Zoom out'));
      await tester.pump();
      final restored = controller.toScene(centre);
      expect(restored.dx, closeTo(before.dx, 0.01));
      expect(restored.dy, closeTo(before.dy, 0.01));
      expect(controller.value.getMaxScaleOnAxis(), 1);
    });

    testWidgets('a double tap zooms about the point, and the next returns '
        'to 1x', (tester) async {
      await tester.pumpApp(viewer(heatmapOn: false, onHeatmapChanged: (_) {}));
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(
        find.byType(InteractiveViewer),
      );
      const local = Offset(70, 120);
      final controller = transformOf(tester);
      final before = controller.toScene(local);

      await doubleTapAt(tester, box.localToGlobal(local));
      expect(
        controller.value.getMaxScaleOnAxis(),
        closeTo(SlideViewer.doubleTapScale, 0.01),
      );
      final zoomed = controller.toScene(local);
      expect(zoomed.dx, closeTo(before.dx, 0.01));
      expect(zoomed.dy, closeTo(before.dy, 0.01));

      await doubleTapAt(tester, box.localToGlobal(local));
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
      expect(controller.value.getTranslation().x, closeTo(0, 0.01));
      expect(controller.value.getTranslation().y, closeTo(0, 0.01));
    });

    testWidgets('the crop after a double tap is the visible region', (
      tester,
    ) async {
      final controller = RegionCaptureController();
      await tester.pumpApp(
        viewer(
          heatmapOn: false,
          onHeatmapChanged: (_) {},
          regionCaptureController: controller,
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(
        find.byType(InteractiveViewer),
      );
      await doubleTapAt(tester, box.localToGlobal(const Offset(80, 140)));

      final matrix = transformOf(tester).value;
      final size = tester.getSize(find.byType(InteractiveViewer));
      final visible = visibleRegionRect(transform: matrix, viewportSize: size);
      expect(visible.width, lessThan(size.width - 1));

      final png = await tester.runAsync(controller.captureRegion);
      expect(png, isNotNull);
      final image = await tester.runAsync(() {
        final done = Completer<ui.Image>();
        ui.decodeImageFromList(png!, done.complete);
        return done.future;
      });
      addTearDown(image!.dispose);
      final ratio = regionCapturePixelRatio(max(visible.width, visible.height));
      expect(image.width, closeTo(visible.width * ratio, 2));
      expect(image.height, closeTo(visible.height * ratio, 2));
    });
  });
}
