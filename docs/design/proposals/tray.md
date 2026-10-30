# The Tray (roadmap v2)

Status: design proposal for the v2 design session named in `PRODUCT.md` (section 8), revised 2026-10-30 after the design, accessibility, security and strategy panel reviews. Vocabulary from `CONTEXT.md`: the **Tray** is a temporary holding place for things the user is carrying until they decide what to do with them; **Organize** files them onto **shelves**. Copy avoids "drop zone", "basket", "stash" and "shelf" for the Tray. Mockups of the four states are at the bottom of each `proposal-*.html`; they differ per direction (A black notch, B glass capsule, C diff-style rows).

## v2 scope: files only
The strategy review ranks the Tray first among v2 work, and the security review finds the link and snippet paths the riskiest (SSRF, secrets on disk, quarantine). v2 therefore ships **files and folders only**.

| Kind | v2 | Later (v2.x, each needs its own review) |
|---|---|---|
| File / folder | A **reference** (bookmark data plus metadata). Never moved or copied on drop. Organize moves it like any sort (journaled, Recents link). | |
| Link | Not accepted. A dropped URL is refused with "The Tray holds files for now." | `.webloc` on a new 🔗 Links type. Title fetch stays off by default and needs the SSRF rules below. |
| Snippet (text) | Not accepted. | `.txt`/`.md` on a new 📝 Notes type; `tray.json` mode 0600, excluded from backup and Spotlight, wiped by "Forget everything"; 500 KB per snippet, 100 items. |
New types Links and Notes are **not** added in v2, so `default_config` and the engine's type table do not change.

Open owner decision (kept as recorded, not overridden): file references versus copies. Recommended: references. A file moved or deleted by the user meanwhile becomes a "Missing" row. Security-scoped bookmarks mean nothing for an unsandboxed app (`Kanso.entitlements` is empty), so v2 stores plain bookmark data; the wording returns if the build is sandboxed.

## Principles (inherited)
1. **Calm and silent.** The Tray never opens by itself, never notifies, never sorts on its own. Holding is not sorting.
2. **Everything can be undone; Kanso never deletes.** Forgetting removes the reference, not the file. Organize only moves, journals, and is undoable with one run id.
3. **Adopt the user's structure.** Destinations are existing shelves; a new shelf follows the unknown-extension rule (name, emoji, description, only for files with an extension).
4. **Local first.** Metadata only. No Tray feature reads file content in v2.

## Where it lives and how it opens
- **Island, expanded, a new page.** The lip gains a third glass button (tray glyph, 28 pt, count badge when carrying). `⌘T` inside the open island switches to the Tray and `esc` returns. **No new global hot key** (`⌥⌘K` stays the only one).
- **Dragging onto the island:** see "Drag detection" below. The whole island is the drop target.
- **No notch, below-the-notch mode, a notch app running:** the capsule skin is the drop target.
- **Alternatives to dragging:** `⌘V` into the open Tray (files from the pasteboard), the Finder Service "Add to Kanso Tray" next to Don't Sort / Allow Sort, and the keyboard-only path below.

## Drag detection, dwell and multi-monitor
The island panel is `ignoresMouseEvents = true` except while a compatible drag is live, so it never steals clicks.
1. **Detect:** a global `NSEvent` monitor for `.leftMouseDragged` (and `.leftMouseUp` to end). A drag is compatible only if `NSPasteboard(name: .drag).changeCount` has changed since mouse-down **and** the drag pasteboard contains `public.file-url` items. Dragging a window, text, a URL or an app tab never qualifies.
2. **Dwell:** the island grows only after the pointer has stayed **250 ms** inside a **160 × 44 pt zone** centred at the top of the screen under the pointer. It shrinks only after the pointer leaves a **220 pt** radius (hysteresis). A pointer sweeping across the menu bar toward a status item never triggers it.
3. **Drop zone:** the live drop zone is the island itself (not a 120 pt halo); a 480 pt island can cover other apps' status items, so it never grows for a non-file drag.
4. **File promises** (Mail attachments, images dragged from a browser) cannot be bookmarked. They are **refused** with "That item isn't a file on this Mac yet. Save it first." (v2 does not accept promises into a temp folder.)
5. **Multi-monitor:** the screen is the one under the cursor (`NSEvent.mouseLocation` against `NSScreen.frame`), not `NSScreen.main`. A screen with a notch gets the notch skin if the setting allows; an external display gets the capsule at the **bottom of the menu bar + 8 pt**. A full-screen app hides the menu bar: the island does not grow there, and the Finder Service and `⌘V` remain.
6. **Reduce Motion:** the island appears in place with a 200 ms cross-fade instead of growing toward the pointer.
7. **After the drop:** "Added 3 to the Tray" (compact, 2 s), then shrink. It never expands on its own.

## Flows

