#!/usr/bin/env bash
# Builds the plugin bundle (unsigned): droidtop_plugin/build/manifest.json and
# droidtop_plugin/build/payload/{lib,dex,flutter_assets}. Same shape as
# droidtop's own samples/plugin-sample-flutter-statustile/build.sh: the
# Android host project is boilerplate, scaffolded fresh by `flutter create`
# every run and never committed; this repo's pubspec.yaml and lib/ are laid
# over it and built with a real `flutter build apk` for both ABIs.
#
# Flutter must be EXACTLY the version whose engine droidtop pins
# (plugin-host/src/main/assets/flutter-runtimes.json in droidtop): Flutter
# 3.47.5, engine af7e796e161ae0bb1ff0758c71a7105418bd9ded. droidtop refuses a
# libapp.so built against another engine at load.
#
# Never touches a key. sign.sh is the separate signing step.

set -euo pipefail
cd "$(dirname "$0")/.."

RUNTIME_VERSION="af7e796e161ae0bb1ff0758c71a7105418bd9ded"
OUT=droidtop_plugin/build

command -v flutter >/dev/null || { echo "flutter not on PATH (Flutter 3.47.5, see this script's header)" >&2; exit 1; }

PLUGIN_ID="$(python3 -c "import json; print(json.load(open('droidtop_plugin/manifest.template.json'))['id'])")"

rm -rf -- "${OUT:?}"
mkdir -p "$OUT/scaffold" "$OUT/payload"

flutter create --platforms=android --org io.github.gamegrabsources --project-name droidtop_plugin_f95 "$OUT/scaffold" >/dev/null
cp pubspec.yaml analysis_options.yaml "$OUT/scaffold/"
rm -rf -- "${OUT:?}/scaffold/lib" "${OUT:?}/scaffold/test"
cp -r lib "$OUT/scaffold/lib"

(
  cd "$OUT/scaffold"
  flutter pub get
  flutter build apk --release \
    --target-platform android-arm64,android-x64 \
    --dart-define=DROIDTOP_PLUGIN_ID="$PLUGIN_ID"
)

APK="$OUT/scaffold/build/app/outputs/flutter-apk/app-release.apk"
test -f "$APK" || { echo "flutter build apk did not produce $APK" >&2; exit 1; }

# Both ABIs in every bundle (arm64-v8a for the console, x86_64 for the rigs).
for abi in arm64-v8a x86_64; do
  mkdir -p "$OUT/payload/lib/$abi"
  unzip -p "$APK" "lib/$abi/libapp.so" > "$OUT/payload/lib/$abi/libapp.so"
  test -s "$OUT/payload/lib/$abi/libapp.so" || { echo "no libapp.so for $abi" >&2; exit 1; }
done

# The generated plugin registrant and any Flutter plugin package's Android
# half; droidtop's engine host loads payload/dex and calls the registrant.
mkdir -p "$OUT/payload/dex"
unzip -qo "$APK" 'classes*.dex' -d "$OUT/payload/dex"

# flutter_assets sits at assets/flutter_assets/** in the APK and at the
# payload's top level in a bundle.
EXTRACT_DIR="$(mktemp -d)"
unzip -q "$APK" 'assets/flutter_assets/*' -d "$EXTRACT_DIR"
cp -r "$EXTRACT_DIR/assets/flutter_assets" "$OUT/payload/flutter_assets"
rm -rf -- "${EXTRACT_DIR:?}"

python3 - "$RUNTIME_VERSION" <<'PY'
import hashlib, json, os, sys

runtime_version = sys.argv[1]
root = "droidtop_plugin/build/payload"
payload = []
for dirpath, _dirs, files in os.walk(root):
    for name in sorted(files):
        full = os.path.join(dirpath, name)
        rel = os.path.relpath(full, root).replace(os.sep, "/")
        payload.append({"path": rel, "sha256": hashlib.sha256(open(full, "rb").read()).hexdigest()})
payload.sort(key=lambda e: e["path"])

manifest = json.load(open("droidtop_plugin/manifest.template.json"))
# The published version is <declared>-<CI run> (Droidtop/tracker#126): two
# builds of one declared version never show the same string.
build = os.environ.get("DROIDTOP_PLUGIN_BUILD", "").strip()
if build:
    if not build.isdigit():
        sys.exit(f"DROIDTOP_PLUGIN_BUILD must be a CI run number, got {build!r}")
    manifest["version"] = f'{manifest["version"]}-{build}'
manifest["runtimeVersion"] = runtime_version
manifest["payload"] = payload
json.dump(manifest, open("droidtop_plugin/build/manifest.json", "w"), indent=2, sort_keys=True)
print(f"payload: {len(payload)} files, id={manifest['id']}, version={manifest['version']}")
PY

echo "Built $OUT/manifest.json and $OUT/payload (unsigned)"
