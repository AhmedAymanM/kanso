# Kanso design direction

The design to implement, from the 2026-10-30 design work and its accessibility, security and design reviews, updated with the owner's decisions in the goals grilling of 2026-11-19/20. `PRODUCT.md` says *what* each feature does; this file says how it looks and moves. Nothing here is applied to code yet unless noted.

## Decision
- **Paper & Ink.** Solid warm surfaces in the content area, one mint ink for brand surfaces, **SF everywhere** (no serif; owner, 2026-11-20).
- **Mac conventions** (owner, 2026-11-20, from the `macos-app-design` skill):
  - **The window is resizable**, with a 1170 × 772 minimum. It does not remember the last page.
  - **Native controls follow the system accent** (switches, focus rings, sidebar selection); mint stays on brand surfaces (hero, tinted cards, primary buttons).
  - **The sidebar uses plain `.listStyle(.sidebar)`** selection and the system sidebar material; paper stays in the content area.
  - **Larger Text:** text styles scale with the macOS Larger Text setting.
  - **Menus:** App, File, Edit, View (pages on ⌘1–⌘8), Window, Help (opens GitHub); "Check for Updates…" in the App menu.
  - **Everywhere:** right-click menus on Activity rows and shelves, ⌘F focuses the Activity search, type-to-select in lists, a hover state on every button.
  - **Kept our way:** settings stay pages of the one App window; the island replaces system notifications; `SoftTopEdge` stays (retest on macOS 27); plain-English rules keep their Save; no notarization. A ⌘K palette is v1.1.
- **The material rule:** glass only for things that float (the island, the popover, the Tray). No glass on content cards, no floating glass panes, no `.hiddenTitleBar`, no glass morph between windows (impossible across `NSWindow` and `NSPanel`). The sidebar and toolbar keep the automatic macOS 26 glass; buttons keep `liquid(_:)`.
- **Monospace** only for paths and counts in the Activity detail, and the time column in the island's "Recently" rows.
- **The capsule is the default island** (owner, 2026-11-19), with **Position: Top / Bottom**. The notch skin is an option; its bottom edge melts into glass over the **last 12 pt only**, with the esc row on solid black.
- **Overview keeps the four tinted counter tiles** (owner, 2026-11-19).
- Overview and Activity stay separate pages; the window is not dark-led.

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
| `TS.body` | 14 / 19 | 400, SF | `body` |
| `TS.emphasis` | 15 / 20 | 600, SF | `emphasis` |
| `TS.heading` | 17 / 22 | 600, SF | `heading` |
| `TS.title` | 22 / 28 | 600, SF | `title` (20), `title2`, `headline` (26) |
| `TS.display` | 34 / 40, tracking -0.4 | 700, SF | `display` (30), `statement` (34), `hero` (40) |
| `TS.numeral` | 44 / 48 | 700, SF Rounded (`design: .rounded`), `.monospacedDigit()` | `numeral` (52) |
Notes: Activity headline becomes `title` (toolbar title 13 pt semibold, the macOS window-title size). Folder emoji (old `headline` 26) uses an explicit icon size, not a text token. No font under 11 pt; chart labels and badges are `meta`. Map each step onto a semantic text style so the Larger Text setting scales it; test layouts at the minimum window size and with Larger Text on.

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
| spacing | 4 / 8 / 12 / 16 / 24 / 32 (page padding 24) | |
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
| Tray: confirmations | "Added N" 2 s; "Removed N · ⌘Z" 3 s | |
| notice dismiss and illustration rest | unchanged (illustrations rest after 15 s) | |
| Reduce Motion | 0.2 s cross-fade; no grow, stagger, beam, or parallax; progress shown as static text | `Motion.reduced` |
| Reduce Transparency | solid `K.glass` | existing `Motion.solid` |
| Increase Contrast | 1 pt `controlStroke` on every glass surface | existing `Motion.contrast` |
Only these things animate: island grow and shrink, Needs-you swap and collapse, undo confirmation, Tray drag-over, illustrations (one pass then rest).

