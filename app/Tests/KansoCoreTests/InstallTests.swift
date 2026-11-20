import XCTest
@testable import KansoCore

/// Smart Installer on temp folders: a real ad hoc signed app bundle, a fake /Applications, a download in a watched folder.
/// Trashing tests put a few small files in ~/.Trash.
final class InstallTests: XCTestCase {
    var tmp: URL!, root: URL!, apps: URL!, store: Store!, engine: Engine!
    let fm = FileManager.default

    override func setUp() {
        tmp = fm.temporaryDirectory.appendingPathComponent("kanso-install-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("Downloads")
        apps = tmp.appendingPathComponent("Applications")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: apps, withIntermediateDirectories: true)
        store = Store(dir: tmp.appendingPathComponent("state"))
        store.update { $0.roots = [self.root.path]; $0.folderIcons = false }
        engine = Engine(store: store, classifier: FakeAI(pick: nil))
    }

    override func tearDown() { try? fm.removeItem(at: tmp) }

    /// A minimal app bundle; signed ad hoc unless `signed` is false.
    @discardableResult
    func app(_ dir: URL, _ name: String = "Figma", id: String = "com.figma.Desktop", version: String = "1.0", signed: Bool = true) throws -> URL {
        let a = dir.appendingPathComponent("\(name).app"), c = a.appendingPathComponent("Contents")
        try fm.createDirectory(at: c.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": id, "CFBundleExecutable": name, "CFBundleShortVersionString": version, "CFBundleVersion": "1"])
            .write(to: c.appendingPathComponent("Info.plist"), atomically: true)
        if signed { try fm.copyItem(atPath: "/usr/bin/true", toPath: c.appendingPathComponent("MacOS/\(name)").path) }
        else {   // a script, so nothing in the bundle carries a signature
            let exe = c.appendingPathComponent("MacOS/\(name)")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: exe)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }
        if signed { XCTAssertNotNil(SmartInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", a.path], timeout: 30), "ad hoc signing failed") }
        return a
    }

    func download(_ name: String = "Figma.dmg") -> URL {
        let u = root.appendingPathComponent(name)
        try! Data("image".utf8).write(to: u)
        return u
    }

    // MARK: What a volume offers

    func testSingleAppIgnoresHiddenFilesAndTheApplicationsAlias() throws {
        let vol = tmp.appendingPathComponent("vol")
        try app(vol, signed: false)
        try fm.createSymbolicLink(atPath: vol.appendingPathComponent("Applications").path, withDestinationPath: "/Applications")
        try fm.createDirectory(at: vol.appendingPathComponent(".background"), withIntermediateDirectories: true)
        XCTAssertEqual(SmartInstaller.singleApp(in: vol)?.lastPathComponent, "Figma.app")
        try Data().write(to: vol.appendingPathComponent("Read Me.pdf"))
        XCTAssertNil(SmartInstaller.singleApp(in: vol), "another item: the fallback applies")
    }

    func testTwoAppsOrAPackageFallBack() throws {
        let vol = tmp.appendingPathComponent("vol")
        try app(vol, signed: false); try app(vol, "Figma Agent", signed: false)
        XCTAssertNil(SmartInstaller.singleApp(in: vol))
        let vol2 = tmp.appendingPathComponent("vol2")
        try app(vol2, signed: false); try Data().write(to: vol2.appendingPathComponent("Extras.pkg"))
        XCTAssertNil(SmartInstaller.singleApp(in: vol2))
    }

    func testVersionsCompareNumerically() throws {
        typealias V = SmartInstaller.Version
        XCTAssertEqual(SmartInstaller.compare(V(version: "3.9", build: "1"), V(version: "3.10", build: "1")), .orderedAscending)
        XCTAssertEqual(SmartInstaller.compare(V(version: "3.10", build: "2"), V(version: "3.10", build: "10")), .orderedAscending)
        let vol = tmp.appendingPathComponent("vol")
        let new = try XCTUnwrap(SmartInstaller.appInfo(try app(vol, version: "3.4", signed: false)))
        XCTAssertEqual(SmartInstaller.existing(new, in: apps), .none)
        try app(apps, version: "3.2", signed: false)
        XCTAssertEqual(SmartInstaller.existing(new, in: apps), .older(installed: "3.2"))
        try fm.removeItem(at: apps.appendingPathComponent("Figma.app"))
        try app(apps, version: "3.4", signed: false)
        XCTAssertEqual(SmartInstaller.existing(new, in: apps), .current(installed: "3.4"))
    }

    func testHomebrewCacheIsIgnored() {
        let brew = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/Homebrew/downloads/abc--Figma.dmg")
        XCTAssertTrue(SmartInstaller.isHomebrewCache(brew))
        XCTAssertTrue(SmartInstaller.refuses(brew, roots: [], keepTagged: false))
        XCTAssertFalse(SmartInstaller.isHomebrewCache(root.appendingPathComponent("Figma.dmg")))
    }

    // MARK: Installing

    func testInstallCopiesVerifiesEjectsAndTrashesTheDownload() throws {
        let vol = tmp.appendingPathComponent("vol"), src = try app(vol), dmg = download()
        var ejected = false
        let r = engine.install(app: src, download: dmg, apps: apps, trashDownload: true) { ejected = true; return true }
        XCTAssertNil(r.failure)
        XCTAssertEqual(r.installed?.path, apps.appendingPathComponent("Figma.app").path)
        XCTAssertTrue(SmartInstaller.signatureValid(apps.appendingPathComponent("Figma.app")))
        XCTAssertTrue(fm.fileExists(atPath: src.path), "a disk image install copies; the volume keeps its app")
        XCTAssertTrue(ejected)
        XCTAssertFalse(fm.fileExists(atPath: dmg.path))
        let t = try XCTUnwrap(r.trashed)
        XCTAssertEqual(t.source, "Smart Installer")
        XCTAssertTrue(store.actions.contains { $0.id == t.id }, "journaled")
        engine.undo([t.id])
        XCTAssertTrue(fm.fileExists(atPath: dmg.path), "⌘Z puts the download back")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: apps.path), ["Figma.app"], "no temporary copy left behind")
    }

