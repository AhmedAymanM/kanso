import XCTest
@testable import KansoCore

struct FakeRuleCompiler: RuleCompiler {
    var raw: RawRuleDraft?
    func compile(_ sentence: String, shelves: [String]) async -> RawRuleDraft? { raw }
}

final class RuleDraftTests: XCTestCase {
    let settings = Settings()
    let sentence = "Move invoices from Stripe to Invoices"

    func raw(_ conditions: [(String, String)], dest: String, name: String = "", any: Bool = false) -> RawRuleDraft {
        RawRuleDraft(matchAny: any, conditions: conditions.map { .init(field: $0.0, value: $0.1) }, destination: dest, newName: name, newEmoji: "🧾", newDescription: "Invoices")
    }

    func draft(_ r: RawRuleDraft?, _ text: String? = nil, settings: Settings? = nil, model: Classifier = AllCapable()) async -> Result<RuleDraft, RuleDraftError> {
        await RuleDrafting.draft(text ?? sentence, settings: settings ?? self.settings, model: model, compiler: FakeRuleCompiler(raw: r))
    }

    func testTheExampleSentenceBecomesATypedDraftWithANewShelf() async throws {
        let d = try await draft(raw([("name", "invoice"), ("from", "stripe")], dest: "new", name: "Invoices")).get()
        XCTAssertEqual(d.rule.conditions, [Condition(.name, "*invoice*"), Condition(.from, "stripe")])
        XCTAssertEqual(d.rule.dest, "Invoices")
        XCTAssertEqual(d.newShelf?.name, "Invoices")
        XCTAssertTrue(d.rule.automatic, "model-made rules stay inside My Shelves")
        XCTAssertFalse(d.rule.matchAny)
        XCTAssertEqual(settings.type(named: "Invoices"), nil, "drafting creates nothing")
    }

    func testAnExistingShelfNeedsNoNewType() async throws {
        let d = try await draft(raw([("ext", ".PDF")], dest: "Documents"), "put every PDF in Documents").get()
        XCTAssertEqual(d.rule.conditions, [Condition(.ext, "pdf")])
        XCTAssertNil(d.newShelf)
    }

    func testValuesTheSentenceNeverContainedAreDropped() async {
        let r = await draft(raw([("name", "passport"), ("from", "evil.example")], dest: "Documents"))
        XCTAssertEqual(r, .failure(.noValidConditions), "the model may only use the user's words")
        let r2 = await draft(raw([("name", "passport"), ("from", "stripe")], dest: "Documents"))
        XCTAssertEqual(try? r2.get().rule.conditions, [Condition(.from, "stripe")])
    }

