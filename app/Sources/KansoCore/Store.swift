import Foundation

/// Everything Kanso did, in order. Undo reads it; Activity, stats and insights are computed from it.
public struct Action: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case sorted, renamed, duplicate, trashed }

    public var id = UUID()
    public var run: String
    public var ts = Date()
    public var kind: Kind
    public var src: String          // where the item was
    public var dst: String          // where it is now
    public var link: String?        // Recents symlink left for it
    public var root: String
    public var shelf: String        // type / shelf name ("Documents", "Duplicates")
    public var why: String          // "extension", "rule invoice*", "screenshot", "apple-intelligence new type Torrents"
    public var source: String       // what the decision used: "metadata only", "from name", "contents, page 1", "size + hash"
    public var trigger: String = "auto"  // auto · menu · sort-everything · review
    public var tags: [String] = []  // Finder tags Kanso added
    public var oldName: String?     // set when renamed
    public var details: [String: String] = [:]  // kind, organization, date, kept (duplicate), size, from
    public var undone = false
    public var pending = false      // duplicate waiting for Move to Trash / Keep both

    enum CodingKeys: String, CodingKey {
        case id, run, ts, kind, src, dst, link, root, shelf, why, source, trigger, tags, oldName, details, undone, pending
    }

    /// Tolerant: only run, kind, src and dst are essential. Anything else missing or malformed gets a default,
    /// so a journal written by another version still loads. A line that fails (unknown kind…) is kept verbatim on disk.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decode(String.self, forKey: .run)
        kind = try c.decode(Kind.self, forKey: .kind)
        src = try c.decode(String.self, forKey: .src)
        dst = try c.decode(String.self, forKey: .dst)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        ts = (try? c.decodeIfPresent(Date.self, forKey: .ts)) ?? Date()
        link = (try? c.decodeIfPresent(String.self, forKey: .link)) ?? nil
        root = (try? c.decodeIfPresent(String.self, forKey: .root)) ?? ""
        shelf = (try? c.decodeIfPresent(String.self, forKey: .shelf)) ?? ""
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? ""
        trigger = (try? c.decodeIfPresent(String.self, forKey: .trigger)) ?? "auto"
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        oldName = (try? c.decodeIfPresent(String.self, forKey: .oldName)) ?? nil
        details = (try? c.decodeIfPresent([String: String].self, forKey: .details)) ?? [:]
        undone = (try? c.decodeIfPresent(Bool.self, forKey: .undone)) ?? false
        pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? false
    }

    public init(run: String, kind: Kind, src: String, dst: String, root: String, shelf: String, why: String, source: String) {
        self.run = run; self.kind = kind; self.src = src; self.dst = dst; self.root = root
        self.shelf = shelf; self.why = why; self.source = source
    }

    public var name: String { (dst as NSString).lastPathComponent }
    public var srcName: String { (src as NSString).lastPathComponent }
    public var renamed: Bool { oldName != nil }
}

/// A rename Kanso proposes but hasn't done: mass renames wait for the review window.
public struct RenameProposal: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var path: String
    public var newName: String
    public var shelf: String
    public var source: String
    public var details: [String: String] = [:]
    public init(path: String, newName: String, shelf: String, source: String, details: [String: String] = [:]) {
        self.path = path; self.newName = newName; self.shelf = shelf; self.source = source; self.details = details
    }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Learned from repeated manual moves between shelves.
public struct RuleSuggestion: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var condition: Condition
    public var shelf: String
    public var files: [String]
    public var ts = Date()
    public init(condition: Condition, shelf: String, files: [String]) {
        self.condition = condition; self.shelf = shelf; self.files = files
    }
}

public struct Correction: Codable, Hashable, Sendable {
    public var name: String
    public var ext: String
    public var from: String?
    public var fromShelf: String
    public var toShelf: String
    public var ts = Date()
}

public struct Pending: Codable, Equatable, Sendable {
    public var renames: [RenameProposal] = []
    public var renamesFound: Date?
    public var suggestions: [RuleSuggestion] = []
    public var dismissed: [String] = []   // suggestion keys the user said no to
    public var corrections: [Correction] = []
    public init() {}
}

/// On-disk state in ~/Library/Application Support/Kanso (or $KANSO_HOME): settings.json, journal.jsonl, pending.json.
public final class Store: @unchecked Sendable {
    public let dir: URL
    private let lock = NSLock()
    private let ioLock = NSLock()   // serializes settings.json / pending.json writes so they land in order
    public private(set) var settings: Settings
    public private(set) var actions: [Action]
    public private(set) var pending: Pending

