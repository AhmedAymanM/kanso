import KansoCore
import SwiftUI

/// A group of rename proposals that share a pattern ("Scan_####"), or the ones with no clear title.
struct RenameGroup: Identifiable {
    var id: String
    var label: String
    var icon: String
    var items: [RenameProposal]
    var unclear: Bool
}

func isClear(_ p: RenameProposal) -> Bool { p.details["kind"] != nil }

func renameGroups(_ p: [RenameProposal]) -> [RenameGroup] {
    let clear = p.filter(isClear), unclear = p.filter { !isClear($0) }
    let g = Dictionary(grouping: clear) { Meaningless.label(($0.name as NSString).deletingPathExtension) ?? "Other" }
    var out = g.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }.map { k, v in
        let icon = k.hasPrefix("Scan") ? "viewfinder" : k.hasPrefix("IMG") ? "camera" : k.hasPrefix("download") ? "arrow.down.to.line" : "textformat"
        return RenameGroup(id: k, label: k, icon: icon, items: v, unclear: false)
    }
    if !unclear.isEmpty { out.append(RenameGroup(id: "Unclear", label: "Unclear", icon: "doc.badge.ellipsis", items: unclear, unclear: true)) }
    return out
}

/// Activity v3 detail: head row, a pastel hero per kind, "How Kanso decided", inline action pills and a footer.
struct EntryDetail: View {
    @EnvironmentObject var m: AppModel
    var entry: Entry
    var next: Entry?
    @State private var showKeys = false
    @State private var expanded = ProcessInfo.processInfo.environment["KANSO_EXPAND"] != nil
    @State private var index = Int(ProcessInfo.processInfo.environment["KANSO_INDEX"] ?? "") ?? 0
    @State private var showAllRule = false
    @State private var renameOpen = false
    @State private var editOpen = false

    /// The final Renamed layout (tag flow) is flat: a pill head, a decision table and a bottom bar instead of the card.
    static func isFlat(_ e: Entry) -> Bool { if case .action(let a) = e, a.kind == .renamed, !a.undone { return true }; return false }
    var flat: Bool { EntryDetail.isFlat(entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head.padding(.horizontal, 20).padding(.top, flat ? 18 : 16).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .defaultScrollAnchor(ProcessInfo.processInfo.environment["KANSO_SCROLL"] == "bottom" ? .bottom : .top)
            if flat { flatBar } else {
                actionBar.padding(.horizontal, 20).padding(.bottom, 14).padding(.top, 4).frame(maxWidth: .infinity, alignment: .trailing)
                footer
            }
        }
        .background { KeyCatcher(keys: keys) }
    }

    /// ← → cycle files, esc collapses, → opens the file-by-file view of a rename review or a batch.
    var keys: [Int: () -> Void] {
        if expanded {
            let n = fileCount
            return [123: { step(-1, n) }, 124: { step(1, n) }, 53: { collapse() }]
        }
        switch entry {
        case .need(.renames), .batch: return [124: { expand(0) }]
        default: return [:]
        }
    }

    var fileCount: Int {
        switch entry {
        case .need(.renames(let p, _)): return p.count
        case .batch(_, let a): return a.count
        default: return 0
        }
    }
    func expand(_ i: Int) { withAnimation(Motion.spring(0.3)) { index = i; expanded = true } }
    func collapse() { withAnimation(Motion.spring(0.3)) { expanded = false } }
    func step(_ d: Int, _ n: Int) { guard n > 0 else { return }; withAnimation(Motion.spring(0.25)) { index = (min(index, n - 1) + d + n) % n } }

    // MARK: Head, footer

    var badge: (icon: String, text: String, tint: Tint) {
        switch entry {
        case .need(let n): return (n.icon == "pencil.line" ? "eye" : n.icon, n.label, n.tint)
        case .action(let a):
            switch a.kind {
            case .renamed: return ("pencil", a.undone ? "Rename · undone" : "Renamed", .rename)
            case .duplicate: return ("doc.on.doc", "Duplicate", .duplicate)
            case .trashed: return ("trash", a.details["installer"] != nil ? "Smart Eject" : "Moved to Trash", a.details["installer"] != nil ? .accent : .neutral)
            case .sorted: return ("checkmark", a.undone ? "Sorted · undone" : "Sorted", .accent)
            }
        case .batch: return ("square.3.layers.3d", "Batch", .accent)
        case .waiting: return ("hourglass", "Waiting", .where)
        }
    }

    var meta: String {
        (Calendar.current.isDateInToday(entry.ts) ? "Today" : entry.ts.formatted(.dateTime.month(.abbreviated).day())) + " " + entry.ts.clock
    }

