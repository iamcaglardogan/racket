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

## Limits and later phases

PathGuard is a read-only path and identity check. A successful check is not authority to remove a directory's unexamined descendants. The scanner and removal engine must validate their own scope and every protected descendant before treating any directory as a removal unit.

An identity receipt is an observation, not an atomic filesystem transaction. Revalidation detects the tested substitutions, but a pathname-based Trash operation has a remaining race window. Phase 3 must address and document that boundary; it must not claim that two path checks close every race.

Dataless content-access tests, size accounting, traversal depth, cancellation, manifest ordering, and actual Trash/undo round trips belong to Phases 2 and 3. Phase 1 does not open user file contents or exercise any removal. Mount-boundary logic also needs coverage on separately mounted test volumes before broader roots are enabled.

macOS CI executes with Xcode 16.4 on macOS 15. Its deployment target is macOS 14; that is not a substitute for runtime testing on macOS 14. Command Line Tools can compile the core, but running XCTest requires a toolchain containing that framework.

## Platform references

- [Apple open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html): no-follow opens and metadata-only event descriptors.
- [Apple fcntl(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html): retrieving the path of an open descriptor.
- Installed macOS SDK headers `sys/fcntl.h` and `sys/stat.h` are checked alongside documentation when implementing Darwin calls. They do not replace behavioral tests.
