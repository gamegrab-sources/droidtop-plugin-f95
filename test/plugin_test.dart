import 'package:droidtop_plugin_f95/src/host.dart';
import 'package:droidtop_plugin_f95/src/plugin.dart';
import 'package:droidtop_plugin_f95/src/thread.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoHost implements Host {
  @override
  Future<Map<String, dynamic>> call(String api, int version, String op, Map<String, dynamic> args) =>
      throw StateError('no host call expected');
}

void main() {
  test('a thread is read from the link a browser shows, the short form and the bare number', () {
    expect(F95Thread.parse('https://f95zone.to/threads/star-harbor-v0-9-5-somedev.12345/'), 12345);
    expect(F95Thread.parse('https://f95zone.to/threads/star-harbor-v0.9.5.12345/post-6789'), 12345);
    expect(F95Thread.parse('f95zone.to/threads/12345'), 12345);
    expect(F95Thread.parse('  12345 '), 12345);
    expect(F95Thread.parse('https://example.com/threads/12345'), isNull);
    expect(F95Thread.parse('star harbor'), isNull);
    expect(F95Thread.parse('0'), isNull);
  });

  test('resolve answers a pasted link with the thread, and nothing for other text', () async {
    final plugin = F95Plugin(_NoHost());
    final found = await plugin.handle({
      'point': 'library.updates',
      'op': 'resolve',
      'args': {'source': sourceKey, 'text': 'https://f95zone.to/threads/x.42/'},
    });
    expect(found['ok'], isTrue);
    expect((found['data'] as Map)['found'], {'id': '42', 'url': 'https://f95zone.to/threads/42/'});
    final none = await plugin.handle({
      'point': 'library.updates',
      'op': 'resolve',
      'args': {'source': sourceKey, 'text': 'not a link'},
    });
    expect(none, {'ok': true, 'data': <String, dynamic>{}});
  });

  test('an op that is not built yet says so with droidtop\'s own error code', () async {
    final reply = await F95Plugin(_NoHost()).handle({'point': 'library.updates', 'op': 'check', 'args': {}});
    expect(reply['ok'], isFalse);
    expect((reply['error'] as Map)['code'], 'UNSUPPORTED');
  });
}
