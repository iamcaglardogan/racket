# Security policy

## Report a security issue privately

Use [GitHub's private vulnerability reporting form](https://github.com/iamcaglardogan/racket/security/advisories/new) for a potential data-loss bug, an incorrect removal rule, a path-guard bypass, or an unexpected network request. Do not put private filesystem paths, manifests, or work files in a public issue.

Include the affected commit or release, macOS version, rule identifier if relevant, expected behavior, and steps to reproduce with synthetic files where possible. Share a redacted manifest only when it helps explain the issue. There is no response-time guarantee at this preparation stage.

If an eventual build moves an unexpected item to Trash, stop that removal session, preserve its manifest, and avoid emptying Trash. Recovery is planned but not implemented in this repository yet.

## Supported versions

There are no releases or distributed builds yet. Phase 0 contains development scaffolding only, with no scanning or cleanup feature. Security reports about the evolving design are welcome. Release support and patch policy will be documented before distribution.

## Threat model

The application will operate on valuable local files. Assets include source media, project databases, application settings, credentials, and recoverable items in Trash. Threats include incorrect rules, symlink escapes, path substitution races, malicious filesystem metadata, cloud placeholder hydration, incorrect ownership attribution, and compromised build inputs.

Planned controls include compiled safe roots, independent protected roots, bounded walks, dataless checks, revalidation at removal, reviewable findings, pre-removal manifest writes, and a single removal gateway. None is implemented or tested yet.

Rule JSON is untrusted input to validation. A rule must never authorize its own safe root. Prefer conservative refusal when ownership or path identity cannot be established.

## Full Disk Access

The intended full feature set requires Full Disk Access to inspect protected locations such as Mail downloads and application containers. This is broad macOS permission and expands the impact of application bugs. Onboarding must explain what is read and why before asking. Limited scans must remain honest about inaccessible locations.

Never ask users to grant Full Disk Access to Terminal or another general-purpose shell. The app will request access under its own identity. No privileged helper is planned for v1; items requiring elevation are skipped and explained.

## Network and release integrity

Telemetry is prohibited. The product decision about a default-off GitHub update check is pending; no application networking code exists.

Signing keys, certificates, API tokens, and notarization credentials do not belong in this repository. CI uses read-only permissions, a commit-pinned checkout action, and a checksum-verified XcodeGen release. GitHub secret scanning, push protection, and private vulnerability reporting are enabled. Release signing and notarization will be configured after the owner supplies the required developer account setup.

The safety contract and its planned enforcement map are in [SAFETY.md](SAFETY.md).
