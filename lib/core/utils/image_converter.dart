import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Kết quả letterbox: tensor đã sẵn sàng cho model + metadata để un-letterbox
class LetterboxResult {
  final Float32List
      inputTensor; // flattened [H, W, 3] = [inputSize*inputSize*3]
  final double scale; // tỉ lệ scale từ ảnh đã xoay → inputSize×inputSize
  final double padLeft; // pixel padding bên trái (normalized 0→1)
  final double padTop; // pixel padding phía trên (normalized 0→1)
  final int origWidth; // width ảnh ĐÃ XOÁ (sau rotate, trước letterbox)
  final int origHeight;

  const LetterboxResult({
    required this.inputTensor,
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.origWidth,
    required this.origHeight,
  });
}

class ImageConverter {
  ImageConverter._();
  static LetterboxResult yuvToLetterboxedFloat32({
    required List<Uint8List> planes,
    required List<int> rowStrides,
    required List<int> pixelStrides,
    required int srcWidth, // camera frame width (landscape)
    required int srcHeight, // camera frame height (landscape)
    required int inputSize, // 640
    required int rotationDegrees, // 90, 180, 270 (or 0)
    Float32List? reuseBuffer, // reuse từ frame trước
  }) {
    // ── 1. Tính kích thước sau khi xoay ───────────────────────────────────
    final bool swapDims = rotationDegrees == 90 || rotationDegrees == 270;
    final int rotW = swapDims ? srcHeight : srcWidth;
    final int rotH = swapDims ? srcWidth : srcHeight;

    // ── 2. Letterbox geometry ──────────────────────────────────────────────
    final double scale = inputSize / (rotW > rotH ? rotW : rotH);
    final int scaledW = (rotW * scale).round().clamp(1, inputSize);
    final int scaledH = (rotH * scale).round().clamp(1, inputSize);
    final int padL = (inputSize - scaledW) ~/ 2;
    final int padT = (inputSize - scaledH) ~/ 2;

    // ── 3. Alloc / reuse output buffer ────────────────────────────────────
    final int tensorLen = inputSize * inputSize * 3;
    final Float32List tensor =
        (reuseBuffer != null && reuseBuffer.length == tensorLen)
            ? reuseBuffer
            : Float32List(tensorLen);

    // ── 4. YUV plane pointers ──────────────────────────────────────────────
    final Uint8List yPlane = planes[0];
    final Uint8List uPlane = planes[1];
    final Uint8List vPlane = planes[2];
    final int yStride = rowStrides[0];
    final int uvStride = rowStrides[1];
    final int uvPixStride = pixelStrides[1];
    final bool isPlanar =
        pixelStrides[1] == 1; // true = I420, false = NV12/NV21

    // ── 5. Single-pass loop ────────────────────────────────────────────────
    // Mỗi pixel đầu ra (ox, oy) trong 640×640:
    //   → tính toạ độ trong rotated image
    //   → inverse-rotate về original YUV space
    //   → tra bảng YUV, convert RGB, normalize → tensor

    const double gray = 114.0 / 255.0; // padding YOLO standard
    int outIdx = 0;

    for (int oy = 0; oy < inputSize; oy++) {
      for (int ox = 0; ox < inputSize; ox++) {
        // Trong vùng padding → xám YOLO
        final int lx = ox - padL;
        final int ly = oy - padT;

        if (lx < 0 || lx >= scaledW || ly < 0 || ly >= scaledH) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
          outIdx += 3;
          continue;
        }

        // Back-project về toạ độ rotated image [0..rotW) × [0..rotH)
        // Dùng round() giống copyResize linear để nhất quán
        final int rx = ((lx / scale) + 0.5).toInt().clamp(0, rotW - 1);
        final int ry = ((ly / scale) + 0.5).toInt().clamp(0, rotH - 1);

        // Inverse-rotate → original sensor coords (srcX, srcY)
        int srcX, srcY;
        switch (rotationDegrees) {
          case 90: // CW 90: rotated(x,y) = (srcH-1-srcY, srcX) → inv: srcX=ry, srcY=srcH-1-rx
            srcX = ry;
            srcY = srcHeight - 1 - rx;
            break;
          case 270: // CW 270 (= CCW 90): rotated(x,y) = (srcY, srcW-1-srcX) → inv: srcX=srcW-1-ry, srcY=rx
            srcX = srcWidth - 1 - ry;
            srcY = rx;
            break;
          case 180:
            srcX = srcWidth - 1 - rx;
            srcY = srcHeight - 1 - ry;
            break;
          default: // 0°
            srcX = rx;
            srcY = ry;
        }

        // YUV lookup
        final int yIdx = srcY * yStride + srcX;
        final int uvRow = srcY ~/ 2;
        final int uvCol = srcX ~/ 2;
        final int uvIdx = isPlanar
            ? uvRow * uvStride + uvCol // I420 planar
            : uvRow * uvStride + uvCol * uvPixStride; // NV12/NV21 interleaved

        // Bounds check (thiết bị lạ có stride khác nhau)
        if (yIdx >= yPlane.length ||
            uvIdx >= uPlane.length ||
            uvIdx >= vPlane.length) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
          outIdx += 3;
          continue;
        }

        final int yy = yPlane[yIdx];
        final int uu = uPlane[uvIdx] - 128;
        final int vv = vPlane[uvIdx] - 128;

        // BT.601 YCbCr → RGB, clamp, normalize [0,1]
        tensor[outIdx] = (yy + 1.402 * vv).clamp(0, 255) / 255.0;
        tensor[outIdx + 1] =
            (yy - 0.344136 * uu - 0.714136 * vv).clamp(0, 255) / 255.0;
        tensor[outIdx + 2] = (yy + 1.772 * uu).clamp(0, 255) / 255.0;
        outIdx += 3;
      }
    }

    return LetterboxResult(
      inputTensor: tensor,
      scale: scale,
      padLeft: padL / inputSize,
      padTop: padT / inputSize,
      origWidth: rotW,
      origHeight: rotH,
    );
  }

  static LetterboxResult letterboxAndNormalize(
    img.Image image,
    int inputSize,
  ) {
    final scale =
        inputSize / (image.width > image.height ? image.width : image.height);
    final scaledW = (image.width * scale).round().clamp(1, inputSize);
    final scaledH = (image.height * scale).round().clamp(1, inputSize);
    final padL = (inputSize - scaledW) ~/ 2;
    final padT = (inputSize - scaledH) ~/ 2;
    final resized = img.copyResize(image, width: scaledW, height: scaledH);
    final tensor = Float32List(inputSize * inputSize * 3);
    const gray = 114.0 / 255.0;

    int outIdx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final rx = x - padL;
        final ry = y - padT;
        if (rx < 0 || ry < 0 || rx >= scaledW || ry >= scaledH) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
        } else {
          final pixel = resized.getPixel(rx, ry);
          tensor[outIdx] = pixel.r / 255.0;
          tensor[outIdx + 1] = pixel.g / 255.0;
          tensor[outIdx + 2] = pixel.b / 255.0;
        }
        outIdx += 3;
      }
    }

    return LetterboxResult(
      inputTensor: tensor,
      scale: scale,
      padLeft: padL / inputSize,
      padTop: padT / inputSize,
      origWidth: image.width,
      origHeight: image.height,
    );
  }

  // ── Legacy: YUV420 → img.Image (giữ lại để tương thích nếu cần) ─────────
  // Không dùng trong pipeline chính nữa — chỉ dùng nếu cần debug snapshot

  static img.Image convertYuv420(
    List<Uint8List> planes,
    List<int> rowStrides,
    List<int> pixelStrides,
    int width,
    int height,
  ) {
    final isPlanar = pixelStrides[1] == 1;
    return isPlanar
        ? _convertPlanar(planes, rowStrides, width, height)
        : _convertSemiPlanar(planes, rowStrides, pixelStrides, width, height);
  }

  static img.Image _convertPlanar(
    List<Uint8List> planes,
    List<int> strides,
    int w,
    int h,
  ) {
    final rgb = Uint8List(w * h * 3);
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yStr = strides[0];
    final uvStr = strides[1];
    int out = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * yStr + x;
        final uvIndex = (y ~/ 2) * uvStr + (x ~/ 2);

        if (yIndex >= yPlane.length ||
            uvIndex >= uPlane.length ||
            uvIndex >= vPlane.length) {
          rgb[out++] = 114;
          rgb[out++] = 114;
          rgb[out++] = 114;
          continue;
        }

        final yy = yPlane[yIndex];
        final uu = uPlane[uvIndex] - 128;
        final vv = vPlane[uvIndex] - 128;
        rgb[out++] = (yy + 1.402 * vv).round().clamp(0, 255);
        rgb[out++] = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        rgb[out++] = (yy + 1.772 * uu).round().clamp(0, 255);
      }
    }
    return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgb.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb);
  }

  // file: lib/core/utils/image_converter.dart
