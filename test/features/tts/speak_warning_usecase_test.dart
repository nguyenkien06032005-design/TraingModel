import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/speak_warning_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_bloc.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_event.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_state.dart';

// ── Mock ──────────────────────────────────────────────────────────────────

class MockTtsRepository extends Mock implements TtsRepository {}

void main() {
  late MockTtsRepository mockRepo;

  setUp(() {
    mockRepo = MockTtsRepository();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SpeakWarningUsecase
  // ══════════════════════════════════════════════════════════════════════════

  group('SpeakWarningUsecase', () {
    late SpeakWarningUsecase usecase;

    setUp(() {
      usecase = SpeakWarningUsecase(mockRepo);
    });

    // .call(text) → repository.speakWarning(text)
    test('call() delegates to repository.speakWarning()', () async {
      const text = 'Phát hiện người đi bộ phía trước, gần';
      when(() => mockRepo.speakWarning(text)).thenAnswer((_) async {});

      await usecase(text);

      verify(() => mockRepo.speakWarning(text)).called(1);
    });

    // .immediate(text) → repository.speakImmediate(text)
    test('immediate() delegates to repository.speakImmediate()', () async {
      const text = 'Cảnh báo! Người đi bộ rất gần';
      when(() => mockRepo.speakImmediate(text)).thenAnswer((_) async {});

      await usecase.immediate(text);

      verify(() => mockRepo.speakImmediate(text)).called(1);
    });

    // .call() does NOT call speakImmediate
    test('call() does not trigger speakImmediate', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async {});

      await usecase('test');

      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    // .immediate() does NOT call speakWarning
    test('immediate() does not trigger speakWarning', () async {
      when(() => mockRepo.speakImmediate(any())).thenAnswer((_) async {});

      await usecase.immediate('test');

      verifyNever(() => mockRepo.speakWarning(any()));
    });

    // Exact text is passed through without modification
    test('passes exact text to repository', () async {
      const exactText = 'Phát hiện xe đạp bên trái, trung bình';
      when(() => mockRepo.speakWarning(exactText)).thenAnswer((_) async {});

      await usecase(exactText);

      verify(() => mockRepo.speakWarning(exactText)).called(1);
    });

    // Exception from repository propagates to caller
    test('call() propagates repository exception', () async {
      when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase('text'), throwsException);
    });

    test('immediate() propagates repository exception', () async {
      when(() => mockRepo.speakImmediate(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase.immediate('text'), throwsException);
    });

    // Empty string is forwarded as-is (no filtering at usecase level)
    test('forwards empty string to repository', () async {
      when(() => mockRepo.speakWarning('')).thenAnswer((_) async {});

      await usecase('');

      verify(() => mockRepo.speakWarning('')).called(1);
    });

    // Multiple calls are each forwarded individually
    test('multiple calls each delegate separately', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async {});

      await usecase('first');
      await usecase('second');
      await usecase('third');

      verify(() => mockRepo.speakWarning(any())).called(3);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // StopSpeakingUsecase
  // ══════════════════════════════════════════════════════════════════════════

  group('StopSpeakingUsecase', () {
    late StopSpeakingUsecase usecase;

    setUp(() {
      usecase = StopSpeakingUsecase(mockRepo);
    });

    // .call() → repository.stop()
    test('call() delegates to repository.stop()', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.stop()).called(1);
    });

    // Does not call speakWarning or speakImmediate
    test('does not call speak methods', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verifyNever(() => mockRepo.speakWarning(any()));
      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    // Exception propagates
    test('propagates repository exception', () async {
      when(() => mockRepo.stop()).thenThrow(Exception('stop failed'));

      expect(() => usecase(), throwsException);
    });

    // Multiple stop calls are each forwarded
    test('multiple stop calls are each delegated', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();
      await usecase();

      verify(() => mockRepo.stop()).called(2);
    });
  });

  group('PauseSpeakingUsecase', () {
    late PauseSpeakingUsecase usecase;

    setUp(() {
      usecase = PauseSpeakingUsecase(mockRepo);
    });

    test('call() delegates to repository.pause()', () async {
      when(() => mockRepo.pause()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.pause()).called(1);
    });

    test('propagates repository exception', () async {
      when(() => mockRepo.pause()).thenThrow(Exception('pause failed'));

      expect(() => usecase(), throwsException);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TtsBloc — state machine
  // ══════════════════════════════════════════════════════════════════════════

  group('TtsBloc', () {
    late SpeakWarningUsecase speakWarningUsecase;
    late StopSpeakingUsecase stopSpeakingUsecase;
    late PauseSpeakingUsecase pauseSpeakingUsecase;

    setUp(() {
      speakWarningUsecase = SpeakWarningUsecase(mockRepo);
      stopSpeakingUsecase = StopSpeakingUsecase(mockRepo);
      pauseSpeakingUsecase = PauseSpeakingUsecase(mockRepo);
    });

    TtsBloc buildBloc() => TtsBloc(
          speakWarning: speakWarningUsecase,
          stopSpeaking: stopSpeakingUsecase,
          pauseSpeaking: pauseSpeakingUsecase,
        );

    // ── Initial state ──────────────────────────────────────────────────────

    test('initial state is TtsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const TtsInitial());
      bloc.close();
    });

    // ── TtsSpeak (regular, no vibration) ──────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak (regular) → calls speakWarning and emits TtsSpeaking',
      setUp: () {
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak(
        'Phát hiện người đi bộ phía trước',
      )),
      expect: () => [
        const TtsSpeaking('Phát hiện người đi bộ phía trước'),
      ],
      verify: (_) {
        verify(() => mockRepo.speakWarning(
          'Phát hiện người đi bộ phía trước',
        )).called(1);
      },
    );

    // ── TtsSpeak immediate ─────────────────────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak(immediate:true) → calls speakImmediate and emits TtsSpeaking',
      setUp: () {
        when(() => mockRepo.speakImmediate(any())).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak(
        'Cảnh báo! Rất gần',
        immediate: true,
        withVibration: false, // vibration tested separately
      )),
      expect: () => [const TtsSpeaking('Cảnh báo! Rất gần')],
      verify: (_) {
        verify(() => mockRepo.speakImmediate('Cảnh báo! Rất gần')).called(1);
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    // ── TtsStop ────────────────────────────────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'TtsStop → calls repository.stop() and emits TtsStopped',
      setUp: () {
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsStop()),
      expect: () => [const TtsStopped()],
      verify: (_) {
        verify(() => mockRepo.stop()).called(1);
      },
    );

    // ── TtsPause ──────────────────────────────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'TtsPause → calls repository.pause() and emits TtsPaused',
      setUp: () {
        when(() => mockRepo.pause()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsPause()),
      expect: () => [const TtsPaused()],
      verify: (_) {
        verify(() => mockRepo.pause()).called(1);
        verifyNever(() => mockRepo.stop());
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    // ── Error handling ─────────────────────────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak emits TtsError when speakWarning throws',
      setUp: () {
        when(() => mockRepo.speakWarning(any()))
            .thenThrow(Exception('engine crashed'));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [isA<TtsError>()],
    );

    blocTest<TtsBloc, TtsState>(
      'TtsError contains error message',
      setUp: () {
        when(() => mockRepo.speakWarning(any()))
            .thenThrow(Exception('engine crashed'));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [
        predicate<TtsState>(
          (s) => s is TtsError && s.message.contains('engine crashed'),
          'TtsError with engine crashed',
        ),
      ],
    );

    // ── Sequence: speak then stop ──────────────────────────────────────────

    blocTest<TtsBloc, TtsState>(
      'speak then stop → [TtsSpeaking, TtsStopped]',
      setUp: () {
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async {});
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TtsSpeak('hello'));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TtsStop());
      },
      expect: () => [
        const TtsSpeaking('hello'),
        const TtsStopped(),
      ],
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TtsEvent equality (Equatable)
  // ══════════════════════════════════════════════════════════════════════════

  group('TtsEvent equality', () {
    test('TtsSpeak with same params are equal', () {
      const a = TtsSpeak('hello', immediate: true, withVibration: true);
      const b = TtsSpeak('hello', immediate: true, withVibration: true);
      expect(a, equals(b));
    });

    test('TtsSpeak with different text are not equal', () {
      const a = TtsSpeak('hello');
      const b = TtsSpeak('world');
      expect(a, isNot(equals(b)));
    });

    test('TtsSpeak with different immediate flag are not equal', () {
      const a = TtsSpeak('hello', immediate: true);
      const b = TtsSpeak('hello', immediate: false);
      expect(a, isNot(equals(b)));
    });

    test('TtsStop equals TtsStop', () {
      expect(const TtsStop(), equals(const TtsStop()));
    });

    test('TtsPause equals TtsPause', () {
      expect(const TtsPause(), equals(const TtsPause()));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TtsState equality (Equatable)
  // ══════════════════════════════════════════════════════════════════════════

  group('TtsState equality', () {
    test('TtsInitial equals TtsInitial', () {
      expect(const TtsInitial(), equals(const TtsInitial()));
    });

    test('TtsSpeaking with same text are equal', () {
      const a = TtsSpeaking('text');
      const b = TtsSpeaking('text');
      expect(a, equals(b));
    });

    test('TtsSpeaking with different text are not equal', () {
      const a = TtsSpeaking('hello');
      const b = TtsSpeaking('world');
      expect(a, isNot(equals(b)));
    });

    test('TtsStopped equals TtsStopped', () {
      expect(const TtsStopped(), equals(const TtsStopped()));
    });

    test('TtsPaused equals TtsPaused', () {
      expect(const TtsPaused(), equals(const TtsPaused()));
    });

    test('TtsError with same message are equal', () {
      const a = TtsError('oops');
      const b = TtsError('oops');
      expect(a, equals(b));
    });

    test('TtsError with different messages are not equal', () {
      const a = TtsError('err1');
      const b = TtsError('err2');
      expect(a, isNot(equals(b)));
    });
  });
}
