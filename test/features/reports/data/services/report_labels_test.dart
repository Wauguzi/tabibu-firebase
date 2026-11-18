import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/reports/data/services/report_labels.dart';
import 'package:tabibu/l10n/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final sw = lookupAppLocalizations(const Locale('sw'));

  group('reportSectionLabel', () {
    test("names every known section in the reader's language", () {
      for (final section in ReportSection.values) {
        expect(reportSectionLabel(en, section.value), section.description(en));
        expect(reportSectionLabel(sw, section.value), section.description(sw));
      }
      expect(reportSectionLabel(en, 'Macroscopic'), 'Macroscopic findings');
    });

    test('an unknown key falls back to the key', () {
      expect(reportSectionLabel(en, 'Other'), 'Other');
      expect(reportSectionLabel(sw, ''), '');
    });
  });

  group('reportQuestionLabel', () {
    test('a known key reads as its label', () {
      expect(reportQuestionLabel(en, 'tumourGrade'), 'Tumour grade');
      expect(reportQuestionLabel(sw, 'tumourGrade'), isNot('tumourGrade'));
    });

    test('an unknown key falls back to the key', () {
      expect(reportQuestionLabel(en, 'madeUpQuestion'), 'madeUpQuestion');
    });
  });

  group('reportDiagnosisTypeLabel', () {
    test('a known type reads as its label', () {
      expect(reportDiagnosisTypeLabel(en, 'Final'), 'Final');
      expect(reportDiagnosisTypeLabel(en, 'Provisional'), 'Provisional');
      expect(reportDiagnosisTypeLabel(en, 'Inconclusive'), 'Inconclusive');
      expect(
        reportDiagnosisTypeLabel(sw, 'Final'),
        sw.reportPdfDiagnosisTypeFinal,
      );
    });

    test('an unknown type falls back to the key', () {
      expect(reportDiagnosisTypeLabel(en, 'Draft'), 'Draft');
    });
  });

  group('reportMeasurementLabel', () {
    test('every measurement the server writes reads as words', () {
      for (final key in const [
        'tileCount',
        'tumourTiles',
        'normalTiles',
        'unknownTiles',
        'largestFocusTiles',
        'largestFocusMm',
        'tumourAreaPercent',
        'parasitaemiaPercent',
      ]) {
        for (final l10n in [en, sw]) {
          final label = reportMeasurementLabel(l10n, key);
          expect(label, isNot(key));
          expect(label, isNot(matches(RegExp('[a-z][A-Z]'))));
        }
      }
      expect(reportMeasurementLabel(en, 'tumourAreaPercent'), 'Tumour area');
    });

    test('an unknown key reads as plain words, not as the key', () {
      expect(reportMeasurementLabel(en, 'mitoticCount'), 'Mitotic count');
      expect(reportMeasurementLabel(en, ''), '');
    });
  });

  group('reportMeasurementValue', () {
    test('a percent, a length and a count', () {
      expect(reportMeasurementValue('tumourAreaPercent', 26.666), '26.67%');
      expect(reportMeasurementValue('largestFocusMm', 1.2), '1.20 mm');
      expect(reportMeasurementValue('tumourTiles', 12), '12');
      expect(reportMeasurementValue('density', 2.5), '2.50');
    });

    test('a unit the report states wins, at its precision', () {
      expect(
        reportMeasurementValue('size', 3, unit: 'mm', precision: 0),
        '3 mm',
      );
    });
  });
}
