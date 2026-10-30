import KansoCore
import SwiftUI

/// Overview (v2 redesign 2026-10-01): headline, the Kept-in-order hero beside one Needs-you card at a time,
/// the month chart beside "Where files went", and four tinted counters.
struct OverviewPage: View {
    @EnvironmentObject var m: AppModel
    @State private var card = 0
    @State private var appeared = Motion.reduced || Motion.snapshot

    var body: some View {
        let needs = m.needs
        let all = Stats.of(m.actions, in: DateInterval(start: .distantPast, end: Date().addingTimeInterval(1)))
        VStack(alignment: .leading, spacing: 14) {
            headline(needs)
            if needs.isEmpty {
                // Nothing to do: the card shrinks to one line and the chart rises into the space.
                QuietLine()
                HStack(alignment: .top, spacing: 14) {
                    hero(all).frame(width: 236)
                    MonthCard().frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                ShelvesCard().frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    hero(all).frame(width: 236)
                    NeedsCard(card: $card).frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    MonthCard().frame(maxWidth: .infinity)
                    ShelvesCard().frame(width: 236)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            counters(all)
        }
        .animation(Motion.spring(), value: needs.isEmpty)
        .task {
            guard !Motion.reduced else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 1)) { appeared = true }
        }
    }

    func headline(_ needs: [Need]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.sortingOn ? "Your Mac is in order." : "Sorting is \(m.sortingStatus.lowercased()).")
                .font(.system(size: TS.display, weight: .regular, design: .serif)).tracking(-0.6).foregroundStyle(K.text)
            Text("\(m.today.sorted) \(m.today.sorted == 1 ? "file" : "files") placed today. " + (needs.isEmpty ? "Nothing needs you." : needs.count == 1 ? "One thing could use a minute." : "\(needs.count == 2 ? "Two" : "\(needs.count)") things could use a minute."))
                .font(.system(size: TS.emphasis)).foregroundStyle(K.text2)
        }
        .padding(.horizontal, 4).padding(.top, 6)
    }

    func hero(_ all: Stats) -> some View {
        let since = m.actions.map(\.ts).min().map { " since \($0.formatted(.dateTime.month(.wide)))" } ?? ""
        let stayed = Int(((1 - all.undoRate) * 100).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            Text("KEPT IN ORDER").font(.system(size: TS.meta, weight: .bold)).kerning(1).foregroundStyle(Heroes.ink.opacity(0.85))
                .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Color.white.opacity(0.12)))
            Spacer(minLength: 6)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                CountingText(value: appeared ? Double(all.sorted) : 0, format: { Int($0).formatted() })
                    .font(.system(size: TS.numeral, weight: .regular, design: .serif)).tracking(-1.5).foregroundStyle(Heroes.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text("files").font(.system(size: TS.body)).foregroundStyle(Heroes.ink.opacity(0.85))
            }
            Text(all.sorted == 0 ? "Nothing sorted yet. New files are placed on a shelf as they arrive, and you can undo any of it." : "placed on the right shelf\(since). \(stayed)% stayed where Kanso put them.")
                .font(.system(size: TS.small)).foregroundStyle(Heroes.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Heroes.fill))
        .accessibilityElement(children: .combine)
    }

    /// One quiet line instead of four tinted tiles: pastels mean an action kind and are never counters.
    func counters(_ all: Stats) -> some View {
        let tagged = m.actions.filter { !$0.undone && !$0.tags.isEmpty }.count
        let ejected = m.actions.filter { !$0.undone && $0.kind == .trashed && $0.details["installer"] != nil }.count
        return HStack(alignment: .top, spacing: 12) {
            CountCell(value: all.renamed.formatted(), label: "Renamed") { m.page = .renaming }
            CountCell(value: tagged.formatted(), label: "Tagged") { m.page = .tagging }
            CountCell(value: all.duplicateBytes.bytes, label: "Copies held") { m.page = .duplicates }
            CountCell(value: ejected.formatted(), label: "Installers ejected") { m.page = .smartEject }
        }
        .padding(16).card()
    }
}

enum Heroes {
    static let fill = K.hero
    static let ink = K.heroText
}

/// Thin diagonal hatching, the Kanso paper texture.
struct Stripes: Shape {
    var step: CGFloat = 26
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = -r.height
        while x < r.width {
            p.move(to: CGPoint(x: x, y: r.height)); p.addLine(to: CGPoint(x: x + r.height, y: 0))
            x += step
        }
        return p
    }
}

