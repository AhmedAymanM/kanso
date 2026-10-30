# Accessibility and first-run review

Scope: `05-accessibility.md`, `04-unhappy-paths.md`, `Onboarding.swift`, proposals A/B/C tokens, `tray.md`. Ratios are WCAG 2.x, computed from the specs. Disk-full and eject handling were checked against the spec only.

## Contrast

| Pair | Ratio | Verdict |
|---|---|---|
| A light text2 `#6E6E73` on window `#F4F2EE` | 4.54 | passes, at the floor |
| `K.text3` `#8A8A8E` on window / card (light) | 3.08 / 3.44 | fails AA text |
| `K.text3` `#8E8E93` on card (dark) | 4.27 | fails |
| A dark text2 `#A1A1A6` on card | 5.42 | passes |
| A mint ink `#2E5A4B` on `#CFE8D8` | 6.04 | passes |
| Butter `#7E531B` on `#F7E4B5` | 5.32 | passes |
| Periwinkle `#3C509A` on `#D9E0FA` | 5.70 | passes |
| B light text2 `#5C5C63` on pane `#FBFAF8` | 6.36 | solid fallback only |
| C light text2 `#66666B` on `#FAFAF8` | 5.46 | passes |
| C dark accent `#8FD3B0` on `#19191C` | 10.12 | passes |
| Light separator (black 10%) on window | 1.25 | fails 3:1 for control edges |
| White 40% on black (`Onboarding.swift:258`) | 3.66 | fails |
| White 35% on black (`Onboarding.swift:261`) | 3.00 | fails |
| White 55% / 62% on black (Tray notch) | 6.25 / 7.84 | passes |

## BLOCKER

1. **False privacy claim on first run.** `Onboarding.swift:63` and `:154` say "Nothing leaves this Mac." Auto-update is on by default (`Settings.swift:138`) and calls api.github.com (`UpdateChecker.swift:46`). Fix: "Your files never leave this Mac. Once a day Kanso checks GitHub for a new version; turn that off in Settings."
2. **Focus is invisible in the first-run window.** `Onboarding.swift:46` applies `.focusEffectDisabled()` to the whole view, which removes the ring from the folder checkboxes (`:69`) and the footer buttons. Only `choice()` draws its own ring. Fix: delete the modifier, add `.focusRing` to each folder row.

## MAJOR

3. The caption "or click the island" (`:133`) is false: `DemoIsland` has no tap gesture. Fix: add `.onTapGesture { demo.pressed = true }` with button semantics, or cut the words.
4. The 10-second auto-expand (`:141`) changes the content under VoiceOver with no announcement and no focus change. Fix: skip the timer when `NSWorkspace.shared.isVoiceOverEnabled`, or announce "That's the island" and keep focus on Continue.
5. Denied folders are paused silently (`:111`). The island step never says which folder is off, and the declined screen (`:188`) has no Back and no retry. Fix: list each paused folder with "Off · Allow in Privacy & Security", and add Back. Whether `refreshAccess` picks up a later grant is unverified, so the copy "picks them up as soon as you do" is a promise nothing checks.
6. `05-accessibility.md` specifies a rule-table window (S0–S6, rule rows, ⌘⏎ Apply) that the shipped app no longer has. There is no spec for the island, onboarding or Overview. Fix: rewrite it for the current surfaces, with the table above.
7. Island announcements use `.high` priority (`Island.swift:537`). High interrupts speech; the Tray spec asks for polite. Fix: `.medium` for confirmations, `.high` only for failures.
8. The Tray's "Rows reorderable" (`tray.md`, Carry) has no keyboard path, and the keyboard table lacks one. Fix: ⌥↑ / ⌥↓ moves a row, as the rule list does.
9. `K.text3` is used for text (`:133`, `Theme.swift:66`). Fix: light text3 `#6B6B70` (4.74 on window), dark `#9C9CA2` (5.10 on card). Keep the old grey for dividers and icons.

## MINOR

10. Proposal B's text sits on a translucent pane. The 6.36 figure is the solid fallback only. Fix: measure on three wallpapers, dark and light.
11. Onboarding choice cards (`:180`) use the 1.25:1 separator as their only edge. Fix: a 3:1 stroke.
12. Dynamic Type: `05` requires system text styles, but Onboarding and the island use fixed `TS` sizes throughout. macOS has no Dynamic Type, so the rule can't be tested. Fix: drop the rule and test at the 600 pt minimum width.
13. The compact island truncates the shortcut chip to "⌥…" (audit item 14). Fix: icon-only chip, or a wider chip.
14. Reduce Motion gates `IslandBeam` (`IslandViews.swift:80`), so Tray planning shows no progress. Fix: static "Planning 3 of 4".
15. "Open System Settings" (`:151`) uses a Siri-Settings deep link that is unverified on macOS 26/27.

## Trust on first run

Good: "Only sort new files" is preselected (`cleanup = false`), and the folder prompt is explained before macOS asks. Fix the false privacy line first, because it undermines the rest.
