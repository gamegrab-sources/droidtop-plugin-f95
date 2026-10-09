import 'dart:convert';

import 'package:droidtop_plugin_f95/src/f95.dart';
import 'package:droidtop_plugin_f95/src/host.dart';
import 'package:droidtop_plugin_f95/src/plugin.dart';
import 'package:droidtop_plugin_f95/src/state.dart';
import 'package:droidtop_plugin_f95/src/thread.dart';
import 'package:flutter_test/flutter_test.dart';

/// droidtop's side in memory: canned answers per address, the plugin's data files, the session, notifications.
class FakeHost implements Host {
  final Map<String, List<Object>> web = {}; // url -> [status, body]
  final Map<String, List<int>> files = {};
  final List<String> requested = [];
  final List<List<String>> notified = [];
  bool signedIn = false;
  Map<String, dynamic>? captured;

  @override
  Future<Map<String, dynamic>> call(String api, int version, String op, Map<String, dynamic> args) async {
    switch ('$api $op') {
      case 'net http':
      case 'web.session fetch':
        final url = args['url'] as String;
        requested.add('${args['method'] ?? 'GET'} $url');
        final answer = web[url] ?? [404, ''];
        return Reply.ok({'status': answer[0], 'url': url, 'body': answer[1]});
      case 'data read':
        final bytes = files[args['name']];
        if (bytes == null) return Reply.error('NOT_FOUND', 'no file');
        final offset = args['offset'] as int;
        final end = (offset + (args['length'] as int)).clamp(0, bytes.length);
        return Reply.ok({'base64': base64Encode(bytes.sublist(offset, end)), 'size': bytes.length, 'eof': end >= bytes.length});
      case 'data write':
        final chunk = base64Decode(args['base64'] as String);
        final name = args['name'] as String;
        files[name] = args['append'] == true ? [...?files[name], ...chunk] : chunk;
        return Reply.ok({'size': files[name]!.length});
      case 'notify post':
        notified.add([args['title'] as String, args['text'] as String]);
        return Reply.ok({'posted': true});
      case 'web.session status':
        return Reply.ok({'signedIn': signedIn});
      case 'web.session open_in_session':
        return Reply.ok({'captured': captured != null, if (captured != null) 'download': captured});
    }
    return Reply.error('UNSUPPORTED', '$api $op');
  }
}

F95Plugin pluginOn(FakeHost host) => F95Plugin(host, client: F95Client(Services(host), pause: (_) async {}), now: () => 5000);

