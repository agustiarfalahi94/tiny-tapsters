import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'speech_to_text_platform_interface.dart';

const MethodChannel _channel =
    MethodChannel('plugin.csdcorp.com/speech_to_text');

/// An implementation of [SpeechToTextPlatform] that uses method channels.
class MethodChannelSpeechToText extends SpeechToTextPlatform {
  // TINY TAPSTERS PATCH — IDs survive queued native delivery. Filter here,
  // before SpeechToText changes listening/results/error state.
  static int _nextSessionId = 0;
  int? _sessionId;
  bool get _requiresOwnership =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  static const String textRecognitionMethod = 'textRecognition';
  static const String notifyErrorMethod = 'notifyError';
  static const String notifyStatusMethod = 'notifyStatus';
  static const String soundLevelChangeMethod = "soundLevelChange";

  /// Returns true if the user has already granted permission to access the
  /// microphone, does not prompt the user.
  ///
  /// This method can be called before [initialize] to check if permission
  /// has already been granted. If this returns false then the [initialize]
  /// call will prompt the user for permission if it is allowed to do so.
  /// Note that applications cannot ask for permission again if the user has
  /// denied them permission in the past.
  @override
  Future<bool> hasPermission() async {
    return await _channel.invokeMethod<bool>('has_permission') ?? false;
  }

  @override
  Future<bool> initialize(
      {debugLogging = false, List<SpeechConfigOption>? options}) async {
    _channel.setMethodCallHandler(_handleCallbacks);
    var params = <String, Object>{
      'debugLogging': debugLogging,
    };
    options?.forEach((option) => params[option.name] = option.value);
    return await _channel.invokeMethod<bool>(
          'initialize',
          params,
        ) ??
        false;
  }

  /// Stops the current listen for speech if active, does nothing if not.
  ///
  /// Stopping a listen session will cause a final result to be sent. Each
  /// listen session should be ended with either [stop] or [cancel], for
  /// example in the dispose method of a Widget. [cancel] is automatically
  /// invoked by a permanent error if [cancelOnError] is set to true in the
  /// [listen] call.
  ///
  /// *Note:* Cannot be used until a successful [initialize] call. Should
  /// only be used after a successful [listen] call.
  @override
  Future<void> stop() {
    return _channel.invokeMethod('stop', {'sessionId': _sessionId});
  }

  /// Cancels the current listen for speech if active, does nothing if not.
  ///
  /// Canceling means that there will be no final result returned from the
  /// recognizer. Each listen session should be ended with either [stop] or
  /// [cancel], for example in the dispose method of a Widget. [cancel] is
  /// automatically invoked by a permanent error if [cancelOnError] is set
  /// to true in the [listen] call.
  ///
  /// *Note* Cannot be used until a successful [initialize] call. Should only
  /// be used after a successful [listen] call.
  @override
  Future<void> cancel() {
    final retired = _sessionId;
    _sessionId = null;
    return _channel.invokeMethod('cancel', {'sessionId': retired});
  }

  /// Starts a listening session for speech and converts it to text.
  ///
  /// Cannot be used until a successful [initialize] call. There is a
  /// time limit on listening imposed by both Android and iOS. The time
  /// depends on the device, network, etc. Android is usually quite short,
  /// especially if there is no active speech event detected, on the order
  /// of ten seconds or so.
  ///
  /// [localeId] is an optional locale that can be used to listen in a language
  /// other than the current system default. See [locales] to find the list of
  /// supported languages for listening.
  ///
  /// [partialResults] if true the listen reports results as they are recognized,
  /// when false only final results are reported. Defaults to true.
  ///
  /// [onDevice] if true the listen attempts to recognize locally with speech never
  /// leaving the device. If it cannot do this the listen attempt will fail. This is
  /// usually only needed for sensitive content where privacy or security is a concern.
  ///
  /// [sampleRate] optional for compatibility with certain iOS devices, some devices
  /// crash with `sampleRate != device's supported sampleRate`, try 44100 if seeing
  /// crashes
  ///
  @override
  Future<bool> listen(
      {String? localeId,
      @deprecated partialResults = true,
      @deprecated onDevice = false,
      @deprecated int listenMode = 0,
      @deprecated sampleRate = 0,
      SpeechListenOptions? options}) async {
    final sessionId = ++_nextSessionId;
    _sessionId = sessionId;
    Map<String, dynamic> listenParams = {
      'sessionId': sessionId,
      "partialResults": options?.partialResults ?? partialResults,
      "onDevice": options?.onDevice ?? onDevice,
      "listenMode": options?.listenMode.index ?? listenMode,
      "sampleRate": options?.sampleRate ?? sampleRate,
      "enableHaptics": options?.enableHapticFeedback ?? false,
      "autoPunctuation": options?.autoPunctuation ?? false,
      "pauseFor": options?.pauseFor?.inMilliseconds ?? null,
      // TINY TAPSTERS PATCH — see packages/PATCH.md.
      "possiblyCompleteSilence":
          options?.possiblyCompleteSilence?.inMilliseconds ?? null,
      "minimumLength": options?.minimumLength?.inMilliseconds ?? null,
      "completeSilence": options?.completeSilence?.inMilliseconds ?? null,
      "listenFor": options?.listenFor?.inMilliseconds ?? null,
    };
    if (null != (localeId ?? options?.localeId)) {
      listenParams["localeId"] = (localeId ?? options?.localeId);
    }
    final started = await _channel.invokeMethod<bool>('listen', listenParams) ?? false;
    if (!started && _sessionId == sessionId) _sessionId = null;
    return started;
  }

  /// returns the list of speech locales available on the device.
  ///
  @override
  Future<List<dynamic>> locales() async {
    return await _channel.invokeMethod<List<dynamic>>('locales') ?? [];
  }

  Future _handleCallbacks(MethodCall call) async {
    var payload = call.arguments;
    if (payload is Map) {
      if (_sessionId == null || payload['sessionId'] != _sessionId) return;
      payload = payload['payload'];
    } else if (_requiresOwnership) {
      // Paired Android/Apple forks must not silently accept untagged events.
      return;
    }
    switch (call.method) {
      case textRecognitionMethod:
        if (payload is String && null != onTextRecognition) {
          onTextRecognition!(payload);
        }
        break;
      case notifyErrorMethod:
        if (payload is String && null != onError) {
          onError!(payload);
        }
        break;
      case notifyStatusMethod:
        if (payload is String && null != onStatus) {
          onStatus!(payload);
        }
        break;
      case soundLevelChangeMethod:
        if (payload is double && null != onSoundLevel) {
          onSoundLevel!(payload);
        }
        break;
      default:
    }
  }

  @visibleForTesting
  Future processMethodCall(MethodCall call) async {
    return await _handleCallbacks(call);
  }

  @visibleForTesting
  MethodChannel get channel => _channel;
}
