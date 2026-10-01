import AppKit
import KansoCore
import SwiftUI

/// What the ask field is showing (v1.1, ADR 0001). Kanso writes every confirmation itself; model text only ever appears as an answer.
enum AskState: Equatable {
    case idle
    case thinking
    case move(shelf: String, ids: [UUID])
    case trash(ids: [UUID])
    case answer(String, tainted: Bool, ids: [UUID])

    var isProposal: Bool {
        switch self { case .move, .trash, .answer: return true; default: return false }
    }
}

extension Island {
    /// macOS 26 with Apple Intelligence on; hidden otherwise (v1 reserves the slot).
    var askAvailable: Bool { Motion.snapshot || AppModel.shared.ai.available }

    /// The closed set of files the model may name: the shown notices, else the last few sorts.
    func askContext() -> [Action] {
        let m = AppModel.shared
        var out: [Action] = []
        for n in notices { switch n { case .renamed(let a), .duplicate(let a), .installer(let a): out.append(a); default: break } }
        if out.isEmpty { out = Array(m.done.prefix(5)) }
        return out
    }

    /// Held duplicates (the Duplicates shelf) may also be trashed by id, never by path.
    func askTrashSet(_ ctx: [Action]) -> [Action] {
        let held = AppModel.shared.actions.filter { $0.kind == .duplicate && $0.pending && !$0.undone }
        var seen = Set<UUID>(); return (ctx + held).filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
    }

    func submitAsk() {
        let q = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, askState != .thinking else { return }
        askHistory.append(q); askHistoryIndex = askHistory.count
        askText = ""
        askReadyAt = Date().addingTimeInterval(1)
        withAnimation(Motion.spring()) { askState = .thinking }
        let m = AppModel.shared
        let ctx = askContext()
        let trashable = askTrashSet(ctx)
        // The numbered list: context first, then held duplicates.
        let items = trashable.enumerated().map { AskItem(index: $0.offset, name: $0.element.name, detail: $0.element.kind == .duplicate ? "extra copy, \((Int64($0.element.details["size"] ?? "") ?? 0).bytes)" : "\($0.element.kind.rawValue) to \($0.element.shelf)") }
        let shelves = m.settings.types.map(\.name)
        let ai = m.ai
        askTask?.cancel()
        askTask = Task { @MainActor in
            let r = await ai.ask(q, items: items, shelves: shelves, canTrash: true)
            if Task.isCancelled { return }
            func ids(_ i: [Int]) -> [UUID] { i.compactMap { trashable.indices.contains($0) ? trashable[$0].id : nil } }
            withAnimation(Motion.spring()) {
                switch r {
                case .move(let shelf, let i)?: askState = .move(shelf: shelf, ids: ids(i))
                case .trash(let i)?: askState = .trash(ids: ids(i))
                case .answer(let t)?: askState = .answer(t, tainted: false, ids: [])
                case .read(let i)?: break
                case nil: askState = .answer("Apple Intelligence couldn't answer that. Nothing changed.", tainted: false, ids: [])
                }
            }
            if case .read(let i)? = r {
                // Reading a little of a file taints the request: answer, but never offer trash as a tool (ADR 0001).
                let chosen = ids(i).compactMap { id in trashable.first { $0.id == id } }
                let texts = chosen.compactMap { a in Reader.text(URL(fileURLWithPath: a.dst), shelf: a.shelf).map { (name: a.name, text: $0.text) } }
                let ans = texts.isEmpty ? nil : await ai.describe(q, texts: texts)
                withAnimation(Motion.spring()) { askState = .answer((ans ?? "That file can't be read here."), tainted: !texts.isEmpty, ids: chosen.map(\.id)) }
            }
        }
    }

    func recallAsk() {
        guard !askHistory.isEmpty else { return }
        askHistoryIndex = max(0, askHistoryIndex - 1)
        askText = askHistory[askHistoryIndex]
    }

    func cancelAsk() { askTask?.cancel(); withAnimation(Motion.spring()) { askState = .idle } }

    /// Return confirms a move; only ⌘⌫ confirms a trash, and Return is inert for 1 s after a submit.
    func confirmAsk(trash: Bool) {
        let m = AppModel.shared
        guard Date() >= askReadyAt else { return }
        switch askState {
        case .move(let shelf, let ids) where !trash:
            for id in ids { m.move(id, to: shelf) }
            m.refresh()
        case .trash(let ids) where trash:
            for id in ids.prefix(20) { m.trash(id) }
        default: return
        }
        withAnimation(Motion.spring()) { askState = .idle }
    }
}

// MARK: Views

struct AskField: View {
    @EnvironmentObject var island: Island
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: TS.body)).foregroundStyle(Color.white.opacity(0.55))
            TextField("Ask about these files…", text: $island.askText).textFieldStyle(.plain).font(.system(size: TS.body))
                .foregroundStyle(island.askFocus ? IslandInk.text : Color.white.opacity(0.6)).focused($focused)
                .onSubmit { island.submitAsk() }
            if island.askState == .thinking {
                ThinkingOrb()
                Text("Thinking…").font(.system(size: TS.small)).foregroundStyle(Color.white.opacity(0.6))
            } else if island.askText.isEmpty {
                Text(island.askHistory.isEmpty ? "Tab" : "sent · ↑ recalls").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3)
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .overlay { if island.askState == .thinking && !Motion.reduced { Beam().allowsHitTesting(false) } }
        .onChange(of: island.askFocus) { _, f in focused = f }
        .onChange(of: focused) { _, f in if island.askFocus != f { island.askFocus = f } }
        .accessibilityLabel("Ask about these files")
    }
}

