// file: lib/features/tts/domain/usecases/configure_tts_usecase.dart

import '../repositories/tts_repository.dart';

/// Usecase cho phép Settings feature cập nhật TTS config
/// mà không cần biết về TtsService (data layer).
class ConfigureTtsUsecase {
  final TtsRepository _repository;
  ConfigureTtsUsecase(this._repository);

  Future<void> call({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) => _repository.configure(
    language:   language,
    speechRate: speechRate,
    pitch:      pitch,
    volume:     volume,
  );
}