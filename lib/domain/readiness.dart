import 'sleep.dart';
import 'training_load.dart';

enum Signal { good, neutral, bad }

/// One input to the verdict, stated so the user can see why.
class ReadinessFactor {
  const ReadinessFactor(this.label, this.value, this.note, this.signal);
  final String label, value, note;
  final Signal signal;
}

enum ReadinessLevel {
  ready('Ready', 'Recovered. A hard session is fair game today.'),
  steady('Steady', 'Nothing is flashing red. Train as planned.'),
  easy('Go easy', 'Recovery is behind. Keep today light or technical.'),
  recover('Recover', 'Several signs say you are run down. Rest or move gently.');

  const ReadinessLevel(this.label, this.advice);
  final String label, advice;
}

/// A transparent morning verdict: each factor votes, HRV counts double
/// because it is the most direct read on recovery.
class Readiness {
  const Readiness(this.level, this.factors);
  final ReadinessLevel level;
  final List<ReadinessFactor> factors;

  static Readiness? from({
    required SleepNight? night,
    required double? restingBaseline,
    required DayLoad? load,
  }) {
    if (night == null) return null;
    final f = <ReadinessFactor>[];
    var points = 0;

    final status = night.hrvStatus;
    if (status != null) {
      final v = night.hrv!.round(), lo = night.hrvLow!.round(), hi = night.hrvHigh!.round();
      switch (status) {
        case HrvStatus.below:
          points += 2;
          f.add(ReadinessFactor('HRV', '$v ms', 'Below your usual $lo–$hi', Signal.bad));
        case HrvStatus.within:
          f.add(ReadinessFactor('HRV', '$v ms', 'Within your usual $lo–$hi', Signal.good));
        case HrvStatus.above:
          f.add(ReadinessFactor('HRV', '$v ms', 'Above your usual $lo–$hi', Signal.good));
      }
    }

    final rhr = night.restingHr;
    if (rhr != null && restingBaseline != null) {
      final d = rhr - restingBaseline;
      final base = restingBaseline.round();
      if (d >= 5) {
        points += 1;
        f.add(ReadinessFactor('Resting HR', '$rhr bpm', '${d.round()} above your 30-day $base', Signal.bad));
      } else if (d <= -2) {
        f.add(ReadinessFactor('Resting HR', '$rhr bpm', 'Below your 30-day $base', Signal.good));
      } else {
        f.add(ReadinessFactor('Resting HR', '$rhr bpm', 'Normal for you ($base)', Signal.neutral));
      }
    }

    final hours = night.asleepS / 3600;
    final short = hours < 6;
    final sleepSignal = night.score < 60 || short
        ? Signal.bad
        : night.score >= 80
            ? Signal.good
            : Signal.neutral;
    if (sleepSignal == Signal.bad) points += 1;
    f.add(ReadinessFactor(
      'Sleep',
      '${night.score}',
      '${_hm(night.asleepS)} asleep${short ? ', under 6 h' : ''}',
      sleepSignal,
    ));

    if (load != null) {
      final s = load.state;
      final signal = switch (s) {
        FormStatus.overreaching => Signal.bad,
        FormStatus.fresh => Signal.good,
        _ => Signal.neutral,
      };
      if (signal == Signal.bad) points += 1;
      f.add(ReadinessFactor('Training', s.label, 'Form ${load.form >= 0 ? '+' : '−'}${load.form.abs().round()}', signal));
    }

    final goods = f.where((x) => x.signal == Signal.good).length;
    final level = points >= 3
        ? ReadinessLevel.recover
        : points == 2
            ? ReadinessLevel.easy
            : points == 1
                ? ReadinessLevel.steady
                : (goods >= 2 ? ReadinessLevel.ready : ReadinessLevel.steady);
    return Readiness(level, f);
  }

  static String _hm(int s) => '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
}
