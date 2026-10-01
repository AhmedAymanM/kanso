import AppKit
import KansoCore
import SwiftUI

typealias Settings = KansoCore.Settings
typealias Group = SwiftUI.Group

// v2 tokens (PRODUCT.md "Pastel theme", docs/design-validation-2026-09-29.md): every color is a pastel + ink pair.
// Pastel for surfaces, chips and button fills; ink for text, icons, switch on-states, selection, focus and chart marks.
extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark, alpha: da) : NSColor(hex: light, alpha: la)
        })
    }
}

/// A meaning (Kanso, rename, duplicate…) as a pastel surface and a deep ink. `fg` is the ink (text, icons, marks).
struct Tint: Equatable {
    var fg: Color, bg: Color, soft: Color, stroke: Color
    /// Island palette (not themed): the light pastel as an icon fill with its ink as the glyph.
    var islandFill: Color = .clear, islandGlyph: Color = .clear

    /// Light: pastel surface + ink. Dark (spec): the ink becomes the pastel, and the surface is the ink at 30% over #2C2C2E.
    static func pair(_ pastel: UInt32, _ ink: UInt32, _ darkSurface: UInt32) -> Tint {
        Tint(fg: .dyn(ink, pastel), bg: .dyn(pastel, darkSurface), soft: .dyn(pastel, darkSurface, 0.75, 0.8), stroke: .dyn(ink, pastel, 0.25, 0.25),
             islandFill: Color(nsColor: NSColor(hex: pastel)), islandGlyph: Color(nsColor: NSColor(hex: ink)))
    }

    static let accent = pair(0xCFE8D8, 0x2E5A4B, 0x2D3A37)      // mint: Kanso, sorted, brand, Smart Eject
    static let rename = pair(0xD9E0FA, 0x3C509A, 0x31374E)      // periwinkle: rename, reads contents
    static let duplicate = pair(0xF7E4B5, 0x7E531B, 0x453828)   // butter: duplicate
    static let rule = pair(0xE5DCF7, 0x5A4687, 0x3A3449)        // lavender: rules
    static let `where` = pair(0xD0ECEC, 0x1E666B, 0x283D40)     // aqua: where should this go, waiting
    static let neutral = pair(0xECEAE5, 0x48484D, 0x343437)     // stone: neutral, batch, off

    static func of(_ a: Action) -> Tint {
        switch a.kind {
        case .renamed: return .rename
        case .duplicate: return .duplicate
        case .trashed: return .neutral
        case .sorted: return .neutral
        }
    }
}

enum K {
    static let accent = Tint.accent.fg           // mint ink: switches, selection, links, focus
    static let accentSoft = Tint.accent.bg       // mint pastel: selected rows, on tiles
    static let accentStroke = Tint.accent.stroke
    static let window = Color.dyn(0xF4F2EE, 0x1C1C1E)
    static let sidebar = Color.dyn(0xECE8E1, 0x232325)
    static let sidebarText2 = Color.dyn(0x5E5E63, 0xA1A1A6)   // secondary text on the sidebar material: 5.3:1 light, 5.9:1 dark
    static let rowSelected = Color.dyn(0x000000, 0xFFFFFF, 0.08, 0.10)   // selected sidebar row, hovered pop-up row
    static let glass = Color.dyn(0xFBFAF8, 0x2A2A2C, 0.90, 0.92)
    static let card = Color.dyn(0xFFFFFF, 0x2C2C2E)
    static let cardSoft = Color.dyn(0xFFFFFF, 0x3A3A3C, 0.70, 0.55)
    static let text = Color.dyn(0x1D1D1F, 0xF5F5F7)
    static let text2 = Color.dyn(0x6E6E73, 0xA1A1A6)
    static let text3 = Color.dyn(0x8A8A8E, 0x8E8E93)
    static let separator = Color.dyn(0x000000, 0xFFFFFF, 0.10, 0.12)
    static let fill = Color.dyn(0x000000, 0xFFFFFF, 0.04, 0.07)
    static let fillStrong = Color.dyn(0x000000, 0xFFFFFF, 0.06, 0.10)
    static let neutralBg = Tint.neutral.bg
    static let off = Color.dyn(0x000000, 0xFFFFFF, 0.12, 0.16)   // k2-switch-off
    static let focus = Tint.accent.fg
    static let switchOn = Color.dyn(0x34C759, 0x30D158)   // native switch green (design: k3-switch-on)
}

