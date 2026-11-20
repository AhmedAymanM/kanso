import AppKit
import CoreServices
import KansoCore
import ServiceManagement
import SwiftUI

/// Something that needs the user: pinned to the top of every list, one card at a time.
enum Need: Identifiable, Equatable {
    case duplicate(Action)
    case renames([RenameProposal], Date)
    case rule(RuleSuggestion)
    case shelf(ShelfSuggestion)

    var id: String {
        switch self {
        case .duplicate(let a): return a.id.uuidString
        case .renames: return "renames"
        case .rule(let r): return r.id.uuidString
        case .shelf(let s): return s.id
        }
    }
    var ts: Date {
        switch self {
        case .duplicate(let a): return a.ts
        case .renames(_, let d): return d
        case .rule(let r): return r.ts
        case .shelf(let s): return s.ts
        }
    }
    var tint: Tint {
        switch self {
        case .duplicate: return .duplicate
        case .renames: return .rename
        case .rule, .shelf: return .rule
        }
    }
    var label: String {
        switch self {
        case .duplicate: return "Duplicate"
        case .renames: return "Rename review"
        case .rule: return "Rule suggestion"
        case .shelf: return "Shelf suggestion"
        }
    }
    var icon: String {
        switch self {
        case .duplicate: return "doc.on.doc"
        case .renames: return "pencil.line"
        case .rule: return "wand.and.stars"
        case .shelf: return "square.stack.3d.up"
        }
    }
}

/// The pages of the one App window (design handoff 2026-09-30): history, the five features, then app settings.
enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", activity = "Activity"
    case sorting = "Sorting", renaming = "Renaming", duplicates = "Duplicates", tagging = "Tagging", smartInstaller = "Smart Installer"
    case general = "General", privacy = "Privacy & AI"
    var id: String { rawValue }
    var title: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .activity: return "list.bullet"
        case .sorting: return "square.3.layers.3d"
        case .renaming: return "pencil"
        case .duplicates: return "doc.on.doc"
        case .tagging: return "tag"
        case .smartInstaller: return "arrow.down.app"
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        }
    }
    /// Sidebar groups, separated by space.
    static let groups: [[Page]] = [[.overview, .activity], [.sorting, .renaming, .duplicates, .tagging, .smartInstaller], [.general, .privacy]]
}

/// How long Sorting stays off (PRODUCT.md: turning Sorting off asks for how long).
enum OffDuration: CaseIterable, Identifiable {
    case quarter, hour, tomorrow, untilOn
    var id: Self { self }
    var label: String {
        switch self {
        case .quarter: return "15 minutes"
        case .hour: return "1 hour"
        case .tomorrow: return "Until tomorrow"
        case .untilOn: return "Until I turn it on"
        }
    }
    func until(_ now: Date = Date()) -> Date? {
        switch self {
        case .quarter: return now.addingTimeInterval(15 * 60)
        case .hour: return now.addingTimeInterval(3600)
        case .tomorrow: return Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        case .untilOn: return nil
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store: Store
    let engine: Engine
    let ai = AppleIntelligence()

    @Published private(set) var settings: Settings {
        didSet { if oldValue.roots != settings.roots { refreshAccess() } }
    }
    /// Watched folders macOS won't let Kanso read (privacy blocks Desktop, Documents, Downloads until allowed). Drives the Sorting badge.
    @Published private(set) var inaccessibleRoots: [String] = []
    @Published private(set) var actions: [Action] = []
    @Published private(set) var pending = Pending()
    /// New shelves proposed for what piles up in Unsorted (found by counting, applied only on Accept).
    @Published private(set) var shelfSuggestions: [ShelfSuggestion] = []
    @Published var waiting: [Waiting] = []   // set by the sort run; snapshots set it too
    @Published private(set) var busy = false
    @Published private(set) var duplicatesBytes: Int64 = 0
    @Published var page: Page = .overview
    @Published var selectedActivity: String?
    @Published var preview: [Planned] = []     // Sort everything preview, shown in the review window
    @Published var collected = 0               // notices waiting while quiet (Focus / full-screen)
    @Published var hotKeyConflict = false      // set by HotKeys: the island shortcut could not be registered
    @Published private(set) var loginItemError: String?   // SMAppService refused the last change (shown in General)

    private var watcher: FSEventStreamRef?
    private var pendingRun: DispatchWorkItem?
    private var timer: Timer?
    private var minuteTimer: Timer?
    private var mounted: [URL: SmartInstaller.Watch] = [:]   // Smart Installer fallback: volumes we watch for a manual install
    private var offered = Set<String>()                    // carrier offers shown this session (dismissed ones persist in pending)
    private var installTimer: Timer?                      // runs only while something is mounted
    private var checkingInstalls = false
    private var checkingCarriers = false

    init(store: Store = Store()) {
        self.store = store
        self.engine = Engine(store: store)
        engine.reading = { name, started in
            Task { @MainActor in AppModel.shared.readingChanged(name, started) }
        }
        self.settings = store.settings
        refresh()
        refreshAccess()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshAccess() }
        }
    }

