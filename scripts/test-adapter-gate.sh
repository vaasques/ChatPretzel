#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# No XCTest dependency, web page, window, or clipboard access.
xcrun swift build --product ChatDesk
BIN_DIR="$(xcrun swift build --show-bin-path)"
mkdir -p test-results
xcrun swiftc -parse-as-library -I "$BIN_DIR/Modules" \
  Tests/Native/WebAdapterGateHarness.swift \
  "$BIN_DIR"/ChatDeskCore.build/*.swift.o \
  "$BIN_DIR"/ChatDeskMac.build/*.swift.o \
  -framework AppKit -framework WebKit -framework Carbon \
  -framework UniformTypeIdentifiers -framework NaturalLanguage \
  -o test-results/web-adapter-gate-test
test-results/web-adapter-gate-test | tee test-results/web-adapter-gate-test.txt
