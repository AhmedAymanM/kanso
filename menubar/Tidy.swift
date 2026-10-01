// Menu bar front end for tidy. All logic lives in the `tidy` CLI; this only calls it.
// Build: ./build.sh

import AppKit
import SwiftUI

struct Status: Decodable {
    var enabled = false
    var roots: [String] = []
    var apple_intelligence = false
    var python = ""
    var keep_tag = "Keep"
}

/// Finder right-click → "Don't Sort with Tidy" / "Allow Tidy to Sort" (declared as NSServices in Info.plist).
/// Toggles the keep tag, which the sorter already skips.
final class Services: NSObject {
    @objc func skipFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        setKeep(true, pboard)
    }

    @objc func allowFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        setKeep(false, pboard)
    }

    private func setKeep(_ keep: Bool, _ pboard: NSPasteboard) {
        let tag = UserDefaults.standard.string(forKey: "keepTag") ?? "Keep"
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
            let new = keep ? (tags.contains(tag) ? tags : tags + [tag]) : tags.filter { $0 != tag }
            try? (url as NSURL).setResourceValue(new, forKey: .tagNamesKey)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = Services()
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var status = Status()
    @Published var busy = false
    @Published var message = ""
    private let cli = Bundle.main.object(forInfoDictionaryKey: "TidyCLI") as? String ?? "tidy"

    init() { Task { await refresh() } }

    /// Runs `tidy <args>` off the main thread; returns (exit code, stdout).
    private func tidy(_ args: [String]) async -> (Int32, String) {
        let cli = self.cli
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            do { try p.run() } catch { return (-1, "\(error.localizedDescription)") }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    func refresh() async {
        let (code, out) = await tidy(["status", "--json"])
        if code == 0, let s = try? JSONDecoder().decode(Status.self, from: Data(out.utf8)) {
            status = s
            UserDefaults.standard.set(s.keep_tag, forKey: "keepTag")  // the Finder service may run before any refresh
        } else {
            message = "tidy CLI failed: \(out.suffix(200))"
        }
    }

    private func perform(_ args: [String], summary: @escaping (String) -> String = { $0 }) {
        busy = true
        Task {
            let (code, out) = await tidy(args)
            let last = out.split(separator: "\n").last.map(String.init) ?? ""
            message = code == 0 ? summary(last) : "Failed: \(last)"
            busy = false
            await refresh()
        }
    }

    func setEnabled(_ on: Bool) {
        perform([on ? "install" : "uninstall"]) { _ in on ? "Auto-sort is on" : "Auto-sort is off" }
        if on && !UserDefaults.standard.bool(forKey: "askedFDA") {
            UserDefaults.standard.set(true, forKey: "askedFDA")
            grantAccess()
        }
    }

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Sort This Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !status.roots.contains($0) }
        if !added.isEmpty { perform(["roots"] + status.roots + added) { _ in "Added \(added.count) folder(s)" } }
    }

    func remove(_ root: String) {
        let rest = status.roots.filter { $0 != root }
        guard !rest.isEmpty else { message = "Keep at least one folder"; return }
        perform(["roots"] + rest) { _ in "Stopped sorting \((root as NSString).lastPathComponent)" }
    }

    func sortNow() { perform(["run"]) }

    func sortEverything() {
        let alert = NSAlert()
        alert.messageText = "Sort everything already in your folders?"
        alert.informativeText = "Existing files and folders at the top level of \(status.roots.count) folder(s) will be moved into categories. You can revert it with Undo Last Sort."
        alert.addButton(withTitle: "Sort Everything")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { perform(["run", "--all"]) }
    }

    func undo() { perform(["undo"]) { _ in "Last sort undone" } }

    func editRules() { perform(["config"]) { _ in "" } }

    /// The background agent is a Python process; macOS needs it in Full Disk Access.
    func grantAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        if !status.python.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.python)])
        }
        let alert = NSAlert()
        alert.messageText = "Allow tidy to reach your folders"
        alert.informativeText = "In Full Disk Access, click + and add the highlighted Python file (or drag it from Finder into the list):\n\n\(status.python)"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra("tidy", systemImage: model.busy ? "arrow.triangle.2.circlepath" : (model.status.enabled ? "tray.full.fill" : "tray")) {
            Toggle("Auto-Sort", isOn: Binding(get: { model.status.enabled }, set: { model.setEnabled($0) }))
            if !model.message.isEmpty { Text(model.message) }
            Divider()

            Text("Folders")
            ForEach(model.status.roots, id: \.self) { root in
                Menu((root as NSString).abbreviatingWithTildeInPath) {
                    Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: root)) }
                    Button("Stop Sorting") { model.remove(root) }
                }
            }
            Button("Add Folder…") { model.addFolders() }
            Divider()

            Button("Sort New Files Now") { model.sortNow() }.disabled(model.busy)
            Button("Sort Everything…") { model.sortEverything() }.disabled(model.busy)
            Button("Undo Last Sort") { model.undo() }.disabled(model.busy)
            Divider()

            Text(model.status.apple_intelligence ? "Apple Intelligence: on" : "Apple Intelligence: off (von decides)")
            Button("Edit Rules…") { model.editRules() }
            Button("Grant Folder Access…") { model.grantAccess() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
