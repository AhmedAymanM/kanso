import AppKit
import KansoCore
import SwiftUI

// The Tray page of the expanded island (v2 beta, files only). docs/design/proposals/tray.md.
// Copy: "Tray", "Organize", "Forget" (a row, never a file). Never "drop zone", "basket" or "stash".

private enum TrayInk {
    static let mint = Color(nsColor: NSColor(hex: 0xCFE8D8))
    static let mintInk = Color(nsColor: NSColor(hex: 0x2E5A4B))
    static let edge = Color.white.opacity(0.4)       // 3.66:1 on black, for control edges
    static let warn = Color(nsColor: NSColor(hex: 0xF3D79B))
}

struct TrayBody: View {
    @EnvironmentObject var island: Island
    @EnvironmentObject var m: AppModel
    @ObservedObject var tray = TrayModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.stagger(0)
            content.stagger(1)
            if let e = tray.error { line(e, icon: "exclamationmark.triangle", color: TrayInk.warn).stagger(2) }
            else if let n = tray.note { line(n, icon: "checkmark.circle", color: IslandInk.text2).stagger(2) }
            footer.stagger(3)
        }
        .padding(.top, island.skin == .capsule ? 10 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tray, \(tray.count) \(tray.count == 1 ? "item" : "items")")
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.accent.islandGlyph)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tint.accent.islandFill)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Tray").font(.system(size: TS.heading, weight: .bold)).foregroundStyle(IslandInk.text)
                    Text("BETA").font(.system(size: TS.meta, weight: .semibold)).kerning(0.5).foregroundStyle(IslandInk.text2)
                        .padding(.horizontal, 6).frame(height: 16).background(Capsule().strokeBorder(TrayInk.edge, lineWidth: 1))
                }
                Text(subtitle).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2)
            }
            Spacer(minLength: 8)
            if tray.phase == .list && tray.count > 0 {
                Button { tray.clear() } label: {
                    Text("Clear").font(.system(size: TS.small, weight: .medium)).foregroundStyle(IslandInk.text)
                        .padding(.horizontal, 12).frame(minHeight: 28).background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressStyle()).help("Forget every row. The files stay where they are.").accessibilityLabel("Clear the Tray")
                .accessibilityHint("Forgets the rows. The files stay where they are.")
            }
        }
    }

    var subtitle: String {
        switch tray.phase {
        case .planning(let i, let n): return "Planning \(max(i, 1)) of \(n)"
        case .review: return "Where each file would go. Nothing has moved."
        case .moving: return "Moving…"
        case .list: return tray.count == 0 ? "Carry files here, then file them together." : "\(tray.count) \(tray.count == 1 ? "file" : "files") · they stay where they are until you Organize"
        }
    }

    // MARK: Content

    @ViewBuilder var content: some View {
        if tray.over { well("Release to add to the Tray", "Nothing moves until you Organize.", icon: "arrow.down.to.line", active: true) }
        else {
            switch tray.phase {
            case .list:
                if tray.entries.isEmpty { well("Drop files here", "or paste with ⌘V", icon: "tray", active: false) } else { rows }
            case .planning(let i, let n):
                HStack(spacing: 10) {
                    ThinkingOrb().accessibilityHidden(true)
                    Text("Planning \(max(i, 1)) of \(n)").font(.system(size: TS.body, weight: .medium)).foregroundStyle(IslandInk.text)
                    Spacer()
                }
                .padding(.vertical, 22).padding(.horizontal, 4)
            case .review: plan
            case .moving:
                Text("Moving…").font(.system(size: TS.body, weight: .medium)).foregroundStyle(IslandInk.text).padding(.vertical, 22)
            }
        }
    }

    func well(_ title: String, _ detail: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(active ? TrayInk.mint : IslandInk.text2)
            Text(title).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(IslandInk.text)
            Text(detail).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2)
        }
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(active ? TrayInk.mint.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? TrayInk.mint : TrayInk.edge, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }

    var rows: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Array(tray.entries.enumerated()), id: \.element.id) { i, e in
                    TrayRowView(entry: e, selected: i == tray.selection) { tray.forget(e.id) }
                        .onTapGesture { tray.selection = i }
                }
            }
        }
        .frame(height: min(CGFloat(tray.entries.count), 6) * 46)
    }

    var plan: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Array((tray.plan?.rows ?? []).enumerated()), id: \.element.id) { i, row in TrayPlanRow(selected: i == tray.planSelection, row: row) }
            }
        }
        .frame(height: min((tray.plan?.rows ?? []).reduce(CGFloat(0)) { $0 + ($1.stays.map { $0.count > 46 } == true ? 60 : 46) }, 300))
    }

    func line(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: TS.small)).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(.system(size: TS.small)).foregroundStyle(color == IslandInk.text2 ? IslandInk.text2 : IslandInk.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    @ViewBuilder var footer: some View {
        HStack(spacing: 8) {
            switch tray.phase {
            case .list:
                TrayButton(label: "Organize", key: "↩", primary: true, enabled: tray.entries.contains { $0.state == .ready }) { tray.organize() }
                if tray.canUndo && tray.error != nil { TrayButton(label: tray.undoLabel, key: "⌘Z", primary: false) { tray.undo() } }
                Spacer(minLength: 0)
                if tray.entries.isEmpty == false {
                    Text("Nothing moves until you Organize").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3).lineLimit(2).multilineTextAlignment(.trailing)
                }
            case .planning:
                TrayButton(label: "Cancel", key: "esc", primary: false) { _ = tray.escape() }
                Spacer(minLength: 0)
            case .review:
                let n = tray.plan?.movable ?? 0
                TrayButton(label: "Move \(n)", key: "↩", primary: true) { tray.move() }
                TrayButton(label: "Not now", key: "esc", primary: false) { _ = tray.escape() }
                Text("↑ ↓ pick a file · ← → change its shelf").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3).lineLimit(2)
                Spacer(minLength: 0)
                if tray.plan?.modelOff == true { Text("Apple Intelligence is off").font(.system(size: TS.meta)).foregroundStyle(IslandInk.text3) }
            case .moving:
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: Rows

struct TrayRowView: View {
    var entry: TrayEntry
    var selected: Bool
    var forget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 28, height: 28).opacity(entry.state == .missing ? 0.4 : 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: TS.body, weight: .medium)).foregroundStyle(entry.state == .missing ? IslandInk.text3 : IslandInk.text)
                    .strikethrough(entry.state == .missing).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.locked { Image(systemName: "lock.fill").font(.system(size: TS.small)).foregroundStyle(IslandInk.text2).help("Moved by file type only, never read").accessibilityHidden(true) }
            Button(action: forget) {
                Image(systemName: "xmark").font(.system(size: TS.small, weight: .semibold)).foregroundStyle(IslandInk.text2).frame(width: 28, height: 28)
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(PlainRowStyle()).help("Forget (the file stays where it is)").accessibilityLabel("Forget \(entry.name)")
        }
        .padding(.horizontal, 8).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(selected ? 0.1 : 0)))
        .overlay { if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(spoken)")
        .accessibilityAction(named: "Forget") { forget() }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var detail: String {
        switch entry.state {
        case .missing: return "Missing. Forget it to clear the row."
        case .manualShelves: return "In Manual Shelves, Kanso leaves it there"
        case .keep: return "Kanso leaves it where it is"
        case .ready: return "From \(entry.folder)" + (entry.placeholder ? " · in iCloud, never read" : "")
        }
    }

    var spoken: String {
        switch entry.state {
        case .missing: return "missing"
        case .manualShelves: return "in Manual Shelves, Kanso leaves it there"
        case .keep: return "Kanso leaves it where it is"
        case .ready: return "file from \(entry.folder)" + (entry.locked ? ", locked, never read" : "")
        }
    }
}

