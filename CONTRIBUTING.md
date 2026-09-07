# Contributing to RACKET

RACKET is being built in reviewable phases. Read [SAFETY.md](SAFETY.md) before proposing an implementation change and check the current phase in [README.md](README.md). Phase 0 is accepted; Phase 1 path and rule validation is implemented and verified in CI, with owner review pending. Keep `phase-1-trust-core` unmerged until the owner reviews the checkpoint. Scanning, removal, verified creative rules, and product interface work belong to later phases.

## Build and verify

Use a full Xcode installation with Swift 6 for `make build` and `make test`; the build prepares a pinned XcodeGen tool locally. `make core-build` compiles the Foundation-only core with Swift 6 Command Line Tools. `make core-test` additionally requires XCTest, which is absent from some Command Line Tools installations. Neither package command validates the application. See the README for the current verification limits.

Edit `project.yml`, not the generated Xcode project. Keep `Core/` independent of SwiftUI. Do not introduce a dependency without the owner's approval. Run `make check-policy` alongside the relevant tests; it flags selected destructive and networking APIs, misplaced Trash calls, and UI imports in the core. It is a source guardrail, not proof of runtime safety. Record the commands run, their results, and anything you could not verify in the pull request. See [testing scope and limits](docs/TESTING.md).

## Adding or changing a cleanup rule

The rule model and loader are implemented in Phase 1; creative rule verification and grouping follow in Phase 4. The bundled `RACKET/Core/Rules/Rules/core-v1.json` intentionally contains no rules. A rule proposal must include:

- A unique identifier, producer bundle identifiers, bounded paths and walk depth, and applicable conditions.
- A plain-language `reason` and `regenerationCost`, rendered directly in the future findings interface.
- A source citation from the application's vendor or another primary source supporting the path and its purpose.
- A risk tier that reflects the cost of recovery. Deliberate downloads and data that may be the only local copy belong in `judgement`, which is never preselected.
- Verification notes naming the application version, macOS version, path, expected contents, and whether the application must be closed. Merely finding a directory or having the app installed does not establish that its contents are safe to remove.

If a path or its behavior has not been verified, include `"verified": false` and `"enabled": false`. Missing flags default to false; explicit nulls are rejected, and an enabled unverified rule fails validation. Do not infer ownership or safe deletion from a cache-like name. When an API or path is uncertain, document the uncertainty before relying on it.

Rules cannot grant themselves removal authority. Every declaration, even a disabled rule, must pass the compiled safe-root allow-list and independent protected-root checks. Only `~/Library/Caches` and `~/Library/Logs` are enumerated in this phase. Rule data cannot specify roots, change home-directory resolution, or relax protected paths. Any proposed change to roots requires its own safety justification and adversarial tests. A directory-contents declaration may name a root, but the root itself can never be a removal candidate.

Schema 1 requires a three-part numeric document version. It supports only `directoryContents` with `maxDepth` from 1 through 32, and at most one `olderThanDays` condition from 1 through 36,500. Unknown fields and matching modes, duplicate JSON keys including escaped equivalents, duplicate IDs, missing reasons or regeneration notes, and invalid citations fail validation. Citations must be HTTPS URLs without embedded credentials. The loader caps input at 1 MiB, 1,000 rules, and 64 paths per rule; see the model for field-length limits.

Use the fixed bundle loader in the application and the explicit Data loader for synthetic tests. Supply `SafeRoots.validateRulePath` as the path validator. Validation checks declarations; future scanners and the removal boundary must still validate every actual item and protected descendant. Add tests for accepted and refused examples, including disabled unsafe rules. There is no filesystem path or network rule-loading API.

## Test data and file safety

Tests use isolated synthetic fixtures. They must never scan or mutate the real home directory, creative projects, application caches, or live cloud storage. No test, teardown, helper script, or scratch utility may permanently delete user-visible content. Test cleanup follows the same safety contract as application code; do not add deletion calls to make a test convenient.

Only the future `RemovalEngine` may call the Trash API. Until it exists and is verified, fixtures can be retained in an isolated test location. Removal tests must record the manifest before invoking Trash and prove that a failure preserves that record. Required adversarial coverage is mapped in SAFETY.md.

## Reporting a problem

Use a public issue for ordinary build bugs or feature proposals, with synthetic examples and redacted paths. Report an incorrect removal, possible data loss, path-guard bypass, or unexpected network request through the [private security report](https://github.com/iamcaglardogan/racket/security/advisories/new). Do not attach personal manifests, source media, or private filesystem paths to a public issue.
