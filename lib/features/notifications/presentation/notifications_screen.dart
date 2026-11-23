import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/role_helper.dart';
import 'package:tabibu/core/utils/nairobi_time.dart';
import 'package:tabibu/core/utils/settle_refresh.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_bloc.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_event.dart';
import 'package:tabibu/features/appointments/blocs/appointments_bloc/appointments_state.dart';
import 'package:tabibu/features/appointments/presentation/widgets/decline_booking_sheet.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_bloc.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/conversations/presentation/mdt_routes.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_bloc.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_event.dart';
import 'package:tabibu/features/notifications/blocs/notifications_bloc/notifications_state.dart';
import 'package:tabibu/features/notifications/data/models/notification_model.dart';
import 'package:tabibu/features/notifications/presentation/notification_target.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// P-02, PA-05 and the doctor notifications frame. One inbox for all three
/// roles; only the empty sentence changes with the role (N-19).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.role, super.key});

  final Role role;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _MenuAction { markAllRead, refresh }

enum _Group { today, yesterday, earlier }

class _NotificationsScreenState extends State<NotificationsScreen> {
  final GlobalKey _menuKey = GlobalKey();

  late final String _uid;
  late final RoleHelper _roles;

  /// The invite row being answered, and which button was tapped.
  /// A second tap while this is set does nothing.
  String? _answeringUid;
  bool _answeringAccept = false;
  String _answeringConversation = '';
  String _answeringTemplate = '';

  /// Rows this screen has settled: a decline, or a refusal from the server.
  final Map<String, NotificationActionStatus> _settled = {};

  /// Africa/Nairobi is a fixed UTC+3 with no daylight saving; grouping and
  /// times use it, never the device zone (N-10).

  @override
  void initState() {
    super.initState();
    final session = context.read<AuthBloc>().state.session;
    _uid = switch (session) {
      PatientSession(:final patient) => patient.uid,
      PractitionerSession(:final doctor) => doctor.uid,
      _ => '',
    };
    _roles = switch (session) {
      PatientSession(:final roles) => roles,
      PractitionerSession(:final roles) => roles,
      _ => RoleHelper.none,
    };
    context.read<NotificationsBloc>().add(NotificationsRequested(uid: _uid));
    // A booking is answered only once it is on the phone, and a new one
    // may not be in an older list, so the appointments always sync here.
    if (widget.role == .doctor) {
      context.read<AppointmentsBloc>().add(
        AppointmentsRequested(uid: _uid, role: widget.role),
      );
    }
  }

  Future<void> _refresh() async {
    final bloc = context.read<NotificationsBloc>()
      ..add(NotificationsRefreshed(uid: _uid));
    await settleRefresh<NotificationsState>(
      bloc.stream,
      (state) => state is NotificationsLoadInProgress,
    );
  }

