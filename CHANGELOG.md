# Changelog

Every working build of `main` is a release (`v<version>-<CI run>`); the
declared version moves with every change to the plugin's sources.

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
