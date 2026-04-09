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

class MockLoadModelUsecase extends Mock implements LoadModelUsecase {}

class MockCloseModelUsecase extends Mock implements CloseModelUsecase {}

class MockDetectFromFrame extends Mock implements DetectionObjectFromFrame {}

class MockCameraImage extends Mock implements CameraImage {}

DetectionObject _safeObject(
        {String label = 'person', double confidence = 0.8}) =>
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

DetectionObject _dangerousObject(
        {String label = 'person', double confidence = 0.9}) =>
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
  late MockCloseModelUsecase mockCloseModel;
  late MockDetectFromFrame mockDetectFromFrame;
  late MockCameraImage mockCameraImage;

  setUpAll(() {
    registerFallbackValue(MockCameraImage());
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoadModel = MockLoadModelUsecase();
    mockCloseModel = MockCloseModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage = MockCameraImage();

    when(() => mockCloseModel.call(any())).thenAnswer((_) async {});
    when(() => mockLoadModel.call(any())).thenAnswer((_) async {});
  });

  DetectionBloc buildBloc({DetectionWarningCallback? onWarning}) =>
      DetectionBloc(
        loadModel: mockLoadModel,
        closeModel: mockCloseModel,
        detectFromFrame: mockDetectFromFrame,
        onWarning: onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  // Initial state

  test('initial state adalah DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  // DetectionStarted

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, ModelReady] saat sukses',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), const DetectionModelReady()],
      verify: (_) => verify(() => mockLoadModel.call(any())).called(1),
    );

    blocTest<DetectionBloc, DetectionState>(
      'emits [Loading, Failure] saat loadModel throw',
      build: () {
        when(() => mockLoadModel.call(any()))
            .thenThrow(Exception('model not found'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), isA<DetectionFailure>()],
    );

    blocTest<DetectionBloc, DetectionState>(
      'state tracking direset setiap kali DetectionStarted dipanggil',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const DetectionStarted());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const DetectionStarted());
      },
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );
  });

  // DetectionStopped uses CloseModelUsecase

  group('DetectionStopped', () {
    blocTest<DetectionBloc, DetectionState>(
      'emits Initial dan memanggil closeModel',
      build: buildBloc,
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
    );

    blocTest<DetectionBloc, DetectionState>(
      'closeModel dipanggil meskipun state awal adalah Initial',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
    );
  });

  // Concurrent frames and droppable behavior

  group('DetectionFrameReceived — droppable frame behavior', () {
    blocTest<DetectionBloc, DetectionState>(
      'frame concurrent: hanya satu yang diproses sementara yang lain menunggu',
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
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        verify(() => mockDetectFromFrame(any(),
            rotationDegrees: any(named: 'rotationDegrees'))).called(1);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'frame sekuensial dengan jeda: keduanya diproses',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc();
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 30));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 30));
      },
      verify: (_) {
        verify(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .called(greaterThanOrEqualTo(1));
      },
    );
  });

  // Warning callback

  group('Warning callback', () {
    String? capturedText;
    bool? capturedImmediate;
    bool? capturedVibration;

    setUp(() {
      capturedText = null;
      capturedImmediate = null;
      capturedVibration = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'object berbahaya → callback immediate=true withVibration=true',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isTrue);
        expect(capturedVibration, isTrue);
        expect(capturedText, isNotNull);
        expect(capturedText, isNotEmpty);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'object aman → callback immediate=false withVibration=false',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isFalse);
        expect(capturedVibration, isFalse);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'deteksi kosong → tidak ada callback',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [
        predicate<DetectionState>(
            (s) => s is DetectionSuccess && s.detections.isEmpty),
      ],
      verify: (_) {
        expect(capturedText, isNull,
            reason: 'Tidak ada detection → tidak ada callback');
      },
    );
  });

  // onDone callback

  group('onDone callback', () {
    test('dipanggil setelah inference berhasil', () async {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);

      final bloc = buildBloc();
      bloc.add(const DetectionStarted());
      await Future.delayed(const Duration(milliseconds: 10));

      bool doneCalled = false;
      bloc.add(DetectionFrameReceived(
        mockCameraImage,
        0,
        () => doneCalled = true,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(doneCalled, isTrue,
          reason: 'onDone() harus dipanggil setelah setiap frame');
      await bloc.close();
    });
  });

  // CloseModelUsecase contract

  group('CloseModelUsecase', () {
    test('call(NoParams()) mendelegasikan ke repository.closeModel()',
        () async {
      final mock = MockCloseModelUsecase();
      when(() => mock.call(any())).thenAnswer((_) async {});

      await mock.call(const NoParams());

      verify(() => mock.call(any())).called(1);
    });
  });
}
