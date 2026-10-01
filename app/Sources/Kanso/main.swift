import AppKit

// `--snapshot DIR` renders every screen to PNGs (light and dark) and exits; used to check the UI without clicking.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshot.run(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

// `--icon FILE` writes the 1024 px app icon (build.sh turns it into AppIcon.icns).
if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshot.icon(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
