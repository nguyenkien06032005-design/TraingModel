import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../../../core/utils/perf_monitor.dart';
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

  /// Reusable sort buffer — avoids a heap allocation on every frame.
  ///
  /// [_triggerWarningIfNeeded] needs a sorted copy of the detection list to
  /// process objects in a stable label order. Previously this was done with
  /// `[...detections]..sort(...)`, which allocates a new [List] on every call
  /// (up to 6 times per second at the target frame rate). Reusing this buffer
  /// eliminates that per-frame GC pressure while keeping the sort result local
  /// to the method.
  ///
  /// Lifecycle: cleared on [_onStarted], [_onStopped], and [close].
  final List<DetectionObject> _sortBuffer = [];

  /// Tracks the in-flight [CloseModelUsecase] future so [_onStarted] can
  /// await it before loading a new model.  Because each `on<>` registration
  /// has its own event stream, awaiting close inside [_onStopped] alone is not
  /// enough — a concurrent [DetectionStarted] would bypass it.
  Future<void>? _closeFuture;

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
    // Wait for any in-flight close to finish before loading a new model.
    // This prevents the race where a rapid Stop→Start sequence calls
    // loadModel while the previous interpreter is still being released.
    if (_closeFuture != null) {
      await _closeFuture;
      _closeFuture = null;
    }
    _previousObjects = {};
    _consecutiveFrames = {};
    _sortBuffer.clear();
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

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    _previousObjects.clear();
    _consecutiveFrames.clear();
    _sortBuffer.clear();
    emit(const DetectionInitial());
    // Store the close future so that a concurrent _onStarted can await it.
    _closeFuture = _closeModel.call(const NoParams());
    await _closeFuture;
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // [event.onDone] must be called in finally so CameraService can release
    // the frame lock and accept the next frame.

    // Stopwatch is only allocated in debug builds. The kDebugMode constant is
    // evaluated at compile time, so the release build eliminates this branch
    // entirely — zero overhead in production.
    final sw = kDebugMode ? (Stopwatch()..start()) : null;

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

      if (kDebugMode) {
        sw?.stop();
        // Record how long the full inference round-trip took (frame dispatch →
        // isolate → NMS → result), then mark this frame as successfully
        // processed so PerfMonitor can compute rolling FPS and avg latency.
        PerfMonitor.inferenceCompleted(sw?.elapsedMilliseconds ?? 0);
        PerfMonitor.frameReceived();
        if (detections.isNotEmpty) {
          debugPrint('[DetectionBloc] detections=${detections.length}');
        }
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
  ///
  /// Uses [_sortBuffer] instead of a spread copy to avoid per-frame heap
  /// allocation. The buffer is cleared and repopulated on each call, so its
  /// contents are never stale across frames.
  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);

    // Reuse _sortBuffer: clear → addAll → sort.
    // This is equivalent to `[...detections]..sort(...)` but reuses the
    // backing array instead of allocating a new List on every frame.
    _sortBuffer
      ..clear()
      ..addAll(detections)
      ..sort((a, b) {
        final labelCompare = a.label.compareTo(b.label);
        if (labelCompare != 0) return labelCompare;
        return b.boundingBox.area.compareTo(a.boundingBox.area);
      });

    final candidates = <DetectionObject>[];
    final currentIndices = <String, int>{};
    final newConsecutive = <String, int>{};

    for (final d in _sortBuffer) {
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

  @override
  Future<void> close() async {
    _sortBuffer.clear();
    return super.close();
  }
}
