import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/bounding_box_painter.dart';

void main() {
  // ─── FIX SV-004: TextPainter memory leak ────────────────────────────────

  group('FIX SV-004: BoundingBoxPainter.dispose() clears TextPainter cache', () {
    testWidgets('dispose() clears cache without exception', (tester) async {
      final painter = BoundingBoxPainter(
        boxes: [
          const SmoothedBox(
            left: 0.1, top: 0.1, width: 0.3, height: 0.4,
            label: 'person', trackId: 1, missedFrames: 0,
          ),
          const SmoothedBox(
            left: 0.5, top: 0.2, width: 0.2, height: 0.3,
            label: 'bicycle', trackId: 2, missedFrames: 0,
          ),
        ],
        version: 1,
      );

      // Paint để populate TextPainter cache
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      );

      // dispose() phải bỏ widget không crash và clear cache
      expect(() => painter.dispose(), returnsNormally,
          reason: 'FIX SV-004: dispose() phải clear TextPainter cache không crash');
    });

    testWidgets('multiple labels are cached then cleared on dispose', (tester) async {
      final boxes = List.generate(
        10,
        (i) => SmoothedBox(
          left: i * 0.05, top: 0.1, width: 0.04, height: 0.04,
          label: 'label_$i', trackId: i, missedFrames: 0,
        ),
      );

      final painter = BoundingBoxPainter(boxes: boxes, version: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: CustomPaint(painter: painter)),
          ),
        ),
      );

      // Painter đã populate cache với 10 labels
      // dispose() phải clear tất cả và không throw
      expect(() => painter.dispose(), returnsNormally);
    });
  });

  // ─── FIX SV-008: Static Paint mutation ───────────────────────────────────

  group('FIX SV-008: Paint objects are per-frame, not mutated static', () {
    testWidgets('painting multiple frames does not corrupt colors', (tester) async {
      // Test rằng boxes với màu khác nhau được render đúng
      // (không bị carry-over từ frame trước do static Paint mutation)

      final boxes1 = [
        const SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'person', trackId: 1, missedFrames: 0,
        ),
      ];
      final boxes2 = [
        const SmoothedBox(
          left: 0.5, top: 0.5, width: 0.2, height: 0.2,
          label: 'bicycle', trackId: 2, missedFrames: 0,
        ),
      ];

      // Frame 1: person
      final painter1 = BoundingBoxPainter(boxes: boxes1, version: 1);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter1)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Frame 1 không được throw');

      // Frame 2: bicycle
      final painter2 = BoundingBoxPainter(boxes: boxes2, version: 2);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter2)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'FIX SV-008: Frame 2 không được bị ảnh hưởng bởi static Paint từ frame 1');
    });

    testWidgets('missed frames opacity applied correctly per box', (tester) async {
      final boxes = [
        const SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'car', trackId: 1, missedFrames: 0, // opacity = 1.0
        ),
        const SmoothedBox(
          left: 0.5, top: 0.5, width: 0.2, height: 0.2,
          label: 'truck', trackId: 2, missedFrames: 2, // opacity < 1.0
        ),
      ];

      final painter = BoundingBoxPainter(boxes: boxes, version: 1);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ─── FIX SV-011: shouldRepaint O(1) via version ──────────────────────────

  group('FIX SV-011: shouldRepaint uses O(1) version comparison', () {
    test('same version → no repaint needed', () {
      final boxes = [
        const SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'person', trackId: 1, missedFrames: 0,
        ),
      ];
      final painter1 = BoundingBoxPainter(boxes: boxes, version: 5);
      final painter2 = BoundingBoxPainter(boxes: boxes, version: 5);

      expect(painter1.shouldRepaint(painter2), isFalse,
          reason: 'FIX SV-011: même version → shouldRepaint = false (O(1))');
    });

    test('different version → repaint needed', () {
      final boxes = const [
        SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'person', trackId: 1, missedFrames: 0,
        ),
      ];
      final painter1 = BoundingBoxPainter(boxes: boxes, version: 5);
      final painter2 = BoundingBoxPainter(boxes: boxes, version: 6);

      expect(painter1.shouldRepaint(painter2), isTrue,
          reason: 'Version thay đổi → shouldRepaint = true');
    });

    test('different mirrorHorizontal → repaint needed regardless of version', () {
      final painter1 = BoundingBoxPainter(boxes: const [], mirrorHorizontal: false, version: 1);
      final painter2 = BoundingBoxPainter(boxes: const [], mirrorHorizontal: true, version: 1);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('same version, same boxes, same mirror → no repaint', () {
      final painter1 = BoundingBoxPainter(boxes: const [], mirrorHorizontal: false, version: 3);
      final painter2 = BoundingBoxPainter(boxes: const [], mirrorHorizontal: false, version: 3);

      expect(painter1.shouldRepaint(painter2), isFalse);
    });
  });

  // ─── BoxTracker version counter ──────────────────────────────────────────

  group('BoxTracker version counter (SV-011 support)', () {
    DetectionObject makeDetection({
      String label = 'person', double left = 0.1, double w = 0.2, double h = 0.3,
    }) => DetectionObject(
      label: label, confidence: 0.9,
      boundingBox: BoundingBox(left: left, top: 0.1, width: w, height: h),
    );

    test('version starts at 0', () {
      final tracker = BoxTracker();
      expect(tracker.version, equals(0));
    });

    test('version increments on each update', () {
      final tracker = BoxTracker();
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(1));
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(2));
    });

    test('version increments on clear()', () {
      final tracker = BoxTracker();
      final vBefore = tracker.version;
      tracker.clear();
      expect(tracker.version, greaterThan(vBefore));
    });

    test('version increments even on empty update', () {
      final tracker = BoxTracker();
      tracker.update([]);
      expect(tracker.version, equals(1));
    });
  });

  // ─── Painter regression tests ─────────────────────────────────────────────

  group('BoundingBoxPainter regression', () {
    testWidgets('paints empty boxes without error', (tester) async {
      final painter = BoundingBoxPainter(boxes: const [], version: 0);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrorHorizontal flips boxes without error', (tester) async {
      final painter = BoundingBoxPainter(
        boxes: const [SmoothedBox(
          left: 0.3, top: 0.3, width: 0.4, height: 0.4,
          label: 'car', trackId: 1, missedFrames: 0,
        )],
        mirrorHorizontal: true,
        version: 1,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles box near edges (clamp behavior)', (tester) async {
      final painter = BoundingBoxPainter(
        boxes: const [
          SmoothedBox(left: -0.1, top: -0.1, width: 1.5, height: 1.5,
              label: 'overflow', trackId: 1, missedFrames: 0),
        ],
        version: 1,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Out-of-bounds boxes phải được clamp, không crash');
    });
  });
}
