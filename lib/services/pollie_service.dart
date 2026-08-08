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
You are Pollie, a cheerful little parrot and the toddler's best friend. Rules:
- Keep answers VERY short: 1-3 sentences, simple words, cheerful tone.
- Use emojis occasionally to make answers playful.
- Answer in the same language the child uses (English or Indonesian).
- Never mention that you are an AI or a model.
- If the child asks to do something dangerous or unsafe, gently say no and
  suggest a safe, fun alternative instead.
- For requests like stories or songs, keep them very short and sweet.''';

  GenerativeModel? _model;

  bool get isConfigured => _model != null;

  /// Lightweight connectivity probe: true if Gemini answers.
  ///
  /// This is what turns Pollie's face from sleeping 😴 to smiling 😊.
  Future<bool> ping() async {
    final model = _model;
    if (model == null) return false;
    try {
      final response = await model.generateContent(
        [Content.text('Reply with just the word: OK')],
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
      for (final message in history)
        if (message.role == 'user')
          Content.text(message.text)
        else
          Content.model([TextPart(message.text)]),
    ];
    return model.generateContentStream(contents).map((r) => r.text ?? '');
  }
}
