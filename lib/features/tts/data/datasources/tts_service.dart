// file: lib/features/tts/data/datasources/tts_service.dart
// Bug 5 FIX: Dùng AppConstants.ttsCooldownMs
// Bug 8 FIX: dispose() async
// Bug 11 FIX: configure() partial update
// FIX: _lastSpoken cleared trong stop() + dispose() — tránh memory leak và cooldown stale qua session

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/constants/app_constants.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool           _isSpeaking = false;
  final List<String>        _queue      = [];
  final Map<String, DateTime> _lastSpoken = {};

  // Bug 11 FIX: Cache current config để partial update không reset unrelated settings
  String _language   = AppConstants.ttsLanguage;
  double _speechRate = AppConstants.ttsSpeechRate;
  double _pitch      = AppConstants.ttsPitch;
  double _volume     = AppConstants.ttsVolume;

  Future<void> initialize({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    // Chỉ update những gì được truyền vào — không reset các field khác
    if (language   != null) _language   = language;
    if (speechRate != null) _speechRate = speechRate;
    if (pitch      != null) _pitch      = pitch;
    if (volume     != null) _volume     = volume;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(_volume);

    _tts.setStartHandler(()      { _isSpeaking = true; });
    _tts.setCompletionHandler(() { _isSpeaking = false; _processQueue(); });
    _tts.setCancelHandler(()    { _isSpeaking = false; _queue.clear(); });
    _tts.setErrorHandler((_)    { _isSpeaking = false; _processQueue(); });
  }

  Future<void> speakWarning(String text) async {
    final now  = DateTime.now();
    final last = _lastSpoken[text];
    // Bug 5 FIX: AppConstants.ttsCooldownMs thay vì hardcoded 3000
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return;
    }
    _lastSpoken[text] = now;
    _enqueue(text);
  }

  Future<void> speakImmediate(String text) async {
    await _tts.stop();
    _queue.clear();
    _isSpeaking = false;
    await _speak(text);
  }

  Future<void> stop() async {
    _queue.clear();
    _lastSpoken.clear(); // FIX: xóa cooldown stale — không để session cũ ảnh hưởng session sau
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> pause() async => _tts.pause();

  bool get isSpeaking => _isSpeaking;

  // Bug 8 FIX: async + await — không discard Future
  Future<void> dispose() async {
    _queue.clear();
    _lastSpoken.clear(); // FIX: giải phóng toàn bộ cooldown cache khi dispose
    await _tts.stop();
    _isSpeaking = false;
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
    await _tts.speak(text);
  }
}