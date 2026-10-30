import XCTest
@testable import KansoCore

final class SettingsTests: XCTestCase {
    let fm = FileManager.default

    /// What a settings.json looked like before versioning: no "version", no newer fields, one unknown key.
    let v0Fixture = """
    {"onboarded": true, "roots": ["~/Downloads", "", "~/Desktop"], "autoSort": false, "settleSeconds": -4,
     "keeper": "bestNamed", "recents": "hold", "keepTag": "Stay", "futureThing": {"a": 1},
     "since": "2026-09-01T10:00:00Z",
     "rules": [{"conditions": [{"field": "ext", "value": "pdf"}], "dest": "Documents/Invoices"}, {"broken": true}]}
    """

    func testOldFixtureLoadsAndIsMigrated() throws {
        let s = try Store.decoder.decode(Settings.self, from: Data(v0Fixture.utf8))
        XCTAssertEqual(Settings.storedVersion(Data(v0Fixture.utf8)), 0)
        XCTAssertEqual(s.version, Settings.currentVersion)
        XCTAssertTrue(s.onboarded)
        XCTAssertFalse(s.autoSort)
        XCTAssertEqual(s.roots, ["~/Downloads", "~/Desktop"])   // empty root dropped by the v0 to v1 step
        XCTAssertEqual(s.settleSeconds, 0)
        XCTAssertEqual(s.keeper, .bestNamed)
        XCTAssertEqual(s.recents, .hold)
        XCTAssertEqual(s.keepTag, "Stay")
        XCTAssertEqual(s.rules.count, 1)            // the malformed rule is skipped, the good one survives
        XCTAssertEqual(s.rules.first?.dest, "Documents/Invoices")
        XCTAssertEqual(s.types.count, FileType.defaults.count)   // missing keys take defaults
    }

    func testNewerVersionIsKept() throws {
        let s = try Store.decoder.decode(Settings.self, from: Data(#"{"version": 99, "keepTag": "Future"}"#.utf8))
        XCTAssertEqual(s.version, 99)
        XCTAssertEqual(s.keepTag, "Future")
    }

    func testStoreBacksUpAndRewritesAnOldFile() throws {
        let dir = fm.temporaryDirectory.appendingPathComponent("kanso-settings-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(v0Fixture.utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = Store(dir: dir)
        XCTAssertEqual(store.settings.version, Settings.currentVersion)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("settings.v0.bak").path))
        let rewritten = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
        XCTAssertEqual(Settings.storedVersion(rewritten), Settings.currentVersion)
        // Opening again changes nothing and makes no second backup of a current file.
        try fm.removeItem(at: dir.appendingPathComponent("settings.v0.bak"))
        _ = Store(dir: dir)
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("settings.v0.bak").path))
    }

    /// Every stored property must be read back by `init(from:)`. The JSON of a default Settings has one key per property
    /// (plus the optional dates, added here); every value is changed to something else, decoded, and encoded again.
    /// A key that `init(from:)` forgot comes back as its default and the comparison fails with the key's name.
    func testEveryFieldSurvivesARoundTrip() throws {
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Store.encoder.encode(Settings())) as? [String: Any])
        let enums: [String: String] = ["approach": "purpose", "recents": "hold", "keeper": "onShelf", "unknownFiles": "unsorted", "islandMode": "notch"]
        let dates: Set<String> = ["since", "sortingOffUntil", "sortingOffSince", "shortcutHintUntil"]
        for k in ["sortingOffUntil", "sortingOffSince"] { dict[k] = "2020-01-01T00:00:00Z" }
        for (k, v) in dict {
            if let e = enums[k] { dict[k] = e }
            else if dates.contains(k) { dict[k] = "2021-02-03T04:05:06Z" }
            else if let n = v as? NSNumber {
                dict[k] = CFGetTypeID(n) == CFBooleanGetTypeID() ? NSNumber(value: !n.boolValue) : NSNumber(value: n.intValue + 1)
            }
            else if v is String { dict[k] = "changed" }
            else if let a = v as? [Any] { dict[k] = (a.isEmpty || a.first is String) ? ["changed"] : [] }   // string lists, or lists of objects
            else if var o = v as? [String: Any] {   // the shortcut
                for (ik, iv) in o { if let n = iv as? NSNumber { o[ik] = NSNumber(value: n.intValue + 1) } else { o[ik] = "changed" } }
                dict[k] = o
            }
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try Store.decoder.decode(Settings.self, from: data)
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: Store.encoder.encode(decoded)) as? [String: Any])
        let want = NSDictionary(dictionary: dict), got = NSDictionary(dictionary: back)
        for k in dict.keys.sorted() {
            let same = (want.object(forKey: k) as? NSObject)?.isEqual(got.object(forKey: k)) ?? false
            XCTAssertTrue(same, "Settings.\(k) is not decoded by init(from:)")
        }
        XCTAssertEqual(Set(back.keys), Set(dict.keys))
    }
}
