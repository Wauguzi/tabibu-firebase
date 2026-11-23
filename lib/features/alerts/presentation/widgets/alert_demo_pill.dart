import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The demo mark, in the timeline's Now tone. A row, not a stretched
/// parent: [StatusChip] flexes to the width it is given.
class AlertDemoPill extends StatelessWidget {
  const AlertDemoPill({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.alertDemoPillSemantics,
      child: ExcludeSemantics(
        child: UnconstrainedBox(
          alignment: AlignmentDirectional.centerStart,
          child: StatusChip(label: l10n.alertDemoPill, tone: .attention),
        ),
      ),
    );
  }
}