## Per-screen change list, ordered by impact
1. **Global tokens (all screens).** Apply the text2 / text3 / controlStroke / glass values above; swap button and field edges from `K.separator` to `K.controlStroke`; fix white 40% and 35% text on black (`Onboarding.swift:258,261`) to 70%; use `TS` eight steps; set announcement priority to `.medium` for confirmations and `.high` only for failures (`Island.swift:537`).
2. **First-run window (Onboarding).** Replace "Nothing leaves this Mac." (`:63`, `:154`) with: "Your files never leave this Mac. Once a day Kanso checks GitHub for a new version; turn that off in Settings." Delete `.focusEffectDisabled()` (`:46`) and give each folder row a focus ring (`controlStroke` edge on choice cards, ink ring on focus). Fix or cut "or click the island" (`:133`) (add a tap gesture with button semantics, preferred). Skip the 10 s auto-expand under VoiceOver (`:141`). Name each paused folder with "Off · Allow in Privacy & Security" and add Back to the declined screen (`:188`).
3. **Overview.** Needs-you card collapses to a 56 pt line when empty (spring on `frame(height:)`), month chart rises into the space and draws elapsed days only (ink past, accent today); hero loses the hatch and its secondary text goes to 85%; the four tinted counter `Tile`s stay (owner, 2026-11-19); "Where files went" uses a single icon style; card radius 14, padding 16.
4. **Island.** Notch skin: Compact width `max(290, notch.width + 140)`; row 1 notch height with the 24 pt tile, cutout, chip; row 2 centred line; the chip shows only until the first dwell, then becomes a 28 pt icon-only key (stops the `⌥…` truncation); expanded "Extra copy · 120 MB · id…" gets a wider text column, no truncation of the size; bottom melt confined to the last 12 pt with the esc row above it on solid black; two lip glass buttons are 28 pt with labels. Capsule: 320 × 38, glass at 92%, secondary text `K.glassText2`. The capsule is the default skin: at Top it drops 6 pt below the menu bar; at Bottom it sits 8 pt above the Dock and follows the Dock when it auto-hides. The onboarding demo shows the capsule.
5. **Activity.** Groups newest first; one date format; Quick Look thumbnails plus destination shelf emoji on rows; remove the orphan "Don't rename files like this" heading unless it has its control; paths and counts in the Activity detail in `.system(.footnote, design: .monospaced)` with an `accessibilityLabel` that reads "moved to Documents"; title in `TS.title`.
6. **Sorting.** Banner capped at 160 pt so Approach cards are visible; one greens rule (mint ink for banner and hero, system green only for native switches); one icon style in watched folders; the "Downloads → My Shelves → Documents" chip becomes plain SF text.
7. **Quick settings.** Off tiles get a weight and glyph change (not only the dot), text at `text2` 4.5:1 or better; 12 pt grid with equal gutters; the Sorting row becomes the same shape as tiles.
8. **Sidebar.** Plain `.listStyle(.sidebar)` selection in the system accent, system sidebar material, 16 pt hierarchical SF Symbols; no custom `K.rowSelected` or accent dot. The Activity filter pill and Overview mint stop competing.
9. **Tray (v1).** Per "The Tray" below, after its UX redesign in Pencil (the Tray comes back by reverting #20).
10. **Smart Installer.** Per its section below; the sidebar page "Smart Eject" becomes "Smart Installer".
11. **Cleanup.** Per its section below; a new sidebar page after Smart Installer.
12. **General.** Island style (Capsule / Notch) and position (Top / Bottom) replace "Island: Automatic / From the notch / Below the notch".
13. **First launch.** The Open Anyway guide comes before the folders step (self-signed build).
14. **Docs.** Rewrite `05-accessibility.md` for the current surfaces (island, onboarding, Overview) with the contrast table in this file.

## What to check on a real Mac before sign-off
- Contrast of every capsule and popover state on three real wallpapers (the table gives floors, not measurements).
- Compact island chip width on a 14-inch and a 16-inch MacBook Pro (notch widths differ).
- The melt: that the esc row is on solid black at both expanded heights.
- Derived dark `fg` values for `Tint.rule`, `Tint.where`, `Tint.neutral`.

## The Tray (v1)
A place on the island to **collect things from across the Mac and then take them somewhere**: drag them into another folder or app, share them, or upload them. It never sorts or moves anything on its own: **no Organize** (owner, 2026-11-20). Copy never calls it a drop zone, basket, stash or shelf (a shelf is a sorted folder).

### What it holds
| Kind | Shown as |
|---|---|
| File / folder | A **Quick Look thumbnail** (`QLThumbnailGenerator`), falling back to the file icon. A reference (bookmark data), never copied on drop. A file moved or deleted meanwhile shows a "Missing" tile. |
| Link | A **link preview** card (`LPLinkView`: title, site icon, image) once the link passes the safety check below; until then, or if it fails, a plain card with the host and the URL. |
| Snippet (text) | A text card with the first lines. |
| File promise (browser image, Mail attachment) | Saved as a **temporary copy** in `~/Library/Application Support/Kanso/Tray/` (mode 0700, excluded from backup and Spotlight, `com.apple.quarantine` set), then shown like any file. While it saves, the tile shows a progress ring; a failed save shows "Couldn't save that image" and adds nothing. Dragging it out moves the copy to the destination (a copy across disks). When it leaves the Tray by any route, Kanso deletes its temporary copy once ⌘Z can no longer restore it (the next removal, closing the island, or quitting). "Forget everything" and launch clean up any leftovers. |

### Layout
- **A grid of preview tiles, not a list**: 88 × 88 pt tiles with a 10 pt corner radius, the name under each (two lines, middle-truncated), 4 per row in the 480 pt expanded island, scrolling after 3 rows. Newest first.
- **Header, top right: Share and Clear.** Share opens the system share sheet (`NSSharingServicePicker`) for the **selected items, or all of them when nothing is selected**; the button's label says which ("Share 3" / "Share all"). Clear empties the Tray (the files stay where they are), with ⌘Z to bring it back. The count sits top left.
- Empty state: "Drop files, links or text here", "or paste with ⌘V".

### Selecting and removing (like Finder)
- **Click** selects one item; **⌘-click** adds or removes; **⇧-click** selects a range; **⌘A** selects all; **drag a rectangle** on empty space to select (marquee); arrow keys move the selection, ⇧-arrows extend it. Selected tiles get a 2 pt ring in the system accent.
- **Space** opens Quick Look for the selection (`QLPreviewPanel`), with arrows to page through, as in Finder. Links open their preview there too.
- Share, drag and remove act on the **selection** when there is one.
- **Remove an item** three ways: the **×** that appears top right of a tile on hover; **⌫ / Delete** on the selection; or **dragging it out** to another folder or app (it leaves the Tray once the destination accepts it). Removing takes it off the Tray only; the file is never trashed. ⌘Z restores the last removal.
- **Dragging out follows Finder:** a move within the same disk, a copy across disks, ⌥ forces a copy. ⇧ while dragging keeps the item in the Tray.

### Adding
- Drag onto the island: it grows after a **250 ms** dwell in a 160 × 44 pt zone where the capsule (or notch) sits, on the screen under the cursor, and shrinks after the pointer leaves a 220 pt radius. Only a drag holding a file URL, a file promise, an http(s) URL or text qualifies. "Added 3 to the Tray" for 2 s; it never expands on its own.
- **⌘V** into the open Tray, and the Finder Service **Add to Kanso Tray** (with Finder in front, ⌥⌘K then ⌘T opens the Tray).
- Full-screen apps: no growing; ⌘V and the Service still work.

### Link safety check (before any preview is fetched)
https only (http links stay plain cards); resolve the host and refuse loopback, link-local, private (RFC 1918) and `.local` addresses, re-checked on each of at most 3 redirects; 1 MB and 5 s caps; no cookies, no Referer. The fetch goes only to the link's own site, and only for links the user added. Privacy & AI lists it as a network call.

### Keyboard
`⌥⌘K` opens the island, `⌘T` switches to the Tray, `esc` goes back. Inside: arrows, ⇧-arrows, `⌘A`, `Space` (Quick Look), `⌫` (remove), `↩` (open the selection), `⌘C` (copy the selection), `⌘V` (add), `⌘Z` (undo the last removal or Clear), `⌘/` (shortcuts).

### Accessibility and safety
- VoiceOver: the grid is "Tray, 6 items"; a tile reads "Lease-2026.pdf, PDF, from Downloads" with Remove, Share and Quick Look as actions, so hover and drag are never the only way. Adding announces at `.medium` priority. No auto-expand or auto-collapse under VoiceOver. The × has a 28 × 28 pt hit area.
- Names are untrusted: control characters stripped, capped at 120 characters. Kanso never writes executable types. `tray.json` (references, links, snippets) is mode 0600, excluded from backup and Spotlight, wiped by "Forget everything", and never sent to a model.
- A pending Tray never counts toward Needs you.

### Later
Upload actions (a share link) and the file actions of v1.2 (convert, compress, optimize) attach to the selection.

## Smart Installer (island)
- **Offer** (compact island, app icon tile): "Install Figma → Applications" with a "Trash the download" checkbox, ticked. Return installs. After the first time both answers are remembered and the offer becomes the progress notice directly.
- **Progress:** the work beam with "Copying Figma…", then "Checking…". With Reduce Motion, static text.
- **Done:** "Installed Figma · download moved to Trash · ⌘Z" (the morph icon fills); the app opens from `/Applications`.
- **Already installed:** "Figma 3.2 is installed · Replace with 3.4?" with Replace and Skip; Replace is disabled with "Quit Figma first" while it runs.
- **Failure:** one line naming the failed step ("Installed, but the disk image couldn't be ejected. The download was kept.").
- **Archives and torrents:** the same compact offer, "Trash the zip" / "Trash it", with Keep.

## Cleanup (island and page)
- **Weekly card** (Needs you, butter): "Sunday: 9 installers and archives leave · 2.1 GB" with Review and Keep all. Review opens Activity filtered to those files.
- **After a cleanup:** one compact line, "Moved 9 to Trash · ⌘Z".
- **Move to Documents** (Needs you, mint): "Keep Lease-2026.pdf in Documents?" with Move and Not now.
- **Offer** after a week of sorting (Needs you, once): "4 installers and 6 archives you've finished with · 3.4 GB · Turn on Cleanup".
- **Page:** banner, the switch card, one row per carrier with its days (a stepper), "Suggest moving kept files to Documents", and, when Finder empties the Trash after 30 days, "Undo works for 30 days".

