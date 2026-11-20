import AppKit
import KansoCore
import SwiftUI

// The Tray page of the expanded island (kanso-current.pen, "v5 — Tray grid"): a 4-column grid of 88 pt preview tiles,
// Share and Clear top right, Finder-style selection, drag out to take things away. No Organize, no "Added" notices.

struct TrayPage: View {
    @EnvironmentObject var island: Island
    @ObservedObject var tray = TrayModel.shared
    @State private var frames: [Int: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var shareAnchor = NSView()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if tray.entries.isEmpty && tray.saving.isEmpty { empty } else { grid }
            if let m = tray.message {
                Label(m, systemImage: "exclamationmark.triangle.fill").font(.system(size: TS.small)).foregroundStyle(Tint.duplicate.islandGlyph)
                    .padding(.horizontal, 10).frame(height: 28).background(Capsule().fill(Tint.duplicate.islandFill)).transition(.opacity)
            }
        }
        .overlay {
            if tray.over {   // something is being dragged in
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).padding(-6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tray, \(tray.count) \(tray.count == 1 ? "item" : "items")")
    }

    var header: some View {
        HStack(spacing: 8) {
            Button { withAnimation(Motion.spring()) { island.tray = false } } label: {
                Image(systemName: "chevron.left").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(IslandInk.text).frame(width: 28, height: 28)
                    .background(Circle().fill(IslandInk.control)).contentShape(Circle())
            }
            .buttonStyle(.plain).help("Back (esc)").accessibilityLabel("Back")
            Text("Tray").font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text)
            Text(countLine).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2).monospacedDigit()
            Spacer(minLength: 4)
            if !tray.entries.isEmpty {
                Button { tray.share(from: shareAnchor) } label: { Label(tray.shareLabel, systemImage: "square.and.arrow.up") }
                    .buttonStyle(IslandPillStyle()).background(AnchorView(view: $shareAnchor)).help("Share with AirDrop, Mail, Messages…")
                Button("Clear") { withAnimation(Motion.spring(0.3)) { tray.clear() } }.buttonStyle(IslandPillStyle()).help("Take everything off the Tray (⌘Z brings it back)")
            }
        }
    }

    var gridHeight: CGFloat {
        let rows = (tray.entries.count + tray.saving.count + TrayModel.columns - 1) / TrayModel.columns
        return CGFloat(min(max(rows, 1), 3)) * 138 + 8   // 88 tile + 6 + two lines of name + 12
    }

    var countLine: String {
        let n = tray.count
        let base = n == 0 ? "" : "\(n) \(n == 1 ? "item" : "items")"
        return tray.selected.isEmpty ? base : "\(base) · \(tray.selected.count) selected"
    }

    var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.system(size: TS.title)).foregroundStyle(IslandInk.text2)
            Text("Drop files, links or text here").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text)
            Text("or paste with ⌘V · Finder: Services › Add to Kanso Tray").font(.system(size: TS.small)).foregroundStyle(IslandInk.text2)
        }
        .frame(maxWidth: .infinity).frame(height: 170)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandInk.ink(0.06)))
    }

    var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 20), count: TrayModel.columns), alignment: .leading, spacing: 12) {
                ForEach(tray.saving) { s in TraySavingTile(name: s.name) }
                ForEach(Array(tray.entries.enumerated()), id: \.element.id) { i, e in
                    TrayTile(entry: e, index: i, selected: tray.selection.selected.contains(i))
                        .background(GeometryReader { g in Color.clear.preference(key: TileFrames.self, value: [i: g.frame(in: .named("trayGrid"))]) })
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {   // empty space: a click clears the selection, a drag draws a marquee
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { tray.selection.clear() }
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("trayGrid"))
                        .onChanged { v in
                            let r = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                           width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                            marquee = r
                            tray.selection.marquee(Set(frames.filter { $0.value.intersects(r) }.keys), adding: NSEvent.modifierFlags.contains(.command))
                        }
                        .onEnded { _ in marquee = nil })
            }
            .overlay(alignment: .topLeading) {
                if let r = marquee {
                    Rectangle().fill(Color.accentColor.opacity(0.12)).overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1))
                        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY).allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "trayGrid")
        }
        .frame(height: gridHeight)   // as tall as its rows; scrolls after 3
        .scrollIndicators(.automatic)
        .onPreferenceChange(TileFrames.self) { frames = $0 }
    }
}

