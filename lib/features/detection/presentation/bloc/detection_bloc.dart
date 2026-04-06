// file: lib/features/detection/presentation/bloc/detection_bloc.dart
// Bug 5 FIX:  Xoá _lastSpoken — TtsService owns cooldown (AppConstants.ttsCooldownMs)
// Bug 10 FIX: DetectionWarningCallback thay vì TtsBloc reference
// Bug 18 FIX: Xoá droppable() transformer — redundant + deadlock risk
// Bug 20 FIX: Reset _previousObjects trong _onStarted

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import 'detection_event.dart';
import 'detection_state.dart';

// Bug 10 FIX: Typedef callback — DetectionBloc không import bất cứ gì từ TTS feature
typedef DetectionWarningCallback = void Function({
  required String text,
  required bool   immediate,
  required bool   withVibration,
});

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase         _loadModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning; // Bug 10 FIX

  // Bug 5 FIX: Xoá _lastSpoken — TtsService.speakWarning() owns cooldown
  Map<String, double> _previousObjects = {};

  // Frame-drop lock: chỉ xử lý 1 frame tại một thời điểm.
  // Khi CameraService bị bypass trong test (frame add trực tiếp),
  // cơ chế này đảm bảo frame thứ 2 bị drop thay vì chạy song song.
  bool _isProcessingFrame = false;

  DetectionBloc({
    required LoadModelUsecase         loadModel,
    required DetectionObjectFromFrame detectFromFrame,
    required DetectionWarningCallback onWarning,
  })  : _loadModel       = loadModel,
        _detectFromFrame = detectFromFrame,
        _onWarning       = onWarning,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived);
    // Bug 18 FIX: Không dùng droppable() — _isProcessingFrame trong CameraService
    // là single frame-drop mechanism. droppable() + _isProcessingFrame tạo
    // deadlock: nếu droppable drop 1 event, onDone() trong finally không chạy
    // → _isProcessingFrame never reset → camera stream đóng băng.
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    // Bug 20 FIX: Reset stale state từ session trước
    // (e.g. reload sau lỗi mà không có DetectionStopped)
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
    // Bug 10 FIX: Không còn _ttsBloc.add(TtsStop()) ở đây
    // Page tự stop TTS trong dispose() — page là orchestrator, không phải bloc
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // Drop frame nếu đang xử lý frame trước đó
    if (_isProcessingFrame) {
      event.onDone();
      return;
    }
    _isProcessingFrame = true;
    try {
      final detections = await _detectFromFrame(
        event.image,
        rotationDegrees: event.rotationDegrees,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) debugPrint('[DetectionBloc] inference timeout — skipping frame');
          return [];
        },
      );

      if (kDebugMode) {
        if (detections.isNotEmpty) {
          debugPrint('[DetectionBloc] detections=${detections.length}');
        }
      }

      emit(DetectionSuccess(
        detections: detections,
        timestamp:  DateTime.now().microsecondsSinceEpoch,
      ));

      if (detections.isEmpty) return;

      // Area-growth filter: chỉ trigger TTS khi object mới xuất hiện
      // hoặc tiến lại gần >30% — giảm TTS spam trong scene tĩnh
      final currentObjects = {
        for (final d in detections) d.label: d.boundingBox.area,
      };

      final candidates = <DetectionObject>[];
      for (final d in detections) {
        final oldArea = _previousObjects[d.label];
        if (oldArea == null || d.boundingBox.area > oldArea * 1.3) {
          candidates.add(d);
        }
      }
      _previousObjects = currentObjects;

      if (candidates.isEmpty) return;

      // Bug 5 FIX: Không có _lastSpoken guard ở đây
      // TtsService.speakWarning() đã có per-text cooldown via AppConstants.ttsCooldownMs
      final dangerous = candidates.where((d) => d.isDangerous).toList()
        ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

      if (dangerous.isNotEmpty) {
        if (kDebugMode) debugPrint('[DetectionBloc] TTS danger: ${dangerous.first.voiceWarning}');
        // Bug 10 FIX: callback thay vì _ttsBloc.add(TtsSpeak(...))
        _onWarning(
          text:          dangerous.first.voiceWarning,
          immediate:     true,
          withVibration: true,
        );
      } else {
        final top = candidates.reduce(
          (a, b) => a.confidence > b.confidence ? a : b,
        );
        if (kDebugMode) debugPrint('[DetectionBloc] TTS: ${top.voiceWarning}');
        _onWarning(
          text:          top.voiceWarning,
          immediate:     false,
          withVibration: false,
        );
      }
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      _isProcessingFrame = false;
      // Luôn release CameraService frame lock kể cả khi có exception
      event.onDone();
    }
  }
}