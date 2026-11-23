/// The client Remote Config defaults: what the app shows before a fetch, or
/// when one fails. The server keeps its own template for jobs and delivery
/// (functions/src/config.ts); a kill switch is flipped in both, server first.
abstract final class RemoteConfigDefaults {
  /// The eight AI and alert kill switches. On means the surface shows; the
  /// server still decides whether the job runs.
  static const killSwitches = <String, Object>{
    'preread_enabled': true,
    'risk_check_enabled': true,
    'patient_explanations_enabled': true,
    'alerts_delivery_enabled': true,
    'symptom_intake_enabled': true,
    'report_translation_enabled': true,
    // The server takes no audio, and fails closed on its own template.
    'voice_input_enabled': true,
    'alert_drafting_enabled': true,
  };

  /// The in-app hybrid tasks: a switch each, the on-device model channel and
  /// the cloud model a tidy falls back to. They match `HybridSettings`.
  static const hybrid = <String, Object>{
    'hybrid_symptom_tidy_enabled': true,
    'hybrid_notes_summary_enabled': true,
    'hybrid_model_option': 'stable',
    'hybrid_cloud_model': 'gemini-3.5-flash-lite',
  };

  /// AI Logic calls: symptom speech, explanation speech, the region read.
  /// Template ids match `prompts/` without the extension. Limited-use tokens
  /// stay off until a live call has proved them; the calls match the live
  /// project, on.
  static const ai = <String, Object>{
    'ai_location': 'global',
    'ai_template_symptom_transcribe': 'symptom-transcribe-v1-0-0',
    'ai_limited_use_tokens': false,
    'ai_tts_model': 'gemini-3.8-flash-tts',
    'ai_tts_voice': 'Achernar',
    'ai_template_slide_region': 'slide-region-read-v1-0-0',
    'region_read_enabled': true,
    'explanation_listen_enabled': true,
  };

  /// The force-update parameters.
  static const appUpdate = <String, Object>{
    'force_update': false,
    'min_required_version': '',
    'store_url_android': '',
    'store_url_ios': '',
    'update_title': '',
    'update_message': '',
  };

  static const values = <String, Object>{
    ...appUpdate,
    ...killSwitches,
    ...hybrid,
    ...ai,
  };
}
