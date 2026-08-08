/// Local content guard for the Pollie companion.
///
/// A defense-in-depth backstop on top of Gemini's own safety filters:
/// obviously adult/abusive words are caught here so they never reach Google
/// (user input) and never reach the child (model output).
class KidSafety {
  KidSafety._();

  static const _blocked = [
    // English — adult / sexual
    'fuck', 'shit', 'bitch', 'bastard', 'dick', 'cock', 'pussy', 'cunt',
    'whore', 'slut', 'asshole', 'tits', 'boobs', 'porn', 'penis', 'vagina',
    'dildo', 'orgasm', 'wank', 'blowjob', 'nude', 'sexy', 'sex', 'rape',
    'molest', 'nigger', 'faggot', 'retard',
    // English — harassment
    'stupid', 'idiot', 'moron',
    // Indonesian
    'kontol', 'memek', 'ngentot', 'jancok', 'bangsat', 'goblok', 'goblog',
    'tolol', 'kampang', 'bajingan', 'tai',
  ];

  /// True when [text] contains any blocked word (word-boundary matched, so
  /// "asshole" never trips on innocent words like "class").
  static bool containsBlocked(String text) {
    final lower = text.toLowerCase();
    for (final term in _blocked) {
      if (RegExp('\\b${RegExp.escape(term)}\\b').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }
}
