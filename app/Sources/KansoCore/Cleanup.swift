import Foundation

/// Cleanup (PRODUCT.md §7, ADR 0002 2026-11-20 amendment). Downloads is an inbox with two exits: carriers the user is done
/// with go to the Trash on a timer the user turned on; content that shows it's kept is suggested for Documents.
/// Only carriers are ever on a timer. Kanso never deletes and never empties the Trash.
public enum Carrier: String, CaseIterable, Codable, Sendable {
    case installer, archive, screenshot, torrent

    static let installers: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
    static let archives: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]

    /// What a sorted file is, by the screenshot flag or its extension; nil for content (never on a timer).
    public static func of(_ a: Action) -> Carrier? {
        if a.why == "screenshot" { return .screenshot }
        let ext = (a.dst as NSString).pathExtension.lowercased()
        if installers.contains(ext) { return .installer }
        if archives.contains(ext) { return .archive }
        return ext == "torrent" ? .torrent : nil
    }

    public var plural: String {
        switch self {
        case .installer: return "installers"
        case .archive: return "archives"
        case .screenshot: return "screenshots"
        case .torrent: return "torrents"
        }
    }
}

/// A carrier on its timer: where it is, when it leaves, and why.
public struct CleanupItem: Identifiable, Equatable, Sendable {
    public var id: UUID           // the sort action that put it on its shelf
    public var url: URL
    public var carrier: Carrier
    public var size: Int64
    public var due: Date
    public var why: String        // "14 days unused", "extracted 3 days ago"
    public init(id: UUID, url: URL, carrier: Carrier, size: Int64, due: Date, why: String) {
        self.id = id; self.url = url; self.carrier = carrier; self.size = size; self.due = due; self.why = why
    }
}

extension Engine {
    /// Days per carrier (settings, with the PRODUCT.md defaults). `extracted` is the archive timer once its contents are
    /// next to it.
    public func cleanupDays(_ key: String) -> Int { max(1, s.cleanupDays[key] ?? Settings.defaultCleanupDays[key] ?? 30) }

    /// "Unused" is measured from the latest of: when Kanso sorted it, the last open (`com.apple.lastuseddate#PS`) and the
    /// modification date. Never the access time, which Kanso's own reads move and real opens often don't.
    public func unusedSince(_ url: URL, sorted: Date) -> Date {
        let mtime = Stat.mtime(url).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        return max(sorted, Carriers.lastUsed(url) ?? .distantPast, mtime)
    }

    /// Opens Kanso has seen, counted from changes of the last-used date (kept in Kanso's own xattr on the file).
    /// Two or more is a sign the file is kept.
    @discardableResult
    public func countOpens(_ url: URL) -> Int {
        guard let used = Carriers.lastUsed(url) else { return 0 }
        let key = "com.kanso.opens"
        var seen = (Xattr.plist(url, key) as? [String: Any]) ?? [:]
        var count = seen["count"] as? Int ?? 0
        let last = seen["last"] as? Double ?? 0
        if used.timeIntervalSince1970 > last + 1 {
            count += 1
            seen = ["count": count, "last": used.timeIntervalSince1970]
            Xattr.setPlist(url, key, seen)
        }
        return count
    }

    /// Signs a file is kept, which take it off every timer: any Finder tag (Keep included) or opening it twice.
    /// (A rename by the user or a move out of the shelf already takes it off: the file is no longer where Kanso put it.)
    public func keptSign(_ url: URL) -> String? {
        if !Tags.read(url).isEmpty { return "tagged" }
        if countOpens(url) >= 2 { return "opened twice" }
        return nil
    }

