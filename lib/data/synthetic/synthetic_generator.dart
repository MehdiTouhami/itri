import 'dart:math' as math;

import '../../domain/activity.dart';
import '../../domain/athlete.dart';
import '../../domain/sample.dart';
import '../../domain/sport.dart';

/// Deterministic six months of training around Preston.
///
/// Not random noise: sessions follow a 3-build / 1-recovery block, fitness
/// improves pace over time, HR lags effort and drifts on long sessions, and
/// speed responds to gradient. That gives the analytics something real to find.
class SyntheticGenerator {
  SyntheticGenerator({
    required this.today,
    this.days = 182,
    this.seed = 20260924,
    this.athlete = const Athlete(),
    this.ageYears = 24,
  });

  final DateTime today;
  final int days;
  final int seed;
  final Athlete athlete;
  final int ageYears;

  static const _dt = 5; // seconds between samples (Garmin smart-recording-ish)
  static const _ftp = 230.0;

  late final math.Random _r = math.Random(seed);
  int _nextId = 1;

  List<Activity> generate() {
    final first = DateTime(today.year, today.month, today.day - days + 1);
    final out = <Activity>[];
    // One short illness gap makes the load curves look lived-in.
    final sickFrom = 64 + _r.nextInt(20);

    for (var i = 0; i < days; i++) {
      final day = DateTime(first.year, first.month, first.day + i);
      if (i >= sickFrom && i < sickFrom + 5) continue;
      final week = i ~/ 7;
      final block = week % 4;
      final recovery = block == 3;
      final progress = i / days;
      final scale = (0.85 + 0.3 * progress) * (recovery ? 0.65 : 1.0 + 0.05 * block);

      for (final plan in _plansFor(day.weekday, recovery, scale)) {
        out.add(_build(day, plan, progress));
      }
    }
    return out;
  }

  // ─── Weekly template ────────────────────────────────────────────────────

  List<_Plan> _plansFor(int weekday, bool recovery, double scale) {
    bool chance(double p) => _r.nextDouble() < p;
    int mins(num m) => (m * scale * 60).round();
    switch (weekday) {
      case DateTime.monday:
        if (!chance(0.75)) return const [];
        final focus = ['Lower body', 'Upper body', 'Full body'][_r.nextInt(3)];
        return [_Plan.strength('Strength · $focus', mins(40 + _r.nextInt(15)))];
      case DateTime.tuesday:
        if (!chance(0.9)) return const [];
        if (recovery) return [_Plan.steady(Sport.run, 'Easy run', mins(35), 0.62)];
        final reps = 4 + _r.nextInt(3);
        return [_Plan.intervals('$reps × 4 min intervals', reps)];
      case DateTime.wednesday:
        if (!chance(0.6)) return const [];
        return [_Plan.steady(Sport.ride, 'Endurance ride', mins(50 + _r.nextInt(25)), 0.58)];
      case DateTime.thursday:
        if (!chance(0.85)) return const [];
        if (recovery) return [_Plan.steady(Sport.run, 'Easy run', mins(30), 0.6)];
        return [_Plan.tempo('Tempo run', mins(20 + _r.nextInt(12)))];
      case DateTime.friday:
        if (!chance(0.5)) return const [];
        return [_Plan.steady(Sport.walk, 'Walk', mins(30 + _r.nextInt(20)), 0.3)];
      case DateTime.saturday:
        if (!chance(0.9)) return const [];
        return [_Plan.steady(Sport.run, 'Long run', mins(recovery ? 55 : 70 + _r.nextInt(30)), 0.67)];
      default: // Sunday
        if (chance(0.55)) {
          return [_Plan.steady(Sport.ride, 'Long ride', mins(95 + _r.nextInt(55)), 0.6)];
        }
        return chance(0.4) ? [_Plan.steady(Sport.run, 'Easy run', mins(40), 0.62)] : const [];
    }
  }

  // ─── Session synthesis ──────────────────────────────────────────────────

