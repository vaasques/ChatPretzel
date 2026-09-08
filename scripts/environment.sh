#!/bin/bash
set -euo pipefail
printf 'System: '; uname -s
printf 'Processorarkitektur: '; uname -m
if [[ "$(uname -s)" == Darwin ]]; then
  sw_vers
  printf 'Fysiskt RAM (bytes): '; sysctl -n hw.memsize
  xcrun swift --version
  xcrun --sdk macosx --show-sdk-version
else
  swift --version
  echo 'AppKit/WebKit SDK: UNAVAILABLE. Endast plattformsoberoende tester kan köras.'
fi
