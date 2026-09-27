import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/activity.dart';
import '../../domain/athlete.dart';
import '../../domain/sample.dart';
import '../../domain/sleep.dart';
import '../../domain/sport.dart';

/// How closely our load model tracks the watch's own figure (Pearson r).
class LoadCheck {
  const LoadCheck({required this.n, required this.pearson, required this.spearman, required this.bySport});

  /// No comparison available (live data carries no Garmin load figures).
  const LoadCheck.none() : n = 0, pearson = 0, spearman = 0, bySport = const {};

  final int n;
  final double pearson;
  final double spearman;
  final Map<Sport, ({int n, double r})> bySport;
}

/// The user's own data. Either a Garmin Connect export converted by
/// `tools/garmin_import.py`, a live intervals.icu sync stored in the same
/// shape, or the two merged (see [mergeBundles]).
class GarminBundle {
  const GarminBundle({
    required this.source,
    required this.dataUntil,
    required this.athlete,
    required this.restingHr,
    required this.check,
    required this.activities,
    required this.recovery,
  });

  static const assetPath = 'assets/private/garmin_bundle.json';

  final String source;
  final DateTime dataUntil;
  final Athlete athlete;
  final Map<DateTime, int> restingHr;
  final LoadCheck check;
  final List<Activity> activities; // newest first
  final RecoveryData recovery;

  /// Null when no export has been converted, so the app falls back to samples.
  static Future<GarminBundle?> load(AssetBundle assets) async {
    final String raw;
    try {
      raw = await assets.loadString(assetPath, cache: false);
    } catch (_) {
      return null;
    }
    final json = await compute(_decode, raw);
    return GarminBundle.fromJson(json);
  }

  static Map<String, dynamic> _decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  factory GarminBundle.fromJson(Map<String, dynamic> j) {
    final a = j['athlete'] as Map<String, dynamic>;
    final birthYear = a['birthYear'] as int?;
    final athlete = Athlete(
      name: a['name'] as String? ?? 'Athlete',
      maxHr: (a['maxHr'] as num).toInt(),
      restHr: (a['restHr'] as num).toInt(),
      weightKg: (a['weightKg'] as num).toDouble(),
    );

    final activities = <Activity>[];
    for (final raw in j['activities'] as List) {
      final m = raw as Map<String, dynamic>;
      final sport = Sport.byName(m['sport'] as String);
      if (sport == null) continue;
      final start = DateTime.parse(m['start'] as String);
      final samples = _samples(m['s'] as Map<String, dynamic>);
      if (samples.length < 2) continue;
      activities.add(Activity.fromSamples(
        id: (m['id'] as num).toInt(),
        sport: sport,
        name: m['name'] as String,
        start: start,
        locality: m['locality'] as String? ?? '',
        samples: samples,
        weightKg: athlete.weightKg,
        ageYears: birthYear == null ? 30 : start.year - birthYear,
        calories: (m['calories'] as num?)?.toInt(),
        indoor: m['indoor'] as bool? ?? false,
        deviceLoad: (m['garminLoad'] as num?)?.toDouble(),
        aerobicTE: (m['aerobicTE'] as num?)?.toDouble(),
        anaerobicTE: (m['anaerobicTE'] as num?)?.toDouble(),
      ));
    }
    activities.sort((x, y) => y.start.compareTo(x.start));

    final v = j['validation'] as Map<String, dynamic>?;
    final bySport = <Sport, ({int n, double r})>{};
    (v?['bySport'] as Map<String, dynamic>? ?? const {}).forEach((k, e) {
      final s = Sport.byName(k);
      final m = e as Map<String, dynamic>;
      if (s != null) bySport[s] = (n: (m['n'] as num).toInt(), r: (m['r'] as num).toDouble());
    });

    return GarminBundle(
      source: j['source'] as String? ?? 'Garmin',
      dataUntil: DateTime.parse(j['exportedAt'] as String),
      athlete: athlete,
      restingHr: {
        for (final e in (j['restingHr'] as Map<String, dynamic>? ?? const {}).entries)
          DateTime.parse(e.key): (e.value as num).toInt(),
      },
      check: v == null
          ? const LoadCheck.none()
          : LoadCheck(
              n: (v['n'] as num).toInt(),
              pearson: (v['pearson'] as num).toDouble(),
              spearman: (v['spearman'] as num).toDouble(),
              bySport: bySport,
            ),
      activities: activities,
      recovery: RecoveryData(
        nights: [
          for (final raw in j['nights'] as List<dynamic>? ?? const [])
            _night(raw as Map<String, dynamic>),
        ],
        days: {
          for (final e in (j['days'] as Map<String, dynamic>? ?? const {}).entries)
            DateTime.parse(e.key): _day(e.value as Map<String, dynamic>),
        },
      ),
    );
  }