/// Visible keyboard focus for custom controls (the system ring is hidden because it's rectangular).
struct FocusRing: ViewModifier {
    var radius: CGFloat
    @Environment(\.isFocused) private var focused
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: radius + 2).stroke(K.focus, lineWidth: 2).padding(-2).opacity(focused ? 1 : 0))
    }
}

extension View {
    func focusRing(_ radius: CGFloat = 7) -> some View { modifier(FocusRing(radius: radius)) }
}

/// Reduce Motion / Reduce Transparency, read live.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var solid: Bool { snapshot || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    static var snapshot = false   // ImageRenderer can't draw glass or materials, so snapshots use the solid fallbacks
    /// Critically damped (docs/design-validation §9): no overshoot, interruptible.
    static func spring(_ response: Double = 0.35) -> Animation { reduced ? .easeOut(duration: 0.2) : .spring(response: response, dampingFraction: 1) }
}

// MARK: Text styles

/// The type scale (DESIGN_SYSTEM.md §3). Every text and glyph size comes from here; icons smaller than text (8–9 pt chevrons) stay literal.
enum TS {
    static let micro: CGFloat = 10      // chart labels, tiny badges
    static let meta: CGFloat = 11       // eyebrows, times, sources, key hints, badges
    static let small: CGFloat = 12      // descriptions, secondary lines
    static let body: CGFloat = 13       // rows, buttons, body text
    static let emphasis: CGFloat = 15   // card and section titles, names, page title
    static let heading: CGFloat = 17    // file names in notices
    static let title: CGFloat = 20      // wordmark, large values
    static let title2: CGFloat = 22     // Activity headline
    static let headline: CGFloat = 26   // showcase headline, folder emoji
    static let display: CGFloat = 30    // statements, numerals
    static let hero: CGFloat = 40       // showcase glyph, big emoji
}

extension View {
    func eyebrow() -> some View { font(.system(size: TS.meta, weight: .semibold)).kerning(0.5).foregroundStyle(K.text2).textCase(.uppercase) }
    func card(radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(K.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(K.separator, lineWidth: 0.75))
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).buttonStyle(LinkStyle())
                } else {
                    Text(trailing).font(.system(size: TS.meta)).foregroundStyle(K.text2)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: Buttons

/// Liquid Glass is on for real windows on macOS 26; snapshots (which can't render glass) draw the solid look.
enum Glass26 {
    static var on: Bool { if #available(macOS 26, *) { return !Motion.snapshot } else { return false } }
}

extension View {
    /// Interactive Liquid Glass in `shape`, tinted with a pastel; a solid fill where glass can't render.
    @ViewBuilder func liquid<S: Shape>(_ shape: S, tint: Color? = nil, fallback: Color = K.card, interactive: Bool = true) -> some View {
        if #available(macOS 26, *), Glass26.on {
            glassEffect(SwiftUI.Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(shape.fill(tint ?? fallback)).overlay(shape.stroke(K.separator, lineWidth: 0.75))
        }
    }
}

/// Primary action: a capsule of Liquid Glass tinted with the meaning's pastel, ink label (no white-text buttons).
struct PrimaryStyle: ButtonStyle {
    var tint: Tint = .accent
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .semibold))
            .foregroundStyle(tint.fg)
            .padding(.horizontal, small ? 12 : 14)
            .frame(height: small ? 26 : 30)
            .contentShape(Capsule())
            .liquid(Capsule(), tint: tint.bg.opacity(0.9))
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .focusRing(13)
    }
}

/// Secondary action: a clear Liquid Glass capsule.
struct SecondaryStyle: ButtonStyle {
    var small = false
    var fill: Color = K.card
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .medium))
            .foregroundStyle(K.text)
            .padding(.horizontal, small ? 11 : 14)
            .frame(height: small ? 26 : 30)
            .contentShape(Capsule())
            .liquid(Capsule())
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .focusRing(13)
    }
}

/// The small grey "Undo" pill in rows.
struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TS.small, weight: .medium))
            .foregroundStyle(K.text)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? K.fillStrong.opacity(2) : K.fillStrong))
            .contentShape(Rectangle())
    }
}

