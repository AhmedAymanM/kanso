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
    public init(id: UUID = UUID(), url: URL, state: TrayState = .ready, locked: Bool = false, placeholder: Bool = false) {
        self.id = id; self.url = url; self.state = state; self.locked = locked; self.placeholder = placeholder
    }
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
    private let saveLock = NSLock()     // writes are serial: a stale snapshot can never land after a newer one
    private let url: URL
    private var list: [TrayItem]
    private var missing = Set<UUID>()   // known-missing: not re-resolved through their bookmark on every refresh
    private var dirty = false

    public init(dir: URL) {
        url = dir.appendingPathComponent("tray.json")
        list = TrayStore.load(url)
    }

    /// Element by element: one bad entry never loses the rest. An unreadable file is kept as tray.json.bad.
    static func load(_ url: URL) -> [TrayItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bad"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bad"))
            return []
        }
        var out: [TrayItem] = []
        for el in raw {
            guard let d = try? JSONSerialization.data(withJSONObject: el),
                  let item = try? Store.decoder.decode(TrayItem.self, from: d),
                  item.path.hasPrefix("/"), !out.contains(where: { $0.id == item.id }) else { continue }
            out.append(item)
        }
        return Array(out.prefix(cap))
    }

    public var items: [TrayItem] { lock.lock(); defer { lock.unlock() }; return list }
    public var count: Int { items.count }

    /// Symlinks in the parents resolved, so /tmp/a and /private/tmp/a are the same file.
    static func canon(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    /// Add files by reference. Only existing files and folders (not links, not file promises) are carried; the first
    /// `cap` are kept and the rest counted. Bookmarks are made before the lock is taken.
    @discardableResult
    public func add(_ urls: [URL]) -> TrayAdd {
        var r = TrayAdd()
        var candidates: [(path: String, canon: String, bookmark: Data?)] = []
        for u in urls {
            guard u.isFileURL else { r.refused.append("The Tray holds files for now."); continue }
            let f = URL(fileURLWithPath: u.path)   // no file-reference or percent-encoded forms
            guard f.path.hasPrefix("/"), Stat.exists(f) else { r.refused.append("\(f.lastPathComponent) isn't a file on this Mac yet. Save it first."); continue }
            guard !Stat.isSymlink(f) else { r.refused.append("\(f.lastPathComponent) is a link, not a file."); continue }
            candidates.append((f.path, TrayStore.canon(f.path), try? f.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)))
        }
        lock.lock()
        var seen = Set(list.map { TrayStore.canon($0.path) })
        for c in candidates {
            if seen.contains(c.canon) { r.already += 1; continue }
            if list.count >= TrayStore.cap { r.overflow += 1; continue }
            list.append(TrayItem(path: c.path, bookmark: c.bookmark))
            seen.insert(c.canon)
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
        missing.subtract(ids)
        lock.unlock()
        if !gone.isEmpty { save() }
        return gone
    }

    public func clear() { remove(Set(items.map(\.id))) }

    /// Put forgotten rows back (⌘Z after a forget).
    public func restore(_ back: [TrayItem]) {
        lock.lock()
        var seen = Set(list.map { TrayStore.canon($0.path) })
        for item in back where item.path.hasPrefix("/") && !list.contains(where: { $0.id == item.id }) && !seen.contains(TrayStore.canon(item.path)) && list.count < TrayStore.cap {
            list.append(item); seen.insert(TrayStore.canon(item.path))
        }
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
    /// Does not write; call `commit()` once after a loop. A known-missing item is not re-resolved unless `retryMissing`.
    func resolve(_ item: TrayItem, retryMissing: Bool = false) -> URL? {
        let here = URL(fileURLWithPath: item.path)
        if Stat.exists(here) {
            lock.lock(); missing.remove(item.id); lock.unlock()
            return here
        }
        lock.lock(); let known = missing.contains(item.id); lock.unlock()
        if known && !retryMissing { return nil }
        var stale = false
        guard let data = item.bookmark,
              let u = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
              u.path.hasPrefix("/"), Stat.exists(URL(fileURLWithPath: u.path)) else {
            lock.lock(); missing.insert(item.id); lock.unlock()
            return nil
        }
        let found = URL(fileURLWithPath: u.path)
        let fresh = stale ? try? found.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        lock.lock()
        missing.remove(item.id)
        if let i = list.firstIndex(where: { $0.id == item.id }) {
            list[i].path = found.path
            if let fresh { list[i].bookmark = fresh }
            dirty = true
        }
        lock.unlock()
        return found
    }

    /// Writes once if resolving changed anything.
    func commit() {
        lock.lock(); let d = dirty; dirty = false; lock.unlock()
        if d { save() }
    }

    private func save() {
        saveLock.lock(); defer { saveLock.unlock() }
        lock.lock(); let snapshot = list; lock.unlock()   // taken inside the save lock: the last writer holds the latest list
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
        saveLock.lock(); defer { saveLock.unlock() }
        lock.lock(); list = []; missing = []; lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }
}

/// ⌘Z in the Tray undoes the single most recent action, whether it was a forget or a move.
public struct TrayUndoStack: Sendable {
    public enum Entry: Sendable, Equatable { case forget([TrayItem]), move(String) }
    public private(set) var entries: [Entry] = []
    public init() {}
    public var top: Entry? { entries.last }
    public var isEmpty: Bool { entries.isEmpty }
    public mutating func push(_ e: Entry) { entries.append(e) }
    public mutating func pop() -> Entry? { entries.popLast() }
    /// A run undone elsewhere (a notice's Undo) can't be undone again from here.
    public mutating func drop(run: String) { entries.removeAll { $0 == .move(run) } }
    public var label: String? {
        switch top { case .forget: return "Undo forget"; case .move: return "Undo move"; case nil: return nil }
    }
    public var topRun: String? { if case .move(let r)? = top { return r }; return nil }
}

/// What a key does on the Tray page. Pure, so key routing is testable; the island only supplies the facts.
public enum TrayKey {
    public enum Phase: Sendable { case list, planning, review, moving }
    public enum Action: Sendable, Equatable {
        case passThrough            // not ours: the focused control or the island's own handling gets it
        case consume
        case organize, move
        case step(Int), reorder(Int)
        case planStep(Int), cycleShelf(Int)
        case forget, paste, undo, reveal, quickLook
    }
    public static let returnKey = 36, enterKey = 76, space = 49, left = 123, right = 124, down = 125, up = 126
    public static let delete = 51, forwardDelete = 117, v = 9, z = 6, r = 15, escape = 53, slash = 44, comma = 43

    /// `controlFocused`: a button or other control has keyboard focus, so Return and Space belong to it
    /// (that is how "Not now" cancels) and arrows move focus.
    public static func route(code: Int, cmd: Bool, option: Bool, phase: Phase, controlFocused: Bool) -> Action {
        switch code {
        case returnKey, enterKey:
            if cmd { return .consume }
            if controlFocused { return .passThrough }
            switch phase { case .list: return .organize; case .review: return .move; default: return .consume }
        case space:
            return controlFocused ? .passThrough : .quickLook
        case up, down:
            if controlFocused && !cmd { return .passThrough }
            let d = code == up ? -1 : 1
            switch phase { case .list: return option ? .reorder(d) : .step(d); case .review: return .planStep(d); default: return .consume }
        case left, right:
            if controlFocused && !cmd { return .passThrough }
            return phase == .review && !cmd ? .cycleShelf(code == left ? -1 : 1) : .consume
        case delete, forwardDelete:
            if controlFocused && !cmd { return .passThrough }
            return !cmd && phase == .list ? .forget : .consume     // ⌘⌫ is not used here
        case v where cmd: return phase == .list ? .paste : .consume
        case z where cmd: return .undo
        case r where cmd: return .reveal
        case escape, slash, comma: return .passThrough
        default: return cmd ? .consume : .passThrough
        }
    }

    /// The shelf after `current`, stepping through `choices` and wrapping.
    public static func cycled(_ current: String?, in choices: [String], by d: Int) -> String? {
        guard !choices.isEmpty else { return nil }
        guard let current, let i = choices.firstIndex(of: current) else { return d >= 0 ? choices.first : choices.last }
        return choices[((i + d) % choices.count + choices.count) % choices.count]
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
    public var destRoot: String?    // the watched folder it would be filed in, when that isn't where it is now
    public var planned: Planned?
    public var name: String { entry.name }
    public var willMove = false     // set by previews that carry no Planned (snapshots)
    public var moves: Bool { planned != nil || willMove }
    public init(entry: TrayEntry, shelf: String? = nil, basis: String = "", newShelf: Bool = false, stays: String? = nil, planned: Planned? = nil, willMove: Bool = false) {
        self.willMove = willMove
        self.id = entry.id; self.entry = entry; self.shelf = shelf; self.basis = basis; self.newShelf = newShelf; self.stays = stays; self.planned = planned
    }
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
    public func trayEntries(retryMissing: Bool = false) -> [TrayEntry] {
        defer { tray.commit() }
        return tray.items.map { item in
            guard let url = tray.resolve(item, retryMissing: retryMissing) else {
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

    /// The folder rules of a normal sort, for a file the user dropped: plain folders stay unless "sort folders" is on
    /// (never a git repository), Kanso's own folder names are never filed, and nothing inside a library folder moves.
    func trayStayReason(_ url: URL) -> String? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue && s.type(forExt: url.pathExtension.lowercased()) == nil {
            if !s.sortFolders { return "A folder. Kanso only sorts files unless you turn on sorting folders." }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return "A git repository, Kanso leaves it there." }
        }
        if Engine.ownFolders.contains(Engine.fold(url.lastPathComponent)) { return "That's one of Kanso's own folders." }
        for root in s.activeRoots {
            for lib in [Library.mine, Library.manual, Library.recents] where Engine.contained(url, in: root.appendingPathComponent(lib)) {
                return "Already in \(lib), Kanso leaves it there."
            }
        }
        return nil
    }

    /// Same disk? A move across disks would be a copy and a delete, which the Tray never does.
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        var x = stat(), y = stat()
        var pa = a, pb = b
        while stat(pa.path, &x) != 0, pa.path != "/" { pa = pa.deletingLastPathComponent() }
        while stat(pb.path, &y) != 0, pb.path != "/" { pb = pb.deletingLastPathComponent() }
        return x.st_dev == y.st_dev
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
            var row = TrayRow(entry: e)
            switch e.state {
            case .missing: row.stays = "Missing. Forget it to clear the row."; plan.rows.append(row); continue
            case .manualShelves: row.stays = "In Manual Shelves, Kanso leaves it there."; plan.rows.append(row); continue
            case .keep: row.stays = "Tagged \(s.keepTag) or excluded, Kanso leaves it there."; plan.rows.append(row); continue
            case .ready: break
            }
            if let why = trayStayReason(e.url) { row.stays = why; plan.rows.append(row); continue }
            guard let root = rootFor(e.url) ?? s.activeRoots.first else {
                row.stays = "No watched folder to file it in."; plan.rows.append(row); continue
            }
            if rootFor(e.url) == nil || s.activeRoots.count > 1 { row.destRoot = root.lastPathComponent }
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
            if !Engine.sameVolume(e.url, root) {
                row.stays = "On another disk"; row.shelf = nil; plan.rows.append(row); continue
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
        var byPath: [String: [TrayRow]] = [:]
        defer { tray.commit() }
        let items = tray.items
        for row in plan.rows {
            guard var m = row.planned, only?.contains(row.id) ?? true else { continue }
            if let pick = shelves[row.id], s.types.contains(where: { $0.name == pick }), Engine.automaticShelfAllowed(pick) {
                m.dest = resolve(m.item.root, pick); m.shelf = pick; m.why = "chosen in the Tray"; m.source = "you chose it"; m.learning = nil
            }
            // The file may have moved on since the plan was made: always act on where it is now.
            guard let now = items.first(where: { $0.id == row.id }).flatMap({ tray.resolve($0, retryMissing: true) }) else { continue }
            if now.path != m.item.url.path { m.item = Item.inspect(now, root: m.item.root) }
            if byPath[m.item.url.path] == nil { moves.append(m) }   // two rows for one file: it moves once, both rows leave
            byPath[m.item.url.path, default: []].append(row)
        }
        var result = TrayResult()
        result.moved = apply(moves, trigger: "tray")
        let movedSrc = Set(result.moved.map(\.src))
        var done = Set<UUID>()
        for (path, rows) in byPath {
            for row in rows {
                if movedSrc.contains(path) { done.insert(row.id) }
                else if !Stat.exists(URL(fileURLWithPath: path)) { done.insert(row.id) }   // it left on its own
                else { result.stayed.append((row.name, "Couldn't move it. It may be open in another app, or the shelf isn't writable.")) }
            }
        }
        tray.remove(done)
        return result
    }
}