  static SleepNight _night(Map<String, dynamic> m) {
    int? i(String k) => (m[k] as num?)?.round();
    double? d(String k) => (m[k] as num?)?.toDouble();
    DateTime? at(String k) => m[k] == null ? null : DateTime.parse(m[k] as String);
    return SleepNight(
      date: DateTime.parse(m['date'] as String),
      start: at('start'),
      end: at('end'),
      deepS: i('deep') ?? 0,
      lightS: i('light') ?? 0,
      remS: i('rem'),
      awakeS: i('awake') ?? 0,
      totalSleepS: i('total'),
      score: i('score') ?? 0,
      subScores: {
        for (final e in (m['sub'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as num).round(),
      },
      feedback: m['feedback'] as String?,
      respiration: d('resp'),
      stress: d('stress'),
      restless: i('restless'),
      awakenings: i('awakenings'),
      hrv: d('hrv'),
      hrvLow: d('hrvLow'),
      hrvHigh: d('hrvHigh'),
      restingHr: i('rhr'),
    );
  }

  static DayStats _day(Map<String, dynamic> m) {
    int? i(String k) => (m[k] as num?)?.round();
    return DayStats(
      restingHr: i('rhr'),
      stress: i('stress'),
      steps: i('steps'),
      bodyBatteryHigh: i('bbHigh'),
      bodyBatteryLow: i('bbLow'),
    );
  }

  /// Columnar arrays (t, hr, d, v, alt, lat, lon, cad, pw) back into samples.
  static List<Sample> _samples(Map<String, dynamic> s) {
    final t = (s['t'] as List).cast<num>();
    List<dynamic>? col(String k) => s[k] as List<dynamic>?;
    final hr = col('hr'), d = col('d'), v = col('v'), alt = col('alt');
    final lat = col('lat'), lon = col('lon'), cad = col('cad'), pw = col('pw');
    double? dbl(List<dynamic>? c, int i) => (c?[i] as num?)?.toDouble();
    int? integer(List<dynamic>? c, int i) => (c?[i] as num?)?.round();
    return [
      for (var i = 0; i < t.length; i++)
        Sample(
          t: t[i].toInt(),
          heartRate: integer(hr, i),
          distanceM: dbl(d, i),
          speedMs: dbl(v, i),
          altitudeM: dbl(alt, i),
          lat: dbl(lat, i),
          lon: dbl(lon, i),
          cadence: integer(cad, i),
          power: integer(pw, i),
        ),
    ];
  }
}

/// The export and the live sync as one data set.
///
/// The export is richer (sleep stages, bed times, Garmin's load and HRV range),
/// so it wins wherever both have the same session or night; the live sync adds
/// everything else. Nights without a usual HRV range get one computed from the
/// nights before them, export history included.
GarminBundle? mergeBundles(GarminBundle? export, GarminBundle? live) {
  if (export == null && live == null) return null;
  final base = export ?? live!;

  final activities = [...?export?.activities];
  for (final a in live?.activities ?? const <Activity>[]) {
    final dup = activities.any((e) => e.start.difference(a.start).inSeconds.abs() <= 120);
    if (!dup) activities.add(a);
  }
  activities.sort((x, y) => y.start.compareTo(x.start));

  final nights = <DateTime, SleepNight>{
    for (final n in live?.recovery.nights ?? const <SleepNight>[]) n.date: n,
    for (final n in export?.recovery.nights ?? const <SleepNight>[]) n.date: n,
  };
  final days = <DateTime, DayStats>{...?live?.recovery.days, ...?export?.recovery.days};
  final ordered = nights.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  final until = [export?.dataUntil, live?.dataUntil].whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
  return GarminBundle(
    source: export != null && live != null ? '${export.source} + intervals.icu' : base.source,
    dataUntil: until,
    athlete: base.athlete,
    restingHr: {...?live?.restingHr, ...?export?.restingHr},
    check: base.check,
    activities: activities,
    recovery: RecoveryData(nights: withHrvRanges(ordered), days: days),
  );
}
