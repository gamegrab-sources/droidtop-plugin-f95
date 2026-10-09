import 'dart:convert';

import 'host.dart';

/// One thread as F95zone's Latest Updates feed lists it.
class ThreadSummary {
  ThreadSummary({required this.id, required this.title, required this.creator, this.version, this.cover});

  final int id;
  final String title;
  final String creator;
  final String? version;
  final String? cover;

  static ThreadSummary? fromFeed(Map<String, dynamic> item) {
    final id = (item['thread_id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    return ThreadSummary(
      id: id,
      title: item['title']?.toString() ?? '',
      creator: item['creator']?.toString() ?? '',
      version: _blankToNull(item['version']?.toString()),
      cover: _httpOrNull(item['cover']?.toString()),
    );
  }
}

/// A download mirror as F95Checker's index gives it: a label and an XPath
/// selector for the link on the thread page (`//a[starts-with(@href,'...')][n]`).
class Mirror {
  Mirror(this.section, this.label, this.selector);
  final String section;
  final String label;
  final String selector;
}

/// What F95Checker's index says about one thread (api.f95checker.dev/full).
class ThreadDetail {
  ThreadDetail({
    required this.id,
    required this.name,
    this.version,
    this.developer,
    this.engine,
    this.status,
    this.description,
    this.changelog,
    this.score,
    this.image,
    this.mirrors = const [],
    this.lastUpdated,
    this.engineId,
  });

  final int id;
  final String name;
  final String? version;
  final String? developer;
  final String? engine;
  final String? status;
  final String? description;
  final String? changelog;
  final double? score;
  final String? image;
  final List<Mirror> mirrors;
  final int? lastUpdated;

  /// The engines-database id for [engine], when it names one engine.
  final String? engineId;

  static ThreadDetail parse(int id, Map<String, dynamic> root) {
    final mirrors = <Mirror>[];
    for (final section in decodeList(root['downloads'])) {
      if (section is! List || section.isEmpty) continue;
      final name = section.first?.toString() ?? 'Downloads';
      final links = section.length > 1 && section[1] is List ? section[1] as List : const [];
      for (final link in links) {
        if (link is List && link.length >= 2) {
          mirrors.add(Mirror(name, link[0]?.toString() ?? 'Download', link[1]?.toString() ?? ''));
        }
      }
    }
    final type = int.tryParse(root['type']?.toString() ?? '');
    return ThreadDetail(
      id: id,
      name: _blankToNull(root['name']?.toString()) ?? 'Thread $id',
      version: versionOrNull(root['version']?.toString()),
      developer: _blankToNull(root['developer']?.toString()),
      engine: type == null ? null : engines[type],
      status: statuses[root['status']?.toString()],
      description: _blankToNull(root['description']?.toString()),
      changelog: _blankToNull(root['changelog']?.toString()),
      score: double.tryParse(root['score']?.toString() ?? ''),
      image: _httpOrNull(root['image_url']?.toString()),
      mirrors: mirrors,
      lastUpdated: int.tryParse(root['last_updated']?.toString() ?? ''),
      engineId: type == null ? null : engineIds[type],
    );
  }

