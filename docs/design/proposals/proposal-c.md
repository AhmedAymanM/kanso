# Proposal C · Ink Notch

Mockup: [proposal-c.html](proposal-c.html). References: Hyperfocus (dark, quiet, evidence), Butter (real UI at real size), Haptic (one decision per screen). Revised 2026-10-30 after the panel reviews.

## Idea
The island is the product; the window is a ledger you consult. Dark-led, graphite surfaces, SF for text, a monospace for paths, counts and times, one sage accent. The window reads like an audit log: every line says what moved where, with Undo at the right.

## Layout
- **Overview ("In order."):** a 260 pt left rail (headline, one mono status line, a shelf ledger with the top shelf in mint) and a feed: NEEDS YOU first (butter wash, two buttons), then TODAY lines (time, name, `Downloads → My Shelves/Documents`, Undo). The "nothing to do" frame is in the mock. Activity and Overview become one page (this reopens the 2026-10-01 app-pages decision; **owner call**, not applied).
- **Island, notch skin:** the same real two-row structure as A (32 pt notch row with a 24 pt tile, the 200 pt cutout and the chip; row 2 the centred line; 34 pt lip) but **12 pt padding** instead of 14, radius 20 compact and 28 expanded, and a **mono time column** (48 pt) in the "Recently" rows with a per-row Undo. The bottom edge keeps the owner's melt-into-glass decision; the proposal for a clean edge is noted, not applied.
- **Tray:** items show a mono path line (`Downloads → Documents · file type`); the plan is diff-style with the destination in sage mono (`+ Documents`).

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

### Colour and contrast (dark first)
| Token | Light | Dark |
|---|---|---|
| `window` | `#EEEDEA` | `#111113` |
| `card` | `#FAFAF8` | `#19191C` |
| `text` | `#161618` | `#EDEDEF` |
| `text2` | **`#5E5E63`** (5.13 on the butter wash start `#F7E4B5`; the old `#66666B` was 4.55 there, a pass at the floor, and 4.88 on window) | **`#A0A0A8`** (6.76 on card, 4.89 on the butter wash `#3C3122`; the old `#8E8E95` was 3.90 there, a fail) |
| `separator` (dividers) | black 9% | white 9% |
| `controlStroke` | `#8A8A8E` (3.29 on card) | `#78787D` (3.99 on card) |
| `accent` (sage) | `#2F7D5F` (4.76 on card) | `#8FD3B0` (10.12 on card) |
| primary button text | white on `#2F7D5F` (4.98) | **`#0B2A1F` on `#8FD3B0` (8.87)**; the mock had white on mint, about 1.6:1 |
| `mint` | `#245244` on `#CFE8D8` (6.84) | `#9FDCBC` on `#24362F` (8.18) |
| `butter` | `#7E531B` on `#F7E4B5` (5.32) | `#EBCB8B` on `#3C3122` (8.13) |
| `periwinkle` | `#3C509A` on `#D9E0FA` (5.70) | `#B9C6FF` on `#2A2F46` (7.90) |
Washes (needs-you) are a left-to-right gradient from the tint to transparent. Text on a wash is measured at the **tint end**, the worst case.

### Radii and spacing
Window 14, rows 7, buttons 7 (rect in the window; pill only in the island), ask field 10, notch bottom 20 compact / 28 expanded. Spacing 4 / 8 / 12 / 16 / 26; row height 44.

### Motion
| Token | Value |
|---|---|
| `ease.snap` | `cubic-bezier(.25,1,.3,1)` |
| `dur.fast / base / island` | 90 / 160 / 220 ms |
| Row removal | height collapse 160 ms; Undo restores in 160 ms |
Fast and short, no stagger. Reduce Motion: no height animation, instant swaps.

## Material
Window and rail solid. Notch black; capsule glass at 92% on 26+, material before, solid with Reduce Transparency. Window buttons are flat with `controlStroke` edges; interactive glass only inside floating surfaces. Dark is the primary design; light needs its own pass.

## Mapping to `Theme.swift`
| Change | Where |
|---|---|
| Dark values become the source; `Color.dyn` pairs reordered | `enum K` |
| New `TS.mono` plus `Font.kmono` | `enum TS` |
| Overview/Activity merge (owner call): `OverviewPage` becomes `Ledger` | `OverviewPage.swift`, `ActivityPage.swift` |
| `Tint` washes via `LinearGradient` helper `wash(_:)` | `struct Tint` |
| Rect buttons in the window | `PillStyle`, `SecondaryStyle` |

## Risks
- Changes the product's voice from calm to precise; "Kanso" (簡素) may read as developer-ish.
- Mono text localises poorly and VoiceOver reads paths letter by letter unless rows carry an `accessibilityLabel` ("moved to Documents").
- Merging Overview and Activity reopens a recorded decision.
