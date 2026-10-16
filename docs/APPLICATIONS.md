# Application management

RACKET lists application bundles and supports explicit, reviewed removal of a bounded subset of current-user-owned bundles. A successful removal moves the whole reviewed bundle to Trash and records an authenticated app-specific undo session. Ordinary cache cleanup retains its existing independent file-only policy.

## Discovery and review

`ApplicationInventory.scan()` reads application metadata under `/Applications`, `~/Applications`, `/System/Applications`, and `/System/Library/CoreServices/Applications`. Discovery stops at `.app` boundaries and searches vendor folders to depth three. It is bounded to 20,000 inspected locations and 2,000 applications. The report exposes skipped/unavailable locations and whether a limit was reached; it is not a claim to find every installed application, helper, login item, or extension.

Metadata comes from a no-follow, bounded read of `Contents/Info.plist` (at most 1 MiB). The parser requires `CFBundlePackageType=APPL`, a syntactically valid bundle identifier, and a single-component executable name. It does not load code, launch an application, register it with Launch Services, inspect preferences, or assess the application's signature/notarization. A valid plist is identification metadata, not proof of application trust.

The inventory records the path, display name, version, bundle identifier, and root metadata identity. Apple bundle identifiers, system locations, RACKET itself, other owners, and shared writable application roots are visibly protected. Preliminary eligibility does not authorize removal. `reviewRemoval(of:)` reopens the selected exact path, verifies the inventory identity and metadata, checks process activity, and inspects every descendant before returning an `ApplicationRemovalSelection` receipt. Inventory sizes remain unavailable until that full review; review allocation is the sum of the admitted files' Foundation allocated sizes, not uniquely reclaimable APFS space.

Only exact `~/Library/Caches/<bundle-id>` and `~/Library/Logs/<bundle-id>` locations are associated with an application. This read-only association does not create a cleanup rule. Preferences, application support data, containers, login items, receipts, and similarly named sibling directories receive no new cleanup authority. Uninstall therefore removes the reviewed application bundle; it does not promise exhaustive removal of every leftover or vendor service.

## Separate directory authority

The app removal capability accepts only explicit `.app` selections beneath `/Applications` and `~/Applications`, within three components of those roots, outside another application bundle. It never elevates privileges. App roots and all descendants must be owned by the current non-root user and must not be writable by other users or contain ACL allow grants. `/Applications` alone admits its standard root:admin group-writable directory mode; descendant permissions remain strict. Other ancestors retain trusted-directory checks. No cache root or protected-name denial is broadened by this module.

The review refuses:

- Symlinks anywhere, including common framework aliases, without following their targets. Such applications can still be revealed and reviewed in Finder.
- Hard-linked regular files, FIFOs, sockets, devices, foreign-owned/shared descendants, and unsupported metadata.
- Dataless/offline placeholders, uncertain cloud residency, nonlocal volumes, and descendant device changes.
- Protected original media, autosave, `.git`, cloud storage names, and project/catalog extensions already independently protected by cleanup.
- More than 50,000 total entries, depth greater than 64, malformed directory batches, changed directory observations, or allocation overflow.
- Running executable paths inside the application bundle, or an unavailable/incomplete process observation.

Process checks use the existing kernel process snapshot source and are repeated at review and mutation boundaries. Live observations retry up to three complete fresh strict snapshots after transient process churn; persistent incomplete observation still refuses the action. They observe executables inside the selected original/staged bundle, including bundled helpers. They do not identify every external vendor service, prevent a subsequent launch/exec, or constitute an application lock.

The receipt contains a SHA-256 digest of ordered relative descendant paths, metadata identities, and allocated sizes. It includes descendant ctime and excludes only the bundle-root ctime, which changes when the bundle is renamed. It is a metadata tree digest, not a hash of file contents and not a substitute for signature validation. The entire tree is freshly inspected before capture, after capture, immediately before Trash, after Trash, and before/after undo.

## Journal and recovery

`RemovalEngine.moveApplicationToTrash(reviewedApplication:appVersion:)` shares the existing authenticated `ManifestStore` but creates a dedicated `application-removal-v1` session. The app-specific rule identifier contains the exact bundle identifier and tree digest. Directory identities in these sessions cannot pass the ordinary cache `UndoService`; application sessions must be routed to `RemovalEngine.restoreApplication(sessionID:)`.

Before namespace changes, the engine durably records the intended source and exact staging location. It captures the bundle with a descriptor-relative, no-overwrite, no-follow rename into a private sibling reservation:

```
<application parent>/.racket-app-staging-<uid>/<session UUID>/<item UUID>.app
```

The reservation and session directories must be current-user-owned mode 0700. There is no cross-volume copy/delete fallback. After full tree revalidation and a durable staged record, the engine calls the same sole Foundation Trash transport in `RemovalEngine.swift` used by ordinary cleanup. A returned Trash location must be verified, and its entire tree must retain the reviewed identity before success is recorded.

App undo authenticates and validates the entire session history before moving anything. It accepts only a recorded staging/Trash source, revalidates the full bundle, refuses destination conflicts, creates no missing original parent, and uses an exclusive rename. A failed final restore record can be reconciled only when the original entire tree matches and the recorded source is now missing. An app already restored returns `alreadyRestored`.

A journal failure stops processing and preserves evidence. If Trash succeeded without a durable returned destination, the engine never guesses a path from the bundle name. Recovery may require manual Finder review. If a captured bundle changes, it is preserved at its recorded location instead of being blindly rolled back or trashed.

The existing threat-model limits still apply: no local protocol isolates a malicious process running as the same user, and Foundation consumes a pathname after the final validation. HMAC authentication detects corruption/changes without key access, not same-user forgery or truncation to a previously valid complete prefix. The module provides conservative observations and verified recovery paths, not atomic protection against every filesystem/process race.

## Verification

`Tests/AppManagementTests/ApplicationManagementTests.swift` uses only synthetic private temporary application trees, injected activity/metadata, an authenticated fixture journal, and fake Trash. The 31 application-management tests pass locally. They cover inventory and system/self protection, nested vendor folders, exact cache association, root/descendant ownership and cloud gates, linked/protected/shared/FIFO descendants, running/unknown activity, replacement before review/capture, tree change after capture/before Trash, full app undo, destination conflict, missing original parents, journal failures before and after mutations, interrupted restore reconciliation, post-rename verification failure recovery, descendant ctime checks when mtime is restored, exact Unicode path bytes, separation from ordinary file undo, full Debug runtime/inventory/removal/undo integration, and refusal of aliased/non-fixture/symlink verification homes.

A separate read-only production inventory smoke on October 15, 2026 returned 110 applications on the development Mac, with 20 eligible for detailed review and 90 protected. Fifteen locations were skipped/unavailable and the bounded-depth indicator was set. This smoke read metadata only: it did not remove a real application or touch real Trash. Synthetic tests do not establish provider behavior or platform coverage on macOS 14, and the guarded CI fixture now also exercises a synthetic complete app-bundle roundtrip through production inventory, review, Foundation Trash, and authenticated app undo. The added fixture compiles locally but is never executed on the development Mac; its live result is reported only after disposable CI execution.
