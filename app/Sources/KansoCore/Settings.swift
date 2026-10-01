import Foundation

/// A shelf in "My Shelves". `match` lists the extensions that belong there.
public struct FileType: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var emoji: String
    public var description: String
    public var match: [String]
    public var learned = false
    public var id: String { name }

    public init(_ name: String, _ emoji: String, _ description: String, _ match: [String], learned: Bool = false) {
        self.name = name; self.emoji = emoji; self.description = description; self.match = match; self.learned = learned
    }
}

public enum Shelf {
    public static let unsorted = "Unsorted"
    public static let screenshots = "Screenshots"
    public static let duplicates = "Duplicates"
    public static let keys = "Keys"
}

/// One condition of a rule. All conditions of a rule must hold.
public struct Condition: Codable, Hashable, Sendable {
    public enum Field: String, Codable, CaseIterable, Sendable { case name, ext, from, size }
    public var field: Field
    public var value: String  // name: glob · ext: "dmg" · from: text in the download URL · size: minimum, like "2 GB"
    public init(_ field: Field, _ value: String) { self.field = field; self.value = value }
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var enabled = true
    public var conditions: [Condition]
    public var dest: String  // a shelf ("Automations", "Documents/Invoices") or an absolute / ~ path
    public var tags: [String] = []
    public var matchAny = false // false: all conditions must match; true: any one
    public var builtIn = false  // Kanso's own defaults: they work, but Rules shows only the user's rules
    public init(_ conditions: [Condition], dest: String, tags: [String] = [], builtIn: Bool = false) {
        self.conditions = conditions; self.dest = dest; self.tags = tags; self.builtIn = builtIn
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        conditions = try c.decode([Condition].self, forKey: .conditions)
        dest = try c.decode(String.self, forKey: .dest)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        matchAny = (try? c.decode(Bool.self, forKey: .matchAny)) ?? false
        builtIn = (try? c.decode(Bool.self, forKey: .builtIn)) ?? Rule.defaults.contains { $0.conditions == conditions && $0.dest == dest }
    }
}

public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32  // Carbon modifier flags
    public var display: String    // "⌃⌥⌘Z"
    public init(keyCode: UInt32, modifiers: UInt32, display: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.display = display }
}

public enum RecentsMode: String, Codable, CaseIterable, Sendable { case links, hold, off }
public enum Approach: String, Codable, Sendable { case kind, purpose }
public enum Keeper: String, Codable, CaseIterable, Sendable { case oldest, bestNamed, onShelf }
public enum UnknownFiles: String, Codable, CaseIterable, Sendable { case askModel, unsorted }
public enum IslandMode: String, Codable, CaseIterable, Sendable { case automatic, notch, below }

public struct Settings: Codable, Equatable, Sendable {
    public var onboarded = false
    public var roots: [String] = ["~/Downloads", "~/Desktop", "~/Documents"]
    public var pausedRoots: [String] = []
    public var since = Date()  // auto mode only touches items that arrived after this

    // Sorting
    public var autoSort = true         // the "Sorting" switch
    public var sortingOffUntil: Date?  // set when Sorting is turned off for a while; nil while off = until turned on
    public var sortingOffSince: Date?
    public var offReminderShown = false
    public var settleSeconds = 10
    public var graceMinutes = 0        // "Leave new files alone for"
    public var smartEject = true
    public var approach = Approach.kind
    public var recents = RecentsMode.links
    public var recentDays = 7
    public var folderIcons = true
    public var sortFolders = false
    public var keepTag = "Keep"
    public var learnCorrections = true
    public var unknownFiles = UnknownFiles.askModel
    public var suggestTypes = true
    public var appleIntelligence = true

    // Features
    public var renaming = true
    public var normalizeNames = false
    public var keepOriginalSearchable = true
    public var askBeforeMassRenames = true
    public var massRenameThreshold = 10
    public var separator = "-"
    public var nameParts = ["kind", "organization", "date"]   // order of the rename template; parts can be removed
    public var dateFormat = "yyyy-MM"
    public var extraMeaningless: [String] = []   // user globs, like "Rechnung_*"
    public var disabledPatterns: [String] = []   // built-in pattern labels the user turned off ("Don't rename files like this")
    public var tagging = false
    public var tagsPerFile = 2
    public var tagKind = true
    public var tagOrganization = true
    public var useExistingTags = true
    public var duplicates = true
    public var keeper = Keeper.oldest
    public var checkManualShelves = true
    public var duplicatesToTrash = false   // opt-in: extra copies go straight to the Trash (ADR 0002 amendment)
    public var autoTrashDuplicates = false // opt-in: held copies untouched for autoTrashDays go to the Trash
    public var autoTrashDays = 30

