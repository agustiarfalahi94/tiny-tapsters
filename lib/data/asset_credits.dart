/// Attribution for every animal call in "Which Animal?".
///
/// Nothing here obliges attribution: the Pixabay Content License does not
/// require it and CC0 obliges nothing. `CreditsScreen` shows them anyway,
/// because provenance is what keeps the licence claim checkable a year from
/// now — and a half-filled credits page invites the question of what is
/// missing.
///
/// Keep in step with `ASSET_CREDITS.md`, which covers the music and effects
/// too. A test checks there is an entry here for every bundled call.
class AssetCredit {
  const AssetCredit({
    required this.emoji,
    required this.title,
    required this.author,
    required this.licence,
    required this.source,
  });

  final String emoji;
  final String title;
  final String author;
  final String licence;
  final String source;
}

const kAnimalSoundCredits = <AssetCredit>[
  AssetCredit(
    emoji: '🐱',
    title: 'cat sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐶',
    title: 'Ladrido perro.ogg',
    author: 'Wikimedia Commons contributor',
    licence: 'CC0',
    source: 'https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg',
  ),
  AssetCredit(
    emoji: '🐮',
    title: 'cow sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐴',
    title: 'horse sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐷',
    title: 'pig sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐔',
    title: 'chicken sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐦',
    title: 'bird sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐭',
    title: 'mouse sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐸',
    title: 'frog sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🦁',
    title: 'lion sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐯',
    title: 'tiger sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐵',
    title: 'monkey sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐻',
    title: 'bear sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐘',
    title: 'elephant sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
  AssetCredit(
    emoji: '🐧',
    title: 'penguin sound effect',
    author: 'Pixabay contributor',
    licence: 'Pixabay Content License',
    source: 'https://pixabay.com/sound-effects/',
  ),
];
