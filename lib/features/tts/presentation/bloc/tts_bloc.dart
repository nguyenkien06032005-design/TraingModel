import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import '../../../settings/domain/repositories/settings_repository.dart';
import '../../domain/usecases/speak_warning_usecase.dart';
import '../../domain/usecases/stop_speaking_usecase.dart';
import '../../domain/usecases/pause_speaking_usecase.dart';
import 'tts_event.dart';
import 'tts_state.dart';

class TtsBloc extends Bloc<TtsEvent, TtsState> {
  final SpeakWarningUsecase  _speakWarning;
  final StopSpeakingUsecase  _stopSpeaking;
  final PauseSpeakingUsecase _pauseSpeaking; 
  final SettingsRepository   _settingsRepository;

  TtsBloc({
    required SpeakWarningUsecase  speakWarning,
    required StopSpeakingUsecase  stopSpeaking,
    required PauseSpeakingUsecase pauseSpeaking,
    required SettingsRepository settingsRepository,
  })  : _speakWarning  = speakWarning,
        _stopSpeaking  = stopSpeaking,
        _pauseSpeaking = pauseSpeaking,
        _settingsRepository = settingsRepository,
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
  }

  Future<void> _onSpeak(TtsSpeak event, Emitter<TtsState> emit) async {
    try {
      final voiceEnabled = await _settingsRepository.getVoiceEnabled();
      if (!voiceEnabled) {
        if (state is TtsSpeaking) {
          await _stopSpeaking();
          emit(const TtsStopped());
        }
        return;
      }

      bool accepted = false;
      if (event.immediate) {
        accepted = await _speakWarning.immediate(event.text);
      } else {
        accepted = await _speakWarning(event.text);
      }

      // ✅ FIX SV-014: Gỡ Rung Ảo.
      // Chỉ kích hoạt motor rung nếu thực sự TTS vượt qua rào cản Cooldown
      if (accepted && event.withVibration) {
        final bool hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [0, 300, 150, 300]);
        }
      }

      emit(TtsSpeaking(event.text));
    } catch (e) {
      emit(TtsError(e.toString()));
    }
  }

  Future<void> _onStop(TtsStop event, Emitter<TtsState> emit) async {
    await _stopSpeaking();
    emit(const TtsStopped());
  }

  Future<void> _onPause(TtsPause event, Emitter<TtsState> emit) async {
    
    await _pauseSpeaking();
    emit(const TtsPaused());
  }
}
