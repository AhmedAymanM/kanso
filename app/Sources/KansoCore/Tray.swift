import Foundation

// The Tray (PRODUCT.md §7, final-direction.md "The Tray (v1)"): a place on the island to collect files, links and text,
// then take them somewhere (drag out, share). It never sorts or moves anything on its own: no Organize.

/// One thing in the Tray. Files are references (path + bookmark, so a file moved meanwhile is still found), never copied,
/// except browser images and Mail attachments (file promises), which are saved as Kanso's own temporary copies.
public struct TrayItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, link, snippet }
    public var id = UUID()
    public var kind: Kind
    public var path = ""            // file: where it is; link: the URL; snippet: unused
    public var bookmark: Data?
    public var text = ""            // snippet text
    public var temporary = false    // a saved file promise in the Tray folder: deleted once it leaves the Tray
    public var added = Date()

    public init(kind: Kind, path: String = "", bookmark: Data? = nil, text: String = "", temporary: Bool = false) {
        self.kind = kind; self.path = path; self.bookmark = bookmark; self.text = text; self.temporary = temporary
    }

    /// The name under the tile: untrusted, so control characters are stripped and it's capped at 120.
    public var name: String {
        switch kind {
        case .file: return TrayStore.clean((path as NSString).lastPathComponent)
        case .link: return TrayStore.clean(URL(string: path)?.host ?? path)
        case .snippet: return TrayStore.clean(text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Text")
        }
    }
}

/// What an add did.
public struct TrayAdd: Sendable, Equatable {
    public var added: [UUID] = []
    public var already = 0
    public var refused: [String] = []   // user-facing reasons
    public init() {}
}

/// `tray.json` (references, links, snippets) at mode 0600, excluded from backup; temporary copies in `Tray/` beside it
/// (0700, excluded from backup and Spotlight). Newest first. Removing keeps the last removal for ⌘Z; a temporary copy
/// is deleted only once ⌘Z can no longer bring it back (the next removal, `closeUndo()`, or launch).
public final class TrayStore: @unchecked Sendable {
    public static let cap = 100
    public static let snippetCap = 500_000
    private let lock = NSLock()
    private let saveLock = NSLock()
    private let url: URL
    public let scratch: URL           // where temporary copies live
    private var list: [TrayItem]
    private var undo: [TrayItem] = []  // the last removal

    public init(dir: URL) {
        url = dir.appendingPathComponent("tray.json")
        scratch = dir.appendingPathComponent("Tray", isDirectory: true)
        list = TrayStore.load(url)
        cleanLeftovers()
    }

