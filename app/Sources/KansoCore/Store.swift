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
        settings = Store.read(Settings.self, dir.appendingPathComponent("settings.json")) ?? Settings()
        pending = Store.read(Pending.self, dir.appendingPathComponent("pending.json")) ?? Pending()
        let lines = (try? String(contentsOf: dir.appendingPathComponent("journal.jsonl"), encoding: .utf8)) ?? ""
        actions = lines.split(separator: "\n").compactMap { try? Store.decoder.decode(Action.self, from: Data($0.utf8)) }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path) { saveSettings() }
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func read<T: Decodable>(_ t: T.Type, _ url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? decoder.decode(T.self, from: $0) }
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
        lock.lock(); let data = try? e.encode(settings); lock.unlock()
        try? data?.write(to: dir.appendingPathComponent("settings.json"), options: .atomic)
    }

    private func write<T: Encodable>(_ value: T, _ file: String) {
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
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// ponytail: rewrites the whole journal; fine for years of actions, switch to SQLite if it grows past ~100k.
    public func modify(_ ids: Set<UUID>, _ change: (inout Action) -> Void) {
        lock.lock()
        for i in actions.indices where ids.contains(actions[i].id) { change(&actions[i]) }
        let body = actions.compactMap { try? Store.encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        lock.unlock()
        try? (body.isEmpty ? "" : body + "\n").write(to: dir.appendingPathComponent("journal.jsonl"), atomically: true, encoding: .utf8)
    }
}
