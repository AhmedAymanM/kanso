import XCTest
@testable import KansoCore

/// Cleanup on temp folders: carriers sorted from a "Downloads" root, timers measured from the sort, the last-used date
/// and the modification date (never access time), kept signs, one journaled run, Move to Documents.
final class CleanupTests: XCTestCase {
    var tmp: URL!, root: URL!, store: Store!, engine: Engine!
    let fm = FileManager.default
    let day: TimeInterval = 86400

    override func setUp() {
        Engine.batteryLow = { false }
        tmp = fm.temporaryDirectory.appendingPathComponent("kanso-cleanup-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("Downloads")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        store = Store(dir: tmp.appendingPathComponent("state"))
        store.update {
            $0.roots = [self.root.path]; $0.since = .distantPast; $0.settleSeconds = 0; $0.folderIcons = false
            $0.renaming = false; $0.duplicates = false; $0.cleanup = true
        }
        engine = Engine(store: store, classifier: FakeAI(pick: nil))
        engine.setIcon = { _, _ in }
    }

    override func tearDown() { try? fm.removeItem(at: tmp) }

    /// Puts files in Downloads and sorts them; returns the sort actions. mtimes are set in the past so only the sort counts.
    func sorted(_ names: [String], in dir: URL? = nil) async -> [Action] {
        for n in names {
            let u = (dir ?? root).appendingPathComponent(n)
            try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data("x".utf8).write(to: u)
            try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-60 * day)], ofItemAtPath: u.path)
        }
        return engine.apply(await engine.plan(all: true, trigger: "menu").moves, trigger: "menu")
    }

    func setLastUsed(_ url: URL, _ date: Date) {
        var spec: (Int64, Int64) = (Int64(date.timeIntervalSince1970), 0)
        _ = withUnsafeBytes(of: &spec) { setxattr(url.path, "com.apple.lastuseddate#PS", $0.baseAddress, 16, 0, 0) }
    }

    func testOnlyCarriersAreOnATimer() async {
        let acts = await sorted(["Figma.dmg", "Lease.pdf", "photo.jpg", "ubuntu.torrent", "notes.zip"])
        XCTAssertEqual(acts.count, 5)
        XCTAssertEqual(Set(engine.cleanupItems().map(\.carrier)), [.installer, .torrent, .archive])
        XCTAssertFalse(engine.cleanupItems().contains { $0.url.pathExtension == "pdf" || $0.url.pathExtension == "jpg" }, "content is never on a timer")
    }

    func testOffByDefaultAndDueAfterItsDays() async throws {
        store.update { $0.cleanup = false }
        _ = await sorted(["Figma.dmg"])
        XCTAssertTrue(engine.cleanupDue(now: Date().addingTimeInterval(60 * day)).isEmpty, "off: nothing is due")
        XCTAssertTrue(engine.runCleanup(engine.cleanupItems(), now: Date().addingTimeInterval(60 * day)).isEmpty)
        store.update { $0.cleanup = true }
        XCTAssertTrue(engine.cleanupDue(now: Date().addingTimeInterval(13 * day)).isEmpty)
        let due = engine.cleanupDue(now: Date().addingTimeInterval(15 * day))
        XCTAssertEqual(due.map(\.carrier), [.installer])
        let done = engine.runCleanup(due, now: Date().addingTimeInterval(15 * day))
        let t = try XCTUnwrap(done.first)
        XCTAssertEqual(t.trigger, "cleanup")
        XCTAssertEqual(t.details["carrier"], "installer")
        XCTAssertFalse(fm.fileExists(atPath: due[0].url.path))
        engine.undo([t.id])
        XCTAssertTrue(fm.fileExists(atPath: due[0].url.path), "⌘Z puts it back")
    }

    func testOneCleanupIsOneRun() async {
        _ = await sorted(["a.dmg", "b.torrent"])
        let later = Date().addingTimeInterval(20 * day)
        let done = engine.runCleanup(engine.cleanupDue(now: later), now: later)
        XCTAssertEqual(done.count, 2)
        XCTAssertEqual(Set(done.map(\.run)).count, 1)
        for a in done { engine.undo([a.id]) }
    }

    func testLastUsedDateRestartsTheClockButAccessTimeNever() async throws {
        _ = await sorted(["Figma.dmg"])
        let url = try XCTUnwrap(engine.cleanupItems().first?.url)
        var v = URLResourceValues(); v.contentAccessDate = Date().addingTimeInterval(10 * day)
        var u = url; try u.setResourceValues(v)
        XCTAssertEqual(engine.cleanupDue(now: Date().addingTimeInterval(15 * day)).count, 1, "access time is ignored")
        setLastUsed(url, Date().addingTimeInterval(10 * day))
        XCTAssertTrue(engine.cleanupDue(now: Date().addingTimeInterval(15 * day)).isEmpty, "opened on day 10: due on day 24")
        XCTAssertEqual(engine.cleanupDue(now: Date().addingTimeInterval(25 * day)).count, 1)
    }

    func testKeptSignsTakeAFileOffEveryTimer() async throws {
        _ = await sorted(["a.dmg", "b.dmg", "c.dmg", "d.dmg"])
        let items = engine.cleanupItems()
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0.url) })
        Tags.add(try XCTUnwrap(byName["a.dmg"]), ["Red"])                                  // any Finder tag
        let b = try XCTUnwrap(byName["b.dmg"])                                            // opened twice
        setLastUsed(b, Date().addingTimeInterval(-2 * day)); engine.countOpens(b)
        setLastUsed(b, Date().addingTimeInterval(-1 * day)); engine.countOpens(b)
        let c = try XCTUnwrap(byName["c.dmg"])                                            // renamed by the user
        try fm.moveItem(at: c, to: c.deletingLastPathComponent().appendingPathComponent("Keep this.dmg"))
        XCTAssertEqual(engine.cleanupItems().map(\.url.lastPathComponent), ["d.dmg"])
    }

    func testRunCleanupChecksEachFileAgain() async throws {
        _ = await sorted(["Figma.dmg"])
        let later = Date().addingTimeInterval(20 * day)
        let due = engine.cleanupDue(now: later)
        Tags.add(due[0].url, ["Keep"])          // tagged between the weekly card and the cleanup
        XCTAssertTrue(engine.runCleanup(due, now: later).isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: due[0].url.path))
    }

    func testOnlyDownloadsExceptScreenshots() async {
        let desktop = tmp.appendingPathComponent("Desktop")
        try! fm.createDirectory(at: desktop, withIntermediateDirectories: true)
        store.update { $0.roots = [self.root.path, desktop.path] }
        _ = await sorted(["old.dmg"], in: desktop)
        XCTAssertTrue(engine.cleanupItems().isEmpty, "files outside Downloads never expire")
        var shot = Action(run: "r", kind: .sorted, src: "/x", dst: "/x/Screenshot.png", root: desktop.path, shelf: "Screenshots", why: "screenshot", source: "metadata only")
        XCTAssertEqual(Carrier.of(shot), .screenshot)
        shot.why = "extension"
        XCTAssertNil(Carrier.of(shot))
    }

    func testExtractedArchiveLeavesAfterThreeDays() async throws {
        let src = tmp.appendingPathComponent("src/report.pdf")
        try fm.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: src)
        let zip = root.appendingPathComponent("report.zip")
        XCTAssertNotNil(SmartInstaller.run("/usr/bin/ditto", ["-c", "-k", src.path, zip.path]))
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-60 * day)], ofItemAtPath: zip.path)
        _ = engine.apply(await engine.plan(all: true, trigger: "menu").moves, trigger: "menu")
        let item = try XCTUnwrap(engine.cleanupItems().first)
        XCTAssertEqual(item.why, "30 days unused")
        try Data("pdf".utf8).write(to: item.url.deletingLastPathComponent().appendingPathComponent("report.pdf"))   // extracted next to it
        let early = try XCTUnwrap(engine.cleanupItems().first)
        XCTAssertEqual(early.why, "extracted 3 days ago")
        XCTAssertEqual(early.due.timeIntervalSinceNow, 3 * day, accuracy: 60)
    }

    func testKeptContentIsSuggestedForDocumentsAndMovesUndoably() async throws {
        let acts = await sorted(["Lease-2026.pdf", "Figma.dmg"])
        XCTAssertTrue(engine.documentsSuggestions().isEmpty, "nothing shows it's kept yet")
        let pdf = try XCTUnwrap(acts.first { $0.dst.hasSuffix(".pdf") })
        Tags.add(URL(fileURLWithPath: pdf.dst), ["Home"])
        Tags.add(URL(fileURLWithPath: try XCTUnwrap(acts.first { $0.dst.hasSuffix(".dmg") }).dst), ["Home"])
        XCTAssertEqual(engine.documentsSuggestions().map(\.id), [pdf.id], "content only, never carriers")
        let docs = tmp.appendingPathComponent("Documents")
        let m = try XCTUnwrap(engine.moveToDocuments(pdf.id, documents: docs))
        XCTAssertEqual(m.dst, docs.appendingPathComponent("My Shelves/Documents/Lease-2026.pdf").path)
        XCTAssertTrue(fm.fileExists(atPath: m.dst))
        engine.undo([m.id])
        XCTAssertTrue(fm.fileExists(atPath: pdf.dst), "⌘Z moves it back to Downloads")
        store.update { $0.suggestDocuments = false }
        XCTAssertTrue(engine.documentsSuggestions().isEmpty)
    }
}
