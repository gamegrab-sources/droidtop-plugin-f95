# F95zone for droidtop (unofficial)

An unofficial [droidtop](https://github.com/Droidtop/droidtop) plugin from
the gamegrab-sources organisation. It is not part of droidtop and is not
affiliated with F95zone or F95Checker. Use it under the rules of the sites it
talks to.

Everything it shows appears in droidtop's own UI: a game's page gets an
"F95zone thread" row, a sheet to link the game to its thread, and droidtop's
update badge, shelf and filter when a newer version is out. The plugin draws
no screens of its own.

## Status

In development (0.1.0). Built so far: pasting a thread link or number to link
a game. Planned, in this order: update checks through F95Checker's public
index (api.f95checker.dev), matching a game to its thread by its folder name,
search through F95zone's Latest Updates feed, thread details, downloads into
droidtop's Downloads place, F95zone sign-in, watched-thread sync, and context
sync with F95Checker on your computer. See CHANGELOG.md.

## How it fits droidtop

- `library.updates` (droidtop `docs/plugin-api.md` 3 A6), source key
  `f95zone`. droidtop keeps the links and the last answer, decides when a
  thread is due (at most every six hours, once a minute for Check now) and
  compares versions itself; the plugin reads pasted links, offers matches and
  answers checks.
- It runs **contained** (droidtop `docs/plugin-api.md` 5.3): an isolated
  process with no sockets and no files of its own. Network goes through
  droidtop's `net.http`, secrets (the sign-in session) through the vault, and
  state through droidtop's data API. It does not ask for `host.full_trust`.

## Installing

Releases carry the signed bundle (`gamegrab.f95.droidplugin.tar.xz`) and its
manifest. The bundle is signed with this repository's own key, and the key's
certificate (`origin.cert`, inside the bundle) comes from the gamegrab-sources
master, not droidtop's plugin master. In droidtop, add the gamegrab-sources
catalog (Settings > Plugins > Add > Catalogs); droidtop then trusts that
master, and the plugin installs from the catalog as unofficial.

## Building

CI builds every push (`.github/workflows/build.yml`): `flutter analyze`,
`flutter test`, and `droidtop_plugin/build.sh`, which scaffolds the Android
host project with `flutter create`, builds `libapp.so` for arm64-v8a and
x86_64, and writes the unsigned manifest and payload. On `main` it signs with
the repository secrets `PLUGIN_SIGNING_KEY` and `PLUGIN_SIGNING_CERT` (set by
droidtop's `plugin-key-provision official` against the gamegrab-sources
master seed) and publishes a release. Flutter
must be 3.47.5, the engine droidtop pins.

## Licence

GPL-3.0, because it adapts code from F95Checker and f95seeker (see NOTICE).
