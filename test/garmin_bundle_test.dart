import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/data/garmin/garmin_bundle.dart';
import 'package:itri_fitness/domain/sport.dart';

void main() {
  Map<String, dynamic> activity(String sport, {bool gps = false, bool indoor = false}) => {
        'id': sport.hashCode,
        'sport': sport,
        'indoor': indoor,
        'name': 'Preston ${sport[0].toUpperCase()}${sport.substring(1)}',
        'start': '2026-05-07T15:55:43',
        'locality': 'Preston',
        'calories': 400,
        'garminLoad': 120.5,
        'aerobicTE': 3.1,
        'anaerobicTE': 2.2,
        's': {
          't': [0, 5, 10, 15],
          'hr': [120, 140, null, 150],
          'd': [0.0, 20.0, 40.0, 60.0],
          if (gps) 'lat': [null, 53.76, 53.77, null],
          if (gps) 'lon': [null, -2.70, -2.71, null],
        },
      };

  final json = {
    'version': 1,
    'source': 'Garmin Connect export',
    'exportedAt': '2026-05-07',
    'athlete': {'name': 'Alex', 'maxHr': 200, 'restHr': 51, 'weightKg': 80.0, 'birthYear': 2000},
    'restingHr': {'2026-05-06': 52, '2026-05-07': 51},
    'validation': {
      'n': 3,
      'pearson': 0.88,
      'spearman': 0.87,
      'bySport': {
        'tennis': {'n': 62, 'r': 0.9},
        'curling': {'n': 5, 'r': 0.1}, // unknown sports are ignored
      },
    },
    'activities': [
      activity('tennis', gps: true),
      activity('ride', gps: true),
      activity('run', indoor: true),
      activity('curling'),
    ],
  };

  test('parses athlete, validation and activities', () {
    final b = GarminBundle.fromJson(json);
    expect(b.athlete.restHr, 51);
    expect(b.dataUntil, DateTime(2026, 5, 7));
    expect(b.restingHr[DateTime(2026, 5, 7)], 51);
    expect(b.check.pearson, 0.88);
    expect(b.check.bySport.keys, [Sport.tennis]);
    expect(b.activities.map((a) => a.sport), [Sport.tennis, Sport.ride, Sport.run]);
  });

  test('keeps device figures and summarises from samples', () {
    final tennis = GarminBundle.fromJson(json).activities.first;
    expect(tennis.deviceLoad, 120.5);
    expect(tennis.calories, 400);
    expect(tennis.durationS, 15);
    expect(tennis.maxHr, 150);
    expect(tennis.samples[2].heartRate, isNull);
  });

  test('routes only for GPS sports recorded outdoors', () {
    final list = GarminBundle.fromJson(json).activities;
    expect(list[0].hasRoute, isFalse); // tennis: court scribble, not a route
    expect(list[1].hasRoute, isTrue); // ride
    expect(list[2].hasRoute, isFalse); // treadmill
  });
}
