import 'package:intl/intl.dart';

import '../domain/athlete.dart';

/// Display formatting. Pure functions so they are trivial to test.
abstract final class Fmt {
  static const _mPerMile = 1609.344;

  static double unitM(Units u) => u == Units.metric ? 1000 : _mPerMile;
  static String distUnit(Units u) => u == Units.metric ? 'km' : 'mi';
  static String paceUnit(Units u) => u == Units.metric ? '/km' : '/mi';
  static String speedUnit(Units u) => u == Units.metric ? 'km/h' : 'mph';

  static String distance(double m, Units u, {int decimals = 2}) =>
      (m / unitM(u)).toStringAsFixed(decimals);

  /// 1:05:09 or 42:07.
  static String duration(num seconds) {
    final s = seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  /// Compact: 1h 05m, 42m.
  static String durationShort(num seconds) {
    final s = seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }

  /// Pace per unit from speed; "—" when stationary.
  static String pace(double? speedMs, Units u) {
    if (speedMs == null || speedMs < 0.3) return '—';
    final secPerUnit = unitM(u) / speedMs;
    final m = secPerUnit ~/ 60, s = (secPerUnit % 60).round();
    return s == 60 ? '${m + 1}:00' : '$m:${s.toString().padLeft(2, '0')}';
  }

  static String paceFromSeconds(double secPerUnit) {
    final m = secPerUnit ~/ 60, s = (secPerUnit % 60).round();
    return s == 60 ? '${m + 1}:00' : '$m:${s.toString().padLeft(2, '0')}';
  }

  static String speed(double? speedMs, Units u) {
    if (speedMs == null) return '—';
    return (speedMs * 3600 / unitM(u)).toStringAsFixed(1);
  }

  static String elevation(double m, Units u) =>
      u == Units.metric ? m.round().toString() : (m * 3.28084).round().toString();
  static String elevUnit(Units u) => u == Units.metric ? 'm' : 'ft';

  static String signed(num v, {int decimals = 0}) {
    final s = v.toStringAsFixed(decimals);
    return v > 0 ? '+$s' : s.replaceFirst('-', '−');
  }

  static final _dayMonth = DateFormat('EEE d MMM');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _time = DateFormat('HH:mm');
  static final _shortDate = DateFormat('d MMM');

  static String dayMonth(DateTime d) => _dayMonth.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String time(DateTime d) => _time.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);
}
