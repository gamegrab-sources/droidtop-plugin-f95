/// An F95zone thread, from whatever a person pastes: the thread's link as a
/// browser shows it (`https://f95zone.to/threads/<slug>.<id>/`), the short
/// form (`f95zone.to/threads/<id>`), or the bare number. Ported from
/// droidtop's former core `F95Thread` when F95 support moved into this
/// plugin (Droidtop/tracker#380).
class F95Thread {
  static final RegExp _link = RegExp(r'f95zone\.to/threads/(?:[^/?#\s]*\.)?(\d+)', caseSensitive: false);

  /// The thread id in [text], or null when it names none.
  static int? parse(String text) {
    final trimmed = text.trim();
    final id = int.tryParse(trimmed) ?? int.tryParse(_link.firstMatch(trimmed)?.group(1) ?? '');
    return (id != null && id > 0) ? id : null;
  }

  /// The thread's own page.
  static String url(int thread) => 'https://f95zone.to/threads/$thread/';
}
