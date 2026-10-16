# RACKET 0.1.0 preview verification — 16 October 2026

**Status: READY — verified local preview, with the manual/platform limits below.** Corrected universal app/ZIP/DMG packages, local tests, both hosted CI runs and actual disposable-account Foundation file/app recovery passed. The verified artifact is `dist/local-0.1.0-verified`; older packages are superseded. Dates use Europe/Istanbul; preserved filenames may retain their initial-session date.

## Version and environment

- Product 0.1.0, build 1; rule document 1.2.0; identifier `io.github.iamcaglardogan.racket`.
- Validated production/archive source: **`30e92c7efddee550a21e3bce4a36749faebaf887`**. Subsequent documentation commits do not change the packaged runtime.
- Local host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple Clang 21.0.0 (`clang-2100.3.34.2`).
- Deployment target macOS 14.0; both arm64 and x86_64 Release slices are built. macOS 14 and Intel runtime coverage remain unverified.
- An explicit x86_64 installation-check attempt on this Apple Silicon host returned `Bad CPU type in executable`; Rosetta is unavailable here. That attempt provides no Intel runtime result (`/private/tmp/racket-intel-installation-check.err`).
- Distribution target is a local ad-hoc signed app/ZIP/DMG. No valid Developer ID identity is available; no Apple notarization or public Homebrew-release claim is made.

## Completed local checks

| Check | Result | Exact evidence |
| --- | --- | --- |
| Debug Core suite | **350 tests, zero failures** in final SwiftPM and Xcode runs | `/private/tmp/RACKET-CoreFinalProcessTests.log`; `/private/tmp/racket-product-xcode-final-tests.log` |
| Actual Release Core suite | **346 tests, zero failures**, without enabling Debug fixture code | `/private/tmp/racket-product-release-tests.log` |
| Xcode app-flow and native geometry suite | **5 tests passed**: reviewed scan/conflict/undo, exclusions/busy guards, application/storage journey, actual visible app row/path, full-window list viewports | Same final Xcode log; result bundle `/private/tmp/racket-product-tests/Logs/Test/Test-RACKET-2026.10.16_08-25-13-+0300.xcresult` |
| Source policy/entitlements | Passed local and current hosted checks | `scripts/check-source-policy.py`; successful CI runs below |
| Rebuilt universal Release installation check | **Passed**: version 0.1.0, rule document 1.2.0, all three expected enabled developer IDs, telemetry false | `/private/tmp/racket-product-derived/Build/Products/Release/RACKET.app/Contents/MacOS/RACKET --verify-installation` |
| External optimized-framework ID regression | Five valid-ID refusals before fix; **zero mismatches after fix**; slash/non-ASCII IDs still refused | `/private/tmp/RACKET-ReleaseRuleEvidence-20261016/framework-before.log` and `framework-after.log` |
| Real npm regeneration | Missing blob refetched with its index retained; empty `_cacache` regenerated; three offline installs matched; fixture cache verified | `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json` |
| Real Clang regeneration | PCM regenerated; identical executable bytes and successful behavior; generated sources unchanged | Same evidence JSON |
| Real Homebrew regeneration | Actual disposable checkout refetched identical local-file formula download; no formula installed | Same evidence JSON; source `be9411f7d2cef522201891d38260c63e66da88f7` |
| Production app inventory smoke | Metadata only: 110 discovered, 20 preliminarily eligible, 90 protected, 15 unavailable/skipped, depth limit indicated | [APPLICATIONS.md](APPLICATIONS.md); no real application removed |

The Debug/Release count differs by four Debug-only fixture tests. Initial counts of 329/345/347 and the earlier 3-app-test run are historical snapshots. [TESTING.md](TESTING.md) separates configuration, synthetic, producer and hosted evidence; [RULE-VERIFICATION.md](RULE-VERIFICATION.md) records exact enabled paths, versions, hashes and regeneration limits.

## Real native interactions on synthetic data

The computer-use service initially timed out and later recovered. Actual pointer interaction then verified these journeys; screenshots are inline in the working conversation and summarized in [native verification](NATIVE-VERIFICATION-2026-10-16.md).

- **File cleanup:** scan produced four synthetic files, Select Visible selected all four, confirmation showed the four exact paths, fixture Trash reported 4/4 moved, and Recovery restored 4/4.
- **Application cleanup after native layout correction:** workspace `/private/tmp/RACKET-UI-D3642BCC-44F8-4114-A858-208BE745DF03` displayed one visible `Sample Tool` row and its actual path. Review confirmed that exact synthetic bundle, fixture Trash reported 1/1 moved, and app-specific Recovery restored 1/1.
- **Storage:** the same isolated journey showed 475 KB across 17 entries with partial coverage from one package skip. Exploration granted no cleanup authority.
- **Native UI/accessibility observations:** real controls and accessibility roles/labels were observed. Corrected app/storage lists occupied visible window viewports. Command-1 navigation and Command-R scan passed. The Command-F standard menu/focus correction is implemented; its final unlocked native focus check was not completed because the Mac locked and requires manual unlock.
- **Model assertions:** the five app tests cover hidden selections remaining fully reviewable, exact exclusions, exclusion changes refused while busy, conflict preservation/details and both ordinary/app recovery routing. These assertions do not establish every pointer/cancellation path or OS notification/login behavior.

All removal interactions above used isolated fixtures and fake Trash with real namespace moves. They neither removed personal cache files nor used the owner's real Trash. VoiceOver was **not run**; no accessibility-compliance claim follows from pointer checks, labels, geometry or screenshots.

