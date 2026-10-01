import AppKit
import Carbon.HIToolbox
import KansoCore
import SwiftUI

/// Something Kanso tells the user about. Plain sorts never become notices (PRODUCT.md).
enum Notice: Identifiable, Equatable {
    case renamed(Action)
    case duplicate(Action)
    case installer(Action)
    case renameReview(Int)
    case sortingOff(Date)
    case reading(String)
    case info(icon: String, text: String, undo: UUID? = nil)

    var id: String {
        switch self {
        case .renamed(let a), .duplicate(let a), .installer(let a): return a.id.uuidString
        case .renameReview: return "review"
        case .sortingOff: return "sorting-off"
        case .reading: return "reading"
        case .info(_, let t, _): return "info-" + t
        }
    }
    var tint: Tint {
        switch self {
        case .renamed, .renameReview: return .rename
        case .duplicate: return .duplicate
        case .installer, .sortingOff: return .accent
        case .reading: return .where
        case .info: return .neutral
        }
    }
    /// The icon's final shape; it morphs from a plain document into this (Linear's status control).
    var icon: String {
        switch self {
        case .renamed: return "pencil.line"
        case .duplicate: return "doc.on.doc"
        case .installer: return "externaldrive.badge.checkmark"
        case .renameReview: return "text.badge.checkmark"
        case .sortingOff: return "pause.circle"
        case .reading: return "doc.text.viewfinder"
        case .info(let i, _, _): return i
        }
    }
    var line: String {
        switch self {
        case .renamed(let a): return a.name
        case .duplicate(let a): return a.shelf == "Trash" ? "Copy of \(kept(a)) moved to Trash" : "Copy of \(kept(a)) held on Duplicates"
        case .installer(let a): return "\(a.details["installer"] ?? "The app") installer moved to Trash"
        case .reading(let n): return "Reading page 1 of \(n)…"
        case .renameReview(let n): return "\(n) files can be renamed"
        case .sortingOff: return "Sorting off since yesterday · Turn on"
        case .info(_, let t, _): return t
        }
    }
    /// What VoiceOver says.
    var spoken: String {
        switch self {
        case .renamed(let a): return "Renamed \(a.oldName ?? "") to \(a.name)."
        default: return line + "."
        }
    }
    var needsYou: Bool { if case .duplicate(let a) = self { return a.pending }; if case .renameReview = self { return true }; return false }
    var kindKey: String {
        switch self {
        case .renamed: return "renamed"
        case .duplicate: return "duplicate"
        case .installer: return "installer"
        default: return id
        }
    }
}

private func kept(_ a: Action) -> String { ((a.details["kept"] ?? a.name) as NSString).lastPathComponent }

/// One action on the expanded island, with its key.
struct IslandAction: Identifiable {
    var id: String { label }
    var label: String
    var key: String
    var icon = "arrow.uturn.backward"
    var shown = true          // false: reachable by its key or a glyph, but no button
    var run: () -> Void
}

/// Other apps that live in the notch. With Island: Automatic, Kanso moves below the notch while one runs, and yields to it.
enum NotchApps {
    static let names = ["NotchNook", "Alcove", "Droppy", "Boring Notch", "boringNotch", "Notchy", "DynamicLake", "Atoll", "Sapphire", "NotchBox", "Crest", "Brow", "OneNotch", "NotchSpace", "Seam", "MediaMate"]

