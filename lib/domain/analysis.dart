import 'activity.dart';
import 'athlete.dart';
import 'efforts.dart';
import 'hr_zones.dart';
import 'sample.dart';
import 'training_load.dart';

/// Athlete-dependent view of an activity: recomputed when zones change.
class ActivityAnalysis {
  ActivityAnalysis._(this.activity, this.load, this.zoneSeconds, this.efforts);

  factory ActivityAnalysis.of(Activity a, Athlete athlete, HrZoneModel zones) => ActivityAnalysis._(
        a,
        trimp(a.samples, athlete),
        zones.timeInZones(a.samples),
        // An effort is 10 s or more in zone 4 or above.
        effortsOf(a.samples, zones.zones[3].lower),
      );

  final Activity activity;
  final double load;
  final List<int> zoneSeconds;
  final List<Effort> efforts;

  double get hours => activity.durationS / 3600;
  double get loadPerHour => hours == 0 ? 0 : load / hours;
  double get effortsPerHour => hours == 0 ? 0 : efforts.length / hours;
  double? get recovery => meanRecovery(efforts);

  int get dominantZone {
    var best = 0;
    for (var i = 1; i < zoneSeconds.length; i++) {
      if (zoneSeconds[i] > zoneSeconds[best]) best = i;
    }
    return best;
  }
}

/// One split (per km, per mile or per 5 km). Named to avoid Flutter's `Split` curve.
class KmSplit {
  const KmSplit(this.index, this.distanceM, this.seconds, this.avgHr, this.elevDeltaM);

  final int index;
  final double distanceM; // < unit for the final partial split
  final double seconds;
  final int avgHr;
  final double elevDeltaM;

  /// Seconds per full unit, so a partial last split compares fairly.
  double pacePerUnit(double unitM) => seconds / distanceM * unitM;
}

/// Splits every [unitM] metres, interpolating the crossing time.
List<KmSplit> splitsOf(List<Sample> s, {double unitM = 1000}) {
  final out = <KmSplit>[];
  if (s.length < 2) return out;
  var startT = 0.0, startD = 0.0;
  var startAlt = s.first.altitudeM ?? 0;
  var hrSum = 0, hrN = 0;
  var next = unitM;

  for (var i = 1; i < s.length; i++) {
    final d0 = s[i - 1].distanceM ?? 0, d1 = s[i].distanceM ?? 0;
    final hr = s[i].heartRate;
    if (hr != null) {
      hrSum += hr;
      hrN++;
    }
    while (d1 >= next && d1 > d0) {
      final f = (next - d0) / (d1 - d0);
      final t = s[i - 1].t + f * (s[i].t - s[i - 1].t);
      final a0 = s[i - 1].altitudeM ?? 0, a1 = s[i].altitudeM ?? 0;
      final alt = a0 + f * (a1 - a0);
      out.add(KmSplit(out.length, unitM, t - startT, hrN == 0 ? 0 : hrSum ~/ hrN, alt - startAlt));
      startT = t;
      startD = next;
      startAlt = alt;
      hrSum = 0;
      hrN = 0;
      next += unitM;
    }
  }
  final last = s.last;
  final rest = (last.distanceM ?? 0) - startD;
  if (rest > unitM * 0.05) {
    out.add(KmSplit(out.length, rest, last.t - startT, hrN == 0 ? 0 : hrSum ~/ hrN,
        (last.altitudeM ?? 0) - startAlt));
  }
  return out;
}

/// Averages samples into [buckets] equal time slices for drawing. Keeps charts
/// smooth when zoomed out and cheap to paint (same idea as DB-side bucketing).
List<Sample> downsample(List<Sample> s, int buckets) {
  if (s.length <= buckets || buckets < 2) return s;
  final total = s.last.t;
  final out = <Sample>[];
  var i = 0;
  for (var b = 0; b < buckets; b++) {
    final end = total * (b + 1) / buckets;
    final group = <Sample>[];
    while (i < s.length && (s[i].t <= end || b == buckets - 1)) {
      group.add(s[i]);
      i++;
    }
    if (group.isEmpty) continue;
    double? avg(double? Function(Sample) f) {
      var sum = 0.0, n = 0;
      for (final g in group) {
        final v = f(g);
        if (v != null) {
          sum += v;
          n++;
        }
      }
      return n == 0 ? null : sum / n;
    }

    out.add(Sample(
      t: group.first.t,
      lat: avg((g) => g.lat),
      lon: avg((g) => g.lon),
      altitudeM: avg((g) => g.altitudeM),
      distanceM: group.last.distanceM,
      speedMs: avg((g) => g.speedMs),
      heartRate: avg((g) => g.heartRate?.toDouble())?.round(),
      cadence: avg((g) => g.cadence?.toDouble())?.round(),
      power: avg((g) => g.power?.toDouble())?.round(),
    ));
  }
  return out;
}
