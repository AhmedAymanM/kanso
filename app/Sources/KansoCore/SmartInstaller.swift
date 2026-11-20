import CryptoKit
import Foundation
import Security

/// Smart Installer (PRODUCT.md §7). Opening a disk image (or a zip) that holds exactly one app offers to install it:
/// Kanso copies the app to /Applications, checks its signature, ejects the image, moves the download to the Trash
/// (journaled, ⌘Z) and opens the app from /Applications. Anything else keeps the fallback below.
///
/// Fallback (the old Smart Eject): once an installer's payload has verifiably landed, the installer is provably spent
/// (ADR 0002): the volume is ejected and the .dmg goes to the Trash, journaled and one ⌘Z away.
///
/// - .dmg with apps: spent when EVERY app on the volume is in /Applications (same bundle id) with a ctime after the
///   mount and settled for 5 s. An app that was already installed at mount time (same bundle id + path) only counts if
///   its version/build changed since the mount AND now equals the volume's, so an auto-update's ctime bump isn't mistaken
///   for the install.
/// - .dmg/.pkg with packages: identifiers come from the flat package's `Distribution` (`pkg-ref id`) and `PackageInfo`
///   (`pkg-info identifier`), extracted with `xar` (only those two members, no payload copy). Spent when
///   `pkgutil --pkg-info-plist <id>` reports an `install-time` after the mount for EVERY identifier.
/// - Everything that spawns a process has a timeout and is meant to run off the main thread.
public enum SmartInstaller {
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

