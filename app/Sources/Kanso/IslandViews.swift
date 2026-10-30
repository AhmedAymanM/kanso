import AppKit
import KansoCore
import SwiftUI

// The island's views (design handoff 2026-09-30). The black island fades into a clear Liquid Glass lip at the bottom;
// text stays on the black part, and only glass controls sit in the lip. Fixed palette, not themed.

enum IslandInk {
    static let text = Color(nsColor: NSColor(hex: 0xF5F5F7))
    static let text2 = Color.white.opacity(0.7)
    static let text3 = Color.white.opacity(0.62)   // floor: 7.8:1 on black
    static let control = Color.white.opacity(0.14)
    static let rim = Color.white.opacity(0.18)
}

/// The whole panel is transparent; only the island shape draws (and takes clicks), anchored at the top center.
struct IslandRoot: View {
    @EnvironmentObject var island: Island
    @ObservedObject private var a11y = AccessibilityOptions.shared   // re-render when Reduce Transparency etc. change
    var body: some View {
        VStack(spacing: 0) {
            if island.visible {
                // From the notch, the island grows out from under the hardware notch and shrinks back into it;
                // the capsule fades and scales in place.
                IslandBody().transition(island.skin == .notch && !Motion.reduced
                    ? .modifier(active: NotchReveal(progress: 0, notch: island.notch), identity: NotchReveal(progress: 1, notch: island.notch))
                    : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
            Spacer(minLength: 0)
        }
        .frame(width: Island.size.width, height: Island.size.height, alignment: .top)
    }
}

/// Notch skin: concave "ears" join the screen's top edge, like the hardware notch growing down.
struct IslandShape: Shape {
    var ears: Bool
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in r: CGRect) -> Path {
        guard ears else { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r) }
        let e: CGFloat = 10
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + e + radius, y: r.maxY), control: CGPoint(x: r.minX + e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - radius), control: CGPoint(x: r.maxX - e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandBody: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel
    @ObservedObject private var a11y = AccessibilityOptions.shared

    var notchSkin: Bool { island.skin == .notch }
    var width: CGFloat { island.expanded ? 480 : (notchSkin ? max(290, island.notch.width + 140) : 320) }
    var radius: CGFloat { island.expanded ? 30 : (notchSkin ? 20 : 22) }
    /// Text never enters the clear lip: expanded 64 pt, compact 30 pt (capsule compact 14).
    var lip: CGFloat { island.expanded ? 92 : (notchSkin ? 34 : 14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if island.expanded { IslandExpanded() } else { compact }
            Color.clear.frame(height: lip)
        }
        .overlay(alignment: .bottom) { if island.expanded { IslandLip().padding(.bottom, 16).stagger(5) } }
        .padding(.horizontal, notchSkin ? 10 : 0)   // room for the ears
        .frame(width: width)
        .background { IslandFill(shape: IslandShape(ears: notchSkin, radius: radius), expanded: island.expanded) }
        .overlay { if case .reading? = island.current, !Motion.reduced, !Motion.snapshot, !island.expanded { IslandBeam(shape: IslandShape(ears: notchSkin, radius: radius), top: notchSkin ? island.notch.height : 0).allowsHitTesting(false) } }
        .clipShape(IslandShape(ears: notchSkin, radius: radius))
        .environment(\.colorScheme, .dark)
        .contentShape(IslandShape(ears: notchSkin, radius: radius))
        .onHover { island.hover($0) }
        .onTapGesture { if !island.expanded { island.expand() } }
        .padding(.top, notchSkin ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kanso")
    }

    // MARK: Compact: icon beside the notch, key on the other side, one line below

    @ViewBuilder var compact: some View {
        if let n = island.current {
            if notchSkin {
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        icon(n).padding(.leading, 14)
                        Spacer(minLength: island.notch.width)
                        Group {
                            if hint { IslandKey(text: m.settings.islandShortcut.display, dark: true) }
                            else if island.notices.count > 1 { countBadge(n) }
                        }.padding(.trailing, 14)
                    }
                    .frame(height: island.notch.height)
                    line(n).lineLimit(1).truncationMode(.middle).help(n.line).padding(.horizontal, 14).frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 10) {
                    icon(n)
                    line(n).lineLimit(1).truncationMode(.middle).help(n.line)
                    Spacer(minLength: 4)
                    if island.notices.count > 1 { countBadge(n) }
                    if hint { IslandKey(text: m.settings.islandShortcut.display, dark: true) }
                }
                .padding(.horizontal, 12).frame(height: 38)
            }
        } else if notchSkin {
            Color.clear.frame(height: island.notch.height)
        }
    }

