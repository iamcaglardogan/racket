# Bundled cleanup rule verification

Verified on **15 October 2026**. Bundled rules version **1.2.0** enables three narrowly scoped developer caches. Adobe Camera Raw remains disabled and unverified. No general system-cache or log sweep is enabled.

“Verified” means the declared cache purpose has a primary source, the real producer regenerated disposable cache data in the checks below, and the bundled declarations passed synthetic scanner/removal/recovery tests. It is not a promise that every historical package remains available, that a process cannot start after observation, or that all tool versions have been exercised.

## Enabled scope

| Rule ID | Exact default location | Minimum file age | Walk depth | Producer refusal |
| --- | --- | --- | --- | --- |
| `developer.homebrew-downloads` | `~/Library/Caches/Homebrew/downloads` | More than 120 days | 1 | `brew`, Ruby or curl observed running |
| `developer.npm-content-cache` | `~/.npm/_cacache` | More than 30 days | 8 | Node, npm or npx observed running |
| `developer.xcode-module-cache` | `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex` | More than 30 days | 4 | Xcode, its build services, supported compiler or SourceKit executables observed running |

These rules offer individual ordinary files for explicit review. Directories, symlinks, mount boundaries, dataless placeholders, protected project names, and multiple-link/changed files remain subject to the existing refusal policy. All enabled rules retain their producer checks in scan findings, and removal makes fresh observations before staging, capture and Trash. Unknown activity refuses progress. Names are conservative identity heuristics; they are not process locks.

The two new compiled roots are exactly npm’s `_cacache` and Xcode’s `ModuleCache.noindex`. The rest of `.npm`, `.npmrc`, `_npx`, project `node_modules`, package checkouts, Xcode archives, simulators and other DerivedData locations are outside those roots. Homebrew uses the existing cache policy, while its bundled rule narrows selection to the dedicated `downloads` directory. Custom cache locations are not discovered or followed.

Age means observed **file modification time**, not last use. An old cache file may still be useful. The explanation and regeneration cost are retained in every finding so a review can account for slower future builds/downloads and loss of offline availability. Moving files to Trash does not promise physically reclaimed disk space.

## Primary references

