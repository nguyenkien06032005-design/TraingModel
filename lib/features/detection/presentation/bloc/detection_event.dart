// file: lib/features/detection/presentation/bloc/detection_event.dart

import 'package:equatable/equatable.dart';
import 'package:camera/camera.dart';

abstract class DetectionEvent extends Equatable {
  const DetectionEvent();
  @override List<Object?> get props => [];
}

class DetectionStarted extends DetectionEvent { const DetectionStarted(); }
class DetectionStopped extends DetectionEvent { const DetectionStopped(); }

// Bug 21 FIX: DetectionModelLoaded DELETED — không có handler, misleading API

class DetectionFrameReceived extends DetectionEvent {
  final CameraImage      image;
  final int              rotationDegrees;
  final void Function()  onDone;

  const DetectionFrameReceived(this.image, this.rotationDegrees, this.onDone);

  // Bug 10 FIX: Xoá onDone khỏi props
  // Function comparison by identity là vô nghĩa trong Equatable context
  @override List<Object?> get props => [image, rotationDegrees];
}