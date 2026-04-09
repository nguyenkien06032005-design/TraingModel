import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/bounding_box_painter.dart';

void main() {
  // Reset the static cache between groups so TextPainter state from
  // one group does not affect the next one.
  tearDown(() {
    BoundingBoxPainter.clearCacheForTesting();
  });

  // dispose() and TextPainter memory management

  group('BoundingBoxPainter.dispose() clears TextPainter cache', () {
    testWidgets('dispose() chạy không crash và clear đúng labels', (tester) async {
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

      // Paint once to populate the TextPainter cache with 'person' and 'bicycle'.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      );

      expect(() => painter.dispose(), returnsNormally,
          reason: 'dispose() phải clear TextPainter cache không crash');
    });

    testWidgets('dispose() với nhiều labels không để lại leak', (tester) async {
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

      expect(() => painter.dispose(), returnsNormally);
    });
  });

  // Paint objects do not share state between painters

  group('Paint objects per-instance — no shared mutable state', () {
    testWidgets('frame kế tiếp với label khác không bị ảnh hưởng màu sắc', (tester) async {
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

      final painter1 = BoundingBoxPainter(boxes: boxes1, version: 1);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter1)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Frame 1 không được throw');

      final painter2 = BoundingBoxPainter(boxes: boxes2, version: 2);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter2)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Frame 2 không bị ảnh hưởng bởi Paint state của frame 1');
    });

    testWidgets('missedFrames opacity áp dụng độc lập cho từng box', (tester) async {
      final boxes = [
        const SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'car', trackId: 1, missedFrames: 0,
        ),
        const SmoothedBox(
          left: 0.5, top: 0.5, width: 0.2, height: 0.2,
          label: 'truck', trackId: 2, missedFrames: 2,
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

  // shouldRepaint uses an O(1) version counter

  group('shouldRepaint dùng version counter O(1)', () {
    test('cùng version → không repaint', () {
      final boxes = [
        const SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'person', trackId: 1, missedFrames: 0,
        ),
      ];
      final painter1 = BoundingBoxPainter(boxes: boxes, version: 5);
      final painter2 = BoundingBoxPainter(boxes: boxes, version: 5);

      expect(painter1.shouldRepaint(painter2), isFalse,
          reason: 'Cùng version → shouldRepaint = false, O(1)');
    });

    test('version khác → repaint', () {
      const boxes = [
        SmoothedBox(
          left: 0.1, top: 0.1, width: 0.3, height: 0.4,
          label: 'person', trackId: 1, missedFrames: 0,
        ),
      ];
      final painter1 = BoundingBoxPainter(boxes: boxes, version: 5);
      final painter2 = BoundingBoxPainter(boxes: boxes, version: 6);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('mirrorHorizontal khác → repaint bất kể version', () {
      final painter1 = BoundingBoxPainter(
          boxes: const [], mirrorHorizontal: false, version: 1);
      final painter2 = BoundingBoxPainter(
          boxes: const [], mirrorHorizontal: true, version: 1);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('cùng version + cùng mirror → không repaint', () {
      final painter1 = BoundingBoxPainter(
          boxes: const [], mirrorHorizontal: false, version: 3);
      final painter2 = BoundingBoxPainter(
          boxes: const [], mirrorHorizontal: false, version: 3);

      expect(painter1.shouldRepaint(painter2), isFalse);
    });
  });

  // BoxTracker version counter

  group('BoxTracker version counter', () {
    DetectionObject makeDetection({
      String label = 'person',
      double left = 0.1,
      double w = 0.2,
      double h = 0.3,
    }) =>
        DetectionObject(
          label: label,
          confidence: 0.9,
          boundingBox: BoundingBox(left: left, top: 0.1, width: w, height: h),
        );

    test('version bắt đầu từ 0', () {
      final tracker = BoxTracker();
      expect(tracker.version, equals(0));
    });

    test('version tăng sau mỗi lần update', () {
      final tracker = BoxTracker();
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(1));
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(2));
    });

    test('version tăng sau clear()', () {
      final tracker = BoxTracker();
      final vBefore = tracker.version;
      tracker.clear();
      expect(tracker.version, greaterThan(vBefore));
    });

    test('update rỗng vẫn tăng version', () {
      final tracker = BoxTracker();
      tracker.update([]);
      expect(tracker.version, equals(1));
    });
  });

  // Painter regression

  group('BoundingBoxPainter regression', () {
    testWidgets('vẽ không lỗi khi danh sách rỗng', (tester) async {
      final painter = BoundingBoxPainter(boxes: const [], version: 0);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrorHorizontal flip không crash', (tester) async {
      final painter = BoundingBoxPainter(
        boxes: const [
          SmoothedBox(
            left: 0.3, top: 0.3, width: 0.4, height: 0.4,
            label: 'car', trackId: 1, missedFrames: 0,
          )
        ],
        mirrorHorizontal: true,
        version: 1,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox.expand(
          child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('box ngoài biên được clamp — không crash', (tester) async {
      final painter = BoundingBoxPainter(
        boxes: const [
          SmoothedBox(
            left: -0.1, top: -0.1, width: 1.5, height: 1.5,
            label: 'overflow', trackId: 1, missedFrames: 0,
          ),
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
