# RACKET 0.1.0 preview verification — 16 October 2026

**Status: READY — verified local preview.** Runtime **`4ccfa68`** passed actual native focus/filter journeys, 350 hosted Core tests, seven app tests, current archive checks and both hosted CI runs. One run required a transparent retry after a read-only unknown-activity refusal; the failed attempt remains recorded. The promoted artifact is **`dist/local-0.1.0-keyboard-verified`**. Prior `30e92c7` receipts remain historical. Dates use Europe/Istanbul.

## Version and environment

- Product 0.1.0, build 1; rule document 1.2.0; identifier `io.github.iamcaglardogan.racket`.
- Current native-search runtime: **`4ccfa684597f48b3352d1919d0c202dba6a2b401`**, committed/pushed. Core files are unchanged from the previously validated **`30e92c7efddee550a21e3bce4a36749faebaf887`**; its archive/CI receipts remain tied to that earlier source.
- Local host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple Clang 21.0.0 (`clang-2100.3.34.2`).
- Deployment target macOS 14.0; both arm64 and x86_64 Release slices are built. macOS 14 and Intel runtime coverage remain unverified.
- An explicit x86_64 installation-check attempt on this Apple Silicon host returned `Bad CPU type in executable`; Rosetta is unavailable here. That attempt provides no Intel runtime result (`/private/tmp/racket-intel-installation-check.err`).
- Distribution target is a local ad-hoc signed app/ZIP/DMG. No valid Developer ID identity is available; no Apple notarization or public Homebrew-release claim is made.

## Completed local checks

| Check | Result | Exact evidence |
| --- | --- | --- |
| Prior Debug Core suite | **350 tests, zero failures at `30e92c7`** in SwiftPM and Xcode; current Core sources unchanged | `/private/tmp/RACKET-CoreFinalProcessTests.log`; `/private/tmp/racket-product-xcode-final-tests.log` |
| Prior actual Release Core suite | **346 tests, zero failures at `30e92c7`**, without enabling Debug fixture code; current Core sources unchanged | `/private/tmp/racket-product-release-tests.log` |
| Current Xcode app-flow/native suite | **7 tests passed at `4ccfa68`**, adding actual native search focus/recreation/window-routing regressions to the earlier five flows | `/private/tmp/RACKET-NativeSearchFinalAppFlowTests.log`; result bundle `/private/tmp/racket-product-tests/Logs/Test/Test-RACKET-2026.10.16_10-10-34-+0300.xcresult` |
| Current hosted Debug/app checks | **350 Core + 7 app tests passed**; both completed successful runs include actual Foundation file/app recovery | Run `38865863334` attempt 1; run `38865857832` attempt 2; original refused attempt preserved below |
| Prior source policy/entitlements | Passed local and hosted checks at `30e92c7` | `scripts/check-source-policy.py`; prior successful CI below |
| Prior universal Release installation check | **Passed at `30e92c7`**: version 0.1.0, document 1.2.0, three enabled IDs, telemetry false | Earlier Release/package receipts; the promoted `4ccfa68` package has separate current receipts |
| External optimized-framework ID regression | Five valid-ID refusals before fix; **zero mismatches after fix**; slash/non-ASCII IDs still refused | `/private/tmp/RACKET-ReleaseRuleEvidence-20261016/framework-before.log` and `framework-after.log` |
| Real npm regeneration | Missing blob refetched with its index retained; empty `_cacache` regenerated; three offline installs matched; fixture cache verified | `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json` |
| Real Clang regeneration | PCM regenerated; identical executable bytes and successful behavior; generated sources unchanged | Same evidence JSON |
| Real Homebrew regeneration | Actual disposable checkout refetched identical local-file formula download; no formula installed | Same evidence JSON; source `be9411f7d2cef522201891d38260c63e66da88f7` |
| Production app inventory smoke | Metadata only: 110 discovered, 20 preliminarily eligible, 90 protected, 15 unavailable/skipped, depth limit indicated | [APPLICATIONS.md](APPLICATIONS.md); no real application removed |

