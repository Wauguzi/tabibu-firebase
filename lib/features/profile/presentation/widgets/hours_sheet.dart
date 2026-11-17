import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoDatePicker,
        CupertinoTheme,
        CupertinoThemeData,
        showCupertinoModalPopup;
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/presentation/widgets/picker_field.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// A day group's draft from its sheet: whether the days stay open, and the
/// one range every open day shares.
typedef HoursDraft = ({bool open, int startMinute, int endMinute});

/// The weekdays/Saturday/Sunday editors as bottom sheets (D-HOURS). The
/// switch keeps or drops the group's days; Opens and Closes set the one
/// range the backend keeps for all days. The frame's lunch break stays out:
/// it has no field. Answers null when dismissed.
Future<HoursDraft?> showHoursSheet({
  required BuildContext context,
  required String title,
  required bool open,
  required int startMinute,
  required int endMinute,
}) => TabibuBottomSheet.show<HoursDraft>(
  context,
  title: title,
  builder: (context) =>
      _HoursBody(open: open, startMinute: startMinute, endMinute: endMinute),
);

class _HoursBody extends StatefulWidget {
  const _HoursBody({
    required this.open,
    required this.startMinute,
    required this.endMinute,
  });

  final bool open;
  final int startMinute;
  final int endMinute;

  @override
  State<_HoursBody> createState() => _HoursBodyState();
}

class _HoursBodyState extends State<_HoursBody> {
  late bool _open = widget.open;
  late int _start = widget.startMinute;
  late int _end = widget.endMinute;
  bool _badRange = false;

  /// The rules take the :00/:30 grid inside the day; the wheel offers only
  /// those, and its first position must sit on the grid too.
  static int _onGrid(int minutes) => (minutes ~/ 30 * 30).clamp(0, 1410);

  /// The app's Cupertino wheel, as for the date of birth, in half hours.
  /// Turning it sets the time; there is nothing to confirm.
  Future<void> _pick(bool isStart) async {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final minutes = _onGrid(isStart ? _start : _end);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 216,
        padding: const EdgeInsets.only(top: 6),
        margin: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.tile),
            topRight: Radius.circular(AppRadii.tile),
          ),
        ),
        child: SafeArea(
          top: false,
          child: CupertinoTheme(
            data: CupertinoThemeData(brightness: theme.brightness),
            child: CupertinoDatePicker(
              backgroundColor: AppColors.transparent,
              mode: .time,
              minuteInterval: 30,
              use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
              initialDateTime: today.add(Duration(minutes: minutes)),
              onDateTimeChanged: (picked) {
                if (!mounted) return;
                final chosen = _onGrid(picked.hour * 60 + picked.minute);
                setState(() {
                  if (isStart) {
                    _start = chosen;
                  } else {
                    _end = chosen;
                  }
                  _badRange = false;
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  String _time(BuildContext context, int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  void _save() {
    if (_end - _start < 30) {
      setState(() => _badRange = true);
      return;
    }
    Navigator.of(
      context,
    ).pop((open: _open, startMinute: _start, endMinute: _end));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final badRange = _badRange;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _open ? l10n.clinicHoursOpen : l10n.clinicHoursClosedDay,
                  style: textTheme.titleMedium,
                ),
              ),
              Switch(
                value: _open,
                onChanged: (value) => setState(() => _open = value),
                materialTapTargetSize: .shrinkWrap,
              ),
            ],
          ),
        ),
        if (_open) ...[
          const SizedBox(height: AppSpacing.md),
          // Fields that open the wheel, outlined as fields on a sheet are.
          Row(
            crossAxisAlignment: .start,
            children: [
              Expanded(
                child: PickerField(
                  label: l10n.clinicHoursOpens,
                  value: _time(context, _start),
                  leading: Assets.icons.clockIcon,
                  bordered: true,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PickerField(
                  label: l10n.clinicHoursCloses,
                  value: _time(context, _end),
                  leading: Assets.icons.clockIcon,
                  bordered: true,
                  onTap: () => _pick(false),
                ),
              ),
            ],
          ),
          if (badRange) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.clinicHoursBadRange,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        NoticeCard(
          variant: .info,
          icon: Assets.icons.infoIcon,
          body: l10n.clinicHoursBookedStay,
        ),
        const SizedBox(height: AppSpacing.md),
        TabibuButton.primary(label: l10n.clinicHoursSave, onTap: _save),
      ],
    );
  }
}
