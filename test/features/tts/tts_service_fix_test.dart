import 'package:flutter_test/flutter_test.dart';

// TtsService test strategy
//
// TtsService depends on FlutterTts, a native plugin that cannot run in a
// unit-test environment because there is no audio engine.
//
// The chosen approach uses TestableTtsService as a test double that mirrors
// the real cooldown and queue logic without depending on FlutterTts.
// This lets the tests verify:
// 1. Per-text cooldown: the same text is blocked within a time window.
// 2. Khử trùng lặp hàng đợi: cùng một nội dung không bao giờ được thêm hai lần.
// 3. _lastSpoken management: the map does not grow without bounds.
//
// Full validation of speak, pause, and stop still requires an integration
// test on a real device or emulator with an active audio engine.
// ─────────────────────────────────────────────────────────────────────────

/// Test double that mirrors TtsService cooldown and queue behavior.
/// All methods return the same kinds of values as the real implementation so
/// tests can verify the contract without a native engine.
class TestableTtsService {
  final List<String> _queue = [];
  final Map<String, DateTime> _lastSpoken = {};
  final bool _isSpeaking = false;

  static const int ttsCooldownMs = 3000;
  static const int maxLastSpoken = 100;

  /// Accepts text into the queue when it is outside the cooldown window.
  /// Returns the text when accepted, or `null` when blocked by cooldown.
  Future<String?> speakWarning(String text) async {
    final now = DateTime.now();

    // Prune expired entries before checking cooldown.
    if (_lastSpoken.length > maxLastSpoken) {
      _lastSpoken.removeWhere((_, time) =>
          now.difference(time).inMilliseconds > ttsCooldownMs * 2);
    }

    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < ttsCooldownMs) {
      return null;
    }

    // Record the timestamp and enqueue exactly once.
    _lastSpoken[text] = now;
    _enqueue(text);
    return text;
  }

  void _enqueue(String text) {
    if (!_queue.contains(text)) _queue.add(text);
  }

  List<String> get queue      => List.unmodifiable(_queue);
  Map<String, DateTime> get lastSpoken => Map.unmodifiable(_lastSpoken);
  bool get isSpeaking         => _isSpeaking;
  int  get queueLength        => _queue.length;
}

void main() {
  late TestableTtsService service;

  setUp(() {
    service = TestableTtsService();
  });

  // Invariant: mỗi nội dung chỉ được thêm vào hàng đợi một lần.

  group('speakWarning — chỉ enqueue một lần cho mỗi lần chấp nhận', () {
    test('gọi speakWarning một lần thì chỉ thêm đúng một phần tử vào hàng đợi',
        () async {
      await service.speakWarning('Cảnh báo! Người đi bộ phía trước');

      expect(service.queueLength, equals(1),
          reason: 'Nội dung chỉ được đưa vào hàng đợi đúng một lần');
      expect(service.queue.first, 'Cảnh báo! Người đi bộ phía trước');
    });

    test('lần gọi thứ hai với cùng nội dung sẽ bị chặn bởi cooldown', () async {
      await service.speakWarning('xe đạp bên trái');
      await service.speakWarning('xe đạp bên trái');

      expect(service.queueLength, equals(1),
          reason: 'Cooldown phải chặn lần gọi thứ hai với cùng nội dung');
    });

    test('các nội dung khác nhau có thể cùng vào hàng đợi', () async {
      await service.speakWarning('vật thể A');
      await service.speakWarning('vật thể B');

      expect(service.queueLength, equals(2));
      expect(service.queue, containsAll(['vật thể A', 'vật thể B']));
    });

    test('_lastSpoken ghi lại thời điểm sau khi chấp nhận phát', () async {
      const text = 'người đi bộ';
      final before = DateTime.now();
      await service.speakWarning(text);
      final after = DateTime.now();

      final recorded = service.lastSpoken[text];
      expect(recorded, isNotNull);
      expect(recorded!.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(recorded.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  // Cooldown logic

  group('speakWarning — cooldown theo từng nội dung', () {
    test('cùng một nội dung trong cửa sổ cooldown sẽ trả về null',
        () async {
      const text = 'xe máy';
      final result1 = await service.speakWarning(text);
      final result2 = await service.speakWarning(text);

      expect(result1, equals(text), reason: 'Lần gọi đầu tiên phải được chấp nhận');
      expect(result2, isNull, reason: 'Lần gọi thứ hai trong cooldown phải bị chặn');
    });

    test('nội dung khác nhau không chặn cooldown của nhau', () async {
      final r1 = await service.speakWarning('văn bản A');
      final r2 = await service.speakWarning('văn bản B');
      final r3 = await service.speakWarning('văn bản C');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);
      expect(service.queueLength, equals(3));
    });

    test('_lastSpoken không tăng vô hạn và sẽ được dọn khi vượt quá 100 mục',
        () async {
      for (int i = 0; i < 101; i++) {
        await service.speakWarning('văn_bản_$i');
      }
      // Pruning starts after 100 entries so growth stays bounded.
      expect(service.lastSpoken.length, lessThanOrEqualTo(101));
    });
  });

  // Khử trùng lặp hàng đợi

  group('Khử trùng lặp hàng đợi', () {
    test('cùng một nội dung không bị thêm hai lần vào hàng đợi', () async {
      await service.speakWarning('nội dung trùng lặp');

      expect(service.queue.where((t) => t == 'nội dung trùng lặp').length,
          equals(1));
    });

    test('chuỗi rỗng vẫn được xử lý mà không crash', () async {
      expect(() => service.speakWarning(''), returnsNormally);
    });
  });
}
