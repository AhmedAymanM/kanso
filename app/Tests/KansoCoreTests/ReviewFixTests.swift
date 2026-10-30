import XCTest
@testable import KansoCore

// Regressions from the adversarial review of the plain-English rules / suggested shelves work.

extension RuleDraftTests {
    func testAConditionOfJustADotOrALetterIsRejected() async {
        for (field, value) in [("from", "."), ("from", ".."), ("name", "."), ("name", "a"), ("ext", "p"), ("ext", "."), ("from", "-")] {
            let r = await draft(raw([(field, value)], dest: "Documents"), "move a.pdf files from stripe.com to Documents")
            XCTAssertEqual(r, .failure(.noValidConditions), "\(field)=\(value)")
        }
    }

    func testAValueMustBeAWholeWordOfTheSentence() async {
        // "pdf" is inside "pdfs"? No: a bare extension inside another word is not what the user said.
        let r = await draft(raw([("ext", "pd")], dest: "Documents"), "move my pdfs to Documents")
        XCTAssertEqual(r, .failure(.noValidConditions))
        let host = await draft(raw([("from", "stripe.co")], dest: "Documents"), "move files from stripe.com to Documents")
        XCTAssertEqual(host, .failure(.noValidConditions), "half a domain is not the domain")
        let ok = try? await draft(raw([("from", "stripe.com")], dest: "Documents"), "move files from stripe.com to Documents").get()
        XCTAssertEqual(ok?.rule.conditions, [Condition(.from, "stripe.com")])
        let multi = try? await draft(raw([("name", "tax return")], dest: "Documents"), "move my tax return files to Documents").get()
        XCTAssertEqual(multi?.rule.conditions, [Condition(.name, "*tax return*")])
        let split = await draft(raw([("name", "return tax")], dest: "Documents"), "move my tax return files to Documents")
        XCTAssertEqual(split, .failure(.noValidConditions), "words must be adjacent and in order")
    }

    func testASizeMustBeExactlyTheOneInTheSentence() async throws {
        let cases: [(String, String)] = [("1", "files over 100 MB"), ("1 MB", "files over 100 MB"), ("2 GB", "files over 20 GB"), ("20 GB", "files over 2 GB"),
                                         ("5 GB", "files over 1.5 GB"), ("1 GB", "files over 1024 MB"), ("100", "files over 100 MB"), ("MB", "files over 100 MB")]
        for (value, said) in cases {
            let r = await draft(raw([("size", value)], dest: "Videos"), "move \(said) to Videos")
            XCTAssertEqual(r, .failure(.noValidConditions), "size \(value) in “\(said)”")
        }
        let ok = try await draft(raw([("size", "20 GB")], dest: "Videos"), "move files over 20 GB to Videos").get()
        XCTAssertEqual(ok.rule.conditions, [Condition(.size, "20 GB")])
        let tight = try await draft(raw([("size", "1.5GB")], dest: "Videos"), "move files over 1.5 GB to Videos").get()
        XCTAssertEqual(tight.rule.conditions.count, 1)
    }

    func testMatchAnyNeedsTheWordOrInTheSentence() async throws {
        let conds = [("ext", "pdf"), ("ext", "docx")]
        let all = try await draft(raw(conds, dest: "Documents", any: true), "move pdf and docx files to Documents").get()
        XCTAssertFalse(all.rule.matchAny, "the model can't turn an AND sentence into an OR rule")
        let any = try await draft(raw(conds, dest: "Documents", any: true), "move pdf or docx files to Documents").get()
        XCTAssertTrue(any.rule.matchAny)
        let word = try await draft(raw(conds, dest: "Documents", any: true), "move pdf files and docx files to Documents, the colour of a doctor").get()
        XCTAssertFalse(word.rule.matchAny, "'or' inside another word does not count")
    }

