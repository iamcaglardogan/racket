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

Phase 1 implements `SafeRoots`, read-only `PathGuard` validation and identity receipts, the declarative rule model and bundle loader, and source-policy checks. Its 62 XCTest cases comprise 31 PathGuard tests, including 10,000 generated adversarial path cases, and 31 rule tests. CI verification passed, and the owner authorized Phase 2 after the checkpoint. [Pull request 1](https://github.com/iamcaglardogan/racket/pull/1) was merged into main after the owner's explicit approval.

Only `~/Library/Caches` and `~/Library/Logs` are compiled rule roots. A root may be a directory-contents rule location but never a removal candidate. Independent protected-name checks cover preferences, project files and packages, original media, autosaves, cloud paths, and `.git`. Additional roots need a separate safety justification and adversarial coverage.

The Phase 1 bundled schema-1 document was version `1.0.0` with zero rules, retained through Phase 3. Application presence and vendor examples do not establish removal safety. Creative rules were deferred to Phase 4 verification; no cache-path claim shipped in the Phase 1 checkpoint.

The loader rejects unknown fields, duplicate JSON keys including escaped equivalents, duplicate rule IDs, missing explanations/citations, invalid bounds, unsupported matching modes, and enabled unverified rules. Every path, including a disabled rule's path, must pass the supplied compiled policy. Rule JSON cannot set a home directory, grant roots, or override protection.

`PathGuard` uses metadata-only no-follow descriptor traversal, checks flags before `fstat`, and records item and ancestor identity for later revalidation. The checks do not authorize a directory's unexamined descendants or provide an atomic Trash operation. Actual dataless hydration behavior, live mount transitions, and removal races need further work in Phases 2 and 3. [Testing notes](TESTING.md) record those limits.

## Phase 2 scope and review

The owner authorized Phase 2 after the Phase 1 checkpoint. It was developed on `phase-2-read-only-scanner`, originally based on `phase-1-trust-core`. The owner accepted the scanner checkpoint and explicitly approved merging [pull request 2](https://github.com/iamcaglardogan/racket/pull/2), which is now merged into main.

The implementation uses bulk names/flags enumeration, compiled path boundaries, no-follow descriptors, a synchronous thread policy preventing dataless materialization, explicit metadata gates, regular-file findings, Foundation total allocated size, and bounded per-module orchestration. Read [SCANNING.md](SCANNING.md) for the decision rationale, limits, scheduling, and counting semantics.

The optional schema-1 Boolean `skipExcludedFromBackup` defaults to false. No protected roots or match modes are added. Direct files have depth 1; directories at the maximum depth are reported as limited, never emitted as findings. Overlapping paths and hard links count once, with deterministic rule ownership. APFS clone sharing is not quantified, and reported allocation is not a claim of bytes that deletion would free.

The brief's request to synthesize actual dataless files cannot be met by setting SF_DATALESS on ordinary unprivileged fixtures: the SDK marks it read-only. This checkpoint uses injected flags/cloud metadata and explicit operation-order tests, supplemented by actual policy-restoration and ordinary-file checks. Genuine provider integration remains a separate prerequisite to broader enabled rules and distribution.

## Phase 3 scope and review

The owner authorized Phase 3 by asking to continue after the merged Phase 1 and 2 checkpoints. Its synthetic suite and guarded ordinary-file Foundation Trash/public-undo integration passed CI. The owner accepted the checkpoint and [PR 3](https://github.com/iamcaglardogan/racket/pull/3) merged on September 11, 2026, at `aff383d`, authorizing Phase 4.

`RemovalEngine` and `UndoService` are actors whose filesystem operations remain synchronous under the no-materialization thread policy. Removal accepts an explicit reviewed selection of at most 256 observed files, rechecks current rule scope and metadata, and requires ordinary single-link files owned by the current non-root user. The scanner now retains its complete internal metadata fingerprint; manufactured findings without that observation cannot enter a removal session.

Each file is first moved with an exclusive descriptor-relative rename into a private `.racket-staging` reservation inside its existing safe root. That name is excluded from rule declarations and findings. After identity revalidation and durable records, the sole production Trash call uses Foundation. This capture narrows exposure to replacement at the original name, but it neither closes Foundation's final pathname race nor isolates other processes running as the same user.

`ManifestStore` appends bounded NDJSON records authenticated with HMAC-SHA256 using Apple's CryptoKit framework. A session header records app and rule-set versions; each event records intent or outcome with paths, rule ID, allocated size, and file identity. Private file modes, no-follow opens, cross-instance file locks, and `fsync` protect the journal boundary. This introduces no third-party package. Local authentication does not provide confidentiality, prevent same-user forgery, or detect truncation to a complete authenticated prefix.

Undo authenticates and validates the full session history before moving any file. It requires a recorded and verified source, refuses destination conflicts, creates no missing original parent, and never guesses a Trash path by name. Interrupted records remain conservative; a final record failure can require manual recovery. Both services stop processing further items when a journal write fails.

The scope excludes directory removal, multi-link files, elevated privileges, a helper, new cleanup rules, product views, and snapshots. XCTest and local checks use private temporary homes, real Darwin namespace operations and manifests, and a fake Trash transport. They do not exercise a developer’s home, real Trash, or cloud storage. A separate guarded CI integration passed an ordinary-file round trip through actual Foundation Trash and public `UndoService`, using the public current-user APIs under a new synthetic OS account in a disposable GitHub-hosted macOS VM. The account setup assumes no concurrent account creation, and preflight is not an atomic reservation. Foundation’s destination is checked but cannot be pinned by the public API. Provider behavior remains unverified. Read [REMOVAL.md](REMOVAL.md) for failure states, recovery limits, and platform references.

## Phase 4 scope and current decisions

Phase 4 is in progress on `codex/phase-4-creative-cache` in [draft PR 4](https://github.com/iamcaglardogan/racket/pull/4). The implemented headless grouping preserves findings and explicit association provenance, keeps application-wide caches separate from unattributed project caches, and uses stable producer/project identifiers. File modification times are displayed as `lastTouched`; they do not establish when a project was last opened. No live vendor metadata resolver or product view is implemented.

The optional schema-1 Boolean `requiresClosedApplications` defaults to false. When true, scanning checks producer activity before and after each path job, and removal repeats the check before filesystem mutations. Findings retain the required producer set so a later rule change cannot silently weaken the reviewed condition. `AppActivity` observes current-user kernel process metadata; running, unsupported, or uncertain producers prevent proceeding. A successful observation is not an application lock and cannot eliminate a later launch or exec race.

Bundled rule-set version `1.1.0` contains one Camera Raw candidate with `verified: false` and `enabled: false`. Its provisional producer list includes Lightroom Classic, Photoshop, Bridge, After Effects, and the After Effects Render Engine; it is not a complete host catalogue. Bridge's executable identity remains unverified, so the declared set currently yields unknown activity. Compiled safe roots remain unchanged. Metadata observations and a read-only native-settings inspection on September 17 confirm only configured parents: Resolve uses `~/Movies`; After Effects shows `~/Library/Caches` for disk cache and `~/Library/Application Support/Adobe/Common/` for shared media cache/database. These mixed parents do not establish cache-specific scope or cleanup safety. Dedicated Resolve candidates were refused or missing, and bounded direct-name enumeration found no After Effects disk-cache candidate. No preferences or permissions were changed. [CREATIVE-CACHE.md](CREATIVE-CACHE.md) records the evidence, deferred locations, and remaining checks.

## Verification status

The Phase 1 headless core compiles locally. A limited prototype smoke check on this Mac passed ordinary-file validation, unchanged receipt revalidation, symlink-ancestor refusal, FIFO refusal, and replacement refusal. It is not execution of the complete XCTest suite. [CI run 34125991610](https://github.com/iamcaglardogan/racket/actions/runs/34125991610) passed all 62 tests through both SwiftPM and Xcode, source-policy checks, and the universal app build and architecture verification.

XCTest requires a suitable toolchain; Command Line Tools alone are not sufficient on every installation. CI uses Xcode 16.4 on macOS 15 and checks both the package and application test entry points and universal binary architectures. The target minimum is macOS 14; runtime testing on macOS 14 is still outstanding. The source-policy check rejects selected forbidden APIs and module imports as a guardrail, not a proof of all runtime behavior.

Application presence does not verify a cleanup rule. Phase 4 has a disabled candidate and synthetic coverage for grouping and producer guards; complete vendor-specific path, content, attribution, process-identity, and recovery verification remains open. No cache rule is enabled.

Phase 2 has 146 XCTest cases in total. The updated core compiled locally, source guardrails passed, and 57 narrow metadata/walker/parser smoke cases passed against synthetic fixtures. [Phase 2 CI run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143) passed all 146 cases in both test runners, source guardrails, and the universal build; the owner accepted the checkpoint and explicitly approved its merge. Those XCTest cases neither scan a developer’s real home directory nor delete their fixtures.

[Phase 3 PR CI run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716), at `780a4ad`, passed all 226 XCTest cases in each of SwiftPM and Xcode, source guardrails, the universal `arm64`/`x86_64` build, and entitlements validation. A separate local narrow harness passed 76 cases; it is not XCTest execution. The same run passed the guarded live integration: the ordinary file retained its original inode and bytes through actual Foundation Trash and public undo, and the reopened journal contained all five authenticated removal/restore actions. [TESTING.md](TESTING.md) records the evidence boundaries and remaining platform gaps.

[Phase 4 PR CI run 35216679049](https://github.com/iamcaglardogan/racket/actions/runs/35216679049), at `8f94aa5`, passed 281 XCTest cases with zero failures in each of SwiftPM and Xcode, the application build, both source-policy guardrail tests, and entitlements validation. The guarded live Foundation Trash/public-undo round trip also passed with the original inode, identical bytes, and five authenticated journal actions. A local 55-case creative fixture harness also passed; it is narrower evidence, not XCTest execution. Vendor verification and Phase 4 owner checkpoint acceptance remain pending.

## Interface proposal for later review

The naming discussion explored metal, smoke-grey, and a restrained burgundy accent. The original brief proposes cool paper neutrals and a desaturated mineral accent. Neither palette is an approved design. Resolve the visual direction in Phase 5, retaining readable tabular storage figures and project-focused cache lists. Every finding must show its path, allocated size, rule reason, and Reveal in Finder action. A single restrained scan-completion transition may create the visual signature, with Reduce Motion support.

Write and review `DESIGN.md` and the token system in Phase 5 before implementing views. This proposal is not a completed design or approval to bypass the earlier safety phases.
