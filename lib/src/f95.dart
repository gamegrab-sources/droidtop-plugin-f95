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
    this.tags = const [],
    this.votes,
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

  /// The thread's tags by name (F95Checker's numbers, [tags] below); a number it does not know is left out.
  final List<String> tags;

  /// How many people rated it, beside [score].
  final int? votes;

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
      tags: [
        for (final tag in decodeList(root['tags']))
          if (tagNames[int.tryParse('$tag')] case final String name) name,
      ],
      votes: int.tryParse(root['votes']?.toString() ?? ''),
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
/// A site's HTTP failure in plain words, for the line droidtop shows under the source.
String httpError(String site, int status) {
  if (status == 401 || status == 403) return '$site refused the request. Try again later.';
  if (status == 404 || status == 410) return '$site no longer has that page.';
  if (status == 429) return '$site asks to slow down. Try again in a minute.';
  if (status >= 500 || status == 0) return '$site is not answering right now. Try again later.';
  return '$site sent an error ($status). Try again later.';
}

const Map<String, String> statuses = {'1': 'In development', '2': 'Completed', '3': 'On hold', '4': 'Abandoned'};

/// F95Checker's own `Tag` enum (common/structs.py): the index answers a thread's tags by these numbers.
const Map<int, String> tagNames = {
  1: '2d game',
  2: '2dcg',
  3: '3d game',
  4: '3dcg',
  5: 'adventure',
  6: 'ahegao',
  140: 'ai cg',
  7: 'anal sex',
  8: 'animated',
  9: 'asset-addon',
  10: 'asset-ai-shoujo',
  11: 'asset-animal',
  12: 'asset-animation',
  13: 'asset-audio',
  14: 'asset-bundle',
  15: 'asset-character',
  16: 'asset-clothing',
  151: 'asset-daz-gen1',
  141: 'asset-daz-gen2',
  142: 'asset-daz-gen3',
  143: 'asset-daz-gen8',
  144: 'asset-daz-gen81',
  145: 'asset-daz-gen9',
  152: 'asset-daz-m4',
  153: 'asset-daz-v4',
  17: 'asset-environment',
  18: 'asset-expression',
  146: 'asset-female',
  19: 'asset-hair',
  20: 'asset-hdri',
  21: 'asset-honey-select',
  22: 'asset-honey-select2',
  23: 'asset-koikatu',
  24: 'asset-light',
  147: 'asset-male',
  25: 'asset-morph',
  148: 'asset-nonbinary',
  150: 'asset-playhome',
  26: 'asset-plugin',
  27: 'asset-pose',
  28: 'asset-prop',
  149: 'asset-scene',
  29: 'asset-script',
  30: 'asset-shader',
  31: 'asset-texture',
  32: 'asset-utility',
  33: 'asset-vehicle',
  34: 'bdsm',
  35: 'bestiality',
  36: 'big ass',
  37: 'big tits',
  38: 'blackmail',
  39: 'bukkake',
  40: 'censored',
  41: 'character creation',
  42: 'cheating',
  43: 'combat',
  44: 'corruption',
  45: 'cosplay',
  46: 'creampie',
  47: 'dating sim',
  48: 'dilf',
  49: 'drugs',
  50: 'dystopian setting',
  51: 'exhibitionism',
  52: 'fantasy',
  54: 'female protagonist',
  53: 'female domination',
  55: 'footjob',
  56: 'furry',
  57: 'futa/trans',
  58: 'futa/trans protagonist',
  59: 'gay',
  60: 'graphic violence',
  61: 'groping',
  62: 'group sex',
  63: 'handjob',
  64: 'harem',
  65: 'horror',
  66: 'humiliation',
  67: 'humor',
  68: 'incest',
  69: 'internal view',
  70: 'interracial',
  71: 'japanese game',
  72: 'kinetic novel',
  73: 'lactation',
  74: 'lesbian',
  75: 'loli',
  77: 'male protagonist',
  76: 'male domination',
  78: 'management',
  79: 'masturbation',
  80: 'milf',
  81: 'mind control',
  82: 'mobile game',
  83: 'monster',
  84: 'monster girl',
  85: 'multiple endings',
  86: 'multiple penetration',
  87: 'multiple protagonist',
  88: 'necrophilia',
  89: 'no sexual content',
  90: 'netorare',
  91: 'oral sex',
  92: 'paranormal',
  93: 'parody',
  94: 'platformer',
  95: 'point & click',
  96: 'possession',
  97: 'pov',
  98: 'pregnancy',
  99: 'prostitution',
  100: 'puzzle',
  101: 'rape',
  102: 'real porn',
  103: 'religion',
  104: 'romance',
  105: 'rpg',
  106: 'sandbox',
  107: 'scat',
  108: 'school setting',
  109: 'sci-fi',
  110: 'sex toys',
  111: 'sexual harassment',
  112: 'shooter',
  113: 'shota',
  114: 'side-scroller',
  115: 'simulator',
  116: 'sissification',
  117: 'slave',
  118: 'sleep sex',
  119: 'spanking',
  120: 'strategy',
  121: 'stripping',
  122: 'superpowers',
  123: 'swinging',
  124: 'teasing',
  125: 'tentacles',
  126: 'text based',
  127: 'titfuck',
  128: 'trainer',
  129: 'transformation',
  130: 'trap',
  131: 'turn based combat',
  132: 'twins',
  133: 'urination',
  134: 'vaginal sex',
  135: 'virgin',
  136: 'virtual reality',
  137: 'voiced',
  138: 'vore',
  139: 'voyeurism',
};

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

