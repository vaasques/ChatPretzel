#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if bash scripts/build.sh; then
  echo 'Bygget är klart. Öppnar det lokala app-paketet; ingen befintlig app ersätts.'
  open dist/ChatPretzel.app
else
  echo 'Bygget misslyckades eller är blockerat. Spara feltexten i test-results/mac-build.txt för Codex.'
  read -r -p 'Tryck Enter för att stänga.' _
  exit 1
fi
