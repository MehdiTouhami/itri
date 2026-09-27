import 'athlete.dart';
import 'sample.dart';

/// A heart-rate zone. [lower] is inclusive, [upper] exclusive (null = open).
class HrZone {
  const HrZone(this.index, this.name, this.lower, this.upper);

  final int index; // 0-based
  final String name;
  final int lower;
  final int? upper;

  String get label => 'Z${index + 1}';
  String get range => upper == null ? '$lower+' : '$lower–${upper! - 1}';
  bool contains(int hr) => hr >= lower && (upper == null || hr < upper!);
}

/// Garmin's default model: five zones at 50/60/70/80/90 % of max HR.
class HrZoneModel {
  HrZoneModel(this.zones);

  factory HrZoneModel.percentOfMax(int maxHr) {
    const names = ['Recovery', 'Endurance', 'Tempo', 'Threshold', 'VO₂ max'];
    const pct = [0.5, 0.6, 0.7, 0.8, 0.9];
    final bounds = pct.map((p) => (maxHr * p).round()).toList();
    return HrZoneModel([
      for (var i = 0; i < 5; i++) HrZone(i, names[i], bounds[i], i < 4 ? bounds[i + 1] : null),
    ]);
  }

  factory HrZoneModel.forAthlete(Athlete a) => HrZoneModel.percentOfMax(a.maxHr);

  final List<HrZone> zones;

  /// Zone index for [hr]; below Z1 counts as Z1.
  int indexOf(int hr) {
    for (final z in zones.reversed) {
      if (hr >= z.lower) return z.index;
    }
    return 0;
  }

  /// Seconds spent in each zone. Each sample owns the gap to the next one.
  List<int> timeInZones(List<Sample> samples) {
    final out = List<int>.filled(zones.length, 0);
    for (var i = 0; i < samples.length - 1; i++) {
      final hr = samples[i].heartRate;
      if (hr == null) continue;
      out[indexOf(hr)] += samples[i + 1].t - samples[i].t;
    }
    return out;
  }
}
