import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_shadows.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/app_status_colors.dart';
import 'package:tabibu/core/constants/app_styles.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/preread/presentation/widgets/region_capture.dart';
import 'package:tabibu/gen/assets.gen.dart';

/// Pan/zoom slide panel: optional heatmap overlay, tiles and region-read
/// entries, viridis legend. Labels and images come from the caller.
class SlideViewer extends StatefulWidget {
  const SlideViewer({
    required this.image,
    required this.heatmapOn,
    required this.onHeatmapChanged,
    required this.heatmapLabel,
    required this.tilesLabel,
    required this.scaleLabel,
    required this.legendLow,
    required this.legendHigh,
    required this.zoomInLabel,
    required this.zoomOutLabel,
    this.onTiles,
    this.heatmap,
    this.askRegionLabel = '',
    this.askRegionSemanticLabel,
    this.onAskRegion,
    this.regionCaptureController,
    super.key,
  });

  final ImageProvider image;
  final bool heatmapOn;
  final ValueChanged<bool> onHeatmapChanged;
  final String heatmapLabel;
  final String tilesLabel;

  /// Null hides the Tiles control (CS-03 is not built yet).
  final VoidCallback? onTiles;

  /// Null hides the region-read entry; the label is unused then.
  final VoidCallback? onAskRegion;
  final String askRegionLabel;

  /// The full action for screen readers when [askRegionLabel] is short.
  final String? askRegionSemanticLabel;

  /// When set, binds region capture: the base image renders inside a
  /// boundary, and captures cut the visible region from it. Heatmap and
  /// controls stay outside and never reach the model.
  final RegionCaptureController? regionCaptureController;
  final String scaleLabel;
  final String legendLow;
  final String legendHigh;
  final String zoomInLabel;
  final String zoomOutLabel;
  final ImageProvider? heatmap;

  static const double minScale = 1;
  static const double maxScale = 8;
  static const double zoomStep = 0.5;

  /// Where a double tap lands when the slide is at 1×.
  static const double doubleTapScale = 2.5;
  static const Duration zoomDuration = Duration(milliseconds: 200);

  @override
  State<SlideViewer> createState() => _SlideViewerState();
}