  String get url => threadUrl(id);
}

/// F95Checker's own `Type` enum (common/structs.py), the engine or kind of a thread.
const Map<int, String> engines = {
  2: 'ADRIFT',
  4: 'Flash',
  31: 'Godot',
  5: 'HTML',
  6: 'Java',
  9: 'Others',
  10: 'QSP',
  11: 'RAGS',
  14: "Ren'Py",
  13: 'RPG Maker',
  16: 'TADS',
  19: 'Unity',
  20: 'Unreal Engine',
  21: 'WebGL',
  22: 'Wolf RPG',
  25: 'GIF',
  29: 'Video',
  30: 'CG',
  24: 'Comics',
  26: 'Manga',
  27: 'Pinup',
  3: 'Cheat Mod',
  8: 'Mod',
  12: 'README',
  15: 'Request',
  17: 'Tool',
  18: 'Tutorial',
  1: 'Misc',
};

/// droidtop's engines-database ids for the F95Checker types that name one
/// engine (droidtop `EngineRegistryParser.ENGINE_IDS`); the acquire reply's
/// engine hint. RPGM is left out on purpose: it is several engines (MV, MZ,
/// VX Ace, ...), which droidtop tells apart from the files.
const Map<int, String> engineIds = {14: 'renpy', 5: 'html', 31: 'godot', 19: 'unity', 20: 'unreal'};

/// F95Checker's `Status` as the index sends it.
const Map<String, String> statuses = {'1': 'In development', '2': 'Completed', '3': 'On hold', '4': 'Abandoned'};

String threadUrl(int id) => 'https://f95zone.to/threads/$id/';

String? _blankToNull(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();

String? _httpOrNull(String? value) => (value != null && value.startsWith('https://')) ? value : null;

/// A version as a thread writes it, or null for none (blank, F95Checker's `N/A`).
String? versionOrNull(String? value) {
  final v = _blankToNull(value);
  return (v == null || v.toUpperCase() == 'N/A') ? null : v;
}

/// The index stores some lists as JSON text inside the JSON.
List<dynamic> decodeList(Object? value) {
  if (value is List) return value;
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }
  return const [];
}

const _stopWords = {
  'a', 'is', 'the', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'for', 'if', 'in', 'into', 'it', 'no', 'not',
  'of', 'on', 'or', 'such', 'that', 'their', 'then', 'there', 'these', 'they', 'this', 'to', 'was', 'will', 'with',
};

/// A search the Latest Updates feed accepts: adapted from F95Checker's
/// `latest_updates_search_sanitize_query` through f95seeker (30 characters,
/// punctuation and stop words out).
String sanitizeQuery(String input) {
  final normalized = input
      .replaceAll(RegExp(r"[’']s\s+", caseSensitive: false), ' ')
      .replaceAll(RegExp(r"[?&/':;.\-+!~(),*\[\]_]+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final words = normalized.split(' ').where((w) => w.isNotEmpty && !_stopWords.contains(w.toLowerCase()));
  var result = '';
  for (final word in words) {
    final addition = '${result.isEmpty ? '' : ' '}$word';
    final remaining = 30 - result.length;
    if (remaining <= 0) break;
    result += addition.substring(0, addition.length.clamp(0, remaining));
    if (addition.length > remaining) break;
  }
  return result;
}

/// Two names are the same game when they are equal less case and
/// punctuation (droidtop's own `GameNaming.nameKey` comparison).
String nameKey(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// The link a mirror selector picks out of a thread page: the supported form
/// is F95Checker's `//a[starts-with(@href,'PREFIX')][N]` (the Nth link whose
/// address starts with PREFIX). Null when the page has no such link or the
/// selector is another form.
String? resolveMirror(String html, String selector) {
  final match = RegExp(r"""^//a\[starts-with\(@href,\s*['"]([^'"]+)['"]\)\](?:\[(\d+)\])?$""").firstMatch(selector.trim());
  if (match == null) return null;
  final prefix = match.group(1)!;
  final index = int.tryParse(match.group(2) ?? '1') ?? 1;
  var seen = 0;
  for (final href in RegExp(r'''<a\s[^>]*href\s*=\s*["']([^"']+)["']''', caseSensitive: false).allMatches(html)) {
    final url = _unescape(href.group(1)!);
    if (url.startsWith(prefix)) {
      seen++;
      if (seen == index) return url;
    }
  }
  return null;
}

String _unescape(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#039;', "'");

/// A fast check's answer: thread -> last-changed stamp; null when the index
/// refused the batch (it refuses a whole batch for one id it cannot index).
Map<int, int>? parseFastCheck(String body, List<int> asked) {
  Object? parsed;
  try {
    parsed = jsonDecode(body);
  } on FormatException {
    throw HostError('FAILED', "F95Checker's index answered with something that is not JSON");
  }
  if (parsed is! Map) return null;
  final error = parsed['INDEX_ERROR']?.toString() ?? '';
  if (error.isNotEmpty) throw HostError('FAILED', "F95Checker's index said: $error");
  final out = <int, int>{};
  for (final id in asked) {
    final stamp = int.tryParse(parsed['$id']?.toString() ?? '');
    if (stamp != null && stamp > 0) out[id] = stamp;
  }
  return out;
}

/// The index's own downtime pages come back as HTML with a 200.
bool indexDown(String body) => body.contains('502: Bad gateway') || body.contains('521: Web server is down');

/// The client for F95zone's Latest Updates feed and F95Checker's public
/// index, with the pacing F95Checker's own client uses: at most ten threads
/// per fast check, a second between requests.
class F95Client {
  F95Client(this.services, {Future<void> Function(Duration)? pause}) : _pause = pause ?? Future<void>.delayed;

  final Services services;
  final Future<void> Function(Duration) _pause;
  int _requests = 0;

  static const String index = 'https://api.f95checker.dev';
  static const int fastCheckMax = 10;
  static const Duration spacing = Duration(seconds: 1);

  Future<void> _spaced() async {
    if (_requests++ > 0) await _pause(spacing);
  }

  Future<List<ThreadSummary>> search(String query, {int rows = 30}) async {
    final clean = sanitizeQuery(query);
    if (clean.isEmpty) return const [];
    final uri = Uri.https('f95zone.to', '/sam/latest_alpha/latest_data.php', {
      'cmd': 'list',
      'cat': 'games',
      'page': '1',
      'search': clean,
      'sort': 'likes',
      'rows': '$rows',
    });
    await _spaced();
    final answer = await services.http(uri.toString());
    if (answer.status != 200) throw HostError('FAILED', 'F95zone answered the search with HTTP ${answer.status}');
    final root = jsonDecode(answer.body);
    if (root is! Map || root['status']?.toString() != 'ok') {
      throw HostError('FAILED', 'F95zone refused the search');
    }
    final data = ((root['msg'] as Map?)?['data'] as List?) ?? const [];
    return data.whereType<Map>().map((m) => ThreadSummary.fromFeed(m.cast<String, dynamic>())).whereType<ThreadSummary>().toList();
  }

  /// Last-changed stamps for [threads]; a refused batch is asked again one
  /// thread at a time, so one bad id does not cost the others their answer.
  Future<Map<int, int>> fastCheck(List<int> threads) async {
    final stamps = <int, int>{};
    for (var i = 0; i < threads.length; i += fastCheckMax) {
      final batch = threads.sublist(i, (i + fastCheckMax).clamp(0, threads.length));
      final answered = await _fast(batch);
      if (answered != null) {
        stamps.addAll(answered);
      } else if (batch.length > 1) {
        for (final id in batch) {
          final one = await _fast([id]);
          if (one != null) stamps.addAll(one);
        }
      }
    }
    return stamps;
  }

  Future<Map<int, int>?> _fast(List<int> batch) async {
    await _spaced();
    final answer = await services.http('$index/fast?ids=${batch.join(',')}');
    if (answer.status >= 500 || indexDown(answer.body)) throw HostError('FAILED', "F95Checker's index is down; it is asked again later");
    return parseFastCheck(answer.body, batch);
  }

  /// The thread's details, or null when the index says it is gone (400, 403, 404).
  Future<ThreadDetail?> full(int id, {int stamp = 0}) async {
    await _spaced();
    final answer = await services.http('$index/full/$id?ts=$stamp');
    if (answer.status == 400 || answer.status == 403 || answer.status == 404) return null;
    if (answer.status >= 500 || indexDown(answer.body)) throw HostError('FAILED', "F95Checker's index is down; it is asked again later");
    final root = jsonDecode(answer.body);
    if (root is! Map) throw HostError('FAILED', "F95Checker's index answered thread $id with something that is not a thread");
    final error = root['INDEX_ERROR']?.toString() ?? '';
    if (error.isNotEmpty) throw HostError('FAILED', "F95Checker's index said: $error");
    return ThreadDetail.parse(id, root.cast<String, dynamic>());
  }
}
