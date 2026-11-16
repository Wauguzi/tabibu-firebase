import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Long-side cap for a captured region, in pixels.
const regionCaptureLongSide = 1024.0;

/// The pixel ratio that renders [logicalSize] with a long side of at most
/// [maxLongSide]. A zero size renders at 1 rather than dividing by zero.
double regionCapturePixelRatio(
  Size logicalSize, {
  double maxLongSide = regionCaptureLongSide,
}) {
  final longest = max(logicalSize.width, logicalSize.height);
  if (longest <= 0) return 1;
  return maxLongSide / longest;
}

/// PNG bytes of exactly what [boundaryKey] shows, or null when the boundary
/// is gone. The caller wraps the base image only: overlays and controls sit
/// outside the boundary so they never reach the model.
Future<Uint8List?> captureRegionBytes(
  GlobalKey boundaryKey, {
  double maxLongSide = regionCaptureLongSide,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || !boundary.attached) return null;
  final image = await boundary.toImage(
    pixelRatio: regionCapturePixelRatio(
      boundary.size,
      maxLongSide: maxLongSide,
    ),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
