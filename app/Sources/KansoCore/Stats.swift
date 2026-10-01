import AppKit
import Foundation

public enum FolderIcon {
    /// Draws the emoji over the system folder icon and sets it as the folder's Finder icon (writes "Icon\r").
    public static func set(_ url: URL, _ emoji: String) {
        let size: CGFloat = 512
        let folder = NSWorkspace.shared.icon(for: .folder)
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            folder.draw(in: rect)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * 0.42)]
            let s = (emoji as NSString).size(withAttributes: attrs)
            (emoji as NSString).draw(at: NSPoint(x: (size - s.width) / 2, y: size * 0.40 - s.height / 2), withAttributes: attrs)
            return true
        }
        NSWorkspace.shared.setIcon(img, forFile: url.path, options: [])
    }
}

/// Local stats, computed from the journal. Nobody else sees them.
public struct Stats: Sendable {
    public var sorted = 0
    public var renamed = 0
    public var duplicates = 0
    public var duplicateBytes: Int64 = 0
    public var undone = 0
    public var total = 0
    public var undoRate: Double { total == 0 ? 0 : Double(undone) / Double(total) }

    public static func of(_ actions: [Action], in interval: DateInterval) -> Stats {
        var s = Stats()
        for a in actions where interval.contains(a.ts) && a.kind != .trashed {
            s.total += 1
            if a.undone { s.undone += 1; continue }
            switch a.kind {
            case .sorted: s.sorted += 1
            case .renamed: s.renamed += 1; s.sorted += a.src.hasPrefix(a.root + "/") && (a.src as NSString).deletingLastPathComponent == a.root ? 1 : 0
            case .duplicate: s.duplicates += 1; s.duplicateBytes += Int64(a.details["size"] ?? "") ?? 0
            case .trashed: break
            }
        }
        return s
    }

    public static func today(_ actions: [Action], now: Date = Date()) -> Stats {
        of(actions, in: Calendar.current.dateInterval(of: .day, for: now)!)
    }

    public static func month(_ actions: [Action], offset: Int = 0, now: Date = Date()) -> Stats {
        let d = Calendar.current.date(byAdding: .month, value: offset, to: now)!
        return of(actions, in: Calendar.current.dateInterval(of: .month, for: d)!)
    }
}

/// The Insights page: what Kanso did this month, from the journal and the shelves on disk.
public struct Insights: Sendable {
    public var month: Stats
    public var previous: Stats
    public var weekly: [Int] = []           // sorted per week, last 4
    public var thisWeek = 0
    public var byWeekday: [Int] = Array(repeating: 0, count: 7)   // Monday first, for the top shelf
    public var topShelf: String?
    public var topShelfCount = 0
    public var byHour: [Int] = Array(repeating: 0, count: 24)
    public var shelfGrowth: [(shelf: String, count: Int)] = []
    public var learned: [FileType] = []
    public var ruleHits: [(rule: String, shelf: String, count: Int)] = []
    public var ruleTotal = 0
    public var ruleUndos = 0
    public var reDownloads = 0
    public var otherDuplicates = 0

    public static func compute(_ actions: [Action], settings: Settings, month offset: Int = 0, now: Date = Date()) -> Insights {
        let cal = Calendar.current
        let ref = cal.date(byAdding: .month, value: offset, to: now)!
        let interval = cal.dateInterval(of: .month, for: ref)!
        var i = Insights(month: Stats.of(actions, in: interval), previous: Stats.month(actions, offset: offset - 1, now: now))
        let inMonth = actions.filter { interval.contains($0.ts) && !$0.undone && $0.kind != .trashed }

        let weekStart = cal.dateInterval(of: .weekOfYear, for: min(now, interval.end.addingTimeInterval(-1)))!.start
        i.weekly = (0..<4).reversed().map { w in
            let start = cal.date(byAdding: .weekOfYear, value: -w, to: weekStart)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            return actions.filter { $0.ts >= start && $0.ts < end && !$0.undone && $0.kind != .trashed }.count
        }
        i.thisWeek = i.weekly.last ?? 0

        var shelves: [String: Int] = [:]
        for a in inMonth { shelves[a.shelf, default: 0] += 1 }
        let top = shelves.filter { $0.key != Shelf.duplicates }.max { $0.value < $1.value }
        i.topShelf = top?.key
        i.topShelfCount = top?.value ?? 0
        for a in inMonth {
            if a.shelf == i.topShelf { i.byWeekday[(cal.component(.weekday, from: a.ts) + 5) % 7] += 1 }
            i.byHour[cal.component(.hour, from: a.ts)] += 1
        }
        i.shelfGrowth = shelves.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value) }
        i.learned = settings.types.filter(\.learned)

        var rules: [String: (String, Int)] = [:]
        for a in actions where interval.contains(a.ts) && a.why.hasPrefix("rule ") {
            i.ruleTotal += 1
            if a.undone { i.ruleUndos += 1 }
            rules[String(a.why.dropFirst(5)), default: (a.shelf, 0)].1 += 1
        }
        i.ruleHits = rules.sorted { $0.value.1 > $1.value.1 }.prefix(3).map { ($0.key, $0.value.0, $0.value.1) }

        for a in inMonth where a.kind == .duplicate {
            let kept = a.details["kept"] ?? ""
            let sameName = (kept as NSString).lastPathComponent.split(separator: ".").first.map { a.srcName.hasPrefix($0) } ?? false
            if sameName { i.reDownloads += 1 } else { i.otherDuplicates += 1 }
        }
        return i
    }

    public var busiestHour: Int? { byHour.max().flatMap { $0 > 0 ? byHour.firstIndex(of: $0) : nil } }
}

/// Size of each shelf on disk, across all watched folders.
public func shelfSizes(_ settings: Settings) -> [(shelf: String, bytes: Int64)] {
    var out: [String: Int64] = [:]
    let fm = FileManager.default
    for root in settings.activeRoots {
        let lib = root.appendingPathComponent(Library.mine)
        for shelf in (try? fm.contentsOfDirectory(atPath: lib.path)) ?? [] where !shelf.hasPrefix(".") && shelf != "Icon\r" {
            let e = fm.enumerator(at: lib.appendingPathComponent(shelf), includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles])
            var n: Int64 = 0
            while let u = e?.nextObject() as? URL { n += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
            out[shelf, default: 0] += n
        }
    }
    return out.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
}
