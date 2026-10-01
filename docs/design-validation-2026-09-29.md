# Design validation, 2026-09-29

Scope: the UI/UX decisions in `PRODUCT.md` (sections "The island and shortcuts", "Smart Eject", "Settings structure", "Onboarding") and `CONTEXT.md`, reviewed **as decisions, before implementation**. Nothing was rendered, so visual claims are marked where they need checking in the designs.

Skills applied: `emil-design-eng` (animation decisions), `apple-design` (fluid motion, materials, principles), `apple-hig` (`keyboards.md`, `privacy.md`, `onboarding.md`), `better-interface` (its escalation triggers; the six `better-*` domain skills were not run because there is no rendered UI yet), `libraries-dev` (Border beam, Thinking orbs), `axiom-design` (Liquid Glass), `axiom-ai` + agentic security (ask field).

## Findings

| # | Severity | Finding | Source | Resolution for the designs |
|---|---|---|---|---|
| 1 | HIGH | **Custom controls lose their focus indicator.** The current build hides the system focus ring (`focusEffectDisabled` in `app/Sources/Kanso/*.swift`) and nothing replaces it, so keyboard users can't see focus. | better-interface trigger "keyboard-reachable control with no visible focus indicator" | Every custom control gets a visible focus ring: 2 pt mint **ink** (`#2E5A4B`, dark: lightened mint) following the control's corner radius, offset 2 pt. Design it on buttons, rows, switches, tiles and the island's action row. |
| 2 | HIGH | **Motion without reduced-motion handling** in the new pieces: island springs, the icon morph, the border beam, count-up and rolling digits, bar growth. (The sweep already had a rule.) | better-interface trigger; apple-design §14; Border beam's rotate types "do not handle prefers-reduced-motion" | Reduce Motion: the island cross-fades (opacity 200 ms) instead of springing; the icon shows its final state; no beam; numbers appear at their value; bars appear full. Nothing is conveyed by motion alone: the text line and the final icon carry the state. Reduce Transparency: glass becomes a solid surface (light `#FBFAF8`, dark `#2A2A2C`). Increase Contrast: surfaces gain a 1 pt ink border. |
| 3 | HIGH | **Switches and selection in pastel mint would fail non-text contrast.** Pastel on the window is about 1.1:1; switches, the selected tab and progress bars need 3:1 against their surroundings. | better-interface trigger (contrast); computed below | **Pastels are for surfaces only.** On-state switches, selection indicators, focus rings, progress fills and chart marks use the **ink** of the pair (mint ink `#2E5A4B` is 7.8:1 on white). Pastel buttons get a hairline ink border at 25% or sit on a white card, so their shape is visible (pastel on window alone is 1.1:1). |
| 4 | HIGH | **The island is invisible to VoiceOver.** A non-activating panel never takes focus, so a spoken user never hears a notice. | better-interface (accessible names); apple-design (utility of feedback) | Each notice posts a VoiceOver announcement ("Renamed Scan_0012 to Invoice-Vattenfall-2026-03. Press Option-Command-K to open.") and ⌥⌘K moves VoiceOver focus into the expanded island. Every icon-only control (gear, Open Kanso, keycap buttons) has a label. |
| 5 | MEDIUM | **Glass stacked on glass** on screens without a notch: the capsule is Liquid Glass, and the decided "Liquid Glass controls inside the island" would put glass buttons on a glass surface, where legibility collapses. | apple-design §12 ("never stack a light translucent surface on another"); axiom-design Liquid Glass (remove the inner glass, keep the outermost) | Inside the **black** notch island, controls are Liquid Glass (`.buttonStyle(.glass)`, grouped in a `GlassEffectContainer`). Inside the **glass capsule**, controls are solid pastel-with-ink buttons, not glass. |
| 6 | MEDIUM | **"Liquid Glass on all screens" would put glass on content.** Liquid Glass belongs to controls and navigation layered over content, not to content itself (stat cards, lists, settings rows). | axiom-design Liquid Glass | Glass only for floating and navigation chrome: the window toolbar and tab bar, the popover, the island, floating action bars. Cards, rows and charts are solid (white or pastel). "Island design language" means the same shapes, springs, keycaps and palette, not glass everywhere. |
| 7 | MEDIUM | **Border beam on a finished rename** goes against the library author's placement rules (beam = work in progress over 3 s; nothing under 2 s) and against "don't stack effects" (the beam and the ASCII sweep would both run on the island). | libraries-dev decision rules | **Open, the owner's call:** design variant A (sweep plus one single pass of a `mono`, sage-tinted beam, no loop) and variant B (sweep only). The beam's certain home is work in progress: the island while OCR or reading takes over 3 s, and the ask field from submit until the answer (`line` type). |
| 8 | MEDIUM | **Spinners have no designed replacement.** Waiting states (a big scan being read, the ask field answering, "still downloading" in Activity) need a component. | libraries-dev (Thinking orbs: 2 s or more, beside a text label) | Thinking orb at 20 pt beside a label ("Reading page 1…", "Thinking…"), shown only after 2 s. Under 2 s, nothing. |
| 9 | MEDIUM | **The island's spring needs values and an interruption rule.** "Fluid" has to be concrete, and Esc during expansion must reverse from where the island is. | apple-design §3–4, §7; emil-design-eng | Expand and collapse: critically damped (damping 1.0, response 0.35), no overshoot (no momentum gesture precedes it). ⌥⌘K-opened: response 0.25. Always interruptible from the current shape; collapse retraces the expansion path (down from the notch, back up into it). The capsule "materializes": blur and scale animate together on enter, not a plain fade. Keyboard repeats (← → through notices) don't animate. |
| 10 | MEDIUM | **Model-proposed action labels are vague** ("↩ Do it"). | apple-design §16 ("direct, specific labels"); better-interface writing | Preview buttons name the action and count: "↩ Move 3 files", "↩ Rename", "⌘⌫ Move 2 to Trash". |
| 11 | LOW | **Serif numerals need size-specific tracking** (the stat cards and statement use New York). | apple-design §15 | Large serif numerals: tracking −0.02 em, leading 1.05; labels under them at 0 or +0.01 em. |
| 12 | LOW | **"Move all to Trash…" confirmation alert.** The action is reversible (Put Back), and Apple says to reserve confirmations for irreversible actions. | apple-design §16 Agency | Keep one confirmation because it's bulk, but make it the island's inline confirmation ("Move 9 copies (340 MB) to Trash · ⌘⌫"), not a modal alert. |