    // General
    public var islandMode = IslandMode.automatic
    public var shortcutHintUntil = Date().addingTimeInterval(5 * 86400)  // the ⌥⌘K hint shows for the first days
    public var showShortcutHint = true
    public var collectDuringFocus = true
    public var openAtLogin = false
    public var showMenuBarIcon = true
    public var appearance = "system"   // the app's theme: "system", "light" or "dark"
    public var updateChecks = true
    public var crashReports = false
    public var islandShortcut = Shortcut(keyCode: 40, modifiers: 0x0800 | 0x0100, display: "⌥⌘K")  // K for Kanso

    public var types: [FileType] = FileType.defaults
    public var learnedExts: [String] = []   // extensions Kanso learned (from the model or your moves), even when filed under a built-in type
    public var rules: [Rule] = Rule.defaults

    public init() {}

    public var activeRoots: [URL] {
        roots.filter { !pausedRoots.contains($0) }.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    public func type(named name: String) -> FileType? { types.first { $0.name == name } }

    /// The type an extension belongs to (the first type listing it).
    public func type(forExt ext: String) -> FileType? {
        guard !ext.isEmpty else { return nil }
        return types.first { $0.match.contains(ext) }
    }

    public func emoji(for shelf: String) -> String {
        switch shelf {
        case Library.mine: return "✨"
        case Library.manual: return "🏠"
        case Library.recents: return "🆕"
        case Shelf.duplicates: return "🪞"
        default: return type(named: shelf.components(separatedBy: "/").first ?? shelf)?.emoji ?? "📁"
        }
    }

    // Decoding tolerates missing keys, so settings files from older versions keep working.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decode(T.self, forKey: k) { v = x } }
        d(.onboarded, &onboarded); d(.roots, &roots); d(.pausedRoots, &pausedRoots); d(.since, &since)
        d(.autoSort, &autoSort); d(.settleSeconds, &settleSeconds); d(.graceMinutes, &graceMinutes)
        sortingOffUntil = try? c.decode(Date.self, forKey: .sortingOffUntil)
        sortingOffSince = try? c.decode(Date.self, forKey: .sortingOffSince)
        d(.offReminderShown, &offReminderShown); d(.smartEject, &smartEject)
        d(.approach, &approach); d(.recents, &recents); d(.recentDays, &recentDays); d(.folderIcons, &folderIcons)
        d(.sortFolders, &sortFolders); d(.keepTag, &keepTag); d(.learnCorrections, &learnCorrections)
        d(.unknownFiles, &unknownFiles); d(.suggestTypes, &suggestTypes); d(.appleIntelligence, &appleIntelligence)
        d(.renaming, &renaming); d(.normalizeNames, &normalizeNames); d(.keepOriginalSearchable, &keepOriginalSearchable)
        d(.askBeforeMassRenames, &askBeforeMassRenames); d(.massRenameThreshold, &massRenameThreshold)
        d(.separator, &separator); d(.dateFormat, &dateFormat); d(.nameParts, &nameParts)
        d(.extraMeaningless, &extraMeaningless); d(.disabledPatterns, &disabledPatterns); d(.tagging, &tagging); d(.tagsPerFile, &tagsPerFile)
        d(.tagKind, &tagKind); d(.tagOrganization, &tagOrganization); d(.useExistingTags, &useExistingTags)
        d(.duplicates, &duplicates); d(.keeper, &keeper); d(.checkManualShelves, &checkManualShelves)
        d(.duplicatesToTrash, &duplicatesToTrash); d(.autoTrashDuplicates, &autoTrashDuplicates); d(.autoTrashDays, &autoTrashDays)
        d(.islandMode, &islandMode); d(.shortcutHintUntil, &shortcutHintUntil); d(.showShortcutHint, &showShortcutHint)
        d(.collectDuringFocus, &collectDuringFocus); d(.openAtLogin, &openAtLogin)
        d(.showMenuBarIcon, &showMenuBarIcon); d(.appearance, &appearance); d(.updateChecks, &updateChecks); d(.crashReports, &crashReports)
        d(.islandShortcut, &islandShortcut)
        d(.types, &types); d(.rules, &rules); d(.learnedExts, &learnedExts)
    }
}

/// The three folders Kanso keeps in each watched folder.
public enum Library {
    public static let mine = "My Shelves"
    public static let manual = "Manual Shelves"
    public static let recents = "Recents"
    public static let all: Set<String> = [mine, manual, recents]
}

