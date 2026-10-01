import XCTest
@testable import KansoCore

struct FakeAI: Classifier {
    var pick: Pick?
    var available: Bool { true }
    func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? { pick }
}

final class EngineTests: XCTestCase {
    var tmp: URL!
    var root: URL!
    var store: Store!
    var engine: Engine!
    let fm = FileManager.default

    override func setUp() {
        tmp = fm.temporaryDirectory.appendingPathComponent("kanso-tests-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("Downloads")
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        make(pick: nil)
    }

    override func tearDown() { try? fm.removeItem(at: tmp) }

    func make(pick: Pick?, _ change: (inout Settings) -> Void = { _ in }) {
        store = Store(dir: tmp.appendingPathComponent("state"))
        store.update {
            $0.roots = [self.root.path]; $0.since = .distantPast; $0.settleSeconds = 0; $0.folderIcons = false
            $0.renaming = false; $0.duplicates = false; change(&$0)
        }
        engine = Engine(store: store, classifier: FakeAI(pick: pick))
        engine.setIcon = { _, _ in }
    }

    @discardableResult
    func file(_ name: String, _ body: String = "x", in dir: URL? = nil) -> URL {
        let u = (dir ?? root).appendingPathComponent(name)
        try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! body.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func shelf(_ s: String) -> URL { root.appendingPathComponent(Library.mine).appendingPathComponent(s) }
    func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }

    func run(all: Bool = false, trigger: String = "auto") async -> [Action] {
        return engine.apply(await engine.plan(all: all, trigger: trigger).moves, trigger: trigger)
    }

    func testSortsByExtensionAndLeavesLinkInRecents() async {
        file("report.pdf"); file("photo.JPG"); file("tool.dmg")
        let done = await run()
        XCTAssertEqual(done.count, 3)
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("report.pdf")))
        XCTAssertTrue(exists(shelf("Images").appendingPathComponent("photo.JPG")))
        XCTAssertTrue(exists(shelf("Apps").appendingPathComponent("tool.dmg")))
        XCTAssertTrue(Stat.isSymlink(root.appendingPathComponent("Recents/report.pdf")))
        XCTAssertTrue(exists(root.appendingPathComponent(Library.manual)))
        XCTAssertEqual(done.first?.source, "metadata only")
    }

    func testSkipsHiddenPartialKeepTaggedAndManagedFolders() async {
        file(".DS_Store"); file("big.zip.crdownload"); file("~$lock.docx")
        let kept = file("keep.pdf")
        Tags.add(kept, ["Keep"])
        file("inside.pdf", in: root.appendingPathComponent(Library.manual))
        let plan = await engine.plan()
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.waiting.map(\.url.lastPathComponent), ["big.zip.crdownload"])
        XCTAssertEqual(plan.waiting.first?.shelf, "Archives")
    }

    func testIgnoresItemsFromBeforeSetupUnlessAll() async {
        make(pick: nil) { $0.since = Date().addingTimeInterval(3600) }
        file("old.pdf")
        let plan = await engine.plan()
        XCTAssertTrue(plan.moves.isEmpty)
        let all = await engine.plan(all: true)
        XCTAssertEqual(all.moves.count, 1)
    }

    func testFoldersStayUnlessSortFoldersAndGitNeverMoves() async {
        try! fm.createDirectory(at: root.appendingPathComponent("project/.git"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: root.appendingPathComponent("stuff"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: root.appendingPathComponent("Some.app"), withIntermediateDirectories: true)
        let plan = await engine.plan()
        XCTAssertEqual(plan.moves.map(\.item.name), ["Some.app"])
    }

    func testRulesWinOverTypes() async {
        let u = file("scenario.json")
        Xattr.setPlist(u, "com.apple.metadata:kMDItemWhereFroms", ["https://eu1.make.com/export"])
        file("my-blueprint.json"); file("data.json")
        make(pick: nil) { $0.rules.append(Rule([Condition(.size, "1 GB")], dest: "Videos")) }
        _ = await run()
        XCTAssertTrue(exists(shelf("Automations").appendingPathComponent("scenario.json")))
        XCTAssertTrue(exists(shelf("Automations").appendingPathComponent("my-blueprint.json")))
        XCTAssertTrue(exists(shelf("JSON").appendingPathComponent("data.json")))
    }

    func testScreenshotFlagBeatsExtension() async {
        let u = file("Screenshot 2026-09-25 at 09.38.png")
        Xattr.setPlist(u, "com.apple.metadata:kMDItemIsScreenCapture", true)
        _ = await run()
        XCTAssertTrue(exists(shelf("Screenshots").appendingPathComponent(u.lastPathComponent)))
    }

    func testUndoRestoresAndAddsKeepTag() async {
        let u = file("report.pdf")
        _ = await run()
        XCTAssertFalse(exists(u))
        let restored = engine.undoLast()
        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(exists(u))
        XCTAssertTrue(Tags.read(u).contains("Keep"))
        XCTAssertFalse(Stat.isSymlink(root.appendingPathComponent("Recents/report.pdf")))
        XCTAssertTrue(store.actions.allSatisfy(\.undone))
        let again = await engine.plan()
        XCTAssertTrue(again.moves.isEmpty, "a restored file stays put")
        XCTAssertTrue(engine.undoLast().isEmpty)
    }

    func testJournalSurvivesReload() async {
        file("a.pdf")
        _ = await run()
        let reloaded = Store(dir: tmp.appendingPathComponent("state"))
        XCTAssertEqual(reloaded.actions.count, 1)
        XCTAssertEqual(reloaded.settings.roots, [root.path])
    }

    func testHoldModeParksNewFilesInRecentsFirst() async {
        make(pick: nil) { $0.recents = .hold }
        file("new.pdf")
        _ = await run()
        XCTAssertTrue(exists(root.appendingPathComponent("Recents/new.pdf")))
        make(pick: nil) { $0.recents = .hold; $0.recentDays = 0 }
        _ = await run()
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("new.pdf")))
    }

    func testCleanRecentsDropsBrokenLinks() async {
        file("a.pdf")
        _ = await run()
        try! fm.removeItem(at: shelf("Documents").appendingPathComponent("a.pdf"))
        engine.cleanRecents()
        XCTAssertFalse(Stat.isSymlink(root.appendingPathComponent("Recents/a.pdf")))
    }

    func testUnknownTypeCreatesLearnedType() async {
        make(pick: Pick(folder: Brain.new, name: "Subtitles", emoji: "💬", description: "Subtitle tracks"))
        file("movie.srt")
        let done = await run()
        XCTAssertEqual(done.first?.shelf, "Subtitles")
        XCTAssertTrue(exists(shelf("Subtitles").appendingPathComponent("movie.srt")))
        let t = store.settings.type(forExt: "srt")
        XCTAssertEqual(t?.name, "Subtitles"); XCTAssertEqual(t?.emoji, "💬"); XCTAssertEqual(t?.learned, true)
        XCTAssertEqual(store.settings.types.last?.name, Shelf.unsorted, "Unsorted stays last")
    }

    func testCatchAllAndUnsureGoToUnsorted() async {
        make(pick: Pick(folder: Brain.new, name: "Unknown Files", emoji: "❔"))
        file("x.qqq")
        _ = await run()
        XCTAssertTrue(exists(shelf("Unsorted").appendingPathComponent("x.qqq")))
        XCTAssertNil(store.settings.type(forExt: "qqq"))
        make(pick: Pick(folder: Brain.new, name: "QQQ Files", emoji: "📁"))
        file("z.qqq")
        _ = await run()
        XCTAssertTrue(exists(shelf("Unsorted").appendingPathComponent("z.qqq")), "a type named after the extension is not a type")
        make(pick: Pick(folder: Brain.unsure))
        file("y.zzz")
        _ = await run()
        XCTAssertTrue(exists(shelf("Unsorted").appendingPathComponent("y.zzz")))
    }

    func testModelPickOfExistingTypeIsRemembered() async {
        make(pick: Pick(folder: "Documents"))
        file("notes.wpd")
        _ = await run()
        XCTAssertEqual(store.settings.type(forExt: "wpd")?.name, "Documents")
    }

    func testDuplicatesGoToDuplicatesShelfAndCanBeTrashedOrKept() async {
        make(pick: nil) { $0.duplicates = true }
        file("invoice.pdf", "same bytes", in: shelf("Documents"))
        file("invoice (1).pdf", "same bytes")
        file("other.pdf", "different")
        let done = await run()
        let dup = done.first { $0.kind == .duplicate }!
        XCTAssertTrue(dup.pending)
        XCTAssertEqual(dup.source, "size + hash")
        XCTAssertTrue(exists(shelf("Duplicates").appendingPathComponent("invoice (1).pdf")))
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("other.pdf")))
        XCTAssertEqual(engine.duplicatesSize(), 10)

        let kept = engine.keepBoth(dup.id)
        XCTAssertNotNil(kept)
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("invoice (1).pdf")))
        XCTAssertFalse(store.actions.first { $0.id == dup.id }!.pending)
    }

    func testTwoLooseCopiesKeepTheOldest() async {
        make(pick: nil) { $0.duplicates = true }
        file("a.pdf", "same")
        Thread.sleep(forTimeInterval: 1.1)
        file("a copy.pdf", "same")
        let done = await run()
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("a.pdf")))
        XCTAssertTrue(exists(shelf("Duplicates").appendingPathComponent("a copy.pdf")))
        let dup = done.first { $0.kind == .duplicate }!
        XCTAssertEqual(dup.details["kept"], shelf("Documents").appendingPathComponent("a.pdf").path)
    }

    func testTrashAndPutBack() async {
        make(pick: nil) { $0.duplicates = true }
        file("song.mp3", "same", in: shelf("Audio"))
        file("song 2.mp3", "same")
        let dup = await run().first { $0.kind == .duplicate }!
        let tr = engine.trash(dup.id)
        XCTAssertNotNil(tr)
        XCTAssertFalse(exists(shelf("Duplicates").appendingPathComponent("song 2.mp3")))
        engine.undo([tr!.id])
        XCTAssertTrue(exists(shelf("Duplicates").appendingPathComponent("song 2.mp3")))
        XCTAssertTrue(store.actions.first { $0.id == dup.id }!.pending, "put back makes it pending again")
        XCTAssertEqual(engine.trashAllDuplicates(), 1)
        XCTAssertTrue(engine.duplicateFiles().isEmpty)
    }

    func testMeaninglessNames() {
        for n in ["Scan_0012", "IMG_1615", "download (3)", "document", "untitled", "Untitled 2", "3f9a1c2e-7b", "20260925", "DSC01234", "PXL_20260101_120000"] {
            XCTAssertTrue(Meaningless.check(n), n)
        }
        for n in ["Invoice-Vattenfall-2026-03", "report-final", "Screenshot 2026-09-25 at 09.38", "Lecture-07-slides", "cv"] {
            XCTAssertFalse(Meaningless.check(n), n)
        }
        XCTAssertTrue(Meaningless.check("Rechnung_123", extra: ["rechnung_*"]))
    }

    func testTemplateName() {
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 12
        let e = Extracted(kind: "Invoice", organization: "Vattenfall", date: Calendar.current.date(from: c), source: "contents, page 1")
        XCTAssertEqual(Renamer.name(e, ext: "pdf"), "Invoice-Vattenfall-2026-03.pdf")
        XCTAssertEqual(Renamer.name(e, ext: "pdf", separator: "_"), "Invoice_Vattenfall_2026-03.pdf")
        XCTAssertNil(Renamer.name(Extracted(kind: nil, organization: "X", date: nil, source: ""), ext: "pdf"))
        XCTAssertNil(Renamer.name(Extracted(kind: "Invoice", organization: nil, date: nil, source: ""), ext: "pdf"))
    }

    func testExtractFindsKindOrganizationDate() {
        let e = Reader.extract("INVOICE\nVattenfall AB\nInvoice date: 12 March 2026\nAmount due: 1 204 SEK", source: "contents, page 1")
        XCTAssertEqual(e.kind, "Invoice")
        XCTAssertNotNil(e.date)
        XCTAssertEqual(Reader.org(fromHost: "www.vattenfall.se"), "Vattenfall")
        XCTAssertNil(Reader.org(fromHost: "mail.google.com"))
    }

    let invoice = "INVOICE\nVattenfall AB\nInvoice date: 12 March 2026\nAmount due: 1 204 SEK\nThank you."

    func testRenamesMeaninglessNewDownloadAndUndoRestoresName() async {
        make(pick: nil) { $0.renaming = true }
        let u = file("Scan_0012.txt", invoice)
        Xattr.setPlist(u, "com.apple.metadata:kMDItemWhereFroms", ["https://www.vattenfall.se/invoice/123"])
        let done = await run()
        let a = done.first!
        XCTAssertEqual(a.kind, .renamed)
        XCTAssertEqual(a.oldName, "Scan_0012.txt")
        XCTAssertTrue(a.name.hasPrefix("Invoice-"), a.name)
        XCTAssertTrue(a.name.hasSuffix("-2026-03.txt"), a.name)
        XCTAssertEqual(a.source, "contents, page 1")
        XCTAssertEqual(Xattr.plist(URL(fileURLWithPath: a.dst), "app.kanso.original-name") as? String, "Scan_0012.txt")
        engine.undo([a.id])
        XCTAssertTrue(exists(u))
    }

    func testNameTemplateOrderAndMatchAnyRule() {
        let e = Extracted(kind: "Invoice", organization: "Vattenfall", date: Date(timeIntervalSince1970: 1_773_000_000), source: "")
        XCTAssertEqual(Renamer.name(e, ext: "pdf", parts: ["organization", "kind"]), "Vattenfall-Invoice.pdf")
        XCTAssertEqual(Renamer.name(e, ext: "pdf", parts: ["date", "kind"])?.hasSuffix("-Invoice.pdf"), true)
        var r = Rule([Condition(.ext, "dmg"), Condition(.ext, "pkg")], dest: "Apps")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("a.dmg"); try? Data("x".utf8).write(to: f)
        let item = Item.inspect(f, root: dir)
        XCTAssertFalse(Engine.matches(r, item))   // all: .dmg is not also .pkg
        r.matchAny = true
        XCTAssertTrue(Engine.matches(r, item))
    }

    func testHumanNamesAreNeverRenamed() async {
        make(pick: nil) { $0.renaming = true }
        file("my invoice.txt", invoice)
        let done = await run()
        XCTAssertEqual(done.first?.kind, .sorted)
        XCTAssertEqual(done.first?.name, "my invoice.txt")
    }

    func testMassRenamesWaitForReview() async {
        make(pick: nil) { $0.renaming = true; $0.massRenameThreshold = 2 }
        for i in 1...3 { file("Scan_00\(i).txt", invoice) }
        let done = await run()
        XCTAssertTrue(done.allSatisfy { $0.kind == .sorted })
        XCTAssertEqual(store.pending.renames.count, 3)
        let renamed = engine.applyRenames(Array(store.pending.renames.prefix(2)))
        XCTAssertEqual(renamed.count, 2)
        XCTAssertEqual(store.pending.renames.count, 1)
        XCTAssertEqual(Set(renamed.map(\.run)).count, 1, "one review, one undo")
        XCTAssertEqual(engine.undoLast().count, 2)
    }

    func testSortEverythingNeverRenamesDirectly() async {
        make(pick: nil) { $0.renaming = true }
        file("Scan_0001.txt", invoice)
        let done = await run(all: true, trigger: "sort-everything")
        XCTAssertEqual(done.first?.name, "Scan_0001.txt")
        XCTAssertEqual(store.pending.renames.count, 1)
    }

    func testTaggingAddsKindTagAndUndoRemovesIt() async {
        make(pick: nil) { $0.tagging = true; $0.tagOrganization = false }
        let u = file("power bill.txt", invoice)
        let a = await run().first!
        XCTAssertEqual(a.tags, ["Invoice"])
        XCTAssertEqual(Tags.read(URL(fileURLWithPath: a.dst)), ["Invoice"])
        engine.undo([a.id])
        XCTAssertEqual(Tags.read(u), ["Keep"])
    }

    func testCorrectionsBecomeRuleSuggestion() async {
        for i in 1...3 {
            let u = file("Lecture_0\(i).pdf")
            Xattr.setPlist(u, "com.apple.metadata:kMDItemWhereFroms", ["https://canvas.kth.se/files/\(i)"])
        }
        _ = await run()
        try! fm.createDirectory(at: shelf("Uni"), withIntermediateDirectories: true)
        for i in 1...3 { try! fm.moveItem(at: shelf("Documents").appendingPathComponent("Lecture_0\(i).pdf"), to: shelf("Uni").appendingPathComponent("Lecture_0\(i).pdf")) }
        engine.detectCorrections()
        let sug = store.pending.suggestions
        XCTAssertTrue(sug.contains { $0.condition == Condition(.from, "canvas.kth.se") && $0.shelf == "Uni" }, "\(sug)")
        engine.acceptSuggestion(sug.first { $0.condition.field == .from }!.id)
        XCTAssertEqual(store.settings.rules.first?.dest, "Uni")
        let u = file("Lecture_04.pdf")
        Xattr.setPlist(u, "com.apple.metadata:kMDItemWhereFroms", ["https://canvas.kth.se/files/4"])
        _ = await run()
        XCTAssertTrue(exists(shelf("Uni").appendingPathComponent("Lecture_04.pdf")))
    }

    func testStats() async {
        make(pick: nil) { $0.duplicates = true }
        file("a.pdf", "same", in: shelf("Documents"))
        file("b.pdf", "same"); file("c.png")
        _ = await run()
        let t = Stats.today(store.actions)
        XCTAssertEqual(t.sorted, 1); XCTAssertEqual(t.duplicates, 1); XCTAssertEqual(t.duplicateBytes, 4)
        engine.undoLast()
        XCTAssertEqual(Stats.today(store.actions).undone, 2)
        let ins = Insights.compute(store.actions, settings: store.settings)
        XCTAssertEqual(ins.month.total, 2)
    }

    func testExtractCompanyLinesCapsAndMonthYear() {
        let e = Reader.extract("Acme Corporation\nPayslip\nPay period: September 2026\nNet pay: 32 100 SEK", source: "")
        XCTAssertEqual(e.kind, "Payslip"); XCTAssertEqual(e.organization, "Acme")
        XCTAssertEqual(e.date.map { Calendar.current.component(.month, from: $0) }, 9)
        XCTAssertEqual(Reader.extract("VATTENFALL AB\nINVOICE\n12 March 2026", source: "").organization, "Vattenfall")
        XCTAssertEqual(Reader.extract("Hemnet AB\nLease agreement", source: "").organization, "Hemnet")
        XCTAssertEqual(Reader.clean("SJ"), "SJ")
    }

    func testNoEmptyFoldersUntilFirstSort() async {
        _ = await run()
        XCTAssertFalse(exists(root.appendingPathComponent(Library.mine)), "nothing to sort, nothing created")
        XCTAssertFalse(exists(root.appendingPathComponent(Library.manual)))
        make(pick: nil) { $0.recents = .off }
        file("a.pdf")
        _ = await run()
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("a.pdf")))
        XCTAssertTrue(exists(root.appendingPathComponent(Library.manual)), "Manual Shelves arrives with the first sort")
        XCTAssertFalse(exists(root.appendingPathComponent(Library.recents)), "no links, no Recents")
        XCTAssertFalse(exists(shelf("Images")), "no shelf before its first file")
    }

    func testEmptiedShelvesStay() async {
        let u = file("a.pdf")
        _ = await run()
        engine.undoLast()
        XCTAssertTrue(exists(u))
        XCTAssertTrue(exists(shelf("Documents")), "a shelf, once created, stays")
    }

    func testDuplicatesStraightToTrashWhenChosen() async {
        make(pick: nil) { $0.duplicates = true; $0.duplicatesToTrash = true }
        file("song.mp3", "same", in: shelf("Audio"))
        let copy = file("song 2.mp3", "same")
        let a = await run().first { $0.kind == .duplicate }!
        XCTAssertTrue(a.dst.contains("/.Trash/"), a.dst)
        XCTAssertFalse(exists(shelf("Duplicates")), "no Duplicates shelf when copies go to the Trash")
        engine.undo([a.id])
        XCTAssertTrue(exists(copy))
    }

    func testHeldDuplicatesExpireOnlyWhenOptedInAndUntouched() async {
        make(pick: nil) { $0.duplicates = true }
        file("x.pdf", "same", in: shelf("Documents"))
        file("x (1).pdf", "same")
        let dup = await run().first { $0.kind == .duplicate }!
        let held = URL(fileURLWithPath: dup.dst)
        let later = Date().addingTimeInterval(40 * 86400)
        XCTAssertTrue(engine.expireDuplicates(now: later).isEmpty, "off by default")
        store.update { $0.autoTrashDuplicates = true }
        var v = URLResourceValues(); v.contentAccessDate = Date().addingTimeInterval(35 * 86400)
        var h = held; try? h.setResourceValues(v)
        XCTAssertTrue(engine.expireDuplicates(now: later).isEmpty, "opened 5 days ago: timer reset")
        let expired = engine.expireDuplicates(now: later.addingTimeInterval(30 * 86400))
        XCTAssertEqual(expired.count, 1)
        XCTAssertFalse(exists(held))
    }

    func testCorrectionsTeachLearnedTypesButNotBuiltIns() async {
        make(pick: Pick(folder: "Documents"))
        file("ep.srt"); file("lecture.pdf")
        _ = await run()
        XCTAssertEqual(store.settings.type(forExt: "srt")?.name, "Documents")
        let srt = store.actions.first { $0.name == "ep.srt" }!, pdf = store.actions.first { $0.name == "lecture.pdf" }!
        engine.move(srt.id, to: "Subtitles")
        engine.move(pdf.id, to: "Uni")
        XCTAssertEqual(store.settings.type(forExt: "srt")?.name, "Subtitles", "a learned type follows the move")
        XCTAssertEqual(store.settings.type(forExt: "pdf")?.name, "Documents", "built-in types never move")
    }

    func testSmartEjectFindsInstalledAppsAndTrashesInstaller() throws {
        func app(_ dir: URL, _ name: String, _ id: String) {
            let c = dir.appendingPathComponent("\(name).app/Contents")
            try! fm.createDirectory(at: c, withIntermediateDirectories: true)
            NSDictionary(dictionary: ["CFBundleIdentifier": id]).write(to: c.appendingPathComponent("Info.plist"), atomically: true)
        }
        let vol = tmp.appendingPathComponent("Volumes/Figma"), apps = tmp.appendingPathComponent("Applications")
        app(vol, "Figma", "com.figma.Desktop")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        let onVolume = SmartEject.apps(onVolume: vol)
        XCTAssertEqual(onVolume, ["com.figma.Desktop": "Figma"])
        XCTAssertTrue(SmartEject.installed(Set(onVolume.keys), in: apps).isEmpty, "not installed yet: never trash")
        app(apps, "Figma", "com.figma.Desktop")
        XCTAssertEqual(SmartEject.installed(Set(onVolume.keys), in: apps), ["com.figma.Desktop"])
        let dmg = file("Figma.dmg", "image")
        let a = try XCTUnwrap(engine.trashInstaller(dmg, app: "Figma"))
        XCTAssertFalse(exists(dmg))
        XCTAssertEqual(a.details["installer"], "Figma")
        engine.undo([a.id])
        XCTAssertTrue(exists(dmg), "Put Back restores the installer")
    }

    func testDefaultRulesAreMarkedBuiltIn() throws {
        XCTAssertTrue(Rule.defaults.allSatisfy(\.builtIn))
        let old = #"{"conditions":[{"field":"from","value":"n8n"},{"field":"ext","value":"json"}],"dest":"Automations"}"#
        XCTAssertTrue(try JSONDecoder().decode(Rule.self, from: Data(old.utf8)).builtIn, "older settings files are migrated")
    }

    func testRenameFileIsJournaledAndUndoRestores() async {
        make(pick: nil)
        let u = file("report.txt")
        let a = await run().first!
        let r = engine.renameFile(a.id, to: "Q3 report.txt")
        XCTAssertEqual(r?.kind, .renamed)
        XCTAssertEqual(r?.oldName, "report.txt")
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("Q3 report.txt")))
        XCTAssertNil(engine.renameFile(a.id, to: "../evil.txt"), "no path separators")
        engine.undo([r!.id])
        XCTAssertTrue(exists(shelf("Documents").appendingPathComponent("report.txt")) || exists(u))
        XCTAssertFalse(exists(shelf("Documents").appendingPathComponent("Q3 report.txt")))
    }

    func testTagCountsSkipKeepTag() async {
        make(pick: nil)
        let u = file("a.txt"); Tags.add(u, ["Utilities", "Keep"])
        XCTAssertEqual(engine.tagCounts()["Utilities"], 1)
        XCTAssertNil(engine.tagCounts()["Keep"])
    }

    func testSizeParsing() {
        XCTAssertEqual(Engine.parseSize("2 GB"), 2_000_000_000)
        XCTAssertEqual(Engine.parseSize("500mb"), 500_000_000)
        XCTAssertNil(Engine.parseSize("big"))
    }

    /// Settings written before the Smart Eject options existed still load, with the old behaviour.
    func testOldSettingsGetSmartEjectDefaults() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"smartEject": true, "tagging": true}"#.utf8))
        XCTAssertTrue(old.smartEjectNotice)
        XCTAssertFalse(old.smartEjectOnlyEject)
        XCTAssertTrue(old.tagging)
        let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(round.smartEjectNotice, true)
    }
}
