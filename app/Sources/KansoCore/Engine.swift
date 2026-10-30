import AppKit
import CryptoKit
import Foundation
import IOKit.ps

/// True on battery below 20%: reading file contents waits for the charger (fixed behavior, no setting).
public func lowBattery() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue,
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
    for src in list {
        if let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
           let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
            return Double(cap) / Double(max) < 0.2
        }
    }
    return false
}

/// One planned move. The review window can uncheck it (`include`) or edit `newName`.
public struct Planned: Identifiable, Sendable {
    public enum Stage: Sendable { case recent, sort }
    public var id = UUID()
    public var item: Item
    public var stage = Stage.sort
    public var dest: URL          // destination folder
    public var shelf: String
    public var kind = Action.Kind.sorted
    public var newName: String?   // rename now
    public var proposedName: String?  // rename later, after review
    public var tags: [String] = []
    public var why: String
    public var source: String
    public var link: URL?         // Recents folder to leave a symlink in
    public var details: [String: String] = [:]
    public var include = true
    public var learning: Learning?   // applied by apply(), only if the move happens
}

/// What a model pick teaches: this extension belongs on that type. Carried in the plan so dry runs and unchecked items teach nothing.
public struct Learning: Sendable, Equatable {
    public var ext: String
    public var type: String
    public var emoji: String = "📁"
    public var description: String = ""
}

/// Items not moved yet because they are still downloading or changing.
public struct Waiting: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public var url: URL
    public var root: URL
    public var size: Int64
    public var partial: Bool
    public var since: Date
    public var shelf: String?
    public init(url: URL, root: URL, size: Int64, partial: Bool, since: Date, shelf: String?) {
        self.url = url; self.root = root; self.size = size; self.partial = partial; self.since = since; self.shelf = shelf
    }
}

public struct Plan: Sendable {
    public var moves: [Planned] = []
    public var waiting: [Waiting] = []
}

public let partialExtensions = [".crdownload", ".download", ".part", ".partial", ".opdownload", ".tmp"]

public final class Engine: @unchecked Sendable {
    /// Reading contents pauses on a low battery; tests replace this so they don't depend on the machine's charge.
    nonisolated(unsafe) public static var batteryLow: () -> Bool = { lowBattery() }

    public let store: Store
    public let classifier: Classifier
    public var setIcon: (URL, String) -> Void = FolderIcon.set
    public var reading: @Sendable (String, Bool) -> Void = { _, _ in }   // (file name, started): lets the island show a slow read
    let fm = FileManager.default

    public init(store: Store, classifier: Classifier = AppleIntelligence()) {
        self.store = store
        self.classifier = classifier
    }

    var s: Settings { store.settings }

    // MARK: Scanning

    func ignored(_ url: URL) -> Bool {
        let n = url.lastPathComponent
        return n.hasPrefix(".") || n.hasPrefix("~$") || n == "Icon\r" || partialExtensions.contains { n.lowercased().hasSuffix($0) }
            || Tags.read(url).contains(s.keepTag)
    }

    func candidates(all: Bool, now: Date) -> ([(URL, URL, Planned.Stage, Bool)], [Waiting]) {
        let recentS = TimeInterval(s.recentDays * 86400)
        let hold = s.recents == .hold
        let after = all ? 0 : s.since.timeIntervalSince1970
        var out: [(URL, URL, Planned.Stage, Bool)] = []
        var waiting: [Waiting] = []
        for root in s.activeRoots {
            guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            var entries = names.filter { !Library.all.contains($0) }.map { (root.appendingPathComponent($0), false) }
            let recents = root.appendingPathComponent(Library.recents)
            if hold, let r = try? fm.contentsOfDirectory(atPath: recents.path) {
                entries += r.map { recents.appendingPathComponent($0) }.filter { !Stat.isSymlink($0) }.map { ($0, true) }
            }
            for (url, inRecent) in entries {
                if Stat.isSymlink(url) { continue }   // links at a root are never sorted, hashed or read through
                guard let ctime = Stat.ctime(url), let mtime = Stat.mtime(url) else { continue }
                if !inRecent && ctime < after { continue }
                let name = url.lastPathComponent
                if partialExtensions.contains(where: { name.lowercased().hasSuffix($0) }) {
                    let real = url.deletingPathExtension()
                    waiting.append(Waiting(url: url, root: root, size: Stat.size(url), partial: true, since: Date(timeIntervalSince1970: ctime),
                                           shelf: s.type(forExt: real.pathExtension.lowercased())?.name))
                    continue
                }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue && s.type(forExt: url.pathExtension.lowercased()) == nil {  // bundles like .app count as files
                    if !s.sortFolders || fm.fileExists(atPath: url.appendingPathComponent(".git").path) { continue }
                }
                if ignored(url) { continue }
                let age = now.timeIntervalSince1970 - max(mtime, ctime)
                if age < TimeInterval(s.settleSeconds) || (!all && age < TimeInterval(s.graceMinutes * 60)) {
                    waiting.append(Waiting(url: url, root: root, size: Stat.size(url), partial: false, since: Date(timeIntervalSince1970: ctime),
                                           shelf: s.type(forExt: url.pathExtension.lowercased())?.name))
                    continue
                }
                let fresh = now.timeIntervalSince1970 - ctime < recentS
                if hold && fresh {
                    if !inRecent { out.append((url, root, .recent, fresh)) }
                } else {
                    out.append((url, root, .sort, fresh))
                }
            }
        }
        return (out, waiting)
    }

