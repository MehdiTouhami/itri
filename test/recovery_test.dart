import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/data/garmin/garmin_bundle.dart';
import 'package:itri_fitness/data/synthetic/synthetic_generator.dart';
import 'package:itri_fitness/data/synthetic/synthetic_sleep.dart';
import 'package:itri_fitness/domain/activity.dart';
import 'package:itri_fitness/domain/analysis.dart';
import 'package:itri_fitness/domain/athlete.dart';
import 'package:itri_fitness/domain/facts.dart';
import 'package:itri_fitness/domain/hr_zones.dart';
import 'package:itri_fitness/domain/readiness.dart';
import 'package:itri_fitness/domain/sample.dart';
import 'package:itri_fitness/domain/sleep.dart';
import 'package:itri_fitness/domain/sleep_stats.dart';
import 'package:itri_fitness/domain/sport.dart';
import 'package:itri_fitness/domain/training_load.dart';

SleepNight night(
  DateTime wake, {
  int score = 75,
  int asleepH = 7,
  int bedHour = 23,
  double? hrv = 70.0,
  int? rhr = 52,
}) {
  final start = DateTime(wake.year, wake.month, wake.day - 1, bedHour);
  return SleepNight(
    date: wake,
    start: start,
    end: start.add(Duration(hours: asleepH, minutes: 20)),
    deepS: asleepH * 600,
    lightS: asleepH * 2400,
    remS: asleepH * 600,
    awakeS: 1200,
    score: score,
    hrv: hrv,
    hrvLow: 60.0,
    hrvHigh: 80.0,
    restingHr: rhr,
  );
}

