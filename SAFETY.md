# Safety contract

This contract governs every future implementation change. When a feature conflicts with an invariant, the feature loses.

**Implementation status:** Phase 0 scaffolding only. The enforcement test references below are planned destinations, not existing or passing safety tests. The initial empty test target only checks that test infrastructure can run. No scanning or removal code exists. Each planned control must become an executable check in its delivery phase before that phase can be accepted.

1. **S1. Trash, never unlink.** All removals go through `FileManager.trashItem(at:resultingItemURL:)`, called only by `RemovalEngine`. No code path, test, temporary utility, or script may permanently delete user-visible content. The sole exception is the user's explicit Empty Trash action.
2. **S2. Allow-list, not deny-list.** A deletable path must resolve inside a compiled, explicitly enumerated safe root. Anything else is refused even when a rule matches. Rule data cannot extend the allow-list.
3. **S3. Symlink and TOCTOU resistance.** Resolve every path before validation and re-resolve immediately before the Trash call. Open directories with `O_NOFOLLOW` where possible. Symlink escapes are hard errors, not skips. Race resistance must be tested rather than inferred from a second path lookup.
4. **S4. Never touch dataless files.** Inspect `ubiquitousItemDownloadingStatus` and `SF_DATALESS` before collecting size or reading contents. Do not cause placeholder hydration. Report dataless items as skipped.
5. **S5. Preferences are not junk.** `~/Library/Preferences` contains settings and licence state. Consider it only during an explicit user-initiated uninstall of a specific application, never in a cache sweep.
6. **S6. No auto-delete without review.** A schedule may scan. Removal requires review or a previous standing approval for that exact category, followed by a notification with undo. Judgement findings are never preselected or eligible for standing automatic selection.
7. **S7. No telemetry, ever.** No analytics, crash reporting, or anonymous statistics. The only potentially permitted app network operation is an optional GitHub release check, disabled by default and permanently disableable; whether it exists is still undecided. Reject dependencies that contact external services.
8. **S8. Honest numbers only.** Count allocated size with `UInt64`, distinguish real free space from Finder's estimates, and make no claim to reclaim purgeable space, boost RAM, or accelerate a Mac.
9. **S9. No fear.** Do not use alarm counters, health scores, threat meters, fear-based copy, or inflated findings. Size is information rather than a danger signal.
10. **S10. Auditable by construction.** Every finding identifies one readable rule and one path. Rules must carry a unique identifier, source citation, plain-language reason, and regeneration cost. Unverified rules do not ship enabled.

## Planned enforcement map

| Invariant | Planned test location | Required evidence |
| --- | --- | --- |
| S1 | `Tests/RemovalEngineTests/` and a repository source policy check | Only RemovalEngine calls the Trash API; no forbidden destructive path in application, tests, or scripts |
| S2 | `Tests/PathGuardTests/` | Generated adversarial paths never authorize content outside safe roots |
| S3 | `Tests/PathGuardTests/`, `Tests/RemovalEngineTests/` | Symlink farm, loops, protected origins, mount boundaries, and replacement between validation and removal fail closed |
| S4 | `Tests/ScanEngineTests/`, `Tests/RemovalEngineTests/` | Dataless metadata gates all size/content access and produces a recorded skip |
| S5 | `Tests/RuleSetTests/`, `Tests/PathGuardTests/` | Cache sweeps reject Preferences; uninstall authority is explicit and scoped |
| S6 | Selection and scheduling tests in the relevant feature phases | No removal from a scan timer alone; judgement findings never preselected; approved automation supplies undo |
| S7 | Network-policy tests in the app phase and dependency checks in CI | Zero telemetry; any version check is opt-in and can be disabled permanently |
| S8 | `Tests/ScanEngineTests/` and storage accounting tests | Allocated-size accounting, overflow handling, and separate free/purgeable reporting |
| S9 | Copy/token checks and accessibility/UI review in the design phase | No alarm metrics, misleading copy, or fear-based presentation |
| S10 | `Tests/RuleSetTests/` | Rule explanations and citations are mandatory, identifiers unique, safe roots validated, and unverified rules disabled |

Tests must use isolated synthetic fixtures rather than the real home directory. A failed Trash call must still leave a manifest entry proving the pre-call record was written. A test's cleanup is subject to S1 too.

## Clarifications required before affected implementation

- The brief mentions snapshot deletion, simulator deletion, Docker pruning, and language-file removal. These must not be implemented as implicit exceptions to S1. Resolve the conflict with the owner before adding any such action.
- Preference removal during uninstall needs narrowly scoped authority; it must not weaken the independent deny rules for ordinary cleanup.
- The dataless requirement needs a documented metadata-access sequence: inspect the metadata required to recognize a placeholder without opening or reading its contents. Verify API behavior before relying on it.
- Two pathname checks do not by themselves prove resistance to all filesystem races. Phase 1 and Phase 3 must document the guarantees and remaining OS API constraints, supported by adversarial tests.
