import 'dart:convert';

import 'f95.dart';
import 'host.dart';
import 'state.dart';
import 'thread.dart';

/// The source key droidtop stores a person's thread links under: the `id`
/// of this plugin's `library.updates` entry. Never change it: droidtop
/// moved every link made before F95 support left its core to this key.
const String sourceKey = 'f95zone';

/// F95zone's sign-in page, and the cookie XenForo sets once someone is signed in.
const String loginUrl = 'https://f95zone.to/login/';
const String signedInCookie = 'xf_user';

const String _stateFile = 'state.json';
const String _contextFile = 'context.json';

/// The plugin's answers to droidtop's calls, by extension point and op
/// (droidtop docs/plugin-api.md 3: A2 sources, A3 metadata, A6 updates, C
/// settings), and the jobs droidtop starts on it. Everything it shows is a
/// view document droidtop draws; it draws nothing itself.
class F95Plugin {
  F95Plugin(this.host, {F95Client? client, int Function()? now})
      : services = Services(host),
        _client = client,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Host host;
  final Services services;
  final F95Client? _client;
  final int Function() _now;

  F95Client get client => _client ?? F95Client(services);

  Future<Map<String, dynamic>> handle(Map<String, dynamic> envelope) async {
    final point = envelope['point'] as String?;
    final op = envelope['op'] as String?;
    final args = (envelope['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    try {
      switch ('$point $op') {
        case 'library.updates resolve':
          return _resolve(args);
        case 'library.updates check':
          return await _check(args);
        case 'library.updates match':
          return await _match(args);
        case 'library.sources form':
          return Reply.ok(searchForm());
        case 'library.sources search':
          return await _search(args);
        case 'library.sources detail':
          return await _detail(args);
        case 'library.metadata match':
          return await _metadataMatch(args);
        case 'library.metadata fetch':
          return await _metadataFetch(args);
        case 'ui.settings view':
          return Reply.ok(await _settings());
        case 'ui.settings signOut':
          await services.signOut();
          return Reply.ok({'message': 'Signed out of F95zone', 'view': await _settings()});
      }
      return Reply.error('UNSUPPORTED', 'not offered: $point $op');
    } on HostError catch (e) {
      return Reply.error(e.code == 'PERMISSION_DENIED' ? 'PERMISSION_DENIED' : 'FAILED', e.message);
    } on FormatException catch (e) {
      return Reply.error('FAILED', 'F95zone answered with something unexpected (${e.message})');
    }
  }

  /// A job droidtop started: [op] on [point]. The result is `{ok, error?, values?}`; values are strings.
  Future<Map<String, dynamic>> job(String point, String op, Map<String, dynamic> args) async {
    try {
      switch ('$point $op') {
        case 'ui.settings signIn':
          final ok = await services.signIn(loginUrl, doneCookie: signedInCookie);
          if (ok) await syncWatched();
          return _done(ok ? 'Signed in to F95zone' : 'Not signed in');
        case 'ui.settings syncWatched':
          return _done(await syncWatched());
        case 'library.sources acquire':
          return await _acquire(args);
      }
      return {'ok': false, 'error': 'not offered: $point $op'};
    } on HostError catch (e) {
      return {'ok': false, 'error': e.message};
    } on FormatException {
      return {'ok': false, 'error': 'F95zone answered with something unexpected'};
    }
  }

  Map<String, dynamic> _done(String message, [Map<String, String> more = const {}]) =>
      {'ok': true, 'values': {'message': message, ...more}};

  // ------------------------------------------------------------ updates (A6)

  /// A person's pasted link or number, read without asking the site.
  Map<String, dynamic> _resolve(Map<String, dynamic> args) {
    final thread = F95Thread.parse(args['text'] as String? ?? '');
    if (thread == null) return Reply.ok();
    return Reply.ok({
      'found': {'id': '$thread', 'url': F95Thread.url(thread)},
    });
  }

  /// droidtop's update round for the threads people linked: a fast check of
  /// all, a full check only of the ones whose stamp moved (F95Checker's own
  /// way), and one notification for new versions found.
  Future<Map<String, dynamic>> _check(Map<String, dynamic> args) async {
    final ids = ((args['ids'] as List?) ?? const []).map((e) => int.tryParse('$e')).whereType<int>().toSet().toList();
    final state = PluginState.fromJson(await services.readJson(_stateFile));
    final f95 = client;
    final stamps = await f95.fastCheck(ids);
    final answers = <Map<String, dynamic>>[];
    final news = <String>[];
    for (final id in ids) {
      final last = state.checks[id];
      final previous = last?.version;
      final stamp = stamps[id];
      if (stamp == null) {
        answers.add({'id': '$id', 'gone': true});
        continue;
      }
      var check = last ?? ThreadCheck(id: id);
      if (last == null || last.version == null || stamp > last.stamp) {
        final detail = await f95.full(id, stamp: stamp);
        if (detail == null) {
          answers.add({'id': '$id', 'gone': true});
          continue;
        }
        check
          ..stamp = stamp
          ..version = detail.version
          ..title = detail.name;
      }
      state.checks[id] = check;
      final version = check.version;
      if (version != null && previous != null && version != previous && check.notified != version) {
        news.add('${check.title ?? 'Thread $id'}: $version');
        check.notified = version;
      }
      answers.add({'id': '$id', 'version': version, 'url': threadUrl(id)});
    }
    await services.writeJson(_stateFile, state.toJson());
    if (news.isNotEmpty) {
      await services.notify(
        news.length == 1 ? 'New version on F95zone' : '${news.length} new versions on F95zone',
        news.take(8).join('\n'),
      );
    }
    return Reply.ok({'answers': answers});
  }

  /// Threads that may be the game called `title`: the person's own watched
  /// threads with that name first, then F95zone's search.
  Future<Map<String, dynamic>> _match(Map<String, dynamic> args) async {
    final title = args['title'] as String? ?? '';
    final key = nameKey(title);
    final context = Context.fromJson(await services.readJson(_contextFile));
    final candidates = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final w in context.active) {
      if (key.isNotEmpty && nameKey(w.name) == key && seen.add(w.id)) {
        candidates.add({
          'id': '${w.id}',
          'title': w.name,
          if (w.version != null) 'version': w.version,
          'url': threadUrl(w.id),
          'note': w.installed == null ? 'On your watch list' : 'On your watch list, ${w.installed} installed',
        });
      }
    }
    for (final t in await client.search(title, rows: 15)) {
      if (!seen.add(t.id)) continue;
      final watched = context.watched[t.id]?.watched == true;
      candidates.add({
        'id': '${t.id}',
        'title': t.title,
        if (t.version != null) 'version': t.version,
        'url': threadUrl(t.id),
        'note': [if (t.creator.isNotEmpty) 'by ${t.creator}', if (watched) 'on your watch list'].join(', '),
      });
    }
    return Reply.ok({'candidates': candidates.take(20).toList()});
  }

