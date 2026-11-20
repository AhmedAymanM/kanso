import XCTest
@testable import KansoCore

final class SmartInstallerTests: XCTestCase {
    let root = URL(fileURLWithPath: "/Users/x/Downloads")

    func testRefusals() {
        let ok = root.appendingPathComponent("Figma.dmg")
        XCTAssertFalse(SmartInstaller.refuses(ok, roots: [root], keepTagged: false))
        XCTAssertTrue(SmartInstaller.refuses(ok, roots: [root], keepTagged: true))
        XCTAssertTrue(SmartInstaller.refuses(root.appendingPathComponent("Figma.iso"), roots: [root], keepTagged: false))
        XCTAssertTrue(SmartInstaller.refuses(root.appendingPathComponent("Manual Shelves/Figma.dmg"), roots: [root], keepTagged: false))
        XCTAssertTrue(SmartInstaller.refuses(root.appendingPathComponent("Manual Shelves/Old/Figma.dmg"), roots: [], keepTagged: false))
    }

    func testParsePackageIDs() {
        let info = #"<?xml version="1.0"?><pkg-info format-version="2" identifier="com.acme.tool" version="1.0" install-location="/">"#
        let dist = #"<installer-gui-script><pkg-ref id="com.acme.a"/><pkg-ref id="com.acme.b" version="2">x</pkg-ref><pkg-ref auth="root" id="com.acme.c"/></installer-gui-script>"#
        XCTAssertEqual(SmartInstaller.parsePackageIDs(info), ["com.acme.tool"])
        XCTAssertEqual(SmartInstaller.parsePackageIDs(dist), ["com.acme.a", "com.acme.b", "com.acme.c"])
    }

    func testAppsSpentNeedsEveryAppAndAfterMount() {
        let v1 = SmartInstaller.Version(version: "1.0", build: "1"), v2 = SmartInstaller.Version(version: "2.0", build: "5")
        func app(_ id: String, _ v: SmartInstaller.Version, ctime: TimeInterval = 200) -> SmartInstaller.AppInfo {
            .init(id: id, name: id, path: "/Applications/\(id).app", v: v, ctime: ctime, mtime: ctime)
        }
        let volume = [app("a", v2, ctime: 0), app("b", v2, ctime: 0)]
        // Only one of two installed.
        XCTAssertFalse(SmartInstaller.appsSpent(volume: volume, installed: [app("a", v2)], before: [:], mounted: 100, now: 300))
        // Both installed after the mount.
        XCTAssertTrue(SmartInstaller.appsSpent(volume: volume, installed: [app("a", v2), app("b", v2)], before: [:], mounted: 100, now: 300))
        // Installed before the mount.
        XCTAssertFalse(SmartInstaller.appsSpent(volume: volume, installed: [app("a", v2, ctime: 50), app("b", v2, ctime: 50)], before: [:], mounted: 100, now: 300))
        // Not settled yet.
        XCTAssertFalse(SmartInstaller.appsSpent(volume: volume, installed: [app("a", v2), app("b", v2)], before: [:], mounted: 100, now: 202))
        // Already installed at mount with the same version: an auto-update touching ctime doesn't count.
        let was = [app("a", v1).key: v1]
        XCTAssertFalse(SmartInstaller.appsSpent(volume: [app("a", v2)], installed: [app("a", v1)], before: was, mounted: 100, now: 300))
        XCTAssertFalse(SmartInstaller.appsSpent(volume: [app("a", v1)], installed: [app("a", v1)], before: was, mounted: 100, now: 300))
        // Upgrade to the volume's version counts.
        XCTAssertTrue(SmartInstaller.appsSpent(volume: [app("a", v2)], installed: [app("a", v2)], before: was, mounted: 100, now: 300))
    }

    func testPackageIDsFromARealFlatPackage() throws {
        let pkgbuild = "/usr/bin/pkgbuild"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: pkgbuild))
        let vol = FileManager.default.temporaryDirectory.appendingPathComponent("kanso-pkg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vol, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vol) }
        XCTAssertNotNil(SmartInstaller.run(pkgbuild, ["--nopayload", "--identifier", "test.kanso", "--version", "1", vol.appendingPathComponent("t.pkg").path]))
        XCTAssertEqual(SmartInstaller.packageIDs(onVolume: vol), ["test.kanso"])
    }
}