    // MARK: State

    private var readTimer: Timer?

    /// A read that takes over ~2 s opens the island with the thinking orb; a quick read stays silent.
    func readingChanged(_ name: String, _ started: Bool) {
        readTimer?.invalidate()
        if started {
            readTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in MainActor.assumeIsolated { Island.shared.show(.reading(name)) } }
        } else {
            Island.shared.dismiss(id: "reading")
        }
    }

    func refresh() {
        settings = store.settings
        actions = store.actions
        pending = store.pending
        shelfSuggestions = engine.suggestedShelves()
        duplicatesBytes = engine.duplicatesSize()
    }

    func set<V>(_ kp: WritableKeyPath<Settings, V>, _ value: V) {
        store.update { $0[keyPath: kp] = value }
        settings = store.settings
        if kp == \Settings.openAtLogin { applyLoginItem() }
        if kp == \Settings.appearance { applyAppearance() }
        if kp == \Settings.roots || kp == \Settings.pausedRoots { startWatching() }
        HotKeys.shared.register(settings)
        StatusItem.shared.update()
        Island.shared.relayout()
    }

    /// Light, dark, or follow the system. KANSO_APPEARANCE (screenshots) wins.
    func applyAppearance() {
        let a = ProcessInfo.processInfo.environment["KANSO_APPEARANCE"] ?? settings.appearance
        NSApp.appearance = a == "dark" ? NSAppearance(named: .darkAqua) : a == "light" ? NSAppearance(named: .aqua) : nil
    }

    func binding<V>(_ kp: WritableKeyPath<Settings, V>) -> Binding<V> {
        // Settings changes animate: options dim, rows reveal and cards re-select with the same spring.
        Binding(get: { self.settings[keyPath: kp] }, set: { v in withAnimation(Motion.spring(0.35)) { self.set(kp, v) } })
    }

    /// Saves a rule the user approved from a plain-English draft, creating its shelf type if it is new.
    @discardableResult
    func saveDraftedRule(_ rule: Rule, newShelf: NewShelf?) -> Bool {
        let ok = engine.saveDraft(rule, newShelf: newShelf)
        settings = store.settings
        return ok
    }

    /// Why the plain-English rule field is hidden; nil when it can be used.
    var ruleFieldReason: String? { RuleDrafting.unavailableReason(settings, model: ai) }

    func update(_ change: (inout Settings) -> Void) {
        store.update(change)
        settings = store.settings
    }

    var needs: [Need] {
        var out: [Need] = actions.filter { $0.kind == .duplicate && $0.pending && !$0.undone && FileManager.default.fileExists(atPath: $0.dst) }.map { .duplicate($0) }
        if !pending.renames.isEmpty { out.append(.renames(pending.renames, pending.renamesFound ?? Date())) }
        out += pending.suggestions.map { .rule($0) }
        out += shelfSuggestions.map { .shelf($0) }
        return out.sorted { $0.ts > $1.ts }
    }

    /// Done actions, newest first (trash records and undone actions excluded).
    var done: [Action] { actions.reversed().filter { !$0.undone && !$0.pending && $0.kind != .trashed } }

    var today: Stats { Stats.today(actions) }
    var sortingOn: Bool { settings.autoSort }
    var aiReady: Bool { settings.appleIntelligence && ai.available }
    var modelLine: String { aiReady ? "Apple Intelligence · files stay on this Mac" : "Sorting by type · files stay on this Mac" }

    // MARK: Sorting on / off

    func setSorting(_ on: Bool, for duration: OffDuration = .untilOn) {
        update { s in
            s.autoSort = on
            s.sortingOffUntil = on ? nil : duration.until()
            s.sortingOffSince = on ? nil : Date()
            s.offReminderShown = false
        }
        StatusItem.shared.update()
        if on { changed() }
    }

    /// "back on in 58 min", or "until I turn it on".
    var offLine: String {
        guard let u = settings.sortingOffUntil else { return "until I turn it on" }
        let mins = max(1, Int(u.timeIntervalSinceNow / 60))
        return mins >= 90 ? "back on \(u.formatted(date: Calendar.current.isDateInToday(u) ? .omitted : .abbreviated, time: .shortened))" : "back on in \(mins) min"
    }

    var sortingStatus: String {
        guard !settings.autoSort else { return "On" }
        if let u = settings.sortingOffUntil { return "Off until \(u.formatted(date: Calendar.current.isDateInToday(u) ? .omitted : .abbreviated, time: .shortened))" }
        return "Off"
    }

    // MARK: Sorting

    func sortNow(trigger: String = "menu") {
        guard !busy else { return }
        busy = true
        StatusItem.shared.update()
        let engine = self.engine
        Task.detached(priority: .utility) {   // always background priority
            engine.cleanRecents()
            engine.detectCorrections()
            let plan = await engine.plan(trigger: trigger)
            let done = engine.apply(plan.moves, trigger: trigger)
            await MainActor.run {
                self.busy = false
                self.waiting = plan.waiting
                let newRenames = self.store.pending.renames.count > self.pending.renames.count
                self.refresh()
                StatusItem.shared.update()
                self.announce(done, renamesFound: newRenames, trigger: trigger)
                if !plan.waiting.isEmpty { self.schedule(after: TimeInterval(max(self.settings.settleSeconds, 5))) }
            }
        }
    }

    /// The first Sort everything is always a preview: the plan opens in the review window.
    func previewSortEverything() {
        busy = true
        let engine = self.engine
        Task.detached {
            let plan = await engine.plan(all: true, trigger: "sort-everything")
            await MainActor.run {
                self.busy = false
                self.preview = plan.moves
                Windows.shared.showReview(tab: .sort)
            }
        }
    }

    func applyPreview(_ moves: [Planned]) {
        let done = engine.apply(moves, trigger: "sort-everything")
        preview = []
        refresh()
        announce(done, renamesFound: !store.pending.renames.isEmpty, trigger: "sort-everything")
    }

    /// Plain sorts are silent (PRODUCT.md): only renames, duplicates and needs-you items reach the island.
    /// A run the user started (Sort now, Sort everything) that touched several files gets one card with one Undo for the whole run;
    /// its per-file rename notices are folded into it. Automatic runs never get a card.
    func announce(_ done: [Action], renamesFound: Bool, trigger: String = "auto") {
        if let b = Batch.summary(done, trigger: trigger) {
            Island.shared.show(.batch(run: b.run, text: b.text))
        } else {
            for a in done where a.kind == .renamed { Island.shared.show(.renamed(a)) }
        }
        for a in done where a.kind == .duplicate { Island.shared.show(.duplicate(a)) }
        if renamesFound { Island.shared.show(.renameReview(store.pending.renames.count)) }
    }

    // MARK: Actions

    func undoLast() {
        let r = engine.undoLast()
        refresh()
        if !r.isEmpty { Island.shared.show(.info(icon: "arrow.uturn.backward", text: "Put back \(r.count == 1 ? r[0].srcName : "\(r.count) files")")) }
    }

    func undo(_ ids: Set<UUID>) { engine.undo(ids); refresh() }

    func undoRun(_ run: String) { undo(Set(actions.filter { $0.run == run && !$0.undone }.map(\.id))) }

    func trash(_ id: UUID) {
        if let t = engine.trash(id) { Island.shared.show(.info(icon: "trash", text: "\(t.srcName) moved to Trash", undo: t.id)) }
        refresh()
    }

    func keepBoth(_ id: UUID) { engine.keepBoth(id); refresh() }

    func trashAllDuplicates() {
        let n = engine.trashAllDuplicates()
        refresh()
        if n > 0 { Island.shared.show(.info(icon: "trash", text: "Moved \(n) extra \(n == 1 ? "copy" : "copies") to Trash")) }
    }

    /// `announce: false` when the caller shows its own confirmation (the island overview).
    func applyRenames(_ p: [RenameProposal], announce: Bool = true) {
        let done = engine.applyRenames(p)
        refresh()
        if announce, let b = Batch.summary(done, trigger: "review") { Island.shared.show(.batch(run: b.run, text: b.text)) }
    }
    func dismissRenames() { engine.dismissRenames(); refresh() }
    /// Accept a suggested shelf: the files move as one run; the island shows one card with one Undo for it.
    @discardableResult
    func acceptShelf(_ id: String) -> [Action] {
        let done = engine.acceptShelfSuggestion(id)
        refresh()
        if let b = Batch.summary(done, trigger: "suggestion") { Island.shared.show(.batch(run: b.run, text: b.text)) }
        return done
    }
    func dismissShelf(_ id: String) { engine.dismissShelfSuggestion(id); refresh() }
    func acceptSuggestion(_ id: UUID) { engine.acceptSuggestion(id); refresh() }
    func dismissSuggestion(_ id: UUID) { engine.dismissSuggestion(id); refresh() }
    /// "+ Add tag" on a sorted or renamed file: a Finder tag (with a Finder colour label) on the file, remembered on the action.
    func addTag(_ id: UUID, _ name: String, color: Int? = nil) {
        guard let a = actions.first(where: { $0.id == id }), !name.isEmpty, !a.tags.contains(name) else { return }
        Tags.add(URL(fileURLWithPath: a.dst), [name], color: color)
        store.modify([id]) { $0.tags.append(name); if let color { $0.details["tagcolor:" + name] = String(color) } }
        refresh()
    }

    func removeTag(_ id: UUID, _ name: String) {
        guard let a = actions.first(where: { $0.id == id }) else { return }
        Tags.remove(URL(fileURLWithPath: a.dst), [name])
        store.modify([id]) { $0.tags.removeAll { $0 == name }; $0.details["tagcolor:" + name] = nil }
        refresh()
    }

    /// "Rename…": journaled as a rename, so Undo restores the old name. False when the name is refused.
    @discardableResult
    func renameFile(_ id: UUID, to name: String) -> Bool {
        let r = engine.renameFile(id, to: name)
        refresh()
        if let r { selectedActivity = r.id.uuidString }
        return r != nil
    }

    /// "Edit name…" on a rename proposal: the review keeps the edited name.
    func editProposal(_ id: UUID, name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !n.contains("/") else { return }
        store.updatePending { p in if let i = p.renames.firstIndex(where: { $0.id == id }) { p.renames[i].newName = n } }
        refresh()
    }

    /// Tag name → files carrying it, for the tag picker.
    nonisolated func tagCounts() async -> [String: Int] { engine.tagCounts() }

    func move(_ id: UUID, to shelf: String) { engine.move(id, to: shelf); refresh() }

    /// "Don't sort this file": adds the keep tag.
    func keep(_ url: URL) { Tags.add(url, [settings.keepTag]); waiting.removeAll { $0.url == url } }

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
    }

    // MARK: Folders

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch Folder"
        panel.message = "Kanso sorts only the top level of the folders you pick."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let home = NSHomeDirectory()
        let added = panel.urls.map { $0.path.hasPrefix(home + "/") ? "~" + $0.path.dropFirst(home.count) : $0.path }.filter { !settings.roots.contains($0) }
        if !added.isEmpty { set(\.roots, settings.roots + added) }
    }

    func removeFolder(_ root: String) { set(\.roots, settings.roots.filter { $0 != root }); set(\.pausedRoots, settings.pausedRoots.filter { $0 != root }) }

    func toggleFolder(_ root: String, _ on: Bool) {
        set(\.pausedRoots, on ? settings.pausedRoots.filter { $0 != root } : settings.pausedRoots + [root])
    }

    // MARK: Watching

    /// FSEvents on the watched folders; a change waits for the settle time, then sorts.
    func startWatching() {
        if let w = watcher { FSEventStreamStop(w); FSEventStreamInvalidate(w); FSEventStreamRelease(w); watcher = nil }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in Task { @MainActor in self.tick() } }
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in self.minute() } }
        guard settings.onboarded else { return }
        let paths = settings.activeRoots.map(\.path) as CFArray
        // passUnretained is safe only because AppModel.shared lives for the whole app; the stream is stopped before a restart.
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, _, flags, _ in
            let me = Unmanaged<AppModel>.fromOpaque(info!).takeUnretainedValue()
            // A watched folder was moved, renamed or deleted: the stream no longer follows it, so start again.
            let rootChanged = (0..<count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagRootChanged) != 0 }
            Task { @MainActor in
                if rootChanged { me.startWatching() } else { me.changed() }
            }
        }
        let createFlags = UInt32(kFSEventStreamCreateFlagNoDefer) | UInt32(kFSEventStreamCreateFlagWatchRoot)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, createFlags) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        watcher = s
        tick()
    }

    func changed() {
        checkCarriers()
        guard settings.autoSort, settings.onboarded else { return }
        schedule(after: TimeInterval(settings.settleSeconds) + 1)
    }

    func schedule(after seconds: TimeInterval) {
        pendingRun?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in self?.sortNow(trigger: "auto") } }
        pendingRun = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    /// Hourly: expire Recents links, expire held duplicates (opt-in), pick up anything that settled.
    func tick() {
        engine.cleanRecents()
        UpdateChecker.shared.checkAutomatically(enabled: settings.updateChecks)
        if !engine.expireDuplicates().isEmpty { refresh() }
        if settings.autoSort && settings.onboarded { sortNow(trigger: "auto") }
    }

    /// Every minute: timed Sorting-off ends by itself; after 24 h off, the island says so once.
    func minute() {
        if !settings.autoSort, let until = settings.sortingOffUntil, until <= Date() { setSorting(true); return }
        if !settings.autoSort, !settings.offReminderShown, let since = settings.sortingOffSince, Date().timeIntervalSince(since) >= 86400 {
            update { $0.offReminderShown = true }
            Island.shared.show(.sortingOff(since))
        }
    }

    func applyLoginItem() {
        do {
            if settings.openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            NSLog("Kanso: login item: \(error.localizedDescription)")
            // Put the switch back where macOS left it, and say why in General. Written to the store directly so
            // set() doesn't call applyLoginItem again.
            let wanted = settings.openAtLogin
            store.update { $0.openAtLogin = !wanted }
            settings = store.settings
            loginItemError = error.localizedDescription
        }
    }

    func finishOnboarding(previewCleanup: Bool) {
        update { $0.onboarded = true; $0.since = Date(); $0.shortcutHintUntil = Date().addingTimeInterval(5 * 86400) }
        startWatching()
        StatusItem.shared.update()
        if previewCleanup { previewSortEverything() }
    }

    // MARK: Folder access

    /// Whether macOS lets Kanso read a watched folder ("not allowed" means the user declined the prompt).
    nonisolated static func canRead(_ path: String) -> Bool {
        let p = (path as NSString).expandingTildeInPath
        return (try? FileManager.default.contentsOfDirectory(atPath: p)) != nil
    }

    func refreshAccess() {
        let bad = settings.roots.filter { !AppModel.canRead($0) }
        if bad != inaccessibleRoots { inaccessibleRoots = bad }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }

    // MARK: Smart Installer

    func startSmartInstaller() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self.volumeMounted(url) }
        }
        nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                _ = self.mounted.removeValue(forKey: url.standardizedFileURL)
                self.updateInstallTimer()
            }
        }
    }

    /// hdiutil, reading the volume and the receipts all run off the main thread; only the state lands back here.
    /// One app and nothing else: the install offer. Anything else (or Not now): the fallback watch.
    private func volumeMounted(_ volume: URL) {
        guard settings.smartInstaller else { return }
        let key = volume.standardizedFileURL
        let mountedAt = Date()
        Task.detached(priority: .utility) {
            let watch = SmartInstaller.inspect(volume, at: mountedAt)
            let offer = watch.flatMap { w in
                SmartInstaller.singleApp(in: volume).flatMap { app in
                    SmartInstaller.appInfo(app).map { InstallOffer(app: app, info: $0, download: w.image, volume: volume, existing: SmartInstaller.existing($0, in: URL(fileURLWithPath: "/Applications"))).checked() }
                }
            }
            await MainActor.run {
                guard let watch, self.settings.smartInstaller else { return }
                self.mounted[key] = watch
                self.updateInstallTimer()
                if let offer { self.offerInstall(offer) }
            }
        }
    }

    /// After the first Install, a fresh app installs in one step; Replace and Skip always ask.
    func offerInstall(_ o: InstallOffer) {
        if o.signature == .broken {   // changed after signing: never installed, not even with a warning
            Island.shared.show(.info(icon: "exclamationmark.shield", text: "\(o.info.name) was changed after it was signed. Kanso won't install it."))
            return
        }
        if settings.installWithoutAsking, o.existing == .none, o.signature == .valid { install(o); return }   // unsigned always asks
        Island.shared.show(.offer(.install(o)))
    }

    /// Copy, check, eject, trash the download, open. The island shows the work, then one line with what happened.
    func install(_ o: InstallOffer, replace: Bool = false) {
        if !settings.installWithoutAsking { set(\.installWithoutAsking, true) }   // both answers are remembered
        if let v = o.volume { mounted.removeValue(forKey: v.standardizedFileURL); updateInstallTimer() }   // the offer handles it, not the fallback
        let name = o.info.name, trashDownload = settings.trashDownload, engine = engine
        Island.shared.show(.info(icon: "arrow.down.app", text: "Installing \(name)…"))
        Task.detached(priority: .userInitiated) {
            let r = engine.install(app: o.app, download: o.download, move: o.volume == nil, replace: replace, allowUnsigned: o.signature == .unsigned, trashDownload: trashDownload) {
                guard let v = o.volume else { return true }
                return (try? NSWorkspace.shared.unmountAndEjectDevice(at: v)) != nil
            }
            await MainActor.run {
                self.refresh()
                Island.shared.dismiss(id: "info-Installing \(name)…")
                // Success says nothing: the app opening from Applications is the confirmation (Put Back for the download
                // is in Activity). The island speaks only when a step failed.
                if let f = r.failure { Island.shared.show(.info(icon: r.installed == nil ? "exclamationmark.triangle" : "checkmark.circle", text: f)) }
                if let app = r.installed, self.settings.openAfterInstall {
                    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())   // from /Applications, never a translocated copy
                }
            }
        }
    }

    /// Whether an app with this bundle id is running (Replace waits until it's quit).
    func isRunning(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    /// Extracted archives and opened torrents get one "done with it?" offer; a zip that extracted to one app gets the
    /// install offer. Each file is offered once (dismissals persist). Unanswered, the Cleanup timers apply.
    func checkCarriers() {
        guard settings.smartInstaller, settings.onboarded, !checkingCarriers else { return }
        checkingCarriers = true
        let roots = settings.activeRoots, dismissed = Set(pending.dismissed), offered = offered, keep = settings.keepTag
        Task.detached(priority: .utility) {
            var found: [CarrierOffer] = []
            for root in roots {
                let shelves = root.appendingPathComponent(Library.mine)
                let dirs = [root] + ((try? FileManager.default.contentsOfDirectory(at: shelves, includingPropertiesForKeys: nil)) ?? [])
                for dir in dirs {
                    for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                        let key = "carrier:" + u.path
                        guard !dismissed.contains(key), !offered.contains(key), !Tags.read(u).contains(keep) else { continue }
                        switch u.pathExtension.lowercased() {
                        case "zip":
                            guard let x = Carriers.extraction(of: u) else { continue }
                            NSLog("Kanso carrier match: %@ lists %@; found %@", u.lastPathComponent, x.listing.joined(separator: ", "), x.found.joined(separator: ", "))
                            if x.sibling.pathExtension.lowercased() == "app", let info = SmartInstaller.appInfo(x.sibling) {
                                found.append(.install(InstallOffer(app: x.sibling, info: info, download: u, volume: nil, existing: SmartInstaller.existing(info, in: URL(fileURLWithPath: "/Applications"))).checked()))
                            } else { found.append(.trashZip(u)) }
                        case "torrent" where Carriers.torrentOpened(u): found.append(.trashTorrent(u))
                        default: continue
                        }
                    }
                }
            }
            await MainActor.run {
                self.checkingCarriers = false
                for o in found where !self.offered.contains(o.key) {
                    self.offered.insert(o.key)
                    if case .install(let i) = o { self.offerInstall(i) } else { Island.shared.show(.offer(o)) }
                }
            }
        }
    }

    /// The user answered a carrier offer: never offer that file again.
    func dismissCarrier(_ o: CarrierOffer) { engine.store.updatePending { $0.dismissed.append(o.key) }; refresh() }

    /// "Trash the zip" / "Trash it": journaled, one ⌘Z away.
    @discardableResult
    func trashCarrier(_ o: CarrierOffer) -> Action? {
        guard let u = o.url else { return nil }
        let a = engine.trashCarrier(u, kind: o.kind)
        dismissCarrier(o)
        return a
    }

    /// ponytail: polls every 3 s, but only while an installer volume is mounted; switch to FSEvents if it ever matters.
    private func updateInstallTimer() {
        if mounted.isEmpty {
            installTimer?.invalidate()
            installTimer = nil
        } else if installTimer == nil {
            installTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkInstalls() }
            }
        }
    }

    /// Fallback: the user installed by hand (a .pkg, several items, or Not now). Once it's verifiably in, eject and trash.
    private func checkInstalls() {
        guard settings.smartInstaller, !mounted.isEmpty, !checkingInstalls else { return }
        checkingInstalls = true
        let watching = mounted
        Task.detached(priority: .utility) {
            let spent = watching.filter { SmartInstaller.isSpent($0.value) }
            await MainActor.run {
                self.checkingInstalls = false
                for (volume, entry) in spent where self.mounted[volume] != nil {
                    self.mounted.removeValue(forKey: volume)
                    try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                    guard self.settings.trashDownload else { continue }
                    // trashInstaller refuses Manual Shelves, Keep-tagged, Homebrew's cache and non-.dmg images.
                    if self.engine.trashInstaller(entry.image, app: entry.label) != nil { self.refresh() }   // silent, like any install: it's in Activity
                }
                self.updateInstallTimer()
            }
        }
    }
}

