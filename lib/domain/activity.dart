import 'sample.dart';
import 'sport.dart';

/// A recorded session. Summary fields mirror a FIT `session` message and are
/// athlete-independent; zone time and load live in [ActivityAnalysis].
class Activity {
  const Activity({
    required this.id,
    required this.sport,
    required this.name,
    required this.start,
    required this.locality,
    required this.durationS,
    required this.distanceM,
    required this.elevationGainM,
    required this.avgHr,
    required this.maxHr,
    required this.avgSpeedMs,
    required this.maxSpeedMs,
    required this.avgCadence,
    required this.avgPower,
    required this.calories,
    required this.samples,
    this.indoor = false,
    this.deviceLoad,
    this.aerobicTE,
    this.anaerobicTE,
  });

  final int id;
  final Sport sport;
  final String name;
  final DateTime start;
  final String locality;
  final int durationS;
  final double distanceM;
  final double elevationGainM;
  final int avgHr;
  final int maxHr;
  final double avgSpeedMs;
  final double maxSpeedMs;
  final int? avgCadence;
  final int? avgPower;
  final int calories;
  final List<Sample> samples;
  final bool indoor;

  /// The watch's own figures, when imported from a device. Kept alongside our
  /// model so the two can be compared rather than one silently replacing the other.
  final double? deviceLoad;
  final double? aerobicTE;
  final double? anaerobicTE;

  DateTime get day => DateTime(start.year, start.month, start.day);
  bool get hasRoute => sport.hasGps && !indoor && samples.any((s) => s.lat != null);

  /// Builds the summary from raw samples, the same way a FIT importer would.
  factory Activity.fromSamples({
    required int id,
    required Sport sport,
    required String name,
    required DateTime start,
    required String locality,
    required List<Sample> samples,
    required double weightKg,
    required int ageYears,
    int? calories,
    bool indoor = false,
    double? deviceLoad,
    double? aerobicTE,
    double? anaerobicTE,
  }) {
    final last = samples.last;
    final duration = last.t;
    final distance = last.distanceM ?? 0;

    var hrSum = 0, hrN = 0, hrMax = 0;
    var cadSum = 0, cadN = 0, powSum = 0, powN = 0;
    var vMax = 0.0;
    for (final s in samples) {
      final hr = s.heartRate;
      if (hr != null) {
        hrSum += hr;
        hrN++;
        if (hr > hrMax) hrMax = hr;
      }
      if (s.cadence != null) {
        cadSum += s.cadence!;
        cadN++;
      }
      if (s.power != null) {
        powSum += s.power!;
        powN++;
      }
      if ((s.speedMs ?? 0) > vMax) vMax = s.speedMs!;
    }
    final avgHr = hrN == 0 ? 0 : (hrSum / hrN).round();

    return Activity(
      id: id,
      sport: sport,
      name: name,
      start: start,
      locality: locality,
      durationS: duration,
      distanceM: distance,
      elevationGainM: elevationGain(samples),
      avgHr: avgHr,
      maxHr: hrMax,
      avgSpeedMs: duration == 0 ? 0 : distance / duration,
      maxSpeedMs: vMax,
      avgCadence: cadN == 0 ? null : (cadSum / cadN).round(),
      avgPower: powN == 0 ? null : (powSum / powN).round(),
      calories: calories ?? _keytelKcal(avgHr, duration, weightKg, ageYears),
      samples: samples,
      indoor: indoor,
      deviceLoad: deviceLoad,
      aerobicTE: aerobicTE,
      anaerobicTE: anaerobicTE,
    );
  }

  /// Positive climb with a 2 m hysteresis so sensor noise doesn't count.
  static double elevationGain(List<Sample> samples) {
    double? ref;
    var gain = 0.0;
    for (final s in samples) {
      final a = s.altitudeM;
      if (a == null) continue;
      ref ??= a;
      if (a - ref > 2) {
        gain += a - ref;
        ref = a;
      } else if (a < ref) {
        ref = a;
      }
    }
    return gain;
  }

  /// Keytel et al. (2005) HR-based energy estimate, male coefficients.
  static int _keytelKcal(int avgHr, int durationS, double weightKg, int age) {
    if (avgHr == 0) return 0;
    final perMin = (-55.0969 + 0.6309 * avgHr + 0.1988 * weightKg + 0.2017 * age) / 4.184;
    return (perMin.clamp(0, 30) * durationS / 60).round();
  }
}
