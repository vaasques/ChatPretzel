#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'BLOCKED: DMG packaging requires macOS.' >&2; exit 2; }
[[ -d dist/ChatPretzel.app ]] || { echo 'Run scripts/build.sh first.' >&2; exit 2; }
# Stage outside File Provider-backed folders so Finder metadata cannot be
# reattached between signature verification and disk-image creation.
STAGE="$(mktemp -d "/private/tmp/chatpretzel-dmg.XXXXXX")"
trap '[[ -n "${STAGE:-}" && -d "$STAGE" ]] && rm -rf -- "$STAGE"' EXIT
/usr/bin/ditto --norsrc --noextattr dist/ChatPretzel.app "$STAGE/ChatPretzel.app"
/usr/bin/xattr -cr "$STAGE/ChatPretzel.app"
CHATPRETZEL_APP_PATH="$STAGE/ChatPretzel.app" bash scripts/verify-app.sh
/usr/bin/codesign --verify --strict --verbose=2 "$STAGE/ChatPretzel.app"
ln -s /Applications "$STAGE/Applications"
cp START_HERE.md "$STAGE/START_HERE.md"
OUT="$ROOT/dist/ChatPretzel-0.2.0-$(uname -m)-$(date +%Y%m%d-%H%M%S).dmg"
/usr/bin/hdiutil create -volname ChatPretzel -srcfolder "$STAGE" -ov -format UDZO "$OUT"
/usr/bin/shasum -a 256 "$OUT" > "$OUT.sha256"
printf 'DMG created: %s\n' "$OUT"
echo 'DMG packaging does not imply notarization or verified ChatGPT compatibility.'
