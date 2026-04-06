// file: lib/features/detection/data/datasources/detection_local_datasource_impl.dart
// (File này được viết lại toàn bộ — cover cả Bug 1, 4, 14, 16, 17)

import 'dart:isolate';
import 'dart:math';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_local_datasource.dart';
import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/image_converter.dart';

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl(this._config);

  // Bug 4 FIX: Mutable runtime config thay vì AppConstants compile-time constant
  final DetectionConfig _config;

  Interpreter? _interpreter;
  List<String> _labels      = [];
  List<int>    _outputShape = [];
  bool         _modelLoaded = false;

  Isolate?     _isolate;
  SendPort?    _isolateSendPort;
  ReceivePort? _mainReceivePort;
  int          _consecutiveTimeouts = 0;

  @override
  Future<void> loadModel() async {
    try {
      final raw = await rootBundle.loadString(AssetPaths.labels);
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final options = InterpreterOptions();
      var delegateEnabled = false;

      if (Platform.isAndroid) {
        try {
          options.addDelegate(
            GpuDelegateV2(
              options: GpuDelegateOptionsV2(
                isPrecisionLossAllowed: true,
              ),
            ),
          );
          delegateEnabled = true;
          if (kDebugMode) debugPrint('[DS] Android GPU delegate enabled');
        } catch (e) {
          if (kDebugMode) debugPrint('[DS] Android GPU delegate failed: $e');
        }

        if (!delegateEnabled) {
          options.useNnApiForAndroid = true;
          delegateEnabled = true;
          if (kDebugMode) debugPrint('[DS] NNAPI enabled');
        }
      } else if (Platform.isIOS) {
        try {
          options.useMetalDelegateForIOS = true;
          delegateEnabled = true;
          if (kDebugMode) debugPrint('[DS] Metal delegate enabled');
        } catch (e) {
          if (kDebugMode) debugPrint('[DS] Metal delegate failed: $e');
        }
      }

      if (!delegateEnabled) {
        options.threads = AppConstants.inferenceThreads;
        if (kDebugMode) {
          debugPrint('[DS] CPU-only inference (${AppConstants.inferenceThreads} threads)');
        }
      }

      _interpreter = await Interpreter.fromAsset(AssetPaths.modelFile, options: options);
      _outputShape = _interpreter!.getOutputTensor(0).shape;

      if (kDebugMode) {
        debugPrint('[DS] Model OK — threads=${AppConstants.inferenceThreads}');
        debugPrint('[DS]   input  = ${_interpreter!.getInputTensor(0).shape}');
        debugPrint('[DS]   output = $_outputShape  labels=${_labels.length}');
      }

      _modelLoaded = true;
      await _spawnIsolate();
      if (kDebugMode) debugPrint('[DS] Isolate ready');
    } catch (e, st) {
      debugPrint('[DS] loadModel FAILED: $e\n$st');
      throw ModelNotFoundException('Cannot load model: $e');
    }
  }

  Future<void> _spawnIsolate() async {
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _mainReceivePort!.sendPort);
    _isolateSendPort = await _mainReceivePort!.first as SendPort;

    // Bug 16 FIX: Gửi labels + static config 1 lần lúc spawn
    // thay vì copy 80 strings mỗi frame (~480 string copies/giây)
    _isolateSendPort!.send(_IsolateInitMsg(
      labels:      List.unmodifiable(_labels),
      inputSize:   AppConstants.inputSize,
      outputShape: List.unmodifiable(_outputShape),
    ));
  }

  Future<void> _killAndRespawnIsolate() async {
    if (kDebugMode) debugPrint('[DS] Respawning isolate...');
    try {
      _isolate?.kill(priority: Isolate.immediate);
      _mainReceivePort?.close();
    } catch (_) {}
    _isolate = null;
    _mainReceivePort = null;
    _isolateSendPort = null;
    // _spawnIsolate tự gửi lại init msg → isolate mới luôn có đủ data
    await _spawnIsolate();
    if (kDebugMode) debugPrint('[DS] Isolate respawned');
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraImage image, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded || _interpreter == null || _isolateSendPort == null) return [];

    ReceivePort? replyPort;
    try {
      final planeBytes = <TransferableTypedData>[
        for (final p in image.planes)
          TransferableTypedData.fromList([p.bytes]),
      ];
      final rowStrides   = image.planes.map((p) => p.bytesPerRow).toList();
      final pixelStrides = image.planes.map((p) => p.bytesPerPixel ?? 1).toList();

      replyPort = ReceivePort();
      _isolateSendPort!.send(_InferenceJob(
        replyPort:           replyPort.sendPort,
        planeBytes:          planeBytes,
        planeRowStrides:     rowStrides,
        planePixelStrides:   pixelStrides,
        imageWidth:          image.width,
        imageHeight:         image.height,
        interpreterAddress:  _interpreter!.address,
        rotationDegrees:     rotationDegrees,
        // Bug 4 FIX: Đọc live config thay vì compile-time constant
        confidenceThreshold: _config.confidenceThreshold,
        iouThreshold:        _config.iouThreshold,
        maxDetections:       _config.maxDetections,
      ));

      final dynamic result = await replyPort.first.timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () {
          if (kDebugMode) debugPrint('[DS] inference timeout after 2.5s');
          return 'TIMEOUT';
        },
      );

      if (result is String) {
        if (kDebugMode) debugPrint('[DS] isolate signal: $result');
        if (result == 'TIMEOUT') {
          _consecutiveTimeouts++;
          if (_consecutiveTimeouts >= 3) {
            debugPrint('[DS] 3 consecutive timeouts -> respawning isolate');
            await _killAndRespawnIsolate();
            _consecutiveTimeouts = 0;
          } else {
            debugPrint('[DS] timeout #$_consecutiveTimeouts -> skipping frame');
          }
        } else {
          await _killAndRespawnIsolate();
          _consecutiveTimeouts = 0;
        }
        return [];
      }

      _consecutiveTimeouts = 0;
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('[DS] exception: $e');
      return [];
    } finally {
      replyPort?.close();
    }
  }

  @override
  Future<void> closeModel() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
    _consecutiveTimeouts = 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ISOLATE GLOBALS — cache 1 lần từ _IsolateInitMsg
