import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/activity_repository.dart';
import '../data/garmin/garmin_bundle.dart';
import '../data/intervals/intervals_client.dart';
import '../data/intervals/intervals_sync.dart';
import '../data/intervals/live_store.dart';
import '../data/synthetic/synthetic_sleep.dart';
import '../domain/activity.dart';
import '../domain/analysis.dart';
import '../domain/athlete.dart';
import '../domain/facts.dart';
import '../domain/hr_zones.dart';
import '../domain/readiness.dart';
import '../domain/sleep.dart';
import '../domain/sport_stats.dart';
import '../domain/training_load.dart';

enum DataSource { sample, garmin }

/// The converted Garmin export, or null when none is bundled.
final exportBundleProvider = FutureProvider<GarminBundle?>((ref) => GarminBundle.load(rootBundle));

/// The user's own data: the export merged with everything synced live since.
/// Synchronous once both sources have loaded, so a finished sync swaps the
/// data in place instead of dropping every screen back to a spinner.
final garminBundleProvider = Provider<AsyncValue<GarminBundle?>>((ref) {
  final export = ref.watch(exportBundleProvider);
  final live = ref.watch(liveProvider);
  if (export is AsyncError<GarminBundle?>) return AsyncError(export.error, export.stackTrace);
  if (export is! AsyncData<GarminBundle?> || live is! AsyncData<LiveData>) return const AsyncLoading();
  return AsyncData(mergeBundles(export.value, live.value.bundle));
});