    // MARK: Deciding

    public struct Decision: Sendable {
        public var dest: String; public var tags: [String]; public var why: String; public var source: String
        public var learning: Learning? = nil
    }

    public static func matches(_ rule: Rule, _ item: Item) -> Bool {
        guard rule.enabled, !rule.conditions.isEmpty else { return false }
        let test: (Condition) -> Bool = { c in
            let v = c.value.trimmingCharacters(in: .whitespaces)
            switch c.field {
            case .name: return fnmatch(v.lowercased(), item.name.lowercased(), 0) == 0
            case .ext: return v.lowercased().split { $0 == " " || $0 == "," }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.contains(item.ext)
            case .from: return !v.isEmpty && item.whereFrom.contains { $0.localizedCaseInsensitiveContains(v) }
            case .size: return parseSize(v).map { item.size >= $0 } ?? false
            }
        }
        return rule.matchAny ? rule.conditions.contains(where: test) : rule.conditions.allSatisfy(test)
    }

    public static func parseSize(_ s: String) -> Int64? {
        let parts = s.uppercased().replacingOccurrences(of: " ", with: "")
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
        for (u, m) in units where parts.hasSuffix(u) { return Double(parts.dropLast(u.count)).map { Int64($0 * m) } }
        return Int64(parts)
    }

    public static func describe(_ rule: Rule) -> String {
        rule.conditions.map { c in
            switch c.field {
            case .name: return c.value
            case .ext: return "." + c.value
            case .from: return c.value
            case .size: return "over " + c.value
            }
        }.joined(separator: " + ")
    }

    public func decide(_ item: Item) async -> Decision {
        let settings = s
        if let rule = settings.rules.first(where: { Engine.matches($0, item) }) {
            return Decision(dest: rule.dest, tags: rule.tags, why: "rule \(Engine.describe(rule))", source: "metadata only")
        }
        if item.screenshot, settings.type(named: Shelf.screenshots) != nil {
            return Decision(dest: Shelf.screenshots, tags: [], why: "screenshot", source: "metadata only")
        }
        if let t = settings.type(forExt: item.ext) {
            return Decision(dest: t.name, tags: [], why: "extension", source: "metadata only")
        }
        guard settings.unknownFiles == .askModel, settings.appleIntelligence, classifier.available else {
            return Decision(dest: Shelf.unsorted, tags: [], why: "unknown type", source: "metadata only")
        }
        let options = Brain.options(settings)
        let creating = !item.ext.isEmpty && !item.isDir
        guard let pick = await classifier.choose(facts: Brain.facts(item), options: options, creating: creating) else {
            return Decision(dest: Shelf.unsorted, tags: [], why: "apple-intelligence failed", source: "from name")
        }
        if options.contains(where: { $0.0 == pick.folder }) {
            return Decision(dest: pick.folder, tags: [], why: "apple-intelligence \(pick.folder)", source: "from name",
                            learning: Learning(ext: item.ext, type: pick.folder))
        }
        let name = Brain.cleanName(pick.name)
        if creating, pick.folder == Brain.new, !name.isEmpty, !Brain.isCatchAll(name), !name.lowercased().contains(item.ext) {  // "Qx7 files" says nothing
            let existing = settings.types.first { $0.name.lowercased() == name.lowercased() }?.name ?? name
            return Decision(dest: existing, tags: [], why: "apple-intelligence new type \(existing)", source: "from name",
                            learning: Learning(ext: item.ext, type: existing, emoji: Brain.cleanEmoji(pick.emoji),
                                               description: String(pick.description.trimmingCharacters(in: .whitespaces).prefix(200))))
        }
        return Decision(dest: Shelf.unsorted, tags: [], why: "apple-intelligence unsure", source: "from name")
    }

    /// Remember the type for this extension, so the next file like it skips the model.
    func learn(_ l: Learning) {
        guard !l.ext.isEmpty else { return }
        store.update { s in
            if !s.learnedExts.contains(l.ext) { s.learnedExts.append(l.ext) }
            if let i = s.types.firstIndex(where: { $0.name == l.type }) {
                if !s.types[i].match.contains(l.ext) { s.types[i].match.append(l.ext) }
            } else {
                let at = s.types.firstIndex { $0.name == Shelf.unsorted } ?? s.types.endIndex
                s.types.insert(FileType(l.type, l.emoji, l.description, [l.ext], learned: true), at: at)
            }
        }
    }

