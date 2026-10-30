import XCTest
@testable import KansoCore

/// Tests for the v1 parity features. They reuse the fixtures of EngineTests (temp root, store, fake classifier).
extension EngineTests {
    // MARK: Destination safety

    var outside: URL {
        let u = tmp.appendingPathComponent("Outside")
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testModelCannotCreateOrPickProtectedShelves() async {
        for name in ["Manual Shelves", "keys", "Ｍａｎｕａｌ Ｓｈｅｌｖｅｓ", "Recents", "My Shelves", "Duplicates"] {
            make(pick: Pick(folder: Brain.new, name: name, emoji: "📁", description: "x"))
            let u = file("a.xyz")
            _ = await run()
            XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("a.xyz")), "\(name) must end in Unsorted")
            XCTAssertNil(store.settings.type(named: name), "\(name) must not become a type")
            XCTAssertFalse(exists(u))
            try? fm.removeItem(at: root)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    func testModelCannotPickKeysEvenIfAskedFor() async {
        make(pick: Pick(folder: "Keys"))
        file("a.xyz")
        _ = await run()
        XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("a.xyz")))
        XCTAssertFalse(Brain.options(store.settings).contains { $0.0 == "Keys" })
    }

    func testExtensionTableStillFilesKeys() async {
        file("id.pem")
        _ = await run()
        XCTAssertTrue(exists(shelf("Keys").appendingPathComponent("id.pem")))
    }

    func testAutomaticRuleCannotLeaveMyShelves() async {
        let out = outside
        make(pick: nil) {
            var r = Rule([Condition(.ext, "zzz")], dest: out.path)
            r.automatic = true
            $0.rules = [r]
        }
        file("a.zzz")
        _ = await run()
        XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("a.zzz")))
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: out.path))?.count, 0)
    }

    func testUserWrittenAbsoluteDestinationStillWorks() async {
        let out = outside
        make(pick: nil) { $0.rules = [Rule([Condition(.ext, "zzz")], dest: out.path)] }
        file("a.zzz")
        _ = await run()
        XCTAssertTrue(exists(out.appendingPathComponent("a.zzz")))
    }

    func testRelativeDestinationsNeverReachOwnFoldersOrEscapeThroughSymlinks() throws {
        let mine = root.appendingPathComponent(Library.mine)
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: mine.appendingPathComponent("Escape"), withDestinationURL: outside)
        for dest in ["Manual Shelves", "Documents/Recents", "manual shelves", "Escape", "Escape/deeper", "/etc", "~/Desktop"] {
            XCTAssertEqual(engine.resolve(root, dest).lastPathComponent, Shelf.unsorted, dest)
        }
        XCTAssertEqual(engine.resolve(root, "Documents/Invoices").path, mine.appendingPathComponent("Documents/Invoices").path)
        XCTAssertEqual(engine.resolve(root, "/tmp/x", userPath: true).path, "/tmp/x")
    }

    func testDestinationWarning() {
        XCTAssertNil(Engine.destinationWarning("Documents/Invoices"))
        XCTAssertNotNil(Engine.destinationWarning("~/Taxes"))
        XCTAssertTrue(Engine.destinationWarning("/Users/me/Downloads/Manual Shelves/x")?.contains("Manual Shelves") == true)
    }

    func testSuggestionsAndCorrectionsNeverTeachKeys() {
        let sug = RuleSuggestion(condition: Condition(.ext, "zzz"), shelf: "Keys", files: ["a.zzz"])
        store.updatePending { $0.suggestions = [sug] }
        let before = store.settings.rules.count
        engine.acceptSuggestion(sug.id)
        XCTAssertEqual(store.settings.rules.count, before)
        XCTAssertTrue(store.pending.suggestions.isEmpty)

        engine.teach(Correction(name: "a.zzz", ext: "zzz", from: nil, fromShelf: "Documents", toShelf: "Keys"))
        XCTAssertFalse(store.settings.learnedExts.contains("zzz"))

        let ok = RuleSuggestion(condition: Condition(.ext, "zzz"), shelf: "Documents", files: [])
        store.updatePending { $0.suggestions = [ok] }
        engine.acceptSuggestion(ok.id)
        XCTAssertEqual(store.settings.rules.first?.dest, "Documents")
        XCTAssertEqual(store.settings.rules.first?.automatic, true)
    }
}
