import KansoCore
import SwiftUI

/// The one App window (k3/App Window): a native split view, so the sidebar, the toolbar title and the scroll edge
/// effect under it are Liquid Glass on macOS 26. Content stays solid.
struct AppWindow: View {
    @State private var columns = NavigationSplitViewVisibility.all   // always .all: there is no toggle
    static let size = CGSize(width: 900, height: 660)
    @EnvironmentObject var m: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
                .noSidebarToggle()
                .frame(width: 220)   // without the toggle the column otherwise shrinks to its minimum
        } detail: {
            detail
                .navigationTitle(m.page.title)
                .hideToolbarTitle()
                .toolbar { PageTitle(title: m.page.title) }
                .background(K.window)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: AppWindow.size.width, height: AppWindow.size.height)   // one small, fixed size (like System Settings)
    }

    @ViewBuilder var detail: some View {
        if m.page == .activity {
            ActivityPage()
        } else {
            // The scroll view is the detail's root so the toolbar finds it and draws the Liquid Glass edge under the title.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { page }
                    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 28)
                    .frame(maxWidth: 900).frame(maxWidth: .infinity)
                    .id(m.page)
                    .transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
            .animation(Motion.spring(0.3), value: m.page)
            .softTopEdge()
            .defaultScrollAnchor(ProcessInfo.processInfo.environment["KANSO_SCROLL"] == "bottom" ? .bottom : .top)   // screenshots of the scrolled state
        }
    }

    @ViewBuilder var page: some View {
        switch m.page {
        case .overview: OverviewPage()
        case .sorting: SortingPage()
        case .renaming: RenamingPage()
        case .duplicates: DuplicatesPage()
        case .tagging: TaggingPage()
        case .smartEject: SmartEjectPage()
        case .general: GeneralPage()
        case .privacy: PrivacyPage()
        case .activity: EmptyView()
        }
    }
}

/// The page title in the toolbar, 15/700, with no capsule.
struct PageTitle: ToolbarContent {
    var title: String
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { titleText }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { titleText }
        }
    }
    var titleText: some View {
        Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(K.text)
            .contentTransition(.opacity).accessibilityAddTraits(.isHeader).padding(.leading, 6)
    }
}

/// Native source list: grey line icons, a pill for the selected row, a small count badge on Activity.
struct Sidebar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        List(selection: Binding(get: { m.page }, set: { if let p = $0 { m.page = p } })) {
            ForEach(Array(Page.groups.enumerated()), id: \.offset) { _, g in
                Section {
                    ForEach(g) { p in
                        Label { Text(p.title).font(.system(size: 13)) } icon: { Image(systemName: p.icon).font(.system(size: 12)).foregroundStyle(m.page == p ? K.text : K.text2) }
                            .badge(p == .activity ? m.needs.count : 0)
                            .tag(p)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listItemTint(.monochrome)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                CoffeeLink()
                Text("Your files never leave your Mac.").font(.system(size: 11)).foregroundStyle(K.sidebarText2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 12)
        }
    }
}

extension Bundle {
    var version: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var build: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}

// MARK: Overview: statement, Needs you, Since you started, Highlights (one non-scrolling page)

struct OverviewPage: View {
    @EnvironmentObject var m: AppModel
    @State private var sizes: [(shelf: String, bytes: Int64)] = []
    @State private var appeared = Motion.reduced

    /// Counts per day for the last 7 days, oldest first.
    func daily(_ keep: (Action) -> Bool) -> [Int] {
        let cal = Calendar.current
        return (0..<7).reversed().map { d in
            let day = cal.date(byAdding: .day, value: -d, to: Date())!
            return m.actions.filter { !$0.undone && keep($0) && cal.isDate($0.ts, inSameDayAs: day) }.count
        }
    }

