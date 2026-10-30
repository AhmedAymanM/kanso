import AppKit
import KansoCore
import SwiftUI
import UniformTypeIdentifiers

/// The Tray's state for the island (v2 beta, files only; docs/design/proposals/tray.md).
/// Holding is not sorting: nothing here moves a file until Organize, and nothing runs unless `settings.trayEnabled`.
@MainActor
final class TrayModel: ObservableObject {
    static let shared = TrayModel()

    enum Phase: Equatable {
        case list
        case planning(Int, Int)     // "Planning 3 of 4"
        case review                 // where each file would go; nothing has moved
        case moving
    }

    @Published var entries: [TrayEntry] = []
    @Published var phase = Phase.list
    var focusedButton: (label: String, action: () -> Void)?   // the footer button that has keyboard focus (see TrayButton)
    @Published var plan: TrayPlan?
    @Published var overrides: [UUID: String] = [:]   // "Change a shelf…" choices
    @Published var selection = 0
    @Published var note: String?                      // a quiet line: "Added 3 to the Tray"
    @Published var error: String?                     // a failure: what stayed and why
    @Published var over = false                       // a file drag is over the island
    @Published var undoStack = TrayUndoStack()        // ⌘Z undoes the most recent forget or move, for this session
    @Published var changing: UUID?                    // the row whose shelf is being picked
    @Published var planSelection = 0                  // the preview row ← → change the shelf of

    private var planTask: Task<Void, Never>?
    private var planGeneration = 0
    private var planRunning = false                   // a plan is still computing (even a cancelled one): never two at once
    private var refreshGeneration = 0
    private var noteTask: Task<Void, Never>?
    private(set) var dropped = false                  // a drop happened during the current drag

