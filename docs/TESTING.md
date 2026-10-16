# Verification scope

RACKET uses synthetic safety suites, isolated producer regeneration checks, Debug UI verification, package validation and a separate guarded live Foundation integration. These establish different boundaries; none substitutes for all the others. Final evidence for the exact 0.1.0 preview is collected in [VERIFICATION-2026-10-16.md](VERIFICATION-2026-10-16.md).

## Local development checks

```sh
make core-test
make test
make check-policy
make build CONFIGURATION=Release
make package
```

SwiftPM and Xcode use the same Core sources/tests. Full Xcode supplies XCTest and the SwiftUI app toolchain; some Command Line Tools installations can compile Core but cannot run XCTest. The generated project comes from `project.yml`. Source policy checks selected permanent-deletion/networking APIs, misplaced Trash calls and UI imports in Core; regex checks are guardrails rather than runtime proof.

Recorded local checks passed **347 Debug Core tests, 343 Release Core tests and 5 Xcode app-flow tests**, with zero failures. The four-case configuration difference comes from Debug-only fixture tests. Logs: `/private/tmp/RACKET-Rules-DebugRegression-20261016.log`, `/private/tmp/RACKET-ReleaseRules-20261016-after.log` and `/private/tmp/RACKET-AppFlowGeometryFinalTests.log`. The Xcode result bundle is `/private/tmp/racket-product-tests/Logs/Test/Test-RACKET-2026.10.16_08-12-30-+0300.xcresult`. Earlier isolated checks passed 329 Core tests and 94 focused rule/path/producer/developer-integration tests; the historical log remains `/private/tmp/RACKET-RuleTests-20261015-full.log`. Rerun checks after implementation changes and record them against the actual package.

The isolated package invocation used `--disable-sandbox` because nested SwiftPM manifest sandboxing is unavailable inside the agent's filesystem sandbox. Build outputs/caches remained redirected to approved workspace/temporary locations. This does not relax the app's own filesystem policies.

## Synthetic filesystem evidence

XCTest and local fixture checks create unique private temporary directories, inject home/policy/manifest locations and use fake Trash transports with real namespace moves. Generated content is retained; there is no permanent-deletion teardown. Tests must not scan or mutate the owner's home, installed apps, caches, creative projects, real Trash or live cloud data.

| Boundary | Covered behavior |
| --- | --- |
| Compiled authority | Exact roots, root-candidate refusal, independent protected names/extensions, declaration validation for enabled and disabled rules, npm/Xcode prefix/case/Unicode collisions and 10,000 generated adversarial paths |
| Rule schema | Required explanations/citations, bounded fields/depth/age, supported modes, strict flags, duplicate keys/IDs, unsupported schema, unsafe declarations and bundled resources |
| Metadata and traversal | Flags-before-stat/size gates, thread-policy restoration/nesting, no-follow ancestry, symlinks, special files, changed roots/parents/entries, deterministic hard-link deduplication, cancellation and resource bounds |
| Allocation | Allocated metadata rather than logical length, sparse/resource-fork fixtures, negative/missing values, checked totals and overflow refusal |
| Ordinary removal | Current observations/rules/producer guards, single-link ownership, durable intent before capture, private staging, exact returned transport path, replacement/refusal/failure states and a stop on journal failure |
| Ordinary undo | Whole-history authentication, recorded-source identity, destination conflicts, missing parents, interrupted operations and no overwrite/path guessing |
| Developer rules | Actual bundled declarations scan old synthetic cache files, preserve recent/protected/out-of-scope files, move an explicit review through fixture Trash and restore identical bytes; newly running/unknown producers refuse progress |
| Creative grouping | Explicit association provenance, complete producer sets, separate unknown/application-wide groups, byte-exact opaque identities, checked totals, retained findings and file-mtime semantics |
| Storage | Separate read-only authority, capacity math, allocated/hard-link totals, package/link/cloud skips, partial coverage, bounds and cancellation |
| App management | Metadata discovery, system/self/owner protections, bounded tree receipts, linked/shared/protected/dataless descendants, running/unknown activity, substitutions, app-specific journal/undo, conflict/journal-failure handling and separation from ordinary undo |
| Product runtime | Debug-only isolated workspace, reviewed synthetic file removal, reopening session history, public undo flow and unchanged restored bytes |

