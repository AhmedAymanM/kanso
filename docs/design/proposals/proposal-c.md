# Proposal C · Ink Notch

Mockup: [proposal-c.html](proposal-c.html). References: Hyperfocus (dark, quiet, evidence), Butter (real UI at real size), Haptic (one decision per screen).

## Idea
The island is the product; the window is a ledger you consult. Dark-led, graphite surfaces, SF for text, a monospace for paths and counts, one sage accent. The window reads like an audit log: every line says what moved where, with Undo at the right.

## Layout
- **Overview ("In order."):** a 260 pt left rail with the headline, one status line in mono and a shelf ledger (shelf, count; the top shelf in mint). The right pane is a feed: NEEDS YOU first (butter wash, two buttons), then TODAY lines (time, name, `Downloads → My Shelves/Documents`, Undo). There are no charts or tiles; Activity and Overview become one page, so the sidebar loses a row.
- **Island:** capsule corners 28, tighter 12 pt padding, mono time stamps in the Recently rows.
- **Tray:** items are rows with mono source ("file · Downloads"); the plan is a diff-style list (`→ Documents`).

## Tokens

### Type
| Token | Size / line | Weight | Face |
|---|---|---|---|
| `title` | 22 / 26 | 600 | SF |
| `heading` | 15 / 20 | 600 | SF |
| `body` | 13 / 18 | 400 | SF |
| `small` | 12 / 16 | 400 | SF |
| `mono` | 12 / 16 | 500 | SF Mono (paths, counts, times) |
| `meta` | 11 / 14, +0.08 em, caps | 600 | SF Mono |

### Colour (dark first)
| Token | Light | Dark |
|---|---|---|
| `window` | `#EEEDEA` | `#111113` |
| `card` | `#FAFAF8` | `#19191C` |
| `text` / `text2` | `#161618` / `#66666B` | `#EDEDEF` / `#8E8E95` |
| `separator` | black 9% | white 9% |
| `accent` (sage) | `#2F7D5F` | `#8FD3B0` |
| `mint` bg/fg | `#CFE8D8` / `#245244` | `#24362F` / `#9FDCBC` |
| `butter` | `#F7E4B5` / `#7E531B` | `#3C3122` / `#EBCB8B` |
| `periwinkle` | `#D9E0FA` / `#3C509A` | `#2A2F46` / `#B9C6FF` |
Washes (needs-you) are a left-to-right gradient from the tint to transparent, never a full pastel block.

### Radii and spacing
Window 14, rows 7, buttons 7 (rect, not pill, in the window; pill only in the island), ask field 10, notch bottom 28. Spacing 4 / 8 / 12 / 16 / 26; row height 44.

### Motion
| Token | Value |
|---|---|
| `ease.snap` | `cubic-bezier(.25,1,.3,1)` |
| `dur.fast` / `base` / `island` | 90 / 160 / 220 ms |
| Row removal | height collapse 160 ms; Undo restores in 160 ms |
Fast and short, no stagger. Reduce Motion: no height animation, instant swaps.

## Material
Window and rail solid. Island: notch black; capsule skin glass on 26+, material before, solid with Reduce Transparency. Buttons in the window are flat with hairline strokes; interactive glass only inside floating surfaces. The dark palette is the primary design; light is derived and needs its own pass (the current app derives dark from light).

## Mapping to `Theme.swift`
| Change | Where |
|---|---|
| Dark values become the source; `Color.dyn` pairs reordered | `enum K` |
| New `TS.mono` plus a `Font.kmono` helper | `enum TS` |
| Overview/Activity merge: `OverviewPage` becomes `Ledger` (reusing `ActivityRow` data) | `OverviewPage.swift`, `ActivityPage.swift` |
| `Tint` washes via `LinearGradient` helper `wash(_:)` | `struct Tint` |
| Pill buttons in window replaced by `RectButtonStyle` | `PillStyle`, `SecondaryStyle` |

## Risks
- Changes the product's voice from calm to precise; "Kanso" (簡素, simplicity) may read as developer-ish for users who just want their Downloads tidy.
- Mono text localises poorly (German paths and long names) and is harder for VoiceOver users when read as paths.
- Merging Overview and Activity reopens a decision made in the 2026-10-01 app-pages grilling.
