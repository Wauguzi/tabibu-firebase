import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// Bridge to the native hybrid SDK. Flutter has no hybrid API, so the
/// native side owns the model and the prompts.
///
/// Method channel `tabibu/hybrid_ai`:
/// - `status` → `available` | `downloadable` | `downloading` | `unavailable`
/// - `download` — progress on event channel `tabibu/hybrid_ai/download`
///   as doubles from 0 to 1
/// - `warmUp`
/// - `generate` with `task`, `input`, `mode`, `modelOption`, `cloudModel`
///   → `text` and `source` (`on_device` | `in_cloud`)
///
/// `task` is only `symptom_tidy` or `notes_summary`. The prompt for each
/// stays in the native plugin, so this side cannot run an arbitrary prompt.
/// `ONLY_ON_DEVICE` never falls back; the native plugin must ignore
/// `cloudModel` for that mode.
abstract class HybridAiService {
  static const channelName = 'tabibu/hybrid_ai';
  static const downloadChannelName = 'tabibu/hybrid_ai/download';

  Future<HybridStatus> status();

  /// Only from an explicit action: neither plugin downloads on its own.
  Future<void> download();

  Stream<double> get downloadProgress;

  Future<void> warmUp();

  Future<HybridResult> generate(HybridRequest request);
}

enum HybridTask {
  symptomTidy,
  notesSummary;

  String get wire => switch (this) {
    .symptomTidy => 'symptom_tidy',
    .notesSummary => 'notes_summary',
  };

  static HybridTask? fromWire(String? raw) => switch (raw) {
    'symptom_tidy' => .symptomTidy,
    'notes_summary' => .notesSummary,
    _ => null,
  };
}

/// Cloud fallback exists only for [preferOnDevice]. Notes stay on device:
/// they may identify the patient (S-5).
enum HybridMode {
  preferOnDevice,
  onlyOnDevice;

  String get wire => switch (this) {
    .preferOnDevice => 'PREFER_ON_DEVICE',
    .onlyOnDevice => 'ONLY_ON_DEVICE',
  };

  static HybridMode forTask(HybridTask task) => switch (task) {
    .symptomTidy => .preferOnDevice,
    .notesSummary => .onlyOnDevice,
  };
}

enum HybridSource {
  onDevice,
  inCloud;

  String get wire => switch (this) {
    .onDevice => 'on_device',
    .inCloud => 'in_cloud',
  };

  static HybridSource? fromWire(String? raw) => switch (raw) {
    'on_device' => .onDevice,
    'in_cloud' => .inCloud,
    _ => null,
  };
}

enum HybridStatus {
  available,
  downloadable,
  downloading,
  unavailable;

  bool get onDeviceReady => this == .available;

  static HybridStatus fromWire(String? raw) => switch (raw) {
    'available' => .available,
    'downloadable' => .downloadable,
    'downloading' => .downloading,
    _ => .unavailable,
  };
}

enum HybridFailure {
  unavailable,
  busy,
  battery,
  notEnglish,
  tooLong,
  network,
  unknown;

  static HybridFailure fromCode(String? code) => switch (code) {
    'unavailable' => .unavailable,
    'busy' => .busy,
    'battery' => .battery,
    'not_english' => .notEnglish,
    'too_long' => .tooLong,
    'network' => .network,
    _ => .unknown,
  };
}

class HybridAiException implements Exception {
  const HybridAiException(this.failure);

  final HybridFailure failure;

  @override
  String toString() => 'HybridAiException(${failure.name})';
}

/// Rough stand-in for the on-device cap of 4,000 tokens, at about four
/// characters a token. Longer input is refused here and never sent.
const hybridMaxInputChars = 16000;

class HybridRequest {
  const HybridRequest({
    required this.task,
    required this.input,
    required this.mode,
    required this.modelOption,
    required this.cloudModel,
  });

  final HybridTask task;
  final String input;
  final HybridMode mode;
  final String modelOption;
  final String cloudModel;

  /// A tidy may reach the cloud, so its input leaves without phone numbers
  /// or email addresses; a notes summary never leaves the device.
  Map<String, Object> toMap() => {
    'task': task.wire,
    'input': task == .symptomTidy ? stripContactDetails(input) : input,
    'mode': mode.wire,
    'modelOption': modelOption,
    'cloudModel': cloudModel,
  };

  /// The note can identify a patient, so it stays out of logs.
  @override
  String toString() => 'HybridRequest(${task.wire}, ${mode.wire})';
}

