import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_read_gating.dart';

void main() {
  group('regionCapturePixelRatio', () {
    test('caps the long side at 1024', () {
      for (final size in [
        const Size(800, 600),
        const Size(600, 800),
        const Size(4000, 3000),
        const Size(100, 100),
      ]) {
        final ratio = regionCapturePixelRatio(size);
        final rendered = size.width * ratio;
        final renderedHeight = size.height * ratio;
        expect(
          rendered > renderedHeight ? rendered : renderedHeight,
          lessThanOrEqualTo(1024.0 + 1e-6),
        );
      }
    });

    test('renders a zero size at 1 rather than dividing by zero', () {
      expect(regionCapturePixelRatio(Size.zero), 1);
    });
  });

  group('captureRegionBytes', () {
    testWidgets('returns null for a detached boundary', (tester) async {
      await tester.pumpWidget(const SizedBox());
      expect(await captureRegionBytes(GlobalKey()), isNull);
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