    func testSignatureStates() throws {
        XCTAssertEqual(SmartInstaller.signature(try app(tmp.appendingPathComponent("a"))), .valid)
        XCTAssertEqual(SmartInstaller.signature(try app(tmp.appendingPathComponent("b"), signed: false)), .unsigned)
        let broken = try app(tmp.appendingPathComponent("c"))
        try Data("#!/bin/sh\n".utf8).write(to: broken.appendingPathComponent("Contents/Resources-added.txt"))
        try Data("changed".utf8).write(to: broken.appendingPathComponent("Contents/MacOS/Figma"))
        XCTAssertEqual(SmartInstaller.signature(broken), .broken, "changed after signing")
    }

    func testUnsignedAppNeedsTheUsersConfirmation() throws {
        let src = try app(tmp.appendingPathComponent("vol"), signed: false), dmg = download()
        let r = engine.install(app: src, download: dmg, apps: apps, trashDownload: true) { XCTFail("never ejects"); return true }
        XCTAssertNil(r.installed)
        XCTAssertEqual(r.failure, "Figma isn't signed, so Kanso didn't install it.")
        XCTAssertTrue(fm.fileExists(atPath: dmg.path), "nothing was installed, so the download stays")
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: apps.path).isEmpty)
    }

    func testConfirmedUnsignedInstallIsVerifiedFileByFile() throws {
        let src = try app(tmp.appendingPathComponent("vol"), signed: false), dmg = download()
        let r = engine.install(app: src, download: dmg, apps: apps, allowUnsigned: true, trashDownload: true) { true }
        XCTAssertNil(r.failure)
        XCTAssertTrue(r.unsigned)
        XCTAssertEqual(SmartInstaller.treeDigest(apps.appendingPathComponent("Figma.app")), SmartInstaller.treeDigest(src))
        XCTAssertEqual(r.trashed?.details["unsigned"], "1", "the journal says it was installed without a signature")
        if let t = r.trashed { engine.undo([t.id]) }
    }

    func testBrokenSignatureIsNeverInstalled() throws {
        let src = try app(tmp.appendingPathComponent("vol")), dmg = download()
        try Data("changed".utf8).write(to: src.appendingPathComponent("Contents/MacOS/Figma"))
        let r = engine.install(app: src, download: dmg, apps: apps, allowUnsigned: true, trashDownload: true) { XCTFail("never ejects"); return true }
        XCTAssertNil(r.installed)
        XCTAssertEqual(r.failure, "Figma was changed after it was signed, so Kanso didn't install it.")
        XCTAssertTrue(fm.fileExists(atPath: dmg.path))
    }

    func testTreeDigestNoticesAnyChange() throws {
        let a = try app(tmp.appendingPathComponent("a"), signed: false)
        let d = try XCTUnwrap(SmartInstaller.treeDigest(a))
        try Data("x".utf8).write(to: a.appendingPathComponent("Contents/extra"))
        XCTAssertNotEqual(SmartInstaller.treeDigest(a), d)
        XCTAssertEqual(SmartInstaller.checksum(download("x.dmg")), "6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d", "SHA-256 of the bytes \"image\"")
    }

    func testFailedEjectKeepsTheDownload() throws {
        let src = try app(tmp.appendingPathComponent("vol")), dmg = download()
        let r = engine.install(app: src, download: dmg, apps: apps, trashDownload: true) { false }
        XCTAssertNotNil(r.installed)
        XCTAssertEqual(r.failure, "Installed, but the disk image couldn't be ejected. The download was kept.")
        XCTAssertTrue(fm.fileExists(atPath: dmg.path))
        XCTAssertNil(r.trashed)
    }

    func testTrashTheDownloadUnticked() throws {
        let src = try app(tmp.appendingPathComponent("vol")), dmg = download()
        let r = engine.install(app: src, download: dmg, apps: apps, trashDownload: false) { true }
        XCTAssertNil(r.failure)
        XCTAssertTrue(fm.fileExists(atPath: dmg.path))
    }

    func testAlreadyInstalledNeedsReplace() throws {
        try app(apps, version: "3.2")
        let src = try app(tmp.appendingPathComponent("vol"), version: "3.4"), dmg = download()
        let skipped = engine.install(app: src, download: dmg, apps: apps, trashDownload: true) { XCTFail("never ejects"); return true }
        XCTAssertEqual(skipped.failure, "Figma is already installed. Nothing changed.")
        let r = engine.install(app: src, download: dmg, apps: apps, replace: true, trashDownload: true) { true }
        XCTAssertNil(r.failure)
        XCTAssertEqual(SmartInstaller.appInfo(apps.appendingPathComponent("Figma.app"))?.v.version, "3.4")
        let old = try XCTUnwrap(r.replaced)
        XCTAssertEqual(old.details["replaced"], "1")
        XCTAssertTrue(fm.fileExists(atPath: old.dst), "the old copy is in the Trash, not deleted")
        try? fm.removeItem(atPath: old.dst)
    }

    func testZipInstallMovesTheExtractedApp() throws {
        let src = try app(root), zip = download("Figma.zip")
        let r = engine.install(app: src, download: zip, apps: apps, move: true, trashDownload: true) { true }
        XCTAssertNil(r.failure)
        XCTAssertFalse(fm.fileExists(atPath: src.path), "the extracted copy moves, so nothing is left to sort")
        XCTAssertTrue(fm.fileExists(atPath: apps.appendingPathComponent("Figma.app").path))
        XCTAssertFalse(fm.fileExists(atPath: zip.path))
        if let t = r.trashed { engine.undo([t.id]) }
    }

    // MARK: Carriers

    func testExtractionMatchesTheArchiveListing() throws {
        let one = tmp.appendingPathComponent("src/report.pdf")
        try fm.createDirectory(at: one.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: one)
        let zip1 = root.appendingPathComponent("report.zip")
        XCTAssertNotNil(SmartInstaller.run("/usr/bin/ditto", ["-c", "-k", one.path, zip1.path]))
        XCTAssertEqual(Carriers.listing(zip1), ["report.pdf"])
        XCTAssertNil(Carriers.extraction(of: zip1), "not extracted yet")
        try Data("pdf".utf8).write(to: root.appendingPathComponent("report.pdf"))
        XCTAssertEqual(Carriers.extraction(of: zip1)?.sibling.lastPathComponent, "report.pdf")

        let many = tmp.appendingPathComponent("photos")
        try fm.createDirectory(at: many, withIntermediateDirectories: true)
        for n in ["a.jpg", "b.jpg"] { try Data().write(to: many.appendingPathComponent(n)) }
        let zip2 = root.appendingPathComponent("holiday.zip")
        XCTAssertNotNil(SmartInstaller.run("/usr/bin/ditto", ["-c", "-k", many.path, zip2.path]))
        XCTAssertEqual(Set(Carriers.listing(zip2) ?? []), ["a.jpg", "b.jpg"])
        let out = root.appendingPathComponent("holiday")
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        try Data().write(to: out.appendingPathComponent("a.jpg"))
        XCTAssertNil(Carriers.extraction(of: zip2), "b.jpg is missing: not the extraction")
        try Data().write(to: out.appendingPathComponent("b.jpg"))
        XCTAssertEqual(Carriers.extraction(of: zip2)?.found, ["a.jpg", "b.jpg"])
    }

    func testLastUsedDateAndOpenedTorrent() throws {
        let t = download("ubuntu.torrent")
        XCTAssertNil(Carriers.lastUsed(t))
        XCTAssertFalse(Carriers.torrentOpened(t))
        var spec: (Int64, Int64) = (Int64(Date().addingTimeInterval(60).timeIntervalSince1970), 500)
        let data = Data(bytes: &spec, count: 16)
        _ = data.withUnsafeBytes { setxattr(t.path, "com.apple.lastuseddate#PS", $0.baseAddress, 16, 0, 0) }
        XCTAssertNotNil(Carriers.lastUsed(t))
        XCTAssertTrue(Carriers.torrentOpened(t))
    }

    func testTrashCarrierIsJournaledAndRefusesManualShelvesAndKeep() throws {
        let zip = download("photos.zip")
        let a = try XCTUnwrap(engine.trashCarrier(zip, kind: "archive"))
        XCTAssertEqual(a.details["carrier"], "archive")
        XCTAssertTrue(ActivityFilter.installed.includes(a))
        XCTAssertFalse(ActivityFilter.duplicates.includes(a), "a carrier isn't a duplicate")
        engine.undo([a.id])
        XCTAssertTrue(fm.fileExists(atPath: zip.path))
        let manual = root.appendingPathComponent("Manual Shelves/old.zip")
        try fm.createDirectory(at: manual.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: manual)
        XCTAssertNil(engine.trashCarrier(manual, kind: "archive"))
        Tags.add(zip, ["Keep"])
        XCTAssertNil(engine.trashCarrier(zip, kind: "archive"))
    }

    func testSavedViewWithTheOldFilterNameStillWorks() throws {
        let v = try JSONDecoder().decode(SavedView.self, from: Data(#"{"name": "Installers", "filter": "Smart Eject"}"#.utf8))
        XCTAssertEqual(ActivityFilter(rawValue: v.filter), .installed)
    }
}