public extension FileType {
    static let defaults: [FileType] = [
        FileType("Documents", "📄", "Text documents: PDFs, word-processor files, plain text and notes", ["pdf", "doc", "docx", "pages", "txt", "md", "rtf", "odt"]),
        FileType("Reports", "📊", "Spreadsheets and tabular data: budgets, tables, exports", ["xls", "xlsx", "numbers", "csv", "tsv", "ods"]),
        FileType("Presentations", "📽️", "Slide decks", ["key", "ppt", "pptx", "odp"]),
        FileType("Ebooks", "📚", "Electronic books for e-readers", ["epub", "mobi", "azw", "azw3", "fb2", "djvu"]),
        FileType("Images", "🖼️", "Photos, pictures, graphics and icons", ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "bmp", "svg", "raw", "ico", "avif"]),
        FileType("Screenshots", "📸", "Screenshots and screen recordings taken on this Mac (found by the screen-capture flag, not the extension)", []),
        FileType("Videos", "🎬", "Video clips and movies", ["mov", "mp4", "m4v", "avi", "mkv", "webm"]),
        FileType("Audio", "🎵", "Music, podcasts, voice memos and sound files", ["mp3", "m4a", "wav", "aiff", "flac", "ogg", "mid", "midi"]),
        FileType("Design", "🎨", "Design and layered graphics source files", ["psd", "fig", "sketch", "ai", "xd"]),
        FileType("Code", "💻", "Source code, scripts, notebooks and config files", ["py", "js", "ts", "tsx", "jsx", "sh", "rb", "go", "rs", "swift", "java", "c", "cpp", "h", "html", "css", "ipynb", "yaml", "yml", "toml"]),
        FileType("Automations", "⚙️", "Automation workflows and macros: Shortcuts, Automator, AppleScript, Keyboard Maestro, Alfred, Hazel, BetterTouchTool", ["shortcut", "workflow", "scpt", "scptd", "applescript", "kmmacros", "kmlibrary", "alfredworkflow", "hazelrules", "bttpreset", "popclipextz"]),
        FileType("Databases", "🗄️", "Databases and database dumps: SQL scripts, SQLite, MongoDB, Access and other database files", ["sql", "sqlite", "sqlite3", "db", "db3", "duckdb", "mdb", "accdb", "bson", "dump", "rdb", "realm", "frm", "ibd"]),
        FileType("Diagrams", "📐", "Diagrams and charts: architecture, flowcharts, schemas, mind maps", ["mermaid", "mmd", "drawio", "excalidraw", "puml", "plantuml", "dot", "gv", "vsdx", "graffle"]),
        FileType("JSON", "🧾", "JSON data files and API exports", ["json", "jsonl", "geojson"]),
        FileType("Archives", "📦", "Compressed archives and bundles of files", ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]),
        FileType("Apps", "📲", "Applications, installers and disk images", ["dmg", "pkg", "mpkg", "app", "iso"]),
        FileType("3D Models", "🧊", "3D models and scenes for printing, games and design", ["stl", "obj", "fbx", "blend", "glb", "gltf", "usdz", "3mf", "dae"]),
        FileType("Keys", "🔑", "Security keys, certificates and password vaults", ["pem", "p12", "pfx", "cer", "crt", "der", "csr", "pub", "gpg", "asc", "kdbx", "keychain"]),
        FileType("Calendars", "📅", "Calendar invites and events", ["ics", "ical", "vcs"]),
        FileType("Contacts", "👤", "Contact cards", ["vcf", "vcard"]),
        FileType("Torrents", "🧲", "Torrent and magnet files for peer-to-peer downloads", ["torrent"]),
        FileType("Fonts", "🔤", "Font files", ["ttf", "otf", "woff", "woff2"]),
        FileType("Unsorted", "❓", "Items whose type could not be determined", []),
    ]
}

public extension Rule {
    /// Automation exports that are plain .json, told apart by where they came from.
    static let defaults: [Rule] = [
        Rule([Condition(.from, "make.com"), Condition(.ext, "json")], dest: "Automations", builtIn: true),
        Rule([Condition(.from, "n8n"), Condition(.ext, "json")], dest: "Automations", builtIn: true),
        Rule([Condition(.from, "zapier.com"), Condition(.ext, "json zip")], dest: "Automations", builtIn: true),
        Rule([Condition(.name, "*blueprint*.json")], dest: "Automations", builtIn: true),
    ]
}