    @ViewBuilder func icon(_ n: Notice) -> some View {
        if case .reading = n { ThinkingOrb() } else { MorphIcon(notice: n) }
    }

    var hint: Bool { m.settings.showShortcutHint && m.settings.shortcutHintUntil > Date() }

    func countBadge(_ n: Notice) -> some View {
        Text("\(island.notices.count)").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(n.tint.islandGlyph)
            .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(n.tint.islandFill)).contentTransition(.numericText())
            .accessibilityLabel("\(island.notices.count) notices")
    }

    @ViewBuilder func line(_ n: Notice) -> some View {
        if case .renamed(let a) = n, let old = a.oldName {
            SweepText(from: old, to: a.name, glyphColor: Color(nsColor: NSColor(hex: 0x8FC9A8)), final: "Renamed \(a.name)").font(.system(size: TS.small, weight: .medium)).foregroundStyle(IslandInk.text)
        } else if island.notices.count > 1, Set(island.notices.map(\.kindKey)).count == 1, let k = island.notices.first?.kindKey {
            Text("\(island.notices.count) \(k == "renamed" ? "renamed" : k == "duplicate" ? "copies held" : "notices")")
                .font(.system(size: TS.small, weight: .medium)).foregroundStyle(IslandInk.text).contentTransition(.numericText())
        } else {
            Text(n.line).font(.system(size: TS.small, weight: .medium)).foregroundStyle(IslandInk.text)
        }
    }
}

/// Opaque black at the notch, fading to fully clear at the bottom, with a glass rim (the Siri pattern). No frosted blur.
struct IslandFill: View {
    var shape: IslandShape
    var expanded: Bool
    @ObservedObject private var a11y = AccessibilityOptions.shared
    var body: some View {
        if Motion.solid || Motion.contrast {   // Increase Contrast: opaque, with a 1 pt edge so the shape reads on any wallpaper
            shape.fill(Color.black)
                .overlay { if Motion.contrast { shape.stroke(K.text.opacity(0.6), lineWidth: 1) } }
        } else {
            // The melt into glass is confined to the last 12 pt; everything above, including the esc row, is solid black.
            GeometryReader { g in
                let h = max(g.size.height, 1), m0 = max(0, 1 - 12 / h)
                let stops: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: m0), .init(color: .black.opacity(0.55), location: m0 + (1 - m0) * 0.5), .init(color: .clear, location: 1)]
                fill(stops)
            }
        }
    }

    @ViewBuilder private func fill(_ stops: [Gradient.Stop]) -> some View {
        ZStack {
            if #available(macOS 26, *) { Color.clear.glassEffect(.regular, in: shape) }   // the lip shows real frosted Liquid Glass
            shape.fill(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
            shape.stroke(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.25), location: 0.85), .init(color: .white.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            shape.stroke(Color.white.opacity(0.18), lineWidth: 6).blur(radius: 7).mask(LinearGradient(colors: [.clear, .white], startPoint: .init(x: 0.5, y: 0.8), endPoint: .bottom))
        }
    }
}

// MARK: Lip: key hints on the left, glass buttons on the right

struct IslandLip: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(hints).font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3).lineLimit(1)
            Spacer()
            LipButtons {
                IslandGlassButton(symbol: "keyboard", label: "Keyboard shortcuts") { withAnimation(Motion.spring()) { island.shortcuts.toggle() } }.keyboardShortcut("/")
                IslandGlassButton(symbol: "gearshape", label: "Settings") { island.hide(); Windows.shared.showSettings() }.keyboardShortcut(",")
            }
        }
        .padding(.horizontal, 20)
    }

    /// Only esc to close, plus the arrows when they do something in this state. Actions show their own keys.
    var hints: String {
        if island.shortcuts { return "esc back" }
        var parts: [String] = []
        let rows = island.overview ? min(m.needs.count, 3) + min(m.done.count, 3) : (island.fanned || island.stacked ? 0 : island.notices.count)
        if island.overview && m.needs.count > 1 { parts.append("← → cycle cards") }
        if rows > 1 { parts.append("↑ ↓ select") }
        if island.stacked || (island.fanned && island.notices.count > 1) { parts.append("← → other files") }
        parts.append("esc to close")
        return parts.joined(separator: " · ")
    }
}

