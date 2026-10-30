# Proposal A · Paper & Ink

Mockup: [proposal-a.html](proposal-a.html). References: Superlist (one accent, one moment), Protagonist (editorial voice), Taskade (two pastels), Haptic (one card, one decision). Revised 2026-10-30 after the design, accessibility, security and strategy panel reviews (`docs/research/panel/`). The adopted direction is in [final-direction.md](final-direction.md).

## Idea
Kanso is a quiet desk. Surfaces are warm paper; sentences are set in a serif, controls in SF; one mint ink carries meaning; everything that floats (island, popover, Tray) is glass or black. **There is no glass on content cards.** The sidebar and toolbar keep the automatic macOS 26 glass, and buttons keep the interactive `glassEffect` (`liquid(_:)`) the app already uses.

## Layout
- **Overview:** headline (`display`) and one sentence. Row 1: *Kept in order* hero (1/3) and one Needs-you card (2/3). When nothing needs you the card collapses to a 56 pt single line and the month chart rises into its place (frame in the mock). Row 2: month chart (elapsed days only) and Where files went. Row 3: one line of counts (no tinted tiles).
- **Activity (frame in the mock):** toolbar with traffic lights and a 15 pt SF title; 220 pt sidebar; detail with the serif `title`, a "How Kanso decided" card, paths in a monospace (detail only, taken from C). Sorting is unchanged except for the audit fixes.
- **Island, notch skin (the real structure, see below).**
- **Tray:** the same shell as the expanded island; see [tray.md](tray.md).

