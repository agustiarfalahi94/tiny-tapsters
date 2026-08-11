import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_tapsters/screens/companion_screen.dart';
import 'package:tiny_tapsters/services/pollie_service.dart';

/// A stand-in for the Cloudflare Worker, so the client is tested against real
/// sockets and real chunking rather than a mock that agrees with it.
class FakeProxy {
  FakeProxy._(this._server);

  final HttpServer _server;
  final requests = <HttpRequest>[];
  final bodies = <String>[];

  int status = 200;
  List<String> chunks = const [];
  String body = '';
  Map<String, String> extraHeaders = const {};

  static Future<FakeProxy> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = FakeProxy._(server);
    unawaited(proxy._serve());
    return proxy;
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _serve() async {
    await for (final request in _server) {
      requests.add(request);
      bodies.add(await utf8.decoder.bind(request).join());
      request.response.statusCode = status;
      extraHeaders.forEach(request.response.headers.set);
      if (chunks.isNotEmpty) {
        for (final chunk in chunks) {
          request.response.write(chunk);
          // Flush per chunk so the client sees a real streamed response.
          await request.response.flush();
        }
      } else if (body.isNotEmpty) {
        request.response.write(body);
      }
      await request.response.close();
    }
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  group('sentence splitting', () {
    test('only complete sentences are handed over', () {
      // Pollie must not start saying half a sentence.
      expect(lastSentenceEnd('Hello there', 0), 0);
      // The cut lands past the separating space, so the spoken piece is the
      // sentence and the unspoken remainder starts at the next word.
      const two = 'Hello there. And';
      expect(two.substring(0, lastSentenceEnd(two, 0)).trim(), 'Hello there.');
      expect(two.substring(lastSentenceEnd(two, 0)), 'And');
      expect(lastSentenceEnd('Hi! How are you? Good', 0), 17);
    });

    test('picks up where the last sentence left off', () {
      const reply = 'One. Two. Three.';
      final first = lastSentenceEnd(reply, 0);
      expect(reply.substring(0, first).trim(), 'One. Two. Three.');
      // Nothing new to say once everything has been said.
      expect(lastSentenceEnd(reply, first), first);
    });

    test('a decimal is not a sentence', () {
      // The trailing-whitespace requirement is the whole reason this holds.
      expect(lastSentenceEnd('You have 3.5 apples', 0), 0);
    });

    test('handles closing quotes, ellipses and Indonesian', () {
      expect(lastSentenceEnd('He said "hi!" Then', 0), 14);
      expect(lastSentenceEnd('Well… okay', 0), 6);
      expect(lastSentenceEnd('Halo! Apa kabar? Baik', 0), 17);
    });

    test('an unterminated tail is left for the caller to flush', () {
      const reply = 'All done. Bye';
      final cut = lastSentenceEnd(reply, 0);
      expect(reply.substring(cut), 'Bye');
    });
  });

  group('a repeated short answer', () {
    test('collapses back to what the child meant', () {
      // Measured on the device: two spoken "no"s came back as one guess,
      // "no no", because the recogniser re-scores the first once it has heard
      // the second.
      expect(collapseRepeatedAnswer('no no'), 'no');
      expect(collapseRepeatedAnswer('no no no'), 'no');
      expect(collapseRepeatedAnswer('Yes yes'), 'Yes');
      expect(collapseRepeatedAnswer('tidak tidak'), 'tidak');
    });

    test('leaves reduplication that means something alone', () {
      // These are real words, not a child repeating themselves.
      expect(collapseRepeatedAnswer('bye bye'), 'bye bye');
      expect(collapseRepeatedAnswer('night night'), 'night night');
      expect(collapseRepeatedAnswer('knock knock'), 'knock knock');
    });

    test('never touches a real sentence', () {
      expect(collapseRepeatedAnswer('no i want a story'), 'no i want a story');
      expect(collapseRepeatedAnswer('yes please'), 'yes please');
      expect(collapseRepeatedAnswer('no'), 'no');
      expect(collapseRepeatedAnswer(''), '');
    });
  });

  group('choosing the recogniser language', () {
    test('the app language wins, in whatever form the device spells it', () {
      // The reported bug: the setting said Indonesian, Pollie answered in
      // Indonesian, and the microphone was still listening in English —
      // because the system locale was read *after* the choice and overwrote
      // it. Nothing the child said in Indonesian could be understood.
      expect(matchLocale('id-ID', ['en-US', 'id_ID']), 'id_ID');
      expect(matchLocale('id-ID', ['en_US', 'id-ID']), 'id-ID');
      expect(matchLocale('en-US', ['en_US', 'id_ID']), 'en_US');
    });

    test('a bare language code still counts', () {
      expect(matchLocale('id-ID', ['en-US', 'id']), 'id');
      expect(matchLocale('id-ID', ['id-Latn-ID']), 'id-Latn-ID');
    });

    test('null when the device really has nothing for that language', () {
      // Better to say so in the log than to silently listen in the wrong one.
      expect(matchLocale('id-ID', ['en-US', 'fr-FR']), isNull);
      expect(matchLocale('id-ID', const []), isNull);
    });
  });

  group('joining what the recogniser heard', () {
    test('a dying session keeps its words', () {
      // The reported bug: "do you know about minecraft?" arrived as
      // "know minecraft", because the session holding "do you" ended without
      // a final result and the next session overwrote it.
      expect(
        appendHeard('do you', 'know about minecraft'),
        'do you know about minecraft',
      );
    });

    test('nothing is added for an empty guess', () {
      expect(appendHeard('hello there', ''), 'hello there');
      expect(appendHeard('hello there', '   '), 'hello there');
      expect(appendHeard('', 'hello'), 'hello');
    });

    test('a restatement does not stutter', () {
      // Some recognisers repeat the whole utterance in the next session.
      expect(appendHeard('do you', 'do you'), 'do you');
      expect(
        appendHeard('do you know', 'know about cats'),
        'do you know about cats',
      );
    });

    test('a partial overlap is joined without repeating', () {
      expect(
        appendHeard('tell me a', 'a story about dogs'),
        'tell me a story about dogs',
      );
    });

    test('a repeat is one word, whatever the recogniser capitalises', () {
      // A child whose short "no" did not register says it again. The
      // recogniser capitalises the first word of every fresh guess, so this
      // arrives as "No" then "no" — and a literal comparison sent "No no".
      expect(appendHeard('No', 'no'), 'No');
      expect(appendHeard('no', 'No'), 'no');
      expect(appendHeard('Yes', 'yes please'), 'Yes please');
      expect(appendHeard('No.', 'no'), 'No.');
      expect(
        appendHeard('tell me a story', 'Story about a dog'),
        'tell me a story about a dog',
      );
    });

    test('unrelated speech is simply appended', () {
      expect(appendHeard('hello', 'goodbye'), 'hello goodbye');
    });
  });

  group('PollieService', () {
    test('a build with no endpoint set still reaches the proxy', () {
      // CI always passes --dart-define=POLLIE_ENDPOINT=..., so an unset repo
      // variable passes an *empty* one. Empty must mean "not configured", or
      // every APK the workflow builds ships with Pollie silently switched off.
      expect(PollieService().isConfigured, isTrue);
    });

    test('an unconfigured endpoint is reported, not thrown', () async {
      final pollie = PollieService(endpoint: '');
      expect(pollie.isConfigured, isFalse);
      expect(await pollie.ping(), PolliePing.unreachable);
      expect(pollie.reply(const []), emitsError(isA<StateError>()));
    });

    test('a reply arrives as text, one NDJSON line at a time', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"text":"Hi there!"}\n', '{"text":" How are you?"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      final pieces = await pollie.reply(const [
        ChatMessage(role: 'user', text: 'hello'),
      ]).toList();

      expect(pieces.join(), 'Hi there! How are you?');
    });

    test('a line split across chunks is still parsed', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      // A phone on a bad connection is exactly where a JSON object arrives in
      // two pieces, so the client must not assume chunk == line.
      proxy.chunks = ['{"text":"Hel', 'lo!"}\n{"text":" Bye"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      final pieces = await pollie.reply(const [
        ChatMessage(role: 'user', text: 'hi'),
      ]).toList();

      expect(pieces.join(), 'Hello! Bye');
    });