/// The lip's buttons sit in one clear glass capsule (macOS 26); two separate circles before, or with Reduce Transparency.
struct LipButtons<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *), !Motion.solid {
            HStack(spacing: 2) { content }.environment(\.inLipCapsule, true).padding(2)
                .background { Color.clear.glassEffect(.clear, in: Capsule()) }
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        } else {
            HStack(spacing: 8) { content }
        }
    }
}

private struct InLipCapsuleKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inLipCapsule: Bool {
        get { self[InLipCapsuleKey.self] }
        set { self[InLipCapsuleKey.self] = newValue }
    }
}

/// 32 pt clear glass circle.
struct IslandGlassButton: View {
    var symbol: String, label: String
    var action: () -> Void
    @Environment(\.inLipCapsule) private var inCapsule
    @ObservedObject private var a11y = AccessibilityOptions.shared
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: TS.emphasis)).foregroundStyle(Color.white.opacity(0.9)).frame(width: 32, height: 32)
                .background {
                    if inCapsule { Color.clear }   // the capsule behind both buttons is the glass
                    else if #available(macOS 26, *), !Motion.solid { Color.clear.glassEffect(.clear, in: Circle()) }
                    else { Circle().fill(IslandInk.control) }
                }
                .overlay { if !inCapsule { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75) } }
                .overlay(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(PlainRowStyle()).onHover { hover = $0 }
        .focusRing(16).help(label).accessibilityLabel(label)
    }
}

// MARK: Expanded body

struct IslandExpanded: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The body sits below the notch.
            if island.skin == .notch { Color.clear.frame(height: island.notch.height) }
            Group {
                if island.shortcuts { ShortcutsList() }
                else if island.askState.isProposal { AskProposal().stagger(0) }
                else if island.overview { OverviewBody() }
                else if let n = island.current { notice(n).id(n.id) }
            }
            .padding(.horizontal, 20).padding(.top, 2)   // the black island starts right under the notch: no extra space
            .transition(.opacity)
            if island.askAvailable && !island.shortcuts && !island.overview {
                AskField().padding(.horizontal, 20).padding(.top, 10).stagger(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder func notice(_ n: Notice) -> some View {
        let renames = island.notices.filter { if case .renamed = $0 { return true } else { return false } }
        if island.notices.count > 1 {
            if renames.count == island.notices.count { FanBody() } else { CountedList() }
        } else {
            switch n {
            case .renamed(let a): RenameBody(a: a)
            case .duplicate(let a) where a.pending: DuplicateBody(a: a)
            default: SimpleBody(n: n)
            }
        }
    }
}

// MARK: Pieces

/// Finder tag dots: 9 pt overlapping dots with an island-coloured ring, then the names.
struct TagDots: View {
    var tags: [String]
    static func color(_ t: String) -> Color {
        switch t.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray", "grey": return .gray
        default: return [Color.orange, .blue, .green, .purple, .pink, .teal][abs(t.hashValue) % 6]
        }
    }
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: -3) {
                    ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { _, t in
                        Circle().fill(Self.color(t)).frame(width: 9, height: 9).overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5).padding(-1.5))
                    }
                }
                Text(tags.joined(separator: ", ")).font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
            .accessibilityLabel("Tags: " + tags.joined(separator: ", "))
        }
    }
}

struct NoticeHead: View {
    var icon: String, tint: Tint
    var title: String, time: String
    var tags: [String] = []
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: TS.meta, weight: .bold)).foregroundStyle(tint.islandGlyph).frame(width: 20, height: 20).background(Circle().fill(tint.islandFill))
            Text(title + " ·").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text).lineLimit(1)
            Text(time).font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3)
            Spacer(minLength: 8)
            TagDots(tags: tags)
        }
    }
}

