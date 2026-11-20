# Accessibility

Target: every surface works fully by keyboard, with VoiceOver, Increase Contrast, Reduce Motion and Reduce Transparency. macOS has no Dynamic Type, so layouts are tested at the App window's fixed size and at the 600 pt onboarding minimum instead. Contrast floors are in `final-direction.md` (token table); this file says how each surface behaves.

## Surfaces and keys

| Surface | Keys |
|---|---|
| Anywhere | ⌥⌘K opens the island (changeable in General). While a notice shows, it opens that notice with its primary action selected. |
| Expanded island | Return runs the selected action · Esc collapses, then hides · ← → page notices · ↑ ↓ move the selection · Space Quick Look · ⌘Z undo · ⌘⌫ Move to Trash (duplicates only) · ⌘R reveal · ⌘O open · ⌘/ shortcuts · ⌘, Settings. No action is a bare letter, and plain ⌫ never trashes. Return never runs a ⌘⌫ action. |
| Ask field (macOS 26) | Return sends · ↑ recalls · Esc leaves the field without clearing it · ⌘⌫ deletes the line, never a file. Return stays inert for 1 s after the field is emptied. |
| App window | ⌘, opens General. Sidebar: ↑ ↓ (native list). Activity: ↑ ↓ entries, ← → files in a review or batch, Esc back, ⌘Z undo, ⌘⌫ Move to Trash on a duplicate, ⌘/ shortcuts. |
| Onboarding | Return is the one primary button on every step; Tab reaches each folder row and choice card (each draws the ink focus ring). The island demo opens with ⌥⌘K, a click, or Skip. |
| Review windows | Real windows: plain ⌘Z and ⌘⌫ work. |

Every pointer-only action (drag into the Tray, hover help) has a keyboard path: the "Add to Kanso Tray" Finder Service, ⌘V, and the shortcuts sheet (⌘/).

## VoiceOver

- **Island notices** post an announcement: `.medium` priority for confirmations ("Renamed Scan_0012.pdf to Invoice-Vattenfall-2026-03.pdf"), `.high` only for failures.
- **Nothing expands or collapses on its own** under VoiceOver: the onboarding demo skips its 10 s auto-open, and the Tray never auto-expands.
- **Sidebar rows** read their badge: "Activity, 2 need you", "Sorting, a watched folder needs access".
- **Overview tiles** read as one element: "Renamed: 12, from contents, page 1", with the button trait (each opens its page).
- **Activity rows** combine title, time and subtitle; the selected row has `.isSelected`. Thumbnails and shelf badges are hidden from VoiceOver because the subtitle names the shelf.
- **Folder rows** without access read "Off · Allow in Privacy & Security".

## Display options

| Option | What changes |
|---|---|
| Reduce Motion | 0.2 s cross-fades replace grow, stagger, beam and parallax; progress shows as static text; illustrations draw one settled frame. |
| Reduce Transparency | Glass becomes solid `K.glass`; the island's capsule uses the solid fill. |
| Increase Contrast | A 1 pt `controlStroke` edge on every glass surface and control. |

## Colour

- Text meets 4.5:1 and control edges and focus rings 3:1 (`final-direction.md` has every ratio).
- Never put `text2` or `text3` on a tint; use the tint's ink.
- Colour is never the only signal: each island state has its own icon shape, tags carry words, and the Quick settings off tiles change weight and glyph as well as colour.
- Mint ink (`K.accent`) is the one selection and focus colour; system green appears only in native switches.

## Check by hand before sign-off

- VoiceOver through onboarding, an island notice (⌥⌘K, Return), and Activity.
- Full Keyboard Access: every control in the App window is reachable.
- Each display option above on the island, on three wallpapers.
