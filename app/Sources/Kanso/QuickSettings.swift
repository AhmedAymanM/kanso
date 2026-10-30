import KansoCore
import SwiftUI

/// Quick settings: the popover under the menu bar icon, for configuring Kanso, never for activity or stats (CONTEXT.md).
/// Sorting is the first, wide tile; tapping it morphs the tile into the On / Off menu.
struct QuickSettings: View {
    @EnvironmentObject var m: AppModel
    @State private var menuOpen = ProcessInfo.processInfo.environment["KANSO_QS"] == "menu"   // screenshots of the open menu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !m.needs.isEmpty && m.sortingOn { needsRow }
            VStack(alignment: .leading, spacing: 6) {
                Text("Features").eyebrow().padding(.horizontal, 2)
                tiles
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(K.sidebar)   // the same shade as the App window's sidebar, solid over the popover's own material
        .focusEffectDisabled()   // our own mint focus ring is drawn instead of the square system one
        .animation(Motion.spring(), value: menuOpen)
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Kanso").font(.system(size: TS.title, weight: .regular, design: .serif)).foregroundStyle(K.text)
            Text("簡素").font(.system(size: TS.small, design: .serif)).foregroundStyle(K.text2)
            Spacer()
            Text("v\(Bundle.main.version)").font(.system(size: TS.meta)).foregroundStyle(K.text2)
        }
        .padding(.horizontal, 4)
    }

    var needsRow: some View {
        Button { StatusItem.shared.close(); Island.shared.openOverview() } label: {
            HStack(spacing: 8) {
                Circle().fill(Tint.accent.fg).frame(width: 7, height: 7)
                Text("\(m.needs.count) need\(m.needs.count == 1 ? "s" : "") you").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(Tint.accent.fg)
                Text("· Show Kanso").font(.system(size: TS.body)).foregroundStyle(K.text2)
                Spacer()
                Keycap(key: m.settings.islandShortcut.display)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.tileOn))
        }
        .buttonStyle(PlainRowStyle())
        .focusRing(12)
    }

    var tiles: some View {
        VStack(spacing: 8) {
            sortingHeader.frame(height: 52).tileBackground(on: m.sortingOn).opacity(menuOpen ? 0 : 1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                FeatureTile(icon: "pencil", name: "Renaming", on: m.binding(\.renaming))
                FeatureTile(icon: "tag", name: "Tagging", on: m.binding(\.tagging))
                FeatureTile(icon: "doc.on.doc", name: "Duplicates", on: m.binding(\.duplicates))
                FeatureTile(icon: "eject", name: "Smart Eject", on: m.binding(\.smartEject))
            }
            .allowsHitTesting(!menuOpen)
        }
        // No container: tiles sit straight on the popover's glass, 8 pt apart (never glass on glass).
        // The menu morphs out of the tile: same top-left origin, the tile becomes its header row, and it floats over the grid.
        .overlay(alignment: .top) {
            if menuOpen {
                VStack(spacing: 0) {
                    sortingHeader.frame(height: 52)
                    Rectangle().fill(K.separator).frame(height: 0.75).padding(.horizontal, 10)
                    VStack(spacing: 2) {
                        option("power", "On", checked: m.sortingOn) { m.setSorting(true) }
                        option("timer", "Off for 1 hour", checked: false) { m.setSorting(false, for: .hour) }
                        option("sunrise", "Off until tomorrow", checked: false) { m.setSorting(false, for: .tomorrow) }
                        option("moon.zzz", "Off until I turn it on", checked: !m.sortingOn && m.settings.sortingOffUntil == nil) { m.setSorting(false, for: .untilOn) }
                    }
                    .padding(6)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.tileOn))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                .transition(Motion.reduced ? .opacity : .scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .onExitCommand { menuOpen = false }
    }

    /// The wide first tile's content; the same row heads the open menu.
    var sortingHeader: some View {
        let on = m.sortingOn
        return Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { menuOpen.toggle() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d").font(.system(size: TS.emphasis)).foregroundStyle(on ? K.text2 : K.text3).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sorting").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    Text(on ? "On · watching \(m.settings.activeRoots.count) \(m.settings.activeRoots.count == 1 ? "folder" : "folders")" : "Off · \(m.offLine)").font(.system(size: TS.meta)).foregroundStyle(on ? Tint.accent.fg : K.text2)
                        .contentTransition(.opacity)
                }
                Spacer()
                if !menuOpen { Dot(on: on, size: 7) }
                Image(systemName: "chevron.down").font(.system(size: TS.meta, weight: .semibold)).foregroundStyle(K.text2).rotationEffect(.degrees(menuOpen ? 180 : 0))
            }
            .padding(.horizontal, 14).frame(maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .focusRing(16)
        .accessibilityLabel("Sorting, \(on ? "on" : "off")")
        .accessibilityHint("Shows options for turning Sorting off")
    }

    func option(_ icon: String, _ title: String, checked: Bool, _ run: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { run(); menuOpen = false } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: TS.small)).foregroundStyle(K.text2).frame(width: 18)
                Text(title).font(.system(size: TS.body)).foregroundStyle(K.text)
                Spacer()
                if checked { Image(systemName: "checkmark").font(.system(size: TS.meta, weight: .semibold)).foregroundStyle(K.text) }
            }
            .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    var footer: some View {
        HStack(spacing: 6) {
            Dot(on: m.aiReady || !m.settings.appleIntelligence, size: 6)
            Text("Apple Intelligence").font(.system(size: TS.small)).foregroundStyle(K.text2)
            Spacer()
            GlassIconButton(symbol: "gearshape", label: "Settings") { Windows.shared.showSettings() }.keyboardShortcut(",")
            GlassIconButton(symbol: "power", label: "Quit Kanso") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}

extension QuickSettings {
    /// On: a solid tile, white in light mode and near-black in dark (no glass on the popover's glass).
    static let tileOn = Color.dyn(0xFFFFFF, 0x1C1C1E)
    /// Off: a flat grey that reads as disabled.
    static let tileOff = Color.dyn(0xE3E3E6, 0x3A3A3C)
}

extension View {
    /// A Quick settings tile: solid and slightly raised when on; flat grey when off.
    func tileBackground(on: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? QuickSettings.tileOn : QuickSettings.tileOff)
            .shadow(color: .black.opacity(on ? 0.14 : 0), radius: on ? 4 : 0, y: on ? 2 : 0))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(K.separator, lineWidth: on ? 0.5 : 0))
    }
}

