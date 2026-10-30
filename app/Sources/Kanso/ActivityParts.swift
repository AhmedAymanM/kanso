import KansoCore
import SwiftUI

// Building blocks of the Activity detail (Activity v3): heroes, pager, decision rows, tags, small popovers.

// MARK: Finder tag colours (the only hard-coded colours: they are Finder's own label colours)

enum FinderColor {
    /// Finder label index, name, colour — in the order the picker shows them.
    static let all: [(idx: Int, name: String, color: Color)] = [
        (6, "Red", Color(nsColor: NSColor(hex: 0xFF453A))), (7, "Orange", Color(nsColor: NSColor(hex: 0xFF9F0A))),
        (5, "Yellow", Color(nsColor: NSColor(hex: 0xFFD60A))), (2, "Green", Color(nsColor: NSColor(hex: 0x30B35A))),
        (4, "Blue", Color(nsColor: NSColor(hex: 0x0A84FF))), (3, "Purple", Color(nsColor: NSColor(hex: 0xBF5AF2))),
        (1, "Gray", Color(nsColor: NSColor(hex: 0x8E8E93))),
    ]
    static func color(_ idx: Int) -> Color { all.first { $0.idx == idx }?.color ?? all[4].color }
    /// A tag without a stored colour cycles through a few calm ones, so neighbours differ.
    static func fallback(_ i: Int) -> Int { [4, 2, 7, 6][i % 4] }
    static func index(_ a: Action, _ tag: String, _ i: Int) -> Int { a.details["tagcolor:" + tag].flatMap(Int.init) ?? fallback(i) }
}

// MARK: Hero

/// The pastel block at the top of a detail: one tint per kind.
struct HeroBlock<Content: View>: View {
    var tint: Tint
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.bg))
    }
}

/// Three pages fanned out behind a Quick Look preview (rename review, batch, rule).
struct StackArt: View {
    var path: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(K.card.opacity(0.45)).frame(width: 54, height: 72).rotationEffect(.degrees(-9)).offset(x: -24, y: 5)
            RoundedRectangle(cornerRadius: 6).fill(K.card.opacity(0.45)).frame(width: 54, height: 72).rotationEffect(.degrees(7)).offset(x: 24, y: 3)
            HeroPreview(path: path).frame(width: 64, height: 84)
        }
        .frame(width: 112, height: 96)
        .accessibilityHidden(true)
    }
}

/// "Show all →": a quiet capsule inside the hero.
struct ShowAllButton: View {
    var tint: Tint
    var label = "Show all"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                Image(systemName: "arrow.right").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(tint.fg)
                    .frame(width: 22, height: 16).background(RoundedRectangle(cornerRadius: 5).fill(tint.fg.opacity(0.18)))
            }
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(tint.fg.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).focusRing(14)
    }
}

/// The small "i" line under a hero title.
struct InfoNote: View {
    var tint: Tint
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: TS.meta))
            Text(text).font(.system(size: TS.meta)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint.fg)
    }
}

/// Hero with the stack art on the left and a title, line, "Show all" and note on the right.
struct StackHero: View {
    var tint: Tint
    var path: String
    var title: String
    var sub: String
    var note: String
    var showAll: (() -> Void)?
    var body: some View {
        HeroBlock(tint: tint) {
            HStack(alignment: .center, spacing: 14) {
                StackArt(path: path)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(tint.fg).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.system(size: TS.body)).foregroundStyle(tint.fg).fixedSize(horizontal: false, vertical: true)
                    if let showAll { ShowAllButton(tint: tint, action: showAll) }
                    InfoNote(tint: tint, text: note)
                }
            }
        }
    }
}

/// Hero with a big glyph or emoji: duplicates, installers, waiting files, undone entries.
struct GlyphHero<Extra: View>: View {
    var tint: Tint
    var glyph: String?
    var emoji: String?
    var title: String
    var sub: String
    var note: String?
    @ViewBuilder var extra: Extra
    var body: some View {
        HeroBlock(tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Group {
                        if let emoji { Text(emoji).font(.system(size: TS.emoji)) }
                        else if let glyph { Image(systemName: glyph).font(.system(size: TS.title, weight: .medium)).foregroundStyle(tint.fg) }
                    }
                    .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(K.card.opacity(0.7))).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(tint.fg).fixedSize(horizontal: false, vertical: true)
                        Text(sub).font(.system(size: TS.body)).foregroundStyle(tint.fg).fixedSize(horizontal: false, vertical: true)
                        if let note { InfoNote(tint: tint, text: note) }
                    }
                }
                extra
            }
        }
    }
}

