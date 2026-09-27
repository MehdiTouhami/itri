import 'dart:math' as math;

import '../../domain/activity.dart';
import '../../domain/sleep.dart';

/// Sample nights to sit beside the sample training. Seeded, and causally
/// linked: hard or late sessions cost sleep and HRV, weekends run later.
class SyntheticSleep {
  SyntheticSleep({required this.activities, required this.to, this.seed = 7});

  final List<Activity> activities;
  final DateTime to;
  final int seed;

  late final math.Random _r = math.Random(seed);

  double _gauss() {
    final u = 1 - _r.nextDouble(), v = _r.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  RecoveryData generate() {
    if (activities.isEmpty) return RecoveryData(nights: const []);
    final strain = <DateTime, double>{};
    final late = <DateTime>{};
    var first = activities.first.day;
    for (final a in activities) {
      // Minutes weighted by how far above rest the heart was working.
      strain[a.day] = (strain[a.day] ?? 0) + a.durationS / 60 * ((a.avgHr - 50) / 140).clamp(0.0, 1.0);
      if (a.start.hour >= 19) late.add(a.day);
      if (a.day.isBefore(first)) first = a.day;
    }

    final nights = <SleepNight>[];
    final days = <DateTime, DayStats>{};
    for (var d = DateTime(first.year, first.month, first.day + 1);
        !d.isAfter(to);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final evening = DateTime(d.year, d.month, d.day - 1);
      final load = strain[evening] ?? 0;
      final isLate = late.contains(evening);
      final weekend = evening.weekday == DateTime.friday || evening.weekday == DateTime.saturday;

      final bed = 330 + (weekend ? 55 : 0) + (isLate ? 25 : 0) + _gauss() * 25; // minutes after 18:00
      final asleepMin = (455 - (isLate ? 20 : 0) - load * 0.08 + (weekend ? 20 : 0) + _gauss() * 30).clamp(300.0, 570.0);
      final awakeMin = (18 + _r.nextDouble() * 22).roundToDouble();
      final deepF = (0.17 - load * 0.0002 + _gauss() * 0.025).clamp(0.08, 0.28);
      final remF = (0.20 - (isLate ? 0.02 : 0) + _gauss() * 0.03).clamp(0.08, 0.30);
      final lightF = 1 - deepF - remF;

      final start = DateTime(evening.year, evening.month, evening.day, 18).add(Duration(minutes: bed.round()));
      final end = start.add(Duration(minutes: (asleepMin + awakeMin).round()));
      final score = (38 + asleepMin / 480 * 32 + deepF * 70 + remF * 45 - awakeMin / 4 + _gauss() * 4).clamp(35.0, 96.0).round();
      final hrv = 68 - load * 0.04 - (isLate ? 3 : 0) + _gauss() * 6;
      final rhr = (52 + load * 0.012 + _gauss() * 1.4).round();

      nights.add(SleepNight(
        date: d,
        start: start,
        end: end,
        deepS: (asleepMin * deepF * 60).round(),
        lightS: (asleepMin * lightF * 60).round(),
        remS: (asleepMin * remF * 60).round(),
        awakeS: (awakeMin * 60).round(),
        score: score,
        feedback: score >= 80
            ? 'POSITIVE_LONG_AND_RECOVERING'
            : score >= 65
                ? 'POSITIVE_RECOVERING'
                : remF < 0.16
                    ? 'NEGATIVE_NOT_ENOUGH_REM'
                    : 'NEGATIVE_SHORT_AND_POOR_QUALITY',
        respiration: 15.5 + _gauss() * 0.5,
        restless: (30 + _r.nextInt(30)),
        awakenings: _r.nextInt(4),
        hrv: hrv.roundToDouble(),
        hrvLow: 58.0,
        hrvHigh: 80.0,
        restingHr: rhr,
      ));
      days[d] = DayStats(restingHr: rhr);
    }
    return RecoveryData(nights: nights, days: days);
  }
}
