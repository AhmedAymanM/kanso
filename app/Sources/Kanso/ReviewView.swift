import KansoCore
import SwiftUI

/// Mass renames and the Sort everything preview. Space toggles, ⌘⌫ unchecks, ⌘Z undoes the last uncheck, ↩ applies.
struct ReviewView: View {
    @EnvironmentObject var m: AppModel
    @State var tab: Windows.ReviewTab
    @State private var renames: [RenameProposal] = []
    @State private var excluded: Set<UUID> = []
    @State private var history: [Set<UUID>] = []
    @State private var selection: UUID?
    @State private var query = ""
    @FocusState private var focused: Bool

    init(tab: Windows.ReviewTab) { _tab = State(initialValue: tab) }

    var sortRows: [Planned] { m.preview.filter { query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query) || $0.shelf.localizedCaseInsensitiveContains(query) } }
    var renameRows: [RenameProposal] { renames.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.newName.localizedCaseInsensitiveContains(query) } }
    var ids: [UUID] { tab == .renames ? renameRows.map(\.id) : sortRows.map(\.id) }
    var total: Int { tab == .renames ? renames.count : m.preview.count }
    var chosen: Int { total - excluded.count }
    var tint: Color { tab == .renames ? Tint.rename.fg : K.accent }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(K.text)
                        Text(tab == .renames ? "Uncheck anything you want to keep as is. Original names stay searchable, and every rename can be undone."
                             : "This is the plan for files already in your folders. Uncheck anything that should stay. Everything can be undone.")
                            .font(.system(size: TS.body)).foregroundStyle(K.text2)
                    }
                    Spacer()
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(K.text3); TextField("Filter names", text: $query).textFieldStyle(.plain) }
                        .padding(.horizontal, 10).frame(width: 200, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(K.fillStrong))
                }
                table
            }
            .padding(.horizontal, 24).padding(.top, 18)
            footer
        }
        .background(K.window)
        .ignoresSafeArea()
        .focusEffectDisabled()
        .onAppear { renames = m.pending.renames; focused = true }
        .onChange(of: tab) { _, _ in excluded = []; history = []; selection = nil }
        .focusable()
        .focused($focused)
        .onKeyPress(.space) { if let s = selection { toggle(s) }; return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }

    var headline: String {
        if tab == .renames {
            let roots = Set(renames.compactMap { r in m.settings.activeRoots.first { r.path.hasPrefix($0.path + "/") } })
            let folder = roots.count == 1 ? "\(folderEmoji(roots.first!.path)) \(roots.first!.lastPathComponent)" : "your folders"
            return renames.isEmpty ? "Nothing to rename" : "\(renames.count) files in \(folder) can be renamed"
        }
        return m.preview.isEmpty ? "Everything is already on a shelf" : "\(m.preview.count) files are ready for their shelves"
    }

    var titleBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                segment("Renames", renames.count, .renames)
                segment("Sort preview", m.preview.count, .sort)
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(K.fillStrong))
            Spacer()
        }
        .frame(height: 52)
        .background(K.neutralBg)
        .overlay(alignment: .bottom) { Rectangle().fill(K.separator).frame(height: 0.75) }
    }

    func segment(_ t: String, _ n: Int, _ v: Windows.ReviewTab) -> some View {
        Button { tab = v } label: {
            HStack(spacing: 6) { Text(t).font(.system(size: TS.small, weight: tab == v ? .semibold : .regular)); Text("\(n)").font(.system(size: TS.meta)).foregroundStyle(K.text3) }
                .foregroundStyle(K.text).padding(.horizontal, 14).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(tab == v ? K.card : .clear).shadow(color: .black.opacity(tab == v ? 0.08 : 0), radius: 1, y: 0.5))
        }
        .buttonStyle(PlainRowStyle())
    }

    var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { toggleAll() } label: { checkbox(excluded.isEmpty ? .on : excluded.count == total ? .off : .mixed) }.buttonStyle(PlainRowStyle()).accessibilityLabel("Select all")
                Text("Current name").frame(maxWidth: .infinity, alignment: .leading)
                Text(tab == .renames ? "New name" : "New name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Shelf").frame(width: 130, alignment: .leading)
                Text("From").frame(width: 110, alignment: .leading)
            }
            .eyebrow().padding(.horizontal, 10).frame(height: 30)
            Rectangle().fill(K.separator).frame(height: 0.75)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if tab == .renames {
                        ForEach(renameRows) { r in renameRow(r) }
                    } else {
                        ForEach(sortRows) { p in sortRow(p) }
                    }
                    if ids.isEmpty {
                        Text(tab == .renames ? "No meaningless names waiting for review." : "Nothing to sort. Your folders are in order.").font(.system(size: TS.body)).foregroundStyle(K.text2).padding(30)
                    }
                }
            }
        }
    }

    enum Check { case on, off, mixed }

    func checkbox(_ c: Check) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(c == .off ? K.card : tint)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(c == .off ? K.text3 : .clear, lineWidth: 1))
            .overlay(Image(systemName: c == .mixed ? "minus" : "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).opacity(c == .off ? 0 : 1))
            .frame(width: 16, height: 16)
    }

    func renameRow(_ r: RenameProposal) -> some View {
        let on = !excluded.contains(r.id)
        return row(id: r.id, on: on) {
            Label { Text(r.name).lineLimit(1).truncationMode(.middle) } icon: { Image(systemName: "doc.text") }
                .font(.system(size: TS.body)).foregroundStyle(on ? K.text2 : K.text3).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.system(size: TS.micro)).foregroundStyle(on ? K.text2 : K.text3)
                if on {
                    TextField("", text: Binding(get: { renames.first { $0.id == r.id }?.newName ?? "" }, set: { v in if let i = renames.firstIndex(where: { $0.id == r.id }) { renames[i].newName = v } }))
                        .textFieldStyle(.plain).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                } else {
                    Text("Keep “\(r.name)”").font(.system(size: TS.body)).foregroundStyle(K.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(m.settings.emoji(for: r.shelf)) \(r.shelf)").font(.system(size: TS.small)).foregroundStyle(on ? K.text2 : K.text3).frame(width: 130, alignment: .leading)
            Pill(text: r.source.replacingOccurrences(of: "contents, page 1", with: "contents, p.1")).opacity(on ? 1 : 0.5).frame(width: 110, alignment: .leading)
        }
    }

    func sortRow(_ p: Planned) -> some View {
        let on = !excluded.contains(p.id)
        let root = p.item.root.lastPathComponent
        return row(id: p.id, on: on) {
            Label { Text(p.item.name).lineLimit(1).truncationMode(.middle) } icon: { Text(folderEmoji(p.item.root.path)).font(.system(size: TS.meta)) }
                .font(.system(size: TS.body)).foregroundStyle(on ? K.text : K.text3).frame(maxWidth: .infinity, alignment: .leading).help("\(root)/\(p.item.name)")
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.system(size: TS.micro)).foregroundStyle(K.text3)
                Text(p.kind == .duplicate ? "Duplicate of \((p.details["kept"].map { ($0 as NSString).lastPathComponent }) ?? "")" : (p.proposedName.map { "Rename later: \($0)" } ?? "Same name"))
                    .font(.system(size: TS.small)).foregroundStyle(p.kind == .duplicate ? Tint.duplicate.fg : K.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(m.settings.emoji(for: p.shelf)) \(p.shelf)").font(.system(size: TS.small, weight: .medium)).foregroundStyle(on ? K.text : K.text3).frame(width: 130, alignment: .leading)
            Pill(text: p.source == "metadata only" ? (p.why == "extension" ? "extension" : p.why.hasPrefix("rule") ? "your rule" : p.why) : p.source).opacity(on ? 1 : 0.5).frame(width: 110, alignment: .leading)
        }
    }

    func row<C: View>(id: UUID, on: Bool, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { toggle(id) } label: { checkbox(on ? .on : .off) }.buttonStyle(PlainRowStyle()).accessibilityLabel(on ? "Included" : "Excluded")
                content()
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(selection == id ? tint.opacity(0.08) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { selection = id; focused = true }
            Rectangle().fill(K.separator).frame(height: 0.5)
        }
    }

    var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { Keycap(key: "Space"); Text("toggle") }
            HStack(spacing: 5) { Keycap(key: "⌘Z"); Text("undo") }
            HStack(spacing: 5) { Keycap(key: "⌘⌫"); Text("uncheck") }
            HStack(spacing: 5) { Keycap(key: "↩"); Text("apply") }
            Spacer()
            Text("\(chosen) of \(total) selected").font(.system(size: TS.small)).foregroundStyle(K.text2)
            Button("Cancel") { Windows.shared.closeReview() }.buttonStyle(SecondaryStyle()).keyboardShortcut(.cancelAction)
            Button { apply() } label: { HStack(spacing: 6) { Text(tab == .renames ? "Rename \(chosen) files" : "Sort \(chosen) files"); Hint(text: "↩") } }
                .buttonStyle(PrimaryStyle(tint: tab == .renames ? .rename : .accent)).keyboardShortcut(.defaultAction).disabled(chosen == 0)
            // Hidden buttons carry the review shortcuts.
            Button("") { undoUncheck() }.keyboardShortcut("z").hidden().frame(width: 0)
            Button("") { if let s = selection, !excluded.contains(s) { toggle(s) } }.keyboardShortcut(.delete, modifiers: .command).hidden().frame(width: 0)
        }
        .font(.system(size: TS.meta)).foregroundStyle(K.text2)
        .padding(.horizontal, 24).frame(height: 60)
        .background(K.neutralBg)
        .overlay(alignment: .top) { Rectangle().fill(K.separator).frame(height: 0.75) }
    }

    func toggle(_ id: UUID) {
        history.append(excluded)
        if excluded.contains(id) { excluded.remove(id) } else { excluded.insert(id) }
    }

    func toggleAll() {
        history.append(excluded)
        excluded = excluded.isEmpty ? Set(tab == .renames ? renames.map(\.id) : m.preview.map(\.id)) : []
    }

    func undoUncheck() { if let last = history.popLast() { excluded = last } }

    func move(_ d: Int) {
        guard !ids.isEmpty else { return }
        let i = selection.flatMap { ids.firstIndex(of: $0) } ?? (d > 0 ? -1 : ids.count)
        selection = ids[max(0, min(ids.count - 1, i + d))]
    }

    func apply() {
        if tab == .renames {
            m.applyRenames(renames.filter { !excluded.contains($0.id) })
            m.engine.dismissRenames(Set(excluded))
            m.refresh()
        } else {
            var moves = m.preview
            for i in moves.indices { moves[i].include = !excluded.contains(moves[i].id) }
            m.applyPreview(moves)
            if !m.pending.renames.isEmpty { renames = m.pending.renames; excluded = []; history = []; tab = .renames; return }
        }
        Windows.shared.closeReview()
    }
}
