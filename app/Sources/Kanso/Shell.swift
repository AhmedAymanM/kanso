import AppKit
import Carbon.HIToolbox
import KansoCore
import SwiftUI

/// Menu bar glyph + popover. The glyph is a tray: outline when paused, filled when active, arrows while sorting,
/// with an accent dot when notices were collected quietly.
@MainActor
final class StatusItem: NSObject, NSPopoverDelegate {
    static let shared = StatusItem()
    private var item: NSStatusItem?
    let popover = NSPopover()

    func install() {
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        i.button?.target = self
        i.button?.action = #selector(toggle)
        i.button?.setAccessibilityLabel("Kanso")
        item = i
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // No arrow: the popover hangs straight from the menu bar (private key, guarded; the arrow returns if it's ever removed).
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) { popover.setValue(true, forKey: "shouldHideAnchor") }
        let host = NSHostingController(rootView: QuickSettings().environmentObject(AppModel.shared))
        host.sizingOptions = .preferredContentSize   // the popover follows SwiftUI's size, so it never grows past the menu bar
        popover.contentViewController = host
        update()
    }

    func update() {
        let m = AppModel.shared
        item?.isVisible = m.settings.showMenuBarIcon
        let name = m.busy ? "arrow.triangle.2.circlepath" : (m.settings.autoSort ? "tray.full.fill" : "tray")
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "Kanso") else { return }
        let dot = m.collected > 0
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { r in
            base.draw(in: NSRect(x: 0, y: 0, width: 17, height: 15))
            if dot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12, y: 10, width: 6, height: 6)).fill()
            }
            return true
        }
        img.isTemplate = true
        item?.button?.image = img
    }

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    func show() {
        guard let b = item?.button else { return }
        AppModel.shared.refresh()
        AppModel.shared.collected = 0
        update()
        NSApp.activate(ignoringOtherApps: true)
        if let f = b.window?.frame, StatusItem.visible(f) {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        } else {
            // The glyph is hidden (a crowded menu bar pushes it under the notch or off screen):
            // open from a point just below the menu bar instead, never over it.
            guard let s = Island.activeScreen else { return }
            let top = s.visibleFrame.maxY
            let x = min(max((b.window?.frame.midX ?? s.frame.maxX - 220), s.frame.minX + 200), s.frame.maxX - 200)
            let a = anchorWindow ?? NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            a.backgroundColor = .clear; a.isOpaque = false; a.level = .statusBar; a.ignoresMouseEvents = true
            a.setFrame(NSRect(x: x - 1, y: top - 2, width: 2, height: 2), display: false)
            a.orderFrontRegardless()
            anchorWindow = a
            guard let anchor = a.contentView else { return }
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    private var anchorWindow: NSWindow?

    /// The glyph is on screen and not under the notch.
    static func visible(_ f: NSRect) -> Bool {
        guard let s = NSScreen.screens.first(where: { $0.frame.intersects(f) }), s.frame.contains(f) else { return false }
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            let notch = NSRect(x: s.frame.minX + l.width, y: s.frame.maxY - s.safeAreaInsets.top, width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
            if notch.intersects(f) { return false }
        }
        return true
    }

    func close() { popover.performClose(nil) }

    /// Where toasts appear: under the menu bar, near the glyph.
    var anchor: NSRect? { item?.button?.window?.frame }
}

@MainActor
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()
    private var main: NSWindow?
    private var review: NSWindow?
    private var onboarding: NSWindow?

    func showMain(_ page: Page? = nil) {
        let m = AppModel.shared
        if let page { m.page = page }
        StatusItem.shared.close()
        if main == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: AppWindow.size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Kanso"
            w.isReleasedWhenClosed = false
            // NSHostingController bridges the SwiftUI toolbar and title into the window (Liquid Glass toolbar on 26).
            let host = NSHostingController(rootView: AppWindow().environmentObject(m))
            host.sceneBridgingOptions = [.toolbars, .title]
            w.contentViewController = host
            w.setContentSize(AppWindow.size)
            w.contentMinSize = AppWindow.size
            w.toolbarStyle = .unified
            w.center()
            w.setFrameAutosaveName("KansoAppWindow")   // position and size; the page always opens fresh
            w.delegate = self
            main = w
        }
        activate(main!)
        // No control starts focused: the ring appears only once someone tabs (it otherwise lands on the first switch).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.main?.makeFirstResponder(nil) }
    }

    /// Settings live in the one App window now: ⌘, and the gear open its General page.
    func showSettings(_ page: Page = .general) { showMain(page) }

    enum ReviewTab { case renames, sort }

    func showReview(tab: ReviewTab) {
        StatusItem.shared.close()
        review?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Review"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 760, height: 480)
        w.contentView = NSHostingView(rootView: ReviewView(tab: tab).environmentObject(AppModel.shared))
        w.center()
        w.delegate = self
        review = w
        activate(w)
    }

    func closeReview() { review?.close() }

    func showOnboarding() {
        StatusItem.shared.close()
        if onboarding == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Welcome to Kanso"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView().environmentObject(AppModel.shared))
            w.center()
            w.delegate = self
            onboarding = w
        }
        activate(onboarding!)
    }

    func closeOnboarding() { onboarding?.close() }

    private func activate(_ w: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === onboarding { onboarding = nil }
        if w === review { review = nil }
        // Back to a pure menu bar app once no window is open.
        DispatchQueue.main.async {
            if ![self.main, self.review, self.onboarding].contains(where: { $0?.isVisible == true }) { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

/// Global shortcuts (work from any app): Carbon hot keys need no accessibility permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    /// Registers the island shortcut. A failure (another app or the system holds the combination) sets
    /// `AppModel.hotKeyConflict`, which General settings shows next to the shortcut.
    func register(_ s: Settings) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                Task { @MainActor in HotKeys.fire(id.id) }
                return noErr
            }, 1, &spec, nil, nil)
        }
        // One island shortcut (⌥⌘K) replaces the old undo / trash / menu chords (PRODUCT.md).
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4B4E534F), id: 0)  // 'KNSO'
        let status = RegisterEventHotKey(s.islandShortcut.keyCode, s.islandShortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Kanso: island shortcut \(s.islandShortcut.display) not registered (status \(status))")
            AppModel.shared.hotKeyConflict = true
            return
        }
        refs.append(ref)
        AppModel.shared.hotKeyConflict = false
    }

    static func fire(_ id: UInt32) {
        if OnboardingDemo.shared.active { withAnimation(Motion.spring()) { OnboardingDemo.shared.pressed = true }; return }
        Island.shared.toggleShortcut()
    }

    /// Carbon modifier flags + display string from an NSEvent (for "Change" in General).
    static func shortcut(from e: NSEvent) -> Shortcut? {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !f.intersection([.command, .control, .option]).isEmpty else { return nil }
        var mods: UInt32 = 0
        var disp = ""
        if f.contains(.control) { mods |= UInt32(controlKey); disp += "⌃" }
        if f.contains(.option) { mods |= UInt32(optionKey); disp += "⌥" }
        if f.contains(.shift) { mods |= UInt32(shiftKey); disp += "⇧" }
        if f.contains(.command) { mods |= UInt32(cmdKey); disp += "⌘" }
        let key: String
        switch Int(e.keyCode) {
        case kVK_Delete: key = "⌫"
        case kVK_Return: key = "↩"
        case kVK_Space: key = "Space"
        case kVK_Escape: return nil
        default: key = (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
        return Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods, display: disp + key)
    }
}

