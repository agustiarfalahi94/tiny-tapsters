import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the facts the documentation asserts about the app.
///
/// **Why this file exists.** Documentation was once rewritten from the *folder
/// name* rather than from the code: the app was renamed to "Our Toddlers'
/// Journey", given a package id that does not exist, a version that went
/// backwards, six games instead of seven, and — the dangerous one — a README
/// telling readers the Gemini key ships inside the APK, which stopped being
/// true when it moved to the Cloudflare Worker. None of it broke a build, so
/// nothing caught it, and it was published.
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
    // `our-toddlers-journey` is the checkout directory, not the product.
    expect(field('name'), 'tiny_tapsters');
    for (final entry in docs.entries) {
      expect(
        entry.value,
        contains('Tiny Tapsters'),
        reason: '${entry.key} should name the app',
      );
      // The CHANGELOG records the rename from "Our Toddlers' Journey" in
      // v1.19.0 and must keep saying so; that history, plus the checkout
      // directory still being named after it, is exactly what misled a later
      // rewrite into renaming the app back.
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
