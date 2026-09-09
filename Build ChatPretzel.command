#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if bash scripts/build.sh; then
  echo 'The build is complete. Opening the local app bundle; no installed app is replaced.'
  open dist/ChatPretzel.app
else
  echo 'The build failed or is blocked. Keep the error output in test-results/mac-build.txt for Codex.'
  read -r -p 'Press Enter to close.' _
  exit 1
fi