    func testGlobCharactersAreEscaped() async throws {
        let d = try await draft(raw([("name", "a*b[1]?")], dest: "Documents"), "move files named a*b[1]? to Documents").get()
        XCTAssertEqual(d.rule.conditions, [Condition(.name, #"*a\*b\[1\]\?*"#)])
        let item = Item(url: URL(fileURLWithPath: "/tmp/xa*b[1]?y.txt"), root: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(Engine.matches(d.rule, item), "an escaped value matches literally")
        let other = Item(url: URL(fileURLWithPath: "/tmp/xaZb1y.txt"), root: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(Engine.matches(d.rule, other), "and never as a wildcard")
    }

    func testPathsInsideAFilenameConditionAreSanitized() async throws {
        let text = "move files named ../../etc/passwd or ~/secrets to Documents"
        let d = try await draft(raw([("name", "../../etc/passwd"), ("name", "~/secrets")], dest: "Documents"), text).get()
        for c in d.rule.conditions {
            XCTAssertFalse(c.value.contains("/"), c.value)
            XCTAssertFalse(c.value.contains("\\/"), c.value)
        }
        XCTAssertEqual(d.rule.dest, "Documents")
    }

    func testHostileDestinationsAreRejected() async {
        for dest in ["../", "/", "~", "/etc", "~/Library", "../Manual Shelves", "Manual Shelves", "Keys", "Trash", ".Trash", "Documents/../..", "My Shelves", "Recents", "Duplicates", "Unsorted", "Screenshots", "new/../x"] {
            let r = await draft(raw([("name", "invoice")], dest: dest))
            XCTAssertEqual(r, .failure(.badDestination), "destination \(dest)")
        }
    }

    func testHostileNewShelfNamesAreRejected() async {
        for name in ["../", "/", "~", "Manual Shelves", "MANUAL SHELVES", "Ｍａｎｕａｌ Ｓｈｅｌｖｅｓ", "Keys", "keys", "Trash", ".Trash", "Recents", "My Shelves", "Duplicates", "Unknown Files", "", "...", "Manual\u{200B} Shelves"] {
            let r = await draft(raw([("name", "invoice")], dest: "new", name: name))
            XCTAssertEqual(r, .failure(.badDestination), "new shelf \(name.debugDescription)")
        }
    }

    func testANewShelfNameWithPathCharactersIsFlattened() async throws {
        let d = try await draft(raw([("name", "invoice")], dest: "new", name: "Docs/../Invoices"), "move invoices to Docs/../Invoices").get()
        XCTAssertFalse(d.rule.dest.contains("/"))
        XCTAssertFalse(d.rule.dest.contains(".."))
        XCTAssertTrue(Engine.automaticShelfAllowed(d.rule.dest))
    }

    func testANewNameThatMatchesAnExistingShelfReusesIt() async throws {
        let d = try await draft(raw([("name", "invoice")], dest: "new", name: "documents")).get()
        XCTAssertEqual(d.rule.dest, "Documents")
        XCTAssertNil(d.newShelf)
    }

    func testUnknownFieldsAndGarbageGiveNoDraft() async {
        let r = await draft(raw([("command", "invoice"), ("path", "/etc")], dest: "Documents"))
        XCTAssertEqual(r, .failure(.noValidConditions))
        let none = await draft(nil)
        XCTAssertEqual(none, .failure(.notUnderstood))
        let empty = await draft(raw([("name", "x")], dest: "Documents"), "   \n ")
        XCTAssertEqual(empty, .failure(.emptySentence))
    }

    func testSizeNeedsAParseableSizeFromTheSentence() async throws {
        let d = try await draft(raw([("size", "2 GB")], dest: "Videos"), "move videos over 2GB to Videos").get()
        XCTAssertEqual(d.rule.conditions, [Condition(.size, "2 GB")])
        let bad = await draft(raw([("size", "huge")], dest: "Videos"), "move huge videos to Videos")
        XCTAssertEqual(bad, .failure(.noValidConditions))
    }

    func testNoModelNoDraftAndTheReasonSaysWhy() async {
        var off = Settings()
        off.modelChoice = .rulesOnly
        let r = await draft(raw([("name", "invoice")], dest: "Documents"), settings: off)
        guard case .failure(.unavailable(let why)) = r else { return XCTFail("expected unavailable") }
        XCTAssertTrue(why.contains("Privacy & AI"))
        XCTAssertNotNil(RuleDrafting.unavailableReason(off, model: FakeAI(pick: nil)))
        XCTAssertNotNil(RuleDrafting.unavailableReason(settings, model: EngineTests.Unready()))
        XCTAssertNil(RuleDrafting.unavailableReason(settings, model: AllCapable()))
        XCTAssertNotNil(RuleDrafting.unavailableReason(settings, model: FakeAI(pick: nil)), "a model without the capability can't write rules")
    }

    struct AllCapable: Classifier {
        var available: Bool { true }
        var capabilities: Set<ModelCapability> { Set(ModelCapability.allCases) }
        func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? { nil }
    }

    func testTheClosedShelfListNeverOffersGuardedShelves() {
        let list = RuleDrafting.shelves(settings)
        for banned in ["Keys", "Unsorted", "Screenshots", "Duplicates", "Manual Shelves", "Trash"] { XCTAssertFalse(list.contains(banned), banned) }
        XCTAssertTrue(list.contains("Documents"))
    }

    // MARK: Saving

    func testSavingCreatesTheShelfTypeAndAppendsTheRule() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kanso-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = Store(dir: tmp)
        let engine = Engine(store: store, classifier: FakeAI(pick: nil))
        let d = try await draft(raw([("name", "invoice"), ("from", "stripe")], dest: "new", name: "Invoices")).get()
        XCTAssertNil(store.settings.type(named: "Invoices"), "nothing exists before Save")
        let before = store.settings.rules.count
        XCTAssertTrue(engine.saveDraft(d.rule, newShelf: d.newShelf))
        XCTAssertEqual(store.settings.type(named: "Invoices")?.emoji, "🧾")
        XCTAssertEqual(store.settings.rules.count, before + 1)
        XCTAssertEqual(store.settings.rules.last?.automatic, true)
        XCTAssertEqual(store.settings.rules.last?.builtIn, false)
    }

    func testSaveRefusesAForgedAutomaticRule() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kanso-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = Store(dir: tmp)
        let engine = Engine(store: store, classifier: FakeAI(pick: nil))
        for dest in ["../x", "/etc", "~/x", "Manual Shelves", "Keys", "Trash"] {
            var r = Rule([Condition(.name, "*a*")], dest: dest)
            r.automatic = true
            let before = store.settings.rules.count, types = store.settings.types.count
            XCTAssertFalse(engine.saveDraft(r, newShelf: NewShelf(name: dest, emoji: "📁", description: "")), dest)
            XCTAssertEqual(store.settings.rules.count, before)
            XCTAssertEqual(store.settings.types.count, types)
        }
    }
}
