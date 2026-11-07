import 'package:flutter_test/flutter_test.dart';
import 'package:mwomeogeo/models.dart';

MealPost post(String id, String user, int minute) => MealPost(
  id: id,
  author: user,
  authorId: user,
  photo: 'cloud:photo',
  meal: 0,
  date: DateTime(2026, 11, 7, 8, minute),
  tableIds: ['table'],
);
void main() {
  test('capture time boundaries and gaps', () {
    for (final row in [
      (5, 0, 0),
      (10, 0, 0),
      (11, 0, 1),
      (16, 0, 1),
      (17, 0, 2),
      (22, 0, 2),
    ]) {
      expect(mealAtCaptureTime(DateTime(2026, 11, 7, row.$1, row.$2)), row.$3);
    }
    for (final row in [(4, 59), (10, 1), (16, 1), (22, 1), (0, 0)]) {
      expect(mealAtCaptureTime(DateTime(2026, 11, 7, row.$1, row.$2)), isNull);
    }
  });
  test(
    'the same member keeps their seat regardless of upload order or day',
    () {
      final left = post('left', 'owner', 40);
      final right = post('right', 'guest', 10);
      expect(fixedMealRows([right, left], ['owner', 'guest']).single, [
        left,
        right,
      ]);
      expect(fixedMealRows([left, right], ['owner', 'guest']).single, [
        left,
        right,
      ]);
      expect(fixedMealRows([right], ['owner', 'guest']).single, [null, right]);
      expect(fixedMealRows([left], ['owner', 'guest']).single, [left, null]);
    },
  );
  test(
    'multiple posts by one member stay in their column; no records disappear',
    () {
      final a = post('a', 'owner', 40), b = post('b', 'owner', 10);
      final c = post('c', 'guest', 20), d = post('d', 'third', 30);
      final rows = fixedMealRows([b, d, c, a], ['owner', 'guest', 'third']);
      expect(rows, [
        [a, c],
        [b, null],
        [d, null],
      ]);
      expect(rows.expand((row) => row).whereType<MealPost>().length, 4);
    },
  );
}