// Chỉ sửa phần _convertSemiPlanar — toàn bộ phần còn lại giữ nguyên

  static img.Image _convertSemiPlanar(
    List<Uint8List> planes,
    List<int> rowStrides,
    List<int> pixelStrides,
    int w,
    int h,
  ) {
    final rgb = Uint8List(w * h * 3);
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    // Bug 19 FIX: Dùng rowStrides[0] cho Y plane thay vì width
    // Thiết bị có padded stride (e.g. 768 cho width=720) sẽ bị diagonal shear
    // nếu dùng y * w + x
    final yStr = rowStrides[0]; // ← FIX: was hardcoded to w
    final uvStr = rowStrides[1];
    final uvPxStr = pixelStrides[1];
    int out = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * yStr + x; // Bug 19 FIX: yStr not w
        final uvIndex = (y ~/ 2) * uvStr + (x ~/ 2) * uvPxStr;

        if (yIndex >= yPlane.length ||
            uvIndex >= uPlane.length ||
            uvIndex >= vPlane.length) {
          rgb[out++] = 114;
          rgb[out++] = 114;
          rgb[out++] = 114;
          continue;
        }

        final yy = yPlane[yIndex];
        final uu = uPlane[uvIndex] - 128;
        final vv = vPlane[uvIndex] - 128;
        rgb[out++] = (yy + 1.402 * vv).round().clamp(0, 255);
        rgb[out++] = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        rgb[out++] = (yy + 1.772 * uu).round().clamp(0, 255);
      }
    }

    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
  }

  // ── Un-letterbox: model output box → normalized original image coords ──────
  static ({double left, double top, double width, double height})
      unLetterboxBox({
    required double cx,
    required double cy,
    required double bw,
    required double bh,
    required double padLeft, // từ LetterboxResult (normalized)
    required double padTop,
    required double scale,
    required int origWidth,
    required int origHeight,
    required int inputSize,
  }) {
    final cxPx = cx * inputSize;
    final cyPx = cy * inputSize;
    final wPx = bw * inputSize;
    final hPx = bh * inputSize;
    final padLPx = padLeft * inputSize;
    final padTPx = padTop * inputSize;

    final x1 = (cxPx - wPx / 2 - padLPx) / scale;
    final y1 = (cyPx - hPx / 2 - padTPx) / scale;
    final w = wPx / scale;
    final h = hPx / scale;

    return (
      left: (x1 / origWidth).clamp(0.0, 1.0),
      top: (y1 / origHeight).clamp(0.0, 1.0),
      width: (w / origWidth).clamp(0.0, 1.0),
      height: (h / origHeight).clamp(0.0, 1.0),
    );
  }
}
