# Proposal B · Glass Shelf

Mockup: [proposal-b.html](proposal-b.html). References: Butter (neutral shell, coloured things, real UI), Hyperfocus (dark, quiet, native), Taskade (soft pastel pair). Revised 2026-10-30 after the panel reviews.

**Panel verdict.** B is rejected for the window and kept for the island capsule only. What survives: the capsule-first island, the shelf strip idea (as a possible Overview detail), and the rule that text on glass sits on a 92% fill.

## Idea
Lean into macOS 26. Colour comes only from meaning: a segmented shelf strip and pill tints. The island's capsule skin is the default, so Kanso looks like part of the system.

## Layout
- **Overview (as proposed, not adopted):** floating glass sidebar (200 pt) and content pane; a 72 pt numeral card beside the Needs-you card; one card "Where N files went" with a proportional shelf strip, legend and counts as pills. The month chart moves to Activity.
- **Why the window is rejected:** floating panes need `.hiddenTitleBar` and a non-opaque window. That fights the fixed 1170 × 772 `NavigationSplitView` with its native toolbar title and `SoftTopEdge`, and nests glass on glass, which breaks Apple's rule that glass belongs to the controls layer.
- **Island (adopted for the capsule):** capsule skin by default (one row, 320 × 38, radius 22 compact; 480 wide, radius 30 expanded; 6 pt below the menu bar). The notch skin remains an option and is identical to A's. Buttons inside are solid with a 3:1 stroke; glass is the container only.
- **Tray:** the same glass capsule. There is no ear geometry and no cutout. The plan puts the basis on a second line under the name.

## Island: real structure
The capsule has no hardware coupling, so it is one row (tile, centred-left line, optional count badge, shortcut chip) at 38 pt, as in `IslandBody.compact`. Expanded it keeps the same content order as the notch skin (head, pair, actions, ask field, lip) without the 32 pt clear band. Its differences from A and C: no ears, no black, glass at 92%, text in `text` / `glassText2`.

## Tokens

### Type (SF Pro only)
| Token | Size / line | Weight |
|---|---|---|
| `display` | 34 / 38, tracking -0.02 em | 700 |
| `numeral` | 72 / 72, tracking -0.04 em | 700 |
| `title` | 22 / 28 | 600 |
| `heading` | 17 / 22 | 600 |
| `emphasis` | 15 / 20 | 600 |
| `body` | 13 / 18 | 400 |
| `small` | 12 / 16 | 400 |
| `meta` | 11 / 14 | 600 |

### Colour and contrast
The original `text2` values (light `#5C5C63`, dark `#A6A6AD`) were only measured on the solid fallback (6.36). On a translucent pane the ratio depends on the wallpaper; at the worst case (white 55% pane over mid-green wallpaper) it was 4.47, a fail. Revised:
| Token | Light | Dark |
|---|---|---|
| `pane` fill | white 72% over blur 28 | `#2A2A2C` 85% over blur 28 |
| `text` | `#18181B` (8.93 on the worst case, white 72% over black) | `#F5F5F7` (8.12 on the worst case, `#2A2A2C` 85% over white) |
| `text2` | `#45454B` (4.80 worst case, 9.52 on white) | `#C0C0C7` (4.89 worst case) |
| `controlStroke` | `#6E6E73` | `#9C9CA2` |
| `capsule` fill | `#FBFAF8` 92% | `#2A2A2C` 92% |
| `mint` / `butter` / `periwinkle` | as A (6.04 / 5.32 / 5.70 light; 8.53 / 8.11 / 7.97 dark) | |
| shelf strip | `#7FB89C`, `#9DB0E8`, `#E8C879`, `#B8A8E0`; not text, 3:1 against the pane is not required for decorative fills but each segment carries a legend label | |
Verification still required on three real wallpapers (bright, dark, busy) in both modes; the table gives the worst-case floor, not a measurement of a real desktop.

### Radii and spacing
Panes 30, cards 26 (concentric: 30 - 16 gap = 14 minimum inner radius, so cards 26 only work with 4 pt inset), buttons 99, ask field 22, capsule 22 / 30. Spacing 4 / 8 / 12 / 16 / 20 / 30.

### Motion
| Token | Value |
|---|---|
| `ease.glass` | `cubic-bezier(.3,.9,.3,1)` |
| `spring.settle` | response 0.4, damping 1.0 |
| `dur.base / island` | 180 / 360 ms |
| Needs-you card to island hand-off | **220 ms cross-fade** (the glass morph is cut) |
**The glass morph is removed.** `glassEffectID` morphs only between views inside one `GlassEffectContainer` in one view tree. The Needs-you card lives in an `NSWindow` and the island in a separate `NSPanel`, so no morph can run between them. When the island opens from a card the card's buttons dim for 120 ms and the island fades in over 220 ms. Reduce Motion: 200 ms cross-fade, same as without it.

## Material
`glassEffect(.regular, in: ...)` on the capsule only; `GlassEffectContainer` around adjacent buttons inside it only if the buttons are glass (they are solid here). Fallback below macOS 26: `.regularMaterial` with a `controlStroke` edge; Reduce Transparency and Increase Contrast: solid fills with a 1 pt stroke.

## Mapping to `Theme.swift`
| Change | Where |
|---|---|
| `K.glass` stays at 92% light / 92% dark; add `K.glassText2` | `enum K` |
| Capsule becomes the default skin when the user has no notch preference | `Island.swift` (`relayout`) |
| Window panes, `.hiddenTitleBar`, transparent window | **not adopted** |
| Shelf-strip view fed by `Stats.shelves` | optional, `OverviewPage.swift` |

## Risks
- The capsule default changes the look for notch Macs (the owner chose the notch skin as the default look; this stays an owner call).
- Legibility on busy wallpapers is bounded by the 92% fill, which also makes the capsule less "glassy".
