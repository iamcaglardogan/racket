#!/bin/bash
set -euo pipefail

# XcodeGen is a development tool required by the build brief, never an app dependency.
# Digest source: the official 2.46.0 release asset metadata on GitHub.
version='2.46.0'
archive_sha256='4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806'
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_directory="$project_root/.tools/xcodegen-$version"
tool_binary="$tool_directory/xcodegen/bin/xcodegen"

if [[ -x "$tool_binary" ]]; then
  "$tool_binary" --version
  exit 0
fi

mkdir -p "$project_root/.tools/downloads" "$tool_directory"
# Preserve downloads on failure for inspection. This script has no cleanup/deletion command.
archive="$(mktemp "$project_root/.tools/downloads/xcodegen-$version.XXXXXX")"
curl --fail --silent --show-error --location --http1.1 --proto '=https' --tlsv1.2 \
  --connect-timeout 20 --max-time 180 --retry 2 \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" \
  --output "$archive"
printf '%s  %s\n' "$archive_sha256" "$archive" | /usr/bin/shasum -a 256 --check --status
/usr/bin/unzip -q -n "$archive" -d "$tool_directory"
"$tool_binary" --version
