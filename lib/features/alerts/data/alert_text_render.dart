import 'package:collection/collection.dart';
import 'package:tabibu/features/alerts/data/models/alert_model.dart';
import 'package:tabibu/features/alerts/data/models/alert_text_model.dart';
import 'package:tabibu/features/alerts/data/models/notifiable_disease_model.dart';

final _placeholder = RegExp(r'\{([a-zA-Z]+)\}');

/// The values delivery fills in (`alert-delivery.ts` `renderArgs`), for one
/// draft language. A value the phone does not have is left out, so its
/// placeholder stays visible rather than blank.
Map<String, String> alertRenderArgs(
  AlertModel alert,
  List<NotifiableDiseaseModel> register,
  String language,
) {
  final disease = register.firstWhereOrNull(
    (d) => d.diseaseId == alert.diseaseId,
  );
  final name = language == 'sw' ? disease?.nameSw : disease?.nameEn;
  return {
    if (name != null && name.isNotEmpty) 'disease': name,
    if (alert.countyName.isNotEmpty) 'county': alert.countyName,
    'count': '${alert.evidence.confirmedCount}',
    if (alert.evidence.weekStart.isNotEmpty)
      'weekStart': alert.evidence.weekStart,
  };
}

String _fill(String text, Map<String, String> args) =>
    text.replaceAllMapped(_placeholder, (m) => args[m[1]] ?? m[0]!);

/// The alert's drafts as their readers will see them: each key filled with
/// its own language's values. The model never writes these facts (T-5).
Map<String, AlertTextModel> renderAlertDrafts(
  AlertModel alert,
  List<NotifiableDiseaseModel> register,
) => {
  for (final MapEntry(:key, :value) in alert.machineText.entries)
    key: _render(value, alertRenderArgs(alert, register, key.split('_').last)),
};

AlertTextModel _render(AlertTextModel text, Map<String, String> args) =>
    AlertTextModel(
      headline: _fill(text.headline, args),
      body: _fill(text.body, args),
    );

/// What an approval sends: a key the approver left exactly as rendered goes
/// back as the machine wrote it, so approving unchanged stays `Approve`
/// (`acceptedUnchanged`); a key they changed goes as typed.
Map<String, AlertTextModel> restoreUntouched({
  required Map<String, AlertTextModel> machine,
  required Map<String, AlertTextModel> rendered,
  required Map<String, AlertTextModel> edited,
}) => {
  for (final MapEntry(:key, :value) in edited.entries)
    key: value == rendered[key] ? machine[key] ?? value : value,
};
