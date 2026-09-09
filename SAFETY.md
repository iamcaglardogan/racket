# Safety contract

This contract governs every future implementation change. When a feature conflicts with an invariant, the feature loses.

**Implementation status:** Phases 1 and 2 are accepted and merged through pull requests [1](https://github.com/iamcaglardogan/racket/pull/1) and [2](https://github.com/iamcaglardogan/racket/pull/2). [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed its 146 XCTest cases in both runners, source guardrails, and the universal app build. Phase 3 adds headless removal, authenticated manifests, and undo with synthetic tests; verification and owner review are pending. There is no product interface or enabled cleanup rule. No current evidence establishes a live Foundation Trash or cloud-provider round trip.

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

Phase 1 and Phase 2 checks passed the linked CI runs. Phase 3 entries describe implementation and added tests awaiting execution evidence; later entries remain requirements. See [testing scope and limits](docs/TESTING.md) for the boundaries of the current evidence.

| Invariant | Enforcement location | Current coverage and remaining work |
| --- | --- | --- |
| S1 | [Source policy check](scripts/check-source-policy.py), [removal tests](Tests/RemovalEngineTests/RemovalEngineTests.swift), [manifest tests](Tests/RemovalEngineTests/ManifestTests.swift), [undo tests](Tests/RemovalEngineTests/UndoServiceTests.swift) | The live Trash call is confined to RemovalEngine. New synthetic cases cover durable intent, fake-transport failure, authenticated records, and restore without overwrite. Actual Foundation Trash integration remains unverified. |
| S2 | [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift), [rule tests](Tests/RuleSetTests/RuleSetTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift) | Compiled roots, independent declaration checks, unsafe children, and root-candidate refusal are tested. Rules cannot supply roots. |
| S3 | [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift), [removal tests](Tests/RemovalEngineTests/RemovalEngineTests.swift), [undo tests](Tests/RemovalEngineTests/UndoServiceTests.swift) | The scanner discards changed observations. Phase 3 adds scan-fingerprint revalidation, private staging, exclusive descriptor-relative moves, and substitution cases. The final Foundation pathname race and live mount transitions remain unproven. |
| S4 | [Size tests](Tests/ScanEngineTests/SizeCalculatorTests.swift), [walker tests](Tests/ScanEngineTests/DirectoryWalkerTests.swift), [bulk parser tests](Tests/ScanEngineTests/BulkDirectoryReaderTests.swift) | Injected dataless/cloud states stop before explicit stat/size operations; the walker reports skips. Thread materialization-policy restoration is tested. Real provider placeholders remain unverified. |
| S5 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift), [PathGuard tests](Tests/PathGuardTests/PathGuardTests.swift) | Compiled policy rejects Preferences and protected project paths. There is no uninstall exception or uninstall implementation. |
| S6 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift), [removal tests](Tests/RemovalEngineTests/RemovalEngineTests.swift) | Judgement findings remain ineligible for preselection. Removal requires a caller-supplied reviewed selection of observed files; this API cannot establish that a human reviewed it. Review UI, standing rules, and notifications remain future work. |
| S7 | [Source policy check](scripts/check-source-policy.py); future network-policy tests | Selected networking APIs are blocked and the core has no dependencies. This static guardrail does not prove absence of every possible network path. |
| S8 | [Size tests](Tests/ScanEngineTests/SizeCalculatorTests.swift), [engine tests](Tests/ScanEngineTests/ScanEngineTests.swift) | Foundation total allocated size, sparse/resource-fork fixtures, deduplication, and UInt64 overflow refusal are tested. The sum is not a claim of unique APFS extents or reclaimable bytes. Free/purgeable reporting remains Phase 8. |
| S9 | Future copy/token checks and accessibility/UI review | Product views and metrics are not implemented. |
| S10 | [Rule tests](Tests/RuleSetTests/RuleSetTests.swift) | Strict versioned schema, unknown/duplicate JSON keys, unique IDs, required explanations and citations, bounded matches, compiled path policy, and unverified/disabled states are covered. The bundled document contains zero rules. |

Tests must use isolated synthetic fixtures rather than the real home directory. A failed Trash call must still leave a manifest entry proving the pre-call record was written. A test's cleanup is subject to S1 too.

## Current boundary

`SafeRoots` currently enumerates only `~/Library/Caches` and `~/Library/Logs`. Rule declarations may name a root for matching its contents; the root itself cannot be a removal candidate. Protected names and extensions are checked independently. No broader creative or system path has been enabled.

`PathGuard` opens each component using `O_EVTONLY` and `O_NOFOLLOW`, reads flags before `fstat`, and produces a read-only identity receipt. Revalidation compares both the item and its ancestors. The scanner emits ordinary files and retains an internal metadata fingerprint. Removal rechecks that observation, the rule, ownership, link count, allocation, and path, then uses a reserved `.racket-staging` directory inside the existing root. Directory candidates, multi-link files, root-owned files, and elevation are refused or skipped.

Prepared and staged records precede the live Trash call; its returned location is checked before recording success. Undo authenticates the full session before moving anything and uses exclusive moves to the original path. Journal failures stop the session. An uncertain operation can require manual review, particularly if a final record fails after Trash moved the file. It is not safe to infer a replacement location from a matching filename.

Private staging and journal permissions do not protect against another process running as the same user. HMAC authentication detects damage and modifications without the key, but cannot detect truncation to a previously valid complete prefix. Foundation still accepts a pathname, leaving a final race window. See [the scanner design](docs/SCANNING.md) and [removal boundaries](docs/REMOVAL.md).

## Clarifications required before affected implementation

- The brief mentions snapshot deletion, simulator deletion, Docker pruning, and language-file removal. These must not be implemented as implicit exceptions to S1. Resolve the conflict with the owner before adding any such action.
- Preference removal during uninstall needs narrowly scoped authority; it must not weaken the independent deny rules for ordinary cleanup.
- Real provider integration needs behavioral verification before enabling cleanup rules or distributing the application. The scanner combines flags/cloud checks with a no-materialization thread policy; injected tests and ordinary-file checks do not prove every provider's behavior.
- Receipt replacement tests do not prove resistance to every filesystem race. The final Trash boundary and live mount transitions require platform integration evidence. Directory removal remains unsupported; adding it requires a separate descendant-safety design and adversarial coverage.
