import KansoCore
import QuickLookThumbnailing
import Quartz
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

enum Filter: String, CaseIterable {
    case all = "All", needs = "Needs you", handled = "Handled", renamed = "Renamed", tagged = "Tagged", duplicates = "Duplicates", ejected = "Smart Eject", undone = "Undone"
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .needs: return "exclamationmark.circle"
        case .handled: return "checkmark.circle"
        case .renamed: return "pencil"
        case .tagged: return "tag"
        case .duplicates: return "doc.on.doc"
        case .ejected: return "eject"
        case .undone: return "arrow.uturn.backward"
        }
    }
    var emptyLine: String {
        switch self {
        case .all: return "Everything Kanso does shows up here, with Undo."
        case .needs: return "Nothing needs you. Duplicates and rename suggestions appear here first."
        case .handled: return "Nothing handled yet. Sorted files, renames and Trash moves show up here, with Undo."
        case .renamed: return "No renamed files yet. Kanso renames only meaningless names, like Scan_0012."
        case .tagged: return "No tagged files yet. Turn on Tagging to add Finder tags from a file's first page."
        case .duplicates: return "No duplicates. Extra copies wait on the Duplicates shelf when they show up."
        case .ejected: return "No installers ejected yet. Smart Eject waits until the app is in Applications."
        case .undone: return "Nothing undone. Every action can be undone from here."
        }
    }
}

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
            case (.handled, .need): passes = false
            case (.handled, _): passes = true
            case (.renamed, .action(let a)): passes = a.kind == .renamed && !a.undone
            case (.renamed, .need(.renames)): passes = true
            case (.tagged, .action(let a)): passes = !a.tags.isEmpty && !a.undone
            case (.ejected, .action(let a)): passes = a.kind == .trashed && a.details["installer"] != nil
            case (.undone, .action(let a)): passes = a.undone
            case (.duplicates, .action(let a)): passes = (a.kind == .duplicate || (a.kind == .trashed && a.details["installer"] == nil)) && !a.undone
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
            if let selected {
                // Activity v3: the detail is one rounded card with a soft border.
                EntryDetail(entry: selected, next: next(after: selected, in: list)).id(selected.id)
                    .transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(x: 12)))
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(K.card))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4).padding(.trailing, 12).padding(.bottom, 12)
            } else {
                emptyState
            }
        }
        .background { KeyCatcher(up: { move(-1, list, selected?.id) }, down: { move(1, list, selected?.id) }) }
    }

    /// The three empty states: nothing at all, nothing under this filter, nothing matching the search.
    var emptyState: some View {
        let searching = !query.isEmpty
        let icon = searching ? "magnifyingglass" : filter.icon
        return VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: TS.hero, weight: .light)).foregroundStyle(K.text3).frame(width: 84, height: 84)
                .liquid(Circle(), tint: Tint.accent.bg.opacity(0.5), interactive: false)
            Text(searching ? "No matches for “\(query)”" : filter == .all ? "Nothing yet" : "Nothing under \(filter.rawValue)").font(.system(size: TS.title2, design: .serif)).foregroundStyle(K.text)
            Text(searching ? "Search looks at file names and shelves." : filter.emptyLine).font(.system(size: TS.body)).foregroundStyle(K.text2).multilineTextAlignment(.center).frame(maxWidth: 320)
            if searching || filter != .all {
                Button(searching ? "Clear search" : "Show all activity") { withAnimation(Motion.spring(0.3)) { if searching { query = "" } else { filter = .all } } }
                    .buttonStyle(SecondaryStyle(small: true)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ↑ ↓ walk the list; after an action removes the selected row the next one is picked.
    func move(_ d: Int, _ list: [Entry], _ current: String?) {
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == current } ?? 0
        let n = min(max(i + d, 0), list.count - 1)
        withAnimation(Motion.spring(0.25)) { m.selectedActivity = list[n].id }
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
                // HIG (search fields, pop-up buttons): search at the top of the list column, with a filter menu beside it
                // (the Mail pattern). One pop-up for mutually exclusive filters scales to any number of them.
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: TS.small)).foregroundStyle(K.text2)
                        TextField("Search files and shelves", text: $query).textFieldStyle(.plain).font(.system(size: TS.body))
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(K.text3) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                    }
                    .padding(.horizontal, 12).frame(height: 32).liquid(Capsule(), tint: nil, fallback: K.fill, interactive: false)
                    filterMenu
                }
                Picker("Show", selection: $filter.animation(Motion.spring(0.3))) {
                    Text("All").tag(Filter.all)
                    Text(m.needs.isEmpty ? "Needs you" : "Needs you · \(m.needs.count)").tag(Filter.needs)
                    Text("Handled").tag(Filter.handled)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 236)
                if ![.all, .needs, .handled].contains(filter) {
                    HStack(spacing: 6) {
                        Text("Filtered by \(filter.rawValue)").font(.system(size: TS.small)).foregroundStyle(K.text2)
                        Button { withAnimation(Motion.spring(0.3)) { filter = .all } } label: { Image(systemName: "xmark.circle.fill").font(.system(size: TS.small)).foregroundStyle(K.text3) }
                            .buttonStyle(.plain).help("Show all activity").accessibilityLabel("Clear filter")
                    }
                    .padding(.horizontal, 4)
                }
                LazyVStack(alignment: .leading, spacing: 4) {
                    let groups = group(list)
                    ForEach(groups, id: \.0) { g in
                        HStack {
                            Text(g.0).eyebrow()
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(g.1) { e in Button { withAnimation(Motion.spring(0.25)) { m.selectedActivity = e.id } } label: { ListRow(entry: e, selected: e.id == selected) }.buttonStyle(PlainRowStyle()).focusRing(9) }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 4).padding(.horizontal, 12)
        }
        .softTopEdge()
    }

    /// A glass circle with the filter symbol (filled and tinted while a filter is on); opens a menu with a check on the current one.
    var filterMenu: some View {
        let fine = ![.all, .needs, .handled].contains(filter)
        return Menu {
            Picker("Filter", selection: $filter) {
                ForEach([Filter.renamed, .tagged, .duplicates, .ejected, .undone], id: \.self) { f in
                    Label(f.rawValue, systemImage: f.icon).tag(f)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: fine ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: TS.body, weight: .medium)).foregroundStyle(fine ? Tint.accent.fg : K.text2)
                .frame(width: 32, height: 32).contentShape(Circle())
                .liquid(Circle(), tint: fine ? Tint.accent.bg : nil, fallback: fine ? Tint.accent.bg : K.fill)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Filter activity").accessibilityLabel(fine ? "Filter activity, \(filter.rawValue)" : "Filter activity")
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
    case .batch(_, let a): return "\(a.count) files"
    case .waiting(let w): return w.partial ? w.url.deletingPathExtension().lastPathComponent : w.url.lastPathComponent
    }
}

