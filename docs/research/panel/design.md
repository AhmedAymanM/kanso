# Design panel review: proposals A/B/C, audit, Tray

Verdict: the audit is mostly right (I confirmed #2, #4, #6, #8, #9, #14 in the screenshots). The proposals are less distinct and less buildable than they claim.

## BLOCKER

1. **The island and Tray are identical in all three mockups.** The CSS is copy-pasted; only the bottom radius changes (34/38/28). Hardware notch corners are fixed, so that axis isn't a design choice. Fix: either drop the island from the A/B/C comparison, or give each a real difference (A: black, 0.5 pt top highlight; B: capsule default; C: 12 pt padding with a mono time column).
2. **B's signature morph can't be built.** `glassEffectID` morphs only inside one `GlassEffectContainer` and one view tree. The Needs-you card is in an NSWindow and the island is a separate NSPanel. Fix: cut the morph, or do a 220 ms cross-fade with a matched-geometry fake. Also, nested glass panes break Apple's rule that glass is for the controls layer, and B's `.hiddenTitleBar` plus transparent window fights the fixed 1170x772 `NavigationSplitView`. Reject B for the window; use it for the capsule only.
3. **The mockups misstate the baseline.** The real compact island (`island-compact.png`) is two rows: a 48 pt icon tile with the chip on top, text centred below. The mock draws one 44 pt row with a 24 pt icon. The notch is a rectangle with square top corners and no hardware cutout, so the notch geometry is untested. Redraw with a 200x32 pt cutout, an 80 pt-wide compact island, and the 48 pt tile.

## MAJOR

4. **Tray drag target is under-specified.**
   - "Within 120 pt" never says how a drag is detected. Fix: a global `leftMouseDragged` monitor plus `NSPasteboard(name: .drag).changeCount`; the panel stays `ignoresMouseEvents = true` until a compatible drag is live.
   - There is no dwell. Fix: grow after 250 ms inside a 160x44 pt zone at top centre, and shrink only after leaving 220 pt (hysteresis). Otherwise dragging a window or file to the menu bar triggers it.
   - A 460 pt island covers other apps' status items. Fix: the live drop zone is the island only; the window-drag case is ignored.
   - Multi-monitor is missing. Fix: use the screen under the cursor. External displays get the capsule at menu-bar bottom + 8 pt. A full-screen app hides the menu bar, so don't grow.
   - File promises (Mail, browser images) can't be bookmarked. Say they are refused or saved to a temp folder.
   - The 26 pt-padding well is a small target; make the whole island the drop target.
5. **Mock plan row breaks.** `.conf` is a fixed 88 px column holding "asks Apple Intelligence" and "reads text on this Mac", so they wrap to two lines. This contradicts "never truncate". Fix: `auto` column, `white-space:nowrap`, or move the basis under the name at 11 pt.
6. **C's primary button fails contrast.** `.ev button.p` is `#fff` on dark `--acc` `#8FD3B0`, about 1.6:1. Fix: `#0B2A1F` text.
7. **A violates its own scale.** The mock uses 15 px (`.card h3`, `.sub`), 16, 18 and 10 px; the spec lists 7 steps, with the 64 numeral filed under `display` (40). Fix: add `numeral` 64 and `emphasis` 15, which makes 9 steps, or fix the mock. Drop 10 px (below the 11 minimum).
8. **A says "the window never uses glass".** AGENTS says buttons use interactive `glassEffect`, and macOS 26 gives the sidebar and toolbar glass automatically. Fix: say "no glass on content cards".
9. **Audit #15 overrides an owner decision.** The "ears melting into glass" edge is a recorded decision (AGENTS, Droppy-style). Mark it "owner call" instead of a defect. The black-to-grey smudge is real: fade over the last 12 pt only, with the "esc" text on solid black.
10. **Only Overview is mocked.** Nothing shows Activity, Sorting, the sidebar, a toolbar, or traffic lights. States are missing: hover, focus ring, pressed, disabled, and A's collapsed 56 pt Needs-you (the common state). Fix: add two more frames per direction, Activity detail and Overview with nothing to do. Make `.notch` states toggle on click; right now the JS only switches the theme.

## MINOR

11. **The serif is native, but the mock isn't.** `ui-serif` is New York in Safari and Georgia in Chrome, so the mock may mislead. In SwiftUI use `.font(.system(size: 40, design: .serif))` with `.tracking(-0.4)`. For the 64 numeral use `.monospacedDigit()`; New York's proportional digits make counters jitter. Extend the serif to the Activity title (the toolbar stays 15 pt SF).
12. **Radii:** A's card radius (20) is bigger than the window (18), and card padding 20 makes the concentric inner radius 0. Use `ConcentricRectangle` on 26+; on 14-15 use outer minus padding, minimum 8.
13. **Hit areas:** the Tray ✕ column is 22 px with 50% opacity, against the spec's 44 pt. Use `contentShape` 44x44.
14. **The "Needs you" collapse** needs a spring (response 0.35) on `frame(height:)`, not a layout snap.
