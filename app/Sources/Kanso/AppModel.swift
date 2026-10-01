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

    var id: String {
        switch self {
        case .duplicate(let a): return a.id.uuidString
        case .renames: return "renames"
        case .rule(let r): return r.id.uuidString
        }
    }
    var ts: Date {
        switch self {
        case .duplicate(let a): return a.ts
        case .renames(_, let d): return d
        case .rule(let r): return r.ts
        }
    }
    var tint: Tint {
        switch self {
        case .duplicate: return .duplicate
        case .renames: return .rename
        case .rule: return .rule
        }
    }
    var label: String {
        switch self {
        case .duplicate: return "Duplicate"
        case .renames: return "Rename review"
        case .rule: return "Rule suggestion"
        }
    }
    var icon: String {
        switch self {
        case .duplicate: return "doc.on.doc"
        case .renames: return "pencil.line"
        case .rule: return "wand.and.stars"
        }
    }
}

/// The pages of the one App window (design handoff 2026-09-30): history, the five features, then app settings.
enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", activity = "Activity"
    case sorting = "Sorting", renaming = "Renaming", duplicates = "Duplicates", tagging = "Tagging", smartEject = "Smart Eject"
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
        case .smartEject: return "eject"
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        }
    }
    /// Sidebar groups, separated by space.
    static let groups: [[Page]] = [[.overview, .activity], [.sorting, .renaming, .duplicates, .tagging, .smartEject], [.general, .privacy]]
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

    @Published private(set) var settings: Settings
    @Published private(set) var actions: [Action] = []
    @Published private(set) var pending = Pending()
    @Published private(set) var waiting: [Waiting] = []
    @Published private(set) var busy = false
    @Published private(set) var duplicatesBytes: Int64 = 0
    @Published var page: Page = .overview
    @Published var selectedActivity: String?
    @Published var preview: [Planned] = []     // Sort everything preview, shown in the review window
    @Published var collected = 0               // notices waiting while quiet (Focus / full-screen)

    private var watcher: FSEventStreamRef?
    private var pendingRun: DispatchWorkItem?
    private var timer: Timer?
    private var minuteTimer: Timer?
    private var mounted: [URL: (image: URL, apps: [String: String], at: Date)] = [:]   // Smart Eject: volumes we watch

    init(store: Store = Store()) {
        self.store = store
        self.engine = Engine(store: store)
        engine.reading = { name, started in
            Task { @MainActor in AppModel.shared.readingChanged(name, started) }
        }
        self.settings = store.settings
        refresh()
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

    func update(_ change: (inout Settings) -> Void) {
        store.update(change)
        settings = store.settings
    }

    var needs: [Need] {
        var out: [Need] = actions.filter { $0.kind == .duplicate && $0.pending && !$0.undone && FileManager.default.fileExists(atPath: $0.dst) }.map { .duplicate($0) }
        if !pending.renames.isEmpty { out.append(.renames(pending.renames, pending.renamesFound ?? Date())) }
        out += pending.suggestions.map { .rule($0) }
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
                self.announce(done, renamesFound: newRenames)
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
        announce(done, renamesFound: !store.pending.renames.isEmpty)
    }

    /// Plain sorts are silent (PRODUCT.md): only renames, duplicates and needs-you items reach the island.
    func announce(_ done: [Action], renamesFound: Bool) {
        for a in done where a.kind == .renamed { Island.shared.show(.renamed(a)) }
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

    func applyRenames(_ p: [RenameProposal]) { engine.applyRenames(p); refresh() }
    func dismissRenames() { engine.dismissRenames(); refresh() }
    func acceptSuggestion(_ id: UUID) { engine.acceptSuggestion(id); refresh() }
    func dismissSuggestion(_ id: UUID) { engine.dismissSuggestion(id); refresh() }
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
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            let me = Unmanaged<AppModel>.fromOpaque(info!).takeUnretainedValue()
            Task { @MainActor in me.changed() }
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, UInt32(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        watcher = s
        tick()
    }

    func changed() {
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
        } catch {
            NSLog("Kanso: login item: \(error.localizedDescription)")
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

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }

    // MARK: Smart Eject

    func startSmartEject() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self.volumeMounted(url) }
        }
        nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { _ = self.mounted.removeValue(forKey: url.standardizedFileURL) }
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { @MainActor in self.checkInstalls() } }
    }

    private func volumeMounted(_ volume: URL) {
        guard settings.smartEject else { return }
        let apps = SmartEject.apps(onVolume: volume)
        guard !apps.isEmpty, let image = SmartEject.imagePath(forVolume: volume) else { return }
        mounted[volume.standardizedFileURL] = (image, apps, Date())
    }

    /// ponytail: polls /Applications every 3 s while an installer volume is mounted; switch to FSEvents if it ever matters.
    private func checkInstalls() {
        guard settings.smartEject, !mounted.isEmpty else { return }
        for (volume, entry) in mounted {
            let done = SmartEject.installed(Set(entry.apps.keys), in: URL(fileURLWithPath: "/Applications"))
            guard let id = done.first, let app = entry.apps[id] else { continue }
            let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(app + ".app")
            // Installed means copied *after* the volume mounted (a reinstall counts; an old copy doesn't),
            // and settled: no change for 5 s.
            guard let c = Stat.ctime(target), c > entry.at.timeIntervalSince1970,
                  Date().timeIntervalSince1970 - (Stat.mtime(target).map { max($0, c) } ?? c) >= 5 else { continue }
            mounted.removeValue(forKey: volume)
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            if settings.smartEjectOnlyEject { continue }
            if let a = engine.trashInstaller(entry.image, app: app) {
                refresh()
                if settings.smartEjectNotice { Island.shared.show(.installer(a)) }
            }
        }
    }
}