    var engine: Engine { AppModel.shared.engine }
    var count: Int { entries.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var undoLabel: String { undoStack.label ?? "Undo" }
    var lastRun: String? { undoStack.topRun }
    var planning: Bool { if case .planning = phase { return true }; return false }

    // MARK: Reading

    /// Bookmarks, tags and file checks run off the main thread; the newest result wins.
    func refresh(retryMissing: Bool = false, then: (() -> Void)? = nil) {
        refreshGeneration += 1
        let gen = refreshGeneration
        let engine = self.engine
        Task { [weak self] in
            let found = await Task.detached { engine.trayEntries(retryMissing: retryMissing) }.value
            guard let self, gen == self.refreshGeneration else { return }
            self.entries = found
            self.selection = min(self.selection, max(found.count - 1, 0))
            then?()
        }
    }

    /// Only rows that exist show the count on the lip.
    var badge: Int { engine.tray.count }

    // MARK: Adding

    /// Files from a drop, a paste or the Finder service. Returns what happened, already spoken and shown.
    @discardableResult
    func add(_ urls: [URL], refused extra: [String] = []) -> TrayAdd {
        var r = engine.tray.add(urls)
        r.refused += extra
        dropped = true
        refresh()
        var parts: [String] = []
        if r.added > 0 { parts.append("Added \(r.added) to the Tray") }
        if r.already > 0 { parts.append(r.added == 0 && r.already == 1 ? "Already in the Tray" : "\(r.already) already in the Tray") }
        if r.overflow > 0 { parts.append("\(r.overflow) more were not added (the Tray holds \(TrayStore.cap))") }
        if let first = r.refused.first { parts.append(first + (r.refused.count > 1 ? " (\(r.refused.count) refused)" : "")) }
        if !parts.isEmpty {
            let text = parts.joined(separator: ". ")
            if r.refused.isEmpty && r.overflow == 0 { say(text) } else { fail(text) }
        }
        return r
    }

    /// Drop providers: only real file URLs count. A file promise (Mail attachment, image from a browser) has no file on
    /// this Mac yet and is refused.
    func add(providers: [NSItemProvider]) {
        dropped = true
        // A real Finder drag can reach SwiftUI as providers that list only the content type (com.adobe.pdf), with no
        // public.file-url, so they would all be refused. The drag pasteboard still carries the file URLs: use it when it does.
        let dragged = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !dragged.isEmpty {
            add(dragged)
            Island.shared.dropFinished()
            return
        }
        var urls: [URL] = []
        var refused: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    lock.lock(); if let url, url.isFileURL { urls.append(url) } else { refused.append("That item isn't a file on this Mac yet. Save it first.") }; lock.unlock()
                    group.leave()
                }
            } else {
                let link = p.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                lock.lock(); refused.append(link ? "The Tray holds files for now." : "That item isn't a file on this Mac yet. Save it first."); lock.unlock()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                self.add(urls, refused: refused)
                Island.shared.dropFinished()
            }
        }
    }

    func addFromPasteboard() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty { fail("Copy files in Finder first (⌘C), then paste here."); return }
        add(urls)
    }

    func beginDrag() { dropped = false }

    // MARK: Forgetting (never touches a file)

    func forget(_ id: UUID) {
        let name = entries.first { $0.id == id }?.name ?? "it"
        let gone = engine.tray.remove([id])
        guard !gone.isEmpty else { return }
        undoStack.push(.forget(gone))
        entries.removeAll { $0.id == id }
        selection = min(selection, max(entries.count - 1, 0))
        refresh()
        plan = nil; phase = .list
        say("Removed \(name) from the Tray. The file is still where it was.")
    }

    func forgetSelected() { if entries.indices.contains(selection) { forget(entries[selection].id) } }

    func clear() {
        let all = engine.tray.items
        guard !all.isEmpty else { return }
        engine.tray.clear()
        undoStack.push(.forget(all))
        entries = []; selection = 0
        refresh()
        plan = nil; phase = .list
        say("Cleared \(all.count) from the Tray. The files are untouched.")
    }

    /// ⌘Z: the single most recent action, a forget or a move.
    func undo() {
        guard let entry = undoStack.pop() else { return }
        switch entry {
        case .forget(let back):
            engine.tray.restore(back)
            refresh()
            say("Put \(back.count == 1 ? "it" : "\(back.count) rows") back in the Tray.")
        case .move(let run):
            AppModel.shared.undoRun(run)
            error = nil
            say("Put the files back.")
        }
    }

    func reorder(by delta: Int) {
        guard entries.indices.contains(selection) else { return }
        let id = entries[selection].id
        engine.tray.move(id, by: delta)
        let j = min(max(selection + delta, 0), entries.count - 1)
        entries.insert(entries.remove(at: selection), at: j)
        selection = j
        refresh()
    }

    func step(_ d: Int) {
        guard !entries.isEmpty else { return }
        selection = min(max(selection + d, 0), entries.count - 1)
    }

    // MARK: Organize

    /// Builds the plan (nothing moves). The preview shows the first 5 times, then only for a new shelf or more than 10 files.
    func organize() {
        guard phase == .list, !planRunning, !entries.isEmpty else { return }
        error = nil; note = nil
        let engine = self.engine
        phase = .planning(0, entries.count)
        planGeneration += 1
        planRunning = true
        let gen = planGeneration
        let work = Task.detached { await engine.trayPlan(progress: { i, n in Task { @MainActor in
            let t = TrayModel.shared
            if gen == t.planGeneration, case .planning = t.phase { t.phase = .planning(i, n) } } }) }
        planTask = Task { [weak self] in
            let plan = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self else { return }
            self.planRunning = false
            if gen == self.planGeneration { self.planTask = nil }
            guard gen == self.planGeneration, !Task.isCancelled, case .planning = self.phase else { return }
            self.planSelection = 0
            self.plan = plan
            if plan.movable == 0 {
                self.phase = .list
                self.fail(plan.rows.first?.stays ?? "Nothing in the Tray can move.")
                return
            }
            let shown = AppModel.shared.settings.trayPlansShown
            if shown < 5 || plan.newShelves > 0 || plan.movable > 10 {
                AppModel.shared.set(\.trayPlansShown, shown + 1)
                withAnimation(Motion.spring()) { self.phase = .review }
                Island.shared.announceTray("Plan ready. \(plan.movable) \(plan.movable == 1 ? "file" : "files") would move.")
            } else {
                self.move()
            }
        }
    }

    /// Moves the planned files as one journaled run (one Undo).
    func move() {
        guard let plan, phase == .review || isPlanning else { return }
        phase = .moving
        let overrides = self.overrides
        let engine = self.engine
        Task { [weak self] in
            let res = await Task.detached { engine.trayOrganize(plan, shelves: overrides) }.value
            guard let self else { return }
            AppModel.shared.refresh()
            self.finish(res, total: plan.movable)
        }
    }

    private var isPlanning: Bool { planning }

    private func finish(_ res: TrayResult, total: Int) {
        plan = nil; overrides = [:]; phase = .list
        refresh()
        if let run = res.run { undoStack.push(.move(run)) }
        if res.moved.isEmpty {
            fail("Nothing moved. \(res.stayed.first.map { "\($0.name): \($0.reason)" } ?? "")")
            return
        }
        let n = res.moved.count, s = res.shelves
        let text = "Moved \(n) to \(s) \(s == 1 ? "shelf" : "shelves")"
        if res.stayed.isEmpty {
            Island.shared.finishTray(text: text, run: res.run, single: n == 1 ? res.moved.first?.id : nil)
        } else {
            // Partial: stay on the Tray page, with the reason and an Undo for what did move.
            fail("Moved \(n) of \(total). \(res.stayed.count) stayed in the Tray: \(res.stayed[0].name). \(res.stayed[0].reason)")
        }
    }

    /// esc: leaves the preview or cancels planning first. true when it handled the key.
    func escape() -> Bool {
        switch phase {
        case .review: plan = nil; overrides = [:]; changing = nil; withAnimation(Motion.spring()) { phase = .list }; return true
        case .planning: planTask?.cancel(); planTask = nil; planGeneration += 1; plan = nil; phase = .list; say("Nothing moved."); return true
        case .moving: return true
        case .list: if error != nil || note != nil { error = nil; note = nil }; return false
        }
    }

    /// "Change a shelf…": the shelf choices are the existing types (never Keys, Duplicates or a Kanso folder).
    var shelfChoices: [String] {
        AppModel.shared.settings.types.map(\.name).filter { Engine.automaticShelfAllowed($0) }
    }

    func choose(_ shelf: String, for id: UUID) {
        overrides[id] = shelf
        changing = nil
    }

    func planStep(_ d: Int) {
        let n = plan?.rows.count ?? 0
        guard n > 0 else { return }
        planSelection = min(max(planSelection + d, 0), n - 1)
    }

    /// ← → on the selected preview row: the next or previous shelf (the keyboard way to "Change a shelf…").
    func cycleShelf(by d: Int) {
        guard let rows = plan?.rows, rows.indices.contains(planSelection), rows[planSelection].moves, rows[planSelection].planned != nil else { return }
        let row = rows[planSelection]
        guard let next = TrayKey.cycled(shelf(for: row), in: shelfChoices, by: d) else { return }
        choose(next, for: row.id)
        Island.shared.announceTray("\(row.name) goes to \(next)")
    }

    func shelf(for row: TrayRow) -> String? { overrides[row.id] ?? row.shelf }

    // MARK: Lines

    private func say(_ text: String) {
        error = nil
        note = text
        Island.shared.announceTray(text)
        noteTask?.cancel()
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }   // VoiceOver users get the line until they act
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.note = nil }
        }
    }

    private func fail(_ text: String) {
        note = nil
        error = text
        Island.shared.announceTray(text, high: true)
    }

    /// For snapshots: the model in a given state without touching the engine.
    func demo(entries: [TrayEntry], phase: Phase = .list, plan: TrayPlan? = nil, note: String? = nil, error: String? = nil, over: Bool = false, selection: Int = 0) {
        self.entries = entries; self.phase = phase; self.plan = plan; self.note = note; self.error = error; self.over = over; self.selection = selection
        overrides = [:]; changing = nil
    }
}