private struct TileFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// Small glass-like pills on the island (Share, Clear).
struct IslandPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TS.small, weight: .semibold)).foregroundStyle(IslandInk.text)
            .padding(.horizontal, 11).frame(height: 28)
            .background(Capsule().fill(IslandInk.ink(configuration.isPressed ? 0.2 : 0.12)))
            .hoverHighlight(Capsule())
            .contentShape(Capsule())
    }
}

/// Hands the SwiftUI button's NSView to AppKit (the share sheet anchors to it).
struct AnchorView: NSViewRepresentable {
    @Binding var view: NSView
    func makeNSView(context: Context) -> NSView { let v = NSView(); DispatchQueue.main.async { view = v }; return v }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: Tiles

struct TrayTile: View {
    @ObservedObject var tray = TrayModel.shared
    var entry: TrayModel.Entry
    var index: Int
    var selected: Bool
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Color.accentColor : IslandInk.ink(0.12), lineWidth: selected ? 2.5 : 0.75))
                .overlay { TileInteraction(entry: entry, index: index, hover: $hover) }
                .overlay(alignment: .topTrailing) {
                    if hover {
                        Button { withAnimation(Motion.spring(0.3)) { tray.remove([entry.id]) } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.75)))
                                .frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Remove from the Tray (the file stays where it is)").accessibilityLabel("Remove \(name)")
                        .transition(.opacity)
                    }
                }
            Text(name)
                .font(.system(size: TS.meta, weight: .medium)).multilineTextAlignment(.center).lineLimit(2).truncationMode(entry.item.kind == .file ? .middle : .tail)   // file names keep their extension
                .foregroundStyle(selected ? .white : IslandInk.text)
                .padding(.horizontal, selected ? 4 : 0)
                .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : .clear))
                .frame(width: 88)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Remove") { tray.remove([entry.id]) }
        .accessibilityAction(named: "Quick Look") { tray.selection.click(index); tray.quickLook() }
        .accessibilityAction(named: "Copy") { tray.selection.click(index); tray.copySelection() }
    }

    var name: String {
        if entry.item.kind == .link, let t = tray.previews[entry.id]?.title { return t }
        return entry.item.kind == .snippet ? "Text" : entry.item.name
    }

    var spoken: String {
        switch entry.item.kind {
        case .file: return entry.missing ? "\(name), missing" : "\(name), \(entry.url?.pathExtension.uppercased() ?? "file"), from \(entry.url?.deletingLastPathComponent().lastPathComponent ?? "")"
        case .link: return "\(name), link to \(entry.item.name)"
        case .snippet: return "Text: \(entry.item.text.prefix(80))"
        }
    }

    @ViewBuilder var preview: some View {
        switch entry.item.kind {
        case .file:
            if let u = entry.url { Thumb(path: u.path).background(IslandInk.ink(0.06)) }
            else {
                VStack(spacing: 4) {
                    Image(systemName: "doc.badge.ellipsis").font(.system(size: TS.title)).foregroundStyle(IslandInk.text3)
                    Text("Missing").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(IslandInk.ink(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(IslandInk.ink(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        case .link:
            if let img = tray.previews[entry.id]?.image {
                VStack(spacing: 0) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 88, height: 62).clipped()
                    host.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(IslandInk.ink(0.06))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: TS.heading)).foregroundStyle(IslandInk.text2)
                    host
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(IslandInk.ink(0.06))
            }
        case .snippet:
            Text(entry.item.text).font(.system(size: TS.meta)).foregroundStyle(Tint.rename.islandGlyph).lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                .background(Tint.rename.islandFill)
        }
    }

    var host: some View {
        Text(entry.item.name.hasPrefix("www.") ? String(entry.item.name.dropFirst(4)) : entry.item.name).font(.system(size: TS.meta, weight: .medium)).foregroundStyle(IslandInk.text2).lineLimit(1).truncationMode(.middle).padding(.horizontal, 6)
    }
}

/// A browser image or Mail attachment being saved: a dimmed tile with a turning ring.
struct TraySavingTile: View {
    var name: String
    @State private var turn = false
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IslandInk.ink(0.1)).frame(width: 88, height: 88)
                .overlay {
                    Circle().trim(from: 0, to: 0.65).stroke(IslandInk.text2, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 30, height: 30)
                        .rotationEffect(.degrees(turn ? 360 : 0))
                        .animation(Motion.reduced ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: turn)
                }
            Text("Saving…").font(.system(size: TS.meta, weight: .medium)).foregroundStyle(IslandInk.text2).frame(width: 88)
        }
        .onAppear { turn = true }
        .accessibilityElement(children: .ignore).accessibilityLabel("Saving \(name)")
    }
}

