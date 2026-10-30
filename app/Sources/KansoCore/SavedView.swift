import Foundation

/// The Activity filters. The raw values are the labels the filter menu shows (and what a saved view stores).
public enum ActivityFilter: String, CaseIterable, Sendable {
    case all = "All", needs = "Needs you", handled = "Handled", renamed = "Renamed", tagged = "Tagged"
    case duplicates = "Duplicates", ejected = "Smart Eject", undone = "Undone"

    /// Does a journaled action belong under this filter? ("Needs you" holds pending items, never journal entries.)
    public func includes(_ a: Action) -> Bool {
        switch self {
        case .all, .handled: return true
        case .needs: return false
        case .renamed: return a.kind == .renamed && !a.undone
        case .tagged: return !a.tags.isEmpty && !a.undone
        case .duplicates: return (a.kind == .duplicate || (a.kind == .trashed && a.details["installer"] == nil)) && !a.undone
        case .ejected: return a.kind == .trashed && a.details["installer"] != nil
        case .undone: return a.undone
        }
    }
}

/// A named combination of Activity filters. It only changes what the list shows: a saved view never moves, renames or deletes anything.
public struct SavedView: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var filter: String = ActivityFilter.all.rawValue   // an ActivityFilter label
    public var query = ""
    public var shelf: String?    // only actions on this shelf
    public var days: Int?        // only actions from the last N days

    public init(name: String, filter: String = ActivityFilter.all.rawValue, query: String = "", shelf: String? = nil, days: Int? = nil) {
        self.name = name; self.filter = filter; self.query = query; self.shelf = shelf; self.days = days
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        filter = (try? c.decode(String.self, forKey: .filter)) ?? ActivityFilter.all.rawValue
        query = (try? c.decode(String.self, forKey: .query)) ?? ""
        shelf = try? c.decode(String.self, forKey: .shelf)
        days = try? c.decode(Int.self, forKey: .days)
    }

    /// True when the view narrows by shelf or time (beyond the filter and search).
    public var isNarrowed: Bool { shelf != nil || days != nil }

    /// The shelf and time part of the view.
    public func narrows(_ a: Action, now: Date = Date()) -> Bool {
        if let shelf, a.shelf != shelf { return false }
        if let days, now.timeIntervalSince(a.ts) > Double(days) * 86400 { return false }
        return true
    }

    /// The whole view applied to one journal action. An unknown filter label (saved by a newer build) falls back to All.
    public func includes(_ a: Action, now: Date = Date()) -> Bool {
        guard (ActivityFilter(rawValue: filter) ?? .all).includes(a), narrows(a, now: now) else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return [a.name, a.srcName, a.oldName ?? "", a.shelf, a.why].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// The same view? (name and id aside)
    public func sameFilters(as o: SavedView) -> Bool { filter == o.filter && query == o.query && shelf == o.shelf && days == o.days }
}

public extension Settings {
    static let maxSavedViews = 20

    /// Adds a view, or replaces the one with the same name (any case). Blank names are refused.
    @discardableResult
    mutating func saveView(_ v: SavedView) -> Bool {
        var v = v
        v.name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.name.isEmpty else { return false }
        if let i = savedViews.firstIndex(where: { $0.name.caseInsensitiveCompare(v.name) == .orderedSame }) {
            v.id = savedViews[i].id
            savedViews[i] = v
        } else if savedViews.count < Settings.maxSavedViews {
            savedViews.append(v)
        } else {
            return false
        }
        return true
    }
}
