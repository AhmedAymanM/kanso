# Accessibility

Target: usable fully by keyboard, VoiceOver, with Increase Contrast, Reduce Motion, Reduce Transparency, and Larger Text. Using standard controls gets ~80% of this free; the list below is what we must add or not break.

## Keyboard map
| Context | Key | Action |
|---|---|---|
| Global | ⌘O | Choose folder |
| | ⌘⏎ | Apply (works from any focus) |
| | ⏎ | Apply, only when focus is not in a text field/table editing |
| | ⌘Z / ⇧⌘Z | Undo / Redo Sort (and Undo Delete Rule when the rule list is focused) |
| | ⌘, | Settings (if present) |
| | F6 / ⇧F6 | cycle regions: toolbar → rules → preview → action bar (standard pane cycling; tab order below) |
| Tab order | | toolbar folder menu → Undo → Apply → rule list → (rule filter chip) → preview table → action bar |
| Rule list | ↑ ↓ | select rule; selecting filters preview (VoiceOver announces count) |
| | ⏎ / ⌘E | open editor popover; focus lands on first field |
| | ⌥⌘↑ / ⌥⌘↓ | move rule up/down (drag has an equal keyboard path) |
| | ⌘N, ⌘D, ⌫, ⌘⇧E | new, duplicate, delete, enable/disable |
| Editor popover | Tab / ⇧Tab | through fields, in reading order; Esc or ⏎ on Done closes; focus returns to the rule row |
| Preview table | ↑ ↓ ← → | rows; ← / → collapse/expand groups |
| | Space | toggle include for selected rows |
| | ⌘A | select all rows; ⌘⇧A none |
| | ⌘R / ⌘Y | reveal in Finder / Quick Look |
| | Esc | clear rule filter; while applying = Stop |
| | ⌘⇧H | show/hide “Stays” group |
No custom shortcut conflicts with system ones; every pointer-only action (drag reorder, hover tooltip) has a keyboard/menu equivalent.

## VoiceOver
Rules are *labels from data*, not decorations.
| Element | accessibilityLabel | value / hint |
|---|---|---|
| Rule row | `Rule 1. PDFs, move to Documents/PDFs.` | value `41 files`; hint `Press Return to edit.` Shadowed: value `Covered by rule 1, no files`. Disabled: `Rule 3, off.` |
| Preview group header | `Documents/PDFs, 41 files` | value `expanded`/`collapsed` (disclosure trait) |
| Preview row (will move) | `Invoice-03.pdf, will move to Documents/PDFs by rule 1.` | value `included` / `skipped`; trait toggle (checkbox) |
| Row, renamed | `report.pdf, will move to Documents/PDFs as report 2.pdf because that name is taken, rule 1.` | |
| Row, stays | `notes.txt, stays in Downloads. No rule matched.` | |
| Row, blocked | `Contract.pdf cannot be moved. It is locked.` | |
| Summary bar | merged into one element, label = its two lines | `accessibilityAddTraits(.isHeader)`; **posts an announcement** when it changes after a rule edit: `Now moving 127 of 214 files.` (throttled to ≥ 1 s, polite) |
| Apply progress | `Moving 41 of 128` value updates every 10% only (avoid chatter) | |
| Apply done | announcement `Moved 128 files. Undo is available.` | |
| Undo button | `Undo sort. Puts 128 files back.` | |
| Number badge | hidden (`accessibilityHidden`) — folded into the row label | |
| Icons | file-type icons hidden; status icons carry labels via the row | |
| Banners | `accessibilityAddTraits(.isStaticText)` and posted as announcement on appearance | |
Never convey meaning by color alone: renamed = badge text “Renamed”, blocked = “Can’t move”, shadowed = text “Covered by rule N”, skipped = text “Skipped by you” — color only reinforces.

## Contrast (measured, WCAG 2.x)
| Pair | Ratio | Verdict |
|---|---|---|
| text / window (L) | 15.1 | AA/AAA |
| text2 / window (L), text2 / card (L), text2 / card (D) | 4.5, 5.1, 5.4 | AA — **text2 on window in Light is exactly at the floor; do not make it lighter or smaller than `callout`** |
| text3 / window (L) | 3.1 | **fails AA text.** Decoration/disabled only |
| move ink on pastel (L) | 6.0 | AA |
| rule ink on pastel / attention ink on pastel / stay ink | 6.0 / 5.3 / ≥7 | AA |
| blocked ink on window (L) | 6.7 | AA |
| dark: pastel-on-darkSurface (move/attention) | 9.1 / 9.0 | AAA |
Increase Contrast (`accessibilityDisplayShouldIncreaseContrast`): separators → 0.30 alpha; badge gets a 1pt ink-colored border; `text2` → `text`. Focus rings are the system ring (3pt) wherever the control is standard; custom focus (rule rows) uses `KT.Color.focus` 2pt outline, 3:1+ against both surfaces.

## Dynamic / Larger Text
macOS has no full Dynamic Type; we honor: **system text styles only** (never fixed point sizes), and test at the largest "Text Size" in Settings ▸ Accessibility ▸ Display. Rules: row height `32pt` is a *minimum* (`.frame(minHeight:)`), group headers min 28pt; rule rows grow to a 3-line sentence rather than truncating beyond 3 lines; toolbar items collapse to the overflow menu rather than clip; minimum window width 800pt ensures the Moves-to column keeps ≥ 180pt at largest text.

## Motion / transparency
Reduce Motion: `KT.Motion.animation` returns nil → every transition is instant; progress bar still determinate. No parallax, no auto-playing anything. Reduce Transparency: no materials are used in this loop (all surfaces are opaque tokens), so nothing to do — keep it that way.

## Test checklist (for review of the built screen)
1. Complete the whole loop with keyboard only, mouse unplugged.
2. VoiceOver: read the summary, walk 3 rule rows and 3 preview rows, open the editor, change a value, hear the new summary.
3. Increase Contrast + Dark: badges legible, no text on tinted fill below 4.5.
4. Largest text: no clipped Apply button, no overlapped rule sentence.
5. Reduce Motion: no animation anywhere.
