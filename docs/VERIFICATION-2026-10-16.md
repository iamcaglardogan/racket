# RACKET 0.1.0 preview verification — 16 October 2026

**Status: IN PROGRESS.** Local Core/Release validation and real pointer journeys have passed. Final Command-F behavior, corrected final archives and the current hosted CI/live Foundation integrations still require their recorded outcomes. The older package is not the ready artifact. Dates use Europe/Istanbul; preserved filenames may retain their initial-session date.

## Version and environment

- Product 0.1.0, build 1; rule document 1.2.0; identifier `io.github.iamcaglardogan.racket`.
- Validated production source: `274b759259e8b23c89f4d9075f134e86d422c415`. A subsequent Command-F focus correction is in progress; final source/archive provenance must be entered below.
- Local host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple Clang 21.0.0 (`clang-2100.3.34.2`).
- Deployment target macOS 14.0; both arm64 and x86_64 Release slices are built. macOS 14 and Intel runtime coverage remain unverified.
- Distribution target is a local ad-hoc signed app/ZIP/DMG. No valid Developer ID identity is available; no Apple notarization or public Homebrew-release claim is made.

## Completed local checks

| Check | Result | Exact evidence |
| --- | --- | --- |
| Debug Core suite | **347 tests, zero failures** | `/private/tmp/RACKET-Rules-DebugRegression-20261016.log` |
| Actual Release Core suite | **343 tests, zero failures**, without enabling Debug fixture code | `/private/tmp/RACKET-ReleaseRules-20261016-after.log` |
| Xcode app-flow and native geometry suite | **5 tests passed**: reviewed scan/conflict/undo, exclusions/busy guards, application/storage journey, actual visible app row/path, full-window list viewports | `/private/tmp/RACKET-AppFlowGeometryFinalTests.log`; result bundle `/private/tmp/racket-product-tests/Logs/Test/Test-RACKET-2026.10.16_08-12-30-+0300.xcresult` |
| Source policy and diff checks | Passed after rule-validation fix | `scripts/check-source-policy.py`; final source/package checks remain part of finalization |
| Rebuilt universal Release installation check | **Passed**: version 0.1.0, rule document 1.2.0, all three expected enabled developer IDs, telemetry false | `/private/tmp/racket-product-derived/Build/Products/Release/RACKET.app/Contents/MacOS/RACKET --verify-installation` |
| External optimized-framework ID regression | Five valid-ID refusals before fix; **zero mismatches after fix**; slash/non-ASCII IDs still refused | `/private/tmp/RACKET-ReleaseRuleEvidence-20261016/framework-before.log` and `framework-after.log` |
| Real npm regeneration | Missing blob refetched with its index retained; empty `_cacache` regenerated; three offline installs matched; fixture cache verified | `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json` |
| Real Clang regeneration | PCM regenerated; identical executable bytes and successful behavior; generated sources unchanged | Same evidence JSON |
| Real Homebrew regeneration | Actual disposable checkout refetched identical local-file formula download; no formula installed | Same evidence JSON; source `be9411f7d2cef522201891d38260c63e66da88f7` |
| Production app inventory smoke | Metadata only: 110 discovered, 20 preliminarily eligible, 90 protected, 15 unavailable/skipped, depth limit indicated | [APPLICATIONS.md](APPLICATIONS.md); no real application removed |

The Debug/Release count differs by four Debug-only fixture tests. Initial counts of 329/345 and the earlier 3-app-test run predate the fixes above. [TESTING.md](TESTING.md) separates configuration, synthetic, producer and historical CI evidence; [RULE-VERIFICATION.md](RULE-VERIFICATION.md) records exact enabled paths, versions, hashes and regeneration limits.

## Real native interactions on synthetic data

The computer-use service initially timed out and later recovered. Actual pointer interaction then verified these journeys; screenshots are inline in the working conversation. A separate `NATIVE-VERIFICATION-2026-10-16.md` evidence record is being prepared.

- **File cleanup:** scan produced four synthetic files, Select Visible selected all four, confirmation showed the four exact paths, fixture Trash reported 4/4 moved, and Recovery restored 4/4.
- **Application cleanup after native layout correction:** workspace `/private/tmp/RACKET-UI-D3642BCC-44F8-4114-A858-208BE745DF03` displayed one visible `Sample Tool` row and its actual path. Review confirmed that exact synthetic bundle, fixture Trash reported 1/1 moved, and app-specific Recovery restored 1/1.
- **Storage:** the same isolated journey showed 475 KB across 17 entries with partial coverage from one package skip. Exploration granted no cleanup authority.
- **Native UI/accessibility observations:** real controls and accessibility roles/labels were observed. The corrected app/storage lists occupied visible window viewports. Command-1 navigation and Command-R scan passed. Command-F focus is undergoing its final correction/check.
- **Model assertions:** the five app tests cover hidden selections remaining fully reviewable, exact exclusions, exclusion changes refused while busy, conflict preservation/details and both ordinary/app recovery routing. These assertions do not establish every pointer/cancellation path or OS notification/login behavior.

