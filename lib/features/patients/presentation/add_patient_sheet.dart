import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoDatePicker,
        CupertinoTheme,
        CupertinoThemeData,
        showCupertinoModalPopup;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_colors.dart';
import 'package:tabibu/core/constants/app_radii.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/presentation/widgets/field_errors.dart';
import 'package:tabibu/features/auth/presentation/widgets/field_icon.dart';
import 'package:tabibu/features/auth/presentation/widgets/picker_field.dart';
import 'package:tabibu/features/auth/presentation/widgets/single_select_sheet.dart';
import 'package:tabibu/features/auth/presentation/widgets/validators.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';
import 'package:uuid/uuid.dart';

/// The sign-up fields a doctor fills for someone with no app account.
/// County, sub-county and language come from the doctor, not this sheet.
class AddPatientSheet extends StatefulWidget {
  const AddPatientSheet({
    required this.doctorUid,
    required this.county,
    required this.subCounty,
    required this.onSave,
    this.language = '',
    super.key,
  });

  final String doctorUid;
  final String county;
  final String subCounty;

  /// The doctor's profile language. An unknown value is stored as English.
  final String language;
  final ValueChanged<PatientModel> onSave;

  static Future<PatientModel?> show(
    BuildContext context, {
    required String doctorUid,
    required String county,
    required String subCounty,
    String language = '',
  }) {
    final l10n = context.l10n;
    return TabibuBottomSheet.show<PatientModel>(
      context,
      title: l10n.addPatientTitle,
      builder: (sheetContext) => AddPatientSheet(
        doctorUid: doctorUid,
        county: county,
        subCounty: subCounty,
        language: language,
        onSave: (patient) => Navigator.of(sheetContext).pop(patient),
      ),
    );
  }

  @override
  State<AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends State<AddPatientSheet> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  Sex? _sex;
  DateTime? _birthDate;
  AppError? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Female, then male: the order sign-up uses.
  static const _sexes = <Sex>[.female, .male];

  Future<void> _pickSex() async {
    final l10n = context.l10n;
    final picked = await showSingleSelectSheet<Sex>(
      context: context,
      title: l10n.sexLabel,
      searchHint: l10n.deskSearchTitle,
      items: _sexes,
      label: (sex) => sex.description(l10n),
      selected: _sex,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _sex = picked;
      _error = errorAfterChange(_error, .sex);
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).colorScheme.surfaceContainerLowest;
    final opening = _birthDate ?? DateTime(now.year - 25, now.month, now.day);
    setState(() {
      _birthDate = opening;
      _error = errorAfterChange(_error, .dateOfBirth);
    });
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 216,
        padding: const EdgeInsets.only(top: 6),
        margin: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.tile),
            topRight: Radius.circular(AppRadii.tile),
          ),
        ),
        child: SafeArea(
          top: false,
          child: CupertinoTheme(
            data: CupertinoThemeData(brightness: brightness),
            child: CupertinoDatePicker(
              backgroundColor: AppColors.transparent,
              initialDateTime: opening,
              minimumDate: DateTime(1900),
              maximumDate: now,
              mode: .date,
              onDateTimeChanged: (picked) => setState(() {
                _birthDate = picked;
                _error = errorAfterChange(_error, .dateOfBirth);
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = .invalidName);
      return;
    }
    final sex = _sex;
    if (sex == null) {
      setState(() => _error = .invalidSex);
      return;
    }
    final birth = _birthDate;
    if (birth == null) {
      setState(() => _error = .invalidDateOfBirth);
      return;
    }
    final phone = normalizeKePhone(_phone.text);
    if (phone == null) {
      setState(() => _error = .invalidPhone);
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _error = .invalidEmail);
      return;
    }
    setState(() => _error = null);
    final now = DateTime.now().toUtc().toIso8601String();
    widget.onSave(
      PatientModel.empty().copyWith(
        patientId: const Uuid().v4(),
        uid: '',
        isRegistered: false,
        createdByUid: widget.doctorUid,
        firstName: first,
        middleName: '',
        lastName: last,
        sex: sex.value,
        dateOfBirth: DateFormat('yyyy-MM-dd').format(birth),
        phoneNumber: phone,
        email: email,
        county: widget.county,
        subCounty: widget.subCounty,
        doctorUids: [widget.doctorUid],
        language: AppLanguage.fromValue(widget.language).value,
        createdAt: now,
        lastUpdatedAt: now,
        synced: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    final birth = _birthDate;
    final firstEmpty = _first.text.trim().isEmpty;
    final lastEmpty = _last.text.trim().isEmpty;
    final sex = _sex;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TabibuTextField(
          label: l10n.firstNameLabel,
          controller: _first,
          leading: FieldIcon(Assets.icons.personIcon),
          errorText: error == .invalidName && firstEmpty
              ? fieldErrorText(error!, l10n)
              : null,
          required: true,
          bordered: true,
          textInputAction: .next,
          onChanged: (_) =>
              setState(() => _error = errorAfterChange(_error, .name)),
        ),
        const SizedBox(height: AppSpacing.md),
        TabibuTextField(
          label: l10n.lastNameLabel,
          controller: _last,
          leading: FieldIcon(Assets.icons.personIcon),
          errorText: error == .invalidName && !firstEmpty && lastEmpty
              ? fieldErrorText(error!, l10n)
              : null,
          required: true,
          bordered: true,
          textInputAction: .next,
          onChanged: (_) =>
              setState(() => _error = errorAfterChange(_error, .name)),
        ),
        const SizedBox(height: AppSpacing.md),
        PickerField(
          label: l10n.sexLabel,
          required: true,
          bordered: true,
          hint: l10n.fieldErrorSex,
          value: sex?.description(l10n),
          leading: Assets.icons.personIcon,
          errorText: error == .invalidSex ? fieldErrorText(error!, l10n) : null,
          onTap: _pickSex,
        ),
        const SizedBox(height: AppSpacing.md),
        PickerField(
          label: l10n.dobLabel,
          required: true,
          bordered: true,
          hint: l10n.dobHint,
          value: birth == null
              ? null
              : DateFormat(
                  'd MMM y',
                  Localizations.localeOf(context).languageCode,
                ).format(birth),
          leading: Assets.icons.calendarIcon,
          errorText: error == .invalidDateOfBirth
              ? fieldErrorText(error!, l10n)
              : null,
          onTap: _pickBirthDate,
        ),
        const SizedBox(height: AppSpacing.md),
        TabibuTextField(
          label: l10n.phoneLabel,
          controller: _phone,
          leading: FieldIcon(Assets.icons.phoneIcon),
          errorText: error == .invalidPhone
              ? fieldErrorText(error!, l10n)
              : null,
          required: true,
          bordered: true,
          keyboardType: TextInputType.phone,
          inputFormatters: const [KePhoneFormatter()],
          onChanged: (_) =>
              setState(() => _error = errorAfterChange(_error, .phone)),
        ),
        const SizedBox(height: AppSpacing.md),
        TabibuTextField(
          label: l10n.signInEmailLabel,
          controller: _email,
          leading: FieldIcon(Assets.icons.emailIcon),
          errorText: error == .invalidEmail
              ? fieldErrorText(error!, l10n)
              : null,
          bordered: true,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) =>
              setState(() => _error = errorAfterChange(_error, .email)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.addPatientAreaLine(
            [
              widget.subCounty,
              widget.county,
            ].where((part) => part.isNotEmpty).join(', '),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TabibuButton.primary(label: l10n.addPatientSave, onTap: _save),
      ],
    );
  }
}