## Contrast check (WCAG, computed)

| Pair | Ink on pastel | White on pastel | Pastel on window `#F4F2EE` | Ink on white |
|---|---|---|---|---|
| mint `#CFE8D8` / `#2E5A4B` | 6.04 | 1.30 | 1.16 | 7.84 |
| rename `#D9E0FA` / `#3C509A` | 5.70 | 1.31 | 1.17 | 7.48 |
| duplicate `#F7E4B5` / `#7E531B` | 5.32 | 1.26 | 1.12 | 6.69 |
| rule `#E5DCF7` / `#5A4687` | 5.98 | 1.32 | 1.18 | 7.89 |
| where `#D0ECEC` / `#1E666B` | 5.33 | 1.24 | 1.11 | 6.63 |
| neutral `#ECEAE5` / `#48484D` | 7.56 | 1.20 | 1.08 | 9.09 |

All ink text passes AA (4.5:1). White text on any pastel fails, which confirms "no white-text buttons". Pastel surfaces are nearly invisible against the window, which leads to finding 3.

## Confirmed as sound

- ⌥⌘K: the HIG reserves the Space combinations, and "avoid Control as a modifier" rules out ⌃⌘Space.
- The key map: no bare letters, Finder conventions, plain ⌫ never trashes; plus the HIG's "don't repurpose standard shortcuts" (⌘Z, ⌘R, ⌘O, Space keep their Finder meanings).
- The onboarding permission step matches the HIG's pre-alert rules (one Continue button, no "Allow", no escape before the system prompt).
- Silent sorts and rare notices match Emil's frequency rule and apple-design's "utility" (over-feedback trains people to ignore all of it).
- Spatial consistency: the popover grows from the menu bar icon, and the island grows from and returns to the notch.
- ADR 0001 matches the agentic-security guidance: deterministic confirmation before side-effectful tools, and untrusted content can't trigger them.

## Not verified

Rendered legibility of the glass capsule over busy wallpapers, dark-mode pastel values, and motion timing all need to be checked in the designs and then in the build.
