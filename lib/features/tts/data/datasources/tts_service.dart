import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/constants/app_constants.dart';

/// SV-001 FIX: Xóa double _enqueue() call ở cuối speakWarning()
/// SV-012 FIX: Refactor _lastSpoken cleanup — logic đơn giản, nhất quán
class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  final List<String> _queue = [];

  /// Lưu timestamp lần cuối mỗi text được phát — dùng để enforce cooldown
  final Map<String, DateTime> _lastSpoken = {};

  String _language = AppConstants.ttsLanguage;
  double _speechRate = AppConstants.ttsSpeechRate;
  double _pitch = AppConstants.ttsPitch;
  double _volume = AppConstants.ttsVolume;

  Future<void> initialize({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    if (language != null) _language = language;
    if (speechRate != null) _speechRate = speechRate;
    if (pitch != null) _pitch = pitch;
    if (volume != null) _volume = volume;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(_volume);

    _tts.setStartHandler(() => _isSpeaking = true);
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

  /// FIX SV-001 + SV-012:
  /// - Cleanup _lastSpoken TRƯỚC khi check cooldown (đúng thứ tự)
  /// - Set lastSpoken và enqueue chỉ MỘT LẦN (không còn duplicate)
  /// - Logic đơn giản, linear, dễ đọc
  Future<bool> speakWarning(String text) async {
    final now = DateTime.now();

    // 1. Cleanup các entry đã expired trước khi làm gì
    _pruneLastSpoken(now);

    // 2. Kiểm tra cooldown
    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return false;
    }

    // 3. Ghi nhớ và enqueue — CHỈ MỘT LẦN (đây là fix chính cho SV-001)
    _lastSpoken[text] = now;
    _enqueue(text);
    return true;
  }

  Future<bool> speakImmediate(String text) async {
    final now = DateTime.now();
    _pruneLastSpoken(now);

    // ✅ FIX SV-014: Thêm cooldown cho immediate để chống Stutter
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

  // ─── Private helpers ────────────────────────────────────────────────────────

  /// Xóa các entry đã quá 2× cooldown — tránh map phình không giới hạn
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