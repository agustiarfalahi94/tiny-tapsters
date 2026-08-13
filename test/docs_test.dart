import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the facts the documentation asserts about the app.
///
/// **Why this file exists.** Documentation was once rewritten from the *folder
/// name* rather than from the code: the app was given back the name it had
/// been renamed away from, a package id that does not exist, a version that
/// went backwards, six games instead of seven, and — the dangerous one — a
/// README telling readers the Gemini key ships inside the APK, which stopped
/// being true when it moved to the Cloudflare Worker. None of it broke a
/// build, so nothing caught it, and it was published.
///
/// The checkout directory has since been renamed to `tiny-tapsters`, so that
/// particular trap is gone. These assertions are not: the failure mode was
/// writing documentation from something other than the code, and the folder
/// was only the most convenient wrong source.
///
/// Prose cannot be type-checked, but the handful of load-bearing facts inside
/// it can. Anything asserted here is a fact a reader would act on.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final docs = {
    'README.md': File('README.md').readAsStringSync(),
    'CLAUDE.md': File('CLAUDE.md').readAsStringSync(),
    'AGENTS.md': File('AGENTS.md').readAsStringSync(),
    'CHANGELOG.md': File('CHANGELOG.md').readAsStringSync(),
  };

  String field(String name) => RegExp(
    '^$name:(.*)\$',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!.trim();

  test('the app is called what the code calls it', () {
    expect(field('name'), 'tiny_tapsters');
    for (final entry in docs.entries) {
      expect(
        entry.value,
        contains('Tiny Tapsters'),
        reason: '${entry.key} should name the app',
      );
      // The CHANGELOG records the v1.6.0 rename and must keep saying so, which
      // means it is the one document allowed to spell the old name out. Every
      // other document naming it is a document describing the app as it is
      // not.
      if (entry.key == 'CHANGELOG.md') continue;
      expect(
        entry.value.toLowerCase(),
        isNot(contains("toddlers' journey")),
        reason:
            '${entry.key} names the checkout directory, not the app. The app '
            'is Tiny Tapsters everywhere: pubspec, the launcher, main.dart, '
            'the release asset and the git remote.',
      );
    }
  });

  test('the package id in the docs is the one that ships', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final id = RegExp(
      r'applicationId\s*=\s*"([^"]+)"',
    ).firstMatch(gradle)!.group(1)!;
    expect(id, 'com.inkpebble.tiny_tapsters');
    for (final name in ['CLAUDE.md', 'AGENTS.md']) {
      expect(docs[name], contains(id), reason: '$name must state the real id');
    }
  });

  test('the version in the docs is the version being built', () {
    final version = field('version');
    for (final name in ['CLAUDE.md', 'AGENTS.md']) {
      expect(
        docs[name],
        contains(version),
        reason:
            '$name states a version that is not $version from pubspec.yaml. '
            'Bump all three together, or a reader trusts the wrong one.',
      );
    }
  });

  test('the docs count the games the app actually has', () {
    final games = Directory('lib/screens')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('_screen.dart'))
        .where(
          (n) => !const [
            'home_screen.dart',
            'levels_screen.dart',
            'companion_screen.dart',
            'credits_screen.dart',
          ].contains(n),
        )
        .toList();
    expect(
      games,
      hasLength(7),
      reason: 'add or remove a game, update the docs',
    );

    const written = {1: 'one', 2: 'two', 7: 'seven'};
    for (final name in ['CLAUDE.md', 'AGENTS.md']) {
      expect(
        docs[name],
        contains('${written[games.length]} games'),
        reason: '$name should say "${written[games.length]} games"',
      );
    }
  });

  test('no document claims the Gemini key ships in the app', () {
    // The most consequential thing a wrong README can say here. The key lives
    // in the Cloudflare Worker under `worker/`; the app only knows a URL.
    final claims = [
      RegExp(r'key\s+(is\s+)?(baked|compiled)\s+in', caseSensitive: false),
      RegExp(r'key\s+lives\s+in\s+the\s+APK', caseSensitive: false),
      RegExp(r'needs\s+an\s+API\s+key', caseSensitive: false),
    ];
    for (final entry in docs.entries) {
      for (final claim in claims) {
        final match = claim.firstMatch(entry.value);
        // The CHANGELOG may describe the past, so only flag the present tense
        // in the docs a newcomer reads as current.
        if (entry.key == 'CHANGELOG.md') continue;
        expect(
          match,
          isNull,
          reason:
              '${entry.key} says "${match?.group(0)}". The key has not shipped '
              'in the APK since v1.10.0 — it is a Cloudflare Worker secret. '
              'See docs/pollie-architecture-and-costs.md.',
        );
      }
    }
  });

  test('the README maps every service and widget', () {
    // The layout block is how somebody new — human or otherwise — finds their
    // way around. A file missing from it is a file they will not know exists.
    final readme = docs['README.md']!;
    final missing = <String>[];
    for (final dir in ['lib/services', 'lib/widgets', 'lib/data']) {
      for (final file in Directory(dir).listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith('.dart')) continue;
        if (!readme.contains(name)) missing.add('$dir/$name');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'these exist but the README does not mention them: $missing',
    );
  });

  test(
    'AGENTS.md lists every test file, so nobody wonders what is covered',
    () {
      final agents = docs['AGENTS.md']!;
      final missing = Directory('test')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('_test.dart'))
          .where((n) => !agents.contains(n))
          .toList();
      expect(missing, isEmpty, reason: 'undocumented test files: $missing');
    },
  );

  test('no document promises a round count Easy never asks for', () {
    // Find It! and Count the Animals both drop Easy to three rounds: five
    // questions inside a 30-second clock is six seconds each, which a
    // four-year-old will not make. Prose that states one flat number is
    // describing Medium and Big, and a reader applies it to the game in front
    // of them. `test/timer_test.dart` covers the behaviour; this covers the
    // sentence about it.
    final rule = RegExp(
      r'_roundsToWin =>\s*widget\.level == GameLevel\.easy \? (\d+) : (\d+)',
    );

    /// The `- **Name** — …` bullet for one game, up to the next bullet.
    String readmeBullet(String name) => RegExp(
      '^- \\*\\*$name\\*\\*.*?(?=^- \\*\\*)',
      multiLine: true,
      dotAll: true,
    ).firstMatch(docs['README.md']!)!.group(0)!;

    /// The `///` block introducing the class — the first thing anyone reads.
    String classDoc(String source) => RegExp(
      r'(^/// .*\n)+(?=class )',
      multiLine: true,
    ).firstMatch(source)!.group(0)!;

    for (final (screen, readmeName) in [
      ('find_it_screen', 'Find It!'),
      ('count_game_screen', 'Count the Animals!'),
    ]) {
      final source = File('lib/screens/$screen.dart').readAsStringSync();
      final match = rule.firstMatch(source);
      expect(
        match,
        isNotNull,
        reason:
            '$screen no longer varies its round count by level. Update this '
            'test and the sentences it guards together.',
      );
      final easy = match!.group(1)!;
      final rest = match.group(2)!;
      expect(
        easy,
        isNot(rest),
        reason: 'if every level asks the same, this test has nothing to guard',
      );

      final prose = {
        '$screen.dart': classDoc(source),
        'README.md ($readmeName)': readmeBullet(readmeName),
      };
      // A number next to "win" or "rounds" is a promise about how long a game
      // is. Making it must mean saying Easy is shorter.
      final promise = RegExp('\\b$rest\\b[^.]*\\b(win|rounds)\\b');
      // Deliberately the exact phrase, not just "contains $easy": the Count
      // the Animals! blurb already says "Easy (count to 3)" about how high it
      // counts, which is a different 3 and let a missing round count through.
      final correction = RegExp('\\b$easy on Easy\\b');
      for (final entry in prose.entries) {
        if (!promise.hasMatch(entry.value)) continue;
        expect(
          entry.value,
          matches(correction),
          reason:
              '${entry.key} promises $rest rounds without saying "$easy on '
              'Easy" ($screen.dart sets it). A reader who opens Easy is told '
              'the wrong game length.',
        );
      }
    }
  });

  test('the two agent files agree with each other', () {
    // They are the same instructions for two tools. Drift between them is how
    // one agent ends up working from facts the other has already corrected.
    final claude = docs['CLAUDE.md']!;
    final agents = docs['AGENTS.md']!;
    for (final fact in [
      field('version'),
      'com.inkpebble.tiny_tapsters',
      'seven games',
    ]) {
      expect(claude, contains(fact));
      expect(agents, contains(fact));
    }
  });
}
