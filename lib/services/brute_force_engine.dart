import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

enum CharsetPreset {
  digits(
    label: 'Chỉ số (0–9)',
    chars: '0123456789',
  ),
  lowerAndDigits(
    label: 'Chữ thường + số',
    chars: 'abcdefghijklmnopqrstuvwxyz0123456789',
  ),
  full(
    label: 'Đầy đủ (như bản Python gốc)',
    chars:
        'abcdefghijklmnopqrstuvwxyz1234567890!§\$%&/()=?-_ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  );

  const CharsetPreset({
    required this.label,
    required this.chars,
  });

  final String label;
  final String chars;
}

class BruteForceProgress {
  const BruteForceProgress({
    required this.attempts,
    required this.currentGuess,
    required this.currentLength,
    required this.elapsedMs,
    this.isDone = false,
    this.found = false,
    this.foundPassword,
    this.errorMessage,
  });

  final int attempts;
  final String currentGuess;
  final int currentLength;
  final int elapsedMs;
  final bool isDone;
  final bool found;
  final String? foundPassword;
  final String? errorMessage;

  double get elapsedSeconds => elapsedMs / 1000.0;

  double get attemptsPerSecond {
    if (elapsedMs <= 0) return attempts.toDouble();
    return attempts / (elapsedMs / 1000.0);
  }
}

class BruteForceSession {
  BruteForceSession._({
    required this.stream,
    required VoidCallback onCancel,
  }) : _onCancel = onCancel;

  final Stream<BruteForceProgress> stream;
  final VoidCallback _onCancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}

typedef VoidCallback = void Function();

class BruteForceEngine {
  BruteForceEngine._();

  static const int defaultMaxLength = 12;

  /// Returns characters in [target] that are missing from [charset].
  static List<String> findUnsupportedCharacters(String target, String charset) {
    final allowed = charset.codeUnits.toSet();
    final missing = <String>{};
    for (final unit in target.codeUnits) {
      if (!allowed.contains(unit)) {
        missing.add(String.fromCharCode(unit));
      }
    }
    return missing.toList(growable: false);
  }

  /// Estimates total keyspace combinations up to [passwordLength] for [charsetLength].
  static double estimateCombinations(int charsetLength, int passwordLength) {
    if (charsetLength <= 0 || passwordLength <= 0) return 0;
    double total = 0;
    for (int len = 1; len <= passwordLength; len++) {
      total += math.pow(charsetLength, len).toDouble();
    }
    return total;
  }

  /// Synchronous O(1)-RAM odometer search (useful for deterministic unit tests).
  static BruteForceProgress runSync({
    required String target,
    required String charset,
    int maxLength = defaultMaxLength,
    int? maxAttempts,
  }) {
    final stopwatch = Stopwatch()..start();
    final charCodes = charset.codeUnits;
    final targetCodes = target.codeUnits;
    final base = charCodes.length;

    if (targetCodes.isEmpty || base == 0) {
      stopwatch.stop();
      return BruteForceProgress(
        attempts: 0,
        currentGuess: '',
        currentLength: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
        isDone: true,
        found: false,
      );
    }

    int attempts = 0;
    String lastGuess = '';

    for (int len = 1; len <= maxLength; len++) {
      final indices = List<int>.filled(len, 0);
      final buffer = List<int>.filled(len, charCodes[0]);
      final checkLength = len == targetCodes.length;

      while (true) {
        attempts++;

        if (checkLength) {
          var matched = true;
          for (int i = 0; i < len; i++) {
            if (buffer[i] != targetCodes[i]) {
              matched = false;
              break;
            }
          }
          if (matched) {
            stopwatch.stop();
            final foundStr = String.fromCharCodes(buffer);
            return BruteForceProgress(
              attempts: attempts,
              currentGuess: foundStr,
              currentLength: len,
              elapsedMs: stopwatch.elapsedMilliseconds,
              isDone: true,
              found: true,
              foundPassword: foundStr,
            );
          }
        }

        if (maxAttempts != null && attempts >= maxAttempts) {
          stopwatch.stop();
          lastGuess = String.fromCharCodes(buffer);
          return BruteForceProgress(
            attempts: attempts,
            currentGuess: lastGuess,
            currentLength: len,
            elapsedMs: stopwatch.elapsedMilliseconds,
            isDone: true,
            found: false,
          );
        }

        // Advance odometer
        int pos = len - 1;
        while (pos >= 0) {
          final nextIdx = indices[pos] + 1;
          if (nextIdx < base) {
            indices[pos] = nextIdx;
            buffer[pos] = charCodes[nextIdx];
            break;
          } else {
            indices[pos] = 0;
            buffer[pos] = charCodes[0];
            pos--;
          }
        }
        if (pos < 0) {
          lastGuess = String.fromCharCodes(buffer);
          break;
        }
      }
    }

    stopwatch.stop();
    return BruteForceProgress(
      attempts: attempts,
      currentGuess: lastGuess,
      currentLength: maxLength,
      elapsedMs: stopwatch.elapsedMilliseconds,
      isDone: true,
      found: false,
    );
  }