// MARK: Pager and file-by-file chrome

/// "← All files", dots, "2 of 42": the top row of an expanded hero.
struct PagerRow: View {
    var tint: Tint
    var index: Int
    var count: Int
    var back: () -> Void
    var step: (Int) -> Void
    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 5) { Image(systemName: "arrow.left").font(.system(size: TS.small, weight: .semibold)); Text("All files").font(.system(size: TS.body, weight: .semibold)) }
                    .foregroundStyle(tint.fg).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusRing(6).accessibilityLabel("Back to all files").help("Back to all files (esc)")
            Spacer()
            HStack(spacing: 8) {
                chev("chevron.left", "Previous file", -1)
                dots
                chev("chevron.right", "Next file", 1)
            }
            Spacer()
            Text("\(index + 1) of \(count)").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(tint.fg).monospacedDigit()
        }
    }
    var dots: some View {
        let lo = max(0, min(index - 3, count - 7)), hi = min(count, lo + 7)
        return HStack(spacing: 4) {
            ForEach(lo..<max(lo, hi), id: \.self) { i in
                Capsule().fill(i == index ? K.text : tint.fg.opacity(0.3)).frame(width: i == index ? 18 : 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
    func chev(_ name: String, _ label: String, _ d: Int) -> some View {
        Button { step(d) } label: { Image(systemName: name).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(tint.fg).frame(width: 20, height: 20).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusRing(6).accessibilityLabel(label)
    }
}

// MARK: Decision section

struct DecidedTitle: View {
    var warn = false
    var text = "How Kanso decided"
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text2)
            if warn { Image(systemName: "exclamationmark.triangle").font(.system(size: TS.small)).foregroundStyle(Tint.duplicate.fg).accessibilityLabel("Something here was a guess") }
        }
    }
}

/// A source chip at the end of a table row ("contents, page 1", "from name", "metadata only").
struct SourceChip: View {
    var text: String
    var body: some View {
        let c = text.hasPrefix("contents")
        Text(text).font(.system(size: TS.meta)).lineLimit(1).fixedSize()
            .foregroundStyle(c ? Tint.rename.fg : K.text2)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(c ? Tint.rename.bg : K.fill))
    }
}

/// One row of a "How Kanso decided" table: icon, label, value, source.
struct DecisionRow<Value: View>: View {
    var icon: String
    var label: String
    var source: String
    @ViewBuilder var value: Value
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: TS.small)).foregroundStyle(K.text2).frame(width: 18)
            Text(label).font(.system(size: TS.body)).foregroundStyle(K.text2).frame(width: 92, alignment: .leading)
            value.font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text).frame(maxWidth: .infinity, alignment: .leading)
            SourceChip(text: source)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

/// Rows separated by hairlines on a quiet rounded surface.
struct RowStack<Content: View>: View {
    var fill: Color = K.fill
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Hairline: View { var body: some View { Rectangle().fill(K.separator).frame(height: 0.75) } }

/// One step of the "Checked in order" ladder.
struct LadderStep: Identifiable {
    enum State { case none, hit, skipped }
    var id = UUID()
    var title: String
    var sub: String
    var state: State
    var chip: String? = nil
}

struct LadderView: View {
    var steps: [LadderStep]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checked in order").font(.system(size: TS.meta, weight: .semibold, design: .monospaced)).kerning(0.5).foregroundStyle(K.text2).textCase(.uppercase)
            VStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in row(i, s) }
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.fill))
        }
    }
    func row(_ i: Int, _ s: LadderStep) -> some View {
        let hit = s.state == .hit, skipped = s.state == .skipped
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(hit ? Tint.accent.bg : K.fillStrong).frame(width: 30, height: 30)
                if hit { Image(systemName: "checkmark").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.accent.fg) }
                else if skipped { Text("\(i + 1)").font(.system(size: TS.small)).foregroundStyle(K.text3) }
                else { Image(systemName: "minus").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text3) }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(skipped ? K.text3 : K.text)
                Text(s.sub).font(.system(size: TS.small)).foregroundStyle(skipped ? K.text3 : K.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let chip = s.chip, hit {
                Text(chip).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.accent.fg).lineLimit(1)
                    .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Tint.accent.bg))
            } else {
                Text(skipped ? "not reached" : "no match").font(.system(size: TS.small)).foregroundStyle(skipped ? K.text3 : K.text2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hit ? K.card : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hit ? K.separator : .clear, lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

/// "1 file was a guess": a white card with a warning triangle and a link on the right.
struct Callout: View {
    var title: String
    var sub: String
    var action: String
    var run: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: TS.emphasis)).foregroundStyle(Tint.duplicate.fg).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: TS.emphasis, weight: .bold)).foregroundStyle(K.text)
                Text(sub).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: run) { Text(action).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.accent).contentShape(Rectangle()) }
                .buttonStyle(.plain).focusRing(6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
    }
}