/// Quick Look thumbnail; the eye shows on hover only.
struct PreviewTile: View {
    var path: String
    var size: CGSize = CGSize(width: 86, height: 112)
    var eye = true
    @EnvironmentObject var island: Island
    @State private var hover = false
    var body: some View {
        Thumb(path: path).frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) {
                if eye && hover {
                    Button { island.quickLook() } label: {
                        Image(systemName: "eye").font(.system(size: TS.meta)).foregroundStyle(.white).frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain).padding(4).help("Quick Look").accessibilityLabel("Quick Look").transition(.opacity)
                }
            }
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// Old name struck through (mono), new name, and a hover-only reveal glyph. Clicking the name opens the file.
struct NameUnit: View {
    var old: String?
    var name: String
    var path: String
    var size: CGFloat = 17
    @State private var hover = false
    var body: some View {
        VStack(spacing: 2) {
            if let old { Text(old).font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(Color.white.opacity(0.6)).strikethrough().lineLimit(1).truncationMode(.middle) }
            HStack(spacing: 6) {
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                    Text(name).font(.system(size: size, weight: .bold)).foregroundStyle(IslandInk.text).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center).help(name)
                }
                .buttonStyle(.plain).help("Open")
                Button { AppModel.shared.reveal(path) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.body)).foregroundStyle(Color.white.opacity(0.45)) }
                    .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Show in Finder (⌘R)").accessibilityLabel("Show in Finder")
            }
        }
        .onHover { hover = $0 }
    }
}

/// Ancestors in full (11 pt); the current folder with its emoji is full width. Ancestors fold first when space runs out.
struct Breadcrumb: View {
    var ancestors: [String]
    var current: String
    var emoji: String
    var leading = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(ancestors.enumerated()), id: \.offset) { _, a in
                Text(a).font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.white.opacity(0.3))
            }
            Text("\(emoji) \(current)").font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

/// 26 pt capsule, 8% white, no stroke; the default action is a little brighter.
struct SubtleAction: View {
    var action: IslandAction
    var selected: Bool
    var label: String? = nil
    var body: some View {
        Button(action: action.run) {
            HStack(spacing: 6) {
                Image(systemName: action.icon).font(.system(size: TS.small)).foregroundStyle(Color.white.opacity(0.7))
                Text(label ?? action.label).font(.system(size: TS.small, weight: .medium)).foregroundStyle(Color.white.opacity(0.85))
                if !action.key.isEmpty { Text(action.key).font(.system(size: TS.meta, weight: .medium)).foregroundStyle(Color.white.opacity(0.6)) }
            }
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.15 : 0.08)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(action.label)
    }
}

struct ActionRow: View {
    @EnvironmentObject var island: Island
    var labelOverride: String? = nil
    var body: some View {
        let acts = island.actions().filter(\.shown)
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(Array(acts.enumerated()), id: \.element.id) { i, a in SubtleAction(action: a, selected: i == island.selection, label: i == 0 ? labelOverride : nil) }
            Spacer(minLength: 0)
        }
    }
}

@MainActor func crumb(_ a: Action, _ m: AppModel) -> some View {
    Breadcrumb(ancestors: [((a.root as NSString).lastPathComponent), "My Shelves"], current: a.shelf, emoji: m.settings.emoji(for: a.shelf))
}

// MARK: Bodies

struct RenameBody: View {
    @EnvironmentObject var m: AppModel
    var a: Action
    var body: some View {
        VStack(spacing: 10) {
            NoticeHead(icon: "checkmark", tint: .rename, title: "Renamed", time: a.ts.relative, tags: a.tags).stagger(0)
            PreviewTile(path: a.dst).stagger(1)
            VStack(spacing: 4) {
                NameUnit(old: a.oldName, name: a.name, path: a.dst)
                crumb(a, m)
            }
            .stagger(2)
            ActionRow().stagger(3)
        }
    }
}

struct DuplicateBody: View {
    @EnvironmentObject var m: AppModel
    var a: Action
    var body: some View {
        let keptPath = a.details["kept"] ?? a.dst
        let keptName = (keptPath as NSString).lastPathComponent
        let size = (Int64(a.details["size"] ?? "") ?? 0).bytes
        VStack(spacing: 12) {
            NoticeHead(icon: "doc.on.doc", tint: .duplicate, title: "Copy of \(keptName) held", time: a.ts.relative).stagger(0)
            HStack(alignment: .top, spacing: 16) {
                column(label: "Kept", path: keptPath, name: keptName, folder: shelfName(keptPath))
                column(label: "Extra copy · \(size) · identical", path: a.dst, name: a.name, folder: a.shelf)
            }
            .stagger(1)
            ActionRow().stagger(2)
        }
    }

