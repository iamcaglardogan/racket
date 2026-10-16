# Changelog

Changes are grouped by preview/release. A local preview is not a published, Apple-notarized release.

## [0.1.0] — Local preview, 2026-10-16

### Added

- Native SwiftUI overview, cleanup review, creative status, storage explorer, application inventory, recovery and settings views, plus onboarding and an optional menu bar item.
- Explicit file selection, search/category filters, full-path cleanup confirmation, exclusions and visible skipped/incomplete scan details.
- Three enabled developer rules in bundled document 1.2.0: Homebrew downloads older than 120 days, npm's exact `_cacache` older than 30 days, and Xcode's exact `ModuleCache.noindex` older than 30 days. All require fresh producer observations.
- Real isolated npm, Homebrew and Clang regeneration evidence, with preserved fixtures, recorded hashes and a replayable harness. No owner's cache was cleaned to establish this evidence.
- Two narrow compiled cache roots, adversarial boundary coverage, and integration checks for actual bundled-rule scan → reviewed fixture Trash → authenticated undo.
- Read-only filesystem capacity reporting and bounded folder exploration, with allocation semantics, drilldown, visible partial coverage and Reveal in Finder.
- Conservative application-bundle inventory, explicit whole-tree removal review, app-specific authenticated sessions and app undo. Linked/shared/unsupported bundles, other owners, system/self apps and uncertain/running process states are refused.
- Optional daily, three-day and weekly **scan-only** scheduling while the app is open, local review notifications and the standard macOS open-at-login control.
- Debug-only isolated product verification workspace. Release packaging rejects inclusion of its fixture entry point and synthetic rule.
- Local ad-hoc packaging and verification for universal app/ZIP/DMG output, archive SHA-256 checksums, extracted-bundle content manifests and explicit signing status.
- A separate Developer ID/notarization workflow that requires real installed signing credentials, plus an unreleased Homebrew cask template. No public release or working cask install command is claimed.

### Changed

- Product status now reflects a usable local preview instead of an empty app target. Feature and safety documentation distinguishes actual capabilities from deferred work.
- `RuleSet.bundled()` applies the current-user compiled policy; `filtered(modules:)` can only narrow an already validated document.
- Ordinary file cleanup and reviewed application-directory removal have separate authority and undo paths. No general directory-cleanup capability was added.
- The owner's October 15 full-flow delegation supersedes earlier phase approval stops for this development run. Verification, safety boundaries and credential requirements remain in force.

### Verification and limits

- Recorded integrated checks passed 345 Core tests in SwiftPM/Xcode and 3 Xcode app-flow tests; focused rule/path/producer/integration checks earlier passed 94 tests. Final build, UI and package evidence is recorded in [VERIFICATION-2026-10-16.md](docs/VERIFICATION-2026-10-16.md).
- Camera Raw remains disabled and unverified. Broader creative caches, live project resolution, general system/log sweeps, exhaustive app leftovers, snapshots and a shipping CLI are unavailable.
- No valid Developer ID identity is available in the implementation environment. Local packages are ad-hoc signed and not Apple notarized; publication and Homebrew distribution remain unavailable.
- macOS 14 runtime, Intel runtime, genuine cloud-provider behavior and live application-bundle Foundation Trash integration remain separately unverified. Building universal slices does not establish runtime coverage.

## Historical foundation — through 2026-09-17

- Established the MIT-licensed RACKET identity, `io.github.iamcaglardogan.racket`, XcodeGen project, SwiftPM core, CI and ten-point safety contract.
- Added strict declarative rule validation, duplicate-key rejection, compiled Caches/Logs policy, metadata-only no-follow `PathGuard`, and 10,000 generated adversarial paths.
- Added bounded bulk scanning, dataless gates, materialization-policy restoration, observed allocated-size accounting, age/backup filters, deterministic overlap/hard-link deduplication and cancellation.
- Added serial reviewed-file removal, private staging, authenticated persistent journals, failure-state handling and exclusive no-overwrite undo.
- Added pure creative grouping and retained producer guards; Camera Raw was recorded as a disabled candidate in document 1.1.0.
- Historical CI passed 62 tests in Phase 1, 146 in Phase 2, 226 in Phase 3 and 281 in Phase 4, in both SwiftPM and Xcode. Phases 1–3 were accepted and merged. Phase 4's ordinary-file live Foundation Trash/public-undo round trip also passed on a disposable hosted VM. These results do not validate later preview changes; source references are retained in [TESTING.md](docs/TESTING.md).
