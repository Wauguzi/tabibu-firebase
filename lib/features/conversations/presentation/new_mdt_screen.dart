import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/utils/text_fold.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_bloc.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_event.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_bloc.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_event.dart';
import 'package:tabibu/features/conversations/blocs/mdt_bloc/mdt_state.dart';
import 'package:tabibu/features/conversations/presentation/mdt_routes.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_invite_picker.dart';
import 'package:tabibu/features/practitioners/blocs/directory_bloc/directory_bloc.dart';
import 'package:tabibu/features/practitioners/blocs/directory_bloc/directory_event.dart';
import 'package:tabibu/features/practitioners/blocs/directory_bloc/directory_state.dart';
import 'package:tabibu/features/practitioners/data/models/practitioner_model.dart';
import 'package:tabibu/features/reports/presentation/widgets/workspace_step_section.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The most people a consult holds, the owner included (the server's limit).
const mdtMaxMembers = 10;

/// The longest subject the server takes.
const mdtSubjectMaxLength = 1000;

/// About five rows at the default text size. A larger size scrolls inside.
const mdtPickerListHeight = 360.0;

/// D-MDT and PA-MDT · New consult. Pick one of my cases, say what the
/// consult is about (the server requires it), choose who to invite, and
/// send. Nothing is created until the invite is sent.
class NewMdtScreen extends StatefulWidget {
  const NewMdtScreen({required this.role, this.caseUid = '', super.key});

  final Role role;

  /// A case chosen before arriving, from a case's options.
  final String caseUid;

  @override
  State<NewMdtScreen> createState() => _NewMdtScreenState();
}

class _NewMdtScreenState extends State<NewMdtScreen> {
  late final String _uid;
  late final List<String> _ownSpecialties;
  late String _caseUid = widget.caseUid;
  final _about = TextEditingController();
  final _caseQuery = TextEditingController();
  final Set<String> _invitees = {};
  var _pickOpen = true;
  var _inviteOpen = true;

  /// This screen sent the request, so a success belongs to it.
  var _sent = false;

  @override
  void initState() {
    super.initState();
    final doctor = switch (context.read<AuthBloc>().state.session) {
      PractitionerSession(:final doctor) => doctor,
      _ => null,
    };
    _uid = doctor?.uid ?? '';
    _ownSpecialties = doctor?.specialties ?? const [];
    _pickOpen = widget.caseUid.isEmpty;
    final cases = context.read<CasesBloc>();
    if (cases.state.cases.isEmpty) {
      cases.add(CasesRequested(uid: _uid, role: widget.role));
    }
    context.read<DirectoryBloc>().add(const DirectoryRequested());
  }

  @override
  void dispose() {
    _about.dispose();
    _caseQuery.dispose();
    super.dispose();
  }

  /// My cases a consult can be about: the pathologist has accepted, the
  /// case is not over, and it does not already have an open consult.
  List<CaseModel> _eligible(List<CaseModel> all) => [
    for (final c in all)
      if (c.pathologistUid.isNotEmpty && !c.isDone && c.openMdtUid.isEmpty)
        if (widget.role == .pathologist
            ? c.pathologistUid == _uid
            : c.doctorUid == _uid)
          c,
  ];

  /// The specialty the consult is asked in: the first invitee's, else mine.
  String _specialty() {
    final directory = context.read<DirectoryBloc>().state.all;
    for (final uid in _invitees) {
      final found = directory.firstWhereOrNull((p) => p.uid == uid);
      final specialty = found == null ? null : mdtSpecialtyOf(found);
      if (specialty != null) return specialty.value;
    }
    for (final raw in _ownSpecialties) {
      if (Specialty.fromValue(raw) != null) return raw;
    }
    return (widget.role == .pathologist
            ? Specialty.histopathology
            : Specialty.generalPractice)
        .value;
  }

  void _send() {
    final about = _about.text.trim();
    final chosen = _eligible(
      context.read<CasesBloc>().state.cases,
    ).firstWhereOrNull((c) => c.uid == _caseUid);
    if (chosen == null || _invitees.isEmpty || about.isEmpty) return;
    _sent = true;
    context.read<MdtBloc>().add(
      MdtOpenRequested(
        uid: _uid,
        caseUid: chosen.uid,
        specialty: _specialty(),
        description: about,
        inviteeUids: _invitees.toList(),
      ),
    );
  }

  void _onState(BuildContext context, MdtState state) {
    switch (state) {
      case MdtWriteSuccess(:final openedConversationUid)
          when _sent && openedConversationUid.isNotEmpty:
        _sent = false;
        // Replaces the form, so back never returns to a sent invite.
        mdtConsultRoute(
          widget.role,
          openedConversationUid,
        ).pushReplacement(context);
      case MdtWriteFailure(:final error) when _sent:
        _sent = false;
        unawaited(
          showTabibuNotification(
            context,
            message: error.description(context.l10n),
            isError: true,
            dismissLabel: context.l10n.commonDismiss,
          ),
        );
      default:
        break;
    }
  }

  /// The step strings already carry their number. The section adds it again.
  String _stepName(String numbered) {
    const mark = ' · ';
    final at = numbered.indexOf(mark);
    return at < 0 ? numbered : numbered.substring(at + mark.length);
  }

  List<CaseModel> _matching(List<CaseModel> cases, String needle) {
    if (needle.isEmpty) return cases;
    return [
      for (final c in cases)
        if (_caseHaystack(c).contains(needle)) c,
    ];
  }

