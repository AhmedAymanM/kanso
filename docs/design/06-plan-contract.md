# Plan contract (engine ↔ preview)

The engine emits one `Plan`; the preview renders it and nothing else. The UI never recomputes matching. Proposed to Forge; shapes follow the existing `Planned`/`Plan`/`Rule` types in `app/Sources/KansoCore`. **Status: proposal, needs Forge's sign-off (KAN-2 comment).**

```swift
struct Plan {
    let id: UUID
    let folder: URL                 // the folder the user picked
    let generatedAt: Date
    let rules: [RuleSummary]        // in priority order; drives the rule column's counts
    let items: [PlanItem]           // EVERY top-level item scanned, including the ones that stay
    let scan: ScanState             // .complete | .partial(reason)  (e.g. unreadable subfolder, 5k cap hit)
}

struct RuleSummary {
    let ruleID: UUID
    let matched: Int                // files this rule will move
    let shadowed: Int               // files it WOULD match but an earlier rule took them
    let invalid: RuleProblem?       // e.g. .emptyValue, .destinationOutsideFolder
}

struct PlanItem: Identifiable {
    let id: UUID
    let source: URL
    let isFolder: Bool              // v1: folders are listed as .stays(.folder); never moved
    let size: Int64
    let dateAdded: Date, dateModified: Date, dateCreated: Date
    let outcome: Outcome
}

enum Outcome {
    case moves(Move)
    case stays(StayReason)          // .noRuleMatched | .alreadyInPlace | .folder | .hidden | .keepTag | .downloading | .cloudPlaceholder
    case blocked(BlockReason)       // .noPermission | .locked | .sourceVanished  — decided at plan time when detectable
}

struct Move {
    let ruleID: UUID
    let destinationFolder: URL      // absolute, inside `folder`
    let finalName: String           // == source name unless a collision forced a rename
    let collision: Collision?       // nil = clean
}

enum Collision {
    case existsAtDestination(existing: URL)     // a file with that name is already there
    case sameNameInPlan(with: UUID)             // two planned moves want the same final path
    // Resolution is NOT user-selectable in v1: always keep both, rename the incoming file "name 2.ext", "name 3.ext"…
    // `finalName` already holds the resolved name. Kanso never overwrites and never skips silently.
}
```

```swift
// Apply + undo
func apply(_ plan: Plan, excluding: Set<UUID>) -> AsyncStream<ApplyEvent>   // .moved(id) .failed(id, reason) .finished(RunSummary)
struct RunSummary { let runID: UUID; let moved: Int; let failed: [(UUID, BlockReason)]; let completed: Bool }
func undo(run: UUID) -> UndoResult      // .restored(n) / .partial(restored: n, conflicts: [(URL, resolvedName)])
func interruptedRun() -> RunSummary?    // journal has a run without a completion marker (crash, force-quit, power loss)
```

Requirements the design depends on:
1. **Journal write-ahead:** a journal line is written *before* each move and marked done after. Then an interrupted run is always fully undoable.
2. **Undo is by run**, whole or per-file ("Put back" on a row in the post-apply list). Restoring onto a taken name keeps both (`name 2.ext`) and reports it.
3. **Deterministic plan:** same folder + same rules + same disk state → same plan (stable sort: destination, then name, `localizedStandardCompare`).
4. **`generatedAt` and a folder fingerprint** (item count + newest mtime): Apply re-checks each source still exists and is unchanged; a changed file becomes `.failed(.sourceVanished)`, never a wrong move.
5. **Rule model additions** (Settings.swift today has name/ext/from/size): add a `date` field (`dateAdded|dateModified|dateCreated` with operators below). `from` and `size` stay in the engine but are **not exposed in v1 UI**.
6. **Cost target:** plan for 5,000 items in ≤ 300 ms on M-series so live recompute after each rule edit feels instant. If the engine can't, the cheap version: recompute on edit-commit (popover close / Return) instead of per keystroke.
