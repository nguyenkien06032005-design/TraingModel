import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/detection_object.dart';

class SmoothedBox {
  final double left, top, width, height;
  final String label;
  final int trackId;
  final int missedFrames;

  const SmoothedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.trackId,
    required this.missedFrames,
  });

  @override
  bool operator ==(Object other) =>
      other is SmoothedBox &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      label == other.label &&
      trackId == other.trackId &&
      missedFrames == other.missedFrames;

  @override
  int get hashCode =>
      Object.hash(left, top, width, height, label, trackId, missedFrames);
}

class _TrackedBox {
  static const double alpha = AppConstants.trackingSmoothingAlpha;

  final int trackId;
  double left, top, width, height;
  final String label;
  DateTime lastSeenAt;
  int missedFrames;

  _TrackedBox({
    required this.trackId,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.lastSeenAt,
  }) : missedFrames = 0;

  void update(BoundingBox box, DateTime now) {
    left = left * (1 - alpha) + box.left * alpha;
    top = top * (1 - alpha) + box.top * alpha;
    width = width * (1 - alpha) + box.width * alpha;
    height = height * (1 - alpha) + box.height * alpha;
    missedFrames = 0;
    lastSeenAt = now;
  }

  SmoothedBox snapshot() => SmoothedBox(
        left: left,
        top: top,
        width: width,
        height: height,
        label: label,
        trackId: trackId,
        missedFrames: missedFrames,
      );
}

class BoxTracker {
  final Map<int, _TrackedBox> _tracked = {};
  int _nextTrackId = 0;

  static const double matchThreshold = 0.35;
  static const Duration maxTrackAge =
      Duration(milliseconds: AppConstants.trackingMaxAgeMs);

  List<SmoothedBox> update(List<DetectionObject> detections, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();

    for (final tracked in _tracked.values) {
      tracked.missedFrames++;
    }

    final usedTrackIds = <int>{};

    for (final det in detections) {
      final box = det.boundingBox;
      int? bestTrackId;
      double bestIou = 0;

      for (final entry in _tracked.entries) {
        final tracked = entry.value;
        if (tracked.label != det.label) continue;
        if (usedTrackIds.contains(entry.key)) continue;

        final iou = _iou(
          tracked.left,
          tracked.top,
          tracked.width,
          tracked.height,
          box.left,
          box.top,
          box.width,
          box.height,
        );
        if (iou > bestIou) {
          bestIou = iou;
          bestTrackId = entry.key;
        }
      }

      if (bestTrackId != null && bestIou > matchThreshold) {
        _tracked[bestTrackId]!.update(box, timestamp);
        usedTrackIds.add(bestTrackId);
      } else {
        final trackId = _nextTrackId++;
        _tracked[trackId] = _TrackedBox(
          trackId: trackId,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          label: det.label,
          lastSeenAt: timestamp,
        );
        usedTrackIds.add(trackId);
      }
    }

    _tracked.removeWhere(
      (_, tracked) => timestamp.difference(tracked.lastSeenAt) > maxTrackAge,
    );

    return _tracked.values.map((t) => t.snapshot()).toList(growable: false)
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
  }

  double _iou(
    double al,
    double at,
    double aw,
    double ah,
    double bl,
    double bt,
    double bw,
    double bh,
  ) {
    final iL = al > bl ? al : bl;
    final iT = at > bt ? at : bt;
    final iR = (al + aw) < (bl + bw) ? (al + aw) : (bl + bw);
    final iB = (at + ah) < (bt + bh) ? (at + ah) : (bt + bh);
    if (iR <= iL || iB <= iT) return 0;
    final inter = (iR - iL) * (iB - iT);
    return inter / (aw * ah + bw * bh - inter);
  }

  void clear() {
    _tracked.clear();
    _nextTrackId = 0;
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<SmoothedBox> boxes;
  final bool mirrorHorizontal;

  static final _strokePaint = Paint()..style = PaintingStyle.stroke;
  static final _cornerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _labelPaint = Paint()..style = PaintingStyle.fill;

  final Map<String, TextPainter> _textCache = {};
  static const int _maxCacheEntries = 100;

  BoundingBoxPainter({
    required this.boxes,
    this.mirrorHorizontal = false,
  });

  @override
  bool shouldRepaint(covariant BoundingBoxPainter old) {
    if (mirrorHorizontal != old.mirrorHorizontal) return true;
    if (boxes.length != old.boxes.length) return true;
    for (int i = 0; i < boxes.length; i++) {
      if (boxes[i] != old.boxes[i]) return true;
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      _drawBox(canvas, size, box);
    }
  }

  void _drawBox(Canvas canvas, Size size, SmoothedBox box) {
    double l = box.left * size.width;
    double t = box.top * size.height;
    double r = (box.left + box.width) * size.width;
    double b = (box.top + box.height) * size.height;

    if (mirrorHorizontal) {
      final tmp = l;
      l = size.width - r;
      r = size.width - tmp;
    }

    l = l.clamp(0, size.width);
    t = t.clamp(0, size.height);
    r = r.clamp(0, size.width);
    b = b.clamp(0, size.height);

    if (r - l < 2 || b - t < 2) return;

    final rect = Rect.fromLTRB(l, t, r, b);
    final color = _colorForLabel(box.label);
    final opacity = box.missedFrames == 0
        ? 1.0
        : (1.0 - box.missedFrames / 4.0).clamp(0.2, 1.0);

    _strokePaint
      ..color = color.withValues(alpha: 0.85 * opacity)
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, _strokePaint);

    _drawCorners(canvas, rect, color.withValues(alpha: opacity));
    _drawLabel(canvas, size, rect, box.label, color.withValues(alpha: opacity));
  }

  void _drawCorners(Canvas canvas, Rect rect, Color color) {
    final len = (rect.width * 0.15).clamp(8.0, 20.0);
    _cornerPaint
      ..color = color
      ..strokeWidth = 3.0;

    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + len, rect.top)
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + len)
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + len, rect.bottom)
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - len),
      _cornerPaint,
    );
  }

  void _drawLabel(
      Canvas canvas, Size size, Rect rect, String label, Color color) {
    final tp = _getOrCreatePainter(label);
    final lw = tp.width + 10;
    final lh = tp.height + 5;
    final lt = (rect.top - lh - 2).clamp(0.0, size.height - lh);

    _labelPaint.color = color.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, lt, lw, lh),
        const Radius.circular(3),
      ),
      _labelPaint,
    );
    tp.paint(canvas, Offset(rect.left + 5, lt + 2.5));
  }

  TextPainter _getOrCreatePainter(String label) {
    if (_textCache.containsKey(label)) return _textCache[label]!;

    if (_textCache.length >= _maxCacheEntries) {
      final toEvict = _textCache.keys.take(_maxCacheEntries ~/ 2).toList();
      for (final key in toEvict) {
        _textCache[key]!.dispose();
        _textCache.remove(key);
      }
    }

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 200);

    _textCache[label] = painter;
    return painter;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Color _colorForLabel(String label) {
    const palette = [
      Color(0xFF00E676),
      Color(0xFF00B0FF),
      Color(0xFFFF6D00),
      Color(0xFFD500F9),
      Color(0xFF00E5FF),
      Color(0xFFFF4081),
    ];
    return palette[label.hashCode.abs() % palette.length];
  }
}