/// The thinking orb: mint to periwinkle to lavender, shown beside a label.
struct ThinkingOrb: View {
    var body: some View {
        Circle().fill(AngularGradient(colors: [Color(nsColor: NSColor(hex: 0xCFE8D8)), Color(nsColor: NSColor(hex: 0xD9E0FA)), Color(nsColor: NSColor(hex: 0xE5DCF7)), Color(nsColor: NSColor(hex: 0xCFE8D8))], center: .center))
            .frame(width: 18, height: 18).blur(radius: 0.6).overlay(Circle().fill(Color.white.opacity(0.5)).frame(width: 6, height: 6)).accessibilityHidden(true)
    }
}

/// A mono sage line that travels along the field's edge from submit until the answer lands.
struct Beam: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: Color(nsColor: NSColor(hex: 0x8FC9A8)), location: 0.08), .init(color: .clear, location: 0.2), .init(color: .clear, location: 1)], center: .center, angle: .degrees(t * 360)), lineWidth: 1.5)
        }
    }
}

/// The proposal above the field: a preview line, a butter trash card written by Kanso, or an answer.
struct AskProposal: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel

    var body: some View {
        switch island.askState {
        case .move(let shelf, let ids):
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus").font(.system(size: TS.body)).foregroundStyle(Color.white.opacity(0.7))
                Text("Move \(ids.count) \(ids.count == 1 ? "file" : "files") → \(m.settings.emoji(for: shelf)) \(shelf)").font(.system(size: TS.body, weight: .medium)).foregroundStyle(IslandInk.text)
                Spacer()
                pill("Move \(ids.count) \(ids.count == 1 ? "file" : "files")", "↩", prominent: true) { island.confirmAsk(trash: false) }
                pill("Cancel", "esc") { island.cancelAsk() }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))
        case .trash(let ids):
            // Written from the journal, never from model text.
            let acts = ids.compactMap { id in m.actions.first { $0.id == id } }
            let total = acts.reduce(Int64(0)) { $0 + (Int64($1.details["size"] ?? "") ?? 0) }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: "trash").font(.system(size: TS.small)); Text("Move \(acts.count) \(acts.count == 1 ? "file" : "files") to Trash (\(total.bytes))").font(.system(size: TS.body, weight: .semibold)); Spacer(); Text("written by Kanso").font(.system(size: TS.meta)).opacity(0.7) }
                    ForEach(acts.prefix(5)) { a in
                        HStack { Image(systemName: "doc").font(.system(size: TS.meta)); Text(a.name).font(.system(size: TS.small, weight: .medium)).lineLimit(1); Spacer()
                            Text(detail(a)).font(.system(size: TS.meta)).opacity(0.75).lineLimit(1) }
                    }
                    if acts.count > 5 { Text("+ \(acts.count - 5) more").font(.system(size: TS.meta)).opacity(0.75) }
                }
                .foregroundStyle(Tint.duplicate.fg).padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: NSColor(hex: 0xF7E4B5))))
                .environment(\.colorScheme, .light)
                HStack(spacing: 8) {
                    pill("Move \(acts.count) to Trash", "⌘⌫", prominent: true) { island.confirmAsk(trash: true) }
                    pill("Cancel", "esc") { island.cancelAsk() }
                }
            }
        case .answer(let text, let tainted, let ids):
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.system(size: TS.body)).foregroundStyle(IslandInk.text).fixedSize(horizontal: false, vertical: true)
                if tainted, !ids.isEmpty {
                    // The request read file contents: no trash tool, only a plain button the user presses.
                    HStack(spacing: 8) {
                        if let a = m.actions.first(where: { $0.id == ids[0] }) {
                            pill("Open", "⌘O", icon: "doc") { NSWorkspace.shared.open(URL(fileURLWithPath: a.dst)) }
                            pill("Move to Trash…", "⌘⌫", icon: "trash") { island.askState = .trash(ids: [a.id]) }
                            pill("Reveal in Finder", "⌘R", icon: "folder.badge.magnifyingglass") { m.reveal(a.dst) }
                        }
                    }
                }
            }
        default: EmptyView()
        }
    }

    func detail(_ a: Action) -> String {
        let size = (Int64(a.details["size"] ?? "") ?? 0).bytes
        if a.kind == .duplicate, let kept = a.details["kept"] {
            let shelf = ((kept as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return "\(size) · same bytes as \((kept as NSString).lastPathComponent) on \(m.settings.emoji(for: shelf)) \(shelf)"
        }
        return "\(size) · \(a.shelf)"
    }

    func pill(_ label: String, _ key: String, icon: String? = nil, prominent: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: TS.small)).foregroundStyle(Color.white.opacity(0.7)) }
                Text(label).font(.system(size: TS.small, weight: .medium)).foregroundStyle(Color.white.opacity(0.9))
                Text(key).font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Color.white.opacity(prominent ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}
