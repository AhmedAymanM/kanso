import Foundation

// The Tray (v2 beta, files only): a place to carry files until the user decides. Holding is not sorting:
// a dropped file stays exactly where it is (nothing is moved, copied or read) until Organize.
// Design: docs/design/proposals/tray.md.

/// A reference to a file the user dropped: its path plus bookmark data, so a file that moves (even sorted by
/// Kanso itself meanwhile) is still found. Never the file's contents.
public struct TrayItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var path: String
    public var bookmark: Data?
    public var added = Date()
    public init(path: String, bookmark: Data?) { self.path = path; self.bookmark = bookmark }
}

public enum TrayState: Equatable, Sendable {
    case ready
    case missing                // gone or moved out of reach
    case manualShelves          // the user's own folder: Kanso leaves it there
    case keep                   // tagged Keep, or matched by an exclude
}

/// A tray item as the UI shows it.
public struct TrayEntry: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var url: URL
    public var state: TrayState
    public var locked: Bool         // a key or vault: moved by extension only, never sent to a model
    public var placeholder: Bool    // an iCloud placeholder: carried and moved by name, never read
    public var name: String { url.lastPathComponent }
    public var folder: String { url.deletingLastPathComponent().lastPathComponent }
}

/// What a drop did.
public struct TrayAdd: Sendable, Equatable {
    public var added = 0
    public var already = 0
    public var refused: [String] = []   // user-facing reasons, one per refused item
    public var overflow = 0             // past the cap
    public init() {}
}

/// `tray.json`: references only, mode 0600, excluded from backup. Atomic writes; survives a relaunch.
public final class TrayStore: @unchecked Sendable {
    public static let cap = 100
    private let lock = NSLock()
    private let url: URL
    private var list: [TrayItem]

    public init(dir: URL) {
        url = dir.appendingPathComponent("tray.json")
        list = (try? Data(contentsOf: url)).flatMap { try? Store.decoder.decode([TrayItem].self, from: $0) } ?? []
    }

    public var items: [TrayItem] { lock.lock(); defer { lock.unlock() }; return list }
    public var count: Int { items.count }

