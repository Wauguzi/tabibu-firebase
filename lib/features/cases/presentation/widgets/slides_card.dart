import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_shadows.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/app_styles.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/cases/data/models/slide_image_model.dart';
import 'package:tabibu/features/preread/data/datasources/preread_storage.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The slides on a case: a thumbnail for each, and a tap opens it at full size
/// to pan and zoom. The picture only, with no AI overlay: what the doctor
/// attached is what the doctor and the pathologist both see. The Storage rules
/// let the case's own doctor and its accepted pathologist read them.
class SlidesCard extends StatefulWidget {
  const SlidesCard({
    required this.slides,
    this.orderNumber = '',
    this.urlFor,
    super.key,
  });

  final List<SlideImageModel> slides;

  /// The full-size view's title, as on the order; the slide's details go
  /// beneath it.
  final String orderNumber;

  /// Resolves a Storage path to a URL; the app's own storage by default.
  final Future<String?> Function(String path)? urlFor;

  @override
  State<SlidesCard> createState() => _SlidesCardState();
}

class _SlidesCardState extends State<SlidesCard> {
  final _urls = <String, String?>{};

  Future<String?> Function(String) get _resolve =>
      widget.urlFor ?? getIt<PrereadStorage>().downloadUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SlidesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides != widget.slides) unawaited(_load());
  }

  Future<void> _load() async {
    for (final slide in widget.slides) {
      if (slide.path.isEmpty || _urls.containsKey(slide.path)) continue;
      final url = await _resolve(slide.path);
      if (!mounted) return;
      setState(() => _urls[slide.path] = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = scheme.brightness == .dark;
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card(),
      ),
      child: Padding(
        padding: AppStyles.cardPadding,
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(l10n.orderSlidesTitle, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.workspaceRequestSlides(slides.length),
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final slide in slides)
                  _Thumb(
                    url: _urls[slide.path],
                    resolved: _urls.containsKey(slide.path),
                    scale: slide.micronsPerPixel,
                    onTap: _urls[slide.path] == null
                        ? null
                        : () => unawaited(
                            _open(context, _urls[slide.path]!, slide),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url, SlideImageModel slide) =>
      showDialog<void>(
        context: context,
        // Edge to edge: the default safe area left the dimmed screen showing
        // above and below, so the slide looked like it floated over it. The
        // page keeps its own safe area inside.
        useSafeArea: false,
        builder: (_) => _FullSlide(
          url: url,
          scale: slide.micronsPerPixel,
          orderNumber: widget.orderNumber,
        ),
      );
}

String _scaleLabel(double micronsPerPixel) {
  if (micronsPerPixel <= 0) return '';
  return '${micronsPerPixel.toStringAsFixed(micronsPerPixel >= 1 ? 0 : 3)} µm/px';
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.resolved,
    required this.scale,
    required this.onTap,
  });

  final String? url;
  final bool resolved;
  final double scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final url = this.url;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.field),
      child: SizedBox(
        width: 96,
        height: 96,
        child: url == null
            ? ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Center(
                  child: resolved
                      ? AssetIcon(
                          Assets.icons.alertIcon,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        )
                      : const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              )
            : Image.network(
                url,
                fit: .cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerLow,
                  child: Center(
                    child: AssetIcon(
                      Assets.icons.alertIcon,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
      ),
    );
    final caption = _scaleLabel(scale);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Tappable(
          onTap: onTap,
          semanticLabel: caption.isEmpty
              ? context.l10n.patientHomeSlideLabel(1, 1)
              : caption,
          child: image,
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(caption, style: textTheme.labelSmall),
        ],
      ],
    );
  }
}

class _FullSlide extends StatefulWidget {
  const _FullSlide({
    required this.url,
    required this.scale,
    required this.orderNumber,
  });

  final String url;
  final double scale;
  final String orderNumber;

  @override
  State<_FullSlide> createState() => _FullSlideState();
}

class _FullSlideState extends State<_FullSlide>
    with SingleTickerProviderStateMixin {
  static const _maxScale = 8.0;

  /// How far a double tap zooms in.
  static const _tapScale = 2.5;

  final _transform = TransformationController();
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => _transform.value = _zoomTo.value);
  late Animation<Matrix4> _zoomTo;
  late Offset _tapAt;

  @override
  void dispose() {
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// In about the tapped point, or back out when already zoomed in: a pinch
  /// can be taken by the page, a double tap is not.
  void _doubleTap() {
    final zoomedIn = _transform.value.getMaxScaleOnAxis() > 1.01;
    final target = zoomedIn
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -_tapAt.dx * (_tapScale - 1),
              -_tapAt.dy * (_tapScale - 1),
              0,
              1,
            )
            ..scaleByDouble(_tapScale, _tapScale, 1, 1));
    _zoomTo = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOut));
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final caption = _scaleLabel(widget.scale);
    final details = caption.isEmpty
        ? l10n.orderSlidesTitle
        : '${l10n.orderSlidesTitle} · $caption';
    final hasOrder = widget.orderNumber.isNotEmpty;
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMargin,
                AppSpacing.md,
                AppSpacing.screenMargin,
                0,
              ),
              // As the order's own header: its number, the slide beneath.
              child: TopBar(
                backLabel: l10n.commonBack,
                onBack: () => Navigator.of(context).pop(),
                title: hasOrder ? widget.orderNumber : details,
                subtitle: hasOrder ? details : null,
              ),
            ),
            Expanded(
              child: GestureDetector(
                onDoubleTapDown: (details) => _tapAt = details.localPosition,
                onDoubleTap: _doubleTap,
                child: InteractiveViewer(
                  transformationController: _transform,
                  maxScale: _maxScale,
                  child: Center(
                    child: Image.network(widget.url, fit: .contain),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
