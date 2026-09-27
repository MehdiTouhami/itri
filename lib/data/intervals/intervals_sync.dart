import 'dart:math' as math;

import 'intervals_client.dart';
import 'intervals_mapper.dart';

/// What one sync produced. [store] is the full live data set, in the same
/// JSON shape as the converted Garmin export.
class SyncResult {
  const SyncResult(this.store, {required this.newSessions, required this.newNights, required this.stoppedEarly});
  final Map<String, dynamic> store;
  final int newSessions, newNights;

  /// intervals.icu rate-limited us part-way; the rest comes on the next sync.
  final bool stoppedEarly;

  String get summary {
    String n(int v, String what) => '$v new $what${v == 1 ? '' : 's'}';
    final parts = [if (newSessions > 0) n(newSessions, 'session'), if (newNights > 0) n(newNights, 'night')];
    final base = parts.isEmpty ? 'Up to date' : parts.join(', ');
    return stoppedEarly ? '$base · the rest follows on the next sync' : base;
  }
}

/// Incremental sync: only sessions not seen before are downloaded in full.
class IntervalsSync {
  IntervalsSync(this.client, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final IntervalsClient client;
  final DateTime Function() _now;

  /// How far back the very first sync reaches when there is no export:
  /// enough for the 42-day fitness average and the trend charts.
  static const firstSyncDays = 120;

  Future<SyncResult> run({
    Map<String, dynamic>? previous,
    DateTime? historyEnd,
    void Function(int done, int total)? onProgress,
  }) async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime back(DateTime d, int days) => DateTime(d.year, d.month, d.day - days);

    // Always list the whole window, not just since the last sync: Garmin
    // backfills history into intervals.icu over hours, and sessions sometimes
    // sync late. Listing is one cheap request; only unseen sessions are
    // downloaded in full. Wellness is re-read for the same window because
    // sleep scores and HRV can be revised after the fact.
    final from = historyEnd != null ? back(historyEnd, 3) : back(today, firstSyncDays);
    final weekAgo = back(today, 7);
    final wellnessFrom = from.isBefore(weekAgo) ? from : weekAgo;

    final profile = await client.athlete();
    final summaries = await client.activities(from, today);
    final wellness = await client.wellness(wellnessFrom, today);

    final oldActivities = [
      for (final a in previous?['activities'] as List? ?? const []) if (a is Map<String, dynamic>) a,
    ];
    final known = {for (final a in oldActivities) a['icuId']};
    final todo = [
      for (final m in summaries)
        if (isUsable(m) &&
            !known.contains('${m['id']}') &&
            sportOf(m['type'] as String?, m['name'] as String?) != null)
          m,
    ];

    final fresh = <Map<String, dynamic>>[];
    var done = 0;
    var stopped = false;
    IntervalsException? fatal;
    onProgress?.call(0, todo.length);
    Future<void> fetch(Map<String, dynamic> m) async {
      if (stopped) return;
      try {
        final a = activityJson(m, await client.streams('${m['id']}'));
        if (a != null) fresh.add(a);
      } on IntervalsException catch (e) {
        if (e.rateLimited || e.auth) {
          stopped = true;
          if (e.auth) fatal = e;
        }
        // Anything else: skip this session and carry on.
      }
      onProgress?.call(++done, todo.length);
    }

    await _pool(todo, 3, fetch);
    if (fatal != null) throw fatal!;

    final w = wellnessJson(wellness);
    final nights = <String, Map<String, dynamic>>{
      for (final n in previous?['nights'] as List? ?? const [])
        if (n is Map<String, dynamic> && n['date'] is String) n['date'] as String: n,
    };
    var newNights = 0;
    for (final n in w.nights) {
      final date = n['date'] as String;
      if (!nights.containsKey(date)) newNights++;
      nights[date] = n;
    }
    final days = <String, dynamic>{...?(previous?['days'] as Map<String, dynamic>?), ...w.days};

    final rests = [for (final n in nights.values) if (n['rhr'] is num) (n['rhr'] as num).round()]..sort();
    final activities = [...oldActivities, ...fresh]
      ..sort((a, b) => (b['start'] as String).compareTo(a['start'] as String));
    final orderedNights = nights.values.toList()..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final previousMark = previous?['syncedAt'];
    return SyncResult(
      {
        'version': 1,
        'source': 'intervals.icu',
        // After a partial sync keep the old mark, so the next run covers the same window.
        'syncedAt': stopped ? previousMark : now.toIso8601String(),
        'exportedAt': '${today.year}-${_two(today.month)}-${_two(today.day)}',
        'athlete': athleteJson(profile, restingFallback: rests.isEmpty ? null : rests[rests.length ~/ 2]),
        'activities': activities,
        'nights': orderedNights,
        'days': days,
      },
      newSessions: fresh.length,
      newNights: newNights,
      stoppedEarly: stopped,
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Runs [f] over [items] with at most [n] requests in flight.
  static Future<void> _pool<T>(List<T> items, int n, Future<void> Function(T) f) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await f(items[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < math.min(n, items.length); i++) worker()]);
  }
}