    test('a malformed line does not lose the rest of the reply', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"text":"Good"}\n', 'not json\n', '{"text":" one!"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      final pieces = await pollie.reply(const [
        ChatMessage(role: 'user', text: 'hi'),
      ]).toList();

      expect(pieces.join(), 'Good one!');
    });

    test('the request carries the history and an install id', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"text":"ok"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      await pollie.reply(const [
        ChatMessage(role: 'user', text: 'hello'),
        ChatMessage(role: 'model', text: 'hi!'),
      ]).toList();

      final installId = proxy.requests.single.headers.value('X-Install-Id');
      expect(installId, isNotNull);
      expect(installId!.length, greaterThanOrEqualTo(8));

      final sent = jsonDecode(proxy.bodies.single) as Map<String, dynamic>;
      expect(sent['messages'], [
        {'role': 'user', 'text': 'hello'},
        {'role': 'model', 'text': 'hi!'},
      ]);
    });

    test('being rate limited reads as running out of words', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.status = 429;
      proxy.body = '{"error":"quota"}';

      final pollie = PollieService(endpoint: proxy.url);
      expect(await pollie.ping(), PolliePing.quota);
      // The screen decides quota vs. generic failure by looking for "quota"
      // in the error text, so that has to survive.
      await expectLater(
        pollie.reply(const [ChatMessage(role: 'user', text: 'hi')]).toList(),
        throwsA(
          isA<PollieQuotaException>().having(
            (e) => e.toString(),
            'toString',
            contains('quota'),
          ),
        ),
      );
    });

    test('a long conversation does not exhaust the connection pool', () async {
      // Every request used to build a brand-new HttpClient and never close it,
      // so a long chat ran the phone out of sockets and then failed forever.
      // Fifty turns against a real socket is a coarse but honest guard.
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"text":"ok"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      addTearDown(pollie.dispose);
      for (var turn = 0; turn < 50; turn++) {
        final pieces = await pollie.reply(const [
          ChatMessage(role: 'user', text: 'hi'),
        ]).toList();
        expect(pieces.join(), 'ok', reason: 'turn $turn failed');
      }
      expect(proxy.requests.length, 50);
      // The actual fix: one client for the whole session. This used to be 50,
      // each with its own connection pool and none of them ever closed.
      expect(pollie.clientsCreated, 1);
    });

    test('a disposed service refuses to talk instead of leaking', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.body = '{"ok":true}';

      final pollie = PollieService(endpoint: proxy.url);
      expect(await pollie.ping(), PolliePing.ok);
      pollie.dispose();
      // Leaving Pollie's screen closes the pool; anything still in flight
      // afterwards must fail rather than reopen it.
      expect(await pollie.ping(), PolliePing.unreachable);
    });

    test('an empty reply is a hiccup, not a breakdown', () async {
      // A 200 carrying no words used to surface as a generic failure, which
      // put Pollie to sleep and greyed out the mic — leaving a child with no
      // way to continue. It is now its own thing, so the screen can stay
      // awake and simply invite them to ask again.
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"empty":true,"reason":"SAFETY"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      addTearDown(pollie.dispose);
      await expectLater(
        pollie.reply(const [ChatMessage(role: 'user', text: 'hi')]).toList(),
        throwsA(isA<PollieEmptyReplyException>()),
      );
    });

    test('words still arrive when the proxy also reports the reason', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.chunks = ['{"text":"Halo!"}\n'];

      final pollie = PollieService(endpoint: proxy.url);
      addTearDown(pollie.dispose);
      expect(
        (await pollie.reply(const [
          ChatMessage(role: 'user', text: 'hi'),
        ]).toList()).join(),
        'Halo!',
      );
    });

    test('a brief pause is told apart from the day being over', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.status = 429;
      proxy.body = '{"error":"rate"}';
      proxy.extraHeaders = {'Retry-After': '30'};

      final pollie = PollieService(endpoint: proxy.url);
      addTearDown(pollie.dispose);
      await expectLater(
        pollie.reply(const [ChatMessage(role: 'user', text: 'hi')]).toList(),
        throwsA(
          isA<PollieQuotaException>().having((e) => e.isBrief, 'isBrief', true),
        ),
      );
    });

    test(
      'an emoji in the history does not break every later request',
      () async {
        // Dart's HttpClient.write encodes as Latin-1. Pollie uses an emoji now
        // and then; the moment one entered the history, every request after it
        // threw "Contains invalid characters" and the conversation was over for
        // the rest of the session. Indonesian accents would have done the same.
        final proxy = await FakeProxy.start();
        addTearDown(proxy.stop);
        proxy.chunks = ['{"text":"ok"}\n'];

        final pollie = PollieService(endpoint: proxy.url);
        addTearDown(pollie.dispose);
        final pieces = await pollie.reply(const [
          ChatMessage(role: 'user', text: 'hello'),
          ChatMessage(role: 'model', text: 'A bright sunny day! ☀️'),
          ChatMessage(
            role: 'user',
            text: 'Halo, apa kabar? Saya suka warna hijau',
          ),
        ]).toList();

        expect(pieces.join(), 'ok');
        // And the server received the characters intact, not mangled.
        final sent = jsonDecode(proxy.bodies.single) as Map<String, dynamic>;
        final texts = [
          for (final m in sent['messages'] as List)
            (m as Map)['text'] as String,
        ];
        expect(texts[1], contains('☀️'));
        expect(texts[2], contains('kabar'));
      },
    );

    test('a successful ping is remembered for a few minutes', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.body = '{"ok":true}';

      final pollie = PollieService(endpoint: proxy.url);
      expect(pollie.recentlyAwake, isFalse);
      expect(await pollie.ping(), PolliePing.ok);
      // Free-tier quota is precious; one probe per screen open adds up.
      expect(pollie.recentlyAwake, isTrue);
    });

    test('a ping that says nothing is not a wake-up', () async {
      final proxy = await FakeProxy.start();
      addTearDown(proxy.stop);
      proxy.body = '{"ok":false}';

      final pollie = PollieService(endpoint: proxy.url);
      expect(await pollie.ping(), PolliePing.unreachable);
      expect(pollie.recentlyAwake, isFalse);
    });
  });
}
