import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppLanguage {
  english('en-US'),
  indonesian('id-ID');

  const AppLanguage(this.localeId);

  /// Used for speech recognition and the text-to-speech voice.
  final String localeId;

  String get flag => this == AppLanguage.english ? '🇬🇧' : '🇮🇩';
}

/// The chosen language, and the one thing this app remembers between launches.
///
/// English is the default. A language that reset on every launch would be
/// worse than no switch at all — an Indonesian family would re-pick it every
/// single time — so this is the one setting worth storing. It is stored
/// through a tiny platform channel rather than a package: one string, no
/// dependency, and nothing else is written to the device.
class AppLanguageService {
  AppLanguageService._();

  static final AppLanguageService instance = AppLanguageService._();

  static const _channel = MethodChannel('com.inkpebble.tiny_tapsters/prefs');
  static const _key = 'language';

  /// Everything rebuilds off this, so a change repaints the whole app.
  final ValueNotifier<AppLanguage> current = ValueNotifier(AppLanguage.english);

  /// Reads the stored choice. Called once, before the app builds.
  Future<void> load() async {
    try {
      final stored = await _channel.invokeMethod<String>('get', {'key': _key});
      if (stored == AppLanguage.indonesian.name) {
        current.value = AppLanguage.indonesian;
      }
    } catch (e) {
      // No stored preference, or no platform: English it is.
      debugPrint('Language preference unavailable: $e');
    }
  }

  Future<void> set(AppLanguage language) async {
    if (current.value == language) return;
    current.value = language;
    try {
      await _channel.invokeMethod<void>('set', {
        'key': _key,
        'value': language.name,
      });
    } catch (e) {
      // Losing the preference is survivable; failing to switch is not.
      debugPrint('Could not store language preference: $e');
    }
  }

  void toggle() => set(
    current.value == AppLanguage.english
        ? AppLanguage.indonesian
        : AppLanguage.english,
  );
}

/// The current language's words.
///
/// Read as a plain global rather than through an `InheritedWidget`: the whole
/// app is rebuilt when the language changes, so there is nothing to look up.
AppStrings get strings => AppStrings(AppLanguageService.instance.current.value);

