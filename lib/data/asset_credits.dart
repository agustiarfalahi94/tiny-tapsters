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
    title:
        'Vervet Monkey (Chlorocebus pygerythrus) (W CERCOPITHECUS AETHIOPS R2 C2).ogg',
    author: 'Wikimedia Commons contributor',
    licence: 'CC BY 4.0',
    source:
        'https://commons.wikimedia.org/wiki/File:Vervet_Monkey_(Chlorocebus_pygerythrus)_(W_CERCOPITHECUS_AETHIOPS_R2_C2).ogg',
  ),
  AssetCredit(
    emoji: '🐘',
    title: 'Elephant voice - trumpeting.ogg',
    author: 'Wikimedia Commons contributor',
    licence: 'CC0',
    source:
        'https://commons.wikimedia.org/wiki/File:Elephant_voice_-_trumpeting.ogg',
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
