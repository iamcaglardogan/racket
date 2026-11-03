# Build and distribution

RACKET requires macOS 14 or later and is built for Apple Silicon and Intel.
Local packaging and public distribution have distinct signing requirements.

## Verified local packages

Build Release first, then package the resulting app:

```sh
make build CONFIGURATION=Release
make package APP_PATH="$(pwd)/build/DerivedData/Build/Products/Release/RACKET.app"
```

`APP_PATH` can point to a separately built Release bundle. `OUTPUT_DIR` optionally
selects an empty destination. Otherwise each run creates a fresh dated directory
under `dist/`. Existing outputs are never overwritten and source bundles are not
modified. Temporary staging and verification directories are preserved under the
system temporary directory.

The local package contains:

- An ad-hoc signed `RACKET.app`.
- A universal ZIP and compressed DMG with an Applications shortcut.
- `SHA256SUMS` for the exact archive bytes.
- `BUNDLE-MANIFEST.json` for file hashes, permissions, and symlink targets inside the app.
- `DISTRIBUTION.txt`, which records the actual signing status.
- `INSTALLATION-CHECK.json`, `ZIP-INSTALLATION-CHECK.json`, and
  `DMG-INSTALLATION-CHECK.json`, which record successful bundled-rule loading in
  the copied app and both archive copies.

An ad-hoc signature verifies the integrity of this local copy. It does **not**
identify an Apple Developer ID publisher and is **not** Apple notarization.
Gatekeeper can prevent a downloaded local build from launching. Do not describe
these artifacts as a signed, notarized public release or as Homebrew-installable.

The packaging script verifies both `arm64` and `x86_64` slices in the app and
embedded frameworks, minimum macOS 14, strict code signatures, and absence of the
Debug-only fixture argument and fixture rule. It extracts the ZIP, mounts the DMG
read-only, checks their signatures, and compares both extracted bundles against
the same manifest. It also executes each trusted app's `--verify-installation`
entry point, which loads bundled rules and plist values and exits before starting
windows, scanning, journals, preferences, or networking. Each diagnostic must
report success with matching app metadata, disabled telemetry, and a nonempty
unique set of enabled rules. SHA-256 checks prove the integrity of these artifacts, not
byte-for-byte reproducibility across builds: signing timestamps and disk-image
metadata can differ.

Repeat verification with:

```sh
bash scripts/verify-package.sh /absolute/package-directory/RACKET.app /absolute/package-directory
```

For a notarized release, append `--require-notarized` to the verification command.

## Developer ID and Apple notarization

`make release` requires an installed, valid **Developer ID Application** signing
identity and an existing `notarytool` keychain profile. It fails before producing
a release if either is missing. Credentials are never created, guessed, written
into source, or passed as passwords on command lines.

```sh
DEVELOPER_ID_IDENTITY="Developer ID Application: Your Legal Name (TEAMID)" \
NOTARIZATION_PROFILE="your-existing-keychain-profile" \
make release APP_PATH="/absolute/path/to/Release/RACKET.app"
```

The release operation signs embedded frameworks and the app with hardened runtime
and a secure timestamp. It submits the app to Apple, requires an `Accepted`
response, staples the ticket, creates final ZIP/DMG archives, then signs, notarizes,
and staples the DMG. It validates tickets and Gatekeeper acceptance as well as the
same archive integrity checks used for local packaging. Accepted notarization
metadata is retained as `NOTARIZATION.json`; the keychain profile remains local.

This process produces local artifacts. It does not publish to GitHub, create a
release tag, upload an app, or submit anything to the Mac App Store. A public
release additionally needs the release notes, a verified public download, and a
published license/source link.

## Homebrew

`packaging/Homebrew/racket.rb` is an **unreleased template**. No working
`brew install --cask racket` command is claimed. Before publication, replace the
version and checksum with the final notarized ZIP values, verify the public URL,
and run the Homebrew cask checks in the intended tap. Keep recovery journals and
user exclusions during uninstall; the template supplies no destructive zap rule.

## Current environment

The implementation environment has no valid code-signing identities. It can
produce verified local ad-hoc packages. Developer ID distribution and Apple
notarization require the owner's real Apple Developer credentials and remain
explicitly unavailable until those credentials are supplied.