  Activity _build(DateTime day, _Plan plan, double progress) {
    final weekend = day.weekday >= DateTime.saturday;
    final hour = plan.sport == Sport.strength
        ? 18
        : weekend
            ? 9
            : (_r.nextBool() ? 7 : 18);
    final start = day.add(Duration(hours: hour, minutes: _r.nextInt(40)));
    final place = _placeFor(plan.sport);

    final speedOf = _speedModel(plan.sport, progress);
    final plannedM = plan.segments.fold<double>(0, (s, g) => s + g.seconds * speedOf(g.to, 0));
    final route = plan.sport.hasGps ? _Route.loop(_r, plannedM, plan.sport) : null;

    final samples = <Sample>[];
    final hrr = athlete.hrReserve.toDouble();
    var hr = athlete.restHr + 0.25 * hrr;
    var dist = 0.0;
    var t = 0;
    var wobble = 0.0;
    final totalS = plan.segments.fold<int>(0, (s, g) => s + g.seconds);

    for (final g in plan.segments) {
      for (var local = 0; local < g.seconds; local += _dt) {
        if (t % 60 == 0) wobble = (wobble + _gauss() * 0.01).clamp(-0.03, 0.03);
        final f = g.seconds == 0 ? 0.0 : local / g.seconds;
        final effort = g.from + (g.to - g.from) * f + wobble;

        final alt = route?.altitudeAt(dist);
        final grade = route == null ? 0.0 : (route.altitudeAt(dist + 10) - alt!) / 10;

        // HR chases effort with a lag, plus cardiac drift on long efforts.
        final drift = 0.05 * hrr * (t / 3600).clamp(0, 2.5) * (effort > 0.5 ? 1 : 0.3);
        final target = athlete.restHr + effort * hrr + drift;
        final tau = target > hr ? 30.0 : 55.0;
        hr += (target - hr) * (1 - math.exp(-_dt / tau)) + _gauss() * 0.9;
        hr = hr.clamp(athlete.restHr.toDouble(), athlete.maxHr.toDouble());

        double? speed;
        int? cadence, power;
        if (route != null) {
          speed = math.max(0.4, speedOf(effort, grade) * (1 + _gauss() * 0.025));
          if (plan.sport == Sport.ride) {
            power = math.max(0, _ftp * (0.35 + effort * 0.6) + grade * 1800 + _gauss() * 12).round();
            cadence = grade < -0.03 && _r.nextDouble() < 0.4 ? 0 : (86 + _gauss() * 3).round();
          } else {
            cadence = (152 + (speed - 2.6) * 14 + _gauss() * 1.5).round();
          }
        }

        final pos = route?.positionAt(dist);
        samples.add(Sample(
          t: t,
          lat: pos?.$1,
          lon: pos?.$2,
          altitudeM: alt == null ? null : alt + _gauss() * 0.3,
          distanceM: route == null ? null : dist,
          speedMs: speed,
          heartRate: hr.round(),
          cadence: cadence,
          power: power,
        ));

        if (speed != null) dist += speed * _dt;
        t += _dt;
      }
    }
    // Closing sample so duration and distance land exactly.
    final end = route?.positionAt(dist);
    samples.add(Sample(
      t: totalS,
      lat: end?.$1,
      lon: end?.$2,
      altitudeM: route?.altitudeAt(dist),
      distanceM: route == null ? null : dist,
      speedMs: samples.last.speedMs,
      heartRate: hr.round(),
      cadence: samples.last.cadence,
      power: samples.last.power,
    ));

    return Activity.fromSamples(
      id: _nextId++,
      sport: plan.sport,
      name: plan.name,
      start: start,
      locality: place,
      samples: samples,
      weightKg: athlete.weightKg,
      ageYears: ageYears,
    );
  }

  /// Speed (m/s) from effort (fraction of HR reserve) and gradient.
  double Function(double effort, double grade) _speedModel(Sport s, double progress) {
    final fit = 1 + 0.05 * progress; // ~5 % faster by the end
    switch (s) {
      case Sport.run:
        return (e, g) => (2.75 + (e - 0.55) * 3.4) * fit * (1 - 4 * g).clamp(0.6, 1.2);
      case Sport.ride:
        return (e, g) => (6.2 + (e - 0.5) * 9) * fit * (1 - 8 * g).clamp(0.4, 1.5);
      case Sport.walk:
        return (e, g) => 1.45 * (1 - 3 * g).clamp(0.7, 1.1);
      default:
        return (e, g) => 0;
    }
  }

  String _placeFor(Sport s) {
    const runs = ['Avenham & Miller Parks', 'Preston Docks', 'Fulwood', 'Ribble riverside'];
    const rides = ['Guild Wheel', 'Guild Wheel', 'Forest of Bowland'];
    switch (s) {
      case Sport.run:
        return runs[_r.nextInt(runs.length)];
      case Sport.ride:
        return rides[_r.nextInt(rides.length)];
      case Sport.walk:
        return 'Fulwood';
      default:
        return 'Gym';
    }
  }

  double _gauss() {
    final u = 1 - _r.nextDouble(), v = _r.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}

// ─── Plans ────────────────────────────────────────────────────────────────

class _Seg {
  const _Seg(this.seconds, this.from, [double? to]) : to = to ?? from;
  final int seconds;
  final double from; // effort as fraction of HR reserve
  final double to;
}

class _Plan {
  _Plan(this.sport, this.name, this.segments);

