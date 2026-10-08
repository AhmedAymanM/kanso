# Preview screen — the trust moment

The preview answers one question: **"If I press Apply, exactly what happens to my files?"** It is never stale, never partial without saying so, and every line is a promise Kanso keeps. Renders a `Plan` ([06](06-plan-contract.md)). Tokens: `KT.*` ([tokens](tokens/KansoDesignTokens.swift)).

## Layout (default 1000×660)

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   [📁 Downloads ▾]                                    [↶ Undo Sort]   [  Apply  ]  │ toolbar (unified)
├───────────────────────┬──────────────────────────────────────────────────────────────────┤
│ RULES            [+]  │  Kanso will move 128 of 214 files                          56pt  │ summary bar
│                       │  86 stay put · 2 will be renamed to avoid a clash                │
│ ① PDFs → Documents    ├──────────────────────────────────────────────────────────────────┤
│    41 files           │  Name                    Rule              Moves to              │ column header 24pt
│ ② Images older than   ├──────────────────────────────────────────────────────────────────┤
│    30 days → Archive  │ ▾ Documents/PDFs · 41 files                                 28pt │ group header
│    63 files           │ ☑ 📄 Invoice-03.pdf      ① PDFs            Documents/PDFs        │ row 32pt
│ ③ Names starting      │ ☑ 📄 Receipt (1).pdf     ① PDFs            Documents/PDFs        │
│    "Screenshot" →     │ ☑ 📄 report.pdf   ⚠ ①    ① PDFs            …/PDFs/report 2.pdf   │ collision
│    Screenshots        │ ▸ Archive/Images · 63 files                                      │
│    24 files           │ ▸ Stays in Downloads · 86 files                                  │ collapsed by default
│                       ├──────────────────────────────────────────────────────────────────┤
│ [+ Add Rule]          │  128 selected · 41.2 MB                       [Select None]      │ action bar 52pt
└───────────────────────┴──────────────────────────────────────────────────────────────────┘
```

- **Split view** (`NavigationSplitView`-style two-pane via `HSplitView`/`NavigationSplitView`): rules column 320pt (min 260, max 420, user-resizable, remembered), preview fills the rest. The rules column is *not* a sidebar material panel; it uses `KT.Color.window` so rules and preview read as one document.
- **Summary bar** (56pt, top of preview pane): line 1 `title2 semibold`, line 2 `callout` in `text2`. Always the first thing read; it states the total consequence in a sentence.
- **Column header** 24pt, `callout`, `text2`, sortable by Name only (default sort within a group: `localizedStandardCompare` on name).
- **Table:** SwiftUI `Table` with `.tableStyle(.inset(alternatesRowBackgrounds: false))`. Columns: **Checkbox** (28pt) · **Name** (flexible, min 220; icon 20pt + name, middle-truncated) · **Rule** (140pt, rule number badge + rule name, tail-truncated) · **Moves to** (flexible, min 180, `callout`, path relative to the chosen folder, head-truncated: `…/Documents/PDFs`).
- **Row height 32pt** — single line. The source path is *not* repeated per row (all sources are top-level files in the chosen folder); it appears in the tooltip and the VoiceOver label. This is the reason a row can stay at 32pt without truncating the name more than one would anyway.
- **Group header** 28pt, `headline`, disclosure triangle (hit target ≥ 24pt), count right-aligned in `text2`. Groups sorted: destinations A→Z, then **"Needs a look"** first when non-empty (collisions are shown inline as well, see below), **"Stays in Downloads"** last.
- **Action bar** 52pt: left = `128 selected · 41.2 MB` (live; size via `ByteCountFormatter`, `.file`); right = `Select None` / `Select All` (toggles; ⌘A when the table is focused).
- **Apply button** in the toolbar, `.borderedProminent`, default action (⏎), label "Apply" with a count suffix once selected < total: `Apply 120 Moves`. Disabled with nothing selected.

## Row anatomy and states

| Row kind | Appearance | Notes |
|---|---|---|
| **Will move** | ☑ checkbox, icon, name, rule badge (`KT.Color.rule` pastel w/ number in ink), destination | the normal row |
| **Excluded** (user unchecked) | name and destination `text2`, strikethrough **not** used; rule column reads "Skipped by you"; row moves *within its group*, does not jump | unchecking is the per-file brake |
| **Renamed to avoid a clash** | amber `KT.Color.attention` capsule badge `Renamed` (18pt high) after the name; Moves-to shows the *final* name: `…/PDFs/report 2.pdf` | collision resolved by keeping both; see below |
| **Stays — no rule matched** | in the "Stays in Downloads" group; no checkbox; rule column `—`; text `text2` | collapsed by default; ⌘⇧H toggles show |
| **Stays — already in place** | same group; Moves-to column: "Already in Documents/PDFs" | |
| **Stays — protected** | same group; reason text: "Folder", "Still downloading", "In iCloud, not downloaded", "Tagged Keep" | one short reason from `StayReason` |
| **Blocked** | rose `KT.Color.blocked` badge `Can't move`, reason in Moves-to column, no checkbox; counted in the summary | detected at plan time when possible, otherwise shown after Apply |

