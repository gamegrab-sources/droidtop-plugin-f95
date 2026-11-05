# The F95zone plugin's context, and how it syncs

droidtop's plugin context sync (Droidtop/tracker#380 and #794, transport by
the desktop agent, tracker#373) keeps a plugin's own supporting state the same on the
handheld and on the person's computer, both ways: watch a thread or mark a
version installed in F95Checker on the PC and the plugin shows it; do it in
droidtop and F95Checker's database shows it. This file says what this
plugin's context is and how it syncs. The PC side
(gamegrab-sources/droidtop-agent-f95-adapter) reads and writes F95Checker's
`db.sqlite3`; this plugin reads and writes `context.json` in its own data
folder (droidtop's data API); droidtop merges the copies between them.

Library facts are not context. Which droidtop game is linked to which thread
is droidtop's (its source links, SPEC 7g), and so is whether a newer version
counts as an update for a game (droidtop compares versions itself). The
context is only what F95Checker itself keeps about threads.

## What the context is

One record per thread, keyed by the F95zone thread id. In F95Checker that is
one row of the `games` table: its `id` is the thread id (`create_game`
inserts `thread.id`). Rows with a negative id are F95Checker's custom games,
not threads, and are never part of the context.

| Field | In `context.json` | F95Checker `games` column | Who changes it | Meaning |
| --- | --- | --- | --- | --- |
| thread | `id` | `id` (positive only) | nobody (the key) | the F95zone thread |
| watched | `watched` | the row exists | the person, on either side | watched in F95Checker = a row; unwatched = no row |
| name | `name` | `name` | the index, the person (F95Checker lets them rename) | the thread's title as kept |
| latest | `version` | `version` | the index (either side's update check) | the thread's newest version |
| installed | `installed` | `installed` | the person | the version they have installed (F95Checker's own string) |
| finished | `finished` | `finished` | the person | the version they finished |
| notes | `notes` | `notes` | the person | free text |

Every record also carries, here only, the time each field last changed
(`changedAt`, `fieldAt`, milliseconds since 1970), for the watch list's own
sync with F95zone below.

Not context, deliberately: F95Checker's launch settings (`executables`,
`launch_wrapper`) and play time are about the PC's own copies of games;
labels, tabs and ratings are F95Checker's UI. They stay on the PC.

## How it syncs: a copy, merged by droidtop

The context syncs by copies (droidtop docs/plugin-api.md 3 F8, protocol 2;
droidtop-agent docs/DESIGN.md section 8; Droidtop/tracker#794). The plugin's
live `context.json` never travels.

- **Publishing.** After every change to the watch list (the record page's
  switch, a watch-list sync with F95zone), the plugin declares the context
  (`context.open`) and publishes the watched threads as its copy
  (`context.publish`). droidtop makes the copy current in one step and syncs
  it with each paired computer.
- **The merge is droidtop's** (the agent core's three-way merge per field,
  against the baseline droidtop keeps per computer). The plugin declares, per
  field, which way it travels and who wins when both sides changed it:

  | Field | Direction | Both changed it |
  | --- | --- | --- |
  | `name` | computer to handheld | the computer (F95Checker's rename is the person's) |
  | `url` | computer to handheld | the computer |
  | `version` | computer to handheld | the computer |
  | `installed` | both | the handheld (the person's own mark here) |
  | `finished` | both | the handheld |
  | `notes` | both | the person is asked |

  Whole threads (watching and unwatching) travel both ways. A version not
  set is the empty text, as F95Checker keeps it.
- **On the computer**, the adapter (gamegrab-sources/droidtop-agent-f95-adapter,
  adapter protocol 2) gives the agent a snapshot of F95Checker's threads before
  each sync, and takes the merged copy back into `db.sqlite3` while
  F95Checker is closed, keeping a change made there since the snapshot.
- **Receiving.** When a merged copy that differs from what the plugin last
  published is made current here, droidtop sends `context.received`. The
  plugin reads it (`context.copy`) and brings it into `context.json`
  (`Context.takeCopy`): every thread in it is watched with its fields. A
  thread is unwatched only when it was in the last copy both sides had
  (`copyKeys`) and this one no longer has it, so a thread watched here since
  is never lost. What changed reaches F95zone at the next watch-list sync.

## F95zone itself

Signed in, the plugin also syncs `watched` with the account's watch list on
F95zone (the site has no installed, finished or notes). That is a separate
two-way merge with the same "only what changed since the last read" rule
(`Context.mergeSite`, `pendingForSite` in lib/src/state.dart): a thread
watched or unwatched here since the last read is sent to the site, anything
else follows the site.

## Files

- `context.json` in the plugin's data folder: `{"format": 1, "siteSyncedAt":
  ms, "copyKeys": [thread ids], "watched": [records]}`, records as in the
  table above. The copy itself and its baselines are droidtop's, in its own
  folders, never the plugin's.
- `toCopy` and `takeCopy` in lib/src/state.dart, `publishContext` and
  `takeReceived` in lib/src/plugin.dart, with their tests in
  test/plugin_test.dart.
