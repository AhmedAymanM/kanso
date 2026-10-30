# Strategy panel review (skeptic), 2026-10-30

## BLOCKER

1. **Nothing can be installed yet.** README/AGENTS.md: no notarized release, no cask, no updater, placeholder GitHub and donation URLs (`Components.swift` `Links`); competitors.md lists this as gap 1. The dogfood gate (PRODUCT.md s9) has no recorded start. Rec: ship notarized DMG + working links before any v2 work; start the dogfood clock now.
2. **The v1 story depends on Apple Intelligence, but Tidy covers macOS 14+ with no model.** competitors.md (Tidy: macOS 14+, Intel, 5 languages, $9). Kanso's "Kanso Local" model does not exist (AGENTS.md: "Not available yet"). Rec: market the deterministic mode as the product (extension table needs no model); drop "Kanso Local" from v1 copy until a bench result exists.
3. **No wedge is stated, and the first user is not named.** competitors.md s"Where Kanso can win" lists privacy, open source, free; all are weak against a $9 closed app. Rec: wedge = "sorts by type into a container, never touches your folders, one-click undo, verifiable code" for privacy-minded Mac users who distrust Sparkle (file names reportedly leave the Mac). First user: the owner's own 8 GB M2 setup, then Homebrew/GitHub users who already run Hazel-style tools. Put it in PRODUCT.md s1.

## MAJOR

4. **Roadmap order ignores Tidy and Sherlocking.** Tidy already ships Smart Eject, renaming, plain-English rules, duplicates, undo (competitors.md). macOS 27 reportedly suggests names from contents (indirect-competitors.md, "unverified beyond a summary"). Renaming and Smart Eject are therefore not differentiators; the container layout, Recents, and the Tray's "carry, then decide" are. Rec: reorder to v1 (shipping) > parity gaps > Tray > everything else; "By purpose" (content reading) is the most Sherlockable and costs the privacy story, so demote it below the Tray.
5. **Tray: build first among v2.** It has no direct rival in sorters (indirect-competitors rank 1; Dropover/Yoink are not sorters), reuses the engine (`decide`, journal, undo), and tray.md's references design avoids new ADR risk. Open: security-scoped bookmarks are not done (AGENTS.md). Rec: ship files-only Tray with references; defer links/snippets/new Links and Notes types.
6. **Model picker with BYOK/cloud: do not build.** It contradicts local-first; indirect-competitors ranks "subscription or cloud AI tier" as Avoid (rank 11) while PRODUCT.md s2 still plans a paid cloud tier. Rec: delete the paid tier from s2; revisit only after a benchmarked local model wins in `bench.py`.
7. **Parity gaps, in order:** (a) natural-language rules (competitors.md gap 3; ask-field infra exists, so build the rules UI plus a "what would match" preview, indirect rank 4); (b) subfolder exclusion / per-folder settings (Tidy's one concrete complaint); (c) Shortcuts via App Intents; (d) localization. Content search stays out. "Suggested shelves" already half exists (rule suggestions from corrections). Defer.
8. **Free + donations is not a business, only a project.** No evidence of donation conversion; competitors price at $9 to $42 one-time. Rec: treat it as a reputation project; if revenue matters, sell a $9 supporter build.

## MINOR

9. **Research claims are weak where they matter.** Sparkle pricing and data flow are unverified; no Reddit/HN/App Store reviews found; macOS 27 naming claim from one summary; Stacks "from general knowledge". The privacy wedge rests on Sparkle's data flow, which is unconfirmed. Rec: do not claim "Sparkle sends names to the cloud" until verified.

## Build order for tonight (code)

1. Verify the signing/notarize script and `Links` placeholders resolve (build.sh, `Components.swift`); wire the update check.
2. Make the no-model path explicit: Sorting page shows "Works without Apple Intelligence" and the onboarding step is skippable.
3. Per-folder subfolder exclusion setting.
4. "What would match" preview for rules (dry-run over existing candidates; reuse `plan`).
5. Then a files-only Tray spike behind a flag. No BYOK, cloud, By purpose or suggested shelves.
