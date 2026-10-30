# Proposal A · Paper & Ink

Mockup: [proposal-a.html](proposal-a.html). References: Superlist (one accent, one moment), Protagonist (editorial voice), Taskade (two pastels), Haptic (one card, one decision).

## Idea
Kanso is a quiet desk. Surfaces are warm paper; sentences are set in a serif, controls in SF; one mint ink carries meaning; everything that floats (island, popover, Tray) is glass. The window never uses glass.

## Layout
- **Overview:** headline (serif 40) and one sentence. Row 1: *Kept in order* hero (1/3) + one Needs-you card (2/3). When nothing needs you the card collapses to a 56 pt single line and the month chart rises into its place. Row 2: month chart (only elapsed days) + Where files went. Row 3: one text line of counts (no tinted tiles).
- **Activity, Sorting:** unchanged structure; fixes from the audit (group order, one date format, Quick Look thumbnails, no orphan headings, banner max 160 pt).
- **Island:** black notch skin as today, but with a clean bottom edge (no fade-to-grey), left-aligned icon + text in compact, shortcut chip only before the first dwell.
- **Tray:** see [tray.md](tray.md); same shell as the expanded island with a dashed well.

## Tokens

### Type (SF Pro + New York, system fonts only)
| Token | Size / line | Weight | Face | Use |
|---|---|---|---|---|
| `display` | 40 / 44 | 400 | New York | Overview headline, Kept-in-order numeral at 64 |
| `title` | 22 / 28 | 400 | New York | Page statements, Quick settings wordmark |
| `heading` | 17 / 22 | 600 | SF | File names in notices, card titles |
| `body` | 13 / 18 | 400 | SF | Rows, buttons |
| `small` | 12 / 16 | 400 | SF | Descriptions |
| `meta` | 11 / 14 | 600, +0.5 kerning, caps | SF | Eyebrows, key hints |
| `numeral` | 22 / 26 | 400 | New York | Counts line |
Seven steps (today: thirteen). Serif only for statements and numerals; never for controls.

### Colour (light / dark)
| Token | Light | Dark |
|---|---|---|
| `window` | `#F4F2EE` | `#1C1C1E` |
| `card` | `#FFFFFF` | `#2C2C2E` |
| `text` / `text2` | `#1D1D1F` / `#6E6E73` | `#F5F5F7` / `#A1A1A6` |
| `separator` | black 10% | white 12% |
| `ink` (accent) | `#2E5A4B` | `#BFE3D0` |
| `mint` bg / fg | `#CFE8D8` / `#2E5A4B` | `#2D3A37` / `#BFE3D0` |
| `butter` bg / fg (duplicates, needs-you) | `#F7E4B5` / `#7E531B` | `#453828` / `#F3D79B` |
| `periwinkle` bg / fg (rename) | `#D9E0FA` / `#3C509A` | `#31374E` / `#C9D3FF` |
| `hero` | `#2E5A4B` on `#F4F2EE` text | `#243A33` on `#E8F3EC` text |
Rule: only mint, butter, periwinkle appear on screen in normal use; lavender and aqua become icon strokes (rules, waiting). Tints mean an action kind and are never used for counters.

### Radii and spacing
Radii (concentric: inner = outer minus padding): window 18, card 20, row group 14, button 99, ask field 14, notch bottom 34, capsule 99, tile 12. Spacing scale 4 / 8 / 12 / 16 / 24 / 36; card padding 20; page padding 36.

### Motion
| Token | Value | Use |
|---|---|---|
| `ease.standard` | `cubic-bezier(.2,.8,.2,1)` | hover, selection, card swap |
| `spring.settle` | response 0.35, damping 1.0 (existing, no overshoot) | island grow, Tray open |
| `dur.fast` / `base` / `island` | 120 / 220 / 420 ms | hover / cards / island grow |
| `stagger` | 40 ms per item, max 5 | island content after shape grows |
Only these places move: island grow/shrink, needs-you card swap, undo confirmation, Tray drag-over. Illustrations: one pass, then rest (15 s limit stays). Reduce Motion: cross-fade 200 ms, no grow, no stagger.

## Material (Liquid Glass)
- Window, cards, sidebar: solid `window` / `card` colours (the sidebar keeps its system material).
- Floating: Quick settings popover and capsule island use `glassEffect(.regular)`; interactive glass only on buttons inside floating surfaces (`liquid(_:)` as today).
- Notch skin stays black: it must merge with the hardware.
- Fallbacks: macOS 14-15 `.regularMaterial` + 0.75 pt separator stroke; Reduce Transparency solid `glass` colour (existing `Motion.solid` path).

## Mapping to `Theme.swift`
| Change | Where |
|---|---|
| Collapse `TS` from 13 to the 7 steps above; keep old names as deprecated aliases for one release | `enum TS` |
| Add `K.ink`, drop the separate `K.accent`/`K.focus` duplicates (same value) | `enum K` |
| Demote `Tint.rule` and `Tint.where` to `strokeOnly` (no `bg` use outside icons) | `struct Tint` |
| Add `enum Dur { fast, base, island }` and `Ease.standard`; `Motion.spring` stays | `enum Motion` |
| `GlassSurface` radius becomes a parameter set by the caller to keep concentric radii | `GlassSurface` |
| Overview counters: replace four `Tile` views by one `CountsLine` | `OverviewPage.swift` |
| Sidebar selected row uses `rowSelected` plus `accent` dot (one selection language) | `MainView.swift` |

## Risks
Lowest of the three. Least differentiated from today's look, so it needs the audit fixes to feel finished.
