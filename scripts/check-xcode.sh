#!/bin/bash
set -euo pipefail

if ! /usr/bin/xcrun xcodebuild -version >/dev/null 2>&1; then
  printf '%s\n' \
    'A full Xcode installation is required for the macOS app and Xcode tests.' \
    'Install Xcode, complete its first-launch setup, then select it in Xcode > Settings > Locations.' \
    'With Command Line Tools only, use make core-build to compile the headless core.' >&2
  exit 1
fi

swift_version="$(/usr/bin/xcrun swift -version)"
if [[ ! "$swift_version" =~ Swift\ version\ ([6-9]|[1-9][0-9])\. ]]; then
  printf '%s\n' 'RACKET requires Swift 6 or later. Select a supported Xcode installation.' >&2
  exit 1
fi