## Failures caught and corrected

1. **Optimized Release rule loading:** archive hashes, signatures and Debug tests passed, but the old Release app's bundle-only installation check rejected valid ASCII rule IDs. An external harness linked to that optimized framework reproduced five valid-ID refusals. Direct UTF-8 ASCII grammar validation preserved the exact accepted alphabet and all text/length gates. Exhaustive ASCII/Unicode/boundary regressions, 347 Debug tests, 343 actual Release tests and the rebuilt app self-check passed. The older `dist/local-0.1.0` artifact is therefore **superseded**, despite passing earlier archive-integrity checks.
2. **Native list geometry:** a synthetic application existed but its list row was not visibly usable in the full window. The native viewport correction now has mounted-row/full-window geometry assertions and a real pointer app review/removal/undo journey.
3. **Older CI compiler failure:** Swift 6.1.2 IRGen crashed while adapting the actor-isolated Boolean `setLogin` method reference for a binding. Replacing that reference with an explicit closure addressed the reported trigger; both current hosted runs at `30e92c7` passed.

## Final package and hosted verification

| Check | Recorded outcome | Evidence |
| --- | --- | --- |
| Current hosted CI | **Both SUCCESS**, source `30e92c7` | [Run 38855678771](https://github.com/iamcaglardogan/racket/actions/runs/38855678771), [run 38855673309](https://github.com/iamcaglardogan/racket/actions/runs/38855673309) |
| Actual ordinary-file and application Foundation Trash/public undo | **Passed** in disposable account; app retained complete original tree/identical bytes and five authenticated actions | Same hosted runs; `/private/tmp/RACKET-LiveCI-30e92c7.log`, lines 3488–3498; no owner's installed app or real Trash used |
| Final universal Release | **Passed**, app/framework contain arm64 and x86_64; minimum OS metadata 14.0 | `dist/local-0.1.0-verified/PACKAGING-REPORT.json` |
| App/ZIP/DMG signatures, hashes and extracted manifests | **Passed**, explicit local ad-hoc mode | `VERIFICATION.log`, `BUNDLE-MANIFEST.json`, `SHA256SUMS` in verified output |
| Release fixture-code exclusion | **Passed** | Final verifier rejects Debug fixture entry points/rules |
| Packaged app and both extracted bundles | **All bundle-only installation checks passed**, three enabled rules | `INSTALLATION-CHECK.json`, `ZIP-INSTALLATION-CHECK.json`, `DMG-INSTALLATION-CHECK.json`; this is not a production GUI-session claim |
| Developer ID release gate | **Rejected the local ad-hoc artifact as expected** | `RELEASE-GATE-VERIFICATION.log`; no notarization claim |
| Production cleanup scan | **Not performed by design** | Personal cache data was not converted into local fixture inputs or removed for verification |

Elapsed schedule triggering, OS notification delivery, Login Items approval, pointer cancellation and full keyboard/VoiceOver coverage have not been established by the completed journeys. Scheduling remains scan-only by implementation and product contract.

## Verified artifacts

Do not use the superseded `dist/local-0.1.0` archive as the ready build.

- Output: **`dist/local-0.1.0-verified/`**, locally `/Volumes/ELCHEDO/CODE/MACCLEANERAPP/dist/local-0.1.0-verified/`; runtime source `30e92c7efddee550a21e3bce4a36749faebaf887`.
- App: `RACKET.app`; ZIP: `RACKET-0.1.0-macOS-local.zip`; DMG: `RACKET-0.1.0-macOS-local.dmg`.
- `SHA256SUMS`, `BUNDLE-MANIFEST.json`, `PACKAGING-REPORT.json`, `DISTRIBUTION.txt`, all installation receipts and verification logs are retained alongside the artifacts.
- Native evidence: [NATIVE-VERIFICATION-2026-10-16.md](NATIVE-VERIFICATION-2026-10-16.md), plus inline conversation screenshots.

| Archive | Exact bytes | SHA-256 |
| --- | ---: | --- |
| DMG | 2,336,259 | `4ef90cba56e179daee84ffd0a7fb8b8ea5e2af1d3aa4b9fba97309cd9e9ee671` |
| ZIP | 1,807,240 | `b7dfc413e34885bb1a191590a2a643a39d301b3dc6ce33ea90a09ef4ff7a96c9` |

## Remaining product/platform limits

- No Developer ID/Apple notarization/public Homebrew release. Ad-hoc signatures verify local integrity and do not identify an Apple-approved publisher.
- Camera Raw/broader creative cleanup and live project resolution remain disabled/unavailable.
- General system/log sweeping, broad DerivedData cleanup, scheduled automatic removal, exhaustive app leftovers, snapshots and shipping CLI are not implemented.
- macOS 14/Intel runtime, genuine cloud providers, separately mounted volumes and power-loss recovery remain unverified. Current file/app Foundation integration passed only in the disposable hosted account.
- Command-F's final native focus check requires an unlocked Mac and remains unverified. VoiceOver, full keyboard/accessibility compliance, elapsed schedule triggering, OS notification delivery and Login Items approval are not claimed verified.
- Core operations retain the documented same-UID interference, final Foundation pathname race and journal-authentication limitations.

The verified package and core file/app recovery journeys are ready as a deliberately scoped **local preview**. This is not full cleaner parity, an Apple-notarized public release or universal platform/accessibility certification. Bundle diagnostics do not claim a production GUI session or cleanup of the owner's real caches.
