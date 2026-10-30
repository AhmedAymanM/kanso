import XCTest
@testable import KansoCore

final class TrayTests: XCTestCase {
    var tmp: URL!
    var root: URL!
    var outside: URL!
    var store: Store!
    var engine: Engine!
    let fm = FileManager.default

    override func setUp() {
        Engine.batteryLow = { false }
        tmp = fm.temporaryDirectory.appendingPathComponent("kanso-tray-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("Downloads")
        outside = tmp.appendingPathComponent("Elsewhere")
        for d in [root!, outside!] { try! fm.createDirectory(at: d, withIntermediateDirectories: true) }
        reload()
    }

    override func tearDown() { try? fm.removeItem(at: tmp) }

    func reload(pick: Pick? = nil) {
        store = Store(dir: tmp.appendingPathComponent("state"))
        store.update { $0.roots = [self.root.path]; $0.since = .distantPast; $0.settleSeconds = 0; $0.folderIcons = false; $0.renaming = false; $0.duplicates = false; $0.trayEnabled = true }
        engine = Engine(store: store, classifier: FakeAI(pick: pick))
        engine.setIcon = { _, _ in }
    }

    @discardableResult
    func file(_ name: String, in dir: URL? = nil) -> URL {
        let u = (dir ?? root).appendingPathComponent(name)
        try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! "x".write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func shelf(_ s: String) -> URL { root.appendingPathComponent(Library.mine).appendingPathComponent(s) }

    func testHoldingNeverMovesAndForgettingNeverTouchesTheFile() {
        let a = file("a.pdf"), b = file("b.png")
        let r = engine.tray.add([a, b])
        XCTAssertEqual(r.added, 2)
        XCTAssertTrue(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(Library.mine).path), "dropping creates no shelves")
        engine.tray.remove([engine.tray.items[0].id])
        XCTAssertEqual(engine.tray.count, 1)
        engine.tray.clear()
        XCTAssertEqual(engine.tray.count, 0)
        XCTAssertTrue(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path), "forgetting keeps the files")
    }

    func testSurvivesRelaunchWithPrivateFile() throws {
        engine.tray.add([file("a.pdf")])
        let again = TrayStore(dir: store.dir)
        XCTAssertEqual(again.items.map { ($0.path as NSString).lastPathComponent }, ["a.pdf"])
        let attrs = try fm.attributesOfItem(atPath: store.dir.appendingPathComponent("tray.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRefusesLinksMissingAndDuplicatesAndCaps() throws {
        let a = file("a.pdf")
        let link = root.appendingPathComponent("l.pdf")
        try fm.createSymbolicLink(at: link, withDestinationURL: a)
        var r = engine.tray.add([a, a, link, root.appendingPathComponent("ghost.pdf"), URL(string: "https://example.com/x")!])
        XCTAssertEqual(r.added, 1)
        XCTAssertEqual(r.already, 1)
        XCTAssertEqual(r.refused.count, 3)
        engine.tray.clear()
        let many = (0..<(TrayStore.cap + 5)).map { file("f\($0).txt") }
        r = engine.tray.add(many)
        XCTAssertEqual(r.added, TrayStore.cap)
        XCTAssertEqual(r.overflow, 5)
    }

    func testOrganizeIsOneUndoableRun() async {
        let a = file("a.pdf"), b = file("b.png")
        engine.tray.add([a, b])
        let plan = await engine.trayPlan()
        XCTAssertEqual(plan.movable, 2)
        XCTAssertEqual(Set(plan.rows.compactMap(\.shelf)), ["Documents", "Images"])
        XCTAssertTrue(fm.fileExists(atPath: a.path), "planning moves nothing")
        let res = engine.trayOrganize(plan)
        XCTAssertEqual(res.moved.count, 2)
        XCTAssertEqual(Set(res.moved.map(\.run)).count, 1)
        XCTAssertTrue(fm.fileExists(atPath: shelf("Documents").appendingPathComponent("a.pdf").path))
        XCTAssertEqual(engine.tray.count, 0)
        let back = engine.undoLast()
        XCTAssertEqual(back.count, 2)
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }

    func testFilesOutsideWatchedFoldersGoToTheFirstRoot() async {
        let a = file("a.pdf", in: outside)
        engine.tray.add([a])
        let res = engine.trayOrganize(await engine.trayPlan())
        XCTAssertEqual(res.moved.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: shelf("Documents").appendingPathComponent("a.pdf").path))
        XCTAssertFalse(fm.fileExists(atPath: a.path))
    }

    func testManualShelvesKeepAndMissingStay() async {
        let manual = file("m.pdf", in: root.appendingPathComponent(Library.manual))
        let kept = file("k.pdf")
        Tags.add(kept, [store.settings.keepTag])
        let gone = file("g.pdf")
        engine.tray.add([manual, kept, gone])
        try! fm.removeItem(at: gone)
        let plan = await engine.trayPlan()
        XCTAssertEqual(plan.movable, 0)
        XCTAssertEqual(Set(plan.rows.map { $0.entry.state }), [.manualShelves, .keep, .missing])
        let res = engine.trayOrganize(plan)
        XCTAssertTrue(res.moved.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: manual.path) && fm.fileExists(atPath: kept.path))
        XCTAssertEqual(engine.tray.count, 3, "nothing is dropped silently")
    }