### 1. Carry
1. Drag from Finder. The island grows (spring.settle, 420 ms); the well says "Release to add to the Tray" with the file count and a dashed 2 pt outline marks the whole island as the target.
2. Release: rows appear (icon, name, source folder, forget ✕). The well becomes a footer strip.
3. The island shrinks after the 2 s confirmation if the user did not open it; the lip button shows the count.

### 2. Organize
1. `Organize` (↩ on the primary button). Kanso builds a **plan** with the same `decide` as a normal sort: extension table, then the screenshot flag, then Apple Intelligence on metadata for unknown extensions, then Unsorted.
2. The plan lists each row as name, then a second line with the source and basis (`by file type`, `asks Apple Intelligence`, `by file type, never read`), and the destination at the right, never wrapping. A `new shelf` chip marks a proposed shelf. Shown **the first 5 times, then only for plans with a new shelf or more than 10 items.**
3. `Move N` runs one journaled run with one undo; Recents links as for normal sorts. "Moved 4 to 3 shelves · Undo ⌘Z" for 6 s, then the Tray empties.
4. `Change a shelf…` on a row opens the Activity shelf picker; a choice teaches a learned extension like a correction.

### 3. Forget
✕ removes the row only: "Removed from the Tray. The file is still in Downloads." `⌘Z` restores the row in the session.

### 4. Ask
The ask field works on the Tray: "put the PDFs in Documents". Same rules as ADR 0001 (below).

## Keyboard-only alternative (no pointer, no drag)
WCAG 2.5.7 needs a non-dragging path for every drag action.
1. In Finder select files, run the service **Add to Kanso Tray** (or `⌘C` then, in the open Tray, `⌘V`).
2. `⌥⌘K` opens the island, `⌘T` shows the Tray, `↑ ↓` move between rows, `⌥↑ ⌥↓` reorder the focused row (as in the rule list), `⌫` forgets, `↩` Organize, then `↩` Move N.
3. Every control has a visible focus ring (2 pt ink, 2 pt offset) and a VoiceOver label.

## States
| State | Appearance | Behaviour |
|---|---|---|
| Empty | Title, dashed well "Drop files here", "or paste with ⌘V" | Via `⌘T` or the lip button. No badge. |
| Drag over | Whole-island dashed outline, mint-tinted well, count; lip: "Nothing moves until you Organize" | An incompatible drag leaves it idle. |
| Carrying | Rows plus Organize; footer "Files stay where they are until you Organize" | Reorder `⌥↑ ⌥↓`; type-to-filter after 8 items. |
| Planning | Static "Planning 3 of 4" text; with motion allowed also the existing `IslandBeam` (left to right, never crossing the top edge) | `esc` cancels; nothing moved. The progress text shows even with Reduce Motion (the beam alone hid progress before). |
| Plan review | Destination per row, chips, buttons Move N, Change a shelf…, Not now | Return = Move N. Never a trash action. |
| Moving / done | Rows resolve one by one, then the confirmation | One undo reverts the run. |
| Partial result | "Moved 3 of 4. 1 stayed in the Tray: Lease-2026.pdf is open in another app." with Retry | Failed items stay with a reason row. |

## Empty, error and edge cases
| Case | Behaviour |
|---|---|
| File no longer exists | "Missing" row (strikethrough); Organize skips it; ✕ forgets. |
| iCloud placeholder | Carried and moved by name; never read ("metadata only"). |
| Key, vault, password file (`.pem`, `.p12`, `.kdbx`, 1Password) | Carried and moved by extension only; never sent to a model; lock icon. |
| Already in Manual Shelves | "In Manual Shelves, Kanso leaves it there"; Organize skips. Dropping into Manual Shelves is never offered. |
| Destination volume offline / permission missing | Row fails with "Kanso can't write to Desktop. Open Privacy Settings"; the rest continue. |
| Name collision | The normal collision suffix, shown in the plan. |
| Duplicate drop | Carried once; "Already in the Tray". |
| More than 100 items | First 100 added; "Added 100. 240 more were not added." |
| Model unavailable | Files organize by extension; unknown ones go to ❓ Unsorted; plan says "Apple Intelligence is off". |
| Sorting paused | The Tray works; Organize is user-initiated. |

## Security invariants
From the security panel (findings 1, 2, 5, 6, 9, 10 and the v2 invariant list), applied to the Tray:
1. **Model output is a choice from a closed set**: shelf names from the existing type list, or Tray item numbers. Never a path, glob, command or URL. Resolved destinations are standardized and symlink-resolved, and anything outside `<root>/My Shelves` is rejected; Manual Shelves is always refused.
2. **Nothing a model produces reaches trash, Manual Shelves, Keys, vaults** or a path outside My Shelves. `canTrash` is enforced in code, and the Tray has no trash tool at all.
3. **Names are untrusted.** Strip control characters and newlines, cap at 120 characters, and delimit them in prompts. New-shelf names from the model are rejected if (NFKC, case-folded) they equal a reserved or existing name (`Manual Shelves`, `Recents`, `My Shelves`).
4. **Any content read taints the request** (no content reads exist in v2; the rule stays for later kinds): no trash, moves need confirmation.
5. **Dropped and fetched content is untrusted** (later kinds): `com.apple.quarantine` set, `.webloc` only for http(s), never executable types (`.command`, `.app`, `.pkg`, `.terminal`).
6. **SSRF rules** for any later link title fetch: off by default; https only; resolve the host and refuse loopback, link-local, RFC1918 and `.local`; re-check at every redirect (max 3); 1 MB and 5 s caps; ephemeral session (no cookies); no Referer.
7. **Local state:** `tray.json` (references only in v2) is mode 0600, excluded from backup and Spotlight, wiped by "Forget everything", and never added to a prompt without a user action.
8. **No network** in v2 Tray flows.

