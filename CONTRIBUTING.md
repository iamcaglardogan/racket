# Contributing to RACKET

RACKET is being built in reviewable phases. Read [SAFETY.md](SAFETY.md) before proposing an implementation change and check the current phase in [README.md](README.md). The owner accepted Phases 1 and 2, merged through pull requests [1](https://github.com/iamcaglardogan/racket/pull/1) and [2](https://github.com/iamcaglardogan/racket/pull/2), and authorized Phase 3. Headless removal, manifests, and undo passed 226 XCTest cases in both runners and a guarded ordinary-file Foundation Trash/public-undo integration in [CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716) at `780a4ad`. The Phase 3 owner checkpoint in [draft PR 3](https://github.com/iamcaglardogan/racket/pull/3) remains pending. Phase 4 has not begun. Verified creative rules and product interface work remain later phases.

## Build and verify

Use a full Xcode installation with Swift 6 for `make build` and `make test`; the build prepares a pinned XcodeGen tool locally. `make core-build` compiles the headless core with Swift 6 Command Line Tools; CryptoKit is an Apple platform framework, not a third-party dependency. `make core-test` additionally requires XCTest, which is absent from some Command Line Tools installations. Neither package command validates the application. See the README for the current verification limits.

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

Schema 1 requires a three-part numeric document version. It supports only `directoryContents` with `maxDepth` from 1 through 32, and at most one `olderThanDays` condition from 1 through 36,500. Phase 2 adds the optional Boolean `skipExcludedFromBackup`, which defaults to false; explicit nulls and other types are rejected. Only explicit true enables this filter, and the scanner reports excluded items. Unknown fields and matching modes, duplicate JSON keys including escaped equivalents, duplicate IDs, missing reasons or regeneration notes, and invalid citations fail validation. Citations must be HTTPS URLs without embedded credentials. The loader caps input at 1 MiB, 1,000 rules, and 64 paths per rule; see the model for field-length limits.

Use the fixed bundle loader in the application and the explicit Data loader for synthetic tests. Supply `SafeRoots.validateRulePath` as the path validator. Validation checks declarations; the scanner independently checks rule paths and actual children, and the removal boundary rechecks its own scope and the current rule. Add tests for accepted and refused examples, including disabled unsafe rules. There is no filesystem path or network rule-loading API. The reserved `.racket-staging` name cannot become a rule location or scan finding.

## Changing the scanner

Read [SCANNING.md](docs/SCANNING.md) before changing metadata access, traversal, scheduling, or size totals. Keep the entire no-materialization policy scope synchronous, including ancestor lookup, and preserve its restoration on error. No size query or regular-file content read may precede dataless gates. Test injected metadata call order independently of ordinary-file integration; do not describe either as proof against real provider hydration.

Use a fixed reference date and synthetic rule data for exact findings tests. Assert reported skips and refusals as well as findings, depth and entry limits, cancellation, deterministic overlapping-rule behavior, hard-link deduplication, and overflow refusal. Allocated-size expectations must come from allocated metadata or controlled injected values, not logical file length. Do not add directory findings or enable cache rules to make the test harness more convenient.

## Test data and file safety

XCTest and local checks use isolated synthetic fixtures. They must never scan or mutate a developer’s home directory, creative projects, application caches, real Trash, or live cloud storage. No test, teardown, helper script, or scratch utility may permanently delete user-visible content. Test cleanup follows the same safety contract as application code; do not add deletion calls to make a test convenient.

Only `RemovalEngine` may call the Trash API. XCTest and local fixtures retain all files inside unique private temporary homes and use an injected fake Trash transport and manifest location; they must not invoke the live transport or use the production manifest initializer.

The sole exception for live transport and production manifest initialization is the guarded [CI integration fixture](docs/TESTING.md#guarded-live-integration): it runs only on a disposable GitHub-hosted macOS VM under a new synthetic OS account whose actual home is the fixture directory. Never run `scripts/check-live-trash.sh` locally or on a self-hosted runner, and never spoof its environment guards. The fixture must use public Core entry points, with no direct Trash call, and preserve its account and files for the VM’s lifetime. Its account preflight is not an atomic reservation; concurrent account setup is outside this disposable-job assumption.

Removal tests must record the manifest before invoking the transport and prove that a failure preserves that record. Required adversarial coverage is mapped in SAFETY.md.

## Changing removal or recovery

Read [REMOVAL.md](docs/REMOVAL.md) before changing the transaction order. Preserve synchronous actor operations, the no-materialization thread scope, the cross-instance operation lock, durable intent records, and a stop on journal failure. Accept only explicitly supplied scan observations that still match the current path, metadata, and rule; a synthetic test `Finding` without the scanner’s internal metadata observation is not a removal authorization. `Finding` has no public initializer.

Test substitutions before and after capture, failed journal writes, uncertain transport outcomes, occupied restore destinations, and interrupted operations. No fallback may overwrite a destination, recreate a missing original parent, move a directory as a removal unit, copy across volumes, or guess a Trash location by name. Keep the remaining Foundation race and the limits of local manifest authentication visible in documentation and review notes.

## Reporting a problem

Use a public issue for ordinary build bugs or feature proposals, with synthetic examples and redacted paths. Report an incorrect removal, possible data loss, path-guard bypass, or unexpected network request through the [private security report](https://github.com/iamcaglardogan/racket/security/advisories/new). Do not attach personal manifests, source media, or private filesystem paths to a public issue.
