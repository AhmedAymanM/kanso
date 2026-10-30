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

    // MARK: Duplicate keeper reason

    func testKeeperReasonIsJournaled() async {
        make(pick: nil) { $0.duplicates = true }
        file("invoice.pdf", "same bytes", in: shelf("Documents"))
        file("invoice (1).pdf", "same bytes")
        file("contract.pdf", "other bytes", in: root.appendingPathComponent(Library.manual))
        file("contract copy.pdf", "other bytes")
        let done = await run().filter { $0.kind == .duplicate }
        XCTAssertEqual(done.count, 2)
        XCTAssertEqual(done.first { $0.srcName == "invoice (1).pdf" }?.details["keptWhy"], "The other copy was already filed on a shelf")
        XCTAssertEqual(done.first { $0.srcName == "contract copy.pdf" }?.details["keptWhy"], "The other copy is already in your Manual Shelves")
        let reloaded = Store(dir: tmp.appendingPathComponent("state"))
        XCTAssertNotNil(reloaded.actions.first { $0.kind == .duplicate }?.details["keptWhy"], "the reason survives a restart")
    }

    func testKeeperReasonForTwoLooseCopies() async {
        make(pick: nil) { $0.duplicates = true }
        file("a.pdf", "same")
        Thread.sleep(forTimeInterval: 1.1)
        file("a copy.pdf", "same")
        let dup = await run().first { $0.kind == .duplicate }
        XCTAssertEqual(dup?.details["keptWhy"], "Both arrived together, and its name is cleaner")
    }

    func testKeeperReasonWording() {
        let a = file("a.pdf"), b = file("a (1).pdf")
        XCTAssertEqual(Engine.keeperReason(kept: a, copy: b, root: root, setting: .bestNamed), "Its name is cleaner than \u{201C}a (1).pdf\u{201D}")
        XCTAssertEqual(Engine.keeperReason(kept: b, copy: a, root: root, setting: .bestNamed), "Its name is as clean as the other copy's")
    }

    // MARK: Rule preview

    func testRulePreviewListsMatchesWithoutSideEffects() throws {
        file("a.pdf"); file("b.pdf"); file("c.png")
        let before = try fm.contentsOfDirectory(atPath: root.path).sorted()
        let draft = Rule([Condition(.ext, "pdf")], dest: "Invoices")
        let p = engine.previewRule(draft)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.hits.map(\.name), ["a.pdf", "b.pdf"])
        XCTAssertEqual(p.hits.first?.otherwise, "Documents")
        XCTAssertEqual(p.scanned, 3)
        XCTAssertEqual(p.shadowedCount, 0)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), before, "nothing moved, nothing created")
        XCTAssertTrue(store.actions.isEmpty)
        XCTAssertFalse(store.settings.rules.contains { $0.id == draft.id }, "the draft is not saved")
        XCTAssertFalse(exists(root.appendingPathComponent(Library.mine)))
    }

    func testRulePreviewShowsFirstMatchWinsAndLimits() {
        make(pick: nil) { $0.rules.append(Rule([Condition(.ext, "pdf")], dest: "Reports")) }
        file("a.pdf"); file("a2.txt")
        for i in 0..<9 { file("note\(i).txt") }
        let draft = Rule([Condition(.name, "a*")], dest: "Notes")
        let p = engine.previewRule(draft)
        XCTAssertEqual(p.count, 1)                          // a2.txt
        XCTAssertEqual(p.shadowedCount, 1)                  // a.pdf goes to the earlier .pdf rule
        XCTAssertEqual(p.shadowed.first?.shadowedBy, ".pdf")
        let all = engine.previewRule(Rule([Condition(.ext, "txt")], dest: "Notes"), limit: 3)
        XCTAssertEqual(all.count, 10)
        XCTAssertEqual(all.hits.count, 3, "only the first few are listed")
    }

    func testRulePreviewWorksForASwitchedOffSavedRule() {
        var r = Rule([Condition(.ext, "png")], dest: "Images")
        r.enabled = false
        store.update { $0.rules.append(r) }
        file("c.png")
        XCTAssertEqual(engine.previewRule(r).count, 1)
        XCTAssertEqual(engine.previewRule(r).shadowedCount, 0)
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