// ═══════════════════════════════════════════════════════════════════════════

Interpreter?              _cachedInterpreter;
int                       _cachedAddress = 0;
Float32List?              _cachedTensor;
Uint8List?                _cachedOutputBytes;
Float32List?              _cachedOutputFloats;
int                       _cachedOutputLen = 0;

// Bug 16 FIX: Nhận 1 lần lúc spawn thay vì mỗi frame
List<String>? _initLabels;
int           _initInputSize  = 0;
List<int>     _initOutputShape = const [];

void _isolateEntry(SendPort mainSendPort) {
  final jobPort = ReceivePort();
  mainSendPort.send(jobPort.sendPort);
  jobPort.listen((msg) {
    if (msg is _IsolateInitMsg) {
      _initLabels      = msg.labels;
      _initInputSize   = msg.inputSize;
      _initOutputShape = msg.outputShape;
      if (kDebugMode) {
        debugPrint(
          '[Isolate] init received: ${msg.labels.length} labels '
          'inputSize=${msg.inputSize} shape=${msg.outputShape}',
        );
      }
    } else if (msg is _InferenceJob) {
      if (_initLabels == null) {
        debugPrint('[Isolate] ERROR: init msg not yet received — dropping frame');
        msg.replyPort.send('ERROR: not initialized');
        return;
      }
      _processJob(msg);
    }
  });
}

void _processJob(_InferenceJob job) {
  final swTotal = Stopwatch()..start();
  final swPreproc = Stopwatch();
  final swInfer = Stopwatch();
  final swParse = Stopwatch();
  try {
    // Cache interpreter theo address
    if (_cachedAddress != job.interpreterAddress) {
      _cachedInterpreter?.close();
      _cachedInterpreter = Interpreter.fromAddress(job.interpreterAddress);
      _cachedAddress     = job.interpreterAddress;
      if (kDebugMode) debugPrint('[Isolate] interpreter cached (addr=$_cachedAddress)');
    }
    final interpreter = _cachedInterpreter!;

    swPreproc.start();
    final planes = <Uint8List>[
      for (final t in job.planeBytes) t.materialize().asUint8List(),
    ];

    // Single-pass YUV → rotate → letterbox → Float32
    final lb = ImageConverter.yuvToLetterboxedFloat32(
      planes:          planes,
      rowStrides:      job.planeRowStrides,
      pixelStrides:    job.planePixelStrides,
      srcWidth:        job.imageWidth,
      srcHeight:       job.imageHeight,
      inputSize:       _initInputSize,
      rotationDegrees: job.rotationDegrees,
      reuseBuffer:     _cachedTensor,
    );
    _cachedTensor = lb.inputTensor;

    final inputTensor = lb.inputTensor.reshape([1, _initInputSize, _initInputSize, 3]);
    swPreproc.stop();

    swInfer.start();
    _ensureOutputFlat();
    final outputMap = <int, Object>{0: _cachedOutputBytes!};
    interpreter.runForMultipleInputs([inputTensor], outputMap);
    swInfer.stop();

    swParse.start();
    final results = _parseFlat(
      flat:                _cachedOutputFloats!,
      letterbox:           lb,
      confidenceThreshold: job.confidenceThreshold,
      iouThreshold:        job.iouThreshold,
      maxDetections:       job.maxDetections,
    );
    swParse.stop();
    swTotal.stop();

    if (kDebugMode) {
      debugPrint(
        '[Perf] total=${swTotal.elapsedMilliseconds}ms '
        'preproc=${swPreproc.elapsedMilliseconds}ms '
        'infer=${swInfer.elapsedMilliseconds}ms '
        'parse=${swParse.elapsedMilliseconds}ms',
      );
    }

    job.replyPort.send(results);
  } catch (e, st) {
    job.replyPort.send('ERROR: $e\n$st');
  }
}

