# Unhappy paths

Each has: when it happens → what the user sees → what they can do → what Kanso guarantees. Banners use the **inline status banner** pattern: full-width strip in the preview pane under the toolbar, 44pt, icon 16pt + text `body` + buttons right; never an alert unless the app cannot continue.

## U1. Permission denied / access lost
| Case | UI | Copy |
|---|---|---|
| First pick of a protected folder (Desktop/Documents/Downloads) | the **system** TCC prompt appears from `NSOpenPanel` selection; Kanso adds nothing. Before the panel, welcome screen explains in one line | Welcome sub-line: `Kanso only touches files directly inside the folder you choose.` |
| User denies in the system prompt or panel is cancelled | S0 stays; no error | (none — cancelling is not an error) |
| Bookmark stale/folder moved/renamed/ejected | S6 full-pane empty state, lock icon 40pt `text2` | Title `Kanso can’t open “Downloads”` · Body `It may have been moved, or access was removed. Choose the folder again to continue.` · Button `Choose Folder…` (default) · secondary `Open Privacy Settings…` only if the OS reports a TCC denial (deep link to Files & Folders) |
| One file can’t be moved (locked, no write permission, in use) | row → Blocked state (rose `Can’t move`); run continues | tooltip reason: `“{name}” is locked.` / `You don’t have permission to move “{name}”.` |
| Destination folder not writable | plan marks every move to it Blocked; banner | `Kanso can’t write to “Finance”. Choose a different destination in rule ③.` link `Edit Rule` |
Guarantee: failure of one item never aborts the others, and never leaves a half-moved file (move is atomic rename on the same volume; across volumes: copy → verify size → remove source, journaled in that order).

## U2. Empty folder
S5 full-pane: folder icon 40pt `text2`. Title `“Downloads” is empty` · Body `There’s nothing to sort yet.` Buttons: none. Rules column still editable. (A folder with only subfolders/hidden files counts as empty for the message: `There are no files directly inside “Downloads”.`)

## U3. Nothing matched
Rules exist, ≥ 1 file, zero moves. Summary bar: `Nothing to move` / `None of the 214 files match your rules.` Stays group auto-expanded (it is the whole list). Below the table: button `Add a Rule` plus `Show Suggestions` if the rule list is empty. Rules with “No files match” in line 2 each suggest what they target. Apply disabled (it would do nothing; the disabled state is the message).

## U4. Name collisions
Handled by policy (keep both, rename incoming), shown before Apply. See 02. Edge cases:
- Two files in one run → same destination name: first in sort order keeps its name, the rest get ` 2`, ` 3`.
- Suffix before extension; hidden extension preserved; `archive.tar.gz` → `archive 2.tar.gz`.
- Destination name taken *between preview and Apply* (race): Apply re-checks, renames the same way, run summary lists it: `1 file was renamed because its name was taken after the preview.`
- Undo onto a taken original name: file returns as `name 2.ext`; summary `Put 127 files back. 1 was renamed because its original name is now in use.`

## U5. Interrupted apply
| Interruption | Behavior |
|---|---|
| **User presses Stop/Esc** | finishes the current file, stops; state S4 (partial): `Moved 41 of 128 files` / `You stopped the sort. Undo puts these back, or press Apply to continue.` Apply re-plans the rest. |
| **Crash / force-quit / power loss** | next launch shows banner (44pt, `KT.Color.attention` pastel) before anything else, on the same folder: `The last sort was interrupted after 41 of 128 moves.` Buttons: `Undo Those Moves` (default) · `Keep Them`. Both are safe; no decision is time-limited. Journal is write-ahead so every moved file is accounted for. |
| **Volume ejected mid-run** | remaining moves fail with `Blocked`; summary `The disk was disconnected. 41 files moved before it did.` + Undo. |
| **Disk full (cross-volume copy)** | failing file stays at source untouched; `Not enough space on “{volume}”.` |

## U6. Plan went stale
Folder changes on disk while the preview is open (FSEvents on the chosen folder only while the window is open — not a daemon): debounce 500ms, S2′ recompute silently. If a *checked* file disappears between preview and Apply: counted in Blocked, `“{name}” is no longer there.` No dialog.

## U7. Big folders
More than 5,000 top-level items: the scan stops, plan is `.partial`. Banner: `Kanso is showing the first 5,000 of {total} items.` with no batching feature in v1; the honest message is the whole handling. (CTO: if the engine handles more at the 300 ms target, drop this case.)

## U8. Special items (all shown under “Stays”, with reason)
Folders (v1 doesn't move folders), `.app` bundles & packages (treated as one item and **may** match Kind rules; Installers group includes `.pkg`/`.dmg`, not `.app`), files still downloading (`.crdownload`, `.download`, `.part`), iCloud placeholders (`.icloud`) — `In iCloud, not downloaded`; aliases/symlinks move as themselves, never followed; files tagged `Keep` stay (the engine's existing convention; surface in copy as `Tagged “Keep”`).