/// Hovered row is a soft grey pill (k3-row-selected).
struct HoverRowStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover || configuration.isPressed ? K.rowSelected : .clear))   // 16 card − 6 padding
            .onHover { hover = $0 }
    }
}

/// 28 pt icon-only glass circle, like the island's Settings button.
struct GlassIconButton: View {
    var symbol: String, label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: TS.small)).foregroundStyle(K.text).frame(width: 28, height: 28)
                .background(Circle().fill(QuickSettings.tileOn).shadow(color: .black.opacity(0.12), radius: 2, y: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PlainRowStyle()).focusRing(14).help(label).accessibilityLabel(label)
    }
}

struct FeatureTile: View {
    var icon: String
    var name: String
    @Binding var on: Bool
    var body: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { on.toggle() } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).font(.system(size: TS.body, weight: on ? .semibold : .light)).foregroundStyle(on ? K.text : K.text3)
                    Spacer()
                    if on { Circle().fill(Tint.accent.fg).frame(width: 7, height: 7) } else { Circle().strokeBorder(K.controlStroke, lineWidth: 1).frame(width: 7, height: 7) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    Text(on ? "On" : "Off").font(.system(size: TS.meta)).foregroundStyle(on ? Tint.accent.fg : K.text2)
                }
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .tileBackground(on: on)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: on)
        }
        .buttonStyle(PressStyle())
        .focusRing(16)
        .accessibilityLabel("\(name), \(on ? "on" : "off")")
    }
}

func summary(_ a: Action) -> String {
    switch a.kind {
    case .renamed: return "Renamed from \(a.oldName ?? a.srcName)"
    case .duplicate: return a.shelf == "Trash" ? "Copy moved to Trash" : "Copy moved to Duplicates"
    case .trashed: return a.details["installer"] != nil ? "Installer moved to Trash" : "Moved to Trash"
    case .sorted: return "Sorted to \(a.shelf)"
    }
}

struct RulePreviewRow: View {
    var condition: Condition
    var shelf: String
    var emoji: String
    var body: some View {
        HStack(spacing: 6) {
            Text("IF").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(Tint.rule.fg)
            Text(conditionText(condition)).font(.system(size: TS.small)).padding(.horizontal, 6).frame(height: 20).background(RoundedRectangle(cornerRadius: 5).fill(K.card))
            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(K.text3)
            Text("\(emoji) \(shelf)").font(.system(size: TS.small, weight: .medium)).padding(.horizontal, 6).frame(height: 20).background(RoundedRectangle(cornerRadius: 5).fill(K.card))
            Spacer(minLength: 0)
        }
        .foregroundStyle(K.text)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(K.cardSoft))
    }
}

func conditionText(_ c: Condition) -> String {
    switch c.field {
    case .name: return "name matches “\(c.value)”"
    case .ext: return "extension is .\(c.value)"
    case .from: return "downloaded from \(c.value)"
    case .size: return "size is over \(c.value)"
    }
}