  factory _Plan.steady(Sport sport, String name, int seconds, double effort) => _Plan(sport, name, [
        _Seg(600, effort - 0.15, effort),
        _Seg(math.max(300, seconds - 900), effort),
        _Seg(300, effort, effort - 0.12),
      ]);

  factory _Plan.tempo(String name, int tempoSeconds) => _Plan(Sport.run, name, [
        const _Seg(600, 0.45, 0.62),
        _Seg(tempoSeconds, 0.8),
        const _Seg(480, 0.6, 0.45),
      ]);

  factory _Plan.intervals(String name, int reps) => _Plan(Sport.run, name, [
        const _Seg(720, 0.45, 0.62),
        for (var i = 0; i < reps; i++) ...[const _Seg(240, 0.9), const _Seg(120, 0.5)],
        const _Seg(480, 0.55, 0.42),
      ]);

  factory _Plan.strength(String name, int seconds) => _Plan(Sport.strength, name, [
        const _Seg(300, 0.3, 0.45),
        for (var i = 0; i < seconds ~/ 135; i++) ...[const _Seg(45, 0.68), const _Seg(90, 0.34)],
      ]);

  final Sport sport;
  final String name;
  final List<_Seg> segments;
}

// ─── Routes ───────────────────────────────────────────────────────────────

/// A closed loop starting at home, scaled so its length matches the plan.
class _Route {
  _Route._(this._xy, this._cum, this._alt, this._lat0, this._lon0);

  factory _Route.loop(math.Random r, double lengthM, Sport sport) {
    const n = 360;
    final rot = r.nextDouble() * 2 * math.pi;
    final a = [0.16 * r.nextDouble(), 0.12 * r.nextDouble(), 0.06 * r.nextDouble()];
    final p = [for (var i = 0; i < 3; i++) r.nextDouble() * 2 * math.pi];
    final raw = <(double, double)>[];
    for (var i = 0; i <= n; i++) {
      final th = 2 * math.pi * i / n;
      final rr = 1 + a[0] * math.sin(2 * th + p[0]) + a[1] * math.sin(3 * th + p[1]) + a[2] * math.sin(5 * th + p[2]);
      raw.add((rr * math.cos(th + rot), rr * math.sin(th + rot)));
    }
    final ox = raw.first.$1, oy = raw.first.$2;
    final cum = <double>[0];
    for (var i = 1; i < raw.length; i++) {
      cum.add(cum.last + math.sqrt(math.pow(raw[i].$1 - raw[i - 1].$1, 2) + math.pow(raw[i].$2 - raw[i - 1].$2, 2)));
    }
    final k = lengthM / cum.last;
    final xy = [for (final q in raw) ((q.$1 - ox) * k, (q.$2 - oy) * k)];
    final scaled = [for (final c in cum) c * k];

    final hilly = sport == Sport.ride ? 2.8 : 1.0;
    final amp = [9.0 * hilly, 4.0 * hilly, 2.0 * hilly];
    final ph = [for (var i = 0; i < 3; i++) r.nextDouble() * 2 * math.pi];
    double alt(double f) {
      var v = 38.0;
      for (var j = 0; j < 3; j++) {
        v += amp[j] * (math.sin(2 * math.pi * (j + 1) * f + ph[j]) - math.sin(ph[j]));
      }
      return v;
    }

    const home = (53.7632, -2.7031); // Preston city centre
    return _Route._(xy, scaled, alt, home.$1 + (r.nextDouble() - 0.5) * 0.02,
        home.$2 + (r.nextDouble() - 0.5) * 0.03);
  }

  final List<(double, double)> _xy;
  final List<double> _cum;
  final double Function(double fraction) _alt;
  final double _lat0, _lon0;

  double get length => _cum.last;

  double altitudeAt(double d) => math.max(2.0, _alt((d % length) / length));

  (double, double) positionAt(double d) {
    final dd = d % length;
    var lo = 0, hi = _cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] <= dd) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = _cum[hi] - _cum[lo];
    final f = seg == 0 ? 0.0 : (dd - _cum[lo]) / seg;
    final x = _xy[lo].$1 + (_xy[hi].$1 - _xy[lo].$1) * f;
    final y = _xy[lo].$2 + (_xy[hi].$2 - _xy[lo].$2) * f;
    const mPerDeg = 111320.0;
    final lat = _lat0 + y / mPerDeg;
    final lon = _lon0 + x / (mPerDeg * math.cos(_lat0 * math.pi / 180));
    return (lat, lon);
  }
}