/// One app ready to install: from a mounted disk image (`volume` set) or extracted from a zip (`volume` nil, moved).
struct InstallOffer: Equatable {
    var app: URL
    var info: SmartInstaller.AppInfo
    var download: URL
    var volume: URL?
    var existing: SmartInstaller.Existing
    var signature = SmartInstaller.Signature.valid
    var checksum: String?          // the download's SHA-256, shown for an unsigned app so it can be compared with the developer's
    var isCurrent: Bool { if case .current = existing { return true }; return false }

    /// Reads the signature, and for an unsigned app the download's checksum. Blocking: off the main thread.
    func checked() -> InstallOffer {
        var o = self
        o.signature = SmartInstaller.signature(app)
        if o.signature == .unsigned { o.checksum = SmartInstaller.checksum(download) }
        return o
    }
}

/// A "done with it?" offer on the island.
enum CarrierOffer: Equatable {
    case install(InstallOffer)
    case trashZip(URL)
    case trashTorrent(URL)

    var url: URL? {
        switch self {
        case .install(let o): return o.download
        case .trashZip(let u), .trashTorrent(let u): return u
        }
    }
    var key: String { "carrier:" + (url?.path ?? "") }
    var kind: String { if case .trashTorrent = self { return "torrent" }; return "archive" }
}