All removal interactions above used isolated fixtures and fake Trash with real namespace moves. They neither removed personal cache files nor used the owner's real Trash. VoiceOver was **not run**; no accessibility-compliance claim follows from pointer checks, labels, geometry or screenshots.

## Failures caught and corrected

1. **Optimized Release rule loading:** archive hashes, signatures and Debug tests passed, but the old Release app's bundle-only installation check rejected valid ASCII rule IDs. An external harness linked to that optimized framework reproduced five valid-ID refusals. Direct UTF-8 ASCII grammar validation preserved the exact accepted alphabet and all text/length gates. Exhaustive ASCII/Unicode/boundary regressions, 347 Debug tests, 343 actual Release tests and the rebuilt app self-check passed. The older `dist/local-0.1.0` artifact is therefore **superseded**, despite passing earlier archive-integrity checks.
2. **Native list geometry:** a synthetic application existed but its list row was not visibly usable in the full window. The native viewport correction now has mounted-row/full-window geometry assertions and a real pointer app review/removal/undo journey.
3. **Older CI compiler failure:** Swift 6.1.2 IRGen crashed while adapting the actor-isolated Boolean `setLogin` method reference for a binding. Replacing that reference with an explicit closure addressed the reported trigger. New hosted runs are in progress; no success is inferred from the local Swift 6.4 results.

## Checks still in progress

| Check | Current state | Evidence/result to enter |
| --- | --- | --- |
| Command-F native search focus | Correction in progress | Record actual keyboard-focus result and final source commit |
| Current hosted CI | Latest runs for `274b759` reported in progress | [Run 38854687814](https://github.com/iamcaglardogan/racket/actions/runs/38854687814), [run 38854683505](https://github.com/iamcaglardogan/racket/actions/runs/38854683505); record final conclusion |
| Current ordinary-file/app-bundle Foundation Trash integration | Awaiting hosted disposable-account results | Record actual ordinary and complete app-tree round trips; fake transport/local tests do not substitute |
| Corrected final universal Release app | Rebuild after final keyboard correction required | Record source/build log, three-rule installation self-check and app/framework slices |
| Final ZIP/DMG signatures, hashes and extracted manifests | Packaging agent preparing corrected `dist/local-0.1.0-final` output | Record verifier result, final checksums and explicit ad-hoc status |
| Release fixture-code exclusion | Must pass for corrected final output | Record final binary verifier result |
| Corrected packaged app launch/self-check | Awaiting corrected final package | Record exact packaged path and successful bundle diagnostic/launch |
| Production read-only cleanup scan | No final aggregate outcome entered | If performed, report separately from fixture tests; no personal data as disposable inputs |

Elapsed schedule triggering, OS notification delivery, Login Items approval, pointer cancellation and full keyboard/VoiceOver coverage have not been established by the completed journeys. Scheduling remains scan-only by implementation and product contract.

## Final artifact record — awaiting corrected package

Do not use the superseded `dist/local-0.1.0` archive as the ready build.

- Intended corrected output: `dist/local-0.1.0-final/` — **not yet recorded as verified**.
- Verified local app/ZIP/DMG: **awaiting final output**.
- Exact `SHA256SUMS`, `BUNDLE-MANIFEST.json`, `DISTRIBUTION.txt` and verification log: **awaiting final output**.
- Final source and keyboard-check evidence: **awaiting final entry**.
- Native evidence index: **being prepared**; inline conversation screenshots are currently the pointer evidence.

## Remaining product/platform limits

- No Developer ID/Apple notarization/public Homebrew release. Ad-hoc signatures verify local integrity and do not identify an Apple-approved publisher.
- Camera Raw/broader creative cleanup and live project resolution remain disabled/unavailable.
- General system/log sweeping, broad DerivedData cleanup, scheduled automatic removal, exhaustive app leftovers, snapshots and shipping CLI are not implemented.
- macOS 14/Intel runtime, genuine cloud providers, separately mounted volumes and power-loss recovery remain unverified. Live app-bundle Foundation coverage depends on the still-running hosted result above.
- Historical ordinary-file Foundation Trash/public undo passed on a disposable hosted account; that does not imply the new preview's current app-bundle CI has passed.
- Core operations retain the documented same-UID interference, final Foundation pathname race and journal-authentication limitations.

The verified local behavior is a deliberately scoped preview, not full cleaner parity or universal platform certification. Final artifact/CI completion must be entered before changing this report's in-progress status.
