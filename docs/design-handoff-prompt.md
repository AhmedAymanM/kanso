# Design handoff: Kanso v2 designs in Pencil

You are the product designer for **Kanso**, a calm macOS menu bar app that keeps Downloads, Desktop and Documents tidy. A long design review (2026-09-29) changed how Kanso talks to people and simplified every screen. Your job: **update the design system and design the new screens in Pencil**, keeping all existing designs intact.

## Where things are

- **Design file:** `~/Desktop/projects/kanso-designs/untitled.pen`. Access it only through the Pencil MCP tools (`get_app_state`, `execute`, `read_skill`, `get_style`); never read `.pen` files directly. Start with `mcp__pencil__read_skill()` and then `read_skill({path: "execute.md"})`, and follow them exactly.
- **Current design system:** `~/Desktop/projects/kanso-designs/DESIGN_SYSTEM.md` (v1, sage accent).
- **Read these before designing** (all in `~/Desktop/projects/kanso/`):
  - `PRODUCT.md`: the source of truth. Sections that matter most: "The island and shortcuts", "Smart Eject", "Settings structure", "Onboarding", "Duplicates", "Trust mechanics", "Roadmap".
  - `CONTEXT.md`: the vocabulary. Use these words exactly in all copy (shelf, tray, watched folder, island, compact/expanded island, ask field, quick settings, below-the-notch mode, provably spent).
  - `docs/design-validation-2026-09-29.md`: **12 findings you must apply** (focus rings, reduced motion, pastels only on surfaces, VoiceOver, no glass on glass, no glass on content, spring values, action labels, serif tracking).
  - `docs/adr/0001-ask-field-destructive-actions.md` and `docs/adr/0002-trash-only-provably-spent-files.md`: the trash rules that the ask-field and duplicate designs must show.
  - `design-brief.md`: the original brief, for context (older decisions there are superseded by PRODUCT.md).
  - `docs/design-refs/`: visual references. The Linear status morph (`linear-status-*.png`, `.gif`) shows how the island's icon morphs; the analytics micro-interactions (`analytics-microinteractions-*`) and `insight-cards.jpg` show the Insights card style.
- **Web references:** Droppy's island (https://getdroppy.app: "black at the notch, melting into glass"), NotchRail's notch-less floating shelf, the libraries.dev Border beam and Thinking orbs, Apple's Dynamic Island.

## Ground rules

1. **Keep every existing layer.** Don't modify, move or delete the four `FINAL — Kanso — …` frames or the `PROTOTYPES & EXPLORATION` frame. Before your first edit, save a copy of the file as `untitled.backup-2026-09-29.pen` next to it (if the tools can't copy files, skip this and say so).
2. **Add new top-level frames prefixed `v2 — Kanso — …`**, placed to the right of or below the existing ones (use `FindEmptySpace`). Name every node.
3. **Light and dark for every screen** (two copies side by side, or a themed variable set with `mode: light/dark`, using both themes).
4. **Design system as variables:** define the v2 tokens with `SetVariables` (themed light/dark) and use them everywhere; reuse components (`reusable: true`) for buttons, keycaps, chips, switches, rows, cards and the island.
5. Take a screenshot of each finished frame (`TakeScreenshot`) and check it against the rules below before moving on.

## The v2 design language (summary; details in PRODUCT.md and the validation doc)

- **Pastel pairs**, each color keeping its meaning: mint `#CFE8D8`/`#2E5A4B` (brand, Kanso, sorted) · periwinkle `#D9E0FA`/`#3C509A` (rename) · butter `#F7E4B5`/`#7E531B` (duplicate) · lavender `#E5DCF7`/`#5A4687` (rule) · aqua `#D0ECEC`/`#1E666B` (where should this go) · stone `#ECEAE5`/`#48484D` (neutral). Window `#F4F2EE`, card `#FFFFFF`. **Pastel for surfaces and button fills; the deep ink for text, icons, switch on-states, selection, focus rings, progress and chart marks. No white text on pastel.** Pastel buttons get a hairline ink border at 25% or sit on white. Dark mode: surfaces are the ink hue at about 25% over `#1C1C1E`/`#2C2C2E`, text is a lightened pastel. Propose exact dark values and check contrast (4.5:1 text, 3:1 controls).
- **Mint is the single brand accent.** Cards are tinted by what they measure, never for decoration.
- **Type:** SF Pro (Inter as stand-in); New York (serif) for statements and big numerals, tracking −0.02 em, leading 1.05.
- **Materials:** Liquid Glass only for floating and navigation chrome (the island, popover, toolbar and tabs, floating action bars). Content (cards, rows, charts) is solid. Never glass on glass.
- **Motion** (annotate it on frames): critically damped springs (response 0.35; 0.25 when opened with ⌥⌘K), interruptible, collapse retraces the expansion. Reduced motion means cross-fades. Thinking orb beside a label for waits over 2 s. Every state is readable without motion.
- **Visible focus ring** on every control: 2 pt mint ink, following the corner radius.

