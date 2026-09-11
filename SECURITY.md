# Security policy

## Report a security issue privately

Use [GitHub's private vulnerability reporting form](https://github.com/iamcaglardogan/racket/security/advisories/new) for a potential data-loss bug, an incorrect removal rule, a path-guard bypass, or an unexpected network request. Do not put private filesystem paths, manifests, or work files in a public issue.

Include the affected commit or release, macOS version, rule identifier if relevant, expected behavior, and steps to reproduce with synthetic files where possible. Share a redacted manifest only when it helps explain the issue. There is no response-time guarantee at this preparation stage.

If a development build moves an unexpected item, stop that removal session and preserve its manifest, authentication key, and recorded locations. Avoid emptying Trash. The headless undo implementation can attempt recovery only when the journal and file identity are valid; an uncertain or missing location may need manual review. Do not retry a damaged journal or guess recovery paths by filename.

## Supported versions

There are no releases or distributed builds yet. Phases 1 and 2 are merged; their 146-test suite and universal build passed CI. Phase 3 adds headless removal, authenticated session records, and undo. [PR CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716), at `780a4ad`, passed 226 XCTest cases in both runners, source guardrails, the universal build, and entitlements validation. The same run passed the guarded ordinary-file Foundation Trash/public-undo integration. The owner’s checkpoint review in [draft PR 3](https://github.com/iamcaglardogan/racket/pull/3) remains pending; Phase 4 has not begun. The bundled rule document remains empty, and there is no product interface. Security reports about the evolving design are welcome. Release support and patch policy will be documented before distribution.

## Threat model

The application will operate on valuable local files. Assets include source media, project databases, application settings, credentials, and recoverable items in Trash. Threats include incorrect rules, symlink escapes, path substitution races, malicious filesystem metadata, cloud placeholder hydration, incorrect ownership attribution, and compromised build inputs.

Phase 1 implements compiled cache/log roots, independent protected-path checks, metadata-only no-follow path walks, dataless flag checks, identity receipts and revalidation, and bounded, strict rule decoding. Synthetic tests cover path rejection and identity substitutions; live cloud-placeholder behavior and separately mounted volumes still need dedicated validation.

Phase 2 adds bounded directory enumeration, per-child path checks, regular-file findings, and visible skip/refusal/incomplete issues. The synchronous walk disables dataless materialization for its thread, checks descriptor flags and URL cloud metadata before size access, and restores the prior thread policy. Synthetic metadata tests cannot prove that every real cloud provider avoids hydration; that integration remains unverified.

A successful path check or scan finding is an observation, not permission to remove unexamined descendants or a guarantee against all concurrent filesystem changes. Phase 3 revalidates the observation and rule, accepts only resident ordinary files owned by the current non-root user with one link, and moves them through private staging before the single Foundation Trash gateway. A review interface remains future work; the core's explicit selection parameter cannot itself prove human review.

The local manifest uses a chained HMAC-SHA256 record format, a 0600 key and journals inside a 0700 directory, bounded parsing, file locks, and `fsync` before mutation. Authentication is local integrity protection, not encryption or a public digital signature. Anyone with the same user's key access can forge records, and truncation to a valid complete prefix is not detectable. Paths in exported journals remain sensitive; export verifies bytes but does not redact them. There is no network export endpoint.

Private staging narrows exposure to pathname substitution but is not isolation from another process running with the same UID. The Foundation Trash call still has a final pathname race; metadata checks and retained descriptors do not make it atomic or pin its destination. A final journal failure may leave a moved item without a durable Trash URL. Undo refuses unknown identities, occupied destinations, absent parents, malformed histories, and guessed locations. A guarded live integration fixture passed an ordinary-file round trip through actual Foundation Trash and public `UndoService`, under a new synthetic OS account and home in a disposable GitHub-hosted macOS VM. Account-name and UID/GID preflight assumes no concurrent account creation and is not an atomic reservation. XCTest and local fixtures continue to use fake Trash. Real cloud-provider behavior, separate volumes, Finder Put Back, macOS 14 runtime, and power-loss durability remain unverified. See [removal and recovery boundaries](docs/REMOVAL.md), [scanner boundaries](docs/SCANNING.md), and [the test plan and its limits](docs/TESTING.md).

Rule JSON is untrusted input to validation. A rule must never authorize its own safe root. Prefer conservative refusal when ownership or path identity cannot be established.

## Full Disk Access

The intended full feature set requires Full Disk Access to inspect protected locations such as Mail downloads and application containers. This is broad macOS permission and expands the impact of application bugs. Onboarding must explain what is read and why before asking. Limited scans must remain honest about inaccessible locations.

Never ask users to grant Full Disk Access to Terminal or another general-purpose shell. The app will request access under its own identity. No privileged helper is planned for v1; items requiring elevation are skipped and explained.

## Network and release integrity

Telemetry is prohibited. The product decision about a default-off GitHub update check is pending; no application networking code exists.

Signing keys, certificates, API tokens, and notarization credentials do not belong in this repository. CI uses read-only permissions, a commit-pinned checkout action, and a checksum-verified XcodeGen release. GitHub secret scanning, push protection, and private vulnerability reporting are enabled. Main requires the GitHub Actions build/test check on an up-to-date branch, including for administrators, and disallows force pushes and deletion. Release signing and notarization will be configured after the owner supplies the required developer account setup.

The safety contract and its planned enforcement map are in [SAFETY.md](SAFETY.md).
