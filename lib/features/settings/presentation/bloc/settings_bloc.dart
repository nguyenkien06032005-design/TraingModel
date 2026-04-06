




import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/detection_config.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../../tts/domain/usecases/configure_tts_usecase.dart';
import '../../../tts/domain/usecases/stop_speaking_usecase.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository  _repository;
  final ConfigureTtsUsecase _configureTts;    
  final StopSpeakingUsecase _stopSpeaking;
  final DetectionConfig     _detectionConfig; 

  SettingsBloc(
    this._repository,
    this._configureTts,
    this._stopSpeaking,
    this._detectionConfig,
  ) : super(const SettingsState()) {
    on<SettingsLoaded>(_onLoaded);
    on<SettingsSpeechRateChanged>(_onSpeechRate);
    on<SettingsConfidenceChanged>(_onConfidence);
    on<SettingsVoiceToggled>(_onVoice);
    on<SettingsConfidencePanelToggled>(_onPanel);
    on<SettingsTtsLanguageChanged>(_onLanguage);
  }

  Future<void> _onLoaded(
    SettingsLoaded event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    final speechRate   = await _repository.getSpeechRate();
    final confThresh   = await _repository.getConfidenceThreshold();
    final voiceEnabled = await _repository.getVoiceEnabled();
    final showPanel    = await _repository.getShowConfidencePanel();
    final language     = await _repository.getTtsLanguage();

    
    _detectionConfig.setConfidenceThreshold(confThresh);
    await _configureTts(
      speechRate: speechRate,
      language: language,
    );

    emit(state.copyWith(
      speechRate:          speechRate,
      confidenceThreshold: confThresh,
      voiceEnabled:        voiceEnabled,
      showConfidencePanel: showPanel,
      ttsLanguage:         language,
      isLoading:           false,
    ));
  }

  Future<void> _onSpeechRate(
    SettingsSpeechRateChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setSpeechRate(e.rate);
    await _configureTts(speechRate: e.rate); 
    emit(state.copyWith(speechRate: e.rate));
  }

  Future<void> _onConfidence(
    SettingsConfidenceChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setConfidenceThreshold(e.threshold);
    
    _detectionConfig.setConfidenceThreshold(e.threshold);
    emit(state.copyWith(confidenceThreshold: e.threshold));
  }

  Future<void> _onVoice(
    SettingsVoiceToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setVoiceEnabled(e.enabled);
    if (!e.enabled) {
      await _stopSpeaking();
    }
    emit(state.copyWith(voiceEnabled: e.enabled));
  }

  Future<void> _onPanel(
    SettingsConfidencePanelToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setShowConfidencePanel(e.show);
    emit(state.copyWith(showConfidencePanel: e.show));
  }

  Future<void> _onLanguage(
    SettingsTtsLanguageChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setTtsLanguage(e.lang);
    
    
    await _configureTts(language: e.lang);
    emit(state.copyWith(ttsLanguage: e.lang));
  }
}
