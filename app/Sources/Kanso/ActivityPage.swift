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
            listColumn(list, selected: selected?.id).frame(width: 340)
            if let selected {
                // Activity v3: the detail is one rounded card with a soft border.
                let flat = EntryDetail.isFlat(selected)   // the final Renamed layout (tag flow) has no card
                EntryDetail(entry: selected, next: next(after: selected, in: list)).id(selected.id)
                    .transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(x: 12)))
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(flat ? Color.clear : K.card))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(flat ? Color.clear : K.separator, lineWidth: 0.75))
                    .overlay(alignment: .leading) { if flat { Rectangle().fill(K.separator).frame(width: 0.75).padding(.top, 8) } }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4).padding(.trailing, 12).padding(.bottom, 12)
            } else {
                emptyState
            }
        }
        .background { KeyCatcher(keys: [126: { move(-1, list, selected?.id) }, 125: { move(1, list, selected?.id) }]) }
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
                ActivityFilterBar(filter: $filter, needs: m.needs.count)
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
        case .batch: return "📦"
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

/// Arrow keys, esc: a local monitor while the page is on screen, with no text field focused. `keys` maps key codes
/// (126 up, 125 down, 123 left, 124 right, 53 esc) to actions; codes without an entry pass through.
struct KeyCatcher: NSViewRepresentable {
    var keys: [Int: () -> Void]
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ v: NSView, context: Context) { context.coordinator.keys = keys }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let view = NSView()
        var keys: [Int: () -> Void] = [:]
        var monitor: Any?
        init() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.view.window?.isKeyWindow == true, !(self.view.window?.firstResponder is NSText), e.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      let act = self.keys[Int(e.keyCode)] else { return e }
                act(); return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// All / Needs you / Handled: a light track with a raised white pill on the selection (drawn here, not the native blue control).
struct ActivityFilterBar: View {
    @Binding var filter: Filter
    var needs: Int
    @Namespace private var ns
    var body: some View {
        let segs: [(Filter, String)] = [(.all, "All"), (.needs, needs == 0 ? "Needs you" : "Needs you · \(needs)"), (.handled, "Handled")]
        HStack(spacing: 0) {
            ForEach(segs, id: \.0) { seg in
                let on = filter == seg.0
                Button { withAnimation(Motion.spring(0.3)) { filter = seg.0 } } label: {
                    Text(seg.1).font(.system(size: TS.small, weight: on ? .semibold : .regular)).foregroundStyle(on ? K.text : K.text2).lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background {
                            if on {
                                Capsule().fill(K.segThumb).shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                    .overlay(Capsule().strokeBorder(K.separator, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).focusRing(14)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2).frame(maxWidth: .infinity)
        .background(Capsule().fill(K.fill))
        .overlay(Capsule().strokeBorder(K.separator, lineWidth: 0.75))
        .accessibilityElement(children: .contain).accessibilityLabel("Show")
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
