#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'BLOCKED: The native app must be built on macOS. A Linux test of ChatDeskCore is not a Mac build.' >&2
  exit 2
fi
if ! command -v xcrun >/dev/null || ! xcrun --find swift >/dev/null 2>&1; then
  printf '%s\n' 'Swift/Xcode tools are missing. Install Apple Xcode or Command Line Tools manually and try again. This script installs nothing.' >&2
  exit 2
fi
CONFIGURATION="${CONFIGURATION:-release}"
case "$CONFIGURATION" in release|debug) ;; *) echo 'CONFIGURATION must be release or debug.' >&2; exit 2;; esac
mkdir -p dist test-results
xcrun swift --version > test-results/mac-toolchain.txt
xcrun --sdk macosx --show-sdk-version >> test-results/mac-toolchain.txt
# There are no third-party Swift packages to resolve.
xcrun swift build -c "$CONFIGURATION" --product ChatDesk 2>&1 | tee test-results/mac-build.txt
BIN_DIR="$(xcrun swift build -c "$CONFIGURATION" --show-bin-path)"
[[ -x "$BIN_DIR/ChatDesk" ]] || { echo 'The build did not produce a ChatDesk executable.' >&2; exit 1; }
STAGE="$(mktemp -d "/private/tmp/chatpretzel-build.XXXXXX")"
trap '[[ -n "${STAGE:-}" && -d "$STAGE" ]] && rm -rf -- "$STAGE"' EXIT
APP="$STAGE/ChatPretzel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ChatDesk" "$APP/Contents/MacOS/ChatPretzel"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp -R Sources/ChatDeskMac/Resources "$APP/Contents/Resources/ChatDeskAssets"
xcrun swift scripts/make-icon.swift "$STAGE/AppIcon.iconset" "$ROOT/Packaging/ChatPretzelIconSource.png"
/usr/bin/iconutil -c icns "$STAGE/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)"
/usr/libexec/PlistBuddy -c "Add :ChatDeskBuildID string $BUILD_ID" "$APP/Contents/Info.plist"
# ZIP/Finder metadata is not app content and can make codesign reject an otherwise valid bundle.
# Remove it only from the newly staged app; source files and installed apps are untouched.
/usr/bin/xattr -cr "$APP"
# Code-sign ONLY the new local build. No installed application or global security setting is changed.
IDENTITY="${CODE_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$IDENTITY" --options runtime \
  --entitlements Packaging/ChatDesk.entitlements "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
CHATPRETZEL_APP_PATH="$APP" bash scripts/verify-app.sh
if [[ -e "$ROOT/dist/ChatPretzel.app" ]]; then
  BACKUP="$ROOT/dist/ChatPretzel.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "$ROOT/dist/ChatPretzel.app" "$BACKUP"
  printf 'Previous local build saved at: %s\n' "$BACKUP"
fi
mv "$APP" "$ROOT/dist/ChatPretzel.app"
/usr/bin/xattr -cr "$ROOT/dist/ChatPretzel.app"
printf '\nBuilt locally: %s\n' "$ROOT/dist/ChatPretzel.app"
if [[ "$IDENTITY" == '-' ]]; then
  echo 'Signing: local ad hoc. Not signed with Apple Developer ID and not notarized.'
fi
echo 'Live ChatGPT compatibility and Finder/Mail attachment paste remain separate tests.'
echo 'Launch with: open dist/ChatPretzel.app'
