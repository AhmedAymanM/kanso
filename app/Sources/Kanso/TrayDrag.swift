import AppKit
import KansoCore

/// Drag detection for the Tray (docs/design/proposals/tray.md, "Drag detection, dwell and multi-monitor").
/// Global event monitors only observe; they run only while the Tray beta is on. The island grows only for a drag that
/// carries file URLs, and only after the pointer rests in a small zone at the top of the screen.
///
/// 1. Detect: a drag is compatible when the drag pasteboard changed since the mouse went down AND holds `public.file-url`.
///    Window drags, text, links and tab drags never qualify.
/// 2. Dwell: 250 ms inside a 160 x 44 pt zone at the top centre of the screen under the pointer. It closes only after the
///    pointer leaves the island and a 220 pt radius (hysteresis), so sweeping toward a status item does nothing.
/// 3. Multi-monitor: the screen under the pointer, not the main one. A full-screen app hides the menu bar: no grow there.
@MainActor
final class TrayDragMonitor {
    static let shared = TrayDragMonitor()

    private var monitors: [Any] = []
    private var downCount = 0
    private var live = false          // a compatible drag is in progress
    private var dwell: Task<Void, Never>?
    private var endTask: Task<Void, Never>?

    func sync(_ on: Bool) {
        if on, monitors.isEmpty {
            let mask: [NSEvent.EventTypeMask] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            for m in mask {
                if let token = NSEvent.addGlobalMonitorForEvents(matching: m, handler: { e in
                    let type = e.type
                    MainActor.assumeIsolated { TrayDragMonitor.shared.handle(type) }
                }) { monitors.append(token) }
            }
        } else if !on, !monitors.isEmpty {
            for t in monitors { NSEvent.removeMonitor(t) }
            monitors = []
            dwell?.cancel()
            live = false
        }
    }

    /// True when the drag pasteboard carries file URLs (a promise or plain text does not).
    static func hasFiles(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            downCount = NSPasteboard(name: .drag).changeCount
            live = false
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            ended()
        default: break
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) }
    }

    private func dragged() {
        let island = Island.shared
        let pb = NSPasteboard(name: .drag)
        if !live {
            guard pb.changeCount != downCount, TrayDragMonitor.hasFiles(pb) else { return }
            live = true
        }
        guard AppModel.shared.settings.trayEnabled, let screen = screenUnderPointer() else { return }
        let p = NSEvent.mouseLocation
        let top = screen.frame.maxY
        let zone = NSRect(x: screen.frame.midX - 80, y: top - 44, width: 160, height: 44)
        if island.openedByDrag || (island.expanded && island.tray) {
            // Open: stay while the pointer is over the island or within 220 pt of its centre.
            let c = CGPoint(x: screen.frame.midX, y: top - 20)
            let overIsland = NSRect(x: screen.frame.midX - 250, y: top - 460, width: 500, height: 460).contains(p)
            if !overIsland && hypot(p.x - c.x, p.y - c.y) > 220 {
                if island.openedByDrag { island.closeTrayForDrag() }
                TrayModel.shared.over = false
            } else {
                TrayModel.shared.over = true
            }
            return
        }
        if Island.frontmostIsFullScreen() { return }   // no menu bar to grow from
        if zone.contains(p) {
            guard dwell == nil else { return }
            dwell = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                defer { self.dwell = nil }
                guard !Task.isCancelled, self.live, zone.contains(NSEvent.mouseLocation) else { return }
                if island.expanded && island.tray { TrayModel.shared.beginDrag(); TrayModel.shared.over = true }
                else { island.openTrayForDrag(on: screen) }
            }
        } else {
            dwell?.cancel()
            dwell = nil
        }
    }

    /// The drag ended. A drop is handled by the island's drop target; if none happened the island shrinks again.
    private func ended() {
        guard live else { return }
        live = false
        dwell?.cancel()
        dwell = nil
        endTask?.cancel()
        endTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            Island.shared.closeTrayForDrag()
            TrayModel.shared.over = false
        }
    }
}