/// Every sentence the app shows, in both languages.
///
/// Deliberately getters on a class rather than a map of keys: a missing
/// translation is then a compile error instead of a blank label discovered by
/// a child. No code generation, no `.arb` files — 60-odd sentences do not
/// justify the machinery.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  String _pick(String en, String id) =>
      language == AppLanguage.english ? en : id;

  // --- home ---------------------------------------------------------------
  String get appTagline =>
      _pick('Fun games for little learners', 'Permainan seru untuk si kecil');
  String get talkToPollie => _pick('Talk to Pollie', 'Ngobrol dengan Pollie');
  String get tapToTalk => _pick('Tap to talk! 💬', 'Tekan untuk ngobrol! 💬');
  String get pickALevel => _pick('Pick a level!', 'Pilih tingkatan!');

  // --- levels -------------------------------------------------------------
  String get easy => _pick('Easy', 'Mudah');
  String get medium => _pick('Medium', 'Sedang');
  String get big => _pick('Big', 'Sulit');

  String animals(int n) => _pick('$n animals', '$n hewan');
  String pieces(int n) => _pick('$n pieces', '$n kepingan');
  String pairs(int n) => _pick('$n pairs', '$n pasang');
  String bubbles(int n) => _pick('$n bubbles', '$n balon');
  String catchTimes(int n) => _pick('Catch $n', 'Tangkap $n');
  String choices(int n) => _pick('$n to choose from', '$n pilihan');
  String countTo(int n) => _pick('Count to $n', 'Berhitung sampai $n');

  // --- game names and subtitles -------------------------------------------
  String get jigsaw => _pick('Jigsaw Puzzle', 'Susun Gambar');
  String get jigsawSubtitle =>
      _pick('Put the picture back together!', 'Susun kembali gambarnya!');

  String get animalFood => _pick('Animal Food', 'Beri Makan Hewan');
  String get animalFoodSubtitle =>
      _pick('Feed each animal its food!', 'Beri setiap hewan makanannya!');
  String get animalFoodSubtitleLong => _pick(
    'Feed each animal its favorite food!',
    'Beri setiap hewan makanan kesukaannya!',
  );

  String get memory => _pick('Memory Match', 'Cocokkan Kartu');
  String get memorySubtitle => _pick(
    'Flip the cards and find the pairs!',
    'Balik kartu, cari pasangan!',
  );

  String get bubblePop => _pick('Bubble Pop', 'Pecahkan Balon');
  String get bubblePopSubtitle =>
      _pick('Catch the right animal!', 'Tangkap hewan yang benar!');
  String get bubblePopGoal => _pick(
    'Only pop the animal at the top!',
    'Pecahkan hewan yang di atas saja!',
  );

  String get findIt => _pick('Find It!', 'Cari Hewan Ini!');
  String get findItSubtitle =>
      _pick('Find the animal that matches!', 'Cari hewan yang sama!');

  String get whichAnimal => _pick('Which Animal?', 'Tebak Suara Hewan');
  String get whichAnimalSubtitle =>
      _pick('Listen and find the animal!', 'Dengarkan dan cari hewannya!');
  String get whichAnimalGoal => _pick(
    'Listen, then tap who made that sound!',
    'Dengarkan, lalu tekan siapa yang bersuara!',
  );

  String get countAnimals => _pick('Count the Animals!', 'Hitung Hewannya!');
  String get countAnimalsSubtitle => _pick(
    'Count the animals and tap the number!',
    'Hitung hewannya lalu tekan angkanya!',
  );

  // --- in-game ------------------------------------------------------------
  String get feedTheAnimals => _pick('Feed the animals!', 'Beri makan hewan!');
  String get whoMadeThatSound =>
      _pick('Who made that sound?', 'Siapa yang bersuara?');
  String get playTheSound =>
      _pick('Play the animal sound', 'Putar suara hewannya');
  String get findThe => _pick('Find the ', 'Cari ');
  String pairsLeft(int n) => _pick('Pairs left: $n', 'Sisa pasangan: $n');
  String jigsawSize(int rows, int cols) =>
      _pick('Jigsaw $rows×$cols', 'Susun $rows×$cols');

  // --- endings ------------------------------------------------------------
  String get timesUp => _pick("Time's up!", 'Waktu habis!');
  String get tryAgain => _pick('Try again 🔁', 'Coba lagi 🔁');
  String get playAgain => _pick('Play again 🔁', 'Main lagi 🔁');
  String get playAgainBubbles => _pick('Play again 🎈', 'Main lagi 🎈');
  String get newPuzzle => _pick('New puzzle 🧩', 'Gambar baru 🧩');
  String get home => _pick('Home 🏠', 'Beranda 🏠');
  String get levels => _pick('Levels 🏠', 'Tingkatan 🏠');
  String get moreGames => _pick('More games 🏠', 'Permainan lain 🏠');

  String get wonJigsaw => _pick('Jigsaw done!', 'Gambar selesai!');
  String get wonAnimalFood => _pick('Yay! All fed!', 'Hore! Semua kenyang!');
  String get wonMemory => _pick('Yay! You did it!', 'Hore! Kamu berhasil!');
  String get wonBubbles => _pick('Pop-tastic!', 'Hebat sekali!');
  String get wonFindIt =>
      _pick('You found them all!', 'Kamu menemukan semuanya!');
  String get wonCount => _pick('Great counting!', 'Hitunganmu hebat!');
  String get wonSound => _pick('Great listening!', 'Pendengaranmu hebat!');

  // --- credits ------------------------------------------------------------
  String get soundCredits => _pick('Sound credits', 'Kredit suara');
  String get soundCreditsBody => _pick(
    'The animal sounds come from Wikimedia Commons. Thank you to '
        'everyone who recorded them and shared them freely.',
    'Suara hewan berasal dari Wikimedia Commons. Terima kasih kepada '
        'semua yang merekam dan membagikannya dengan cuma-cuma.',
  );

  // --- Pollie -------------------------------------------------------------
  String get pollieGreeting =>
      _pick("Hi kids! Let's talk with me 🦜", 'Hai! Ayo ngobrol denganku 🦜');
  String get pollieGreetingSpoken =>
      _pick("Hi kids! Let's talk with me!", 'Hai! Ayo ngobrol denganku!');
  String get saySomething => _pick('Say something…', 'Bilang sesuatu…');
  String get listening => _pick('Listening…', 'Mendengarkan…');
  String get sleeping => _pick('sleeping… 😴', 'tidur… 😴');
  String get awake => _pick('awake! 😊', 'bangun! 😊');
  String get listeningStatus => _pick('listening… 👂', 'mendengarkan… 👂');
  String get thinking => _pick('thinking… 🤔', 'berpikir… 🤔');
  String get speaking => _pick('speaking… 🗣️', 'berbicara… 🗣️');
  String get wakingUp => _pick('waking up…', 'sedang bangun…');

  String get chipStory => _pick('Tell me a story! 🐰', 'Ceritakan dongeng! 🐰');
  String get chipSong => _pick('Sing a song! 🎵', 'Nyanyikan lagu! 🎵');
  String get chipCow =>
      _pick('What does a cow say? 🐮', 'Bagaimana bunyi sapi? 🐮');
  String get chipFact => _pick('Fun fact! 🦕', 'Fakta seru! 🦕');
  String get chipLove => _pick('I love you! ❤️', 'Aku sayang kamu! ❤️');
  String get chipHow => _pick('How are you? 😊', 'Apa kabar? 😊');

  String get pollieLost => _pick(
    'Oops, I got lost for a moment! 😅 Can you ask me again?',
    'Aduh, aku bingung sebentar! 😅 Coba tanya lagi ya?',
  );
  String get pollieSayAgain => _pick(
    "Hmm, I didn't think of anything to say! 😊 Ask me again?",
    'Hmm, aku tidak kepikiran jawabannya! 😊 Tanya lagi ya?',
  );
  String get pollieBreath => _pick(
    'Phew! Let me catch my breath for a moment, then ask me again! 😊',
    'Fiuh! Aku istirahat sebentar, lalu tanya lagi ya! 😊',
  );
  String pollieOutOfWords(String reset) => _pick(
    "Pollie is all out of words for today! He'll be back $reset 😴",
    'Kata-kata Pollie habis untuk hari ini! Dia kembali $reset 😴',
  );
  String get pollieAsleep => _pick(
    "Zzz… I can't reach the internet yet. Tap me to try waking up again! 😴",
    'Zzz… aku belum bisa terhubung ke internet. Tekan aku untuk membangunkan! 😴',
  );
  String get pollieNoKey => _pick(
    "Hi! I'm Pollie! 🦜 I can't talk yet — ask a grown-up to give me my "
        'magic key! 🔑',
    'Hai! Aku Pollie! 🦜 Aku belum bisa bicara — minta orang dewasa memberiku '
        'kunci ajaib! 🔑',
  );
  String get pollieNoMic => _pick(
    "I can't hear you! 🎤 Ask a grown-up to allow the microphone, then tap "
        'the mic again.',
    'Aku tidak bisa mendengarmu! 🎤 Minta orang dewasa mengizinkan mikrofon, '
        'lalu tekan mikrofonnya lagi.',
  );
  String get pollieNotNice => _pick(
    "Hmm, that's not a nice thing to say! Let's talk about something fun "
        'instead. 😊',
    'Hmm, itu kurang sopan! Ayo bicarakan hal yang seru saja. 😊',
  );
  String get pollieDidntCatch => _pick(
    "Oops, I didn't catch that! 😅 Tap the mic and try again?",
    'Aduh, aku tidak menangkapnya! 😅 Tekan mikrofon dan coba lagi?',
  );
}
