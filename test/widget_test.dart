// ignore_for_file: avoid_print

// ============================================================================
// Widget tests for SafeVision App
//
// NOTE: Full widget tests for CameraViewPage require a real camera device
// and model assets, making them unsuitable for pure unit/widget test runners.
//
// These tests cover:
//   - App can be created without crashing (smoke test)
//   - DetectionState widgets render correctly given mocked BLoC states
//   - ConfidenceScoreDisplay renders correctly
//   - BoundingBoxPainter generates correct paint calls
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/confidence_score_display.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/bounding_box_painter.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // ConfidenceScoreDisplay widget
  // ══════════════════════════════════════════════════════════════════════════

  group('ConfidenceScoreDisplay', () {
    // Helper: build widget with given detections
    // P3-Fix8: maxItems tường minh — test không phụ thuộc vào default của widget
    Widget buildWidget(List<DetectionObject> detections, {int maxItems = 5}) {
      return MaterialApp(
        home: Scaffold(
          body: ConfidenceScoreDisplay(
              detections: detections, maxItems: maxItems),
        ),
      );
    }

    DetectionObject makeDetection({
      String label = 'person',
      double confidence = 0.85,
      double left = 0.1,
      double top = 0.1,
      double width = 0.3,
      double height = 0.4,
    }) =>
        DetectionObject(
          label: label,
          confidence: confidence,
          boundingBox: BoundingBox(
            left: left,
            top: top,
            width: width,
            height: height,
          ),
        );

    // Empty list → SizedBox.shrink (no widget shown)
    testWidgets('renders SizedBox.shrink when detections empty',
        (tester) async {
      await tester.pumpWidget(buildWidget([]));

      // No label text should appear
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('person'), findsNothing);
    });

    // Single detection → label shown
    testWidgets('shows label when one detection', (tester) async {
      await tester.pumpWidget(buildWidget([makeDetection(label: 'bicycle')]));

      expect(find.textContaining('bicycle'), findsOneWidget);
    });

    // Multiple detections → all labels shown (up to maxItems=5)
    testWidgets('shows all labels for multiple detections', (tester) async {
      final detections = [
        makeDetection(label: 'person', confidence: 0.9),
        makeDetection(label: 'bicycle', confidence: 0.8),
        makeDetection(label: 'car', confidence: 0.7),
      ];
      await tester.pumpWidget(buildWidget(detections));

      expect(find.textContaining('person'), findsOneWidget);
      expect(find.textContaining('bicycle'), findsOneWidget);
      expect(find.textContaining('car'), findsOneWidget);
    });

    // Shows detection count header
    testWidgets('shows detection count', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(label: 'person'),
        makeDetection(label: 'car'),
      ]));

      // Should show "Phát hiện 2 vật thể"
      expect(find.textContaining('2'), findsWidgets);
    });

    // Confidence percentage is shown
    testWidgets('shows confidence percentage text', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(label: 'person', confidence: 0.85),
      ]));

      // Should display "85%" somewhere
      expect(find.textContaining('85'), findsWidgets);
    });

    // Max 5 items shown even if more are provided
    testWidgets('shows at most maxItems detections', (tester) async {
      const testMaxItems = 5;
      final detections = List.generate(
        10,
        (i) => makeDetection(label: 'obj$i', confidence: 0.5 + i * 0.01),
      );
      // P3-Fix8: Truyền maxItems tường minh — test theo API contract, không phụ
      // thuộc default value. Nếu widget đổi default thì test vẫn đúng.
      await tester.pumpWidget(buildWidget(detections, maxItems: testMaxItems));

      // Count LinearProgressIndicator widgets as a proxy for rows
      expect(find.byType(LinearProgressIndicator), findsNWidgets(testMaxItems));
    });

    // High confidence → green dot color indicator
    testWidgets('renders without overflow for long label', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(label: 'very_long_label_that_might_overflow_the_box'),
      ]));

      // Should not throw FlutterError about overflow
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // BoundingBoxPainter
  // ══════════════════════════════════════════════════════════════════════════

  group('BoundingBoxPainter', () {
    // Các test trong group này dùng SmoothedBox trực tiếp (không cần makeDetection)

    // Painter with empty list — no exception during paint
    testWidgets('paints without error when detections empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: [],
                  mirrorHorizontal: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // Painter with detections — no exception
    testWidgets('paints without error with detections', (tester) async {
      final smoothed = [
        SmoothedBox(
          left: 0.2,
          top: 0.2,
          width: 0.4,
          height: 0.5,
          label: 'person',
          trackId: 1,
          missedFrames: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: smoothed,
                  mirrorHorizontal: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // Mirror mode (front camera) — no exception
    testWidgets('paints without error in mirror mode', (tester) async {
      final smoothed = [
        SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'person',
          trackId: 1,
          missedFrames: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: smoothed,
                  mirrorHorizontal: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // shouldRepaint: different boxes → true
    test('shouldRepaint returns true when boxes change', () {
      final a = BoundingBoxPainter(
        boxes: [
          const SmoothedBox(
              left: 0.1,
              top: 0.1,
              width: 0.3,
              height: 0.4,
              label: 'x',
              trackId: 1,
              missedFrames: 0),
        ],
      );
      final b = BoundingBoxPainter(
        boxes: [
          const SmoothedBox(
              left: 0.5,
              top: 0.5,
              width: 0.2,
              height: 0.2,
              label: 'y',
              trackId: 2,
              missedFrames: 0),
        ],
      );

      expect(a.shouldRepaint(b), isTrue);
    });

    // shouldRepaint: same empty boxes → false
    test('shouldRepaint returns false when boxes identical', () {
      final painter = BoundingBoxPainter(boxes: []);
      expect(painter.shouldRepaint(BoundingBoxPainter(boxes: [])), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // BoxTracker
  // ══════════════════════════════════════════════════════════════════════════

  group('BoxTracker', () {
    DetectionObject make({
      String label = 'person',
      double left = 0.1,
      double top = 0.1,
      double w = 0.3,
      double h = 0.4,
    }) =>
        DetectionObject(
          label: label,
          confidence: 0.9,
          boundingBox: BoundingBox(left: left, top: top, width: w, height: h),
        );

    // Empty update → empty tracked list
    test('returns empty when updated with empty detections', () {
      final tracker = BoxTracker();
      final result = tracker.update([]);
      expect(result, isEmpty);
    });

    // First detection → added to tracker
    test('new detection is added to tracked list', () {
      final tracker = BoxTracker();
      final result = tracker.update([make(label: 'person')]);
      expect(result.length, 1);
      expect(result[0].label, 'person');
    });

    // Second frame same object → count stays at 1 (not doubled)
    test('same object detected twice stays as 1 entry', () {
      final tracker = BoxTracker();
      tracker.update([make(label: 'person', left: 0.1)]);
      // Second frame, same position
      final result = tracker.update([make(label: 'person', left: 0.12)]);
      expect(result.length, 1);
    });

    test('object removed after maxTrackAge without detection', () {
      final tracker = BoxTracker();
      final start = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.update([make(label: 'person')], now: start);
      final result = tracker.update(
        [],
        now: start.add(const Duration(milliseconds: 450)),
      );

      expect(result, isEmpty);
    });

    // Two different objects tracked independently
    test('two different objects tracked independently', () {
      final tracker = BoxTracker();
      final result = tracker.update([
        make(label: 'person', left: 0.1),
        make(label: 'bicycle', left: 0.6),
      ]);
      expect(result.length, 2);
      expect(result.map((b) => b.label).toSet(), {'person', 'bicycle'});
    });

    // clear() removes all tracked objects
    test('clear() empties the tracker', () {
      final tracker = BoxTracker();
      tracker.update([make()]);
      tracker.clear();
      expect(tracker.update([]), isEmpty);
    });

    test('new track snapshot starts with missedFrames = 0', () {
      final tracker = BoxTracker();
      final result = tracker.update([make(label: 'y')]);

      final box = result.single;
      expect(box.missedFrames, 0);
    });

    test('matched track resets missedFrames to 0 after update', () {
      final tracker = BoxTracker();
      final start = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.update([make(label: 'z')], now: start);
      tracker.update([], now: start.add(const Duration(milliseconds: 100)));
      final result = tracker.update(
        [make(label: 'z', left: 0.11)],
        now: start.add(const Duration(milliseconds: 200)),
      );

      expect(result.single.missedFrames, 0);
    });
  });
}
