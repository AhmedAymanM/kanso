import XCTest
@testable import KansoCore

final class SmartEjectTests: XCTestCase {
    let root = URL(fileURLWithPath: "/Users/x/Downloads")

    func testRefusals() {
        let ok = root.appendingPathComponent("Figma.dmg")
        XCTAssertFalse(SmartEject.refuses(ok, roots: [root], keepTagged: false))
        XCTAssertTrue(SmartEject.refuses(ok, roots: [root], keepTagged: true))
        XCTAssertTrue(SmartEject.refuses(root.appendingPathComponent("Figma.iso"), roots: [root], keepTagged: false))
        XCTAssertTrue(SmartEject.refuses(root.appendingPathComponent("Manual Shelves/Figma.dmg"), roots: [root], keepTagged: false))
        XCTAssertTrue(SmartEject.refuses(root.appendingPathComponent("Manual Shelves/Old/Figma.dmg"), roots: [], keepTagged: false))
    }

    func testParsePackageIDs() {
        let info = #"<?xml version="1.0"?><pkg-info format-version="2" identifier="com.acme.tool" version="1.0" install-location="/">"#
        let dist = #"<installer-gui-script><pkg-ref id="com.acme.a"/><pkg-ref id="com.acme.b" version="2">x</pkg-ref><pkg-ref auth="root" id="com.acme.c"/></installer-gui-script>"#
        XCTAssertEqual(SmartEject.parsePackageIDs(info), ["com.acme.tool"])
        XCTAssertEqual(SmartEject.parsePackageIDs(dist), ["com.acme.a", "com.acme.b", "com.acme.c"])
    }

    func testAppsSpentNeedsEveryAppAndAfterMount() {
        let v1 = SmartEject.Version(version: "1.0", build: "1"), v2 = SmartEject.Version(version: "2.0", build: "5")
        func app(_ id: String, _ v: SmartEject.Version, ctime: TimeInterval = 200) -> SmartEject.AppInfo {
            .init(id: id, name: id, path: "/Applications/\(id).app", v: v, ctime: ctime, mtime: ctime)
        }
        let volume = [app("a", v2, ctime: 0), app("b", v2, ctime: 0)]
        // Only one of two installed.
        XCTAssertFalse(SmartEject.appsSpent(volume: volume, installed: [app("a", v2)], before: [:], mounted: 100, now: 300))
        // Both installed after the mount.
        XCTAssertTrue(SmartEject.appsSpent(volume: volume, installed: [app("a", v2), app("b", v2)], before: [:], mounted: 100, now: 300))
        // Installed before the mount.
        XCTAssertFalse(SmartEject.appsSpent(volume: volume, installed: [app("a", v2, ctime: 50), app("b", v2, ctime: 50)], before: [:], mounted: 100, now: 300))
        // Not settled yet.
        XCTAssertFalse(SmartEject.appsSpent(volume: volume, installed: [app("a", v2), app("b", v2)], before: [:], mounted: 100, now: 202))
        // Already installed at mount with the same version: an auto-update touching ctime doesn't count.
        let was = [app("a", v1).key: v1]
        XCTAssertFalse(SmartEject.appsSpent(volume: [app("a", v2)], installed: [app("a", v1)], before: was, mounted: 100, now: 300))
        XCTAssertFalse(SmartEject.appsSpent(volume: [app("a", v1)], installed: [app("a", v1)], before: was, mounted: 100, now: 300))
        // Upgrade to the volume's version counts.
        XCTAssertTrue(SmartEject.appsSpent(volume: [app("a", v2)], installed: [app("a", v2)], before: was, mounted: 100, now: 300))
    }
}