    func testANewShelfNameMustBeInTheSentenceAndLosesControlCharacters() async throws {
        let invented = await draft(raw([("name", "invoice")], dest: "new", name: "Receipts"))
        XCTAssertEqual(invented, .failure(.badDestination), "the model may not name a shelf the user never said")
        let d = try await draft(raw([("name", "invoice")], dest: "new", name: "In\u{202E}vo\u{200B}ices")).get()
        XCTAssertEqual(d.rule.dest, "Invoices")
        XCTAssertEqual(d.newShelf?.name, "Invoices")
        XCTAssertFalse(d.rule.dest.unicodeScalars.contains { $0.properties.generalCategory == .format })
        let bidiOnly = await draft(raw([("name", "invoice")], dest: "new", name: "\u{202E}\u{200B}"))
        XCTAssertEqual(bidiOnly, .failure(.badDestination))
    }
}

extension EngineTests {
    // MARK: Excludes and Unicode normalization

    func testExcludesMatchAcrossUnicodeNormalizationForms() async {
        let nfc = "caf\u{00E9}*", nfd = "cafe\u{0301}*"
        XCTAssertNotEqual(Array(nfc.unicodeScalars), Array(nfd.unicodeScalars))   // Swift String == is canonical, so compare scalars
        for (pattern, name) in [(nfc, "cafe\u{0301}-menu.pdf"), (nfd, "caf\u{00E9}-menu.pdf")] {
            make(pick: nil) { $0.excludes = [pattern] }
            file(name)
            let plan = await engine.plan()
            XCTAssertTrue(plan.moves.isEmpty, "pattern \(pattern.debugDescription) must exclude \(name.debugDescription)")
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
        make(pick: nil) { $0.excludes = []; $0.rootExcludes = [self.root.path: ["Caf\u{00E9}"]]; $0.sortFolders = true }
        try? fm.createDirectory(at: root.appendingPathComponent("cafe\u{0301}"), withIntermediateDirectories: true)
        let plan = await engine.plan()
        XCTAssertTrue(plan.moves.isEmpty, "the per-folder list folds too")
    }

    // MARK: Batch card

    func testDuplicatesSentToTheTrashAreCountedAsTrashedNotHeld() {
        func act(_ k: Action.Kind, _ shelf: String) -> Action {
            var a = Action(run: "r1", kind: k, src: "/d/a.pdf", dst: "/d/My Shelves/Documents/a.pdf", root: "/d", shelf: shelf, why: "x", source: "x")
            a.trigger = "menu"
            return a
        }
        let trashed = Batch.summary([act(.sorted, "Documents"), act(.sorted, "Documents"), act(.duplicate, "Trash")], trigger: "menu")
        XCTAssertEqual(trashed?.text, "Sorted 2 files, moved 1 copy to Trash")
        XCTAssertFalse(trashed?.text.contains("held") ?? true)
        let mixed = Batch.summary([act(.sorted, "Documents"), act(.duplicate, "Duplicates"), act(.duplicate, "Trash"), act(.duplicate, "Trash")], trigger: "menu")
        XCTAssertEqual(mixed?.text, "Sorted 1 file, held 1 copy, moved 2 copies to Trash")
    }

    // MARK: Suggested shelves

    func testUndoingAcceptTakesTheTypeAndLearnedExtensionBackOut() {
        unsorted((1...5).map { "item\($0).qqq" })
        let done = engine.acceptShelfSuggestion("ext:qqq")
        XCTAssertEqual(done.count, 5)
        XCTAssertNotNil(store.settings.type(named: "QQQ Files"))
        XCTAssertEqual(engine.undoLast().count, 5)
        XCTAssertNil(store.settings.type(named: "QQQ Files"), "an undone Accept leaves no type")
        XCTAssertFalse(store.settings.learnedExts.contains("qqq"))
        XCTAssertNil(store.settings.type(forExt: "qqq"))
    }

    func testTheFolderIconFileDoesNotKeepAnUndoneShelfAlive() {
        unsorted((1...5).map { "item\($0).qqq" })
        engine.acceptShelfSuggestion("ext:qqq")
        file("Icon\r", in: shelf("QQQ Files"))   // what set_folder_icon leaves in every shelf Kanso creates
        _ = engine.undoLast()
        XCTAssertNil(store.settings.type(named: "QQQ Files"))
    }

    func testAcceptedSuggestionMovesAreNotCountedAsYourCorrections() async {
        for i in 1...6 { file("thing\(i).qqq") }
        _ = await run()   // Kanso files them in Unsorted
        engine.acceptShelfSuggestion("ext:qqq")
        engine.detectCorrections()
        XCTAssertTrue(store.pending.corrections.isEmpty, "Kanso moved them, not you")
        XCTAssertTrue(store.actions.allSatisfy { $0.details["corrected"] == nil })
    }

    func testUndoingAcceptOfAWordShelfRemovesItsRule() {
        unsorted((1...5).map { "invoice-\($0)-acme.xyz\($0)" })
        let rules = store.settings.rules.count
        XCTAssertEqual(engine.acceptShelfSuggestion("word:invoice").count, 5)
        XCTAssertEqual(store.settings.rules.count, rules + 1)
        _ = engine.undoLast()
        XCTAssertEqual(store.settings.rules.count, rules)
        XCTAssertNil(store.settings.type(named: "Invoices"))
    }

    func testAPartialUndoKeepsTheShelfType() {
        unsorted((1...5).map { "item\($0).qqq" })
        let done = engine.acceptShelfSuggestion("ext:qqq")
        engine.undo(Set(done.prefix(2).map(\.id)))
        XCTAssertNotNil(store.settings.type(named: "QQQ Files"), "three files still live on the shelf")
        XCTAssertTrue(store.settings.learnedExts.contains("qqq"))
        engine.undo(Set(done.map(\.id)))
        XCTAssertNil(store.settings.type(named: "QQQ Files"), "the rest of the run is undone, so the type goes")
    }

    func testAShelfWithSomethingNewInItKeepsItsTypeOnUndo() {
        unsorted((1...5).map { "item\($0).qqq" })
        engine.acceptShelfSuggestion("ext:qqq")
        file("mine.txt", in: shelf("QQQ Files"))
        _ = engine.undoLast()
        XCTAssertNotNil(store.settings.type(named: "QQQ Files"), "a file the user put there is not ours to orphan")
    }

    func testASymlinkedUnsortedShelfIsNotASource() throws {
        let outside = tmp.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        for i in 1...6 { _ = file("item\(i).qqq", in: outside) }
        let lib = root.appendingPathComponent(Library.mine)
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: lib.appendingPathComponent(Shelf.unsorted), withDestinationURL: outside)
        XCTAssertTrue(engine.suggestedShelves().isEmpty)
        XCTAssertTrue(engine.acceptShelfSuggestion("ext:qqq").isEmpty)
        XCTAssertTrue(exists(outside.appendingPathComponent("item1.qqq")))
    }
}

final class FutureSettingsTests: XCTestCase {
    func testASettingsFileFromANewerBuildIsBackedUpBeforeThisBuildSavesOverIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kanso-future-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let future = Settings.currentVersion + 7
        let original = "{\"version\":\(future),\"futureOnlyKey\":{\"a\":1}}"
        try original.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let store = Store(dir: dir)
        store.update { $0.onboarded = true }   // a save that drops the key this build doesn't know
        let bak = dir.appendingPathComponent("settings.v\(future).bak")
        XCTAssertEqual(try String(contentsOf: bak, encoding: .utf8), original)
        XCTAssertFalse(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8).contains("futureOnlyKey"))
        // A second launch does not overwrite the backup with the already-rewritten file.
        _ = Store(dir: dir)
        XCTAssertEqual(try String(contentsOf: bak, encoding: .utf8), original)
    }
}