  // ------------------------------------------------------------ sources (A2)

  Future<Map<String, dynamic>> _search(Map<String, dynamic> args) async {
    final values = (args['values'] as Map?)?.cast<String, dynamic>() ?? const {};
    final query = (args['query'] as String?) ?? values['query'] as String? ?? '';
    if (sanitizeQuery(query).isEmpty) return Reply.ok({'results': <Object>[]});
    final results = await client.search(query);
    return Reply.ok({'results': results.map(searchResult).toList()});
  }

  Future<Map<String, dynamic>> _detail(Map<String, dynamic> args) async {
    final id = int.tryParse('${(args['ref'] as Map?)?['id'] ?? ''}');
    if (id == null) return Reply.error('INVALID_ARGS', 'Missing thread');
    final detail = await client.full(id);
    if (detail == null) return Reply.error('NOT_FOUND', 'That thread is private, moved or deleted');
    return Reply.ok(detailView(detail, signedIn: await services.signedIn()));
  }

  /// The person's Download: the thread page (signed in, links are for
  /// members) gives the chosen mirror's link, droidtop's web view opens it
  /// with the session, and the file the page starts is handed back as the
  /// acquire reply's download, which droidtop runs in its Downloads place.
  Future<Map<String, dynamic>> _acquire(Map<String, dynamic> args) async {
    final id = int.tryParse('${(args['ref'] as Map?)?['id'] ?? ''}');
    if (id == null) return {'ok': false, 'error': 'Missing thread'};
    if (!await services.signedIn()) {
      return {'ok': false, 'error': "F95zone shows download links only to members: sign in on the plugin's Settings page first"};
    }
    final detail = await client.full(id);
    if (detail == null) return {'ok': false, 'error': 'That thread is private, moved or deleted'};
    final values = (args['values'] as Map?)?.cast<String, dynamic>() ?? const {};
    final index = int.tryParse('${values['mirror'] ?? ''}') ?? 0;
    if (index < 0 || index >= detail.mirrors.length) return {'ok': false, 'error': 'Choose where to download from first'};
    final mirror = detail.mirrors[index];
    final page = await services.http(detail.url, session: true);
    final link = resolveMirror(page.body, mirror.selector);
    if (link == null) {
      return {'ok': false, 'error': 'The thread page has no ${mirror.label} link now; try another mirror'};
    }
    final download = await services.openInSession(link);
    if (download == null) return {'ok': false, 'error': 'No download was started'};
    return _done('Downloading ${detail.name}', {'download': jsonEncode(download)});
  }