struct CountCell: View {
    var value: String, label: String
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: TS.title, weight: .regular, design: .serif)).foregroundStyle(K.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainRowStyle()).focusRing(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: Needs you: one card at a time

struct NeedsCard: View {
    @EnvironmentObject var m: AppModel
    @Binding var card: Int

    var body: some View {
        let needs = m.needs
        let i = min(card, max(needs.count - 1, 0))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Needs you").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                if !needs.isEmpty { Text("\(i + 1) of \(needs.count)").font(.system(size: TS.small)).foregroundStyle(K.text2).contentTransition(.numericText()) }
                Spacer()
                if needs.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<min(needs.count, 6), id: \.self) { d in Capsule().fill(d == i ? K.text : K.text3.opacity(0.4)).frame(width: d == i ? 16 : 5, height: 5) }
                    }
                    .padding(.trailing, 4).accessibilityHidden(true)
                    chevron("chevron.left", "Previous") { step(-1, needs.count) }
                    chevron("chevron.right", "Next") { step(1, needs.count) }
                }
            }
            if needs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: TS.emphasis, weight: .bold)).foregroundStyle(Tint.accent.fg).frame(width: 34, height: 34).background(Circle().fill(Tint.accent.bg))
                    Text("Nothing needs you").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    Text("Duplicates and rename suggestions show up here.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NeedBody(need: needs[i], next: { step(1, needs.count) })
                    .id(needs[i].id).transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(x: 20)))
            }
        }
        .padding(16).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
        .background(alignment: .bottom) {   // the next card peeks out underneath
            if needs.count > 1 { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75).padding(.horizontal, 22).offset(y: 6) }
        }
        .animation(Motion.spring(), value: card)
        .accessibilityElement(children: .contain)
    }

    func step(_ d: Int, _ n: Int) { guard n > 1 else { return }; withAnimation(Motion.spring()) { card = (min(card, n - 1) + d + n) % n } }

    func chevron(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text2).frame(width: 26, height: 26).background(Circle().fill(K.fill))
        }
        .buttonStyle(PlainRowStyle()).focusRing(13).help(label).accessibilityLabel(label)
    }
}

struct NeedBody: View {
    @EnvironmentObject var m: AppModel
    var need: Need
    var next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                preview.frame(width: 64, height: 82)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: need.icon).font(.system(size: TS.meta)).foregroundStyle(need.tint.fg).frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(need.tint.bg))
                        Text(kind).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(1)
                    }
                    Text(title).font(.system(size: TS.heading, weight: .semibold)).foregroundStyle(K.text).lineLimit(1).truncationMode(.middle)
                    Text(why).font(.system(size: TS.small)).foregroundStyle(K.text2).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }
        }
    }

    @ViewBuilder var preview: some View {
        switch need {
        case .duplicate(let a): Thumb(path: a.dst)
        case .renames(let p, _): Thumb(path: p.first?.path ?? "")
        case .rule, .shelf: Image(systemName: need.icon).font(.system(size: TS.title)).foregroundStyle(need.tint.fg).frame(width: 56, height: 56).background(Circle().fill(need.tint.bg))
        }
    }
    var kind: String {
        switch need {
        case .duplicate(let a): return "Duplicate held · \((Int64(a.details["size"] ?? "") ?? 0).bytes)"
        case .renames: return "Rename suggestions"
        case .rule: return "Rule suggestion"
        case .shelf: return "Shelf suggestion"
        }
    }
    var title: String {
        switch need {
        case .duplicate(let a): return a.name
        case .renames(let p, _): return "\(p.count) files can be renamed"
        case .rule(let r): return "You moved \(r.files.count) files to \(r.shelf)"
        case .shelf(let s): return "\(s.files.count) files could have their own shelf"
        }
    }
    var why: String {
        switch need {
        case .duplicate(let a): return "Same bytes as \(((a.details["kept"] ?? a.name) as NSString).lastPathComponent) · \(a.shelf)"
        case .renames: return "Names from contents, page 1. You review every name first."
        case .rule: return "Make it a rule for next time?"
        case .shelf(let s): return "\(s.emoji) \(s.name): \(s.description). Nothing moves until you accept."
        }
    }

    @ViewBuilder var actions: some View {
        switch need {
        case .duplicate(let a):
            Button { m.trash(a.id) } label: { HStack(spacing: 5) { Image(systemName: "trash"); Text("Move copy to Trash"); Text("⌘⌫").font(.system(size: TS.meta)) } }.buttonStyle(PrimaryStyle(tint: .duplicate, small: true)).fixedSize().keyboardShortcut(.delete, modifiers: .command)
            Button { m.keepBoth(a.id) } label: { Label("Keep both", systemImage: "doc.on.doc") }.buttonStyle(SecondaryStyle(small: true)).fixedSize()
        case .renames(let p, _):
            Button { Windows.shared.showReview(tab: .renames) } label: { Label("Review names", systemImage: "checklist") }.buttonStyle(PrimaryStyle(tint: .rename, small: true)).fixedSize()
            Button { m.applyRenames(p) } label: { Label("Rename all", systemImage: "wand.and.sparkles") }.buttonStyle(SecondaryStyle(small: true)).fixedSize()
        case .rule(let r):
            Button("Create rule") { m.acceptSuggestion(r.id) }.buttonStyle(PrimaryStyle(tint: .rule, small: true)).fixedSize()
        case .shelf(let s):
            Button("Create \(s.name)") { m.acceptShelf(s.id) }.buttonStyle(PrimaryStyle(tint: .rule, small: true)).fixedSize()
            Button("Dismiss") { m.dismissShelf(s.id) }.buttonStyle(SecondaryStyle(small: true)).fixedSize()
        }
        if m.needs.count > 1 { Button { next() } label: { HStack(spacing: 4) { Text("Later"); Image(systemName: "arrow.right").font(.system(size: TS.meta)) } }.buttonStyle(SecondaryStyle(small: true)).fixedSize() }
    }
}

