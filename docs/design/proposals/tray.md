# The Tray (roadmap v2)

Status: design proposal for the v2 design session named in `PRODUCT.md` (section 8). Vocabulary from `CONTEXT.md`: the **Tray** is a temporary holding place for things the user is carrying (files, links, snippets dropped onto the island) until they decide what to do with them; **Organize** files them onto **shelves**. Copy avoids "drop zone", "basket", "stash" and "shelf" for the Tray. Mockups of the four states are at the bottom of each `proposal-*.html`.

## Principles (inherited)
1. **Calm and silent.** The Tray never opens by itself, never notifies, never sorts on its own. Holding is not sorting.
2. **Everything can be undone; Kanso never deletes.** Forgetting a Tray item removes the reference, not the file. Organize only moves, journals, and is undoable with one run id.
3. **Adopt the user's structure.** Destinations are existing shelves (by kind); new shelves follow the same "name, emoji, description" rule as unknown extensions and only for things that have an extension.
4. **Local first.** Anything that reads content stays on the Mac and is opt-in; metadata-only is the default.

## What the Tray holds

| Kind | What is stored | Where it ends up on Organize |
|---|---|---|
| **File / folder** | A security-scoped **reference** (bookmark) and its metadata. The file is **not moved or copied** when dropped. | A shelf of its type, moved like any sort (journaled, Recents link). |
| **Link** | The URL and, if the user allows, a title fetched on demand. | A `.webloc` file on a Links shelf (new type: 🔗 Links). |
| **Snippet** (text) | The text, kept in Kanso's state folder (`$KANSO_HOME/tray.json`), local only. | A `.txt` or `.md` file on a Notes shelf (new type: 📝 Notes). |

Open choice (owner decision): file references vs. copies. References keep the "nothing moves until you say so" promise and never duplicate data; their cost is that a file moved or deleted by the user meanwhile becomes a "missing" row (state below). Recommended: references.

Snippets and links are user-provided content that Kanso keeps until Organize or Forget. This is a deliberate exception to "keeps nothing" because the user handed it over to be kept; it never goes to the cloud and is capped (500 KB per snippet, 100 items). Retention: items stay until the user acts; after 7 days the island's overview says once "Still carrying 4 things", with Organize and Forget actions. It never auto-forgets.

## Where it lives and how it opens
- **Island, expanded state, a new page.** The island's lip already has two glass buttons (keyboard, Settings); the Tray adds a third (a tray glyph with a count badge when carrying). Inside an open island, `⌘T` switches to the Tray and `esc` returns. **No new global hot key** (one Carbon hot key, `⌥⌘K`, stays the only one); the Tray opens from `⌥⌘K` then `⌘T`, or by dragging.
- **Dragging onto the island.** While a drag carrying files, URLs or text is in progress and the pointer comes within 120 pt of the island's resting position, the island grows toward it (notch skin: out of the notch; capsule skin: it appears below the menu bar). It is a drop target only while a compatible drag is active, so it never steals clicks the rest of the time. After the drop it shows "Added 3 to the Tray" for 2 s and shrinks back.
- **No notch / below-the-notch mode / a notch app running.** The capsule skin is used; the drop target is the capsule.
- **Alternatives to dragging:** `⌘V` into the open Tray (files, URLs or text from the pasteboard); a Finder Service "Add to Kanso Tray" next to the existing Don't Sort / Allow Sort services; the Share menu is a later option (needs an extension).

## Flows

### 1. Carry
1. User drags from Finder, a browser tab or selected text. The island grows toward the pointer; the well shows "Release to add to the Tray" with the item count.
2. Release: items appear as rows (icon, name, source, a forget ✕). The well becomes a thin footer drop strip so more can be added.
3. The island shrinks after a 2 s confirmation if the user did not open it; the lip button shows a badge.

### 2. Organize
1. `Organize` (↩ with focus on the primary button, or click). Kanso builds a **plan**: for each item a destination and the basis for it.
   - Files: **extension table first** (no model), then Apple Intelligence on metadata for unknown extensions, then Unsorted. Same engine as a normal sort (`decide`).
   - Links and snippets: kind decides the shelf (Links, Notes). **Reading the text to choose a shelf or name is opt-in** (Privacy & AI, "Let Kanso read text you add to the Tray"), on-device only, ≤ 2,000 chars, nothing kept.
