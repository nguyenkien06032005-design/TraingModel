// file: lib/features/tts/domain/usecases/pause_speaking_usecase.dart

import '../repositories/tts_repository.dart';

class PauseSpeakingUsecase {
  final TtsRepository _repository;
  PauseSpeakingUsecase(this._repository);

  Future<void> call() => _repository.pause();
}