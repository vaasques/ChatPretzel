#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'BLOCKED: DMG-paketering kräver macOS.' >&2; exit 2; }
[[ -d dist/ChatPretzel.app ]] || { echo 'Kör scripts/build.sh först.' >&2; exit 2; }
# Finder may attach non-content metadata after the locally built app has been opened.
# Remove it only from this build artifact before strict verification and packaging.
/usr/bin/xattr -cr dist/ChatPretzel.app
bash scripts/verify-app.sh
# Stage outside File Provider-backed folders so Finder metadata cannot be
# reattached between signature verification and disk-image creation.
STAGE="$(mktemp -d "/private/tmp/chatpretzel-dmg.XXXXXX")"
trap '[[ -n "${STAGE:-}" && -d "$STAGE" ]] && rm -rf -- "$STAGE"' EXIT
/usr/bin/ditto --norsrc --noextattr dist/ChatPretzel.app "$STAGE/ChatPretzel.app"
/usr/bin/xattr -cr "$STAGE/ChatPretzel.app"
/usr/bin/codesign --verify --strict --verbose=2 "$STAGE/ChatPretzel.app"
ln -s /Applications "$STAGE/Applications"
cp START_HÄR.md "$STAGE/START_HÄR.md"
OUT="$ROOT/dist/ChatPretzel-0.1.3-$(uname -m)-$(date +%Y%m%d-%H%M%S).dmg"
/usr/bin/hdiutil create -volname ChatPretzel -srcfolder "$STAGE" -ov -format UDZO "$OUT"
/usr/bin/shasum -a 256 "$OUT" > "$OUT.sha256"
printf 'DMG skapad: %s\n' "$OUT"
echo 'DMG-paketering innebär inte notarisering eller godkänd ChatGPT-kompatibilitet.'
