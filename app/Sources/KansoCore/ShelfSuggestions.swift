import Foundation

/// A proposed new shelf for items piling up in Unsorted: 5 or more share an extension, or start with the same word.
/// Found by counting names, with no model; nothing moves until the user accepts.
public struct ShelfSuggestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case ext, word }
    public var kind: Kind
    public var key: String            // the extension ("qqq") or the leading word ("invoice")
    public var name: String           // the shelf to create
    public var emoji: String
    public var description: String
    public var files: [String]        // full paths, all inside some watched folder's My Shelves/Unsorted
    public var id: String { "\(kind.rawValue):\(key)" }
    /// What dismissal remembers.
    public var dismissalKey: String { "shelf:\(id)" }
    public var ts: Date = Date()
}

public extension Engine {
    static let shelfSuggestionMinimum = 5
    /// Leading words too generic to name a shelf.
    static let genericWords: Set<String> = ["scan", "scanned", "image", "images", "photo", "document", "documents", "untitled", "screenshot", "copy", "file", "files",
                                            "download", "downloads", "final", "draft", "new", "temp", "test", "backup", "export", "unknown", "attachment", "data", "video", "audio"]

    /// Suggestions from what sits in Unsorted right now, minus the ones the user dismissed.
    func suggestedShelves() -> [ShelfSuggestion] {
        let settings = s
        guard settings.suggestTypes else { return [] }
        let dismissed = Set(store.pending.dismissed)
        struct UFile { var path: String; var name: String; var ext: String }
        var files: [UFile] = []
        for root in settings.activeRoots {
            let dir = root.appendingPathComponent(Library.mine).appendingPathComponent(Shelf.unsorted)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names where !n.hasPrefix(".") {
                let u = dir.appendingPathComponent(n)
                guard !isDir(u), !Stat.isSymlink(u), !Tags.read(u).contains(settings.keepTag) else { continue }
                files.append(UFile(path: u.path, name: n, ext: (n as NSString).pathExtension.lowercased()))
            }
        }
        func taken(_ name: String) -> Bool { settings.types.contains { Engine.fold($0.name) == Engine.fold(name) } }
        var out: [ShelfSuggestion] = []
        var used = Set<String>()

        // 1. A shared extension that no shelf claims.
        let plainExt: (UFile) -> Bool = { f in
            !f.ext.isEmpty && f.ext.count <= 12 && f.ext.allSatisfy { ch in ch.isLetter || ch.isNumber } && settings.type(forExt: f.ext) == nil
        }
        let byExt = Dictionary(grouping: files.filter(plainExt), by: { $0.ext })
        for (ext, group) in byExt.sorted(by: { $0.key < $1.key }) where group.count >= Engine.shelfSuggestionMinimum {
            let name = ext.uppercased() + " Files"
            let sug = ShelfSuggestion(kind: .ext, key: ext, name: name, emoji: "🗂️", description: "Files with the .\(ext) extension", files: group.map { $0.path }.sorted())
            group.forEach { used.insert($0.path) }   // claimed even when dismissed, so the same files aren't offered again by name
            guard Engine.automaticShelfAllowed(name), !taken(name), !dismissed.contains(sug.dismissalKey) else { continue }
            out.append(sug)
        }

        // 2. A shared leading word in the name, among what is left.
        func leadingWord(_ file: String) -> String? {
            let stem = (file as NSString).deletingPathExtension.lowercased()
            let word = stem.prefix { $0.isLetter }
            return word.count >= 4 && word.count <= 20 && !Engine.genericWords.contains(String(word)) ? String(word) : nil
        }
        let byWord = Dictionary(grouping: files.filter { !used.contains($0.path) && plainExt($0) || !used.contains($0.path) && $0.ext.isEmpty }.filter { leadingWord($0.name) != nil }, by: { leadingWord($0.name)! })
        for (word, group) in byWord.sorted(by: { $0.key < $1.key }) where group.count >= Engine.shelfSuggestionMinimum {
            let cap = word.prefix(1).uppercased() + word.dropFirst()
            let name = cap.hasSuffix("s") ? cap : cap + "s"
            let sug = ShelfSuggestion(kind: .word, key: word, name: name, emoji: "🗂️", description: "Files whose name starts with “\(word)”", files: group.map { $0.path }.sorted())
            guard Engine.automaticShelfAllowed(name), !taken(name), !dismissed.contains(sug.dismissalKey) else { continue }
            out.append(sug)
        }
        return out
    }

    /// Accept: create the shelf (and, for a word, a rule that keeps filing there), then move the items as ONE run, so one Undo reverts them all.
    /// The suggestion is recomputed from disk; only its id is trusted, so a stale or forged one does nothing.
    @discardableResult
    func acceptShelfSuggestion(_ id: String) -> [Action] {
        guard let sug = suggestedShelves().first(where: { $0.id == id }), Engine.automaticShelfAllowed(sug.name) else { return [] }
        store.update { s in
            let at = s.types.firstIndex { $0.name == Shelf.unsorted } ?? s.types.endIndex
            switch sug.kind {
            case .ext:
                s.types.insert(FileType(sug.name, sug.emoji, sug.description, [sug.key], learned: true), at: at)
                if !s.learnedExts.contains(sug.key) { s.learnedExts.append(sug.key) }
            case .word:
                s.types.insert(FileType(sug.name, sug.emoji, sug.description, []), at: at)
                var rule = Rule([Condition(.name, sug.key + "*")], dest: sug.name)
                rule.automatic = true
                s.rules.append(rule)
            }
        }
        let moves: [Planned] = sug.files.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let root = rootFor(url) else { return nil }
            return Planned(item: Item(url: url, root: root), dest: resolve(root, sug.name), shelf: sug.name,
                           why: "new shelf \(sug.name)", source: "your Unsorted shelf")
        }
        return apply(moves, trigger: "suggestion")
    }

    /// Dismiss: remembered, so the same suggestion doesn't come back.
    func dismissShelfSuggestion(_ id: String) {
        store.updatePending { p in
            let key = "shelf:\(id)"
            if !p.dismissed.contains(key) { p.dismissed.append(key) }
        }
    }
}