Sources: [path tests](../Tests/PathGuardTests/PathGuardTests.swift), [rule tests](../Tests/RuleSetTests/RuleSetTests.swift), [developer integration](../Tests/RuleSetTests/DeveloperRuleIntegrationTests.swift), [scanning tests](../Tests/ScanEngineTests/), [removal/recovery tests](../Tests/RemovalEngineTests/), [creative tests](../Tests/CreativeCacheTests/), [storage tests](../Tests/StorageTests/), [app tests](../Tests/AppManagementTests/), and [workflow tests](../Tests/WorkflowTests/).

`SF_DATALESS` is read-only SDK metadata, so an ordinary unprivileged file cannot faithfully synthesize a provider placeholder by setting that flag. Injected states prove refusal/call order, not real iCloud/File Provider hydration behavior. No scanner production path opens ordinary file contents. App inventory separately reads bounded admitted bundle metadata; that is not a general content scanner.

## Real producer regeneration

[verify-developer-caches.py](../scripts/fixtures/verify-developer-caches.py) generates private disposable sources and redirects producer cache/config/log/temp locations. It preserves original caches before regeneration. It does not use the owner's real caches or install a Homebrew formula.

- npm 11.17.0 on Node 24.19.0 refetched a missing content blob with its index retained, regenerated an empty `_cacache`, installed the same local pinned package offline three times, and verified the new fixture cache.
- Apple Clang 21 regenerated a compiled module from a generated header/module map. Rebuilt executable bytes and behavior matched, and original sources remained unchanged.
- A disposable actual Homebrew checkout refetched an identical local-file formula download after its original cache file was preserved; installed software was unchanged.

The preserved successful evidence is `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json`. [RULE-VERIFICATION.md](RULE-VERIFICATION.md) provides the source commit, exact hashes, versions and limitations. Local-file/offline fixture refill does not prove availability of every historical/private upstream package or every compiler/SDK combination.

## UI and package verification

Debug builds may be opened with `--verification-fixtures` to create a clearly labelled `AppRuntime.verification()` workspace under `/private/tmp/RACKET-UI-*`. Its scan/removal/recovery use synthetic data and fake Trash. Review actual controls for selection, hidden filters, exclusions, full confirmation, cancellation, result details, ordinary/app restore routing, storage exploration and scan-only scheduling. Preserve screenshots and fixture journals. Product UI checks must be reported separately from Core suite counts.

The app supplies native controls, accessibility labels and keyboard actions. After an initial computer-use timeout was resolved, real pointer checks completed a four-file exact-selection/confirmation/fixture-Trash/undo journey and a visible single-app exact-bundle review/fixture-Trash/undo journey. The corrected native list viewport was checked in the full window; accessibility roles/labels were observed. Storage exploration reported 475 KB, 17 entries and one package skip as partial coverage. Command-1 navigation and Command-R scan passed; Command-F focus is being corrected and its final check remains outstanding. VoiceOver and accessibility compliance remain unverified. These real interactions use synthetic workspaces, not the owner's caches or real Trash.

A bundle-only Release installation check caught a failure that archive/signature checks and Debug tests had missed: the optimized framework rejected valid ASCII rule identifiers. Equivalent direct ASCII-byte validation, exhaustive schema regressions and real Release tests fixed it. The rebuilt universal Release app's `--verify-installation` then passed with document 1.2.0 and all three expected enabled rules. The old `dist/local-0.1.0` package is superseded and must not be treated as the ready artifact; final packaging must use the corrected Release build.

Release packaging rejects fixture entry points/synthetic rules. `scripts/verify-package.sh` checks both binary slices, minimum OS metadata, strict signatures and the extracted ZIP/DMG bundles against the same content manifest. It verifies exact archive checksums, ZIP path confinement, DMG structure and expected Applications shortcut. Temporary extracts/mount workspaces are preserved; the image is detached after inspection. These checks establish artifact integrity, not reproducibility across builds or runtime coverage on both architectures.

Local packages are ad-hoc signed and **not Apple notarized**. The credential-gated release path additionally requires valid Developer ID signing, accepted notary responses, stapled tickets and Gatekeeper assessment. No success is claimed for that path without those actual results. See [DISTRIBUTION.md](DISTRIBUTION.md).

Owner-authorized read-only production scans/inventory are operational smoke observations, not fixture tests. Record aggregate results and limitations separately; do not turn personal cache/app data into disposable test inputs or remove it to demonstrate the preview.

