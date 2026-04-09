/// Static helpers for building consistent TTS phrases across the app.
/// This keeps message formatting separate from the business logic in
/// [DetectionObject] and [TtsService].
class VoiceHelper {
  VoiceHelper._();

  /// Full warning sentence including object name, horizontal position,
  /// and estimated distance. The phrasing is tuned for natural playback
  /// by the Vietnamese TTS engine.
  static String buildWarning({
    required String label,
    required String position,
    required String distance,
  }) =>
      'Cảnh báo! $label $position, $distance';

  static String modelLoaded()   => 'Hệ thống sẵn sàng';
  static String noObjectFound() => 'Không phát hiện vật thể';
  static String systemError()   => 'Lỗi hệ thống, vui lòng thử lại';
}
