#!/bin/bash
set -euo pipefail
printf 'System: '; uname -s
printf 'Processor architecture: '; uname -m
if [[ "$(uname -s)" == Darwin ]]; then
  sw_vers
  printf 'Physical RAM (bytes): '; sysctl -n hw.memsize
  xcrun swift --version
  xcrun --sdk macosx --show-sdk-version
else
  swift --version
  echo 'AppKit/WebKit SDK: UNAVAILABLE. Only platform-independent tests can run.'
fi
