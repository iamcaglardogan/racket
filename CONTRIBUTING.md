# Contributing to RACKET

RACKET is being built in reviewable phases. Read [SAFETY.md](SAFETY.md) before proposing an implementation change and check the current phase in [README.md](README.md). Complete the current phase's checks and owner review before starting the next one. Phase 0 does not include scanning, removal, cleanup rules, or product interface work.

## Build and verify

Use a full Xcode installation with Swift 6 for `make build` and `make test`; the build prepares a pinned XcodeGen tool locally. `make core-build` compiles the Foundation-only core with Swift 6 Command Line Tools. `make core-test` additionally requires XCTest, which is absent from some Command Line Tools installations. Neither package command validates the application. See the README for the current verification limits.

Edit `project.yml`, not the generated Xcode project. Keep `Core/` independent of SwiftUI. Do not introduce a dependency without the owner's approval. Record the commands run, their results, and anything you could not verify in the pull request. Passing an empty suite establishes only that the test runner works.

## Adding or changing a cleanup rule

Rule implementation starts in Phase 1; creative rule verification and grouping follow in Phase 4. A rule proposal must include:

- A unique identifier, producer bundle identifiers, bounded paths and walk depth, and applicable conditions.
- A plain-language `reason` and `regenerationCost`, rendered directly in the future findings interface.
- A source citation from the application's vendor or another primary source supporting the path and its purpose.
- A risk tier that reflects the cost of recovery. Deliberate downloads and data that may be the only local copy belong in `judgement`, which is never preselected.
- Verification notes naming the application version, macOS version, path, expected contents, and whether the application must be closed. Merely finding a directory or having the app installed does not establish that its contents are safe to remove.

If a path or its behavior has not been verified, include `"verified": false`. Unverified rules must remain disabled and must not ship enabled. Do not infer ownership or safe deletion from a cache-like name. When an API or path is uncertain, document the uncertainty before relying on it.

Rules cannot grant themselves removal authority. Their paths must pass the compiled safe-root allow-list and independent protected-root checks. Preferences, project databases, original media, autosaves, and offline copies need explicit protection. Any proposed change to safe roots requires its own safety justification and adversarial tests.

Validation must reject missing reasons, regeneration notes, citations, duplicate identifiers, unsafe roots, and enabled unverified rules. Include synthetic examples of what must match and what must be refused. These checks are planned; do not claim that the Phase 0 scaffold implements the rule validator.

## Test data and file safety

Tests use isolated synthetic fixtures. They must never scan or mutate the real home directory, creative projects, application caches, or live cloud storage. No test, teardown, helper script, or scratch utility may permanently delete user-visible content. Test cleanup follows the same safety contract as application code; do not add deletion calls to make a test convenient.

Only the future `RemovalEngine` may call the Trash API. Until it exists and is verified, fixtures can be retained in an isolated test location. Removal tests must record the manifest before invoking Trash and prove that a failure preserves that record. Required adversarial coverage is mapped in SAFETY.md.

## Reporting a problem

Use a public issue for ordinary build bugs or feature proposals, with synthetic examples and redacted paths. Report an incorrect removal, possible data loss, path-guard bypass, or unexpected network request through the [private security report](https://github.com/iamcaglardogan/racket/security/advisories/new). Do not attach personal manifests, source media, or private filesystem paths to a public issue.
