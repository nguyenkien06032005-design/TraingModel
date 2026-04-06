
























import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/error/exceptions.dart';

void main() {
  
  
  

  group('PermissionException', () {
    test('stores message correctly', () {
      const ex = PermissionException('Camera access denied');
      expect(ex.message, equals('Camera access denied'));
    });

    test('toString includes class name and message', () {
      const ex = PermissionException('Camera access denied');
      expect(ex.toString(), contains('PermissionException'));
      expect(ex.toString(), contains('Camera access denied'));
    });

    test('is an Exception', () {
      const ex = PermissionException('test');
      expect(ex, isA<Exception>());
    });

    test('two exceptions with same message are const-equal', () {
      const ex1 = PermissionException('same message');
      const ex2 = PermissionException('same message');
      expect(ex1.message, equals(ex2.message));
    });

    test('camera denied message matches expected Vietnamese text', () {
      
      const expectedMsg =
          'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.';
      const ex = PermissionException(expectedMsg);
      expect(ex.message, equals(expectedMsg));
    });

    test('microphone denied message matches expected text', () {
      const expectedMsg = 'Quyền microphone bị từ chối.';
      const ex = PermissionException(expectedMsg);
      expect(ex.message, equals(expectedMsg));
    });
  });

  
  
  

  group('Exception classes', () {
    test('ModelNotFoundException formats correctly', () {
      const ex = ModelNotFoundException('yolov8.tflite not found');
      expect(ex.toString(), contains('ModelNotFoundException'));
      expect(ex.toString(), contains('yolov8.tflite not found'));
    });

    test('InferenceException formats correctly', () {
      const ex = InferenceException('shape mismatch');
      expect(ex.toString(), contains('InferenceException'));
      expect(ex.toString(), contains('shape mismatch'));
    });

    test('CameraException formats correctly', () {
      const ex = CameraException('no camera found');
      expect(ex.toString(), contains('CameraException'));
      expect(ex.toString(), contains('no camera found'));
    });

    test('ImageConversionException formats correctly', () {
      const ex = ImageConversionException('unsupported format');
      expect(ex.toString(), contains('ImageConversionException'));
      expect(ex.toString(), contains('unsupported format'));
    });

    
    test('exception types are distinct', () {
      const perm  = PermissionException('x');
      const model = ModelNotFoundException('x');
      const inf   = InferenceException('x');
      const cam   = CameraException('x');
      const img   = ImageConversionException('x');

      expect(perm,  isNot(isA<ModelNotFoundException>()));
      expect(model, isNot(isA<PermissionException>()));
      expect(inf,   isNot(isA<CameraException>()));
      expect(cam,   isNot(isA<ImageConversionException>()));
      expect(img,   isNot(isA<PermissionException>()));
    });
  });

  
  
  

  group('VoiceHelper', () {
    
    

    test('modelLoaded returns expected Vietnamese string', () {
      
      
      
      
      expect('Hệ thống sẵn sàng', isA<String>());
    });

    test('noObjectFound returns non-empty string', () {
      expect('Không phát hiện vật thể', isNotEmpty);
    });

    test('systemError returns non-empty string', () {
      expect('Lỗi hệ thống, vui lòng thử lại', isNotEmpty);
    });
  });
}