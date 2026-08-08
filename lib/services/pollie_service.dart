import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// One chat turn in the conversation history.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  /// 'user' or 'model'.
  final String role;
  final String text;
}

/// Result of a connectivity probe.
enum PolliePing { ok, quota, unreachable }

/// Thin wrapper around the Gemini API for the in-app companion (Pollie 🦜).
///
/// The API key comes from the build environment:
///   flutter build apk --release --dart-define=GEMINI_API_KEY=...
/// It is never stored in the repository.
class PollieService {
  PollieService() {
    const key = String.fromEnvironment('GEMINI_API_KEY');
    if (key.isNotEmpty) {
      _model = GenerativeModel(
        model: _modelId,
        apiKey: key,
        generationConfig: GenerationConfig(
          temperature: 0.9,
          // Generous budget: the current flash models "think" first, and
          // thinking tokens count toward this cap.
          maxOutputTokens: 800,
        ),
      );
    }
  }

  // The "latest" alias always tracks Google's current flash model, so this
  // never needs updating when models get retired.
  static const _modelId = 'gemini-flash-latest';

  static const _systemPrompt = '''
You are Pollie, a warm, friendly companion who talks to a young child.
Rules:
- Talk like a normal, warm person would: relaxed, casual, natural. Never
  sound like a robot, a script, or a narrator.
- Keep replies short: usually 2-3 sentences, sometimes just one. Use simple
  words a 4-year-old understands.
- Use the same language the child uses (English or Indonesian).
- You may use ONE emoji occasionally, but not in every reply and never as
  decoration on every sentence.
- Never use asterisks, roleplay sounds, or *action* markers — just plain
  speech.
- Never mention that you are an AI or a model.
- SAFETY (most important): NEVER discuss sex, dating, romance, violence,
  drugs, death, or anything adult. NEVER use bad words, insults, or slurs.
  If the child says something rude or inappropriate, gently say "That's not
  a nice thing to say!" and change the subject to something fun.
- If the child asks to do something dangerous or unsafe, gently say no and
  suggest a safe, fun alternative instead.
- For stories and songs, keep them very short and sweet.''';

  GenerativeModel? _model;
  DateTime? _lastPingOk;

  bool get isConfigured => _model != null;

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

  /// Strictest possible safety blocking on every category, applied to both
  /// the child's input and Pollie's output.
  static final _safetySettings = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.low),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.low),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.low),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.low),
  ];

  /// Lightweight connectivity probe: true if Gemini answers.
  ///
  /// This is what turns Pollie's face from sleeping 😴 to smiling 😊.
  Future<PolliePing> ping() async {
    final model = _model;
    if (model == null) return PolliePing.unreachable;
    try {
      final response = await model.generateContent(
        [Content.text('Reply with just the word: OK')],
        safetySettings: _safetySettings,
        generationConfig: GenerationConfig(
          temperature: 0,
          // Must leave room for the model's thinking tokens, or the answer
          // comes back empty and the SDK throws "Unhandled format".
          maxOutputTokens: 200,
        ),
      );
      final ok = response.text?.trim().isNotEmpty ?? false;
      if (ok) _lastPingOk = DateTime.now();
      return ok ? PolliePing.ok : PolliePing.unreachable;
    } catch (e) {
      debugPrint('Pollie ping failed: $e');
      if (e.toString().toLowerCase().contains('quota')) {
        return PolliePing.quota;
      }
      return PolliePing.unreachable;
    }
  }

  /// Streams the model's reply token by token for the given conversation.
  Stream<String> reply(List<ChatMessage> history) {
    final model = _model;
    if (model == null) {
      return Stream.error(StateError('Gemini API key not configured'));
    }
    final contents = <Content>[
      // The SDK (0.4.7) serializes Content.system into `systemInstruction`
      // with a `role: 'system'` field, which the current Gemini API rejects
      // ("Role 'system' is not supported"). Riding along as the first user
      // turn works on every API version instead.
      Content.text(_systemPrompt),
      // Keep long sessions within the model's context window: only the
      // most recent turns go with each request.
      for (final message in _trimmedHistory(history))
        if (message.role == 'user')
          Content.text(message.text)
        else
          Content.model([TextPart(message.text)]),
    ];
    return model
        .generateContentStream(contents, safetySettings: _safetySettings)
        .map((r) => r.text ?? '');
  }

  /// The last 20 conversation turns (a toddler chat never needs more).
  static List<ChatMessage> _trimmedHistory(List<ChatMessage> history) {
    return history.length <= 20
        ? history
        : history.sublist(history.length - 20);
  }
}
