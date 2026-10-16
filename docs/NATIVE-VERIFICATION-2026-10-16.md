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

## Native search defect and verified correction

The initial keyboard check was interrupted when the Mac locked. After the owner unlocked it, source `30e92c7` exposed a real defect: both Command-F and Edit → Find in Results left focus on the window; typing `Thumbnail` left all four cleanup rows unchanged. Direct field-click typing worked. The later native correction uses `NSSearchField` with key-window focus dispatch rather than assuming a SwiftUI focus state reaches the toolbar editor.

At runtime source **`4ccfa684597f48b3352d1919d0c202dba6a2b401`**, actual keyboard/menu input in isolated workspace **`/private/tmp/RACKET-UI-A56306B2-BE47-45CC-86D0-CFE66F21ADD2`** verified:

1. Command-R produced four synthetic files. Command-F followed by `Thumbnail` focused the native search field and left one visible Thumbnail result, displaying 66 KB allocated.
2. Command-1 then Command-2 recreated the toolbar. Command-F followed by `Render` replaced the previous query, retained native editor focus and showed one matching file.
3. Command-5, Read Applications, Command-F and `Sample` showed the one Sample Tool. Clicking Edit → Find in Results and typing `Missing` replaced `Sample`, retained focus and showed zero apps.
4. Returning with Command-2, Command-F and Backspace cleared the query and restored all four files with **zero selected**.
5. A final Command-F/`Thumbnail` repeat again focused the native field and showed one matching row; the screenshot is preserved inline in the development conversation.

All **7 app-flow tests passed**, including regression checks for focus after blur/toolbar recreation and routing only to the selected native window while retaining Unicode binding. Log: `/private/tmp/RACKET-NativeSearchFinalAppFlowTests.log`; result bundle: `/private/tmp/racket-product-tests/Logs/Test/Test-RACKET-2026.10.16_10-10-34-+0300.xcresult`.

These observations verify the actual shortcut/menu focus and filtering paths above. They do not establish full keyboard navigation, VoiceOver behavior or accessibility conformance. The promoted source-matched `4ccfa68` archive and successful hosted attempts are recorded separately in the [dated verification report](VERIFICATION-2026-10-16.md), including the parallel run's preserved read-only activity refusal before its successful retry. Older `30e92c7` package receipts are not attributed to the corrected runtime.

## Evidence boundaries

These native operations exercise real interface actions and real file moves in isolated fixtures using an injected Trash transport. They do not establish actual Foundation Trash behavior; that is separately tested only in the guarded disposable GitHub-hosted account. Developer ID signing, Apple notarization, real cloud providers, macOS 14 runtime and Intel runtime are separate checks.
