# Changelog

All notable changes will be documented here using the Keep a Changelog format.
There are no releases yet.

## [Unreleased]

### Added

- Initial project documentation for El Chedo Production's planned macOS cleaner.
- Ten-point safety contract with an enforcement map distinguishing implemented controls from future requirements.
- Private security-reporting guidance and a security contact link in the issue chooser.
- MIT license and ignores for generated files, signing material, and private runtime data.
- Phase 0 contributor guidance and public bug/feature templates, with data-loss reports routed privately.
- Empty SwiftUI app, Foundation-only core framework, XCTest target, and Swift package.
- XcodeGen 2.46.0 configuration and verified build-tool download, build commands, and macOS CI.
- Read-only PathGuard with metadata-only no-follow traversal, flags-before-stat checks, and item/ancestor identity receipts for revalidation.
- Compiled Caches/Logs roots with protected-path checks and refusal of the roots themselves as removal candidates.
- Versioned rule schema and fixed bundled loader, with strict fields, duplicate JSON-key rejection, bounded matching, required explanations/citations, and disabled unverified rules.
- Empty schema-1 rule document; no cache path is enabled or claimed verified.
- 31 PathGuard tests, including 10,000 generated adversarial paths, and 31 rule-validation tests using synthetic data.
- CI source-policy guardrails for selected destructive/networking APIs, misplaced Trash calls, and UI imports in the core.
- Testing documentation that records unverified dataless hydration, live mount transitions, directory-descendant safety, and the remaining Trash race.
- Phase 2 read-only bulk directory walker, dataless metadata gates and per-thread materialization policy, with regular-file findings and visible skip/refusal/incomplete reasons.
- Bounded scan orchestration, cancellation, per-module path progress, age/explicit backup filters, deterministic overlap and hard-link deduplication, and checked `UInt64` allocated-size totals.
- Scanner architecture and verification notes separating allocated observations from reclaimable physical space, and synthetic metadata checks from cloud-provider integration.
- 84 additional tests; the 146-test suite passed in SwiftPM and Xcode, alongside universal build and source guardrails.
- Phase 3 headless removal for explicit reviewed selections of observed, owned single-link files, with independent rule checks and private staging inside the existing safe roots.
- Authenticated NDJSON session records with app/rule-set versions, pre-move intent, resulting paths, bounded parsing, private key storage, cross-instance locks, and synchronized writes.
- Undo from verified Trash or staging locations, with exclusive moves, destination-conflict refusal, interrupted-operation handling, and a stop on journal failure.
- Synthetic scan-observation, manifest, removal, and undo cases using real temporary filesystem operations and a fake Trash transport; execution evidence is pending.
- Removal and recovery documentation covering the final Foundation pathname race, local authentication limits, uncertain outcomes, and unverified platform integration.

### Changed

- Selected **RACKET** as the product name and updated the repository links for `iamcaglardogan/racket`.
- Confirmed `io.github.iamcaglardogan.racket` as the application identifier.
- Documented the Phase 0 build commands, local Xcode limitation, and separation between core checks and application validation.
- Recorded owner acceptance of Phase 0 and prepared the Phase 1 trust-core checkpoint for separate pull-request review.
- Recorded owner acceptance and merging of Phases 1 and 2 through pull requests [1](https://github.com/iamcaglardogan/racket/pull/1) and [2](https://github.com/iamcaglardogan/racket/pull/2), and authorization to develop Phase 3.
- Scanner findings now retain their internal metadata fingerprint for removal-time comparison; `.racket-staging` is reserved from rule paths and findings.

### Fixed

- Scanner hard-link observations now bind to verified parent entries and fresh no-follow identities, rather than assuming a regular inode has one reverse-resolved path. Added name-cache and ordinary-file substitution regressions.

### Pending

- Phase 3 verification and owner checkpoint review.
- Owner confirmation of shipping CLI scope and final network policy.
