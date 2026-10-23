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
        case 'library.updates record':
          return await _record(args);
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
        case 'ui.facets get':
          return Reply.ok(await _facets('${args['target'] ?? ''}'));
      }
      return Reply.error('UNSUPPORTED', 'not offered: $point $op');
    } on HostError catch (e) {
      return Reply.error(e.code == 'PERMISSION_DENIED' ? 'PERMISSION_DENIED' : 'FAILED', e.message);
    } on FormatException {
      return Reply.error('FAILED', unreadablePage);
    }
  }

  /// A job droidtop started: [op] on [point]. The result is `{ok, error?, values?}`; values are strings.
  Future<Map<String, dynamic>> job(String point, String op, Map<String, dynamic> args) async {
    try {
      switch ('$point $op') {
        case 'library.sources signIn':
          // A game page's Sign in: the job asks for the sign-in it needs, in droidtop's same web view and session.
          final ok = await services.signIn(loginUrl, doneCookie: signedInCookie);
          if (ok) await syncWatched();
          return _done(ok ? 'Signed in to F95zone' : 'Not signed in');
        case 'ui.facets syncWatched':
          return _done(await syncWatched());
        case 'library.sources acquire':
          return await _acquire(args);
        case 'library.updates download':
          return await _download(args);
      }
      return {'ok': false, 'error': 'not offered: $point $op'};
    } on HostError catch (e) {
      return {'ok': false, 'error': e.message};
    } on FormatException {
      return {'ok': false, 'error': unreadablePage};
    }
  }

  /// An event droidtop sent: after the person signed in to F95zone through droidtop, the account's name for its
  /// account row, and the watch list. The answer starts no job.
  Future<Map<String, dynamic>> onEvent(String event) async {
    if (event == 'web.session.signed_in') {
      try {
        await syncWatched();
      } on HostError {
        // The name and the list are read again at the next sync; the sign-in itself is kept.
      } on FormatException {
        // As above.
      }
    }
    return {'ok': true};
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

  /// `library.updates` `record`: the thread as droidtop's record page shows it (droidtop docs/plugin-api.md 3 A6;
  /// F95Checker's Overview, Changelog, Downloads and Info, as f95seeker draws them). Each download's `link` is the
  /// mirror's place and label, which `download` checks against the thread as it is then.
  Future<Map<String, dynamic>> _record(Map<String, dynamic> args) async {
    final id = int.tryParse('${args['id'] ?? ''}');
    if (id == null) return Reply.error('INVALID_ARGS', 'Missing thread');
    final detail = await client.full(id);
    if (detail == null) return Reply.error('NOT_FOUND', 'That thread is private, moved or deleted');
    // Each mirror's address, read once from the thread page now (links are for members), so droidtop keeps it with the
    // record and opens it itself in its web view; nothing is fetched again to download (droidtop Droidtop/tracker#599).
    Map<int, String> addresses = const {};
    if (detail.mirrors.isNotEmpty && await services.signedIn()) {
      try {
        final page = await services.http(detail.url, session: true);
        addresses = mirrorAddresses(detail, page.body);
      } on HostError {
        // The page could not be read: the record keeps the mirrors as tokens for the download job.
      }
    }
    // The record twice: as contract 3's item.page bundles, which droidtop draws through its guards, and as the
    // contract 2 record an older droidtop reads.
    return Reply.ok({
      'record': recordOf(detail, addresses: addresses),
      'items': [itemPageOf(detail, addresses: addresses)],
    });
  }

  /// `library.updates` `download`, a job: the mirror the person picked on droidtop's record page, opened the way the
  /// game page's Download is ([_acquire]). droidtop places the file as a new version folder of the linked game.
  Future<Map<String, dynamic>> _download(Map<String, dynamic> args) async {
    final id = int.tryParse('${args['id'] ?? ''}');
    if (id == null) return {'ok': false, 'error': 'Missing thread'};
    final detail = await client.full(id);
    if (detail == null) return {'ok': false, 'error': 'That thread is private, moved or deleted'};
    final index = mirrorFor(detail, '${args['link'] ?? ''}');
    if (index == null) return {'ok': false, 'error': 'The thread no longer lists that link; open the page again'};
    return _acquire({
      'ref': {'id': '$id'},
      'values': {'mirror': '$index'},
    });
  }

  /// The person's Download: the thread page (signed in, links are for
  /// members) gives the chosen mirror's link, droidtop's web view opens it
  /// with the session, and the file the page starts is handed back as the
  /// acquire reply's download, which droidtop runs in its Downloads place.
  Future<Map<String, dynamic>> _acquire(Map<String, dynamic> args) async {
    final id = int.tryParse('${(args['ref'] as Map?)?['id'] ?? ''}');
    if (id == null) return {'ok': false, 'error': 'Missing thread'};
    if (!await services.signedIn()) {
      return {'ok': false, 'error': 'Sign in to F95zone first.'};
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
    return _done('Downloading ${detail.name}', {
      'download': jsonEncode(download),
      // droidtop pins the placed game to this engine's player (plugin-api 1.6, engine hint).
      'engine': ?detail.engineId,
    });
  }

  // ----------------------------------------------------------- metadata (A3)

  Future<Map<String, dynamic>> _metadataMatch(Map<String, dynamic> args) async {
    // A game the person linked to its thread is that thread, no search needed.
    final linked = int.tryParse('${(args['sourceLinks'] as Map?)?[sourceKey] ?? ''}');
    if (linked != null) {
      return Reply.ok({
        'candidates': [
          {'ids': {'thread': '$linked'}, 'confidence': 1.0},
        ],
      });
    }
    // An unlinked game is searched by its title and by its folder's name, and only exact names count, as droidtop's
    // own sources match (droidtop docs/SPEC.md 7h, "A source's own match"). One thread is the game; several with the
    // same name tie, and droidtop asks the person to pick.
    final folder = (args['folder'] as Map?)?['name'] as String? ?? args['fileName'] as String? ?? '';
    final queries = <String, String>{};
    for (final query in [args['title'] as String? ?? '', folderTitle(folder)]) {
      final key = nameKey(query);
      if (key.isNotEmpty) queries.putIfAbsent(key, () => query);
    }
    final found = <int, String>{};
    for (final entry in queries.entries) {
      for (final t in await _scrapeSearch(entry.key, entry.value)) {
        if (nameKey(t.key) == entry.key) found.putIfAbsent(t.value, () => t.key);
      }
    }
    return Reply.ok({
      'candidates': [
        for (final t in found.entries) {'ids': {'thread': '${t.key}'}, 'confidence': found.length == 1 ? 0.95 : 0.6, 'title': t.value},
      ],
    });
  }

  Future<Map<String, dynamic>> _metadataFetch(Map<String, dynamic> args) async {
    final id = int.tryParse('${(args['ids'] as Map?)?['thread'] ?? ''}');
    if (id == null) return Reply.error('INVALID_ARGS', 'Missing thread');
    final detail = await _scrapeThread(id);
    if (detail == null) return Reply.error('NOT_FOUND', 'That thread is private, moved or deleted');
    return Reply.ok({
      // The thread this game is, so droidtop links the game to it: the next scrape and the update checks find it.
      'sourceLinks': {sourceKey: '$id'},
      // The thread's banner, the picture people know a game by: droidtop fetches it itself as the cover.
      if (detail.image != null) 'cover': detail.image,
      if (detail.description != null) 'description': detail.description,
      if (detail.developer != null) 'developer': detail.developer,
      if (detail.engine != null) 'genre': detail.engine,
      if (detail.score != null && detail.score! > 0) 'rating': (detail.score! / 5).clamp(0.0, 1.0),
    });
  }

  /// How long the scrape keeps what F95zone and F95Checker told it: a game's name, banner and text rarely change, and
  /// a library of hundreds of games re-scraped each week would otherwise ask both sites for every one again. Game
  /// pages and update checks always ask anew.
  static const int scrapeCacheMs = 7 * 24 * 60 * 60 * 1000;

  Future<Map<String, dynamic>?> _fresh(String name) async {
    final kept = await services.readJson(name);
    if (kept is! Map) return null;
    final at = (kept['at'] as num?)?.toInt() ?? 0;
    final age = _now() - at;
    return age >= 0 && age < scrapeCacheMs ? kept.cast<String, dynamic>() : null;
  }

  Future<void> _keep(String name, Map<String, dynamic> value) async {
    try {
      await services.writeJson(name, {'at': _now(), ...value});
    } on HostError {
      // Over the data quota: this answer is still good, it is only not kept.
    }
  }

  /// A scrape search's threads as (title, id), from the cache when it is under a week old.
  Future<List<MapEntry<String, int>>> _scrapeSearch(String key, String query) async {
    final name = 'cache/search-$key.json';
    final kept = await _fresh(name);
    if (kept != null) {
      return [
        for (final t in (kept['threads'] as List? ?? const []).whereType<Map>())
          if ((t['id'] as num?) != null) MapEntry('${t['title'] ?? ''}', (t['id'] as num).toInt()),
      ];
    }
    final found = [for (final t in await client.search(query, rows: 15)) MapEntry(t.title, t.id)];
    await _keep(name, {'threads': [for (final t in found) {'id': t.value, 'title': t.key}]});
    return found;
  }

  /// A thread's details for the scrape, from the cache when it is under a week old. A gone thread is not kept.
  Future<ThreadDetail?> _scrapeThread(int id) async {
    final name = 'cache/full-$id.json';
    final kept = await _fresh(name);
    final root = kept?['index'];
    if (root is Map) return ThreadDetail.parse(id, root.cast<String, dynamic>());
    final fresh = await client.fullJson(id);
    if (fresh == null) return null;
    await _keep(name, {'index': fresh});
    return ThreadDetail.parse(id, fresh);
  }

  // ----------------------------------------------------------- settings (C)

  /// `ui.facets` `get`: the plugin's settings page (droidtop docs/plugin-api.md 1.10); no other target is declared.
  Future<Map<String, dynamic>> _facets(String target) async {
    if (target != settingsTarget) return {'facets': <Map<String, dynamic>>[]};
    final signedIn = await services.signedIn();
    final context = Context.fromJson(await services.readJson(_contextFile));
    return settingsFacets(signedIn: signedIn, watched: context.active.length, syncedAt: context.siteSyncedAt);
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
      if (page == 1) {
        final name = accountName(answer.body);
        if (name != null) await services.setAccount(name);
      }
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

/// The signed-in member's name from a XenForo page's navigation, or null.
String? accountName(String html) {
  final raw = RegExp(r'class="p-navgroup-user-linkText"[^>]*>([^<]{1,64})<').firstMatch(html)?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#039;', "'").replaceAll('&amp;', '&');
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

/// A page the plugin could not read, in plain words; what the parser said stays off the screen.
const String unreadablePage = 'F95zone sent a page this plugin could not read. Try again later.';

Map<String, dynamic> _view(String title, List<Map<String, dynamic>> items, {String? subtitle}) => {
      'view': 1,
      'title': title,
      'subtitle': ?subtitle,
      'sections': [
        {'id': 'main', 'items': items},
      ],
    };

/// A record page's link for mirror [index]: its place and its label, so a thread that changed since is noticed.
String mirrorLink(int index, Mirror mirror) => '$index:${mirror.label}';

/// The mirror a record page's [link] names, if the thread still lists it at that place under that label.
int? mirrorFor(ThreadDetail detail, String link) {
  final colon = link.indexOf(':');
  final index = colon > 0 ? int.tryParse(link.substring(0, colon)) : null;
  if (index == null || index < 0 || index >= detail.mirrors.length) return null;
  return detail.mirrors[index].label == link.substring(colon + 1) ? index : null;
}

/// Each mirror's https address on the thread page [html], by the mirror's place; a mirror the page has no link for is
/// left out.
Map<int, String> mirrorAddresses(ThreadDetail d, String html) => {
      for (var i = 0; i < d.mirrors.length; i++)
        if (resolveMirror(html, d.mirrors[i].selector) case final String url when url.startsWith('https://') && url.length <= 2048) i: url,
    };

/// The thread as droidtop's record page takes it (droidtop docs/plugin-api.md 3 A6 `record`); [addresses] are the
/// mirrors' links as the thread page has them, which droidtop opens itself.
Map<String, dynamic> recordOf(ThreadDetail d, {Map<int, String> addresses = const {}}) => {
      'id': '${d.id}',
      'title': d.name,
      'url': d.url,
      'version': ?d.version,
      'developer': ?d.developer,
      'status': ?d.status,
      if (d.score != null && d.score! > 0) 'rating': (d.score! / 5).clamp(0.0, 1.0),
      'votes': ?d.votes,
      if (d.tags.isNotEmpty) 'tags': d.tags,
      // F95Checker's stamp is in seconds.
      if (d.lastUpdated != null && d.lastUpdated! > 0) 'updated': d.lastUpdated! * 1000,
      'cover': ?d.image,
      'overview': ?d.description,
      'changelog': ?d.changelog,
      'downloads': [
        for (var i = 0; i < d.mirrors.length; i++)
          {
            'section': d.mirrors[i].section,
            'host': d.mirrors[i].label,
            'label': d.mirrors[i].label,
            'link': mirrorLink(i, d.mirrors[i]),
            'url': ?addresses[i],
          },
      ],
    };

/// The `metadata` bundle's status for each of F95Checker's words ([statuses]).
const Map<String, String> metadataStatus = {
  'In development': 'ongoing',
  'Completed': 'completed',
  'On hold': 'onhold',
  'Abandoned': 'abandoned',
};

/// The thread as one item of droidtop's item page (droidtop docs/plugin-api.md 1.10, contract 3): its metadata,
/// description, cover, mirrors and thread link as bundles, kept by droidtop for a day.
Map<String, dynamic> itemPageOf(ThreadDetail d, {Map<int, String> addresses = const {}}) => {
      'source': 'f95zone',
      'id': '${d.id}',
      'ttl': 86400,
      'facets': [
        {
          'id': 'meta',
          'kind': 'metadata',
          'v': 1,
          'title': d.name,
          'version': ?d.version,
          'developer': ?d.developer,
          'engine': ?d.engine,
          'status': ?metadataStatus[d.status],
          if (d.score != null && d.score! > 0) 'rating': (d.score! / 5).clamp(0.0, 1.0),
          'votes': ?d.votes,
          if (d.tags.isNotEmpty) 'tags': d.tags,
          if (d.lastUpdated != null && d.lastUpdated! > 0) 'updated': d.lastUpdated! * 1000,
        },
        if (d.description != null || d.changelog != null)
          {'id': 'about', 'kind': 'description', 'v': 1, 'overview': ?d.description, 'changelog': ?d.changelog},
        if (d.image case final String image when image.startsWith('https://'))
          {'id': 'cover', 'kind': 'image', 'v': 1, 'role': 'cover', 'url': image, 'alt': d.name},
        if (d.mirrors.isNotEmpty)
          {
            'id': 'dl',
            'kind': 'download',
            'v': 1,
            'entries': [
              for (var i = 0; i < d.mirrors.length; i++)
                {
                  'section': d.mirrors[i].section,
                  'host': d.mirrors[i].label,
                  'label': d.mirrors[i].label,
                  'link': mirrorLink(i, d.mirrors[i]),
                  if (addresses[i] case final String url) ...{'url': url, 'kind': 'page'},
                },
            ],
          },
        {
          'id': 'links',
          'kind': 'links',
          'v': 1,
          'entries': [
            {'kind': 'source', 'label': 'F95zone thread', 'url': d.url},
          ],
        },
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
        'subtitle': 'F95zone shows download links to members.',
      },
    if (!signedIn)
      {
        'type': 'button',
        'id': 'signin-button',
        'title': 'Sign in to F95zone',
        'action': {'kind': 'job', 'op': 'signIn', 'title': 'Sign in to F95zone'},
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

/// The settings page's target (droidtop docs/plugin-api.md 1.10).
const String settingsTarget = 'settings.page';

/// `ui.facets` on the settings page: the watch list. The F95zone account is droidtop's own account row on this
/// plugin's page (droidtop docs/SPEC.md 12a, "A plugin's site account"), so no facet signs in, names the account or
/// signs out.
Map<String, dynamic> settingsFacets({required bool signedIn, required int watched, required int syncedAt}) => {
      'facets': [
        if (signedIn)
          {
            'id': 'sync',
            'kind': 'action',
            'v': 1,
            'targets': [settingsTarget],
            'label': 'Sync the watch list now',
            'sub': '$watched watched threads${syncedAt > 0 ? '' : ', never synced'}',
            'call': {'op': 'syncWatched', 'kind': 'job'},
          }
        else
          {
            'id': 'watched',
            'kind': 'info',
            'v': 1,
            'targets': [settingsTarget],
            'label': 'Watch list',
            'value': '$watched threads',
            'sub': "Syncs with F95zone once you sign in on droidtop's F95zone account row, on this plugin's page.",
          },
      ],
    };