    public static var defaultDir: URL {
        if let h = ProcessInfo.processInfo.environment["KANSO_HOME"] { return URL(fileURLWithPath: (h as NSString).expandingTildeInPath) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kanso")
    }

    public init(dir: URL = Store.defaultDir) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = Store.readOrBackup(Settings.self, dir.appendingPathComponent("settings.json")) ?? Settings()
        pending = Store.readOrBackup(Pending.self, dir.appendingPathComponent("pending.json")) ?? Pending()
        let lines = (try? String(contentsOf: dir.appendingPathComponent("journal.jsonl"), encoding: .utf8)) ?? ""
        actions = lines.split(separator: "\n").compactMap { try? Store.decoder.decode(Action.self, from: Data($0.utf8)) }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path) { saveSettings() }
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func read<T: Decodable>(_ t: T.Type, _ url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? decoder.decode(T.self, from: $0) }
    }

    /// Like `read`, but a file that exists and can't be decoded is copied to `<name>.bak` before the defaults overwrite it.
    static func readOrBackup<T: Decodable>(_ t: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let v = try? decoder.decode(T.self, from: data) { return v }
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
        return nil
    }

    public func update(_ change: (inout Settings) -> Void) {
        lock.lock(); change(&settings); lock.unlock()
        saveSettings()
    }

    public func updatePending(_ change: (inout Pending) -> Void) {
        lock.lock(); change(&pending); lock.unlock()
        write(pending, "pending.json")
    }

    private func saveSettings() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        ioLock.lock(); defer { ioLock.unlock() }
        lock.lock(); let data = try? e.encode(settings); lock.unlock()
        try? data?.write(to: dir.appendingPathComponent("settings.json"), options: .atomic)
    }

    private func write<T: Encodable>(_ value: T, _ file: String) {
        ioLock.lock(); defer { ioLock.unlock() }
        lock.lock(); let data = try? Store.encoder.encode(value); lock.unlock()
        try? data?.write(to: dir.appendingPathComponent(file), options: .atomic)
    }

    /// Append as it happens, so undo survives a crash mid-run.
    public func append(_ a: Action) {
        lock.lock(); defer { lock.unlock() }
        actions.append(a)
        guard var data = try? Store.encoder.encode(a) else { return }
        data.append(0x0A)
        let url = dir.appendingPathComponent("journal.jsonl")
        do {
            if let h = try? FileHandle(forUpdating: url) {
                defer { try? h.close() }
                let end = try h.seekToEnd()
                if end > 0 {
                    // A torn last line (crash, full disk) must not swallow this entry: start a fresh line.
                    try h.seek(toOffset: end - 1)
                    let last = try h.read(upToCount: 1)
                    if last != Data([0x0A]) { try h.seekToEnd(); try h.write(contentsOf: Data([0x0A])) }
                    else { try h.seekToEnd() }
                }
                try h.write(contentsOf: data)
            } else {
                try data.write(to: url)
            }
        } catch {
            NSLog("Kanso: journal append failed: \(error)")
        }
    }

    /// ponytail: rewrites the whole journal; fine for years of actions, switch to SQLite if it grows past ~100k.
    /// Lines that don't decode (torn, or written by a newer version) are kept verbatim; the write happens inside the lock.
    public func modify(_ ids: Set<UUID>, _ change: (inout Action) -> Void) {
        lock.lock(); defer { lock.unlock() }
        for i in actions.indices where ids.contains(actions[i].id) { change(&actions[i]) }
        let url = dir.appendingPathComponent("journal.jsonl")
        let current = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out: [String] = []
        var seen = Set<UUID>()
        for line in old.split(separator: "\n", omittingEmptySubsequences: true) {
            if let a = try? Store.decoder.decode(Action.self, from: Data(line.utf8)), let now = current[a.id] {
                seen.insert(a.id)
                if ids.contains(a.id), let d = try? Store.encoder.encode(now) { out.append(String(decoding: d, as: UTF8.self)); continue }
            }
            out.append(String(line))
        }
        // In-memory actions whose append never reached the disk.
        for a in actions where !seen.contains(a.id) {
            if let d = try? Store.encoder.encode(a) { out.append(String(decoding: d, as: UTF8.self)) }
        }
        do {
            try (out.isEmpty ? "" : out.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Kanso: journal rewrite failed: \(error)")
        }
    }
}
