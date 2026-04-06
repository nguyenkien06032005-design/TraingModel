// file: lib/core/constants/app_constants.dart

class AppConstants {
  AppConstants._();

  // ── Model ──────────────────────────────────────────────────────────────────
  static const String modelFileName  = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  // ── Detection ──────────────────────────────────────────────────────────────
  static const double confidenceThreshold = 0.30;
  static const double iouThreshold        = 0.45;
  static const int    maxDetections       = 10;
  static const int    inputSize           = 320;
  static const int    activeInferenceFps  = 6;
  static const int    inferenceThreads    = 2;

  static const bool   yoloOutputLogits    = false;

  // Bug 17 FIX: Explicit constant — không infer từ label count
  // true = YOLOv5 (có objectness channel), false = YOLOv8 (không có)
  static const bool   yoloHasObjectness   = false;

  // Tracking
  static const double trackingSmoothingAlpha = 0.65;
  static const int    trackingMaxAgeMs       = 400;

  // Ngưỡng "nguy hiểm" dùng để trigger immediate TTS + vibration.
  // Tách ra khỏi entity để dễ tune theo model mới hoặc FOV camera khác nhau.
  static const double dangerousAreaThreshold = 0.10;

  // ── TTS ────────────────────────────────────────────────────────────────────
  // Bug 5 FIX: Single source of truth — TtsService dùng constant này,
  // DetectionBloc không có cooldown riêng nữa
  static const int    ttsCooldownMs = 3000;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch      = 1.00;
  static const double ttsVolume     = 1.00;
  static const String ttsLanguage   = 'vi-VN';
}