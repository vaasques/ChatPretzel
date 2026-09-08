#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP="${CHATPRETZEL_APP_PATH:-$ROOT/dist/ChatPretzel.app}"
[[ "$(uname -s)" == Darwin && -d "$APP" ]] || { echo 'BLOCKED: no native Mac build is available for verification.' >&2; exit 2; }
mkdir -p test-results
[[ -f "$APP/Contents/Resources/ChatDeskAssets/Adapter.js" ]]
[[ -f "$APP/Contents/Resources/ChatDeskAssets/ClipboardFixture.html" ]]
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/codesign -d --entitlements :- "$APP" > test-results/mac-entitlements.plist 2> test-results/mac-signature.txt
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' test-results/mac-entitlements.plist | grep -qx true
/usr/bin/otool -L "$APP/Contents/MacOS/ChatPretzel" > test-results/mac-linked-libraries.txt
if find "$APP" \( -iname '*Electron*' -o -iname '*Chromium*' -o -iname '*QtWebEngine*' -o -name node -o -name python3 \) -print | grep -q .; then
  echo 'FAIL: prohibited runtime found in the app bundle.' >&2; exit 1
fi
SIZE_KIB="$(du -sk "$APP" | awk '{print $1}')"
printf 'Installed .app size: %s KiB\n' "$SIZE_KIB" | tee test-results/mac-app-size.txt
if (( SIZE_KIB > 30720 )); then echo 'FAIL: app bundle exceeds the 30 MiB budget.' >&2; exit 1; fi
echo 'PASS-package: size, resources, and signature verified. This is not a live paste test.'
