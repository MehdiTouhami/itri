import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/core/format.dart';
import 'package:itri_fitness/data/synthetic/synthetic_generator.dart';
import 'package:itri_fitness/domain/aggregates.dart';
import 'package:itri_fitness/domain/analysis.dart';
import 'package:itri_fitness/domain/athlete.dart';
import 'package:itri_fitness/domain/hr_zones.dart';
import 'package:itri_fitness/domain/sample.dart';
import 'package:itri_fitness/domain/sport.dart';
import 'package:itri_fitness/domain/training_load.dart';

void main() {
  const athlete = Athlete(maxHr: 200, restHr: 50);
  final today = DateTime(2026, 9, 24);

  group('HR zones', () {
    final z = HrZoneModel.percentOfMax(200);

    test('bounds follow 50/60/70/80/90 % of max', () {
      expect([for (final x in z.zones) x.lower], [100, 120, 140, 160, 180]);
      expect(z.zones.last.upper, isNull);
    });

    test('indexOf is inclusive at the lower edge', () {
      expect(z.indexOf(80), 0); // below Z1 counts as Z1
      expect(z.indexOf(139), 1);
      expect(z.indexOf(140), 2);
      expect(z.indexOf(199), 4);
    });

    test('time in zones sums to duration', () {
      final s = [for (var t = 0; t <= 600; t += 5) Sample(t: t, heartRate: 100 + t ~/ 10)];
      final secs = z.timeInZones(s);
      expect(secs.reduce((a, b) => a + b), 600);
    });
  });

  group('Training load', () {
    test('TRIMP grows faster than linearly with intensity', () {
      List<Sample> steady(int hr) => [for (var t = 0; t <= 3600; t += 5) Sample(t: t, heartRate: hr)];
      final easy = trimp(steady(120), athlete);
      final hard = trimp(steady(170), athlete);
      final hrrRatio = (170 - 50) / (120 - 50);
      expect(hard / easy, greaterThan(hrrRatio));
    });

    test('rest days reduce fatigue faster than fitness', () {
      final from = DateTime(2026, 1, 1);
      final daily = {for (var i = 0; i < 40; i++) addDays(from, i): 100.0};
      final s = loadSeries(daily, from, addDays(from, 49));
      final lastTraining = s[39], afterRest = s.last;
      expect(afterRest.fatigue, lessThan(lastTraining.fatigue * 0.3));
      expect(afterRest.fitness, greaterThan(lastTraining.fitness * 0.7));
      expect(afterRest.form, greaterThan(0));
      expect(afterRest.state, FormStatus.fresh);
    });
  });

  group('Splits', () {
    test('interpolates crossings and keeps a partial last split', () {
      // 3.5 km at a constant 4 m/s.
      final s = [for (var t = 0; t <= 875; t += 5) Sample(t: t, distanceM: t * 4.0, heartRate: 150, altitudeM: 10)];
      final sp = splitsOf(s);
      expect(sp.length, 4);
      expect(sp.first.seconds, closeTo(250, 0.01));
      expect(sp.last.distanceM, closeTo(500, 0.01));
      expect(sp.last.pacePerUnit(1000), closeTo(250, 0.01));
    });
  });

  group('Synthetic generator', () {
    final a = SyntheticGenerator(today: today).generate();

    test('is deterministic for a seed', () {
      final b = SyntheticGenerator(today: today).generate();
      expect(b.length, a.length);
      expect(b[10].distanceM, a[10].distanceM);
      expect(b[10].avgHr, a[10].avgHr);
    });

    test('covers ~6 months with a realistic weekly volume', () {
      expect(a.length, inInclusiveRange(100, 190));
      expect(a.first.day.isBefore(DateTime(2026, 4, 5)), isTrue);
      expect(a.map((x) => x.sport).toSet(), containsAll([Sport.run, Sport.ride, Sport.walk, Sport.strength]));
    });

    test('summaries are physiologically plausible', () {
      for (final x in a) {
        expect(x.maxHr, lessThanOrEqualTo(const Athlete().maxHr));
        expect(x.avgHr, greaterThan(const Athlete().restHr));
        if (x.sport == Sport.run) {
          final paceMinPerKm = 1000 / x.avgSpeedMs / 60;
          expect(paceMinPerKm, inInclusiveRange(3.8, 7.5));
        }
        if (x.sport == Sport.strength) expect(x.distanceM, 0);
      }
    });

    test('weekly totals bucket every recent session', () {
      final list = [for (final x in a) ActivityAnalysis.of(x, athlete, HrZoneModel.forAthlete(athlete))];
      final weeks = weeklyTotals(list, today, 12);
      expect(weeks.length, 12);
      final inRange = list.where((x) => !x.activity.day.isBefore(weeks.first.monday)).length;
      expect(weeks.fold<int>(0, (s, w) => s + w.sessions), inRange);
    });
  });

  group('Format', () {
    test('duration', () {
      expect(Fmt.duration(59), '0:59');
      expect(Fmt.duration(3909), '1:05:09');
    });

    test('pace rounds without producing :60', () {
      expect(Fmt.pace(1000 / 299.8, Units.metric), '5:00');
      expect(Fmt.pace(0.1, Units.metric), '—');
    });

    test('signed uses a real minus sign', () {
      expect(Fmt.signed(-4), '−4');
      expect(Fmt.signed(3), '+3');
    });
  });
}