    /// Every carrier on a timer, due or not: files Kanso sorted that are still exactly where it put them, in Downloads
    /// (screenshots from any watched folder), never in Manual Shelves or Keys, with no sign they're kept.
    public func cleanupItems() -> [CleanupItem] {
        var out: [CleanupItem] = []
        var seen = Set<String>()
        for a in store.actions.reversed() where a.kind == .sorted && !a.undone && !seen.contains(a.dst) {
            seen.insert(a.dst)
            guard let c = Carrier.of(a), fm.fileExists(atPath: a.dst) else { continue }
            let url = URL(fileURLWithPath: a.dst)
            let inDownloads = URL(fileURLWithPath: a.root).lastPathComponent == "Downloads"
            guard inDownloads || c == .screenshot, a.shelf != "Keys", !url.pathComponents.contains(Library.manual),
                  !url.path.contains("/\(Library.mine)/\(Shelf.duplicates)/"), keptSign(url) == nil else { continue }
            let since = unusedSince(url, sorted: a.ts)
            var due = since.addingTimeInterval(TimeInterval(cleanupDays(c.rawValue)) * 86400)
            var why = "\(cleanupDays(c.rawValue)) days unused"
            if c == .archive, let x = Carriers.extraction(of: url) {
                let appeared = (try? x.sibling.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? since
                let early = appeared.addingTimeInterval(TimeInterval(cleanupDays("extracted")) * 86400)
                if early < due { due = early; why = "extracted \(cleanupDays("extracted")) days ago" }
            }
            out.append(CleanupItem(id: a.id, url: url, carrier: c, size: Stat.size(url), due: due, why: why))
        }
        return out.sorted { $0.due < $1.due }
    }

    /// Carriers whose timer has run out. Empty while Cleanup is off.
    public func cleanupDue(now: Date = Date()) -> [CleanupItem] {
        guard s.cleanup else { return [] }
        return cleanupItems().filter { $0.due <= now }
    }

    /// One cleanup is one journaled run (trigger "cleanup"): each file is checked again just before it moves, and
    /// anything that changed (moved, tagged, opened twice, no longer due) is skipped.
    public func runCleanup(_ items: [CleanupItem], now: Date = Date()) -> [Action] {
        guard s.cleanup else { return [] }
        let current = Dictionary(cleanupItems().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        var out: [Action] = []
        for i in items {
            guard let c = current[i.id], c.url == i.url, c.due <= now else { continue }
            var tr = Action(run: run, kind: .trashed, src: c.url.path, dst: "", root: rootFor(c.url)?.path ?? "", shelf: "Trash",
                            why: "\(c.carrier.rawValue) · \(c.why) (Cleanup, your setting)", source: "metadata only")
            tr.trigger = "cleanup"
            tr.details = ["size": String(c.size), "carrier": c.carrier.rawValue, "cleanup": "1"]
            guard let t = trashJournaled(c.url, &tr) else { continue }
            tr.dst = t.path
            store.append(tr)
            out.append(tr)
        }
        return out
    }

    /// "Keep all": tags each file Keep, which takes it off every timer.
    public func keepAll(_ items: [CleanupItem]) {
        for i in items where fm.fileExists(atPath: i.url.path) { Tags.add(i.url, [s.keepTag]) }
    }

    /// Content (never carriers) that Kanso sorted in Downloads, still where it put it, showing it's kept: candidates for
    /// "Move to Documents". Kanso only suggests; it never moves these on its own.
    public func documentsSuggestions(dismissed: Set<String> = []) -> [Action] {
        guard s.cleanup, s.suggestDocuments else { return [] }
        var seen = Set<String>()
        return store.actions.reversed().filter { a in
            guard a.kind == .sorted, !a.undone, seen.insert(a.dst).inserted, Carrier.of(a) == nil, a.shelf != "Keys",
                  URL(fileURLWithPath: a.root).lastPathComponent == "Downloads", !dismissed.contains("documents:" + a.dst),
                  fm.fileExists(atPath: a.dst) else { return false }
            let url = URL(fileURLWithPath: a.dst)
            return Tags.read(url).contains { $0 != s.keepTag } || countOpens(url) >= 2
        }
    }

    /// Moves a sorted file to `<Documents>/My Shelves/<its shelf>`, journaled as a sort the user chose (⌘Z moves it back).
    public func moveToDocuments(_ id: UUID, documents: URL? = nil) -> Action? {
        guard let a = store.actions.first(where: { $0.id == id }), fm.fileExists(atPath: a.dst) else { return nil }
        let docs = documents ?? s.activeRoots.first { $0.lastPathComponent == "Documents" } ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let dest = resolve(docs, a.shelf)
        guard dest.path.hasPrefix(docs.appendingPathComponent(Library.mine).path + "/") else { return nil }
        makeDir(dest)
        let dst = Engine.unique(dest.appendingPathComponent(a.name))
        guard (try? fm.moveItem(atPath: a.dst, toPath: dst.path)) != nil else { return nil }
        var m = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .sorted, src: a.dst, dst: dst.path, root: docs.path,
                       shelf: a.shelf, why: "moved to Documents by you", source: "you")
        m.trigger = "suggestion"
        if Stat.isRegular(dst) { m.details["size"] = String(Stat.size(dst)) }
        store.append(m)
        return m
    }
}
