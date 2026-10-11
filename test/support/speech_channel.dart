import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/method_channel_speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Only the native recognizer is replaced; channel decoding and Dart speech
/// state are real. Ownership comes from outbound listen requests, not the fake.
class NativeSpeechChannel {
  final platform = MethodChannelSpeechToText();
  final listens = <Map<Object?, Object?>>[];
  final calls = <String>[];
  Completer<void>? cancellation;
  Completer<void>? stopping;
  Completer<bool>? starting;

  void install() {
    SpeechToTextPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'initialize':
            case 'has_permission':
              return true;
            case 'locales':
              return ['en-US:English'];
            case 'listen':
              listens.add(Map<Object?, Object?>.from(call.arguments as Map));
              return starting == null ? true : await starting!.future;
            case 'cancel':
              await cancellation?.future;
              return true;
            case 'stop':
              await stopping?.future;
              return true;
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.channel, null);
  }

  Object? get owner => listens.last['sessionId'];

  Future<void> emit(Object? owner, String method, Object payload) =>
      platform.processMethodCall(
        MethodCall(
          method,
          owner == null ? payload : {'sessionId': owner, 'payload': payload},
        ),
      );
}
