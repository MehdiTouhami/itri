import 'dart:math' as math;

import 'aggregates.dart';
import 'analysis.dart';
import 'athlete.dart';
import 'readiness.dart';
import 'sleep.dart';
import 'sleep_stats.dart';
import 'sport_stats.dart';
import 'training_load.dart';

/// The exact numbers the coach is allowed to talk about. Built on the phone,
/// so the model never has to guess dates or averages from loose snippets.
String buildFacts({
  required DateTime asOf,
  required Athlete athlete,
  required List<ActivityAnalysis> sessions,
  required List<DayLoad> load,
  required RecoveryData recovery,
  required List<SportSummary> sports,
  Readiness? readiness,
}) {
  final b = StringBuffer()
    ..writeln('YOUR DATA (as of ${_d(asOf)}). These figures are exact. Do not invent others.')
    ..writeln()
    ..writeln('PROFILE: max HR ${athlete.maxHr}, resting HR ${athlete.restHr}.');

  if (readiness != null) {
    b
      ..writeln()
      ..writeln('READINESS TODAY: ${readiness.level.label}. '
          '${readiness.factors.map((f) => '${f.label} ${f.value} (${f.note})').join('; ')}.');
  }

  if (load.isNotEmpty) {
    final today = load.last;
    final weekAgo = load.length > 7 ? load[load.length - 8] : load.first;
    b
      ..writeln()
      ..writeln('TRAINING LOAD: fitness ${today.fitness.round()}, fatigue ${today.fatigue.round()}, '
          'form ${today.form.round()} (${today.state.label}). '
          'Fitness change over 7 days: ${(today.fitness - weekAgo.fitness).toStringAsFixed(1)}.');
  }

  final weeks = weeklyTotals(sessions, asOf, 2);
  if (weeks.length == 2) {
    String w(WeekTotals x) =>
        '${x.sessions} sessions, ${_hm(x.seconds)}, load ${x.load.round()}, '
        '${((x.zoneSeconds[3] + x.zoneSeconds[4]) / 60).round()} min in zones 4-5';
    b
      ..writeln('THIS WEEK (from ${_d(weeks[1].monday)}): ${w(weeks[1])}.')
      ..writeln('LAST WEEK: ${w(weeks[0])}.');
  }

  final from = DateTime(asOf.year, asOf.month, asOf.day - 13);
  final recent = sessions.where((x) => !x.activity.day.isBefore(from) && !x.activity.day.isAfter(asOf)).toList();
  b
    ..writeln()
    ..writeln('SESSIONS, LAST 14 DAYS (date | sport | start | duration | load | avg HR | hard efforts):');
  if (recent.isEmpty) b.writeln('none');
  for (final x in recent) {
    final a = x.activity;
    b.writeln('${_d(a.day)} | ${a.sport.label} | ${_clock(a.start)} | ${_hm(a.durationS)} | '
        '${x.load.round()} | ${a.avgHr} | ${x.efforts.length}');
  }

  final nights = recovery.window(asOf, 14).reversed.toList();
  if (nights.isNotEmpty) {
    b
      ..writeln()
      ..writeln('SLEEP, LAST 14 NIGHTS (night of | score | asleep | deep | REM | asleep at | woke | HRV | resting HR):');
    for (final n in nights) {
      b.writeln('${_d(n.evening)} | ${n.score} | ${_hm(n.asleepS)} | ${n.hasStages ? _hm(n.deepS) : 'n/a'} | '
          '${n.remS == null ? 'n/a' : _hm(n.remS!)} | ${n.start == null ? 'n/a' : _clock(n.start!)} | '
          '${n.end == null ? 'n/a' : _clock(n.end!)} | '
          '${n.hrv?.round() ?? 'n/a'} | ${n.restingHr ?? 'n/a'}');
    }
    String avg(List<SleepNight> ns) {
      if (ns.isEmpty) return 'no data';
      final hrv = [for (final n in ns) if (n.hrv != null) n.hrv!];
      return 'score ${(ns.fold<int>(0, (a, n) => a + n.score) / ns.length).round()}, '
          'asleep ${_hm(ns.fold<int>(0, (a, n) => a + n.asleepS) ~/ ns.length)}'
          '${hrv.isEmpty ? '' : ', HRV ${(hrv.reduce((a, c) => a + c) / hrv.length).round()}'}';
    }

    final last7 = recovery.window(asOf, 7);
    final prev28 = recovery.window(DateTime(asOf.year, asOf.month, asOf.day - 7), 28);
    b.writeln('LAST 7 NIGHTS average: ${avg(last7)}. THE 28 NIGHTS BEFORE: ${avg(prev28)}.');
    final lastNight = nights.first;
    if (lastNight.hrvLow != null && lastNight.hrvHigh != null) {
      b.writeln('USUAL HRV RANGE: ${lastNight.hrvLow!.round()}-${lastNight.hrvHigh!.round()} ms.');
    }
  }

  if (sports.isNotEmpty) {
    b
      ..writeln()
      ..writeln('SPORTS, ALL TIME: ${sports.map((s) => '${s.sport.label} ${s.count} sessions, '
          '${s.hours.round()} h, load per hour ${s.loadPerHour.round()}'
          '${s.recovery == null ? '' : ', recovery after efforts ${s.recovery!.round()} bpm'}').join('; ')}.');
  }

  final after = sleepAfterTraining(recovery, sessions);
  if (after.isNotEmpty) {
    b
      ..writeln()
      ..writeln('TRAINING AND THE NEXT NIGHT (your history, observational): ${after.map((g) => '${g.label}: '
          '${g.nights} nights, score ${g.score.toStringAsFixed(1)}, asleep ${_hm((g.asleepH * 3600).round())}'
          '${g.hrv == null ? '' : ', HRV ${g.hrv!.round()}'}').join('; ')}.');
  }
  return b.toString();
}

/// Numbers in [reply] that appear nowhere in [facts] (allowing for rounding).
/// Small whole numbers are skipped: "3 tips" is not a data claim.
List<String> unverifiedNumbers(String reply, String facts) {
  final re = RegExp(r'(?<![\d.])\d+(?:\.\d+)?');
  final known = re.allMatches(facts).map((m) => double.parse(m.group(0)!)).toSet();
  final out = <String>[];
  for (final m in re.allMatches(reply)) {
    final s = m.group(0)!;
    final v = double.parse(s);
    if (v < 10 && !s.contains('.')) continue;
    final ok = known.any((k) => (k - v).abs() <= math.max(0.5, k.abs() * 0.01));
    if (!ok && !out.contains(s)) out.add(s);
  }
  return out;
}

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _hm(int s) => '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
