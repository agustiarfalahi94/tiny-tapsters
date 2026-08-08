import 'package:google_generative_ai/google_generative_ai.dart';

/// One chat turn in the conversation history.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  /// 'user' or 'model'.
  final String role;
  final String text;
}

/// Thin wrapper around the Gemini API for the in-app companion ("Buddy").
///
/// The API key comes from the build environment:
///   flutter build apk --release --dart-define=GEMINI_API_KEY=...
/// It is never stored in the repository.
class BuddyService {
  BuddyService() {
    const key = String.fromEnvironment('GEMINI_API_KEY');
    if (key.isNotEmpty) {
      _model = GenerativeModel(
        model: _modelId,
        apiKey: key,
        generationConfig: GenerationConfig(
          temperature: 0.9,
          maxOutputTokens: 200,
        ),
      );
    }
  }

  // Swap this if Google deprecates the model.
  static const _modelId = 'gemini-2.5-flash';

  static const _systemPrompt = '''
You are Buddy, a warm, playful companion for a toddler. Rules:
- Keep answers VERY short: 1-3 sentences, simple words, cheerful tone.
- Use emojis occasionally to make answers playful.
- Answer in the same language the child uses (English or Indonesian).
- Never mention that you are an AI or a model.
- If the child asks to do something dangerous or unsafe, gently say no and
  suggest a safe, fun alternative instead.
- For requests like stories or songs, keep them very short and sweet.''';

  GenerativeModel? _model;

  bool get isConfigured => _model != null;

  /// Streams the model's reply token by token for the given conversation.
  Stream<String> reply(List<ChatMessage> history) {
    final model = _model;
    if (model == null) {
      return Stream.error(StateError('Gemini API key not configured'));
    }
    final contents = <Content>[
      Content.system(_systemPrompt),
      for (final message in history)
        if (message.role == 'user')
          Content.text(message.text)
        else
          Content.model([TextPart(message.text)]),
    ];
    return model.generateContentStream(contents).map((r) => r.text ?? '');
  }
}
