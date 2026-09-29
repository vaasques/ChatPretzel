#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p test-results
xcrun swiftc -parse-as-library Sources/ChatDeskMac/FileAccess.swift \
  Tests/Native/FileAccessHarness.swift -framework UniformTypeIdentifiers \
  -o test-results/file-access-test
test-results/file-access-test | tee test-results/file-access-test.txt
