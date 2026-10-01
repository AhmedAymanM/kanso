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
            let s = Island.activeScreen
            let top = s.visibleFrame.maxY
            let x = min(max((b.window?.frame.midX ?? s.frame.maxX - 220), s.frame.minX + 200), s.frame.maxX - 200)
            let a = anchorWindow ?? NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            a.backgroundColor = .clear; a.isOpaque = false; a.level = .statusBar; a.ignoresMouseEvents = true
            a.setFrame(NSRect(x: x - 1, y: top - 2, width: 2, height: 2), display: false)
            a.orderFrontRegardless()
            anchorWindow = a
            popover.show(relativeTo: a.contentView!.bounds, of: a.contentView!, preferredEdge: .minY)
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
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Kanso"
            w.isReleasedWhenClosed = false
            // NSHostingController bridges the SwiftUI toolbar and title into the window (Liquid Glass toolbar on 26).
            let host = NSHostingController(rootView: AppWindow().environmentObject(m))
            host.sceneBridgingOptions = [.toolbars, .title]
            w.contentViewController = host
            w.setContentSize(AppWindow.size)
            w.toolbarStyle = .unified
            w.center()
            w.setFrameAutosaveName("KansoAppWindow")   // position only; the size is fixed
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
        if RegisterEventHotKey(s.islandShortcut.keyCode, s.islandShortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
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
            m.startSmartEject()
            Island.shared.relayout()
            NSApp.mainMenu = mainMenu()
            if !m.settings.onboarded { Windows.shared.showOnboarding() }
            else if ProcessInfo.processInfo.arguments.contains("--show") {
                let args = ProcessInfo.processInfo.arguments
                let page = args.firstIndex(of: "--page").flatMap { i in args.indices.contains(i + 1) ? Page.allCases.first { $0.rawValue.lowercased().hasPrefix(args[i + 1].lowercased()) } : nil }
                Windows.shared.showMain(page)
            }
            if ProcessInfo.processInfo.arguments.contains("--popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { StatusItem.shared.show() } }
            if ProcessInfo.processInfo.arguments.contains("--island") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Island.shared.toggleShortcut() } }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { Windows.shared.showMain() }
        return true
    }

    /// Standard Edit menu so ⌘C/⌘V/⌘Z work in text fields, plus ⌘, for the main window.
    func mainMenu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenuItem(); app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "About Kanso", action: #selector(showAbout), keyEquivalent: "").target = self
        app.submenu?.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.submenu?.addItem(.separator())
        app.submenu?.addItem(withTitle: "Quit Kanso", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(app)
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "Edit")
        for (t, s, k) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: t, action: Selector(s), keyEquivalent: k)
        }
        menu.addItem(edit)
        let win = NSMenuItem(); win.submenu = NSMenu(title: "Window")
        win.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(win)
        return menu
    }

    @objc func showAbout() { MainActor.assumeIsolated { Windows.shared.showSettings(.privacy) } }
    @objc func showSettings() { MainActor.assumeIsolated { Windows.shared.showSettings() } }
}
