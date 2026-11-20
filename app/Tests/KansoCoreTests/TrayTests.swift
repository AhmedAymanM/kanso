import XCTest
@testable import KansoCore

/// The Tray on temp folders: references, links and snippets; temporary copies that are deleted only once ⌘Z can't
/// bring them back and never outside the Tray folder; the link safety check; Finder-style selection.
final class TrayTests: XCTestCase {
    var tmp: URL!, store: TrayStore!
    let fm = FileManager.default

    override func setUp() {
        tmp = fm.temporaryDirectory.appendingPathComponent("kanso-tray-\(UUID().uuidString)")
        try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = TrayStore(dir: tmp.appendingPathComponent("state"))
    }
    override func tearDown() { try? fm.removeItem(at: tmp) }

    func file(_ name: String) -> URL {
        let u = tmp.appendingPathComponent(name)
        try! Data("x".utf8).write(to: u)
        return u
    }

    /// A saved file promise, as the app writes it: `Tray/<uuid>/name`.
    func promise(_ name: String) throws -> URL {
        let folder = try store.promiseFolder()
        let u = folder.appendingPathComponent(name)
        try Data("img".utf8).write(to: u)
        store.adopt(saved: u)
        return u
    }

    func testFilesLinksAndSnippetsNewestFirstWithoutDuplicates() {
        let a = file("Lease.pdf")
        XCTAssertEqual(store.add(files: [a]).added.count, 1)
        XCTAssertEqual(store.add(files: [a]).already, 1)
        XCTAssertEqual(store.add(links: [URL(string: "https://figma.com/design/x")!]).added.count, 1)
        XCTAssertEqual(store.add(links: [URL(string: "file:///etc/passwd")!, URL(string: "javascript:alert(1)")!]).added.count, 0, "web links only")
        XCTAssertEqual(store.add(text: "Call Anna about the deposit").added.count, 1)
        XCTAssertEqual(store.items.map(\.kind), [.snippet, .link, .file], "newest first")
        XCTAssertTrue(fm.fileExists(atPath: a.path), "adding never touches the file")
        let again = TrayStore(dir: tmp.appendingPathComponent("state"))
        XCTAssertEqual(again.items.count, 3, "survives a relaunch")
        let attrs = try? fm.attributesOfItem(atPath: tmp.appendingPathComponent("state/tray.json").path)
        XCTAssertEqual((attrs?[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRefusalsAndCaps() {
        XCTAssertFalse(store.add(files: [tmp.appendingPathComponent("nope.pdf")]).refused.isEmpty)
        let target = file("real.txt")
        let link = tmp.appendingPathComponent("link.txt")
        try? fm.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(store.add(files: [link]).added.count, 0, "symlinks are refused")
        XCTAssertFalse(store.add(text: String(repeating: "a", count: TrayStore.snippetCap + 1)).refused.isEmpty)
        XCTAssertEqual(TrayStore.clean("evil\u{0007}\nname" + String(repeating: "x", count: 200)).count, 120)
        XCTAssertFalse(TrayStore.clean("a\u{0000}b\u{001B}c").unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
    }

    func testRemovingNeverTouchesTheUsersFilesAndUndoBringsItBack() {
        let a = file("Lease.pdf")
        let id = store.add(files: [a]).added[0]
        store.remove([id])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: a.path), "removing only takes it off the Tray")
        XCTAssertEqual(store.restoreLast().count, 1)
        XCTAssertEqual(store.items.map(\.id), [id])
        store.clear()
        store.closeUndo()
        XCTAssertTrue(fm.fileExists(atPath: a.path), "Clear and the end of ⌘Z never delete a user's file")
    }

    func testTemporaryCopyIsQuarantinedPrivateAndDeletedOnlyAfterTheUndoWindow() throws {
        let img = try promise("photo.jpg")
        let item = try XCTUnwrap(store.items.first)
        XCTAssertTrue(item.temporary)
        XCTAssertTrue(Xattr.has(img, "com.apple.quarantine"))
        let mode = (try fm.attributesOfItem(atPath: store.scratch.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o700)
        XCTAssertTrue(fm.fileExists(atPath: store.scratch.appendingPathComponent(".metadata_never_index").path), "Spotlight skips it")
        XCTAssertEqual(try store.scratch.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        store.remove([item.id])
        XCTAssertTrue(fm.fileExists(atPath: img.path), "⌘Z can still bring it back")
        store.restoreLast()
        XCTAssertTrue(fm.fileExists(atPath: img.path))
        store.remove([item.id])
        store.closeUndo()   // the island closed
        XCTAssertFalse(fm.fileExists(atPath: img.path), "gone once ⌘Z can't reach it")
        XCTAssertFalse(fm.fileExists(atPath: img.deletingLastPathComponent().path), "its folder too")
    }

    func testTheNextRemovalEndsTheUndoWindow() throws {
        let img = try promise("a.png")
        let other = store.add(text: "note").added[0]
        store.remove([store.items.first { $0.temporary }!.id])
        store.remove([other])
        XCTAssertFalse(fm.fileExists(atPath: img.path))
    }

    func testDraggedOutCopyMovedByFinderIsNotAProblem() throws {
        let img = try promise("b.png")
        let kept = tmp.appendingPathComponent("Desktop-b.png")
        try fm.moveItem(at: img, to: kept)   // the user dragged it out: Finder moved the copy
        store.remove([store.items[0].id]); store.closeUndo()
        XCTAssertTrue(fm.fileExists(atPath: kept.path), "the file the user kept is theirs")
    }

    func testNeverDeletesOutsideTheTrayFolder() {
        let mine = file("mine.png")
        var forged = TrayItem(kind: .file, path: mine.path, temporary: true)   // a tampered tray.json
        forged.id = UUID()
        store.deleteCopy(forged)
        XCTAssertTrue(fm.fileExists(atPath: mine.path))
    }

    func testLeftoversAreCleanedAtLaunchAndWipeRemovesEverything() throws {
        let keep = try promise("keep.png")
        let stray = try store.promiseFolder().appendingPathComponent("stray.png")
        try Data().write(to: stray)
        _ = TrayStore(dir: tmp.appendingPathComponent("state"))   // launch
        XCTAssertTrue(fm.fileExists(atPath: keep.path))
        XCTAssertFalse(fm.fileExists(atPath: stray.path))
        store.wipe()
        XCTAssertTrue(TrayStore(dir: tmp.appendingPathComponent("state")).items.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: store.scratch.path))
    }

    func testMovedFileIsFoundThroughItsBookmark() throws {
        let a = file("Lease.pdf")
        store.add(files: [a])
        let moved = tmp.appendingPathComponent("Lease moved.pdf")
        try fm.moveItem(at: a, to: moved)
        XCTAssertEqual(store.resolve(store.items[0])?.lastPathComponent, "Lease moved.pdf")
        try fm.removeItem(at: moved)
        XCTAssertNil(store.resolve(store.items[0]), "missing")
    }

    // MARK: Link safety

    func testOnlyPublicAddressesPass() {
        for ip in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "::1", "::", "fe80::1", "fd00::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1", "300.1.1.1", "nonsense"] {
            XCTAssertFalse(LinkSafety.isPublic(ip), ip)
        }
        for ip in ["93.184.216.34", "172.32.0.1", "8.8.8.8", "2606:2800:220:1::1", "::ffff:93.184.216.34"] {
            XCTAssertTrue(LinkSafety.isPublic(ip), ip)
        }
    }

    func testLinkRulesRefuseWithoutNetwork() {
        for s in ["http://example.com", "https://localhost/x", "https://printer.local", "https://127.0.0.1/", "https://10.0.0.4/admin", "https://[::1]/", "ftp://example.com"] {
            XCTAssertFalse(LinkSafety.allowed(URL(string: s)!), s)
        }
    }

    func testPreviewParsing() {
        let html = #"<html><head><title>Fallback</title><meta property="og:title" content="Kanso &amp; the Tray"><meta content="/img/card.png" property="og:image"></head>"#
        let p = LinkPreview.parse(html, base: URL(string: "https://example.com/post")!)
        XCTAssertEqual(p.title, "Kanso & the Tray")
        XCTAssertEqual(p.image?.absoluteString, "https://example.com/img/card.png")
        XCTAssertEqual(LinkPreview.parse("<title> Plain </title>", base: URL(string: "https://e.com")!).title, "Plain")
    }

    // MARK: Selection

    func testFinderSelection() {
        var s = TraySelection()
        s.click(1); XCTAssertEqual(s.selected, [1])
        s.click(3, command: true); XCTAssertEqual(s.selected, [1, 3])
        s.click(1, command: true); XCTAssertEqual(s.selected, [3], "⌘-click toggles")
        s.click(0); s.click(4, shift: true); XCTAssertEqual(s.selected, [0, 1, 2, 3, 4], "⇧-click selects the range")
        s.all(6); XCTAssertEqual(s.selected.count, 6)
        s.click(1); s.move(by: 4, count: 6); XCTAssertEqual(s.selected, [5], "↓ moves a row of 4")
        s.move(by: -1, count: 6, extend: true); XCTAssertEqual(s.selected, [4, 5], "⇧← extends")
        s.move(by: 10, count: 6); XCTAssertEqual(s.selected, [5], "clamped to the last tile")
        s.marquee([0, 1]); XCTAssertEqual(s.selected, [0, 1])
        s.marquee([3], adding: true); XCTAssertEqual(s.selected, [0, 1, 3])
        s.clamp(2); XCTAssertEqual(s.selected, [0, 1])
        var e = TraySelection(); e.move(by: 1, count: 3); XCTAssertEqual(e.selected, [0], "the first arrow selects the first tile")
    }
}
