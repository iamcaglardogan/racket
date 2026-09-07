# Read-only scanning

Phase 2 adds a headless scanner. [Phase 2 CI run 34164251933](https://github.com/iamcaglardogan/racket/actions/runs/34164251933) passed all 144 tests under SwiftPM and Xcode, source guardrails, and the universal app build; owner checkpoint review remains pending. It does not expose a product interface, move files, create recovery records, or add creative cleanup rules. The bundled rule document remains empty.

## Scope and output

`ScanEngine` accepts a validated `RuleSet`, uses only enabled and verified rules, and independently checks every declared path against its compiled `SafeRoots` policy before starting a walk. Test-injected rule validators cannot grant the engine broader access. The only compiled roots remain the current user's `Library/Caches` and `Library/Logs`.

`DirectoryWalker` enumerates each rule's `directoryContents` scope. It validates every child against protected-path rules and emits ordinary regular files only. It does not emit directories, approve their unexamined contents, infer project ownership, or choose which files to remove. A finding carries its resolved path, allocated size, modification date, rule ID, module, risk, reason, and regeneration note. `judgement` findings are ineligible for preselection; eligibility for other risks is not user approval.

`ScanReport` also carries the rule-set version, visited-entry count, and path-specific issues. Issues distinguish skips, refusals, and incomplete observations. Dataless items, age exclusions, explicit backup exclusions, and duplicates are visible skips. Unsafe paths are refusals. Missing metadata and traversal limits mark incomplete coverage. Consumers must not present a report with incomplete issues as a complete scan.

## Enumeration and path observations

`BulkDirectoryReader` requests names, per-entry errors, returned-attribute information, and flags through Darwin `getattrlistbulk`. It does not request size or allocation fields in the batch. Returned records are bounds-checked before their names can be used. Darwin does not promise a directory order, so the engine sorts observations before assigning rule explanations. The API takes an already-open directory descriptor and reports symlink metadata without following its target. [Apple's `getattrlistbulk(2)` manual](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlistbulk.2)

The walker retains metadata-only `O_NOFOLLOW` descriptors for the origin and ancestors. It opens readable descriptors only for directories, compares descriptor paths, checks mount boundaries, and brackets Foundation pathname metadata queries with identity checks. Changed directories lose their collected descendant findings and produce a visible refusal. There is no fallback enumeration that weakens these checks; an unsupported or failed operation is reported.

These checks reduce the chance of reporting a substituted path. They are not an atomic snapshot of a changing filesystem. Foundation's pathname queries remain observations, and a later consumer cannot treat a finding as a removal receipt. Phase 3 must independently validate removal scope and its remaining race boundary.

Regular files bind to a retained, verified parent directory plus their exact entry name and a fresh no-follow open with a matching fingerprint. Reverse descriptor paths are checked for directories, not used as unique names for regular inodes: hard links can give the same inode multiple paths. A name-cache-churn regression exercises this case, alongside regular-file and symlink substitutions. Apple's kernel documents the ambiguity of reverse vnode paths with hard links. [Apple vnode declarations](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/vnode.h)

## Dataless metadata sequence

Enumeration and even ancestor lookups may materialize dataless directories. Apple documents a per-thread policy to refuse that materialization and report `EDEADLK`. RACKET applies this policy around the entire synchronous walk, including origin lookup, then restores the prior policy on success or failure. No `await` may enter this scope because a Swift task can resume on a different thread. A policy setup or restoration error cannot produce a successful complete scan. [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files)

Within that scope, the order is:

1. Reject a bulk entry whose flags include `SF_DATALESS` before opening the child.
2. Query descriptor flags and reject `SF_DATALESS` before `fstat` or allocated-size access.
3. Query only the URL's ubiquity and downloading-state keys. Reject a not-downloaded item; refuse contradictory or unsupported provider states.
4. If the rule explicitly requests backup exclusions, read that metadata and report excluded entries.
5. Read descriptor metadata, check file type and flags, then recheck flags before requesting allocated size for a regular file.
6. Reopen from the retained parent and compare metadata fingerprints before retaining the observation.

Ordinary local files may return neither URL cloud value. The implementation allows that absence only while the independent descriptor flags and no-materialization policy remain in force. Two absent URL values are not proof that content is resident. Missing or unsupported allocated-size metadata has no logical-size fallback.

The scanner never opens a regular file for content reading or hashing. Injected metadata tests can establish call ordering and refusal behavior; they cannot establish behavior of a real cloud provider. `SF_DATALESS` is not a general-purpose writable fixture flag, so this checkpoint does not claim that synthetic files reproduce genuine cloud placeholders. Real provider integration remains unverified.

## Bounds, scheduling, and totals

Each module gets one task group. Modules run sequentially, while each group schedules at most the physical-core count, capped at 64 and falling back to one if the query fails. Cancellation is checked between jobs, directory boundaries, batches, and entries. A synchronous filesystem call cannot be interrupted midway; no wall-clock completion guarantee is made. Progress counts completed declared paths, not estimated bytes, percentages, or remaining time.

| Limit or filter | Behavior |
| --- | --- |
| `maxDepth` | Rule range 1–32; depth 1 inspects direct files and reports deeper directories as limited |
| Entries per walk | Default 20,000; reaching the bound records incomplete coverage |
| Collected observations | At most 100,000 files plus issues across the report; exceeding this throws without a complete report |
| `olderThanDays` | File modification time must be strictly before the supplied reference time minus that many 24-hour days |
| `skipExcludedFromBackup` | Defaults to false; only explicit true enables this filter, and every exclusion is reported |

Overlapping paths and hard links are deduplicated by exact path bytes and device/inode identity. Module, rule ID, declared path, and file-path ordering determine which eligible explanation wins, independently of task completion order. The visited-entry count can still include repeated observations from overlapping walks.

`reportedAllocatedBytes` adds each retained file's Foundation `totalFileAllocatedSize` using `UInt64` and fails on overflow. It is an observed allocated-size sum, not unique physical storage or a promise of bytes that removal would free. APFS clones may share extents that this identity-based deduplication cannot measure. Sparse files use allocated-size metadata, without a logical-size substitute. Free space and purgeable-space accounting belong to Phase 8.

## Verification boundary

The [test plan](TESTING.md) separates synthetic assertions from platform integration evidence. Current gaps include genuine provider placeholders, separately mounted test volumes, concurrent changes beyond the tested substitutions, macOS 14 runtime testing, and a representative performance benchmark. No order-of-magnitude speed claim or removal-safety claim follows from choosing a bulk API.