    var body: some View {
        let all = Stats.of(m.actions, in: DateInterval(start: .distantPast, end: Date().addingTimeInterval(1)))
        let ins = Insights.compute(m.actions, settings: m.settings)
        let needs = m.needs
        VStack(alignment: .leading, spacing: 22) {
            statement(needs, all)
            if !needs.isEmpty { needsBlock(needs) }
            since(all)
            highlights(ins)
        }
        .task {
            let s = m.settings
            sizes = await Task.detached { shelfSizes(s) }.value
            guard !Motion.reduced else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 1)) { appeared = true }
        }
    }

    func statement(_ needs: [Need], _ all: Stats) -> some View {
        let first = m.actions.map(\.ts).min()
        var t = m.sortingOn ? "\(m.today.sorted) \(m.today.sorted == 1 ? "file" : "files") placed today" : "Sorting is \(m.sortingStatus.lowercased())"
        if let first, all.sorted > 0 { t += " · \(all.sorted.formatted()) since \(first.formatted(.dateTime.month(.wide)))" }
        t += needs.isEmpty ? ". Your Mac is in order." : needs.count == 1 ? ". One thing could use a minute." : ". \(needs.count) things could use a minute."
        return Text(t).font(.system(size: 14)).foregroundStyle(K.text2).padding(.horizontal, 4)
    }

    func needsBlock(_ needs: [Need]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Needs you").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(K.text2)
                Spacer()
                Button("Open Activity") { m.page = .activity }.buttonStyle(LinkStyle())
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(needs.prefix(3).enumerated()), id: \.element.id) { i, n in
                    HStack(spacing: 14) {
                        Image(systemName: n.icon).font(.system(size: 15)).foregroundStyle(K.text2).frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(needTitle(n)).font(.system(size: 13.5, weight: .medium)).foregroundStyle(K.text).lineLimit(1)
                            Text(needSub(n)).font(.system(size: 11.5)).foregroundStyle(K.text2).lineLimit(1)
                        }
                        Spacer()
                        needAction(n)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if i < min(needs.count, 3) - 1 { Rectangle().fill(K.separator).frame(height: 0.75) }
                }
            }
            .card(radius: 14)
            if needs.count > 3 { Button("+ \(needs.count - 3) more · Activity") { m.page = .activity }.buttonStyle(LinkStyle(color: K.text2)).padding(.horizontal, 4) }
        }
    }

    @ViewBuilder func needAction(_ n: Need) -> some View {
        switch n {
        case .duplicate(let a):
            Button { m.trash(a.id) } label: { HStack(spacing: 6) { Text("Move to Trash"); Text("⌘⌫").font(.system(size: 10.5)) } }.buttonStyle(PrimaryStyle(tint: .duplicate, small: true))
        case .renames:
            Button { Windows.shared.showReview(tab: .renames) } label: { HStack(spacing: 6) { Text("Review…"); Image(systemName: "return").font(.system(size: 10)) } }.buttonStyle(PrimaryStyle(tint: .rename, small: true))
        case .rule(let r):
            Button("Create rule") { m.acceptSuggestion(r.id) }.buttonStyle(PrimaryStyle(tint: .rule, small: true))
        }
    }

    func needTitle(_ n: Need) -> String {
        switch n {
        case .duplicate(let a): return "Copy of \(((a.details["kept"] ?? a.name) as NSString).lastPathComponent) held"
        case .renames(let p, _): return "\(p.count) files can be renamed"
        case .rule(let r): return "You moved \(r.files.count) files to \(r.shelf)"
        }
    }

    func needSub(_ n: Need) -> String {
        switch n {
        case .duplicate(let a): return "\(Int64(a.details["size"] ?? "")?.bytes ?? "") · identical to \(((a.details["kept"] ?? a.name) as NSString).lastPathComponent)"
        case .renames: return "Nothing changes until you review"
        case .rule: return "Make it a rule for next time?"
        }
    }

    // Since you started: pinned row of four cards, 112 tall.
    func since(_ all: Stats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Since you started").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(K.text2)
                Spacer()
                Text("counted on this Mac").font(.system(size: 11)).foregroundStyle(K.text2)
            }
            .padding(.horizontal, 4)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {   // 2 × 2 in the fixed-size window
                GridRow {
                    PinnedCard(icon: "square.3.layers.3d", label: "Sorted today", value: Double(m.today.sorted), format: { "\(Int($0))" }, unit: "files", bars: daily { $0.kind == .sorted || $0.kind == .renamed }, tint: .teal, appeared: appeared) { m.page = .activity }
                    PinnedCard(icon: "pencil", label: "Renamed", value: Double(all.renamed), format: { "\(Int($0))" }, unit: "all time", bars: daily { $0.kind == .renamed }, tint: .indigo, appeared: appeared) { m.page = .renaming }
                }
                GridRow {
                    PinnedCard(icon: "doc.on.doc", label: "Duplicates found", value: Double(all.duplicateBytes), format: { Int64($0).bytes }, unit: "all time", bars: daily { $0.kind == .duplicate }, tint: .orange, appeared: appeared) { m.page = .duplicates }
                    PinnedCard(icon: "arrow.uturn.backward", label: "Undo rate", value: all.undoRate * 100, format: { String(format: "%.1f%%", $0) }, unit: all.undoRate < 0.05 ? "rarely wrong" : "Kanso is learning", ring: all.undoRate, tint: Tint.neutral.fg, appeared: appeared) { m.page = .activity }
                }
            }
        }
    }

    func highlights(_ i: Insights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HIGHLIGHTS").font(.system(size: 10.5, weight: .semibold)).kerning(0.6).foregroundStyle(K.text2).padding(.horizontal, 4)
            HStack(alignment: .top, spacing: 12) {
                InsightCard(icon: "square.3.layers.3d", tag: "Sorting", color: Tint.where.fg, sentence: "Kanso sorts about \(monthlyAverage) files a month", sub: busiest) {
                    BarChart(values: monthly.map(\.1), labels: monthly.map(\.0), highlight: monthly.count - 1, color: Tint.accent.fg)
                }
                InsightCard(icon: "folder", tag: "Shelves", color: Tint.rename.fg, sentence: "Most filed: \(sizes.first.map { "\(m.settings.emoji(for: $0.shelf)) \($0.shelf)" } ?? "nothing yet")", sub: "Biggest shelves on this Mac.") {
                    VStack(spacing: 7) {
                        ForEach(Array(sizes.prefix(4).enumerated()), id: \.offset) { idx, s in
                            HStack(spacing: 8) {
                                Text("\(m.settings.emoji(for: s.shelf)) \(s.shelf)").font(.system(size: 11.5)).foregroundStyle(K.text).frame(width: 110, alignment: .leading).lineLimit(1)
                                ProgressBar(value: Double(s.bytes) / Double(max(sizes.first?.bytes ?? 1, 1)), color: idx == 0 ? Tint.accent.fg : K.text3)
                                Text(s.bytes.bytes).font(.system(size: 10.5)).foregroundStyle(K.text2).frame(width: 54, alignment: .trailing)
                            }
                        }
                        if sizes.isEmpty { Text("Shelves appear with the first sorted file.").font(.system(size: 11.5)).foregroundStyle(K.text2) }
                    }
                }
            }
        }
    }

    /// Sorted files per month for the last 7 months, oldest first, labelled with the month's first letters.
    var monthly: [(String, Int)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .month, value: -back, to: Date())!
            let n = m.actions.filter { !$0.undone && $0.kind != .trashed && cal.isDate($0.ts, equalTo: d, toGranularity: .month) }.count
            return (d.formatted(.dateTime.month(.abbreviated)), n)
        }
    }
    var monthlyAverage: Int { let v = monthly.map(\.1).filter { $0 > 0 }; return v.isEmpty ? 0 : v.reduce(0, +) / v.count }
    var busiest: String {
        guard let top = monthly.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return "Nothing sorted yet." }
        return monthly.last?.1 == top.1 ? "This month is your busiest so far." : "\(top.0) was your busiest month."
    }
}

