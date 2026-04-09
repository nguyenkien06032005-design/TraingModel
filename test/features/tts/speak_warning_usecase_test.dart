import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/speak_warning_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_bloc.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_event.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_state.dart';

class MockTtsRepository      extends Mock implements TtsRepository {}
class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late MockTtsRepository      mockRepo;
  late MockSettingsRepository mockSettingsRepository;

  setUp(() {
    mockRepo               = MockTtsRepository();
    mockSettingsRepository = MockSettingsRepository();
    when(() => mockSettingsRepository.getVoiceEnabled())
        .thenAnswer((_) async => true);
  });

  // ─── SpeakWarningUsecase ──────────────────────────────────────────────────

  group('SpeakWarningUsecase', () {
    late SpeakWarningUsecase usecase;

    setUp(() => usecase = SpeakWarningUsecase(mockRepo));

    test('call() delegates to repository.speakWarning()', () async {
      const text = 'Pedestrian detected ahead, close';
      // speakWarning returns Future<bool> — stub must match the declared type.
      when(() => mockRepo.speakWarning(text)).thenAnswer((_) async => true);

      await usecase(text);

      verify(() => mockRepo.speakWarning(text)).called(1);
    });

    test('immediate() delegates to repository.speakImmediate()', () async {
      const text = 'Warning! Pedestrian very close';
      // speakImmediate returns Future<bool> — stub must match the declared type.
      when(() => mockRepo.speakImmediate(text)).thenAnswer((_) async => true);

      await usecase.immediate(text);

      verify(() => mockRepo.speakImmediate(text)).called(1);
    });

    test('call() does not invoke speakImmediate()', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);

      await usecase('test');

      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    test('immediate() does not invoke speakWarning()', () async {
      when(() => mockRepo.speakImmediate(any())).thenAnswer((_) async => true);

      await usecase.immediate('test');

      verifyNever(() => mockRepo.speakWarning(any()));
    });

    test('passes text exactly to repository', () async {
      const exactText = 'Bicycle detected on the left, medium distance';
      when(() => mockRepo.speakWarning(exactText)).thenAnswer((_) async => true);

      await usecase(exactText);

      verify(() => mockRepo.speakWarning(exactText)).called(1);
    });

    test('call() meneruskan exception dari repository', () async {
      when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase('text'), throwsException);
    });

    test('immediate() meneruskan exception dari repository', () async {
      when(() => mockRepo.speakImmediate(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase.immediate('text'), throwsException);
    });

    test('forwards empty string to repository', () async {
      when(() => mockRepo.speakWarning('')).thenAnswer((_) async => true);

      await usecase('');

      verify(() => mockRepo.speakWarning('')).called(1);
    });

    test('multiple calls are each delegated independently', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);

      await usecase('first');
      await usecase('second');
      await usecase('third');

      verify(() => mockRepo.speakWarning(any())).called(3);
    });
  });

  // ─── StopSpeakingUsecase ──────────────────────────────────────────────────

  group('StopSpeakingUsecase', () {
    late StopSpeakingUsecase usecase;

    setUp(() => usecase = StopSpeakingUsecase(mockRepo));

    test('call() mendelegasikan ke repository.stop()', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.stop()).called(1);
    });

    test('tidak memanggil speak methods', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verifyNever(() => mockRepo.speakWarning(any()));
      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    test('meneruskan exception dari repository', () async {
      when(() => mockRepo.stop()).thenThrow(Exception('stop failed'));

      expect(() => usecase(), throwsException);
    });

    test('beberapa panggilan stop masing-masing didelegasikan', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();
      await usecase();

      verify(() => mockRepo.stop()).called(2);
    });
  });

  // ─── PauseSpeakingUsecase ─────────────────────────────────────────────────

  group('PauseSpeakingUsecase', () {
    late PauseSpeakingUsecase usecase;

    setUp(() => usecase = PauseSpeakingUsecase(mockRepo));

    test('call() mendelegasikan ke repository.pause()', () async {
      when(() => mockRepo.pause()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.pause()).called(1);
    });

    test('meneruskan exception dari repository', () async {
      when(() => mockRepo.pause()).thenThrow(Exception('pause failed'));

      expect(() => usecase(), throwsException);
    });
  });

  // ─── TtsBloc ──────────────────────────────────────────────────────────────

  group('TtsBloc', () {
    late SpeakWarningUsecase  speakWarningUsecase;
    late StopSpeakingUsecase  stopSpeakingUsecase;
    late PauseSpeakingUsecase pauseSpeakingUsecase;

    setUp(() {
      speakWarningUsecase  = SpeakWarningUsecase(mockRepo);
      stopSpeakingUsecase  = StopSpeakingUsecase(mockRepo);
      pauseSpeakingUsecase = PauseSpeakingUsecase(mockRepo);
    });

    TtsBloc buildBloc() => TtsBloc(
          speakWarning:       speakWarningUsecase,
          stopSpeaking:       stopSpeakingUsecase,
          pauseSpeaking:      pauseSpeakingUsecase,
          settingsRepository: mockSettingsRepository,
        );

    test('state awal adalah TtsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const TtsInitial());
      bloc.close();
    });

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak (queued) → calls speakWarning and emits TtsSpeaking',
      // speakWarning returns Future<bool>; returning true means TTS accepted the call.
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenAnswer((_) async => true),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('Pedestrian detected ahead')),
      expect: () => [const TtsSpeaking('Pedestrian detected ahead')],
      verify: (_) => verify(() => mockRepo.speakWarning(
            'Pedestrian detected ahead',
          )).called(1),
    );

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak(immediate:true) → calls speakImmediate and emits TtsSpeaking',
      // speakImmediate returns Future<bool>; returning true means TTS accepted.
      setUp: () => when(() => mockRepo.speakImmediate(any()))
          .thenAnswer((_) async => true),
      build: buildBloc,
      act: (bloc) => bloc.add(
          const TtsSpeak('Warning! Very close', immediate: true, withVibration: false)),
      expect: () => [const TtsSpeaking('Warning! Very close')],
      verify: (_) {
        verify(() => mockRepo.speakImmediate('Warning! Very close')).called(1);
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsStop → memanggil repository.stop() dan emit TtsStopped',
      setUp: () => when(() => mockRepo.stop()).thenAnswer((_) async {}),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsStop()),
      expect: () => [const TtsStopped()],
      verify: (_) => verify(() => mockRepo.stop()).called(1),
    );

    blocTest<TtsBloc, TtsState>(
      'TtsPause → memanggil repository.pause() dan emit TtsPaused',
      setUp: () => when(() => mockRepo.pause()).thenAnswer((_) async {}),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsPause()),
      expect: () => [const TtsPaused()],
      verify: (_) {
        verify(() => mockRepo.pause()).called(1);
        verifyNever(() => mockRepo.stop());
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak emit TtsError saat speakWarning throw',
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('engine crashed')),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [isA<TtsError>()],
    );

    blocTest<TtsBloc, TtsState>(
      'tidak memanggil speak saat voice dinonaktifkan di pengaturan',
      setUp: () => when(() => mockSettingsRepository.getVoiceEnabled())
          .thenAnswer((_) async => false),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => <TtsState>[],
      verify: (_) {
        verifyNever(() => mockRepo.speakWarning(any()));
        verifyNever(() => mockRepo.speakImmediate(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsError berisi pesan error dari exception',
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('engine crashed')),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [
        predicate<TtsState>(
          (s) => s is TtsError && s.message.contains('engine crashed'),
          'TtsError dengan pesan engine crashed',
        ),
      ],
    );

    blocTest<TtsBloc, TtsState>(
      'speak then stop sequence emits [TtsSpeaking, TtsStopped]',
      setUp: () {
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TtsSpeak('hello'));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TtsStop());
      },
      expect: () => [const TtsSpeaking('hello'), const TtsStopped()],
    );
  });

  // ─── TtsEvent equality ────────────────────────────────────────────────────

  group('TtsEvent equality', () {
    test('TtsSpeak dengan params yang sama adalah equal', () {
      const a = TtsSpeak('hello', immediate: true, withVibration: true);
      const b = TtsSpeak('hello', immediate: true, withVibration: true);
      expect(a, equals(b));
    });

    test('TtsSpeak dengan text berbeda tidak equal', () {
      const a = TtsSpeak('hello');
      const b = TtsSpeak('world');
      expect(a, isNot(equals(b)));
    });

    test('TtsSpeak dengan flag immediate berbeda tidak equal', () {
      const a = TtsSpeak('hello', immediate: true);
      const b = TtsSpeak('hello', immediate: false);
      expect(a, isNot(equals(b)));
    });

    test('TtsStop equal dengan TtsStop lainnya', () {
      expect(const TtsStop(), equals(const TtsStop()));
    });

    test('TtsPause equal dengan TtsPause lainnya', () {
      expect(const TtsPause(), equals(const TtsPause()));
    });
  });

  // ─── TtsState equality ────────────────────────────────────────────────────

  group('TtsState equality', () {
    test('TtsInitial equal', () =>
        expect(const TtsInitial(), equals(const TtsInitial())));

    test('TtsSpeaking dengan text sama equal', () {
      expect(const TtsSpeaking('text'), equals(const TtsSpeaking('text')));
    });

    test('TtsSpeaking dengan text berbeda tidak equal', () {
      expect(const TtsSpeaking('hello'), isNot(equals(const TtsSpeaking('world'))));
    });

    test('TtsStopped equal', () =>
        expect(const TtsStopped(), equals(const TtsStopped())));

    test('TtsPaused equal', () =>
        expect(const TtsPaused(), equals(const TtsPaused())));

    test('TtsError dengan pesan sama equal', () {
      expect(const TtsError('oops'), equals(const TtsError('oops')));
    });

    test('TtsError dengan pesan berbeda tidak equal', () {
      expect(const TtsError('err1'), isNot(equals(const TtsError('err2'))));
    });
  });
}