## Island: what it really is
Measured from `IslandViews.swift` (`IslandBody`) and `island-compact.png`, not from the old mock:
- **Compact, notch skin:** two rows. Row 1 is exactly the hardware notch height (32 pt on a 14-inch MacBook Pro): a 24 pt tile (`MorphIcon`) 14 pt from the left edge, the clear 200 pt cutout, and the shortcut chip 14 pt from the right edge. Row 2 is the one-line notice, centred, middle-truncated. Below it a clear 34 pt lip. Ears are 10 pt, radius 20.
- **Width.** Today `max(290, notch + 110)`, which leaves 38 pt for the chip and truncates `⌥⌘K` to `⌥…`. **A sets it to `notch + 140` (340 pt for a 200 pt notch)**, which leaves 68 pt. The chip appears only until the first dwell, then drops to a 28 pt icon-only key.
- **Expanded:** 480 pt wide, radius 30. The top 32 pt is the clear notch band (no content). Then head (24 pt tile, title, age), the Kept / Extra-copy pair, one row of actions that never wraps, the ask field, and the lip (esc hint left, two 28 pt glass buttons right).
- **Capsule skin (no notch):** one row, 320 × 38, radius 22, 6 pt below the menu bar.
- **Owner call, not a defect (audit #15):** the bottom edge melting into glass ("ears melting into glass", Droppy-style) is a recorded owner decision (AGENTS.md). A keeps it. What A fixes is the smudge: the melt is limited to the **last 12 pt**, the "esc to close" row sits above it on solid black (7.8:1 or better), and nothing else changes. The alternative (a clean edge with a 0.5 pt highlight) is a proposal the owner may take or leave; it is not applied.

## Tokens

### Type (SF Pro + New York, system fonts only)
Eight steps; today `TS` has thirteen. Nothing below 11 pt.
| Token | Size / line | Weight | Face | Use |
|---|---|---|---|---|
| `meta` | 11 / 14 | 600, +0.5 kerning, caps | SF | Eyebrows, key hints, chart labels (replaces 10 pt `micro`) |
| `small` | 12 / 16 | 400 | SF | Descriptions |
| `body` | 13 / 18 | 400 | SF | Rows, buttons |
| `emphasis` | 15 / 20 | 600 | SF | Card titles, sub-headline, toolbar title |
| `heading` | 17 / 22 | 600 | SF | File names in notices |
| `title` | 22 / 28 | 400 | New York | Page statements, counts line, Quick settings wordmark, Activity title |
| `display` | 40 / 44, tracking -0.4 | 400 | New York | Overview headline |
| `numeral` | 64 / 64 | 400, `monospacedDigit` | New York | Kept-in-order number |
Serif only for statements and numerals, never for controls. In SwiftUI: `.font(.system(size: 40, design: .serif))`; the web mock falls back to Georgia in Chrome, so judge the serif in the app.

### Colour and contrast (WCAG 2.x, computed)
Body text needs 4.5:1, text of 18 pt or 14 pt bold and larger needs 3:1, control edges 3:1.
| Token | Light | Dark |
|---|---|---|
| `window` | `#F4F2EE` | `#1C1C1E` |
| `card` | `#FFFFFF` | `#2C2C2E` |
| `text` | `#1D1D1F` (15.05 window, 16.83 card) | `#F5F5F7` (15.63, 12.80) |
| `text2` | `#636368` (5.34 window, 5.97 card) | `#A1A1A6` (6.61, 5.42) |
| `text3` | `#666669` (5.12 window) | `#9C9CA2` (6.23 window, 5.10 card) |
| `separator` (dividers only) | black 10% (1.25) | white 12% |
| `controlStroke` (edges of buttons, fields) | `#8A8A8E` (3.08 window, 3.44 card) | `#78787D` (3.87 window, 3.17 card) |
| `ink` (accent, focus ring) | `#2E5A4B` (7.01 window) | `#BFE3D0` (12.25 window) |
| `mint` fg on bg | `#2E5A4B` on `#CFE8D8` (6.04) | `#BFE3D0` on `#2D3A37` (8.53) |
| `butter` | `#7E531B` on `#F7E4B5` (5.32) | `#F3D79B` on `#453828` (8.11) |
| `periwinkle` | `#3C509A` on `#D9E0FA` (5.70) | `#C9D3FF` on `#31374E` (7.97) |
| `hero` text on fill | `#F4F2EE` on `#2E5A4B` (7.01); secondary text at 85% = 5.58 | `#E8F3EC` on `#243A33` (10.68); at 85% = 8.20 |
| glass capsule `glassText2` | `#636368` on `#FBFAF8` at 92% over black (4.79) | `#C0C0C7` on `#2A2A2C` at 92% over white (6.18) |
| notch text | white (21.0), secondary white 70% (9.90), floor 62% (7.84) | same (always dark) |
| notch chip | white on white 14% (15.52); 70% text on it 7.32 | same |
Rules that make the numbers hold:
- `text2` and `text3` never sit on a tint (dark `text2` on butter is 4.41, a fail); text on a tint uses that tint's own fg.
- Translucent glass fills are at least 92%; on translucent glass `text2` is `glassText2`.
- `Tint.rule` / `Tint.where` / `Tint.neutral` are icon strokes only: light 5.98 / 5.33 / 7.56 against their fills, over the 3:1 non-text minimum.
- Dark `separator` and light `separator` are decoration. Anything the user must find (buttons, the ask field, onboarding choice cards) uses `controlStroke`.
- Hero secondary text opacity is 85%, not 70% (70% is 4.36, a fail).

### Radii and spacing
Concentric: inner radius = outer radius minus padding, never below 8. Window 18 (system), **card 14, card padding 16**, hero 14, inner controls 8, row group 12, button 99, ask field 14, notch bottom 20 compact / 30 expanded, capsule 22 compact / 30 expanded, tile 12. On macOS 26 prefer `ConcentricRectangle`. Spacing 4 / 8 / 12 / 16 / 24 / 36; page padding 36. Hit areas: 28 pt minimum, 44 pt for the Tray forget button (via `contentShape`).

### Motion
| Token | Value | Use |
|---|---|---|
| `ease.standard` | `cubic-bezier(.2,.8,.2,1)` | hover, selection, card swap |
| `spring.settle` | response 0.35, damping 1.0 (no overshoot) | island grow, Tray open, Needs-you collapse (`frame(height:)`) |
| `dur.fast / base / island` | 120 / 220 / 420 ms | hover / cards / island grow |
| `stagger` | 40 ms per item, max 5 | island content after the shape grows |
Only these move: island grow/shrink, Needs-you card swap and collapse, undo confirmation, Tray drag-over. Illustrations: one pass, then rest (15 s limit stays). Reduce Motion: 200 ms cross-fade, no grow, no stagger, `IslandBeam` replaced by static text ("Planning 3 of 4").

## Material (Liquid Glass)
- Window content cards and hero: solid `window` / `card`. Sidebar and toolbar: system material (automatic on 26). Buttons: interactive glass as today.
- Floating: Quick settings popover and capsule island use `glassEffect(.regular)` at the 92% floor; Tray inherits its host skin.
- Notch skin stays black (it merges with the hardware).
- Fallbacks: macOS 14-15 `.regularMaterial` plus a 0.75 pt `controlStroke`; Reduce Transparency uses solid `K.glass`; Increase Contrast adds a 1 pt stroke.

## Mapping to `Theme.swift`
See [final-direction.md](final-direction.md) for the exact table. In short: collapse `TS` to the eight steps (migrate call sites in one PR; no value-changing aliases), add `K.controlStroke` and `K.glassText2`, fix `K.text2` / `K.text3`, demote `Tint.rule` and `Tint.where` to strokes, add `Dur`/`Ease`, replace the four counter `Tile`s by `CountsLine`.

## Risks
Lowest of the three. Least differentiated from today, so the audit fixes must land for it to feel finished. The 340 pt compact island is 50 pt wider than today's.