void _ensureOutputFlat() {
  // FIX: Validate shape trước khi truy cập index — tránh RangeError khi model
  // khác chuẩn hoặc load lỗi một phần (e.g. shape=[84,8400] thay vì [1,8400,84])
  if (_initOutputShape.length < 3) {
    throw StateError(
      '[Isolate] Output shape invalid: $_initOutputShape — '
      'cần ít nhất 3 chiều [batch, dim0, dim1]',
    );
  }
  final needed = _initOutputShape[1] * _initOutputShape[2];
  if (needed <= 0) {
    throw StateError(
      '[Isolate] Output shape produced needed=$needed — '
      'shape=$_initOutputShape có thể bị transpose sai hoặc zero-dim',
    );
  }
  if (_cachedOutputBytes == null || _cachedOutputLen != needed) {
    _cachedOutputBytes = Uint8List(needed * Float32List.bytesPerElement);
    _cachedOutputFloats = _cachedOutputBytes!.buffer.asFloat32List();
    _cachedOutputLen = needed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARSE + UN-LETTERBOX
// Bug 1 FIX:  Detect transposed vs non-transposed từ shape
// Bug 17 FIX: Dùng AppConstants.yoloHasObjectness thay vì infer từ label count
// ═══════════════════════════════════════════════════════════════════════════

List<Map<String, dynamic>> _parseFlat({
  required Float32List       flat,
  required LetterboxResult   letterbox,
  required double            confidenceThreshold,
  required double            iouThreshold,
  required int               maxDetections,
}) {
  final labels = _initLabels!;
  final inputSize = _initInputSize;
  final shape = _initOutputShape;

  // FIX: Guard shape trước khi truy cập index cố định — tránh RangeError isolate
  if (shape.length < 3) {
    debugPrint('[Parse] ERROR: shape $shape không đủ 3 chiều — bỏ qua frame');
    return [];
  }

  final int dim0 = shape[1];
  final int dim1 = shape[2];
  final bool isTransposed = dim0 < dim1;
  final int numBoxes = isTransposed ? dim1 : dim0;
  final int numChannels = isTransposed ? dim0 : dim1;
  final int classOffset = AppConstants.yoloHasObjectness ? 5 : 4;
  final int availableClasses = (numChannels - classOffset).clamp(0, labels.length);

  if (availableClasses <= 0) {
    debugPrint(
      '[Parse] ERROR: availableClasses=$availableClasses '
      '-> shape $shape incompatible with ${labels.length} labels',
    );
    return [];
  }

  double valueAt(int boxIndex, int channelIndex) {
    if (isTransposed) {
      return flat[channelIndex * numBoxes + boxIndex];
    }
    return flat[boxIndex * numChannels + channelIndex];
  }

  final rawBoxes = <_RawBox>[];

  for (int i = 0; i < numBoxes; i++) {
    final double cx = valueAt(i, 0);
    final double cy = valueAt(i, 1);
    final double bw = valueAt(i, 2);
    final double bh = valueAt(i, 3);

    if (bw <= 0 || bh <= 0) continue;

    final double objectness = AppConstants.yoloHasObjectness
        ? _activateScore(valueAt(i, 4))
        : 1.0;
    if (objectness < confidenceThreshold) continue;

    int bestClassId = -1;
    double bestClassScore = 0.0;
    for (int c = 0; c < availableClasses; c++) {
      final double score = _activateScore(valueAt(i, classOffset + c));
      if (score > bestClassScore) {
        bestClassScore = score;
        bestClassId = c;
      }
    }

    if (bestClassId < 0) continue;

    final double finalScore = objectness * bestClassScore;
    if (finalScore < confidenceThreshold) continue;

    final box = ImageConverter.unLetterboxBox(
      cx: cx,
      cy: cy,
      bw: bw,
      bh: bh,
      padLeft: letterbox.padLeft,
      padTop: letterbox.padTop,
      scale: letterbox.scale,
      origWidth: letterbox.origWidth,
      origHeight: letterbox.origHeight,
      inputSize: inputSize,
    );

    if (box.width <= 0 || box.height <= 0) continue;

    rawBoxes.add(_RawBox(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      score: finalScore,
      classId: bestClassId,
    ));
  }

  // FIX: Top-k pre-filter trước NMS — giới hạn O(n²) khi confidence threshold thấp
  // dẫn đến hàng trăm raw boxes (đặc biệt với scene đông vật thể).
  // maxDetections * 10 là heuristic đủ rộng để NMS hoạt động chính xác.
  const int nmsTopK = 100; // absolute cap, không phụ thuộc maxDetections
  if (rawBoxes.length > nmsTopK) {
    rawBoxes.sort((a, b) => b.score.compareTo(a.score));
    rawBoxes.removeRange(nmsTopK, rawBoxes.length);
    if (kDebugMode) {
      debugPrint('[Parse] top-k capped raw boxes to $nmsTopK');
    }
  }

  final kept = _nms(rawBoxes, iouThreshold);

  if (kept.isNotEmpty && kDebugMode) {
    debugPrint('[Parse] NMS kept=${kept.length}');
  }

  return kept.take(maxDetections).map((b) {
    final label = b.classId < labels.length
        ? labels[b.classId]
        : 'class_${b.classId}';
    return <String, dynamic>{
      'label': label,
      'confidence': b.score,
      'left': b.left,
      'top': b.top,
      'width': b.width,
      'height': b.height,
    };
  }).toList();
}

double _activateScore(double rawScore) {
  if (!AppConstants.yoloOutputLogits) return rawScore;
  return 1.0 / (1.0 + exp(-rawScore));
}

List<_RawBox> _nms(List<_RawBox> boxes, double iouThreshold) {
  boxes.sort((a, b) => b.score.compareTo(a.score));
  final result = <_RawBox>[];
  for (final box in boxes) {
    bool suppressed = false;
    for (final kept in result) {
      if (box.classId == kept.classId && _iou(box, kept) > iouThreshold) {
        suppressed = true;
        break;
      }
    }
    if (!suppressed) result.add(box);
  }
  return result;
}

double _iou(_RawBox a, _RawBox b) {
  final iL = max(a.left, b.left);
  final iT = max(a.top, b.top);
  final iR = min(a.left + a.width, b.left + b.width);
  final iB = min(a.top + a.height, b.top + b.height);
  if (iR <= iL || iB <= iT) return 0;
  final inter = (iR - iL) * (iB - iT);
  return inter / (a.width * a.height + b.width * b.height - inter);
}

class _RawBox {
  final double left, top, width, height, score;
  final int    classId;
  const _RawBox({
    required this.left, required this.top,
    required this.width, required this.height,
    required this.score, required this.classId,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGES
// ═══════════════════════════════════════════════════════════════════════════

/// Bug 16 FIX: Gửi labels + static data 1 lần khi spawn isolate
class _IsolateInitMsg {
  final List<String> labels;
  final int          inputSize;
  final List<int>    outputShape;

  const _IsolateInitMsg({
    required this.labels,
    required this.inputSize,
    required this.outputShape,
  });
}

/// Per-frame job — chỉ chứa data thực sự thay đổi mỗi frame
class _InferenceJob {
  final SendPort                    replyPort;
  final List<TransferableTypedData> planeBytes;
  final List<int>                   planeRowStrides;
  final List<int>                   planePixelStrides;
  final int                         imageWidth;
  final int                         imageHeight;
  final int                         interpreterAddress;
  final int                         rotationDegrees;
  // Bug 4 FIX: Runtime values từ DetectionConfig, có thể thay đổi từ Settings
  final double                      confidenceThreshold;
  final double                      iouThreshold;
  final int                         maxDetections;

  const _InferenceJob({
    required this.replyPort,
    required this.planeBytes,
    required this.planeRowStrides,
    required this.planePixelStrides,
    required this.imageWidth,
    required this.imageHeight,
    required this.interpreterAddress,
    required this.rotationDegrees,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.maxDetections,
  });
}
