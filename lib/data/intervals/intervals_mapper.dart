import 'dart:math' as math;

import '../../domain/sample.dart';
import '../../domain/sport.dart';

// Same processing as tools/garmin_import.py, so live sessions and exported
// sessions go through identical analysis.
const _dt = 5; // output sample spacing (s)
const _pauseGap = 30; // a gap longer than this is a pause, not recorded time
const _privacyM = 500.0; // GPS removed within this distance of start and finish

/// Sport from intervals.icu's activity type, falling back to the session name
/// (Garmin names sessions "Preston Padel" even when the type is generic).
/// Null for sports the app does not model.
Sport? sportOf(String? type, String? name) {
  Sport? match(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('padel')) return Sport.padel;
    if (s.contains('squash')) return Sport.squash;
    if (s.contains('tennis') && !s.contains('table')) return Sport.tennis;
    if (s.contains('soccer') || s.contains('football')) return Sport.football;
    if (s.contains('ride') || s.contains('cycl') || s.contains('bike')) return Sport.ride;
    if (s.contains('run')) return Sport.run;
    if (s.contains('walk') || s.contains('hike')) return Sport.walk;
    if (s.contains('weight') || s.contains('strength')) return Sport.strength;
    return null;
  }

  return match(type ?? '') ?? match(name ?? '');
}

class _Pt {
  _Pt(this.t, this.hr, this.d, this.v, this.alt, this.lat, this.lon, this.cad, this.pw);
  final double t;
  final double? hr, d, v, alt, lat, lon, cad, pw;
}

/// intervals.icu streams -> 5 s samples: pauses collapsed, values averaged per
/// bucket, distance taken at the end of each bucket, GPS privacy applied.
List<Sample> samplesFromStreams(List<Map<String, dynamic>> streams, Sport sport, {bool indoor = false}) {
  List<num?>? col(String type, [String key = 'data']) {
    for (final s in streams) {
      if (s['type'] != type) continue;
      final d = s[key];
      return d is List ? [for (final e in d) e is num ? e : null] : null;
    }
    return null;
  }

  final time = col('time');
  if (time == null || time.length < 2) return const [];
  final hr = col('heartrate'), dist = col('distance'), vel = col('velocity_smooth'), alt = col('altitude');
  final lat = col('latlng'), lon = col('latlng', 'data2'), cad = col('cadence'), pw = col('watts');
  double? at(List<num?>? c, int i) => c == null || i >= c.length ? null : c[i]?.toDouble();

  // Runs: steps per minute. Anything under 120 is strides per minute, so double it.
  var cadScale = 1.0;
  if (sport == Sport.run && cad != null) {
    final vals = [for (final c in cad) if (c != null && c > 0) c.toDouble()]..sort();
    if (vals.isNotEmpty && vals[vals.length ~/ 2] < 120) cadScale = 2;
  }

  final pts = <_Pt>[];
  var t = 0.0;
  num? prev;
  for (var i = 0; i < time.length; i++) {
    final ts = time[i];
    if (ts == null) continue;
    if (prev != null) {
      final gap = (ts - prev).toDouble();
      t += gap > _pauseGap ? _dt : gap;
    }
    prev = ts;
    final c = at(cad, i);
    pts.add(_Pt(t, at(hr, i), at(dist, i), at(vel, i), at(alt, i), at(lat, i), at(lon, i),
        sport == Sport.run && c != null ? c * cadScale : null, at(pw, i)));
  }
  if (pts.isEmpty) return const [];

  final out = <Sample>[];
  var bucket = <_Pt>[];
  var edge = _dt.toDouble();
  void flush() {
    if (bucket.isEmpty) return;
    double? mean(double? Function(_Pt) f) {
      var sum = 0.0, n = 0;
      for (final p in bucket) {
        final x = f(p);
        if (x == null) continue;
        sum += x;
        n++;
      }
      return n == 0 ? null : sum / n;
    }

    double? lastD;
    for (final p in bucket.reversed) {
      if (p.d != null) {
        lastD = p.d;
        break;
      }
    }
    out.add(Sample(
      t: bucket.first.t ~/ _dt * _dt,
      heartRate: mean((p) => p.hr)?.round(),
      distanceM: lastD,
      speedMs: mean((p) => p.v),
      altitudeM: mean((p) => p.alt),
      lat: mean((p) => p.lat),
      lon: mean((p) => p.lon),
      cadence: mean((p) => p.cad)?.round(),
      power: mean((p) => p.pw)?.round(),
    ));
  }

  for (final p in pts) {
    while (p.t >= edge) {
      flush();
      bucket = [];
      edge += _dt;
    }
    bucket.add(p);
  }
  flush();
  final last = out.last;
  out.add(_copy(last, t: math.max(last.t + 1, pts.last.t.round())));

  // Court and pitch sports, and indoor sessions, keep no GPS at all.
  if (!sport.hasGps || indoor) return [for (final s in out) _copy(s, noGps: true)];
  var total = 0.0;
  for (final s in out.reversed) {
    if (s.distanceM != null) {
      total = s.distanceM!;
      break;
    }
  }
  return [
    for (final s in out)
      s.distanceM == null || s.distanceM! < _privacyM || s.distanceM! > total - _privacyM ? _copy(s, noGps: true) : s,
  ];
}