    /// "Images" → <root>/My Shelves/Images. Absolute or ~ paths are used as-is.
    public func resolve(_ root: URL, _ dest: String) -> URL {
        let mine = root.appendingPathComponent(Library.mine)
        // A rule destination with ".." could climb out of My Shelves (or out of the path it names): park the file in Unsorted instead.
        if dest.split(separator: "/").contains(where: { $0 == ".." }) { return mine.appendingPathComponent(Shelf.unsorted) }
        if dest.hasPrefix("/") || dest.hasPrefix("~") { return URL(fileURLWithPath: (dest as NSString).expandingTildeInPath) }
        return dest.split(separator: "/").reduce(mine) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: Planning

    public func plan(all: Bool = false, trigger: String = "auto", now: Date = Date()) async -> Plan {
        let settings = s
        var (found, waiting) = candidates(all: all, now: now)
        var moves: [Planned] = []
        let dup = settings.duplicates ? Duplicates(engine: self) : nil
        found.sort { keeperOrder($0.0, $1.0, settings.keeper) }
        let knownTags = settings.tagging && settings.useExistingTags ? existingTags() : []
        let mayRead = !Engine.batteryLow()

        for (url, root, stage, fresh) in found {
            if stage == .recent {
                moves.append(Planned(item: Item(url: url, root: root), stage: .recent, dest: root.appendingPathComponent(Library.recents),
                                     shelf: Library.recents, why: "new", source: "metadata only"))
                continue
            }
            let item = Item.inspect(url, root: root)
            let d = await decide(item)
            var m = Planned(item: item, dest: resolve(root, d.dest), shelf: d.dest, tags: d.tags, why: d.why, source: d.source)
            m.learning = d.learning
            if settings.recents == .links && fresh { m.link = root.appendingPathComponent(Library.recents) }
            if let w = item.whereFrom.first { m.details["from"] = w }

            if let dup, !item.isDir, let kept = dup.match(item) {
                m.kind = .duplicate
                m.dest = resolve(root, Shelf.duplicates)
                m.shelf = Shelf.duplicates
                m.why = "duplicate of \(kept.lastPathComponent)"
                m.source = "size + hash"
                m.details["kept"] = kept.path
                m.details["size"] = String(item.size)
                m.tags = []
                m.link = nil
                m.learning = nil
                moves.append(m)
                continue
            }
            dup?.remember(item)

            let meaningless = settings.renaming && !item.isDir && Meaningless.check(item.stem, extra: settings.extraMeaningless, disabled: settings.disabledPatterns)
            if mayRead, meaningless || settings.tagging, let (text, source) = { () -> (String, String)? in reading(item.name, true); defer { reading(item.name, false) }; return Reader.text(url, shelf: d.dest) }() {
                let e = Reader.extract(text, source: source, host: item.fromHost)
                if meaningless, let name = Renamer.name(e, ext: item.url.pathExtension, separator: settings.separator, dateFormat: settings.dateFormat, parts: settings.nameParts) {
                    m.newName = name
                    m.source = source
                    m.details["pattern"] = Meaningless.label(item.stem) ?? "meaningless"
                }
                if let k = e.kind { m.details["kind"] = k }
                if let o = e.organization { m.details["organization"] = o }
                if let dt = e.date { m.details["date"] = ISO8601DateFormatter().string(from: dt) }
                if settings.tagging {
                    var t: [String] = []
                    if settings.tagKind, let k = e.kind { t.append(k) }
                    if settings.tagOrganization, let o = e.organization { t.append(o) }
                    t = t.map { tag in knownTags.first { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? tag }
                    m.tags += t.prefix(max(1, min(settings.tagsPerFile, 2)))
                    if m.newName == nil { m.source = source }
                }
            }
            moves.append(m)
        }

        // Mass renames and anything found by Sort everything wait for the review window.
        let renames = moves.filter { $0.newName != nil }.count
        if trigger == "sort-everything" || (settings.askBeforeMassRenames && renames > settings.massRenameThreshold) {
            for i in moves.indices where moves[i].newName != nil {
                moves[i].proposedName = moves[i].newName
                moves[i].newName = nil
            }
        }
        waiting.sort { $0.since > $1.since }
        return Plan(moves: moves, waiting: waiting)
    }

    func keeperOrder(_ a: URL, _ b: URL, _ k: Keeper) -> Bool {
        switch k {
        case .bestNamed: return Duplicates.nameScore(a.lastPathComponent) < Duplicates.nameScore(b.lastPathComponent)
        default:
            let ca = Stat.ctime(a) ?? 0, cb = Stat.ctime(b) ?? 0
            if abs(ca - cb) < 5 { return Duplicates.nameScore(a.lastPathComponent) < Duplicates.nameScore(b.lastPathComponent) }  // arrived together: the better name stays
            return ca < cb
        }
    }

    /// Tag names already in use on the user's files, reused before any new tag is made.
    public func existingTags() -> [String] { tagCounts().keys.sorted() }

    /// Tag name → how many files carry it (most used first when sorted by count); for the tag picker.
    public func tagCounts() -> [String: Int] {
        var tags: [String: Int] = [:]
        for root in s.activeRoots {
            let e = fm.enumerator(at: root, includingPropertiesForKeys: [.tagNamesKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var n = 0
            while let u = e?.nextObject() as? URL, n < 5000 {  // ponytail: bounded walk; read Finder's tag list if this misses tags
                n += 1
                if e!.level > 3 { e!.skipDescendants() }
                for t in Tags.read(u) { tags[t, default: 0] += 1 }
            }
        }
        tags[s.keepTag] = nil
        return tags
    }

    // MARK: Acting

    /// Nothing is created ahead of time: a watched folder gets My Shelves and Manual Shelves at its first sort
    /// (Manual Shelves is the one folder created before it's used, so the user sees their own space next to Kanso's).
    func ensureLibrary(for dest: URL) {
        guard let root = s.activeRoots.first(where: { dest.path.hasPrefix($0.appendingPathComponent(Library.mine).path) }) else { return }
        makeDir(root.appendingPathComponent(Library.mine))
        makeDir(root.appendingPathComponent(Library.manual))
    }

    func isDir(_ u: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }

    func icons() -> [String: String] {
        guard s.folderIcons else { return [:] }
        var out = Dictionary(s.types.map { ($0.name, $0.emoji) }, uniquingKeysWith: { a, _ in a })
        out[Library.mine] = "✨"; out[Library.manual] = "🏠"; out[Library.recents] = "🆕"; out[Shelf.duplicates] = "🪞"
        return out
    }

    /// mkdir -p, giving each folder Kanso creates its emoji icon.
    func makeDir(_ url: URL) {
        var missing: [URL] = []
        var p = url
        while !fm.fileExists(atPath: p.path) && p.path != "/" { missing.insert(p, at: 0); p = p.deletingLastPathComponent() }
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        let ic = icons()
        for m in missing { if let e = ic[m.lastPathComponent] { setIcon(m, e) } }
    }

    public static func unique(_ url: URL) -> URL {
        var u = url
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) || Stat.isSymlink(u) {
            u = url.deletingLastPathComponent().appendingPathComponent("\(stem) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        return u
    }

    /// Drop Recents symlinks older than recentDays or whose file is gone. Real files there are left alone.
    public func cleanRecents(now: Date = Date()) {
        for root in s.activeRoots {
            let d = root.appendingPathComponent(Library.recents)
            for name in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] {
                let p = d.appendingPathComponent(name)
                guard Stat.isSymlink(p) else { continue }
                let gone = !fm.fileExists(atPath: p.path)
                let old = now.timeIntervalSince1970 - (Stat.mtime(p) ?? 0) >= TimeInterval(s.recentDays * 86400)
                if gone || old { try? fm.removeItem(at: p) }
            }
        }
    }

    /// A file name Kanso is willing to create: one path component, nothing hidden, nothing the Finder shows as a path.
    public static func validName(_ n: String) -> Bool {
        !n.isEmpty && !n.contains("/") && !n.contains(":") && !n.contains("\0") && !n.hasPrefix(".") && n.utf8.count <= 255
    }

    static func log(_ message: String) { FileHandle.standardError.write(Data("kanso: \(message)\n".utf8)) }

    /// ADR 0002: a duplicate may only go to the Trash on its own if the keeper still holds the same bytes right now.
    func keeperStillHolds(_ keeper: String?, _ copy: URL) -> Bool {
        guard let keeper, !keeper.isEmpty else { return false }
        let k = URL(fileURLWithPath: keeper)
        guard Stat.isRegular(k), Stat.isRegular(copy), k.standardizedFileURL != copy.standardizedFileURL,
              !Placeholder.isPlaceholder(k), !Placeholder.isPlaceholder(copy) else { return false }
        let size = Stat.size(copy)
        guard size > 0, Stat.size(k) == size, let a = Duplicates.digest(k), let b = Duplicates.digest(copy) else { return false }
        return a == b
    }

    @discardableResult
    public func apply(_ moves: [Planned], trigger: String = "auto") -> [Action] {
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        var done: [Action] = []
        var proposals: [RenameProposal] = []
        var movedTo: [String: String] = [:]  // a keeper that moved earlier in this run
        for m in moves where m.include {
            let src = m.item.url
            // The plan may be old (review window): the file may be gone, replaced by a link, or tagged Keep since.
            guard Stat.exists(src), !Stat.isSymlink(src), !ignored(src) else { continue }
            var name = m.newName ?? m.item.name
            if !Engine.validName(name) { name = m.item.name }
            if m.dest.standardizedFileURL == src.deletingLastPathComponent().standardizedFileURL && name == m.item.name { continue }
            var dest = m.dest
            var shelf = m.shelf
            var why = m.why
            if m.kind == .duplicate && s.duplicatesToTrash {
                // The user chose "extra copies go to the Trash" (ADR 0002 amendment); journaled, one ⌘Z away.
                // Identical bytes are re-checked now: if the keeper changed or vanished, the copy is held on the shelf instead.
                let keeper = m.details["kept"].map { movedTo[$0] ?? $0 }
                if keeperStillHolds(keeper, src) {
                    var a = Action(run: run, kind: .duplicate, src: src.path, dst: "", root: m.item.root.path, shelf: "Trash", why: m.why + " · moved to Trash (your setting)", source: m.source)
                    a.trigger = trigger
                    a.details = m.details
                    if let keeper { a.details["kept"] = keeper }
                    guard let t = trashJournaled(src, &a) else { continue }
                    a.dst = t.path
                    store.append(a)
                    done.append(a)
                    continue
                }
                dest = resolve(m.item.root, Shelf.duplicates)
                shelf = Shelf.duplicates
                why = m.why + " · kept on the shelf (the other copy changed)"
                if dest.standardizedFileURL == src.deletingLastPathComponent().standardizedFileURL { continue }
            }
            ensureLibrary(for: dest)
            makeDir(dest)
            var dst = Engine.unique(dest.appendingPathComponent(name))
            var a = Action(run: run, kind: m.kind, src: src.path, dst: dst.path, root: m.item.root.path, shelf: shelf, why: why, source: m.source)
            a.trigger = trigger
            a.details = m.details
            if !m.item.isDir && a.details["size"] == nil { a.details["size"] = String(Stat.size(src)) }   // corrections check it later
            // Write-ahead: the origin is on disk before the file moves. A crash mid-move leaves a record undo can
            // handle (it skips entries whose dst is missing); a failed move discards it.
            store.append(a)
            do { try fm.moveItem(at: src, to: dst) } catch {
                // The new name may be what the volume refuses: keep the file's own name before giving up.
                guard name != m.item.name else { Engine.log("could not move \(src.path): \(error.localizedDescription)"); store.discard(a.id); continue }
                name = m.item.name
                dst = Engine.unique(dest.appendingPathComponent(name))
                a.dst = dst.path
                store.append(a)   // same id: replaces the first record
                do { try fm.moveItem(at: src, to: dst) } catch { Engine.log("could not move \(src.path): \(error.localizedDescription)"); store.discard(a.id); continue }
            }
            if let l = m.learning { learn(l) }
            if let k = a.details["kept"], let moved = movedTo[k] { a.details["kept"] = moved }
            movedTo[src.path] = dst.path
            let renamedNow = name != m.item.name
            if renamedNow {
                a.oldName = m.item.name
                if a.kind == .sorted { a.kind = .renamed }
                if s.keepOriginalSearchable { Renamer.keepOriginal(dst, m.item.name) }
            }
            a.pending = m.kind == .duplicate
            if let linkDir = m.link {
                makeDir(linkDir)
                let link = Engine.unique(linkDir.appendingPathComponent(dst.lastPathComponent))
                if (try? fm.createSymbolicLink(at: link, withDestinationURL: dst)) != nil { a.link = link.path }
            }
            if !m.tags.isEmpty {
                let before = Tags.read(dst)
                Tags.add(dst, m.tags)
                a.tags = Tags.read(dst).filter { !before.contains($0) }
            }
            if let p = m.proposedName, p != dst.lastPathComponent, Engine.validName(p) {
                proposals.append(RenameProposal(path: dst.path, newName: p, shelf: shelf, source: m.source, details: m.details))
            }
            store.append(a)
            done.append(a)
        }
        if !proposals.isEmpty {
            store.updatePending { p in
                let paths = Set(proposals.map(\.path))
                p.renames = p.renames.filter { !paths.contains($0.path) } + proposals
                p.renamesFound = Date()
            }
        }
        return done
    }

    /// Renames approved in the review window; one run, so one Undo reverts them all.
    @discardableResult
    public func applyRenames(_ proposals: [RenameProposal]) -> [Action] {
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        var done: [Action] = []
        for p in proposals {
            let src = URL(fileURLWithPath: p.path)
            guard Stat.exists(src), !Stat.isSymlink(src), Engine.validName(p.newName), p.newName != src.lastPathComponent else { continue }
            let dst = Engine.unique(src.deletingLastPathComponent().appendingPathComponent(p.newName))
            do { try fm.moveItem(at: src, to: dst) } catch { Engine.log("could not rename \(src.path): \(error.localizedDescription)"); continue }
            if s.keepOriginalSearchable { Renamer.keepOriginal(dst, src.lastPathComponent) }
            var a = Action(run: run, kind: .renamed, src: src.path, dst: dst.path, root: rootFor(src)?.path ?? "", shelf: p.shelf, why: "rename review", source: p.source)
            a.oldName = src.lastPathComponent
            a.trigger = "review"
            a.details = p.details
            if Stat.isRegular(dst) { a.details["size"] = String(Stat.size(dst)) }
            store.append(a)
            done.append(a)
        }
        let ids = Set(proposals.map(\.id))
        store.updatePending { $0.renames.removeAll { ids.contains($0.id) } }
        return done
    }

    public func dismissRenames(_ ids: Set<UUID>? = nil) {
        store.updatePending { p in if let ids { p.renames.removeAll { ids.contains($0.id) } } else { p.renames = [] } }
    }

    /// "Rename…": renames one file in place. Journaled as a rename, so Undo restores the old name.
    @discardableResult
    public func renameFile(_ id: UUID, to newName: String) -> Action? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = store.actions.first(where: { $0.id == id }), fm.fileExists(atPath: a.dst),
              Engine.validName(name), name != a.name else { return nil }
        let src = URL(fileURLWithPath: a.dst)
        let dst = Engine.unique(src.deletingLastPathComponent().appendingPathComponent(name))
        guard (try? fm.moveItem(at: src, to: dst)) != nil else { return nil }
        if s.keepOriginalSearchable { Renamer.keepOriginal(dst, a.oldName ?? src.lastPathComponent) }
        var r = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .renamed, src: src.path, dst: dst.path, root: a.root, shelf: a.shelf, why: "renamed by you", source: "you")
        r.oldName = src.lastPathComponent
        r.trigger = "menu"
        r.tags = a.tags
        if Stat.isRegular(dst) { r.details["size"] = String(Stat.size(dst)) }
        store.append(r)
        return r
    }

    func rootFor(_ url: URL) -> URL? { s.activeRoots.first { url.path.hasPrefix($0.path + "/") } }

    // MARK: Undo

    /// Undo the most recent run that still has something to undo. A run whose files are all gone is retired
    /// (marked undone) and the next older run is tried, so one vanished file never blocks Undo forever.
    @discardableResult
    public func undoLast() -> [Action] {
        var runs: [String] = []
        for a in store.actions.reversed() where !a.undone && !runs.contains(a.run) { runs.append(a.run) }
        for run in runs {
            let restored = undo(Set(store.actions.filter { $0.run == run && !$0.undone }.map(\.id)))
            if !restored.isEmpty { return restored }
        }
        return []
    }

    /// Put items back where they were (with their original names). Restored items get the keep tag so they stay put.
    /// If something else sits at the old path, the item comes back under a free name. An item that no longer exists
    /// anywhere is marked undone with a "gone" detail instead of staying in the list forever.
    @discardableResult
    public func undo(_ ids: Set<UUID>) -> [Action] {
        var restored: [Action] = []
        var gone = Set<UUID>()
        var relocated: [UUID: String] = [:]
        for a in store.actions.reversed() where ids.contains(a.id) && !a.undone {
            let dst = URL(fileURLWithPath: a.dst), src = URL(fileURLWithPath: a.src)
            if a.dst.isEmpty || !Stat.exists(dst) {   // empty dst: a write-ahead record whose move never finished
                gone.insert(a.id)
                if let l = a.link, Stat.isSymlink(URL(fileURLWithPath: l)) { try? fm.removeItem(atPath: l) }
                continue
            }
            let target = Stat.exists(src) ? Engine.unique(src) : src
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? fm.moveItem(at: dst, to: target)) != nil else { continue }
            if let l = a.link, Stat.isSymlink(URL(fileURLWithPath: l)) { try? fm.removeItem(atPath: l) }   // only now that the file is back
            if target != src { relocated[a.id] = target.path }
            if !a.tags.isEmpty { Tags.remove(target, a.tags) }
            if a.renamed, let old = a.oldName { Renamer.forgetOriginal(target, old) }
            if target.deletingLastPathComponent().lastPathComponent != Library.recents && a.kind != .trashed { Tags.add(target, [s.keepTag]) }
            restored.append(a)
        }
        let done = Set(restored.map(\.id))
        store.modify(done) { $0.undone = true; $0.pending = false }
        if !gone.isEmpty { store.modify(gone) { $0.undone = true; $0.pending = false; $0.details["gone"] = "true" } }
        for (id, path) in relocated { store.modify([id]) { $0.details["restoredTo"] = path } }
        // Putting back a trashed copy makes its duplicate decision pending again.
        let putBack = restored.filter { $0.kind == .trashed }.compactMap { $0.details["action"].flatMap(UUID.init) }
        if !putBack.isEmpty { store.modify(Set(putBack)) { $0.pending = true } }
        return restored
    }

    // MARK: Duplicates

    /// A held copy is only ever trashed if it is still the file Kanso journaled: a real file in this root's Duplicates
    /// shelf, the size it had when it was held.
    func isHeldCopy(_ a: Action) -> Bool {
        guard a.kind == .duplicate, a.pending, !a.undone, !a.root.isEmpty else { return false }
        let url = URL(fileURLWithPath: a.dst).standardizedFileURL
        let shelfDir = resolve(URL(fileURLWithPath: a.root), Shelf.duplicates).standardizedFileURL
        guard url.deletingLastPathComponent().path == shelfDir.path, Stat.isRegular(url),
              let journaled = a.details["size"].flatMap(Int64.init), Stat.size(url) == journaled else { return false }
        return true
    }

    /// Write-ahead trash: the origin is journaled before the file leaves (the Trash path isn't known until it has),
    /// so a crash mid-trash leaves a record. Undo skips entries with no dst; a failed trash discards the record.
    private func trashJournaled(_ url: URL, _ a: inout Action) -> URL? {
        store.append(a)
        var result: NSURL?
        guard (try? fm.trashItem(at: url, resultingItemURL: &result)) != nil, let t = result as URL? else { store.discard(a.id); return nil }
        return t
    }

    /// Move a held copy to the Trash. Only ever called from a user action.
    @discardableResult
    public func trash(_ id: UUID) -> Action? {
        guard let a = store.actions.first(where: { $0.id == id }), isHeldCopy(a) else { return nil }
        let url = URL(fileURLWithPath: a.dst)
        var tr = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .trashed, src: a.dst, dst: "", root: a.root, shelf: "Trash", why: "moved to Trash by you", source: "size + hash")
        tr.trigger = "menu"
        guard let t = trashJournaled(url, &tr) else { return nil }
        tr.dst = t.path
        tr.details = ["size": a.details["size"] ?? String(Stat.size(t)), "action": a.id.uuidString]
        store.append(tr)
        store.modify([id]) { $0.pending = false }
        return tr
    }

