# Safety contract

This contract governs implementation changes. Features must preserve the invariants below.

**Current scope: 0.1.0 local preview.** Three narrowly verified developer caches are enabled; ordinary cleanup uses reviewed individual files. Application bundles use a separate bounded tree review/removal capability. The SwiftUI app offers storage inspection, review/recovery and scan-only scheduling. Camera Raw and broader creative cleanup remain disabled. Local packages are ad-hoc signed, without Developer ID or Apple notarization. [Testing](docs/TESTING.md) and the [dated verification report](docs/VERIFICATION-2026-10-16.md) distinguish known evidence from outstanding platform checks.

1. **S1. Trash, never unlink.** Production removal uses `FileManager.trashItem(at:resultingItemURL:)` only through `RemovalEngine`. RACKET code, tests and helpers must not issue permanent-deletion requests for user-visible content. RACKET currently implements no Empty Trash action.
2. **S2. Explicit compiled authority.** Ordinary cleanup must remain within compiled cache/log roots and readable verified rules. Rule JSON cannot add roots. Whole-app removal requires its separate explicit bundle capability; it does not expand ordinary cleanup authority.
3. **S3. Resist symlinks and stale paths.** Use no-follow component traversal, retained identities and fresh checks at mutation boundaries. Refuse changed or unsupported objects. Observations and private staging reduce exposure but do not make Foundation's final pathname call atomic.
4. **S4. Refuse dataless files.** Apply flags/cloud-residency gates before explicit stat, size or content work, within the synchronous no-materialization thread policy. Report offline placeholders and uncertain metadata. Injected checks are not proof of genuine provider behavior.
5. **S5. Preferences are not junk.** Ordinary cleanup protects preferences and licence state. The current app-uninstall flow also retains preferences, licences, documents, application support, external services and related leftovers.
6. **S6. Removal requires an exact review.** A schedule may scan and notify. It may not select or remove files. A cleanup confirmation must show every selected path, including selections hidden by filters. No standing automatic-cleanup approval mechanism is implemented; judgement data is never preselected.
7. **S7. No telemetry or app networking.** No analytics, crash uploads, accounts or app network requests. The preview has no update check. Development-tool downloads, contributor GitHub access and an explicitly chosen browser link are separate from application networking.
8. **S8. Honest numbers.** Use checked allocated-byte observations and distinguish filesystem free space from purgeable estimates. Allocation is not uniquely reclaimable APFS storage. Moving files to Trash does not promise freed space; never promise RAM boosts or speed improvements.
9. **S9. Calm, factual copy.** No health scores, danger counters, threat meters or inflated findings. Show incomplete coverage and refusal reasons without treating cache size as a threat.
10. **S10. Auditable findings.** Every cleanup finding carries its exact path, rule ID, reason and regeneration cost; its rule supplies a primary source. Unverified rules remain disabled. App review binds the exact bundle and descendant metadata separately from cleanup rules.

## Enforcement map

| Invariant | Implementation and evidence | Important limit |
| --- | --- | --- |
| S1 | Sole Trash transport in `RemovalEngine`; removal/manifest/undo tests; [application tests](Tests/AppManagementTests/ApplicationManagementTests.swift); [source policy](scripts/check-source-policy.py) | Static source checks are guardrails. The historical live CI fixture proves an ordinary-file round trip, not every app/provider/volume case. |
| S2 | [Path tests](Tests/PathGuardTests/PathGuardTests.swift), [rule tests](Tests/RuleSetTests/RuleSetTests.swift), scanner independent policy checks, dedicated application policy | A valid rule declaration is not future filesystem authority. Application review does not make its caches or leftovers removable. |
| S3 | Component descriptors, scan fingerprints, private staging, exclusive renames, producer checks and adversarial substitution tests | Same-UID interference, later process launches and Foundation's final pathname race remain. |
| S4 | [Size/metadata tests](Tests/ScanEngineTests/SizeCalculatorTests.swift), bulk/walker tests, removal/undo gates, storage/app dataless refusal | Genuine File Provider/iCloud hydration and mounted-volume transitions remain unverified. |
| S5 | Compiled protected-path checks and app removal limited to a reviewed `.app` tree | No preference, orphan, licence or vendor-service removal authority exists. |
| S6 | Empty initial selection, complete confirmation, exclusions, busy-operation controls, scan-only schedule, explicit reviewed Core APIs | Core cannot establish human review by itself. Product behavior and Core boundaries both require verification. |
| S7 | No third-party runtime dependencies or networking implementation; selected APIs blocked by source policy | Pattern matching cannot prove the absence of every possible indirect network path. |
| S8 | Checked scanner/group/storage sums, allocated metadata, sparse/resource-fork cases, separate capacity values | APFS clones, snapshots, shared extents and purgeable storage prevent a guaranteed reclaimable total. |
| S9 | Factual product copy, skip/incomplete disclosures and [design guidance](DESIGN.md) | Full accessibility and representative usability testing are not established by Core tests. |
| S10 | Strict schema, source/reason/cost rendering, retained producer set, [real producer evidence](docs/RULE-VERIFICATION.md) and separate app-tree receipts | Verified synthetic regeneration covers named producer versions, not every historical package, project or toolchain. |

