import '../domain/activity.dart';
import 'garmin/garmin_bundle.dart';
import 'synthetic/synthetic_generator.dart';

/// Where activities come from. Nothing above this layer knows which one it got.
abstract interface class ActivityRepository {
  /// Newest first.
  List<Activity> all();
}

class SyntheticActivityRepository implements ActivityRepository {
  SyntheticActivityRepository({DateTime? today}) : _today = today ?? DateTime.now();

  final DateTime _today;
  List<Activity>? _cache;

  @override
  List<Activity> all() => _cache ??= (SyntheticGenerator(today: _today).generate()
    ..sort((a, b) => b.start.compareTo(a.start)));
}

/// Real sessions: the Garmin export and/or the live intervals.icu sync.
class GarminActivityRepository implements ActivityRepository {
  const GarminActivityRepository(this.bundle);
  final GarminBundle bundle;

  @override
  List<Activity> all() => bundle.activities;
}
