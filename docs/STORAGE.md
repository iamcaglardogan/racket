# Storage overview and explorer

The storage view is read-only. Explorer entries are not cleanup findings and do
not grant permission to remove anything. The cleanup engine retains its separate
compiled safe roots and reviewed rules.

`StorageVolumeSnapshot.read(at:)` observes the filesystem containing a selected
directory. It distinguishes physical free blocks from blocks available to the
current user. Apple's optional important/opportunistic capacity estimates are
separate values; they can include purgeable space and never replace physical free
space. An unsupported estimate stays `nil`. APFS volumes share container capacity,
so capacities from multiple APFS volumes must not be summed.

`StorageExplorer.explore(at:options:)` asynchronously returns the selected folder's
immediate entries, sorted by observed allocated bytes. Directory totals include
visited descendants. Calling the same API with one directory's URL provides
drilldown. It has no delete, move, or contents-reading operation.

Entries retain their original `rawPath` and use its UTF-8 bytes as a `Data`
identity. Foundation URLs are constructed from the filesystem representation so
both the URL path and metadata lookups preserve those bytes. This prevents Swift's
canonical Unicode string comparison from combining distinct observations and
preserves the chosen directory when drilling down.

## Observation limits

- Default bounds are 100,000 entries, 24 levels, and 30 seconds. Callers can lower
  them; maximum supported bounds are 100,000 entries, 32 levels, and 120 seconds.
- Time limits and cancellation are cooperative between filesystem calls. The
  operating system can delay an individual metadata operation on an unhealthy or
  remote filesystem; this is not a hard timeout guarantee.
- Cancellation throws `CancellationError`; it does not return an empty success.
- Every skipped item, unavailable metadata value, traversal limit, filesystem
  change, or size overflow is visible in `issues`. Any issue makes `isComplete`
  false. Each top-level entry also carries its descendant issue count.
- Package contents, symbolic links, special files, dataless placeholders, and
  nested mount points are skipped. Selecting a folder inside a package is refused.
- The scanner uses allocated file bytes, not logical file lengths. Each hard-linked
  inode contributes once per report and additional names are reported explicitly.
  APFS clones, snapshots, compression, and shared extents mean these totals are
  observations rather than a promise of physical space that could be reclaimed.
- Directory metadata allocation is excluded; totals cover observed regular files.
  Empty folders therefore show zero bytes.

## Filesystem safety

Traversal reuses the cleanup scanner's `SizeCalculator`, bulk name/flag reader,
and synchronous per-thread no-materialization policy. Dataless flags and cloud
residency are checked before explicit stat or size reads. Bulk enumeration requests
names and flags only. Folder ancestry is opened component by component with
no-follow descriptors; those descriptors are retained and their path bindings are
rechecked. File metadata is bracketed with a fresh no-follow relative open and
fingerprint comparison. A changed directory's observations are discarded and the
report remains visibly partial.

The explorer intentionally does not reuse `DirectoryWalker`'s cleanup-root policy:
that policy cannot be broadened for storage inspection. Its independent read-only
API accepts a caller-selected folder without creating cleanup authority.

Tests create synthetic folders under `/private/tmp`; they do not scan or alter
the user's real cache, applications, cloud files, or home directory.