Sample _copy(Sample s, {int? t, bool noGps = false}) => Sample(
      t: t ?? s.t,
      lat: noGps ? null : s.lat,
      lon: noGps ? null : s.lon,
      altitudeM: s.altitudeM,
      distanceM: s.distanceM,
      speedMs: s.speedMs,
      heartRate: s.heartRate,
      cadence: s.cadence,
      power: s.power,
    );

/// Samples as the bundle's columnar arrays (same rounding as the converter).
Map<String, dynamic> columnsOf(List<Sample> samples) {
  List<num?>? col(num? Function(Sample) f, int digits) {
    final v = [for (final s in samples) f(s)];
    if (v.every((e) => e == null)) return null;
    return [
      for (final e in v)
        e == null ? null : (digits == 0 ? e.round() : double.parse(e.toStringAsFixed(digits))),
    ];
  }

  final cols = <String, dynamic>{
    't': [for (final s in samples) s.t],
    'hr': col((s) => s.heartRate, 0),
    'd': col((s) => s.distanceM, 1),
    'v': col((s) => s.speedMs, 2),
    'alt': col((s) => s.altitudeM, 1),
    'lat': col((s) => s.lat, 5),
    'lon': col((s) => s.lon, 5),
    'cad': col((s) => s.cadence, 0),
    'pw': col((s) => s.power, 0),
  };
  cols.removeWhere((_, v) => v == null);
  return cols;
}

/// Whether a session summary can be fetched in full. Sessions that reached
/// intervals.icu through Strava come back as stubs (Strava's API terms).
bool isUsable(Map<String, dynamic> m) =>
    m['id'] != null && m['start_date_local'] is String && m['source'] != 'STRAVA' && !m.containsKey('_note');

/// One session in the bundle's activity format, or null if the app does not
/// model the sport or the recording is empty.
Map<String, dynamic>? activityJson(Map<String, dynamic> m, List<Map<String, dynamic>> streams) {
  final type = m['type'] as String?, name = m['name'] as String?;
  final sport = sportOf(type, name);
  final start = m['start_date_local'] as String?;
  if (sport == null || start == null) return null;
  final indoor = m['trainer'] == true || (type ?? '').startsWith('Virtual');
  final samples = samplesFromStreams(streams, sport, indoor: indoor);
  if (samples.length < 2) return null;
  return {
    'id': numericId(m['id']),
    'icuId': '${m['id']}',
    'sport': sport.name,
    'name': (name == null || name.isEmpty) ? sport.label : name,
    'start': start,
    'locality': '',
    'calories': (m['calories'] as num?)?.round(),
    'indoor': indoor,
    's': columnsOf(samples),
  };
}

/// intervals.icu ids look like "i12345678"; the app keys sessions by int.
int numericId(Object? id) => int.tryParse('$id'.replaceAll(RegExp(r'\D'), '')) ?? '$id'.hashCode;

/// Daily wellness rows -> bundle nights (only when there is a scored sleep)
/// and day stats. Sleep is filed on the wake-up date, like the export.
({List<Map<String, dynamic>> nights, Map<String, Map<String, dynamic>> days}) wellnessJson(
    List<Map<String, dynamic>> rows) {
  final nights = <Map<String, dynamic>>[];
  final days = <String, Map<String, dynamic>>{};
  for (final w in rows) {
    final date = w['id'];
    if (date is! String || DateTime.tryParse(date) == null) continue;
    final sleep = (w['sleepSecs'] as num?)?.round();
    final score = (w['sleepScore'] as num?)?.round();
    final hrv = (w['hrv'] as num?)?.toDouble();
    final rhr = (w['restingHR'] as num?)?.round();
    if (sleep != null && sleep > 0 && score != null) {
      nights.add(<String, dynamic>{
        'date': date,
        'total': sleep,
        'score': score,
        'hrv': hrv,
        'rhr': rhr,
        'resp': (w['respiration'] as num?)?.toDouble(),
      }..removeWhere((_, v) => v == null));
    }
    final day = <String, dynamic>{'rhr': rhr, 'steps': (w['steps'] as num?)?.round()}
      ..removeWhere((_, v) => v == null);
    if (day.isNotEmpty) days[date] = day;
  }
  return (nights: nights, days: days);
}

/// The key owner's physiology, as the bundle's athlete block.
Map<String, dynamic> athleteJson(Map<String, dynamic> j, {int? restingFallback}) {
  int? maxHr;
  for (final s in j['sportSettings'] as List? ?? const []) {
    final v = s is Map<String, dynamic> ? s['max_hr'] as num? : null;
    if (v != null && v > 0 && (maxHr == null || v > maxHr)) maxHr = v.round();
  }
  final first = j['firstname'] as String? ?? (j['name'] as String?)?.split(' ').first;
  return {
    'name': (first == null || first.isEmpty) ? 'Athlete' : first,
    'maxHr': maxHr ?? 190,
    'restHr': (j['icu_resting_hr'] as num?)?.round() ?? restingFallback ?? 55,
    'weightKg': (j['icu_weight'] as num?)?.toDouble() ?? (j['weight'] as num?)?.toDouble() ?? 75.0,
  };
}