## ADR rules
- **ADR 0001.** No trash action in the UI or via the ask field. The ask field proposes *move*, *rename* or *answer* over a closed set of Tray item numbers, never paths; Kanso writes every confirmation from tool arguments and the journal.
- **ADR 0002.** The Tray never trashes. Forgetting a row is not a deletion; a duplicate found while organizing goes to the Duplicates shelf under the normal settings.
- **Return never runs a ⌘⌫ action.**
- **Never touches Manual Shelves, Keys, vaults.**

## Keyboard
| Key | Action |
|---|---|
| `⌥⌘K` | Open the island (unchanged) |
| `⌘T` | Switch to the Tray (in the island) |
| `⌘V` | Add files from the pasteboard |
| `↑ ↓` | Move between rows |
| `⌥↑ ⌥↓` | Reorder the focused row |
| `Space` | Quick Look the focused file |
| `⌫` | Forget the focused row (`⌘⌫` is not used here) |
| `↩` | Organize, then Move N |
| `⌘Z` | Undo the last run, or restore a forgotten row |
| `Tab` | Ask field |
| `esc` | Back to the overview, then close |
| `⌘/` | Shortcuts |

## Accessibility
- **VoiceOver:** the list is `Tray, 4 items`. A row reads "Lease-2026.pdf, file from Downloads", with actions Forget and Change a shelf (as `accessibilityActions`), so the ✕ is not the only path. Plan rows read "Lease-2026.pdf, goes to Documents, based on file type"; a new shelf reads "new shelf". Drop: "Added 3 to the Tray" at `.medium` priority (polite); only failures use `.high`. When the island grows for a drag, post an `.layoutChanged` notification and do not move focus. The island does not auto-expand or auto-collapse content under VoiceOver (skip timers when `NSWorkspace.shared.isVoiceOverEnabled`); the 2 s confirmation is spoken, and the island stays until dismissed.
- **Contrast** (computed): on the black notch, text is white (21:1) or white at 70% (9.90:1), never below 62% (7.84:1). Capsule skin: 92% fill, `glassText2` (4.79:1 light worst case, 6.18:1 dark). Control edges (ask field, wells, buttons) use 3:1 strokes (white 40% on black is 3.66:1), not the 1.25:1 separator.
- **Targets:** 28 pt minimum for rows and buttons; the ✕ has a 44 × 44 pt hit area at full opacity text (white 70%).
- **Reduce Motion:** no grow-toward-pointer, 200 ms cross-fade, no stagger, static planning text.
- **Wrapping:** rows are two lines (name, then source and basis) with a no-wrap destination column; names middle-truncate but destinations and bases never truncate. Test at the 600 pt minimum window width (macOS has no Dynamic Type, so that rule is dropped).

## How it fits the island
- The Tray is a page of the expanded island: same shell, lip, glass buttons, ask field. Its look follows the chosen skin (black notch or glass capsule).
- A drop produces the compact notice "Added 3 to the Tray"; the island never expands on its own.
- A pending Tray never counts toward the **Needs you** badge (parked on purpose). "Still carrying 4 things" appears once after 7 days.
- Organize is not silent (user-initiated) but short.
- It yields like the island: a notch app forces the capsule.

## Engine and code impact (for the later build)
- `KansoCore`: `TrayStore` (file references only, JSON in the state dir), `Engine.organize(trayItems:) -> Plan` reusing `decide`, `apply`, journal run ids.
- App: `TrayView` in `IslandViews.swift`; an `NSEvent` global monitor plus drag-pasteboard check for drag detection; the island panel accepts `NSDraggingDestination` only while a compatible drag is live; a Finder Service.
- Tests: plan ordering, collision, iCloud placeholder never read, Keys never read, missing file, manual-shelves skip, destination containment (symlink and `..`), reserved-name rejection, undo of a whole run, no trash tool under any Tray ask, file-promise refusal, non-file drag ignored.

## Open questions
1. References or copies for files? (recommended: references; owner decision stays open)
2. When links and snippets return: is on-disk storage acceptable under "keeps nothing"? (recommended: yes, capped, local, wiped by "Forget everything")
3. Link titles: off by default (recommended).
4. Links and Notes types: add to the type table when those kinds ship, not before.
