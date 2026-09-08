# Project decisions

## Confirmed by the owner

- Agency: El Chedo Production.
- Product name: **RACKET**. The owner selected it after asking for a name independent of the agency name.
- Application identifier: `io.github.iamcaglardogan.racket`, explicitly confirmed by the owner.
- Product: a free, open-source, native macOS cleaner under the MIT license.
- Minimum operating system: macOS 14.0.
- Creative priorities: DaVinci Resolve, After Effects, Photoshop, and additional creative applications as rules can be verified.
- Interface quality is a priority; it should feel distinctive while remaining calm, legible, and honest.
- Start a GitHub repository and prioritize the safety contract.
- Apple Developer Team ID is not currently available. Account setup and distribution signing are deferred.
- Preserve the review checkpoint after each phase of the supplied build brief.

## Open product choices

- A separate shipping CLI: recommended outside v1; the owner questioned its value and prefers investing in the interface.
- Networking: recommend no application network requests for the first version. An optional GitHub version check remains a separate decision. GitHub use by contributors and CI does not require networking in the shipped app.

## Accepted Phase 0

The public repository is `iamcaglardogan/racket`. The workspace folder may retain its original name. Creator attribution to El Chedo Production remains separate from the RACKET product identity.

Phase 0 includes the source directory structure, empty app and test targets, XcodeGen configuration, build commands, CI, contributor guidance, and safety documentation. A Swift package provides a Foundation-only core build with Swift 6 Command Line Tools and a headless test path with XCTest. It is a development check, not a shipping CLI.

The owner accepted Phase 0 by asking to continue. Its empty app entry point exists solely to verify the application target. That acceptance authorizes Phase 1, not later scanning, removal, permissions, or product views.

## Phase 1 scope and review

Phase 1 implements `SafeRoots`, read-only `PathGuard` validation and identity receipts, the declarative rule model and bundle loader, and source-policy checks. Its 62 XCTest cases comprise 31 PathGuard tests, including 10,000 generated adversarial path cases, and 31 rule tests. The checkpoint is prepared for a pull request from `phase-1-trust-core`; CI verification passed, owner review is pending, and it must remain unmerged until reviewed.

Only `~/Library/Caches` and `~/Library/Logs` are compiled rule roots. A root may be a directory-contents rule location but never a removal candidate. Independent protected-name checks cover preferences, project files and packages, original media, autosaves, cloud paths, and `.git`. Additional roots need a separate safety justification and adversarial coverage.

The bundled schema-1 document is version `1.0.0` with zero rules. Application presence and vendor examples do not establish removal safety. Creative rules stay deferred to Phase 4 verification; no enabled or unverified cache-path claim ships in this checkpoint.

The loader rejects unknown fields, duplicate JSON keys including escaped equivalents, duplicate rule IDs, missing explanations/citations, invalid bounds, unsupported matching modes, and enabled unverified rules. Every path, including a disabled rule's path, must pass the supplied compiled policy. Rule JSON cannot set a home directory, grant roots, or override protection.

`PathGuard` uses metadata-only no-follow descriptor traversal, checks flags before `fstat`, and records item and ancestor identity for later revalidation. The checks do not authorize a directory's unexamined descendants or provide an atomic Trash operation. Actual dataless hydration behavior, live mount transitions, and removal races need further work in Phases 2 and 3. [Testing notes](TESTING.md) record those limits.

## Verification status

The Phase 1 headless core compiles locally. A limited prototype smoke check on this Mac passed ordinary-file validation, unchanged receipt revalidation, symlink-ancestor refusal, FIFO refusal, and replacement refusal. It is not execution of the complete XCTest suite. [CI run 34125991610](https://github.com/iamcaglardogan/racket/actions/runs/34125991610) passed all 62 tests through both SwiftPM and Xcode, source-policy checks, and the universal app build and architecture verification.

XCTest requires a suitable toolchain; Command Line Tools alone are not sufficient on every installation. CI uses Xcode 16.4 on macOS 15 and checks both the package and application test entry points and universal binary architectures. The target minimum is macOS 14; runtime testing on macOS 14 is still outstanding. The source-policy check rejects selected forbidden APIs and module imports as a guardrail, not a proof of all runtime behavior.

Application presence does not verify a cleanup rule. Cache paths, project attribution, running-process behavior, and deletion safety have not been verified. No cache rule is enabled or shipped.

## Interface proposal for later review

The naming discussion explored metal, smoke-grey, and a restrained burgundy accent. The original brief proposes cool paper neutrals and a desaturated mineral accent. Neither palette is an approved design. Resolve the visual direction in Phase 5, retaining readable tabular storage figures and project-focused cache lists. Every finding must show its path, allocated size, rule reason, and Reveal in Finder action. A single restrained scan-completion transition may create the visual signature, with Reduce Motion support.

Write and review `DESIGN.md` and the token system in Phase 5 before implementing views. This proposal is not a completed design or approval to bypass the earlier safety phases.
