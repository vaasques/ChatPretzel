#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p test-results
# The filter avoids desktop GUI tests on a Mac; Linux only has the core target.
swift test --filter 'NavigationTests|PermitTests|FileSelectionTests|LocalStoreTests|DraftAndTemplateTests' 2>&1 | tee test-results/core-tests.txt
if command -v node >/dev/null; then
  node --test Tests/Web/adapter.test.mjs 2>&1 | tee test-results/adapter-tests.txt
else
  echo 'NOT RUN: Node is unavailable. It is needed only for JavaScript development tests, not for the app.' | tee test-results/adapter-tests.txt
fi
