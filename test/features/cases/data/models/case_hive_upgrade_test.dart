import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:tabibu/features/cases/data/models/case_hive.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';

/// [CaseHiveAdapter] as the previous build wrote it: every field but 51
/// (`openMdtUid`).
class _LegacyCaseHiveAdapter extends TypeAdapter<CaseHive> {
  @override
  final typeId = CaseHiveAdapter().typeId;

  @override
  CaseHive read(BinaryReader reader) => CaseHiveAdapter().read(reader);

  @override
  void write(BinaryWriter writer, CaseHive obj) {
    writer
      ..writeByte(51)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.orderNumber)
      ..writeByte(2)
      ..write(obj.appointmentUid)
      ..writeByte(3)
      ..write(obj.createdByUid)
      ..writeByte(4)
      ..write(obj.doctorUid)
      ..writeByte(5)
      ..write(obj.doctorName)
      ..writeByte(6)
      ..write(obj.doctorFacilityName)
      ..writeByte(7)
      ..write(obj.patientId)
      ..writeByte(8)
      ..write(obj.patientUid)
      ..writeByte(9)
      ..write(obj.patientName)
      ..writeByte(10)
      ..write(obj.patientSex)
      ..writeByte(11)
      ..write(obj.patientAgeYears)
      ..writeByte(12)
      ..write(obj.requestedPathologistUid)
      ..writeByte(13)
      ..write(obj.requestedPathologistName)
      ..writeByte(14)
      ..write(obj.pathologistRequestedAt)
      ..writeByte(15)
      ..write(obj.pathologistRequestExpiresAt)
      ..writeByte(16)
      ..write(obj.declinedPathologistUids)
      ..writeByte(17)
      ..write(obj.pathologistUid)
      ..writeByte(18)
      ..write(obj.pathologistName)
      ..writeByte(19)
      ..write(obj.pathologistAcceptedAt)
      ..writeByte(20)
      ..write(obj.viewerUids)
      ..writeByte(21)
      ..write(obj.participantUids)
      ..writeByte(22)
      ..write(obj.tests)
      ..writeByte(23)
      ..write(obj.totalPriceKes)
      ..writeByte(24)
      ..write(obj.isPriceEstimate)
      ..writeByte(25)
      ..write(obj.priority)
      ..writeByte(26)
      ..write(obj.clinicalNotes)
      ..writeByte(27)
      ..write(obj.sampleNotes)
      ..writeByte(28)
      ..write(obj.notesLanguage)
      ..writeByte(29)
      ..write(obj.sampleCollectedAt)
      ..writeByte(30)
      ..write(obj.sampleReceivedAt)
      ..writeByte(31)
      ..write(obj.labAccessionNo)
      ..writeByte(32)
      ..write(obj.requiresSlides)
      ..writeByte(33)
      ..write(obj.slideUploadUids)
      ..writeByte(34)
      ..write(obj.slideImages)
      ..writeByte(35)
      ..write(obj.prereadRunUid)
      ..writeByte(36)
      ..write(obj.currentReportUid)
      ..writeByte(37)
      ..write(obj.resultState)
      ..writeByte(38)
      ..write(obj.discussionAppointmentUid)
      ..writeByte(39)
      ..write(obj.currentLocation)
      ..writeByte(40)
      ..write(obj.currentStage)
      ..writeByte(41)
      ..write(obj.currentStep)
      ..writeByte(42)
      ..write(obj.stageSeq)
      ..writeByte(43)
      ..write(obj.stageEnteredAt)
      ..writeByte(44)
      ..write(obj.releasedToPatient)
      ..writeByte(45)
      ..write(obj.discussedAt)
      ..writeByte(46)
      ..write(obj.releasedAt)
      ..writeByte(47)
      ..write(obj.cancelReason)
      ..writeByte(48)
      ..write(obj.createdAt)
      ..writeByte(49)
      ..write(obj.lastUpdatedAt)
      ..writeByte(50)
      ..write(obj.synced);
  }
}

void main() {
  test('a case cached before openMdtUid loads, with no open consult', () async {
    final dir = Directory.systemTemp.createTempSync('tabibu_case_hive_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Hive
      ..init(dir.path)
      ..registerAdapter(_LegacyCaseHiveAdapter());

    const boxName = 'cases_legacy';
    final box = await Hive.openBox<CaseHive>(boxName);
    final written = CaseHive.fromModel(
      const CaseModel(
        uid: 'case-1',
        orderNumber: 'ODR-1',
        patientName: 'Amina Otieno',
        openMdtUid: 'should-not-persist',
      ),
    );
    await box.put('case-1', written);
    await box.close();

    Hive.registerAdapter(CaseHiveAdapter(), override: true);
    final reopened = await Hive.openBox<CaseHive>(boxName);
    final loaded = reopened.get('case-1')!;

    expect(loaded.uid, 'case-1');
    expect(loaded.orderNumber, 'ODR-1');
    expect(loaded.patientName, 'Amina Otieno');
    expect(loaded.openMdtUid, '');
    await reopened.close();
  });
}
