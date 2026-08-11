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

  /// The proxy the app talks to.
  ///
  /// A `--dart-define` that is *present but empty* would otherwise win over
  /// the fallback and silently disable Pollie — which is exactly what CI does
  /// when the `POLLIE_ENDPOINT` repository variable is not set, because the
  /// workflow always passes the flag. An empty value means "not configured",
  /// not "no proxy".
  static String get _defaultEndpoint =>
      _fromEnvironment.isEmpty ? _deployedProxy : _fromEnvironment;

  static const _fromEnvironment = String.fromEnvironment('POLLIE_ENDPOINT');
  static const _deployedProxy = 'https://pollie.inkpebble.workers.dev';

  /// Closes the connection pool. Called when the companion screen is left.
  void dispose() {
    _disposed = true;
    _client?.close(force: true);
    _client = null;
  }

  /// Identifies this install to the proxy's rate limiter and nothing else.
  ///
  /// Random per launch, because the app deliberately writes nothing to disk.
  /// That is enough to bound one session's burst, and it stores nothing about
  /// the child.
  static final String _installId = _randomId();

  final String _endpoint;

  /// One client for the whole session, created on first use.
  ///
  /// This used to be `_client ?? HttpClient()` inside the request method,
  /// which built a fresh client — and a fresh connection pool — for *every*
  /// message, and never closed any of them. A long chat exhausted the phone's
  /// sockets, after which every request failed for the rest of the session.
  /// That is what "it worked, then suddenly stopped" was.
  HttpClient? _client;

  /// How many clients this service has built. Exactly one per session is the
  /// whole point; a test asserts it, because the bug it replaces was invisible
  /// until a real phone ran out of sockets.
  @visibleForTesting
  int clientsCreated = 0;

  bool _disposed = false;
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
  /// [language] is 'en' or 'id'. Pollie used to infer it from the child's
  /// words, which got it wrong on short replies; the app already knows.
  Stream<String> reply(
    List<ChatMessage> history, {
    String language = 'en',
  }) async* {
    if (!isConfigured) {
      throw StateError('Pollie endpoint not configured');
    }
    final response = await _post('/chat', {
      'language': language,
      'messages': [
        for (final message in history)
          {'role': message.role, 'text': message.text},
      ],
    });
    if (response.statusCode == 429) {
      throw PollieQuotaException(retryAfter: _retryAfter(response));
    }
    if (response.statusCode != 200) {
      // The body says which of Google's limits or errors it was; without it
      // a misconfigured proxy is indistinguishable from a retired model.
      final body = await response.transform(utf8.decoder).join();
      debugPrint('Pollie chat HTTP ${response.statusCode}: $body');
      throw HttpException('Pollie returned ${response.statusCode}');
    }
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic>? chunk;
      try {
        chunk = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        // One malformed line is not worth failing a whole reply over.
        continue;
      }
      final text = chunk['text'];
      if (text is String && text.isNotEmpty) {
        yield text;
        continue;
      }
      // The proxy says the reply carried no words, and why. Usually a safety
      // filter — they are set as strictly as Gemini allows, which
      // occasionally catches something innocent.
      if (chunk['empty'] == true) {
        debugPrint('Pollie produced nothing: ${chunk['reason']}');
        throw const PollieEmptyReplyException();
      }
    }
  }

  /// The one client for this session, built on first use.
  HttpClient get _httpClient {
    final existing = _client;
    if (existing != null) return existing;
    clientsCreated++;
    return _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20)
      // A toddler chat is one request at a time; more connections would only
      // be sockets sitting idle.
      ..maxConnectionsPerHost = 2;
  }

  Future<HttpClientResponse> _post(String path, Object body) async {
    if (_disposed) throw StateError('Pollie service was disposed');
    final request = await _httpClient.postUrl(Uri.parse('$_endpoint$path'));
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    request.headers.set('X-Install-Id', _installId);
    // Cloudflare's bot protection rejects requests whose client signature
    // looks automated (error 1010). Dart's default agent passes today, but
    // saying who we are is both politer and less fragile.
    request.headers.set(HttpHeaders.userAgentHeader, 'TinyTapsters/1.0');
    // Write UTF-8 bytes, not a string. `request.write` encodes with the
    // request's charset, which defaults to Latin-1 — so the first time Pollie
    // used an emoji, that reply went into the history and every request after
    // it threw "Contains invalid characters" for the rest of the session.
    // Indonesian accents would have done the same.
    final payload = utf8.encode(jsonEncode(body));
    request.headers.contentLength = payload.length;
    request.add(payload);
    return request.close();
  }

  static Duration? _retryAfter(HttpClientResponse response) {
    final header = response.headers.value(HttpHeaders.retryAfterHeader);
    final seconds = int.tryParse(header ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}

/// Pollie answered with nothing at all.
///
/// Distinct from a failure: the request worked. Treating it as a breakdown is
/// what put her to sleep and greyed out the microphone, leaving a child with
/// no way to carry on. She should just ask again.
class PollieEmptyReplyException implements Exception {
  const PollieEmptyReplyException();

  @override
  String toString() => 'empty reply';
}

/// Pollie cannot answer right now because of a limit.
///
/// [retryAfter] separates "slow down for a moment" from "that is all for
/// today" — the app says something different for each, because telling a child
/// to come back tomorrow when the answer is ten seconds away is a lie.
class PollieQuotaException implements Exception {
  const PollieQuotaException({this.retryAfter});

  final Duration? retryAfter;

  bool get isBrief =>
      retryAfter != null && retryAfter! < const Duration(minutes: 5);

  @override
  String toString() => 'quota';
}
