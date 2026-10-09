#!/usr/bin/env bash
# Signs build.sh's output and packs <plugin id>.droidplugin.tar.xz.
#
# The official shape (as droidtop-plugin-shizuku's sign.sh), under the
# gamegrab-sources master instead of droidtop's: this repository's own key,
# derived from the gamegrab-sources master seed by plugin-key-provision, signs
# the manifest, and the key's certificate from that master travels in the
# bundle as origin.cert. droidtop checks bundle signature, key, certificate,
# master, and that the certificate names gamegrab.f95. CI writes the secrets
# PLUGIN_SIGNING_KEY and PLUGIN_SIGNING_CERT to private temporary files and
# passes their paths here.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${PLUGIN_SIGNING_KEY_FILE:?set to the path of this repository's private key (PEM)}"
: "${PLUGIN_SIGNING_CERT_FILE:?set to the path of this key's certificate from the gamegrab-sources master}"
BUNDLE_DIR=droidtop_plugin/build

for part in manifest.json payload/lib payload/dex payload/flutter_assets; do
  test -e "$BUNDLE_DIR/$part" || { echo "missing $BUNDLE_DIR/$part: run droidtop_plugin/build.sh first" >&2; exit 1; }
done

PLUGIN_ID="$(python3 -c "import json; print(json.load(open('$BUNDLE_DIR/manifest.json'))['id'])")"

openssl dgst -sha256 -sign "$PLUGIN_SIGNING_KEY_FILE" "$BUNDLE_DIR/manifest.json" | base64 -w0 > "$BUNDLE_DIR/manifest.sig"
cp "$PLUGIN_SIGNING_CERT_FILE" "$BUNDLE_DIR/origin.cert"

# GNU tar's repeated -C is cumulative; absolute paths keep each one plain.
BUNDLE_ABS="$(cd "$BUNDLE_DIR" && pwd)"
OUT="${PLUGIN_ID}.droidplugin.tar.xz"
tar --sort=name -cf - \
  -C "$BUNDLE_ABS" manifest.json manifest.sig origin.cert \
  -C "$BUNDLE_ABS/payload" lib dex flutter_assets \
  | xz -9e > "$OUT"

echo "Signed $OUT"
sha256sum "$OUT"
