import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// One chat turn in the conversation history.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  /// 'user' or 'model'.
  final String role;
  final String text;
}

/// Result of a connectivity probe.
enum PolliePing { ok, quota, unreachable }

/// Talks to Pollie's proxy (see `worker/`), which holds the Gemini key.
///
/// This used to call Gemini directly through `google_generative_ai`. That
/// package is discontinued and cannot express `thinkingConfig` at all, which
/// meant every reply paid for a reasoning pass before its first word — and it
/// required the API key to ship inside the APK, where `strings libapp.so`
/// finds it. Both problems live on the other side of the proxy now, so this is
/// a plain HTTP client and one dependency fewer.
class PollieService {
  PollieService({String? endpoint, HttpClient? client})
    : _endpoint = endpoint ?? _defaultEndpoint,
      _client = client;

  /// The deployed proxy. Override at build time with
  ///   flutter build apk --release --dart-define=POLLIE_ENDPOINT=https://...
  ///
  /// A URL in an APK is not a secret; the key it stands in front of was. This
  /// default is what makes Pollie work in a plain `flutter build` and in every
  /// copy of the app someone installs, without anyone needing a key.
  static const _defaultEndpoint = String.fromEnvironment(
    'POLLIE_ENDPOINT',
    defaultValue: 'https://pollie.inkpebble.workers.dev',
  );

  /// Identifies this install to the proxy's rate limiter and nothing else.
  ///
  /// Random per launch, because the app deliberately writes nothing to disk.
  /// That is enough to bound one session's burst, and it stores nothing about
  /// the child.
  static final String _installId = _randomId();

  final String _endpoint;
  final HttpClient? _client;
  DateTime? _lastPingOk;

  bool get isConfigured => _endpoint.isNotEmpty;

  /// True when a successful ping happened within the last few minutes — the
  /// companion skips the network call in that case (free-tier quota is
  /// precious: one request per open adds up fast for a toddler app).
  bool get recentlyAwake =>
      _lastPingOk != null &&
      DateTime.now().difference(_lastPingOk!) < const Duration(minutes: 5);

  /// When the Gemini free-tier daily quota resets, in local time.
  /// Google resets daily quotas at 12:00 AM Pacific Time.
  DateTime nextDailyReset() {
    final nowUtc = DateTime.now().toUtc();
    var resetUtc = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
      _pacificUtcMidnightHour(nowUtc),
    );
    if (!resetUtc.isAfter(nowUtc)) {
      resetUtc = resetUtc.add(const Duration(days: 1));
    }
    return resetUtc.toLocal();
  }

  /// "at HH:MM (in about Xh Ym)" — the notice shown when Pollie is out of
  /// words for the day.
  String quotaResetLabel() {
    final reset = nextDailyReset();
    final diff = reset.difference(DateTime.now());
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final time =
        '${reset.hour.toString().padLeft(2, '0')}:'
        '${reset.minute.toString().padLeft(2, '0')}';
    final inText = hours > 0 ? 'about $hours h $minutes m' : 'about $minutes m';
    return 'at $time (in $inText)';
  }

  /// Hour (UTC) at which it is 12:00 AM in the Pacific timezone, following
  /// US daylight-saving rules (2nd Sunday of March → 1st Sunday of November).
  int _pacificUtcMidnightHour(DateTime utc) {
    final year = utc.year;
    DateTime nthSunday(int month, int n) {
      final first = DateTime.utc(year, month, 1);
      final daysToFirstSunday = (7 - first.weekday) % 7;
      return DateTime.utc(year, month, 1 + daysToFirstSunday + (n - 1) * 7);
    }

    // DST starts 02:00 PDT (= 09:00 UTC) on the 2nd Sunday of March and
    // ends 02:00 PDT (= 09:00 UTC) on the 1st Sunday of November.
    final dstStart = nthSunday(3, 2).add(const Duration(hours: 9));
    final dstEnd = nthSunday(11, 1).add(const Duration(hours: 9));
    final inDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
    return inDst ? 7 : 8;
  }

  /// Lightweight connectivity probe: true if Pollie answers.
  ///
  /// This is what turns Pollie's face from sleeping 😴 to smiling 😊.
  Future<PolliePing> ping() async {
    if (!isConfigured) return PolliePing.unreachable;
    try {
      final response = await _post('/ping', const {});
      if (response.statusCode == 429) return PolliePing.quota;
      if (response.statusCode != 200) return PolliePing.unreachable;
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final ok = body['ok'] == true;
      if (ok) _lastPingOk = DateTime.now();
      return ok ? PolliePing.ok : PolliePing.unreachable;
    } catch (e) {
      debugPrint('Pollie ping failed: $e');
      return PolliePing.unreachable;
    }
  }

  /// Streams the reply as it arrives, one piece of text at a time.
  ///
  /// The proxy hands back newline-delimited JSON — one `{"text": "..."}` per
  /// line — rather than an SSE dialect, so there is as little protocol as
  /// possible for a phone on a bad connection to get wrong.
  Stream<String> reply(List<ChatMessage> history) async* {
    if (!isConfigured) {
      throw StateError('Pollie endpoint not configured');
    }
    final response = await _post('/chat', {
      'messages': [
        for (final message in history)
          {'role': message.role, 'text': message.text},
      ],
    });
    if (response.statusCode == 429) {
      throw const PollieQuotaException();
    }
    if (response.statusCode != 200) {
      throw HttpException('Pollie returned ${response.statusCode}');
    }
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final chunk = jsonDecode(line) as Map<String, dynamic>;
        final text = chunk['text'];
        if (text is String && text.isNotEmpty) yield text;
      } catch (_) {
        // One malformed line is not worth failing a whole reply over.
      }
    }
  }

  Future<HttpClientResponse> _post(String path, Object body) async {
    final client = _client ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.postUrl(Uri.parse('$_endpoint$path'));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set('X-Install-Id', _installId);
    // Cloudflare's bot protection rejects requests whose client signature
    // looks automated (error 1010). Dart's default agent passes today, but
    // saying who we are is both politer and less fragile.
    request.headers.set(HttpHeaders.userAgentHeader, 'TinyTapsters/1.0');
    request.write(jsonEncode(body));
    return request.close();
  }

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}

/// Pollie has used up the day's words.
class PollieQuotaException implements Exception {
  const PollieQuotaException();

  @override
  String toString() => 'quota';
}