/// "Filed in [shelf] because …".
struct FiledInRow: View {
    @EnvironmentObject var m: AppModel
    var action: Action
    var why: String
    var body: some View {
        HStack(spacing: 10) {
            Label("Filed in", systemImage: "folder").font(.system(size: TS.small)).foregroundStyle(K.text2)
            MenuPicker(options: shelfOptions, value: Binding(get: { action.shelf }, set: { if $0 != action.shelf { m.move(action.id, to: $0) } }), emoji: { m.settings.emoji(for: $0) })
                .help("Move to another shelf")
            if !why.isEmpty { Text(why).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1) }
        }
    }
    var shelfOptions: [(String, String)] {
        var o = m.settings.types.map { ($0.name, $0.name) }
        if !o.contains(where: { $0.0 == action.shelf }) { o.insert((action.shelf, action.shelf), at: 0) }
        return o
    }
}

// MARK: Tags

/// Tag pills with colour dots and an × to remove, then "+ Add tag" (opens the picker).
struct TagRow: View {
    @EnvironmentObject var m: AppModel
    var action: Action
    var tint: Tint
    @State private var open = false
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(action.tags.enumerated()), id: \.element) { i, t in
                HStack(spacing: 5) {
                    Circle().fill(FinderColor.color(FinderColor.index(action, t, i))).frame(width: 8, height: 8)
                    Text(t).font(.system(size: TS.meta, weight: .medium)).fixedSize()
                    Button { m.removeTag(action.id, t) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 12, height: 12).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Remove tag \(t)")
                }
                .foregroundStyle(tint.fg).padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(K.card.opacity(0.92)))
                .accessibilityElement(children: .combine)
            }
            Button { open = true } label: {
                HStack(spacing: 4) { Image(systemName: "plus").font(.system(size: TS.meta, weight: .semibold)); Text("Add tag").font(.system(size: TS.meta, weight: .medium)) }
                    .foregroundStyle(tint.fg).padding(.horizontal, 8).frame(height: 22)
                    .overlay(Capsule().strokeBorder(tint.stroke.opacity(2), lineWidth: 0.75)).contentShape(Capsule())
            }
            .buttonStyle(.plain).focusRing(11).accessibilityLabel("Add tag")
            .popover(isPresented: $open, arrowEdge: .bottom) { TagPickerHost(action: action, close: { open = false }) }
        }
    }
}

/// Loads the tag counts when the picker opens.
struct TagPickerHost: View {
    @EnvironmentObject var m: AppModel
    var action: Action
    var close: () -> Void
    @State private var counts: [String: Int] = [:]
    var body: some View {
        TagPicker(counts: counts, existing: Set(action.tags)) { name, color in
            m.addTag(action.id, name, color: color); close()
        }
        .task { counts = await m.tagCounts() }
    }
}

/// Type a tag, pick an existing one (↩) or create it (⇧↩), choose a colour with ← → and ↩.
struct TagPicker: View {
    enum Stage: Equatable { case search, color(String) }
    var counts: [String: Int]
    var existing: Set<String>
    var done: (String, Int?) -> Void
    @State private var text: String
    @State private var stage: Stage
    @State private var sel = 0
    @State private var colorIndex: Int
    @FocusState private var focus: Bool

    init(counts: [String: Int], existing: Set<String>, text: String = "", stage: Stage = .search, color: Int = 4, done: @escaping (String, Int?) -> Void) {
        self.counts = counts; self.existing = existing; self.done = done
        _text = State(initialValue: text); _stage = State(initialValue: stage); _colorIndex = State(initialValue: color)
    }

