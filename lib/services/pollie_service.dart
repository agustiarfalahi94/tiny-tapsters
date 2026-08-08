import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// One chat turn in the conversation history.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  /// 'user' or 'model'.
  final String role;
  final String text;
}

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

  bool get isConfigured => _model != null;

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
  Future<bool> ping() async {
    final model = _model;
    if (model == null) return false;
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
      return response.text?.trim().isNotEmpty ?? false;
    } catch (e) {
      debugPrint('Pollie ping failed: $e');
      return false;
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
