import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/audio_service_contract.dart';
import 'package:tabibu/features/cases/data/explanation_audio_cache.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';
import 'package:tabibu/features/reports/presentation/widgets/explanation_language.dart';
import 'package:tabibu/features/reports/presentation/widgets/listen_card.dart';
import 'package:tabibu/l10n/l10n.dart';

/// Plays the doctor-approved explanation the patient can already read. Fetches
/// audio on tap only, caches per request, and never writes anything to disk.
/// Unknown languages hide the card rather than mispronouncing.
class ExplanationListenCard extends StatefulWidget {
  const ExplanationListenCard({
    required this.text,
    required this.language,
    required this.online,
    required this.speech,
    this.player,
    this.analytics,
    this.settings,
    super.key,
  });

  /// Approved explanation text, exactly as shown.
  final String text;

  /// `en` or `sw`, the approved text's language.
  final String language;
  final bool online;
  final SpeechClient speech;
  final AudioPlayerService? player;
  final AnalyticsService? analytics;

  /// Resolved from Remote Config on first play when absent.
  final SpeechSettings? settings;

  @override
  State<ExplanationListenCard> createState() => _ExplanationListenCardState();
}

class _ExplanationListenCardState extends State<ExplanationListenCard> {
  late final AudioPlayerService _player;
  AnalyticsService? _analyticsOrNull;
  StreamSubscription<AudioPlayback>? _sub;
  final _cache = ExplanationAudioCache();
  var _playing = false;
  var _active = false;
  var _loading = false;
  var _error = false;
  Duration _duration = Duration.zero;
  String? _playId;

  @override
  void initState() {
    super.initState();
    _player = widget.player ?? getIt<AudioPlayerService>();
    _analyticsOrNull = widget.analytics;
    _sub = _player.playback.listen(_onPlayback);
  }

  @override
  void didUpdateWidget(covariant ExplanationListenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text &&
        oldWidget.language == widget.language) {
      return;
    }
    // New words: drop the old clip's cache.
    _cache.clear();
    _playing = false;
    _active = false;
    _error = false;
    _loading = false;
    _duration = Duration.zero;
    _playId = null;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onPlayback(AudioPlayback event) {
    if (event.id != _playId) {
      if (_playing || _active) {
        _playing = false;
        _active = false;
        setState(() {});
      }
      return;
    }
    if (event.duration > Duration.zero) _duration = event.duration;
    if (event.completed) {
      _playing = false;
      _active = false;
      setState(() {});
      return;
    }
    _playing = event.playing;
    if (event.playing) _active = true;
    setState(() {});
  }

  AnalyticsService? get _analytics {
    final cached = _analyticsOrNull;
    if (cached != null) return cached;
    if (widget.analytics != null) return widget.analytics;
    if (getIt.isRegistered<AnalyticsService>()) {
      return _analyticsOrNull = getIt<AnalyticsService>();
    }
    return null;
  }

  SpeechSettings get _settings {
    final explicit = widget.settings;
    if (explicit != null) return explicit;
    try {
      return SpeechSettings.resolve(RemoteConfigAiLogicConfig());
    } on Object catch (_) {
      // No Remote Config in reach (tests): the documented defaults.
      return const SpeechSettings(
        voice: SpeechSettings.defaultVoice,
        model: SpeechSettings.defaultModel,
      );
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    final settings = _settings;
    final request = SpeechRequest(
      text: widget.text,
      language: widget.language,
      voice: settings.voice,
      model: settings.model,
    );
    final key = request.cacheKey;
    // Offline plays only from memory; nothing is fetched.
    if (!widget.online && _cache.get(key) == null) {
      setState(() {});
      return;
    }
    // Same clip still loaded: keep the playhead. If another clip took the
    // shared player, resume fails and we reload.
    if (_active && _cache.get(key) != null) {
      final resumed = await _player.resume(key);
      if (resumed) {
        unawaited(_analytics?.logVoicePlaybackStarted(surface: 'explanation'));
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final bytes = _cache.get(key) ?? await widget.speech.speak(request);
      _cache.put(key, bytes);
      if (!mounted) return;
      _playId = key;
      await _player.playBytes(bytes, id: key);
      unawaited(_analytics?.logVoicePlaybackStarted(surface: 'explanation'));
    } on Object catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _format(Duration d) {
    final total = d.inSeconds.clamp(0, 9999);
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (SpeechRequest.languageCodeFor(widget.language) == null) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final meta = _duration > Duration.zero
        ? l10n.resultDetailListenMeta(
            explanationLanguageName(l10n, widget.language),
            _format(_duration),
          )
        : null;
    final offline = !widget.online && _cache.get(_cacheKey) == null;
    final metaLine = meta;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ListenCard(
          title: l10n.resultDetailListenTitle,
          supporting: metaLine ?? l10n.resultDetailListenComputerVoice,
          playing: _playing,
          loading: _loading,
          onToggle: offline ? null : _toggle,
          playLabel: l10n.resultDetailListenPlay,
          pauseLabel: l10n.resultDetailListenPause,
        ),
        if (metaLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.resultDetailListenComputerVoice,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (offline) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.resultDetailListenOffline, style: textTheme.bodySmall),
        ],
        if (_error) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.resultDetailListenFailed, style: textTheme.bodySmall),
        ],
      ],
    );
  }

  String get _cacheKey => SpeechRequest(
    text: widget.text,
    language: widget.language,
    voice: _settings.voice,
    model: _settings.model,
  ).cacheKey;
}
