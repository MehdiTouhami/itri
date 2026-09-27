import 'dart:math' as math;

import 'analysis.dart';
import 'sleep.dart';

/// Average sleep after a certain kind of day.
class SleepAfter {
  const SleepAfter(this.label, this.nights, this.score, this.asleepH, this.hrv);
  final String label;
  final int nights;
  final double score, asleepH;
  final double? hrv;
}

/// How nights differ depending on the day before. Observational: it shows a
/// pattern in your own data, not a cause.
List<SleepAfter> sleepAfterTraining(RecoveryData r, List<ActivityAnalysis> sessions, {int lateHour = 19}) {
  final load = <DateTime, double>{};
  final late = <DateTime>{};
  for (final x in sessions) {
    final d = x.activity.day;
    load[d] = (load[d] ?? 0) + x.load;
    if (x.activity.start.hour >= lateHour) late.add(d);
  }
  if (load.isEmpty || r.isEmpty) return const [];
  final sorted = load.values.toList()..sort();
  final hard = sorted[(sorted.length * 2 / 3).floor().clamp(0, sorted.length - 1)];

  SleepAfter? group(String label, bool Function(DateTime evening) test) {
    final ns = r.nights.where((n) => test(n.evening)).toList();
    if (ns.length < 5) return null;
    final hrvs = [for (final n in ns) if (n.hrv != null) n.hrv!];
    double mean(Iterable<num> v) => v.fold<double>(0, (a, b) => a + b) / v.length;
    return SleepAfter(
      label,
      ns.length,
      mean(ns.map((n) => n.score)),
      mean(ns.map((n) => n.asleepS / 3600)),
      hrvs.length < 5 ? null : mean(hrvs),
    );
  }

  return [
    group('After a rest day', (e) => !load.containsKey(e)),
    group('After any session', load.containsKey),
    group('After a hard day', (e) => (load[e] ?? 0) >= hard),
    group('After a session from ${lateHour > 12 ? lateHour - 12 : lateHour} pm', late.contains),
  ].whereType<SleepAfter>().toList();
}

/// Mean and spread of bedtime, in minutes after 18:00.
({double mean, double spread})? bedtimeStats(List<SleepNight> nights) {
  final v = [for (final n in nights) if (n.bedMinutes != null) n.bedMinutes!.toDouble()];
  if (v.length < 3) return null;
  final mean = v.reduce((a, b) => a + b) / v.length;
  final variance = v.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / v.length;
  return (mean: mean, spread: math.sqrt(variance));
}

/// Average hours asleep by the weekday of the evening (Mon..Sun).
List<double> asleepByWeekday(List<SleepNight> nights) {
  final sum = List<double>.filled(7, 0), n = List<int>.filled(7, 0);
  for (final x in nights) {
    final i = x.evening.weekday - 1;
    sum[i] += x.asleepS / 3600;
    n[i]++;
  }
  return [for (var i = 0; i < 7; i++) n[i] == 0 ? 0 : sum[i] / n[i]];
}

/// "23:45" from minutes after 18:00.
String clockFromEvening(num minutes) {
  final m = (minutes.round() + 18 * 60) % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Per-night numbers that can be followed over time.
enum NightMetric {
  score('Score', '', 'Garmin\'s 0–100 sleep score.'),
  asleep('Asleep', 'h', 'Time actually asleep, not time in bed.'),
  hrv('HRV', 'ms', 'Overnight heart rate variability. Higher than your usual generally means better recovered.'),
  restingHr('Resting HR', 'bpm', 'Lowest steady heart rate of the day. A rise of 5+ often means fatigue or illness.'),
  bedtime('Bedtime', '', 'When you fell asleep. Regular bedtimes tend to mean better sleep.');

  const NightMetric(this.label, this.unit, this.explainer);
  final String label, unit, explainer;

  double? of(SleepNight n) => switch (this) {
        NightMetric.score => n.score.toDouble(),
        NightMetric.asleep => n.asleepS / 3600,
        NightMetric.hrv => n.hrv,
        NightMetric.restingHr => n.restingHr?.toDouble(),
        NightMetric.bedtime => n.bedMinutes?.toDouble(),
      };

  String format(double v) => switch (this) {
        NightMetric.asleep => _hm((v * 60).round()),
        NightMetric.bedtime => clockFromEvening(v),
        _ => v.round().toString(),
      };
}

String _hm(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
