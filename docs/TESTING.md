# Safety testing

Phase 1 tests were written before the PathGuard implementation. XCTest and local checks exercise public behavior with synthetic files in unique, private temporary directories, injected manifest storage, and fake Trash. Fixtures are retained; there is no permanent-deletion teardown, and these checks do not scan or mutate a developer’s home or real Trash. The separate guarded CI integration below is the only live-transport exception.

## Phase 1 checks

| Boundary | Evidence required |
| --- | --- |
| Compiled roots | Only descendants of the synthetic home's Library/Caches and Library/Logs can pass; roots themselves cannot be removal candidates |
| Lexical paths | Generated traversal, prefix-collision, case, Unicode, repeated-separator, relative, and NUL/control inputs never authorize a path outside those roots |
| Protected data | Preferences, recognized protected folder names such as Original Media and Auto-Save, protected project extensions, cloud-container paths, and .git remain refused independently of allow-list matching; arbitrary media files are not identified by content |
| Filesystem identity | Symlink leaves, ancestors, safe-root replacements, dangling links, and loops are refused; no symlink target is followed |
| Revalidation | An unchanged identity receipt passes; moving aside and replacing an item or ancestor invalidates the receipt |
| Rule data | Unknown fields, malformed values, duplicate IDs, unexplained rules, invalid citations, unverified enabled rules, and unsafe paths fail validation |
| Bundled resources | The actual bundled JSON is decoded and validated in both SwiftPM and the Xcode framework test environment |
| Source boundaries | CI rejects selected permanent-deletion APIs, Trash calls outside RemovalEngine, UI dependencies in Core, and unapproved networking APIs |

## Phase 2 checks