/// Replaces email addresses and Kenyan phone numbers with placeholders, with
/// the same patterns the server's de-identifier uses before its prompts.
String stripContactDetails(String text) =>
    text.replaceAll(_email, '[EMAIL]').replaceAll(_phone, '[PHONE]');

final _email = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
final _phone = RegExp(
  r'(?:\+?254|0)\s*[17](?:[\s\-]*\d){8}'
  r'|(?:\+?254|0)\s*20(?:[\s\-]*\d){6,7}'
  r'|\b0[17]\d(?:[\s\-]?\d){7}\b',
);

class HybridResult {
  const HybridResult({required this.text, required this.source});

  final String text;
  final HybridSource source;

  static HybridResult? fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final text = raw['text'];
    final source = HybridSource.fromWire(raw['source'] as String?);
    if (text is! String || text.trim().isEmpty || source == null) return null;
    return HybridResult(text: text, source: source);
  }
}

/// Client defaults used when Remote Config has no value for the key yet.
/// The reviewer owns `RemoteConfigDefaults`; these match the keys that
/// belong there.
class HybridSettings {
  const HybridSettings({
    this.symptomTidyEnabled = true,
    this.notesSummaryEnabled = true,
    this.modelOption = defaultModelOption,
    this.cloudModel = defaultCloudModel,
  });

  factory HybridSettings.resolve(HybridConfigLookup? lookup) {
    if (lookup == null) return const HybridSettings();
    return HybridSettings(
      symptomTidyEnabled: lookup.optionalBool(symptomTidyKey) ?? true,
      notesSummaryEnabled: lookup.optionalBool(notesSummaryKey) ?? true,
      modelOption: _option(lookup.optionalString(modelOptionKey)),
      cloudModel: _model(lookup.optionalString(cloudModelKey)),
    );
  }

  static const symptomTidyKey = 'hybrid_symptom_tidy_enabled';
  static const notesSummaryKey = 'hybrid_notes_summary_enabled';
  static const modelOptionKey = 'hybrid_model_option';
  static const cloudModelKey = 'hybrid_cloud_model';
  static const defaultModelOption = 'stable';
  static const defaultCloudModel = 'gemini-3.5-flash-lite';

  final bool symptomTidyEnabled;
  final bool notesSummaryEnabled;
  final String modelOption;
  final String cloudModel;

  bool enabledFor(HybridTask task) => switch (task) {
    .symptomTidy => symptomTidyEnabled,
    .notesSummary => notesSummaryEnabled,
  };

  static String _option(String? raw) => switch (raw) {
    'preview' || 'stable' => raw!,
    _ => defaultModelOption,
  };

  static String _model(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return defaultCloudModel;
    return value;
  }
}

/// Null means the key was never configured, so the caller keeps its default.
abstract class HybridConfigLookup {
  bool? optionalBool(String key);

  String? optionalString(String key);
}

@LazySingleton(as: HybridConfigLookup)
class FirebaseHybridConfigLookup implements HybridConfigLookup {
  FirebaseHybridConfigLookup({@ignoreParam this._remote});

  final FirebaseRemoteConfig? _remote;

  FirebaseRemoteConfig get _config => _remote ?? FirebaseRemoteConfig.instance;

  @override
  bool? optionalBool(String key) {
    try {
      final value = _config.getValue(key);
      if (value.source == ValueSource.valueDefault) return null;
      return value.asBool();
    } on Object {
      return null;
    }
  }

  @override
  String? optionalString(String key) {
    try {
      final value = _config.getValue(key);
      if (value.source == ValueSource.valueDefault) return null;
      final raw = value.asString().trim();
      return raw.isEmpty ? null : raw;
    } on Object {
      return null;
    }
  }
}

/// Latin text with none of a small set of Swahili words. Empty text and
/// anything outside basic Latin counts as not English. Enough to hide the
/// action; not a language detector.
bool looksLikeEnglish(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (!_basicLatin.hasMatch(trimmed)) return false;
  if (!_hasLetter.hasMatch(trimmed)) return false;
  final words = trimmed
      .toLowerCase()
      .split(_notLetters)
      .where((word) => word.isNotEmpty);
  return words.every((word) => !_swahiliMarkers.contains(word));
}

final _basicLatin = RegExp(r'^[\x09\x0A\x0D\x20-\x7E]+$');
final _hasLetter = RegExp('[A-Za-z]');
final _notLetters = RegExp('[^a-z]+');