2. The plan is shown as a list: `Lease-2026.pdf → 📄 Documents`, basis chip (`metadata`, `asks Apple Intelligence`, `reads text on this Mac`), `new` chip for a proposed shelf. This is the "earned trust" preview: **always shown the first 5 times, then only for plans with a new shelf, a content read, or more than 10 items** (the same rule the app already applies to mass renames).
3. `Move N` runs it as one journaled run with one undo; Recents links are made as for normal sorts. Confirmation: "Moved 4 to 3 shelves · Undo ⌘Z" for 6 s, then the Tray is empty and the island shrinks.
4. `Change a shelf…` on a row opens the same shelf picker as Activity. A choice teaches a learned extension like a correction does.

### 3. Forget
✕ on a row removes it from the Tray only. For a file it says "Removed from the Tray. The file is still in Downloads." Forget has no undo prompt; the action is itself non-destructive, and `⌘Z` restores the row within the session.

### 4. Ask
The ask field works on the Tray: "put the PDFs in Documents", "what is in this snippet". Same rules as ADR 0001 (below).

## States

| State | Appearance | Behaviour |
|---|---|---|
| Empty | Title, dashed well "Drop files, links or text here", "or paste with ⌘V" | Reached via `⌘T` or the lip button. No badge. |
| Drag over | Well is mint-tinted, text "Release to add to the Tray", count and kinds; lip says "Nothing moves until you Organize" | Incompatible drag (e.g. an app bundle in progress of copy): well stays idle. |
| Carrying | Rows + Organize button; footer "Files stay where they are until you Organize" | Rows reorderable; type-to-filter after 8 items. |
| Planning | Rows get a thin progress sweep (the existing IslandBeam rules: left to right, never crosses the top edge) | Cancel with esc; nothing has moved. |
| Plan review | Destination per row, chips, buttons Move N, Change a shelf…, Not now | Return = Move N. Never a trash action. |
| Moving / done | Rows resolve one by one, then "Moved 4 to 3 shelves · Undo ⌘Z" | Single undo reverts the whole run. |
| Partial result | "Moved 3 of 4. 1 stayed in the Tray: Lease-2026.pdf is open in another app." with Retry | Failed items remain in the Tray with a reason row. |

## Empty, error and edge cases

| Case | Behaviour |
|---|---|
| File no longer exists | Row shows "Missing" (strikethrough, grey); Organize skips it; ✕ forgets. |
| Item is an iCloud placeholder | Can be carried and moved by name; **never read** (no content reading), plan says "metadata only". |
| Item is a Key, vault or password file (`.pem`, `.p12`, `.kdbx`, 1Password) | Carried and moved by extension only; never sent to a model, never read. Row shows a lock. |
| Item is already in Manual Shelves | Row says "In Manual Shelves, Kanso leaves it there"; Organize skips it. Dropping something *into* Manual Shelves is never offered. |
| Destination volume offline / permission missing | The row fails with "Kanso can't write to Desktop. Open Privacy Settings", rest continue. |
| Name collision on the shelf | Kanso's normal collision rule (suffix), shown in the plan. |
| Duplicate of a file in the Tray | Carried once; second drop says "Already in the Tray". |
| Very large drop (more than 100 items) | The first 100 are added; "Added 100. 240 more were not added." |
| Model unavailable | Files still organize by extension; unknown ones go to ❓ Unsorted; links and snippets by kind. The plan says "Apple Intelligence is off". |
| Sorting paused ("off for 1 hour") | The Tray still works; Organize is user-initiated. |

## ADR rules

