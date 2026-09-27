enum Units { metric, imperial }

/// Physiology the analytics depend on. Defaults describe the synthetic athlete.
class Athlete {
  const Athlete({
    this.name = 'Athlete',
    this.maxHr = 192,
    this.restHr = 52,
    this.weightKg = 74,
    this.units = Units.metric,
  });

  final String name;
  final int maxHr;
  final int restHr;
  final double weightKg;
  final Units units;

  int get hrReserve => maxHr - restHr;

  Athlete copyWith({String? name, int? maxHr, int? restHr, double? weightKg, Units? units}) =>
      Athlete(
        name: name ?? this.name,
        maxHr: maxHr ?? this.maxHr,
        restHr: restHr ?? this.restHr,
        weightKg: weightKg ?? this.weightKg,
        units: units ?? this.units,
      );
}
