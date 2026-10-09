/// What the plugin keeps between calls, in its own data folder through
/// droidtop's data API (it has no files of its own when contained).
///
/// Two parts:
/// - [ThreadCheck]s: per linked thread, what F95Checker's index last said
///   (its last-changed stamp and version), so a round asks for full details
///   only of threads that changed, and so a new version is noticed once.
/// - the [Context]: the person's F95 state that belongs to the plugin, not to
///   droidtop's library: watched threads with their installed and latest
///   versions and notes. This is what context sync keeps the same as
///   F95Checker's database on the person's computer (docs/CONTEXT.md).
class ThreadCheck {
  ThreadCheck({required this.id, this.stamp = 0, this.version, this.title, this.notified});

  final int id;
  int stamp;
  String? version;
  String? title;

  /// The newest version the person was told about, so it is said once.
  String? notified;

  Map<String, dynamic> toJson() => {'id': id, 'stamp': stamp, 'version': version, 'title': title, 'notified': notified};

  static ThreadCheck fromJson(Map<String, dynamic> j) => ThreadCheck(
        id: (j['id'] as num).toInt(),
        stamp: (j['stamp'] as num?)?.toInt() ?? 0,
        version: j['version'] as String?,
        title: j['title'] as String?,
        notified: j['notified'] as String?,
      );
}

/// One watched thread in the plugin's context (F95Checker's `games` row: its
/// `id` IS the thread id, and `name`, `version`, `installed`, `notes`).
class WatchedThread {
  WatchedThread({
    required this.id,
    required this.name,
    this.version,
    this.installed,
    this.notes = '',
    required this.changedAt,
    this.watched = true,
    this.finished,
    Map<String, int>? fieldAt,
  }) : fieldAt = fieldAt ?? {};

  final int id;
  String name;

  /// The thread's newest version as last seen.
  String? version;

  /// The version the person has installed, as they marked it (F95Checker's `installed`).
  String? installed;
  String notes;

  /// When any field last changed here or was taken from the other side, in ms; the merge's clock.
  int changedAt;

  /// False is a tombstone: unwatched here, kept so the other side learns it.
  bool watched;

  /// The version the person finished (F95Checker's `finished`).
  String? finished;

  /// When each field last changed on this side (ms), for the merge's conflict rules (docs/CONTEXT.md).
  final Map<String, int> fieldAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'installed': installed,
        'notes': notes,
        'changedAt': changedAt,
        'watched': watched,
        'finished': finished,
        'fieldAt': fieldAt,
      };

  static WatchedThread fromJson(Map<String, dynamic> j) => WatchedThread(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        version: j['version'] as String?,
        installed: j['installed'] as String?,
        notes: j['notes'] as String? ?? '',
        changedAt: (j['changedAt'] as num?)?.toInt() ?? 0,
        watched: j['watched'] as bool? ?? true,
        finished: j['finished'] as String?,
        fieldAt: ((j['fieldAt'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt())),
      );
}

class Context {
  Context({Map<int, WatchedThread>? watched, this.siteSyncedAt = 0}) : watched = watched ?? {};

  final Map<int, WatchedThread> watched;

  /// When the watch list was last read from F95zone (ms), 0 for never.
  int siteSyncedAt;

  Iterable<WatchedThread> get active => watched.values.where((w) => w.watched);

  Map<String, dynamic> toJson() => {
        'format': 1,
        'siteSyncedAt': siteSyncedAt,
        'watched': watched.values.map((w) => w.toJson()).toList(),
      };