Map<String, dynamic> data(Map<String, dynamic> reply) {
  expect(reply['ok'], isTrue, reason: '$reply');
  return (reply['data'] as Map).cast<String, dynamic>();
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
    final plugin = pluginOn(FakeHost());
    final found = data(await plugin.handle({
      'point': 'library.updates',
      'op': 'resolve',
      'args': {'source': sourceKey, 'text': 'https://f95zone.to/threads/x.42/'},
    }));
    expect(found['found'], {'id': '42', 'url': 'https://f95zone.to/threads/42/'});
    expect(data(await plugin.handle({'point': 'library.updates', 'op': 'resolve', 'args': {'text': 'not a link'}})), isEmpty);
  });

  test('a search is cut the way F95Checker cuts it', () {
    expect(sanitizeQuery("The Witch's Curse: Part 2 (v0.3)"), 'Witch Curse Part 2 v0 3');
    expect(sanitizeQuery('a an the'), '');
    expect(sanitizeQuery('Supercalifragilistic expialidocious game'), 'Supercalifragilistic expialido');
  });

  // The shape of api.f95checker.dev/full/{id} as it answered on 2026-10-09 (thread 93340), trimmed.
  final fullAnswer = {
    'type': '14',
    'name': 'Eternum',
    'version': 'v0.9.5 Public',
    'developer': 'Caribdis',
    'status': '1',
    'score': '4.8',
    'description': 'You are moving with your best friend to the city of Kredon.',
    'downloads': jsonEncode([
      [
        'Win/Linux',
        [
          ['AKIRABOX', "//a[starts-with(@href,'https://akirabox.com/')][1]"],
          ['DATANODES', "//a[starts-with(@href,'https://datanodes.to/')][1]"],
        ],
      ],
    ]),
    'image_url': 'https://attachments.f95zone.to/2023/10/3018543_f95zone_banner.png',
    'INDEX_ERROR': '',
  };

  test("a thread's details are read from F95Checker's index, engine included", () {
    final d = ThreadDetail.parse(93340, fullAnswer);
    expect(d.name, 'Eternum');
    expect(d.version, 'v0.9.5 Public');
    expect(d.engine, "Ren'Py");
    expect(d.status, 'In development');
    expect(d.mirrors.map((m) => m.label), ['AKIRABOX', 'DATANODES']);
    expect(versionOrNull('N/A'), isNull);
  });

  test("a mirror selector picks its link out of the thread page", () {
    const html = '<a href="https://datanodes.to/a">x</a> <a class="link" href="https://akirabox.com/one">1</a>'
        '<a href="https://akirabox.com/two">2</a>';
    expect(resolveMirror(html, "//a[starts-with(@href,'https://akirabox.com/')][1]"), 'https://akirabox.com/one');
    expect(resolveMirror(html, "//a[starts-with(@href,'https://akirabox.com/')][2]"), 'https://akirabox.com/two');
    expect(resolveMirror(html, "//a[starts-with(@href,'https://mega.nz/')][1]"), isNull);
    expect(resolveMirror(html, '//div[@id="x"]'), isNull);
  });

  test('a fast check reads stamps, and a refused batch is null', () {
    expect(parseFastCheck('{"93340":1791409117}', [93340, 1]), {93340: 1791409117});
    expect(parseFastCheck('"Invalid thread IDs"', [1]), isNull);
    expect(() => parseFastCheck('{"INDEX_ERROR":"busy"}', [1]), throwsA(isA<HostError>()));
  });

  test('a check asks for details only of changed threads and says a new version once', () async {
    final host = FakeHost();
    final plugin = pluginOn(host);
    host.web['https://api.f95checker.dev/fast?ids=93340'] = [200, '{"93340":100}'];
    host.web['https://api.f95checker.dev/full/93340?ts=100'] = [200, jsonEncode(fullAnswer)];
    final first = data(await plugin.handle({'point': 'library.updates', 'op': 'check', 'args': {'ids': ['93340']}}));
    expect(first['answers'], [
      {'id': '93340', 'version': 'v0.9.5 Public', 'url': 'https://f95zone.to/threads/93340/'},
    ]);
    expect(host.notified, isEmpty, reason: 'the first answer is not news');

    host.requested.clear();
    await plugin.handle({'point': 'library.updates', 'op': 'check', 'args': {'ids': ['93340']}});
    expect(host.requested, ['GET https://api.f95checker.dev/fast?ids=93340'], reason: 'an unchanged stamp needs no full check');

    host.web['https://api.f95checker.dev/fast?ids=93340'] = [200, '{"93340":200}'];
    host.web['https://api.f95checker.dev/full/93340?ts=200'] = [200, jsonEncode({...fullAnswer, 'version': 'v0.9.6 Public'})];
    await plugin.handle({'point': 'library.updates', 'op': 'check', 'args': {'ids': ['93340']}});
    expect(host.notified.single[1], 'Eternum: v0.9.6 Public');
    await plugin.handle({'point': 'library.updates', 'op': 'check', 'args': {'ids': ['93340']}});
    expect(host.notified.length, 1);
  });

  test('a thread the index does not know is gone', () async {
    final host = FakeHost();
    host.web['https://api.f95checker.dev/fast?ids=7'] = [200, '{}'];
    final reply = data(await pluginOn(host).handle({'point': 'library.updates', 'op': 'check', 'args': {'ids': ['7']}}));
    expect(reply['answers'], [
      {'id': '7', 'gone': true},
    ]);
  });

  test('matches offer the watch list first, then the search', () async {
    final host = FakeHost();
    final context = Context(watched: {93340: WatchedThread(id: 93340, name: 'Eternum', installed: 'v0.9.4', changedAt: 1)});
    host.files['context.json'] = utf8.encode(jsonEncode(context.toJson()));
    host.web[Uri.https('f95zone.to', '/sam/latest_alpha/latest_data.php', {
      'cmd': 'list', 'cat': 'games', 'page': '1', 'search': 'Eternum', 'sort': 'likes', 'rows': '15',
    }).toString()] = [
      200,
      jsonEncode({
        'status': 'ok',
        'msg': {
          'data': [
            {'thread_id': 93340, 'title': 'Eternum', 'creator': 'Caribdis', 'version': 'v0.9.5 Public'},
            {'thread_id': 5, 'title': 'Eternum Mod', 'creator': 'someone'},
          ],
        },
      }),
    ];
    final candidates = data(await pluginOn(host).handle({
      'point': 'library.updates',
      'op': 'match',
      'args': {'title': 'Eternum', 'versions': ['0.9.4']},
    }))['candidates'] as List;
    expect(candidates.map((c) => c['id']), ['93340', '5']);
    expect(candidates.first['note'], 'On your watch list, v0.9.4 installed');
  });

  test('the watch list merges with F95zone both ways', () {
    final context = Context(siteSyncedAt: 100, watched: {
      1: WatchedThread(id: 1, name: 'Kept', changedAt: 50),
      2: WatchedThread(id: 2, name: 'Unwatched on the site', changedAt: 50),
      3: WatchedThread(id: 3, name: 'Watched here since', changedAt: 150),
      4: WatchedThread(id: 4, name: 'Unwatched here since', changedAt: 150, watched: false),
    });
    final site = {1: 'Kept', 4: 'Unwatched here since', 9: 'New on the site'};
    expect(context.pendingForSite(site), {3: true, 4: false});
    site.remove(4); // sent
    site[3] = 'Watched here since'; // sent
    context.mergeSite(site, 200);
    expect(context.active.map((w) => w.id).toSet(), {1, 3, 9});
    expect(context.watched[2]!.watched, isFalse);
    expect(context.siteSyncedAt, 200);
  });

  test('watched threads and the form token are read from the page', () {
    // A minimal stand-in for XenForo's watched-threads list markup.
    const html = '<html data-csrf="123,abc"><div class="structItem"><a href="/threads/eternum.93340/" '
        'data-tp-primary="on" data-xf-init="preview-tooltip">Eternum</a></div>'
        '<a href="/threads/other.5/unread">not primary</a></html>';
    expect(watchedThreads(html), {93340: 'Eternum'});
    expect(csrfToken(html), '123,abc');
  });

  test('a download needs a session, and goes through droidtop\'s web view to the acquire reply', () async {
    final host = FakeHost();
    final plugin = pluginOn(host);
    host.web['https://api.f95checker.dev/full/93340?ts=0'] = [200, jsonEncode(fullAnswer)];
    final args = {
      'ref': {'id': '93340'},
      'values': {'mirror': '0'},
    };
    expect((await plugin.job('library.sources', 'acquire', args))['ok'], isFalse);
    host.signedIn = true;
    host.web['https://f95zone.to/threads/93340/'] = [200, '<a href="https://akirabox.com/f/1">AKIRABOX</a>'];
    host.captured = {'url': 'https://dl.akirabox.com/1', 'fileName': 'Eternum-0.9.5-pc.zip', 'session': 'w-1'};
    final result = await plugin.job('library.sources', 'acquire', args);
    expect(result['ok'], isTrue);
    expect(jsonDecode((result['values'] as Map)['download'] as String), host.captured);
  });

  test('an op that is not offered says so with droidtop\'s own error code', () async {
    final reply = await pluginOn(FakeHost()).handle({'point': 'library.artwork', 'op': 'list', 'args': {}});
    expect(reply['ok'], isFalse);
    expect((reply['error'] as Map)['code'], 'UNSUPPORTED');
  });
}
