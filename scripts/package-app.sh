#!/bin/bash
set -euo pipefail

usage() { printf '%s\n' 'Usage: package-app.sh /path/to/Release/RACKET.app [output-directory]' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$1"
output_dir="${2:-$script_root/dist/local-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ -d "$source_app/Contents/MacOS" && ! -L "$source_app" ]] || { printf '%s\n' 'A real Release .app bundle is required.' >&2; exit 1; }
source_app="$(cd "$(dirname "$source_app")" && pwd)/$(basename "$source_app")"
identity="${RACKET_PACKAGE_IDENTITY:--}"
notary_profile="${RACKET_PACKAGE_NOTARY_PROFILE:-}"
mode=local
suffix=-local
if [[ "$identity" != - ]]; then
  [[ "$identity" == 'Developer ID Application: '* && -n "$notary_profile" ]] || {
    printf '%s\n' 'Developer ID packaging requires a Developer ID Application identity and a notarization keychain profile.' >&2; exit 1;
  }
  mode=notarized
  suffix=
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+-][A-Za-z0-9.-]+)?$ ]] || { printf '%s\n' 'The app requires a safe semantic release version.' >&2; exit 1; }
artifact_name="RACKET-$version-macOS$suffix"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
for reserved in RACKET.app "$artifact_name.zip" "$artifact_name.dmg" SHA256SUMS BUNDLE-MANIFEST.json DISTRIBUTION.txt NOTARIZATION.json INSTALLATION-CHECK.json ZIP-INSTALLATION-CHECK.json DMG-INSTALLATION-CHECK.json; do
  [[ ! -e "$output_dir/$reserved" && ! -L "$output_dir/$reserved" ]] || {
    printf 'Refusing to overwrite existing output: %s\n' "$output_dir/$reserved" >&2; exit 1;
  }
done
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/racket-package.XXXXXX")"
stage_app="$stage/RACKET.app"
printf 'Packaging a copy in %s\n' "$stage"
/usr/bin/ditto "$source_app" "$stage_app"

sign_options=(--force --sign "$identity")
if [[ "$mode" == notarized ]]; then sign_options+=(--options runtime --timestamp)
else sign_options+=(--timestamp=none)
fi
# Sign embedded code explicitly before signing the outer bundle. A new helper
# type must be added here deliberately; strict verification rejects omissions.
for embedded in "$stage_app"/Contents/Frameworks/*.framework "$stage_app"/Contents/Frameworks/*.dylib; do
  [[ -e "$embedded" ]] || continue
  /usr/bin/codesign "${sign_options[@]}" "$embedded"
done
/usr/bin/codesign "${sign_options[@]}" --entitlements "$script_root/RACKET/Resources/RACKET.entitlements" "$stage_app"
bash "$script_root/scripts/verify-package.sh" "$stage_app"

notarize() {
  local submission="$1"
  local response="$2"
  /usr/bin/xcrun notarytool submit "$submission" --keychain-profile "$notary_profile" --wait --output-format json > "$response"
  /usr/bin/python3 - "$response" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
if result.get("status") != "Accepted":
    raise SystemExit("Notarization was not accepted; packaging stopped. Inspect the preserved response.")
print("Apple notarization accepted:", result.get("id", "unknown submission"))
PY
}

if [[ "$mode" == notarized ]]; then
  /usr/bin/ditto -c -k --keepParent "$stage_app" "$stage/app-submission.zip"
  notarize "$stage/app-submission.zip" "$stage/app-notarization.json"
  /usr/bin/xcrun stapler staple "$stage_app"
  /usr/bin/xcrun stapler validate "$stage_app"
fi

/usr/bin/ditto "$stage_app" "$output_dir/RACKET.app"
/usr/bin/ditto -c -k --keepParent "$stage_app" "$output_dir/$artifact_name.zip"
mkdir "$stage/dmg-root"
/usr/bin/ditto "$stage_app" "$stage/dmg-root/RACKET.app"
ln -s /Applications "$stage/dmg-root/Applications"
/usr/bin/hdiutil create -volname "RACKET $version" -srcfolder "$stage/dmg-root" -format UDZO "$output_dir/$artifact_name.dmg"
if [[ "$mode" == notarized ]]; then
  /usr/bin/codesign "${sign_options[@]}" "$output_dir/$artifact_name.dmg"
  notarize "$output_dir/$artifact_name.dmg" "$stage/dmg-notarization.json"
  /usr/bin/xcrun stapler staple "$output_dir/$artifact_name.dmg"
  /usr/bin/ditto "$stage/dmg-notarization.json" "$output_dir/NOTARIZATION.json"
fi

/usr/bin/python3 - "$output_dir" "$artifact_name" "$mode" "$version" <<'PY'
import hashlib, json, os, pathlib, sys
out, artifact, mode, version = pathlib.Path(sys.argv[1]), *sys.argv[2:]
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()
def bundle_manifest(root):
    entries = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = pathlib.Path(base) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                entries[relative] = {"kind": "symlink", "target": os.readlink(path)}
            elif path.is_file():
                entries[relative] = {"kind": "file", "sha256": digest(path), "mode": path.stat().st_mode & 0o777}
            elif path.is_dir():
                entries[relative] = {"kind": "directory", "mode": path.stat().st_mode & 0o777}
    return entries
(out / "BUNDLE-MANIFEST.json").write_text(json.dumps(bundle_manifest(out / "RACKET.app"), sort_keys=True, indent=2) + "\n")
lines = []
for suffix in ("zip", "dmg"):
    name = artifact + "." + suffix
    lines.append(digest(out / name) + "  " + name)
(out / "SHA256SUMS").write_text("\n".join(lines) + "\n")
status = ("Developer ID signed and Apple notarized." if mode == "notarized" else
          "LOCAL BUILD: ad-hoc signed. No Developer ID identity. NOT Apple notarized. Not a public release.")
(out / "DISTRIBUTION.txt").write_text(f"RACKET {version}\n{status}\n"
    "Requires macOS 14 or later. Universal arm64 + x86_64.\n"
    "SHA256SUMS verifies these exact ZIP/DMG bytes; BUNDLE-MANIFEST.json verifies extracted bundle contents.\n"
    "Archives are not claimed byte-for-byte reproducible: signatures, timestamps, and disk-image metadata can differ.\n")
PY
if [[ "$mode" == notarized ]]; then bash "$script_root/scripts/verify-package.sh" "$output_dir/RACKET.app" "$output_dir" --require-notarized
else bash "$script_root/scripts/verify-package.sh" "$output_dir/RACKET.app" "$output_dir"
fi
printf 'Verified %s package: %s\n' "$mode" "$output_dir"
if [[ "$mode" == local ]]; then
  printf '%s\n' 'This local build is ad-hoc signed. Apple Developer ID signing and notarization remain unavailable.'
fi
