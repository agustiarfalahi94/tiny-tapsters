/// Attribution for every animal call in "Which Animal?".
///
/// Some of these are CC BY, which obliges us to credit the author wherever
/// the work is used — that is what `CreditsScreen` is for. The CC0 and
/// public-domain entries oblige nothing and are listed anyway, because a
/// half-filled credits page invites the question of what is missing.
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
    title: 'Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN.wav',
    author: 'PantheraLeo1359531',
    licence: 'CC BY 4.0',
    source:
        'https://commons.wikimedia.org/wiki/File:Weibliche_Britisch_Kurzhaar_will_Futter_C1277_MIAUEN.wav',
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
    title: 'Cow, Moo, Snort at End',
    author: 'Nicholas A. Judy (The Designer\'s Choice)',
    licence: 'CC0',
    source: 'https://archive.org/details/designers-choice-complete',
  ),
  AssetCredit(
    emoji: '🐴',
    title: 'Wiehern.ogg',
    author: 'Wikimedia Commons contributor',
    licence: 'Public domain',
    source: 'https://commons.wikimedia.org/wiki/File:Wiehern.ogg',
  ),
  AssetCredit(
    emoji: '🐔',
    title: 'Coq qui chante (DenisChardonnet).wav',
    author: 'Wikimedia Commons contributor',
    licence: 'CC0',
    source:
        'https://commons.wikimedia.org/wiki/File:Coq_qui_chante_(DenisChardonnet).wav',
  ),
  AssetCredit(
    emoji: '🦁',
    title: 'Lionroar.wav',
    author: 'Jonathan Growcott, Alex Lobora, Andrew Markham, Charlotte E.',
    licence: 'CC BY 4.0',
    source: 'https://commons.wikimedia.org/wiki/File:Lionroar.wav',
  ),
  AssetCredit(
    emoji: '🐵',
    title: 'Pant-hoot call made by a male chimpanzee.ogg',
    author: 'Pawel Fedurek et al.',
    licence: 'CC BY 4.0',
    source:
        'https://commons.wikimedia.org/wiki/File:Pant-hoot_call_made_by_a_male_chimpanzee.ogg',
  ),
  AssetCredit(
    emoji: '🐘',
    title: 'Elephant Trumpet',
    author: 'Nicholas A. Judy (The Designer\'s Choice)',
    licence: 'CC0',
    source: 'https://archive.org/details/Designers-Choice-Collection-Animals',
  ),
  AssetCredit(
    emoji: '🐸',
    title: 'CouchsSpadefootToad SaguaroNP 20110705.ogg',
    author: 'Wikimedia Commons contributor',
    licence: 'Public domain',
    source:
        'https://commons.wikimedia.org/wiki/File:CouchsSpadefootToad_SaguaroNP_20110705.ogg',
  ),
];
