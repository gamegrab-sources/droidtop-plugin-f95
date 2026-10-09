# The F95zone plugin's context, and how it syncs

droidtop's plugin context sync (Droidtop/tracker#380, transport by the desktop
agent, tracker#373) keeps a plugin's own supporting state the same on the
handheld and on the person's computer, both ways: watch a thread or mark a
version installed in F95Checker on the PC and the plugin shows it; do it in
droidtop and F95Checker's database shows it. This file says what this
plugin's context is and how two changed copies merge. The PC side
(gamegrab-sources/droidtop-agent-f95-adapter) reads and writes F95Checker's
`db.sqlite3`; this plugin reads and writes `context.json` in its own data
folder (droidtop's data API). Both apply the rules below.

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

Every record also carries, per field, the time the field last changed on the
side that holds the record (`changedAt` for the record, and `fieldAt` with one
time per field once both sides keep them; milliseconds since 1970). F95Checker
keeps no per-field times, so the adapter keeps them itself next to the
database, stamping a field the moment it sees it differ from its last
snapshot.

Not context, deliberately: F95Checker's launch settings (`executables`,
`launch_wrapper`) and play time are about the PC's own copies of games;
labels, tabs and ratings are F95Checker's UI. They stay on the PC.

## How two copies merge: three-way, per field

Each side keeps the **base**: the record as it was at the last successful sync
(the same snapshot on both sides after a sync). A sync compares, field by
field, the base with the handheld's copy (**device**) and the PC's copy
(**pc**):

1. Neither changed it since the base: keep it.
2. One side changed it: take that side's value.
3. Both changed it to the same value: take it.
4. Both changed it to different values (a conflict): the field's own rule.

| Field | Conflict rule | Why |
| --- | --- | --- |
| watched | **watched wins** (add wins over remove) | losing a watch silently is worse than one extra thread on the list; unwatching again is one press |
| name | **pc wins** | F95Checker's rename is the person's deliberate act; the device only ever takes the index's title |
| latest | **the newer check wins** (the later `fieldAt`); equal times: pc | both sides ask the same index; the later answer is the truer one |
| installed | **the later change wins** (`fieldAt`); equal times: device | the person's own statement; the most recent one is what they mean now |
| finished | same as installed | same reason |
| notes | **both kept**: the pc text, a line `-- from the handheld --`, then the device text | text is never thrown away; the person tidies it once |

A record only one side has:
- created since the base on that side: added to the other side;
- deleted since the base on that side (an unwatch): it stays as a tombstone
  (`watched: false`) until the other side has applied it, then both drop it;
- deleted on one side and changed by the person on the other since the base
  (name, installed, finished or notes; a new version from the index does not
  count): "watched wins" above applies, so it comes back, with the other
  side's changes.

After a merge both sides hold the merged record and it becomes the new base.

## F95zone itself

Signed in, the plugin also syncs `watched` with the account's watch list on
F95zone (the site has no installed, finished or notes). That is a separate
two-way merge with the same "only what changed since the last read" rule
(`Context.mergeSite`, `pendingForSite` in lib/src/state.dart): a thread
watched or unwatched here since the last read is sent to the site, anything
else follows the site.

## Files

- `context.json` in the plugin's data folder: `{"format": 1, "siteSyncedAt":
  ms, "watched": [records]}`, records as in the table above. The base for
  context sync is kept beside it as `context-base.json` in the same shape.
- The merge is `mergeContext` in lib/src/state.dart, with its tests in
  test/plugin_test.dart; the adapter implements the same table.
