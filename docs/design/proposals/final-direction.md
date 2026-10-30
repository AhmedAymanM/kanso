# Final direction: A, with adopted bits

Date: 2026-10-30. Inputs: the three proposals, `tray.md`, and the design, accessibility, security and strategy panel reviews in `docs/research/panel/`. This file is enough to implement from without opening the mockups. Nothing here is applied to code yet.

## Decision
- **Base: A (Paper & Ink).** Solid warm surfaces in the window, one mint ink, serif for statements, SF for controls.
- **From B:** the *material rule* (glass only for things that float: capsule island, popover, Tray) and the capsule-first idea as an **option** for the island. Not adopted: floating glass panes, `.hiddenTitleBar`, the glass morph (impossible across `NSWindow` and `NSPanel`).
- **From C:** paths and counts in a monospace **inside the Activity detail only**; the mono time column in the island's "Recently" rows; the primary-button contrast fix. Not adopted: dark-led window, merging Overview and Activity (reopens a recorded decision).
- **Owner decisions kept, not overridden:** the notch skin's bottom edge melting into glass (Droppy-style, AGENTS.md) stays; only its smudge is fixed (melt limited to the last 12 pt, esc row on solid black). The notch skin stays the default look. File references versus copies for the Tray is still open. Whether the capsule becomes the default, and whether Overview drops the counters entirely, are owner calls.
- **Strategy:** the Tray is files-only in v2; links, snippets, BYOK/cloud and "By purpose" stay out of this work.

## Token table (value, contrast, `Theme.swift` name)
Ratios are WCAG 2.x. Body 4.5:1, large text 3:1, control edges and focus 3:1. "Window" is `K.window`, "card" is `K.card`.

### Surfaces and text
| Token | Light | Dark | `Theme.swift` | Contrast (L / D) |
|---|---|---|---|---|
| window | `#F4F2EE` | `#1C1C1E` | `K.window` (unchanged) | n/a |
| card | `#FFFFFF` | `#2C2C2E` | `K.card` (unchanged) | n/a |
| sidebar | `#ECE8E1` | `#232325` | `K.sidebar` (unchanged) | text on it 13.78 / n/a |
| text | `#1D1D1F` | `#F5F5F7` | `K.text` (unchanged) | 15.05 window, 16.83 card / 15.63, 12.80 |
| text2 | **`#636368`** (was `#6E6E73`, 4.54) | `#A1A1A6` | `K.text2` (light changes) | 5.34 window, 5.97 card / 6.61, 5.42 |
| text3 (text) | **`#666669`** (was `#8A8A8E`, 3.08) | **`#9C9CA2`** (was `#8E8E93`, 4.27 on card) | `K.text3` | 5.12 window / 6.23 window, 5.10 card |
| sidebar text2 | `#5E5E63` | `#A1A1A6` | `K.sidebarText2` (unchanged) | 4.89 on `#ECE8E1` / 5.9 |
| separator (dividers only) | black 10% | white 12% | `K.separator` (unchanged) | 1.25: decoration only |
| **controlStroke** (new) | `#8A8A8E` | `#78787D` | `K.controlStroke` (new; the old text3 grey moves here) | 3.08 window, 3.44 card / 3.87 window, 3.17 card |
| ink / accent / focus ring | `#2E5A4B` | `#BFE3D0` | `K.accent` (= `Tint.accent.fg`); **delete `K.focus`** (same value) | 7.01 window / 12.25 window |
| glass fill | `#FBFAF8` at 92% | `#2A2A2C` at 92% | `K.glass` (already .90 / .92; raise light to .92) | n/a |
| glass secondary text | `#636368` | `#C0C0C7` | `K.glassText2` (new) | 4.79 worst (over black) / 6.18 worst (over white) |
| hero fill, text | `#2E5A4B`, `#F4F2EE` | `#243A33`, `#E8F3EC` | `K.hero`, `K.heroText` (new) | 7.01 / 10.68 |
| hero secondary text | heroText at **85%** (was 70%, 4.36) | heroText at 85% | `K.heroText.opacity(0.85)` | 5.58 / 8.20 |