  Future<void> _openMenu() async {
    final action = await showOptionsMenu<_MenuAction>(
      context,
      anchor: _menuKey,
      actions: [
        OptionsAction(
          value: _MenuAction.markAllRead,
          icon: Assets.icons.tickIcon,
          label: context.l10n.notificationsMarkAllRead,
        ),
        OptionsAction(
          value: _MenuAction.refresh,
          icon: Assets.icons.refreshIcon,
          label: context.l10n.notificationsRefresh,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _MenuAction.markAllRead:
        context.read<NotificationsBloc>().add(
          NotificationsAllReadRequested(uid: _uid),
        );
      case _MenuAction.refresh:
        context.read<NotificationsBloc>().add(
          NotificationsRefreshed(uid: _uid),
        );
      case null:
        break;
    }
  }

  bool _loading(NotificationModel row, {required bool accept}) =>
      _answeringUid == row.uid && _answeringAccept == accept;

  /// Pending, unexpired, and addressed to the person reading the inbox.
  bool _canAnswer(NotificationModel row) {
    if (widget.role == .patient || row.recipientUid != _uid) return false;
    if (_settled.containsKey(row.uid)) return false;
    final invite = row.templateKey == NotificationTemplate.mdtInvited.value;
    final booking =
        row.templateKey == NotificationTemplate.appointmentRequested.value &&
        widget.role == .doctor;
    if (!invite && !booking) return false;
    if (booking && !_bookingPending(row.resourceUid)) return false;
    return row.isActionable(DateTime.now().toUtc());
  }

  bool _bookingPending(String appointmentUid) =>
      context
          .read<AppointmentsBloc>()
          .state
          .appointments
          .firstWhereOrNull((a) => a.uid == appointmentUid)
          ?.isRequested ??
      false;

  Future<void> _answer(NotificationModel row, {required bool accept}) async {
    if (_answeringUid != null || row.resourceUid.isEmpty) return;
    if (row.templateKey == NotificationTemplate.appointmentRequested.value) {
      await _answerBooking(row, accept: accept);
      return;
    }
    setState(() {
      _answeringUid = row.uid;
      _answeringAccept = accept;
      _answeringConversation = row.resourceUid;
      _answeringTemplate = row.templateKey;
    });
    context.read<MdtBloc>().add(
      MdtRespondRequested(
        uid: _uid,
        conversationUid: row.resourceUid,
        accept: accept,
      ),
    );
  }

  /// The booking request's own answer: Accept as it is, Decline through the
  /// same reason sheet the booking requests screen uses.
  Future<void> _answerBooking(
    NotificationModel row, {
    required bool accept,
  }) async {
    final appointments = context.read<AppointmentsBloc>();
    DeclineChoice? choice;
    if (!accept) {
      final name =
          appointments.state.appointments
              .firstWhereOrNull((a) => a.uid == row.resourceUid)
              ?.patientName ??
          '';
      choice = await DeclineBookingSheet.show(context, name: name);
      if (choice == null || !mounted) return;
    }
    setState(() {
      _answeringUid = row.uid;
      _answeringAccept = accept;
      _answeringConversation = '';
      _answeringTemplate = row.templateKey;
    });
    appointments.add(
      AppointmentDecisionRequested(
        appointmentUid: row.resourceUid,
        accept: accept,
        reason: choice?.reason,
        note: choice?.note ?? '',
      ),
    );
  }

  void _onAppointments(BuildContext context, AppointmentsState state) {
    final uid = _answeringUid;
    if (uid == null ||
        _answeringTemplate != NotificationTemplate.appointmentRequested.value) {
      return;
    }
    switch (state) {
      case AppointmentDecisionSuccess():
        setState(() {
          _answeringUid = null;
          _settled[uid] = _answeringAccept
              ? NotificationActionStatus.accepted
              : NotificationActionStatus.declined;
        });
        context.read<AppointmentsBloc>().add(
          AppointmentsRefreshed(uid: _uid, role: widget.role),
        );
      case AppointmentWriteFailure(:final error):
        // Not on the phone yet: sync and let the doctor try again.
        final missing = error == AppError.dataNotFound;
        setState(() {
          _answeringUid = null;
          if (error != AppError.noInternet && !missing) {
            _settled[uid] = NotificationActionStatus.cancelled;
          }
        });
        if (missing) {
          context.read<AppointmentsBloc>().add(
            AppointmentsRefreshed(uid: _uid, role: widget.role),
          );
        }
      default:
        break;
    }
  }

  void _onMdt(BuildContext context, MdtState state) {
    final uid = _answeringUid;
    if (uid == null ||
        _answeringTemplate != NotificationTemplate.mdtInvited.value) {
      return;
    }
    switch (state) {
      case MdtWriteSuccess():
        final accept = _answeringAccept;
        final conversationUid = _answeringConversation;
        setState(() {
          _answeringUid = null;
          _settled[uid] = accept
              ? NotificationActionStatus.accepted
              : NotificationActionStatus.declined;
        });
        if (!accept || conversationUid.isEmpty) return;
        context.read<MdtBloc>().add(MdtRefreshed(uid: _uid, role: widget.role));
        unawaited(
          mdtConsultRoute(widget.role, conversationUid).push<void>(context),
        );
      case MdtWriteFailure(:final error):
        setState(() {
          _answeringUid = null;
          // A network miss can be tried again. A refusal cannot.
          if (error != AppError.noInternet) {
            _settled[uid] = NotificationActionStatus.cancelled;
          }
        });
      default:
        break;
    }
  }

  void _onRowTap(NotificationModel row) {
    context.read<NotificationsBloc>().add(
      NotificationReadRequested(uid: _uid, notificationUid: row.uid),
    );
    // Share-first (T-18), same path as push and banner taps.
    final target = notificationRowTarget(row, _roles);
    unawaited(target?.push<void>(context));
  }

  _Group _groupOf(DateTime? time, DateTime now) {
    if (time == null) return _Group.earlier;
    final behind = nairobiDaysBefore(time, now);
    if (behind <= 0) return _Group.today;
    if (behind == 1) return _Group.yesterday;
    return _Group.earlier;
  }

  String? _trailingText(DateTime? time, DateTime now, Locale locale) {
    if (time == null) return null;
    final behind = nairobiDaysBefore(time, now);
    final tag = locale.toString();
    if (behind <= 0) return DateFormat('h:mm a', tag).format(time);
    if (behind < 7) return DateFormat('EEE', tag).format(time);
    return DateFormat('d MMM', tag).format(time);
  }

  @override
  Widget build(BuildContext context) {
    // Booking rows offer answers once their booking loads.
    context.select<AppointmentsBloc, Object>((b) => b.state.appointments);
    final body = SafeArea(
      child: MultiBlocListener(
        listeners: [
          BlocListener<MdtBloc, MdtState>(listener: _onMdt),
          BlocListener<AppointmentsBloc, AppointmentsState>(
            listener: _onAppointments,
          ),
        ],
        child: BlocConsumer<NotificationsBloc, NotificationsState>(
          listener: (context, state) {
            if (state is NotificationsLoadFailure) {
              unawaited(
                showTabibuNotification(
                  context,
                  message: state.error.description(context.l10n),
                  isError: true,
                  dismissLabel: context.l10n.commonDismiss,
                ),
              );
            }
          },
          builder: (context, state) => RefreshIndicator.adaptive(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _slivers(context, state),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: switch (widget.role) {
        .patient => RoleBackground.patient(child: body),
        .doctor => RoleBackground.doctor(child: body),
        .pathologist => RoleBackground.pathologist(child: body),
      },
    );
  }

  List<Widget> _slivers(BuildContext context, NotificationsState state) {
    const sides = EdgeInsets.fromLTRB(
      AppSpacing.screenMargin,
      AppSpacing.md,
      AppSpacing.screenMargin,
      0,
    );
    final l10n = context.l10n;
    final items = state.items;
    final loaded =
        state is NotificationsLoadSuccess || state is NotificationsLoadFailure;
    return [
      SliverPadding(
        padding: sides,
        sliver: SliverToBoxAdapter(
          child: TopBar(
            title: l10n.notificationsTitle,
            backLabel: l10n.commonBack,
            onBack: context.pop,
            // The doctor's empty frame has no menu (N-19).
            trailing: items.isEmpty && loaded
                ? null
                : MoreButton(
                    key: _menuKey,
                    semanticLabel: l10n.notificationsMoreLabel,
                    onTap: _openMenu,
                  ),
          ),
        ),
      ),
      if (state.offline)
        SliverPadding(
          padding: sides,
          sliver: SliverToBoxAdapter(
            child: ConnectivityBanner(
              state: .offline,
              title: l10n.notificationsOfflineTitle,
              body: l10n.notificationsOfflineBody,
            ),
          ),
        ),
      if (items.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenMargin,
            0,
            AppSpacing.screenMargin,
            AppSpacing.md,
          ),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: loaded
                  ? EmptyState(
                      title: l10n.notificationsEmptyTitle,
                      icon: Assets.icons.shieldIcon,
                      tone: .mint,
                      body: switch (widget.role) {
                        .patient => l10n.notificationsEmptyBodyPatient,
                        .doctor => l10n.notificationsEmptyBodyDoctor,
                        .pathologist => l10n.notificationsEmptyBodyPathologist,
                      },
                    )
                  : LoadingView(semanticLabel: l10n.notificationsLoadingLabel),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenMargin,
            AppSpacing.md,
            AppSpacing.screenMargin,
            AppSpacing.md,
          ),
          sliver: SliverList.list(children: _groupedRows(context, items)),
        ),
    ];
  }

  List<Widget> _groupedRows(
    BuildContext context,
    List<NotificationModel> items,
  ) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final now = nairobiNow();
    final groups = <_Group, List<NotificationModel>>{
      for (final group in _Group.values) group: [],
    };
    for (final row in items) {
      groups[_groupOf(nairobiTimeOf(row.creationDate), now)]!.add(row);
    }
    final titles = {
      _Group.today: l10n.notificationsToday,
      _Group.yesterday: l10n.notificationsYesterday,
      _Group.earlier: l10n.notificationsEarlier,
    };
    final children = <Widget>[];
    var first = true;
    for (final group in _Group.values) {
      final rows = groups[group]!;
      if (rows.isEmpty) continue;
      if (!first) {
        children.add(const SizedBox(height: AppSpacing.sectionGap));
      }
      first = false;
      children
        ..add(SectionHeader(title: titles[group]!))
        ..add(const SizedBox(height: AppSpacing.sm));
      var firstRow = true;
      for (final row in rows) {
        if (!firstRow) {
          children.add(const SizedBox(height: AppSpacing.sm));
        }
        firstRow = false;
        children.add(
          _row(
            context,
            row,
            _trailingText(nairobiTimeOf(row.creationDate), now, locale),
          ),
        );
      }
    }
    return children;
  }

  Widget _row(
    BuildContext context,
    NotificationModel row,
    String? trailingText,
  ) {
    final l10n = context.l10n;
    final template = NotificationTemplate.fromValue(row.templateKey);
    final title = template.title(l10n, row.templateArgs);
    final declined = _settled[row.uid] == NotificationActionStatus.declined;
    final answer = _canAnswer(row);
    // The inbox re-renders from the template in the current language; a row
    // whose template the app does not know keeps the server's copy.
    final subtitle = template == NotificationTemplate.unknown
        ? row.message
        : template.body(l10n, row.templateArgs);
    final (icon, tone) = switch (row.categoryValue) {
      .appointment => (Assets.icons.calendarIcon, IconTone.sky),
      .report || .result => (Assets.icons.resultsIcon, IconTone.lavender),
      .preread => (Assets.icons.inProgressIcon, IconTone.lavender),
      .alert => (Assets.icons.infoIcon, IconTone.butter),
      .patientCase => (Assets.icons.testTubeIcon, IconTone.mint),
      .mdt || .message => (Assets.icons.mdtIcon, IconTone.mint),
      .account => (Assets.icons.personIcon, IconTone.sky),
    };
    final card = ListRowCard(
      leading: IconTile(icon: icon, tone: tone),
      title: title.isEmpty ? row.title : title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      // The code a signed or shared report opens with is for this reader's own
      // eyes: it is shown here and typed on the enter-code screen (T-18). It
      // never goes in a route, a log or a field.
      chip: declined
          ? StatusChip(label: l10n.appointmentsDeclined, tone: .info)
          : row.hasShareCode
          ? StatusChip(
              label: l10n.notificationAccessCode(row.metadata.shareCode),
              tone: .info,
            )
          : null,
      trailingText: trailingText,
      unread: !row.isRead,
      chevron: false,
      onTap: () => _onRowTap(row),
    );
    if (!answer) return card;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        card,
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TabibuButton.primary(
                key: ValueKey('mdt-accept-${row.uid}'),
                label: l10n.mdtAccept,
                isLoading: _loading(row, accept: true),
                onTap: () => _answer(row, accept: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TabibuButton.outline(
                key: ValueKey('mdt-decline-${row.uid}'),
                label: l10n.mdtDecline,
                isLoading: _loading(row, accept: false),
                onTap: () => _answer(row, accept: false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
