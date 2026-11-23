import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/l10n/l10n.dart';

// The report's wire keys in words, shared by the PDF and the on-screen
// reports so the two cannot drift. An unknown key falls back to the key
// itself, never to an empty label. (The enums' fromValue fallbacks guess a
// variant, so these lookups are explicit.)

/// The localised name of a [ReportSection] wire value.
String reportSectionLabel(AppLocalizations l10n, String key) {
  for (final section in ReportSection.values) {
    if (section.value == key) return section.description(l10n);
  }
  return key;
}

/// The localised name of a template question key.
String reportQuestionLabel(AppLocalizations l10n, String key) => switch (key) {
  'specimenDescription' => l10n.reportQuestionSpecimenDescription,
  'specimenSize' => l10n.reportQuestionSpecimenSize,
  'representativeSections' => l10n.reportQuestionRepresentativeSections,
  'microscopicDescription' => l10n.reportQuestionMicroscopicDescription,
  'tumourGrade' => l10n.reportQuestionTumourGrade,
  'margins' => l10n.reportQuestionMargins,
  'lymphNodes' => l10n.reportQuestionLymphNodes,
  'immunohistochemistry' => l10n.reportQuestionImmunohistochemistry,
  'parasiteSpecies' => l10n.reportQuestionParasiteSpecies,
  'parasiteDensity' => l10n.reportQuestionParasiteDensity,
  'parasiteStages' => l10n.reportQuestionParasiteStages,
  'rapidTestResult' => l10n.reportQuestionRapidTestResult,
  'findings' => l10n.reportQuestionFindings,
  'methodNotes' => l10n.reportQuestionMethodNotes,
  _ => key,
};

/// The localised name of a [DiagnosisType] wire value.
String reportDiagnosisTypeLabel(AppLocalizations l10n, String key) =>
    switch (key) {
      'Final' => l10n.reportPdfDiagnosisTypeFinal,
      'Provisional' => l10n.reportPdfDiagnosisTypeProvisional,
      'Inconclusive' => l10n.reportPdfDiagnosisTypeInconclusive,
      _ => key,
    };

/// The localised name of a measurement key. A key not listed reads as words
/// ("someNewKey" → "Some new key"), never as the raw key.
String reportMeasurementLabel(AppLocalizations l10n, String key) =>
    switch (key) {
      'tileCount' => l10n.reportMeasurementTileCount,
      'tumourTiles' => l10n.reportMeasurementTumourTiles,
      'normalTiles' => l10n.reportMeasurementNormalTiles,
      'unknownTiles' => l10n.reportMeasurementUnknownTiles,
      'largestFocusTiles' => l10n.reportMeasurementLargestFocusTiles,
      'largestFocusMm' => l10n.reportMeasurementLargestFocusMm,
      'tumourAreaPercent' => l10n.reportMeasurementTumourAreaPercent,
      'parasitaemiaPercent' => l10n.reportMeasurementParasitaemiaPercent,
      _ => _words(key),
    };

/// A measurement's value with its unit. A stated [unit] wins, at
/// [precision]; otherwise the key names it: `…Percent` as %, `…Mm` in mm,
/// tile and other counts as whole numbers.
String reportMeasurementValue(
  String key,
  double value, {
  String unit = '',
  int precision = 2,
}) {
  if (unit.isNotEmpty) return '${value.toStringAsFixed(precision)} $unit';
  if (key.endsWith('Percent')) return '${value.toStringAsFixed(2)}%';
  if (key.endsWith('Mm')) return '${value.toStringAsFixed(2)} mm';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _words(String key) {
  final spaced = key
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .trim();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}
