# Core flow — pick a folder → rules → preview → apply → undo

Kanso v1 is a **single-window** app (one `WindowGroup` window, standard title bar, no menu bar extra required for this loop). The loop is one screen, not a wizard: rules and preview sit side by side so every rule change shows its consequence immediately. Window default 1000×660, min 800×520, resizable, standard traffic lights, toolbar style `.unified`.

> **Scope flag for the CEO (see README):** the repo's shipped app is an automatic, menu-bar type sorter. This flow is the manual, rule-driven, preview-first loop from the company goal. The two can share the engine; they do not share a front door. Needs a decision before CTO builds UI.

## Screen map

```
┌ toolbar ──────────────────────────────────────────────────────────────────────┐
│ [Downloads ▾]  ~/Downloads                         [Undo Sort ⌘Z]  [Apply ⏎] │
├ rules (320) ───────────┬ preview ─────────────────────────────────────────────┤
│ RULES            [+]   │ Will move 128 of 214 files          86 stay · 2 notes │
│ 1 PDFs → Documents/PDF │ ▾ Documents/PDF          41 files                     │
│ 2 Images older than…   │    ☑ Invoice-03.pdf    Rule 1     (from Downloads)    │
│ …                      │ ▸ Archive/Images         63 files                     │
└────────────────────────┴───────────────────────────────────────────────────────┘
```

Detail of each region: [02-preview-screen.md](02-preview-screen.md), [03-rule-editor.md](03-rule-editor.md).

## States

| # | State | What the user sees | Exits |
|---|---|---|---|
| S0 | **Welcome** (no folder yet) | Centered: app icon 64pt, headline, one button | Choose Folder… → S1 |
| S1 | **Scanning** | Rules column visible (default rules, see below); preview shows indeterminate `ProgressView` + "Reading 'Downloads'…". Scan > 400 ms shows spinner; < 400 ms never flashes it | → S2, S5, S6 |
| S2 | **Preview** (the home state) | Summary + grouped moves; Apply enabled | edit rule → S2′; Apply → S3 |
| S2′ | **Recomputing** | Old list stays, dims to 60% opacity after 250 ms; no spinner; swaps atomically when the new plan lands | → S2 |
| S3 | **Applying** | Apply becomes **Stop**; summary line becomes "Moving 41 of 128…"; determinate progress bar in the action bar; rows tick off in place (☑ → ✓ mint) | complete → S4; Stop/Esc → S4 (partial); crash → S7 |
| S4 | **Applied** | Summary: "Moved 128 files." + **Undo** button (prominent, in the summary bar, not a toast). Rows show final locations; the list is the receipt. Rules locked-looking? No: editable; editing starts a new preview of what's *left* | Undo → S8; edit rule/Sort Again → S2 |
| S5 | **Nothing to do** | folder scanned, no moves: see [04](04-unhappy-paths.md) | |
| S6 | **Cannot read** | permission | |
| S7 | **Interrupted** (found at next launch) | banner, see [04](04-unhappy-paths.md) | |
| S8 | **Undone** | Summary: "Put 128 files back." Files shown in their original place; Apply available again (same plan recomputed) | → S2 |

### Principles applied
- **No confirmation dialog anywhere.** Apply is safe because (a) the preview already showed everything, (b) nothing is ever overwritten or deleted, (c) the whole run is one Undo.
- **Undo is in three places, all the same action:** the summary bar button (S4), Edit ▸ Undo Sort (⌘Z), toolbar Undo Sort. ⌘Z undoes the last applied run as long as the app is open *and* across launches via the journal (title adapts: "Undo Sort of 12 Oct, 14:02").
- **First launch rules:** start with **zero rules** and a one-line empty state offering "Add Rule" and "Start with suggestions". Suggestions = 3 pre-filled, editable, not applied until the user keeps them: PDFs → `PDFs`, Images → `Images`, Installers (dmg, pkg) → `Installers`. Rationale: an empty preview teaches nothing, but silent default rules would be a destructive surprise.

## The loop, step by step

1. **Pick a folder.** Welcome screen or toolbar pop-up `Downloads ▾`. Button opens `NSOpenPanel` (`canChooseDirectories`, no files, prompt "Choose", message "Choose a folder for Kanso to sort. Kanso only touches files directly inside it."). The grant is stored as a security-scoped bookmark; the pop-up lists up to 5 recent folders plus "Choose Folder…" (⌘O). Dropping a folder on the window or Dock icon is equivalent.
2. **Define rules.** Rule list in the left column; `+` adds a rule and opens its editor popover immediately. Rules are ordered; **first match wins**; reorder by drag, or ⌥⌘↑/↓. A rule reads as one sentence (see 03).
3. **Preview.** Always on. There is no "Preview" button: the preview *is* the main pane and is never stale (S2′). Nothing in the app touches disk before step 4.
4. **Apply.** `Apply` (⏎ when the window is key and focus is not in a text field; also File ▸ Apply Sort, ⌘⏎ always). Apply moves only checked rows. Per-file failures do not stop the run.
5. **Undo.** See above. Undo moves each file back by the journal, restoring original names. If something else now occupies the original name, the returning file is kept as `name 2.ext` and the summary says so.

## Menu bar (standard, not custom)
File: Choose Folder… ⌘O · Open Recent ▸ · Apply Sort ⌘⏎ · Close ⌘W
Edit: Undo Sort ⌘Z · Redo Sort ⇧⌘Z (re-apply the undone run) · standard text edit items
Rules (custom menu): New Rule ⌘N · Edit Rule… ⌘E · Duplicate ⌘D · Delete ⌫ · Move Up/Down ⌥⌘↑/↓ · Enable/Disable ⌘⇧E
View: Group by Destination / Show as Flat List · Show Files That Stay ⌘⇧H

Preferences (⌘,) are out of v1 loop scope; if present: one pane, "Open at login: not in v1 (no daemon)". Nothing to configure for the loop.
