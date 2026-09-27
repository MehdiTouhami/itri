import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:itri_fitness/data/garmin/garmin_bundle.dart';
import 'package:itri_fitness/data/intervals/intervals_client.dart';
import 'package:itri_fitness/data/intervals/intervals_mapper.dart';
import 'package:itri_fitness/data/intervals/intervals_sync.dart';
import 'package:itri_fitness/domain/sleep.dart';
import 'package:itri_fitness/domain/sport.dart';

/// A 1 Hz run at 3 m/s; the clock jumps by [pause] s at [pauseAt] (auto-pause).
List<Map<String, dynamic>> runStreams({int seconds = 1200, int pauseAt = 600, int pause = 60}) {
  final time = <int>[], hr = <int>[], dist = <double>[], lat = <double>[], lon = <double>[], cad = <int>[];
  for (var i = 0; i <= seconds; i++) {
    time.add(i < pauseAt ? i : i + pause);
    hr.add(140);
    dist.add(i * 3.0);
    lat.add(53.76 + i * 1e-5);
    lon.add(-2.70);
    cad.add(85); // strides per minute
  }
  return [
    {'type': 'time', 'data': time},
    {'type': 'heartrate', 'data': hr},
    {'type': 'distance', 'data': dist},
    {'type': 'latlng', 'data': lat, 'data2': lon},
    {'type': 'cadence', 'data': cad},
  ];
}

GarminBundle bundle(String until, List<Map<String, dynamic>> activities, List<Map<String, dynamic>> nights) =>
    GarminBundle.fromJson({
      'exportedAt': until,
      'athlete': {'name': 'A', 'maxHr': 200, 'restHr': 50, 'weightKg': 80.0},
      'activities': activities,
      'nights': nights,
    });

Map<String, dynamic> run(int id, String start) => {
      'id': id,
      'sport': 'run',
      'name': 'Run',
      'start': start,
      's': {
        't': [0, 5, 10],
        'hr': [120, 130, 140],
      },
    };