## Deliverables, in order

1. **`v2 — Kanso — Design System`**: the token table (light/dark swatches with contrast ratios), type scale, spacing, radii, elevation, and a component sheet (buttons: primary pastel+ink, secondary, tertiary link; keycaps; switch; chips and badges; settings row; expandable feature row; stat card; highlight chart card; island compact, expanded and capsule; thinking orb; focus ring) with every state (default, hover, pressed, focused, disabled).
2. **`v2 — Kanso — Island`**, on a menu bar backdrop (notch and notch-less variants). Compact notices: rename (ASCII-sweep frames plus **variant A with one mono sage beam pass / variant B sweep only**; this is the owner's open choice), duplicate held, Smart Eject ("Installed Figma · installer moved to Trash · ⌘Z"), counting up ("3 renamed"), the sorting-off 24-hour reminder, the ⌥⌘K hint (first days). Expanded: a notice's details with actions and key hints, the counted-up list, the **overview state** (Needs you rows, Recently with undo, Open Kanso plus gear icons; the "All quiet" line when empty), and the v1.1 **ask field** (subtle glass field, a proposed action "↩ Move 3 files → 🎓 Uni", a trash proposal gated by ⌘⌫ with a Kanso-written summary, an answering state with a thinking orb and line beam). Black island on notch screens; glass capsule below the menu bar on notch-less screens and in below-the-notch mode; show the "yields to NotchNook" behavior as an annotated storyboard.
3. **`v2 — Kanso — Quick settings`**: the popover under the tray icon. Sorting switch, the turn-off duration prompt (15 minutes · 1 hour · until tomorrow · until I turn it on), watched folders with switches and "not allowed · Open Privacy Settings", Renaming/Tagging/Duplicates/Smart Eject tiles, the "2 need you · Show Kanso ⌥⌘K" row, model status, Settings and Quit. **No stats.**
4. **`v2 — Kanso — Settings`**: a standard macOS Settings window with Liquid Glass toolbar tabs, **General · Features · Rules · Privacy & AI**. Features: Sorting, Renaming, Tagging, Duplicates, Smart Eject rows (a switch, one sentence, a reads-contents badge), plus each row expanded (the exact contents are in PRODUCT.md "What each Features row keeps"; Duplicates: where copies go, auto-trash after N days off by default). Rules: only the user's own rules, "+ Add rule" with the condition editor; no built-in rules, no Types screen. General: its 6 controls. Privacy & AI: mostly statements plus About.
5. **`v2 — Kanso — Window`**: Overview in 4 blocks (statement plus Sort Now; Needs you; This month with 4 tinted stat cards with serif numerals and deltas, 2 highlight chart cards styled after the analytics reference, and "See all insights" expanded; Shelves by size), and Activity (list plus detail for rename, duplicate, sorted, batch, waiting, Smart Eject; **no timeline**; "How Kanso decided" kept).
6. **`v2 — Kanso — Onboarding`**: the 3 steps (folders with the single-Continue permission explanation; the island demo with "press ⌥⌘K"; existing files), plus the conditional Apple Intelligence step and the "Kanso needs at least one folder to work" screen.
7. **Update `DESIGN_SYSTEM.md`:** first copy the current file to `DESIGN_SYSTEM-v1.md` in the same folder, then rewrite `DESIGN_SYSTEM.md` for v2 (same structure as v1: principles, tokens with light/dark, typography, spacing, shells, components, copy voice, screen inventory, SwiftUI implementation notes), pointing to the `v2 —` frames as the source of truth.

## Copy voice

Calm, short, no first person. Say what happened and that it can be undone. Use CONTEXT.md terms ("shelf", "watched folder", "Move to Trash", never "delete"). Name actions specifically ("Move 3 files", not "Do it").

## When you finish

Report: the frames you created (names and ids), the variables you defined, anything you couldn't do, the open choice (beam variant A or B) with your recommendation after seeing both, and any decision in PRODUCT.md that didn't work visually (describe it; don't silently change it).
