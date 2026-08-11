import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/screens/count_game_screen.dart';

void main() {
  test('rows always add up to the count', () {
    final rng = math.Random(1);
    for (var n = 1; n <= 10; n++) {
      for (var i = 0; i < 50; i++) {
        final rows = countRows(n, rng);
        expect(rows.reduce((a, b) => a + b), n, reason: 'count $n');
        expect(rows.length, lessThanOrEqualTo(3), reason: 'count $n');
        expect(rows.every((r) => r >= 1 && r <= 5), isTrue, reason: 'count $n');
      }
    }
  });

  test('a count has more than one shape, so the shape cannot be learned', () {
    final rng = math.Random(7);
    for (final n in [3, 6, 10]) {
      final shapes = <String>{};
      for (var i = 0; i < 200; i++) {
        shapes.add(countRows(n, rng).join('-'));
      }
      expect(
        shapes.length,
        greaterThan(1),
        reason: 'count $n always looks the same: ${shapes.first}',
      );
    }
  });

  test('the arrangements the user asked for are all possible', () {
    final rng = math.Random(3);
    Set<String> shapesFor(int n) {
      final out = <String>{};
      for (var i = 0; i < 400; i++) {
        out.add(countRows(n, rng).join('-'));
      }
      return out;
    }

    expect(shapesFor(6), containsAll(['5-1', '4-2', '3-3']));
    expect(shapesFor(3), containsAll(['3', '2-1']));
    expect(shapesFor(10), containsAll(['5-5', '5-4-1', '4-4-2']));
  });

  test('at most one row holds a single animal', () {
    // 5-4-1 ends naturally; 4-1-1 reads as scattered rather than arranged.
    final rng = math.Random(11);
    for (var n = 1; n <= 10; n++) {
      for (var i = 0; i < 100; i++) {
        final rows = countRows(n, rng);
        expect(
          rows.where((r) => r == 1).length,
          lessThanOrEqualTo(1),
          reason: '$n gave ${rows.join("-")}',
        );
      }
    }
  });

  test('a lone animal never sits alone on the top row', () {
    final rng = math.Random(5);
    for (var n = 2; n <= 10; n++) {
      for (var i = 0; i < 100; i++) {
        expect(countRows(n, rng).first, greaterThanOrEqualTo(2), reason: '$n');
      }
    }
  });
}
