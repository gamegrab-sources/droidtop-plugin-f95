#!/usr/bin/env bash
# Signs build.sh's output and packs <plugin id>.droidplugin.tar.xz.
#
# This plugin is unofficial: it signs with this repository's own P-256 key,
# never derived from droidtop's plugin master. CI writes the repository secret
# PLUGIN_SIGNING_KEY to a private temporary file and points
# PLUGIN_SIGNING_KEY_FILE at it. People trust the key under droidtop's
# Settings > Plugins > Keys you trust, from droidtop-plugin-key.json at the
# root of this repository.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${PLUGIN_SIGNING_KEY_FILE:?set to the path of this repository's private key (PEM)}"
BUNDLE_DIR=droidtop_plugin/build

for part in manifest.json payload/lib payload/dex payload/flutter_assets; do
  test -e "$BUNDLE_DIR/$part" || { echo "missing $BUNDLE_DIR/$part: run droidtop_plugin/build.sh first" >&2; exit 1; }
done

PLUGIN_ID="$(python3 -c "import json; print(json.load(open('$BUNDLE_DIR/manifest.json'))['id'])")"

openssl dgst -sha256 -sign "$PLUGIN_SIGNING_KEY_FILE" "$BUNDLE_DIR/manifest.json" | base64 -w0 > "$BUNDLE_DIR/manifest.sig"

# GNU tar's repeated -C is cumulative; absolute paths keep each one plain.
BUNDLE_ABS="$(cd "$BUNDLE_DIR" && pwd)"
OUT="${PLUGIN_ID}.droidplugin.tar.xz"
tar --sort=name -cf - \
  -C "$BUNDLE_ABS" manifest.json manifest.sig \
  -C "$BUNDLE_ABS/payload" lib dex flutter_assets \
  | xz -9e > "$OUT"

echo "Signed $OUT"
sha256sum "$OUT"