    func shelfName(_ p: String) -> String { ((p as NSString).deletingLastPathComponent as NSString).lastPathComponent }

    func column(label: String, path: String, name: String, folder: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PreviewTile(path: path, size: CGSize(width: 44, height: 58), eye: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3).lineLimit(1)
                HStack(spacing: 4) {
                    Text(name).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text).lineLimit(1).truncationMode(.middle).help(name)
                    Button { m.reveal(path) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.45)) }.buttonStyle(.plain).accessibilityLabel("Show in Finder")
                }
                Text("\(m.settings.emoji(for: folder)) \(folder)").font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SimpleBody: View {
    @EnvironmentObject var m: AppModel
    var n: Notice
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MorphIcon(notice: n, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text).lineLimit(2)
                    if let sub { Text(sub).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2) }
                }
                Spacer(minLength: 0)
            }
            ActionRow()
        }
    }
    var title: String {
        if case .installer(let a) = n { return "Installed \(a.details["installer"] ?? "the app")" }
        if case .duplicate(let a) = n { return a.shelf == "Trash" ? n.line : "Copy of \(((a.details["kept"] ?? a.name) as NSString).lastPathComponent) held" }
        return n.line
    }
    var sub: String? {
        switch n {
        case .installer(let a): return "\(a.srcName) (\((Int64(a.details["size"] ?? "") ?? 0).bytes)) moved to Trash. Put Back any time."
        case .duplicate: return "Identical by size + hash."
        case .renameReview: return "Nothing changes until you review."
        case .sortingOff: return "Turn it on, or leave it off."
        case .batch: return "Undo puts every file from this run back."
        default: return nil
        }
    }
}

/// Mixed notices: one row per notice, old name struck above the new, destination on the right.
struct CountedList: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(island.notices.count)").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(Tint.rename.islandGlyph).frame(width: 20, height: 20).background(Circle().fill(Tint.rename.islandFill))
                Text("\(island.notices.count) notices ·").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text)
                Text("last \(island.notices.last.map(time) ?? "")").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3)
            }
            .padding(.bottom, 4)
            ForEach(Array(island.notices.enumerated()), id: \.element.id) { i, n in
                let sel = island.selection == i
                HStack(spacing: 10) {
                    MorphIcon(notice: n, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        if case .renamed(let a) = n, let o = a.oldName { Text(o).font(.system(size: TS.meta, design: .monospaced)).foregroundStyle(IslandInk.text3).strikethrough().lineLimit(1) }
                        Text(title(n)).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text).lineLimit(1).truncationMode(.middle).help(title(n))
                    }
                    Spacer(minLength: 8)
                    if case .renamed(let a) = n { Text("\(m.settings.emoji(for: a.shelf)) \(a.shelf)").font(.system(size: TS.meta)).foregroundStyle(Color.white.opacity(0.7)) }
                    if sel { Text("⌘Z").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(sel ? 0.10 : 0)))
                .contentShape(Rectangle()).onTapGesture { island.index = i; island.selection = i }
                // VoiceOver: one button per row (the keyboard uses ↑ ↓ and ⌘Z through the island's key handler).
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                .accessibilityAction { island.index = i; island.selection = i }
                .accessibilityAction(named: "Undo") { island.selection = i; island.actions().first { $0.key == "⌘Z" }?.run() }
            }
        }
    }
    func title(_ n: Notice) -> String { if case .renamed(let a) = n { return a.name }; return n.line }
    func time(_ n: Notice) -> String { if case .renamed(let a) = n { return a.ts.relative }; return "" }
}

