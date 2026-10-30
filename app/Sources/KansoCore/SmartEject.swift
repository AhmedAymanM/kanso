import Foundation

/// Smart Eject: once an installer's payload has verifiably landed, the installer is provably spent (ADR 0002):
/// the volume is ejected and the .dmg goes to the Trash, journaled and one ⌘Z away.
///
/// - .dmg with apps: spent when EVERY app on the volume is in /Applications (same bundle id) with a ctime after the
///   mount and settled for 5 s. An app that was already installed at mount time (same bundle id + path) only counts if
///   its version/build changed since the mount AND now equals the volume's, so an auto-update's ctime bump isn't mistaken
///   for the install.
/// - .dmg/.pkg with packages: identifiers come from the flat package's `Distribution` (`pkg-ref id`) and `PackageInfo`
///   (`pkg-info identifier`), extracted with `xar` (only those two members, no payload copy). Spent when
///   `pkgutil --pkg-info-plist <id>` reports an `install-time` after the mount for EVERY identifier.
/// - Everything that spawns a process has a timeout and is meant to run off the main thread.
public enum SmartEject {
    public struct Version: Hashable, Sendable {
        public var version: String, build: String
        public init(version: String, build: String) { self.version = version; self.build = build }
    }

    /// An app bundle's identity.
    public struct AppInfo: Hashable, Sendable {
        public var id: String, name: String, path: String
        public var v: Version
        public var ctime: TimeInterval, mtime: TimeInterval
        public init(id: String, name: String, path: String, v: Version, ctime: TimeInterval = 0, mtime: TimeInterval = 0) {
            self.id = id; self.name = name; self.path = path; self.v = v; self.ctime = ctime; self.mtime = mtime
        }
        public var key: String { id + "|" + path }
    }

    /// One mounted installer volume being watched.
    public struct Watch: Sendable {
        public var image: URL
        public var apps: [AppInfo]
        public var packageIDs: Set<String>
        public var at: Date
        public var before: [String: Version]   // apps present in /Applications at mount time (AppInfo.key → version)
        public var label: String { apps.first?.name ?? "installer" }
    }

    // MARK: Pure logic

    /// Paths Kanso must never trash on its own: not a .dmg, inside any "Manual Shelves", or carrying the Keep tag.
    public static func refuses(_ image: URL, roots: [URL], keepTagged: Bool) -> Bool {
        if image.pathExtension.lowercased() != "dmg" || keepTagged { return true }
        let path = image.standardizedFileURL.path
        if image.standardizedFileURL.pathComponents.contains(Library.manual) { return true }
        return roots.contains { path.hasPrefix($0.appendingPathComponent(Library.manual).standardizedFileURL.path + "/") }
    }

    /// Whether every app of the volume is installed after the mount (see the type comment).
    public static func appsSpent(volume: [AppInfo], installed: [AppInfo], before: [String: Version],
                                 mounted: TimeInterval, now: TimeInterval) -> Bool {
        guard !volume.isEmpty else { return true }
        return volume.allSatisfy { app in
            installed.contains { inst in
                guard inst.id == app.id, inst.ctime > mounted, now - max(inst.mtime, inst.ctime) >= 5 else { return false }
                if let was = before[inst.key] { return was != inst.v && inst.v == app.v }
                return true
            }
        }
    }

    /// Package identifiers from a `PackageInfo` (`<pkg-info identifier="…">`) or `Distribution` (`<pkg-ref id="…">`) XML.
    public static func parsePackageIDs(_ xml: String) -> Set<String> {
        var out = Set<String>()
        for pattern in ["<pkg-info\\b[^>]*?\\sidentifier=\"([^\"]+)\"", "<pkg-ref\\b[^>]*?\\sid=\"([^\"]+)\""] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            let ns = xml as NSString
            for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                out.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        return out
    }

    // MARK: Process helper