### Tints (bg / fg)
| Tint | Light | Dark | `Theme.swift` | Contrast L / D |
|---|---|---|---|---|
| mint (sorted, brand, selection, primary button) | `#CFE8D8` / `#2E5A4B` | `#2D3A37` / `#BFE3D0` | `Tint.accent` | 6.04 / 8.53 |
| butter (duplicate, needs-you) | `#F7E4B5` / `#7E531B` | `#453828` / `#F3D79B` | `Tint.duplicate` | 5.32 / 8.11 |
| periwinkle (rename) | `#D9E0FA` / `#3C509A` | `#31374E` / `#C9D3FF` | `Tint.rename` | 5.70 / 7.97 |
| lavender (rules) | `#E5DCF7` / `#5A4687` | `#3A3449` / derived | `Tint.rule` (**icon stroke only**) | 5.98 L; verify derived dark fg is at least 3:1 |
| aqua (waiting) | `#D0ECEC` / `#1E666B` | `#283D40` / derived | `Tint.where` (**icon stroke only**) | 5.33 L; same check |
| stone (neutral) | `#ECEAE5` / `#48484D` | `#343437` / derived | `Tint.neutral` | 7.56 L |
Rules: never put `text2` / `text3` on a tint (dark text2 on butter is 4.41); use the tint's fg. Pastels mean an action kind and are never counters.

### Island constants (always dark)
| Item | Value | Contrast |
|---|---|---|
| fill | `#000000` | n/a |
| text | white | 21.0 |
| secondary text | white 70% (`IslandInk.text2`; **floor 62%**) | 9.90 (62%: 7.84) |
| chip / glass button fill | white 14% | text on it 15.52 (70% text: 7.32) |
| field and well edge | white 40% | 3.66 against black |
| primary button | `#CFE8D8` bg, `#2E5A4B` fg | 6.04 |
| Replace | white 40% / 35% text in `Onboarding.swift` (3.66 / 3.00) with white 70% | 9.90 |

### Type (`enum TS`)
Eight steps. **Migrate every call site in one PR using the compiler; do not leave aliases whose name keeps but changes value.**
| New | Size / line | Weight, face | Old names that map to it |
|---|---|---|---|
| `TS.meta` | 11 / 14 | 600, caps, +0.5 kerning, SF | `micro` (10), `meta` |
| `TS.small` | 12 / 16 | 400, SF | `small` |
| `TS.body` | 13 / 18 | 400, SF | `body` |
| `TS.emphasis` | 15 / 20 | 600, SF | `emphasis` |
| `TS.heading` | 17 / 22 | 600, SF | `heading` |
| `TS.title` | 22 / 28 | 400, New York (`design: .serif`) | `title` (20), `title2`, `headline` (26) |
| `TS.display` | 40 / 44, tracking -0.4 | 400, New York | `display` (30), `statement` (34), `hero` (40) |
| `TS.numeral` | 64 / 64 | 400, New York, `.monospacedDigit()` | `numeral` (52) |
Notes: Activity headline becomes `title` serif (toolbar title stays 15 pt SF `emphasis`). Folder emoji (old `headline` 26) uses an explicit icon size, not a text token. No font under 11 pt; chart labels and badges are `meta`. The "Dynamic Type" rule is dropped (macOS has none); test layouts at the 600 pt minimum width instead.

### Radii, spacing, targets
| Token | Value | `Theme.swift` |
|---|---|---|
| window | 18 (system) | n/a |
| card, hero | 14 (was 20), padding 16 | `card(radius:)` default 14; padding in call sites |
| inner control inside card | max(8, outer − padding) = 8; use `ConcentricRectangle` on macOS 26 | new `K.innerRadius = 8` |
| row group | 12 | |
| button, chip, capsule badge | 99 | |
| ask field | 14 | |
| notch compact / expanded bottom radius | 20 / 30 (as `IslandBody.radius`) | unchanged |
| capsule compact / expanded | 22 / 30 | `IslandBody.radius` |
| tile | 12 | |
| spacing | 4 / 8 / 12 / 16 / 24 / 36 (page padding 36) | |
| min target | 28 pt; Tray ✕ and other small glyph buttons 44 × 44 via `contentShape` | |
`GlassSurface` takes its radius from the caller so inner radii stay concentric.

## Motion values
| Name | Value | `Theme.swift` / use |
|---|---|---|
| `Ease.standard` | `cubic-bezier(.2,.8,.2,1)` (SwiftUI: `.timingCurve(0.2,0.8,0.2,1)`) | new `enum Ease`; hover, selection, card swap |
| `Motion.spring` | response 0.35, damping 1.0 | existing `Motion.spring(0.35)`; island grow, Tray open, Needs-you collapse on `frame(height:)` |
| `Dur.fast / base / island` | 0.12 / 0.22 / 0.42 s | new `enum Dur` |
| stagger | 0.04 s per item, max 5 | existing `Stagger` |
| icon morph | 0.18 s delay then spring response 0.3 | existing `MorphIcon` |
| Needs-you card hand-off to island | 0.22 s cross-fade (no glass morph) | |
| Tray: drag dwell | 250 ms in a 160 × 44 pt zone; shrink after leaving 220 pt | `TrayDragMonitor` (new) |
| Tray: confirmations | "Added N" 2 s; "Moved N" 6 s | |
| notice dismiss and illustration rest | unchanged (illustrations rest after 15 s) | |
| Reduce Motion | 0.2 s cross-fade; no grow, stagger, beam, or parallax; progress shown as static text | `Motion.reduced` |
| Reduce Transparency | solid `K.glass` | existing `Motion.solid` |
| Increase Contrast | 1 pt `controlStroke` on every glass surface | existing `Motion.contrast` |
Only these things animate: island grow and shrink, Needs-you swap and collapse, undo confirmation, Tray drag-over, illustrations (one pass then rest).