// MARK: Click, double-click and drag out (AppKit, so Kanso learns whether the drop was accepted)

struct TileInteraction: NSViewRepresentable {
    var entry: TrayModel.Entry
    var index: Int
    @Binding var hover: Bool

    func makeNSView(context: Context) -> TileDragView { let v = TileDragView(); configure(v); return v }
    func updateNSView(_ v: TileDragView, context: Context) { configure(v) }

    private func configure(_ v: TileDragView) {
        let tray = TrayModel.shared, i = index
        v.onClick = { cmd, shift in withAnimation(.easeOut(duration: 0.12)) { tray.selection.click(i, command: cmd, shift: shift) } }
        v.onDouble = { tray.selection.click(i); tray.openSelection() }
        v.onHover = { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        v.items = {
            if !tray.selection.selected.contains(i) { tray.selection.click(i) }
            return tray.selected.filter { !$0.missing }.map { e in (tray.object(e), e) }
        }
        v.onEnded = { ids, accepted, keep in if accepted && !keep { withAnimation(Motion.spring(0.3)) { tray.remove(ids) } } }
    }
}

final class TileDragView: NSView, NSDraggingSource {
    var onClick: (Bool, Bool) -> Void = { _, _ in }
    var onDouble: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var items: () -> [(Any?, TrayModel.Entry)] = { [] }
    var onEnded: (Set<UUID>, Bool, Bool) -> Void = { _, _, _ in }
    private var down: NSEvent?
    private var dragging: Set<UUID> = []

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { onHover(true) }
    override func mouseExited(with e: NSEvent) { onHover(false) }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        down = e
        if e.clickCount == 2 { onDouble(); return }
        onClick(e.modifierFlags.contains(.command), e.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = down, hypot(e.locationInWindow.x - d.locationInWindow.x, e.locationInWindow.y - d.locationInWindow.y) > 3 else { return }
        down = nil
        let picked = items()
        var dragItems: [NSDraggingItem] = []
        for (n, (obj, entry)) in picked.enumerated() {
            guard let w = obj as? NSPasteboardWriting else { continue }
            let item = NSDraggingItem(pasteboardWriter: w)
            let icon: NSImage = entry.url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: entry.item.kind == .link ? "link" : "text.alignleft", accessibilityDescription: nil) ?? NSImage()
            item.setDraggingFrame(NSRect(x: CGFloat(n) * 6, y: CGFloat(-n) * 6, width: 64, height: 64), contents: icon)
            dragItems.append(item)
        }
        guard !dragItems.isEmpty else { return }
        dragging = Set(picked.map(\.1.id))
        let s = beginDraggingSession(with: dragItems, event: e, source: self)
        s.animatesToStartingPositionsOnCancelOrFail = true
    }

    /// Like Finder: Finder moves within a disk and copies across disks; ⌥ forces a copy.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }

    /// Accepted anywhere: the items leave the Tray, unless ⇧ is held.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnded(dragging, operation != [], NSEvent.modifierFlags.contains(.shift))
        dragging = []
    }
}

// MARK: The compact drop target (a drag dwelled on the island)

struct TrayDropTarget: View {
    @ObservedObject var tray = TrayModel.shared
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.to.line").font(.system(size: TS.heading, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text(TrayDragMonitor.shared.dragLabel).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text)
            Text("They stay where they are").font(.system(size: TS.small)).foregroundStyle(IslandInk.text2)
        }
        .frame(width: 380, height: 96)
        .overlay(IslandShape(ears: false, radius: 30).stroke(Color.accentColor, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}
