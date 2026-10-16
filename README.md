# RACKET

RACKET is a free, MIT-licensed native macOS utility for understanding storage, reviewing selected cache files, and keeping a recorded way back from Trash.

**Version 0.1.0 is a local preview.** It now has a SwiftUI application, three verified developer-cache categories, reviewed cleanup and recovery, a read-only storage explorer, conservative application management, and scheduled scans. It has no telemetry, accounts, subscriptions, or application network requests.

The preview is **not Apple Developer ID signed or notarized**. Local packages use ad-hoc signatures and are distinct from a public release. There is no published Homebrew installation command. The exact verification results and package status are recorded in [the October 16 verification report](docs/VERIFICATION-2026-10-16.md).

## Build and open

Requires a full Xcode installation with a Swift 6 toolchain. The deployment target is macOS 14.0; runtime coverage on macOS 14 and Intel remains outstanding. There are no third-party dependencies in the application or core targets.

```sh
make build CONFIGURATION=Release
open build/DerivedData/Build/Products/Release/RACKET.app
```

The build prepares the pinned XcodeGen tool, generates the untracked Xcode project from `project.yml`, and builds both Apple Silicon and Intel slices. Building both slices does not establish runtime testing on both architectures.

To create local ZIP/DMG packages:

```sh
make package
```

Packages go into a fresh directory under `dist/`; existing output is never overwritten. The package includes an ad-hoc signed app, ZIP, DMG, archive checksums, a bundle-content manifest, and an explicit signing-status file. Gatekeeper may refuse a downloaded ad-hoc build. [Distribution documentation](docs/DISTRIBUTION.md) describes verification and the separate credential-gated Developer ID/notarization path.

## Use the preview

1. **Scan verified categories.** The scan reports allocated bytes, exact paths, reasons, age boundaries, skipped items and incomplete coverage. It selects and removes nothing.
2. **Choose files and review every selected path.** Search and category filters can hide selected rows; the confirmation includes the entire selected list. Exclusions keep selected paths out of cleanup.
3. **Move the reviewed selection to Trash.** Each file is rechecked immediately before mutation. Files that changed or cannot be verified are refused or skipped.
4. **Use Recovery to review results and restore.** Recovery requires the recorded object to remain verifiable at its recorded location. It never overwrites an existing destination or creates a missing original parent. Emptying Trash can make removal permanent; RACKET does not empty it.

The storage explorer measures a folder you choose and offers drilldown and Reveal in Finder. Its observations grant no cleanup authority. The storage overview distinguishes filesystem free space from storage macOS may estimate as available or purgeable. Moving files into Trash does not promise reclaimed disk space.

Application management discovers bundle metadata and can review and move a bounded subset of current-user-owned apps to Trash. System/self apps, other owners, linked or unsafe descendants, running apps and uncertain process states are protected. Common framework symlinks can make an otherwise ordinary app ineligible. Removal covers the reviewed bundle; preferences, licences, documents, related services and leftovers are retained. See [application-management boundaries](docs/APPLICATIONS.md).

Optional daily, three-day or weekly scans run while RACKET is open, including in its menu bar. Missed scans become due after reopening. Optional local notifications announce a review list. **Scheduling never selects or removes files.** Open-at-login uses the normal macOS Login Items control.

## Enabled cleanup categories

Bundled rule document **1.2.0** enables only these default locations:

| Category | Exact directory | File modification age |
| --- | --- | --- |
| Homebrew downloads | `~/Library/Caches/Homebrew/downloads` | More than 120 days |
| npm package cache | `~/.npm/_cacache` | More than 30 days |
| Xcode compiler modules | `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex` | More than 30 days |

All three require fresh supported-producer observations. Running or unknown activity blocks the category. Process checks are conservative observations, not locks against future launches. Old modification time does not establish that a file is unused.

Real Homebrew, npm and Clang producers regenerated disposable cache data in isolated fixtures, and the actual bundled rules passed scanner/removal/undo tests. [Rule verification](docs/RULE-VERIFICATION.md) records versions, primary references, hashes and limits. Clearing caches can slow a later download or build, and offline installs can fail until data is fetched again. Historical/private packages still require their original source and access to remain available.

Adobe Camera Raw remains **disabled and unverified**. Resolve, After Effects, Photoshop and broader creative-cache cleanup are unavailable. The creative page explains those boundaries; project grouping in Core is not a live project-discovery feature. General system-cache and log sweeps, broad DerivedData cleanup, Docker/simulator pruning, snapshots, orphan removal, duplicate finding and a shipping CLI are not implemented.

## Safety and privacy

- Production removal uses the sole Foundation Trash transport in `RemovalEngine`; ordinary cleanup accepts observed individual files, while app bundles use a separate reviewed tree capability.
- Compiled roots and independent protected-name checks constrain cleanup. Rule JSON cannot add roots or override protections. Preferences, known project/catalog formats, original-media/autosave names and cloud-container names remain protected.
- Metadata-only no-follow descriptors, identity checks and a synchronous no-materialization policy refuse symlinks, offline placeholders and changed objects. Real cloud-provider behavior remains unverified.
- Authenticated persistent journals record intent before moves. Recovery uses verified recorded identities and exclusive moves. Same-user interference, Foundation's final pathname race and uncertain final journal writes remain documented limits.
- No telemetry, crash uploads, health scores, RAM-cleaning or speed-up claims. Source links open the browser only when chosen.

Read [the safety contract](SAFETY.md), [scanner design](docs/SCANNING.md), [removal/recovery limits](docs/REMOVAL.md), and [storage semantics](docs/STORAGE.md).

## Development and verification

```sh
make test
make core-test
make check-policy
```

`make test` runs the Xcode safety target; `make core-test` runs the headless SwiftPM suite and requires XCTest. `make core-build` supports core compilation with suitable Swift 6 Command Line Tools. Core tests do not validate the product interface or certify a distribution package.

Final local checks passed **350 Debug Core tests, 346 Release Core tests and 5 Xcode app-flow tests**. Four Debug-only fixture tests account for the configuration difference. Both hosted CI runs passed, including actual ordinary-file and complete app-bundle Foundation Trash/public-undo round trips under a disposable account. Actual pointer checks completed isolated review/fixture-Trash/undo journeys. The verified local package is `dist/local-0.1.0-verified`; exact source, hashes and evidence are in [the dated verification report](docs/VERIFICATION-2026-10-16.md). Later changes require fresh checks.

The interface uses native controls, accessibility labels and keyboard actions. Actual pointer interaction and accessibility roles/labels were observed, including successful Command-1 navigation and Command-R scan. The Command-F menu/focus fix is implemented; its final native focus check was not completed because the Mac locked and requires manual unlock. VoiceOver and full keyboard/accessibility compliance remain unverified.

Tests and Debug UI verification use private synthetic homes and fake Trash transports with real namespace moves. No fixture scans or modifies the owner's home, installed apps, caches, real Trash or cloud data. The only live-transport fixture is separately guarded to run under a new synthetic account in a disposable GitHub-hosted macOS VM; never run its account-setup script locally.

The owner delegated completion of the full flow on October 15, 2026. The earlier phase-by-phase approval stops no longer govern this development run. That authorization does not enable unverified creative rules or supply Apple signing credentials.

See [contribution guidance](CONTRIBUTING.md), [project decisions](docs/DECISIONS.md), [private security reporting](SECURITY.md), and the [MIT license](LICENSE). Repository: [`iamcaglardogan/racket`](https://github.com/iamcaglardogan/racket). Application identifier: `io.github.iamcaglardogan.racket`.
