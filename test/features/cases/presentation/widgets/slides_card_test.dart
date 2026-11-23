import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/cases/data/models/slide_image_model.dart';
import 'package:tabibu/features/cases/presentation/widgets/slides_card.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  const one = SlideImageModel(
    imageUid: 'a',
    path: 'slides/c1/a.jpg',
    contentType: 'image/jpeg',
    micronsPerPixel: 0.975,
  );
  const two = SlideImageModel(
    imageUid: 'b',
    path: 'slides/c1/b.png',
    contentType: 'image/png',
    micronsPerPixel: 0.25,
  );

  Future<void> pump(
    WidgetTester tester,
    List<SlideImageModel> slides, {
    required List<String> asked,
    String? Function(String path)? answer,
  }) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      SlidesCard(
        slides: slides,
        urlFor: (path) async {
          asked.add(path);
          return answer == null ? null : answer(path);
        },
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets("says how many slides and shows each one's scale", (
    tester,
  ) async {
    final asked = <String>[];
    await pump(tester, [one, two], asked: asked);

    expect(find.text(en.orderSlidesTitle), findsOneWidget);
    expect(find.text(en.workspaceRequestSlides(2)), findsOneWidget);
    expect(find.text('0.975 µm/px'), findsOneWidget);
    expect(find.text('0.250 µm/px'), findsOneWidget);
    // Each path is resolved once.
    expect(asked, ['slides/c1/a.jpg', 'slides/c1/b.png']);
  });

  testWidgets('a slide that cannot be read shows a mark, not a spinner', (
    tester,
  ) async {
    await pump(tester, [one], asked: <String>[]);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a tapped slide opens edge to edge, not floating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    // A notch and a home indicator, as on the iPhone.
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      SlidesCard(
        slides: const [one],
        urlFor: (path) async => 'https://example.test/$path',
      ),
    );
    await tester.pump();
    await tester.pump();

    tester.takeException();
    await tester.tap(
      find.descendant(
        of: find.byType(SlidesCard),
        matching: find.byType(Tappable),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Test images cannot load; that error is not what this test is about.
    tester.takeException();

    final page = tester.getRect(find.byType(Dialog));
    expect(page.top, 0);
    expect(page.bottom, 2532 / 3);
  });

  Future<void> openFull(WidgetTester tester, {String orderNumber = ''}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      SlidesCard(
        slides: const [one],
        orderNumber: orderNumber,
        urlFor: (path) async => 'https://example.test/$path',
      ),
    );
    await tester.pump();
    await tester.pump();
    tester.takeException();
    await tester.tap(
      find.descendant(
        of: find.byType(SlidesCard),
        matching: find.byType(Tappable),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();
  }

  testWidgets('the full slide is titled by its order, the slide beneath', (
    tester,
  ) async {
    await openFull(tester, orderNumber: 'ODR-AO-NB-17112026-001');

    final bar = tester.widget<TopBar>(find.byType(TopBar));
    expect(bar.title, 'ODR-AO-NB-17112026-001');
    expect(bar.subtitle, '${en.orderSlidesTitle} · 0.975 µm/px');
  });

  testWidgets('a double tap zooms in about the tap, a second goes back', (
    tester,
  ) async {
    await openFull(tester, orderNumber: 'ODR-1');
    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final at = tester.getTopLeft(viewer) + const Offset(100, 200);

    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    tester.takeException();

    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
    // The slide point under the finger stays under it.
    final under = controller.toScene(const Offset(100, 200));
    expect(under.dx, closeTo(100, 0.5));
    expect(under.dy, closeTo(200, 0.5));

    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    tester.takeException();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
  });

  testWidgets('nothing at all without slides', (tester) async {
    final asked = <String>[];
    await pump(tester, const [], asked: asked);

    expect(find.text(en.orderSlidesTitle), findsNothing);
    expect(asked, isEmpty);
  });
}
