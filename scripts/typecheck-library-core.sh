#!/bin/bash
# Supplemental Foundation-only check. It deliberately stubs the native OS file lease.
# It is NOT a substitute for compiling ChatDeskMac with a macOS SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p test-results
swift build --target ChatDeskCore >/dev/null
BIN_DIR="$(swift build --show-bin-path)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
cat > "$WORK/FileAccessLease.swift" <<'SWIFT'
import Foundation
final class FileAccessLease {
    let url: URL
    init(_ url: URL) { self.url = url }
}
SWIFT
{
  swiftc -typecheck -swift-version 5 -I "$BIN_DIR/Modules" \
    Sources/ChatDeskMac/LibraryController.swift "$WORK/FileAccessLease.swift"
  echo 'PASS: Foundation-only library controller typecheck; FileAccessLease stubbed. NOT macOS SDK validation.'
} >test-results/library-concurrency-check.txt 2>&1
cat test-results/library-concurrency-check.txt
