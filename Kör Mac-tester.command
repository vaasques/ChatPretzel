#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if bash scripts/test-macos.sh; then
  echo 'Lokala Mac-tester avslutade. Live-tester måste göras separat.'
else
  echo 'Ett test eller bygget misslyckades. Behåll loggen för Codex.'
fi
read -r -p 'Tryck Enter för att stänga.' _
