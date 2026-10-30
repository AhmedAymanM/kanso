import XCTest
@testable import KansoCore

extension EngineTests {
    struct Unready: Classifier {
        var available: Bool { false }
        var name: String { "Apple Intelligence" }
        var availability: ModelAvailability { ModelAvailability(ready: false, reason: "Turned off in System Settings") }
        func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? { nil }
    }

    func testPickerListsHonestStatuses() {
        let s = Settings()
        let ready = ModelPicker.options(s, apple: FakeAI(pick: nil))
        XCTAssertEqual(ready.map(\.name), ["Model", "Rules and extensions only", "Kanso Local"])
        XCTAssertTrue(ready[0].selectable && ready[0].selected)
        XCTAssertEqual(ready[0].status, "Ready")

        let off = ModelPicker.options(s, apple: Unready())
        XCTAssertFalse(off[0].selectable, "an unavailable model can't be picked")
        XCTAssertEqual(off[0].status, "Turned off in System Settings", "the reason is shown")
        XCTAssertTrue(off[1].selectable)

        let local = off[2]
        XCTAssertEqual(local.name, "Kanso Local")
        XCTAssertFalse(local.selectable)
        XCTAssertNil(local.choice)
        XCTAssertEqual(local.status, "Not available yet")
    }

    func testRulesOnlyIsAlwaysSelectableAndSelectedWhenChosen() {
        var s = Settings()
        s.modelChoice = .rulesOnly
        let o = ModelPicker.options(s, apple: Unready())
        XCTAssertTrue(o[1].selected)
        XCTAssertFalse(o[0].selected)
        XCTAssertFalse(ModelPicker.classifier(s, apple: FakeAI(pick: nil)).availability.ready)
        XCTAssertTrue(ModelPicker.classifier(Settings(), apple: FakeAI(pick: nil)).availability.ready)
    }

    func testChoiceDrivesTheEngine() async {
        make(pick: Pick(folder: "Documents")) { $0.modelChoice = .rulesOnly }
        file("mystery.qqq")
        _ = await run()
        XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("mystery.qqq")), "no model chosen: unknown types wait")
        XCTAssertTrue(store.settings.learnedExts.isEmpty)

        make(pick: Pick(folder: "Documents")) { $0.modelChoice = .appleIntelligence }
        file("mystery.qqq")
        _ = await run()
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("mystery.qqq")))
    }

    func testAModelWithoutTheClassifyCapabilityIsNeverAsked() async {
        struct NoClassify: Classifier {
            var available: Bool { true }
            var capabilities: Set<ModelCapability> { [.ask] }
            func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? {
                XCTFail("lacks .classify"); return Pick(folder: "Documents")
            }
        }
        engine = Engine(store: store, classifier: NoClassify())
        engine.setIcon = { _, _ in }
        file("mystery.qqq")
        _ = await run()
        XCTAssertTrue(exists(shelf(Shelf.unsorted).appendingPathComponent("mystery.qqq")))
    }

    func testLegacyBoolMigratesToTheChoice() throws {
        let off = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 1, "appleIntelligence": false}"#.utf8))
        XCTAssertEqual(off.modelChoice, .rulesOnly)
        XCTAssertEqual(off.version, Settings.currentVersion)
        let on = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 1, "appleIntelligence": true}"#.utf8))
        XCTAssertEqual(on.modelChoice, .appleIntelligence)
        let none = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 1}"#.utf8))
        XCTAssertEqual(none.modelChoice, .appleIntelligence, "default stays Apple Intelligence")
        let both = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 2, "modelChoice": "appleIntelligence", "appleIntelligence": false}"#.utf8))
        XCTAssertEqual(both.modelChoice, .appleIntelligence, "the new key wins")
        let bad = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 2, "modelChoice": "cloud"}"#.utf8))
        XCTAssertEqual(bad.modelChoice, .appleIntelligence, "an unknown choice never selects a model that doesn't exist")
    }

    func testPickConfidenceDefaultsToNil() {
        XCTAssertNil(Pick(folder: "Documents").confidence)
        XCTAssertEqual(Pick(folder: "Documents", confidence: 0.9).confidence, 0.9)
    }
}