    /// Paths Kanso must never trash on its own: not a .dmg (or a .zip it installed from), inside any "Manual Shelves",
    /// in Homebrew's cache, or carrying the Keep tag.
    public static func refuses(_ image: URL, roots: [URL], keepTagged: Bool, allowZip: Bool = false) -> Bool {
        let ext = image.pathExtension.lowercased()
        if !(ext == "dmg" || (allowZip && ext == "zip")) || keepTagged || isHomebrewCache(image) { return true }
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

    /// Homebrew downloads casks into its own cache and installs them itself; Kanso leaves those alone.
    public static func isHomebrewCache(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p.contains("/Library/Caches/Homebrew/") || p.hasPrefix("/opt/homebrew/") || p.hasPrefix("/usr/local/Homebrew/")
    }

    // MARK: Installing one app

    /// The one app on a volume (or in a folder) when that's all there is: exactly one top-level .app, no packages,
    /// and nothing else but hidden files and symlinks (the usual "Applications" alias). Anything else is nil, and the
    /// fallback applies.
    public static func singleApp(in dir: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        var app: URL?
        for n in names where !n.hasPrefix(".") {
            let u = dir.appendingPathComponent(n)
            if Stat.isSymlink(u) { continue }
            guard n.lowercased().hasSuffix(".app"), app == nil else { return nil }
            app = u
        }
        return app
    }

    /// What an already installed copy means for the offer.
    public enum Existing: Equatable, Sendable {
        case none                                  // not installed: Install
        case older(installed: String)              // the download is newer: Replace (when the app isn't running)
        case current(installed: String)            // same or newer installed: Skip
    }

    /// Numeric comparison of the short version, then the build ("3.10" > "3.9").
    public static func compare(_ a: Version, _ b: Version) -> ComparisonResult {
        let v = a.version.compare(b.version, options: .numeric)
        return v != .orderedSame ? v : a.build.compare(b.build, options: .numeric)
    }

    public static func existing(_ new: AppInfo, in apps: URL) -> Existing {
        let dest = apps.appendingPathComponent(URL(fileURLWithPath: new.path).lastPathComponent)
        guard let old = appInfo(dest) else { return .none }
        let label = old.v.version.isEmpty ? old.v.build : old.v.version
        return compare(old.v, new.v) == .orderedAscending ? .older(installed: label) : .current(installed: label)
    }

    /// What an app's code signature says. Any identity counts as `valid` (ad hoc and self-signed included): trust is
    /// Gatekeeper's job on first open. `unsigned` has no signature at all; `broken` was changed after it was signed.
    public enum Signature: String, Equatable, Sendable { case valid, unsigned, broken }

    public static func signature(_ app: URL) -> Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return .broken }
        switch SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) {
        case errSecSuccess: return .valid
        // A bundle that was ever sealed and now fails (an executable swapped for an unsigned one reads as "unsigned")
        // was changed after signing.
        case errSecCSUnsigned: return Stat.exists(app.appendingPathComponent("Contents/_CodeSignature")) ? .broken : .unsigned
        default: return .broken
        }
    }

    public static func signatureValid(_ app: URL) -> Bool { signature(app) == .valid }

    /// SHA-256 over every file in a bundle (relative path, then contents), in path order. With no signature to check,
    /// equal digests prove a copy is byte for byte the original.
    public static func treeDigest(_ dir: URL) -> String? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return nil }
        var paths: [String] = []
        for case let u as URL in e { paths.append(String(u.standardizedFileURL.path.dropFirst(dir.standardizedFileURL.path.count))) }
        var h = SHA256()
        for p in paths.sorted() {
            let u = dir.appendingPathComponent(p)
            h.update(data: Data(p.utf8))
            if Stat.isSymlink(u) { h.update(data: Data(((try? FileManager.default.destinationOfSymbolicLink(atPath: u.path)) ?? "").utf8)) }
            else if Stat.isRegular(u) {
                guard let d = Duplicates.digest(u) else { return nil }
                h.update(data: Data(d))
            }
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The download's SHA-256 in hex, to compare with the checksum the developer publishes.
    public static func checksum(_ file: URL) -> String? { Duplicates.digest(file).map { $0.map { String(format: "%02x", $0) }.joined() } }

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
        let found = SmartInstaller.apps(in: volume)
        let pkgs = packageIDs(onVolume: volume)
        guard !found.isEmpty || !pkgs.isEmpty, let image = imagePath(forVolume: volume), !isHomebrewCache(image) else { return nil }
        var before: [String: Version] = [:]
        for a in SmartInstaller.apps(in: URL(fileURLWithPath: "/Applications")) { before[a.key] = a.v }
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

/// How an install went, step by step, so the island can name the step that failed.
public struct InstallReport: Sendable {
    public var installed: URL?          // the app in /Applications
    public var trashed: Action?         // the download, journaled (⌘Z puts it back)
    public var replaced: Action?        // the older copy, journaled
    public var failure: String?         // one line naming the failed step; nil when everything worked
    public var unsigned = false         // installed without a signature (the user confirmed the warning)
    public init() {}
}

extension Engine {
    /// Installs one app: copy (or move, for an app extracted from a zip) into `apps`, check the copy's signature, then
    /// `eject` (the app layer unmounts the image; return false when it couldn't), then trash the download when asked.
    /// Replacing moves the old copy to the Trash, journaled, only after the new one is in place beside it.
    /// Blocking (ditto): call off the main thread.
    /// `allowUnsigned`: the user confirmed the unsigned-app warning. Without a signature the copy is checked against the
    /// original file by file instead. A broken signature (changed after signing) is never installed.
    public func install(app: URL, download: URL?, apps: URL = URL(fileURLWithPath: "/Applications"), move: Bool = false,
                        replace: Bool = false, allowUnsigned: Bool = false, trashDownload: Bool, eject: () -> Bool) -> InstallReport {
        var r = InstallReport()
        let name = app.deletingPathExtension().lastPathComponent
        let dest = apps.appendingPathComponent(app.lastPathComponent)
        let sig = SmartInstaller.signature(app)
        if sig == .broken {
            r.failure = "\(name) was changed after it was signed, so Kanso didn't install it."
            return r
        }
        if sig == .unsigned && !allowUnsigned {
            r.failure = "\(name) isn't signed, so Kanso didn't install it."
            return r
        }
        r.unsigned = sig == .unsigned
        let original = r.unsigned ? SmartInstaller.treeDigest(app) : nil   // before a move, so it describes the download
        if Stat.exists(dest) && !replace { r.failure = "\(name) is already installed. Nothing changed."; return r }
        let temp = apps.appendingPathComponent(".kanso-\(UUID().uuidString.prefix(8))-\(app.lastPathComponent)")
        let copied = move ? (try? FileManager.default.moveItem(at: app, to: temp)) != nil
                          : SmartInstaller.run("/usr/bin/ditto", [app.path, temp.path], timeout: 600) != nil
        let verified = r.unsigned ? (original != nil && SmartInstaller.treeDigest(temp) == original) : SmartInstaller.signatureValid(temp)
        guard copied, SmartInstaller.appInfo(temp)?.id == SmartInstaller.appInfo(move ? temp : app)?.id, verified else {
            if move, Stat.exists(temp) { try? FileManager.default.moveItem(at: temp, to: app) } else { try? FileManager.default.removeItem(at: temp) }
            r.failure = "Couldn't copy \(name) to Applications. Nothing changed."
            return r
        }
        if replace, Stat.exists(dest) {
            guard let old = trashJournaled(dest, why: "replaced by a newer \(name)", details: ["installer": name, "replaced": "1"]) else {
                try? FileManager.default.removeItem(at: temp)
                r.failure = "Couldn't move the old \(name) to the Trash. Nothing changed."
                return r
            }
            r.replaced = old
        }
        guard (try? FileManager.default.moveItem(at: temp, to: dest)) != nil else {
            try? FileManager.default.removeItem(at: temp)
            r.failure = "Couldn't put \(name) in Applications. Nothing changed."
            return r
        }
        r.installed = dest
        guard eject() else { r.failure = "Installed, but the disk image couldn't be ejected. The download was kept."; return r }
        if trashDownload, let download {
            r.trashed = trashInstaller(download, app: name, allowZip: true, unsigned: r.unsigned)
            if r.trashed == nil { r.failure = "Installed, but the download couldn't be moved to the Trash. It was kept." }
        }
        return r
    }

    /// Trash with a journal line written first (Put Back restores it). Nil when the Trash refused.
    func trashJournaled(_ url: URL, why: String, details: [String: String]) -> Action? {
        var a = Action(run: String(UUID().uuidString.prefix(8)).lowercased(), kind: .trashed, src: url.path, dst: "",
                       root: rootFor(url)?.path ?? "", shelf: "Trash", why: why, source: "Smart Installer")
        a.details = details.merging(["size": String(Stat.size(url))]) { a, _ in a }
        guard let t = trashJournaled(url, &a) else { return nil }
        a.dst = t.path
        store.append(a)   // same id: replaces the write-ahead line's entry with the Trash path
        return a
    }

    /// Moves a spent installer to the Trash and journals it (Put Back restores it).
    @discardableResult
    public func trashInstaller(_ image: URL, app: String, allowZip: Bool = false, unsigned: Bool = false) -> Action? {
        let roots = s.roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard !SmartInstaller.refuses(image, roots: roots, keepTagged: Tags.read(image).contains(s.keepTag), allowZip: allowZip) else { return nil }
        guard FileManager.default.fileExists(atPath: image.path) else { return nil }
        return trashJournaled(image, why: "installer · \(app) is installed", details: unsigned ? ["installer": app, "unsigned": "1"] : ["installer": app])
    }
}
