// file: lib/features/tts/domain/repositories/tts_repository.dart

abstract class TtsRepository {
  Future<void> initialize();
  Future<void> speakWarning(String text);
  Future<void> speakImmediate(String text);
  Future<void> stop();
  Future<void> pause();
  // Bug 11 FIX: Partial config update thay vì reinitialize toàn bộ
  Future<void> configure({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  });
  bool get isSpeaking;
}