    var matches: [(String, Int)] {
        let q = text.trimmingCharacters(in: .whitespaces)
        return counts.filter { !existing.contains($0.key) && (q.isEmpty || $0.key.localizedCaseInsensitiveContains(q)) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(4).map { ($0.key, $0.value) }
    }
    var canCreate: Bool {
        let q = text.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && !counts.keys.contains { $0.caseInsensitiveCompare(q) == .orderedSame } && !existing.contains(q)
    }
    var rowCount: Int { matches.count + (canCreate ? 1 : 0) }

    var body: some View {
        Group {
            switch stage {
            case .search: search
            case .color(let name): color(name)
            }
        }
        .frame(width: 230).padding(8)
    }

    var search: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Tag name", text: $text).textFieldStyle(.plain).font(.system(size: TS.body)).padding(.horizontal, 8).frame(height: 28)
                .focused($focus).onAppear { focus = true }
                .onChange(of: text) { _, _ in sel = 0 }
                .onSubmit { commit(create: NSEvent.modifierFlags.contains(.shift)) }
                .onKeyPress(.downArrow) { sel = min(sel + 1, max(rowCount - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { sel = max(sel - 1, 0); return .handled }
            if rowCount > 0 { Hairline().padding(.horizontal, 4) }
            ForEach(Array(matches.enumerated()), id: \.element.0) { i, t in
                Button { done(t.0, nil) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(FinderColor.color(FinderColor.fallback(i + 1))).frame(width: 8, height: 8)
                        Text(t.0).font(.system(size: TS.body)).foregroundStyle(K.text)
                        Spacer()
                        Text("\(t.1) files").font(.system(size: TS.small)).foregroundStyle(K.text2)
                        if sel == i { Keycap(key: "↩") }
                    }
                    .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 8).fill(sel == i ? K.fillStrong : .clear))
                }
                .buttonStyle(.plain)
            }
            if canCreate {
                if !matches.isEmpty { Hairline().padding(.horizontal, 4) }
                Button { stage = .color(text.trimmingCharacters(in: .whitespaces)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: TS.small, weight: .semibold))
                        Text("Create tag “\(text.trimmingCharacters(in: .whitespaces))”").font(.system(size: TS.body)).lineLimit(1)
                        Spacer()
                        Keycap(key: "⇧↩")
                    }
                    .foregroundStyle(K.accent).padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 8).fill(sel == matches.count ? K.fillStrong : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    func commit(create: Bool) {
        if !create, sel < matches.count { done(matches[sel].0, nil) }
        else if canCreate { stage = .color(text.trimmingCharacters(in: .whitespaces)) }
        else if !text.trimmingCharacters(in: .whitespaces).isEmpty, !existing.contains(text) { done(text.trimmingCharacters(in: .whitespaces), nil) }
    }

    func color(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { stage = .search } label: {
                HStack(spacing: 6) { Image(systemName: "chevron.left").font(.system(size: TS.small, weight: .semibold)); Text("Color for “\(name)”").font(.system(size: TS.body, weight: .semibold)) }
                    .foregroundStyle(K.text).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back to tag name")
            HStack(spacing: 10) {
                ForEach(FinderColor.all, id: \.idx) { c in
                    Button { colorIndex = c.idx } label: {
                        Circle().fill(c.color).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(K.card, lineWidth: colorIndex == c.idx ? 2 : 0).padding(1))
                            .overlay(Circle().strokeBorder(c.color, lineWidth: colorIndex == c.idx ? 2 : 0).padding(-3))
                            .frame(width: 24, height: 24).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(c.name).accessibilityAddTraits(colorIndex == c.idx ? .isSelected : [])
                }
            }
            Hairline()
            HStack {
                Text("← → choose").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Spacer()
                Button { done(name, colorIndex) } label: { HStack(spacing: 6) { Text("Done"); Keycap(key: "↩") }.font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text2) }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
        .padding(4)
        .focusable().focused($focus).onAppear { focus = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
    }

    func step(_ d: Int) {
        let n = FinderColor.all.count
        let i = FinderColor.all.firstIndex { $0.idx == colorIndex } ?? 0
        colorIndex = FinderColor.all[(i + d + n) % n].idx
    }
}

/// "Rename…" and "Edit name…": a name field in a small popover.
struct NamePopover: View {
    var title: String
    var initial: String
    var commit: (String) -> Bool
    var close: () -> Void
    @State private var text = ""
    @State private var refused = false
    @FocusState private var focus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text2)
            TextField("File name", text: $text).textFieldStyle(.roundedBorder).frame(width: 260).focused($focus)
                .onSubmit(go)
            if refused { Text("That name can't be used here.").font(.system(size: TS.meta)).foregroundStyle(Tint.duplicate.fg) }
            HStack {
                Spacer()
                Button("Cancel", action: close).buttonStyle(SecondaryStyle(small: true)).keyboardShortcut(.cancelAction)
                Button { go() } label: { HStack { Text("Rename"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle(tint: .accent, small: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .onAppear { text = initial; focus = true }
    }
    func go() { if commit(text) { close() } else { refused = true } }
}