/// Several renamed files: a fanned stack with one glass pill; expanded, cards fan out horizontally around the active one.
struct FanBody: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel
    var files: [Action] { island.notices.compactMap { if case .renamed(let a) = $0 { return a } else { return nil } } }

    var body: some View {
        if island.fanned, files.indices.contains(island.index) { fan } else { stack }
    }

    var stack: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(Array(files.suffix(3).enumerated()), id: \.offset) { i, a in
                    let depth = CGFloat(min(files.count, 3) - 1 - i)
                    PreviewTile(path: a.dst, size: CGSize(width: 86, height: 112), eye: false)
                        .rotationEffect(.degrees(Double(i - min(files.count, 3) + 1) * -6 + 3))
                        .offset(x: -depth * 22, y: depth * 4).opacity(1 - depth * 0.25)
                }
            }
            .frame(height: 124)
            Button { withAnimation(Motion.spring()) { island.fanned = true } } label: {
                HStack(spacing: 4) { Text("\(files.count) files renamed"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
                    .font(.system(size: TS.small, weight: .medium)).foregroundStyle(IslandInk.text).padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule().fill(IslandInk.control)).overlay(Capsule().strokeBorder(IslandInk.rim, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    var fan: some View {
        let a = files[island.index]
        return VStack(spacing: 10) {
            HStack {
                Text("\(island.index + 1) of \(files.count)").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(IslandInk.text)
                Spacer()
                TagDots(tags: a.tags)
            }
            HStack(alignment: .center, spacing: 14) {
                ForEach(Array(files.enumerated()), id: \.offset) { i, f in
                    let active = i == island.index
                    if abs(i - island.index) <= 1 {
                        PreviewTile(path: f.dst, size: active ? CGSize(width: 100, height: 132) : CGSize(width: 70, height: 92), eye: active)
                            .opacity(active ? 1 : 0.45)
                            .onTapGesture { island.index = i }
                    }
                }
            }
            .frame(height: 136)
            VStack(spacing: 4) {
                NameUnit(old: a.oldName, name: a.name, path: a.dst)
                crumb(a, m)
            }
            .id(a.id).transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(y: 8)))
            ActionRow(labelOverride: "Undo this file")
        }
        .animation(Motion.spring(), value: island.index)
    }
}

struct ShortcutsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard").foregroundStyle(IslandInk.text2)
                Text("Keyboard shortcuts").font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text)
                Spacer()
                IslandKey(text: "esc", dark: true)
            }
            HStack(alignment: .top, spacing: 10) {
                group("This notice", [("Run selected action", "↩"), ("Undo", "⌘Z"), ("Previous / next file", "← →"), ("Move to Trash", "⌘⌫")])
                group("This file", [("Quick Look", "Space"), ("Reveal in Finder", "⌘R"), ("Open", "⌘O"), ("Copy new name", "⌘C")])
                group("The island", [("Open / close", "⌥⌘K"), ("Collapse", "esc"), ("Settings", "⌘,"), ("This list", "⌘/")])
            }
        }
    }
    func group(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: TS.meta, weight: .semibold)).kerning(0.5).foregroundStyle(IslandInk.text3)
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 6) {
                    Text(r.0).font(.system(size: TS.small)).foregroundStyle(IslandInk.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 2)
                    IslandKey(text: r.1, dark: true)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Overview: NEEDS YOU (opaque cards), RECENTLY (faint glass pills). No tab bar, no Sort Now.
struct OverviewBody: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel

    var body: some View {
        let recent = Array(m.done.prefix(3))
        let cardActs = max(0, island.actions().count - recent.count)   // the overview stays on screen while it closes, when actions() is already empty
        VStack(alignment: .leading, spacing: 8) {
            if m.needs.isEmpty && recent.isEmpty {
                VStack(spacing: 4) {
                    if let art = AllQuietArt.image { Image(nsImage: art).resizable().aspectRatio(contentMode: .fit).frame(width: 240, height: 130).accessibilityHidden(true) }
                    Text("All quiet").font(.system(size: TS.heading, weight: .semibold)).foregroundStyle(IslandInk.text)
                    Text("\(Stats.month(m.actions).sorted) files kept in order this month").font(.system(size: TS.body)).foregroundStyle(IslandInk.text3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .stagger(0)
            }
            if let c = island.confirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.accent.islandFill)
                    Text(c.text).font(.system(size: TS.body)).foregroundStyle(IslandInk.text).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let id = c.undo { Button { m.undo([id]); withAnimation(Motion.spring()) { island.confirmation = nil } } label: { Text("⌘Z undo").font(.system(size: TS.small)).foregroundStyle(IslandInk.text3) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 4).transition(.opacity).accessibilityElement(children: .combine)
            }
            if m.needs.isEmpty && island.handled > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(Tint.accent.islandGlyph).frame(width: 24, height: 24).background(Circle().fill(Tint.accent.islandFill))
                    Text("Nothing else needs you").font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text)
                    Text("\(island.handled) handled").font(.system(size: TS.small)).foregroundStyle(IslandInk.text3)
                }
                .padding(.horizontal, 4).stagger(0)
            }
            if !m.needs.isEmpty {
                let i = min(island.card, m.needs.count - 1)
                HStack(spacing: 8) {
                    Text("Needs you").font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text)
                    Text("\(i + 1) of \(m.needs.count)").font(.system(size: TS.small)).foregroundStyle(IslandInk.text3).contentTransition(.numericText())
                    Spacer()
                    if m.needs.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<min(m.needs.count, 6), id: \.self) { d in
                                Capsule().fill(Color.white.opacity(d == i ? 0.9 : 0.3)).frame(width: d == i ? 18 : 6, height: 6)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 4).stagger(0)
                NeedCard(need: m.needs[i], actions: Array(island.actions().prefix(cardActs)))
                    .id(m.needs[i].id).transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(x: 24)))
                    .background(alignment: .bottom) {   // the next card peeks out underneath
                        if m.needs.count > 1 { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: NSColor(hex: 0x161618))).padding(.horizontal, 14).offset(y: 6) }
                    }
                    .padding(.bottom, m.needs.count > 1 ? 6 : 0)
                    .stagger(1)
            }
            if !recent.isEmpty {
                HStack {
                    eyebrow("Recently")
                    Spacer()
                    Button { island.hide(); Windows.shared.showMain(.activity) } label: { Text("All activity ›").font(.system(size: TS.small)).foregroundStyle(IslandInk.text2) }.buttonStyle(.plain)
                }
                .padding(.top, 4).stagger(2)
                ForEach(Array(recent.enumerated()), id: \.element.id) { i, a in recentRow(a, cardActs + i).stagger(3 + i) }
            }
        }
        .animation(Motion.spring(), value: island.card)
    }

    func eyebrow(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: TS.meta, weight: .semibold)).kerning(0.5).foregroundStyle(IslandInk.text3).padding(.horizontal, 4) }

    func recentRow(_ a: Action, _ row: Int) -> some View {
        let sel = island.selection == row
        return HStack(spacing: 10) {
            Image(systemName: a.kind == .renamed ? "checkmark" : a.kind == .duplicate ? "doc.on.doc" : a.kind == .trashed ? "shippingbox" : "square.3.layers.3d").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text2).frame(width: 18)
            Text(a.kind == .renamed ? "Renamed \(a.oldName.map { ($0 as NSString).deletingPathExtension } ?? "") → \((a.name as NSString).deletingPathExtension)" : summary(a) + " · " + a.name)
                .font(.system(size: TS.small)).foregroundStyle(IslandInk.text).lineLimit(1).truncationMode(.middle).help(a.name)
            Spacer(minLength: 8)
            Text(sel ? "⌘Z" : a.ts.shortAgo).font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(sel ? 0.14 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
        .contentShape(Rectangle()).onTapGesture { island.selection = row }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .accessibilityAction { island.selection = row }
        .accessibilityAction(named: "Undo") { m.undo([a.id]) }
    }
}

