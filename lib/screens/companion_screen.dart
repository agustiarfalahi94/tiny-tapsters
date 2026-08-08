import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/kid_safety.dart';
import '../services/pollie_service.dart';
import '../widgets/game_background.dart';
import '../widgets/round_button.dart';

enum _PollieStatus { sleeping, awake, listening, thinking, speaking }

/// Pollie 🦜 — a talking companion powered by Gemini.
///
/// Pollie sleeps 😴 while offline and smiles 😊 once Gemini answers a
/// connectivity probe, then greets the child. Tap the 🎤 to talk: speech is
/// transcribed (Google speech-to-text), answered by Gemini, and spoken aloud
/// (system TTS) — then Pollie listens again automatically, so a toddler can
/// just keep chatting like in the Gemini app. Toddlers can also tap the big
/// chips; grown-ups can type.
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen>
    with WidgetsBindingObserver {
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
  static const _greeting = 'Hi kids! Let\'s talk with me 🦜';
  static const _gentleMessage =
      "Hmm, that's not a nice thing to say! Let's talk about something fun "
      'instead 😊';

  /// Emoji (and symbol) ranges, stripped before speaking so the TTS only
  /// reads plain text. Includes variation selectors and ZWJ sequences.
  static final _emojiPattern = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{2190}-\u{21FF}\u{25A0}-\u{25FF}\u{FE0F}\u{200D}\u{20E3}'
    r'\u{1F1E6}-\u{1F1FF}\u{00A9}\u{00AE}\u{2122}\u{203C}\u{2049}'
    r'\u{3030}\u{303D}]',
    unicode: true,
  );

  final _pollie = PollieService();
  final _history = <ChatMessage>[];
  final _bubbles = <_Bubble>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _speech = SpeechToText();
  _PollieStatus _status = _PollieStatus.sleeping;
  bool _waking = false;
  bool _busy = false;
  bool _speechAvailable = false;
  String _localeId = 'en-US';
  String _partial = '';
  double _soundLevel = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSpeechLocale();
    if (_pollie.isConfigured) {
      _bubbles.add(_Bubble(role: 'model', text: ''));
      _wakeUp();
    } else {
      _bubbles.add(
        _Bubble(
          role: 'model',
          text:
              "Hi! I'm Pollie! 🦜 I can't talk yet — ask a grown-up to "
              'give me my magic key! 🔑',
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Never leave the mic or the TTS engine running after leaving Pollie.
    try {
      _speech.stop();
      _tts.stop();
    } catch (_) {}
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // No mic/TTS while the app is in the background.
      try {
        _speech.stop();
        _tts.stop();
      } catch (_) {}
      if (mounted && _status == _PollieStatus.listening) {
        setState(() {
          _status = _PollieStatus.awake;
          _busy = false;
          _partial = '';
        });
      }
    }
  }

  /// Picks the speech recognition locale from the device language
  /// (Indonesian or English), falling back to en-US.
  Future<void> _initSpeechLocale() async {
    try {
      final available = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: (status) {
          // Listening ended (timeout / stop): return to the idle smile.
          if (status == 'done' && mounted) {
            setState(() {
              if (_status == _PollieStatus.listening) {
                _status = _PollieStatus.awake;
                _busy = false;
                _partial = '';
              }
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
      if (available) {
        final lang = (await _speech.systemLocale())?.localeId ?? '';
        if (lang.startsWith('id') || lang.startsWith('in')) {
          _localeId = 'id-ID';
        } else if (lang.startsWith('en')) {
          _localeId = 'en-US';
        }
      }
    } catch (_) {
      _speechAvailable = false;
    }
  }

  /// Probes Gemini and flips Pollie's mood: smiling 😊 + greeting on
  /// success, sleeping 😴 + a retry hint on failure.
  Future<void> _wakeUp() async {
    if (_waking) return;
    setState(() {
      _waking = true;
      _status = _PollieStatus.sleeping;
    });
    final awake = await _pollie.ping();
    if (!mounted) return;
    setState(() {
      _waking = false;
      _status = awake ? _PollieStatus.awake : _PollieStatus.sleeping;
      _bubbles
        ..clear()
        ..add(
          _Bubble(
            role: 'model',
            text: awake
                ? _greeting
                : 'Zzz… I can\'t reach the internet yet. '
                      'Tap me to try waking up again! 😴',
          ),
        );
    });
    if (awake) {
      _speak('Hi kids! Let\'s talk with me!', thenListen: true);
    }
  }

  /// Pollie's gentle response when the child (or the model) says something
  /// inappropriate.
  void _gentleRedirect() {
    setState(() {
      _bubbles.add(_Bubble(role: 'model', text: _gentleMessage));
    });
    _scrollToBottom();
    _speak(
      "Hmm, that's not a nice thing to say! Let's talk about "
      'something fun instead.',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final atBottom = position.maxScrollExtent - position.pixels < 60;
      if (atBottom) {
        // Jump (not animate) while the reply streams in — restarting a
        // scroll animation on every chunk would jitter.
        position.jumpTo(position.maxScrollExtent);
      } else {
        position.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Starts listening; the mic button toggles it off.
  Future<void> _startListening() async {
    if (_status != _PollieStatus.awake || _busy) return;
    if (!_speechAvailable) {
      _bubbles.add(
        _Bubble(
          role: 'model',
          text:
              "I can't hear you! 🎤 Ask a grown-up to allow the "
              'microphone, then tap the mic again.',
        ),
      );
      _scrollToBottom();
      return;
    }
    setState(() {
      _status = _PollieStatus.listening;
      _busy = true;
      _partial = '';
      _soundLevel = 0;
    });
    try {
      await _speech.listen(
        onResult: (result) {
          setState(() => _partial = result.recognizedWords);
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _speech.stop();
            setState(() {
              _busy = false;
              _partial = '';
            });
            _send(result.recognizedWords.trim());
          }
        },
        onSoundLevelChange: (level) =>
            setState(() => _soundLevel = level.clamp(0, 1)),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Speech engine hiccup: fall back to the idle smile, never crash.
      debugPrint('Listening failed: $e');
      if (mounted) {
        setState(() {
          _status = _PollieStatus.awake;
          _busy = false;
          _partial = '';
        });
      }
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _status = _PollieStatus.awake;
      _busy = false;
      _partial = '';
    });
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    // "No match" / timeout / silence is normal when nobody speaks — stay
    // quiet instead of popping an error bubble.
    final message = error.errorMsg.toLowerCase();
    final quiet =
        message.contains('no match') ||
        message.contains('timeout') ||
        message.contains('no speech') ||
        error.permanent;
    if (!quiet) {
      _bubbles.add(
        _Bubble(
          role: 'model',
          text: "Oops, I didn't catch that! 😅 Tap the mic and try again?",
        ),
      );
      _scrollToBottom();
    }
    setState(() {
      _status = _PollieStatus.awake;
      _busy = false;
      _partial = '';
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    // Local safety guard: inappropriate words never reach Gemini (or the
    // conversation history).
    if (KidSafety.containsBlocked(text)) {
      _input.clear();
      _gentleRedirect();
      return;
    }

    setState(() {
      _bubbles.add(_Bubble(role: 'user', text: text));
      _bubbles.add(_Bubble(role: 'model', text: '', streaming: true));
      _busy = true;
      _status = _PollieStatus.thinking;
    });
    _history.add(ChatMessage(role: 'user', text: text));
    _input.clear();
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      await for (final chunk in _pollie.reply(_history)) {
        buffer.write(chunk);
        if (mounted) {
          setState(() => _bubbles.last.text = buffer.toString());
          _scrollToBottom();
        }
      }
      final reply = buffer.toString().trim();
      if (reply.isEmpty) {
        throw StateError('Pollie said nothing — maybe try again?');
      }
      // Output safety guard: if anything inappropriate slipped through the
      // model filters, the child never sees or hears it.
      if (KidSafety.containsBlocked(reply)) {
        if (mounted) {
          setState(() {
            _bubbles.removeLast();
            _bubbles.add(_Bubble(role: 'model', text: _gentleMessage));
            _busy = false;
          });
        }
        _speak(
          "Hmm, that's not a nice thing to say! Let's talk about "
          'something fun instead.',
        );
        return;
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
      _speak(reply, thenListen: true);
    } catch (e) {
      debugPrint('Pollie reply failed: $e');
      if (!mounted) return;
      setState(() {
        _bubbles.removeLast();
        _bubbles.add(
          _Bubble(
            role: 'model',
            text: _pollie.isConfigured
                ? 'Oops, I got lost for a moment! 😅 '
                      'Can you ask me again?'
                : "I can't talk yet — ask a grown-up for my magic key! 🔑",
          ),
        );
        _status = _PollieStatus.sleeping;
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  /// Plain text for the TTS: emojis and roleplay markers removed.
  String _cleanForSpeech(String text) {
    return text
        .replaceAll(_emojiPattern, '')
        .replaceAll('*', '')
        .replaceAll('…', '.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Map<dynamic, dynamic>>? _cachedVoices;

  /// Picks the warmest available voice for the locale (highest quality,
  /// preferring female voices — the closest to a "kid/Ms-Rachel" feel).
  Future<void> _applyBestVoice(String lang) async {
    try {
      _cachedVoices ??= await _tts.getVoices as List<Map<dynamic, dynamic>>?;
      final voices = _cachedVoices;
      if (voices == null || voices.isEmpty) return;
      final langCode = lang.split('-').first.toLowerCase();
      final candidates = voices
          .where(
            (v) => (v['locale'] ?? '').toString().toLowerCase().startsWith(
              langCode,
            ),
          )
          .toList();
      if (candidates.isEmpty) return;

      Map<dynamic, dynamic> best = candidates.first;
      for (final voice in candidates.skip(1)) {
        final quality = (voice['quality'] as num?)?.toInt() ?? 0;
        final bestQuality = (best['quality'] as num?)?.toInt() ?? 0;
        final name = (voice['name'] ?? '').toString().toLowerCase();
        final bestName = (best['name'] ?? '').toString().toLowerCase();
        final female = name.contains('female') || name.contains('#f_');
        final bestFemale =
            bestName.contains('female') || bestName.contains('#f_');
        if (quality > bestQuality ||
            (quality == bestQuality && female && !bestFemale)) {
          best = voice;
        }
      }
      await _tts.setVoice(best.cast<String, String>());
    } catch (_) {
      // Default engine voice is fine when no choice exists.
    }
  }

  Future<void> _speak(String text, {bool thenListen = false}) async {
    if (mounted) setState(() => _status = _PollieStatus.speaking);
    try {
      // Simple language guess so the TTS voice matches the conversation.
      final lower = text.toLowerCase();
      final indonesian = _idStopWords.any(lower.contains);
      final lang = indonesian ? 'id-ID' : 'en-US';
      await _tts.setLanguage(lang);
      await _applyBestVoice(lang);
      // Slightly higher pitch + warm pace for a gentle, kid-friendly voice.
      await _tts.setPitch(1.35);
      await _tts.setSpeechRate(0.5);
      // Once the reply is spoken, re-arm the microphone for a hands-free
      // conversation loop.
      _tts.setCompletionHandler(() async {
        if (!mounted) return;
        setState(() => _status = _PollieStatus.awake);
        if (thenListen && _speechAvailable && _pollie.isConfigured) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) _startListening();
        }
      });
      _tts.setErrorHandler((message) {
        if (mounted) setState(() => _status = _PollieStatus.awake);
      });
      await _tts.speak(_cleanForSpeech(text));
    } catch (_) {
      // TTS unavailable: the text bubble is still there.
      if (mounted) {
        setState(() => _status = _PollieStatus.awake);
        if (thenListen && _speechAvailable && _pollie.isConfigured) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) _startListening();
        }
      }
    }
  }

  void _reset() {
    _history.clear();
    _stopListening();
    setState(() {
      _bubbles.clear();
      if (_pollie.isConfigured) {
        _bubbles.add(_Bubble(role: 'model', text: ''));
        _status = _PollieStatus.sleeping;
      } else {
        _bubbles.add(
          _Bubble(
            role: 'model',
            text:
                "Hi! I'm Pollie! 🦜 I can't talk yet — ask a grown-up to "
                'give me my magic key! 🔑',
          ),
        );
      }
    });
    if (_pollie.isConfigured) _wakeUp();
  }

  String get _statusText {
    if (_waking) return 'waking up…';
    switch (_status) {
      case _PollieStatus.sleeping:
        return 'sleeping… 😴';
      case _PollieStatus.awake:
        return 'awake! 😊';
      case _PollieStatus.listening:
        return 'listening… 👂';
      case _PollieStatus.thinking:
        return 'thinking… 🤔';
      case _PollieStatus.speaking:
        return 'speaking… 🗣️';
    }
  }

  String get _statusFace {
    switch (_status) {
      case _PollieStatus.sleeping:
        return '😴';
      case _PollieStatus.awake:
        return '😊';
      case _PollieStatus.listening:
        return '👂';
      case _PollieStatus.thinking:
        return '🤔';
      case _PollieStatus.speaking:
        return '🗣️';
    }
  }

  void _onMicTap() {
    if (_status == _PollieStatus.listening) {
      _stopListening();
    } else {
      _startListening();
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
                // Header: home button + Pollie status avatar + name.
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
                      // The face shows Pollie's mood; tap it to wake him up.
                      GestureDetector(
                        onTap: _status == _PollieStatus.sleeping
                            ? _wakeUp
                            : null,
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white,
                          child: Text(
                            _statusFace,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pollie',
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
                              _statusText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(emoji: '🔁', onTap: _reset),
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
                // Live listening transcript.
                if (_status == _PollieStatus.listening)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Text('👂', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _partial.isEmpty ? 'Listening…' : '$_partial …',
                              style: const TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                // Input bar: mic (talk) + text field + send.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      // The mic pulses with the sound level while listening.
                      GestureDetector(
                        onTap: _onMicTap,
                        child: AnimatedScale(
                          scale: _status == _PollieStatus.listening
                              ? 1 + _soundLevel * 0.6
                              : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: Material(
                            color: _status == _PollieStatus.listening
                                ? const Color(0xFFFF5252)
                                : Colors.white,
                            shape: const CircleBorder(),
                            elevation: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '🎤',
                                style: TextStyle(
                                  fontSize: 26,
                                  color: _status == _PollieStatus.listening
                                      ? Colors.white
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
              child: Text('🦜', style: TextStyle(fontSize: 20)),
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
                style: const TextStyle(fontSize: 17, height: 1.3),
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
