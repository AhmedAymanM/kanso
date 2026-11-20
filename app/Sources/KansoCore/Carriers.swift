import Foundation

/// Carriers (CONTEXT.md): files whose job ends once used. These checks decide when one is done with: an archive whose
/// contents were extracted next to it, a torrent a torrent app opened. Metadata only; nothing reads file contents.
public enum Carriers {
    /// What an archive extracted to, with both name lists (logged for the dogfood check, PRODUCT.md §9).
    public struct Extraction: Equatable, Sendable {
        public var archive: URL
        public var sibling: URL             // the extracted file or folder next to the archive
        public var listing: [String]        // the archive's top-level names
        public var found: [String]          // what the sibling holds (or its own name, for one top-level item)
    }

    /// Top-level names inside a zip (from `zipinfo -1`; resource forks under __MACOSX are left out). Nil when it
    /// isn't a zip Kanso can list.
    public static func listing(_ zip: URL) -> [String]? {
        guard zip.pathExtension.lowercased() == "zip",
              let data = SmartInstaller.run("/usr/bin/zipinfo", ["-1", zip.path], timeout: 20),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var seen: [String] = []
        for line in text.split(separator: "\n") {
            guard let first = line.split(separator: "/").first.map(String.init), first != "__MACOSX", !first.hasPrefix("._"), !seen.contains(first) else { continue }
            seen.append(first)
        }
        return seen.isEmpty ? nil : seen
    }

    /// Archive Utility puts a single top-level item right next to the archive and several into a folder named after it.
    /// The extraction counts only when that sibling exists and holds every top-level name.
    public static func extraction(of zip: URL) -> Extraction? {
        guard let names = listing(zip) else { return nil }
        let dir = zip.deletingLastPathComponent()
        if names.count == 1 {
            let sibling = dir.appendingPathComponent(names[0])
            return Stat.exists(sibling) ? Extraction(archive: zip, sibling: sibling, listing: names, found: [names[0]]) : nil
        }
        let folder = dir.appendingPathComponent(zip.deletingPathExtension().lastPathComponent)
        guard let inside = try? FileManager.default.contentsOfDirectory(atPath: folder.path), Set(names).isSubset(of: Set(inside)) else { return nil }
        return Extraction(archive: zip, sibling: folder, listing: names, found: inside.sorted())
    }

    /// When the file was last opened, from the `com.apple.lastuseddate#PS` xattr (a 16-byte timespec that Launch
    /// Services writes on open). Nil when it was never opened. Access time is never used: Kanso's own reads move it.
    public static func lastUsed(_ url: URL) -> Date? {
        guard let d = Xattr.data(url, "com.apple.lastuseddate#PS"), d.count >= 16 else { return nil }
        let sec = d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int64.self) }
        let nsec = d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int64.self) }
        return sec > 0 ? Date(timeIntervalSince1970: TimeInterval(sec) + TimeInterval(nsec) / 1e9) : nil
    }

    /// A torrent counts as opened once something opened it after it arrived.
    public static func torrentOpened(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "torrent", let used = lastUsed(url) else { return false }
        let born = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return used > born
    }
}

extension Engine {
    /// "Trash the zip" / "Trash it": a carrier the user said they're done with, journaled (Put Back restores it).
    /// Refuses Manual Shelves and Keep-tagged files.
    @discardableResult
    public func trashCarrier(_ url: URL, kind: String) -> Action? {
        guard !url.standardizedFileURL.pathComponents.contains(Library.manual), !Tags.read(url).contains(s.keepTag) else { return nil }
        return trashJournaled(url, why: kind == "torrent" ? "torrent · opened" : "archive · extracted", details: ["carrier": kind])
    }
}
