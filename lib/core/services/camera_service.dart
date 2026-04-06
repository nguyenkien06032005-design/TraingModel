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

  // P2: Control FPS an toàn qua time
  DateTime _lastFrameTime = DateTime.now();
  // Time gap per frame theo `activeInferenceFps`: 1000/4 = 250ms
  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  // Native buffer lock - DROP FRAME ngay tức khắc nếu true
  bool _isProcessingFrame = false;

  // Guard tránh double-init khi lifecycle events chồng nhau
  bool _isInitializing = false;

  CameraController? get controller  => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming   => _controller?.value.isStreamingImages ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;
  int get sensorOrientation =>
      _cameras.isNotEmpty ? _cameras[_currentIndex].sensorOrientation : 0;
  int get rotationDegrees => _rotationDegrees;

  // ── Initialize ─────────────────────────────────────────────────────────────

  Future<void> initialize({int cameraIndex = 0}) async {
    // P0-FIX-1: Guard tránh race condition khi lifecycle gọi initialize() 2 lần
    if (_isInitializing) {
      debugPrint('[CameraService] initialize: already in progress, skip');
      return;
    }
    _isInitializing = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw const ex.CameraException('Không tìm thấy camera');
      _currentIndex = cameraIndex.clamp(0, _cameras.length - 1);
      await _setupController(_cameras[_currentIndex]);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    // Dọn dẹp controller cũ theo đúng thứ tự:
    // stopImageStream → dispose (P1-FIX-4: đúng thứ tự dispose)
    final old = _controller;
    _controller = null; // null trước để callback stream không forward nữa
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose old controller error: $e');
      }
    }

    // FIX: Front camera sensor đã mirror ngang theo phần cứng.
    // Nếu dùng công thức (360 - orientation) cho cả 2 loại camera, frame front
    // bị xoay sai chiều → bounding box lệch. Front cần đảo ngược chiều xoay.
    final bool isFront =
        camera.lensDirection == CameraLensDirection.front;
    _rotationDegrees = isFront
        ? camera.sensorOrientation % 360          // front: thuận chiều sensor
        : (360 - camera.sensorOrientation) % 360; // back: ngược chiều sensor

    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium, // FIX P3: Từ Low -> Medium (720x480) giúp model 640x640 không phải upscale
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

  // ── Stream ─────────────────────────────────────────────────────────────────

  void startImageStream({required void Function(CameraImage, void Function()) onFrame}) {
    if (_controller == null || !isInitialized) {
      debugPrint('[CameraService] startImageStream: not ready, skip');
      return;
    }
    if (_controller!.value.isStreamingImages) {
      debugPrint('[CameraService] already streaming');
      return;
    }

    _lastFrameTime = DateTime.now();
    _isProcessingFrame = false;
    _busyDropCount = 0;
    _throttleDropCount = 0;

    _controller!.startImageStream((CameraImage image) {
      // 🚨 BẢO VỆ BUFFER NGUYÊN TỬ: Drop frame ngay và giải phóng native buffer
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
        _isProcessingFrame = false; // Thả lock
      });
    });

    debugPrint('[CameraService] stream started (~${AppConstants.activeInferenceFps}fps forward)');
  }

  Future<void> stopImageStream() async {
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        await _controller!.stopImageStream();
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

  // P1-FIX-4: dispose đúng thứ tự — stopImageStream trước, dispose sau
  Future<void> dispose() async {
    await stopImageStream();
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }
}