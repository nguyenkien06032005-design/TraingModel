import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import '../../domain/usecases/speak_warning_usecase.dart';
import '../../domain/usecases/stop_speaking_usecase.dart';
import '../../domain/usecases/pause_speaking_usecase.dart';
import 'tts_event.dart';
import 'tts_state.dart';

class TtsBloc extends Bloc<TtsEvent, TtsState> {
  final SpeakWarningUsecase  _speakWarning;
  final StopSpeakingUsecase  _stopSpeaking;
  final PauseSpeakingUsecase _pauseSpeaking; // Bug 9 FIX

  TtsBloc({
    required SpeakWarningUsecase  speakWarning,
    required StopSpeakingUsecase  stopSpeaking,
    required PauseSpeakingUsecase pauseSpeaking,
  })  : _speakWarning  = speakWarning,
        _stopSpeaking  = stopSpeaking,
        _pauseSpeaking = pauseSpeaking,
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
  }

  Future<void> _onSpeak(TtsSpeak event, Emitter<TtsState> emit) async {
    try {
      if (event.withVibration) {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator) {
          Vibration.vibrate(pattern: [0, 300, 150, 300]);
        }
      }

      if (event.immediate) {
        await _speakWarning.immediate(event.text);
      } else {
        await _speakWarning(event.text);
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
    // Bug 9 FIX: Thực sự pause TTS engine thay vì chỉ emit state
    await _pauseSpeaking();
    emit(const TtsPaused());
  }
}