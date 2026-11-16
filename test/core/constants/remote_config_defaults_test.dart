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
    expect(RemoteConfigDefaults.values['voice_input_enabled'], isFalse);
  });

  test('symptom speech defaults name the template and keep tokens off', () {
    expect(RemoteConfigDefaults.ai, {
      'ai_location': 'global',
      'ai_template_symptom_transcribe': 'symptom-transcribe-v1-0-0',
      'ai_limited_use_tokens': false,
      'ai_tts_model': 'gemini-3.8-flash-tts',
      'ai_tts_voice': 'Achernar',
      'ai_template_slide_region': 'slide-region-read-v1-0-0',
      'region_read_enabled': false,
      'explanation_listen_enabled': true,
    });
    expect(RemoteConfigDefaults.values['ai_limited_use_tokens'], isFalse);
  });

  test('the narrated explanation is on by default, behind its switch', () {
    expect(RemoteConfigDefaults.values['explanation_listen_enabled'], isTrue);
  });

  test('the region read is off by default', () {
    expect(RemoteConfigDefaults.ai['region_read_enabled'], isFalse);
    expect(RemoteConfigDefaults.values['region_read_enabled'], isFalse);
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
