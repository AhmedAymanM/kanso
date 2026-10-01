import Foundation

/// Smart Eject: once an app from a mounted .dmg is in /Applications, the installer is provably spent (ADR 0002):
/// the volume is ejected and the .dmg goes to the Trash, journaled and one ⌘Z away.
/// ponytail: .dmg only; .pkg installers (receipt-based) come later.
public enum SmartEject {
    /// Top-level apps on a mounted volume: bundle ID → app name.
    public static func apps(onVolume volume: URL) -> [String: String] {
        var out: [String: String] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? [] where name.hasSuffix(".app") {
            if let id = bundleID(volume.appendingPathComponent(name)) { out[id] = (name as NSString).deletingPathExtension }
        }
        return out
    }

    public static func bundleID(_ app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist) else { return nil }
        return d["CFBundleIdentifier"] as? String
    }

    /// Which of these bundle IDs are installed in `appsDir` (a reinstall of the same version counts).
    public static func installed(_ ids: Set<String>, in appsDir: URL = URL(fileURLWithPath: "/Applications")) -> Set<String> {
        var found = Set<String>()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: appsDir.path)) ?? [] where name.hasSuffix(".app") {
            if let id = bundleID(appsDir.appendingPathComponent(name)), ids.contains(id) { found.insert(id) }
        }
        return found
    }

    /// The .dmg file behind a mounted volume, from `hdiutil info`.
    public static func imagePath(forVolume volume: URL) -> URL? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["info", "-plist"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
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
