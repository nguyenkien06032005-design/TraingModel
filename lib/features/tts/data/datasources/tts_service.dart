import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/constants/app_constants.dart';

/// Wrapper around [FlutterTts] with cooldown protection and queue deduplication.
///
/// Important invariants:
/// 1. The same text must not be spoken again within
///    [AppConstants.ttsCooldownMs].
/// 2. A text must not be added to the queue twice. Enqueue happens only once
///    after the cooldown check succeeds.
///
/// Playback modes:
/// - [speakWarning]: enqueue and wait for the current audio to finish.
/// - [speakImmediate]: stop current audio and queue, then speak immediately.
///   Used for high-priority danger warnings.
class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  final List<String> _queue = [];

  /// Last accepted timestamp for each text, used to enforce cooldown.
  /// The map is pruned periodically so it cannot grow without bound.
  final Map<String, DateTime> _lastSpoken = {};

  String _language  = AppConstants.ttsLanguage;
  double _speechRate = AppConstants.ttsSpeechRate;
  double _pitch      = AppConstants.ttsPitch;
  double _volume     = AppConstants.ttsVolume;

  Future<void> initialize({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    if (language   != null) _language   = language;
    if (speechRate != null) _speechRate = speechRate;
    if (pitch      != null) _pitch      = pitch;
    if (volume     != null) _volume     = volume;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(_volume);

    _tts.setStartHandler(()  => _isSpeaking = true);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _queue.clear();
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
      _processQueue();
    });
  }

  /// Speaks text through the queue while respecting per-text cooldown.
  ///
  /// Processing order:
  /// 1. Prune expired entries so the map stays bounded.
  /// 2. Check cooldown and return `false` immediately if still inside it.
  /// 3. Record the timestamp and enqueue exactly once.
  Future<bool> speakWarning(String text) async {
    final now = DateTime.now();
    _pruneLastSpoken(now);

    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return false;
    }

    _lastSpoken[text] = now;
    _enqueue(text);
    return true;
  }

  /// Speaks text immediately, bypassing the current queue.
  /// Applies the same cooldown as [speakWarning] to avoid stutter when the
  /// same danger warning is triggered repeatedly.
  Future<bool> speakImmediate(String text) async {
    final now = DateTime.now();
    _pruneLastSpoken(now);

    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return false;
    }

    _lastSpoken[text] = now;

    await _tts.stop();
    _queue.clear();
    _isSpeaking = false;
    await _speak(text);
    return true;
  }

  Future<void> stop() async {
    _queue.clear();
    _lastSpoken.clear();
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> pause() async => _tts.pause();

  bool get isSpeaking => _isSpeaking;

  Future<void> dispose() async {
    _queue.clear();
    _lastSpoken.clear();
    await _tts.stop();
    _isSpeaking = false;
  }

  // Private helpers

  /// Removes entries older than two cooldown windows.
  /// Runs only when the map grows beyond 100 entries to avoid an O(n) scan on
  /// every frame.
  void _pruneLastSpoken(DateTime now) {
    if (_lastSpoken.length > 100) {
      _lastSpoken.removeWhere((_, time) =>
          now.difference(time).inMilliseconds > AppConstants.ttsCooldownMs * 2);
    }
  }

  void _enqueue(String text) {
    if (!_queue.contains(text)) _queue.add(text);
    if (!_isSpeaking) _processQueue();
  }

  void _processQueue() {
    if (_queue.isEmpty || _isSpeaking) return;
    _speak(_queue.removeAt(0));
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    _isSpeaking = true;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TtsService] speak error: $e');
      _isSpeaking = false;
      _processQueue();
    }
  }
}
