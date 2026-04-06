import 'package:bloc_test/bloc_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────

class MockLoadModelUsecase extends Mock implements LoadModelUsecase {}

class MockDetectFromFrame extends Mock implements DetectionObjectFromFrame {}

class MockCameraImage extends Mock implements CameraImage {}

// ── Helpers ───────────────────────────────────────────────────────────────

DetectionObject _safeObject({
  String label = 'person',
  double confidence = 0.8,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(
        left: 0.4,
        top: 0.4,
        width: 0.05,
        height: 0.05,
      ),
    );

DetectionObject _dangerousObject({
  String label = 'person',
  double confidence = 0.9,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(
        left: 0.1,
        top: 0.1,
        width: 0.4,
        height: 0.4,
      ),
    );

void main() {
  late MockLoadModelUsecase mockLoadModel;
  late MockDetectFromFrame mockDetectFromFrame;
  late MockCameraImage mockCameraImage;

  setUpAll(() {
    registerFallbackValue(MockCameraImage());
  });

  setUp(() {
    mockLoadModel = MockLoadModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage = MockCameraImage();
  });

  // ✅ NEW buildBloc (callback-based)
  DetectionBloc buildBloc({
    DetectionWarningCallback? onWarning,
  }) =>
      DetectionBloc(
        loadModel: mockLoadModel,
        detectFromFrame: mockDetectFromFrame,
        onWarning: onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  // ══════════════════════════════════════════════════════════════════════════
  // Initial state
  // ══════════════════════════════════════════════════════════════════════════

  test('initial state is DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DetectionStarted
  // ══════════════════════════════════════════════════════════════════════════

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, ModelReady]',
      build: () {
        when(() => mockLoadModel.load()).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );

    blocTest<DetectionBloc, DetectionState>(
      'emits Failure when load fails',
      build: () {
        when(() => mockLoadModel.load())
            .thenThrow(Exception('load error'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        isA<DetectionFailure>(),
      ],
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DetectionStopped
  // ══════════════════════════════════════════════════════════════════════════

  blocTest<DetectionBloc, DetectionState>(
    'DetectionStopped → back to Initial',
    build: () => buildBloc(),
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(const DetectionStopped()),
    expect: () => [const DetectionInitial()],
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Frame: empty detections
  // ══════════════════════════════════════════════════════════════════════════

  blocTest<DetectionBloc, DetectionState>(
    'empty detections → success with empty list',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) =>
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => [
      predicate<DetectionState>(
        (s) => s is DetectionSuccess && s.detections.isEmpty,
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Frame: with detections
  // ══════════════════════════════════════════════════════════════════════════

  blocTest<DetectionBloc, DetectionState>(
    'single detection',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => [_safeObject()]);
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) =>
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => [isA<DetectionSuccess>()],
  );

  // ══════════════════════════════════════════════════════════════════════════
  // 🔥 Callback behavior (THAY cho TTS test)
  // ══════════════════════════════════════════════════════════════════════════

  // P3-Fix7: Dùng nullable thay vì late — tránh LateInitializationError giòn
  // nếu callback không được gọi (test failure rõ ràng hơn là LateError).
  // setUp() reset về null trước mỗi test trong group, loại bỏ phụ thuộc
  // trạng thái giữa 2 blocTest.
  group('Callback behavior', () {
    String? capturedText;
    bool? capturedImmediate;

    setUp(() {
      capturedText      = null;
      capturedImmediate = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'dangerous object → callback immediate=true',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning:
              ({required text, required immediate, required withVibration}) {
            capturedText      = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isTrue,  reason: 'dangerous object phải trigger immediate TTS');
        expect(capturedText,      isNotEmpty, reason: 'warning text không được rỗng');
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'safe object → callback immediate=false',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning:
              ({required text, required immediate, required withVibration}) {
            capturedText      = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        // P3-Fix7: verify callback được gọi (capturedImmediate != null)
        // trước khi check giá trị — fail rõ ràng nếu callback im lặng
        expect(capturedImmediate, isNotNull,
            reason: 'callback phải được gọi với safe object');
        expect(capturedImmediate, isFalse,
            reason: 'safe object không được trigger immediate TTS');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Processing lock
  // ══════════════════════════════════════════════════════════════════════════

  blocTest<DetectionBloc, DetectionState>(
    'drops second frame while processing',
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
      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
      await Future.delayed(const Duration(milliseconds: 100));
    },
    expect: () => [isA<DetectionSuccess>()],
    verify: (_) {
      verify(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .called(1);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Error handling
  // ══════════════════════════════════════════════════════════════════════════

  blocTest<DetectionBloc, DetectionState>(
    'handles exception silently',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenThrow(Exception('GPU error'));
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) =>
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => <DetectionState>[],
  );
}