void main() {
  test('sport comes from the type, else from the name', () {
    expect(sportOf('Ride', null), Sport.ride);
    expect(sportOf('VirtualRide', null), Sport.ride);
    expect(sportOf('WeightTraining', null), Sport.strength);
    expect(sportOf('Soccer', null), Sport.football);
    expect(sportOf('Workout', 'Preston Padel'), Sport.padel);
    expect(sportOf('TableTennis', null), isNull);
    expect(sportOf('Swim', 'Morning swim'), isNull);
  });

  group('streams to samples', () {
    final samples = samplesFromStreams(runStreams(), Sport.run);

    test('5 s spacing, pauses collapsed to one step', () {
      expect(samples.sublist(0, samples.length - 1).every((s) => s.t % 5 == 0), isTrue);
      expect(samples.last.t, 1204); // 1200 s recorded + 5 s for the pause - 1
    });

    test('run cadence reported in strides is doubled to steps', () {
      expect(samples[10].cadence, 170);
    });

    test('GPS removed within 500 m of start and finish', () {
      expect(samples.first.lat, isNull);
      expect(samples[samples.length ~/ 2].lat, isNotNull);
      expect(samples.last.lat, isNull);
    });

    test('court sports keep no GPS and no cadence', () {
      final tennis = samplesFromStreams(runStreams(), Sport.tennis);
      expect(tennis.every((s) => s.lat == null && s.cadence == null), isTrue);
      expect(tennis[10].heartRate, 140);
    });
  });

  test('wellness: a night only when there is a scored sleep', () {
    final w = wellnessJson([
      {'id': '2026-09-26', 'sleepSecs': 27000, 'sleepScore': 81, 'hrv': 72.0, 'restingHR': 50, 'steps': 9000},
      {'id': '2026-09-27', 'restingHR': 52},
      {'id': 'bad'},
    ]);
    expect(w.nights.single['total'], 27000);
    expect(w.days.keys, ['2026-09-26', '2026-09-27']);
  });

  test('live nights: asleep from the total, no stages, no times', () {
    final n = SleepNight(date: DateTime(2026, 9, 27), score: 80, totalSleepS: 26000);
    expect(n.asleepS, 26000);
    expect(n.hasStages, isFalse);
    expect(n.efficiency, isNull);
    expect(n.bedMinutes, isNull);
  });

  test('usual HRV range is filled only where the source has none', () {
    final nights = [
      for (var i = 1; i <= 30; i++) SleepNight(date: DateTime(2026, 4, i), score: 75, totalSleepS: 25000, hrv: 60.0 + i % 5),
      SleepNight(date: DateTime(2026, 5, 1), score: 70, totalSleepS: 25000, hrv: 40.0),
      SleepNight(date: DateTime(2026, 5, 2), score: 70, totalSleepS: 25000, hrv: 61.0, hrvLow: 50, hrvHigh: 80),
    ];
    final out = withHrvRanges(nights);
    expect(out[5].hrvLow, isNull); // under 14 nights of history
    expect(out[20].hrvStatus, HrvStatus.within);
    expect(out[30].hrvStatus, HrvStatus.below);
    expect(out[31].hrvLow, 50); // Garmin's own range is kept
  });

  test('merge: export wins on overlaps, live adds the rest', () {
    final export = bundle('2026-05-08', [run(1, '2026-05-08T10:00:00')], [
      {
        'date': '2026-05-08',
        'start': '2026-05-07T23:00',
        'end': '2026-05-08T07:00',
        'deep': 5000,
        'light': 15000,
        'rem': 6000,
        'awake': 600,
        'score': 80,
      },
    ]);
    final live = bundle('2026-09-27', [run(2, '2026-05-08T10:01:00'), run(3, '2026-09-26T18:00:00')], [
      {'date': '2026-05-08', 'total': 20000, 'score': 60},
      {'date': '2026-09-27', 'total': 25000, 'score': 77},
    ]);
    final m = mergeBundles(export, live)!;
    expect(m.activities.map((a) => a.id), [3, 1]); // same session within 2 min: export copy kept
    expect(m.recovery.byDate(DateTime(2026, 5, 8))!.hasStages, isTrue);
    expect(m.recovery.byDate(DateTime(2026, 9, 27))!.score, 77);
    expect(m.dataUntil, DateTime(2026, 9, 27));
    expect(mergeBundles(null, null), isNull);
  });

  group('sync', () {
    final summaries = <Map<String, dynamic>>[
      {'id': 'i101', 'type': 'Run', 'name': 'Morning Run', 'start_date_local': '2026-09-26T07:00:00'},
      {'id': 'i102', 'type': 'Swim', 'name': 'Swim', 'start_date_local': '2026-09-26T12:00:00'},
      {'id': 'i103', 'start_date_local': '2026-09-25T07:00:00', '_note': 'Strava activities are not available'},
    ];

    MockClient api({required void Function() onStreams, int streamStatus = 200}) => MockClient((req) async {
          expect(req.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('API_KEY:k'))}');
          final p = req.url.path;
          if (p.endsWith('/athlete/0')) {
            return http.Response(
                jsonEncode({
                  'firstname': 'Mehdi',
                  'icu_weight': 82.4,
                  'sportSettings': [
                    {'max_hr': 200},
                  ],
                }),
                200);
          }
          if (p.endsWith('/activities')) return http.Response(jsonEncode(summaries), 200);
          if (p.endsWith('/wellness')) {
            return http.Response(
                jsonEncode([
                  {'id': '2026-09-27', 'sleepSecs': 25000, 'sleepScore': 77, 'hrv': 70},
                ]),
                200);
          }
          if (p.contains('/streams')) {
            onStreams();
            return http.Response(jsonEncode(runStreams(seconds: 900, pauseAt: 900, pause: 0)), streamStatus);
          }
          return http.Response('', 404);
        });

    test('first sync downloads new sessions and nights; the next only what is new', () async {
      var streamCalls = 0;
      final sync = IntervalsSync(
        IntervalsClient('k', client: api(onStreams: () => streamCalls++)),
        now: () => DateTime(2026, 9, 27, 9),
      );
      final first = await sync.run();
      expect(streamCalls, 1); // swim not modelled, Strava stub not downloadable
      expect(first.newSessions, 1);
      expect(first.newNights, 1);

      final b = GarminBundle.fromJson(first.store);
      expect(b.activities.single.sport, Sport.run);
      expect(b.athlete.maxHr, 200);
      expect(b.recovery.nights.single.asleepS, 25000);
      expect(b.dataUntil, DateTime(2026, 9, 27));

      final second = await sync.run(previous: first.store);
      expect(streamCalls, 1);
      expect(second.summary, 'Up to date');
    });

    test('history that reaches intervals.icu after the first sync is still picked up', () async {
      var streamCalls = 0;
      final sync = IntervalsSync(
        IntervalsClient('k', client: api(onStreams: () => streamCalls++)),
        now: () => DateTime(2026, 9, 27, 9),
      );
      final first = await sync.run(historyEnd: DateTime(2026, 5, 8));
      summaries.add({'id': 'i104', 'type': 'Ride', 'name': 'June ride', 'start_date_local': '2026-06-02T08:00:00'});
      final later = await sync.run(previous: first.store, historyEnd: DateTime(2026, 5, 8));
      summaries.removeLast();
      expect(streamCalls, 2);
      expect(later.newSessions, 1);
      expect((later.store['activities'] as List).length, 2);
    });

    test('rate limiting stops early and keeps the old sync mark', () async {
      final sync = IntervalsSync(
        IntervalsClient('k', client: api(onStreams: () {}, streamStatus: 429)),
        now: () => DateTime(2026, 9, 27, 9),
      );
      final r = await sync.run();
      expect(r.stoppedEarly, isTrue);
      expect(r.store['syncedAt'], isNull);
    });
  });

  test('a rejected key is an auth error', () async {
    final c = IntervalsClient('bad', client: MockClient((_) async => http.Response('', 401)));
    await expectLater(c.athlete(), throwsA(isA<IntervalsException>().having((e) => e.auth, 'auth', isTrue)));
  });
}
