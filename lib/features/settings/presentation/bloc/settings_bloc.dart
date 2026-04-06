// file: lib/features/settings/presentation/bloc/settings_bloc.dart
// Bug 4 FIX:  Dùng DetectionConfig.setConfidenceThreshold thay vì AppConstants
// Bug 6 FIX:  _onLanguage gọi _configureTts
// Bug 11 FIX: Inject ConfigureTtsUsecase thay vì TtsService trực tiếp

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/detection_config.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../../tts/domain/usecases/configure_tts_usecase.dart';
import '../../../tts/domain/usecases/stop_speaking_usecase.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository  _repository;
  final ConfigureTtsUsecase _configureTts;    // Bug 11 FIX: usecase, không phải TtsService
  final StopSpeakingUsecase _stopSpeaking;
  final DetectionConfig     _detectionConfig; // Bug 4 FIX: mutable config object

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

    // Sync DetectionConfig với persisted value khi load
    _detectionConfig.setConfidenceThreshold(confThresh);

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
    await _configureTts(speechRate: e.rate); // Bug 11 FIX: usecase
    emit(state.copyWith(speechRate: e.rate));
  }

  Future<void> _onConfidence(
    SettingsConfidenceChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setConfidenceThreshold(e.threshold);
    // Bug 4 FIX: Update live config → inference pipeline nhận ngay giá trị mới
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
    // Stop TTS thông qua usecase khi tắt voice
    if (!e.enabled) await _configureTts(); // configure với empty = không đổi gì → OK
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
    // Bug 6 FIX: Re-initialize TTS engine với language mới
    // Bug 11 FIX: Thông qua usecase, không import TtsService
    await _configureTts(language: e.lang);
    emit(state.copyWith(ttsLanguage: e.lang));
  }
}