/// A pinned card: top line (icon, label, chevron), bottom line (serif numeral + unit, sparkline or ring).
struct PinnedCard: View {
    var icon: String, label: String
    var value: Double
    var format: (Double) -> String
    var unit: String
    var bars: [Int] = []
    var ring: Double? = nil
    var tint: Color
    var appeared: Bool
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                    Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(K.text2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(K.text3)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        CountingText(value: appeared ? value : 0, format: format).font(.system(size: 30, weight: .regular, design: .serif)).tracking(-0.6).foregroundStyle(K.text).lineLimit(1).fixedSize()
                        Text(unit).font(.system(size: 11)).foregroundStyle(K.text2)
                    }
                    Spacer()
                    if let ring {
                        ZStack {
                            Circle().stroke(K.fillStrong, lineWidth: 4)
                            Circle().trim(from: 0, to: max(0.02, ring)).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        .frame(width: 34, height: 34)
                    } else {
                        MiniBars(values: bars, color: tint)
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
            .card(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainRowStyle()).focusRing(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(format(value)) \(unit)")
    }
}

/// Numbers that roll to their value (Animatable), once.
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)).monospacedDigit() }
}

struct MiniBars: View {
    var values: [Int]
    var color: Color = K.accent
    var body: some View {
        let mx = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2).fill(i == values.count - 1 ? color : color.opacity(0.25))
                    .frame(width: 6, height: max(4, CGFloat(v) / CGFloat(mx) * 34))
            }
        }
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color = K.accent
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(K.fillStrong)
                Capsule().fill(color).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

