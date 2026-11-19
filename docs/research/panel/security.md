# Security and privacy review (v2 plans)

## BLOCKER

1. **Rule destinations can be absolute.** `Engine.resolve` uses `/` and `~` paths as-is and blocks only `..`. A compiled natural-language rule could send files into Manual Shelves, `~/Library/LaunchAgents` or a vault folder. Fix: AI-made rules take only a shelf name from the existing type list. For every rule, standardize and symlink-resolve the destination and reject anything outside `<root>/My Shelves`, with Manual Shelves always refused.
2. **NL rules are persistent automation.** One injected or hallucinated rule misfiles forever. Fix: the model emits a typed `Rule` through guided generation (condition enum, shelf enum), never a glob or string interpreted later. Show a preview ("matches 14 files now", 5 examples) and require an explicit Save. Rules can never output trash or the Keep tag.
3. **Tray URL fetch (SSRF).** Fix: off by default. When on: https only, resolve the host and refuse loopback, link-local, RFC1918 and `.local`, re-check on each redirect (max 3), 1 MB and 5 s caps, ephemeral session (no cookies), no Referer.

## MAJOR

4. **Update check is unverified.** It opens `html_url` from the JSON without a host check, and the DMG is unsigned-checked. Fix: accept only `https://github.com/<pinned slug>/releases/`. Adopt Sparkle with EdDSA signatures, or verify the Developer ID signature and notarization before install. Never auto-install, and reject downgrades.
5. **Injection through names.** Classifier and Ask put file names and up to 20 child names into the prompt. The closed schemas limit the damage, but fix this anyway: strip control characters and newlines, cap names at 120 characters, and delimit untrusted data. Enforce `canTrash` in code, not only in the schema.
6. **Model-created shelf names.** `cleanName` allows "Manual Shelves", "Recents" and Unicode lookalikes. Fix: reject (NFKC, case-folded) any reserved or existing name.
7. **Cloud payload undefined.** Fix: a local "what was sent" log, switches off by default, and a typed struct per feature (name, extension, source host, and for rename/tag only, at most 2,000 characters if the user opted in). Never send Keys, vaults, Manual Shelves, iCloud placeholders, paths or the journal. A redactor (cards, IBAN, keys, long digit runs) runs first and blocks the item on a hit.
8. **BYOK storage.** Keychain only (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud sync). Never in `settings.json`, the journal, logs, crash reports or snapshots. Offer Remove key and require an https endpoint the user typed.
9. **Tray snippets on disk.** `tray.json` may hold secrets. Fix: mode 0600, excluded from backup and Spotlight, wiped by "Forget everything", and never added to a prompt without a user action.
10. **Files created from network or dropped content.** Set `com.apple.quarantine` on them. Write `.webloc` only for http(s) URLs. Never write executable types (`.command`, `.app`, `.pkg`, `.terminal`). Sanitize names as in finding 6.

## MINOR

11. **No sandbox.** `Kanso.entitlements` is empty, so an engine bug has full user-file reach, and the "security-scoped bookmarks" in tray.md mean nothing unsandboxed. Either sandbox with folder bookmarks, or drop that wording. Warn when `SIGN_ID` is unset and never publish ad-hoc builds.

## Required invariants for v2

- Model output is a choice from a closed set or a typed struct, never a path, glob, command or URL.
- Nothing a model produces can reach trash, Manual Shelves, Keys, vaults or a path outside `My Shelves`.
- Saved AI rules need a preview and an explicit Save.
- Any content read taints the request: no trash, and moves need confirmation.
- Fetched or dropped content is untrusted: quarantined, scheme-allowlisted, never executed.
- Network use is limited to the pinned update check, user-chosen downloads and opt-in cloud, with typed, redacted, inspectable payloads.
- Secrets live in the Keychain only.
- Releases are signed and notarized, and updates are verified.
