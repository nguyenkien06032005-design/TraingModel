import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import 'detection_event.dart';
import 'detection_state.dart';

/// Callback injected from the outside so this BLoC stays decoupled from
/// [TtsBloc]. Communication happens through the callback rather than by
/// holding a direct reference.
typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

/// Coordinates the detection lifecycle: loading the model, processing camera
/// frames, emitting TTS warnings, and tracking approaching motion.
///
/// Frame locking is handled entirely by [CameraService] through
/// [DetectionFrameReceived.onDone]. This BLoC does not guard concurrent frames
/// on its own, so [onDone] must always be called from a `finally` block.
///
/// Warnings are emitted when:
/// - An object appears continuously for at least 3 frames.
/// - The bounding-box area grows by more than 30% compared to the previous
///   frame, which signals an approaching object.
class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;

  /// Stores previous-frame bounding-box areas by label so approaching objects
  /// can be detected from fast area growth.
  Map<String, List<double>> _previousObjects = {};

  /// Counts consecutive frames for each object instance.
  /// Used to debounce warnings so they trigger only after 3 stable frames.
  Map<String, int> _consecutiveFrames = {};

  DetectionBloc({
    required LoadModelUsecase loadModel,
    required CloseModelUsecase closeModel,
    required DetectionObjectFromFrame detectFromFrame,
    required DetectionWarningCallback onWarning,
  })  : _loadModel = loadModel,
        _closeModel = closeModel,
        _detectFromFrame = detectFromFrame,
        _onWarning = onWarning,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    _previousObjects = {};
    _consecutiveFrames = {};
    if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.call(const NoParams());
      if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  void _onStopped(DetectionStopped event, Emitter<DetectionState> emit) {
    _previousObjects.clear();
    _consecutiveFrames.clear();
    emit(const DetectionInitial());
    // Release the isolate interpreter as fire-and-forget because the BLoC has
    // already transitioned back to the initial state.
    unawaited(_closeModel.call(const NoParams()));
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // [event.onDone] must be called in finally so CameraService can release
    // the frame lock and accept the next frame.
    try {
      final detections = await _detectFromFrame(
        event.image,
        rotationDegrees: event.rotationDegrees,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[DetectionBloc] inference timeout — skipping frame');
          }
          return [];
        },
      );

      if (kDebugMode && detections.isNotEmpty) {
        debugPrint('[DetectionBloc] detections=${detections.length}');
      }

      emit(DetectionSuccess(
        detections: detections,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ));

      if (detections.isEmpty) return;

      _triggerWarningIfNeeded(detections);
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      event.onDone();
    }
  }

  /// Decides whether a TTS warning should be emitted based on two criteria:
  /// 1. A newly seen object stays stable for at least 3 consecutive frames.
  /// 2. An existing object appears to be approaching because its area grows by
  ///    more than 30% compared with the previous frame.
  ///
  /// Dangerous objects are spoken immediately with vibration, while normal
  /// objects are queued through TTS.
  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);
    final sortedDetections = [...detections]..sort((a, b) {
        final labelCompare = a.label.compareTo(b.label);
        if (labelCompare != 0) return labelCompare;
        return b.boundingBox.area.compareTo(a.boundingBox.area);
      });

    final candidates = <DetectionObject>[];
    final currentIndices = <String, int>{};
    final newConsecutive = <String, int>{};

    for (final d in sortedDetections) {
      final currentIndex = currentIndices.update(
        d.label,
        (value) => value + 1,
        ifAbsent: () => 0,
      );

      final presenceKey = '${d.label}_$currentIndex';
      final prevCount = _consecutiveFrames[presenceKey] ?? 0;
      final currentCount = prevCount + 1;
      newConsecutive[presenceKey] = currentCount;

      final previousAreas = _previousObjects[d.label];
      final oldArea =
          previousAreas != null && currentIndex < previousAreas.length
              ? previousAreas[currentIndex]
              : null;

      final isApproaching =
          oldArea != null && d.boundingBox.area > oldArea * 1.3;
      final isStable = currentCount == 3;
      final isFirstSeen = currentCount == 1;

      if (isApproaching || isStable || isFirstSeen) candidates.add(d);
    }

    _previousObjects = currentObjects;
    _consecutiveFrames = newConsecutive;

    if (candidates.isEmpty) return;

    final dangerous = candidates.where((d) => d.isDangerous).toList()
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

    if (dangerous.isNotEmpty) {
      _onWarning(
        text: dangerous.first.voiceWarning,
        immediate: true,
        withVibration: true,
      );
    } else {
      final top = candidates.reduce(
        (a, b) => a.confidence > b.confidence ? a : b,
      );
      _onWarning(
        text: top.voiceWarning,
        immediate: false,
        withVibration: false,
      );
    }
  }

  /// Groups bounding-box areas by label and sorts them in descending order.
  /// This makes it possible to compare the current frame against the previous
  /// one to detect approaching motion.
  Map<String, List<double>> _groupAreasByLabel(
    List<DetectionObject> detections,
  ) {
    final grouped = <String, List<double>>{};
    for (final detection in detections) {
      grouped
          .putIfAbsent(detection.label, () => <double>[])
          .add(detection.boundingBox.area);
    }
    for (final areas in grouped.values) {
      areas.sort((a, b) => b.compareTo(a));
    }
    return grouped;
  }
}
