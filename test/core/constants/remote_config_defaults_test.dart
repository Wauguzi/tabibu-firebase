import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/constants/remote_config_defaults.dart';
import 'package:tabibu/core/services/hybrid_ai_service.dart';

void main() {
  test('all eight kill switches have a client default', () {
    expect(RemoteConfigDefaults.killSwitches.keys.toSet(), {
      'preread_enabled',
      'risk_check_enabled',
      'patient_explanations_enabled',
      'alerts_delivery_enabled',
      'symptom_intake_enabled',
      'report_translation_enabled',
      'voice_input_enabled',
      'alert_drafting_enabled',
    });
    final on = {...RemoteConfigDefaults.killSwitches}
      ..remove('voice_input_enabled');
    expect(on.values, everyElement(isTrue));
  });

  test('voice input is off by default', () {
    expect(RemoteConfigDefaults.killSwitches['voice_input_enabled'], isFalse);
  });

  test('the defaults keep the force-update parameters', () {
    expect(
      RemoteConfigDefaults.values.keys,
      containsAll(['force_update', 'min_required_version', 'update_message']),
    );
    expect(RemoteConfigDefaults.values['force_update'], isFalse);
  });

  test('the hybrid defaults match the settings the app falls back to', () {
    const settings = HybridSettings();

    expect(RemoteConfigDefaults.hybrid, {
      HybridSettings.symptomTidyKey: settings.symptomTidyEnabled,
      HybridSettings.notesSummaryKey: settings.notesSummaryEnabled,
      HybridSettings.modelOptionKey: settings.modelOption,
      HybridSettings.cloudModelKey: settings.cloudModel,
    });
    expect(
      RemoteConfigDefaults.values,
      containsPair('hybrid_model_option', 'stable'),
    );
  });
}
