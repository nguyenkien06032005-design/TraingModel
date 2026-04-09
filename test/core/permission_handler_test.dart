import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/error/exceptions.dart';
import 'package:safe_vision_app/core/utils/voice_helper.dart';

void main() {
  group('PermissionException', () {
    test('lưu đúng nội dung thông báo', () {
      const ex = PermissionException('Camera access denied');
      expect(ex.message, equals('Camera access denied'));
    });

    test('toString chứa tên lớp và nội dung', () {
      const ex = PermissionException('Camera access denied');
      expect(ex.toString(), contains('PermissionException'));
      expect(ex.toString(), contains('Camera access denied'));
    });

    test('là một Exception', () {
      const ex = PermissionException('test');
      expect(ex, isA<Exception>());
    });

    test('hai exception có cùng message thì tương đương về dữ liệu', () {
      const ex1 = PermissionException('same message');
      const ex2 = PermissionException('same message');
      expect(ex1.message, equals(ex2.message));
    });

    test('thông báo từ chối camera khớp với tiếng Việt mong đợi', () {
      const expectedMsg =
          'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.';
      const ex = PermissionException(expectedMsg);
      expect(ex.message, equals(expectedMsg));
    });

    test('thông báo từ chối micro khớp với tiếng Việt mong đợi', () {
      const expectedMsg = 'Quyền micro bị từ chối.';
      const ex = PermissionException(expectedMsg);
      expect(ex.message, equals(expectedMsg));
    });
  });

  group('Các lớp exception', () {
    test('ModelNotFoundException định dạng đúng', () {
      const ex = ModelNotFoundException('yolov8.tflite not found');
      expect(ex.toString(), contains('ModelNotFoundException'));
      expect(ex.toString(), contains('yolov8.tflite not found'));
    });

    test('InferenceException định dạng đúng', () {
      const ex = InferenceException('shape mismatch');
      expect(ex.toString(), contains('InferenceException'));
      expect(ex.toString(), contains('shape mismatch'));
    });

    test('CameraException định dạng đúng', () {
      const ex = CameraException('no camera found');
      expect(ex.toString(), contains('CameraException'));
      expect(ex.toString(), contains('no camera found'));
    });

    test('ImageConversionException định dạng đúng', () {
      const ex = ImageConversionException('unsupported format');
      expect(ex.toString(), contains('ImageConversionException'));
      expect(ex.toString(), contains('unsupported format'));
    });

    test('các loại exception là khác nhau', () {
      const perm = PermissionException('x');
      const model = ModelNotFoundException('x');
      const inf = InferenceException('x');
      const cam = CameraException('x');
      const img = ImageConversionException('x');

      expect(perm, isNot(isA<ModelNotFoundException>()));
      expect(model, isNot(isA<PermissionException>()));
      expect(inf, isNot(isA<CameraException>()));
      expect(cam, isNot(isA<ImageConversionException>()));
      expect(img, isNot(isA<PermissionException>()));
    });
  });

  group('VoiceHelper', () {
    test('modelLoaded trả về đúng câu tiếng Việt', () {
      expect(VoiceHelper.modelLoaded(), equals('Hệ thống sẵn sàng'));
    });

    test('noObjectFound trả về câu tiếng Việt không rỗng', () {
      expect(VoiceHelper.noObjectFound(), equals('Không phát hiện vật thể'));
    });

    test('systemError trả về câu tiếng Việt không rỗng', () {
      expect(VoiceHelper.systemError(), equals('Lỗi hệ thống, vui lòng thử lại'));
    });
  });
}