    /// Keep both copies: the extra copy leaves Duplicates for its normal shelf.
    @discardableResult
    public func keepBoth(_ id: UUID) -> Action? {
        guard let a = store.actions.first(where: { $0.id == id }) else { return nil }
        let url = URL(fileURLWithPath: a.dst), root = URL(fileURLWithPath: a.root)
        let shelf = s.type(forExt: url.pathExtension.lowercased())?.name ?? Shelf.unsorted
        let dest = resolve(root, shelf)
        makeDir(dest)
        let dst = Engine.unique(dest.appendingPathComponent(url.lastPathComponent))
        guard (try? fm.moveItem(at: url, to: dst)) != nil else { return nil }
        var k = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .sorted, src: a.dst, dst: dst.path, root: a.root, shelf: shelf, why: "kept both", source: "metadata only")
        k.trigger = "menu"
        store.append(k)
        store.modify([id]) { $0.pending = false }
        return k
    }

    public func duplicateFiles() -> [URL] {
        s.activeRoots.flatMap { root -> [URL] in
            let d = resolve(root, Shelf.duplicates)
            return ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { !$0.hasPrefix(".") && $0 != "Icon\r" }.map { d.appendingPathComponent($0) }
        }
    }

    public func duplicatesSize() -> Int64 { duplicateFiles().reduce(0) { $0 + Stat.size($1) } }

    /// "Move all to Trash": user-pressed only.
    @discardableResult
    public func trashAllDuplicates() -> Int {
        var n = 0
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        let pendingByPath = Dictionary(store.actions.filter { $0.kind == .duplicate && !$0.undone }.map { ($0.dst, $0.id) }, uniquingKeysWith: { _, b in b })
        for url in duplicateFiles() {
            let size = Stat.size(url)
            var tr = Action(run: run, kind: .trashed, src: url.path, dst: "", root: rootFor(url)?.path ?? "", shelf: "Trash", why: "moved to Trash by you", source: "size + hash")
            tr.trigger = "menu"
            guard let t = trashJournaled(url, &tr) else { continue }
            tr.dst = t.path
            tr.details = ["size": String(size)]
            if let id = pendingByPath[url.path] { tr.details["action"] = id.uuidString; store.modify([id]) { $0.pending = false } }
            store.append(tr)
            n += 1
        }
        return n
    }

    /// Opt-in: held copies nobody touched for autoTrashDays go to the Trash. Opening a copy resets its timer.
    @discardableResult
    public func expireDuplicates(now: Date = Date()) -> [Action] {
        guard s.duplicates, s.autoTrashDuplicates else { return [] }
        let limit = TimeInterval(max(1, s.autoTrashDays) * 86400)
        var out: [Action] = []
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        for a in store.actions where a.kind == .duplicate && a.pending && !a.undone && fm.fileExists(atPath: a.dst) {
            let url = URL(fileURLWithPath: a.dst)
            // ADR 0002: only while the copy is what was journaled and the keeper still has the same bytes.
            guard isHeldCopy(a), keeperStillHolds(a.details["kept"], url) else { continue }
            let opened = (try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            guard now.timeIntervalSince(max(a.ts, opened)) >= limit else { continue }
            var tr = Action(run: run, kind: .trashed, src: a.dst, dst: "", root: a.root, shelf: "Trash", why: "held \(s.autoTrashDays) days untouched (your setting)", source: "size + hash")
            guard let t = trashJournaled(url, &tr) else { continue }
            tr.dst = t.path
            tr.details = ["size": a.details["size"] ?? String(Stat.size(t)), "action": a.id.uuidString]
            store.append(tr)
            store.modify([a.id]) { $0.pending = false }
            out.append(tr)
        }
        return out
    }

    // MARK: Learning from corrections

    /// Files the user moved from one shelf to another teach Kanso; repeated moves become rule suggestions.
    public func detectCorrections(now: Date = Date()) {
        guard s.learnCorrections else { return }
        let recent = store.actions.filter { [.sorted, .renamed].contains($0.kind) && !$0.undone && $0.details["corrected"] == nil
            && now.timeIntervalSince($0.ts) < 30 * 86400 && !fm.fileExists(atPath: $0.dst) && !$0.root.isEmpty }
        var found: [UUID: Correction] = [:]
        for a in recent {
            let lib = URL(fileURLWithPath: a.root).appendingPathComponent(Library.mine)
            let journaled = a.details["size"].flatMap(Int64.init)
            for shelf in (try? fm.contentsOfDirectory(atPath: lib.path)) ?? [] where shelf != a.shelf && shelf != Shelf.duplicates {
                let there = lib.appendingPathComponent(shelf).appendingPathComponent(a.name)
                // Same name is not enough: a different file with the same name is not the one Kanso sorted.
                if fm.fileExists(atPath: there.path), journaled == nil || Stat.size(there) == journaled {
                    let host = a.details["from"].flatMap { URL(string: $0)?.host }
                    found[a.id] = Correction(name: a.name, ext: (a.name as NSString).pathExtension.lowercased(), from: host, fromShelf: a.shelf, toShelf: shelf)
                    break
                }
            }
        }
        guard !found.isEmpty else { return }
        store.modify(Set(found.keys)) { $0.details["corrected"] = found[$0.id]?.toShelf }
        for c in found.values { teach(c) }
        store.updatePending { p in
            p.corrections += found.values
            var groups: [String: (Condition, String, [String])] = [:]
            // A download source is a strong signal; an extension only when no type claims it (".pdf → Uni" would be wrong).
            let known = Set(store.settings.types.flatMap(\.match))
            for c in p.corrections {
                if let h = c.from { groups["from:\(h)>\(c.toShelf)", default: (Condition(.from, h), c.toShelf, [])].2.append(c.name) }
                else if !c.ext.isEmpty && !known.contains(c.ext) { groups["ext:\(c.ext)>\(c.toShelf)", default: (Condition(.ext, c.ext), c.toShelf, [])].2.append(c.name) }
            }
            for (key, g) in groups.sorted(by: { $0.key < $1.key }) where g.2.count >= 3 && !p.dismissed.contains(key)
                && !p.suggestions.contains(where: { $0.shelf == g.1 })
                && !store.settings.rules.contains(where: { $0.conditions == [g.0] && $0.dest == g.1 }) {
                p.suggestions.append(RuleSuggestion(condition: g.0, shelf: g.1, files: g.2))
            }
        }
    }

    /// Corrections teach types: a learned (or unknown) extension follows the user's move. Built-in types stay put,
    /// so moving one lecture PDF to "Uni" never sends every PDF there.
    func teach(_ c: Correction) {
        guard !c.ext.isEmpty, c.toShelf != Shelf.duplicates else { return }
        let current = s.type(forExt: c.ext)
        guard current == nil || current?.learned == true || s.learnedExts.contains(c.ext), current?.name != c.toShelf else { return }
        store.update { s in
            if !s.learnedExts.contains(c.ext) { s.learnedExts.append(c.ext) }
            for i in s.types.indices { s.types[i].match.removeAll { $0 == c.ext } }   // a learned extension lives on exactly one shelf
            s.types.removeAll { $0.learned && $0.match.isEmpty }
            if let i = s.types.firstIndex(where: { $0.name == c.toShelf }) {
                if !s.types[i].match.contains(c.ext) { s.types[i].match.append(c.ext) }
            } else {
                let at = s.types.firstIndex { $0.name == Shelf.unsorted } ?? s.types.endIndex
                s.types.insert(FileType(c.toShelf, "📁", "Learned from your moves", [c.ext], learned: true), at: at)
            }
        }
    }

    public func acceptSuggestion(_ id: UUID) {
        guard let sug = store.pending.suggestions.first(where: { $0.id == id }) else { return }
        store.update { $0.rules.insert(Rule([sug.condition], dest: sug.shelf), at: 0) }
        store.updatePending { $0.suggestions.removeAll { $0.id == id } }
    }

    public func dismissSuggestion(_ id: UUID) {
        guard let sug = store.pending.suggestions.first(where: { $0.id == id }) else { return }
        let key = "\(sug.condition.field.rawValue):\(sug.condition.value)>\(sug.shelf)"
        store.updatePending { $0.suggestions.removeAll { $0.id == id }; $0.dismissed.append(key) }
    }

    // MARK: Moving between shelves

    /// "Move to another shelf…": the move is journaled, and it counts as a correction.
    @discardableResult
    public func move(_ id: UUID, to shelf: String) -> Action? {
        guard let a = store.actions.first(where: { $0.id == id }), fm.fileExists(atPath: a.dst) else { return nil }
        let dest = resolve(URL(fileURLWithPath: a.root), shelf)
        makeDir(dest)
        let dst = Engine.unique(dest.appendingPathComponent(a.name))
        guard (try? fm.moveItem(atPath: a.dst, toPath: dst.path)) != nil else { return nil }
        var m = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .sorted, src: a.dst, dst: dst.path, root: a.root, shelf: shelf, why: "moved by you", source: "you")
        m.trigger = "menu"
        if Stat.isRegular(dst) { m.details["size"] = String(Stat.size(dst)) }
        store.append(m)
        let c = Correction(name: a.name, ext: (a.name as NSString).pathExtension.lowercased(), from: a.details["from"].flatMap { URL(string: $0)?.host }, fromShelf: a.shelf, toShelf: shelf)
        store.updatePending { $0.corrections.append(c) }
        teach(c)
        return m
    }
}

