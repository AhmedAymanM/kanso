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
        Text(title).font(.system(size: TS.emphasis, weight: .bold)).foregroundStyle(K.text)
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
                        Label { Text(p.title).font(.system(size: TS.body)) } icon: { Image(systemName: p.icon).font(.system(size: TS.small)).foregroundStyle(m.page == p ? K.text : K.text2) }
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
                Text("Your files never leave your Mac.").font(.system(size: TS.meta)).foregroundStyle(K.sidebarText2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 12)
        }
    }
}

extension Bundle {
    var version: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var build: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
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
                Image(systemName: "cup.and.saucer").font(.system(size: TS.body))
                Text("Free and open source. If it saves you time, a coffee keeps it going.")
                    .font(.system(size: TS.meta)).lineLimit(3).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("Buy Me a Coffee").font(.system(size: TS.small, weight: .semibold))
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