    /// Add files by reference. Only existing files and folders (not links, not file promises) are carried; the first
    /// `cap` are kept and the rest counted.
    @discardableResult
    public func add(_ urls: [URL]) -> TrayAdd {
        var r = TrayAdd()
        lock.lock()
        for u in urls {
            guard u.isFileURL else { r.refused.append("The Tray holds files for now."); continue }
            let f = URL(fileURLWithPath: u.path)   // no file-reference or percent-encoded forms
            guard Stat.exists(f) else { r.refused.append("\(f.lastPathComponent) isn't a file on this Mac yet. Save it first."); continue }
            guard !Stat.isSymlink(f) else { r.refused.append("\(f.lastPathComponent) is a link, not a file."); continue }
            if list.contains(where: { $0.path == f.path }) { r.already += 1; continue }
            if list.count >= TrayStore.cap { r.overflow += 1; continue }
            list.append(TrayItem(path: f.path, bookmark: try? f.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)))
            r.added += 1
        }
        lock.unlock()
        if r.added > 0 { save() }
        return r
    }

    /// Forget references. The files are never touched.
    @discardableResult
    public func remove(_ ids: Set<UUID>) -> [TrayItem] {
        lock.lock()
        let gone = list.filter { ids.contains($0.id) }
        list.removeAll { ids.contains($0.id) }
        lock.unlock()
        if !gone.isEmpty { save() }
        return gone
    }

    public func clear() { remove(Set(items.map(\.id))) }

    /// Put forgotten rows back (⌘Z after a forget), at their old positions where possible.
    public func restore(_ back: [TrayItem]) {
        lock.lock()
        for item in back where !list.contains(where: { $0.id == item.id || $0.path == item.path }) { list.append(item) }
        lock.unlock()
        save()
    }

    public func move(_ id: UUID, by delta: Int) {
        lock.lock()
        if let i = list.firstIndex(where: { $0.id == id }) {
            let j = min(max(i + delta, 0), list.count - 1)
            if j != i { list.insert(list.remove(at: i), at: j) }
        }
        lock.unlock()
        save()
    }

    /// Where the item is now: the bookmark follows a file that was moved or renamed. nil when it can't be found.
    func resolve(_ item: TrayItem) -> URL? {
        if Stat.exists(URL(fileURLWithPath: item.path)) { return URL(fileURLWithPath: item.path) }
        guard let data = item.bookmark else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
              Stat.exists(URL(fileURLWithPath: u.path)) else { return nil }
        let found = URL(fileURLWithPath: u.path)
        lock.lock()
        if let i = list.firstIndex(where: { $0.id == item.id }) {
            list[i].path = found.path
            if stale { list[i].bookmark = try? found.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        }
        lock.unlock()
        save()
        return found
    }

    private func save() {
        lock.lock(); let snapshot = list; lock.unlock()
        guard let data = try? Store.encoder.encode(snapshot) else { return }
        var u = url
        do {
            try data.write(to: u, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            try u.setResourceValues(v)
        } catch { NSLog("Kanso: tray write failed: \(error)") }
    }

    /// "Forget everything" wipes the file too.
    public func wipe() {
        lock.lock(); list = []; lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }
}

/// One tray row in a plan.
public struct TrayRow: Identifiable, Sendable {
    public var id: UUID
    public var entry: TrayEntry
    public var shelf: String?       // where it would go (nil when it stays)
    public var basis: String        // "by file type", "asks Apple Intelligence", ...
    public var newShelf = false
    public var stays: String?       // why it will not move
    public var planned: Planned?
    public var name: String { entry.name }
    public var moves: Bool { planned != nil }
}

public struct TrayPlan: Sendable {
    public var rows: [TrayRow] = []
    public var modelOff = false     // Apple Intelligence is off: unknown files go to Unsorted
    public var movable: Int { rows.filter(\.moves).count }
    public var newShelves: Int { Set(rows.filter { $0.newShelf }.compactMap(\.shelf)).count }
    public init() {}
}

public struct TrayResult: Sendable {
    public var moved: [Action] = []
    public var stayed: [(name: String, reason: String)] = []
    public var run: String? { moved.first?.run }
    public var shelves: Int { Set(moved.map(\.shelf)).count }
}

extension Engine {
    /// Tray items with their current location and state. Metadata only; nothing is read.
    public func trayEntries() -> [TrayEntry] {
        tray.items.map { item in
            guard let url = tray.resolve(item) else {
                return TrayEntry(id: item.id, url: URL(fileURLWithPath: item.path), state: .missing, locked: false, placeholder: false)
            }
            var state = TrayState.ready
            if Engine.inManualShelves(url) { state = .manualShelves }
            else if ignored(url) { state = .keep }
            let locked = s.type(forExt: url.pathExtension.lowercased())?.name == Shelf.keys
            return TrayEntry(id: item.id, url: url, state: state, locked: locked, placeholder: Placeholder.isPlaceholder(url))
        }
    }

    /// Any path component named Manual Shelves: the user's own, never touched.
    static func inManualShelves(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { fold($0) == fold(Library.manual) }
    }

    static func trayBasis(_ why: String) -> String {
        if why == "extension" { return "by file type" }
        if why == "screenshot" { return "screenshot flag" }
        if why.hasPrefix("rule") { return "by your rule" }
        if why.hasPrefix("apple-intelligence") && !why.hasSuffix("failed") && !why.hasSuffix("unsure") { return "asked Apple Intelligence" }
        if why == "unknown type" { return "unknown type" }
        return "no clear type"
    }

    /// The plan Organize would carry out: the same `decide` as a normal sort (rules, screenshot flag, extension table,
    /// then Apple Intelligence on the name for unknown extensions), nothing read, nothing moved.
    public func trayPlan(progress: (@Sendable (Int, Int) -> Void)? = nil) async -> TrayPlan {
        var plan = TrayPlan()
        plan.modelOff = s.unknownFiles == .askModel && (s.modelChoice == .rulesOnly || !classifier.availability.ready)
        let manuals = s.activeRoots.map { $0.appendingPathComponent(Library.manual).standardizedFileURL }
        let entries = trayEntries()
        for (i, e) in entries.enumerated() {
            if Task.isCancelled { break }
            progress?(i + 1, entries.count)
            var row = TrayRow(id: e.id, entry: e, basis: "")
            switch e.state {
            case .missing: row.stays = "Missing. Forget it to clear the row."; plan.rows.append(row); continue
            case .manualShelves: row.stays = "In Manual Shelves, Kanso leaves it there."; plan.rows.append(row); continue
            case .keep: row.stays = "Tagged \(s.keepTag) or excluded, Kanso leaves it there."; plan.rows.append(row); continue
            case .ready: break
            }
            guard let root = rootFor(e.url) ?? s.activeRoots.first else {
                row.stays = "No watched folder to file it in."; plan.rows.append(row); continue
            }
            let item = Item.inspect(e.url, root: root)
            let d = await decide(item)
            let dest = resolve(root, d.dest, userPath: d.userPath).standardizedFileURL
            row.basis = Engine.trayBasis(d.why) + (e.locked ? ", never read" : "")
            if manuals.contains(where: { Engine.contained(dest, in: $0) || dest == $0 }) {
                row.stays = "That would be Manual Shelves, which Kanso never touches."; plan.rows.append(row); continue
            }
            row.shelf = d.dest
            row.newShelf = d.learning != nil && !s.types.contains { $0.name == d.dest }
            if dest == e.url.deletingLastPathComponent().standardizedFileURL {
                row.stays = "Already on its shelf."; row.shelf = nil; plan.rows.append(row); continue
            }
            var m = Planned(item: item, dest: dest, shelf: d.dest, tags: d.tags, why: d.why, source: d.source)
            m.learning = d.learning
            if s.recents == .links { m.link = root.appendingPathComponent(Library.recents) }
            if let w = item.whereFrom.first { m.details["from"] = w }
            row.planned = m
            plan.rows.append(row)
        }
        return plan
    }

    /// Organize: the planned moves as ONE journaled run (one undo). Moved rows leave the Tray; the rest stay with a reason.
    /// `only` limits it to chosen rows; `shelves` overrides a row's shelf ("Change a shelf…").
    @discardableResult
    public func trayOrganize(_ plan: TrayPlan, only: Set<UUID>? = nil, shelves: [UUID: String] = [:]) -> TrayResult {
        var moves: [Planned] = []
        var byPath: [String: TrayRow] = [:]
        for row in plan.rows {
            guard var m = row.planned, only?.contains(row.id) ?? true else { continue }
            if let pick = shelves[row.id], s.types.contains(where: { $0.name == pick }), Engine.automaticShelfAllowed(pick) {
                m.dest = resolve(m.item.root, pick); m.shelf = pick; m.why = "chosen in the Tray"; m.source = "you chose it"; m.learning = nil
            }
            // The file may have moved on since the plan was made: always act on where it is now.
            guard let now = tray.items.first(where: { $0.id == row.id }).flatMap({ tray.resolve($0) }) else { continue }
            if now.path != m.item.url.path { m.item = Item.inspect(now, root: m.item.root) }
            moves.append(m)
            byPath[m.item.url.path] = row
        }
        var result = TrayResult()
        result.moved = apply(moves, trigger: "tray")
        let movedSrc = Set(result.moved.map(\.src))
        var done = Set<UUID>()
        for (path, row) in byPath {
            if movedSrc.contains(path) { done.insert(row.id) }
            else if !Stat.exists(URL(fileURLWithPath: path)) { done.insert(row.id) }   // it left on its own
            else { result.stayed.append((row.name, "Couldn't move it. It may be open in another app, or the shelf isn't writable.")) }
        }
        tray.remove(done)
        return result
    }
}
