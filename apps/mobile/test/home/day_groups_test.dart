import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/day_groups.dart';

import 'fixtures.dart';

void main() {
  group('groupByDay', () {
    test(
      'puts today first, then the past (newest first), then the upcoming days (nearest first)',
      () {
        // The API sends the month newest first.
        final items = [
          tx('internet', '2026-10-28', -3990, status: 'pending'),
          tx('streaming', '2026-10-23', -799, status: 'pending'),
          tx('coffee', '2026-10-21', -120),
          tx('lunch', '2026-10-21', -1240),
          tx('bus', '2026-10-08', -200),
          tx('salary', '2026-10-01', 300000),
        ];
        final groups = groupByDay(items, '2026-10-21');
        expect(groups.map((g) => (g.date, g.when)).toList(), [
          ('2026-10-21', DayWhen.today),
          ('2026-10-08', DayWhen.past),
          ('2026-10-01', DayWhen.past),
          ('2026-10-23', DayWhen.upcoming),
          ('2026-10-28', DayWhen.upcoming),
        ]);
        expect(groups[0].items.map((t) => t.id).toList(), ['coffee', 'lunch']);
        expect(groups[0].total, -1360);
        expect(groups[2].total, 300000);
      },
    );

    test(
      'keeps the pending days still to come after yesterday, not between today and yesterday',
      () {
        final items = [
          tx('internet', '2026-11-28', -3990, status: 'pending'),
          tx('plan', '2026-11-26', -1039, status: 'pending'),
          tx('gym', '2026-11-02', -3200),
          tx('uber', '2026-11-02', -316),
          tx('sushi', '2026-11-01', -1093),
        ];
        final groups = groupByDay(items, '2026-11-02');
        expect(groups.map((g) => (g.date, g.when, g.total)).toList(), [
          ('2026-11-02', DayWhen.today, -3516),
          ('2026-11-01', DayWhen.yesterday, -1093),
          ('2026-11-26', DayWhen.upcoming, -1039),
          ('2026-11-28', DayWhen.upcoming, -3990),
        ]);
      },
    );

    test('marks the day before today as yesterday', () {
      final groups = groupByDay([
        tx('a', '2026-10-20', -1),
        tx('b', '2026-10-19', -1),
      ], '2026-10-21');
      expect(groups.map((g) => g.when).toList(), [DayWhen.yesterday, DayWhen.past]);
    });

    test('works across a month boundary for yesterday', () {
      expect(groupByDay([tx('a', '2026-09-30', -1)], '2026-10-01').first.when, DayWhen.yesterday);
    });

    test('is empty without transactions', () {
      expect(groupByDay([], '2026-10-21'), isEmpty);
    });
  });

  group('groupNewestFirst', () {
    test('keeps the API order: a newer upcoming day stays on top, nothing moves to the bottom', () {
      final items = [
        tx('internet', '2026-10-28', -3990, status: 'pending'),
        tx('lunch', '2026-10-21', -1240),
        tx('coffee', '2026-10-21', -120),
        tx('bus', '2026-10-20', -200),
        tx('old', '2026-10-08', -200),
      ];
      final groups = groupNewestFirst(items, '2026-10-21');
      expect(groups.map((g) => (g.date, g.when)).toList(), [
        ('2026-10-28', DayWhen.upcoming),
        ('2026-10-21', DayWhen.today),
        ('2026-10-20', DayWhen.yesterday),
        ('2026-10-08', DayWhen.past),
      ]);
      expect(groups[1].items.map((t) => t.id).toList(), ['lunch', 'coffee']);
      expect(groups[1].total, -1360);
    });

    test('is empty for no items', () {
      expect(groupNewestFirst(const [], '2026-10-21'), isEmpty);
    });
  });
}