/// One needs-you item: preview with a hover eye, kind, name, why, where, and its own actions.
struct NeedCard: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel
    var need: Need
    var actions: [IslandAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 16) {
            preview.frame(width: 90, height: 112)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: need.icon).font(.system(size: TS.small)).foregroundStyle(need.tint.islandGlyph).frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(need.tint.islandFill))
                    Text(kind).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2)
                }
                if let path { NameUnitLeading(name: title, path: path) } else { Text(title).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(IslandInk.text) }
                Text(why).font(.system(size: TS.small)).foregroundStyle(IslandInk.text3).lineLimit(2)
                if let a = action { Breadcrumb(ancestors: [(a.root as NSString).lastPathComponent], current: a.shelf, emoji: m.settings.emoji(for: a.shelf), leading: true) }
            }
        }
        HStack(spacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in SubtleAction(action: a, selected: i == island.selection).fixedSize() }
        }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: NSColor(hex: 0x1C1C1E))))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind): \(title)")
    }

    var action: Action? { if case .duplicate(let a) = need { return a }; return nil }
    var path: String? {
        switch need {
        case .duplicate(let a): return a.dst
        case .renames(let p, _): return p.first?.path
        case .rule, .shelf: return nil
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
        case .duplicate(let a): return "Same bytes as \(((a.details["kept"] ?? a.name) as NSString).lastPathComponent)"
        case .renames: return "Names from contents, page 1. You review every name first."
        case .rule: return "Make it automatic from now on?"
        case .shelf(let s): return "\(s.emoji) \(s.name). Nothing moves until you accept."
        }
    }

    @ViewBuilder var preview: some View {
        switch need {
        case .duplicate(let a): PreviewTile(path: a.dst, size: CGSize(width: 86, height: 112))
        case .renames(let p, _): PreviewTile(path: p.first?.path ?? "", size: CGSize(width: 86, height: 112), eye: false)
        case .rule, .shelf: Image(systemName: need.icon).font(.system(size: TS.title)).foregroundStyle(need.tint.islandGlyph).frame(width: 86, height: 86).background(Circle().fill(need.tint.islandFill))
        }
    }
}