class _SlideViewerState extends State<SlideViewer>
    with TickerProviderStateMixin {
  late final TransformationController _transform;
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  AnimationController? _zoom;
  CurvedAnimation? _curve;
  Offset? _doubleTapAt;
  var _hasFrame = false;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController();
    widget.regionCaptureController?.capture = _captureRegion;
  }

  @override
  void didUpdateWidget(covariant SlideViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionCaptureController != widget.regionCaptureController) {
      oldWidget.regionCaptureController?.capture = null;
      widget.regionCaptureController?.capture = _captureRegion;
    }
    if (oldWidget.image != widget.image) _hasFrame = false;
  }

  @override
  void dispose() {
    widget.regionCaptureController?.capture = null;
    _curve?.dispose();
    _curve = null;
    _zoom?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<Uint8List?> _captureRegion() {
    // No frame, no pixels: placeholders and the error fallback refuse.
    if (!_hasFrame) return Future.value();
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    final viewport = _viewportKey.currentContext?.size;
    if (boundary == null || viewport == null) return Future.value();
    return captureVisibleRegion(
      boundary: boundary,
      transform: _transform.value,
      viewportSize: viewport,
    );
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  /// A plain scale is about the image's top-left, so the picture walks into
  /// a corner. Scale about [viewportPoint] and the scene under it stays put.
  Matrix4 _scaledAbout(Matrix4 matrix, double ratio, Offset viewportPoint) {
    final scene = MatrixUtils.transformPoint(
      Matrix4.inverted(matrix),
      viewportPoint,
    );
    return matrix.clone()
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
  }

  void _cancelZoom() {
    _curve?.dispose();
    _curve = null;
    _zoom?.dispose();
    _zoom = null;
  }

  void _runZoom(void Function(double t) apply) {
    _cancelZoom();
    final controller = AnimationController(
      vsync: this,
      duration: SlideViewer.zoomDuration,
    );
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    curved.addListener(() {
      apply(curved.value);
      if (mounted) setState(() {});
    });
    _zoom = controller;
    _curve = curved;
    controller.forward();
  }

  void _nudgeScale(double delta) {
    final size = _viewportKey.currentContext?.size;
    if (size == null || size.isEmpty) return;
    final next = (_scale + delta).clamp(
      SlideViewer.minScale,
      SlideViewer.maxScale,
    );
    if (next == _scale) return;
    _cancelZoom();
    final ratio = next / _scale;
    final centre = Offset(size.width / 2, size.height / 2);
    _transform.value = _scaledAbout(_transform.value, ratio, centre);
    setState(() {});
  }

  /// Zoom in about the tapped point. A second double tap, once zoomed,
  /// comes back to the whole slide.
  void _doubleTap() {
    final point = _doubleTapAt;
    if (point == null) return;
    if (_scale > 1.01) {
      final tween = Matrix4Tween(
        begin: _transform.value.clone(),
        end: Matrix4.identity(),
      );
      _runZoom((t) => _transform.value = tween.transform(t));
      return;
    }
    final begin = _transform.value.clone();
    final beginScale = _scale;
    final target = SlideViewer.doubleTapScale.clamp(
      SlideViewer.minScale,
      SlideViewer.maxScale,
    );
    _runZoom((t) {
      final scale = beginScale + (target - beginScale) * t;
      _transform.value = _scaledAbout(begin, scale / beginScale, point);
    });
  }

  Widget _regionBoundary(Widget child) {
    if (widget.regionCaptureController == null) return child;
    return RepaintBoundary(key: _boundaryKey, child: child);
  }

  Widget _fallback(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Center(
        child: AssetIcon(
          Assets.icons.photoIcon,
          size: 32,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = Theme.of(context).extension<AppStatusColors>()!;
    final textTheme = Theme.of(context).textTheme;
    final isDark = scheme.brightness == .dark;
    final onInk = isDark ? AppColors.inkLight : AppColors.white;
    final heatmap = widget.heatmap;
    final imageRadius = BorderRadius.circular(AppRadii.card);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.card(),
      ),
      child: Padding(
        padding: AppStyles.cardPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Prefer 4:3; shrink under a tight parent so the legend still fits.
            var imageHeight = width * 3 / 4;
            if (constraints.hasBoundedHeight) {
              const legendBlock = AppSpacing.sm + 20;
              final budget = constraints.maxHeight - legendBlock;
              if (budget > 0 && budget < imageHeight) {
                imageHeight = budget;
              }
            }

            return Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  key: _viewportKey,
                  width: width,
                  height: imageHeight,
                  child: ClipRRect(
                    borderRadius: imageRadius,
                    child: Stack(
                      fit: .expand,
                      children: [
                        GestureDetector(
                          onDoubleTapDown: (details) =>
                              _doubleTapAt = details.localPosition,
                          onDoubleTap: _doubleTap,
                          child: InteractiveViewer(
                            transformationController: _transform,
                            minScale: SlideViewer.minScale,
                            maxScale: SlideViewer.maxScale,
                            child: Stack(
                              fit: .expand,
                              children: [
                                Positioned.fill(
                                  child: _regionBoundary(
                                    Image(
                                      image: widget.image,
                                      fit: .cover,
                                      frameBuilder: (context, child, frame, _) {
                                        if (frame != null && !_hasFrame) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (mounted && !_hasFrame) {
                                                  setState(
                                                    () => _hasFrame = true,
                                                  );
                                                }
                                              });
                                        }
                                        return child;
                                      },
                                      errorBuilder: (_, _, _) =>
                                          _fallback(scheme),
                                    ),
                                  ),
                                ),
                                if (widget.heatmapOn && heatmap != null)
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.55,
                                      child: Image(
                                        image: heatmap,
                                        fit: .cover,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: AppSpacing.xs,
                          left: AppSpacing.xs,
                          right: AppSpacing.xs,
                          child: Row(
                            crossAxisAlignment: .start,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: AppSpacing.xs,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    _HeatmapPill(
                                      label: widget.heatmapLabel,
                                      value: widget.heatmapOn,
                                      onChanged: widget.onHeatmapChanged,
                                    ),
                                    if (widget.onTiles != null)
                                      _ActionPill(
                                        label: widget.tilesLabel,
                                        onTap: widget.onTiles!,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              _ZoomPill(
                                zoomInLabel: widget.zoomInLabel,
                                zoomOutLabel: widget.zoomOutLabel,
                                onZoomIn: () =>
                                    _nudgeScale(SlideViewer.zoomStep),
                                onZoomOut: () =>
                                    _nudgeScale(-SlideViewer.zoomStep),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: AppSpacing.xs,
                          bottom: AppSpacing.xs,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: status.ink,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              child: Text(
                                widget.scaleLabel,
                                style: textTheme.labelSmall?.copyWith(
                                  color: onInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Bottom right, clear of the controls and the
                        // scale: it asks about what the frame shows.
                        if (widget.onAskRegion != null && _hasFrame)
                          Positioned(
                            right: AppSpacing.xs,
                            bottom: AppSpacing.xs,
                            child: _ActionPill(
                              label: widget.askRegionLabel,
                              semanticLabel: widget.askRegionSemanticLabel,
                              // The AI pre-read's mark: this answer is AI.
                              leading: Assets.icons.sparkleIcon,
                              onTap: widget.onAskRegion!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Text(
                      widget.legendLow,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          gradient: const LinearGradient(
                            colors: AppColors.overlayHeatmap,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      widget.legendHigh,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeatmapPill extends StatelessWidget {
  const _HeatmapPill({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: label,
        toggled: value,
        onTap: () => onChanged(!value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: AppShadows.card(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: .min,
              children: [
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: .w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                ExcludeSemantics(
                  child: Switch.adaptive(
                    value: value,
                    onChanged: onChanged,
                    materialTapTargetSize: .shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.leading,
  });

  final String label;
  final VoidCallback onTap;

  /// What a screen reader hears when [label] is shortened on screen.
  final String? semanticLabel;

  /// Drawn before [label] in the AI-draft colour.
  final SvgGenImage? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      onTap: onTap,
      excludeSemantics: semanticLabel != null,
      child: Tappable(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: AppShadows.card(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: .min,
              children: [
                if (leading case final leading?) ...[
                  AssetIcon(
                    leading,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).extension<AppStatusColors>()!.aiDraft,
                    scaleUp: false,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: .w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({
    required this.zoomInLabel,
    required this.zoomOutLabel,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final String zoomInLabel;
  final String zoomOutLabel;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    // Two round controls with air between them, not one block.
    return Column(
      mainAxisSize: .min,
      children: [
        CircleIconButton(
          icon: Assets.icons.zoomInIcon,
          semanticLabel: zoomInLabel,
          onTap: onZoomIn,
          iconSize: 20,
        ),
        const SizedBox(height: AppSpacing.xs),
        CircleIconButton(
          icon: Assets.icons.zoomOutIcon,
          semanticLabel: zoomOutLabel,
          onTap: onZoomOut,
          iconSize: 20,
        ),
      ],
    );
  }
}
