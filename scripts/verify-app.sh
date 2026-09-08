#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/dist/ChatPretzel.app"
[[ "$(uname -s)" == Darwin && -d "$APP" ]] || { echo 'BLOCKED: inget native Mac-bygge att kontrollera.' >&2; exit 2; }
mkdir -p test-results
[[ -f "$APP/Contents/Resources/ChatDeskAssets/Adapter.js" ]]
[[ -f "$APP/Contents/Resources/ChatDeskAssets/ClipboardFixture.html" ]]
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/codesign -d --entitlements :- "$APP" > test-results/mac-entitlements.plist 2> test-results/mac-signature.txt
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' test-results/mac-entitlements.plist | grep -qx true
/usr/bin/otool -L "$APP/Contents/MacOS/ChatPretzel" > test-results/mac-linked-libraries.txt
if find "$APP" \( -iname '*Electron*' -o -iname '*Chromium*' -o -iname '*QtWebEngine*' -o -name node -o -name python3 \) -print | grep -q .; then
  echo 'FAIL: förbjuden runtime i app-paketet.' >&2; exit 1
fi
SIZE_KIB="$(du -sk "$APP" | awk '{print $1}')"
printf 'Installerad .app-storlek: %s KiB\n' "$SIZE_KIB" | tee test-results/mac-app-size.txt
if (( SIZE_KIB > 30720 )); then echo 'FAIL: app-paketet överstiger budgeten 30 MiB.' >&2; exit 1; fi
echo 'PASS-package: storlek, resurser och signatur kontrollerade. Detta är inte ett live-paste-test.'
