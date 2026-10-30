# Proposal B · Glass Shelf

Mockup: [proposal-b.html](proposal-b.html). References: Butter (neutral shell, coloured things, real UI), Hyperfocus (dark, quiet, native), Taskade (soft pastel pair).

## Idea
Lean into macOS 26. The window is a pair of floating glass panes over the user's wallpaper (sidebar + content), all text in SF Pro, no serif. Colour comes only from meaning: a segmented shelf strip, pill tints. The island and window share one material, so Kanso feels like part of the system.

## Layout
- **Overview:** the sidebar becomes a floating glass pane 200 pt wide; content pane holds the headline, a 56 numeral card and the Needs-you card side by side, then one card "Where N files went" containing a proportional shelf strip, legend and the counts as pills. No chart of days (the strip replaces it; the month chart moves to Activity).
- **Activity / Sorting:** list pane and detail pane both glass; the hero pastel blocks become tinted glass (`glassEffect(.regular.tint(...))`).
- **Island:** capsule skin is the default (rounded 38); notch skin still black. Buttons are interactive glass.
- **Tray:** a glass well with a dashed outline on the notch skin; same on capsule.

## Tokens

### Type (SF Pro only)
| Token | Size / line | Weight |
|---|---|---|
| `display` | 34 / 38, tracking -0.02 em | 700 |
| `numeral` | 72 / 72, tracking -0.04 em | 700 |
| `title` | 22 / 28 | 600 |
| `heading` | 17 / 22 | 600 |
| `body` | 13 / 18 | 400 |
| `small` | 12 / 16 | 400 |
| `meta` | 11 / 14 | 600 |

### Colour
Surfaces are translucent; text colours solid. Fallbacks are the solid values in the last column.
| Token | Light | Dark | Solid fallback L / D |
|---|---|---|---|
| `pane` | white 55% over blur 28 | white 7% over blur 28 | `#FBFAF8` / `#2A2A2C` |
| `paneStroke` | white 70% | white 14% | black 10% / white 12% |
| `text` / `text2` | `#18181B` / `#5C5C63` | `#F5F5F7` / `#A6A6AD` | same |
| `mint` bg/fg | `#CFE8D8` / `#2E5A4B` | `#2D3A37` / `#BFE3D0` | |
| `butter` | `#F7E4B5` / `#7E531B` | `#453828` / `#F3D79B` | |
| `periwinkle` | `#D9E0FA` / `#3C509A` | `#31374E` / `#C9D3FF` | |
| shelf strip | `#7FB89C`, `#9DB0E8`, `#E8C879`, `#B8A8E0` | same at 85% | |
Selection pill: mint bg, mint fg, 600 weight.

### Radii and spacing
Panes 30, cards 26, buttons 99, ask field 22, notch bottom 38. Spacing 4 / 8 / 12 / 16 / 20 / 30. Pane gap 16. Content max 980.

### Motion
| Token | Value |
|---|---|
| `ease.glass` | `cubic-bezier(.3,.9,.3,1)` |
| `spring.settle` | response 0.4, damping 1.0 |
| `dur.base` / `island` | 180 / 360 ms |
| Glass morph (container to container) | `GlassEffectContainer` + `glassEffectID`, 360 ms |
Glass morphing is the signature: the Needs-you card's buttons merge into the island's buttons when it opens. Reduce Motion: no morph, 200 ms cross-fade.

## Material
Everything is glass or tinted glass: `glassEffect(.regular, in: RoundedRectangle(30))` on the panes, `.regular.tint(mint)` on selection, `GlassEffectContainer` around adjacent buttons so they merge. Window background must be transparent or a wallpaper-friendly `NSVisualEffectView`. Fallback below macOS 26: `.regularMaterial` + stroke; Reduce Transparency and Increase Contrast: solid fills with a 1 pt stroke (the contrast check is already listed as not done in AGENTS.md).

## Mapping to `Theme.swift`
| Change | Where |
|---|---|
| New `K.pane`, `K.paneStroke` with solid fallbacks; `K.window` becomes clear on 26+ | `enum K` |
| Remove serif use (`Font.design(.serif)`) from Overview/Quick settings | `OverviewPage.swift`, `QuickSettings.swift` |
| `card()` modifier becomes `pane(radius:)` that picks glass or solid | `extension View` |
| `GlassSurface` generalised to `Pane` with tint parameter | `GlassSurface` |
| Window: `.windowStyle(.hiddenTitleBar)` + `NSWindow.isOpaque = false`; conflicts with the fixed 1170 x 772 `NavigationSplitView` setup | `Shell.swift`, `MainView.swift` |
| Add shelf-strip view fed by `Stats.shelves` | `OverviewPage.swift` |

## Risks
- Highest engineering cost: the current window is a native `NavigationSplitView` with a custom `SoftTopEdge`; floating panes mean a different shell.
- Legibility depends on the user's wallpaper; needs contrast testing on busy wallpapers and with Reduce Transparency.
- Loses the serif, Kanso's one clear identity cue.