const _swahiliMarkers = {
  'daktari',
  'hii',
  'hizi',
  'hiyo',
  'homa',
  'jana',
  'joto',
  'kichwa',
  'kikohozi',
  'koo',
  'kwa',
  'leo',
  'mafua',
  'maumivu',
  'mgonjwa',
  'na',
  'ni',
  'nina',
  'siku',
  'sina',
  'tumbo',
  'wa',
  'wiki',
  'ya',
};

enum HybridHiddenReason {
  switchedOff,
  kiswahili,
  notEnglish,
  unavailable,
  offline,
}

class HybridOffer {
  const HybridOffer({required this.visible, this.reason});

  final bool visible;
  final HybridHiddenReason? reason;
}

/// When the action is offered. Notes need the on-device model. A tidy can
/// use the cloud, so it hides only when that fallback is also impossible.
HybridOffer decideHybridOffer({
  required HybridTask task,
  required HybridSettings settings,
  required HybridStatus status,
  required bool englishLocale,
  required bool online,
  required String text,
}) {
  if (!settings.enabledFor(task)) {
    return const HybridOffer(visible: false, reason: .switchedOff);
  }
  if (!englishLocale) {
    return const HybridOffer(visible: false, reason: .kiswahili);
  }
  if (!looksLikeEnglish(text)) {
    return const HybridOffer(visible: false, reason: .notEnglish);
  }
  final onDevice = status.onDeviceReady;
  if (task == .notesSummary && !onDevice) {
    return HybridOffer(
      visible: false,
      reason: online ? .unavailable : .offline,
    );
  }
  if (task == .symptomTidy && !onDevice && !online) {
    return const HybridOffer(visible: false, reason: .offline);
  }
  return const HybridOffer(visible: true);
}

@LazySingleton(as: HybridAiService)
class ChannelHybridAiService implements HybridAiService {
  ChannelHybridAiService({
    @ignoreParam MethodChannel? channel,
    @ignoreParam EventChannel? events,
  }) : _channel = channel ?? const MethodChannel(HybridAiService.channelName),
       _events =
           events ?? const EventChannel(HybridAiService.downloadChannelName);

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Future<HybridStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<String>('status');
      return HybridStatus.fromWire(raw);
    } on MissingPluginException {
      return .unavailable;
    } on PlatformException catch (error) {
      if (error.code == 'unavailable') return .unavailable;
      throw HybridAiException(HybridFailure.fromCode(error.code));
    }
  }

  @override
  Future<void> download() => _invoke('download');

  @override
  Stream<double> get downloadProgress =>
      _events.receiveBroadcastStream().map((event) {
        if (event is num) return event.toDouble().clamp(0, 1).toDouble();
        return 0;
      });

  @override
  Future<void> warmUp() => _invoke('warmUp');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      throw const HybridAiException(.unavailable);
    } on PlatformException catch (error) {
      throw HybridAiException(HybridFailure.fromCode(error.code));
    }
  }

  @override
  Future<HybridResult> generate(HybridRequest request) async {
    if (request.input.length > hybridMaxInputChars) {
      throw const HybridAiException(.tooLong);
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'generate',
        request.toMap(),
      );
      final result = HybridResult.fromMap(raw);
      if (result == null) throw const HybridAiException(.unknown);
      return result;
    } on HybridAiException {
      rethrow;
    } on MissingPluginException {
      throw const HybridAiException(.unavailable);
    } on PlatformException catch (error) {
      throw HybridAiException(HybridFailure.fromCode(error.code));
    }
  }
}

/// In-process stand-in so the features run before the native plugin exists.
class FakeHybridAiService implements HybridAiService {
  FakeHybridAiService({
    this.statusResult = .available,
    this.result,
    this.error,
  });

  HybridStatus statusResult;
  HybridResult? result;
  HybridAiException? error;
  final List<HybridRequest> requests = [];
  int downloads = 0;
  int warmUps = 0;

  final _progress = StreamController<double>.broadcast();

  @override
  Future<HybridStatus> status() async => statusResult;

  @override
  Future<void> download() async {
    downloads += 1;
  }

  @override
  Stream<double> get downloadProgress => _progress.stream;

  void emitProgress(double value) => _progress.add(value);

  @override
  Future<void> warmUp() async {
    warmUps += 1;
  }

  @override
  Future<HybridResult> generate(HybridRequest request) async {
    requests.add(request);
    final failure = error;
    if (failure != null) throw failure;
    return result ??
        switch (request.task) {
          .symptomTidy => const HybridResult(
            text: 'Headache for two days.',
            source: .onDevice,
          ),
          .notesSummary => const HybridResult(
            text: '- Headache\n- Two days\n- No fever',
            source: .onDevice,
          ),
        };
  }
}
