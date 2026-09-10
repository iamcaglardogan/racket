#!/bin/bash
set -euo pipefail

# This integration fixture creates a disposable OS account. It must never run
# on an owner's Mac or a self-hosted runner. CI uses an explicit macos-15 VM.
if [[ "${GITHUB_ACTIONS:-}" != "true" || "${RUNNER_ENVIRONMENT:-}" != "github-hosted" || "${RUNNER_OS:-}" != "macOS" ]]; then
  printf '%s\n' 'Live Trash integration is restricted to a disposable GitHub-hosted macOS runner.' >&2
  exit 1
fi
if [[ "$(/usr/bin/uname -s)" != "Darwin" || "$(/usr/bin/id -u)" == "0" ]]; then
  printf '%s\n' 'The fixture setup must start as the non-root GitHub runner user.' >&2
  exit 1
fi
trap 'printf "Live Trash fixture setup failed at script line %s; account and files are preserved.\n" "$LINENO" >&2' ERR

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
shopt -s nullglob
resource_accessors=("$repo_root"/.build/*/debug/RacketCore.build/DerivedSources/resource_bundle_accessor.swift)
if [[ ${#resource_accessors[@]} -ne 1 ]]; then
  printf '%s\n' 'Run the headless core build first; exactly one SwiftPM resource accessor is required.' >&2
  exit 1
fi
core_sources=()
while IFS= read -r -d '' source_path; do
  core_sources+=("$source_path")
done < <(/usr/bin/find "$repo_root/RACKET/Core" -type f -name '*.swift' -print0)
if [[ ${#core_sources[@]} -eq 0 ]]; then
  printf '%s\n' 'No core sources were found.' >&2
  exit 1
fi

fixture_uuid="$(/usr/bin/uuidgen)"
if [[ ! "$fixture_uuid" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
  printf '%s\n' 'Could not generate a fresh fixture identifier.' >&2
  exit 1
fi
fixture_root="/private/tmp/RACKET-LiveTrash-$fixture_uuid"
fixture_home="$fixture_root/Home"
fixture_token="$(printf '%s' "$fixture_uuid" | /usr/bin/tr -d '-' | /usr/bin/tr 'A-F' 'a-f')"
fixture_account="_racket_trash_${fixture_token:0:16}"
fixture_group="_racket_trash_${fixture_token:0:16}"
fixture_binary="$fixture_root/LiveTrash"

# mkdir refuses an existing fixture path. The executable includes Core
# directly and is never shipped.
/bin/mkdir -m 700 "$fixture_root"
printf 'Preserving live Trash fixture: %s\n' "$fixture_root"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -D SWIFT_PACKAGE -module-name RacketLiveTrashFixture \
  "${core_sources[@]}" "${resource_accessors[0]}" \
  "$repo_root/scripts/fixtures/LiveTrash.swift" -o "$fixture_binary"

# Resolve IDs across the search node, including system records. The UUID/name
# and ID preflight assume no concurrent account setup in this disposable job;
# dscl record creation itself is not an atomic create-if-absent operation.
# Refuse existing names and never add membership to any existing group.
user_records="$(/usr/bin/dscl /Search -list /Users UniqueID)"
group_records="$(/usr/bin/dscl /Search -list /Groups PrimaryGroupID)"
if printf '%s\n%s\n' "$user_records" "$group_records" | /usr/bin/awk -v name="$fixture_account" '$1 == name { found = 1 } END { exit !found }'; then
  printf '%s\n' 'The generated account or group already exists; refusing reuse.' >&2
  exit 1
fi
fixture_id=""
for ((candidate_id = 45000; candidate_id <= 60000; candidate_id++)); do
  if ! printf '%s\n%s\n' "$user_records" "$group_records" | /usr/bin/awk -v value="$candidate_id" '$NF == value { found = 1 } END { exit !found }'; then
    fixture_id="$candidate_id"
    break
  fi
done
if [[ -z "$fixture_id" ]]; then
  printf '%s\n' 'No unused fixture UID/GID was available.' >&2
  exit 1
fi

# Only these brand-new records are written. No password is enabled, the login
# shell exits immediately, and no admin/root/existing-group membership is added.
group_record="/Groups/$fixture_group"
user_record="/Users/$fixture_account"
/usr/bin/sudo -n /usr/bin/dscl . -create "$group_record"
/usr/bin/sudo -n /usr/bin/dscl . -create "$group_record" PrimaryGroupID "$fixture_id"
/usr/bin/sudo -n /usr/bin/dscl . -create "$group_record" Password '*'
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record"
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" UniqueID "$fixture_id"
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" PrimaryGroupID "$fixture_id"
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" GeneratedUID "$fixture_uuid"
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" NFSHomeDirectory "$fixture_home"
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" UserShell /usr/bin/false
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" Password '*'
/usr/bin/sudo -n /usr/bin/dscl . -create "$user_record" IsHidden 1

if [[ "$(/usr/bin/id -u "$fixture_account")" != "$fixture_id" || "$(/usr/bin/id -g "$fixture_account")" != "$fixture_id" ]]; then
  printf '%s\n' 'The new account did not resolve to its reserved UID/GID.' >&2
  exit 1
fi
/bin/mkdir -m 700 "$fixture_home"
/usr/bin/sudo -n /usr/sbin/chown "$fixture_id:$fixture_id" "$fixture_root" "$fixture_home" "$fixture_binary"

# sudo -H obtains HOME from this account's directory-service record. The
# executable independently verifies real/effective IDs, passwd and Foundation
# home resolution before creating any data. No root or runner-user fallback.
/usr/bin/sudo -n -H -u "$fixture_account" -g "$fixture_group" -- \
  "$fixture_binary" "$fixture_home" "$fixture_id" "$fixture_id" "$fixture_account"
printf 'Live Trash integration passed; account %s and fixture %s are preserved for this VM lifetime.\n' \
  "$fixture_account" "$fixture_root"