/// A game folder's name without what a release adds to it: a version (`-0.9.5`, ` v1.2a`, `_Ep3`) and a platform
/// (`-pc`, `-win`, `-linux`, `-mac`, `-android`), so "Eternum-0.9.5-pc" searches as "Eternum" and "Fallout 4" stays.
String folderTitle(String folder) {
  var name = folder.trim();
  final platform = RegExp(r'[-_ .](pc|win|windows|linux|mac|osx|android|market)$', caseSensitive: false);
  // A version is marked (v2, Ep3) or dotted (0.9.5): a bare trailing number may be the name's own ("Fallout 4").
  final version = RegExp(r'[-_ .]+((v|ver|version|ep|episode|ch|chapter)[ ._-]?\d+([._]\d+)*|\d+([._]\d+)+)[a-z]?$', caseSensitive: false);
  for (var i = 0; i < 4; i++) {
    final before = name;
    name = name.replaceFirst(platform, '').replaceFirst(version, '').trim();
    if (name == before) break;
  }
  return name.replaceAll(RegExp(r'[_.]+'), ' ').trim();
}

/// The link a mirror selector picks out of a thread page: the supported form
/// is F95Checker's `//a[starts-with(@href,'PREFIX')][N]` (the Nth link whose
/// address starts with PREFIX). A mirror the index gives as an F95zone address
/// (a masked link, `https://f95zone.to/masked/...`) is its own link, with
/// nothing to look up on the page: droidtop opens it in its view, where the
/// person solves the CAPTCHA and taps the host link (Droidtop/tracker#650).
/// Null when the page has no such link or the selector is another form.
String? resolveMirror(String html, String selector) {
  final given = selector.trim();
  if (given.startsWith('https://f95zone.to/')) return given;
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

/// Whether [html] is a thread page F95zone served to a guest (XenForo marks its `<html>` `data-logged-in="false"`):
/// download links are for members, so a guest page has none. A page that is not XenForo's (a browser check) is not one.
bool guestPage(String html) => RegExp(r"""<html\b[^>]*\bdata-logged-in\s*=\s*["']false["']""", caseSensitive: false).hasMatch(html);

String _unescape(String s) => s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#039;', "'");

/// A fast check's answer: thread -> last-changed stamp; null when the index
/// refused the batch (it refuses a whole batch for one id it cannot index).
Map<int, int>? parseFastCheck(String body, List<int> asked) {
  Object? parsed;
  try {
    parsed = jsonDecode(body);
  } on FormatException {
    throw HostError('FAILED', "F95Checker's index sent something this plugin could not read. Try again later.");
  }
  if (parsed is! Map) return null;
  final error = parsed['INDEX_ERROR']?.toString() ?? '';
  if (error.isNotEmpty) throw HostError('FAILED', "F95Checker's index could not answer. Try again later.");
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
    return _feed({'search': clean, 'sort': 'likes'}, rows);
  }

  /// The games F95zone's Latest Updates page lists first: the newest updates, as the site shows them.
  Future<List<ThreadSummary>> latest({int rows = 20}) => _feed({'sort': 'date'}, rows);

  Future<List<ThreadSummary>> _feed(Map<String, String> query, int rows) async {
    final uri = Uri.https('f95zone.to', '/sam/latest_alpha/latest_data.php', {
      'cmd': 'list',
      'cat': 'games',
      'page': '1',
      ...query,
      'rows': '$rows',
    });
    await _spaced();
    final answer = await services.http(uri.toString());
    if (answer.status != 200) throw HostError('FAILED', httpError('F95zone', answer.status));
    final root = jsonDecode(answer.body);
    if (root is! Map || root['status']?.toString() != 'ok') {
      throw HostError('FAILED', query.containsKey('search') ? 'F95zone refused the search. Try again later.' : 'F95zone did not list its latest updates. Try again later.');
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
    if (answer.status >= 500 || indexDown(answer.body)) throw HostError('FAILED', "F95Checker's index is down. Try again later.");
    return parseFastCheck(answer.body, batch);
  }

  /// The thread's details, or null when the index says it is gone (400, 403, 404).
  Future<ThreadDetail?> full(int id, {int stamp = 0}) async {
    final root = await fullJson(id, stamp: stamp);
    return root == null ? null : ThreadDetail.parse(id, root);
  }

  /// The index's answer for the thread as it came, for a caller that keeps it; null when the thread is gone.
  Future<Map<String, dynamic>?> fullJson(int id, {int stamp = 0}) async {
    await _spaced();
    final answer = await services.http('$index/full/$id?ts=$stamp');
    if (answer.status == 400 || answer.status == 403 || answer.status == 404) return null;
    if (answer.status >= 500 || indexDown(answer.body)) throw HostError('FAILED', "F95Checker's index is down. Try again later.");
    final root = jsonDecode(answer.body);
    if (root is! Map) throw HostError('FAILED', "F95Checker's index sent something this plugin could not read. Try again later.");
    final error = root['INDEX_ERROR']?.toString() ?? '';
    if (error.isNotEmpty) throw HostError('FAILED', "F95Checker's index could not answer. Try again later.");
    return root.cast<String, dynamic>();
  }
}
