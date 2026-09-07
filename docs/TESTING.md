# Safety testing

Phase 1 tests are written before the PathGuard implementation. They exercise the public behavior and use synthetic files in unique, private temporary directories. Fixtures are retained; there is no permanent-deletion teardown and no test scans the real home directory.

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

The suite now contains 146 XCTest cases: 62 Phase 1 cases plus 3 backup-rule cases, 8 bulk-parser cases, 21 walker/integration cases, 24 engine cases, and 28 metadata/size cases. [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed all 146 cases in SwiftPM and Xcode, source checks, and the universal build. Local core compilation and 57 narrow scanner/size/parser smoke cases passed; these checks do not substitute for XCTest execution.

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

## Limits and later phases

PathGuard is a read-only path and identity check. A successful check is not authority to remove a directory's unexamined descendants. The scanner and removal engine must validate their own scope and every protected descendant before treating any directory as a removal unit.

An identity receipt is an observation, not an atomic filesystem transaction. Revalidation detects the tested substitutions, but a pathname-based Trash operation has a remaining race window. Phase 3 must address and document that boundary; it must not claim that two path checks close every race.

Phase 2 implements metadata gates, size accounting, traversal depth, and cancellation tests. Manifest ordering and actual Trash/undo round trips remain Phase 3. No scanner production path opens regular-file content. Mount-boundary logic still needs coverage on separately mounted test volumes before broader roots are enabled.

macOS CI executes with Xcode 16.4 on macOS 15. Its deployment target is macOS 14; that is not a substitute for runtime testing on macOS 14. Command Line Tools can compile the core, but running XCTest requires a toolchain containing that framework.

## Platform references

- [Apple open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html): no-follow opens and metadata-only event descriptors.
- [Apple fcntl(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html): retrieving the path of an open descriptor.
- [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files): per-thread prevention of dataless materialization, including intermediate directory lookups.
- [Apple getattrlistbulk(2)](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlistbulk.2): directory records and returned attributes.
- Installed macOS SDK headers `sys/fcntl.h` and `sys/stat.h` are checked alongside documentation when implementing Darwin calls. They do not replace behavioral tests.