## Historical CI baselines

| Checkpoint | Historical CI evidence |
| --- | --- |
| Phase 1 | [Run 34125991610](https://github.com/iamcaglardogan/racket/actions/runs/34125991610): 62 XCTest cases in SwiftPM/Xcode, source checks and universal app build |
| Phase 2 | [Run 34165070143](https://github.com/iamcaglardogan/racket/actions/runs/34165070143): 146 cases in both runners, source checks and universal build |
| Phase 3 | [Run 34575529716](https://github.com/iamcaglardogan/racket/actions/runs/34575529716), `780a4ad`: 226 cases in both runners, source checks, universal build/entitlements and live ordinary-file Foundation Trash/undo |
| Phase 4 | [Run 35216679049](https://github.com/iamcaglardogan/racket/actions/runs/35216679049), `8f94aa5`: 281 cases in both runners, application build, source checks/entitlements and live ordinary-file Foundation Trash/undo |

These runs predate the new product views, enabled developer rules, storage/app modules and packaging. They do not certify the current working tree. The configured hosted CI uses macOS 15 and Xcode 16.4; local preview development reported macOS 27.0.1, Xcode 27.0 and Apple Swift 6.4. The deployment target remains macOS 14, whose runtime compatibility is separately unverified.

## Guarded live integration

`scripts/check-live-trash.sh` and `scripts/fixtures/LiveTrash.swift` are separate from XCTest and the app. The historical Phase 3/4 runs above passed an actual Foundation Trash/public-undo ordinary-file round trip with the original inode, identical bytes and five authenticated journal actions after reopening the store. They used a synthetic rule; this is not vendor-cache or app-bundle integration evidence.

**Never run the account-setup script locally or on a self-hosted runner; never spoof its guards.** It requires GitHub Actions, a GitHub-hosted macOS VM, Darwin and a non-root setup process. The workflow uses a disposable `macos-15` runner. Setup creates a fresh mode-0700 `/Users/RACKET-LiveTrash-<UUID>` directory and a new noninteractive account/group with its own synthetic home, without adding membership to existing groups. Compilation and runtime data stay in that fixture; account/files persist until VM disposal.

Account/name/UID/GID preflight assumes no concurrent account creation in the disposable job. `dscl -create` is not an atomic create-if-absent reservation. Environment guards are not a sandbox against deliberate bypass.

Before writing fixture content, the executable checks IDs, supplementary groups, passwd data, actual Foundation home resolution and private canonical fixture directories. It uses public current-user `SafeRoots`, `ScanEngine`, `ManifestStore`, `RemovalEngine` and `UndoService`, without a fake Trash transport or direct Trash call. Only the production removal boundary invokes Foundation. The returned object, identity, bytes and authenticated history are then checked.

Foundation's Trash destination is checked before/after the operation but cannot be pinned by the public pathname API. This integration does not close that race or establish malicious same-UID isolation, Finder Put Back, real-provider/separate-volume behavior, app-bundle live integration, macOS 14 runtime or power-loss durability.

## Remaining verification limits

- macOS 14 and Intel runtime testing are outstanding. Universal compilation and minimum-version metadata do not replace them.
- Genuine iCloud/File Provider placeholders, mounted-volume transitions, cloud/remote filesystem stalls and power-loss durability remain unverified.
- The full app/tree Foundation Trash round trip is distinct from fake-transport app tests and the historical ordinary-file hosted check.
- HMAC does not provide journal confidentiality, same-user forgery protection or detection of valid-prefix truncation. Private permissions do not isolate same-UID attackers.
- A second metadata check is not atomic; last-moment source replacement can be captured then refused, and Foundation retains its final pathname window.
- Representative performance benchmarks, full accessibility/usability coverage and complete vendor-helper identity catalogues are not established.
- Camera Raw/broader creative cleanup, general system/log sweeping and exhaustive app-leftover removal are unavailable. Feature absence is not a completed verification milestone.

## Platform references

- [Apple open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html): no-follow and metadata-only descriptors.
- [Apple fcntl(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html): retrieving an open descriptor's path.
- [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files): per-thread prevention of dataless materialization.
- [Apple getattrlistbulk(2)](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlistbulk.2): bulk directory records and attributes.
- Installed SDK headers are checked alongside the documentation; headers do not replace behavioral evidence.