void main() {
  group('Sleep night', () {
    test('bedtime is measured from 18:00 so late nights stay continuous', () {
      expect(night(DateTime(2026, 5, 8), bedHour: 23).bedMinutes, 300);
      final late = night(DateTime(2026, 5, 8), bedHour: 1 + 24);
      expect(late.start!.hour, 1);
      expect(late.bedMinutes, 420);
      expect(clockFromEvening(420), '01:00');
    });

    test('asleep excludes awake time and efficiency stays within 0–1', () {
      final n = night(DateTime(2026, 5, 8));
      expect(n.asleepS, 7 * 3600);
      expect(n.efficiency, inInclusiveRange(0.9, 1.0));
    });

    test('HRV is read against the personal range', () {
      expect(night(DateTime(2026, 5, 8), hrv: 55.0).hrvStatus, HrvStatus.below);
      expect(night(DateTime(2026, 5, 8), hrv: 70.0).hrvStatus, HrvStatus.within);
      expect(night(DateTime(2026, 5, 8), hrv: 90.0).hrvStatus, HrvStatus.above);
      expect(night(DateTime(2026, 5, 8), hrv: null).hrvStatus, isNull);
    });

    test('feedback codes read as plain English', () {
      expect(describeFeedback('NEGATIVE_LONG_BUT_NOT_ENOUGH_REM'), 'Long, but short on REM');
      expect(describeFeedback('POSITIVE_SOMETHING_NEW'), 'Something new');
      expect(describeFeedback(null), '');
    });
  });

  group('Readiness', () {
    DayLoad form(double f) => DayLoad(DateTime(2026, 5, 8), 0, 60, 60 - f, f);

    test('low HRV plus a short night means recover', () {
      final r = Readiness.from(
        night: night(DateTime(2026, 5, 8), hrv: 50.0, asleepH: 5, score: 55),
        restingBaseline: 52.0,
        load: form(0),
      )!;
      expect(r.level, ReadinessLevel.recover);
      expect(r.factors.first.signal, Signal.bad);
    });

    test('good signals across the board means ready', () {
      final r = Readiness.from(
        night: night(DateTime(2026, 5, 8), hrv: 75.0, score: 85, rhr: 49),
        restingBaseline: 52.0,
        load: form(10),
      )!;
      expect(r.level, ReadinessLevel.ready);
    });

    test('no night, no verdict', () {
      expect(Readiness.from(night: null, restingBaseline: null, load: null), isNull);
    });
  });

  group('Recovery data', () {
    final nights = [for (var i = 1; i <= 40; i++) night(DateTime(2026, 4, i), rhr: 50 + i % 3)];
    final r = RecoveryData(nights: nights.reversed.toList());

    test('keeps nights oldest first and finds by date', () {
      expect(r.nights.first.date, DateTime(2026, 4, 1));
      expect(r.byDate(DateTime(2026, 4, 10))?.date, DateTime(2026, 4, 10));
      expect(r.nightFor(DateTime(2026, 6, 1))?.date, DateTime(2026, 5, 10));
      expect(r.window(DateTime(2026, 5, 10), 7).length, 7);
    });

    test('resting baseline averages the days before', () {
      expect(r.restingBaseline(DateTime(2026, 5, 10)), closeTo(51, 0.2));
    });
  });

  group('Training and sleep', () {
    const athlete = Athlete(maxHr: 200, restHr: 50);
    final zones = HrZoneModel.forAthlete(athlete);

    test('groups nights by the day before', () {
      final sessions = [
        for (var i = 1; i <= 20; i += 2)
          ActivityAnalysis.of(
            Activity.fromSamples(
              id: i,
              sport: Sport.tennis,
              name: 'Tennis',
              start: DateTime(2026, 4, i, i.isOdd && i > 10 ? 20 : 10),
              locality: '',
              samples: [for (var t = 0; t <= 3600; t += 5) Sample(t: t, heartRate: 150)],
              weightKg: 80,
              ageYears: 23,
            ),
            athlete,
            zones,
          ),
      ];
      final r = RecoveryData(nights: [for (var i = 2; i <= 22; i++) night(DateTime(2026, 4, i))]);
      final g = sleepAfterTraining(r, sessions);
      expect(g.map((x) => x.label), contains('After a rest day'));
      expect(g.firstWhere((x) => x.label == 'After any session').nights, 10);
    });
  });

  group('Coach facts', () {
    test('flags numbers that are not in the data', () {
      const facts = 'score 68, HRV 57, asleep 7h 36m';
      expect(unverifiedNumbers('Your score was 68 and HRV 57.3.', facts), isEmpty);
      expect(unverifiedNumbers('That is 12% lower, across 3 nights.', facts), ['12']);
    });

    test('facts pack covers both halves', () {
      final today = DateTime(2026, 9, 24);
      const athlete = Athlete();
      final acts = SyntheticGenerator(today: today).generate();
      final list = [for (final a in acts) ActivityAnalysis.of(a, athlete, HrZoneModel.forAthlete(athlete))]
        ..sort((a, b) => b.activity.start.compareTo(a.activity.start));
      final rec = SyntheticSleep(activities: acts, to: today).generate();
      final daily = dailyLoadOf([for (final x in list) (x.activity, x.load)]);
      final load = loadSeries(daily, list.last.activity.day, today);
      final f = buildFacts(
        asOf: today,
        athlete: athlete,
        sessions: list,
        load: load,
        recovery: rec,
        sports: const [],
      );
      expect(f, contains('TRAINING LOAD'));
      expect(f, contains('SLEEP, LAST 14 NIGHTS'));
      expect(f.length, lessThan(12000));
    });
  });

  group('Synthetic sleep', () {
    test('is deterministic and covers every night', () {
      final today = DateTime(2026, 9, 24);
      final acts = SyntheticGenerator(today: today).generate();
      final a = SyntheticSleep(activities: acts, to: today).generate();
      final b = SyntheticSleep(activities: acts, to: today).generate();
      expect(a.nights.length, greaterThan(170));
      expect(a.nights.last.date, today);
      expect(a.nights[50].score, b.nights[50].score);
      for (final n in a.nights) {
        expect(n.score, inInclusiveRange(35, 96));
        expect(n.end!.isAfter(n.start!), isTrue);
      }
    });
  });

  test('bundle parses nights and days', () {
    final b = GarminBundle.fromJson({
      'exportedAt': '2026-05-08',
      'athlete': {'name': 'Alex', 'maxHr': 200, 'restHr': 51, 'weightKg': 80.0},
      'validation': {'n': 0, 'pearson': 0, 'spearman': 0, 'bySport': <String, dynamic>{}},
      'activities': <dynamic>[],
      'nights': [
        {
          'date': '2026-05-08',
          'start': '2026-05-07T23:45',
          'end': '2026-05-08T07:50',
          'deep': 3360,
          'light': 22560,
          'rem': 1800,
          'awake': 1380,
          'score': 68,
          'sub': {'remScore': 35},
          'feedback': 'NEGATIVE_LONG_BUT_NOT_ENOUGH_REM',
          'hrv': 57.0,
          'hrvLow': 62.0,
          'hrvHigh': 86.0,
          'rhr': 52,
        },
      ],
      'days': {
        '2026-05-08': {'rhr': 52, 'stress': 23},
      },
    });
    final n = b.recovery.nights.single;
    expect(n.asleepS, 3360 + 22560 + 1800);
    expect(n.hrvStatus, HrvStatus.below);
    expect(n.subScores['remScore'], 35);
    expect(b.recovery.days[DateTime(2026, 5, 8)]?.stress, 23);
  });
}