// MARK: The month, day by day

/// The Needs-you card when it is empty: a 56 pt line.
struct QuietLine: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: TS.body, weight: .bold)).foregroundStyle(Tint.accent.fg).frame(width: 28, height: 28).background(Circle().fill(Tint.accent.bg))
            Text("Nothing needs you").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
            Text("Duplicates and rename suggestions show up here.").font(.system(size: TS.small)).foregroundStyle(K.text2)
            Spacer()
        }
        .padding(.horizontal, 16).frame(height: 56).card()
        .accessibilityElement(children: .combine)
    }
}

struct MonthCard: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        let cal = Calendar.current, now = Date()
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let today = cal.component(.day, from: now)
        let counts: [Int] = (1...days).map { d in
            guard let date = cal.date(byAdding: .day, value: d - 1, to: monthStart) else { return 0 }
            return m.actions.filter { !$0.undone && $0.kind != .trashed && cal.isDate($0.ts, inSameDayAs: date) }.count
        }
        let total = counts.reduce(0, +)
        let lastMonth = Stats.month(m.actions, offset: -1).sorted
        let pct = lastMonth == 0 ? nil : Int((Double(total - lastMonth) / Double(lastMonth) * 100).rounded())
        let best = counts.enumerated().max { $0.element < $1.element }
        let mx = max(counts.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.formatted(.dateTime.month(.wide))).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
                    Text("Files placed each day").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                Spacer()
                Button { m.page = .activity } label: { Image(systemName: "calendar").font(.system(size: TS.body)).foregroundStyle(K.text2).frame(width: 30, height: 30).background(Circle().fill(K.fill)) }
                    .buttonStyle(PlainRowStyle()).focusRing(15).help("Open Activity").accessibilityLabel("Open Activity")
            }
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(total.formatted()).font(.system(size: TS.display, weight: .regular, design: .serif)).tracking(-1).foregroundStyle(K.text)
                    Text("files").font(.system(size: TS.body)).foregroundStyle(K.text2)
                }
                Spacer()
                if let pct {
                    Label("\(abs(pct))% vs \((cal.date(byAdding: .month, value: -1, to: now) ?? now).formatted(.dateTime.month(.wide)))", systemImage: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: TS.small, weight: .medium)).foregroundStyle(Tint.accent.fg).padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(Tint.accent.bg))
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<days, id: \.self) { d in
                    ZStack(alignment: .bottom) {
                        if d + 1 <= today { RoundedRectangle(cornerRadius: 2).fill(K.fill) }   // elapsed days only
                        RoundedRectangle(cornerRadius: 2).fill(d + 1 == today ? Tint.accent.fg : K.text).frame(height: counts[d] == 0 ? 0 : max(5, CGFloat(counts[d]) / CGFloat(mx) * 60))
                    }
                    .help("\(counts[d]) files")
                }
            }
            .frame(height: 60).padding(.top, 4)
            HStack {
                Text("1 \(now.formatted(.dateTime.month(.abbreviated)))")
                Spacer()
                if let best, best.element > 0 { Text("Busiest: \(now.formatted(.dateTime.month(.abbreviated))) \(best.offset + 1) · \(best.element) files") }
                Spacer()
                Text("Today").fontWeight(.semibold).foregroundStyle(Tint.accent.fg)
            }
            .font(.system(size: TS.meta)).foregroundStyle(K.text2)
        }
        .padding(16).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

struct ShelvesCard: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let cal = Calendar.current
        let rows = Dictionary(grouping: m.actions.filter { !$0.undone && $0.kind != .trashed && cal.isDate($0.ts, equalTo: Date(), toGranularity: .month) }, by: \.shelf)
            .map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(4)
        let top = max(rows.first?.1 ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Where files went").font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
                Text("Top shelves this month").font(.system(size: TS.small)).foregroundStyle(K.text2)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                VStack(spacing: 5) {
                    HStack {
                        Text("\(m.settings.emoji(for: r.0)) \(r.0)").font(.system(size: TS.body)).foregroundStyle(K.text).lineLimit(1)
                        Spacer()
                        Text("\(r.1)").font(.system(size: TS.small)).foregroundStyle(K.text2)
                    }
                    ProgressBar(value: Double(r.1) / Double(top), color: i == 0 ? Tint.accent.fg : K.text3)
                }
            }
            if rows.isEmpty { Text("Shelves appear with the first sorted file.").font(.system(size: TS.small)).foregroundStyle(K.text2) }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
    }
}
