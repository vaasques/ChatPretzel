#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if bash scripts/test-macos.sh; then
  echo 'Local Mac tests complete. Live tests must be run separately.'
else
  echo 'A test or build failed. Keep the log for Codex.'
fi
read -r -p 'Press Enter to close.' _
