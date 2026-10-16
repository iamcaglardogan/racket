#!/bin/bash
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { printf '%s\n' 'Usage: release-app.sh /path/to/Release/RACKET.app [output-directory]' >&2; exit 2; }
[[ -n "${DEVELOPER_ID_IDENTITY:-}" && -n "${NOTARIZATION_PROFILE:-}" ]] || {
  printf '%s\n' 'No public release was produced.' \
    'Set DEVELOPER_ID_IDENTITY to an installed Developer ID Application identity and NOTARIZATION_PROFILE to an existing notarytool keychain profile.' >&2
  exit 1
}
[[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application: '* ]] || {
  printf '%s\n' 'DEVELOPER_ID_IDENTITY must name an actual Developer ID Application certificate.' >&2; exit 1;
}
identities="$(/usr/bin/security find-identity -v -p codesigning)"
if ! printf '%s\n' "$identities" | /usr/bin/grep -Fq -- "$DEVELOPER_ID_IDENTITY"; then
  printf '%s\n' 'The supplied Developer ID identity is not installed and valid in the current keychain.' >&2; exit 1
fi
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RACKET_PACKAGE_IDENTITY="$DEVELOPER_ID_IDENTITY"
export RACKET_PACKAGE_NOTARY_PROFILE="$NOTARIZATION_PROFILE"
bash "$script_root/scripts/package-app.sh" "$1" "${2:-$script_root/dist/release-$(date -u +%Y%m%dT%H%M%SZ)}"