    static func load(_ url: URL) -> [TrayItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bad"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bad"))
            return []
        }
        var out: [TrayItem] = []
        for el in raw {   // element by element: one bad entry never loses the rest
            guard let d = try? JSONSerialization.data(withJSONObject: el), let item = try? Store.decoder.decode(TrayItem.self, from: d),
                  item.kind != .file || item.path.hasPrefix("/"), !out.contains(where: { $0.id == item.id }) else { continue }
            out.append(item)
        }
        return Array(out.prefix(cap))
    }

    public var items: [TrayItem] { lock.lock(); defer { lock.unlock() }; return list }

    /// Control characters out, 120 characters at most.
    public static func clean(_ s: String) -> String {
        String(String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(120))
    }

    static func canon(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    // MARK: Adding

    /// Files and folders by reference. Missing paths and symlinks are refused; duplicates are counted, not added.
    @discardableResult
    public func add(files urls: [URL], temporary: Bool = false) -> TrayAdd {
        var r = TrayAdd()
        var fresh: [TrayItem] = []
        for u in urls {
            let f = URL(fileURLWithPath: u.path)
            guard u.isFileURL, Stat.exists(f) else { r.refused.append("\(TrayStore.clean(u.lastPathComponent)) isn't on this Mac."); continue }
            guard !Stat.isSymlink(f) else { r.refused.append("\(TrayStore.clean(f.lastPathComponent)) is a link to another file."); continue }
            fresh.append(TrayItem(kind: .file, path: f.path, bookmark: try? f.bookmarkData(), temporary: temporary))
        }
        insert(fresh, &r) { item, list in list.contains { $0.kind == .file && TrayStore.canon($0.path) == TrayStore.canon(item.path) } }
        return r
    }

    /// http and https links only (never file: or javascript:).
    @discardableResult
    public func add(links: [URL]) -> TrayAdd {
        var r = TrayAdd()
        let ok = links.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil }
        r.refused += links.filter { !ok.contains($0) }.map { _ in "Only web links can go in the Tray." }
        insert(ok.map { TrayItem(kind: .link, path: $0.absoluteString) }, &r) { item, list in list.contains { $0.kind == .link && $0.path == item.path } }
        return r
    }

    /// Text, up to 500 KB per snippet.
    @discardableResult
    public func add(text: String) -> TrayAdd {
        var r = TrayAdd()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return r }
        guard t.utf8.count <= TrayStore.snippetCap else { r.refused.append("That text is too long for the Tray (500 KB at most)."); return r }
        insert([TrayItem(kind: .snippet, text: t)], &r) { item, list in list.contains { $0.kind == .snippet && $0.text == item.text } }
        return r
    }

    private func insert(_ fresh: [TrayItem], _ r: inout TrayAdd, isDuplicate: (TrayItem, [TrayItem]) -> Bool) {
        lock.lock()
        for item in fresh {
            if isDuplicate(item, list) { r.already += 1; continue }
            if list.count >= TrayStore.cap { r.refused.append("The Tray holds \(TrayStore.cap) things at most."); break }
            list.insert(item, at: 0)
            r.added.append(item.id)
        }
        lock.unlock()
        if !r.added.isEmpty { save() }
    }

    // MARK: Temporary copies (file promises)

    /// A fresh folder for one saved promise: `Tray/<uuid>/`, so names never collide.
    public func promiseFolder() throws -> URL {
        try prepareScratch()
        let f = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return f
    }

    /// A saved promise joins the Tray as a temporary copy, with the quarantine flag set like any download.
    @discardableResult
    public func adopt(saved file: URL) -> TrayAdd {
        TrayStore.quarantine(file)
        return add(files: [file], temporary: true)
    }

    func prepareScratch() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scratch.path)
        var s = scratch; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? s.setResourceValues(v)
        let never = scratch.appendingPathComponent(".metadata_never_index")   // Spotlight skips the folder
        if !fm.fileExists(atPath: never.path) { fm.createFile(atPath: never.path, contents: nil) }
    }

    /// `com.apple.quarantine`, so Gatekeeper treats a saved attachment like a download.
    public static func quarantine(_ file: URL) {
        let value = String(format: "0081;%08x;Kanso;", Int(Date().timeIntervalSince1970))
        _ = value.withCString { setxattr(file.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    /// Inside the Tray folder, after resolving links: the only place Kanso ever deletes from.
    func isScratch(_ path: String) -> Bool {
        let root = TrayStore.canon(scratch.path) + "/"
        return TrayStore.canon(path).hasPrefix(root)
    }

    /// Deletes a temporary copy (its `Tray/<uuid>/` folder). Never touches anything outside the Tray folder.
    func deleteCopy(_ item: TrayItem) {
        guard item.kind == .file, item.temporary, isScratch(item.path) else { return }
        let folder = URL(fileURLWithPath: item.path).deletingLastPathComponent()
        let target = isScratch(folder.path) && TrayStore.canon(folder.path) != TrayStore.canon(scratch.path) ? folder : URL(fileURLWithPath: item.path)
        try? FileManager.default.removeItem(at: target)
    }

    /// Launch and "Forget everything": folders in `Tray/` no item points to are leftovers.
    public func cleanLeftovers() {
        lock.lock(); let keep = Set((list + undo).filter(\.temporary).map { TrayStore.canon(URL(fileURLWithPath: $0.path).deletingLastPathComponent().path) }); lock.unlock()
        for f in (try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent != ".metadata_never_index" {
            if !keep.contains(TrayStore.canon(f.path)) { try? FileManager.default.removeItem(at: f) }
        }
    }

    // MARK: Removing and undo

    /// Takes items off the Tray (files stay where they are). The removal is kept for ⌘Z; the previous removal's
    /// temporary copies are deleted now, because ⌘Z can no longer reach them.
    @discardableResult
    public func remove(_ ids: Set<UUID>) -> [TrayItem] {
        lock.lock()
        let gone = list.filter { ids.contains($0.id) }
        list.removeAll { ids.contains($0.id) }
        let expired = gone.isEmpty ? [] : undo
        if !gone.isEmpty { undo = gone }
        lock.unlock()
        expired.forEach(deleteCopy)
        if !gone.isEmpty { save() }
        return gone
    }

    public func clear() { remove(Set(items.map(\.id))) }

    /// ⌘Z: the last removal comes back.
    @discardableResult
    public func restoreLast() -> [TrayItem] {
        lock.lock()
        let back = undo.filter { item in !list.contains { $0.id == item.id } }
        list = (back + list).sorted { $0.added > $1.added }
        undo = []
        lock.unlock()
        if !back.isEmpty { save() }
        return back
    }

    public var canUndo: Bool { lock.lock(); defer { lock.unlock() }; return !undo.isEmpty }

    /// The island closed or the app quits: ⌘Z is over, so removed temporary copies go.
    public func closeUndo() {
        lock.lock(); let expired = undo; undo = []; lock.unlock()
        expired.forEach(deleteCopy)
    }

    // MARK: Where things are

    /// The file's current location: the bookmark follows a move or rename. nil when it's gone.
    public func resolve(_ item: TrayItem) -> URL? {
        guard item.kind == .file else { return nil }
        let here = URL(fileURLWithPath: item.path)
        if Stat.exists(here) { return here }
        var stale = false
        guard let data = item.bookmark,
              let u = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
              Stat.exists(URL(fileURLWithPath: u.path)) else { return nil }
        lock.lock()
        if let i = list.firstIndex(where: { $0.id == item.id }) { list[i].path = u.path }
        lock.unlock()
        save()
        return URL(fileURLWithPath: u.path)
    }

    private func save() {
        saveLock.lock(); defer { saveLock.unlock() }
        lock.lock(); let snapshot = list; lock.unlock()
        guard let data = try? Store.encoder.encode(snapshot) else { return }
        var u = url
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: u, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            try u.setResourceValues(v)
        } catch { NSLog("Kanso: tray write failed: \(error)") }
    }

    /// "Forget everything": the list, the undo, and every temporary copy.
    public func wipe() {
        saveLock.lock(); defer { saveLock.unlock() }
        lock.lock(); list = []; undo = []; lock.unlock()
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: scratch)
    }
}

// MARK: Selection (like Finder)

/// Which tiles are selected. Pure, so every Finder gesture is testable: click, ⌘-click, ⇧-click, ⌘A, arrows in a grid,
/// ⇧-arrows, and a marquee.
public struct TraySelection: Equatable, Sendable {
    public var selected: Set<Int> = []
    public var anchor: Int?           // where ⇧-click and ⇧-arrows extend from
    public var focus: Int?            // the last tile touched
    public init() {}

    public mutating func click(_ i: Int, command: Bool = false, shift: Bool = false) {
        if shift, let a = anchor {
            selected = command ? selected.union(range(a, i)) : Set(range(a, i))
        } else if command {
            if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
            anchor = i
        } else {
            selected = [i]; anchor = i
        }
        focus = i
    }

    public mutating func all(_ count: Int) { selected = Set(0..<count); anchor = 0; focus = count > 0 ? count - 1 : nil }

    public mutating func clear() { selected = []; anchor = nil; focus = nil }

    /// Arrows: ← → by one, ↑ ↓ by a row of `columns`; ⇧ extends from the anchor.
    public mutating func move(by d: Int, count: Int, extend: Bool = false) {
        guard count > 0 else { return }
        let from = focus ?? (d > 0 ? -1 : count)
        let to = min(max(from + d, 0), count - 1)
        if extend, let a = anchor { selected = Set(range(a, to)) } else { selected = [to]; anchor = to }
        focus = to
    }

    /// A dragged rectangle: the tiles it touches (⌘ adds them to the selection).
    public mutating func marquee(_ hits: Set<Int>, adding: Bool = false) {
        selected = adding ? selected.union(hits) : hits
        anchor = hits.min(); focus = hits.max()
    }

    /// Keep indexes valid after the list changed.
    public mutating func clamp(_ count: Int) {
        selected = selected.filter { $0 < count }
        if let f = focus, f >= count { focus = count > 0 ? count - 1 : nil }
        if let a = anchor, a >= count { anchor = focus }
    }

    private func range(_ a: Int, _ b: Int) -> ClosedRange<Int> { min(a, b)...max(a, b) }
}

// MARK: Link previews (only after the safety check)

/// The rule a link must pass before Kanso fetches anything from it: https, a public host (never loopback, link-local,
/// private, carrier-grade NAT, multicast or `.local`), checked again on every redirect.
public enum LinkSafety {
    public static func allowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty,
              !host.hasSuffix(".local"), host != "localhost", !host.hasSuffix(".localhost") else { return false }
        let addrs = resolve(host)
        return !addrs.isEmpty && addrs.allSatisfy(isPublic)
    }

    /// Every address the host resolves to (A and AAAA), as text.
    static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(first) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let a = p {
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a.pointee.ai_addr, a.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 { out.append(String(cString: buf)) }
            p = a.pointee.ai_next
        }
        return out
    }

    /// True for addresses on the public internet only.
    public static func isPublic(_ ip: String) -> Bool {
        let s = ip.lowercased().split(separator: "%").first.map(String.init) ?? ip
        if s.contains(":") {   // IPv6
            if s == "::" || s == "::1" { return false }
            if s.hasPrefix("fe8") || s.hasPrefix("fe9") || s.hasPrefix("fea") || s.hasPrefix("feb") { return false }   // link-local
            if s.hasPrefix("fc") || s.hasPrefix("fd") { return false }   // unique local
            if s.hasPrefix("ff") { return false }                        // multicast
            if s.hasPrefix("::ffff:") { return isPublic(String(s.dropFirst(7))) }   // IPv4-mapped
            if s.hasPrefix("64:ff9b::") { return isPublic(String(s.dropFirst(9))) }
            return true
        }
        let o = s.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4, o.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (255, _): return false
        case (172, 16...31), (100, 64...127), (198, 18...19): return false
        case (224...239, _): return false
        default: return true
        }
    }
}

