import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class CoachException implements Exception {
  const CoachException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Itri coach backend (FastAPI + Gemini + research RAG).
/// Override the server with `--dart-define=COACH_URL=http://localhost:8000`.
class CoachClient {
  CoachClient({String? baseUrl})
      : baseUrl = baseUrl ?? const String.fromEnvironment('COACH_URL', defaultValue: 'https://itri-sleep-app.onrender.com');

  final String baseUrl;

  /// Shared secret the backend expects. Comes from the git-ignored
  /// secrets.json via `./run.sh` (`--dart-define-from-file`), never from code.
  static const appKey = String.fromEnvironment('COACH_KEY');

  /// Streams the reply token by token. [facts] carries the user's exact
  /// numbers; the server grounds the answer in them plus research.
  Stream<String> ask(String message, {List<(String, String)> history = const [], String? facts}) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/chat-stream'))
      ..headers['Content-Type'] = 'application/json'
      ..headers.addAll({if (appKey.isNotEmpty) 'X-Itri-Key': appKey})
      ..body = jsonEncode({
        'message': message,
        'history': [for (final (q, a) in history) [q, a]],
        'facts': ?facts,
      });

    final client = http.Client();
    try {
      // The free server sleeps when idle and takes up to a minute to wake.
      final response = await client.send(request).timeout(const Duration(seconds: 90));
      switch (response.statusCode) {
        case 200:
          break;
        case 401:
          throw const CoachException('This build has no coach key. Start the app with ./run.sh.');
        case 429:
          throw const CoachException("You've asked a lot in a short time. Try again in a few minutes.");
        default:
          throw CoachException('The coach replied with an error (${response.statusCode}).');
      }
      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final events = buffer.split('\n\n');
        buffer = events.removeLast();
        for (final event in events) {
          for (final line in event.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;
            final Object? decoded;
            try {
              decoded = jsonDecode(data);
            } on FormatException {
              continue;
            }
            if (decoded is! Map<String, dynamic>) continue;
            final error = decoded['error'];
            if (error != null) {
              throw CoachException(error is String && error.isNotEmpty ? error : 'The coach hit a problem answering that.');
            }
            final token = decoded['token'];
            if (token is String && token.isNotEmpty) yield token;
          }
        }
      }
    } on TimeoutException {
      throw const CoachException('The coach is taking too long to wake up. Try again in a moment.');
    } on http.ClientException {
      throw const CoachException('Could not reach the coach. Check your connection.');
    } finally {
      client.close();
    }
  }
}
