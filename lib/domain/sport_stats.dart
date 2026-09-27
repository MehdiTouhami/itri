import 'analysis.dart';
import 'efforts.dart';
import 'sport.dart';

/// Everything one sport adds up to across the history.
class SportSummary {
  SportSummary(this.sport, Iterable<ActivityAnalysis> sessions)
      : sessions = [...sessions]..sort((a, b) => a.activity.start.compareTo(b.activity.start));

  final Sport sport;

  /// Oldest first.
  final List<ActivityAnalysis> sessions;

  int get count => sessions.length;
  DateTime get first => sessions.first.activity.start;
  DateTime get last => sessions.last.activity.start;

  late final int seconds = sessions.fold(0, (s, x) => s + x.activity.durationS);
  late final double load = sessions.fold(0.0, (s, x) => s + x.load);
  double get hours => seconds / 3600;
  double get loadPerHour => hours == 0 ? 0 : load / hours;
  double get avgSessionS => count == 0 ? 0 : seconds / count;

  late final List<int> zoneSeconds = () {
    final z = List<int>.filled(5, 0);
    for (final x in sessions) {
      for (var i = 0; i < z.length && i < x.zoneSeconds.length; i++) {
        z[i] += x.zoneSeconds[i];
      }
    }
    return z;
  }();

  /// Share of heart-rate time spent in zones 4–5.
  double get hardShare {
    final total = zoneSeconds.fold(0, (a, b) => a + b);
    return total == 0 ? 0 : (zoneSeconds[3] + zoneSeconds[4]) / total;
  }

  /// Time-weighted, so a two-hour match counts more than a warm-up hit.
  late final double avgHr = () {
    var sum = 0.0, w = 0;
    for (final x in sessions) {
      if (x.activity.avgHr == 0) continue;
      sum += x.activity.avgHr * x.activity.durationS;
      w += x.activity.durationS;
    }
    return w == 0 ? 0.0 : sum / w;
  }();

  late final int efforts = sessions.fold(0, (s, x) => s + x.efforts.length);
  double get effortsPerHour => hours == 0 ? 0 : efforts / hours;
  late final double? recovery = meanRecovery([for (final x in sessions) ...x.efforts], minCount: 10);

  /// Session counts Monday..Sunday.
  late final List<int> byWeekday = () {
    final c = List<int>.filled(7, 0);
    for (final x in sessions) {
      c[x.activity.start.weekday - 1]++;
    }
    return c;
  }();

  /// Session counts for morning (before 12), afternoon (12–17) and evening.
  late final List<int> byDaypart = () {
    final c = List<int>.filled(3, 0);
    for (final x in sessions) {
      final h = x.activity.start.hour;
      c[h < 12 ? 0 : (h < 17 ? 1 : 2)]++;
    }
    return c;
  }();

  /// Sessions per calendar month from the first to the last, gaps included.
  late final List<(DateTime, int)> byMonth = () {
    final out = <(DateTime, int)>[];
    var m = DateTime(first.year, first.month);
    final end = DateTime(last.year, last.month);
    while (!m.isAfter(end)) {
      final n = sessions.where((x) => x.activity.start.year == m.year && x.activity.start.month == m.month).length;
      out.add((m, n));
      m = DateTime(m.year, m.month + 1);
    }
    return out;
  }();

  ActivityAnalysis get longest =>
      sessions.reduce((a, b) => b.activity.durationS > a.activity.durationS ? b : a);
  ActivityAnalysis get hardest => sessions.reduce((a, b) => b.load > a.load ? b : a);
  ActivityAnalysis get mostEfforts => sessions.reduce((a, b) => b.efforts.length > a.efforts.length ? b : a);
}

/// One summary per sport, most time first.
List<SportSummary> sportSummaries(Iterable<ActivityAnalysis> list) {
  final by = <Sport, List<ActivityAnalysis>>{};
  for (final x in list) {
    (by[x.activity.sport] ??= []).add(x);
  }
  return [for (final e in by.entries) SportSummary(e.key, e.value)]..sort((a, b) => b.seconds.compareTo(a.seconds));
}

/// Per-session numbers that can be followed over time.
enum SessionMetric {
  recovery('Recovery', 'bpm', 'Heart rate shed in the minute after each hard effort. Bigger usually means fitter.'),
  effortsPerHour('Efforts / h', '', 'Bursts of 10 s or more in zone 4+, per hour of play.'),
  loadPerHour('Load / h', '', 'How much training each hour of this sport gives you.'),
  avgHr('Avg HR', 'bpm', 'Average heart rate across the session.'),
  duration('Duration', 'min', 'How long each session lasted.');

  const SessionMetric(this.label, this.unit, this.explainer);
  final String label, unit, explainer;

  double? of(ActivityAnalysis x) => switch (this) {
        SessionMetric.recovery => x.recovery,
        SessionMetric.effortsPerHour => x.effortsPerHour,
        SessionMetric.loadPerHour => x.loadPerHour,
        SessionMetric.avgHr => x.activity.avgHr == 0 ? null : x.activity.avgHr.toDouble(),
        SessionMetric.duration => x.activity.durationS / 60,
      };

  static List<SessionMetric> forSport(Sport s) => s.stopStart
      ? values
      : [SessionMetric.loadPerHour, SessionMetric.avgHr, SessionMetric.duration];
}

/// Trailing mean over the last [n] present values; null until one exists.
List<double?> rollingMean(List<double?> v, int n) {
  final window = <double>[];
  return [
    for (final x in v)
      () {
        if (x != null) {
          window.add(x);
          if (window.length > n) window.removeAt(0);
        }
        return window.isEmpty ? null : window.reduce((a, b) => a + b) / window.length;
      }(),
  ];
}

/// Mean of the first [window] present values against the last [window], once
/// there are at least two windows' worth. Null means "too early to say".
({double from, double to})? firstVsLast(List<double?> v, {int window = 5}) {
  final p = v.whereType<double>().toList();
  if (p.length < window * 2) return null;
  double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  return (from: mean(p.take(window)), to: mean(p.skip(p.length - window)));
}
