import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../error/exceptions.dart' as ex;

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;
  int _rotationDegrees = 0;
  int _busyDropCount = 0;
  int _throttleDropCount = 0;

  
  DateTime _lastFrameTime = DateTime.now();
  
  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  
  bool _isProcessingFrame = false;

  
  bool _isInitializing = false;
  bool _isDisposing = false;
  Future<void>? _disposeFuture;
  int _streamGeneration = 0;

  CameraController? get controller  => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming   => _controller?.value.isStreamingImages ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;
  int get sensorOrientation =>
      _cameras.isNotEmpty ? _cameras[_currentIndex].sensorOrientation : 0;
  int get rotationDegrees => _rotationDegrees;

  

  Future<void> initialize({int cameraIndex = 0}) async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) {
      await pendingDispose;
    }
    
    if (_isInitializing) {
      debugPrint('[CameraService] initialize: already in progress, skip');
      return;
    }
    _isInitializing = true;
    try {
      _isDisposing = false;
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw const ex.CameraException('Không tìm thấy camera');
      _currentIndex = cameraIndex.clamp(0, _cameras.length - 1);
      await _setupController(_cameras[_currentIndex]);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    
    
    final old = _controller;
    _streamGeneration++;
    _isProcessingFrame = false;
    _controller = null; 
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose old controller error: $e');
      }
    }

    
    
    
    final bool isFront =
        camera.lensDirection == CameraLensDirection.front;
    _rotationDegrees = isFront
        ? camera.sensorOrientation % 360          
        : (360 - camera.sensorOrientation) % 360; 

    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium, 
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    _controller = ctrl;
    debugPrint(
      '[CameraService] camera ready: ${camera.name} (${camera.lensDirection}) '
      'sensor=${camera.sensorOrientation} rotation=$_rotationDegrees',
    );
  }

  

  void startImageStream({
    required void Function(CameraImage, void Function()) onFrame,
  }) {
    if (_controller == null || !isInitialized || _isDisposing) {
      debugPrint('[CameraService] startImageStream: not ready, skip');
      return;
    }
    final controller = _controller!;
    if (controller.value.isStreamingImages) {
      debugPrint('[CameraService] already streaming');
      return;
    }

    _lastFrameTime = DateTime.now();
    _isProcessingFrame = false;
    _busyDropCount = 0;
    _throttleDropCount = 0;

    final int streamGeneration = ++_streamGeneration;

    unawaited(controller.startImageStream((CameraImage image) {
      if (_isDisposing ||
          _controller != controller ||
          _streamGeneration != streamGeneration) {
        return;
      }
      
      if (_isProcessingFrame) {
        _busyDropCount++;
        if (kDebugMode && _busyDropCount % 30 == 0) {
          debugPrint('[CameraService] dropped $_busyDropCount frames: inference busy');
        }
        return;
      }

      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < _minFrameMs) {
        _throttleDropCount++;
        if (kDebugMode && _throttleDropCount % 30 == 0) {
          debugPrint('[CameraService] dropped $_throttleDropCount frames: fps throttle');
        }
        return;
      }

      _isProcessingFrame = true;
      _lastFrameTime = now;
      
      onFrame(image, () {
        _isProcessingFrame = false; // Tháº£ lock
      });
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('[CameraService] startImageStream error: $error');
    }));

    debugPrint('[CameraService] stream started (~${AppConstants.activeInferenceFps}fps forward)');
  }

  Future<void> stopImageStream() async {
    _streamGeneration++;
    _isProcessingFrame = false;
    final controller = _controller;
    try {
      if (controller?.value.isStreamingImages ?? false) {
        await controller!.stopImageStream();
        debugPrint('[CameraService] stream stopped');
      }
    } catch (e) {
      debugPrint('[CameraService] stopImageStream error: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _currentIndex = (_currentIndex + 1) % _cameras.length;
    await _setupController(_cameras[_currentIndex]);
  }

  
  Future<void> dispose() async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) {
      await pendingDispose;
      return;
    }

    final controller = _controller;
    _controller = null;
    _isDisposing = true;
    _streamGeneration++;
    _isProcessingFrame = false;

    final completer = Completer<void>();
    _disposeFuture = completer.future;
    try {
      try {
        if (controller?.value.isStreamingImages ?? false) {
          await controller!.stopImageStream();
        }
      } catch (e) {
        debugPrint('[CameraService] dispose stop stream error: $e');
      }

      try {
        await controller?.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose controller error: $e');
      }
    } finally {
      _isProcessingFrame = false;
      _isDisposing = false;
      _disposeFuture = null;
      completer.complete();
    }
  }
}
