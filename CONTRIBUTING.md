# Contributing to RACKET

Read [SAFETY.md](SAFETY.md) before changing filesystem behavior. RACKET 0.1.0 is a local preview with three enabled developer caches, a SwiftUI review/recovery flow, read-only storage inspection and conservative application-bundle removal. Creative cleanup remains disabled. [README.md](README.md) and the [dated verification report](docs/VERIFICATION-2026-10-16.md) describe the current scope and evidence.

The owner delegated completion of the full flow on October 15, 2026. Earlier phase approval stops no longer block this development run. Safety requirements and missing Apple distribution credentials still apply; do not enable an unverified rule to satisfy a feature list.

## Build and verify

Use full Xcode with a Swift 6 toolchain for `make build` and `make test`. `make core-build` can use suitable Swift 6 Command Line Tools; `make core-test` additionally needs XCTest. Core compilation/tests do not establish UI behavior or package validity.

```sh
make build
make test
make core-test
make check-policy
```

Edit `project.yml`, not the generated Xcode project. Keep Core independent of SwiftUI/AppKit and preserve Swift 6 strict concurrency. Application and core targets currently have no third-party dependencies. Proposed dependencies need a documented reason, privacy assessment and compatibility with the safety contract.

Source-policy checks flag selected permanent-deletion/network APIs, misplaced Trash calls and UI imports in Core. They are guardrails rather than proof of runtime safety. Record relevant commands, exact results and unverified cases in a PR. See [TESTING.md](docs/TESTING.md).

Release packaging is separate from building. [DISTRIBUTION.md](docs/DISTRIBUTION.md) documents `make package`, archive verification and the credential-gated `make release`. Do not describe ad-hoc packages as Developer ID signed, notarized or publicly Homebrew-installable. Debug fixture entry points must be absent from Release artifacts.

## Adding or changing a cleanup rule

Bundled `RACKET/Core/Rules/Rules/core-v1.json` version 1.2.0 enables exactly the three developer locations documented in [RULE-VERIFICATION.md](docs/RULE-VERIFICATION.md). Camera Raw remains disabled. Every proposal needs:

- A unique ID, module, complete producer set, bounded exact paths, walk depth and conditions.
- A readable reason and regeneration cost, rendered directly in cleanup review.
- A vendor or other primary source supporting the path and purpose.
- A risk tier that reflects recovery costs. Deliberate downloads or potentially unique data belong in `judgement`, which is never preselected.
- Producer/macOS versions, the expected content boundary and isolated real-producer regeneration evidence. Directory presence, app installation and owner confirmation of a default location alone do not establish safety.
- Supported process identities and helpers; use `requiresClosedApplications: true` when a fresh absence observation is required. Unknown or incomplete producer sets must refuse progress.
- Accepted/refused examples, boundary tests and synthetic integration through review, fixture Trash and undo.

Unverified proposals use `"verified": false` and `"enabled": false`. Missing flags default to false; null/nonboolean flags and enabled-unverified rules fail validation. Never infer cleanup safety merely from a cache-like name. Cache refill can still depend on a network, credentials and an available historical source; explain loss of offline availability.

Rules cannot grant themselves authority. Every declaration, including disabled ones, must pass the compiled roots and protected-name policy. Current roots are Caches, Logs, exact npm `_cacache`, and exact Xcode `ModuleCache.noindex`; the bundled enabled paths are narrower. Root changes require a separate safety justification and adversarial tests. No root itself is a removal candidate. Do not broaden authority to all `.npm` or DerivedData: those locations can contain configuration, installed tools and source checkouts.

Schema 1 requires a three-part numeric document version, `directoryContents` matching, depth 1–32 and at most one integral `olderThanDays` condition from 1–36,500. Optional Boolean `skipExcludedFromBackup` and `requiresClosedApplications` default to false and reject null/type coercion. Unknown fields/modes, duplicate JSON keys/IDs, invalid bounds, missing reasons/costs and invalid citations are rejected. Citations require HTTPS without embedded credentials. Documents are bounded to 1 MiB, 1,000 rules and 64 paths per rule.

