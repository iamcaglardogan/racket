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

    func testMountedApplicationPageHasVisibleNativeFixtureRowAndExactPath() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        model.loadApplications(); try await idle(model)
        let application = try XCTUnwrap(model.applicationReport?.applications.first)
        model.page = .applications
        let host = NSHostingView(rootView: ApplicationsPage().environmentObject(model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1140, height: 780)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let nodes = ownAccessibilityContent(of: host)
        func tables(_ view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
        }
        let nativeTables = tables(host)
        let tableReport = nativeTables.map { "Native table rows=\($0.numberOfRows) frameInHost=\(host.convert($0.bounds, from: $0)) visibleRect=\($0.visibleRect) firstRow=\($0.numberOfRows > 0 ? $0.rect(ofRow: 0) : .zero) rowInstantiated=\($0.rowView(atRow: 0, makeIfNecessary: false) != nil)" }.joined(separator: "\n")
        XCTAssertEqual(nativeTables.first?.numberOfRows, 1, "The actual app List must bind one fixture row")
        let report = tableReport + "\n" + nodes.map { "\($0.role) frame=\($0.frame) enabled=\($0.enabled) hidden=\($0.hidden): \($0.text)" }.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Application view own accessibility content"
        attachment.lifetime = .keepAlways
        add(attachment)
        let table = try XCTUnwrap(nativeTables.first)
        let tableInHost = host.convert(table.bounds, from: table)
        XCTAssertTrue(host.bounds.intersects(tableInHost), "The actual app list must intersect its hosting viewport")
        XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: 0)), "The fixture row must be in the native table's visible viewport")
        XCTAssertNotNil(table.rowView(atRow: 0, makeIfNecessary: false), "The visible fixture row must already be instantiated")
        let hostOnScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
        XCTAssertTrue(nodes.contains {
            Data($0.text.utf8) == Data(application.path.utf8) && $0.frame.width > 0 && $0.frame.height > 0 &&
            !$0.hidden && hostOnScreen.intersects($0.frame)
        }, "The actual mounted row must expose its exact fixture path inside the window.\n\(report)")
        // SwiftUI-drawn headings and button labels are not exposed by this
        // generic test host's accessibility bridge. This test claims native
        // table realization and exact selectable-path content only.
    }

    func testFullWindowListPagesKeepNativeViewportsWithinWindow() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        model.loadApplications(); try await idle(model)
        let root = try XCTUnwrap(model.runtime?.verificationRoot)
        model.explore(root); try await idle(model)
        model.page = .applications
        let host = NSHostingView(rootView: MainWindow().environmentObject(model).frame(width: 1140, height: 780))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1140, height: 780)
        window.makeKeyAndOrderFront(nil)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for page in [AppPage.applications, .storage, .applications] {
            model.page = page
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let views = descendants(host)
            let split = try XCTUnwrap(views.compactMap { $0 as? NSSplitView }.first)
            XCTAssertLessThanOrEqual(split.bounds.height, host.bounds.height + 1,
                                     "The split must fit the available window height on \(page)")
            let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
            XCTAssertGreaterThan(table.numberOfRows, 0)
            XCTAssertLessThanOrEqual(table.bounds.height, host.bounds.height + 1)
            XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: 0)), "The first native row must remain visible on \(page)")
            XCTAssertNotNil(table.rowView(atRow: 0, makeIfNecessary: false))
            let hostOnScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
            let nodes = ownAccessibilityContent(of: host)
            if page == .applications {
                let path = try XCTUnwrap(model.applicationReport?.applications.first?.path)
                XCTAssertTrue(nodes.contains { Data($0.text.utf8) == Data(path.utf8) && hostOnScreen.intersects($0.frame) },
                              "The full-window application row must expose its exact path inside the visible window")
            }
        }
    }

    func testFindFocusesNativeToolbarEditorAfterBlurAndPageRecreation() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        model.scan(); try await idle(model)
        XCTAssertEqual(model.rows.count, 4)
        let host = NSHostingView(rootView: MainWindow().environmentObject(model).frame(width: 1140, height: 780))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func field() throws -> NSSearchField {
            let root = window.contentView?.superview ?? host
            return try XCTUnwrap(descendants(root).compactMap { $0 as? NSSearchField }.first {
                $0.window === window && !$0.isHiddenOrHasHiddenAncestor && $0.accessibilityLabel() == "Search names and paths"
            })
        }
        let search = try field()
        model.focusSearch(in: window)
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === editor)
        editor.insertText("Thumbnail", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.search, "Thumbnail")
        XCTAssertEqual(model.rows.count, 1, "Native editor input must reach the actual finding filter")
        window.makeFirstResponder(nil)
        model.notice = "A state update must not recapture search focus"
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(window.firstResponder === search.currentEditor())
        model.focusSearch(in: window)
        let repeatedEditor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === repeatedEditor)
        XCTAssertEqual(repeatedEditor.selectedRange(), NSRange(location: 0, length: "Thumbnail".utf16.count))
        model.loadApplications(); try await idle(model)
        model.page = .applications
        model.search = ""
        try await Task.sleep(for: .milliseconds(300))
        let appSearch = try field()
        model.focusSearch(in: window)
        let appEditor = try XCTUnwrap(appSearch.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === appEditor)
        appEditor.insertText("Sample", replacementRange: appEditor.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.search, "Sample")
        model.page = .overview
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.canFocusSearch)
        model.page = .applications
        try await Task.sleep(for: .milliseconds(300))
        let recreated = try field()
        model.focusSearch(in: window)
        XCTAssertTrue(window.firstResponder === recreated.currentEditor())
    }

    func testFindRoutesOnlyToTheSelectedNativeWindowAndPreservesUnicodeBinding() async throws {
        let model = AppModel(); model.start(); try await idle(model)
        model.page = .cleanup
        let firstHost = NSHostingView(rootView: ResultSearchField(model: model).frame(width: 240, height: 24))
        let firstWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        let secondHost = NSHostingView(rootView: ResultSearchField(model: model).frame(width: 240, height: 24))
        let secondWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        defer { firstWindow.orderOut(nil); secondWindow.orderOut(nil) }
        firstWindow.contentView = firstHost; secondWindow.contentView = secondHost
        firstWindow.makeKeyAndOrderFront(nil); secondWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let first = try XCTUnwrap(descendants(firstHost).compactMap { $0 as? NSSearchField }.first)
        let second = try XCTUnwrap(descendants(secondHost).compactMap { $0 as? NSSearchField }.first)
        model.focusSearch(in: secondWindow)
        let editor = try XCTUnwrap(second.currentEditor() as? NSTextView)
        XCTAssertTrue(secondWindow.firstResponder === editor)
        XCTAssertNil(first.currentEditor())
        let query = "\u{0130}stanbul Cafe\u{301}"
        editor.insertText(query, replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(Data(model.search.utf8), Data(query.utf8))
        XCTAssertEqual(Data(first.stringValue.utf8), Data(query.utf8))
        XCTAssertEqual(Data(second.stringValue.utf8), Data(query.utf8))
        firstWindow.makeKeyAndOrderFront(nil)
        model.focusSearch(in: firstWindow)
        XCTAssertTrue(firstWindow.firstResponder === first.currentEditor())
        firstWindow.makeFirstResponder(nil)
        model.search = ""
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(first.stringValue, "")
        XCTAssertEqual(second.stringValue, "")
        XCTAssertNil(first.currentEditor(), "Clearing a binding must not recapture focus")
        let unrelated = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        defer { unrelated.orderOut(nil) }
        unrelated.contentView = NSView()
        let previousResponder = unrelated.firstResponder
        model.focusSearch(in: unrelated)
        XCTAssertTrue(unrelated.firstResponder === previousResponder, "A window without a registered search field must be untouched")
    }

    private struct OwnAccessibilityContent {
        let text: String
        let role: String
        let frame: NSRect
        let enabled: Bool
        let hidden: Bool
    }

    /// Reads only objects owned by this mounted hosting view. No external AX
    /// process, permission request, input action, or screen capture is involved.
    private func ownAccessibilityContent(of root: NSView) -> [OwnAccessibilityContent] {
        var seen = Set<ObjectIdentifier>()
        var result: [OwnAccessibilityContent] = []
        func visit(_ object: AnyObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted, seen.count <= 4_096 else { return }
            if let element = object as? any NSAccessibilityProtocol {
                let value = element.accessibilityValue()
                let texts = [element.accessibilityLabel(), element.accessibilityTitle(), value as? String,
                             (value as? NSAttributedString)?.string].compactMap { $0 }.filter { !$0.isEmpty }
                result.append(OwnAccessibilityContent(text: texts.joined(separator: " | "),
                                                     role: (element.accessibilityRole()?.rawValue ?? "unknown") + " " + String(describing: type(of: object)),
                                                     frame: element.accessibilityFrame(), enabled: element.isAccessibilityEnabled(),
                                                     hidden: element.isAccessibilityHidden()))
                for child in (element.accessibilityChildren() ?? []) + (element.accessibilityVisibleChildren() ?? []) {
                    visit(child as AnyObject)
                }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child) } }
        }
        visit(root)
        for child in NSAccessibility.unignoredChildrenForOnlyChild(from: root) { visit(child as AnyObject) }
        if let window = root.window {
            for x in stride(from: CGFloat(20), through: root.bounds.width - 20, by: 120) {
                for y in stride(from: CGFloat(20), through: root.bounds.height - 20, by: 90) {
                    let point = window.convertPoint(toScreen: root.convert(NSPoint(x: x, y: y), to: nil))
                    if let hit = root.accessibilityHitTest(point) { visit(hit as AnyObject) }
                }
            }
        }
        return result
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
