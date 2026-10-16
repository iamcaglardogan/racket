#!/bin/bash
set -euo pipefail
[[ $# -ge 1 && $# -le 3 ]] || { printf '%s\n' 'Usage: verify-package.sh RACKET.app [package-directory] [--require-notarized]' >&2; exit 2; }
app_path="$1"
package_dir="${2:-}"
require_notarized="${3:-}"
[[ -z "$require_notarized" || "$require_notarized" == --require-notarized ]] || { printf '%s\n' 'Unknown verification option.' >&2; exit 2; }
[[ -d "$app_path/Contents/MacOS" && ! -L "$app_path" ]] || { printf '%s\n' 'Expected a real application bundle.' >&2; exit 1; }
app_path="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"
plist="$app_path/Contents/Info.plist"
/usr/bin/plutil -lint "$plist" >/dev/null
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
[[ "$executable" == RACKET ]] || { printf '%s\n' 'Unexpected app executable.' >&2; exit 1; }
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
[[ "$minimum" == 14.0 || "$minimum" == 14.0.0 ]] || { printf 'Expected macOS 14.0 minimum; observed %s\n' "$minimum" >&2; exit 1; }
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
[[ "$identifier" == *.racket ]] || { printf '%s\n' 'Unexpected bundle identifier.' >&2; exit 1; }
verify_architectures() {
  local architectures
  architectures="$(/usr/bin/lipo "$1" -archs)"
  [[ " $architectures " == *' arm64 '* && " $architectures " == *' x86_64 '* ]] || {
    printf 'Both arm64 and x86_64 are required in %s; observed %s\n' "$1" "$architectures" >&2; exit 1;
  }
}
verify_architectures "$app_path/Contents/MacOS/$executable"
for framework in "$app_path"/Contents/Frameworks/*.framework; do
  [[ -d "$framework" ]] || continue
  framework_executable="$(basename "$framework" .framework)"
  verify_architectures "$framework/$framework_executable"
done
# Do not distribute the Debug-only fixture entry point or synthetic test rule.
for binary in "$app_path/Contents/MacOS/$executable" "$app_path"/Contents/Frameworks/*.framework/*; do
  [[ -f "$binary" ]] || continue
  if /usr/bin/grep -aEq -- '--verification-fixtures|racket\.verification|/private/tmp/RACKET-UI-' "$binary"; then
    printf 'Debug verification code was found in %s\n' "$binary" >&2; exit 1
  fi
done
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
verify_installation() {
  local bundle="$1"
  local receipt="${2:-}"
  local diagnostic
  diagnostic="$(mktemp -d "${TMPDIR:-/private/tmp}/racket-installation-check.XXXXXX")/result.json"
  # This trusted app entry point only loads its bundled rules and plist. It
  # exits before windows, scanning, journals, preferences, or network access.
  "$bundle/Contents/MacOS/RACKET" --verify-installation > "$diagnostic"
  /usr/bin/python3 - "$diagnostic" "$bundle/Contents/Info.plist" "$receipt" <<'PY'
import json, pathlib, plistlib, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
with open(sys.argv[2], "rb") as stream:
    info = plistlib.load(stream)
rules = result.get("enabledRules")
if (result.get("status") != "pass" or result.get("bundleIdentifier") != info.get("CFBundleIdentifier")
        or result.get("version") != info.get("CFBundleShortVersionString")
        or result.get("minimumMacOS") != "14.0" or result.get("telemetry") is not False
        or not isinstance(result.get("ruleSetVersion"), str) or not result["ruleSetVersion"]
        or not isinstance(rules, list) or not rules or not all(isinstance(rule, str) for rule in rules)
        or len(set(rules)) != len(rules)):
    raise SystemExit("Bundle installation diagnostic did not pass all required checks")
if sys.argv[3]:
    receipt = pathlib.Path(sys.argv[3])
    if receipt.exists():
        if json.loads(receipt.read_text()) != result:
            raise SystemExit("Existing installation receipt disagrees with the verified bundle")
    else:
        receipt.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print("Bundle installation check passed:", info["CFBundleIdentifier"], "rules", result["ruleSetVersion"], "enabled", len(rules))
print("Diagnostic receipt:", sys.argv[3] or sys.argv[1])
PY
}
verify_installation "$app_path"
if [[ "$require_notarized" == --require-notarized ]]; then
  signature="$(/usr/bin/codesign -dvv "$app_path" 2>&1)"
  [[ "$signature" == *'Authority=Developer ID Application:'* && "$signature" == *'(runtime)'* ]] || {
    printf '%s\n' 'Expected Developer ID signing and hardened runtime.' >&2; exit 1;
  }
  /usr/bin/xcrun stapler validate "$app_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
fi

if [[ -n "$package_dir" ]]; then
  [[ -d "$package_dir" ]] || { printf '%s\n' 'Package directory does not exist.' >&2; exit 1; }
  package_dir="$(cd "$package_dir" && pwd)"
  verify_installation "$app_path" "$package_dir/INSTALLATION-CHECK.json"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  suffix=-local
  [[ "$require_notarized" != --require-notarized ]] || suffix=
  artifact_name="RACKET-$version-macOS$suffix"
  /usr/bin/python3 - "$package_dir" "$artifact_name" <<'PY'
import hashlib, pathlib, posixpath, re, stat, sys, zipfile
root, artifact = pathlib.Path(sys.argv[1]), sys.argv[2]
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()
expected = {artifact + ".zip", artifact + ".dmg"}
seen = set()
for line in (root / "SHA256SUMS").read_text().splitlines():
    match = re.fullmatch(r"([a-f0-9]{64})  ([A-Za-z0-9.+-]+)", line)
    if not match or match[2] not in expected or match[2] in seen:
        raise SystemExit("Malformed, duplicate, or unexpected archive checksum entry")
    seen.add(match[2])
    actual = digest(root / match[2])
    if actual != match[1]:
        raise SystemExit("Archive checksum mismatch: " + match[2])
if seen != expected:
    raise SystemExit("An expected archive checksum is missing")
with zipfile.ZipFile(root / (artifact + ".zip")) as archive:
    for item in archive.infolist():
        path = pathlib.PurePosixPath(item.filename)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] not in {"RACKET.app", "__MACOSX"}:
            raise SystemExit("Unsafe path in ZIP archive")
        if stat.S_ISLNK(item.external_attr >> 16):
            target = archive.read(item).decode("utf-8")
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(item.filename), target))
            if resolved != "RACKET.app" and not resolved.startswith("RACKET.app/"):
                raise SystemExit("A ZIP symlink escapes the application bundle")
print("ZIP and DMG SHA-256 checksums passed.")
PY
  work="$(mktemp -d "${TMPDIR:-/private/tmp}/racket-verify.XXXXXX")"
  mkdir "$work/zip" "$work/dmg"
  /usr/bin/ditto -x -k "$package_dir/$artifact_name.zip" "$work/zip"
  /usr/bin/hdiutil verify "$package_dir/$artifact_name.dmg"
  mounted=false
  detach_image() { if [[ "$mounted" == true ]]; then /usr/bin/hdiutil detach "$work/dmg" >/dev/null || true; fi; }
  trap detach_image EXIT
  /usr/bin/hdiutil attach "$package_dir/$artifact_name.dmg" -readonly -nobrowse -mountpoint "$work/dmg" >/dev/null
  mounted=true
  [[ -L "$work/dmg/Applications" && "$(readlink "$work/dmg/Applications")" == /Applications ]] || {
    printf '%s\n' 'Disk image is missing the expected Applications shortcut.' >&2; exit 1;
  }
  /usr/bin/python3 - "$package_dir/BUNDLE-MANIFEST.json" "$app_path" "$work/zip/RACKET.app" "$work/dmg/RACKET.app" <<'PY'
import hashlib, json, os, pathlib, sys
expected = json.load(open(sys.argv[1], encoding="utf-8"))
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()
if not expected:
    raise SystemExit("Bundle manifest must not be empty")
for root in map(pathlib.Path, sys.argv[2:]):
    if not root.is_dir() or root.is_symlink():
        raise SystemExit("An archive does not contain the expected RACKET.app")
    actual = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = pathlib.Path(base) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                actual[relative] = {"kind": "symlink", "target": os.readlink(path)}
            elif path.is_file():
                actual[relative] = {"kind": "file", "sha256": digest(path), "mode": path.stat().st_mode & 0o777}
            elif path.is_dir():
                actual[relative] = {"kind": "directory", "mode": path.stat().st_mode & 0o777}
    if actual != expected:
        raise SystemExit("Bundle contents differ from the manifest: " + str(root))
    print("Bundle contents match:", root)
PY
  /usr/bin/codesign --verify --deep --strict "$work/zip/RACKET.app"
  /usr/bin/codesign --verify --deep --strict "$work/dmg/RACKET.app"
  verify_installation "$work/zip/RACKET.app" "$package_dir/ZIP-INSTALLATION-CHECK.json"
  verify_installation "$work/dmg/RACKET.app" "$package_dir/DMG-INSTALLATION-CHECK.json"
  if [[ "$require_notarized" == --require-notarized ]]; then
    /usr/bin/codesign --verify --strict "$package_dir/$artifact_name.dmg"
    /usr/bin/xcrun stapler validate "$package_dir/$artifact_name.dmg"
  fi
  /usr/bin/hdiutil detach "$work/dmg" >/dev/null
  mounted=false
  trap - EXIT
fi
printf '%s\n' 'Verified: universal binaries, minimum macOS 14, valid signatures, bundled rule loading, and no Debug verification entry point.'