/// Size first, then SHA-256; no model.
final class Duplicates {
    let engine: Engine
    var bySize: [String: [Int64: [URL]]] = [:]  // root → size → files
    var hashes: [String: Digest] = [:]
    typealias Digest = SHA256.Digest

    init(engine: Engine) { self.engine = engine }

    func index(_ root: URL) -> [Int64: [URL]] {
        if let i = bySize[root.path] { return i }
        var i: [Int64: [URL]] = [:]
        let s = engine.store.settings
        var dirs = [root.appendingPathComponent(Library.mine)]
        if s.checkManualShelves { dirs.append(root.appendingPathComponent(Library.manual)) }
        for d in dirs {
            let e = FileManager.default.enumerator(at: d, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if u.lastPathComponent == Shelf.duplicates { e?.skipDescendants(); continue }
                let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true, let sz = v?.fileSize, sz > 0, !Placeholder.isPlaceholder(u) { i[Int64(sz), default: []].append(u) }
            }
        }
        bySize[root.path] = i
        return i
    }

    func hash(_ url: URL) -> Digest? {
        if let h = hashes[url.path] { return h }
        guard let d = Duplicates.digest(url) else { return nil }
        hashes[url.path] = d
        return d
    }

    /// SHA-256 of a regular file that is really on this Mac: never through a link, never a download of an iCloud placeholder.
    static func digest(_ url: URL) -> Digest? {
        guard Stat.isRegular(url), !Placeholder.isPlaceholder(url), let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize()
    }

    /// The file this item duplicates, if any.
    func match(_ item: Item) -> URL? {
        guard item.size > 0 else { return nil }
        let same = index(item.root)[item.size] ?? []
        guard !same.isEmpty, let h = hash(item.url) else { return nil }
        return same.first { $0 != item.url && hash($0) == h }
    }

    /// A file kept in this run counts for the files after it (two loose copies: the keeper stays, the other is held).
    func remember(_ item: Item) {
        guard item.size > 0 else { return }
        _ = index(item.root)
        bySize[item.root.path]![item.size, default: []].append(item.url)
    }

    /// Lower is better: "invoice.pdf" beats "invoice (1).pdf" and "invoice copy.pdf".
    static func nameScore(_ n: String) -> Int {
        var s = 0
        if n.range(of: #"\(\d+\)|\bcopy\b|kopia|kopie| \d+\.\w+$"#, options: [.regularExpression, .caseInsensitive]) != nil { s += 10 }
        return s + n.count / 20
    }
}
