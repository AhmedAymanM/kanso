# Kanso trashes on its own only files that are provably spent

Kanso's trust promise was "never deletes; Move to Trash is always user-initiated". Smart Eject (moving an installer to the Trash after its app is installed) broke that literally, so we narrowed the promise instead of dropping it: Kanso never deletes and never empties the Trash; it moves a file to the Trash on its own only when the file is **provably spent**, which today means an installer whose app landed in `/Applications`. Byte-identical duplicates are *not* provably spent (a user may keep two copies on purpose), so they are held on the Duplicates shelf until the user presses ⌘⌫. Every automatic trash is journaled, shown on the island and one ⌘Z away.

## Amendment (2026-09-29): trashing the user chose in advance

A setting the user turns on is their decision made once in advance, not Kanso deciding on its own. So Duplicates may send extra copies straight to the Trash, or auto-trash held copies after N days, **only when the user turned that on**. Defaults stay safe: copies go to the Duplicates shelf and auto-trash is off (30 days preset when enabled; opening a held copy resets its timer). The rule is now: Kanso trashes on its own only provably spent files; beyond that, only what the user told it to trash, by ⌘⌫ or by a setting they enabled.

## Amendment (2026-11-20): carriers on a timer the user turned on

Cleanup lets the user turn on timers that trash **carriers**: files whose purpose ends once used (installers, archives, screenshots, torrents, duplicates). Turning one on is trashing the user chose in advance, as above, and it may cover only carriers. **Content files** (documents, images, media, code, keys) are never on a timer; they reach the Trash only by ⌘⌫, including from the v1.1 review. Idle time is measured from the `com.apple.lastuseddate#PS` xattr, the modification date or the sort, never the access time, which Kanso's own reads change. Any user tag, rename by the user, or move out of My Shelves cancels every timer on that file.

Smart Installer trashes the downloaded image right after the user installs from it, with "Trash the download" shown and ticked before the install starts: the image is provably spent, and the user saw the choice.

Kanso's own scratch files are outside this rule. The Tray's temporary copies of browser images and Mail attachments (file promises) live in `~/Library/Application Support/Kanso/Tray/` and are deleted once they leave the Tray; the user keeps one by dragging it somewhere. Nothing the user saved is ever deleted.

Where a model helps decide what leaves (the v1.1 review, the v1.2 uninstaller), it may only demote an item to Review or Keep, never promote it; Kanso's code finds the candidates and a fixed guard wins.

## Considered options

- **Keep "never trashes on its own"** and ask after every install: safest, but it makes Smart Eject a chore, and the owner wants installers handled automatically.
- **Earned trust** (ask the first few times, then automatic): rejected by the owner as unnecessary for installers.
- **Trash duplicates automatically too**: rejected, because identical bytes don't prove intent.

## Consequences

Any new automatic trash must meet "provably spent" (the file's purpose has verifiably been fulfilled) and needs this ADR revisited; convenience alone doesn't qualify.