    static func running() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            let n = app.localizedName ?? ""
            return names.contains(n) || (app.bundleIdentifier ?? "").lowercased().contains("notch")
        }
    }

    /// True when another notch app has an expanded window over `rect` (screen coordinates, bottom-left origin).
    static func covering(_ rect: NSRect) -> Bool {
        let pids = Set(running().map(\.processIdentifier))
        guard !pids.isEmpty, let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let cg = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        return list.contains { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return r.height > 40 && r.intersects(cg)   // an expanded panel, not the resting notch strip
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Kanso's one surface for things that happen while you're elsewhere (CONTEXT.md "Island").
@MainActor
final class Island: ObservableObject {
    static let shared = Island()

    enum Skin { case notch, capsule }

    @Published var notices: [Notice] = []
    @Published var index = 0           // which notice, when several counted up
    @Published var expanded = false
    @Published var overview = false
    @Published var selection = 0
    @Published var askText = ""
    @Published var askState = AskState.idle
    @Published var askFocus = false
    @Published var askReadyAt = Date.distantPast      // Return stays inert for 1 s after the field is emptied
    var askHistory: [String] = []
    var askHistoryIndex = 0
    var askTask: Task<Void, Never>?
    @Published var shortcuts = false   // the keyboard shortcuts list replaces the body
    @Published var fanned = false      // several renamed files: stack (false) or fanned out (true)
    @Published var skin = Skin.capsule
    @Published var notch = CGSize(width: 180, height: 32)
    @Published var hovering = false
    @Published var dismissAt = Date.distantFuture

    private var panel: IslandPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var dwell: Task<Void, Never>?
    private var timer: Timer?
    private var deferred = 0
    static let size = NSSize(width: 580, height: 560)

    var visible: Bool { !notices.isEmpty || overview }
    var current: Notice? { notices.indices.contains(index) ? notices[index] : notices.last }

    // MARK: Showing

    func show(_ n: Notice) {
        let m = AppModel.shared
        if m.settings.collectDuringFocus && Island.frontmostIsFullScreen() {
            m.collected += 1
            StatusItem.shared.update()
            return
        }
        announce(n.spoken + (m.settings.showShortcutHint ? " Press Option-Command-K to open." : ""))
        withAnimation(Motion.spring(0.42)) {
            if let i = notices.firstIndex(where: { $0.id == n.id }) { notices[i] = n } else { notices.append(n) }
        }
        if !expanded { index = notices.count - 1 }
        overview = false
        present()
    }

    /// ⌥⌘K: acts on the shown notice (opens it with its primary action selected), else opens the overview; again collapses.
    func toggleShortcut() {
        if expanded { hide(); return }
        if notices.isEmpty {
            relayout()
            panel?.alphaValue = 1
            panel?.orderFrontRegardless()
            withAnimation(Motion.spring(0.42)) { overview = true; expanded = true }
        }
        selection = 0
        present(expand: true, fast: true)
    }

    func openOverview() {
        notices = []
        selection = 0
        relayout()
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        withAnimation(Motion.spring(0.42)) { overview = true; expanded = true }   // grows out of the notch already open
        present(expand: true)
    }

    private func present(expand: Bool = false, fast: Bool = false) {
        relayout()
        if let covered = targetRect(), NotchApps.covering(covered), deferred < 60 {   // yield: wait until the other app collapses
            deferred += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.present(expand: expand, fast: fast) }
            return
        }
        deferred = 0
        guard let p = panel else { return }
        p.alphaValue = 1
        p.orderFrontRegardless()
        withAnimation(Motion.spring(fast ? 0.25 : 0.35)) { if expand { expanded = true } }
        if expand { p.makeKey(); installMonitors() }
        scheduleDismiss()
    }

    func expand() {
        guard visible, !expanded else { return }
        selection = 0
        withAnimation(Motion.spring()) { expanded = true }
        panel?.makeKey()
        installMonitors()
        dismissAt = .distantFuture
    }

    func collapse() {
        if shortcuts { withAnimation(Motion.spring()) { shortcuts = false }; return }
        if fanned { withAnimation(Motion.spring()) { fanned = false }; return }
        guard expanded else { hide(); return }
        withAnimation(Motion.spring()) { expanded = false }
        removeMonitors()
        if overview { hide() } else { scheduleDismiss() }
    }

    func hide() {
        removeMonitors()
        let wasNeeds = notices.contains(where: \.needsYou)
        dismissAt = .distantFuture
        // Shrinks back into the notch (the removal transition), then the empty panel leaves.
        withAnimation(Motion.spring(0.38)) {
            notices = []
            overview = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.reduced ? 0.25 : 0.55)) {
            guard !self.visible else { return }
            self.panel?.orderOut(nil)
            self.expanded = false
            self.shortcuts = false
            self.fanned = false
            self.index = 0
        }
        if wasNeeds && !overview {   // ignored needs-you notices wait in the overview; the menu bar gets a dot
            AppModel.shared.collected += 1
            StatusItem.shared.update()
        }
    }

    private func scheduleDismiss() {
        guard !expanded else { dismissAt = .distantFuture; return }
        dismissAt = Date().addingTimeInterval(notices.contains(where: \.needsYou) ? 8 : 5)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !self.expanded, !self.hovering, self.visible else { return }
                if Date() >= self.dismissAt { self.timer?.invalidate(); self.hide() }
            }
        }
    }

    // MARK: Hover and clicks

    func hover(_ on: Bool) {
        hovering = on
        dwell?.cancel()
        if on && !expanded {
            dwell = Task { @MainActor in   // a 300 ms dwell: a mouse passing through toward the menu bar does nothing
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled && self.hovering { self.expand() }
            }
        } else if !on {
            dismissAt = max(dismissAt, Date().addingTimeInterval(2))
        }
    }

    // MARK: Geometry

    static var activeScreen: NSScreen { NSScreen.main ?? NSScreen.screens.first! }

    static func notchSize(_ s: NSScreen) -> CGSize? {
        guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return nil }
        return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
    }

    func relayout() {
        let s = Island.activeScreen
        let mode = AppModel.shared.settings.islandMode
        let n = Island.notchSize(s)
        let wantsNotch = mode == .notch || (mode == .automatic && NotchApps.running().isEmpty)
        let newSkin: Skin = (n != nil && wantsNotch) ? .notch : .capsule
        if !visible || skin == newSkin { skin = newSkin }   // switch only between notices
        if let n { notch = n }
        if panel == nil { makePanel() }
        let size = Island.size
        let top = skin == .notch ? s.frame.maxY : s.visibleFrame.maxY - 6
        panel?.setFrame(NSRect(x: s.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Where the island will be, for the yield check.
    private func targetRect() -> NSRect? {
        guard let f = panel?.frame else { return nil }
        return NSRect(x: f.midX - 190, y: f.maxY - 60, width: 380, height: 60)
    }

    private func makePanel() {
        let p = IslandPanel(contentRect: NSRect(origin: .zero, size: Island.size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: IslandRoot().environmentObject(self).environmentObject(AppModel.shared))
        p.setAccessibilityLabel("Kanso")
        panel = p
    }

    // MARK: Keys (expanded only; no bare letters, PRODUCT.md key map)

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated { self.key(e) ? nil : e }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { self.collapse() }   // a click anywhere else collapses
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil; clickMonitor = nil
    }

    private func key(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let acts = actions()
        if askFocus && !cmd {   // typing: only Return, ↑ (recall) and Esc are ours
            switch Int(e.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: submitAsk(); return true
            case kVK_UpArrow: recallAsk(); return true
            case kVK_Escape: break
            default: return false
            }
        }
        if !askFocus, askAvailable, !cmd, e.modifierFlags.intersection([.control, .option]).isEmpty, Int(e.keyCode) == kVK_Tab || (e.charactersIgnoringModifiers?.first?.isLetter == true && !askState.isProposal) {
            askFocus = true
            if Int(e.keyCode) != kVK_Tab, let ch = e.characters { askText += ch }
            return true
        }
        switch Int(e.keyCode) {
        case kVK_Escape:
            if askFocus { askFocus = false; return true }     // Esc leaves the field without clearing it
            if askState.isProposal { cancelAsk(); return true }
            collapse(); return true
        case kVK_ANSI_Slash where cmd: withAnimation(Motion.spring()) { shortcuts.toggle() }; return true
        case kVK_ANSI_Comma where cmd: hide(); Windows.shared.showSettings(); return true
        case kVK_ANSI_C where cmd:
            if case .renamed(let a)? = current { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a.name, forType: .string); return true }
            return false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if askState.isProposal { confirmAsk(trash: false); return true }
            if stacked { withAnimation(Motion.spring()) { fanned = true }; return true }
            if acts.indices.contains(selection), acts[selection].key != "⌘⌫" { acts[selection].run() }   // Return never trashes
            return true
        case kVK_LeftArrow: step(-1); return true
        case kVK_RightArrow:
            if stacked { withAnimation(Motion.spring()) { fanned = true }; return true }
            step(1); return true
        case kVK_UpArrow: selection = max(0, selection - 1); return true
        case kVK_DownArrow: selection = min(max(acts.count - 1, 0), selection + 1); return true
        case kVK_Space: quickLook(); return true
        case kVK_ANSI_Z where cmd: run(key: "⌘Z", acts); return true
        case kVK_Delete where cmd:
            if case .trash = askState { confirmAsk(trash: true); return true }
            run(key: "⌘⌫", acts); return true
        case kVK_ANSI_R where cmd: run(key: "⌘R", acts); return true
        case kVK_ANSI_O where cmd: run(key: "⌘O", acts); return true
        default: return false   // letters are for the ask field (v1.1); plain ⌫ never trashes
        }
    }

    /// Several renamed files, not yet fanned out.
    var stacked: Bool { expanded && !overview && !shortcuts && !fanned && notices.count > 1 && notices.allSatisfy { if case .renamed = $0 { return true } else { return false } } }

    private func run(key: String, _ acts: [IslandAction]) { acts.first { $0.key == key }?.run() }

    private func step(_ d: Int) {
        guard notices.count > 1 else { return }
        index = (index + d + notices.count) % notices.count   // keyboard repeats don't animate
        selection = 0
    }

    func quickLook() {
        let path: String? = {
            switch current {
            case .renamed(let a)?, .duplicate(let a)?: return a.dst
            default: return nil
            }
        }()
        guard let path else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // MARK: Actions

    func actions() -> [IslandAction] {
        let m = AppModel.shared
        if overview {
            let needs = m.needs.prefix(3).map { n -> IslandAction in
                switch n {
                case .duplicate(let a): return IslandAction(label: "Move to Trash", key: "⌘⌫", icon: "trash") { m.trash(a.id) }
                case .renames: return IslandAction(label: "Review…", key: "↩") { self.hide(); Windows.shared.showReview(tab: .renames) }
                case .rule(let r): return IslandAction(label: "Create rule", key: "↩") { m.acceptSuggestion(r.id) }
                }
            }
            let recent = m.done.prefix(3).map { a in IslandAction(label: "Show \(a.name)", key: "↩") { m.reveal(a.dst) } }
            return Array(needs) + Array(recent)
        }
        guard let n = current else { return [] }
        let done: () -> Void = { self.remove(n) }
        switch n {
        case .renamed(let a):
            return [IslandAction(label: "Undo", key: "⌘Z") { m.undo([a.id]); done() },
                    IslandAction(label: "Show in Finder", key: "⌘R", icon: "folder.badge.magnifyingglass", shown: false) { m.reveal(a.dst) },
                    IslandAction(label: "Open", key: "⌘O", icon: "doc", shown: false) { NSWorkspace.shared.open(URL(fileURLWithPath: a.dst)) }]
        case .duplicate(let a) where a.pending:
            // Undo is primary; trashing is only ever ⌘⌫, never Return (key map: nothing destructive on a plain key).
            return [IslandAction(label: "Undo", key: "⌘Z") { m.undo([a.id]); done() },
                    IslandAction(label: "Move copy to Trash", key: "⌘⌫", icon: "trash") { m.trash(a.id); done() },
                    IslandAction(label: "Keep both", key: "", icon: "doc.on.doc") { m.keepBoth(a.id); done() }]
        case .duplicate(let a), .installer(let a):
            return [IslandAction(label: "Put Back", key: "⌘Z") { m.undo([a.id]); done() }]
        case .renameReview:
            return [IslandAction(label: "Review…", key: "↩", icon: "checklist") { self.hide(); Windows.shared.showReview(tab: .renames) },
                    IslandAction(label: "Not now", key: "esc", icon: "xmark") { done() }]
        case .reading: return []
        case .sortingOff:
            return [IslandAction(label: "Turn on Sorting", key: "↩", icon: "power") { m.setSorting(true); done() }]
        case .info(_, _, let undo):
            return undo.map { id in [IslandAction(label: "Undo", key: "⌘Z") { m.undo([id]); done() }] } ?? []
        }
    }

    /// Opens one item from the overview as a notice, with its details and actions.
    func focus(_ n: Notice) {
        overview = false
        notices = [n]
        index = 0
        selection = 0
    }

    func dismiss(id: String) {
        guard notices.contains(where: { $0.id == id }) else { return }
        notices.removeAll { $0.id == id }
        index = min(index, max(notices.count - 1, 0))
        if notices.isEmpty { hide() }
    }

    private func remove(_ n: Notice) {
        notices.removeAll { $0.id == n.id }
        index = min(index, max(notices.count - 1, 0))
        selection = 0
        if notices.isEmpty { hide() }
    }

    // MARK: Helpers

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Full-screen apps and Focus-like moments: notices collect quietly with the menu bar dot.
    static func frontmostIsFullScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screen = activeScreen.frame
        return list.contains { w in
            guard w[kCGWindowOwnerPID as String] as? pid_t == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (b["Width"] ?? 0) >= screen.width && (b["Height"] ?? 0) >= screen.height
        }
    }
}

// Views are in IslandViews.swift.

/// The notice icon: starts as a plain document and morphs into its final shape (Linear's status control).
/// With Reduce Motion it simply shows the final shape.
struct MorphIcon: View {
    var notice: Notice
    var size: CGFloat = 24
    @State private var final = Motion.reduced

    var body: some View {
        Image(systemName: final ? notice.icon : "doc")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(notice.tint.islandGlyph)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(notice.tint.islandFill))
            .task(id: notice.id) {
                guard !Motion.reduced else { final = true; return }
                final = false
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { final = true }
            }
            .accessibilityHidden(true)
    }
}

