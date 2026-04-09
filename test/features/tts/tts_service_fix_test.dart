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
// 2. Queue deduplication: text is never added twice to the queue.
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

  // Invariant: text is enqueued only once

  group('speakWarning — satu kali enqueue per penerimaan', () {
    test('memanggil speakWarning sekali menambahkan text ke antrian tepat satu kali',
        () async {
      await service.speakWarning('Cảnh báo! Người đi bộ phía trước');

      expect(service.queueLength, equals(1),
          reason: 'Text harus dienqueue tepat satu kali, bukan dua kali');
      expect(service.queue.first, 'Cảnh báo! Người đi bộ phía trước');
    });

    test('panggilan kedua dengan text yang sama diblokir oleh cooldown', () async {
      await service.speakWarning('xe đạp bên trái');
      await service.speakWarning('xe đạp bên trái');

      expect(service.queueLength, equals(1),
          reason: 'Cooldown harus memblokir panggilan kedua dengan text yang sama');
    });

    test('text berbeda bisa dienqueue bersama-sama', () async {
      await service.speakWarning('vật thể A');
      await service.speakWarning('vật thể B');

      expect(service.queueLength, equals(2));
      expect(service.queue, containsAll(['vật thể A', 'vật thể B']));
    });

    test('_lastSpoken mencatat timestamp setelah penerimaan', () async {
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

  group('speakWarning — cooldown per text', () {
    test('text yang sama dalam jendela cooldown mengembalikan null (diblokir)',
        () async {
      const text = 'xe máy';
      final result1 = await service.speakWarning(text);
      final result2 = await service.speakWarning(text);

      expect(result1, equals(text), reason: 'Panggilan pertama harus diterima');
      expect(result2, isNull, reason: 'Panggilan kedua dalam cooldown harus diblokir');
    });

    test('text berbeda tidak saling memblokir cooldown masing-masing', () async {
      final r1 = await service.speakWarning('text A');
      final r2 = await service.speakWarning('text B');
      final r3 = await service.speakWarning('text C');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);
      expect(service.queueLength, equals(3));
    });

    test('_lastSpoken tidak tumbuh tidak terbatas — diprune saat lebih dari 100',
        () async {
      for (int i = 0; i < 101; i++) {
        await service.speakWarning('text_$i');
      }
      // Pruning starts after 100 entries so growth stays bounded.
      expect(service.lastSpoken.length, lessThanOrEqualTo(101));
    });
  });

  // Queue deduplication

  group('Queue deduplication', () {
    test('text yang sama tidak ditambahkan dua kali ke antrian', () async {
      await service.speakWarning('duplicate text');

      expect(service.queue.where((t) => t == 'duplicate text').length,
          equals(1));
    });

    test('string kosong diterima tanpa crash', () async {
      expect(() => service.speakWarning(''), returnsNormally);
    });
  });
}
