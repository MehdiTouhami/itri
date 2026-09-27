import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/domain/activity.dart';
import 'package:itri_fitness/domain/analysis.dart';
import 'package:itri_fitness/domain/athlete.dart';
import 'package:itri_fitness/domain/efforts.dart';
import 'package:itri_fitness/domain/hr_zones.dart';
import 'package:itri_fitness/domain/sample.dart';
import 'package:itri_fitness/domain/sport.dart';
import 'package:itri_fitness/domain/sport_stats.dart';

void main() {
  const athlete = Athlete(maxHr: 200, restHr: 50);
  final zones = HrZoneModel.forAthlete(athlete); // Z4 starts at 160

  /// Rally-like session: 20 s at 170 then 100 s at 130, repeated.
  List<Sample> rallies(int n) => [
        for (var t = 0; t < n * 120; t += 5) Sample(t: t, heartRate: t % 120 < 20 ? 170 : 130),
      ];

  Activity session(Sport sport, DateTime start, List<Sample> s) => Activity.fromSamples(
        id: start.millisecondsSinceEpoch,
        sport: sport,
        name: sport.label,
        start: start,
        locality: '',
        samples: s,
        weightKg: 80,
        ageYears: 23,
      );

  group('Efforts', () {
    test('finds each burst and measures the drop a minute after its peak', () {
      final e = effortsOf(rallies(5), 160);
      expect(e.length, 5);
      expect(e.first.seconds, 15); // samples at 0,5,10,15
      expect(e.first.peakHr, 170);
      expect(e.first.recovery, 40); // 170 → 130
    });

    test('ignores blips shorter than the minimum', () {
      final s = [for (var t = 0; t < 120; t += 5) Sample(t: t, heartRate: t == 50 ? 175 : 120)];
      expect(effortsOf(s, 160), isEmpty);
    });

    test('recovery is null when the session ends first', () {
      final s = [for (var t = 0; t <= 30; t += 5) Sample(t: t, heartRate: 170)];
      expect(effortsOf(s, 160).single.recovery, isNull);
      expect(meanRecovery(effortsOf(s, 160)), isNull);
    });
  });

  group('Sport summaries', () {
    final list = [
      for (var i = 0; i < 12; i++)
        ActivityAnalysis.of(session(Sport.squash, DateTime(2026, 1, 1 + i * 3, 19), rallies(20)), athlete, zones),
      ActivityAnalysis.of(session(Sport.strength, DateTime(2026, 1, 2, 18), rallies(1)), athlete, zones),
    ];
    final all = sportSummaries(list);

    test('groups by sport, most time first', () {
      expect(all.map((s) => s.sport), [Sport.squash, Sport.strength]);
      expect(all.first.count, 12);
      expect(all.first.hours, closeTo(12 * 20 * 120 / 3600, 0.1));
    });

    test('efforts and recovery add up across sessions', () {
      final sq = all.first;
      expect(sq.efforts, 12 * 20);
      expect(sq.effortsPerHour, closeTo(30, 0.5));
      expect(sq.recovery, closeTo(40, 0.01));
      expect(sq.byDaypart, [0, 0, 12]);
      expect(sq.byWeekday.reduce((a, b) => a + b), 12);
    });

    test('months include empty gaps', () {
      final s = SportSummary(Sport.tennis, [
        ActivityAnalysis.of(session(Sport.tennis, DateTime(2026, 1, 5), rallies(2)), athlete, zones),
        ActivityAnalysis.of(session(Sport.tennis, DateTime(2026, 3, 5), rallies(2)), athlete, zones),
      ]);
      expect(s.byMonth.map((m) => m.$2), [1, 0, 1]);
    });
  });

  group('Trends', () {
    test('rolling mean skips missing values', () {
      expect(rollingMean([null, 2, 4, null, 6], 2), [null, 2, 3, 3, 5]);
    });

    test('first vs last needs two full windows', () {
      expect(firstVsLast([1, 2, 3, 4, 5, 6, 7, 8, 9]), isNull);
      final r = firstVsLast([for (var i = 1; i <= 10; i++) i.toDouble()])!;
      expect(r.from, 3);
      expect(r.to, 8);
    });
  });
}