Fresh `4ccfa68` hosted runs verified 350 Core tests and seven app tests. The 346-test Release Core result remains prior `30e92c7` evidence reused only because both Core sources and the exact framework digest are unchanged; no fresh Release Core execution is implied. Four Debug-only fixtures explain the Core count difference. [TESTING.md](TESTING.md) separates source/configuration evidence; [RULE-VERIFICATION.md](RULE-VERIFICATION.md) records exact enabled paths, versions, hashes and regeneration limits.

## Real native interactions on synthetic data

The computer-use service initially timed out and later recovered. Actual pointer interaction then verified these journeys; screenshots are inline in the working conversation and summarized in [native verification](NATIVE-VERIFICATION-2026-10-16.md).

- **File cleanup:** scan produced four synthetic files, Select Visible selected all four, confirmation showed the four exact paths, fixture Trash reported 4/4 moved, and Recovery restored 4/4.
- **Application cleanup after native layout correction:** workspace `/private/tmp/RACKET-UI-D3642BCC-44F8-4114-A858-208BE745DF03` displayed one visible `Sample Tool` row and its actual path. Review confirmed that exact synthetic bundle, fixture Trash reported 1/1 moved, and app-specific Recovery restored 1/1.
- **Storage:** the same isolated journey showed 475 KB across 17 entries with partial coverage from one package skip. Exploration granted no cleanup authority.
- **Native search at `4ccfa68`:** fixture `/private/tmp/RACKET-UI-A56306B2-BE47-45CC-86D0-CFE66F21ADD2` produced four files. Command-F/`Thumbnail` focused `NSSearchField` and showed one 66 KB result. After Command-1/2 toolbar recreation, Command-F/`Render` replaced the query and showed one file. In Applications, Command-F/`Sample` showed one app; Edit → Find in Results/`Missing` replaced it and showed zero. Clearing via Command-F/Backspace restored four files with zero selected. A final Thumbnail repeat passed with an inline screenshot.
- **Native UI/accessibility observations:** real controls and roles/labels were observed, corrected app/storage lists occupied visible viewports, and Command-1/Command-R passed. Shortcut/menu focus, query replacement and filtering now have actual native proof; VoiceOver/full keyboard compliance do not.
- **Model assertions:** seven current app tests cover the earlier hidden selection/exclusion/recovery/geometry flows plus native search focus/recreation and selected-window routing with Unicode binding. They do not establish every pointer/cancellation path or OS notification/login behavior.

All removal interactions above used isolated fixtures and fake Trash with real namespace moves. They neither removed personal cache files nor used the owner's real Trash. VoiceOver was **not run**; no accessibility-compliance claim follows from pointer checks, labels, geometry or screenshots.

## Failures caught and corrected

1. **Optimized Release rule loading:** archive hashes, signatures and Debug tests passed, but the old Release app's bundle-only installation check rejected valid ASCII rule IDs. An external harness linked to that optimized framework reproduced five valid-ID refusals. Direct UTF-8 ASCII grammar validation preserved the exact accepted alphabet and all text/length gates. Exhaustive ASCII/Unicode/boundary regressions, 347 Debug tests, 343 actual Release tests and the rebuilt app self-check passed. The older `dist/local-0.1.0` artifact is therefore **superseded**, despite passing earlier archive-integrity checks.
2. **Native list geometry:** a synthetic application existed but its list row was not visibly usable in the full window. The native viewport correction now has mounted-row/full-window geometry assertions and a real pointer app review/removal/undo journey.
3. **Older CI compiler failure:** Swift 6.1.2 IRGen crashed while adapting the actor-isolated Boolean `setLogin` method reference for a binding. Replacing that reference with an explicit closure addressed the reported trigger; both hosted runs at prior source `30e92c7` passed.
4. **Unlocked native search failure:** source `30e92c7` failed both Command-F and the Find menu action; direct field-click typing worked. A native `NSSearchField`/key-window focus correction at `4ccfa68` passed actual focus, typing, replacement, toolbar-recreation and both cleanup/app filtering paths. Its source-matched archive and hosted outcomes now passed.
5. **Fresh parallel live-integration refusal:** the first attempt of run `38865857832` passed Core/app tests, Release/self-check and the ordinary-file Foundation round trip, but returned `activityUnknown` during read-only application removal review about 8 ms after a seven-process preflight passed. This preceded app-specific manifest/removal-engine construction: no app session, staging or move began. The fixture/account were preserved. The exact inner snapshot cause is unknown; transient churn is plausible, not proven. One failed-job rerun, **attempt 2**, passed at 10:21:29 Europe/Istanbul with the same source and all strict guards unchanged. The original failed log remains `/private/tmp/RACKET-4ccfa68-CI-failed.log`; the successful retry does not erase it.

