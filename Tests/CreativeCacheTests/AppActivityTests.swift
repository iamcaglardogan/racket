import Darwin
import Foundation
import XCTest
@testable import RacketCore

/// All executable paths, identifiers, credentials, and process observations are
/// synthetic. No test enumerates or inspects a real application or its files.
final class AppActivityTests: XCTestCase {
    private let photoshop = "com.adobe.Photoshop"

    func testCompiledPrimaryExecutablesSurviveRenamedApplicationBundles() {
        let cases = [
            ("com.adobe.Photoshop", "Adobe Photoshop 2026"),
            ("com.adobe.AfterEffects.application", "After Effects"),
            ("com.adobe.AfterEffectsRenderEngine", "After Effects Render Engine"),
            ("com.adobe.LightroomClassicCC7", "Adobe Lightroom Classic"),
            ("com.adobe.ame.application.26", "Adobe Media Encoder 2026"),
            ("com.blackmagic-design.DaVinciResolve", "Resolve")
        ]
        for (producer, executable) in cases {
            let checker = checker(paths: ["/synthetic/Renamed.app/Contents/MacOS/" + executable])
            XCTAssertEqual(checker.check(producers: [producer]), .running([producer]))
        }
    }

    func testKnownBundleHelpersAndVersionFamiliesCauseConservativeRefusal() {
        for path in [
            "/synthetic/Adobe Photoshop 2027.app/Contents/Helpers/Worker",
            "/synthetic/Renamed.app/Contents/MacOS/Adobe Photoshop 2027",
            "/synthetic/ADOBE PHOTOSHOP 2026.APP/Contents/Helpers/Worker"
        ] {
            XCTAssertEqual(checker(paths: [path]).check(producers: [photoshop]), .running([photoshop]))
        }
    }

    func testRenderEngineBlocksAfterEffectsEvenWhenOnlyEditorIsRequested() {
        for path in ["/synthetic/Renamed.app/Contents/MacOS/After Effects Render Engine", "/synthetic/Adobe After Effects 2026/aerender"] {
            let checker = checker(paths: [path])
            for producer in ["com.adobe.AfterEffects.application", "com.adobe.AfterEffectsRenderEngine"] {
                XCTAssertEqual(checker.check(producers: [producer]), .running([producer]))
            }
        }
    }

    func testSimilarNamesDoNotCountAsKnownProducerFamilies() {
        let paths = [
            "/synthetic/Adobe Photoshopper.app/Contents/MacOS/Worker",
            "/synthetic/Renamed.app/Contents/MacOS/Adobe Photoshopper",
            "/synthetic/Adobe Photoshop 2026.cache/Worker"
        ]
        XCTAssertEqual(checker(paths: paths).check(producers: [photoshop]), .notObservedRunning)
    }

    func testResultsAreSortedAndDeduplicatedAcrossProcesses() {
        let checker = checker(paths: [
            "/synthetic/Adobe Photoshop 2026", "/synthetic/Resolve", "/synthetic/Resolve"
        ])
        XCTAssertEqual(checker.check(producers: ["com.blackmagic-design.DaVinciResolve", photoshop]),
                       .running([photoshop, "com.blackmagic-design.DaVinciResolve"]))
    }

    func testUnsupportedPartiallySupportedAndInvalidProducerRequestsFailBeforeObservation() {
        let probe = ActivityProcessProbe()
        let checker = checker(probe)
        for producers in [
            [], ["unknown"], [photoshop, "com.adobe.bridge"], [photoshop, photoshop],
            Array(repeating: photoshop, count: 65)
        ] {
            XCTAssertEqual(checker.check(producers: producers), .unknown)
        }
        XCTAssertTrue(probe.events.isEmpty)
    }

    func testAbsentKnownProducerIsOnlyAnObservationAndIsNeverCached() {
        let paths = ActivitySequence(["/synthetic/runner", "/synthetic/Adobe Photoshop 2026"])
        let checker = AppActivity(snapshot: { [AppActivityProcess(executablePath: paths.next())] })
        XCTAssertEqual(checker.check(producers: [photoshop]), .notObservedRunning)
        XCTAssertEqual(checker.check(producers: [photoshop]), .running([photoshop]))
    }

