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

### Changed

- Selected **RACKET** as the product name and updated the repository links for `iamcaglardogan/racket`.
- Confirmed `io.github.iamcaglardogan.racket` as the application identifier.
- Documented the Phase 0 build commands, local Xcode limitation, and separation between core checks and application validation.
- Recorded owner acceptance of Phase 0 and prepared the Phase 1 trust-core checkpoint for separate pull-request review.

### Pending

- Owner confirmation of shipping CLI scope and final network policy.
- Phase 1 owner review before merging `phase-1-trust-core` or beginning Phase 2.