## Per-screen change list, ordered by impact
1. **Global tokens (all screens).** Apply the text2 / text3 / controlStroke / glass values above; swap button and field edges from `K.separator` to `K.controlStroke`; fix white 40% and 35% text on black (`Onboarding.swift:258,261`) to 70%; use `TS` eight steps; set announcement priority to `.medium` for confirmations and `.high` only for failures (`Island.swift:537`).
2. **First-run window (Onboarding).** Replace "Nothing leaves this Mac." (`:63`, `:154`) with: "Your files never leave this Mac. Once a day Kanso checks GitHub for a new version; turn that off in Settings." Delete `.focusEffectDisabled()` (`:46`) and give each folder row a focus ring (`controlStroke` edge on choice cards, ink ring on focus). Fix or cut "or click the island" (`:133`) (add a tap gesture with button semantics, preferred). Skip the 10 s auto-expand under VoiceOver (`:141`). Name each paused folder with "Off · Allow in Privacy & Security" and add Back to the declined screen (`:188`).
3. **Overview.** Needs-you card collapses to a 56 pt line when empty (spring on `frame(height:)`), month chart rises into the space and draws elapsed days only (ink past, accent today); hero loses the hatch and its secondary text goes to 85%; the four tinted counter `Tile`s become one `CountsLine` (numerals `title`, labels `small`, `text2`); "Where files went" uses a single icon style; card radius 14, padding 16.
4. **Island (notch skin).** Compact width `max(290, notch.width + 140)`; row 1 notch height with the 24 pt tile, cutout, chip; row 2 centred line; the chip shows only until the first dwell, then becomes a 28 pt icon-only key (stops the `⌥…` truncation); expanded "Extra copy · 120 MB · id…" gets a wider text column, no truncation of the size; bottom melt confined to the last 12 pt with the esc row above it on solid black; two lip glass buttons are 28 pt with labels. Capsule: 320 × 38, glass at 92%, secondary text `K.glassText2`. Capsule-as-default stays an owner call.
5. **Activity.** Groups newest first; one date format; Quick Look thumbnails plus destination shelf emoji on rows; remove the orphan "Don't rename files like this" heading unless it has its control; paths and counts in the Activity detail in `.system(.footnote, design: .monospaced)` with an `accessibilityLabel` that reads "moved to Documents"; title in `TS.title` serif.
6. **Sorting.** Banner capped at 160 pt so Approach cards are visible; one greens rule (mint ink for banner and hero, system green only for native switches); one icon style in watched folders; the "Downloads → My Shelves → Documents" chip becomes plain SF text.
7. **Quick settings.** Off tiles get a weight and glyph change (not only the dot), text at `text2` 4.5:1 or better; 12 pt grid with equal gutters; the Sorting row becomes the same shape as tiles.
8. **Sidebar.** One selection language: `K.rowSelected` plus an accent dot; the Activity filter pill and Overview mint stop competing.
9. **Tray (v2, behind a flag, files only).** Per `tray.md`: drag monitor with pasteboard check, 250 ms dwell, multi-monitor by cursor screen, `⌘T`, `⌘V`, Finder Service, plan rows with the basis on line two, destination nowrap, ✕ 44 pt, `⌥↑ ⌥↓` reorder, static "Planning 3 of 4", the security invariants.
10. **Docs.** Rewrite `05-accessibility.md` for the current surfaces (island, onboarding, Overview) with the contrast table in this file.

## What to check on a real Mac before sign-off
- Contrast of every capsule and popover state on three real wallpapers (the table gives floors, not measurements).
- Compact island chip width on a 14-inch and a 16-inch MacBook Pro (notch widths differ).
- The melt: that the esc row is on solid black at both expanded heights.
- Derived dark `fg` values for `Tint.rule`, `Tint.where`, `Tint.neutral`.
