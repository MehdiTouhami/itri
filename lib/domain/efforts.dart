import 'sample.dart';

/// A hard burst: heart rate held at or above a threshold for a while.
class Effort {
  const Effort({required this.startS, required this.seconds, required this.peakHr, this.recovery});

  final int startS;
  final int seconds;
  final int peakHr;

  /// Beats per minute shed in the 60 s after the peak. Null when the session
  /// ended first. Larger usually means fitter.
  final int? recovery;
}

/// Efforts in [s]: runs at or above [threshold] bpm lasting at least [minSeconds].
List<Effort> effortsOf(List<Sample> s, int threshold, {int minSeconds = 10}) {
  final out = <Effort>[];
  var i = 0;
  while (i < s.length) {
    final hr = s[i].heartRate;
    if (hr == null || hr < threshold) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < s.length && (s[j + 1].heartRate ?? 0) >= threshold) {
      j++;
    }
    if (s[j].t - s[i].t >= minSeconds) {
      var peak = i;
      for (var k = i + 1; k <= j; k++) {
        if (s[k].heartRate! > s[peak].heartRate!) peak = k;
      }
      var k = peak;
      while (k < s.length && s[k].t - s[peak].t < 60) {
        k++;
      }
      final after = k < s.length ? s[k].heartRate : null;
      final peakHr = s[peak].heartRate!;
      out.add(Effort(
        startS: s[i].t,
        seconds: s[j].t - s[i].t,
        peakHr: peakHr,
        recovery: after == null ? null : peakHr - after,
      ));
    }
    i = j + 1;
  }
  return out;
}

/// Mean recovery across [efforts], or null with fewer than [minCount] measured.
double? meanRecovery(Iterable<Effort> efforts, {int minCount = 3}) {
  var sum = 0, n = 0;
  for (final e in efforts) {
    if (e.recovery == null) continue;
    sum += e.recovery!;
    n++;
  }
  return n < minCount ? null : sum / n;
}