/// Finder right-click: "Don't Sort with Kanso" / "Allow Kanso to Sort" toggle the keep tag.
final class Services: NSObject {
    @objc func skipFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { setKeep(true, pboard) }
    @objc func allowFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { setKeep(false, pboard) }

    private func setKeep(_ keep: Bool, _ pboard: NSPasteboard) {
        let tag = Store().settings.keepTag
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls { keep ? Tags.add(url, [tag]) : Tags.remove(url, [tag]) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = Services()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let m = AppModel.shared
            m.applyAppearance()
            StatusItem.shared.install()
            HotKeys.shared.register(m.settings)
            m.startWatching()
            m.startSmartInstaller()
            Island.shared.relayout()
            NSApp.mainMenu = mainMenu()
            if ProcessInfo.processInfo.environment["KANSO_BACKDROP"] != nil { Self.backdrop() }
            if let n = ProcessInfo.processInfo.environment["KANSO_NOTICE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    switch n {
                    case "reading": Island.shared.show(.reading("Scan_0044.pdf"))
                    case "sortingoff": Island.shared.show(.sortingOff(Date().addingTimeInterval(-90000)))
                    case "offer": Island.shared.show(.offer(.install(Snapshot.demoOffer(.none))))
                    case "duplicate": if let a = m.actions.last(where: { $0.kind == .duplicate && $0.pending }) { Island.shared.show(.duplicate(a)) }
                    default: if let r = m.actions.last(where: { $0.kind == .renamed }) { Island.shared.show(.renamed(r)) }
                    }
                }
            }
            if !m.settings.onboarded { Windows.shared.showOnboarding() }
            else if ProcessInfo.processInfo.arguments.contains("--show") {
                let args = ProcessInfo.processInfo.arguments
                let page = args.firstIndex(of: "--page").flatMap { i in args.indices.contains(i + 1) ? Page.allCases.first { $0.rawValue.lowercased().filter(\.isLetter).hasPrefix(args[i + 1].lowercased().filter(\.isLetter)) } : nil }   // letters only, so "smart-installer" finds Smart Installer
                Windows.shared.showMain(page)
            }
            if let k = ProcessInfo.processInfo.environment["KANSO_ACTIVITY"] {   // open Activity on one entry (a rule or action kind), for README shots
                m.page = .activity
                m.selectedActivity = m.actions.last { $0.kind.rawValue == k && ($0.pending || k != "duplicate") }?.id.uuidString
            }
            if ProcessInfo.processInfo.arguments.contains("--popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { StatusItem.shared.show() } }
            // KANSO_CAPTURE=file.png[:height] grabs the top of the screen (our own windows, glass included) after 3 s and quits; for README shots.
            if let spec = ProcessInfo.processInfo.environment["KANSO_CAPTURE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["KANSO_DELAY"] ?? "") ?? 3)) { Self.capture(spec); NSApp.terminate(nil) }
            }
            if ProcessInfo.processInfo.arguments.contains("--island") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Island.shared.toggleShortcut() } }
        }
    }

    /// KANSO_BACKDROP: an opaque wallpaper-like window behind ours, so README shots never include the desktop.
    static func backdrop() {
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        if ProcessInfo.processInfo.environment["KANSO_BACKDROP"] == "island" { w.level = .mainMenu }   // also hides the menu bar; the island sits above (statusBar)
        w.contentView = NSHostingView(rootView: LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xC9D8CF)), Color(nsColor: NSColor(hex: 0xE9E3D6))], startPoint: .top, endPoint: .bottom))
        w.orderFrontRegardless()
        backdropWindow = w
    }
    nonisolated(unsafe) static var backdropWindow: NSWindow?

    static func capture(_ spec: String) {
        let parts = spec.split(separator: ":").map(String.init)
        guard let screen = NSScreen.main else { return }
        let h = parts.count > 1 ? Double(parts[1]) ?? 400 : 400
        let rect = CGRect(x: 0, y: 0, width: screen.frame.width, height: h)
        guard let img = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: parts[0]))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { Windows.shared.showMain() }
        return true
    }

    /// Standard Edit menu so ⌘C/⌘V/⌘Z work in text fields, plus ⌘, for the main window.
    /// The menu bar while the App window is in front: App, File, Edit, View (pages on ⌘1–⌘8), Window, Help.
    func mainMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods; i.tag = tag; i.target = target ?? self
            return i
        }
        func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let m = NSMenuItem(); m.submenu = NSMenu(title: title); items.forEach { m.submenu?.addItem($0) }; menu.addItem(m); return m
        }
        sub("Kanso", [item("About Kanso", #selector(showAbout)), item("Check for Updates…", #selector(checkForUpdates)), .separator(),
                      item("Settings…", #selector(showSettings), ","), .separator(),
                      item("Hide Kanso", #selector(NSApplication.hide(_:)), "h", target: NSApp),
                      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp),
                      .separator(), item("Quit Kanso", #selector(NSApplication.terminate(_:)), "q", target: NSApp)])
        sub("File", [item("Sort Now", #selector(sortNow)), item("Show the Island", #selector(showIsland)), .separator(),
                     item("Close Window", #selector(NSWindow.performClose(_:)), "w", target: nil)])
        let edit = [("Undo", "undo:", "z", NSEvent.ModifierFlags.command), ("Redo", "redo:", "z", [.command, .shift]), ("Cut", "cut:", "x", .command),
                    ("Copy", "copy:", "c", .command), ("Paste", "paste:", "v", .command), ("Select All", "selectAll:", "a", .command)]
            .map { item($0.0, Selector($0.1), $0.2, $0.3, target: nil) }
        sub("Edit", edit + [.separator(), item("Find…", #selector(find), "f")])
        let pages: [Page] = Page.groups.flatMap { $0 }.filter { $0 != .general && $0 != .privacy }
        sub("View", pages.prefix(9).enumerated().map { i, p in item(p.title, #selector(showPage(_:)), i < 8 ? String(i + 1) : "", tag: Page.allCases.firstIndex(of: p) ?? 0) })
        let win = sub("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil), item("Zoom", #selector(NSWindow.performZoom(_:)), target: nil),
                                 .separator(), item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: NSApp)])
        NSApp.windowsMenu = win.submenu
        let help = sub("Help", [item("Kanso Help", #selector(openHelp)), item("Report a Problem…", #selector(reportProblem))])
        NSApp.helpMenu = help.submenu
        return menu
    }

    @objc func checkForUpdates() {
        MainActor.assumeIsolated {
            Task { @MainActor in
                await UpdateChecker.shared.check()
                switch UpdateChecker.shared.state {
                case .available(let v, _): Island.shared.show(.info(icon: "arrow.down.circle", text: "Kanso \(v) is available"))
                case .upToDate: Island.shared.show(.info(icon: "checkmark.circle", text: "Kanso is up to date"))
                case .failed(let msg): Island.shared.show(.info(icon: "exclamationmark.triangle", text: msg))
                default: break
                }
            }
        }
    }
    @objc func sortNow() { MainActor.assumeIsolated { AppModel.shared.sortNow(trigger: "menu") } }
    @objc func showIsland() { MainActor.assumeIsolated { Island.shared.toggleShortcut() } }
    @objc func find() { MainActor.assumeIsolated { Windows.shared.showMain(.activity); AppModel.shared.focusSearch = true } }
    @objc func showPage(_ sender: NSMenuItem) { MainActor.assumeIsolated { Windows.shared.showMain(Page.allCases[sender.tag]) } }
    @objc func openHelp() { MainActor.assumeIsolated { NSWorkspace.shared.open(Links.repo) } }
    @objc func reportProblem() { MainActor.assumeIsolated { NSWorkspace.shared.open(Links.repo.appendingPathComponent("issues/new")) } }
    @objc func showAbout() { MainActor.assumeIsolated { Windows.shared.showSettings(.privacy) } }
    @objc func showSettings() { MainActor.assumeIsolated { Windows.shared.showSettings() } }
}