    func testEmptyOversizedMalformedAndUnavailableSnapshotsAreUnknown() {
        XCTAssertEqual(checker(paths: []).check(producers: [photoshop]), .unknown)
        XCTAssertEqual(checker(paths: Array(repeating: "/synthetic/runner", count: 65_537))
            .check(producers: [photoshop]), .unknown)
        for path in ["relative", "/", "/synthetic//runner", "/synthetic/../runner",
                     "/synthetic/./runner", "/synthetic/runner/", "/synthetic/runner\n", "/synthetic/\0runner"] {
            XCTAssertEqual(checker(paths: [path]).check(producers: [photoshop]), .unknown)
        }
        let unavailable = AppActivity(snapshot: { throw ActivityFixtureError.unavailable })
        XCTAssertEqual(unavailable.check(producers: [photoshop]), .unknown)
    }

    func testEffectiveAndRealUIDProcessSetsAreUnionedAndDuplicatePIDsInspectedOnce() {
        let probe = ActivityProcessProbe(list: { filter, _, capacity, _ in
            activityPIDList(filter == UInt32(PROC_UID_ONLY) ? [41, 42] : [42, 43], capacity: capacity)
        }, info: { pid, _ in
            activityInfo(pid, effectiveUID: pid == 43 ? 502 : 501, realUID: pid == 41 ? 502 : 501)
        }, path: { pid, _ in pid == 43 ? "/synthetic/Adobe Photoshop 2026" : "/synthetic/runner" })
        XCTAssertEqual(checker(probe).check(producers: [photoshop]), .running([photoshop]))
        for pid in [41, 42, 43] {
            XCTAssertEqual(probe.events.filter { $0 == "info:\(pid)" }.count, 2)
            XCTAssertEqual(probe.events.filter { $0 == "path:\(pid)" }.count, 2)
        }
        XCTAssertEqual(probe.events.filter { $0.hasPrefix("list:") }.count, 12)
    }

