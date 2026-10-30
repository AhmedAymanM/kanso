import XCTest
@testable import KansoCore

extension EngineTests {
    @discardableResult
    func unsorted(_ names: [String]) -> [URL] {
        names.map { file($0, in: shelf(Shelf.unsorted)) }
    }

    func testFiveFilesWithTheSameUnclaimedExtensionSuggestAShelf() {
        unsorted((1...5).map { "item\($0).qqq" } + (1...4).map { "other\($0).zzz" })
        let s = engine.suggestedShelves()
        XCTAssertEqual(s.map(\.id), ["ext:qqq"], "four are not enough")
        XCTAssertEqual(s.first?.name, "QQQ Files")
        XCTAssertEqual(s.first?.files.count, 5)
    }

    func testNothingMovesAndNothingIsCreatedUntilAccept() {
        let urls = unsorted((1...6).map { "item\($0).qqq" })
        _ = engine.suggestedShelves()
        XCTAssertTrue(urls.allSatisfy { exists($0) })
        XCTAssertNil(store.settings.type(named: "QQQ Files"))
        XCTAssertFalse(exists(shelf("QQQ Files")))
    }

    func testAcceptCreatesTheTypeAndMovesEverythingAsOneUndoableRun() {
        unsorted((1...6).map { "item\($0).qqq" })
        let done = engine.acceptShelfSuggestion("ext:qqq")
        XCTAssertEqual(done.count, 6)
        XCTAssertEqual(Set(done.map(\.run)).count, 1, "one run, one Undo")
        XCTAssertTrue(done.allSatisfy { $0.shelf == "QQQ Files" })
        XCTAssertTrue(exists(shelf("QQQ Files").appendingPathComponent("item3.qqq")))
        XCTAssertFalse(exists(shelf(Shelf.unsorted).appendingPathComponent("item3.qqq")))
        XCTAssertEqual(store.settings.type(named: "QQQ Files")?.match, ["qqq"])
        XCTAssertTrue(store.settings.learnedExts.contains("qqq"))
        XCTAssertTrue(engine.suggestedShelves().isEmpty)

        let back = engine.undoLast()
        XCTAssertEqual(back.count, 6)
        XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("item3.qqq")))
    }

    func testDismissIsRememberedAcrossRestarts() {
        unsorted((1...5).map { "item\($0).qqq" })
        engine.dismissShelfSuggestion("ext:qqq")
        XCTAssertTrue(engine.suggestedShelves().isEmpty)
        let reopened = Engine(store: Store(dir: tmp.appendingPathComponent("state")), classifier: FakeAI(pick: nil))
        XCTAssertTrue(reopened.suggestedShelves().isEmpty, "a dismissed suggestion stays dismissed")
        XCTAssertEqual(engine.acceptShelfSuggestion("ext:qqq").count, 0, "and can't be accepted by id either")
    }

    func testALeadingWordSuggestsAShelfAndARule() {
        unsorted((1...5).map { "invoice-\($0)-acme.xyz\($0)" })
        let s = engine.suggestedShelves()
        XCTAssertEqual(s.map(\.id), ["word:invoice"])
        XCTAssertEqual(s.first?.name, "Invoices")
        let done = engine.acceptShelfSuggestion("word:invoice")
        XCTAssertEqual(done.count, 5)
        XCTAssertTrue(exists(shelf("Invoices").appendingPathComponent("invoice-2-acme.xyz2")))
        let rule = store.settings.rules.last
        XCTAssertEqual(rule?.conditions, [Condition(.name, "invoice*")])
        XCTAssertEqual(rule?.dest, "Invoices")
        XCTAssertEqual(rule?.automatic, true)
    }

    func testGenericWordsAndKnownExtensionsAreNotSuggested() {
        unsorted((1...6).map { "scan\($0).xx\($0)" } + (1...6).map { "note\($0).pdf" })
        XCTAssertTrue(engine.suggestedShelves().isEmpty)
    }

    func testAStaleOrForgedIdDoesNothing() {
        unsorted((1...5).map { "item\($0).qqq" })
        for id in ["ext:../../etc", "ext:zzz", "word:keys", "", "ext:qqq/../x"] {
            XCTAssertTrue(engine.acceptShelfSuggestion(id).isEmpty, id)
        }
        XCTAssertNil(store.settings.type(named: "QQQ Files"))
    }

    func testAShelfNameThatAlreadyExistsIsNotSuggested() {
        make(pick: nil) { $0.types.append(FileType("QQQ Files", "📁", "x", [])) }
        unsorted((1...5).map { "item\($0).qqq" })
        XCTAssertTrue(engine.suggestedShelves().isEmpty)
    }

    func testTurnedOffSuggestionsStaySilent() {
        make(pick: nil) { $0.suggestTypes = false }
        unsorted((1...5).map { "item\($0).qqq" })
        XCTAssertTrue(engine.suggestedShelves().isEmpty)
    }
}
