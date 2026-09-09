#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'BLOCKED: AppKit/WKWebView tests require a Mac with a graphical session.' >&2; exit 2; }
mkdir -p test-results
printf '%s\n' 'The tests open a local WebKit test view. They do not visit ChatGPT or change the normal clipboard.'
xcrun swift test 2>&1 | tee test-results/macos-tests.txt
printf '\nLocal Mac tests complete. Then run the manual Finder, Mail, and ChatGPT tests.\n'
