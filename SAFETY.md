# Safety contract

This contract governs every future implementation change. When a feature conflicts with an invariant, the feature loses.

**Implementation status:** Phase 2 adds read-only scanning to the verified Phase 1 path and rule core. There are 146 XCTest cases, including the original 10,000 generated adversarial paths; [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed both test runners, source guardrails, and the universal app build. The owner authorized Phase 2, while the Phase 1 draft pull request remains unmerged. No removal code or product interface exists, and no cleanup rule is enabled. The tests are not proof that a future cleanup operation is safe.

1. **S1. Trash, never unlink.** All removals go through `FileManager.trashItem(at:resultingItemURL:)`, called only by `RemovalEngine`. No code path, test, temporary utility, or script may permanently delete user-visible content. The sole exception is the user's explicit Empty Trash action.
2. **S2. Allow-list, not deny-list.** A deletable path must resolve inside a compiled, explicitly enumerated safe root. Anything else is refused even when a rule matches. Rule data cannot extend the allow-list.
3. **S3. Symlink and TOCTOU resistance.** Resolve every path before validation and re-resolve immediately before the Trash call. Open directories with `O_NOFOLLOW` where possible. Symlink escapes are hard errors, not skips. Race resistance must be tested rather than inferred from a second path lookup.
4. **S4. Never touch dataless files.** Inspect `ubiquitousItemDownloadingStatus` and `SF_DATALESS` before explicit stat, size, or content access. Do not cause placeholder hydration. Report dataless items as skipped.
5. **S5. Preferences are not junk.** `~/Library/Preferences` contains settings and licence state. Consider it only during an explicit user-initiated uninstall of a specific application, never in a cache sweep.
6. **S6. No auto-delete without review.** A schedule may scan. Removal requires review or a previous standing approval for that exact category, followed by a notification with undo. Judgement findings are never preselected or eligible for standing automatic selection.
7. **S7. No telemetry, ever.** No analytics, crash reporting, or anonymous statistics. The only potentially permitted app network operation is an optional GitHub release check, disabled by default and permanently disableable; whether it exists is still undecided. Reject dependencies that contact external services.
8. **S8. Honest numbers only.** Count allocated size with `UInt64`, distinguish real free space from Finder's estimates, and make no claim to reclaim purgeable space, boost RAM, or accelerate a Mac.
9. **S9. No fear.** Do not use alarm counters, health scores, threat meters, fear-based copy, or inflated findings. Size is information rather than a danger signal.
10. **S10. Auditable by construction.** Every finding identifies one readable rule and one path. Rules must carry a unique identifier, source citation, plain-language reason, and regeneration cost. Unverified rules do not ship enabled.

## Enforcement map

Phase 1 and Phase 2 checks passed the linked CI runs. Entries for later phases remain requirements. See [testing scope and limits](docs/TESTING.md) for the boundaries of the current evidence.

| Invariant | Enforcement location | Current coverage and remaining work |
| --- | --- | --- |
| S1 | [Source policy check](scripts/check-source-policy.py); future `Tests/RemovalEngineTests/` | Selected permanent-deletion APIs and misplaced Trash calls are rejected by the source check. Actual Trash/manifest/undo behavior awaits Phase 3. |
| S2 | [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift), [rule tests](Tests/RuleSetTests/RuleSetTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift) | Compiled roots, independent declaration checks, unsafe children, and root-candidate refusal are tested. Rules cannot supply roots. |
| S3 | [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift); future removal tests | No-follow traversal, symlink farms, and path substitutions are tested. Scanner tests discard observations from replaced paths/directories. Atomic Trash behavior and live mount transitions remain unproven. |
| S4 | [Size tests](Tests/ScanEngineTests/SizeCalculatorTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift), [bulk parser tests](Tests/ScanEngineTests/BulkDirectoryReaderTests.swift) | Injected dataless/cloud states stop before explicit stat/size operations; the walker reports skips. Thread materialization-policy restoration is tested. Real provider placeholders remain unverified. |
| S5 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift), [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift) | Compiled policy rejects Preferences and protected project paths. There is no uninstall exception or uninstall implementation. |
| S6 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift); future selection/scheduling tests | Judgement rules and findings are never eligible for preselection. User approval, standing rules, notifications, and undo await their feature phases. |
| S7 | [Source policy check](scripts/check-source-policy.py); future network-policy tests | Selected networking APIs are blocked and the core has no dependencies. This static guardrail does not prove absence of every possible network path. |
| S8 | [Size tests](Tests/ScanEngineTests/SizeCalculatorTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift) | Foundation total allocated size, sparse/resource-fork fixtures, deduplication, and UInt64 overflow refusal are tested. The sum is not a claim of unique APFS extents or reclaimable bytes. Free/purgeable reporting remains Phase 8. |
| S9 | Future copy/token checks and accessibility/UI review | Product views and metrics are not implemented. |
| S10 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift) | Strict versioned schema, unknown/duplicate JSON keys, unique IDs, required explanations and citations, bounded matches, compiled path policy, and unverified/disabled states are covered. The bundled document contains zero rules. |

Tests must use isolated synthetic fixtures rather than the real home directory. A failed Trash call must still leave a manifest entry proving the pre-call record was written. A test's cleanup is subject to S1 too.

## Current boundary

`SafeRoots` currently enumerates only `~/Library/Caches` and `~/Library/Logs`. Rule declarations may name a root for matching its contents; the root itself cannot be a removal candidate. Protected names and extensions are checked independently. No broader creative or system path has been enabled.

`PathGuard` opens each component using `O_EVTONLY` and `O_NOFOLLOW`, reads flags before `fstat`, and produces a read-only identity receipt. Revalidation compares both the item and its ancestors. Phase 2 scans ordinary files only and applies its own descriptor, cloud, and materialization checks. A receipt or finding does not approve unexamined descendants or close a later pathname-based Trash race. See [the scanner design](docs/SCANNING.md); removal remains Phase 3.

## Clarifications required before affected implementation

- The brief mentions snapshot deletion, simulator deletion, Docker pruning, and language-file removal. These must not be implemented as implicit exceptions to S1. Resolve the conflict with the owner before adding any such action.
- Preference removal during uninstall needs narrowly scoped authority; it must not weaken the independent deny rules for ordinary cleanup.
- Real provider integration needs behavioral verification before enabling cleanup rules or distributing the application. The scanner combines flags/cloud checks with a no-materialization thread policy; injected tests and ordinary-file checks do not prove every provider's behavior.
- Receipt replacement tests do not prove resistance to every filesystem race. Phase 3 must address the remaining Trash boundary, directory-descendant safety, and live mount transitions with explicit tests and documented limits.