/// What a link preview shows: the page title and, when there is one, its image.
public struct LinkPreview: Equatable, Sendable {
    public var title: String?
    public var image: URL?

    /// `og:title`, else `<title>`; `og:image` (made absolute). Only the start of the page is ever looked at.
    public static func parse(_ html: String, base: URL) -> LinkPreview {
        func meta(_ prop: String) -> String? {
            for pattern in ["<meta[^>]+(?:property|name)=[\"']\(prop)[\"'][^>]*content=[\"']([^\"']+)[\"']", "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(prop)[\"']"] {
                if let r = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                   let m = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive).firstMatch(in: html, range: NSRange(r, in: html)),
                   let g = Range(m.range(at: 1), in: html) { return String(html[g]) }
            }
            return nil
        }
        var title = meta("og:title")
        if title == nil, let r = html.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]) {
            title = String(html[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        let decoded = title.map { $0.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines) }
        let image = meta("og:image").flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
        return LinkPreview(title: decoded.flatMap { $0.isEmpty ? nil : TrayStore.clean($0) }, image: image)
    }
}

/// Fetches under the safety rules: https to a public host, re-checked on each of at most 3 redirects, 1 MB and 5 s
/// caps, no cookies, no cache, no Referer.
public final class SafeFetcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public static let shared = SafeFetcher()
    public static let maxBytes = 1_000_000
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never; c.httpShouldSetCookies = false; c.urlCache = nil
        c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 5
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    private var redirects: [Int: Int] = [:]
    private let lock = NSLock()

    public func fetch(_ url: URL) async -> Data? {
        guard LinkSafety.allowed(url) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Kanso", forHTTPHeaderField: "User-Agent")
        guard let (bytes, resp) = try? await session.bytes(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        var data = Data()
        do { for try await b in bytes { data.append(b); if data.count > SafeFetcher.maxBytes { return nil } } } catch { return nil }
        return data
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); let n = (redirects[task.taskIdentifier] ?? 0) + 1; redirects[task.taskIdentifier] = n; lock.unlock()
        guard n <= 3, let u = request.url, LinkSafety.allowed(u) else { completionHandler(nil); return }
        var r = request; r.setValue(nil, forHTTPHeaderField: "Referer")
        completionHandler(r)
    }

    /// The page's preview, or nil when it fails any rule.
    public func preview(_ url: URL) async -> (LinkPreview, Data?)? {
        guard let data = await fetch(url), let html = String(data: data.prefix(200_000), encoding: .utf8) ?? String(data: data.prefix(200_000), encoding: .isoLatin1) else { return nil }
        let p = LinkPreview.parse(html, base: url)
        let image = await p.image.asyncFlatMap { $0.scheme == "https" ? await fetch($0) : nil }
        return (p, image)
    }
}

extension Optional {
    func asyncFlatMap<U>(_ f: (Wrapped) async -> U?) async -> U? { if let w = self { return await f(w) }; return nil }
}
