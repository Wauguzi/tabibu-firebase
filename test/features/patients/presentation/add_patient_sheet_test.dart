import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/presentation/widgets/picker_field.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/presentation/add_patient_sheet.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';

void _surface(WidgetTester tester, {double width = 800, double scale = 1}) {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  Locale? locale,
  String language = '',
  ValueChanged<PatientModel>? onSave,
}) {
  return tester.pumpApp(
    SingleChildScrollView(
      child: AddPatientSheet(
        doctorUid: 'doc-1',
        county: 'Nairobi',
        subCounty: 'Kibra',
        language: language,
        onSave: onSave ?? _ignore,
      ),
    ),
    locale: locale,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddPatientSheet', () {
    testWidgets('every field is bordered, and email follows phone', (
      tester,
    ) async {
      _surface(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpSheet(tester);

      final texts = tester.widgetList<TabibuTextField>(
        find.byType(TabibuTextField),
      );
      final pickers = tester.widgetList<PickerField>(find.byType(PickerField));
      expect(texts.map((field) => field.label), [
        l10n.firstNameLabel,
        l10n.lastNameLabel,
        l10n.phoneLabel,
        l10n.signInEmailLabel,
      ]);
      expect(texts.map((field) => field.bordered), everyElement(isTrue));
      expect(pickers.map((field) => field.label), [
        l10n.sexLabel,
        l10n.dobLabel,
      ]);
      expect(pickers.map((field) => field.bordered), everyElement(isTrue));
      expect(pickers.first.required, isTrue);

      expect(
        tester.getTopLeft(find.textContaining(l10n.signInEmailLabel)).dy,
        greaterThan(tester.getTopLeft(find.textContaining(l10n.phoneLabel)).dy),
      );
      expect(
        tester.getTopLeft(find.text(l10n.addPatientSave)).dy,
        greaterThan(
          tester
              .getTopLeft(find.text('Area: Kibra, Nairobi, from your facility'))
              .dy,
        ),
      );
      expect(find.text(l10n.middleNameLabel), findsNothing);
      expect(find.text(l10n.languageTitle), findsNothing);
      expect(find.text('County'), findsNothing);
      expect(find.text('Sub-county'), findsNothing);
    });

    testWidgets('sex is required, and picking one fills the field', (
      tester,
    ) async {
      _surface(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpSheet(tester);

      await tester.enterText(find.byType(EditableText).at(0), 'Amina');
      await tester.enterText(find.byType(EditableText).at(1), 'Otieno');
      await tester.tap(find.text(l10n.addPatientSave));
      await tester.pump();

      expect(
        tester.widget<PickerField>(find.byType(PickerField).first).errorText,
        l10n.fieldErrorSex,
      );

      await tester.tap(find.byType(PickerField).first);
      await _settle(tester);
      expect(find.text(l10n.sexFemale), findsOneWidget);
      expect(find.text(l10n.sexMale), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(l10n.sexFemale)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.sexMale)).dy),
      );

      await tester.tap(find.text(l10n.sexFemale));
      await _settle(tester);

      expect(
        tester.widget<PickerField>(find.byType(PickerField).first).value,
        l10n.sexFemale,
      );
      expect(
        tester.widget<PickerField>(find.byType(PickerField).first).errorText,
        isNull,
      );
    });

    testWidgets('saving sends the doctor language and an empty middle name', (
      tester,
    ) async {
      _surface(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));
      PatientModel? saved;
      await _pumpSheet(
        tester,
        language: 'sw',
        onSave: (patient) => saved = patient,
      );

      await tester.enterText(find.byType(EditableText).at(0), 'Amina');
      await tester.enterText(find.byType(EditableText).at(1), 'Otieno');
      await tester.tap(find.byType(PickerField).first);
      await _settle(tester);
      await tester.tap(find.text(l10n.sexMale));
      await _settle(tester);
      await tester.tap(find.byType(PickerField).at(1));
      await _settle(tester);
      await tester.tapAt(const Offset(20, 20));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText).at(2), '0712345678');
      await tester.tap(find.text(l10n.addPatientSave));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.middleName, isEmpty);
      expect(saved!.language, 'sw');
      expect(saved!.sex, 'Male');
      expect(saved!.firstName, 'Amina');
      expect(saved!.lastName, 'Otieno');
    });

    testWidgets('Kiswahili at 2.0 text and 360 dp shows the facility area', (
      tester,
    ) async {
      _surface(tester, width: 360, scale: 2);
      final l10n = lookupAppLocalizations(const Locale('sw'));
      await _pumpSheet(tester, locale: const Locale('sw'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Eneo: Kibra, Nairobi, kutoka kituo chako'),
        findsOneWidget,
      );
      expect(find.text(l10n.countyLabel), findsNothing);
      expect(find.text(l10n.subCountyLabel), findsNothing);
      expect(find.text(l10n.middleNameLabel), findsNothing);
      expect(find.text(l10n.languageTitle), findsNothing);
      expect(find.textContaining(l10n.firstNameLabel), findsOneWidget);
      expect(find.textContaining(l10n.lastNameLabel), findsOneWidget);
      expect(find.textContaining(l10n.sexLabel), findsOneWidget);
      expect(find.textContaining(l10n.dobLabel), findsOneWidget);
      expect(find.textContaining(l10n.phoneLabel), findsOneWidget);
      expect(find.textContaining(l10n.signInEmailLabel), findsOneWidget);
    });
  });
}

void _ignore(PatientModel _) {}
