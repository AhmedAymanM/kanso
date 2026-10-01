import KansoCore
import QuickLookThumbnailing
import SwiftUI

/// A row in Activity: something pending, one action, a batch (one run of many sorts), or a file still downloading.
enum Entry: Identifiable {
    case need(Need)
    case action(Action)
    case batch(String, [Action])
    case waiting(Waiting)

    var id: String {
        switch self {
        case .need(let n): return n.id
        case .action(let a): return a.id.uuidString
        case .batch(let r, _): return "run-" + r
        case .waiting(let w): return "wait-" + w.id
        }
    }
    var ts: Date {
        switch self {
        case .need(let n): return n.ts
        case .action(let a): return a.ts
        case .batch(_, let a): return a.first?.ts ?? Date()
        case .waiting(let w): return w.since
        }
    }
}

enum Filter: String, CaseIterable { case all = "All", needs = "Needs you", renamed = "Renamed", duplicates = "Duplicates" }

struct ActivityPage: View {
    @EnvironmentObject var m: AppModel
    @State private var filter = Filter.all
    @State private var query = ""

    var entries: [Entry] {
        var done: [Entry] = []
        let visible = m.actions.filter { !$0.pending || $0.kind != .duplicate || $0.undone }
        let runs = Dictionary(grouping: visible, by: \.run)
        var seen = Set<String>()
        for a in visible.reversed() {
            if a.kind == .duplicate && a.pending && !a.undone { continue }
            let run = runs[a.run] ?? []
            if run.count >= 5 && run.allSatisfy({ $0.kind == .sorted || $0.kind == .renamed }) {
                if seen.insert(a.run).inserted { done.append(.batch(a.run, run)) }
            } else {
                done.append(.action(a))
            }
        }
        let waits = m.waiting.map { Entry.waiting($0) }
        return filtered(m.needs.map { .need($0) }) + filtered(waits + done)
    }

