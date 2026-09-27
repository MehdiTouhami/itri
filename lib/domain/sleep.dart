import 'dart:math' as math;

/// One night, as Garmin files it: keyed by the morning you wake up.
///
/// Nights from the Garmin export carry everything. Nights synced live from
/// intervals.icu carry the score, time asleep, HRV and resting HR only: no
/// stages ([hasStages] is false) and no bed or wake time ([start] is null).
class SleepNight {
  const SleepNight({
    required this.date,
    this.start,
    this.end,
    this.deepS = 0,
    this.lightS = 0,
    this.remS,
    this.awakeS = 0,
    this.totalSleepS,
    required this.score,
    this.subScores = const {},
    this.feedback,
    this.respiration,
    this.stress,
    this.restless,
    this.awakenings,
    this.hrv,
    this.hrvLow,
    this.hrvHigh,
    this.restingHr,
  });

  /// Wake-up date (midnight).
  final DateTime date;

  /// Fell asleep / woke up. Null when the source has no times.
  final DateTime? start, end;
  final int deepS, lightS, awakeS;

  /// Time asleep when the source gives a total but no stages.
  final int? totalSleepS;

  /// Null when the watch could not stage REM that night.
  final int? remS;
  final int score;
  final Map<String, int> subScores;
  final String? feedback;
  final double? respiration, stress;
  final int? restless, awakenings;

  /// Overnight HRV (ms) and Garmin's personal normal range for it.
  final double? hrv, hrvLow, hrvHigh;
  final int? restingHr;

  bool get hasStages => deepS + lightS + (remS ?? 0) > 0;
  int get asleepS => hasStages ? deepS + lightS + (remS ?? 0) : totalSleepS ?? 0;
  int? get inBedS => start == null || end == null ? null : end!.difference(start!).inSeconds;

  double? get efficiency {
    final bed = inBedS;
    if (bed == null || !hasStages) return null;
    return bed <= 0 ? 0 : (asleepS / bed).clamp(0.0, 1.0);
  }

  /// The evening the night belongs to (the day before [date]).
  DateTime get evening => DateTime(date.year, date.month, date.day - 1);

  HrvStatus? get hrvStatus {
    final v = hrv, lo = hrvLow, hi = hrvHigh;
    if (v == null || lo == null || hi == null) return null;
    if (v < lo) return HrvStatus.below;
    if (v > hi) return HrvStatus.above;
    return HrvStatus.within;
  }

  /// Bedtime as minutes after 18:00, so 23:30 = 330 and 01:30 = 450.
  /// Keeps late nights on one continuous scale for averaging and charts.
  int? get bedMinutes => start == null ? null : _afterSix(start!);
  int? get wakeMinutes => end == null ? null : _afterSix(end!);
  static int _afterSix(DateTime t) => ((t.hour - 18) % 24) * 60 + t.minute;

  String get feedbackText => describeFeedback(feedback);
  bool get feedbackPositive => feedback?.startsWith('POSITIVE') ?? false;

  SleepNight withHrvRange(double low, double high) => SleepNight(
        date: date,
        start: start,
        end: end,
        deepS: deepS,
        lightS: lightS,
        remS: remS,
        awakeS: awakeS,
        totalSleepS: totalSleepS,
        score: score,
        subScores: subScores,
        feedback: feedback,
        respiration: respiration,
        stress: stress,
        restless: restless,
        awakenings: awakenings,
        hrv: hrv,
        hrvLow: low,
        hrvHigh: high,
        restingHr: restingHr,
      );
}

/// Fills in a usual HRV range for nights whose source has none (intervals.icu
/// sends the nightly value but not Garmin's baseline). Built from the previous
/// [window] nights: mean ± [k] standard deviations of log HRV. Checked against
/// Garmin's own range on 211 real nights: same below/within/above verdict on
/// 97 %, edges within about 3 ms. Nights that already have a range keep it.
List<SleepNight> withHrvRanges(List<SleepNight> oldestFirst, {int window = 60, double k = 1.75, int minNights = 14}) {
  final out = <SleepNight>[];
  for (var i = 0; i < oldestFirst.length; i++) {
    final n = oldestFirst[i];
    if (n.hrv == null || (n.hrvLow != null && n.hrvHigh != null)) {
      out.add(n);
      continue;
    }
    final logs = [
      for (final p in oldestFirst.sublist(math.max(0, i - window), i))
        if (p.hrv != null && p.hrv! > 0) math.log(p.hrv!),
    ];
    if (logs.length < minNights) {
      out.add(n);
      continue;
    }
    final mean = logs.reduce((a, b) => a + b) / logs.length;
    final sd = math.sqrt(logs.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) / logs.length);
    out.add(n.withHrvRange(math.exp(mean - k * sd), math.exp(mean + k * sd)));
  }
  return out;
}