struct TrayPlanRow: View {
    var selected = false
    @EnvironmentObject var m: AppModel
    @ObservedObject var tray = TrayModel.shared
    var row: TrayRow

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.entry.url.path)).resizable().frame(width: 28, height: 28).opacity(row.moves ? 1 : 0.5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: TS.body, weight: .medium)).foregroundStyle(row.moves ? IslandInk.text : IslandInk.text2).lineLimit(1).truncationMode(.middle)
                Text(second).font(.system(size: TS.small)).foregroundStyle(IslandInk.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if row.moves, let shelf = tray.shelf(for: row) {
                if row.newShelf && tray.overrides[row.id] == nil {
                    Text("new shelf").font(.system(size: TS.meta, weight: .semibold)).foregroundStyle(Tint.accent.islandGlyph)
                        .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Tint.accent.islandFill))
                }
                Menu {
                    ForEach(tray.shelfChoices, id: \.self) { s in Button("\(m.settings.emoji(for: s)) \(s)") { tray.choose(s, for: row.id) } }
                } label: {
                    Text((row.destRoot.map { "\($0) › " } ?? "") + "\(m.settings.emoji(for: shelf)) \(shelf)").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(IslandInk.text).fixedSize().lineLimit(1)
                        .padding(.horizontal, 10).frame(minHeight: 28).background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Change a shelf…").accessibilityLabel("Change a shelf for \(row.name), now \(shelf)")
            }
        }
        .padding(.horizontal, 8).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(selected ? 0.1 : 0)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
    }

    var second: String {
        if let why = row.stays { return why }
        return "From \(row.entry.folder) · \(row.basis)"
    }

    var spoken: String {
        if let why = row.stays { return "\(row.name), stays. \(why)" }
        let shelf = tray.shelf(for: row) ?? ""
        return "\(row.name), goes to \(row.destRoot.map { "\($0), " } ?? "")\(shelf), based on \(row.basis)" + (row.newShelf ? ", new shelf" : "")
    }
}

