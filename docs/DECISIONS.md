# Project decisions

## Confirmed by the owner

- Agency: El Chedo Production.
- Product: a free, open-source, native macOS cleaner under the MIT license.
- Minimum operating system: macOS 14.0.
- Creative priorities: DaVinci Resolve, After Effects, Photoshop, and additional creative applications as rules can be verified.
- Interface quality is a priority; it should feel distinctive while remaining calm, legible, and honest.
- Start a GitHub repository and prioritize the safety contract.
- Apple Developer Team ID is not currently available. Account setup and distribution signing are deferred.
- Preserve the review checkpoint after each phase of the supplied build brief.

## Open product choices

- Final product name and bundle identifier prefix. No application identifier will be generated before this decision.
- A separate shipping CLI: recommended outside v1; the owner questioned its value and prefers investing in the interface.
- Networking: recommend no application network requests for the first version. An optional GitHub version check remains a separate decision. GitHub use by contributors and CI does not require networking in the shipped app.

## Repository preparation

Use `maccleanerapp` as a temporary repository name based on the existing workspace directory. This is not a product naming decision. The original brief calls for an open-source project, so the repository is public. Rename it and update documentation links once the name is selected.

Do not add scanning, removal, application targets, or a guessed bundle identifier during this preparation step. Phase 0 remains incomplete until its empty application and test targets build and its required automation is verified.

## Verification status

Build verification is pending. A supported full Xcode environment and XcodeGen are required. Do not claim the macOS application builds until the requested build tooling and empty targets have been configured and tested.

Application presence does not verify a cleanup rule. Cache paths, project attribution, running-process behavior, and deletion safety have not been verified. No cache rule is enabled or shipped.

## Interface proposal for later review

Explore a cool paper neutral palette with a desaturated mineral accent, large tabular storage figures, a readable disk-usage visualization, and project-focused cache lists. Every finding must show its path, allocated size, rule reason, and Reveal in Finder action. A single restrained scan-completion transition may create the visual signature, with Reduce Motion support.

Write and review `DESIGN.md` and the token system in Phase 5 before implementing views. This proposal is not a completed design or approval to bypass the earlier safety phases.