    /// Runs a tool, returns stdout on exit status 0. Killed after `timeout` seconds. Blocking: call off the main thread.
    public static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 10) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0 ? data : nil
    }

    // MARK: Disk reads (blocking; call off the main thread)

    public static func appInfo(_ app: URL) -> AppInfo? {
        guard let d = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let id = d["CFBundleIdentifier"] as? String else { return nil }
        let v = Version(version: d["CFBundleShortVersionString"] as? String ?? "", build: d["CFBundleVersion"] as? String ?? "")
        return AppInfo(id: id, name: app.deletingPathExtension().lastPathComponent, path: app.path, v: v,
                       ctime: Stat.ctime(app) ?? 0, mtime: Stat.mtime(app) ?? 0)
    }

    /// Top-level apps in a directory (a mounted volume or /Applications).
    public static func apps(in dir: URL) -> [AppInfo] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".app") }
            .compactMap { appInfo(dir.appendingPathComponent($0)) }
    }

    /// Package identifiers of the top-level .pkg/.mpkg files on a volume.
    public static func packageIDs(onVolume volume: URL) -> Set<String> {
        var ids = Set<String>()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? [] {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ext == "pkg" || ext == "mpkg" else { continue }
            let pkg = volume.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: pkg.path, isDirectory: &isDir), isDir.boolValue {   // old bundle-style package
                if let id = NSDictionary(contentsOf: pkg.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String { ids.insert(id) }
                continue
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kanso-pkg-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            for member in ["Distribution", "PackageInfo"] {
                _ = run("/usr/bin/xar", ["-x", "-f", pkg.path, "-C", tmp.path, member], timeout: 20)
                if let x = try? String(contentsOf: tmp.appendingPathComponent(member), encoding: .utf8) { ids.formUnion(parsePackageIDs(x)) }
            }
        }
        return ids
    }

    /// When a package id was last installed, from the receipt database.
    public static func installTime(ofPackage id: String) -> TimeInterval? {
        guard let data = run("/usr/sbin/pkgutil", ["--pkg-info-plist", id], timeout: 10),
              let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        if let n = d["install-time"] as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Looks at a freshly mounted volume. Nil when it holds nothing installable.
    public static func inspect(_ volume: URL, at: Date = Date()) -> Watch? {
        let found = SmartEject.apps(in: volume)
        let pkgs = packageIDs(onVolume: volume)
        guard !found.isEmpty || !pkgs.isEmpty, let image = imagePath(forVolume: volume) else { return nil }
        var before: [String: Version] = [:]
        for a in SmartEject.apps(in: URL(fileURLWithPath: "/Applications")) { before[a.key] = a.v }
        return Watch(image: image, apps: found, packageIDs: pkgs, at: at, before: before)
    }

    /// Whether everything the installer carries has been installed since the mount.
    public static func isSpent(_ w: Watch, now: Date = Date()) -> Bool {
        let t = w.at.timeIntervalSince1970
        if !w.apps.isEmpty, !appsSpent(volume: w.apps, installed: apps(in: URL(fileURLWithPath: "/Applications")),
                                      before: w.before, mounted: t, now: now.timeIntervalSince1970) { return false }
        return w.packageIDs.allSatisfy { (installTime(ofPackage: $0) ?? 0) > t }
    }

    /// The .dmg file behind a mounted volume, from `hdiutil info`.
    public static func imagePath(forVolume volume: URL) -> URL? {
        guard let data = run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 15),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = info["images"] as? [[String: Any]] else { return nil }
        for image in images {
            let mounts = (image["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["mount-point"] as? String }
            if mounts.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL == volume.standardizedFileURL }),
               let path = image["image-path"] as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

extension Engine {
    /// Moves a spent installer to the Trash and journals it (Put Back restores it).
    @discardableResult
    public func trashInstaller(_ image: URL, app: String) -> Action? {
        let roots = s.roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard !SmartEject.refuses(image, roots: roots, keepTagged: Tags.read(image).contains(s.keepTag)) else { return nil }
        let size = Stat.size(image)
        var result: NSURL?
        guard FileManager.default.fileExists(atPath: image.path),
              (try? FileManager.default.trashItem(at: image, resultingItemURL: &result)) != nil, let t = result as URL? else { return nil }
        var a = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .trashed, src: image.path, dst: t.path,
                       root: rootFor(image)?.path ?? "", shelf: "Trash", why: "installer · \(app) is installed", source: "Smart Eject")
        a.details = ["installer": app, "size": String(size)]
        store.append(a)
        return a
    }
}