@MainActor func subtitle(_ e: Entry) -> String {
    let st = AppModel.shared.settings
    switch e {
    case .need(.duplicate(let a)): return "Copy held · " + (Int64(a.details["size"] ?? "") ?? 0).bytes
    case .need(.renames): return "Review before renaming"
    case .need(.rule(let r)): return "Rule suggested · \(r.shelf) shelf"
    case .action(let a):
        if a.undone { return "Undone · " + summary(a).lowercased() }
        switch a.kind {
        case .renamed: return "Renamed from \(a.oldName ?? "")"
        case .duplicate: return "Copy kept in Duplicates"
        case .trashed: return a.details["installer"] != nil ? "Smart Eject · installer moved to Trash" : "Moved to Trash · \((Int64(a.details["size"] ?? "") ?? 0).bytes)"
        case .sorted: return "Sorted → \(st.emoji(for: a.shelf)) \(a.shelf)"
        }
    case .batch(_, let a): return "Sorted into \(Set(a.map(\.shelf)).count) shelves"
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
        HStack(alignment: .center, spacing: 10) {
            EmojiTile(emoji: emoji, size: 40, fill: K.card)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title(entry)).font(.system(size: TS.body, weight: .bold)).foregroundStyle(pending ? tint.fg : K.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(entry.ts.listTime).font(.system(size: TS.meta)).foregroundStyle(pending ? tint.fg : K.text2)
                }
                Text(subtitle(entry)).font(.system(size: TS.small)).foregroundStyle(pending ? tint.fg : K.text2).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? K.fillStrong : .clear))
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
    @State private var showKeys = false

    var renamedAction: Action? { if case .action(let a) = entry, a.kind == .renamed { return a }; return nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let a = renamedAction {
                        renamedHero(a)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(headline).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(K.text).lineLimit(2)
                            Text(sub).font(.system(size: TS.body)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        visual
                    }
                    decided
                    filedIn
                    if let next { Button("Next: \(nextLabel(next)) ↓") { m.selectedActivity = next.id }.buttonStyle(LinkStyle(color: K.text2)) }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .defaultScrollAnchor(ProcessInfo.processInfo.environment["KANSO_SCROLL"] == "bottom" ? .bottom : .top)   // screenshots of the scrolled state
            actionBar.padding(.horizontal, 20).padding(.bottom, 14).padding(.top, 4).frame(maxWidth: .infinity, alignment: .trailing)
            footer
        }
    }

    // MARK: Head, footer

    var badge: (icon: String, text: String, tint: Tint) {
        switch entry {
        case .need(let n): return (n.icon, "\(n.label) · needs you", n.tint)
        case .action(let a):
            switch a.kind {
            case .renamed: return ("checkmark", "Renamed", .rename)
            case .duplicate: return ("doc.on.doc", "Duplicate", .duplicate)
            case .trashed: return ("trash", "Moved to Trash", .neutral)
            case .sorted: return ("checkmark", a.undone ? "Sorted · undone" : "Sorted", .accent)
            }
        case .batch: return ("checkmark", "Batch", .neutral)
        case .waiting: return ("hourglass", "Waiting", .neutral)
        }
    }

    var head: some View {
        let b = badge
        return HStack(spacing: 10) {
            Image(systemName: b.icon).font(.system(size: TS.small, weight: .bold)).foregroundStyle(b.tint.fg)
                .frame(width: 26, height: 26).background(Circle().fill(b.tint.bg)).accessibilityHidden(true)
            Text(b.text).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
            Spacer()
            Text(meta).font(.system(size: TS.small)).foregroundStyle(K.text2)
        }
        .accessibilityElement(children: .combine)
    }

    var footer: some View {
        HStack {
            Text("↑↓ move between activities").font(.system(size: TS.small)).foregroundStyle(K.text2)
            Spacer()
            Button { showKeys.toggle() } label: {
                Image(systemName: "keyboard").font(.system(size: TS.body)).foregroundStyle(K.text2)
                    .frame(width: 30, height: 30).contentShape(Circle()).liquid(Circle())
            }
            .buttonStyle(.plain).focusRing(15).help("Keyboard shortcuts").accessibilityLabel("Keyboard shortcuts")
            .popover(isPresented: $showKeys, arrowEdge: .top) { shortcuts }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(K.separator).frame(height: 0.75) }
    }

    var shortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([("↑ ↓", "Move between activities"), ("⌘Z", "Undo or Put Back"), ("⌘⌫", "Move the copy to Trash"), ("↩", "Do the main action"), ("⌘↩", "Rename all"), ("⌥⌘K", "Open the island")], id: \.0) { k in
                HStack(spacing: 14) {
                    Text(k.0).font(.system(size: TS.small, weight: .medium, design: .monospaced)).foregroundStyle(K.text).frame(width: 44, alignment: .leading)
                    Text(k.1).font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
            }
        }
        .padding(16)
    }

    func shelfOptions(_ current: String) -> [(String, String)] {
        var o = m.settings.types.map { ($0.name, $0.name) }
        if !o.contains(where: { $0.0 == current }) { o.insert((current, current), at: 0) }
        return o
    }

    var meta: String {
        (Calendar.current.isDateInToday(entry.ts) ? "Today" : entry.ts.formatted(.dateTime.month(.abbreviated).day())) + " " + entry.ts.clock
    }

    // MARK: Renamed hero and recipe

    func renamedHero(_ a: Action) -> some View {
        let t = Tint.rename
        let palette = [t.fg, Tint.where.fg, Tint.rule.fg, Tint.duplicate.fg]
        return HStack(alignment: .top, spacing: 16) {
            HeroPreview(path: a.dst).frame(width: 72, height: 94)
            VStack(alignment: .leading, spacing: 6) {
                Text(a.oldName ?? "").font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(t.fg.opacity(0.8)).lineLimit(1).truncationMode(.middle)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(a.name).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { m.reveal(a.dst) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg) }
                        .buttonStyle(.plain).focusRing(6).help("Show in Finder").accessibilityLabel("Show in Finder")
                }
                HStack(spacing: 6) {
                    Text((a.root as NSString).lastPathComponent)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    Text("\(m.settings.emoji(for: a.shelf)) \(a.shelf)").fontWeight(.medium)
                }
                .font(.system(size: TS.small)).foregroundStyle(t.fg).lineLimit(1)
                FlowLayout(spacing: 6) {
                    ForEach(Array(a.tags.enumerated()), id: \.element) { i, tag in TagPill(name: tag, color: palette[i % palette.count]) }
                    AddTagPill { m.addTag(a.id, $0) }
                }
                Label { Text("File is still findable by the old name \(a.oldName ?? "")").fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "info.circle") }
                    .font(.system(size: TS.meta)).foregroundStyle(t.fg).labelStyle(TightLabel())
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.bg))
    }

    /// Kind - Organization - Date from the rename details; empty when the engine kept none.
    func recipe(_ a: Action) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        let src = a.source.replacingOccurrences(of: "contents, page ", with: "p.").replacingOccurrences(of: "contents", with: "read")
        if let k = a.details["kind"] { out.append(("Kind", k, src)) }
        if let o = a.details["organization"] { out.append(("Organization", o, src)) }
        if let d = a.details["date"].flatMap({ ISO8601DateFormatter().date(from: $0) }) { out.append(("Date", d.formatted(.iso8601.year().month().dateSeparator(.dash)), src)) }
        return out
    }

    func recipeCard(_ a: Action, _ parts: [(String, String, String)]) -> some View {
        let t = Tint.rename
        let stem = ((a.oldName ?? "") as NSString).deletingPathExtension
        let label = Meaningless.label(stem) ?? ""
        let what = label.hasPrefix("Scan") ? "a scanner default" : label.hasPrefix("IMG") ? "a camera default" : label.hasPrefix("download") ? "a download default" : "a name"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 3) {
                        Text(p.1).font(.system(size: TS.body, weight: .semibold, design: .monospaced)).foregroundStyle(t.fg).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 8).frame(height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.bg))
                        Text(p.0).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text)
                        Text(p.2).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(1)
                    }
                    if i < parts.count - 1 { Text("-").font(.system(size: TS.body, design: .monospaced)).foregroundStyle(K.text3).frame(height: 30) }
                }
                Text(".\((a.name as NSString).pathExtension)").font(.system(size: TS.body, design: .monospaced)).foregroundStyle(K.text3).frame(height: 30)
            }
            Rectangle().fill(K.separator).frame(height: 0.75)
            Label("Replaced \(stem) — \(what) with no meaning", systemImage: "viewfinder").font(.system(size: TS.small)).foregroundStyle(K.text2).labelStyle(TightLabel())
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.fill))
    }

    /// "Filed in [shelf] because …": the shelf picker for anything Kanso sorted or renamed.
    @ViewBuilder var filedIn: some View {
        if case .action(let a) = entry, a.kind == .sorted || a.kind == .renamed, !a.undone {
            let ext = (a.name as NSString).pathExtension.uppercased()
            let why = a.source == "you" ? "you moved it here" : a.why.hasPrefix("rule") ? "your rule matched" : a.why == "screenshot" ? "screenshots go to \(a.shelf)"
                : a.why.hasPrefix("apple-intelligence") ? "Apple Intelligence picked it" : ext.isEmpty ? "" : "\(ext) files go to \(a.shelf)"
            HStack(spacing: 10) {
                Label("Filed in", systemImage: "folder").font(.system(size: TS.small)).foregroundStyle(K.text2)
                MenuPicker(options: shelfOptions(a.shelf), value: Binding(get: { a.shelf }, set: { if $0 != a.shelf { m.move(a.id, to: $0) } }), emoji: { m.settings.emoji(for: $0) })
                    .help("Move to another shelf")
                if !why.isEmpty { Text("because \(why)").font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1) }
            }
        }
    }

    var headline: String {
        switch entry {
        case .need(.duplicate(let a)): return "Copy of \(((a.details["kept"] ?? "") as NSString).lastPathComponent) held"
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
                Text("=").font(.system(size: TS.heading)).foregroundStyle(K.text3)
                previewCard(path: a.dst, label: "Extra copy", meta: "🪞 Duplicates · added \(a.ts.relative) · \((Int64(a.details["size"] ?? "") ?? 0).bytes)", tint: .duplicate)
            }
        case .need(.renames(let p, _)):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(p.prefix(4)) { r in diff(r.name, r.newName) }
                if p.count > 4 { Text("+ \(p.count - 4) more in the review window").font(.system(size: TS.meta)).foregroundStyle(K.text2) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rename.bg))
        case .need(.rule(let r)):
            VStack(alignment: .leading, spacing: 10) {
                RulePreview(condition: r.condition, shelf: r.shelf, emoji: m.settings.emoji(for: r.shelf))
                Text("Matched: " + r.files.prefix(5).joined(separator: ", ") + (r.files.count > 5 ? " and \(r.files.count - 5) more" : "")).font(.system(size: TS.small)).foregroundStyle(K.text2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rule.bg))
        case .action(let a) where a.kind == .renamed:
            HStack(spacing: 16) {
                Thumb(path: a.dst).frame(width: 72, height: 94)
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.oldName ?? "").font(.system(size: TS.body)).foregroundStyle(K.text2).strikethrough()
                    Text(a.name).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
                    if !a.tags.isEmpty { HStack { ForEach(a.tags, id: \.self) { TagPill(name: $0) } } }
                }
                Spacer()
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rename.bg))
        case .action(let a) where a.kind == .trashed && a.details["installer"] != nil:
            HStack(spacing: 14) {
                step("opticaldisc", a.srcName, "Disk image · \((Int64(a.details["size"] ?? "") ?? 0).bytes)")
                Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(K.text3)
                step("macwindow", a.details["installer"] ?? "The app", "In Applications")
                Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(K.text3)
                step("trash", a.undone ? "Put back" : "Installer in Trash", a.undone ? "Restored" : "Put Back any time")
            }
        case .action(let a) where a.kind == .sorted && !a.undone:
            VStack(alignment: .leading, spacing: 8) {
                Text("Where it went").eyebrow()
                HStack(spacing: 8) {
                    PathChips(parts: ["\(folderEmoji(a.root)) \((a.root as NSString).lastPathComponent)"])
                    Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(K.text3)
                    PathChips(parts: pathParts(a))
                }
            }
        case .action:
            EmptyView()   // a trash record or an undone sort needs no picture: the headline says it
        case .batch(_, let actions):
            let counts = Dictionary(grouping: actions, by: \.shelf).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            let mx = counts.first?.1 ?? 1
            VStack(spacing: 10) {
                ForEach(counts, id: \.0) { c in
                    HStack {
                        Text("\(m.settings.emoji(for: c.0)) \(c.0)").font(.system(size: TS.small)).foregroundStyle(K.text).frame(width: 150, alignment: .leading)
                        ProgressBar(value: Double(c.1) / Double(mx))
                        Text("\(c.1)").font(.system(size: TS.meta)).foregroundStyle(K.text2).frame(width: 28, alignment: .trailing)
                    }
                }
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(K.neutralBg))
        case .waiting:
            EmptyView()
        }
    }

    func step(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: TS.emphasis)).foregroundStyle(Tint.accent.fg).frame(width: 40, height: 40).background(Circle().fill(Tint.accent.bg))
            Text(title).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text).lineLimit(1).truncationMode(.middle)
            Text(sub).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).card(radius: 14)
    }

    func diff(_ a: String, _ b: String) -> some View {
        HStack(spacing: 10) {
            Text(a).font(.system(size: TS.small)).foregroundStyle(K.text2).frame(width: 170, alignment: .leading).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: TS.micro)).foregroundStyle(Tint.rename.fg)
            Text(b).font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text).lineLimit(1)
        }
    }

    func previewCard(path: String, label: String, meta: String, tint: Tint?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(path: path).frame(maxWidth: .infinity).frame(height: 130).background(RoundedRectangle(cornerRadius: 2).fill(tint?.soft ?? K.fill))   // 12 card − 14 padding: square-ish inner
            Text(label).eyebrow().foregroundStyle(tint?.fg ?? K.text2)
            Text((path as NSString).lastPathComponent).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text).lineLimit(1)
            Text(meta).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(2)
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

    @ViewBuilder var decided: some View {
        let title = { () -> String in if case .need(.duplicate) = entry { return "How Kanso knew" }; return "How Kanso decided" }()
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text2)
            if let a = renamedAction, !recipe(a).isEmpty {
                recipeCard(a, recipe(a))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        // Title over value, source on the right: fits the narrow detail column without truncating.
                        HStack(spacing: 12) {
                            Image(systemName: r.0).font(.system(size: TS.small)).foregroundStyle(K.text2).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.1).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                                Text(r.2).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(r.3).font(.system(size: TS.meta)).foregroundStyle(r.3.hasPrefix("contents") ? Tint.rename.fg : K.text2).lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        if i < rows.count - 1 { Rectangle().fill(K.separator).frame(height: 0.75) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.fill))
            }
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
        FlowLayout(spacing: 8) {   // wraps to a second line instead of truncating a label in the narrow detail column
            switch entry {
            case .need(.duplicate(let a)):
                Button { m.trash(a.id) } label: { HStack { Text("Move copy to Trash"); Hint(text: "⌘⌫") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut(.delete, modifiers: .command)
                Button("Keep both") { m.keepBoth(a.id) }.buttonStyle(SecondaryStyle())
                Button { m.undo([a.id]) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(SecondaryStyle()).keyboardShortcut("z").help("Undo (⌘Z)").accessibilityLabel("Undo")
            case .need(.renames(let p, _)):
                Button { Windows.shared.showReview(tab: .renames) } label: { HStack { Text("Review \(p.count) files…"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .rename)).keyboardShortcut(.defaultAction)
                Button { m.applyRenames(p) } label: { HStack { Image(systemName: "wand.and.sparkles"); Text("Rename all"); Hint(text: "⌘↩") } }.buttonStyle(SecondaryStyle()).keyboardShortcut(.return, modifiers: .command)
                Button("Not now") { m.dismissRenames() }.buttonStyle(SecondaryStyle())
            case .need(.rule(let r)):
                Button { m.acceptSuggestion(r.id) } label: { HStack { Text("Create rule"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .rule)).keyboardShortcut(.defaultAction)
                Button("Edit…") { m.acceptSuggestion(r.id); Windows.shared.showMain(.sorting) }.buttonStyle(SecondaryStyle())
                Button("No thanks") { m.dismissSuggestion(r.id) }.buttonStyle(SecondaryStyle())
            case .action(let a):
                if a.undone {
                    Button("Show in Finder") { m.reveal(a.src) }.buttonStyle(SecondaryStyle())
                } else if a.kind == .trashed {
                    Button { m.undo([a.id]) } label: { HStack { Image(systemName: "arrow.uturn.backward"); Text("Put Back"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
                } else {
                    Button { m.undo([a.id]) } label: { HStack { Image(systemName: "arrow.uturn.backward"); Text("Undo"); Hint(text: "⌘Z") } }
                        .buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
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
            if case .action(let a) = entry, a.kind == .renamed, !a.undone {
                Button("Don't rename files like this") {
                    if let p = Meaningless.label(((a.oldName ?? "") as NSString).deletingPathExtension) { m.update { $0.disabledPatterns.append(p) } }
                    m.undo([a.id])
                }
                .buttonStyle(LinkStyle(color: K.text2))
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
                Text(p).font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text)
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


/// Groups glass children so they blend and morph on macOS 26; a plain container before.
@ViewBuilder func glassGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    if #available(macOS 26, *), !Motion.solid { GlassEffectContainer(spacing: 6) { content() } } else { content() }
}

/// ↑ ↓ for the list without a focused control: a local monitor while the Activity page is on screen.
struct KeyCatcher: NSViewRepresentable {
    var up: () -> Void
    var down: () -> Void
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ v: NSView, context: Context) { context.coordinator.up = up; context.coordinator.down = down }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let view = NSView()
        var up: () -> Void = {}, down: () -> Void = {}
        var monitor: Any?
        init() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.view.window?.isKeyWindow == true, !(self.view.window?.firstResponder is NSText), e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return e }
                switch Int(e.keyCode) {
                case 126: self.up(); return nil
                case 125: self.down(); return nil
                default: return e
                }
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}


extension View {
    /// A bar pinned to the bottom edge: `safeAreaBar` on macOS 26 (adds the scroll edge effect), `safeAreaInset` before.
    @ViewBuilder func floatingBar<B: View>(@ViewBuilder _ bar: () -> B) -> some View {
        if #available(macOS 26, *) { safeAreaBar(edge: .bottom) { bar() } } else { safeAreaInset(edge: .bottom) { bar() } }
    }
}


/// Icon and text hugging each other (a Label with a 5 pt gap).
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { configuration.icon; configuration.title }
    }
}

/// The page preview in the hero; hovering shows an eye that opens Quick Look.
struct HeroPreview: View {
    var path: String
    @State private var hover = false
    var body: some View {
        Thumb(path: path)
            .overlay {
                Button { QuickLook.show(URL(fileURLWithPath: path)) } label: {
                    Image(systemName: "eye").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain).focusRing(15).help("Quick Look").accessibilityLabel("Quick Look")
                .opacity(hover || Motion.snapshot ? 1 : 0)
            }
            .onHover { hover = $0 }
    }
}

/// "+ Add tag": a pill that opens a small field; Return adds a Finder tag to the file.
struct AddTagPill: View {
    var add: (String) -> Void
    @State private var open = false
    @State private var text = ""
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 4) { Image(systemName: "plus").font(.system(size: TS.micro, weight: .semibold)); Text("Add tag").font(.system(size: TS.meta)) }
                .foregroundStyle(Tint.rename.fg).padding(.horizontal, 7).frame(height: 20)
                .overlay(Capsule().strokeBorder(Tint.rename.stroke, lineWidth: 0.75)).contentShape(Capsule())
        }
        .buttonStyle(.plain).focusRing(10).accessibilityLabel("Add tag")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TextField("Tag name", text: $text).textFieldStyle(.roundedBorder).frame(width: 160).padding(12)
                .onSubmit { add(text.trimmingCharacters(in: .whitespaces)); text = ""; open = false }
        }
    }
}

/// Quick Look panel for one file.
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    var url: URL?
    @MainActor static func show(_ url: URL) {
        shared.url = url
        let p = QLPreviewPanel.shared()!
        p.dataSource = shared
        p.reloadData()
        p.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}