## Ordinary cleanup boundary

`SafeRoots` compiles these current-user locations:

- `~/Library/Caches`
- `~/Library/Logs`
- `~/.npm/_cacache`
- `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex`

Declarations may name a root for matching its contents; a root itself cannot be a removal candidate. Only the three narrow enabled paths in [RULE-VERIFICATION.md](docs/RULE-VERIFICATION.md) are currently scanned. No generic Caches/Logs sweep is enabled. Preferences, protected media/autosave/project/catalog names, cloud-container names and `.git` remain independently refused. Custom cache paths are not followed.

`PathGuard` opens components with metadata-only no-follow descriptors and compares item/ancestor identities. Scanner findings contain an internal fingerprint. Ordinary removal rechecks current rule scope, producer guard, ownership, link count, metadata and allocated bytes, then uses private `.racket-staging` reservations inside the existing root. Ordinary directory findings, multi-link files, root-owned files and elevation are refused.

All enabled rules require fresh supported producer observations before and after scan jobs and before removal mutations. Running or unknown activity blocks progress. Executable/bundle names are conservative heuristics; unsupported or renamed helpers and subsequent launch/exec remain limits. Cache removal can impair offline installation and slow future rebuilding/refetching, which the review must disclose.

## Application boundary

App removal accepts only explicit eligible `.app` selections beneath `/Applications` or `~/Applications` within a bounded depth. It rechecks the whole tree and process activity before capture/Trash/undo and uses a dedicated authenticated session type. It refuses symlinks, linked files, shared/foreign ownership, unsupported or dataless descendants, protected names and inspection-limit violations. Many normal apps with framework symlinks will be refused. See [APPLICATIONS.md](docs/APPLICATIONS.md).

This is a reviewed bundle move, not exhaustive uninstall. It does not remove application preferences, caches, containers, receipts, login items or services, and it grants no general directory-removal authority.

## Recovery and residual risk

Durable prepared/staged records precede the live Trash call. The returned location is verified before success is recorded. Undo authenticates the session and revalidates the recorded object before exclusive restoration. It never overwrites a destination, creates missing original parents, copies across volumes or guesses a recovery path from a filename. Application sessions use their app-specific undo path.

A final journal failure can leave an object moved without a durable returned Trash path. Preserve any recorded staging/recovery location for review. Recovery requires an unchanged identifiable object; emptying Trash or changing the source may prevent it. HMAC protects against corruption/changes without key access, not same-user forgery, confidentiality or truncation to a previously valid authenticated prefix. Private modes do not isolate malicious same-user processes. See [REMOVAL.md](docs/REMOVAL.md).

## Verification and future scope

XCTest, local producer checks and Debug UI fixtures use unique private synthetic directories and injected manifests/fake Trash. They must not scan or mutate the developer's home, installed apps, real caches, projects, real Trash or live cloud data. Generated fixture caches are preserved. Owner-authorized read-only production use must be reported separately from synthetic tests and must not turn personal files into test data.

The sole live-transport fixture exception is [guarded CI integration](docs/TESTING.md#guarded-live-integration) under a new synthetic OS account in a disposable GitHub-hosted macOS VM. Never run its account-setup script locally or spoof its guards.

The owner's October 15 full-flow delegation supersedes earlier phase approval stops for this run. It does not weaken this contract. Broader creative rules, cloud-specific cleanup, snapshots, Docker/simulator pruning, preferences or arbitrary directory removal require their own concrete safety design and evidence before enablement. macOS 14 runtime and Intel runtime remain unverified; missing Developer ID/notarization credentials limit distribution to the explicitly labelled local preview.
