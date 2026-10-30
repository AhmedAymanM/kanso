import AppKit
import KansoCore
import SwiftUI

/// Renders every screen to PNG in light and dark mode (`Kanso --snapshot DIR`), for checking the UI without clicking.
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        Motion.snapshot = true
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let m = AppModel.shared
        m.engine.detectCorrections()
        m.refresh()
        // KANSO_SELECT opens one Activity entry: renamed, sorted, batch, rename-review, rule, duplicate, installer, waiting, undone
        // (or an action kind). KANSO_EXPAND=1 / KANSO_INDEX=n open the file-by-file view of a batch or rename review.
        if let k = ProcessInfo.processInfo.environment["KANSO_SELECT"] {
            m.waiting = [Waiting(url: URL(fileURLWithPath: "/tmp/keynote-recording.mov.crdownload"), root: URL(fileURLWithPath: "/tmp"), size: 48_000_000, partial: true, since: Date().addingTimeInterval(-3600), shelf: "Videos")]
            switch k {
            case "rename-review": m.selectedActivity = "renames"
            case "rule": m.selectedActivity = m.pending.suggestions.first?.id.uuidString
            case "batch": m.selectedActivity = m.actions.first { $0.run == "b1" }.map { "run-" + $0.run }
            case "waiting": m.selectedActivity = m.waiting.first.map { "wait-" + $0.id }
            case "duplicate": m.selectedActivity = m.actions.last { $0.kind == .duplicate && $0.pending }?.id.uuidString
            case "installer": m.selectedActivity = m.actions.last { $0.details["installer"] != nil }?.id.uuidString
            case "undone": m.selectedActivity = m.actions.last { $0.undone }?.id.uuidString
            case "sorted": m.selectedActivity = m.actions.last { $0.kind == .sorted && $0.why == "screenshot" }?.id.uuidString
            default: m.selectedActivity = m.actions.last { $0.kind.rawValue == k }?.id.uuidString
            }
        }
        let only = ProcessInfo.processInfo.environment["KANSO_SNAPSHOT_ONLY"]?.split(separator: ",").map(String.init)
        for mode in ["light", "dark"] {
            let ap = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)!
            func shot<V: View>(_ name: String, _ size: CGSize, _ view: V) {
                if let only, !only.contains(where: { name.hasPrefix($0) }) { return }
                render(view.environmentObject(m).environmentObject(Island.shared), size: size, appearance: ap, to: "\(dir)/\(name)-\(mode).png")
            }
            for p in Page.allCases {
                m.page = p
                shot("app-\(p.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-"))", CGSize(width: 1180, height: 860), AppWindow())
            }
            shot("rule-editor", CGSize(width: 860, height: 420), RowGroup {
                RuleRow(rule: Rule([Condition(.name, "*lecture*"), Condition(.from, "canvas.uni.se")], dest: "Documents"), open: true, count: 14, toggle: {}, close: {})
            }.padding(24).background(K.window))
            let demo: [String: Int] = ["Utilities": 8, "Utility bills": 3]
            shot("tag-picker-search", CGSize(width: 260, height: 170), TagPicker(counts: demo, existing: ["Invoice"], text: "Util") { _, _ in }.background(K.window))
            shot("tag-picker-color", CGSize(width: 260, height: 130), TagPicker(counts: demo, existing: [], text: "Util", stage: .color("Util")) { _, _ in }.background(K.window))
            shot("name-popover", CGSize(width: 300, height: 120), NamePopover(title: "Rename Invoice-Vattenfall-2026-03.pdf", initial: "Invoice-Vattenfall-2026-03.pdf", commit: { _ in true }, close: {}).background(K.window))
            shot("quick-settings", CGSize(width: 340, height: 560), QuickSettings())
            shot("review-renames", CGSize(width: 1000, height: 720), ReviewView(tab: .renames))
            for (i, st) in [OnboardingView.Step.folders, .island, .ai, .files, .declined].enumerated() { shot("onboarding-\(i)", CGSize(width: 640, height: 560), OnboardingView(step: st)) }
            // Island states, both skins, on a menu bar backdrop.
            let island = Island.shared
            island.notch = CGSize(width: 190, height: 32)
            for skin in [Island.Skin.notch, .capsule] {
                island.skin = skin
                let tag = skin == .notch ? "notch" : "capsule"
                for (name, notices, expanded, overview) in islandSamples(m) {
                    island.notices = notices; island.index = name == "fan" ? 1 : max(0, notices.count - 1); island.expanded = expanded; island.overview = overview; island.selection = 0
                    island.shortcuts = name == "shortcuts"; island.fanned = name == "fan"
                    let renamedIDs = m.actions.filter { $0.kind == .renamed }.suffix(3).map(\.id)
                    let dupIDs = m.actions.filter { $0.kind == .duplicate && $0.pending }.map(\.id)
                    switch name {
                    case "ask-thinking": island.askText = "put the lecture slides in Uni"; island.askState = .thinking
                    case "ask-move": island.askState = .move(shelf: "Documents", ids: renamedIDs)
                    case "ask-trash": island.askState = .trash(ids: dupIDs)
                    case "ask-answer": island.askState = .answer("Scan_0044.pdf is a 2019 parking receipt from Q-Park, 1 page. Read on this Mac from page 1; nothing kept.", tainted: true, ids: renamedIDs.suffix(1).map { $0 })
                    default: island.askText = ""; island.askState = .idle
                    }
                    shot("island-\(tag)-\(name)", CGSize(width: Island.size.width, height: expanded ? Island.size.height : 120), IslandBackdrop(skin: skin))
                }
                island.shortcuts = false; island.fanned = false; island.askState = .idle; island.askText = ""
            }
            // The Tray (beta): empty, drag over, items, planning, preview, partial failure.
            m.engine.store.update { $0.trayEnabled = true }
            m.refresh()
            let tm = TrayModel.shared
            let docs = "/Users/demo/Downloads", desk = "/Users/demo/Desktop"
            func ent(_ name: String, _ dir: String, _ state: TrayState = .ready, locked: Bool = false) -> TrayEntry { TrayEntry(url: URL(fileURLWithPath: dir + "/" + name), state: state, locked: locked) }
            let carrying = [ent("Lease-2026.pdf", docs), ent("IMG_2041.heic", desk), ent("id_ed25519.pem", docs, locked: true), ent("old-notes.txt", desk, .missing)]
            func prow(_ e: TrayEntry, _ shelf: String?, _ basis: String, new: Bool = false, stays: String? = nil) -> TrayRow { TrayRow(entry: e, shelf: shelf, basis: basis, newShelf: new, stays: stays, willMove: stays == nil) }
            var preview = TrayPlan()
            preview.rows = [prow(carrying[0], "Documents", "by file type"), prow(carrying[1], "Images", "by file type"), prow(carrying[2], "Keys", "by file type, never read"),
                            prow(TrayEntry(url: URL(fileURLWithPath: desk + "/mockup.qx7")), "Mockups", "asked Apple Intelligence", new: true), prow(carrying[3], nil, "", stays: "Missing. Forget it to clear the row.")]
            let trays: [(String, () -> Void)] = [
                ("empty", { tm.demo(entries: []) }),
                ("over", { tm.demo(entries: Array(carrying.prefix(2)), note: nil, over: true) }),
                ("items", { tm.demo(entries: carrying, note: "Added 3 to the Tray", selection: 1) }),
                ("planning", { tm.demo(entries: carrying, phase: .planning(3, 4)) }),
                ("preview", { tm.demo(entries: carrying, phase: .review, plan: preview) }),
                ("error", { tm.demo(entries: [carrying[0]], error: "Moved 3 of 4. 1 stayed in the Tray: Lease-2026.pdf. Couldn't move it. It may be open in another app, or the shelf isn't writable.") }),
            ]
            for skin in [Island.Skin.notch, .capsule] {
                island.skin = skin
                island.notices = []; island.expanded = true; island.overview = true; island.tray = true; island.shortcuts = false; island.askState = .idle
                for (name, setup) in trays {
                    setup()
                    shot("island-\(skin == .notch ? "notch" : "capsule")-tray-\(name)", CGSize(width: Island.size.width, height: Island.size.height), IslandBackdrop(skin: skin))
                }
            }
            island.tray = false; tm.demo(entries: [])
            m.engine.store.update { $0.trayEnabled = false }
            m.refresh()
            island.notices = []; island.expanded = false; island.overview = false
            shot("icon", CGSize(width: 256, height: 256), AppIcon().padding(20))
        }
        print("snapshots in \(dir)")
    }

    static func icon(to path: String) {
        _ = NSApplication.shared
        render(AppIcon().padding(50), size: CGSize(width: 512, height: 512), appearance: NSAppearance(named: .aqua)!, to: path)  // 2x → 1024 px
    }

    static func islandSamples(_ m: AppModel) -> [(String, [Notice], Bool, Bool)] {
        var out: [(String, [Notice], Bool, Bool)] = []
        let renamed = m.actions.filter { $0.kind == .renamed }.suffix(3).map { Notice.renamed($0) }
        if let r = renamed.last { out.append(("renamed", [r], false, false)); out.append(("renamed-expanded", [r], true, false)) }
        if renamed.count > 1 { out.append(("count-up", Array(renamed), false, false)) }
        if let d = m.actions.last(where: { $0.kind == .duplicate }) { out.append(("duplicate", [.duplicate(d)], false, false)); out.append(("duplicate-expanded", [.duplicate(d)], true, false)) }
        var inst = Action(run: "x", kind: .trashed, src: "/Downloads/My Shelves/Apps/Figma.dmg", dst: "/.Trash/Figma.dmg", root: "/Downloads", shelf: "Trash", why: "installer", source: "Smart Eject")
        inst.details = ["installer": "Figma", "size": "210000000"]
        out.append(("installer", [.installer(inst)], false, false))
        out.append(("sorting-off", [.sortingOff(Date().addingTimeInterval(-90000))], false, false))
        out.append(("reading", [.reading("Scan_0044.pdf")], false, false))
        out.append(("overview", [], true, true))
        if let r = renamed.last { out.append(("shortcuts", [r], true, false)); for n in ["ask-idle", "ask-thinking", "ask-move", "ask-answer"] { out.append((n, renamed.count > 1 ? Array(renamed) : [r], true, false)) } }
        if let d = m.actions.last(where: { $0.kind == .duplicate && $0.pending }) { out.append(("ask-trash", [.duplicate(d)], true, false)) }
        if renamed.count > 1 { out.append(("stack", Array(renamed), true, false)); out.append(("fan", Array(renamed), true, false)) }
        return out
    }

    static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance, to path: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = appearance
        w.backgroundColor = .clear
        w.isOpaque = false
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// A strip of wallpaper and menu bar behind the island, for snapshots.
struct IslandBackdrop: View {
    var skin: Island.Skin
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: scheme == .dark ? [Color(nsColor: NSColor(hex: 0x2B3A36)), Color(nsColor: NSColor(hex: 0x1B2220))] : [Color(nsColor: NSColor(hex: 0xC9D8CF)), Color(nsColor: NSColor(hex: 0xE9E3D6))], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45)).frame(height: 32)
            VStack(spacing: 0) {
                if skin == .capsule { Spacer().frame(height: 38) }
                IslandBody()
                Spacer(minLength: 0)
            }
        }
    }
}
