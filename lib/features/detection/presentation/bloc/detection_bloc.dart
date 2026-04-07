import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import 'detection_event.dart';
import 'detection_state.dart';

typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

/// FIX SV-007: Bỏ dependency trực tiếp vào DetectionRepository.
///             Dùng CloseModelUsecase thay vì _repository.closeModel().
///
/// FIX SV-009: Dùng droppable() transformer từ bloc_concurrency
///             thay vì manual _isProcessingFrame guard.
///             droppable() tự động drop event mới nếu handler đang chạy —
///             đây chính xác là behavior ta muốn cho frame processing.
class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase         _loadModel;
  final CloseModelUsecase        _closeModel;   // ← FIX SV-007: UseCase, không phải Repository
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;

  // Tracking objects để phát hiện approaching motion
  Map<String, List<double>> _previousObjects = {};

  DetectionBloc({
    required LoadModelUsecase         loadModel,
    required CloseModelUsecase        closeModel,
    required DetectionObjectFromFrame detectFromFrame,
    required DetectionWarningCallback onWarning,
  })  : _loadModel       = loadModel,
        _closeModel      = closeModel,
        _detectFromFrame = detectFromFrame,
        _onWarning       = onWarning,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);

    // ✅ FIX SV-009: droppable() = nếu _onFrameReceived đang xử lý frame N,
    // mọi frame mới đến sẽ bị DROP tự động.
    // Tương đương với manual _isProcessingFrame guard nhưng đúng chuẩn BLoC.
    on<DetectionFrameReceived>(
      _onFrameReceived,
      transformer: droppable(),
    );
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    _previousObjects = {};
    if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.load();
      if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  void _onStopped(DetectionStopped event, Emitter<DetectionState> emit) {
    _previousObjects.clear();
    emit(const DetectionInitial());
    // ✅ FIX SV-007: Gọi qua UseCase, không gọi _repository trực tiếp
    unawaited(_closeModel.close());
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // droppable() đã handle việc skip frames concurrent
    // Không cần manual _isProcessingFrame guard nữa
    try {
      final detections = await _detectFromFrame(
        event.image,
        rotationDegrees: event.rotationDegrees,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode)
            debugPrint('[DetectionBloc] inference timeout — skipping frame');
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

  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);
    final sortedDetections = [...detections]
      ..sort((a, b) {
        final labelCompare = a.label.compareTo(b.label);
        if (labelCompare != 0) return labelCompare;
        return b.boundingBox.area.compareTo(a.boundingBox.area);
      });

    final candidates = <DetectionObject>[];
    final currentIndices = <String, int>{};
    for (final d in sortedDetections) {
      final currentIndex = currentIndices.update(
        d.label, (value) => value + 1, ifAbsent: () => 0,
      );
      final previousAreas = _previousObjects[d.label];
      final oldArea = previousAreas != null && currentIndex < previousAreas.length
          ? previousAreas[currentIndex]
          : null;
      if (oldArea == null || d.boundingBox.area > oldArea * 1.3) {
        candidates.add(d);
      }
    }
    _previousObjects = currentObjects;

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

  Map<String, List<double>> _groupAreasByLabel(
    List<DetectionObject> detections,
  ) {
    final grouped = <String, List<double>>{};
    for (final detection in detections) {
      grouped.putIfAbsent(detection.label, () => <double>[])
          .add(detection.boundingBox.area);
    }
    for (final areas in grouped.values) {
      areas.sort((a, b) => b.compareTo(a));
    }
    return grouped;
  }
}