enum HrvStatus { below, within, above }

/// Plain-English versions of Garmin's sleep feedback codes.
String describeFeedback(String? code) {
  if (code == null) return '';
  const known = {
    'LONG_AND_CONTINUOUS': 'Long and unbroken',
    'LONG_BUT_NOT_ENOUGH_REM': 'Long, but short on REM',
    'NOT_ENOUGH_REM': 'Short on REM',
    'HIGHLY_RECOVERING': 'Highly restorative',
    'LONG_AND_RECOVERING': 'Long and restorative',
    'RECOVERING': 'Restorative',
    'SHORT_AND_POOR_STRUCTURE': 'Short and poorly structured',
    'OPTIMAL_STRUCTURE': 'Well-balanced stages',
    'DEEP': 'Plenty of deep sleep',
    'SHORT_AND_POOR_QUALITY': 'Short and poor quality',
    'LONG_AND_DEEP': 'Long and deep',
    'SHORT_BUT_CONTINUOUS': 'Short, but unbroken',
    'SHORT_AND_NONRECOVERING': 'Short and not restorative',
    'SHORT_BUT_RECOVERING': 'Short, but restorative',
    'CONTINUOUS': 'Unbroken',
    'SHORT_BUT_DEEP': 'Short, but deep',
    'LONG_BUT_NOT_RESTORATIVE': 'Long, but not restorative',
    'POOR_STRUCTURE': 'Poorly structured',
    'REFRESHING': 'Refreshing',
    'LONG_BUT_LIGHT': 'Long, but light',
    'LONG_BUT_RESTLESS': 'Long, but restless',
    'LONG_BUT_DISCONTINUOUS': 'Long, but broken up',
    'LONG_AND_REFRESHING': 'Long and refreshing',
    'LIGHT': 'Mostly light sleep',
    'RESTLESS': 'Restless',
    'LONG_BUT_POOR_QUALITY': 'Long, but poor quality',
  };
  final key = code.replaceFirst(RegExp(r'^(POSITIVE|NEGATIVE)_'), '');
  final hit = known[key];
  if (hit != null) return hit;
  final words = key.toLowerCase().replaceAll('_', ' ');
  return words.isEmpty ? '' : '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Day-level wellness numbers that are not tied to one night.
class DayStats {
  const DayStats({this.restingHr, this.stress, this.steps, this.bodyBatteryHigh, this.bodyBatteryLow});
  final int? restingHr, stress, steps, bodyBatteryHigh, bodyBatteryLow;
}

/// Everything the Recovery side reads.
class RecoveryData {
  RecoveryData({required List<SleepNight> nights, this.days = const {}})
      : nights = [...nights]..sort((a, b) => a.date.compareTo(b.date));

  /// Oldest first.
  final List<SleepNight> nights;
  final Map<DateTime, DayStats> days;

  bool get isEmpty => nights.isEmpty;

  /// The most recent night on or before [day].
  SleepNight? nightFor(DateTime day) {
    for (final n in nights.reversed) {
      if (!n.date.isAfter(day)) return n;
    }
    return null;
  }

  SleepNight? byDate(DateTime d) {
    for (final n in nights) {
      if (n.date == d) return n;
    }
    return null;
  }

  /// Nights in the [count] days ending on [day].
  List<SleepNight> window(DateTime day, int count) {
    final from = DateTime(day.year, day.month, day.day - count + 1);
    return [for (final n in nights) if (!n.date.isBefore(from) && !n.date.isAfter(day)) n];
  }

  /// Mean resting HR over the [count] days before [day] (not including it).
  double? restingBaseline(DateTime day, {int count = 30}) {
    var sum = 0, n = 0;
    for (var i = 1; i <= count; i++) {
      final d = DateTime(day.year, day.month, day.day - i);
      final v = days[d]?.restingHr ?? byDate(d)?.restingHr;
      if (v == null) continue;
      sum += v;
      n++;
    }
    return n < 5 ? null : sum / n;
  }
}