/// Left-aligned name with a hover-only reveal glyph (the card's version of `NameUnit`).
struct NameUnitLeading: View {
    var name: String, path: String
    @State private var hover = false
    var body: some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: TS.heading, weight: .bold)).foregroundStyle(IslandInk.text).lineLimit(1).truncationMode(.middle).help(name)
            Button { AppModel.shared.reveal(path) } label: { Image(systemName: "arrow.up.right").font(.system(size: TS.small)).foregroundStyle(Color.white.opacity(0.45)) }
                .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Show in Finder (⌘R)").accessibilityLabel("Show in Finder")
        }
        .onHover { hover = $0 }
    }
}

extension Date {
    var shortAgo: String {
        let s = -timeIntervalSinceNow
        if s < 3600 { return "\(max(1, Int(s / 60))) min" }
        if s < 86400 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86400)) d"
    }
}

struct IslandKey: View {
    var text: String
    var dark: Bool
    var body: some View {
        Text(text).font(.system(size: TS.meta, weight: .medium)).fixedSize().foregroundStyle(dark ? .white.opacity(0.7) : K.text2)
            .padding(.horizontal, 6).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(dark ? .white.opacity(0.14) : K.fill))
    }
}

/// Opening: the island starts as the notch itself and grows down and out from under it, so its curved corners look
/// as if they were always there. Closing runs the same path back into the notch.
struct NotchReveal: ViewModifier, Animatable {
    var progress: CGFloat
    var notch: CGSize
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content
            .mask(alignment: .top) {
                GeometryReader { g in
                    let p = max(0, min(1, progress))
                    let w = notch.width + (g.size.width - notch.width) * p
                    let h = notch.height + (g.size.height - notch.height) * p
                    UnevenRoundedRectangle(bottomLeadingRadius: 8 + 22 * p, bottomTrailingRadius: 8 + 22 * p, style: .continuous)
                        .frame(width: w, height: h)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .opacity(progress <= 0.01 ? 0 : 1)
    }
}

/// Work in progress: a sage line that fades in at the left, travels along the island's sides and bottom, and fades out
/// at the right, then starts again. It never crosses the top: the screen edge is a physical boundary.
struct IslandBeam: View {
    var shape: IslandShape
    var top: CGFloat
    var period = 1.8
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let fade = sin(Double.pi * t)   // fade in from the left, out to the right
            GeometryReader { g in
                shape.stroke(Color(nsColor: NSColor(hex: 0x8FC9A8)), lineWidth: 1.5)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: max(0, t - 0.18)), .init(color: .white, location: t), .init(color: .clear, location: min(1, t + 0.18))],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask(alignment: .bottom) { Rectangle().frame(height: max(0, g.size.height - top - 2)) }   // nothing at the top edge
                    .opacity(fade)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Content enters after the island has grown: each block fades in from 96% scale, staggered by `order`.
/// Reduce Motion: a plain fade.
struct Stagger: ViewModifier {
    var order: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || Motion.reduced ? 1 : 0.96, anchor: .top)
            .offset(y: shown || Motion.reduced ? 0 : 6)
            .onAppear {
                guard !Motion.snapshot else { shown = true; return }
                withAnimation(Motion.reduced ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86).delay(0.12 + 0.05 * Double(order))) { shown = true }
            }
    }
}

extension View {
    func stagger(_ order: Int) -> some View { modifier(Stagger(order: order)) }
}
