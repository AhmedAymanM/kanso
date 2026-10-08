# Kanso v1 design (KAN-2)

Owner: Suki (UX). Status: first complete pass. Specs are written to be built from; tokens are importable.

| Doc | What |
|---|---|
| [01-core-flow.md](01-core-flow.md) | The loop as states S0–S8, menu bar, principles applied |
| [02-preview-screen.md](02-preview-screen.md) | **The trust moment**: layout, measurements, row states, collisions, exact copy |
| [03-rule-editor.md](03-rule-editor.md) | Rule model (kind / date / name), list sentences, popover editor, validation |
| [04-unhappy-paths.md](04-unhappy-paths.md) | Permission, empty, nothing matched, collisions, interrupted apply, stale plan |
| [05-accessibility.md](05-accessibility.md) | Keyboard map, VoiceOver labels, measured contrast, text size, motion |
| [06-plan-contract.md](06-plan-contract.md) | Engine ↔ preview types (proposal for Forge) |
| [tokens/KansoDesignTokens.swift](tokens/KansoDesignTokens.swift), [tokens.json](tokens/tokens.json) | Color (L/D), type, spacing, size, radius, motion |
| [prototype/preview.html](prototype/preview.html) | Open in a browser: live rule edits, collisions, skip, apply/undo. Throwaway. |

## Open questions
1. **Scope vs the shipped app (CEO).** `app/` is an automatic, menu-bar, by-type sorter with an island; this spec is the manual rule-driven preview-first loop from the company goal. Keep both front doors, replace one, or make the preview a "Sort now…" mode of the existing app? Needs a call before UI work.
2. **Date field** doesn't exist in `KansoCore.Rule` (only name/ext/from/size). CTO: cost?
3. **Plan contract** shape (06) is a proposal; Forge to confirm or counter.
4. **Plan speed** (≤300 ms @ 5k items). If not, fall back to recompute-on-commit.
5. **Folders** are never moved in v1; confirm that's acceptable.

## Not yet done
Interaction validation with real people (none available on this host); multi-folder UX; Settings pane; app icon/brand beyond tokens.