  // ----------------------------------------------------------- metadata (A3)

  Future<Map<String, dynamic>> _metadataMatch(Map<String, dynamic> args) async {
    final title = args['title'] as String? ?? '';
    final key = nameKey(title);
    if (key.isEmpty) return Reply.ok({'candidates': <Object>[]});
    final found = (await client.search(title, rows: 10)).where((t) => nameKey(t.title) == key).toList();
    return Reply.ok({
      'candidates': [
        for (final t in found) {'ids': {'thread': '${t.id}'}, 'confidence': found.length == 1 ? 0.9 : 0.6},
      ],
    });
  }

  Future<Map<String, dynamic>> _metadataFetch(Map<String, dynamic> args) async {
    final id = int.tryParse('${(args['ids'] as Map?)?['thread'] ?? ''}');
    if (id == null) return Reply.error('INVALID_ARGS', 'Missing thread');
    final detail = await client.full(id);
    if (detail == null) return Reply.error('NOT_FOUND', 'That thread is private, moved or deleted');
    return Reply.ok({
      if (detail.description != null) 'description': detail.description,
      if (detail.developer != null) 'developer': detail.developer,
      if (detail.engine != null) 'genre': detail.engine,
      if (detail.score != null && detail.score! > 0) 'rating': (detail.score! / 5).clamp(0.0, 1.0),
    });
  }

  // ----------------------------------------------------------- settings (C)

  Future<Map<String, dynamic>> _settings() async {
    final signedIn = await services.signedIn();
    final context = Context.fromJson(await services.readJson(_contextFile));
    return settingsView(signedIn: signedIn, watched: context.active.length, syncedAt: context.siteSyncedAt);
  }

  /// Reads the watch list from F95zone, sends it what was changed here, and
  /// keeps the result as the plugin's context (docs/CONTEXT.md).
  Future<String> syncWatched() async {
    if (!await services.signedIn()) return 'Sign in to F95zone first';
    final context = Context.fromJson(await services.readJson(_contextFile));
    final site = <int, String>{};
    String? csrf;
    for (var page = 1; page <= 50; page++) {
      final answer = await services.http('https://f95zone.to/watched/threads?page=$page', session: true);
      if (answer.status != 200) break;
      csrf ??= csrfToken(answer.body);
      final found = watchedThreads(answer.body);
      site.addAll(found);
      if (found.isEmpty || !answer.body.contains('pageNav-jump--next')) break;
    }
    final pending = context.pendingForSite(site);
    var sent = 0;
    for (final change in pending.entries) {
      if (csrf == null) break;
      final answer = await services.http(
        'https://f95zone.to/threads/${change.key}/watch',
        method: 'POST',
        session: true,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: '_xfToken=${Uri.encodeQueryComponent(csrf)}&_xfResponseType=json&_xfWithData=1${change.value ? '' : '&stop=1'}',
      );
      if (answer.status == 200) {
        sent++;
        if (change.value) {
          site[change.key] = context.watched[change.key]?.name ?? '';
        } else {
          site.remove(change.key);
        }
      }
    }
    context.mergeSite(site, _now());
    await services.writeJson(_contextFile, context.toJson());
    return 'Watch list: ${context.active.length} threads${sent > 0 ? ', $sent changes sent to F95zone' : ''}';
  }
}

/// XenForo's CSRF token, which every form post carries (`data-csrf` on the page's root element).
String? csrfToken(String html) => RegExp(r'''data-csrf\s*=\s*["']([^"']+)["']''').firstMatch(html)?.group(1);

