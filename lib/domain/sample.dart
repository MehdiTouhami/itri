/// One recorded point. Field set mirrors a FIT `record` message so real
/// imports later are a mapping job, not a rewrite.
class Sample {
  const Sample({
    required this.t,
    this.lat,
    this.lon,
    this.altitudeM,
    this.distanceM,
    this.speedMs,
    this.heartRate,
    this.cadence,
    this.power,
  });

  /// Seconds since activity start.
  final int t;
  final double? lat;
  final double? lon;
  final double? altitudeM;

  /// Cumulative distance.
  final double? distanceM;
  final double? speedMs;
  final int? heartRate;
  final int? cadence;
  final int? power;
}
