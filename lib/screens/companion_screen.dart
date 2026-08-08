import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../services/buddy_service.dart';
import '../widgets/game_background.dart';
import '../widgets/round_button.dart';

/// Buddy 🐻 — a talking companion powered by Gemini.
///
/// Toddlers tap the big chips to chat; grown-ups can type too. Buddy's
/// replies stream in as speech bubbles and are spoken aloud (system TTS).
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  static const _chips = [
    'Tell me a story! 🐰',
    'Sing a song! 🎵',
    'What does a cow say? 🐮',
    'How are you? 😊',
    'Fun fact! 🦕',
    'I love you! ❤️',
  ];
  static const _idStopWords = [
    'apa',
    'kenapa',
    'bagaimana',
    'cerita',
    'nyanyi',
    'aku',
    'saya',
    'kamu',
    'kenal',
    'boleh',
    'tolong',
  ];

  final _buddy = BuddyService();
  final _history = <ChatMessage>[];
  final _bubbles = <_Bubble>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bubbles.add(
      _Bubble(
        role: 'model',
        text: _buddy.isConfigured
            ? "Hi! I'm Buddy! 🐻 What should we play today?"
            : "Hi! I'm Buddy! 🐻 I can't talk yet — ask a grown-up to give "
                  'me my magic key! 🔑',
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _bubbles.add(_Bubble(role: 'user', text: text));
      _bubbles.add(_Bubble(role: 'model', text: '', streaming: true));
      _busy = true;
    });
    _history.add(ChatMessage(role: 'user', text: text));
    _input.clear();
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      await for (final chunk in _buddy.reply(_history)) {
        buffer.write(chunk);
        if (mounted) {
          setState(() => _bubbles.last.text = buffer.toString());
          _scrollToBottom();
        }
      }
      final reply = buffer.toString().trim();
      if (reply.isEmpty) {
        throw StateError('Buddy said nothing — maybe try again?');
      }
      _history.add(ChatMessage(role: 'model', text: reply));
      if (mounted) {
        setState(() {
          _bubbles.last
            ..text = reply
            ..streaming = false;
          _busy = false;
        });
      }
      _speak(reply);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bubbles.removeLast();
        _bubbles.add(
          _Bubble(
            role: 'model',
            text: _buddy.isConfigured
                ? "Oops, I got lost for a moment! 😅 Can you ask me again?"
                : "I can't talk yet — ask a grown-up for my magic key! 🔑",
          ),
        );
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _speak(String text) async {
    try {
      // Simple language guess so the TTS voice matches the conversation.
      final lower = text.toLowerCase();
      final indonesian = _idStopWords.any(lower.contains);
      await _tts.setLanguage(indonesian ? 'id-ID' : 'en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(text);
    } catch (_) {
      // TTS unavailable: the text bubble is still there.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameBackground(
            child: Column(
              children: [
                // Header: home button + Buddy avatar + status.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      RoundButton(
                        emoji: '🏠',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white,
                        child: Text('🐻', style: TextStyle(fontSize: 30)),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Buddy',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                            ),
                            Text(
                              'your little friend',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(
                        emoji: '🔁',
                        onTap: () => setState(() {
                          _history.clear();
                          _bubbles
                            ..clear()
                            ..add(
                              _Bubble(
                                role: 'model',
                                text: _buddy.isConfigured
                                    ? "Hi! I'm Buddy! 🐻 What should we "
                                          'play today?'
                                    : "Hi! I'm Buddy! 🐻 I can't talk yet — "
                                          'ask a grown-up to give me my magic '
                                          'key! 🔑',
                              ),
                            );
                        }),
                      ),
                    ],
                  ),
                ),
                // Chat area.
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _bubbles.length,
                    itemBuilder: (context, index) =>
                        _buildBubble(_bubbles[index]),
                  ),
                ),
                // Quick chips for toddlers.
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _chips.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final chip = _chips[index];
                      return ActionChip(
                        onPressed: _busy ? null : () => _send(chip),
                        label: Text(chip, style: const TextStyle(fontSize: 15)),
                        backgroundColor: Colors.white,
                        disabledColor: Colors.white60,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    },
                  ),
                ),
                // Input bar.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !_busy,
                          onSubmitted: _send,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(fontSize: 17),
                          decoration: InputDecoration(
                            hintText: 'Say something…',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RoundButton(
                        emoji: '➡️',
                        fontSize: 26,
                        onTap: () => _send(_input.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_Bubble bubble) {
    final isUser = bubble.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text('🐻', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFFFFC107)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                bubble.streaming && bubble.text.isEmpty
                    ? '…'
                    : bubble.streaming
                    ? '${bubble.text} …'
                    : bubble.text,
                style: TextStyle(
                  fontSize: 17,
                  color: isUser ? Colors.black87 : Colors.black87,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble {
  _Bubble({required this.role, required this.text, this.streaming = false});

  final String role; // 'user' | 'model'
  String text;
  bool streaming;
}
