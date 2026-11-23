import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The demo mark, in the timeline's Now tone. [Align] gives the chip loose
/// constraints: its own width beside a stretched parent, and it wraps,
/// never overflows, where large text leaves it less room.
class AlertDemoPill extends StatelessWidget {
  const AlertDemoPill({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.alertDemoPillSemantics,
      child: ExcludeSemantics(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusChip(label: l10n.alertDemoPill, tone: .attention),
        ),
      ),
    );
  }
}