  static Context fromJson(Object? raw) {
    if (raw is! Map) return Context();
    final list = (raw['watched'] as List?) ?? const [];
    return Context(
      watched: {
        for (final item in list.whereType<Map>()) (item['id'] as num).toInt(): WatchedThread.fromJson(item.cast<String, dynamic>()),
      },
      siteSyncedAt: (raw['siteSyncedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// The watch list as F95zone shows it now ([site]: thread id -> title), taken
  /// in at [now]: a thread watched there and not here is added; a thread here
  /// that F95zone no longer lists is unwatched, unless it was changed here
  /// after the last read (then it is still waiting to be sent: [pendingForSite]).
  void mergeSite(Map<int, String> site, int now) {
    for (final entry in site.entries) {
      final known = watched[entry.key];
      if (known == null) {
        watched[entry.key] = WatchedThread(id: entry.key, name: entry.value, changedAt: now);
      } else if (!known.watched && known.changedAt <= siteSyncedAt) {
        known
          ..watched = true
          ..changedAt = now;
      } else if (known.name.isEmpty) {
        known.name = entry.value;
      }
    }
    for (final known in watched.values) {
      if (known.watched && !site.containsKey(known.id) && known.changedAt <= siteSyncedAt) {
        known
          ..watched = false
          ..changedAt = now;
      }
    }
    siteSyncedAt = now;
  }

  /// Changes made here since the last read that F95zone does not have yet: thread id -> watch (true) or unwatch.
  Map<int, bool> pendingForSite(Map<int, String> site) => {
        for (final w in watched.values)
          if (w.changedAt > siteSyncedAt && w.watched != site.containsKey(w.id)) w.id: w.watched,
      };
}

class PluginState {
  PluginState({Map<int, ThreadCheck>? checks}) : checks = checks ?? {};

  final Map<int, ThreadCheck> checks;

  Map<String, dynamic> toJson() => {'format': 1, 'checks': checks.values.map((c) => c.toJson()).toList()};

  static PluginState fromJson(Object? raw) {
    if (raw is! Map) return PluginState();
    final list = (raw['checks'] as List?) ?? const [];
    return PluginState(checks: {
      for (final item in list.whereType<Map>()) (item['id'] as num).toInt(): ThreadCheck.fromJson(item.cast<String, dynamic>()),
    });
  }
}

/// The separator two conflicting notes are kept around (docs/CONTEXT.md).
const String notesSeparator = '-- from the handheld --';

/// Context sync's three-way merge (docs/CONTEXT.md): [base] as of the last
/// sync, the handheld's copy [device] and the computer's copy [pc], merged
/// field by field. A side without a record it had at the base has unwatched
/// it, and only that; every other field of it is the base's.
Map<int, WatchedThread> mergeContext(
  Map<int, WatchedThread> base,
  Map<int, WatchedThread> device,
  Map<int, WatchedThread> pc,
) {
  final out = <int, WatchedThread>{};
  for (final id in {...base.keys, ...device.keys, ...pc.keys}) {
    final b = base[id];
    WatchedThread? side(WatchedThread? r) => r ??
        (b == null
            ? null
            : WatchedThread(
                id: id,
                name: b.name,
                version: b.version,
                installed: b.installed,
                finished: b.finished,
                notes: b.notes,
                changedAt: b.changedAt,
                watched: false,
                fieldAt: Map.of(b.fieldAt),
              ));
    final d = side(device[id]);
    final p = side(pc[id]);

    T pick<T>(String field, T Function(WatchedThread?) get, T Function(T dv, T pv) conflict) {
      final vb = get(b), vd = get(d), vp = get(p);
      final changedD = d != null && vd != vb;
      final changedP = p != null && vp != vb;
      if (!changedD && !changedP) return vb;
      if (changedD && !changedP) return vd;
      if (!changedD && changedP) return vp;
      if (vd == vp) return vd;
      return conflict(vd, vp);
    }

    int at(WatchedThread? r, String field) => r?.fieldAt[field] ?? 0;
    T later<T>(String field, T dv, T pv, {required bool tieToPc}) {
      final dt = at(d, field), pt = at(p, field);
      if (dt == pt) return tieToPc ? pv : dv;
      return dt > pt ? dv : pv;
    }

    // An unwatch on one side meets the person's own edit of that thread on the other (not the index's new
    // version): the thread comes back, the "watched wins" rule.
    bool edited(WatchedThread? r) =>
        r != null && r.watched && b != null && (r.name != b.name || r.installed != b.installed || r.finished != b.finished || r.notes != b.notes);
    var watched = pick<bool>('watched', (r) => r?.watched ?? false, (dv, pv) => true);
    if (!watched && b != null && ((d?.watched == false && edited(p)) || (p?.watched == false && edited(d)))) watched = true;
    final merged = WatchedThread(
      id: id,
      name: pick<String>('name', (r) => r?.name ?? '', (dv, pv) => pv),
      version: pick<String?>('version', (r) => r?.version, (dv, pv) => later('version', dv, pv, tieToPc: true)),
      installed: pick<String?>('installed', (r) => r?.installed, (dv, pv) => later('installed', dv, pv, tieToPc: false)),
      finished: pick<String?>('finished', (r) => r?.finished, (dv, pv) => later('finished', dv, pv, tieToPc: false)),
      notes: pick<String>('notes', (r) => r?.notes ?? '', (dv, pv) => [pv, notesSeparator, dv].join('\n')),
      changedAt: [b?.changedAt ?? 0, d?.changedAt ?? 0, p?.changedAt ?? 0].reduce((x, y) => x > y ? x : y),
      watched: watched,
      fieldAt: {
        for (final f in const ['watched', 'name', 'version', 'installed', 'finished', 'notes'])
          f: [at(b, f), at(d, f), at(p, f)].reduce((x, y) => x > y ? x : y),
      },
    );
    out[id] = merged;
  }
  return out;
}