The verified Phase 2 baseline contains 146 XCTest cases: 62 Phase 1 cases plus 3 backup-rule cases, 8 bulk-parser cases, 21 walker/integration cases, 24 engine cases, and 28 metadata/size cases. [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed all 146 cases in SwiftPM and Xcode, source checks, and the universal build. Local core compilation and 57 narrow scanner/size/parser smoke cases passed; these checks do not substitute for XCTest execution.

| Boundary | Evidence |
| --- | --- |
| Exact findings | [Checked-in fixture tree](../Tests/Fixtures/scan-tree.json), materialized in a unique private temporary home; real walker and engine assert exact files and protected-path refusals |
| Bulk records | Returned masks, optional error fields, dataless flags, Unicode names, malformed lengths/references, and missing attributes |
| Traversal | Symlink farms and roots, protected children, FIFOs, missing origins, depth and entry limits, no directory findings, unchanged fixture contents |
| Concurrent changes | Injected symlink and ordinary-file substitutions during size lookup, directory movement, and hard-link name-cache churn verify entry identity and discard affected observations |
| Dataless gates | Injected flags and cloud state prove explicit stat/size call ordering; policy success/error/nesting restores the prior thread state; walker emits a visible skip |
| Allocation | Real sparse and resource-fork fixtures, missing/negative/large metadata, no logical-size fallback, and UInt64 overflow refusal |
| Orchestration | Disabled rules, independent policy validation, exact age boundary, explicit backup option, bounded concurrency, cancellation, honest progress counts, deterministic duplicate/hard-link handling, and aggregate limits |

The fixtures are read from source using the test's compile-time file location, not from the real home directory. Temporary files and resource forks remain preserved. Schema fixtures use fixed synthetic citations and do not enable any bundled rule.

`SF_DATALESS` is read-only synthetic metadata in the macOS SDK, not a flag that an unprivileged test can faithfully set on a normal file. Instrumented operations test the refusal logic; they do not reproduce a provider. Actual iCloud/File Provider integration, separate mounted volumes, macOS 14 runtime, and representative speed benchmarks remain outstanding. [SCANNING.md](SCANNING.md) explains the synchronous kernel policy and the remaining pathname-observation limits.

## Phase 3 checks

[PR CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716), at `780a4ad`, passed all 226 XCTest cases in each of SwiftPM and Xcode, source guardrails, the universal `arm64`/`x86_64` app build, and entitlements validation. A separate local narrow harness passed 76 cases; that is not XCTest execution or a substitute for either CI runner. The following boundaries are covered by the synthetic suite. The owner’s Phase 3 checkpoint review remains pending in [draft PR 3](https://github.com/iamcaglardogan/racket/pull/3); Phase 4 has not begun.

| Boundary | Added assertions |
| --- | --- |
| Scan observations | Live fingerprints survive walker/engine conversion; synthetic defaults remain unobserved; replacing a file with the same size and restored modification time changes its observation |
| Removal selection | Missing observations and duplicate paths are rejected before session creation; rules, depth, age, allocation, and current identity are rechecked; hard links are skipped |
| Transaction order | Prepared and staged records exist before the fake Trash call; failure before intent leaves sources in place; failures after capture preserve recoverable evidence; failed final records stop the batch |
| Concurrent changes | Original-file, symlink, staging, and ancestor substitutions cannot produce trusted success; rollback conflicts preserve both files |
| Journal integrity | App/rule-set versions, dates, all event actions, and UInt64 bounds survive authentication; tampering, record reordering, duplicate records, cross-session replay, and partial tails are refused |
| Journal filesystem | Persistent keys reopen existing sessions; symlinks, hard links, unsafe modes, access-granting ACLs, and directory replacement are refused; synchronization errors remain visible; operation locks serialize store instances |
| Undo | Round trip to the original path; exact recorded identities; no overwrite when a destination already exists or appears after intent; no parent recreation; missing and unrecognized recovery locations are reported |
| Interrupted recovery | Recover verified staging records; validate the whole history before any move; resume interrupted restore only with matching identity; no same-name inference; journal failure stops subsequent items |
| Dataless and cancellation | Injected dataless states stop before explicit stat/size/Trash work; cancellation between items stops further namespace changes |

The [removal](../Tests/RemovalEngineTests/RemovalEngineTests.swift), [manifest](../Tests/RemovalEngineTests/ManifestTests.swift), [undo](../Tests/RemovalEngineTests/UndoServiceTests.swift), and [observation](../Tests/ScanEngineTests/RemovalObservationTests.swift) suites use unique synthetic homes under `/private/tmp`. The fake Trash transport renames fixture files to another fixture directory. Descriptor lookup, rename, metadata, journal files, authentication, and synchronization use actual local implementations, with injected failures at selected boundaries. All XCTest fixtures remain preserved; neither a developer’s home nor real Trash is scanned or mutated.

These tests do **not** exercise `FileManager.trashItem`, Foundation's recognition of the actual Trash directory, Finder's Put Back behavior, real cloud providers, separately mounted volumes, or a power-loss crash. Synchronized writes and injected failures do not establish durability under every storage failure. A successful fake-transport round trip is not evidence of a real Foundation Trash round trip.

## Guarded live integration

`scripts/check-live-trash.sh` and `scripts/fixtures/LiveTrash.swift` add a separate integration executable outside XCTest and the app targets. **The ordinary-file live round trip passed [CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716) at `780a4ad`.** It verified actual Foundation Trash followed by public `UndoService`, the original inode and identical bytes, and five authenticated journal actions after reopening the persistent store.

Never run the account-setup script locally or on a self-hosted runner, and never spoof its environment guards. It requires GitHub Actions, a GitHub-hosted macOS runner, Darwin, and a non-root setup process; the workflow selects a disposable `macos-15` VM. Setup creates a fresh 0700 `/Users/RACKET-LiveTrash-<UUID>` directory with `mkdir`, refusing an existing path, and temporarily assigns it to the runner for compilation with Core sources and the SwiftPM resource accessor. It checks account/group names and UID/GID availability, then creates a new account and group with `/Users/RACKET-LiveTrash-<UUID>/Home` as its home, no enabled password, no interactive login shell, and no membership added to existing groups. This live fixture uses `/Users` to keep Foundation’s home spelling canonical; XCTest and local fixtures remain under `/private/tmp`. Setup uses `sudo` and transfers the fixture directory, home, and executable to the new non-root account before running it. Account and files are preserved for the VM’s lifetime.

The name and UID/GID preflight assumes no concurrent account creation in that disposable job. `dscl -create` is not an atomic create-if-absent reservation. The environment checks are guardrails, not a sandbox or protection against someone deliberately bypassing them.

Before writing fixture data, the executable verifies real/effective IDs, supplementary groups, the passwd record, Foundation’s current-user home resolution, and private canonical fixture directories. It creates one ordinary file, uses the public current-user `SafeRoots`, `ScanEngine`, `ManifestStore`, `RemovalEngine`, and `UndoService` APIs, and supplies one explicit synthetic rule and selection. It neither injects a Trash transport nor calls Trash directly; the sole live call remains inside `RemovalEngine`. It checks the returned item’s identity and bytes, reopens the authenticated on-disk journal, restores the original path, and expects the five removal/restore journal actions.

Foundation Trash discovery is checked before removal, and the returned destination is checked afterward. The public Core path cannot pin the destination used by Foundation; these checks do not make the pathname operation atomic or guarantee confinement before the call. The disposable VM and fresh account are the integration environment. This result establishes the ordinary-file public-API round trip on that runner. Same-UID attacker resistance, Finder Put Back, cloud-provider or separate-volume behavior, macOS 14 runtime compatibility, and power-loss durability remain unverified.

## Limits and later phases

PathGuard is a read-only path and identity check. A successful check is not authority to remove a directory's unexamined descendants. The scanner and removal engine validate their own scope. Removal supports individual ordinary files only; directory removal would require a separate descendant-safety design.

An identity receipt is an observation, not an atomic filesystem transaction. Phase 3 rechecks the original observation and uses private staging before Trash. A last-moment source replacement can be captured and then refused, requiring review; the capture does not guarantee that no unrelated file was moved. The final Foundation pathname call has a remaining race window, and private permissions do not isolate another process with the same UID. [REMOVAL.md](REMOVAL.md) documents these boundaries and uncertain journal outcomes.

Phase 2 implements metadata gates, size accounting, traversal depth, and cancellation tests. Phase 3 verifies manifest ordering and synthetic transport round trips; its guarded integration also passed the ordinary-file actual Foundation Trash/public-undo round trip. No scanner production path opens regular-file content. Mount-boundary logic still needs coverage on separately mounted test volumes before broader roots are enabled.

macOS CI executes with Xcode 16.4 on macOS 15. Its deployment target is macOS 14; that is not a substitute for runtime testing on macOS 14. Command Line Tools can compile the core, but running XCTest requires a toolchain containing that framework.

## Platform references

- [Apple open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html): no-follow opens and metadata-only event descriptors.
- [Apple fcntl(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html): retrieving the path of an open descriptor.
- [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files): per-thread prevention of dataless materialization, including intermediate directory lookups.
- [Apple getattrlistbulk(2)](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlistbulk.2): directory records and returned attributes.
- Installed macOS SDK headers `sys/fcntl.h` and `sys/stat.h` are checked alongside documentation when implementing Darwin calls. They do not replace behavioral tests.