struct LinkStyle: ButtonStyle {
    var color: Color = K.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: TS.small, weight: .medium)).foregroundStyle(color.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

/// Tactile press: 96% scale (none with Reduce Motion), no other styling.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PlainRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Small components

struct Keycap: View {
    var key: String
    var inverted = false
    var body: some View {
        Text(key)
            .font(.system(size: TS.meta, weight: .medium))
            .foregroundStyle(inverted ? .white.opacity(0.85) : K.text2)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(inverted ? .white.opacity(0.15) : K.window))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(inverted ? .clear : K.separator, lineWidth: 0.75))
    }
}

/// Shortcut hint inside a button: "⌃⌥⌘⌫" at 70% white.
struct Hint: View {
    var text: String
    var body: some View { Text(text).font(.system(size: TS.meta, weight: .medium)).opacity(0.7) }
}

struct Chip: View {
    var icon: String?
    var text: String
    var tint: Tint
    var onCard = false
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: TS.micro, weight: .semibold)) }
            Text(text).font(.system(size: TS.meta, weight: .semibold))
        }
        .foregroundStyle(tint.fg)
        .padding(.horizontal, 8)
        .frame(height: 21)
        .background(Capsule().fill(onCard ? K.cardSoft : tint.soft))
    }
}

/// "Reads contents · on this Mac" / "Metadata only".
struct Badge: View {
    var icon: String
    var text: String
    var on: Bool? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let on {
                Circle().fill(on ? K.accent : .clear).overlay(Circle().strokeBorder(on ? .clear : K.text3, lineWidth: 1)).frame(width: 6, height: 6)
            } else {
                Image(systemName: icon).font(.system(size: TS.micro))
            }
            Text(text).font(.system(size: TS.meta, weight: .medium))
        }
        .foregroundStyle(on == true ? K.accent : K.text2)
        .padding(.horizontal, 8)
        .frame(height: 21)
        .background(Capsule().fill(on == true ? K.accentSoft : K.fill))
        .overlay(Capsule().strokeBorder(on == nil ? K.separator : .clear, lineWidth: 0.75))
    }
}

struct Pill: View {
    var text: String
    var mono = false
    var body: some View {
        Text(text)
            .font(mono ? .system(size: TS.meta, design: .monospaced) : .system(size: TS.meta))
            .fixedSize()
            .foregroundStyle(K.text2)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(RoundedRectangle(cornerRadius: 5).fill(K.fill))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(K.separator, lineWidth: 0.5))
    }
}

/// Finder tag pill: hollow dot + name.
struct TagPill: View {
    var name: String
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color ?? .clear).overlay(Circle().strokeBorder(color == nil ? K.text3 : .clear, lineWidth: 1)).frame(width: 7, height: 7)
            Text(name).font(.system(size: TS.meta)).fixedSize()
        }
        .foregroundStyle(K.text2)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(K.card))
        .overlay(Capsule().strokeBorder(K.separator, lineWidth: 0.75))
    }
}

struct Dot: View {
    var on: Bool
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(on ? K.accent : .clear)
            .overlay(Circle().strokeBorder(on ? .clear : K.text3, lineWidth: 1.5))
            .frame(width: size, height: size)
            
    }
}

/// The native macOS switch (Liquid Glass knob on macOS 26), green when on per the design.
struct KToggle: View {
    @Binding var on: Bool
    var label: String = ""
    var small = false
    var body: some View {
        Toggle(label, isOn: $on.animation(Motion.spring(0.3)))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(small ? .small : .regular)
            .tint(K.switchOn)
            .accessibilityLabel(label)
    }
}

// MARK: Settings rows

/// A white grouped card of rows separated by hairlines.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }.card()
    }
}

