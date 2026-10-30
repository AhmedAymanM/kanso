import Foundation

/// What the island says after a run the user started (Sort now, Sort everything, Rename all): one line and one Undo for the whole run.
public struct BatchSummary: Equatable, Sendable {
    public var run: String
    public var text: String
    public var count: Int
}

public enum Batch {
    /// Fewer than this and the per-file notices already say everything.
    public static let minimum = 2

    /// nil for automatic runs (plain sorts stay silent, PRODUCT.md) and for runs too small to need a card.
    public static func summary(_ done: [Action], trigger: String) -> BatchSummary? {
        guard trigger != "auto" else { return nil }
        let live = done.filter { !$0.undone }
        guard live.count >= minimum, let run = live.first?.run else { return nil }
        func dir(_ p: String) -> String { (p as NSString).deletingLastPathComponent }
        let renamed = live.filter { $0.kind == .renamed }.count
        let moved = live.filter { $0.kind == .sorted || ($0.kind == .renamed && dir($0.src) != dir($0.dst)) }.count
        // A duplicate sent straight to the Trash is journaled as a duplicate whose shelf is "Trash".
        let inTrash: (Action) -> Bool = { $0.kind == .trashed || ($0.kind == .duplicate && $0.shelf == "Trash") }
        let copies = live.filter { $0.kind == .duplicate && !inTrash($0) }.count
        let trashed = live.filter(inTrash).count
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        var parts: [String] = []
        if moved > 0 { parts.append("sorted \(count(moved, "file", "files"))") }
        if renamed > 0 { parts.append("renamed \(moved > 0 ? String(renamed) : count(renamed, "file", "files"))") }
        if copies > 0 { parts.append("held \(count(copies, "copy", "copies"))") }
        if trashed > 0 { parts.append("moved \(count(trashed, "copy", "copies")) to Trash") }
        guard let first = parts.first else { return nil }
        let text = first.prefix(1).uppercased() + first.dropFirst() + parts.dropFirst().map { ", " + $0 }.joined()
        return BatchSummary(run: run, text: text, count: live.count)
    }
}