    func filtered(_ e: [Entry]) -> [Entry] {
        e.filter { entry in
            let passes: Bool
            switch (filter, entry) {
            case (.all, _): passes = true
            case (.needs, .need): passes = true
            case (.renamed, .action(let a)): passes = a.kind == .renamed
            case (.renamed, .need(.renames)): passes = true
            case (.duplicates, .action(let a)): passes = a.kind == .duplicate || a.kind == .trashed
            case (.duplicates, .need(.duplicate)): passes = true
            default: passes = false
            }
            return passes && (query.isEmpty || title(entry).localizedCaseInsensitiveContains(query) || subtitle(entry).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let list = entries
        let selected = list.first { $0.id == m.selectedActivity } ?? list.first
        HStack(spacing: 0) {
            listColumn(list, selected: selected?.id).frame(width: 260)
            Rectangle().fill(K.separator).frame(width: 0.75)
            if let selected {
                EntryDetail(entry: selected, next: next(after: selected, in: list)).id(selected.id)
                    .transition(.opacity.combined(with: .offset(x: 12)))
            } else {
                VStack(spacing: 8) {
                    Text("Nothing yet").font(.system(size: 22, design: .serif)).foregroundStyle(K.text)
                    Text("Everything Kanso does shows up here, with Undo.").font(.system(size: 12.5)).foregroundStyle(K.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func next(after e: Entry, in list: [Entry]) -> Entry? {
        guard let i = list.firstIndex(where: { $0.id == e.id }), i + 1 < list.count else { return nil }
        if case .need = e, case .need = list[i + 1] { return list[i + 1] }
        return nil
    }

    /// One scroll view from the top edge down, so rows slide under the toolbar title behind the soft glass edge.
    func listColumn(_ list: [Entry], selected: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(m.actions.filter { $0.kind != .trashed }.count) actions · \(m.needs.count) need you").font(.system(size: 12)).foregroundStyle(K.text2)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(K.text2)
                    TextField("Search files and shelves", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
                }
                .padding(.horizontal, 10).frame(height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(K.fill))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Button { withAnimation(Motion.spring(0.3)) { filter = f } } label: {
                                Text(f.rawValue).font(.system(size: 11.5, weight: .medium)).foregroundStyle(filter == f ? Tint.accent.fg : K.text2)
                                    .padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(filter == f ? Tint.accent.bg : K.fill))
                                    .overlay(Capsule().strokeBorder(filter == f ? Tint.accent.stroke : .clear, lineWidth: 0.75))
                            }
                            .buttonStyle(PlainRowStyle())
                        }
                    }
                }
                LazyVStack(alignment: .leading, spacing: 4) {
                    let groups = group(list)
                    ForEach(groups, id: \.0) { g in
                        HStack {
                            Text(g.0).eyebrow()
                            Spacer()
                            if g.0 == "Needs you" { Text("pinned").font(.system(size: 10)).foregroundStyle(K.text3) }
                        }
                        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(g.1) { e in ListRow(entry: e, selected: e.id == selected).onTapGesture { withAnimation(Motion.spring(0.25)) { m.selectedActivity = e.id } } }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 8).padding(.horizontal, 12)
        }
        .softTopEdge()
    }

    func group(_ list: [Entry]) -> [(String, [Entry])] {
        var out: [(String, [Entry])] = []
        func add(_ k: String, _ e: Entry) { if out.last?.0 == k { out[out.count - 1].1.append(e) } else { out.append((k, [e])) } }
        let cal = Calendar.current
        for e in list {
            if case .need = e { add("Needs you", e); continue }
            add(cal.isDateInToday(e.ts) ? "Today" : cal.isDateInYesterday(e.ts) ? "Yesterday" : e.ts.formatted(.dateTime.month(.wide).day()), e)
        }
        return out
    }
}

func title(_ e: Entry) -> String {
    switch e {
    case .need(.duplicate(let a)): return a.name
    case .need(.renames(let p, _)): return "\(p.count) files can be renamed"
    case .need(.rule(let r)): return r.files.first ?? "Rule suggestion"
    case .action(let a): return a.kind == .trashed ? a.srcName : a.name
    case .batch(_, let a): return "\((a.first?.root as NSString?)?.lastPathComponent ?? "Folder") tidied"
    case .waiting(let w): return w.partial ? w.url.deletingPathExtension().lastPathComponent : w.url.lastPathComponent
    }
}

func subtitle(_ e: Entry) -> String {
    switch e {
    case .need(.duplicate): return "Duplicate · trash or keep?"
    case .need(.renames): return "Rename review · nothing changed yet"
    case .need(.rule(let r)): return "Rule suggestion · \(r.files.count) moved to \(r.shelf)"
    case .action(let a):
        if a.undone { return "Undone · " + summary(a).lowercased() }
        switch a.kind {
        case .renamed: return "Renamed from \(a.oldName ?? "")" + (a.tags.isEmpty ? "" : " · tagged")
        case .duplicate: return "Copy kept in Duplicates"
        case .trashed: return "Moved to Trash · \((Int64(a.details["size"] ?? "") ?? 0).bytes)"
        case .sorted: return "Sorted to \(a.shelf)" + (a.tags.isEmpty ? "" : " · tagged")
        }
    case .batch(_, let a): return "\(a.count) files to shelves"
    case .waiting(let w): return w.partial ? "Waiting · still downloading" : "Waiting · settling"
    }
}

struct ListRow: View {
    @EnvironmentObject var m: AppModel
    var entry: Entry
    var selected: Bool

    var tint: Tint {
        switch entry {
        case .need(let n): return n.tint
        case .action(let a): return a.kind == .renamed ? .rename : .neutral
        default: return .neutral
        }
    }
    var pending: Bool { if case .need = entry { return true }; return false }
    var emoji: String {
        switch entry {
        case .need(.duplicate): return "🪞"
        case .need(.renames): return "✏️"
        case .need(.rule(let r)): return m.settings.emoji(for: r.shelf)
        case .action(let a): return a.kind == .trashed ? "🗑️" : a.kind == .duplicate ? "🪞" : m.settings.emoji(for: a.shelf)
        case .batch(_, let a): return folderEmoji(a.first?.root ?? "")
        case .waiting: return "⏳"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EmojiTile(emoji: emoji, fill: pending ? K.cardSoft : K.fill)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title(entry)).font(.system(size: 12, weight: .semibold)).foregroundStyle(K.text).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(entry.ts.listTime).font(.system(size: 10)).foregroundStyle(K.text3)
                }
                Text(subtitle(entry)).font(.system(size: 11)).foregroundStyle(pending ? tint.fg : K.text2).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(pending ? tint.bg : (selected ? K.fillStrong : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? tint.stroke : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: Detail

struct EntryDetail: View {
    @EnvironmentObject var m: AppModel
    var entry: Entry
    var next: Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        chip
                        // The shelf a sorted file landed on: click it to move the file (and teach Kanso).
                        if case .action(let a) = entry, a.kind == .sorted, !a.undone {
                            MenuPicker(options: shelfOptions(a.shelf), value: Binding(get: { a.shelf }, set: { if $0 != a.shelf { m.move(a.id, to: $0) } }),
                                       emoji: { m.settings.emoji(for: $0) })
                                .help("Move to another shelf")
                        }
                        Spacer()
                        Text(meta).font(.system(size: 11)).foregroundStyle(K.text3)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline).font(.system(size: 22, weight: .bold)).foregroundStyle(K.text).lineLimit(2)
                        Text(sub).font(.system(size: 13)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    visual
                    decided
                }
                .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
            }
            .softTopEdge()
            .defaultScrollAnchor(ProcessInfo.processInfo.environment["KANSO_SCROLL"] == "bottom" ? .bottom : .top)   // screenshots of the scrolled state
            Rectangle().fill(K.separator).frame(height: 0.75).padding(.horizontal, 28)
            actionBar.padding(.horizontal, 28).padding(.vertical, 14)
        }
    }

    func shelfOptions(_ current: String) -> [(String, String)] {
        var o = m.settings.types.map { ($0.name, $0.name) }
        if !o.contains(where: { $0.0 == current }) { o.insert((current, current), at: 0) }
        return o
    }

    var chip: some View {
        switch entry {
        case .need(let n): return Chip(icon: n.icon, text: "\(n.label) · needs you", tint: n.tint)
        case .action(let a):
            switch a.kind {
            case .renamed: return Chip(icon: "pencil.line", text: a.tags.isEmpty ? "Renamed" : "Renamed · tagged", tint: .rename)
            case .duplicate: return Chip(icon: "doc.on.doc", text: "Duplicate", tint: .duplicate)
            case .trashed: return Chip(icon: "trash", text: "Moved to Trash", tint: .neutral)
            case .sorted: return Chip(icon: "square.3.layers.3d", text: a.undone ? "Sorted · undone" : "Sorted", tint: .neutral)
            }
        case .batch: return Chip(icon: "display", text: "Batch", tint: .neutral)
        case .waiting: return Chip(icon: "hourglass", text: "Waiting", tint: .neutral)
        }
    }

    var meta: String {
        let when = (Calendar.current.isDateInToday(entry.ts) ? "Today" : entry.ts.formatted(.dateTime.month(.abbreviated).day())) + ", " + entry.ts.clock
        var parts = [when]
        func root(_ r: String) { if !r.isEmpty { parts.append("\(folderEmoji(r)) \((r as NSString).lastPathComponent)") } }
        switch entry {
        case .need(.duplicate(let a)), .action(let a): root(a.root); if let h = a.details["from"].flatMap({ URL(string: $0)?.host }) { parts.append("from \(h)") }
        case .batch(_, let a): root(a.first?.root ?? "")
        case .waiting(let w): root(w.root.path)
        default: break
        }
        return parts.joined(separator: " · ")
    }

    var headline: String {
        switch entry {
        case .need(.duplicate(let a)): return "Already have \(((a.details["kept"] ?? "") as NSString).lastPathComponent)"
        case .need(.renames(let p, _)): return "\(p.count) files can be renamed"
        case .need(.rule(let r)): return "You moved \(r.files.count) files to \(r.shelf)"
        case .action(let a): return a.kind == .trashed ? (a.details["installer"].map { "Installed \($0)" } ?? "\(a.srcName) is in the Trash") : a.name
        case .batch(_, let a): return "\((a.first?.root as NSString?)?.lastPathComponent ?? "Folder") tidied · \(a.count) files moved"
        case .waiting(let w): return "\(title(entry)) is still \(w.partial ? "downloading" : "changing")"
        }
    }

    var sub: String {
        switch entry {
        case .need(.duplicate): return "The copy was moved to 🪞 Duplicates. Nothing was deleted."
        case .need(.renames): return "Files with meaningless names. Nothing changes until you review."
        case .need(.rule): return "Make it a rule so Kanso does it next time?"
        case .action(let a):
            if a.undone { return "Undone. The file is back where it was." }
            switch a.kind {
            case .renamed: return "Renamed from \(a.oldName ?? "") and filed in \(m.settings.emoji(for: a.shelf)) \(a.shelf). The original name stays searchable."
            case .duplicate: return "The copy was moved to 🪞 Duplicates. Nothing was deleted."
            case .trashed: return a.details["installer"] != nil ? "\(a.details["installer"]!) is installed, so Smart Eject ejected the disk image and moved the installer to the Trash. Put Back any time." : "Moved to the Trash. Put Back returns it."
            case .sorted:
                return a.source == "you" ? "You moved it to \(m.settings.emoji(for: a.shelf)) \(a.shelf). Kanso learns from moves like this."
                    : "Sorted by kind into \(m.settings.emoji(for: a.shelf)) \(a.shelf). " + (a.why.hasPrefix("apple-intelligence") ? "Apple Intelligence picked the shelf from the name, on this Mac." : a.why.hasPrefix("rule") ? "One of your rules matched." : "Kanso only looked at the name and file type.")
            }
        case .batch: return "One action, so one Undo puts them all back where they were."
        case .waiting: return "Kanso never moves a file that is still changing. It will be sorted when it's done."
        }
    }

    @ViewBuilder var visual: some View {
        switch entry {
        case .need(.duplicate(let a)), .action(let a) where a.kind == .duplicate:
            HStack(spacing: 14) {
                previewCard(path: a.details["kept"] ?? "", label: "Kept", meta: "\(shelfName(a.details["kept"] ?? "")) · \(sizeOf(a.details["kept"] ?? ""))", tint: nil)
                Text("=").font(.system(size: 18)).foregroundStyle(K.text3)
                previewCard(path: a.dst, label: "Extra copy", meta: "🪞 Duplicates · added \(a.ts.relative) · \((Int64(a.details["size"] ?? "") ?? 0).bytes)", tint: .duplicate)
            }
        case .need(.renames(let p, _)):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(p.prefix(4)) { r in diff(r.name, r.newName) }
                if p.count > 4 { Text("+ \(p.count - 4) more in the review window").font(.system(size: 11)).foregroundStyle(K.text2) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rename.bg))
        case .need(.rule(let r)):
            VStack(alignment: .leading, spacing: 10) {
                RulePreview(condition: r.condition, shelf: r.shelf, emoji: m.settings.emoji(for: r.shelf))
                Text("Matched: " + r.files.prefix(5).joined(separator: ", ") + (r.files.count > 5 ? " and \(r.files.count - 5) more" : "")).font(.system(size: 11.5)).foregroundStyle(K.text2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rule.bg))
        case .action(let a) where a.kind == .renamed:
            HStack(spacing: 16) {
                Thumb(path: a.dst).frame(width: 72, height: 94)
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.oldName ?? "").font(.system(size: 12.5)).foregroundStyle(K.text3).strikethrough()
                    Text(a.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(K.text)
                    if !a.tags.isEmpty { HStack { ForEach(a.tags, id: \.self) { TagPill(name: $0) } } }
                }
                Spacer()
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rename.bg))
        case .action:
            EmptyView()   // a plain sort or a trash record needs no picture: the headline says it
        case .batch(_, let actions):
            let counts = Dictionary(grouping: actions, by: \.shelf).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            let mx = counts.first?.1 ?? 1
            VStack(spacing: 10) {
                ForEach(counts, id: \.0) { c in
                    HStack {
                        Text("\(m.settings.emoji(for: c.0)) \(c.0)").font(.system(size: 12)).foregroundStyle(K.text).frame(width: 150, alignment: .leading)
                        ProgressBar(value: Double(c.1) / Double(mx))
                        Text("\(c.1)").font(.system(size: 11)).foregroundStyle(K.text2).frame(width: 28, alignment: .trailing)
                    }
                }
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(K.neutralBg))
        case .waiting:
            EmptyView()
        }
    }

    func diff(_ a: String, _ b: String) -> some View {
        HStack(spacing: 10) {
            Text(a).font(.system(size: 12)).foregroundStyle(K.text3).frame(width: 170, alignment: .leading).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Tint.rename.fg)
            Text(b).font(.system(size: 12, weight: .medium)).foregroundStyle(K.text).lineLimit(1)
        }
    }

    func previewCard(path: String, label: String, meta: String, tint: Tint?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(path: path).frame(maxWidth: .infinity).frame(height: 130).background(RoundedRectangle(cornerRadius: 8).fill(tint?.soft ?? K.fill))
            Text(label).eyebrow().foregroundStyle(tint?.fg ?? K.text3)
            Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundStyle(K.text).lineLimit(1)
            Text(meta).font(.system(size: 11)).foregroundStyle(K.text2).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint?.bg ?? K.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(K.separator, lineWidth: 0.75))
    }

    func shelfName(_ path: String) -> String {
        let s = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return "\(m.settings.emoji(for: s)) \(s)"
    }

    func sizeOf(_ path: String) -> String { Stat.size(URL(fileURLWithPath: path)).bytes }

    func pathParts(_ a: Action) -> [String] {
        let root = (a.root as NSString).lastPathComponent
        guard a.dst.hasPrefix(a.root + "/") else { return [a.dst] }
        let rel = String(a.dst.dropFirst(a.root.count + 1)).split(separator: "/").dropLast().map(String.init)
        return ["\(folderEmoji(a.root)) \(root)"] + rel.map { "\(m.settings.emoji(for: $0)) \($0)" }
    }

    // "How Kanso decided"
    var rows: [(String, String, String, String)] {
        switch entry {
        case .need(.duplicate(let a)), .action(let a) where a.kind == .duplicate:
            let size = Int64(a.details["size"] ?? "") ?? 0
            return [("ruler", "Same size", "\(size.formatted()) bytes", "metadata only"),
                    ("touchid", "Same content hash", "Identical, byte for byte", "metadata only"),
                    ("checkmark.shield", "Kept the \(m.settings.keeper == .bestNamed ? "better-named" : "older") copy", "Already on a shelf", "metadata only")]
        case .need(.renames(let p, _)):
            let g = Dictionary(grouping: p) { Meaningless.label(($0.name as NSString).deletingPathExtension) ?? "Other" }
            return g.sorted { $0.value.count > $1.value.count }.map { k, v in
                let icon = k.hasPrefix("Scan") ? "viewfinder" : k.hasPrefix("IMG") ? "camera" : k.hasPrefix("download") ? "arrow.down.to.line" : "textformat"
                let name = k.hasPrefix("Scan") ? "Scanner names" : k.hasPrefix("IMG") ? "Camera names" : k.hasPrefix("download") ? "Download names" : "\(k) names"
                return (icon, name, v.prefix(2).map(\.name).joined(separator: ", ") + (v.count > 2 ? " …" : ""), "\(v.count) files")
            }
        case .need(.rule(let r)):
            return [("arrow.triangle.branch", "Pattern", conditionText(r.condition), "\(r.files.count) moves"), ("folder", "Shelf", "\(m.settings.emoji(for: r.shelf)) \(r.shelf)", "your moves")]
        case .action(let a) where a.kind == .renamed:
            var out: [(String, String, String, String)] = []
            if let k = a.details["kind"] { out.append(("doc.text", "Kind", k, a.source)) }
            if let o = a.details["organization"] { out.append(("building.2", "Organization", o, a.source)) }
            if let d = a.details["date"].flatMap({ ISO8601DateFormatter().date(from: $0) }) { out.append(("calendar", "Date", d.formatted(.dateTime.month(.wide).year()), a.source)) }
            if !a.tags.isEmpty { out.append(("tag", "Finder tags", a.tags.joined(separator: " · "), "from the rename")) }
            return out
        case .action(let a):
            let ext = (a.name as NSString).pathExtension.uppercased()
            var out = [("textformat", "Name", a.srcName, "from name"), ("doc", "Type", ext.isEmpty ? "No extension" : "\(ext) file", "metadata")]
            if a.why.hasPrefix("rule") { out.append(("line.3.horizontal.decrease", "Rule", String(a.why.dropFirst(5)), "your rule")) }
            if a.why == "screenshot" { out.append(("camera.viewfinder", "Screen capture", "Taken on this Mac", "metadata")) }
            if a.why.hasPrefix("apple-intelligence") { out.append(("sparkles", "Apple Intelligence", a.why.replacingOccurrences(of: "apple-intelligence ", with: ""), "on this Mac")) }
            out.append(("folder", "Shelf", "\(m.settings.emoji(for: a.shelf)) \(a.shelf)", a.source == "you" ? "you" : "By kind"))
            return out
        case .batch(_, let a):
            return [("square.3.layers.3d", "Approach", "By kind", "metadata only"), ("cursorarrow.click", "Triggered by", trigger(a.first?.trigger ?? "auto"), a.first?.trigger == "auto" ? "automatic" : "from the menu bar")]
        case .waiting(let w):
            return [("hourglass", "Status", w.size.bytes + " so far", "live"), ("folder", "Will go to", w.shelf.map { "\(m.settings.emoji(for: $0)) \($0)" } ?? "Decided when it's done", "By kind"),
                    ("checkmark.shield", "Rule", "Partial downloads are never moved", "always")]
        }
    }

    func trigger(_ t: String) -> String {
        switch t {
        case "menu": return "Sort New Files Now"
        case "sort-everything": return "Sort everything"
        case "review": return "Review window"
        default: return "Auto-Sort"
        }
    }

    var decided: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text({ if case .need(.duplicate) = entry { return "How Kanso knew" }; return "How Kanso decided" }()).font(.system(size: 13, weight: .semibold)).foregroundStyle(K.text)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    // Title over value, source on the right: fits the narrow detail column without truncating.
                    HStack(spacing: 12) {
                        Image(systemName: r.0).font(.system(size: 12)).foregroundStyle(K.text2).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.1).font(.system(size: 12.5, weight: .medium)).foregroundStyle(K.text)
                            Text(r.2).font(.system(size: 12)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(r.3).font(.system(size: 10.5)).foregroundStyle(r.3.hasPrefix("contents") ? Tint.rename.fg : K.text3).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    if i < rows.count - 1 { Rectangle().fill(K.separator).frame(height: 0.75) }
                }
            }
            .card()
        }
    }

    var dotColor: Color {
        switch entry {
        case .need(let n): return n.tint.fg
        case .action(let a) where a.kind == .renamed: return Tint.rename.fg
        default: return K.accent
        }
    }

    @ViewBuilder var actionBar: some View {
        HStack(spacing: 8) {
            switch entry {
            case .need(.duplicate(let a)):
                Button { m.trash(a.id) } label: { HStack { Text("Move to Trash"); Hint(text: "⌘⌫") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut(.delete, modifiers: .command)
                Button("Keep both") { m.keepBoth(a.id) }.buttonStyle(SecondaryStyle())
                Button { m.undo([a.id]) } label: { HStack { Text("Undo"); Text("⌘Z").font(.system(size: 10.5)).foregroundStyle(K.text3) } }.buttonStyle(SecondaryStyle()).keyboardShortcut("z")
            case .need(.renames(let p, _)):
                Button { Windows.shared.showReview(tab: .renames) } label: { HStack { Text("Review \(p.count) files…"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .rename)).keyboardShortcut(.defaultAction)
                Button("Not now") { m.dismissRenames() }.buttonStyle(SecondaryStyle())
            case .need(.rule(let r)):
                Button { m.acceptSuggestion(r.id) } label: { HStack { Text("Create rule"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .rule)).keyboardShortcut(.defaultAction)
                Button("Edit…") { m.acceptSuggestion(r.id); Windows.shared.showMain(.sorting) }.buttonStyle(SecondaryStyle())
                Button("No thanks") { m.dismissSuggestion(r.id) }.buttonStyle(SecondaryStyle())
            case .action(let a):
                if a.undone {
                    Button("Show in Finder") { m.reveal(a.src) }.buttonStyle(SecondaryStyle())
                } else if a.kind == .trashed {
                    Button { m.undo([a.id]) } label: { HStack { Text("Put Back"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle()).keyboardShortcut("z")
                } else {
                    Button { m.undo([a.id]) } label: { HStack { Text(a.kind == .renamed ? "Undo rename" : "Undo"); Hint(text: "⌘Z") } }
                        .buttonStyle(PrimaryStyle(tint: a.kind == .renamed ? .rename : .accent)).keyboardShortcut("z")
                    Button("Show in Finder") { m.reveal(a.dst) }.buttonStyle(SecondaryStyle())
                }
            case .batch(let run, let a):
                Button { m.undoRun(run) } label: { HStack { Text("Undo all \(a.filter { !$0.undone }.count)"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle()).keyboardShortcut("z")
                    .disabled(a.allSatisfy(\.undone))
                Button("Show in Finder") { m.reveal(URL(fileURLWithPath: a.first?.root ?? "").appendingPathComponent(Library.mine).path) }.buttonStyle(SecondaryStyle())
            case .waiting(let w):
                Button("Don't sort this file") { m.keep(w.url) }.buttonStyle(SecondaryStyle())
                Button("Show in Finder") { m.reveal(w.url.path) }.buttonStyle(SecondaryStyle())
            }
            Spacer()
            if case .action(let a) = entry, a.kind == .renamed, !a.undone {
                Button("Don't rename files like this") {
                    if let p = Meaningless.label(((a.oldName ?? "") as NSString).deletingPathExtension) { m.update { $0.disabledPatterns.append(p) } }
                    m.undo([a.id])
                }
                .buttonStyle(LinkStyle(color: K.text2))
            } else if let next {
                Button("Next: \(nextLabel(next)) ↓") { m.selectedActivity = next.id }.buttonStyle(LinkStyle(color: K.text2)).keyboardShortcut(.downArrow, modifiers: [])
            }
        }
    }

    func nextLabel(_ e: Entry) -> String { if case .need(let n) = e { return n.label.lowercased().capitalizedFirst }; return "next" }
}

extension String { var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() } }
extension Date { var seconds: String { formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) } }

struct PathChips: View {
    var parts: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                Text(p).font(.system(size: 12, weight: .medium)).foregroundStyle(K.text)
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(K.card))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(i == parts.count - 1 ? K.accent : K.separator, lineWidth: i == parts.count - 1 ? 1 : 0.75))
                if i < parts.count - 1 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(K.text3) }
            }
        }
    }
}

/// Quick Look thumbnail of a file (rendered by the system; Kanso keeps nothing).
struct Thumb: View {
    var path: String
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 4)).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit).padding(12)
            }
        }
        .task(id: path) {
            let req = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 240, height: 240), scale: 2, representationTypes: .thumbnail)
            if let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { image = r.nsImage }
        }
    }
}
