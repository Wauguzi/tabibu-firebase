import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_measurement_model.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_measurements_card.dart';

import '../../../../helpers/helpers.dart';

void main() {
  const report = PathologyReportModel(
    measurements: [
      ReportMeasurementModel(
        key: 'tumourAreaPercent',
        value: 26.666,
        precision: 2,
      ),
      ReportMeasurementModel(key: 'largestFocusMm', value: 1.2, precision: 2),
      ReportMeasurementModel(key: 'normalTiles', value: 30, precision: 2),
    ],
  );

  Future<void> pump(WidgetTester tester) => tester.pumpApp(
    const Scaffold(
      body: SingleChildScrollView(
        child: ReportMeasurementsCard(report: report),
      ),
    ),
  );

  group('ReportMeasurementsCard', () {
    testWidgets('names each measurement in words, with its unit', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Tumour area'), findsOneWidget);
      expect(find.text('26.67%'), findsOneWidget);
      expect(find.text('Largest focus'), findsOneWidget);
      expect(find.text('1.20 mm'), findsOneWidget);
      expect(find.text('Normal tiles'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.textContaining('tumourAreaPercent'), findsNothing);
    });

    testWidgets('a value starts clear of its name', (tester) async {
      await pump(tester);

      final label = tester.getRect(find.text('Tumour area'));
      final value = tester.getRect(find.text('26.67%'));
      expect(value.left - label.right, greaterThanOrEqualTo(8));
    });

    testWidgets('fits at 2.0x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
