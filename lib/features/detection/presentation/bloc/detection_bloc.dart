





import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import 'detection_event.dart';
import 'detection_state.dart';


typedef DetectionWarningCallback = void Function({
  required String text,
  required bool   immediate,
  required bool   withVibration,
});

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase         _loadModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning; 

  
  Map<String, List<double>> _previousObjects = {};

  
  
  
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
    
    
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    
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
          d.label,
          (value) => value + 1,
          ifAbsent: () => 0,
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
        if (kDebugMode) debugPrint('[DetectionBloc] TTS danger: ${dangerous.first.voiceWarning}');
        
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
      
      event.onDone();
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
