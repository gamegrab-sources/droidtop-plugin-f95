# Changelog

Every working build of `main` is a release (`v<version>-<CI run>`); the
declared version moves with every change to the plugin's sources.

## 0.7.1

- The `web.session` entry declares `expiredText` (droidtop docs/plugin-api.md G3, Droidtop/tracker#783): droidtop opens a
  mirror's masked link out of sight first, and a page saying the link has expired makes droidtop ask the record again
  for the mirror's current link, with no F95 page shown.

## 0.7.0

- A switch on the record page, "On my watch list" (droidtop docs/plugin-api.md 1.10, an `item.page` `toggle`,
  Droidtop/tracker#602): turning it on or off watches or unwatches the thread here at once, then syncs the watch list,
  which sends the change to F95zone. Signed out, the change is kept here and goes to F95zone at the next sync.
- `record` answers with the `item.page` bundles only: the contract 2 `record` an older droidtop read is gone.

## 0.6.1

- A mirror F95Checker's index gives as a masked link (`https://f95zone.to/masked/...`) is its own link: Download and
  the record page's mirror open it in droidtop's view, where the person solves the CAPTCHA and taps the host link, and
  droidtop hands that link to its host resolvers. Before, such a mirror matched nothing on the thread page and
  Download said the thread had no link (Droidtop/tracker#650).

## 0.6.0

- `featured` (droidtop docs/plugin-api.md 1.8, Droidtop/tracker#612): F95zone's Latest Updates, newest first, for
  droidtop's Get new games page, at most the `limit` it asks for (up to 60). A console's page (a `platform` other than
  PC, Windows or Linux) gets none.
- A `search` or `featured` result carries its banner as an `image` facet with role `cover`, first, so droidtop shows it
  as the game's box art.

## 0.5.3

- A thread page F95zone served to a guest (its `<html>` says `data-logged-in="false"`) means the session droidtop keeps
  is no longer honoured, and download links are for members: the session is cleared, so droidtop shows the account
  signed out and offers its sign-in, the record carries no addresses, and a download says "Sign in to F95zone to get
  download links" instead of "The thread page has no <host> link now" (droidtop Droidtop/tracker#599, the console
  updating Bare Witness).

## 0.5.2

- Each mirror names the systems its heading does (`systems`: "Win/Linux" is Windows and Linux, "Android" is Android),
  on the item page's download bundle and the record alike, for droidtop's system picker on the Downloads tab
  (Droidtop/tracker#617). A heading that names none ("Extras") is left for every system.

## 0.5.1

- The release of 0.5.0's facets and contract 3 changes. 0.5.0's two commits shared one declared version, so CI's version rule refused the second
  and 0.5.0 was never released; this version carries both unchanged.

## 0.5.0

- On facets (droidtop docs/plugin-api.md 1.10). The update page's record also comes as the item page's bundles
  (`items: [{id, facets}]`: metadata, description, cover, the mirrors and the thread link). droidtop draws them through
  its guards, and an older droidtop reads the `record` beside them as before.
- The settings are `settings.page` facets in place of the `ui.settings` view: the watch list's sync job, or how many
  threads it holds and where to sign in.
- The manifest says `"contractVersion": 3`: it needs facets, so a droidtop built before them refuses this version
  and keeps the one installed, rather than install a plugin whose settings it cannot draw (droidtop docs/plugin-api.md
  7, "Contract 3").

## 0.4.9

- droidtop keeps the links and opens them itself (droidtop Droidtop/tracker#599): signed in, the update page's record
  carries each mirror's address as the thread page has it, read once when the page opens. droidtop opens the one the
  person picks in its web view, the person starts the download there, and droidtop takes it over. Nothing is fetched
  again to download. A mirror the page has no link for stays a token for the `download` job.

## 0.4.8

- droidtop's update page (`library.updates` `record` and the `download` job, droidtop docs/plugin-api.md 3 A6):
  tapping an update in droidtop shows the thread the way F95Checker and f95seeker do, Overview, Changelog, Downloads
  and Info, and picking a mirror downloads that version for droidtop to place beside the game's other versions.
  Tags (F95Checker's own tag names) and vote counts are read from the index for it.

## 0.4.7

- Fewer requests to F95zone and F95Checker: the scrape keeps a search's threads and a thread's details for a week in
  the plugin's data, so re-scraping a library asks again only for what is new. Game pages, downloads and update
  checks always ask anew.

## 0.4.6

- The scrape's cover (droidtop docs/plugin-api.md 3 A3): `library.metadata fetch` names the thread's banner as
  `cover`, so a game with no cover gets it. droidtop fetches it itself, only from this plugin's sites, which now list
  `attachments.f95zone.to` where F95zone keeps its pictures. An older droidtop ignores the field.

## 0.4.5

- The scrape finds an unlinked game (droidtop Droidtop/tracker#575): `library.metadata match` searches F95zone by the
  game's title and by its folder's name less version and platform ("Eternum-0.9.5-pc" is "Eternum"), and answers only
  exact names. One thread is the game; several with that name tie, and droidtop asks the person to pick. `fetch`
  names the thread (`sourceLinks`), so droidtop links the game to it.

## 0.4.4

- The F95zone account is droidtop's account row on the plugin's page, the one way in (droidtop docs/SPEC.md 12a,
  "A plugin's site account"): the `web.session` entry declares the sign-in page and XenForo's signed-in cookie, and
  the settings show no sign-in, account or sign-out row of their own.
- After a sign-in through droidtop (`web.session.signed_in`), reads the account's name for the row
  (`web.session set_account`) and syncs the watch list. An older droidtop never sends the event and shows "Signed in".

## 0.4.3

- Names its kind for droidtop's Plugins page (`category`, docs/plugin-api.md 1.2, Droidtop/tracker#179).

## 0.4.2

- Signs with a leaf certificate issued by the gamegrab root (`manifest.jws`), and publishes the gamegrab root certificate as `droidtop-plugin-key.json`.

## 0.4.1

- Declares the systems it serves (Windows and Linux games), so droidtop lists it in PC searches and not under a console such as Game Boy Advance.
  Needs a droidtop that reads `systems` on `library.sources` (docs/plugin-api.md 1.6); an older
  droidtop ignores the field and lists the source everywhere, as before.

## 0.4.0

- Failures in plain words: "F95zone refused the request. Try again later."
  instead of "F95zone answered the search with HTTP 403" (seen on the rig),
  and no parser or index text on screen.
- The detail page has its own Sign in button where downloads need it.
- Shorter text: one-line description (the catalog marks the plugin
  Unofficial) and account hint.
- droidtop's contract 2.1 host names (net.request, web.session.get_status;
  needs droidtop 0.2.0-dev.1767 or newer) and 48 KiB data reads.

## 0.3.2

- The bundle's dex is no longer obfuscated, so droidtop's engine can call its
  plugin registrant (the contained-tier rig run on 0.3.1 found
  `registerWith(q6)` and no Flutter plugin package registered). The build
  now fails if the dex does not name droidtop's FlutterEngine.

## 0.3.1

- Declares its context adapter (droidtop `computers.context_adapter`,
  plugin-api F8): `f95checker`, the programs of
  gamegrab-sources/droidtop-agent-f95-adapter release build-1 for Windows
  x86_64, Linux x86_64 and macOS arm64, pinned by SHA-256. droidtop opens the
  plugin's F95Checker context only for an adapter the manifest declares.

## 0.3.0

- Downloads carry an engine hint (droidtop's acquire reply `engine`): Ren'Py,
  HTML, Godot, Unity and Unreal threads (F95Checker's type) are pinned to that
  engine's Enginehost player when droidtop places the file. RPG Maker is left
  to droidtop's detection (it is several engines).
- Details for droidtop's scraper: a game linked to its thread is that thread
  (no search); droidtop now asks for PC and engine games too.
- Context sync defined (docs/CONTEXT.md): watched threads with latest,
  installed and finished versions and notes, merged three ways per field with
  F95Checker on the computer (`mergeContext`). The transport is droidtop's.

## 0.2.0

- Update checks (`library.updates` `check`): F95Checker's public index, a
  fast check of up to ten threads per request and a full check only of the
  threads whose stamp moved, a second between requests; one notification
  when linked games have new versions, each said once.
- Linking (`match`): the watch list's threads with the game's name first,
  then F95zone's Latest Updates search.
- Search, thread details and downloads (`library.sources`): the Latest
  Updates search, the index's details (version, developer, engine, status)
  and mirrors; Download reads the chosen mirror's link from the thread page
  with the F95zone session and opens it in droidtop's web view, and the file
  the page starts goes to droidtop's Downloads place.
- Details for the scraper (`library.metadata`): description, developer,
  engine and score.
- Settings: sign in to F95zone in droidtop's web view (the session stays
  with droidtop), sign out, and sync the watch list with F95zone both ways.
- Runs contained: every request through droidtop (`net.http`,
  `web.session`), state through droidtop's data API.

## 0.1.2

- The official signing shape under the gamegrab-sources master: plugin id
  `gamegrab.f95`, origin `gamegrab`, this repository's own key, and its
  certificate packed as `origin.cert`. No key file at the repository root.

## 0.1.1

- Signed under the gamegrab-sources origin `bi0shacker001` (plugin id
  `bi0shacker001.f95`), the origin the gamegrab-sources catalog trusts, so
  one trusted key covers every plugin in the organisation.

## 0.1.0

- The repository: build, sign and release path (both ABIs), licence and
  notices.
- `library.updates` `resolve`: a pasted thread link or number becomes a
  link droidtop keeps under the source key `f95zone` (the key droidtop moved
  every thread link made before F95 support left its core to).
- Not built yet: `check`, `match`, search, details, downloads, sign-in and
  context sync. They answer `UNSUPPORTED`.
