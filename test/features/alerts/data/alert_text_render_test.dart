import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/alerts/data/alert_text_render.dart';
import 'package:tabibu/features/alerts/data/models/alert_evidence_model.dart';
import 'package:tabibu/features/alerts/data/models/alert_model.dart';
import 'package:tabibu/features/alerts/data/models/alert_text_model.dart';
import 'package:tabibu/features/alerts/data/models/notifiable_disease_model.dart';

// The server's template (`alert-drafts.ts` `templateDraft`), as the approver
// receives it.
const _machine = {
  'clinician_en': AlertTextModel(
    headline: 'Health alert: {disease} in {county} County',
    body:
        'Confirmed {disease} results in {county} County, week of '
        '{weekStart}: {count}.',
  ),
  'patient_en': AlertTextModel(
    headline: 'Health alert: {disease} in {county} County',
    body: 'Cases of {disease} have been confirmed in {county} County.',
  ),
  'clinician_sw': AlertTextModel(
    headline: 'Tahadhari ya afya: {disease} katika Kaunti ya {county}',
    body: 'Wiki ya {weekStart}: {count}.',
  ),
  'patient_sw': AlertTextModel(
    headline: 'Tahadhari ya afya: {disease} katika Kaunti ya {county}',
    body: 'Visa vya {disease} vimethibitishwa katika Kaunti ya {county}.',
  ),
};

const _register = [
  NotifiableDiseaseModel(
    diseaseId: 'ebola_virus_disease',
    nameEn: 'Ebola virus disease',
    nameSw: 'Ugonjwa wa virusi vya Ebola',
  ),
];

AlertModel _alert({
  String countyName = 'Nairobi',
  String weekStart = '2026-11-16',
}) => AlertModel(
  uid: 'a1',
  diseaseId: 'ebola_virus_disease',
  countyName: countyName,
  machineText: _machine,
  evidence: AlertEvidenceModel(confirmedCount: 1, weekStart: weekStart),
);

void main() {
  group('renderAlertDrafts', () {
    test('fills each key with its own language, as delivery does', () {
      final rendered = renderAlertDrafts(_alert(), _register);
      expect(
        rendered['patient_en']!.headline,
        'Health alert: Ebola virus disease in Nairobi County',
      );
      expect(
        rendered['clinician_en']!.body,
        'Confirmed Ebola virus disease results in Nairobi County, week of '
        '2026-11-16: 1.',
      );
      expect(
        rendered['patient_sw']!.body,
        'Visa vya Ugonjwa wa virusi vya Ebola vimethibitishwa katika Kaunti '
        'ya Nairobi.',
      );
      expect(rendered['clinician_sw']!.body, 'Wiki ya 2026-11-16: 1.');
      for (final text in rendered.values) {
        expect('${text.headline} ${text.body}', isNot(contains('{')));
      }
    });

    test('leaves a placeholder it has no value for, never a blank', () {
      final rendered = renderAlertDrafts(
        _alert(countyName: '', weekStart: ''),
        const [],
      );
      expect(
        rendered['patient_en']!.headline,
        'Health alert: {disease} in {county} County',
      );
      expect(rendered['clinician_sw']!.body, 'Wiki ya {weekStart}: 1.');
    });

    test('keeps an unknown placeholder as written', () {
      final alert = _alert().copyWith(
        machineText: const {
          'patient_en': AlertTextModel(headline: '{other}', body: 'x'),
        },
      );
      expect(
        renderAlertDrafts(alert, _register)['patient_en']!.headline,
        '{other}',
      );
    });
  });

  group('restoreUntouched', () {
    test('an untouched key goes back as the machine wrote it', () {
      final rendered = renderAlertDrafts(_alert(), _register);
      final sent = restoreUntouched(
        machine: _machine,
        rendered: rendered,
        edited: rendered,
      );
      expect(sent, _machine);
    });

    test('a changed key goes as typed, the rest as the machine wrote them', () {
      final rendered = renderAlertDrafts(_alert(), _register);
      const typed = AlertTextModel(
        headline: 'Health alert: Ebola in Nairobi County',
        body: 'Cases of Ebola have been confirmed in Nairobi County.',
      );
      final sent = restoreUntouched(
        machine: _machine,
        rendered: rendered,
        edited: {...rendered, 'patient_en': typed},
      );
      expect(sent['patient_en'], typed);
      expect(sent['clinician_en'], _machine['clinician_en']);
    });
  });
}
