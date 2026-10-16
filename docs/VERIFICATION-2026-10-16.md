# RACKET 0.1.0 preview verification — 16 October 2026

**Status: IN PROGRESS — final build, UI and package results have not yet been entered.** This ledger separates completed evidence from checks still being collected. User-facing dates use Europe/Istanbul; preserved log/fixture filenames may retain their UTC or initial-session date.

## Target and environment

- Product version: 0.1.0, build 1; rule document: 1.2.0.
- Application identifier: `io.github.iamcaglardogan.racket`.
- Intended artifact: local ad-hoc signed universal app, ZIP and DMG. No Developer ID/Apple-notarized public-release claim.
- Deployment target: macOS 14.0. macOS 14 and Intel runtime coverage remain unverified.
- Observed development host: macOS 27.0.1 (26A434); Xcode 27.0 (27A266a); Apple Swift 6.4 (`swiftlang-6.4.0.34.1`); Apple Clang 21.0.0 (`clang-2100.3.34.2`).
- Current environment has no valid Developer ID signing identity. Apple notarization cannot be completed without real credentials.

## Completed evidence

| Check | Recorded result | Evidence |
| --- | --- | --- |
| Initial full SwiftPM integration suite | **329 tests, zero failures** before later UI changes | `/private/tmp/RACKET-RuleTests-20261015-full.log` |
| Later integrated SwiftPM suite | **345 Core tests, zero failures**, before final sidebar polish | `/private/tmp/racket-product-core-test.log` |
| Later integrated Xcode suite | **345 Core + 3 app-flow tests passed**, before final sidebar polish | `/private/tmp/racket-product-xcode-tests.log` |
| Focused rule/path/producer/developer integration | **94 tests, zero failures** | Isolated `/private/tmp/RACKET-RuleTests-20261015` scratch output; includes actual bundled declarations |
| Initial source policy | Passed selected API/import/Trash-boundary guardrails | `scripts/check-source-policy.py`; rerun final checks below |
| Real npm regeneration | Missing blob refetched with index retained; empty `_cacache` regenerated; three offline installs matched; regenerated fixture cache verified | `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json` |
| Real Clang regeneration | One PCM regenerated; identical rebuilt executable bytes/behavior; original generated sources unchanged | Same evidence JSON |
| Real Homebrew regeneration | Actual disposable checkout refetched identical local-file formula download; no formula installed | Same evidence JSON; commit `be9411f7d2cef522201891d38260c63e66da88f7` |
| Xcode module-cache location | Disposable `-showBuildSettings` reported `<fixture>/DerivedData/ModuleCache.noindex` | `/private/tmp/RACKET-XcodeModuleLocation-20261015.log`; filtered build-setting observation recorded in RULE-VERIFICATION |
| App-management synthetic suite | 26 app tests passed in the earlier module check | `/private/tmp/RACKET-AppRemovalTests.log`; final integrated count to be entered below |
| Production app inventory smoke | Separately reported metadata-only observation: 110 discovered, 20 preliminarily eligible, 90 protected, 15 skipped/unavailable, depth limit indicated | [APPLICATIONS.md](APPLICATIONS.md); no real app removed |
| Initial local package | `dist/local-0.1.0` passed universal/signature/archive/extracted-manifest verification; final package recorded separately below | Initial verified package reported by packaging workflow; not the final app-polish artifact |
| Test-host view rendering | Seven pages rendered; 3 app-flow tests passed | Test-host screenshot evidence to be indexed below; real pointer/VoiceOver interaction not verified |

[RULE-VERIFICATION.md](RULE-VERIFICATION.md) records producer versions, hashes, exact cache scope and evidence limits. [TESTING.md](TESTING.md) records fixture and historical CI boundaries. These completed checks do not certify later implementation edits or the final archive bytes.

## Final checks to complete

<!-- Parent agent: replace PENDING entries with actual results/logs after final implementation, and remove this instruction when finalized. -->

| Check | Result | Exact evidence |
| --- | --- | --- |
| Final SwiftPM suite | **PENDING** | Enter command, count, failures and preserved log |
| Final Xcode suite | **PENDING** | Enter command, count, failures, result bundle/log |
| Final source-policy/entitlements checks | **PENDING** | Enter results and log |
| Debug build | **PENDING** | `/private/tmp/racket-product-debug.log` exists; inspect final outcome |
| Universal Release build | **PENDING** | Enter final build log and app/framework architectures |
| Debug isolated UI scan/select/confirmation/Trash/undo | **PENDING** | Enter fixture root, result details, screenshots and preserved session |
| Debug UI app review/removal/undo | **PENDING** | Enter synthetic app result and app-specific recovery evidence |
| Hidden selections, exclusions, cancellation and restore-failure UI | **PENDING** | Enter concrete observed outcomes after P2 fixes |
| Storage explorer and scheduling settings | **PENDING** | Enter observed read-only behavior and scan-only schedule verification |
| Owner-authorized production read-only scan smoke | **PENDING** | Aggregate operational result only; no personal files as fixture data, no cleanup |
| Final ZIP/DMG packaging and strict signature checks | **PENDING** | Enter exact package directory and signing status |
| Extracted ZIP/DMG bundle manifests and SHA-256 | **PENDING** | Enter verifier result plus final checksum file |
| Release fixture-code exclusion | **PENDING** | Enter Release binary verifier result |
| Final package launch smoke | **PENDING** | Enter exact packaged app path and observed launch |

## Final artifacts

<!-- Parent agent: fill only after the final package exists and passes verification. -->

- Verified local app: **PENDING**.
- ZIP: **PENDING**.
- DMG: **PENDING**.
- `SHA256SUMS`, `BUNDLE-MANIFEST.json`, `DISTRIBUTION.txt`: **PENDING**.
- Screenshots/evidence index: **PENDING**.
- Final source state/commit, if created: **PENDING**. No commit is required to record an exact preserved working-tree artifact.

## Unavailable or intentionally excluded

- Developer ID signing and Apple notarization: **unavailable; no valid signing identity**. Ad-hoc signatures do not identify an Apple-approved publisher.
- Public download/Homebrew installation: **not published or verified**. The cask is a template.
- Camera Raw and broader creative cleanup/live project resolution: **disabled or unavailable**.
- General system/log sweeping, broad DerivedData cleanup, automatic scheduled removal, exhaustive app leftovers, snapshots and shipping CLI: **not implemented**.
- macOS 14/Intel runtime, genuine cloud providers, separately mounted volumes, live app-bundle Foundation Trash and power-loss recovery: **unverified**.
- Historical ordinary-file Foundation Trash/public undo passed on a disposable hosted CI account; it is **not** a new run against this preview or app-bundle integration.
- Native controls, accessibility labels and Command-1–7/R/F shortcuts are implemented. Real pointer/VoiceOver checks are **unverified because the computer-use service timed out**; no accessibility-compliance claim is made.

## Final assessment

**PENDING:** enter the scope actually ready for local use, any failed/untested checks, and the precise signing/distribution status. Do not describe the preview as full cleaner parity or universally validated.