GarminBundle? _bundleNow(Ref ref) => switch (ref.watch(garminBundleProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };

/// What the user picked. Real data is the default whenever it exists.
class DataSourceNotifier extends Notifier<DataSource> {
  @override
  DataSource build() => DataSource.garmin;

  void set(DataSource s) => state = s;
}

final dataSourceProvider = NotifierProvider<DataSourceNotifier, DataSource>(DataSourceNotifier.new);

/// What is actually on screen: Garmin only if a bundle loaded.
final effectiveSourceProvider = Provider<DataSource>((ref) {
  final want = ref.watch(dataSourceProvider);
  return want == DataSource.garmin && _bundleNow(ref) != null ? DataSource.garmin : DataSource.sample;
});

final _syntheticProvider = Provider<ActivityRepository>((ref) => SyntheticActivityRepository());

final repositoryProvider = Provider<AsyncValue<ActivityRepository>>((ref) {
  final want = ref.watch(dataSourceProvider);
  final synthetic = ref.watch(_syntheticProvider);
  return ref.watch(garminBundleProvider).whenData(
        (bundle) => want == DataSource.garmin && bundle != null ? GarminActivityRepository(bundle) : synthetic,
      );
});

final activitiesProvider = Provider<AsyncValue<List<Activity>>>(
  (ref) => ref.watch(repositoryProvider).whenData((repo) => repo.all()),
);

/// The day the dashboard treats as "today". Imported data stops at the export,
/// so anchoring on the calendar would show months of empty weeks.
final asOfProvider = Provider<DateTime>((ref) {
  final bundle = _bundleNow(ref);
  final d = ref.watch(effectiveSourceProvider) == DataSource.garmin && bundle != null
      ? bundle.dataUntil
      : DateTime.now();
  return DateTime(d.year, d.month, d.day);
});

class AthleteNotifier extends Notifier<Athlete> {
  @override
  Athlete build() {
    final bundle = _bundleNow(ref);
    if (ref.watch(effectiveSourceProvider) == DataSource.garmin && bundle != null) return bundle.athlete;
    return const Athlete();
  }

  void update(Athlete Function(Athlete) change) => state = change(state);
}

final athleteProvider = NotifierProvider<AthleteNotifier, Athlete>(AthleteNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

final zonesProvider = Provider<HrZoneModel>((ref) => HrZoneModel.forAthlete(ref.watch(athleteProvider)));

/// Every activity with its athlete-dependent analysis, newest first.
final analysesProvider = Provider<AsyncValue<List<ActivityAnalysis>>>((ref) {
  final athlete = ref.watch(athleteProvider);
  final zones = ref.watch(zonesProvider);
  return ref.watch(activitiesProvider).whenData(
        (list) => [for (final a in list) ActivityAnalysis.of(a, athlete, zones)],
      );
});

final analysisByIdProvider = Provider.family<ActivityAnalysis?, int>((ref, id) {
  final v = ref.watch(analysesProvider);
  if (v is! AsyncData<List<ActivityAnalysis>>) return null;
  for (final x in v.value) {
    if (x.activity.id == id) return x;
  }
  return null;
});

/// Daily fitness / fatigue / form over the whole history.
final loadSeriesProvider = Provider<AsyncValue<List<DayLoad>>>((ref) {
  final asOf = ref.watch(asOfProvider);
  return ref.watch(analysesProvider).whenData((list) {
    if (list.isEmpty) return const <DayLoad>[];
    final daily = dailyLoadOf([for (final x in list) (x.activity, x.load)]);
    return loadSeries(daily, list.last.activity.day, asOf);
  });
});

/// Per-sport totals, most time first.
final sportSummariesProvider = Provider<AsyncValue<List<SportSummary>>>(
  (ref) => ref.watch(analysesProvider).whenData(sportSummaries),
);

// ─── Modes ──────────────────────────────────────────────────────────────

enum AppMode { training, recovery }

class AppModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() => AppMode.training;

  void set(AppMode m) => state = m;
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(AppModeNotifier.new);

// ─── Recovery ───────────────────────────────────────────────────────────

/// Nights and wellness days: from the Garmin export when it is in use,
/// otherwise sample nights generated to match the sample training.
final recoveryProvider = Provider<AsyncValue<RecoveryData>>((ref) {
  if (ref.watch(effectiveSourceProvider) == DataSource.garmin) {
    return ref.watch(garminBundleProvider).whenData((b) => b?.recovery ?? RecoveryData(nights: const []));
  }
  final asOf = ref.watch(asOfProvider);
  return ref.watch(activitiesProvider).whenData((list) => SyntheticSleep(activities: list, to: asOf).generate());
});

/// This morning's verdict, when there is a recent night to base it on.
final readinessProvider = Provider<Readiness?>((ref) {
  final rec = switch (ref.watch(recoveryProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (rec == null || rec.isEmpty) return null;
  final asOf = ref.watch(asOfProvider);
  final night = rec.nightFor(asOf);
  if (night == null || asOf.difference(night.date).inDays > 2) return null;
  final series = switch (ref.watch(loadSeriesProvider)) {
    AsyncData(:final value) => value,
    _ => const <DayLoad>[],
  };
  return Readiness.from(
    night: night,
    restingBaseline: rec.restingBaseline(night.date),
    load: series.isEmpty ? null : series.last,
  );
});

/// The coach's view of the user: exact numbers from both halves of the app.
/// Null until everything it needs has loaded.
final factsProvider = Provider<String?>((ref) {
  T? data<T>(AsyncValue<T> v) => switch (v) {
        AsyncData(:final value) => value,
        _ => null,
      };
  final sessions = data(ref.watch(analysesProvider));
  final load = data(ref.watch(loadSeriesProvider));
  final recovery = data(ref.watch(recoveryProvider));
  final sports = data(ref.watch(sportSummariesProvider));
  if (sessions == null || load == null || recovery == null || sports == null) return null;
  return buildFacts(
    asOf: ref.watch(asOfProvider),
    athlete: ref.watch(athleteProvider),
    sessions: sessions,
    load: load,
    recovery: recovery,
    sports: sports,
    readiness: ref.watch(readinessProvider),
  );
});

// ─── Live sync (intervals.icu) ──────────────────────────────────────────

final intervalsKeyStoreProvider = Provider<KeyStore>((ref) => const SecureKeyStore());
final liveFileProvider = Provider<LiveFile>((ref) => const AppLiveFile());
final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// The API key and everything synced so far, as stored on the phone.
class LiveData {
  const LiveData({this.apiKey, this.raw, this.bundle});
  final String? apiKey;
  final Map<String, dynamic>? raw;
  final GarminBundle? bundle;

  bool get connected => apiKey != null;
  DateTime? get syncedAt => DateTime.tryParse(raw?['syncedAt'] as String? ?? '');
  int get sessions => (raw?['activities'] as List?)?.length ?? 0;
  int get nights => (raw?['nights'] as List?)?.length ?? 0;

  static GarminBundle? parse(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    try {
      return GarminBundle.fromJson(raw);
    } catch (_) {
      return null; // unreadable store: the next sync rewrites it
    }
  }
}

class LiveNotifier extends AsyncNotifier<LiveData> {
  @override
  Future<LiveData> build() async {
    final key = await ref.watch(intervalsKeyStoreProvider).read();
    final raw = await ref.watch(liveFileProvider).read();
    return LiveData(apiKey: key, raw: raw, bundle: LiveData.parse(raw));
  }

  IntervalsClient _client(String key) => IntervalsClient(key, client: ref.read(httpClientProvider));

  /// Checks the key with intervals.icu, stores it, then runs the first sync.
  /// Returns an error to show, or null on success.
  Future<String?> connect(String key) async {
    key = key.trim();
    if (key.isEmpty) return 'Paste your API key first.';
    try {
      await _client(key).athlete();
      await ref.read(intervalsKeyStoreProvider).write(key);
    } on IntervalsException catch (e) {
      return e.auth ? 'intervals.icu rejected that key. Copy it again from Settings → Developer Settings.' : e.message;
    } catch (_) {
      return 'Could not save the key on this phone.';
    }
    final cur = state.value;
    state = AsyncData(LiveData(apiKey: key, raw: cur?.raw, bundle: cur?.bundle));
    unawaited(sync(force: true));
    return null;
  }

  /// Forgets the key and deletes the synced copy from this phone.
  Future<void> disconnect() async {
    await ref.read(intervalsKeyStoreProvider).write(null);
    await ref.read(liveFileProvider).write(null);
    ref.read(syncStatusProvider.notifier).reset();
    state = const AsyncData(LiveData());
  }

  /// Pulls anything new. Without [force], skips if the last sync was under
  /// two minutes ago, so app resumes don't hammer the API.
  Future<void> sync({bool force = false}) async {
    final cur = state.value;
    final key = cur?.apiKey;
    final status = ref.read(syncStatusProvider.notifier);
    if (cur == null || key == null || status.busy) return;
    final last = cur.syncedAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) return;

    status.start();
    try {
      final export = await ref.read(exportBundleProvider.future);
      final result = await IntervalsSync(_client(key)).run(
        previous: cur.raw,
        historyEnd: export?.dataUntil,
        onProgress: status.progress,
      );
      await ref.read(liveFileProvider).write(result.store);
      state = AsyncData(LiveData(apiKey: key, raw: result.store, bundle: LiveData.parse(result.store)));
      status.finish(result.summary);
    } on IntervalsException catch (e) {
      status.fail(e.message);
    } catch (e) {
      status.fail('Sync failed: $e');
    }
  }
}

final liveProvider = AsyncNotifierProvider<LiveNotifier, LiveData>(LiveNotifier.new);

class SyncStatus {
  const SyncStatus({this.busy = false, this.done = 0, this.total = 0, this.message, this.error = false});
  final bool busy, error;
  final int done, total;
  final String? message;
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  bool get busy => state.busy;
  void start() => state = const SyncStatus(busy: true, message: 'Checking intervals.icu…');
  void progress(int done, int total) => state = SyncStatus(
        busy: true,
        done: done,
        total: total,
        message: total == 0 ? 'Reading nights…' : 'Downloading session $done of $total',
      );
  void finish(String message) => state = SyncStatus(message: message);
  void fail(String message) => state = SyncStatus(message: message, error: true);
  void reset() => state = const SyncStatus();
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

/// "just now", "12 min ago", "3 h ago", or a date.
String syncedAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return 'never';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${at.day} ${months[at.month - 1]}';
}