/// The rename's ASCII sweep: a band of scrambling glyphs travels left to right, and each character settles
/// into the new name as it passes (canvasui ascii-sweep, calm: sage-tinted glyphs, ~0.8 s, no tearing).
struct SweepText: View {
    var from: String
    var to: String
    var glyphColor: Color
    var final: String? = nil
    var duration = 0.8
    @State private var start = Date()
    private static let ramp = Array(".:-=+*#%@01")

    var body: some View {
        if Motion.reduced {
            Text(final ?? to)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { ctx in
                let t = min(1, ctx.date.timeIntervalSince(start) / duration)
                sweep(t)
            }
            .onAppear { start = Date() }
            .accessibilityLabel(to)
        }
    }

    func sweep(_ t: Double) -> Text {
        guard t < 1 else { return Text(final ?? to) }
        let a = Array(from), b = Array(to)
        let n = max(a.count, b.count)
        let band = 0.22
        let head = t * (1 + band)
        var out = Text("")
        for i in 0..<n {
            let x = Double(i) / Double(max(n - 1, 1))
            if x < head - band {
                out = out + Text(i < b.count ? String(b[i]) : "")
            } else if x < head {
                out = out + Text(String(SweepText.ramp[(i * 7 + Int(t * 60)) % SweepText.ramp.count])).foregroundColor(glyphColor)
            } else {
                out = out + Text(i < a.count ? String(a[i]) : "")
            }
        }
        return out
    }
}
