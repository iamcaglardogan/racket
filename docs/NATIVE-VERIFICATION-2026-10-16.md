# Native window verification — 16 October 2026

This is a manual computer-use verification of the real SwiftUI application window on the development Mac. A Debug-only copy at `/private/tmp/RACKET-Verification.app` was configured with `RACKET_TEST_WORKSPACE=1` and a distinct bundle identifier. Its private temporary homes, injected Trash transport and authentication key keep every operation out of the real home, installed applications and real Trash. Screenshots and accessibility observations are preserved in the development conversation; the test-host PNG files are layout diagnostics, not substitutes for these native observations.

## Completed observations

- Overview showed a filesystem-capacity observation, a usage indicator, review and folder actions, all seven navigation buttons and privacy copy.
- A scan produced exactly four synthetic files, with no initial selection. Select Visible selected four; the review sheet displayed every original path and allocated size. Confirming moved four of four through the injected transport. Recovery showed the recorded session. Restore returned four of four to their original paths without overwrite.
- Initial native Applications rendering reproduced the full-window navigation-height defect that generic-host tests had found. Root and detail viewport bounds fixed it. The updated native window displayed the heading, complete sidebar and a visible Sample Tool row within the normal window.
- In the updated private home `/private/tmp/RACKET-UI-D3642BCC-44F8-4114-A858-208BE745DF03`, application discovery returned one Sample Tool. Its review sheet identified the exact bundle, 8 KB allocation and four descendants, and stated the scope of removal. Confirming moved one of one bundles through the injected transport. App-specific recovery restored one of one.
- Storage Explorer measured that private fixture root as 475 KB across 17 entries, visibly labelled Partial Observation with one skipped package. The Home and Manifests rows and drilldown/Finder controls were exposed.
- Command-1 returned to Overview; Command-R started the synthetic scan. Settings exposed appearance, menu bar, scan-only scheduling, exclusions and local privacy information. Login and permission-changing controls were disabled in this fixture mode.
- Native accessibility observations exposed button, checkbox, disclosure, text-field and progress-indicator roles, selected navigation values and complete review paths. This was not a VoiceOver speech test or a conformance audit.

## Final keyboard check

The hidden toolbar Command-F control was replaced with a standard Edit → Find in Results command and a focus request. App tests pass with this implementation. During the final native check, the computer-use service reported that the Mac had locked and automatic unlock had failed. Manual unlock was requested. Until an unlocked repeat confirms typing reaches the search field, Command-F remains pending native verification; no success is inferred from the menu entry alone.

## Evidence boundaries

These native operations exercise real interface actions and real file moves in isolated fixtures using an injected Trash transport. They do not establish actual Foundation Trash behavior; that is separately tested only in the guarded disposable GitHub-hosted account. Developer ID signing, Apple notarization, real cloud providers, macOS 14 runtime and Intel runtime are separate checks.
