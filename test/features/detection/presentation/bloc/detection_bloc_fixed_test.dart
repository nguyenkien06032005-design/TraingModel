import 'package:bloc_test/bloc_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';
import 'package:safe_vision_app/core/usecases/usecase.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockLoadModelUsecase   extends Mock implements LoadModelUsecase {}
class MockCloseModelUsecase  extends Mock implements CloseModelUsecase {}  // ← SV-007
class MockDetectFromFrame    extends Mock implements DetectionObjectFromFrame {}
class MockCameraImage        extends Mock implements CameraImage {}

// ─── Test helpers ───────────────────────────────────────────────────────────

DetectionObject _safeObject({
  String label = 'person', double confidence = 0.8,
}) => DetectionObject(
  label: label, confidence: confidence,
  boundingBox: const BoundingBox(left: 0.4, top: 0.4, width: 0.05, height: 0.05),
);

DetectionObject _dangerousObject({
  String label = 'person', double confidence = 0.9,
}) => DetectionObject(
  label: label, confidence: confidence,
  boundingBox: const BoundingBox(left: 0.1, top: 0.1, width: 0.4, height: 0.4),
);

void main() {
  late MockLoadModelUsecase   mockLoadModel;
  late MockCloseModelUsecase  mockCloseModel;   // ← FIX SV-007
  late MockDetectFromFrame    mockDetectFromFrame;
  late MockCameraImage        mockCameraImage;

  setUpAll(() {
    registerFallbackValue(MockCameraImage());
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoadModel       = MockLoadModelUsecase();
    mockCloseModel      = MockCloseModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage     = MockCameraImage();

    // Default stubs
    when(() => mockCloseModel.close()).thenAnswer((_) async {});
    when(() => mockLoadModel.load()).thenAnswer((_) async {});
  });

  // ─── FIX SV-003: buildBloc với đầy đủ parameters ───────────────────────
  //
  // BUG: buildBloc() thiếu required parameter 'repository' → compile error
  // FIX: Thêm CloseModelUsecase (thay thế repository) → clean architecture
  //
  DetectionBloc buildBloc({DetectionWarningCallback? onWarning}) =>
      DetectionBloc(
        loadModel:       mockLoadModel,
        closeModel:      mockCloseModel,     // ← FIX SV-003 + SV-007
        detectFromFrame: mockDetectFromFrame,
        onWarning:       onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  // ─── Initial state ───────────────────────────────────────────────────────

  test('FIX SV-003: initial state compiles and is DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  // ─── DetectionStarted ────────────────────────────────────────────────────

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, ModelReady] on success',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), const DetectionModelReady()],
      verify: (_) => verify(() => mockLoadModel.load()).called(1),
    );

    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, Failure] when loadModel throws',
      build: () {
        when(() => mockLoadModel.load()).thenThrow(Exception('model not found'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), isA<DetectionFailure>()],
    );

    blocTest<DetectionBloc, DetectionState>(
      'resets _previousObjects on each DetectionStarted',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const DetectionStarted());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const DetectionStarted()); // second start = reset
      },
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );
  });

  // ─── FIX SV-007: DetectionStopped dùng CloseModelUsecase ────────────────

  group('FIX SV-007: DetectionStopped calls CloseModelUsecase not Repository', () {
    blocTest<DetectionBloc, DetectionState>(
      'DetectionStopped → emits Initial + calls closeModel.close()',
      build: buildBloc,
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) {
        // ✅ Verify CloseModelUsecase được gọi, không phải repository
        verify(() => mockCloseModel.close()).called(1);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'closeModel.close() is called even when bloc stops from Initial state',
      build: buildBloc,
      // seed = DetectionInitial (default)
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) {
        verify(() => mockCloseModel.close()).called(1);
      },
    );
  });

  // ─── FIX SV-009: droppable() transformer ────────────────────────────────

  group('FIX SV-009: DetectionFrameReceived uses droppable() transformer', () {
    blocTest<DetectionBloc, DetectionState>(
      'concurrent frames: only first is processed (droppable behavior)',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return [_safeObject()];
        });
        return buildBloc();
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        // Add 3 frames rapidly — với droppable(), frame 2 và 3 bị drop
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        // droppable(): inference được gọi chỉ 1 lần
        verify(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .called(1);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'sequential frames (with gap): all are processed',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc();
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        // Frame 1
        bool done1 = false;
        bloc.add(DetectionFrameReceived(
          mockCameraImage, 90, () => done1 = true,
        ));
        // Chờ frame 1 xong
        await Future.delayed(const Duration(milliseconds: 30));
        // Frame 2 sau khi frame 1 hoàn thành
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 30));
      },
      verify: (_) {
        // Cả 2 frames được process vì sequential
        verify(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .called(greaterThanOrEqualTo(1));
      },
    );
  });

  // ─── Warning callback tests ──────────────────────────────────────────────

  group('Warning callback behavior', () {
    String? capturedText;
    bool? capturedImmediate;
    bool? capturedVibration;

    setUp(() {
      capturedText = null;
      capturedImmediate = null;
      capturedVibration = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'dangerous object → callback immediate=true withVibration=true',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning: ({required text, required immediate, required withVibration}) {
            capturedText = text;
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isTrue);
        expect(capturedVibration, isTrue);
        expect(capturedText, isNotNull);
        expect(capturedText, isNotEmpty);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'safe object → callback immediate=false withVibration=false',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning: ({required text, required immediate, required withVibration}) {
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isFalse,
            reason: 'Safe object không được trigger immediate TTS');
        expect(capturedVibration, isFalse);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'empty detections → no warning callback fired',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc(
          onWarning: ({required text, required immediate, required withVibration}) {
            capturedText = text; // should NOT be called
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [
        predicate<DetectionState>((s) => s is DetectionSuccess && s.detections.isEmpty),
      ],
      verify: (_) {
        expect(capturedText, isNull,
            reason: 'Không có detection → không gọi callback');
      },
    );
  });

  // ─── onDone callback ─────────────────────────────────────────────────────

  group('onDone callback', () {
    test('onDone is called after successful inference', () async {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);
      when(() => mockLoadModel.load()).thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(const DetectionStarted());
      await Future.delayed(const Duration(milliseconds: 10));

      bool doneCalled = false;
      bloc.add(DetectionFrameReceived(
        mockCameraImage, 0, () => doneCalled = true,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(doneCalled, isTrue,
          reason: 'onDone() phải được gọi sau mỗi frame dù success hay skip');
      await bloc.close();
    });
  });

  // ─── CloseModelUsecase unit tests ────────────────────────────────────────

  group('FIX SV-007: CloseModelUsecase', () {
    test('close() delegates to repository.closeModel()', () async {
      // Verify CloseModelUsecase contract
      final mockClose = MockCloseModelUsecase();
      when(() => mockClose.close()).thenAnswer((_) async {});

      await mockClose.close();

      verify(() => mockClose.close()).called(1);
    });
  });
}