    func testCredentialsMustBeNonRootMatchingAndRemainUnchanged() {
        for credentials: ([uid_t], [uid_t]) in [([0], [0]), ([501], [502]), ([501, 502], [501]), ([501], [501, 502])] {
            let probe = ActivityProcessProbe(effectiveUIDs: credentials.0, realUIDs: credentials.1)
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testMalformedSizeHintsFailClosedBeforeReadingProcessMetadata() {
        for hint in [
            AppActivityPIDList(byteCount: 0, pids: []),
            AppActivityPIDList(byteCount: -4, pids: []),
            AppActivityPIDList(byteCount: 3, pids: []),
            AppActivityPIDList(byteCount: 65_536 * MemoryLayout<pid_t>.stride, pids: []),
            AppActivityPIDList(byteCount: MemoryLayout<pid_t>.stride, pids: [41])
        ] {
            let probe = ActivityProcessProbe(list: { _, _, _, _ in hint })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
            XCTAssertFalse(probe.events.contains { $0.hasPrefix("info:") })
        }
    }

    func testFullMisalignedEmptyAndInconsistentPIDBuffersFailClosed() {
        for scenario in 0..<5 {
            let probe = ActivityProcessProbe(list: { _, _, capacity, _ in
                guard capacity > 0 else { return activityPIDList([41], capacity: 0) }
                switch scenario {
                case 0: return AppActivityPIDList(byteCount: capacity * MemoryLayout<pid_t>.stride,
                                                 pids: Array(repeating: 41, count: capacity))
                case 1: return AppActivityPIDList(byteCount: 3, pids: Array(repeating: 0, count: capacity))
                case 2: return AppActivityPIDList(byteCount: 0, pids: Array(repeating: 0, count: capacity))
                case 3: return AppActivityPIDList(byteCount: MemoryLayout<pid_t>.stride, pids: [41])
                default: return AppActivityPIDList(byteCount: -4, pids: Array(repeating: 0, count: capacity))
                }
            })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
            XCTAssertFalse(probe.events.contains { $0.hasPrefix("info:") })
        }
    }

    func testInvalidAndDuplicatePIDsWithinOneFilterFailClosed() {
        for pids: [pid_t] in [[0], [-1], [41, 41]] {
            let probe = ActivityProcessProbe(list: { _, _, capacity, _ in activityPIDList(pids, capacity: capacity) })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testPIDListChurnAfterInspectionIsUnknown() {
        let probe = ActivityProcessProbe(list: { _, _, capacity, call in
            activityPIDList(call <= 3 ? [41] : [41, 42], capacity: capacity)
        })
        XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
    }

    func testKernelInternalHintBoundaryIsUnknownEvenWhenCallerBufferIsNotFull() {
        let probe = ActivityProcessProbe(list: { _, _, capacity, _ in
            activityPIDList(Array(1...64).map { pid_t($0) }, capacity: capacity)
        })
        XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        XCTAssertFalse(probe.events.contains { $0.hasPrefix("info:") })
    }

    func testGlobalSizingHintChurnWithinOrBetweenObservationsIsUnknown() {
        for scenario in 0..<3 {
            let probe = ActivityProcessProbe(list: { filter, _, capacity, call in
                if capacity == 0 && ((scenario == 0 && call == 3) ||
                    (scenario == 1 && filter == UInt32(PROC_RUID_ONLY)) || (scenario == 2 && call >= 4)) {
                    return AppActivityPIDList(byteCount: 65 * MemoryLayout<pid_t>.stride, pids: [])
                }
                return activityPIDList([41], capacity: capacity)
            })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testMissingProcessAndAccessFailuresRemainUnknownAtEveryStage() {
        for stage in ["list", "info", "path"] {
            let probe = ActivityProcessProbe(list: { _, _, capacity, _ in
                if stage == "list" { throw ActivityFixtureError.unavailable }
                return activityPIDList([41], capacity: capacity)
            }, info: { pid, _ in
                if stage == "info" { throw ActivityFixtureError.unavailable }
                return activityInfo(pid)
            }, path: { _, _ in
                if stage == "path" { throw ActivityFixtureError.unavailable }
                return "/synthetic/runner"
            })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testReusedPIDCredentialChangesAndExecChangesAreUnknown() {
        for scenario in 0..<5 {
            let probe = ActivityProcessProbe(info: { pid, call in
                activityInfo(pid, effectiveUID: scenario == 1 && call == 2 ? 502 : 501,
                             realUID: scenario == 2 && call == 2 ? 502 : 501,
                             startedSeconds: scenario == 0 && call == 2 ? 2 : 1,
                             status: scenario == 3 && call == 2 ? UInt32(SZOMB) : UInt32(SRUN))
            }, path: { _, call in scenario == 4 && call == 2 ? "/synthetic/changed" : "/synthetic/runner" })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testMalformedProcessMetadataIsUnknown() {
        for info in [
            activityInfo(42), activityInfo(41, effectiveUID: 502, realUID: 502),
            activityInfo(41, startedSeconds: 0), activityInfo(41, startedMicroseconds: 1_000_000),
            activityInfo(41, status: 0), activityInfo(41, status: UInt32(SZOMB) + 1),
            activityInfo(41, status: UInt32(SIDL))
        ] {
            let probe = ActivityProcessProbe(info: { _, _ in info })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .unknown)
        }
    }

    func testSleepingAndStoppedKnownProcessesStillBlockRemoval() {
        for status in [UInt32(SSLEEP), UInt32(SSTOP)] {
            let probe = ActivityProcessProbe(info: { pid, _ in activityInfo(pid, status: status) },
                                             path: { _, _ in "/synthetic/Adobe Photoshop 2026" })
            XCTAssertEqual(checker(probe).check(producers: [photoshop]), .running([photoshop]))
        }
    }

    func testZombieIdentityIsRecheckedWithoutLookingUpItsExecutable() {
        let probe = ActivityProcessProbe(list: { _, _, capacity, _ in activityPIDList([41, 42], capacity: capacity) },
                                         info: { pid, _ in activityInfo(pid, status: pid == 42 ? UInt32(SZOMB) : UInt32(SRUN)) })
        XCTAssertEqual(checker(probe).check(producers: [photoshop]), .notObservedRunning)
        XCTAssertEqual(probe.events.filter { $0 == "info:42" }.count, 2)
        XCTAssertFalse(probe.events.contains("path:42"))
        let reused = ActivityProcessProbe(info: { pid, call in
            activityInfo(pid, startedSeconds: UInt64(call), status: UInt32(SZOMB))
        })
        XCTAssertEqual(checker(reused).check(producers: [photoshop]), .unknown)
    }

    func testLibprocPathLengthExcludesTerminatingNULAndPreservesUnicode() throws {
        let path = "/synthetic/Créatif/runner"
        let bytes = Array(path.utf8)
        XCTAssertEqual(try AppActivityProcessSource.decodeExecutablePath(bytes + [0, 0], reportedCount: bytes.count), path)
        XCTAssertThrowsError(try AppActivityProcessSource.decodeExecutablePath(bytes + [0, 0], reportedCount: bytes.count + 1))
    }

    func testMalformedTruncatedNonUTF8AndOutOfRangeLibprocPathsAreRefused() {
        for (bytes, count): ([UInt8], Int) in [
            ([47, 97, 0], 0), ([47, 97, 0], -1), ([47, 97], 2),
            ([47, 97, 98], 2), ([47, 0, 97, 0], 3), ([47, 255, 0], 2),
            ([97, 0], 1), (Array(repeating: 47, count: Int(MAXPATHLEN) * 4 + 1), 1)
        ] {
            XCTAssertThrowsError(try AppActivityProcessSource.decodeExecutablePath(bytes, reportedCount: count))
        }
    }

    func testMaterializationScopeCanNestAndIsRestoredAfterObservationAndFailure() throws {
        let original = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        XCTAssertGreaterThanOrEqual(original, 0)
        try withoutDatalessMaterialization {
            let protected = AppActivity(snapshot: {
                guard getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
                    == IOPOL_MATERIALIZE_DATALESS_FILES_OFF else { throw ActivityFixtureError.unavailable }
                return [AppActivityProcess(executablePath: "/synthetic/runner")]
            })
            XCTAssertEqual(protected.check(producers: [photoshop]), .notObservedRunning)
            XCTAssertEqual(AppActivity(snapshot: { throw ActivityFixtureError.unavailable })
                .check(producers: [photoshop]), .unknown)
            XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD),
                           IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        }
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), original)
    }

    private func checker(paths: [String]) -> AppActivity {
        AppActivity(snapshot: { paths.map { AppActivityProcess(executablePath: $0) } })
    }

    private func checker(_ probe: ActivityProcessProbe) -> AppActivity {
        AppActivity(snapshot: { try AppActivityProcessSource(operations: probe.operations).snapshot() })
    }
}

private enum ActivityFixtureError: Error { case unavailable }

private func activityInfo(_ pid: pid_t, effectiveUID: uid_t = 501, realUID: uid_t = 501,
                          startedSeconds: UInt64 = 1, startedMicroseconds: UInt64 = 0,
                          status: UInt32 = UInt32(SRUN)) -> AppActivityProcessInfo {
    AppActivityProcessInfo(pid: pid, effectiveUID: effectiveUID, realUID: realUID,
                           startedSeconds: startedSeconds, startedMicroseconds: startedMicroseconds, status: status)
}

private func activityPIDList(_ pids: [pid_t], capacity: Int) -> AppActivityPIDList {
    // The kernel size hint reflects all users plus slack, not the filtered count.
    AppActivityPIDList(byteCount: (capacity == 0 ? 64 : pids.count) * MemoryLayout<pid_t>.stride,
                      pids: capacity == 0 ? [] : pids + Array(repeating: 0, count: capacity - pids.count))
}

/// Test-only mutable counters are protected by the lock; supplied behaviors are
/// immutable Sendable closures and never access host process state.
private final class ActivityProcessProbe: @unchecked Sendable {
    typealias List = @Sendable (UInt32, uid_t, Int, Int) throws -> AppActivityPIDList
    typealias Info = @Sendable (pid_t, Int) throws -> AppActivityProcessInfo
    typealias Path = @Sendable (pid_t, Int) throws -> String
    private let lock = NSLock()
    private var calls: [String: Int] = [:]
    private var recorded: [String] = []
    private let effectiveUIDs: ActivitySequence<uid_t>
    private let realUIDs: ActivitySequence<uid_t>
    private let list: List
    private let info: Info
    private let path: Path

    init(effectiveUIDs: [uid_t] = [501], realUIDs: [uid_t] = [501],
         list: @escaping List = { _, _, capacity, _ in activityPIDList([41], capacity: capacity) },
         info: @escaping Info = { pid, _ in activityInfo(pid) },
         path: @escaping Path = { _, _ in "/synthetic/runner" }) {
        self.effectiveUIDs = ActivitySequence(effectiveUIDs)
        self.realUIDs = ActivitySequence(realUIDs)
        self.list = list
        self.info = info
        self.path = path
    }

    var events: [String] { lock.withLock { recorded } }

    var operations: AppActivityProcessOperations {
        AppActivityProcessOperations(
            effectiveUID: { self.effectiveUIDs.next() }, realUID: { self.realUIDs.next() },
            listPIDs: { filter, uid, capacity in
                try self.list(filter, uid, capacity, self.record("list:\(filter)"))
            },
            processInfo: { pid in try self.info(pid, self.record("info:\(pid)")) },
            executablePath: { pid in try self.path(pid, self.record("path:\(pid)")) }
        )
    }

    private func record(_ event: String) -> Int {
        lock.withLock {
            recorded.append(event)
            calls[event, default: 0] += 1
            return calls[event, default: 0]
        }
    }
}

private final class ActivitySequence<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [Value]
    private var index = 0

    init(_ values: [Value]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func next() -> Value {
        lock.withLock {
            defer { index += 1 }
            return values[min(index, values.count - 1)]
        }
    }
}
