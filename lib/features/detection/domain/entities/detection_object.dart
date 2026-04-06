

import 'package:equatable/equatable.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart'; 

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

  
  
  String get voiceWarning => VoiceHelper.buildWarning(
    label:    label,
    position: boundingBox.horizontalPosition,
    distance: boundingBox.proximityLabel,
  );

  
  bool get isDangerous => boundingBox.area > AppConstants.dangerousAreaThreshold;

  @override
  List<Object?> get props => [label, confidence, boundingBox];
}