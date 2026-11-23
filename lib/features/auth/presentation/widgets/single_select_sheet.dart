import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';

/// A searchable single-select list in a bottom sheet (county, title). Tapping
/// a row pops with it; dismissing pops null.
Future<T?> showSingleSelectSheet<T extends Object>({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<T> items,
  required String Function(T item) label,
  required T? selected,
}) => TabibuBottomSheet.show<T>(
  context,
  title: title,
  builder: (context) => _SingleSelectBody<T>(
    searchHint: searchHint,
    items: items,
    label: label,
    selected: selected,
  ),
);

class _SingleSelectBody<T extends Object> extends StatefulWidget {
  const _SingleSelectBody({
    required this.searchHint,
    required this.items,
    required this.label,
    required this.selected,
  });

  final String searchHint;
  final List<T> items;
  final String Function(T item) label;
  final T? selected;

  @override
  State<_SingleSelectBody<T>> createState() => _SingleSelectBodyState<T>();
}

class _SingleSelectBodyState<T extends Object>
    extends State<_SingleSelectBody<T>> {
  final _searchController = TextEditingController();
  String _query = '';
  double? _bodyHeight;
  var _measureScheduled = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The sheet sizes its child to the child's height, so a fraction of the
  /// screen leaves the rest of the sheet empty. Measure the gap under this
  /// body instead, and fill it.
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final next = _heightToSheetBottom();
      if (next == null) return;
      final current = _bodyHeight;
      if (current != null && (next - current).abs() < 1) return;
      setState(() => _bodyHeight = next);
    });
  }

  double? _heightToSheetBottom() {
    final box = context.findRenderObject() as RenderBox?;
    final scrollable = Scrollable.maybeOf(context);
    final scrollBox = scrollable?.context.findRenderObject() as RenderBox?;
    if (box == null ||
        scrollBox == null ||
        !box.hasSize ||
        !scrollBox.hasSize) {
      return null;
    }
    final top = scrollBox.globalToLocal(box.localToGlobal(Offset.zero)).dy;
    final bottomPadding = _scrollBottomPadding();
    final height = scrollBox.size.height - bottomPadding - top;
    if (height <= 0) return null;
    return height;
  }

  /// Padding between this body and the sheet's scroll view. The safe area
  /// sits outside that view, so it is not part of the gap.
  double _scrollBottomPadding() {
    var bottom = 0.0;
    context.visitAncestorElements((element) {
      if (element.widget is Scrollable) return false;
      final widget = element.widget;
      if (widget is Padding) {
        bottom += widget.padding.resolve(Directionality.of(context)).bottom;
      }
      return true;
    });
    return bottom;
  }

  /// The sheet dismisses from its own scroll position. A downward drag on
  /// the list never reaches that position, so hand the overscroll back.
  bool _handDragToSheet(ScrollNotification notification) {
    if (notification.metrics.axis != .vertical) return false;
    final outer = Scrollable.maybeOf(context)?.position;
    // The dismiss gesture lives on the sheet position, which is not on the
    // public [ScrollPosition] surface.
    if (outer is! ScrollActivityDelegate) return false;
    final drag = outer! as ScrollActivityDelegate;
    if (notification.metrics.pixels > 0) return false;
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      drag.applyUserOffset(-notification.overscroll);
      return true;
    }
    final velocity = notification is ScrollEndNotification
        ? notification.dragDetails?.primaryVelocity
        : null;
    if (velocity != null && velocity > 0) {
      drag.goBallistic(-velocity);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    final l10n = MaterialLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final item in widget.items)
        if (q.isEmpty || widget.label(item).toLowerCase().contains(q)) item,
    ];
    final search = SearchField(
      hint: widget.searchHint,
      clearLabel: l10n.deleteButtonTooltip,
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
    );
    final height = _bodyHeight;
    // Until the sheet has been measured, keep the search and let the list
    // take no space, so the first frame does not overflow an unbounded list.
    if (height == null) {
      return Column(
        mainAxisSize: .min,
        children: [
          search,
          const SizedBox(height: AppSpacing.sm),
        ],
      );
    }
    return SizedBox(
      height: height,
      child: Column(
        children: [
          search,
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _SelectList<T>(
              items: matches,
              label: widget.label,
              selected: widget.selected,
              onDrag: _handDragToSheet,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rows straight on the sheet, split by the Profile menus' hairline: a
/// card with a shadow cannot sit on a sheet. A builder, so a long county
/// list stays lazy.
class _SelectList<T extends Object> extends StatelessWidget {
  const _SelectList({
    required this.items,
    required this.label,
    required this.selected,
    required this.onDrag,
  });

  final List<T> items;
  final String Function(T item) label;
  final T? selected;
  final bool Function(ScrollNotification notification) onDrag;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: onDrag,
      child: ListView.separated(
        primary: false,
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          indent: AppSpacing.md,
          endIndent: AppSpacing.md,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return _SelectRow(
            title: label(item),
            selected: item == selected,
            onTap: () => Navigator.of(context).pop(item),
          );
        },
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The check alone marks the choice: no fill on the sheet.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Tappable(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(fontWeight: .w500),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ExcludeSemantics(
                    child: StatusMark.selection(
                      selected: selected,
                      label: title,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