  String _caseHaystack(CaseModel c) => [
    c.orderNumber,
    c.patientName,
    for (final test in c.tests) test.name,
  ].map(foldForSearch).join(' ');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final cases = _eligible(context.watch<CasesBloc>().state.cases);
    final chosen = cases.firstWhereOrNull((c) => c.uid == _caseUid);
    final caseUid = chosen?.uid ?? '';
    final directory = context.watch<DirectoryBloc>().state;
    final writing = context.watch<MdtBloc>().state is MdtWriteInProgress;
    final candidates = mdtInvitable(directory.all, myUid: _uid);
    final background = widget.role == .pathologist
        ? RoleBackground.pathologist
        : RoleBackground.doctor;
    final about = _about.text.trim();
    final ready =
        caseUid.isNotEmpty && _invitees.isNotEmpty && about.isNotEmpty;
    final needle = foldForSearch(_caseQuery.text);
    final shown = _matching(cases, needle);
    final caseHeading = chosen == null
        ? ''
        : l10n.mdtCasePatient(chosen.orderNumber, chosen.patientName);

    return BlocListener<MdtBloc, MdtState>(
      listenWhen: (_, current) =>
          current is MdtWriteSuccess || current is MdtWriteFailure,
      listener: _onState,
      child: Scaffold(
        body: background(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenMargin,
                    AppSpacing.md,
                    AppSpacing.screenMargin,
                    0,
                  ),
                  child: TopBar(
                    title: l10n.mdtNewTitle,
                    backLabel: l10n.commonBack,
                    onBack: context.pop,
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior: .onDrag,
                    padding: const EdgeInsets.all(AppSpacing.screenMargin),
                    children: [
                      WorkspaceStepSection(
                        number: 1,
                        title: _stepName(l10n.mdtPickCase),
                        status: chosen == null ? .toDo : .done,
                        statusLabel: chosen == null
                            ? l10n.workspaceStepToDo
                            : caseHeading,
                        expanded: chosen == null || _pickOpen,
                        onToggle: () => setState(() => _pickOpen = !_pickOpen),
                        child: _caseStep(l10n, cases, shown, needle),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TabibuTextField(
                        label: l10n.mdtAboutLabel,
                        hint: l10n.mdtAboutHint,
                        controller: _about,
                        required: true,
                        maxLength: mdtSubjectMaxLength,
                        textInputAction: .done,
                        // The server refuses markup in the subject.
                        inputFormatters: [
                          FilteringTextInputFormatter.deny('<'),
                        ],
                        errorText:
                            caseUid.isNotEmpty &&
                                _invitees.isNotEmpty &&
                                about.isEmpty
                            ? l10n.mdtAboutRequired
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      WorkspaceStepSection(
                        number: 2,
                        title: _stepName(l10n.mdtInviteStep),
                        status: _invitees.isEmpty ? .toDo : .done,
                        statusLabel: _invitees.isEmpty
                            ? l10n.workspaceStepToDo
                            : l10n.workspaceStepDone,
                        expanded: _inviteOpen,
                        onToggle: () =>
                            setState(() => _inviteOpen = !_inviteOpen),
                        child: _inviteStep(l10n, directory, candidates),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.mdtStaysOpen, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                BottomActionBar(
                  primary: TabibuButton.primary(
                    label: l10n.mdtSendInvite,
                    isLoading: writing,
                    onTap: ready && !writing ? _send : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _caseStep(
    AppLocalizations l10n,
    List<CaseModel> cases,
    List<CaseModel> shown,
    String needle,
  ) {
    if (cases.isEmpty) {
      return EmptyState(
        title: l10n.doctorCasesEmptyTitle,
        body: l10n.doctorCasesEmptyBody,
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SearchField(
          hint: l10n.doctorCasesSearchHint,
          clearLabel: MaterialLocalizations.of(context).deleteButtonTooltip,
          controller: _caseQuery,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          EmptyState(
            title: l10n.findDoctorNoResultsTitle(_caseQuery.text.trim()),
            body: l10n.findDoctorNoResultsBody,
          )
        else
          SizedBox(
            key: const Key('mdt-case-list'),
            height: mdtPickerListHeight,
            child: ListView(
              primary: false,
              padding: EdgeInsets.zero,
              children: [
                for (final c in shown) ...[
                  _CaseOption(
                    caseModel: c,
                    selected: c.uid == _caseUid,
                    onTap: () => setState(() {
                      _caseUid = c.uid;
                      _pickOpen = false;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _inviteStep(
    AppLocalizations l10n,
    DirectoryState directory,
    List<PractitionerModel> candidates,
  ) {
    if (directory.all.isEmpty &&
        (directory is DirectoryInitial ||
            directory is DirectoryLoadInProgress)) {
      return SizedBox(
        height: 160,
        child: LoadingView(semanticLabel: l10n.findDoctorLoadingLabel),
      );
    }
    return MdtInvitePicker(
      candidates: candidates,
      selected: _invitees,
      limit: mdtMaxMembers - 1,
      listMaxHeight: mdtPickerListHeight,
      onToggle: (uid) => setState(() {
        if (!_invitees.remove(uid)) _invitees.add(uid);
      }),
    );
  }
}

class _CaseOption extends StatelessWidget {
  const _CaseOption({
    required this.caseModel,
    required this.selected,
    required this.onTap,
  });

  final CaseModel caseModel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final test = caseModel.tests.firstOrNull?.name ?? '';
    // Signed or beyond is the doctor's third step.
    final supporting = caseModel.doctorStep >= 3
        ? l10n.mdtCaseSigned(test)
        : l10n.mdtCaseWithPathologist(test);
    return OptionCard(
      title: l10n.mdtCasePatient(caseModel.orderNumber, caseModel.patientName),
      supporting: supporting,
      icon: Assets.icons.documentIcon,
      selected: selected,
      onTap: onTap,
    );
  }
}
