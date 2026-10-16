import AppKit
import Foundation
import RacketCore
import SwiftUI
import XCTest
@testable import RACKET

@MainActor
final class AppFlowTests: XCTestCase {
    func testScanExplicitReviewTrashHistoryConflictAndUndo() async throws {
        let model = AppModel()
        XCTAssertTrue(model.verificationMode)
        model.start(); try await idle(model)
        let runtime = try XCTUnwrap(model.runtime)
        XCTAssertNotNil(runtime.verificationRoot)
        XCTAssertNil(model.errorMessage)
        try await snapshot(model, name: "01-overview")
        model.scan(); try await idle(model)
        XCTAssertEqual(model.report?.findings.count, 4)
        XCTAssertTrue(model.selected.isEmpty, "A scan never selects files")
        model.selectVisible()
        model.search = "Preview cache"
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.selectedFindings.count, 4, "Hidden selection remains explicitly reviewable")
        model.confirmCleanup = true
        try await snapshot(model, name: "02-review")
        model.confirmCleanup = false
        model.search = ""
        let original = try XCTUnwrap(model.selectedFindings.first)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: original.resolvedPath))
        model.cleanSelected(); try await idle(model)
        XCTAssertNil(model.report)
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertEqual(model.page, .recovery)
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.latestEvents.filter { $0.action == .trashed }.count, 4)
        try await snapshot(model, name: "03-recovery")
        try Data("occupied original".utf8).write(to: URL(fileURLWithPath: original.resolvedPath), options: .withoutOverwriting)
        model.restore(session); try await idle(model)
        XCTAssertTrue(model.lastUndo?.results.contains { $0.outcome == .conflict } == true)
        XCTAssertNotEqual(try Data(contentsOf: URL(fileURLWithPath: original.resolvedPath)), bytes)
        try FileManager.default.moveItem(atPath: original.resolvedPath,
            toPath: try XCTUnwrap(runtime.verificationRoot).appendingPathComponent("preserved-conflicting-file").path)
        model.restore(session); try await idle(model)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: original.resolvedPath)), bytes)
        XCTAssertTrue(model.lastUndo?.results.allSatisfy { $0.outcome == .restored || $0.outcome == .alreadyRestored } == true)
        try await snapshot(model, name: "04-restored")
    }

    func testExclusionIsExactAndCannotChangeDuringAnOperation() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        model.scan(); try await idle(model)
        let path = try XCTUnwrap(model.report?.findings.first?.resolvedPath)
        model.selectVisible(); model.exclude(path)
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.selectedFindings.count, 3)
        model.scan()
        model.removeExclusion(path)
        XCTAssertEqual(model.exclusions.count, 1, "Exclusions cannot change after an operation starts")
        try await idle(model)
        model.removeExclusion(path)
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertTrue(model.selected.isEmpty)
    }

    func testApplicationAndStorageJourneysUseOnlyIsolatedFixtures() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        let root = try XCTUnwrap(model.runtime?.verificationRoot)
        model.loadApplications(); try await idle(model)
        let app = try XCTUnwrap(model.applicationReport?.applications.first)
        XCTAssertTrue(app.path.hasPrefix(root.path))
        model.page = .applications; try await snapshot(model, name: "05-applications")
        model.reviewApplication(app); try await idle(model)
        XCTAssertTrue(model.confirmApplication)
        XCTAssertNotNil(model.reviewedApplication)
        model.removeReviewedApplication(); try await idle(model)
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.session.ruleSetVersion, ApplicationRemovalSelection.manifestVersion)
        XCTAssertEqual(session.latestEvents.first?.action, .trashed)
        model.restore(session); try await idle(model)
        XCTAssertEqual(model.lastUndo?.results.first?.outcome, .restored)
        model.explore(root); try await idle(model)
        XCTAssertNotNil(model.storageReport)
        try await snapshot(model, name: "06-storage")
        model.page = .settings; try await snapshot(model, name: "07-settings")
    }

    private func idle(_ model: AppModel) async throws {
        for _ in 0..<400 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Application operation did not finish within 20 seconds")
        throw CancellationError()
    }

    /// Render the actual SwiftUI views in the test host; this is a layout
    /// snapshot, not a claim of keyboard/VoiceOver computer-use verification.
    private func snapshot(_ model: AppModel, name: String) async throws {
        let view = NSHostingView(rootView: MainWindow().environmentObject(model).frame(width: 1140, height: 780))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 1140, height: 780)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5_000)
        let directory = URL(fileURLWithPath: "/private/tmp/RACKET-ViewVerification-20261016", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        window.orderOut(nil)
    }
}
