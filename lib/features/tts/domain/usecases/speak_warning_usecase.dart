import '../repositories/tts_repository.dart';

class SpeakWarningUsecase {
  final TtsRepository _repository;
  SpeakWarningUsecase(this._repository);

  
  Future<void> call(String text) => _repository.speakWarning(text);

  
  Future<void> immediate(String text) => _repository.speakImmediate(text);
}