### Collisions (the moment people lose trust)
- **Policy, not a dialog:** if the destination already has a file with that name — or two planned files want the same name — the incoming file is kept under a new name (`report 2.pdf`, `report 3.pdf`). **Kanso never overwrites and never silently skips.** No choice needed, so no prompt.
- The row shows the *final* name and the `Renamed` badge; hover tooltip: "A file named “report.pdf” is already in Documents/PDFs. This file will be saved as “report 2.pdf”."
- Summary line 2 counts them: "2 will be renamed to avoid a clash". Clicking that phrase (it's a link-styled button) scrolls to and selects the first such row.

### Selecting a rule highlights its files
Selecting a rule in the left column (single click) applies a **filter chip** above the table: `Showing rule ② · Images older than 30 days  ✕`, and the table shows only that rule's moves. Esc or ✕ clears. This is how a user verifies "what exactly does this rule do?" without running anything. Cost is trivial (filter on `ruleID`).

## Summary bar copy (exact)

| Condition | Line 1 | Line 2 |
|---|---|---|
| normal | `Kanso will move {n} of {total} files` | `{stay} stay put` + (` · {c} will be renamed to avoid a clash` if c>0) + (` · {b} can't be moved` if b>0) |
| n == total | `Kanso will move all {total} files` | as above |
| some unchecked | `Kanso will move {sel} of {total} files` | `{u} skipped by you · {stay} stay put …` |
| n == 0, rules exist | `Nothing to move` | `None of the {total} files match your rules.` |
| n == 0, no rules | `Add a rule to see what Kanso would do` | `Rules decide where files go. Nothing moves until you press Apply.` |
| scan partial | `Kanso will move {n} of {total}+ files` | `Some items couldn't be read. Showing {total} of them.` + link `Details` |
| recomputing | (previous text, dimmed) | |
| applying | `Moving {done} of {sel}…` | `You can stop at any time. Everything moved so far can be undone.` |
| applied | `Moved {m} files` (+` · {f} couldn't be moved`) | `Undo puts them all back.` ← **Undo** button right-aligned, `.bordered`, same height as title line |
| undone | `Put {m} files back` | `Everything is where it was.` |

Pluralization: "1 file", "{n} files" (use `String(localized:)` with plural variants).

## Interactions
- **Click row** selects (standard); **Space** toggles checkbox on selected row(s); **⌘A** all rows; checkbox column header toggles all in view.
- **Group checkbox** (tri-state, in group header, 28pt hit area) toggles the whole group.
- **Double-click row / ⌘R** reveals the source file in Finder (`NSWorkspace.activateFileViewerSelecting`). Context menu: `Reveal in Finder`, `Skip This File` / `Include This File`, `Edit Rule “PDFs”…`, `Copy Path`.
- **Quick Look:** Space is toggle, so Quick Look = ⌘Y (standard in Finder-like lists) — shows `QLPreviewPanel` for the source file.
- **Drag** out of the preview is not supported in v1.
- **Esc** clears the rule filter; while applying, **Esc = Stop**.

## Motion
- Rule edit → list diff: rows that appear/disappear fade 0.22s (`KT.Motion.standard`); groups never reorder animated. **Reduce Motion:** no animation, instant swap.
- Apply: each row's checkbox swaps to a mint ✓ (cross-fade 0.12s) as its move completes; the list does not reflow during apply (rows stay until the run ends, then groups recompute to "Moved" receipt view).
- Never use spring/bounce. No confetti, no celebratory animation on completion — the product is quiet.

## Receipt view (after Apply, S4)
The same table re-labelled: Name · Rule · "Moved to". Unmoved rows (failures) float to the top group "Couldn't be moved" with the reason. Each moved row has context action `Put Back` (single-file undo), the global **Undo** returns everything. Receipt stays until the user edits a rule or chooses Sort Again (⌘R is Reveal, so Sort Again = ⇧⌘R).

## What is deliberately not here
No confirmation sheet, no "are you sure?", no counts-only view, no before/after tree diagram, no per-row overwrite/skip chooser, no dry-run toggle (preview is always on), no sort-by-column beyond Name. Each would add a decision the product can make for the user.
