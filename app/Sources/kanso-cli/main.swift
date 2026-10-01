// kanso-cli: the engine without the UI, for scripts and dry runs.
// Uses the app's settings (or $KANSO_HOME).
import Foundation
import KansoCore

let args = Array(CommandLine.arguments.dropFirst())
let store = Store()
let engine = Engine(store: store)

func out(_ a: Action) {
    print("\(a.src)  ->  \(a.dst)  [\(a.why) · \(a.source)]" + (a.tags.isEmpty ? "" : "  tags=\(a.tags)"))
}

switch args.first {
case "run":
    let all = args.contains("--all"), dry = args.contains("--dry-run")
    if !dry { engine.cleanRecents() }
    let plan = await engine.plan(all: all, trigger: all ? "sort-everything" : "menu")
    if dry {
        for m in plan.moves {
            print("\(m.item.url.path)  ->  \(m.dest.path)/\(m.newName ?? m.item.name)  [\(m.why) · \(m.source)]"
                  + (m.proposedName.map { "  rename later: \($0)" } ?? ""))
        }
        print("planned \(plan.moves.count), waiting \(plan.waiting.count)")
    } else {
        let done = engine.apply(plan.moves, trigger: all ? "sort-everything" : "menu")
        done.forEach(out)
        print("moved \(done.count)")
    }
case "undo":
    let r = engine.undoLast()
    r.forEach { print("\($0.dst)  ->  \($0.src)") }
    print("restored \(r.count)")
case "status":
    let s = store.settings
    print("state: \(store.dir.path)")
    print("roots: \(s.activeRoots.map(\.path).joined(separator: ", "))")
    print("apple intelligence: \(AppleIntelligence().status)")
    print("actions: \(store.actions.count), pending renames: \(store.pending.renames.count)")
default:
    print("usage: kanso-cli run [--all] [--dry-run] | undo | status")
}
