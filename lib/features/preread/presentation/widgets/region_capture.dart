import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Long-side cap for a captured region, in pixels.
const regionCaptureLongSide = 1024.0;

/// Ceiling on the capture pixel ratio: a bound on transient memory. A region
/// zoomed past it renders at true pixels, smaller than the cap.
const _maxPixelRatio = 3.0;

/// Captures the visible slide region for a read. The workspace owns one;
/// SlideViewer binds it while mounted. Unbound captures return null.
class RegionCaptureController {
  /// Bound by SlideViewer while mounted; not for callers.
  Future<Uint8List?> Function()? capture;

  /// Runs the bound capture, or null when no viewer is bound.
  Future<Uint8List?> captureRegion() => capture?.call() ?? Future.value();
}

/// The visible rect in boundary coordinates: the viewport run back through
/// the viewer's transform. Panning past the image is fine; the crop clamps.
Rect visibleRegionRect({
  required Matrix4 transform,
  required Size viewportSize,
}) => MatrixUtils.inverseTransformRect(transform, Offset.zero & viewportSize);

/// The pixel ratio rendering [visibleLongSide] logical pixels at most
/// [maxLongSide] device pixels. A zero size renders at 1.
double regionCapturePixelRatio(
  double visibleLongSide, {
  double maxLongSide = regionCaptureLongSide,
}) {
  if (visibleLongSide <= 0) return 1;
  return min(maxLongSide / visibleLongSide, _maxPixelRatio);
}

/// PNG bytes of [crop] (in [boundarySize] coordinates) cut from [image], or
/// null when the crop misses the image or rounds to nothing.
Future<Uint8List?> cropToPng({
  required ui.Image image,
  required Rect crop,
  required Size boundarySize,
}) async {
  if (boundarySize.isEmpty) return null;
  final scaleX = image.width / boundarySize.width;
  final scaleY = image.height / boundarySize.height;
  final src =
      Rect.fromLTWH(
        crop.left * scaleX,
        crop.top * scaleY,
        crop.width * scaleX,
        crop.height * scaleY,
      ).intersect(
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      );
  if (src.isEmpty || src.width < 1 || src.height < 1) return null;
  final picture = ui.PictureRecorder();
  Canvas(picture).drawImageRect(
    image,
    src,
    Offset.zero & src.size,
    Paint()..filterQuality = .high,
  );
  final cropped = await picture.endRecording().toImage(
    src.width.round(),
    src.height.round(),
  );
  try {
    final bytes = await cropped.toByteData(format: .png);
    return bytes?.buffer.asUint8List();
  } finally {
    cropped.dispose();
  }
}

/// PNG bytes of exactly the visible region: the boundary renders at the ratio
/// its visible long side needs (capped), then the visible rect is cut out.
/// Null when the boundary is gone or nothing is visible.
Future<Uint8List?> captureVisibleRegion({
  required RenderRepaintBoundary boundary,
  required Matrix4 transform,
  required Size viewportSize,
  double maxLongSide = regionCaptureLongSide,
}) async {
  if (!boundary.attached) return null;
  final visible = visibleRegionRect(
    transform: transform,
    viewportSize: viewportSize,
  );
  final longest = max(visible.width, visible.height);
  if (longest <= 0) return null;
  final image = await boundary.toImage(
    pixelRatio: regionCapturePixelRatio(longest, maxLongSide: maxLongSide),
  );
  try {
    return await cropToPng(
      image: image,
      crop: visible,
      boundarySize: boundary.size,
    );
  } finally {
    image.dispose();
  }
}
