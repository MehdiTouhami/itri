import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failure worth showing to the user as-is.
class IntervalsException implements Exception {
  const IntervalsException(this.message, {this.auth = false, this.rateLimited = false});
  final String message;

  /// The API key was rejected.
  final bool auth;

  /// intervals.icu asked us to slow down; stop and try again later.
  final bool rateLimited;

  @override
  String toString() => message;
}

/// Thin client for the intervals.icu REST API (https://intervals.icu/api-docs.html).
/// Auth is HTTP Basic with the literal user name `API_KEY` and the user's key
/// as the password; athlete `0` means "the owner of this key".
class IntervalsClient {
  IntervalsClient(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();

  static const base = 'https://intervals.icu/api/v1';

  /// Everything the analysis uses. `latlng` arrives as two arrays: lat in
  /// `data`, lon in `data2`.
  static const streamTypes = 'time,heartrate,distance,velocity_smooth,altitude,latlng,cadence,watts';

  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('API_KEY:$apiKey'))}',
        'Accept': 'application/json',
      };

  Future<Object?> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final http.Response res;
    try {
      res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const IntervalsException('intervals.icu did not respond. Try again.');
    } catch (_) {
      throw const IntervalsException('Could not reach intervals.icu. Check your connection.');
    }
    switch (res.statusCode) {
      case 200:
        return jsonDecode(utf8.decode(res.bodyBytes));
      case 401 || 403:
        throw const IntervalsException('intervals.icu rejected the API key.', auth: true);
      case 404:
        return null;
      case 429:
        throw const IntervalsException('intervals.icu is limiting requests. Try again in a minute.', rateLimited: true);
      default:
        throw IntervalsException('intervals.icu error ${res.statusCode}.');
    }
  }

  static List<Map<String, dynamic>> _list(Object? json) =>
      json is List ? [for (final e in json) if (e is Map<String, dynamic>) e] : const [];

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The key owner's profile. Also the cheapest way to check a key.
  Future<Map<String, dynamic>> athlete() async {
    final j = await _get('/athlete/0');
    return j is Map<String, dynamic> ? j : const {};
  }

  /// Session summaries started between [oldest] and [newest] (local dates).
  Future<List<Map<String, dynamic>>> activities(DateTime oldest, DateTime newest) async =>
      _list(await _get('/athlete/0/activities', {'oldest': _day(oldest), 'newest': _day(newest)}));

  /// One row per day: sleep, HRV, resting HR and the rest of Garmin's wellness.
  Future<List<Map<String, dynamic>>> wellness(DateTime oldest, DateTime newest) async =>
      _list(await _get('/athlete/0/wellness', {'oldest': _day(oldest), 'newest': _day(newest)}));

  /// Second-by-second recordings for one session.
  Future<List<Map<String, dynamic>>> streams(String activityId) async =>
      _list(await _get('/activity/$activityId/streams.json', {'types': streamTypes}));
}