    func testExcludedFilesStay() async {
        store.update { $0.excludes = ["*.pdf"] }
        engine.tray.add([file("a.pdf")])
        let plan = await engine.trayPlan()
        XCTAssertEqual(plan.rows.first?.entry.state, .keep)
        XCTAssertEqual(plan.movable, 0)
    }

    func testBookmarkFollowsAFileThatMoved() {
        let a = file("a.pdf")
        engine.tray.add([a])
        let moved = outside.appendingPathComponent("renamed.pdf")
        try! fm.moveItem(at: a, to: moved)
        let e = engine.trayEntries()
        XCTAssertEqual(e.first?.state, .ready)
        XCTAssertEqual(e.first?.url.lastPathComponent, "renamed.pdf")
    }

    func testUnknownExtensionWithoutModelGoesToUnsortedAndKeysAreLocked() async {
        store.update { $0.unknownFiles = .unsorted }
        let k = file("id.pem"), q = file("thing.qx7")
        engine.tray.add([k, q])
        let plan = await engine.trayPlan()
        let byName = Dictionary(uniqueKeysWithValues: plan.rows.map { ($0.name, $0) })
        XCTAssertEqual(byName["id.pem"]?.shelf, "Keys")
        XCTAssertTrue(byName["id.pem"]?.entry.locked ?? false)
        XCTAssertEqual(byName["thing.qx7"]?.shelf, "Unsorted")
    }

    func testChosenShelfOverridesButNeverIntoKeys() async {
        engine.tray.add([file("a.pdf")])
        let plan = await engine.trayPlan()
        let res = engine.trayOrganize(plan, shelves: [plan.rows[0].id: "Keys"])
        XCTAssertEqual(res.moved.first?.shelf, "Documents", "an override into Keys is ignored")
        engine.tray.add([file("b.pdf")])
        let p2 = await engine.trayPlan()
        let r2 = engine.trayOrganize(p2, shelves: [p2.rows[0].id: "Images"])
        XCTAssertEqual(r2.moved.first?.shelf, "Images")
    }

    func testOrganizeOnlyChosenRows() async {
        engine.tray.add([file("a.pdf"), file("b.png")])
        let plan = await engine.trayPlan()
        let a = plan.rows.first { $0.name == "a.pdf" }!
        let res = engine.trayOrganize(plan, only: [a.id])
        XCTAssertEqual(res.moved.count, 1)
        XCTAssertEqual(engine.tray.count, 1)
    }

    func testFailedMoveStaysAndIsReported() async {
        // A destination shelf that is a plain file makes the move fail.
        let a = file("a.pdf")
        try! fm.createDirectory(at: root.appendingPathComponent(Library.mine), withIntermediateDirectories: true)
        try! "x".write(to: shelf("Documents"), atomically: true, encoding: .utf8)
        engine.tray.add([a])
        let res = engine.trayOrganize(await engine.trayPlan())
        XCTAssertTrue(res.moved.isEmpty)
        XCTAssertEqual(res.stayed.count, 1)
        XCTAssertEqual(engine.tray.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }
}
