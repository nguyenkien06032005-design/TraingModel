import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  late Interpreter _interpreter;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> loadModel() async {
    if (_isLoaded) return;

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/result_trainexport.tflite',
        options: InterpreterOptions()..threads = 4,
      );

      _isLoaded = true;
      print('✅ TFLite model loaded');
    } catch (e) {
      print('❌ Failed to load TFLite model: $e');
      rethrow;
    }
  }

  Interpreter get interpreter => _interpreter;
}
