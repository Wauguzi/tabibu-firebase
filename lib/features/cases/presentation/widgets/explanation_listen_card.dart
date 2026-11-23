import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/helpers/db_helper.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/audio_service_contract.dart';
import 'package:tabibu/features/cases/data/explanation_audio_cache.dart';
import 'package:tabibu/features/cases/data/explanation_audio_store.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';
import 'package:tabibu/features/reports/presentation/widgets/explanation_language.dart';
import 'package:tabibu/features/reports/presentation/widgets/listen_card.dart';
import 'package:tabibu/l10n/l10n.dart';

/// Plays the doctor-approved explanation the patient can already read. Fetches
/// audio on tap only; keeps played clips in memory and in the encrypted
/// audio store until sign-out. Unknown languages hide the card rather than
/// mispronouncing.
class ExplanationListenCard extends StatefulWidget {
  const ExplanationListenCard({
    required this.text,
    required this.language,
    required this.online,
    required this.speech,
    this.player,
    this.analytics,
    this.settings,
    this.logger,
    this.audioStore,
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

  /// Debug failure log; a default logger when absent.
  final Logger? logger;

  /// On-disk audio; a live store when absent.
  final ExplanationAudioStore? audioStore;

  @override
  State<ExplanationListenCard> createState() => _ExplanationListenCardState();
}

class _ExplanationListenCardState extends State<ExplanationListenCard> {
  late final AudioPlayerService _player;
  late final Logger _logger;
  late final ExplanationAudioStore _store;
  AnalyticsService? _analyticsOrNull;
  StreamSubscription<AudioPlayback>? _sub;
  final _cache = ExplanationAudioCache();
  var _playing = false;
  var _active = false;
  var _loading = false;
  var _error = false;
  Duration _duration = Duration.zero;
  String? _playId;

  /// Bumped by dispose, new words and covering: a start whose generation
  /// went stale drops or stops instead of playing.
  var _generation = 0;

  /// Whether our route is the top one; covering stops playback.
  var _routeCurrent = true;

  @override
  void initState() {
    super.initState();
    _player = widget.player ?? getIt<AudioPlayerService>();
    _logger = widget.logger ?? Logger();
    _store = widget.audioStore ?? ExplanationAudioStore(getIt<DBHelper>());
    _analyticsOrNull = widget.analytics;
    _sub = _player.playback.listen(_onPlayback);
    unawaited(_hydrate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No route (bare pumps) reads as current.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current == _routeCurrent) return;
    _routeCurrent = current;
    // Uncovering never auto-plays: the card just shows play again.
    if (current) return;
    // Covered: pending starts go stale and a playing clip stops. The
    // dependency change already schedules the rebuild.
    _generation++;
    if (_playing) {
      _playing = false;
      _active = false;
      unawaited(_player.stop());
    }
  }

  @override
  void didUpdateWidget(covariant ExplanationListenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text &&
        oldWidget.language == widget.language) {
      return;
    }
    // New words: pending starts go stale, a playing old clip stops, and
    // its cache goes. The play id stays for the late-start stop check.
    final wasPlaying = _playing;
    _generation++;
    _cache.clear();
    _playing = false;
    _active = false;
    _error = false;
    _loading = false;
    _duration = Duration.zero;
    if (wasPlaying) unawaited(_player.stop());
    unawaited(_hydrate());
  }

  /// Warms the memory cache from disk, so an offline replay shows play
  /// instead of the offline line. Key-checked: newer words win.
  Future<void> _hydrate() async {
    final key = _cacheKey;
    final bytes = await _readStored();
    if (!mounted || key != _cacheKey || bytes == null) return;
    setState(() => _cache.put(key, bytes));
  }

  /// Disk audio for the current request, or null on a miss or a store
  /// failure. A miss just means the model is asked.
  Future<Uint8List?> _readStored() async {
    try {
      return await _store.get(_request);
    } on Object catch (error) {
      if (kDebugMode) {
        _logger.e('Listen store read failed: ${error.runtimeType}');
      }
      return null;
    }
  }

  /// Persists a fresh clip. Playback already started, so a failure only logs.
  Future<void> _storePut(SpeechRequest request, Uint8List bytes) async {
    try {
      await _store.put(request, bytes);
    } on Object catch (error) {
      if (kDebugMode) {
        _logger.e('Listen store write failed: ${error.runtimeType}');
      }
    }
  }

  /// Refreshes a replayed clip's age. Playback already started, so a
  /// failure only logs.
  Future<void> _storePlayed(SpeechRequest request) async {
    try {
      await _store.played(request);
    } on Object catch (error) {
      if (kDebugMode) {
        _logger.e('Listen store write failed: ${error.runtimeType}');
      }
    }
  }

  @override
  void dispose() {
    // Cancel first: nothing is left to hear the stop's own event.
    final wasPlaying = _playing;
    _generation++;
    unawaited(_sub?.cancel());
    if (wasPlaying) unawaited(_player.stop());
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
    if (event.failed) {
      // A failed play is not resumable: back to play with the error.
      _playing = false;
      _active = false;
      _loading = false;
      _error = true;
      setState(() {});
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
      unawaited(_analytics?.logVoicePlaybackPaused());
      return;
    }
    final generation = _generation;
    final request = _request;
    final key = request.cacheKey;
    final stored = _cache.get(key) ?? await _readStored();
    // Offline replays come from the caches; nothing is fetched.
    if (!widget.online && stored == null) {
      setState(() {});
      return;
    }
    // Same clip still loaded: keep the playhead. If another clip took the
    // shared player, resume fails and we reload.
    if (_active && _cache.get(key) != null) {
      final resumed = await _player.resume(key);
      if (resumed) {
        unawaited(_analytics?.logVoicePlaybackStarted(surface: 'explanation'));
        unawaited(_storePlayed(request));
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final Uint8List bytes;
      final bool fresh;
      if (stored != null) {
        bytes = stored;
        fresh = false;
      } else {
        fresh = true;
        try {
          bytes = await widget.speech.speak(request);
        } on Object catch (error) {
          if (kDebugMode) {
            _logger.e(
              'Listen speak failed: ${error.runtimeType} '
              '(language ${request.language}, voice ${request.voice}, '
              'model ${request.model}, text ${request.text.length} chars)',
            );
          }
          rethrow;
        }
      }
      // A stale start drops unplayed: new words, dispose or covering.
      if (!mounted || key != _cacheKey || generation != _generation) return;
      _cache.put(key, bytes);
      _playId = key;
      try {
        await _player.playBytes(bytes, id: key);
      } on Object catch (error) {
        if (kDebugMode) {
          _logger.e(
            'Listen play failed: ${error.runtimeType} (${bytes.length} bytes)',
          );
        }
        rethrow;
      }
      if (generation != _generation) {
        // Started late: stop it, unless a newer start took the player.
        if (_playId == key) unawaited(_player.stop());
        return;
      }
      unawaited(_analytics?.logVoicePlaybackStarted(surface: 'explanation'));
      // Persist fresh clips, refresh replays. Playback already started.
      if (fresh) {
        unawaited(_storePut(request, bytes));
      } else {
        unawaited(_storePlayed(request));
      }
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

  SpeechRequest get _request => SpeechRequest(
    text: widget.text,
    language: widget.language,
    voice: _settings.voice,
    model: _settings.model,
  );

  String get _cacheKey => _request.cacheKey;
}
