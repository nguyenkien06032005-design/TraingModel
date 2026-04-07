import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/config/detection_config.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';
import 'package:safe_vision_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_event.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_state.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/configure_tts_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockSettingsRepository extends Mock implements SettingsRepository {}
class MockTtsRepository      extends Mock implements TtsRepository {}

void main() {
  late MockSettingsRepository mockRepo;
  late ConfigureTtsUsecase    configureTts;
  late StopSpeakingUsecase    stopSpeaking;
  late DetectionConfig        detectionConfig;
  late MockTtsRepository      mockTtsRepo;

  /// Capture configure() calls để verify params
  final List<Map<String, dynamic>> capturedConfigCalls = [];

  setUp(() {
    mockRepo        = MockSettingsRepository();
    mockTtsRepo     = MockTtsRepository();
    detectionConfig = DetectionConfig();
    capturedConfigCalls.clear();

    configureTts = ConfigureTtsUsecase(mockTtsRepo);
    stopSpeaking = StopSpeakingUsecase(mockTtsRepo);

    // Default stubs
    when(() => mockRepo.getSpeechRate())
        .thenAnswer((_) async => AppConstants.ttsSpeechRate);
    when(() => mockRepo.getConfidenceThreshold())
        .thenAnswer((_) async => AppConstants.confidenceThreshold);
    when(() => mockRepo.getVoiceEnabled())
        .thenAnswer((_) async => true);
    when(() => mockRepo.getShowConfidencePanel())
        .thenAnswer((_) async => true);
    when(() => mockRepo.getTtsLanguage())
        .thenAnswer((_) async => 'vi-VN');
    when(() => mockRepo.setTtsLanguage(any()))
        .thenAnswer((_) async {});
    when(() => mockRepo.setSpeechRate(any()))
        .thenAnswer((_) async {});
    when(() => mockRepo.setVoiceEnabled(any()))
        .thenAnswer((_) async {});
    when(() => mockRepo.setConfidenceThreshold(any()))
        .thenAnswer((_) async {});
    when(() => mockRepo.setShowConfidencePanel(any()))
        .thenAnswer((_) async {});
    when(() => mockTtsRepo.configure(
      language:   any(named: 'language'),
      speechRate: any(named: 'speechRate'),
      pitch:      any(named: 'pitch'),
      volume:     any(named: 'volume'),
    )).thenAnswer((invocation) async {
      capturedConfigCalls.add({
        'language':   invocation.namedArguments[const Symbol('language')],
        'speechRate': invocation.namedArguments[const Symbol('speechRate')],
      });
    });
    when(() => mockTtsRepo.stop()).thenAnswer((_) async {});
  });

  SettingsBloc buildBloc() => SettingsBloc(
    mockRepo, configureTts, stopSpeaking, detectionConfig,
  );

  // ─── FIX SV-006: Language change preserves speechRate ───────────────────

  group('FIX SV-006: SettingsTtsLanguageChanged preserves speechRate', () {
    blocTest<SettingsBloc, SettingsState>(
      'switching language keeps current speechRate in TTS config',
      build: () {
        // Setup: speechRate đã được set thành 0.75
        when(() => mockRepo.getSpeechRate()).thenAnswer((_) async => 0.75);
        return buildBloc();
      },
      act: (bloc) async {
        // Load settings trước (speechRate = 0.75)
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));

        // Đổi language
        bloc.add(const SettingsTtsLanguageChanged('en-US'));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (_) {
        // Tìm configure call từ SettingsTtsLanguageChanged (lần cuối)
        final langChangeCalls = capturedConfigCalls
            .where((c) => c['language'] == 'en-US')
            .toList();

        expect(langChangeCalls, isNotEmpty,
            reason: 'TTS configure phải được gọi khi đổi language');

        final call = langChangeCalls.last;
        expect(call['speechRate'], equals(0.75),
            reason: 'FIX SV-006: speechRate (0.75) phải được giữ nguyên khi đổi language. '
                'BUG CŨ: speechRate = null → TTS reset về default speed');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'language change emits state with new language but same speechRate',
      build: () {
        when(() => mockRepo.getSpeechRate()).thenAnswer((_) async => 0.6);
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsTtsLanguageChanged('en-US'));
      },
      expect: () => [
        isA<SettingsState>().having((s) => s.isLoading, 'isLoading', isTrue),
        isA<SettingsState>()
            .having((s) => s.isLoading, 'isLoading', isFalse)
            .having((s) => s.speechRate, 'speechRate', closeTo(0.6, 0.001)),
        // State sau language change: language updated, speechRate unchanged
        isA<SettingsState>()
            .having((s) => s.ttsLanguage, 'ttsLanguage', 'en-US')
            .having((s) => s.speechRate, 'speechRate', closeTo(0.6, 0.001)),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'changing speechRate then language: language call uses updated rate',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        // Đổi rate đến 0.8
        bloc.add(const SettingsSpeechRateChanged(0.8));
        await Future.delayed(const Duration(milliseconds: 10));
        // Đổi language — phải dùng rate 0.8
        bloc.add(const SettingsTtsLanguageChanged('en-US'));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (_) {
        final langCalls = capturedConfigCalls
            .where((c) => c['language'] == 'en-US')
            .toList();

        expect(langCalls, isNotEmpty);
        expect(langCalls.last['speechRate'], closeTo(0.8, 0.001),
            reason: 'Sau khi rate được set = 0.8, language change phải dùng 0.8');
      },
    );
  });

  // ─── speechRate change tests ─────────────────────────────────────────────

  group('SettingsSpeechRateChanged', () {
    blocTest<SettingsBloc, SettingsState>(
      'updates state and calls TTS configure with both rate and language',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsSpeechRateChanged(0.75));
      },
      verify: (_) {
        final rateCalls = capturedConfigCalls
            .where((c) => c['speechRate'] == 0.75)
            .toList();
        expect(rateCalls, isNotEmpty);
        // Language phải được pass bersama rate
        expect(rateCalls.last['language'], isNotNull);
      },
    );
  });

  // ─── Confidence threshold → DetectionConfig ──────────────────────────────

  group('SettingsConfidenceChanged → updates DetectionConfig', () {
    blocTest<SettingsBloc, SettingsState>(
      'confidence change applies to DetectionConfig immediately',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsConfidenceChanged(0.65));
      },
      verify: (_) {
        expect(
          detectionConfig.confidenceThreshold,
          closeTo(0.65, 0.001),
          reason: 'DetectionConfig phải được update ngay khi confidence thay đổi',
        );
      },
    );
  });

  // ─── Voice toggle ────────────────────────────────────────────────────────

  group('SettingsVoiceToggled', () {
    blocTest<SettingsBloc, SettingsState>(
      'disabling voice calls stopSpeaking',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsVoiceToggled(false));
      },
      expect: () => [
        isA<SettingsState>().having((s) => s.isLoading, '', isTrue),
        isA<SettingsState>().having((s) => s.voiceEnabled, '', isTrue),
        isA<SettingsState>().having((s) => s.voiceEnabled, '', isFalse),
      ],
      verify: (_) {
        verify(() => mockTtsRepo.stop()).called(1);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'enabling voice does not call stopSpeaking',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsVoiceToggled(true));
      },
      verify: (_) {
        verifyNever(() => mockTtsRepo.stop());
      },
    );
  });
}
