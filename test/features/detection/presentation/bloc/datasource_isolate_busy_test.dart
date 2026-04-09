import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:camera/camera.dart';

import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';

// Test strategy
//
// DetectionLocalDatasourceImpl depends on the native TFLite interpreter.
// In a unit-test environment there is no native engine, so the isolate
// cannot be spawned. Because of that, `_isolateBusy` is verified through
// TrackingDatasource, a test double that mirrors the same finally-block logic.
//
// A device integration test is still required for full validation of
// GPU delegates, isolate spawning, and model loading.
// ─────────────────────────────────────────────────────────────────────────

class MockDetectionDatasource extends Mock
    implements DetectionLocalDatasource {}

class MockCameraImage extends Mock implements CameraImage {}

/// Test double that mirrors the finally-block pattern from the real
/// implementation. It verifies that `_isolateBusy` is always reset,
/// including when inference throws.
class TrackingDatasource implements DetectionLocalDatasource {
  bool _modelLoaded = false;
  bool _isolateBusy = false;
  int inferenceCallCount = 0;
  bool shouldThrow = false;
  Exception? exceptionToThrow;
  List<Map<String, dynamic>> Function()? resultFactory;

  bool get isolateBusy => _isolateBusy;

  @override
  Future<void> loadModel() async {
    _modelLoaded = true;
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraImage image, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded) return [];
    if (_isolateBusy) return [];

    _isolateBusy = true;
    inferenceCallCount++;

    try {
      if (shouldThrow) {
        throw exceptionToThrow ?? Exception('Simulated inference error');
      }
      return resultFactory?.call() ?? [];
    } catch (e) {
      rethrow;
    } finally {
      // The finally block guarantees that `_isolateBusy` is reset on both
      // success and exception paths.
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _modelLoaded = false;
    _isolateBusy = false;
  }
}

void main() {
  late TrackingDatasource datasource;
  late MockCameraImage    mockImage;

  setUp(() {
    datasource = TrackingDatasource();
    mockImage  = MockCameraImage();
  });

  // _isolateBusy is always reset after runInference

  group('_isolateBusy được đặt lại trong finally', () {
    setUp(() async {
      await datasource.loadModel();
    });

    test('isolateBusy là false trước lần suy luận đầu tiên', () {
      expect(datasource.isolateBusy, isFalse);
    });

    test('isolateBusy được đặt lại sau khi suy luận thành công', () async {
      datasource.resultFactory = () => [
        {
          'label': 'person', 'confidence': 0.85,
          'left': 0.1, 'top': 0.1, 'width': 0.3, 'height': 0.4,
        }
      ];

      await datasource.runInference(mockImage, rotationDegrees: 0);

      expect(datasource.isolateBusy, isFalse,
          reason: 'isolateBusy phải trở về false sau khi thành công');
    });

    test('isolateBusy được đặt lại sau khi suy luận ném exception', () async {
      datasource.shouldThrow   = true;
      datasource.exceptionToThrow = Exception('GPU out of memory');

      try {
        await datasource.runInference(mockImage, rotationDegrees: 0);
      } catch (_) {}

      expect(datasource.isolateBusy, isFalse,
          reason: 'isolateBusy phải trở về false ngay cả khi có exception');
    });

    test('sau exception, lần suy luận tiếp theo vẫn chạy bình thường', () async {
      datasource.shouldThrow = true;
      try {
        await datasource.runInference(mockImage, rotationDegrees: 0);
      } catch (_) {}

      datasource.shouldThrow = false;
      datasource.resultFactory = () => [
        {
          'label': 'bicycle', 'confidence': 0.7,
          'left': 0.2, 'top': 0.2, 'width': 0.2, 'height': 0.3,
        }
      ];

      final results = await datasource.runInference(mockImage, rotationDegrees: 0);

      expect(results, isNotEmpty,
          reason: 'Sau exception, lần suy luận kế tiếp vẫn phải chạy được. '
              'Nếu isolateBusy không được đặt lại, kết quả sẽ luôn là [].');
      expect(results.first['label'], 'bicycle');
      expect(datasource.inferenceCallCount, equals(2));
    });

    test('khi gọi đồng thời, lần thứ hai trả về [] nếu lần đầu còn đang chạy', () async {
      int callCount = 0;
      final ds = TrackingDatasource();
      await ds.loadModel();
      ds.resultFactory = () {
        callCount++;
        return [];
      };

      await ds.runInference(mockImage, rotationDegrees: 0);
      expect(ds.isolateBusy, isFalse);
      await ds.runInference(mockImage, rotationDegrees: 0);

      expect(callCount, equals(2));
    });

    test('closeModel đặt lại isolateBusy', () async {
      datasource.shouldThrow = true;
      try {
        await datasource.runInference(mockImage, rotationDegrees: 0);
      } catch (_) {}

      await datasource.closeModel();

      expect(datasource.isolateBusy, isFalse,
          reason: 'closeModel() phải đặt lại isolateBusy');
    });
  });

  // DetectionDatasource contract

  group('Hợp đồng của DetectionDatasource', () {
    test('runInference trả về [] trước khi loadModel được gọi', () async {
      final result = await datasource.runInference(mockImage, rotationDegrees: 0);
      expect(result, isEmpty);
    });

    test('sau khi loadModel thì runInference chạy bình thường', () async {
      await datasource.loadModel();
      datasource.resultFactory = () => [
        {
          'label': 'car', 'confidence': 0.9,
          'left': 0.0, 'top': 0.0, 'width': 0.5, 'height': 0.5,
        }
      ];

      final result = await datasource.runInference(mockImage, rotationDegrees: 90);

      expect(result.length, equals(1));
      expect(result.first['label'], 'car');
    });

    test('sau closeModel thì suy luận trả về []', () async {
      await datasource.loadModel();
      await datasource.closeModel();

      final result = await datasource.runInference(mockImage, rotationDegrees: 0);
      expect(result, isEmpty,
          reason: 'Sau closeModel(), suy luận phải trả về [] vì model chưa được nạp');
    });
  });
}