struct Row<Trailing: View>: View {
    var icon: String
    var title: String
    var desc: String? = nil
    var badge: String? = nil
    var dim = false
    var last = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon).font(.system(size: TS.emphasis)).foregroundStyle(K.text2).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: TS.body, weight: .medium)).foregroundStyle(dim ? K.text3 : K.text)
                        if let badge { Text(badge).font(.system(size: TS.micro, weight: .medium)).foregroundStyle(K.text2).padding(.horizontal, 5).frame(height: 16).background(RoundedRectangle(cornerRadius: 4).fill(K.fill)) }
                    }
                    if let desc { Text(desc).font(.system(size: TS.small)).foregroundStyle(dim ? K.text3 : K.text2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if !last { Rectangle().fill(K.separator).frame(height: 0.75).padding(.leading, 16) }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Row where Trailing == EmptyView {
    init(icon: String, title: String, desc: String? = nil, badge: String? = nil, dim: Bool = false, last: Bool = false) {
        self.init(icon: icon, title: title, desc: desc, badge: badge, dim: dim, last: last) { EmptyView() }
    }
}

/// Capsule segmented control: a quiet track and a raised Liquid Glass thumb that slides to the selection.
struct Segmented<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var value: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                let on = value == opt.0
                Button { withAnimation(Motion.reduced ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.82)) { value = opt.0 } } label: {
                    Text(opt.1).font(.system(size: TS.small, weight: on ? .semibold : .regular)).fixedSize()
                        .foregroundStyle(on ? K.text : K.text2)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background {
                            if on {
                                Capsule().fill(K.card).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5).blendMode(.plusLighter))
                                    .liquid(Capsule(), tint: nil, interactive: true)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(K.fill))
        .overlay(Capsule().strokeBorder(K.separator, lineWidth: 0.5))
    }
}

/// Liquid pop-up (k3/Popup): a 30 pt Liquid Glass capsule (optional emoji, value, up/down chevrons); the native menu opens from it.
struct MenuPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var value: T
    var emoji: ((T) -> String)? = nil
    var body: some View {
        Menu {
            Picker("", selection: $value.animation(Motion.spring(0.3))) {
                ForEach(options, id: \.0) { o in Text(emoji.map { "\($0(o.0))  \(o.1)" } ?? o.1).tag(o.0) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 8) {
                if let emoji { Text(emoji(value)).font(.system(size: TS.emphasis)) }
                Text(options.first { $0.0 == value }?.1 ?? "").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: TS.micro, weight: .semibold)).foregroundStyle(K.text2)
            }
            .padding(.horizontal, 12).frame(height: 30)
            .contentShape(Capsule())
            .liquid(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Floating glass chrome (popover, toolbar): clear Liquid Glass on macOS 26, material before, solid with Reduce Transparency.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if Motion.solid {
                shape.fill(K.glass).overlay(shape.strokeBorder(K.separator, lineWidth: 0.75))
            } else if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial).overlay(shape.strokeBorder(Color.white.opacity(0.4), lineWidth: 0.75))
            }
        }
    }
}

extension View {
    func glassSurface(radius: CGFloat = 26) -> some View { modifier(GlassSurface(radius: radius)) }
}

struct PageHeader<Trailing: View>: View {
    var icon: String?
    var title: String
    var subtitle: String
    var badge: (String, String)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let icon {
                Image(systemName: icon).font(.system(size: TS.title)).foregroundStyle(K.accent)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(K.accentSoft))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: TS.title2, weight: .bold)).kerning(-0.3).foregroundStyle(K.text)
                    if let badge { Badge(icon: badge.0, text: badge.1) }
                }
                Text(subtitle).font(.system(size: TS.body)).foregroundStyle(K.text2)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(icon: String?, title: String, subtitle: String, badge: (String, String)? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, badge: badge) { EmptyView() }
    }
}


/// Emoji in a small tile (activity rows, done rows).
struct EmojiTile: View {
    var emoji: String
    var size: CGFloat = 28
    var fill: Color = K.cardSoft
    var body: some View {
        Text(emoji).font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25).fill(fill))
    }
}

/// Emoji for a watched folder.
func folderEmoji(_ path: String) -> String {
    switch (path as NSString).lastPathComponent {
    case "Downloads": return "📥"
    case "Desktop": return "🖥️"
    case "Documents": return "🗂️"
    default: return "📁"
    }
}

extension Date {
    var relative: String {
        let s = -timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if Calendar.current.isDateInToday(self) { return "\(Int(s / 3600)) h ago" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    var clock: String { formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }

    var listTime: String {
        if Calendar.current.isDateInToday(self) { return clock }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
