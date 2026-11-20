import AppKit
import KansoCore

/// Drag detection for the Tray (final-direction.md "Adding"). Global mouse monitors only observe (no Accessibility
/// permission). A drag counts when the drag pasteboard changed since the mouse went down and holds a file URL, a file
/// promise, a web link or text. The island grows into a drop target after the pointer dwells 250 ms in a 160 × 44 pt
/// zone where the island sits (top or bottom, on the screen under the pointer) and shrinks once it leaves a 220 pt radius.
/// Full-screen apps: never.
@MainActor
final class TrayDragMonitor {
    static let shared = TrayDragMonitor()

    private var monitors: [Any] = []
    private var downCount = 0
    private var live = false
    private var dwell: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    private(set) var dragLabel = "Add to the Tray"

    func start() {
        guard monitors.isEmpty else { return }
        for m: NSEvent.EventTypeMask in [.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            if let t = NSEvent.addGlobalMonitorForEvents(matching: m, handler: { e in
                let type = e.type
                MainActor.assumeIsolated { TrayDragMonitor.shared.handle(type) }
            }) { monitors.append(t) }
        }
    }

    static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    /// What the drag carries, as the drop target says it ("Add 3 files to the Tray"), or nil when it doesn't qualify.
    static func describe(_ pb: NSPasteboard) -> String? {
        if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            return files.count == 1 ? "Add \(TrayStore.clean(files[0].lastPathComponent)) to the Tray" : "Add \(files.count) files to the Tray"
        }
        if pb.availableType(from: promiseTypes) != nil { return "Add this image to the Tray" }
        if let links = pb.readObjects(forClasses: [NSURL.self]) as? [URL], links.contains(where: { ["http", "https"].contains($0.scheme ?? "") }) {
            return links.count == 1 ? "Add a link to the Tray" : "Add \(links.count) links to the Tray"
        }
        if pb.string(forType: .string) != nil { return "Add this text to the Tray" }
        return nil
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown: downCount = NSPasteboard(name: .drag).changeCount; live = false
        case .leftMouseDragged: dragged()
        case .leftMouseUp: ended()
        default: break
        }
    }

    private func screenUnderPointer() -> NSScreen? { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } }

    /// The 160 × 44 pt zone where the island sits on `screen`.
    private func zone(_ s: NSScreen) -> NSRect {
        let island = Island.shared
        let bottom = island.skin == .capsule && AppModel.shared.settings.islandPosition == .bottom
        let y = bottom ? s.visibleFrame.minY + 8 : (island.skin == .notch ? s.frame.maxY - 44 : s.visibleFrame.maxY - 50)
        return NSRect(x: s.frame.midX - 80, y: y, width: 160, height: 44)
    }

    private func dragged() {
        let island = Island.shared
        let pb = NSPasteboard(name: .drag)
        if !live {
            guard pb.changeCount != downCount, let label = TrayDragMonitor.describe(pb) else { return }
            dragLabel = label
            live = true
        }
        guard let screen = screenUnderPointer() else { return }
        let p = NSEvent.mouseLocation
        let z = zone(screen)
        if island.dropTarget || (island.expanded && island.tray) {
            let c = CGPoint(x: z.midX, y: z.midY)
            TrayModel.shared.over = hypot(p.x - c.x, p.y - c.y) <= 220 || (island.expanded && island.tray)
            if island.dropTarget && hypot(p.x - c.x, p.y - c.y) > 220 { island.closeDropTarget() }
            return
        }
        if Island.frontmostIsFullScreen() { return }
        if z.contains(p) {
            guard dwell == nil else { return }
            dwell = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                defer { self.dwell = nil }
                guard !Task.isCancelled, self.live, z.contains(NSEvent.mouseLocation) else { return }
                island.openDropTarget(on: screen)
            }
        } else {
            dwell?.cancel(); dwell = nil
        }
    }

    /// The drag ended: a drop is handled by the island; without one the drop target shrinks.
    private func ended() {
        guard live else { return }
        live = false
        dwell?.cancel(); dwell = nil
        endTask?.cancel()
        endTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            TrayModel.shared.over = false
            Island.shared.closeDropTarget()
        }
    }
}

/// The island panel's content: the SwiftUI island, plus the drop destination for the Tray. Drops are taken only while
/// the Tray is showing (its page, or the drop target a drag opened).
final class IslandDropContainer: NSView {
    init(_ content: NSView) {
        super.init(frame: content.frame)
        content.autoresizingMask = [.width, .height]
        content.frame = bounds
        addSubview(content)
        registerForDraggedTypes([.fileURL, .URL, .string] + TrayDragMonitor.promiseTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var accepting: Bool { MainActor.assumeIsolated { Island.shared.dropTarget || (Island.shared.expanded && Island.shared.tray) } }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        guard accepting, TrayDragMonitor.describe(s.draggingPasteboard) != nil else { return [] }
        MainActor.assumeIsolated { TrayModel.shared.over = true }
        return .copy
    }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { accepting ? .copy : [] }
    override func draggingExited(_ s: NSDraggingInfo?) { MainActor.assumeIsolated { TrayModel.shared.over = false } }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let pb = s.draggingPasteboard
        return MainActor.assumeIsolated {
            TrayModel.shared.over = false
            TrayModel.shared.add(from: pb)
            Island.shared.dropFinished()
            return true
        }
    }
}
