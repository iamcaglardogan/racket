# Project decisions

## Current direction and authorization

- Product: **RACKET**, a free, MIT-licensed native macOS storage and reviewed-cleanup utility by El Chedo Production.
- Repository: `iamcaglardogan/racket`; application identifier: `io.github.iamcaglardogan.racket`. Product identity is separate from the original workspace folder name.
- Platform: Swift 6 strict concurrency and SwiftUI; deployment target macOS 14.0. No third-party application/core runtime dependencies.
- Privacy: no application network requests, telemetry, crash uploads or accounts in 0.1.0. There is no update check. Explicit source links open the user's browser.
- Creative priorities remain Resolve, After Effects and Photoshop, but no unsupported cleanup scope is enabled merely to match competitors.
- On **October 15, 2026**, the owner delegated completion of the entire flow and its verification. This supersedes earlier phase-by-phase approval stops for this run. It does not waive safety invariants or supply Apple signing credentials.

## Local preview scope

Version 0.1.0 implements a main window for storage overview, cleanup review, creative status, storage exploration, application inventory/removal review, recovery and settings. [DESIGN.md](../DESIGN.md) records the calm paper/burgundy direction. Paths, allocation, reasons, regeneration costs and skipped/incomplete coverage are part of review; there are no health scores or speed-up promises.

Selection is initially empty. Search/category filters can hide selected files, so the confirmation shows every selected path. Exclusions keep paths out of cleanup. Ordinary removals are batched into at most 256 observed files per Core transaction; each batch has its own authenticated session. Cleanup changes require a fresh scan before further selection.

Optional scheduling is **scan-only**, with daily/three-day/weekly intervals while RACKET is open. Missed work becomes due on a later launch. Notifications announce files to review; neither scheduling nor menu-bar operation selects or removes files. Open-at-login uses the standard macOS service.

There is no shipping CLI, standing automatic-removal approval, general log/system sweep, duplicate finder, snapshot management, Docker/simulator pruning, malware scanner, RAM cleaner or privileged helper in this preview.

## Cleanup authority and verification

The fixed bundled schema-1 document is version **1.2.0**, with exactly three enabled developer rules:

| Scope | Age | Reason for the narrow boundary |
| --- | --- | --- |
| Homebrew `Library/Caches/Homebrew/downloads` | More than 120 days | Download archives only; no installed formulae/configuration |
| npm `.npm/_cacache` | More than 30 days | Content-addressed package cache only; no `.npmrc`, `_npx`, source or project dependencies |
| Xcode `Library/Developer/Xcode/DerivedData/ModuleCache.noindex` | More than 30 days | Generated compiler modules only; no package checkouts, project DerivedData, archives or simulators |

Primary documentation plus isolated real npm/Homebrew/Clang regeneration checks support these declarations. [RULE-VERIFICATION.md](RULE-VERIFICATION.md) records versions, commands, hashes and limits. Cache refill can still require an available source/network/credentials; file age is modification age, not proof that data is unused.

Compiled roots remain independent of JSON. Two exact roots supplement Caches/Logs: npm `_cacache` and Xcode `ModuleCache.noindex`. Every declaration, even disabled ones, passes the same protected-name policy. A root may be enumerated but cannot itself be a removal candidate. `RuleSet.bundled()` applies current-user policy; `filtered(modules:)` only narrows a validated snapshot.

All enabled rules require fresh supported-producer observations. Findings retain that producer set; changed rules cannot remove its guard without invalidating review. Running or unknown activity blocks the category. Executable-name/bundle-family checks are conservative observations, not an application lock or complete helper catalogue.

Camera Raw remains disabled and unverified. Creative grouping preserves explicit provenance and byte-exact identities but does not discover live projects. Prior settings observations establish configured parents only; mixed creative cache/project paths do not establish content boundaries. [CREATIVE-CACHE.md](CREATIVE-CACHE.md) retains that evidence.

## Storage and application management

Storage inspection uses a separate read-only API for a chosen folder. It grants no deletion authority. Explorer bounds, package/link/cloud skips and partial coverage remain visible. Physical filesystem free space is distinct from Apple's potentially purgeable availability estimates. Allocation does not establish unique APFS extents or guaranteed reclaimed bytes. See [STORAGE.md](STORAGE.md).

Application management is a conservative reviewed bundle move. Discovery reads bounded metadata under normal app locations. Removal accepts only eligible current-user-owned `.app` trees under `/Applications` or `~/Applications`, with complete descendant checks and repeated activity observations. System/self apps and linked/shared/dataless/protected/unsupported trees are refused. Common symlinked frameworks therefore remain ineligible.

App directories have separate authority, staging, authenticated `application-removal-v1` sessions and app-specific undo. They do not weaken file-only ordinary cleanup. Preferences, licences, related caches, application support, vendor services and exhaustive leftovers are retained. See [APPLICATIONS.md](APPLICATIONS.md).

## Journaling and residual risk

Removal/recovery actors keep filesystem operations synchronous inside the no-materialization scope. Durable prepared/staged records precede Foundation Trash; its verified returned path is then recorded. Undo authenticates the session and requires the exact recorded object, using exclusive no-overwrite moves and no missing-parent creation or cross-volume copy fallback.

HMAC-SHA256 journals use Apple's CryptoKit and private local storage. They detect corruption/changes without the key, not same-user forgery, confidentiality or truncation to an authenticated prefix. Same-user interference and Foundation's final pathname race remain. A failed final record can require manual recovery; matching filenames never justify guessing a destination. [REMOVAL.md](REMOVAL.md) describes those states.

## Distribution and evidence

The implementation environment has no valid Developer ID signing identity. Local packaging uses ad-hoc signatures, universal ZIP/DMG archives, exact-byte checksums and extracted-bundle manifests. It is explicitly labelled a **local preview**, not Apple notarized or Homebrew-installable. A credential-gated notarization workflow and cask template are implemented, but have no successful public-release claim. See [DISTRIBUTION.md](DISTRIBUTION.md).

Recorded integrated checks passed 345 Core tests in SwiftPM/Xcode plus 3 Xcode app-flow tests. Final checks for the exact app/package belong in [VERIFICATION-2026-10-16.md](VERIFICATION-2026-10-16.md). Local observations reported macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4 and Apple Clang 21. These do not establish macOS 14/Intel runtime, genuine cloud providers or live app-bundle Trash behavior. Native controls, accessibility labels and Command-1–7/R/F shortcuts are implemented; test-host rendering is not pointer/VoiceOver or compliance verification.

Historical accepted Phases 1–3 built the rule/path, scanner and ordinary-file transaction foundations. Phase 4 added producer checks and pure creative grouping. Historical CI counts progressed through 62, 146, 226 and 281 tests, with the ordinary-file live Foundation round trip passing in the hosted disposable account. These are historical baselines, not tests of the later preview. [TESTING.md](TESTING.md) preserves their source links and scope.
