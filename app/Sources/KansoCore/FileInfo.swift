import Foundation

/// Metadata only: name, xattrs and stat. File contents are never opened here (iCloud placeholders never download).
public struct Item: Sendable {
    public var url: URL
    public var root: URL
    public var whereFrom: [String] = []
    public var screenshot = false
    public var isDir = false
    public var size: Int64 = 0
    public var created = Date()

    public var name: String { url.lastPathComponent }
    public var ext: String { url.pathExtension.lowercased() }
    public var stem: String { url.deletingPathExtension().lastPathComponent }
    public var fromHost: String? { whereFrom.first.flatMap { URL(string: $0)?.host } }

    public static func inspect(_ url: URL, root: URL) -> Item {
        var item = Item(url: url, root: root)
        item.whereFrom = Xattr.plist(url, "com.apple.metadata:kMDItemWhereFroms") as? [String] ?? []
        item.screenshot = Xattr.has(url, "com.apple.metadata:kMDItemIsScreenCapture")
        var st = stat()
        if lstat(url.path, &st) == 0 {
            item.isDir = (st.st_mode & S_IFMT) == S_IFDIR
            item.size = Int64(st.st_size)
            item.created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec))
        }
        return item
    }
}

public enum Xattr {
    public static func data(_ url: URL, _ name: String) -> Data? {
        let n = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard n > 0 else { return nil }
        var buf = Data(count: n)
        let r = buf.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, n, 0, XATTR_NOFOLLOW) }
        return r > 0 ? buf : nil
    }

    public static func has(_ url: URL, _ name: String) -> Bool { getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0 }

    public static func plist(_ url: URL, _ name: String) -> Any? {
        data(url, name).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
    }

    public static func setPlist(_ url: URL, _ name: String, _ value: Any) {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { return }
        _ = d.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, d.count, 0, XATTR_NOFOLLOW) }
    }
}

/// Finder tags.
public enum Tags {
    public static func read(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    public static func add(_ url: URL, _ tags: [String]) {
        let old = read(url)
        let new = old + tags.filter { t in !t.isEmpty && !old.contains { $0.caseInsensitiveCompare(t) == .orderedSame } }
        if new != old { try? (url as NSURL).setResourceValue(new, forKey: .tagNamesKey) }
    }

    public static func remove(_ url: URL, _ tags: [String]) {
        let old = read(url)
        let new = old.filter { !tags.contains($0) }
        if new != old { try? (url as NSURL).setResourceValue(new, forKey: .tagNamesKey) }
    }
}

public enum Stat {
    /// Change time: it changes when an item is moved or renamed in, which makes it the arrival time.
    public static func ctime(_ url: URL) -> TimeInterval? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return TimeInterval(st.st_ctimespec.tv_sec) + TimeInterval(st.st_ctimespec.tv_nsec) / 1e9
    }

    public static func mtime(_ url: URL) -> TimeInterval? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9
    }

    public static func isSymlink(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    public static func size(_ url: URL) -> Int64 {
        var st = stat()
        return lstat(url.path, &st) == 0 ? Int64(st.st_size) : 0
    }
}

public extension Int64 {
    var bytes: String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        return f.string(fromByteCount: self)
    }
}