    var head: some View {
        let b = badge
        return HStack(spacing: 10) {
            if flat {
                HStack(spacing: 6) {
                    Image(systemName: b.icon).font(.system(size: TS.small, weight: .semibold))
                    Text(b.text).font(.system(size: TS.body, weight: .semibold))
                }
                .foregroundStyle(b.tint.fg).padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(b.tint.bg))
            } else {
                Image(systemName: b.icon).font(.system(size: TS.small, weight: .bold)).foregroundStyle(b.tint.fg)
                    .frame(width: 26, height: 26).background(Circle().fill(b.tint.bg)).accessibilityHidden(true)
                Text(b.text).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
            }
            Spacer()
            Text(meta).font(.system(size: TS.small)).foregroundStyle(K.text2)
        }
        .accessibilityElement(children: .combine)
    }

    var hint: String {
        if expanded { return "← → cycle files · esc collapse · ↑↓ activities" }
        if case .need(.renames) = entry { return "→ review one by one · ↑↓ move between activities" }
        return "↑↓ move between activities"
    }

    var footer: some View {
        HStack {
            Text(hint).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1)
            Spacer()
            keysButton(labelled: false)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(K.separator).frame(height: 0.75) }
    }

    func keysButton(labelled: Bool) -> some View {
        Button { showKeys.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard").font(.system(size: TS.body))
                if labelled { Text("Shortcuts").font(.system(size: TS.small, weight: .medium)); Keycap(key: "⌘/") }
            }
            .foregroundStyle(K.text2).padding(.horizontal, labelled ? 10 : 0).frame(minWidth: 30, minHeight: 30).contentShape(Capsule()).liquid(Capsule())
        }
        .buttonStyle(.plain).focusRing(15).help("Keyboard shortcuts (⌘/)").accessibilityLabel("Keyboard shortcuts")
        .keyboardShortcut("/")
        .popover(isPresented: $showKeys, arrowEdge: .top) { shortcuts }
    }

    var shortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([("↑ ↓", "Move between activities"), ("← →", "Cycle files in a review or batch"), ("esc", "Back to all files"), ("⌘Z", "Undo or Put Back"), ("⌘⌫", "Move the copy to Trash"), ("↩", "Do the main action"), ("⌥⌘K", "Open the island")], id: \.0) { k in
                HStack(spacing: 14) {
                    Text(k.0).font(.system(size: TS.small, weight: .medium, design: .monospaced)).foregroundStyle(K.text).frame(width: 44, alignment: .leading)
                    Text(k.1).font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
            }
        }
        .padding(16)
    }

    // MARK: Content

    @ViewBuilder var content: some View {
        switch entry {
        case .need(.renames(let p, _)): if expanded { renameFileView(p) } else { renameSummary(p) }
        case .need(.rule(let r)): ruleDetail(r)
        case .need(.shelf(let s)): shelfDetail(s)
        case .need(.duplicate(let a)): duplicateDetail(a)
        case .batch(let run, let a): if expanded { batchFileView(a) } else { batchSummary(run, a) }
        case .waiting(let w): waitingDetail(w)
        case .action(let a):
            if a.undone { undoneDetail(a) }
            else {
                switch a.kind {
                case .renamed: renamedDetail(a)
                case .sorted: sortedDetail(a)
                case .duplicate: duplicateDetail(a)
                case .trashed: trashedDetail(a)
                }
            }
        }
    }

    // MARK: Rename review

    func renameSummary(_ p: [RenameProposal]) -> some View {
        let groups = renameGroups(p)
        let unclear = groups.first { $0.unclear }?.items.count ?? 0
        let names = groups.filter { !$0.unclear }.map { $0.label.hasPrefix("Scan") ? "Scanner" : $0.label.hasPrefix("IMG") ? "camera" : $0.label.hasPrefix("download") ? "download" : $0.label }
        let sub = names.isEmpty ? "Names that say nothing" : (names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]).capitalizedFirst + " names"
        var starts: [String: Int] = [:]
        var run = 0
        for g in groups { starts[g.id] = run; run += g.items.count }
        return Group {
            StackHero(tint: .rename, path: (p.first { $0.path.hasSuffix(".pdf") } ?? p.first)?.path ?? "", title: "\(p.count) \(p.count == 1 ? "file" : "files") can be renamed", sub: sub, note: "Nothing changes until you approve. Old names stay searchable.", showAll: { expand(0) })
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(warn: unclear > 0)
                RowStack {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        Button { expand(starts[g.id] ?? 0) } label: { renameRow(g) }.buttonStyle(PlainRowStyle()).focusRing(10)
                        if i < groups.count - 1 { Hairline() }
                    }
                }
            }
            if unclear > 0, let first = groups.first(where: { $0.unclear }) {
                Callout(title: "\(unclear) \(unclear == 1 ? "file needs" : "files need") a look", sub: "No clear title found, so they keep their names unless you rename them", action: "Check them") { expand(starts[first.id] ?? 0) }
            }
        }
    }

    func renameRow(_ g: RenameGroup) -> some View {
        let ex = g.items.first
        return HStack(spacing: 12) {
            Image(systemName: g.icon).font(.system(size: TS.body)).foregroundStyle(g.unclear ? Tint.duplicate.fg : K.text2)
                .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.unclear ? Tint.duplicate.soft : K.card)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(g.label).font(.system(size: TS.body, weight: .bold, design: .monospaced)).foregroundStyle(K.text)
                    Text("\(g.items.count) \(g.items.count == 1 ? "file" : "files")").font(.system(size: TS.body)).foregroundStyle(K.text2)
                }
                if let ex {
                    HStack(spacing: 6) {
                        Text(ex.name).font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(K.text2)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(K.text3)
                        Text(g.unclear ? "No clear title found" : ex.newName).font(.system(size: TS.meta, weight: .medium)).foregroundStyle(g.unclear ? Tint.duplicate.fg : K.text)
                    }
                    .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: g.unclear ? "exclamationmark.triangle" : "checkmark.circle").font(.system(size: TS.emphasis)).foregroundStyle(g.unclear ? Tint.duplicate.fg : K.accent).accessibilityLabel(g.unclear ? "Needs a look" : "Clear")
            Image(systemName: "chevron.right").font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text3).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(g.unclear ? Tint.duplicate.bg : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Review these files one by one")
    }

    func renameFileView(_ all: [RenameProposal]) -> some View {
        let p = renameGroups(all).flatMap(\.items)
        let i = min(index, max(p.count - 1, 0))
        let t = Tint.rename
        guard p.indices.contains(i) else { return AnyView(EmptyView()) }
        let r = p[i]
        let clear = isClear(r)
        let stem = (r.name as NSString).deletingPathExtension
        let label = Meaningless.label(stem) ?? ""
        let what = label.hasPrefix("Scan") ? "a scanner default" : label.hasPrefix("IMG") ? "a camera default" : label.hasPrefix("download") ? "a download default" : "a name with no meaning"
        return AnyView(Group {
            HeroBlock(tint: t) {
                VStack(alignment: .leading, spacing: 14) {
                    PagerRow(tint: t, index: i, count: p.count, back: collapse) { step($0, p.count) }
                    HStack(alignment: .top, spacing: 16) {
                        HeroPreview(path: r.path).frame(width: 72, height: 94)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(r.name).font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(t.fg.opacity(0.8)).lineLimit(1).truncationMode(.middle)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(r.newName).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button { m.reveal(r.path) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg) }
                                    .buttonStyle(.plain).focusRing(6).help("Show in Finder").accessibilityLabel("Show in Finder")
                            }
                            breadcrumb(path: r.path, shelf: r.shelf, tint: t)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(warn: !clear)
                if clear { recipeCard(r, t: t, note: "Replaced \(stem), \(what).") }
                else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Tint.duplicate.fg)
                        Text("No clear title found. This file keeps its name unless you rename it.").font(.system(size: TS.body)).foregroundStyle(K.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tint.duplicate.bg))
                }
            }
            HStack(spacing: 10) {
                Label("Filed in", systemImage: "folder").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Text("\(m.settings.emoji(for: r.shelf)) \(r.shelf)").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                Text("because it already is on that shelf").font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1)
            }
        })
    }

    func recipeCard(_ r: RenameProposal, t: Tint, note: String) -> some View {
        var parts: [(String, String)] = []
        if let k = r.details["kind"] { parts.append(("Kind", k)) }
        if let o = r.details["organization"] { parts.append(("Organization", o)) }
        if let d = r.details["date"].flatMap({ ISO8601DateFormatter().date(from: $0) }) { parts.append(("Date", d.formatted(.iso8601.year().month().dateSeparator(.dash)))) }
        let src = r.source.replacingOccurrences(of: "contents, page ", with: "p.")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 3) {
                        Text(p.1).font(.system(size: TS.body, weight: .semibold, design: .monospaced)).foregroundStyle(t.fg).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 8).frame(height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.bg))
                        Text(p.0).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text)
                        Text(src).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(1)
                    }
                    if i < parts.count - 1 { Text("-").font(.system(size: TS.body, design: .monospaced)).foregroundStyle(K.text3).frame(height: 30) }
                }
                Text(".\((r.newName as NSString).pathExtension)").font(.system(size: TS.body, design: .monospaced)).foregroundStyle(K.text3).frame(height: 30)
            }
            Hairline()
            Label(note, systemImage: "viewfinder").font(.system(size: TS.small)).foregroundStyle(K.text2).labelStyle(TightLabel())
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.fill))
    }

    func rootName(_ path: String) -> String {
        let c = path.split(separator: "/").map(String.init)
        if let i = c.firstIndex(of: Library.mine), i > 0 { return c[i - 1] }
        return ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    func breadcrumb(path: String, shelf: String, tint t: Tint) -> some View {
        HStack(spacing: 6) {
            Text(rootName(path))
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            Image(systemName: "folder").font(.system(size: TS.small))
            Text(shelf).fontWeight(.medium)
        }
        .font(.system(size: TS.body)).foregroundStyle(t.fg).lineLimit(1)
    }

    // MARK: Batch

    struct ShelfGroup: Identifiable { var id: String; var actions: [Action]; var guess: Bool }

    func shelfGroups(_ a: [Action]) -> [ShelfGroup] {
        let g = Dictionary(grouping: a, by: \.shelf).map { ($0.key, $0.value) }.sorted { $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0 }
        return g.map { ShelfGroup(id: $0.0, actions: $0.1, guess: $0.1.contains(where: isGuess)) }
    }

    func isGuess(_ a: Action) -> Bool { a.why.hasPrefix("apple-intelligence") }

    func reason(_ g: ShelfGroup) -> String {
        if g.guess { return "Guessed from the name" }
        guard let a = g.actions.first else { return "" }
        if a.why == "screenshot" { return "Marked as a screenshot" }
        if a.why.hasPrefix("rule") { return "Your rule matched" }
        if a.source == "you" { return "You moved it here" }
        let exts = Set(g.actions.map { ($0.name as NSString).pathExtension.uppercased() }.filter { !$0.isEmpty }).sorted().prefix(2)
        return exts.isEmpty ? "By file type" : exts.joined(separator: ", ") + " files"
    }

    func batchSummary(_ run: String, _ a: [Action]) -> some View {
        let groups = shelfGroups(a)
        let guesses = a.filter(isGuess)
        let root = (a.first?.root as NSString?)?.lastPathComponent ?? "Folder"
        return Group {
            StackHero(tint: .accent, path: (a.first { $0.name.hasSuffix(".pdf") } ?? a.first)?.dst ?? "", title: "\(a.count) files sorted into \(groups.count) \(groups.count == 1 ? "shelf" : "shelves")", sub: "\(root) tidy at \((a.first?.ts ?? Date()).clock)",
                      note: "Triggered by \(trigger(a.first?.trigger ?? "auto")). Every file can be undone on its own.", showAll: { expand(0) })
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(warn: !guesses.isEmpty)
                RowStack {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        Button { expand(a.firstIndex { $0.shelf == g.id } ?? 0) } label: { shelfRow(g) }.buttonStyle(PlainRowStyle()).focusRing(10)
                        if i < groups.count - 1 { Hairline() }
                    }
                }
            }
            if let g = guesses.first {
                Callout(title: guesses.count == 1 ? "1 file was a guess" : "\(guesses.count) files were guesses", sub: guesses.count == 1 ? "\(g.name) went to \(g.shelf) based on its name" : "Apple Intelligence picked their shelves from the names", action: "Check it") { expand(a.firstIndex { $0.id == g.id } ?? 0) }
            }
        }
    }

    func shelfRow(_ g: ShelfGroup) -> some View {
        HStack(spacing: 12) {
            Text(m.settings.emoji(for: g.id)).font(.system(size: TS.emphasis)).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.guess ? Tint.duplicate.soft : K.card)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if g.guess { Image(systemName: "exclamationmark.triangle").font(.system(size: TS.small)).foregroundStyle(Tint.duplicate.fg) }
                    Text(g.id).font(.system(size: TS.body, weight: .bold)).foregroundStyle(K.text)
                }
                Text(reason(g)).font(.system(size: TS.small)).foregroundStyle(g.guess ? Tint.duplicate.fg : K.text2).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("\(g.actions.count) \(g.actions.count == 1 ? "file" : "files")").font(.system(size: TS.small, design: .monospaced)).foregroundStyle(K.text2)
            Image(systemName: "chevron.right").font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text3).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(g.guess ? Tint.duplicate.bg : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Review these files one by one")
    }

    func trigger(_ t: String) -> String {
        switch t {
        case "menu": return "Sort New Files Now"
        case "sort-everything": return "Sort everything"
        case "review": return "the review window"
        case "suggestion": return "your shelf suggestion"
        default: return "Auto-Sort"
        }
    }

    func batchFileView(_ acts: [Action]) -> some View {
        let i = min(index, max(acts.count - 1, 0))
        guard acts.indices.contains(i) else { return AnyView(EmptyView()) }
        let a = acts[i]
        let t = Tint.accent
        return AnyView(Group {
            HeroBlock(tint: t) {
                VStack(alignment: .leading, spacing: 14) {
                    PagerRow(tint: t, index: i, count: acts.count, back: collapse) { step($0, acts.count) }
                    HStack(alignment: .top, spacing: 16) {
                        HeroPreview(path: a.dst).frame(width: 72, height: 94)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(a.name).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button { m.reveal(a.dst) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg) }
                                    .buttonStyle(.plain).focusRing(6).help("Show in Finder").accessibilityLabel("Show in Finder")
                            }
                            breadcrumb(path: a.dst, shelf: a.shelf, tint: t)
                            if !a.undone { TagRow(action: a, tint: t) }
                            if a.undone { InfoNote(tint: t, text: "Undone. The file is back where it was.") }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(warn: isGuess(a))
                LadderView(steps: ladder(a))
            }
            if !a.undone { FiledInRow(action: a, why: "") }
        })
    }

    // MARK: Sorted, renamed

    /// The order Kanso checks in, and where it stopped for this file.
    func ladder(_ a: Action) -> [LadderStep] {
        let rules = m.settings.rules.filter(\.enabled).count
        let none = "None of your \(rules) \(rules == 1 ? "rule matches" : "rules match") this file"
        let ext = (a.name as NSString).pathExtension
        let chip = "\(m.settings.emoji(for: a.shelf)) \(a.shelf)"
        let byType = m.settings.type(forExt: ext.lowercased())?.name
        let root = (a.root as NSString).lastPathComponent
        if a.source == "you" || a.why == "moved by you" {
            return [LadderStep(title: "You moved it", sub: "Kanso learns from moves like this", state: .hit, chip: chip)]
        }
        if a.why.hasPrefix("rule") {
            return [LadderStep(title: "Your rules", sub: "Rule: " + String(a.why.dropFirst(5)), state: .hit, chip: chip),
                    LadderStep(title: "File type", sub: byType.map { "Would have gone to \(m.settings.emoji(for: $0)) \($0)" } ?? "Not needed", state: .skipped)]
        }
        if a.why == "screenshot" {
            return [LadderStep(title: "Your rules", sub: none, state: .none),
                    LadderStep(title: "Screenshots", sub: "macOS marked it as a screen capture", state: .hit, chip: chip),
                    LadderStep(title: "Images by file type", sub: "Would have gone to \(m.settings.emoji(for: byType ?? "Images")) \(byType ?? "Images")", state: .skipped)]
        }
        if isGuess(a) {
            return [LadderStep(title: "Your rules", sub: none, state: .none),
                    LadderStep(title: "File type", sub: ext.isEmpty ? "It has no extension" : "No shelf claims .\(ext)", state: .none),
                    LadderStep(title: "Apple Intelligence", sub: "Picked from the name, on this Mac", state: .hit, chip: chip)]
        }
        return [LadderStep(title: "Your rules", sub: none, state: .none),
                LadderStep(title: a.shelf, sub: ext.isEmpty ? "Sorted by file type" : "It is a \(ext.uppercased()) file", state: .hit, chip: chip),
                LadderStep(title: "Everything else", sub: "Would have stayed in \(root)", state: .skipped)]
    }

    func filedWhy(_ a: Action) -> String {
        let ext = (a.name as NSString).pathExtension.uppercased()
        if a.source == "you" { return "because you moved it here" }
        if a.why.hasPrefix("rule") { return "because your rule matched" }
        if a.why == "screenshot" { return "because screenshots go to \(a.shelf)" }
        if isGuess(a) { return "because Apple Intelligence picked it" }
        return ext.isEmpty ? "" : "because \(ext) files go to \(a.shelf)"
    }

    func sortedNote(_ a: Action) -> String {
        if a.source == "you" { return "You moved it to \(m.settings.emoji(for: a.shelf)) \(a.shelf). Kanso learns from moves like this." }
        if a.why.hasPrefix("rule") { return "Your rule put it in \(m.settings.emoji(for: a.shelf)) \(a.shelf). The file keeps its name." }
        if a.why == "screenshot" { return "Screenshots always go to \(m.settings.emoji(for: a.shelf)) \(a.shelf). The file keeps its name." }
        if isGuess(a) { return "Apple Intelligence picked \(m.settings.emoji(for: a.shelf)) \(a.shelf) from the name, on this Mac." }
        return "Sorted by file type into \(m.settings.emoji(for: a.shelf)) \(a.shelf). The file keeps its name."
    }

    func sortedDetail(_ a: Action) -> some View {
        let t = Tint.accent
        return Group {
            HeroBlock(tint: t) {
                HStack(alignment: .top, spacing: 16) {
                    HeroPreview(path: a.dst).frame(width: 96, height: 76).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(K.card.opacity(0.55)))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(a.name).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { m.reveal(a.dst) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg) }
                                .buttonStyle(.plain).focusRing(6).help("Show in Finder").accessibilityLabel("Show in Finder")
                        }
                        breadcrumb(path: a.dst, shelf: a.shelf, tint: t)
                        TagRow(action: a, tint: t)
                        InfoNote(tint: t, text: sortedNote(a))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(warn: isGuess(a))
                LadderView(steps: ladder(a))
            }
            FiledInRow(action: a, why: "")
        }
    }

    func oldNameLine(_ a: Action) -> String {
        let stem = ((a.oldName ?? "") as NSString).deletingPathExtension
        let l = Meaningless.label(stem) ?? ""
        let kind = l.hasPrefix("Scan") ? "a scanner" : l.hasPrefix("IMG") ? "a camera" : l.hasPrefix("download") ? "a download" : "a meaningless-name"
        return "\(stem) matches \(kind) pattern"
    }

    func renamedDetail(_ a: Action) -> some View {
        let t = Tint.rename
        return Group {
            HeroBlock(tint: t) {
                HStack(alignment: .top, spacing: 16) {
                    HeroPreview(path: a.dst).frame(width: 72, height: 94)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.oldName ?? "").font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(t.fg.opacity(0.8)).strikethrough().lineLimit(1).truncationMode(.middle)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(a.name).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Button { m.reveal(a.dst) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg) }
                                .buttonStyle(.plain).focusRing(6).help("Show in Finder").accessibilityLabel("Show in Finder")
                            Spacer(minLength: 0)
                        }
                        breadcrumb(path: a.dst, shelf: a.shelf, tint: t)
                        TagRow(action: a, tint: t)
                        InfoNote(tint: t, text: "File is still findable by the old name \(a.oldName ?? "")")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle()
                RowStack(fill: K.card) {
                    let rows = renamedRows(a)
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        DecisionRow(icon: r.0, label: r.1, source: r.3) { Text(r.2) }
                        Hairline()
                    }
                    DecisionRow(icon: "folder", label: "Shelf", source: a.source == "you" ? "you" : "metadata only") {
                        MenuPicker(options: shelfOptions(a), value: Binding(get: { a.shelf }, set: { if $0 != a.shelf { m.move(a.id, to: $0) } }), emoji: { m.settings.emoji(for: $0) })
                            .help("Move to another shelf")
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
            }
            Button("Don't rename files like this") {
                if let p = Meaningless.label(((a.oldName ?? "") as NSString).deletingPathExtension) { m.update { $0.disabledPatterns.append(p) } }
                m.undo([a.id])
            }
            .buttonStyle(LinkStyle(color: K.text2))
        }
    }

    func shelfOptions(_ a: Action) -> [(String, String)] {
        var o = m.settings.types.map { ($0.name, $0.name) }
        if !o.contains(where: { $0.0 == a.shelf }) { o.insert((a.shelf, a.shelf), at: 0) }
        return o
    }

    func renamedRows(_ a: Action) -> [(String, String, String, String)] {
        var out: [(String, String, String, String)] = []
        if let k = a.details["kind"] { out.append(("doc.text", "Kind", k, a.source)) }
        if let o = a.details["organization"] { out.append(("building.2", "Organization", o, a.source)) }
        if let d = a.details["date"].flatMap({ ISO8601DateFormatter().date(from: $0) }) { out.append(("calendar", "Date", d.formatted(.dateTime.month(.wide).year()), a.source)) }
        if a.oldName != nil && a.source != "you" { out.append(("viewfinder", "Old name", oldNameLine(a), "from name")) }
        if a.source == "you" { out.append(("person", "Renamed by", "You", "you")) }
        return out
    }

    // MARK: Rule suggestion

    func conditionLead(_ c: Condition) -> (String, String) {
        switch c.field {
        case .name: return ("name contains", c.value.replacingOccurrences(of: "*", with: ""))
        case .ext: return ("extension is", "." + c.value)
        case .from: return ("downloaded from", c.value)
        case .size: return ("size over", c.value)
        }
    }

    func ruleTitle(_ r: RuleSuggestion) -> String {
        let (_, v) = conditionLead(r.condition)
        let s = "\(m.settings.emoji(for: r.shelf)) \(r.shelf)"
        switch r.condition.field {
        case .name: return "Put “\(v)” files in \(s)?"
        case .ext: return "Put \(v) files in \(s)?"
        case .from: return "Put files from \(v) in \(s)?"
        case .size: return "Put files over \(v) in \(s)?"
        }
    }

    /// A new shelf for what piles up in Unsorted: the files it would take, and what Accept does.
    func shelfDetail(_ s: ShelfSuggestion) -> some View {
        let t = Tint.rule
        return VStack(alignment: .leading, spacing: 10) {
            DecidedTitle()
            Text("\(s.files.count) files in ❓ Unsorted \(s.kind == .ext ? "share the .\(s.key) extension" : "start with “\(s.key)”"). \(s.emoji) \(s.name) would hold them, and new ones like them.")
                .font(.system(size: TS.body)).foregroundStyle(K.text).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(s.files.prefix(6)), id: \.self) { f in
                    Text((f as NSString).lastPathComponent).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1).truncationMode(.middle)
                }
                if s.files.count > 6 { Text("and \(s.files.count - 6) more").font(.system(size: TS.small)).foregroundStyle(K.text2) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.bg))
            Text("Nothing moves until you accept. Undo puts every file back in one step.").font(.system(size: TS.small)).foregroundStyle(K.text2)
        }
    }

    func ruleDetail(_ r: RuleSuggestion) -> some View {
        let t = Tint.rule
        let path = r.files.compactMap { f in m.actions.last { $0.name == f }?.dst }.first ?? ""
        let (lead, value) = conditionLead(r.condition)
        let from = m.pending.corrections.first { c in r.files.contains(c.name) }?.fromShelf
        let moved = showAllRule ? r.files : Array(r.files.prefix(2))
        let others = otherFiles(on: r.shelf, excluding: r.files).prefix(showAllRule ? 4 : 2)
        return Group {
            StackHero(tint: t, path: path, title: ruleTitle(r), sub: "\(r.files.count) \(r.files.count == 1 ? "file" : "files") you moved match", note: "Applies to new files only. Edit or remove the rule anytime in Sorting.", showAll: r.files.count > 2 ? { withAnimation(Motion.spring(0.3)) { showAllRule.toggle() } } : nil)
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle()
                FlowLayout(spacing: 8) {
                    Text(lead).font(.system(size: TS.body)).foregroundStyle(K.text2).fixedSize().frame(height: 26)
                    Text(value).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(t.fg).fixedSize().padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(t.bg))
                    Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(K.text3).frame(height: 26)
                    Text("\(m.settings.emoji(for: r.shelf)) \(r.shelf)").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text).fixedSize().padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(K.card))
                    Text("\(r.files.count) of \(r.files.count) moves").font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize().frame(height: 26)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.fill))
                .accessibilityElement(children: .combine)
            }
            HStack(alignment: .center, spacing: 8) {
                fileColumn(title: from.map { "\(m.settings.emoji(for: $0)) \($0)" } ?? "Where they were", icon: "folder", files: moved.map { ($0, "arrow.right", true) }, tint: t)
                Image(systemName: "arrow.right").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(t.fg).frame(width: 28, height: 28).background(Circle().fill(t.bg)).accessibilityHidden(true)
                fileColumn(title: "\(m.settings.emoji(for: r.shelf)) \(r.shelf)", icon: "folder", files: moved.map { ($0, "plus", true) } + others.map { ($0, "", false) }, tint: t)
            }
            HStack(spacing: 6) {
                Spacer()
                Image(systemName: "sparkles").font(.system(size: TS.small))
                Text("Also applies to new files").font(.system(size: TS.small))
            }
            .foregroundStyle(K.text2)
        }
    }

    func otherFiles(on shelf: String, excluding: [String]) -> [String] {
        for root in m.settings.activeRoots {
            let dir = root.appendingPathComponent(Library.mine).appendingPathComponent(shelf)
            if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                return names.filter { !$0.hasPrefix(".") && !excluding.contains($0) && $0 != "Icon\r" }.sorted()
            }
        }
        return []
    }

    func fileColumn(title: String, icon: String, files: [(String, String, Bool)], tint t: Tint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Image(systemName: icon).font(.system(size: TS.small)).foregroundStyle(K.text2); Text(title).font(.system(size: TS.body, weight: .bold)).foregroundStyle(K.text).lineLimit(1) }
                .padding(.horizontal, 4).padding(.bottom, 2)
            ForEach(Array(files.enumerated()), id: \.offset) { _, f in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: TS.small))
                    Text(f.0).font(.system(size: TS.small, weight: f.2 ? .medium : .regular)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if !f.1.isEmpty { Image(systemName: f.1).font(.system(size: TS.meta, weight: .semibold)) }
                }
                .foregroundStyle(f.2 ? t.fg : K.text3).padding(.horizontal, 8).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(f.2 ? t.bg : K.card))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(f.2 ? t.stroke : K.separator, lineWidth: 0.75))
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(K.fill))
        .accessibilityElement(children: .combine)
    }

    // MARK: Duplicate, installer, trash, waiting, undone

    func duplicateDetail(_ a: Action) -> some View {
        let t = Tint.duplicate
        let kept = a.details["kept"] ?? ""
        let size = Int64(a.details["size"] ?? "") ?? 0
        return Group {
            HeroBlock(tint: t) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        HStack(spacing: 8) {
                            Thumb(path: kept).frame(width: 64, height: 82)
                            Text("=").font(.system(size: TS.heading, weight: .semibold)).foregroundStyle(t.fg)
                            Thumb(path: a.dst).frame(width: 64, height: 82)
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Copy of \((kept as NSString).lastPathComponent) held").font(.system(size: TS.heading, weight: .bold)).foregroundStyle(t.fg).fixedSize(horizontal: false, vertical: true)
                            Text(a.undone ? "Undone. The file is back where it was." : "The copy was moved to 🪞 Duplicates. Nothing was deleted.").font(.system(size: TS.body)).foregroundStyle(t.fg).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    InfoNote(tint: t, text: "Kept: \(shelfName(kept)) · \(size.bytes). Extra copy added \(a.ts.relative).")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(text: "How Kanso knew")
                RowStack(fill: K.card) {
                    DecisionRow(icon: "ruler", label: "Same size", source: "metadata only") { Text("\(size.formatted()) bytes") }
                    Hairline()
                    DecisionRow(icon: "touchid", label: "Same hash", source: "metadata only") { Text("Identical, byte for byte") }
                    Hairline()
                    DecisionRow(icon: "checkmark.shield", label: "Kept", source: "metadata only") { Text(a.details["keptWhy"] ?? "The \(m.settings.keeper == .bestNamed ? "better-named" : "older") copy") }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
            }
        }
    }

    func shelfName(_ path: String) -> String {
        let s = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return "\(m.settings.emoji(for: s)) \(s)"
    }

    func trashedDetail(_ a: Action) -> some View {
        let size = (Int64(a.details["size"] ?? "") ?? 0).bytes
        if let app = a.details["installer"] {
            return AnyView(Group {
                GlyphHero(tint: .accent, glyph: "eject", emoji: nil, title: "Installed \(app)", sub: "\(app) is installed, so Smart Eject ejected the disk image and moved the installer to the Trash. Put Back any time.", note: nil) {
                    HStack(spacing: 10) {
                        installStep("opticaldisc", "Disk image", size)
                        Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(Tint.accent.fg)
                        installStep("macwindow", app, "In Applications")
                        Image(systemName: "arrow.right").font(.system(size: TS.small)).foregroundStyle(Tint.accent.fg)
                        installStep("trash", "Trash", "Put Back")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    DecidedTitle()
                    RowStack(fill: K.card) {
                        DecisionRow(icon: "opticaldisc", label: "Disk image", source: "metadata only") { Text(a.srcName) }
                        Hairline()
                        DecisionRow(icon: "macwindow", label: "App", source: "ctime check") { Text("\(app) is in Applications") }
                        Hairline()
                        DecisionRow(icon: "checkmark.shield", label: "Safety", source: "always") { Text("Ejected first, then moved to Trash") }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
                }
            })
        }
        return AnyView(Group {
            GlyphHero(tint: .neutral, glyph: "trash", emoji: nil, title: "\(a.srcName) is in the Trash", sub: "Moved to the Trash. Put Back returns it.", note: size) { EmptyView() }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle()
                RowStack(fill: K.card) {
                    DecisionRow(icon: "hand.tap", label: "Moved by", source: a.source) { Text(a.why.hasPrefix("moved to Trash by you") ? "You" : "Kanso") }
                    Hairline()
                    DecisionRow(icon: "scalemass", label: "Size", source: "metadata only") { Text(size) }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
            }
        })
    }

    func installStep(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: TS.emphasis)).foregroundStyle(Tint.accent.fg).frame(width: 34, height: 34).background(Circle().fill(K.card.opacity(0.8)))
            Text(title).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text).lineLimit(1).truncationMode(.middle)
            Text(sub).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(K.card.opacity(0.55)))
    }

    func waitingDetail(_ w: Waiting) -> some View {
        let name = w.partial ? w.url.deletingPathExtension().lastPathComponent : w.url.lastPathComponent
        return Group {
            GlyphHero(tint: .where, glyph: "hourglass", emoji: nil, title: "\(name) is still \(w.partial ? "downloading" : "changing")", sub: "Kanso never moves a file that is still changing. It will be sorted when it's done.", note: "\(w.size.bytes) so far") { EmptyView() }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle()
                RowStack(fill: K.card) {
                    DecisionRow(icon: "hourglass", label: "Status", source: "live") { Text(w.size.bytes + " so far") }
                    Hairline()
                    DecisionRow(icon: "folder", label: "Will go to", source: "By kind") { Text(w.shelf.map { "\(m.settings.emoji(for: $0)) \($0)" } ?? "Decided when it's done") }
                    Hairline()
                    DecisionRow(icon: "checkmark.shield", label: "Rule", source: "always") { Text("Partial downloads are never moved") }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
            }
        }
    }

    func undoneDetail(_ a: Action) -> some View {
        Group {
            GlyphHero(tint: .neutral, glyph: "arrow.uturn.backward", emoji: nil, title: a.kind == .trashed ? a.srcName : a.name, sub: "Undone. The file is back where it was.", note: "Kanso added the Keep tag so it stays put.") { EmptyView() }
            VStack(alignment: .leading, spacing: 8) {
                DecidedTitle(text: "What happened")
                RowStack(fill: K.card) {
                    DecisionRow(icon: "arrow.right", label: "Was", source: "undone") { Text(summary(a)) }
                    Hairline()
                    DecisionRow(icon: "folder", label: "Now in", source: "restored") { Text((a.src as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")) }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
            }
        }
    }

    // MARK: Actions

    /// Pills sit bottom right on one row; in a narrow column they wrap to a second line instead of truncating.
    var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { Spacer(minLength: 0); actionItems }
            FlowLayout(spacing: 8) { actionItems }
        }
    }

    @ViewBuilder var actionItems: some View {
        Group {
            switch entry {
            case .need(.duplicate(let a)):
                Button { m.undo([a.id]) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(SecondaryStyle()).keyboardShortcut("z").help("Undo (⌘Z)").accessibilityLabel("Undo")
                Button("Keep both") { m.keepBoth(a.id) }.buttonStyle(SecondaryStyle())
                Button { m.trash(a.id) } label: { HStack { Text("Move copy to Trash"); Hint(text: "⌘⌫") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut(.delete, modifiers: .command)
            case .need(.renames(let p, _)):
                if expanded {
                    let list = renameGroups(p).flatMap(\.items)
                    if list.indices.contains(min(index, list.count - 1)) {
                        let r = list[min(index, list.count - 1)]
                        Button("Edit name…") { editOpen = true }.buttonStyle(SecondaryStyle())
                            .popover(isPresented: $editOpen, arrowEdge: .top) { NamePopover(title: "Name for \(r.name)", initial: r.newName, commit: { m.editProposal(r.id, name: $0); return true }, close: { editOpen = false }) }
                        Button { m.applyRenames([r]); if list.count <= 1 { collapse() } } label: { HStack { Text("Rename this file"); Hint(text: "↩") } }
                            .buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut(.defaultAction)
                    }
                } else {
                    let clear = p.filter(isClear)
                    Button("Not now") { m.dismissRenames() }.buttonStyle(LinkStyle(color: K.text2))
                    Button("Review one by one") { expand(0) }.buttonStyle(SecondaryStyle())
                    Button { m.applyRenames(clear) } label: { HStack { Text("Rename all"); Hint(text: "↩") } }
                        .buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut(.defaultAction).disabled(clear.isEmpty)
                }
            case .need(.shelf(let s)):
                Button("Dismiss") { m.dismissShelf(s.id) }.buttonStyle(LinkStyle(color: K.text2))
                Button { m.acceptShelf(s.id) } label: { HStack { Text("Create \(s.name)"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut(.defaultAction)
            case .need(.rule(let r)):
                Button("No thanks") { m.dismissSuggestion(r.id) }.buttonStyle(LinkStyle(color: K.text2))
                Button("Edit…") { m.acceptSuggestion(r.id); Windows.shared.showMain(.sorting) }.buttonStyle(SecondaryStyle())
                Button { m.acceptSuggestion(r.id) } label: { HStack { Text("Create rule"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut(.defaultAction)
            case .action(let a):
                if a.undone {
                    Button("Show in Finder") { m.reveal(a.src) }.buttonStyle(SecondaryStyle())
                } else if a.kind == .trashed {
                    Button { m.undo([a.id]) } label: { HStack { Image(systemName: "arrow.uturn.backward"); Text("Put Back"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
                } else {
                    Button { m.undo([a.id]) } label: { HStack { Image(systemName: "arrow.uturn.backward"); Text(a.kind == .duplicate ? "Undo" : "Undo move"); Hint(text: "⌘Z") } }
                        .buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
                    Button("Rename…") { renameOpen = true }.buttonStyle(SecondaryStyle())
                        .popover(isPresented: $renameOpen, arrowEdge: .top) { NamePopover(title: "Rename \(a.name)", initial: a.name, commit: { m.renameFile(a.id, to: $0) }, close: { renameOpen = false }) }
                }
            case .batch(let run, let a):
                if expanded {
                    let i = min(index, max(a.count - 1, 0))
                    if a.indices.contains(i) {
                        let f = a[i]
                        if f.undone { Button("Show in Finder") { m.reveal(f.src) }.buttonStyle(SecondaryStyle()) }
                        else {
                            Button { m.undo([f.id]) } label: { HStack { Image(systemName: "arrow.uturn.backward"); Text("Undo this file"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
                        }
                        Button { if i < a.count - 1 { step(1, a.count) } else { collapse() } } label: { HStack { Text("Keep change"); Hint(text: "↩") } }
                            .buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Review files…") { expand(0) }.buttonStyle(SecondaryStyle())
                    Button { m.undoRun(run) } label: { HStack { Text("Undo all"); Hint(text: "⌘Z") } }.buttonStyle(PrimaryStyle(tint: .duplicate)).keyboardShortcut("z")
                        .disabled(a.allSatisfy(\.undone))
                }
            case .waiting(let w):
                Button("Show in Finder") { m.reveal(w.url.path) }.buttonStyle(SecondaryStyle())
                Button("Don't sort this file") { m.keep(w.url) }.buttonStyle(SecondaryStyle())
            }
        }
        .fixedSize()
    }

    /// The Renamed layout's bottom bar: Undo rename, Rename…, and the shortcuts button.
    @ViewBuilder var flatBar: some View {
        if case .action(let a) = entry {
            HStack(spacing: 8) {
                Button { m.undo([a.id]) } label: { HStack(spacing: 8) { Text("Undo rename"); Keycap(key: "⌘Z") } }
                    .buttonStyle(PrimaryStyle(tint: .accent)).keyboardShortcut("z").fixedSize()
                Button("Rename…") { renameOpen = true }.buttonStyle(SecondaryStyle()).fixedSize()
                    .popover(isPresented: $renameOpen, arrowEdge: .top) { NamePopover(title: "Rename \(a.name)", initial: a.name, commit: { m.renameFile(a.id, to: $0) }, close: { renameOpen = false }) }
                Spacer(minLength: 4)
                keysButton(labelled: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(K.separator).frame(height: 0.75) }
        }
    }
}