## Prior package and hosted verification — `30e92c7`

| Check | Recorded outcome | Evidence |
| --- | --- | --- |
| Prior hosted CI | **Both SUCCESS**, source `30e92c7`; not a result for `4ccfa68` | [Run 38855678771](https://github.com/iamcaglardogan/racket/actions/runs/38855678771), [run 38855673309](https://github.com/iamcaglardogan/racket/actions/runs/38855673309) |
| Actual ordinary-file and application Foundation Trash/public undo | **Passed** in disposable account; app retained complete original tree/identical bytes and five authenticated actions | Same hosted runs; `/private/tmp/RACKET-LiveCI-30e92c7.log`, lines 3488–3498; no owner's installed app or real Trash used |
| Final universal Release | **Passed**, app/framework contain arm64 and x86_64; minimum OS metadata 14.0 | `dist/local-0.1.0-verified/PACKAGING-REPORT.json` |
| App/ZIP/DMG signatures, hashes and extracted manifests | **Passed**, explicit local ad-hoc mode | `VERIFICATION.log`, `BUNDLE-MANIFEST.json`, `SHA256SUMS` in verified output |
| Release fixture-code exclusion | **Passed** | Final verifier rejects Debug fixture entry points/rules |
| Packaged app and both extracted bundles | **All bundle-only installation checks passed**, three enabled rules | `INSTALLATION-CHECK.json`, `ZIP-INSTALLATION-CHECK.json`, `DMG-INSTALLATION-CHECK.json`; this is not a production GUI-session claim |
| Developer ID release gate | **Rejected the local ad-hoc artifact as expected** | `RELEASE-GATE-VERIFICATION.log`; no notarization claim |
| Production cleanup scan | **Not performed by design** | Personal cache data was not converted into local fixture inputs or removed for verification |

Elapsed schedule triggering, OS notification delivery, Login Items approval, pointer cancellation and full keyboard/VoiceOver coverage have not been established by the completed journeys. Scheduling remains scan-only by implementation and product contract.

## Prior verified artifacts — `30e92c7`

Do not use the superseded `dist/local-0.1.0` archive as the ready build.

The artifacts below passed their listed checks at `30e92c7` but contain the earlier native search behavior. They do not contain the `4ccfa68` correction and are not its fresh artifact evidence.

- Output: **`dist/local-0.1.0-verified/`**, locally `/Volumes/ELCHEDO/CODE/MACCLEANERAPP/dist/local-0.1.0-verified/`; runtime source `30e92c7efddee550a21e3bce4a36749faebaf887`.
- App: `RACKET.app`; ZIP: `RACKET-0.1.0-macOS-local.zip`; DMG: `RACKET-0.1.0-macOS-local.dmg`.
- `SHA256SUMS`, `BUNDLE-MANIFEST.json`, `PACKAGING-REPORT.json`, `DISTRIBUTION.txt`, all installation receipts and verification logs are retained alongside the artifacts.
- Native evidence: [NATIVE-VERIFICATION-2026-10-16.md](NATIVE-VERIFICATION-2026-10-16.md), plus inline conversation screenshots.

| Archive | Exact bytes | SHA-256 |
| --- | ---: | --- |
| DMG | 2,336,259 | `4ef90cba56e179daee84ffd0a7fb8b8ea5e2af1d3aa4b9fba97309cd9e9ee671` |
| ZIP | 1,807,240 | `b7dfc413e34885bb1a191590a2a643a39d301b3dc6ce33ea90a09ef4ff7a96c9` |

## Promoted current runtime — `4ccfa68`

- Real native Command-F/Find menu focus and filtering: **passed**, with seven app-flow tests passed.
- Hosted [run 38865863334](https://github.com/iamcaglardogan/racket/actions/runs/38865863334): **SUCCESS**, including 350 Core/7 app tests, Release/self-check and actual ordinary/app Foundation Trash/public undo. Preserved success log: `/private/tmp/RACKET-4ccfa68-CI-success.log`, lines 3493–3501.
- Parallel [run 38865857832](https://github.com/iamcaglardogan/racket/actions/runs/38865857832): **SUCCESS on attempt 2**, completed at 10:21:29 Europe/Istanbul, including 350 Core/7 app tests, universal Release/resources/self-checks, architectures and actual file/app Foundation recovery. `/private/tmp/RACKET-4ccfa68-CI-retry-success.log`, lines 3493–3501, preserves round-trip evidence. Attempt 1's read-only `activityUnknown` failure stays documented above and in the artifact's failure log.
- Promoted output: **`dist/local-0.1.0-keyboard-verified/`**, locally `/Volumes/ELCHEDO/CODE/MACCLEANERAPP/dist/local-0.1.0-keyboard-verified/`, source `4ccfa684597f48b3352d1919d0c202dba6a2b401`. Local signatures/architectures/manifests/checksums, fixture exclusion, app/ZIP/DMG three-rule diagnostics, native keyboard validation and source-matched hosted confirmation **passed**. `PACKAGING-REPORT.json` records `candidate_only: false` and independent validation passed, retaining all three attempt records.
- App: `RACKET.app`; archives and exact hashes are below. `PACKAGING-REPORT.json`, `SHA256SUMS`, `BUNDLE-MANIFEST.json`, `DISTRIBUTION.txt`, installation receipts, build/app-test/verifier logs and all hosted attempt logs remain alongside the package. Bundle diagnostics do not claim a production GUI session or personal-cache cleanup.
- The Core framework's SHA-256 remains `e244a8afa40ed793b3a4caa848ebd2c1166e81e99e5a4ee4793e17e5edf263bc`, matching the prior package; the report separately identifies unchanged-source Core test reuse.

| Promoted archive | Exact bytes | SHA-256 |
| --- | ---: | --- |
| `RACKET-0.1.0-macOS-local.dmg` | 2,342,040 | `5924e5060d48e533ff2b5b02a760fdfb658a046a4cd17b35b6e2608923290e8b` |
| `RACKET-0.1.0-macOS-local.zip` | 1,813,209 | `3b9970e05e73fabaf81b0ba4d5e93133005eb37950d4483cc37a25befdb185a9` |

## Remaining product/platform limits

- No Developer ID/Apple notarization/public Homebrew release. Ad-hoc signatures verify local integrity and do not identify an Apple-approved publisher.
- Camera Raw/broader creative cleanup and live project resolution remain disabled/unavailable.
- General system/log sweeping, broad DerivedData cleanup, scheduled automatic removal, exhaustive app leftovers, snapshots and shipping CLI are not implemented.
- macOS 14/Intel runtime, genuine cloud providers, separately mounted volumes and power-loss recovery remain unverified. Current file/app Foundation integration passed only in the disposable hosted account.
- Command-F/menu focus and filtering passed on the actual unlocked native window. VoiceOver, full keyboard/accessibility compliance, elapsed schedule triggering, OS notification delivery and Login Items approval remain unverified.
- Core operations retain the documented same-UID interference, final Foundation pathname race and journal-authentication limitations.

The promoted source-matched package, actual native search journeys and hosted file/app recovery are ready as a deliberately scoped **local preview**. This is not full cleaner parity, an Apple-notarized public release or universal platform/accessibility certification. Bundle diagnostics do not claim cleanup of the owner's real caches; the first conservative hosted refusal remains part of the evidence.
