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

## Phase 0 scope

The public repository is `iamcaglardogan/racket`. The workspace folder may retain its original name. Creator attribution to El Chedo Production remains separate from the RACKET product identity.

Phase 0 includes the source directory structure, empty app and test targets, XcodeGen configuration, build commands, CI, contributor guidance, and safety documentation. A Swift package provides a Foundation-only core build with Swift 6 Command Line Tools and a headless test path with XCTest. It is a development check, not a shipping CLI.

Do not add scanning, removal, cleanup rules, permission prompts, or product views during Phase 0. Its empty app entry point exists solely to verify the application target. Stop for the owner's review before Phase 1.

## Verification status

XcodeGen generation, the headless core build, and Swift 6 strict-concurrency typechecking of the empty app have passed locally. Full application build and test verification are pending CI with Xcode 16.4. XCTest requires a suitable toolchain; Command Line Tools alone are not sufficient on every installation. Do not treat an empty test suite as evidence that cleanup is safe. Phase 0 is not complete until its required build and CI checks have been verified.

Application presence does not verify a cleanup rule. Cache paths, project attribution, running-process behavior, and deletion safety have not been verified. No cache rule is enabled or shipped.

## Interface proposal for later review

The naming discussion explored metal, smoke-grey, and a restrained burgundy accent. The original brief proposes cool paper neutrals and a desaturated mineral accent. Neither palette is an approved design. Resolve the visual direction in Phase 5, retaining readable tabular storage figures and project-focused cache lists. Every finding must show its path, allocated size, rule reason, and Reveal in Finder action. A single restrained scan-completion transition may create the visual signature, with Reduce Motion support.

Write and review `DESIGN.md` and the token system in Phase 5 before implementing views. This proposal is not a completed design or approval to bypass the earlier safety phases.
