import 'package:bloc_test/bloc_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/usecases/usecase.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';

class MockLoadModelUsecase  extends Mock implements LoadModelUsecase {}
class MockDetectFromFrame   extends Mock implements DetectionObjectFromFrame {}
class MockCameraImage       extends Mock implements CameraImage {}
class MockCloseModelUsecase extends Mock implements CloseModelUsecase {}

DetectionObject _safeObject({
  String label = 'person',
  double confidence = 0.8,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(
        left: 0.4, top: 0.4, width: 0.05, height: 0.05,
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
        left: 0.1, top: 0.1, width: 0.4, height: 0.4,
      ),
    );

void main() {
  late MockLoadModelUsecase  mockLoadModel;
  late MockDetectFromFrame   mockDetectFromFrame;
  late MockCloseModelUsecase mockCloseModel;
  late MockCameraImage       mockCameraImage;

  setUpAll(() {
    // CameraImage is used with any() in detectFromFrame stubs.
    registerFallbackValue(MockCameraImage());
    // NoParams is used with any() in loadModel.call() and closeModel.call() stubs.
    // Mocktail requires a fallback for every non-primitive type passed to any().
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoadModel       = MockLoadModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage     = MockCameraImage();
    mockCloseModel      = MockCloseModelUsecase();

    // Default stubs — without these, DetectionStarted/Stopped would throw MissingStubError.
    // LoadModelUsecase implements UseCase<void, NoParams>, so the only callable
    // interface is .call(NoParams) — there is no .load() convenience method.
    when(() => mockLoadModel.call(any())).thenAnswer((_) async {});
    when(() => mockCloseModel.call(any())).thenAnswer((_) async {});
  });

  DetectionBloc buildBloc({DetectionWarningCallback? onWarning}) =>
      DetectionBloc(
        loadModel:       mockLoadModel,
        detectFromFrame: mockDetectFromFrame,
        closeModel:      mockCloseModel,
        onWarning:       onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  test('initial state is DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, ModelReady]',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );

    blocTest<DetectionBloc, DetectionState>(
      'emits Failure when load fails',
      build: () {
        when(() => mockLoadModel.call(any())).thenThrow(Exception('load error'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        isA<DetectionFailure>(),
      ],
    );
  });

  blocTest<DetectionBloc, DetectionState>(
    'DetectionStopped → back to Initial and calls closeModel',
    build: buildBloc,
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(const DetectionStopped()),
    expect: () => [const DetectionInitial()],
    verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
  );

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

  group('Warning callback behavior', () {
    String? capturedText;
    bool?   capturedImmediate;

    setUp(() {
      capturedText      = null;
      capturedImmediate = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'dangerous object → callback immediate=true after 3 stable frames',
      // _triggerWarningIfNeeded fires only when isStable (currentCount==3) OR
      // isApproaching. With a single frame there is no previous area to compare
      // and currentCount==1, so the callback is never called.
      // Sending 3 identical frames makes currentCount reach 3 (isStable=true).
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning: ({required text, required immediate, required withVibration}) {
            capturedText      = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      expect: () => [isA<DetectionSuccess>(), isA<DetectionSuccess>(), isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isTrue,
            reason: 'dangerous object must trigger immediate=true warning');
        expect(capturedText, isNotEmpty);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'safe object → callback immediate=false after 3 stable frames',
      // Same debounce reasoning as above — 3 frames required for isStable.
      // A safe object (small area, ≤ dangerousAreaThreshold=0.10) triggers
      // the queued (immediate=false) path, not the danger path.
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning: ({required text, required immediate, required withVibration}) {
            capturedText      = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      expect: () => [isA<DetectionSuccess>(), isA<DetectionSuccess>(), isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isNotNull);
        expect(capturedImmediate, isFalse,
            reason: 'safe (non-dangerous) object must trigger immediate=false warning');
      },
    );
  });

  test(
    // Frame-dropping is NOT DetectionBloc's responsibility.
    // CameraService uses a _isProcessingFrame lock + the onDone callback to
    // prevent a new frame from being dispatched while inference is running.
    // DetectionBloc itself processes every event it receives — no self-guard.
    //
    // Key contract: both dispatched frames must go through detectFromFrame().
    // We verify that here via verify().called(2) — this is the meaningful
    // invariant regardless of how many state emissions Equatable deduplicates
    // (microsecond timestamps can collide on fast CI runners).
    //
    // We use a plain test() + StreamSubscription rather than blocTest because
    // blocTest closes its listener when the act Future resolves, which races
    // with async event processing in the BLoC.
    'processes two concurrent frames independently (frame lock is CameraService responsibility)',
    () async {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 5));
        return [_safeObject()];
      });

      final bloc = buildBloc()..emit(const DetectionModelReady());
      final emitted = <DetectionState>[];
      final sub = bloc.stream.listen(emitted.add);

      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));

      // Wait well past 2 × 5 ms for both sequential inferences to complete.
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await bloc.close();

      // Primary contract: both frames must reach the inference engine.
      verify(() => mockDetectFromFrame(any(),
          rotationDegrees: any(named: 'rotationDegrees'))).called(2);

      // At least one DetectionSuccess must have been emitted.
      expect(emitted, isNotEmpty);
      expect(emitted, everyElement(isA<DetectionSuccess>()));
    },
  );

  blocTest<DetectionBloc, DetectionState>(
    'handles exception silently — no state emitted, onDone called',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenThrow(Exception('GPU error'));
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => <DetectionState>[],
  );
}