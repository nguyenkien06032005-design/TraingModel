// file: lib/features/detection/domain/entities/detection_object.dart

import 'package:equatable/equatable.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart'; // Bug 15 FIX: dùng VoiceHelper

class BoundingBox extends Equatable {
  final double left, top, width, height;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right   => left + width;
  double get bottom  => top + height;
  double get centerX => left + width  / 2;
  double get centerY => top  + height / 2;
  double get area    => width * height;

  String get horizontalPosition {
    if (centerX < 0.33) return 'bên trái';
    if (centerX > 0.67) return 'bên phải';
    return 'phía trước';
  }

  String get proximityLabel {
    if (area > 0.25) return 'rất gần';
    if (area > 0.10) return 'gần';
    if (area > 0.03) return 'trung bình';
    return 'xa';
  }

  @override
  List<Object?> get props => [left, top, width, height];
}

class DetectionObject extends Equatable {
  final String      label;
  final double      confidence;
  final BoundingBox boundingBox;

  const DetectionObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  // Bug 15 FIX: Delegate sang VoiceHelper — single source of truth cho TTS strings
  // Trước đây: "Phát hiện $label ..." (mâu thuẫn với VoiceHelper "Cảnh báo! ...")
  String get voiceWarning => VoiceHelper.buildWarning(
    label:    label,
    position: boundingBox.horizontalPosition,
    distance: boundingBox.proximityLabel,
  );

  // P2-Fix6: Dùng constant từ AppConstants — không hardcode trong entity
  bool get isDangerous => boundingBox.area > AppConstants.dangerousAreaThreshold;

  @override
  List<Object?> get props => [label, confidence, boundingBox];
}