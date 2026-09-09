# RACKET

A planned free, open-source, native macOS application for understanding disk usage and reviewing recoverable cleanup, with particular attention to creative work.

**Status: Phase 3 removal and recovery are in development; verification and owner review are pending.** RACKET lives at [`iamcaglardogan/racket`](https://github.com/iamcaglardogan/racket) and uses the owner-confirmed identifier `io.github.iamcaglardogan.racket`. Phases 1 and 2 passed CI, were accepted by the owner, and are merged through pull requests [1](https://github.com/iamcaglardogan/racket/pull/1) and [2](https://github.com/iamcaglardogan/racket/pull/2). Phase 3 adds a headless removal boundary, authenticated session records, and undo. Product views are not implemented, and no cleanup rule is enabled.

The compiled path policy currently permits only the current user's `Library/Caches` and `Library/Logs` as rule locations. It refuses the roots themselves as removal candidates and independently checks protected project formats, original-media and autosave names, preferences, cloud-container names, and `.git` paths. The bundled rule document is deliberately empty: no application cache path has been verified or enabled.

`PathGuard` walks path components through metadata-only, no-follow descriptors and records file and ancestor identities for revalidation. Phase 2 adds bounded bulk directory enumeration, regular-file findings with rule explanations, dataless metadata gates, allocated-size accounting, and cancellation. Its reported bytes are observations, not a promise of physically reclaimable space. Phase 3 rechecks an explicit reviewed selection against its scan observations and rules before moving individual files. No directory becomes a removal candidate merely because its files were scanned. See the [scanner design](docs/SCANNING.md), [removal and recovery boundaries](docs/REMOVAL.md), and [testing scope and limits](docs/TESTING.md).

## Product direction

- macOS 14.0 and later; Swift 6 with strict concurrency and SwiftUI.
- A main window for review and recovery, plus a reporting-only menu bar item.
- Creative caches grouped by project where reliable attribution is possible.
- Initial verification priorities: DaVinci Resolve, After Effects, and Photoshop.
- A calm, expressive interface with real paths, allocated sizes, readable explanations, and accessible controls.
- No dependencies in the application target.
- MIT licensed, with source and rule data available for inspection.

A shipping CLI is proposed to remain outside v1. The choice between no network access and an optional, default-off GitHub version check remains open. Telemetry is prohibited in either case.

## Safety contract

These are requirements for the implementation, not claims about a tested product. Enforcement tests are tracked in [SAFETY.md](SAFETY.md).

1. **Trash, never unlink.** All removals use `FileManager.trashItem(at:resultingItemURL:)`, exclusively through `RemovalEngine`. No other code, including tests, permanently deletes user content. The only permitted permanent-deletion exception in the brief is an explicit Empty Trash action.
2. **Allow-list, not deny-list.** Only paths inside compiled, explicitly enumerated safe roots may be removed. Everything else is refused.
3. **Symlink and TOCTOU resistance.** Resolve and validate paths, reject symlink escapes, and revalidate immediately before moving an item to Trash. Use `O_NOFOLLOW` where possible.
4. **Never touch dataless files.** Check cloud-placeholder metadata before content access or size collection; report skipped placeholders.
5. **Preferences are not junk.** Preferences may only be considered in an explicit uninstall of a specific application, never a cache sweep.
6. **No auto-delete without review.** Scheduled scans do not authorize removal. Standing approvals must identify the exact category and provide a notification and undo. Judgement items are never preselected.
7. **No telemetry, ever.** No analytics or crash reporting. Any version check must be explicitly opted into, off by default, and permanently disableable.
8. **Honest numbers only.** Report allocated size, distinguish real free space from purgeable estimates, and never promise RAM boosts or speed improvements.
9. **No fear.** No health scores, alarm counters, threat meters, or exaggerated findings.
10. **Auditable by construction.** Every finding points to a readable rule with its reason, regeneration cost, and source.

## Storage and recovery

The headless removal engine accepts an explicit selection of up to 256 observed files. It writes an authenticated session record before each move, uses a private staging location inside the existing safe root, then records the actual location returned by macOS Trash. Undo checks the recorded identity and restores to the original path without overwriting an existing item or creating missing parent directories. Missing or uncertain items require review; it never searches for a replacement by filename.

The production Trash call and real cloud providers have not been exercised by the Phase 3 fixtures. Tests use synthetic temporary homes and a fake Trash transport with real Darwin moves and journal files. The final Foundation pathname operation still has a race window, and private directory permissions do not isolate other processes running as the same user. A failed final journal write can leave a moved item without a durable Trash path. These limits are detailed in [REMOVAL.md](docs/REMOVAL.md). Recovery is unavailable once an item is no longer present at a verifiable recovery location; emptying Trash can make that permanent.

Purgeable storage is managed by macOS. It is not guaranteed free space and will not be advertised as space this application can reclaim. A planned storage panel will explain the difference between filesystem free space and Finder's more optimistic figure.

An optional Time Machine snapshot must only be described as protection after its creation succeeds. The application will not claim access to Apple's restricted snapshot entitlement.

## Development checkpoints

Each phase stops for the owner's review before the next begins:

| Phase | Deliverable | Status |
| --- | --- | --- |
| 0 | Repository structure, XcodeGen configuration, Makefile, CI, empty buildable targets | Accepted by the owner |
| 1 | PathGuard tests first, PathGuard, rule model and validation | Verified in CI; accepted by the owner and merged |
| 2 | Headless scanner and synthetic fixtures | Verified in CI; accepted by the owner and merged |
| 3 | Manifest, removal, and undo round trip | Implementation and synthetic tests added; verification and owner review pending |
| 4 | Verified creative rules and project grouping | Not started |
| 5 | Design tokens and reviewed DESIGN.md, then SwiftUI views | Not started |
| 6 | Permissions, onboarding, and menu bar | Not started |
| 7 | Uninstaller and orphan finder | Not started |
| 8 | Developer and system modules, storage and snapshots | Not started |
| 9 | Signing, notarization, release automation, Homebrew, and screenshots | Not started |

## Development

The macOS application requires a full Xcode installation with a Swift 6 toolchain and XcodeGen. Command Line Tools alone cannot build the SwiftUI application or run the Xcode test target. There are no third-party dependencies in the application or core target.

```sh
make build
make test
```

These commands generate `RACKET.xcodeproj` from `project.yml` and use the `RACKET` scheme. The generated project is not committed. Development builds do not require an Apple Developer Team ID; distribution signing is deferred to Phase 9.

For contributors with Swift 6 Command Line Tools, the headless core can be compiled separately. It uses Apple Foundation, Darwin, and CryptoKit without third-party packages:

```sh
make core-build
```

`make core-test` runs the headless XCTest suite and requires a toolchain containing XCTest, such as full Xcode. Command Line Tools installations without XCTest can run `make core-build` only. The verified Phase 2 baseline contains 146 tests, including 10,000 generated adversarial path cases. Phase 3 adds scan-observation, manifest, removal, and undo cases; its execution results are pending. Tests use synthetic paths and isolated temporary fixtures; they do not scan or mutate the real home directory or real Trash. Core tests do not validate the product interface or a live Foundation Trash round trip.

`make check-policy` checks selected destructive APIs, Trash calls outside the removal boundary, unapproved networking APIs, and UI imports in the core. CI runs this source check as an additional guardrail; pattern matching is not proof of runtime safety.

[Phase 1 CI run 34125991610](https://github.com/iamcaglardogan/racket/actions/runs/34125991610) passed its 62 tests under both SwiftPM and Xcode, the source checks, and universal app verification. [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed all 146 tests under both runners, source guardrails, and the universal app build. CI uses macOS 15 with Xcode 16.4, runs both test entry points, and checks that the Release binary contains Apple Silicon and Intel architectures. The target minimum is macOS 14; a successful macOS 15 CI run does not establish runtime compatibility on macOS 14.

The build downloads XcodeGen 2.46.0 from its official release into ignored `.tools/` storage and verifies the published SHA-256 digest before extraction. This is a development tool, not an application dependency.

`make release` deliberately refuses to create a distribution build until signing, notarization, and packaging are implemented and verified in Phase 9. There is no release, downloadable cleaner, or product screenshot yet. Each release will document its exact Xcode and Swift versions for reproducibility.

## Distribution decisions

The planned distribution is a Developer ID signed and notarized DMG on GitHub Releases, plus a Homebrew cask. Signing credentials are deferred until the owner confirms their Apple Developer membership.

There will be no Mac App Store edition. App sandbox restrictions would prevent the full cross-application cleanup and uninstall workflow; a separate reduced edition would make the safety and capability story harder to understand.

Version 1 deliberately excludes malware scanning, RAM cleaning, speed-up claims, duplicate finding, purgeable-space reclamation, and a privileged helper. Items requiring elevated privileges will be reported and skipped.

See [contribution guidance](CONTRIBUTING.md), [project decisions](docs/DECISIONS.md), [security reporting](SECURITY.md), and the [MIT license](LICENSE).
