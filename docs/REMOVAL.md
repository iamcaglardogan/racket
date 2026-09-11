# Removal and recovery

Phase 3 adds a headless `RemovalEngine`, `ManifestStore`, and `UndoService`. [PR CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716), at `780a4ad`, passed all 226 XCTest cases in both runners, source guardrails, the universal build, and entitlements validation. The same run passed the guarded ordinary-file Foundation Trash/public-undo integration. The owner’s checkpoint review in [draft PR 3](https://github.com/iamcaglardogan/racket/pull/3) remains pending; Phase 4 has not begun. No cleanup rule or product interface is enabled. XCTest and local fixtures use synthetic homes and an injected fake Trash transport; they do not touch a developer’s home or real Trash.

The engine records intent before changing a file's location, verifies that the file still matches the reviewed scan, and retains evidence when an operation fails. Undo restores only a verified recorded item to its original path. These controls do not establish an atomic Foundation Trash operation or guarantee recovery after every failure.

## Accepted selections

`moveToTrash(reviewedFindings:ruleSet:appVersion:now:)` accepts a nonempty explicit selection of at most 256 findings. Duplicate paths and findings without the live scanner's internal metadata observation are rejected before creating a session. The API has no automatic-selection or timer path. Its caller remains responsible for presenting and obtaining human review; the parameter name cannot establish that review occurred.

For each selected file, the engine independently verifies:

- Its current path lies below the compiled Caches or Logs root, satisfies the protected-path policy, and is outside the reserved `.racket-staging` name.
- The current rule is enabled and verified, still matches the path and depth, and agrees with the finding's module, risk, reason, and regeneration note.
- The age condition still holds, and any explicit backup exclusion is honored.
- No-follow metadata agrees with the scan fingerprint and allocated size. Dataless gates precede explicit stat and size access.
- The candidate is an ordinary single-link file owned by the current non-root user, with a supported local location. Directories, special files, symlinks, root-owned files, and multi-link files cannot enter the Trash step. Group/world-writable files and ancestors, and access-granting ACLs, are refused. The root-owned sticky `/private/tmp` ancestor is recognized for synthetic fixtures; it does not grant candidate authority outside the compiled safe roots.

The observation is not a content hash or a snapshot. A file with an uncertain or changed identity is refused. The removal report gives per-item outcomes (`trashed`, `refused`, `skipped`, `failed`, or `recoveryRequired`), cancellation state, and any journal failure; it does not promise reclaimed physical bytes.

## Transaction order

Both services are actors. Their filesystem operation bodies remain synchronous inside the per-thread no-materialization policy; there is no `await` inside that scope. Cancellation is checked between items, so an item already in progress completes its available outcome record before the next item is considered. A separate nonblocking operation lock prevents concurrent cooperating removal and recovery operations across store instances.

1. Create and synchronize the session header, including the app version, rule-set version, timestamp, and session ID.
2. Validate the selected file and retain its metadata descriptor and ancestor identities.
3. Append and synchronize `prepared`, including the original path, planned staging path, rule ID, allocated size, and recorded identity. No transaction directory or file move precedes this record.
4. Create or verify `<safe-root>/.racket-staging/<session-ID>/` with private permissions. Revalidate the original scan observation and path receipt.
5. Move the exact source entry to its item-ID staging name using descriptor-relative `renameatx_np` with `RENAME_EXCL | RENAME_NOFOLLOW_ANY`. No destination is overwritten and there is no cross-volume copy fallback.
6. Verify the captured item against the retained descriptor and recorded identity, then append and synchronize `staged`.
7. Recheck staging and ancestor identities immediately before the sole production `FileManager.trashItem(at:resultingItemURL:)` call in `RemovalEngine.swift`.
8. Validate the actual returned path, its file identity, and Foundation's Trash-directory relationship. Append and synchronize `trashed` before returning a successful outcome.

The reservation stays inside the existing compiled root; it grants no broader removal authority. It is excluded from rule locations and scan findings, so a later scan cannot offer transaction contents as new cleanup work. Empty reservations and failed-operation evidence are preserved.

Apple's Trash API accepts a pathname and provides the resulting location through its output parameter. RACKET records that returned path rather than constructing a name in Trash. Neither its public Core API nor the integration fixture can pin the destination chosen by Foundation; discovery and returned-path checks do not make the call atomic. [Apple Foundation Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))

The Darwin rename flags and descriptor-relative API are declared in Apple's versioned XNU source. Exclusive moves prevent replacement of an occupied destination; they do not compare an expected source inode atomically with the rename. [Apple XNU 10002.1.13 rename declarations](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/sys/stdio.h)

## Session journal

Production storage is `~/Library/Application Support/RACKET/Manifests/`. A 0700 directory contains a 0600 `authentication.key`, 0600 session `.jsonl` files, and the operation lock. Each session is newline-delimited JSON. Its header and event payloads are authenticated in sequence with HMAC-SHA256 using Apple's CryptoKit framework; there is no third-party package.

Each record includes a sequence number, the previous record's authentication value, a readable JSON string payload, and its own authentication value. Authentication covers the exact UTF-8 payload bytes, without decoding and re-encoding the object. The payload can be inspected with `jq '.payload | fromjson'`; editing it invalidates authentication. The header binds the session ID, format version, application version, rule-set version, and creation time. Events bind timestamps, action, original/staging/Trash paths, rule ID, allocated size, identity, and explanatory failure details when present.

The store uses no-follow opens, validates directory and file identities, ownership, modes, link counts, and ACL access, and refuses substituted storage. File locks serialize appends across store instances; `fsync` errors are surfaced. Parsing is bounded to a 32 MiB journal, records below 128 KiB, and 10,000 events. A missing final newline, invalid authentication, malformed record, or broken sequence prevents reading, export, and further append. The implementation never silently discards a damaged tail.

`export(sessionID:)` returns the original authenticated NDJSON bytes only after verification. Export is a headless API; a save dialog is not implemented. It preserves private paths and is not a redaction operation. Share manifests only through an appropriate private report and retain the authentication key locally.

HMAC is local integrity protection, not encryption or a public signature. It can detect corruption and changes by an actor without key access. Another process running as the same user may read the key and forge records. Truncation to a complete previously authenticated prefix is also undetectable without independent trusted state. Advisory locks coordinate cooperating instances; they are not a security boundary against hostile same-user processes.

## Failure and interruption

| Last known state | Behavior |
| --- | --- |
| Prepared record cannot be written | No file capture or Trash call; stop the batch |
| File changes before capture | Refuse it and record the outcome when possible |
| A last-moment replacement is captured | Refuse it after identity comparison; preserve the captured item for review if verified rollback is impossible |
| Staged record cannot be written | Preserve the deterministic staged location; stop the batch |
| Trash throws while the original item remains in staging | Attempt exclusive rollback only after verifying the item and original parent chain |
| Rollback destination is occupied or ancestry changed | Preserve both locations and report recovery required |
| Trash may have moved the item without returning a usable location | Report uncertainty; do not infer that nothing moved or search for a matching name |
| Final record cannot be written after a successful move | Return recovery required with any known in-memory location and stop the batch; the durable journal may lack the Trash path |
| Journal is malformed or incomplete | Refuse further journal use and automatic recovery; preserve its bytes |

An application interruption between the filesystem move and its outcome record remains possible. A journal write is not an atomic transaction with Foundation Trash. When a path exists only in the in-memory result and the process exits, automatic recovery may no longer know it. Preserve evidence and surface uncertainty rather than treating a prepared or staged record as proof that the item still occupies that path.

## Undo

`restore(sessionID:)` first authenticates the entire journal and validates its complete event history, item consistency, canonical paths, deterministic staging paths, and path ownership between records. A malformed later record prevents an earlier valid item from moving.

For each eligible item, the service verifies either its recorded Trash path or its exact deterministic staging path. A Trash source must have the expected Foundation relationship and recorded file identity. The original destination must still be inside a compiled safe root, its parent must exist, and the destination must be unoccupied. The service writes `restorePrepared`, rechecks source and ancestors, moves with exclusive no-follow rename, verifies the restored identity, and records `restored`.

Undo never overwrites an existing file, creates a missing original parent, substitutes a same-name file, or copies across volumes. A missing source is reported. Extra hard links or changed metadata are refused. Already-restored items are reported without another move. Cancellation stops between items; journal failures stop further processing.

An interrupted `restorePrepared` may be reconciled only when the known source is absent and the original path contains the recorded identity. If the verified source remains available, restore can retry without overwriting the destination. A same-name replacement is not evidence of a completed restore.

The staging step means Finder's Put Back may point to the staging path rather than the original application path. That platform behavior has not been exercised by the fixtures. RACKET's undo uses the original path from its authenticated manifest. Emptying Trash, removing recovery files, or losing the journal/key can prevent recovery; this implementation is not a backup or snapshot service.

## Platform and verification limits

The no-materialization policy covers ancestor lookups, removal, journal access, and recovery synchronously. It is restored on exit. Apple documents thread policy refusal of dataless materialization and `EDEADLK` behavior; injected flags and ordinary fixtures do not establish actual provider behavior. [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files)

Private staging narrows the exposed original-name window but does not close the final pathname race inside Foundation. A process running as the same user can alter a 0700 directory. A replacement can also arrive between the last source check and capture; post-capture verification prevents trusted success for that replacement but cannot promise that no unrelated item was moved. There is no claim of protection against every same-user race.

The [test plan](TESTING.md) distinguishes the passed XCTest suite’s real Darwin moves and journal files inside synthetic `/private/tmp` homes from its injected fake Trash transport. A separate guarded CI executable passed an ordinary-file round trip through actual Foundation Trash and public `UndoService`, under a new synthetic OS account in a disposable GitHub-hosted macOS VM. It verified the original inode, identical bytes, and five authenticated journal actions through the public current-user APIs. Its UUID and account/UID/GID preflight assumes no concurrent account creation and is not an atomic reservation. Never run the account script locally. No developer’s home, application cache, project, or cloud storage is used as test data. Finder Put Back, genuine cloud placeholders, separate-volume behavior, power-loss durability, and macOS 14 runtime compatibility remain unverified.

This checkpoint does not add directory removal, multi-link cleanup, elevated privileges, a helper, new rules, snapshots, standing approvals, or product views. Those capabilities cannot be inferred from this headless boundary.