- Homebrew’s [pre-download instructions](https://docs.brew.sh/Tips-and-Tricks#pre-download-a-file-for-a-formula) identify the `downloads` subdirectory, its URL-hash naming, and `brew fetch` as the way to populate it. The [Homebrew manual](https://docs.brew.sh/Manpage) identifies the default macOS cache and its 120-day cleanup age. RACKET neither invokes `brew cleanup` nor removes installed formulae.
- npm’s [cache documentation](https://docs.npmjs.com/cli/v11/commands/npm-cache/) identifies `_cacache` as its content-addressed package/HTTP cache. It documents integrity checking and refetching missing/corrupt cached data, while explicitly distinguishing a cache from persistent storage. RACKET does not execute npm or read npm configuration.
- Apple’s [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) identifies `MODULE_CACHE_DIR` as the compiler’s performance cache. The [Clang Modules documentation](https://clang.llvm.org/docs/Modules.html#command-line-parameters) describes the module-cache path and generation of implicit compiled modules. A local `xcodebuild -showBuildSettings` with a disposable derived-data path independently reported `MODULE_CACHE_DIR = <fixture>/DerivedData/ModuleCache.noindex`; it did not access the current user’s real DerivedData cache.

## Real producer regeneration evidence

The replayable [verification harness](../scripts/fixtures/verify-developer-caches.py) creates a fresh private `/private/tmp/RACKET-DeveloperCacheEvidence-*` directory. It explicitly redirects writable cache/config/log/temp locations to that fixture and leaves the process’s actual home setting unchanged. It preserves generated caches by moving them into the fixture’s `preserved` directory. It never invokes a cache-cleaning command, installs a Homebrew formula, scans the owner’s cache, or uses the owner’s Trash. npm’s own verification operates only on its newly generated fixture cache.

Successful run: `/private/tmp/RACKET-DeveloperCacheEvidence-v7uqdl2k/evidence.json`. Generated inputs, both cache generations, test installs and binaries remain preserved there. The preceding Clang harness trial used different executable output names, which produced different Mach-O hashes; the final run used the same output path and preserved the first binary before rebuilding. This fixed the comparison procedure rather than weakening the assertion.

| Producer | Actual check | Result |
| --- | --- | --- |
| npm **11.17.0**, Node **24.19.0** | Created a pinned local package tarball, installed it offline with scripts/audit/funding/update notices disabled, preserved one cached content blob while retaining the cache index, installed again, preserved the whole `_cacache`, installed a third time, then ran `npm cache verify` on the regenerated fixture cache | Missing blob refetched; empty cache repopulated; all three installed payloads identical; verification reported one intact content item and two index entries; original package unchanged |
| Apple Clang **21.0.0**, `clang-2100.3.34.2` | Compiled a generated header/module map/C program with an explicitly configured module cache, ran the binary, preserved the PCM cache and binary, rebuilt with the same command/output path, and ran the new binary | One PCM module regenerated; binary SHA-256 identical; both executions returned success; all source/header/map bytes unchanged |
| Actual Homebrew source at **`be9411f7d2cef522201891d38260c63e66da88f7`** | Used a disposable Homebrew checkout and private Ruby runtime under `/private/tmp`, a generated local-file formula in a fixture tap, isolated cache/log/temp locations, disabled analytics and updates, ran `brew fetch --build-from-source`, preserved the downloaded archive, then fetched again | Same URL-hash download path recreated with identical SHA-256; original source fixture unchanged; no formula installed |

Recorded hashes from that successful run:

- npm tarball: `bfc07c62b0d671c8f583c4b618995c9f32793d449cc75fe052e99efba4d98980`
- npm installed payload: `1737ef29ba647e558b55fccbdaebad1b5737bc2528f166d42d062e240a25c766`
- Clang executable: `8baee4235149bf341c10b4414b675d562f7c64e5c05930a4d0ff545014ebabf9`
- Homebrew source/download: `be13cf8c9fb8ca40118a4a30d3964d47d759db2b7c926288f7501b2f30691efb`

Replay npm/Clang checks with `python3 scripts/fixtures/verify-developer-caches.py`. Include Homebrew with `--brew /private/tmp/RACKET-<disposable-checkout>/bin/brew`; the harness refuses an installed Homebrew location. Homebrew’s temporary runtime may need to be obtained first, with its writable locations redirected and analytics/updates disabled. The harness itself downloads no tooling.

## Bundled-rule integration and adversarial checks

The [developer-rule integration tests](../Tests/RuleSetTests/DeveloperRuleIntegrationTests.swift) load the actual bundled JSON against a unique synthetic home and use the real descriptor walker, compiled policy, persistent authenticated manifest, removal engine and undo service. Their fixture Trash transport performs real no-follow/exclusive renames to another private fixture directory.

The tests verify that every enabled rule finds its eligible old file, leaves recent files and protected/out-of-scope data unchanged, records its producer guard, moves only the reviewed files, and restores their identical bytes through five authenticated journal transitions per file. Separate cases verify that a producer starting after review skips every developer category, and unknown producer activity prevents any directory walk.

[Path policy tests](../Tests/PathGuardTests/PathGuardTests.swift) exercise the new exact roots, root-as-candidate refusal, prefix collisions, case/Unicode variants, traversal, protected descendants and symlinks. The 10,000-path generated test now includes both new roots and requires every accepted candidate to remain a strict descendant of an exact compiled root. [Rule tests](../Tests/RuleSetTests/RuleSetTests.swift) enforce the enabled IDs/locations, conservative ages and supported producer identities, and ensure module filtering cannot enable or add a rule. [Producer tests](../Tests/CreativeCacheTests/AppActivityTests.swift) exercise executable and Xcode-bundle/helper refusal matches.

Focused SwiftPM verification completed **94 tests with zero failures** across rule, path, producer and bundled developer integration suites. The package used an isolated scratch directory and `--disable-sandbox` because nested SwiftPM manifest sandboxing is unavailable inside the agent’s filesystem sandbox. No test accessed real developer caches.

The complete SwiftPM suite also passed **329 tests with zero failures** at this integration snapshot. Its obsolete “all bundled candidates disabled” test was narrowed to the creative module, preserving that test’s original no-walk assertion while allowing the verified developer rules to run.

## Boundaries

- The producer runs used disposable synthetic packages, headers and a local-file Homebrew URL. They establish cache refill mechanics and byte/behavior preservation for these versions, not the continued availability of arbitrary historical packages or an outage-free network. Remote/private package downloads may require network access, credentials and a still-available upstream; offline installs can fail after cleanup.
- Clang regeneration is a small C module test. No claim is made that every Xcode project, SDK, module format or compiler version has been rebuilt. Only the dedicated default module-cache directory is enabled.
- The bundled integration tests use fixture Trash transport. The existing separately guarded ordinary-file live Foundation Trash checks are documented in [TESTING.md](TESTING.md); these producer checks do not substitute for that integration.
- Process observation can become stale immediately. Same-UID races, unsupported or renamed helper executables, separate-volume/cloud-provider behavior and crash durability retain the documented limits in [REMOVAL.md](REMOVAL.md).
- Camera Raw verification is incomplete, so `adobe.camera-raw-cache-2` stays `verified: false` and `enabled: false`. No Adobe/Resolve cache was cleaned or used as disposable test data. General logs/system caches and broad DerivedData cleanup remain disabled.