/// The threads a watched-threads page lists: thread id -> title, from the
/// list's primary thread links (`data-tp-primary="on"`).
Map<int, String> watchedThreads(String html) {
  final out = <int, String>{};
  final link = RegExp(r'<a\s([^>]*data-tp-primary\s*=\s*"on"[^>]*)>(.*?)</a>', caseSensitive: false, dotAll: true);
  for (final m in link.allMatches(html)) {
    final href = RegExp(r'''href\s*=\s*["']([^"']+)["']''').firstMatch(m.group(1)!)?.group(1) ?? '';
    final id = F95Thread.parse(href.startsWith('/') ? 'f95zone.to$href' : href);
    if (id == null) continue;
    out[id] = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  return out;
}

// --------------------------------------------------------------- views

Map<String, dynamic> _view(String title, List<Map<String, dynamic>> items, {String? subtitle}) => {
      'view': 1,
      'title': title,
      'subtitle': ?subtitle,
      'sections': [
        {'id': 'main', 'items': items},
      ],
    };

/// `library.sources` `form`: one search field.
Map<String, dynamic> searchForm() => _view('Search F95zone', [
      {'type': 'text', 'id': 'query', 'title': 'Search', 'value': ''},
    ]);

/// One `library.sources` `search` result; `ref` is only the thread id.
Map<String, dynamic> searchResult(ThreadSummary t) => {
      'id': '${t.id}',
      'title': t.title,
      'subtitle': t.creator,
      'columns': [?t.version],
      'ref': {'id': '${t.id}'},
    };

/// `library.sources` `detail`: what the thread is, a picker over its
/// mirrors, and the one Download job.
Map<String, dynamic> detailView(ThreadDetail d, {required bool signedIn}) {
  final options = [
    for (var i = 0; i < d.mirrors.length; i++) {'value': '$i', 'label': '${d.mirrors[i].section} · ${d.mirrors[i].label}'},
  ];
  return _view(d.name, [
    if (d.version != null) {'type': 'info', 'id': 'version', 'title': 'Version', 'value': d.version},
    if (d.developer != null) {'type': 'info', 'id': 'developer', 'title': 'Developer', 'value': d.developer},
    if (d.engine != null) {'type': 'info', 'id': 'engine', 'title': 'Engine', 'value': d.engine},
    if (d.status != null) {'type': 'info', 'id': 'status', 'title': 'Status', 'value': d.status},
    if (d.description != null)
      {'type': 'info', 'id': 'about', 'title': 'About', 'subtitle': d.description!.length > 600 ? '${d.description!.substring(0, 600)}…' : d.description},
    if (!signedIn)
      {
        'type': 'info',
        'id': 'signin',
        'title': 'Sign in to download',
        'subtitle': "F95zone shows download links only to members. Sign in on this plugin's Settings page.",
      }
    else if (options.isEmpty)
      {'type': 'info', 'id': 'none', 'title': 'No downloads listed', 'subtitle': 'The thread lists no download mirrors.'}
    else ...[
      {'type': 'choice', 'id': 'mirror', 'title': 'Download from', 'options': options, 'value': '0'},
      {
        'type': 'button',
        'id': 'acquire',
        'title': 'Download',
        'action': {
          'kind': 'job',
          'op': 'acquire',
          'title': 'Download ${d.name}',
          'args': {
            'ref': {'id': '${d.id}'},
          },
        },
      },
    ],
  ]);
}

/// `ui.settings` `view`: the F95zone session and the watch list.
Map<String, dynamic> settingsView({required bool signedIn, required int watched, required int syncedAt}) => _view('F95zone', [
      {
        'type': 'info',
        'id': 'account',
        'title': 'F95zone account',
        'value': signedIn ? 'Signed in' : 'Not signed in',
        'subtitle': 'You sign in on F95zone\'s own page in droidtop\'s browser view; this plugin never sees your password.',
      },
      if (signedIn) ...[
        {
          'type': 'button',
          'id': 'sync',
          'title': 'Sync the watch list now',
          'subtitle': '$watched watched threads${syncedAt > 0 ? '' : ', never synced'}',
          'action': {'kind': 'job', 'op': 'syncWatched', 'title': 'Sync the F95zone watch list'},
        },
        {
          'type': 'button',
          'id': 'signout',
          'title': 'Sign out',
          'action': {'kind': 'call', 'op': 'signOut'},
        },
      ] else
        {
          'type': 'button',
          'id': 'signin',
          'title': 'Sign in to F95zone',
          'action': {'kind': 'job', 'op': 'signIn', 'title': 'Sign in to F95zone'},
        },
    ]);
