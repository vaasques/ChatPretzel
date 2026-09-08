#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'BLOCKED: AppKit-/WKWebView-tester kräver en Mac med grafisk session.' >&2; exit 2; }
mkdir -p test-results
printf '%s\n' 'Testerna öppnar en lokal WebKit-testvy. De besöker inte ChatGPT och ändrar inte det vanliga urklippet.'
xcrun swift test 2>&1 | tee test-results/macos-tests.txt
printf '\nLokala Mac-tester klara. Kör sedan det MANUELLA Finder- och ChatGPT-testet i CLIPBOARD_TESTS.md.\n'