extension View {
    /// Our own 20/700 title replaces the system's small one; the window title stays for Mission Control and VoiceOver.
    @ViewBuilder func hideToolbarTitle() -> some View {
        if #available(macOS 15, *) { toolbar(removing: .title) } else { self }
    }

    /// A soft Liquid Glass edge under the toolbar title: content scrolling beneath it blurs and fades.
    /// Drawn by us because the system edge effect only appears in some split-view states.
    func softTopEdge() -> some View { modifier(SoftTopEdge()) }
}

/// The Buy Me a Coffee card at the bottom of the sidebar: quiet at rest (no fill, muted text), the light butter card on hover.
struct CoffeeLink: View {
    @State private var hover = false
    var body: some View {
        Button { NSWorkspace.shared.open(Links.coffee) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "cup.and.saucer").font(.system(size: 13))
                Text("Free and open source. If it saves you time, a coffee keeps it going.")
                    .font(.system(size: 11)).lineLimit(3).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("Buy Me a Coffee").font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(hover ? Tint.duplicate.fg : K.sidebarText2)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tint.duplicate.bg).opacity(hover ? 1 : 0))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hover ? Tint.duplicate.stroke : K.separator, lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .accessibilityLabel("Buy Me a Coffee")
    }
}

struct SoftTopEdge: ViewModifier {
    @State private var scrolled = false
    func body(content: Content) -> some View {
        content
            .onScrollOffset { scrolled = $0 > 1 }
            .overlay(alignment: .top) {
                Rectangle().fill(.regularMaterial)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 64)
                    .ignoresSafeArea(edges: .top)
                    .opacity(scrolled ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: scrolled)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Calls back with the vertical scroll offset (macOS 15+; older systems never report a scroll).
    @ViewBuilder func onScrollOffset(_ f: @escaping (CGFloat) -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in f(y) }
        } else { self }
    }

    /// The sidebar is always shown: no toggle button in the toolbar.
    @ViewBuilder func noSidebarToggle() -> some View {
        if #available(macOS 14, *) { toolbar(removing: .sidebarToggle) } else { self }
    }
}
