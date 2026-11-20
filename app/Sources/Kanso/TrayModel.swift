import AppKit
import KansoCore
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// The Tray's state on the island (final-direction.md "The Tray (v1)"). It never shows "Added" or "Removed" notices:
/// the tiles are the feedback (owner, 2026-11-20).
@MainActor
final class TrayModel: ObservableObject {
    static let shared = TrayModel()

    struct Entry: Identifiable, Equatable {
        var item: TrayItem
        var url: URL?             // files: where it is now; nil when missing
        var id: UUID { item.id }
        var missing: Bool { item.kind == .file && url == nil }
    }

    /// A browser image or Mail attachment still being saved: a tile with a progress ring.
    struct Saving: Identifiable, Equatable { let id = UUID(); var name: String }

    let store: TrayStore
    @Published private(set) var entries: [Entry] = []
    @Published var selection = TraySelection()
    @Published var saving: [Saving] = []
    @Published var previews: [UUID: (title: String?, image: NSImage?)] = [:]
    @Published var over = false               // a compatible drag is over the island
    @Published var message: String?           // a short inline line ("Couldn't save that image")
    private var fetching = Set<UUID>()

    init(store: TrayStore = TrayStore(dir: AppModel.shared.store.dir)) {
        self.store = store
        refresh()
    }

    static let columns = 4
    var count: Int { entries.count }
    var selected: [Entry] { selection.selected.sorted().compactMap { entries.indices.contains($0) ? entries[$0] : nil } }
    /// What Share, drag and remove act on: the selection, else everything.
    var targets: [Entry] { selected.isEmpty ? entries : selected }

    func refresh() {
        entries = store.items.map { Entry(item: $0, url: $0.kind == .file ? store.resolve($0) : nil) }
        selection.clamp(entries.count)
        loadPreviews()
    }

    // MARK: Adding

    /// Reads a drop or a paste: file promises are saved as temporary copies; files by reference; web links; text.
    func add(from pb: NSPasteboard) {
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !receivers.isEmpty,
           !pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            receivers.forEach(save)
            return
        }
        if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            note(store.add(files: files))
        } else if let links = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !links.isEmpty {
            note(store.add(links: links))
        } else if let text = pb.string(forType: .string) {
            if let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil { note(store.add(links: [u])) }
            else { note(store.add(text: text)) }
        }
        refresh()
    }

    func add(files: [URL]) { note(store.add(files: files)); refresh() }

    /// One file promise: saved into its own folder in Kanso's Tray folder, then added as a temporary copy.
    private func save(_ receiver: NSFilePromiseReceiver) {
        let s = Saving(name: receiver.fileNames.first ?? "Image")
        saving.append(s)
        guard let folder = try? store.promiseFolder() else { failedSave(s); return }
        receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
            MainActor.assumeIsolated {
                if error == nil, FileManager.default.fileExists(atPath: url.path) {
                    self.saving.removeAll { $0.id == s.id }
                    self.store.adopt(saved: url)
                    self.refresh()
                } else {
                    try? FileManager.default.removeItem(at: folder)
                    self.failedSave(s)
                }
            }
        }
    }

    private func failedSave(_ s: Saving) {
        saving.removeAll { $0.id == s.id }
        say("Couldn't save that image")
    }

    /// Refusals are worth a line; successful adds are not (the tile appears).
    private func note(_ r: TrayAdd) { if r.added.isEmpty, let why = r.refused.first { say(why) } }

    func say(_ text: String) {
        if Island.shared.tray { message = text; Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if message == text { message = nil } } }
        else { Island.shared.show(.info(icon: "exclamationmark.triangle", text: text)) }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Removing

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        store.remove(ids)
        selection.clear()
        refresh()
    }

    func removeSelected() { remove(Set(selected.map(\.id))) }
    func clear() { remove(Set(entries.map(\.id))) }

    /// ⌘Z: the last removal (or Clear) comes back.
    func undo() { if !store.restoreLast().isEmpty { refresh() } }

    /// The island closed: ⌘Z can't reach the removed items any more, so their temporary copies go.
    func closeUndo() { store.closeUndo() }

    // MARK: Taking things out

    /// What goes on a pasteboard or into the share sheet for one entry.
    func object(_ e: Entry) -> Any? {
        switch e.item.kind {
        case .file: return e.url
        case .link: return URL(string: e.item.path)
        case .snippet: return e.item.text
        }
    }

    func copySelection() {
        let objs = targets.compactMap(object).compactMap { $0 as? NSPasteboardWriting }
        guard !objs.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(objs)
    }

    func openSelection() {
        for e in selected {
            switch e.item.kind {
            case .file: if let u = e.url { NSWorkspace.shared.open(u) }
            case .link: if let u = URL(string: e.item.path) { NSWorkspace.shared.open(u) }
            case .snippet: break
            }
        }
    }

    /// The system share sheet for the selection, or everything.
    func share(from view: NSView) {
        let items = targets.compactMap(object)
        guard !items.isEmpty else { return }
        NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    var shareLabel: String { selected.isEmpty ? "Share all" : "Share \(selected.count)" }

    // MARK: Quick Look (Space), like Finder

    func quickLook() {
        let urls = targets.compactMap { e -> URL? in e.item.kind == .file ? e.url : nil }
        TrayQuickLook.shared.show(urls)
    }

    // MARK: Link previews

    private func loadPreviews() {
        guard AppModel.shared.settings.trayLinkPreviews, !Motion.snapshot else { return }
        for e in entries where e.item.kind == .link && previews[e.id] == nil && !fetching.contains(e.id) {
            guard let u = URL(string: e.item.path), u.scheme == "https" else { continue }   // http stays a plain card
            fetching.insert(e.id)
            let id = e.id
            Task.detached(priority: .utility) {
                let result = await SafeFetcher.shared.preview(u)
                await MainActor.run {
                    self.fetching.remove(id)
                    if let (p, data) = result { self.previews[id] = (p.title, data.flatMap(NSImage.init(data:))) }
                }
            }
        }
    }

    func wipe() { store.wipe(); previews = [:]; refresh() }

    // MARK: Keys on the Tray page

    /// Arrows, ⇧-arrows, ⌘A, Space, ⌫, ↩, ⌘C, ⌘V, ⌘Z. Returns false for keys the island handles (esc, ⌘/, ⌘,).
    func key(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command), shift = e.modifierFlags.contains(.shift)
        switch Int(e.keyCode) {
        case 123: selection.move(by: -1, count: count, extend: shift)
        case 124: selection.move(by: 1, count: count, extend: shift)
        case 126: selection.move(by: -TrayModel.columns, count: count, extend: shift)
        case 125: selection.move(by: TrayModel.columns, count: count, extend: shift)
        case 49 where !cmd: quickLook()
        case 51, 117: removeSelected()
        case 36, 76: openSelection()
        case 0 where cmd: selection.all(count)
        case 8 where cmd: copySelection()
        case 9 where cmd: add(from: .general)
        case 6 where cmd: undo()
        default: return false
        }
        return true
    }
}

/// Quick Look for the Tray's files, with arrows to page through, as in Finder.
@MainActor
final class TrayQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = TrayQuickLook()
    private var urls: [URL] = []
    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let p = QLPreviewPanel.shared() else { return }
        self.urls = urls
        p.dataSource = self
        p.reloadData()
        p.makeKeyAndOrderFront(nil)
    }
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { MainActor.assumeIsolated { urls.count } }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { MainActor.assumeIsolated { urls[index] as NSURL } }
}
