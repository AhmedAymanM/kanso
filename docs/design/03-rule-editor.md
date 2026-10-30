# Rule list and rule editor

Goal (principle 4): **read the rule set and predict the outcome without running it.** Every rule is one plain-English sentence, rules are ordered, first match wins, and each shows how many files it takes.

## Rule model (v1: small on purpose)

A rule = **conditions** + **match mode** + **destination folder** + enabled flag + optional name.

| Condition field | Operators | Value control | Sentence fragment |
|---|---|---|---|
| **Kind** | is / is not | pop-up of groups + "Other extension…": PDF documents, Images, Videos, Audio, Archives, Installers (dmg, pkg), Spreadsheets, Presentations, Text & Markdown, Code; "Other…" = free text of extensions `.epub, .mobi` | `PDFs` / `images` / `files ending .epub` |
| **Name** | contains / starts with / ends with / matches pattern | text field; pattern allows `*` and `?` only (no regex); case-insensitive; compared to the name without extension unless the pattern contains a `.` | `named like “Screenshot*”` |
| **Date** | Date added / Date modified / Date created × is older than / is within the last / is before / is after / is in year | number + unit pop-up (days, weeks, months) or a `DatePicker(.compact)` | `added over 30 days ago` |

- **Max 3 conditions per rule**; `+` on a condition row disappears at 3. More is a sign the rule should be two rules.
- **All / Any**: shown only when ≥ 2 conditions: "Match **all** ▾ of the following". Default All.
- `from` (download URL) and `size` exist in the engine; **not exposed in v1** (they widen the matrix without being in the v1 must-haves). If the CTO finds `size` nearly free, add it as a fourth field; tell me.
- **Destination:** a folder *inside the chosen folder*, typed as a relative path (`Documents/PDFs`) with a "Choose…" button (`NSOpenPanel` rooted at the chosen folder). Missing folders are created at Apply (preview marks them `new folder`). Destinations outside the chosen folder are not allowed in v1 (one sandbox grant, no surprise moves); the field validates.

## Rule list (left column)

Each rule is a **two-line row, 56pt** (selected/hover radius 6):
```
 ①  PDFs → Documents/PDFs                      ⠿   line 1: body, text (sentence, truncating tail)
    41 files                                       line 2: callout, text2 (count) or a state message
```
- Number badge ① (18pt circle, `KT.Color.rule` pastel, ink numeral) = priority = what the Rule column in the preview shows. Matches 1:1.
- **Sentence composition** (`{conditions} → {destination}`): conditions joined by "and" (All) or "or" (Any). Examples:
  - `PDFs → Documents/PDFs`
  - `Images added over 30 days ago → Archive/Images`
  - `Names starting “Screenshot” → Screenshots`
  - `PDFs named like “*invoice*” → Finance` (2 conditions, All)
  - `Disk images or installers → Installers` (Kind is DMG/PKG group)
- **Line 2 states:** `41 files` · `No files match` · `Covered by rule ①` (everything it would take, an earlier rule took — shadowed; amber text via `KT.Color.attention.ink`) · `Needs a destination` / `Needs a value` (rose, when invalid) · `Off` (disabled; whole row `text2`) .
- Row actions: **drag handle ⠿** (reorder), checkbox-less enable via context menu / ⌘⇧E, double-click or Return or ⌘E opens editor, ⌫ deletes (no confirm; **Edit ▸ Undo Delete Rule** ⌘Z restores it).
- Footer: `+ Add Rule` (⌘N). List header: `RULES` `callout` caps `text2`, with `[+]`.
- **Order explanation, once:** when the list has ≥ 2 rules, a single-line footnote at the bottom of the column, `callout`, `text2`: “Rules run top to bottom. A file goes to the first rule that matches.” (always visible; it is the only teaching text in the app and it earns its place.)

## Editor: a non-modal popover

Opens anchored to the row (`NSPopover`, `.semitransient`, 440pt wide, height to fit). **Non-modal on purpose:** the preview stays visible and updates live behind/beside it (debounce `KT.Motion.previewDebounce`), and the rule's matched files are highlighted. A sheet would hide the thing being edited.

```
┌ 440 ───────────────────────────────────────────┐
│ Rule name (optional)   [ Invoices            ] │  text field, placeholder: Name this rule
│                                                │
│ Match [all ▾] of the following                 │  shown if ≥ 2 conditions
│ [Kind ▾] [is ▾]     [PDF documents ▾]   [−][+] │  condition row 28pt, 8pt gap
│ [Name ▾] [contains ▾] [invoice        ] [−][+] │
│                                                │
│ Move to  [ Finance                ] [Choose…]  │
│                                                │
│ ─────────────────────────────────────────────  │
│ Moves 12 files · Skips 3 an earlier rule took  │  live line, callout
│ [Show those files]                  [Done ⏎]   │
└────────────────────────────────────────────────┘
```
- Controls are standard AppKit-backed SwiftUI: `Picker(.menu)`, `TextField(.roundedBorder)`, `Stepper`/number field, `DatePicker`. No custom controls.
- Condition rows: 28pt tall, 8pt gap; first row has `[−]` disabled when it's the only one.
- Live line copy: `Moves {n} files` + (`· {s} are taken by an earlier rule` if shadowed>0). If 0: `No files in “Downloads” match.` (neutral, not an error).
- **Show those files** = sets the preview's rule filter chip (see 02).
- **Done** (⏎ / Esc both close — edits are live and already applied to the draft; there is no Cancel because nothing touches disk). Closing with an invalid rule keeps it in the list, flagged "Needs a value", and excluded from the plan.
- New rule defaults: Kind **is** PDF documents → destination empty (focused) so the first thing typed is the useful thing.

## Validation (inline, never modal)
| Problem | Where | Copy |
|---|---|---|
| Name/kind value empty | the field gets a rose underline + the row's line 2 | `Needs a value` |
| Destination empty | destination field | `Choose where these files should go` |
| Destination outside folder / absolute path | destination field | `Choose a folder inside “Downloads”` |
| Destination same as source (`.` or empty path) | destination field | `That’s where these files already are` |
| Pattern has `/` | name field | `Names can’t contain “/”` |
| Number ≤ 0 | number field | `Use 1 or more` |
| Duplicate rule (identical sentence) | list line 2, amber | `Same as rule ③` |
Rules with problems are skipped by the engine (not guessed at).

## Rule persistence
Per chosen folder: rules are stored with the folder's bookmark (the "Downloads" set differs from "Desktop"). Switching folders swaps the rule list; a "Copy Rules From…" is not v1. Rules are saved on every change (no Save command).

## Predictability checks the design relies on
1. Sentence ↔ editor are the same data; no rule has hidden state.
2. Count under each rule + "Covered by rule ①" tell the user the *outcome* without opening the preview.
3. Dates are relative by default ("over 30 days ago") and evaluated at plan time; the preview is the contract for *today*. Say so once: the date field's help text `Counted from today.`
