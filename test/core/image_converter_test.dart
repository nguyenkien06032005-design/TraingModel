
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:safe_vision_app/core/utils/image_converter.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // LetterboxResult
  // ══════════════════════════════════════════════════════════════════════════

  group('LetterboxResult', () {
    test('stores all fields correctly', () {
      final tensor = Float32List(640 * 640 * 3);
      final result = LetterboxResult(
        inputTensor: tensor,
        scale: 2.0,
        padLeft: 0.0625,
        padTop: 0.0,
        origWidth: 240,
        origHeight: 320,
      );

      expect(result.inputTensor, same(tensor));
      expect(result.scale, 2.0);
      expect(result.padLeft, 0.0625);
      expect(result.padTop, 0.0);
      expect(result.origWidth, 240);
      expect(result.origHeight, 320);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ImageConverter.letterboxAndNormalize
  // ══════════════════════════════════════════════════════════════════════════

  group('ImageConverter.letterboxAndNormalize', () {
    const inputSize = 640;

    // Helper: creates a solid-color image for testing
    img.Image makeImage(int w, int h, {int r = 128, int g = 64, int b = 32}) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      return image;
    }

    // Portrait image (240×320): scale = 640/320 = 2.0
    // scaled = 480×640 → padLeft = 80px, padTop = 0
    test('portrait image — correct scale and horizontal padding', () {
      final image = makeImage(240, 320);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      // scale = 640 / max(240, 320) = 640/320 = 2.0
      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.origWidth, 240);
      expect(result.origHeight, 320);

      // padLeft = (640 - 480) / 2 / 640 = 80 / 640 = 0.125
      expect(result.padLeft, closeTo(0.125, 0.002));
      // padTop = 0
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    // Landscape image (320×240): scale = 640/320 = 2.0
    // scaled = 640×480 → padLeft = 0, padTop = 80px
    test('landscape image — correct scale and vertical padding', () {
      final image = makeImage(320, 240);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      // padTop = (640 - 480) / 2 / 640 = 0.125
      expect(result.padTop, closeTo(0.125, 0.002));
    });

    // Square image (320×320): scale = 640/320 = 2.0, no padding
    test('square image — no padding', () {
      final image = makeImage(320, 320);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    // Already 640×640: scale = 1.0, no padding
    test('already input-size image — scale = 1.0, no padding', () {
      final image = makeImage(640, 640);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(1.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    // Tensor size is always inputSize * inputSize * 3
    test('output tensor has correct size', () {
      final image = makeImage(100, 200);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.inputTensor.length, equals(inputSize * inputSize * 3));
    });

    // Tensor values must be in [0.0, 1.0]
    test('tensor values normalized to [0, 1]', () {
      final image = makeImage(320, 240, r: 255, g: 0, b: 128);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      for (final v in result.inputTensor) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    // Padding area should be ~0.447 (= 114/255) — YOLO gray
    test('padding area fills with gray value ≈ 114/255', () {
      // Landscape 320×240 → padTop = 80px
      final image = makeImage(320, 240, r: 255, g: 0, b: 0);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      // First pixel (0,0) is in the top padding area → gray
      // tensor[0] = R channel of pixel (0,0)
      final grayNorm = 114.0 / 255.0;
      expect(result.inputTensor[0], closeTo(grayNorm, 0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ImageConverter.unLetterboxBox
  // ══════════════════════════════════════════════════════════════════════════

  group('ImageConverter.unLetterboxBox', () {
    const inputSize = 640;

    // Portrait scenario: origW=240, origH=320, scale=2.0, padLeft=0.125, padTop=0
    // Center of image (cx=0.5, cy=0.5) should map back to ~(0.5, 0.5) in orig
    test('center box maps back to center of original image', () {
      // scale = 2.0, padLeft = 80/640 = 0.125, padTop = 0
      // A centered box: cx=0.5, cy=0.5, w=0.5, h=0.5
      // cxPx=320, cyPx=320, wPx=320, hPx=320
      // padLPx = 0.125*640 = 80, padTPx = 0
      // x1 = 320 - 160 - 80 = 80, y1 = 320 - 160 - 0 = 160
      // origX1 = 80/2 = 40, origY1 = 160/2 = 80
      // origW = 320/2 = 160, origH = 320/2 = 160
      // normLeft = 40/240 ≈ 0.167, normTop = 80/320 = 0.25
      // normW = 160/240 ≈ 0.667, normH = 160/320 = 0.5
      final box = ImageConverter.unLetterboxBox(
        cx: 0.5, cy: 0.5,
        bw: 0.5, bh: 0.5,
        padLeft: 0.125, padTop: 0.0,
        scale: 2.0,
        origWidth: 240, origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left,   closeTo(0.167, 0.01));
      expect(box.top,    closeTo(0.25,  0.01));
      expect(box.width,  closeTo(0.667, 0.01));
      expect(box.height, closeTo(0.5,   0.01));
    });

    // Box entirely outside letterbox padding → should clamp to [0, 1]
    test('boxes outside frame are clamped to [0, 1]', () {
      // A box in the padding area (x far left in padded region)
      final box = ImageConverter.unLetterboxBox(
        cx: 0.0, cy: 0.5,
        bw: 0.1, bh: 0.3,
        padLeft: 0.125, padTop: 0.0,
        scale: 2.0,
        origWidth: 240, origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left,   greaterThanOrEqualTo(0.0));
      expect(box.top,    greaterThanOrEqualTo(0.0));
      expect(box.width,  greaterThanOrEqualTo(0.0));
      expect(box.height, greaterThanOrEqualTo(0.0));
    });

    // Full-frame box: model detects something covering whole image
    test('full-frame box (1.0×1.0) maps to full original image', () {
      // Square image, no padding: scale=2.0, padLeft=0, padTop=0
      // cx=0.5,cy=0.5,bw=1.0,bh=1.0 in 640×640 space
      // cxPx=320,cyPx=320,wPx=640,hPx=640
      // x1=320-320-0=0, y1=320-320-0=0
      // origX1=0/2=0, origY1=0/2=0, origW=640/2=320, origH=640/2=320
      // normLeft=0/320=0, normTop=0/320=0, normW=1.0, normH=1.0
      final box = ImageConverter.unLetterboxBox(
        cx: 0.5, cy: 0.5,
        bw: 1.0, bh: 1.0,
        padLeft: 0.0, padTop: 0.0,
        scale: 2.0,
        origWidth: 320, origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left,   closeTo(0.0, 0.01));
      expect(box.top,    closeTo(0.0, 0.01));
      expect(box.width,  closeTo(1.0, 0.01));
      expect(box.height, closeTo(1.0, 0.01));
    });

    // All output values are in [0, 1]
    test('output values always clamped to [0, 1]', () {
      // Extreme values that could go out of range
      final box = ImageConverter.unLetterboxBox(
        cx: 1.5, cy: 1.5,
        bw: 2.0, bh: 2.0,
        padLeft: 0.0, padTop: 0.0,
        scale: 1.0,
        origWidth: 100, origHeight: 100,
        inputSize: inputSize,
      );

      expect(box.left,   lessThanOrEqualTo(1.0));
      expect(box.top,    lessThanOrEqualTo(1.0));
      expect(box.width,  lessThanOrEqualTo(1.0));
      expect(box.height, lessThanOrEqualTo(1.0));
      expect(box.left,   greaterThanOrEqualTo(0.0));
      expect(box.top,    greaterThanOrEqualTo(0.0));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ImageConverter.convertYuv420
  // ══════════════════════════════════════════════════════════════════════════

  group('ImageConverter.convertYuv420', () {
    // Creates minimal valid YUV420 planes for a WxH image
    // All pixels pure white: Y=235, U=128, V=128
    (List<Uint8List>, List<int>, List<int>) makeYuvPlanes(int w, int h) {
      // Y plane: w*h bytes
      final y = Uint8List(w * h)..fillRange(0, w * h, 235);
      // U plane: (w/2)*(h/2) bytes, interleaved stride = w
      final uSize = (w ~/ 2) * (h ~/ 2);
      final u = Uint8List(uSize)..fillRange(0, uSize, 128);
      final v = Uint8List(uSize)..fillRange(0, uSize, 128);

      return (
        [y, u, v],
        [w, w ~/ 2, w ~/ 2],   // bytesPerRow for each plane
        [1, 1, 1],              // bytesPerPixel
      );
    }

    test('output image has correct dimensions', () {
      const w = 8, h = 8;
      final (planes, rowStrides, pixelStrides) = makeYuvPlanes(w, h);

      final result = ImageConverter.convertYuv420(
        planes, rowStrides, pixelStrides, w, h,
      );

      expect(result.width, w);
      expect(result.height, h);
    });

    test('neutral UV (128,128) produces gray-ish pixel from Y value', () {
      // Y=235, U=128, V=128 → R≈235, G≈235, B≈235 (white-ish)
      const w = 4, h = 4;
      final (planes, rowStrides, pixelStrides) = makeYuvPlanes(w, h);

      final result = ImageConverter.convertYuv420(
        planes, rowStrides, pixelStrides, w, h,
      );

      // Pixel values should be high (near white)
      final pixel = result.getPixel(0, 0);
      expect(pixel.r, greaterThan(200));
      expect(pixel.g, greaterThan(200));
      expect(pixel.b, greaterThan(200));
    });

    test('handles out-of-bounds gracefully (no exception)', () {
      // Small planes that could cause index issues — should not throw
      final y = Uint8List(4)..fillRange(0, 4, 128);
      final u = Uint8List(1)..fillRange(0, 1, 128);
      final v = Uint8List(1)..fillRange(0, 1, 128);

      expect(
        () => ImageConverter.convertYuv420(
          [y, u, v],
          [4, 2, 2],
          [1, 1, 1],
          4, 4, // h=4 will cause index overflow → should be handled
        ),
        returnsNormally,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Round-trip: letterbox → unLetterbox consistency
  // ══════════════════════════════════════════════════════════════════════════

  group('letterbox round-trip consistency', () {
    test('applying unLetterbox to letterbox result produces sensible coords', () {
      const inputSize = 640;

      // Simulate a portrait camera frame
      final image = img.Image(width: 240, height: 320);
      img.fill(image, color: img.ColorRgb8(100, 150, 200));

      final lb = ImageConverter.letterboxAndNormalize(image, inputSize);

      // Simulate model detecting full image center
      final box = ImageConverter.unLetterboxBox(
        cx: 0.5, cy: 0.5,
        bw: 0.3, bh: 0.4,
        padLeft:   lb.padLeft,
        padTop:    lb.padTop,
        scale:     lb.scale,
        origWidth: lb.origWidth,
        origHeight: lb.origHeight,
        inputSize: inputSize,
      );

      // Result should be a valid box somewhere in [0,1]
      expect(box.left,   inInclusiveRange(0.0, 1.0));
      expect(box.top,    inInclusiveRange(0.0, 1.0));
      expect(box.width,  inInclusiveRange(0.0, 1.0));
      expect(box.height, inInclusiveRange(0.0, 1.0));

      // Width + left should not exceed 1.0 (since we clamp)
      expect(box.left + box.width,  lessThanOrEqualTo(1.0 + 1e-9));
      expect(box.top  + box.height, lessThanOrEqualTo(1.0 + 1e-9));
    });
  });
}