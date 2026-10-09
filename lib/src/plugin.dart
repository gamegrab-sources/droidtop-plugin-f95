import 'host.dart';
import 'thread.dart';

/// The source key droidtop stores a person's thread links under: the `id`
/// of this plugin's `library.updates` entry. Never change it: droidtop
/// moved every link made before F95 support left its core to this key.
const String sourceKey = 'f95zone';

/// The plugin's answers to droidtop's calls, by extension point and op.
class F95Plugin {
  F95Plugin(this.host);

  final Host host;

  Future<Map<String, dynamic>> handle(Map<String, dynamic> envelope) async {
    final point = envelope['point'] as String?;
    final op = envelope['op'] as String?;
    final args = (envelope['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (point == 'library.updates') {
      switch (op) {
        case 'resolve':
          return _resolve(args);
      }
    }
    return Reply.error('UNSUPPORTED', 'not built yet: $point $op');
  }

  /// A person's pasted link or number, read without asking the site.
  Map<String, dynamic> _resolve(Map<String, dynamic> args) {
    final thread = F95Thread.parse(args['text'] as String? ?? '');
    if (thread == null) return Reply.ok();
    return Reply.ok({
      'found': {'id': '$thread', 'url': F95Thread.url(thread)},
    });
  }
}
