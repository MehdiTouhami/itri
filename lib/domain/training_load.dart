import 'dart:math' as math;

import 'activity.dart';
import 'athlete.dart';
import 'sample.dart';

/// Banister TRIMP: time weighted by heart-rate reserve, exponentially, so
/// ten minutes near max costs far more than ten easy minutes.
double trimp(List<Sample> samples, Athlete a) {
  var load = 0.0;
  for (var i = 0; i < samples.length - 1; i++) {
    final hr = samples[i].heartRate;
    if (hr == null) continue;
    final hrr = ((hr - a.restHr) / a.hrReserve).clamp(0.0, 1.0);
    final minutes = (samples[i + 1].t - samples[i].t) / 60;
    load += minutes * hrr * 0.64 * math.exp(1.92 * hrr);
  }
  return load;
}

enum FormStatus {
  fresh('Fresh', 'Rested and ready for a hard session.'),
  neutral('Maintaining', 'Load and recovery are in balance.'),
  productive('Building', 'Fatigue is high enough to drive adaptation.'),
  overreaching('Overreaching', 'Fatigue is well above fitness. Ease off.');

  const FormStatus(this.label, this.advice);
  final String label;
  final String advice;

  /// Classified on form relative to fitness, so it scales with the athlete.
  static FormStatus of(double fitness, double form) {
    if (fitness <= 0) return FormStatus.neutral;
    final r = form / fitness;
    if (r > 0.05) return FormStatus.fresh;
    if (r > -0.10) return FormStatus.neutral;
    if (r > -0.30) return FormStatus.productive;
    return FormStatus.overreaching;
  }
}

class DayLoad {
  const DayLoad(this.day, this.load, this.fitness, this.fatigue, this.form);

  final DateTime day;
  final double load; // summed TRIMP for the day
  final double fitness; // 42-day EWMA (CTL)
  final double fatigue; // 7-day EWMA (ATL)
  final double form; // yesterday's fitness − fatigue (TSB)

  FormStatus get state => FormStatus.of(fitness, form);
}

/// Fitness / fatigue / form for every day in [from]..[to] inclusive.
List<DayLoad> loadSeries(
  Map<DateTime, double> dailyLoad,
  DateTime from,
  DateTime to,
) {
  // Seed both averages with the first four weeks' mean so history doesn't
  // start from an artificial zero.
  var seed = 0.0;
  for (var i = 0; i < 28; i++) {
    seed += dailyLoad[_addDays(from, i)] ?? 0;
  }
  seed /= 28;

  var ctl = seed, atl = seed;
  final out = <DayLoad>[];
  for (var d = from; !d.isAfter(to); d = _addDays(d, 1)) {
    final form = ctl - atl;
    final l = dailyLoad[d] ?? 0;
    ctl += (l - ctl) / 42;
    atl += (l - atl) / 7;
    out.add(DayLoad(d, l, ctl, atl, form));
  }
  return out;
}

Map<DateTime, double> dailyLoadOf(Iterable<(Activity, double)> activityLoads) {
  final m = <DateTime, double>{};
  for (final (a, load) in activityLoads) {
    m[a.day] = (m[a.day] ?? 0) + load;
  }
  return m;
}

/// Calendar-safe day arithmetic (avoids DST hour drift).
DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
DateTime addDays(DateTime d, int n) => _addDays(d, n);
