# Security policy

## Report a security issue privately

Use [GitHub's private vulnerability reporting form](https://github.com/iamcaglardogan/racket/security/advisories/new) for a potential data-loss bug, an incorrect removal rule, a path-guard bypass, or an unexpected network request. Do not put private filesystem paths, manifests, or work files in a public issue.

Include the affected commit or release, macOS version, rule identifier if relevant, expected behavior, and steps to reproduce with synthetic files where possible. Share a redacted manifest only when it helps explain the issue. There is no response-time guarantee at this preparation stage.

If a development build moves an unexpected item, stop that removal session and preserve its manifest, authentication key, and recorded locations. Avoid emptying Trash. The headless undo implementation can attempt recovery only when the journal and file identity are valid; an uncertain or missing location may need manual review. Do not retry a damaged journal or guess recovery paths by filename.

## Supported versions

Version 0.1.0 is a local preview with a SwiftUI review/recovery flow, three narrowly verified developer rules in document `1.2.0`, read-only storage inspection and conservative application-bundle management. Camera Raw/broader creative cleanup remain disabled. Local packages are ad-hoc signed, without Developer ID or Apple notarization; no public Homebrew release is claimed. [The dated verification report](docs/VERIFICATION-2026-10-16.md) and [testing scope](docs/TESTING.md) distinguish current evidence from historical CI and platform gaps. Security reports are welcome; there is no response-time or long-term support guarantee for this preview.

## Threat model

The application will operate on valuable local files. Assets include source media, project databases, application settings, credentials, and recoverable items in Trash. Threats include incorrect rules, symlink escapes, path substitution races, malicious filesystem metadata, cloud placeholder hydration, incorrect ownership attribution, and compromised build inputs.

Phase 1 implements compiled cache/log roots, independent protected-path checks, metadata-only no-follow path walks, dataless flag checks, identity receipts and revalidation, and bounded, strict rule decoding. Synthetic tests cover path rejection and identity substitutions; live cloud-placeholder behavior and separately mounted volumes still need dedicated validation.

Phase 2 adds bounded directory enumeration, per-child path checks, regular-file findings, and visible skip/refusal/incomplete issues. The synchronous walk disables dataless materialization for its thread, checks descriptor flags and URL cloud metadata before size access, and restores the prior thread policy. Synthetic metadata tests cannot prove that every real cloud provider avoids hydration; that integration remains unverified.

A successful path check or scan finding is an observation, not permission to remove unexamined descendants or a guarantee against all concurrent filesystem changes. Ordinary removal revalidates rules/observations, accepts only resident current-user-owned single-link files and uses private staging before the single Foundation Trash gateway. SwiftUI now presents explicit selection and full-path confirmation; Core's parameter alone cannot establish human review. Application directories require the separate bounded whole-tree capability and app-specific undo documented in [APPLICATIONS.md](docs/APPLICATIONS.md); they grant no ordinary folder or leftover authority.

Phase 4 binds a guarded finding to its complete required producer set and rejects later rule mismatches. Current-user process observations gate scanning and removal when `requiresClosedApplications` is true; running or uncertain states cannot pass. Executable and bundle-family names are incomplete heuristics, and a producer may launch or exec after a check. Bridge remains unsupported. Pure grouping preserves original findings and supplied provenance without discovering projects or granting removal authority. Default-location confirmations do not verify cache contents or broaden the compiled roots. See [creative-cache evidence](docs/CREATIVE-CACHE.md).

The local manifest uses a chained HMAC-SHA256 record format, a 0600 key and journals inside a 0700 directory, bounded parsing, file locks, and `fsync` before mutation. Authentication is local integrity protection, not encryption or a public digital signature. Anyone with the same user's key access can forge records, and truncation to a valid complete prefix is not detectable. Paths in exported journals remain sensitive; export verifies bytes but does not redact them. There is no network export endpoint.

Private staging narrows exposure to pathname substitution but is not isolation from another process running with the same UID. The Foundation Trash call still has a final pathname race; metadata checks and retained descriptors do not make it atomic or pin its destination. A final journal failure may leave a moved item without a durable Trash URL. Undo refuses unknown identities, occupied destinations, absent parents, malformed histories, and guessed locations. A guarded live integration fixture passed an ordinary-file round trip through actual Foundation Trash and public `UndoService`, under a new synthetic OS account and home in a disposable GitHub-hosted macOS VM. Account-name and UID/GID preflight assumes no concurrent account creation and is not an atomic reservation. XCTest and local fixtures continue to use fake Trash. Real cloud-provider behavior, separate volumes, Finder Put Back, macOS 14 runtime, and power-loss durability remain unverified. See [removal and recovery boundaries](docs/REMOVAL.md), [scanner boundaries](docs/SCANNING.md), and [the test plan and its limits](docs/TESTING.md).

Rule JSON is untrusted input to validation. A rule must never authorize its own safe root. Prefer conservative refusal when ownership or path identity cannot be established.

## Full Disk Access

The intended full feature set requires Full Disk Access to inspect protected locations such as Mail downloads and application containers. This is broad macOS permission and expands the impact of application bugs. Onboarding must explain what is read and why before asking. Limited scans must remain honest about inaccessible locations.

Never ask users to grant Full Disk Access to Terminal or another general-purpose shell. The app will request access under its own identity. No privileged helper is planned for v1; items requiring elevation are skipped and explained.

## Network and release integrity

Telemetry is prohibited. The 0.1.0 preview makes no application network requests and implements no update check. An explicitly chosen source link opens the browser.

Signing keys, certificates, API tokens and notarization credentials do not belong in this repository. CI uses read-only permissions, a commit-pinned checkout action and checksum-verified XcodeGen. Repository protections should be checked separately before publication. Local packaging checks universal binaries, strict ad-hoc signatures, archive hashes and extracted-bundle manifests. The implemented Developer ID/notarization workflow requires a valid installed identity and existing keychain profile; no successful notarized release is claimed without those credentials and actual Apple acceptance.

The safety contract and current enforcement map are in [SAFETY.md](SAFETY.md).
