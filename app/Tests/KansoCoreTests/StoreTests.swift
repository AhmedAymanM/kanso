import XCTest
@testable import KansoCore

final class StoreTests: XCTestCase {
    var dir: URL!
    let fm = FileManager.default

    override func setUp() { dir = fm.temporaryDirectory.appendingPathComponent("kanso-store-\(UUID().uuidString)") }
    override func tearDown() { try? fm.removeItem(at: dir) }

    func action(_ name: String) -> Action {
        Action(run: "r1", kind: .sorted, src: "/a/\(name)", dst: "/b/\(name)", root: "/a", shelf: "Documents", why: "extension", source: "metadata only")
    }

    var journal: URL { dir.appendingPathComponent("journal.jsonl") }

    func testCorruptJournalLineSurvivesModify() throws {
        let store = Store(dir: dir)
        let a = action("one.pdf")
        store.append(a)
        // A torn line without a trailing newline, as after a crash.
        let h = try FileHandle(forWritingTo: journal)
        try h.seekToEnd(); try h.write(contentsOf: Data("{\"run\":\"r1\",\"kind\":\"sor".utf8)); try h.close()
        // The next append starts a fresh line instead of gluing onto the torn one.
        let b = action("two.pdf")
        store.append(b)
        store.modify([a.id]) { $0.undone = true }

        let text = try String(contentsOf: journal, encoding: .utf8)
        XCTAssertTrue(text.contains("{\"run\":\"r1\",\"kind\":\"sor\n"), "torn line kept verbatim")
        let reloaded = Store(dir: dir)
        XCTAssertEqual(reloaded.actions.count, 2)
        XCTAssertTrue(reloaded.actions.first { $0.id == a.id }!.undone)
        XCTAssertFalse(reloaded.actions.first { $0.id == b.id }!.undone)
    }

    func testUnknownKindLineIsPreserved() throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let future = "{\"run\":\"r9\",\"kind\":\"teleported\",\"src\":\"/x\",\"dst\":\"/y\"}"
        try (future + "\n").write(to: journal, atomically: true, encoding: .utf8)
        let store = Store(dir: dir)
        XCTAssertEqual(store.actions.count, 0)
        let a = action("k.pdf")
        store.append(a)
        store.modify([a.id]) { $0.undone = true }
        XCTAssertTrue(try String(contentsOf: journal, encoding: .utf8).contains(future))
    }

    func testActionDecodingToleratesMissingFields() throws {
        let json = "{\"run\":\"r\",\"kind\":\"sorted\",\"src\":\"/a\",\"dst\":\"/b\"}"
        let a = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        XCTAssertEqual(a.shelf, "")
        XCTAssertEqual(a.trigger, "auto")
        XCTAssertFalse(a.undone)
    }

    func testBadRuleElementDoesNotWipeOtherRules() throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"rules":[
          {"conditions":[{"field":"name","value":"inv*"}],"dest":"Finance"},
          {"conditions":"nonsense"},
          {"conditions":[{"field":"ext","value":"zzz"}],"dest":"Zed"}
        ]}
        """
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let store = Store(dir: dir)
        XCTAssertEqual(store.settings.rules.map(\.dest), ["Finance", "Zed"])
    }

    func testCorruptSettingsAreBackedUp() throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try "this is not json {".write(to: url, atomically: true, encoding: .utf8)
        let store = Store(dir: dir)
        store.update { $0.keepTag = "Stay" }   // overwrites settings.json
        let bak = try String(contentsOf: dir.appendingPathComponent("settings.json.bak"), encoding: .utf8)
        XCTAssertEqual(bak, "this is not json {")
        XCTAssertEqual(Store(dir: dir).settings.keepTag, "Stay")
    }
}