Use `RuleSet.bundled()` for current-user production loading, or the explicit Data/fixed-resource loader with a synthetic `SafeRoots.validateRulePath` for tests. `filtered(modules:)` only narrows an already validated snapshot. No arbitrary filesystem/network rule loader exists. Scanner and removal independently recheck policy. Reserved staging names cannot become findings.

## Scanner, storage and creative work

Read [SCANNING.md](docs/SCANNING.md) before changing metadata access, traversal or size accounting. Keep no-materialization scopes synchronous, including ancestor lookup, and restore prior thread state on every exit. No explicit stat/size/content work may precede dataless gates. Injected call-order checks and ordinary-file tests do not prove real-provider behavior.

Exact finding tests need fixed reference dates and synthetic rule data. Assert skips, refusals, depth/entry/result bounds, cancellation, deterministic overlap ownership, hard-link deduplication and overflow handling. Allocation must come from allocated metadata or controlled injected values, not logical length.

The [storage explorer](docs/STORAGE.md) has separate read-only inspection authority. A chosen folder or explorer entry must never become a cleanup selection merely because it was measured. Report partial coverage and package/link/cloud skips.

Creative grouping retains original findings, byte-exact paths, complete producer sets and explicit association provenance. It performs no live project discovery. Do not infer a project from its folder name or equate file modification time with last-opened time. [CREATIVE-CACHE.md](docs/CREATIVE-CACHE.md) records deferred creative paths and producer gaps.

## Removal, recovery and app management

Read [REMOVAL.md](docs/REMOVAL.md) and [APPLICATIONS.md](docs/APPLICATIONS.md). Preserve synchronous actor operations, no-materialization scope, cross-instance locks, durable intent before moves and a stop on journal failure. Ordinary file removal requires original scanner observations matching current path, metadata, producer guard and rule. Public callers cannot manufacture a removal receipt.

App directories require the independent bounded whole-tree review and app-specific journal/undo routing. This capability does not authorize arbitrary folders or application leftovers. Preserve refusal of system/self/other-owner apps and linked/shared/dataless/protected/unsupported descendants. Review and removal must make fresh process observations.

Test substitutions before/after capture, changed trees, journal failures, uncertain transport outcomes, occupied restore destinations and interrupted recovery. Never overwrite a destination, create a missing original parent, copy/delete across volumes or guess a Trash path by name. Keep the final Foundation race, same-UID interference and HMAC limitations explicit.

## Test data and product verification

XCTest, producer harnesses and Debug UI checks use unique private temporary fixtures. They must not scan or mutate a developer's home, real caches, installed apps, creative projects, real Trash or live cloud data. Retain generated fixtures; no permanent-deletion teardown is allowed. Only `RemovalEngine` may call Foundation Trash. Local checks inject fake transport and manifest storage.

Debug UI verification uses `--verification-fixtures` and an isolated `AppRuntime.verification()` workspace. That argument/factory/synthetic rule must not exist in distributed Release binaries. Test the visible selection, hidden selections, exclusions, confirmation, cancellation, result reporting and both ordinary/app undo paths. A successful headless suite alone is not UI evidence.

The sole live-transport exception is the [guarded CI fixture](docs/TESTING.md#guarded-live-integration) under a new synthetic OS account on a disposable GitHub-hosted macOS VM. Never run its account-setup script locally or on a self-hosted runner, and never spoof guards. Preserve its account/files for the VM's lifetime. Owner-authorized read-only production use must be separately labelled and must not convert personal files into test fixtures.

## Reporting a problem

Ordinary build/feature reports should use synthetic examples and redacted paths. Incorrect removal, possible data loss, path-guard bypass or unexpected network activity belongs in a [private security report](https://github.com/iamcaglardogan/racket/security/advisories/new). Never attach personal manifests, source media or private filesystem paths to a public issue.
