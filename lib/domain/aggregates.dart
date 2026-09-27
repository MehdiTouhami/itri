import 'analysis.dart';
import 'training_load.dart';

DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

class WeekTotals {
  WeekTotals(this.monday);
  final DateTime monday;
  int sessions = 0;
  int seconds = 0;
  double distanceM = 0;
  double load = 0;
  final List<int> zoneSeconds = List<int>.filled(5, 0);

  void add(ActivityAnalysis x) {
    sessions++;
    seconds += x.activity.durationS;
    distanceM += x.activity.distanceM;
    load += x.load;
    for (var i = 0; i < zoneSeconds.length && i < x.zoneSeconds.length; i++) {
      zoneSeconds[i] += x.zoneSeconds[i];
    }
  }
}

/// The last [weeks] calendar weeks (Mon–Sun), oldest first, ending this week.
List<WeekTotals> weeklyTotals(List<ActivityAnalysis> list, DateTime today, int weeks) {
  final thisMonday = mondayOf(today);
  final out = [for (var i = weeks - 1; i >= 0; i--) WeekTotals(addDays(thisMonday, -7 * i))];
  final first = out.first.monday;
  for (final x in list) {
    final d = x.activity.day;
    if (d.isBefore(first)) continue;
    // Round to whole days first so a DST hour can't shift the week.
    final idx = (d.difference(first).inHours / 24).round() ~/ 7;
    if (idx >= 0 && idx < out.length) out[idx].add(x);
  }
  return out;
}

/// Summed load per calendar day.
Map<DateTime, double> loadByDay(List<ActivityAnalysis> list) =>
    dailyLoadOf([for (final x in list) (x.activity, x.load)]);