- **ADR 0001 (ask field and destructive actions).** The Tray has **no trash action**, in the UI or via the ask field. The ask field on the Tray may propose *move*, *rename* or *answer* over a **closed set of Tray item numbers, never paths**; Kanso writes every confirmation text from the tool arguments and the journal, never from model text. Content of snippets and pages behind links is **untrusted text** (it may contain instructions aimed at the model): reading it taints the request, which only ever keeps the already-absent trash tool disabled, and moves proposed under taint are shown as a plan to confirm, never auto-run.
- **ADR 0002 (Trash only for provably spent files).** The Tray never trashes. Forgetting a row is not a deletion; an Organized file is moved, not trashed, and a duplicate found while organizing goes to the Duplicates shelf under the normal duplicates settings (the same code path as a normal sort).
- **Return never runs a ⌘⌫ action** (existing island rule): Return is Organize or Move N only.
- **Never touches Manual Shelves, Keys, vaults** (see above).

## Keyboard
| Key | Action |
|---|---|
| `⌥⌘K` | Open the island (unchanged) |
| `⌘T` | Switch to the Tray (in the island) |
| `⌘V` | Add pasteboard contents |
| `↑ ↓` | Move between rows |
| `Space` | Quick Look the focused file |
| `⌫` | Forgets the focused row. `⌘⌫` is reserved for Move to Trash elsewhere and is **not** used here. |
| `↩` | Organize, then Move N |
| `⌘Z` | Undo the last run, or restore a forgotten row |
| `Tab` | Ask field (as in the island) |
| `esc` | Back to the island overview, then close |
| `⌘/` | Shortcuts (as in the island) |

## Accessibility
- Every action is reachable without a pointer: add by `⌘V` or the Finder Service; organize and forget by keyboard.
- Dragging is never the only way (WCAG 2.5.7).
- VoiceOver: the tray is a list ("Tray, 4 items"); rows read "Lease-2026.pdf, file from Downloads, forget button". On drop VoiceOver announces "Added 3 to the Tray" (polite). The plan reads "Lease-2026.pdf, goes to Documents, based on file type"; new shelves read "new shelf".
- Contrast: all text on the black notch skin ≥ 4.5:1 (secondary text white at 62% is 7:1 on black; do not go lower than 55%); on the capsule skin use the solid fallback with Reduce Transparency and a 1 pt stroke with Increase Contrast.
- Reduce Motion: no grow-toward-pointer; the island appears in place with a 200 ms cross-fade. No stagger.
- Target size ≥ 28 pt for rows and ✕; ✕ has a 44 pt hit area.
- Dynamic text: rows wrap to two lines; never truncate a destination.

## How it fits the island
- The Tray is a page of the expanded island, not a new window. Same shell, lip, glass buttons, ask field.
- Compact notices come first: a drop produces the compact notice "Added 3 to the Tray" (peri tile icon); the island never expands on its own after a drop.
- A pending Tray never counts toward the **Needs you** badge on the sidebar (the user parked it on purpose). The "Still carrying 4 things" reminder appears once after 7 days.
- Plain organizes from the Tray are **not** silent (the user asked for them) but are short: confirmation line, then done.
- It yields like the island: a notch app (NotchNook) forces the capsule skin.

## Engine and code impact (for the later build)
- `KansoCore`: `TrayStore` (items, bookmarks, snippets, JSON in state dir), `Engine.organize(trayItems:) -> Plan` reusing `decide`, `apply`, journal run ids; new Links and Notes types chosen by the Tray item kind (check `default_config` for how `webloc`, `txt` and `md` map today, so the two paths do not disagree).
- App: `TrayView` in `IslandViews.swift`, `NSDraggingDestination` on the island panel active only during drags (`NSPasteboard` drag types `fileURL`, `URL`, `string`), a Finder Service.
- Tests: plan ordering, collision, iCloud placeholder never read, Keys never read, missing file, manual-shelves skip, undo of a whole run, taint rule (no trash tool under any Tray ask).

## Open questions
1. References or copies for files? (recommended: references)
2. Is storing snippets on disk acceptable under "keeps nothing", given the user supplied them? (recommended: yes, capped, local, visible in Privacy & AI, wiped by a "Forget everything" button)
3. May link titles be fetched (a network request)? Recommended **off** by default; a Link row shows the URL until the user opts in.
4. New types Links and Notes: ship in the type table at v2 (recommended) rather than let the model invent them.