/// A 28 pt capsule button with its key. The primary one is the mint fill.
struct TrayButton: View {
    var label: String
    var key: String
    var primary: Bool
    var enabled = true
    var action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: TS.body, weight: .semibold))
                Text(key).font(.system(size: TS.meta, weight: .medium)).opacity(0.75)
            }
            .foregroundStyle(primary ? TrayInk.mintInk : IslandInk.text)
            .padding(.horizontal, 14).frame(minHeight: 28)
            .background(Capsule().fill(primary ? TrayInk.mint : Color.white.opacity(0.1)))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle()).disabled(!enabled)
        .focused($focused).focusRing(14)
        // SwiftUI focus never becomes the panel's first responder, so tell the Tray which button has it: Return and Space
        // then press that button (Tab to "Not now" and Return cancels) instead of the page's default action.
        .onChange(of: focused) { f in
            if f { TrayModel.shared.focusedButton = (label, action) }
            else if TrayModel.shared.focusedButton?.label == label { TrayModel.shared.focusedButton = nil }
        }
        .onDisappear { if TrayModel.shared.focusedButton?.label == label { TrayModel.shared.focusedButton = nil } }
        .accessibilityLabel(label)
    }
}

/// The lip's tray glyph with a count badge while carrying.
struct TrayLipButton: View {
    @EnvironmentObject var island: Island
    @ObservedObject var tray = TrayModel.shared
    var body: some View {
        IslandGlassButton(symbol: island.tray ? "tray.full.fill" : "tray", label: tray.badge > 0 ? "Tray, \(tray.badge) \(tray.badge == 1 ? "item" : "items")" : "Tray") { island.toggleTray() }
            .overlay(alignment: .topTrailing) {
                if tray.badge > 0 {
                    Text("\(min(tray.badge, 99))").font(.system(size: TS.meta, weight: .bold)).foregroundStyle(TrayInk.mintInk)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16).background(Capsule().fill(TrayInk.mint)).offset(x: 4, y: -4).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}