  /// Launches the O(1)-RAM brute-force demo inside a real background [Isolate]
  /// so the UI stays smooth at 60fps and can be stopped immediately.
  static Future<BruteForceSession> startIsolate({
    required String target,
    required String charset,
    int maxLength = defaultMaxLength,
  }) async {
    final receivePort = ReceivePort();
    final controller = StreamController<BruteForceProgress>();
    Isolate? isolate;

    void cleanup() {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      receivePort.close();
      if (!controller.isClosed) {
        controller.close();
      }
    }

    receivePort.listen((dynamic message) {
      if (message is Map<String, Object?>) {
        final progress = BruteForceProgress(
          attempts: message['attempts']! as int,
          currentGuess: message['currentGuess']! as String,
          currentLength: message['currentLength']! as int,
          elapsedMs: message['elapsedMs']! as int,
          isDone: message['isDone']! as bool,
          found: message['found']! as bool,
          foundPassword: message['foundPassword'] as String?,
          errorMessage: message['errorMessage'] as String?,
        );
        if (!controller.isClosed) {
          controller.add(progress);
        }
        if (progress.isDone) {
          cleanup();
        }
      }
    });

    try {
      isolate = await Isolate.spawn<_IsolateRequest>(
        _isolateEntryPoint,
        _IsolateRequest(
          sendPort: receivePort.sendPort,
          target: target,
          charset: charset,
          maxLength: maxLength,
        ),
      );
    } catch (error) {
      if (!controller.isClosed) {
        controller.add(
          BruteForceProgress(
            attempts: 0,
            currentGuess: '',
            currentLength: 0,
            elapsedMs: 0,
            isDone: true,
            found: false,
            errorMessage: 'Không thể khởi chạy tiến trình nền: $error',
          ),
        );
      }
      cleanup();
    }

    return BruteForceSession._(
      stream: controller.stream,
      onCancel: cleanup,
    );
  }

  static void _isolateEntryPoint(_IsolateRequest req) {
    final stopwatch = Stopwatch()..start();
    final charCodes = req.charset.codeUnits;
    final targetCodes = req.target.codeUnits;
    final base = charCodes.length;
    final sendPort = req.sendPort;

    if (targetCodes.isEmpty || base == 0) {
      stopwatch.stop();
      sendPort.send(<String, Object?>{
        'attempts': 0,
        'currentGuess': '',
        'currentLength': 0,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'isDone': true,
        'found': false,
        'foundPassword': null,
        'errorMessage': null,
      });
      return;
    }

    int attempts = 0;
    int lastReportMs = 0;

    for (int len = 1; len <= req.maxLength; len++) {
      final indices = List<int>.filled(len, 0);
      final buffer = List<int>.filled(len, charCodes[0]);
      final checkLength = len == targetCodes.length;

      while (true) {
        attempts++;

        if (checkLength) {
          var matched = true;
          for (int i = 0; i < len; i++) {
            if (buffer[i] != targetCodes[i]) {
              matched = false;
              break;
            }
          }
          if (matched) {
            stopwatch.stop();
            final foundStr = String.fromCharCodes(buffer);
            sendPort.send(<String, Object?>{
              'attempts': attempts,
              'currentGuess': foundStr,
              'currentLength': len,
              'elapsedMs': stopwatch.elapsedMilliseconds,
              'isDone': true,
              'found': true,
              'foundPassword': foundStr,
              'errorMessage': null,
            });
            return;
          }
        }

        if (attempts % 50000 == 0) {
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed - lastReportMs >= 80) {
            lastReportMs = elapsed;
            sendPort.send(<String, Object?>{
              'attempts': attempts,
              'currentGuess': String.fromCharCodes(buffer),
              'currentLength': len,
              'elapsedMs': elapsed,
              'isDone': false,
              'found': false,
              'foundPassword': null,
              'errorMessage': null,
            });
          }
        }

        int pos = len - 1;
        while (pos >= 0) {
          final nextIdx = indices[pos] + 1;
          if (nextIdx < base) {
            indices[pos] = nextIdx;
            buffer[pos] = charCodes[nextIdx];
            break;
          } else {
            indices[pos] = 0;
            buffer[pos] = charCodes[0];
            pos--;
          }
        }
        if (pos < 0) break;
      }
    }

    stopwatch.stop();
    sendPort.send(<String, Object?>{
      'attempts': attempts,
      'currentGuess': '',
      'currentLength': req.maxLength,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'isDone': true,
      'found': false,
      'foundPassword': null,
      'errorMessage': null,
    });
  }
}

class _IsolateRequest {
  const _IsolateRequest({
    required this.sendPort,
    required this.target,
    required this.charset,
    required this.maxLength,
  });

  final SendPort sendPort;
  final String target;
  final String charset;
  final int maxLength;
}
