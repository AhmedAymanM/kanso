# Kanso trashes on its own only files that are provably spent

Kanso's trust promise was "never deletes; Move to Trash is always user-initiated". Smart Eject (moving an installer to the Trash after its app is installed) broke that literally, so we narrowed the promise instead of dropping it: Kanso never deletes and never empties the Trash; it moves a file to the Trash on its own only when the file is **provably spent**, which today means an installer whose app landed in `/Applications`. Byte-identical duplicates are *not* provably spent (a user may keep two copies on purpose), so they are held on the Duplicates shelf until the user presses ⌘⌫. Every automatic trash is journaled, shown on the island and one ⌘Z away.

## Amendment (2026-09-29): trashing the user chose in advance

A setting the user turns on is their decision made once in advance, not Kanso deciding on its own. So Duplicates may send extra copies straight to the Trash, or auto-trash held copies after N days, **only when the user turned that on**. Defaults stay safe: copies go to the Duplicates shelf and auto-trash is off (30 days preset when enabled; opening a held copy resets its timer). The rule is now: Kanso trashes on its own only provably spent files; beyond that, only what the user told it to trash, by ⌘⌫ or by a setting they enabled.

## Considered options

- **Keep "never trashes on its own"** and ask after every install: safest, but it makes Smart Eject a chore, and the owner wants Tidy's behavior.
- **Earned trust** (ask the first few times, then automatic): rejected by the owner as unnecessary for installers.
- **Trash duplicates automatically too**: rejected, because identical bytes don't prove intent.

## Consequences

Any new automatic trash must meet "provably spent" (the file's purpose has verifiably been fulfilled) and needs this ADR revisited; convenience alone doesn't qualify.
