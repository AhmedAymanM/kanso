# Kanso architecture

The engineering source of truth. Every engineer re-reads this at the start of a task. `PRODUCT.md` says *what* and *why*, `CONTEXT.md` defines the words (shelf, island, watched folder…), `docs/adr/` holds decisions that must not be quietly reversed, and `AGENTS.md` is a short command reference. When this file and any other doc disagree about how the code works, this file wins; when this file and the code disagree, the code wins and this file gets a fix (see [Changing this doc](#changing-this-doc)).

Checked against `main` at `74f8586` (2026-10-09).

## 1. Module map

```
app/                      SwiftPM package "Kanso" (swift-tools 6.0, Swift 5 language mode, macOS 14+)   ← the product (Kanso v1)
  Sources/KansoCore/      engine library: no UI
  Sources/Kanso/          menu bar app (AppKit shell + SwiftUI views)
  Sources/kanso-cli/      headless engine for scripts and dry runs
  Tests/KansoCoreTests/   engine tests on temp folders (fake classifier)
  build.sh                release build → app/build/Kanso.app (ad-hoc signed)
src/kanso/                Python reference implementation + CLI `kanso`                              ← not shipped
bench.py, tests/          Python benchmark lab and its unit tests
menubar/                  legacy SwiftUI MenuBarExtra that shells out to the Python CLI                 ← legacy
docs/adr/                 accepted decisions
```

### KansoCore (engine)

| File | Owns |
|---|---|
| `Settings.swift` | `Settings` (every user setting, tolerant decoding), `FileType` + the 23 built-in types, `Rule`/`Condition` + 4 built-in rules, `Library` folder names, `Shelf` constants |
| `Store.swift` | On-disk state (§2): `Store`, `Action` (journal entry), `Pending`, `RenameProposal`, `RuleSuggestion`, `Correction` |
| `FileInfo.swift` | `Item.inspect` (metadata only: name, xattrs, stat — never opens contents), `Xattr`, `Tags`, `Stat` |
| `Engine.swift` | The pipeline (§3): `candidates` → `decide` → `plan` → `apply`; undo, trash, duplicates, corrections and rule suggestions, Recents cleanup, folder creation and icons |
| `Classifier.swift` | `Classifier` protocol, `Brain` (model facts/options, name cleaning), `AppleIntelligence` (Foundation Models, guided generation via `DynamicGenerationSchema`) |
| `Renamer.swift` | Meaningless-name detection, `Reader` (PDFKit/Vision, ≤ 2,000 chars, on-device), extraction (kind / organization / date), template names, original name in xattr `app.kanso.original-name` |
| `SmartEject.swift` | Finds the app on a mounted disk image, checks `/Applications`, `trashInstaller` |
| `Ask.swift` | The ask field's guided generation: move / trash / read / answer over file **indices**, never paths (ADR 0001) |
| `Stats.swift` | Overview numbers computed from the journal |

`FoundationModels` is weak-linked (`Package.swift`), so the same binary runs on macOS 14–25 with Apple Intelligence reported unavailable.

### Kanso (app)

AppKit shell: `NSStatusItem` + `NSPopover` (Quick settings), one **App window** (a fixed 1170 × 772 `NavigationSplitView`; sidebar pages Overview, Activity · Sorting, Renaming, Duplicates, Tagging, Smart Eject · General, Privacy & AI — `MainView.swift` `Page`), the **island** (`Island*.swift`, a non-activating `NSPanel`; replaces toasts), onboarding, and the rename review window. `AppModel.swift` owns the single `Engine`, the FSEvents watcher, a 60 s and a 3600 s timer, and `SMAppService` login item. Finder services **Don't Sort with Kanso** / **Allow Kanso to Sort** (`NSServices` in `build.sh`'s Info.plist, handled in `Shell.swift`) toggle the Keep tag.

There is **no separate Settings window and no tabs**; settings are pages of the App window (⌘, opens General). Older text describing a "Settings window with 4 tabs" (2026-09-29) is superseded.

### kanso-cli

`app/Sources/kanso-cli/main.swift`; bundled at `Kanso.app/Contents/Helpers/kanso-cli`. Same `Store` and `Engine` as the app (§4).

### Python reference (`src/kanso/`)

`sorter.py` (all file logic, no models), `brain.py` (the only model code: Apple FM through `apple-fm-sdk`, **von** as fallback), `__init__.py` (CLI and launchd agent `com.kanso.agent`), `default_config.toml`. State lives in `~/.config/kanso/` (`config.toml`, `journal.jsonl`, `state.json`, `learned.json`) — a different layout and format from the Swift app; the two never share state.

**von:** the product has no von (`PRODUCT.md`, decided 2026-10-05); nothing in `app/` references it. The Python reference still depends on `von-sdk` and uses it as the fallback classifier, because it is the benchmark lab. Don't port von to Swift; removing it from Python is a separate decision.

The Python code is a reference for behavior and benchmarks only. Behavior changes land in Swift; the Python side follows only when the benchmark needs it. Classification changes are benchmarked in `bench.py` (procedure in `AGENTS.md`).

## 2. On-disk data (Swift app)

State dir: `$KANSO_HOME` if set (tilde-expanded), else `~/Library/Application Support/Kanso`. Created on first `Store` init; `settings.json` is written immediately if missing. All dates are ISO 8601. Writes are atomic except journal appends.

### `settings.json` — `Settings`

Pretty-printed, sorted keys. **Every key is optional on read**: missing or undecodable keys fall back to the default, so older files keep working. Adding a setting = add a property with a default **and** a `d(.key, &key)` line in `init(from:)` (forgetting the second silently ignores the stored value).

| Group | Keys (defaults) |
|---|---|
| Roots | `onboarded` (false), `roots` (`~/Downloads`, `~/Desktop`, `~/Documents`), `pausedRoots` ([]), `since` (first launch; auto mode ignores items with ctime before it) |
| Sorting | `autoSort` (true), `sortingOffUntil`/`sortingOffSince` (nil), `offReminderShown`, `settleSeconds` (10), `graceMinutes` (0), `approach` (`kind`; `purpose` unused), `recents` (`links` / `hold` / `off`), `recentDays` (7), `folderIcons` (true), `sortFolders` (false), `keepTag` ("Keep"), `learnCorrections` (true), `unknownFiles` (`askModel` / `unsorted`), `suggestTypes` (true), `appleIntelligence` (true) |
| Smart Eject | `smartEject` (true), `smartEjectNotice` (true), `smartEjectOnlyEject` (false) |
| Renaming | `renaming` (true), `normalizeNames` (false, not implemented), `keepOriginalSearchable` (true), `askBeforeMassRenames` (true), `massRenameThreshold` (10), `separator` ("-"), `nameParts` (kind, organization, date), `dateFormat` ("yyyy-MM"), `extraMeaningless`, `disabledPatterns` |
| Tagging | `tagging` (false), `tagsPerFile` (2, capped at 2), `tagKind`, `tagOrganization`, `useExistingTags` (all true) |
| Duplicates | `duplicates` (true), `keeper` (`oldest` / `bestNamed` / `onShelf`), `checkManualShelves` (true), `duplicatesToTrash` (false), `autoTrashDuplicates` (false), `autoTrashDays` (30) |
| General | `islandMode` (`automatic` / `notch` / `below`), `shortcutHintUntil`, `showShortcutHint`, `collectDuringFocus`, `openAtLogin` (false), `showMenuBarIcon` (true), `appearance` ("system" / "light" / "dark"), `updateChecks` (true, not wired), `crashReports` (false), `islandShortcut` (⌥⌘K: keyCode 40, Carbon modifiers) |
| Learned | `types` (`[FileType]`: `name, emoji, description, match[], learned`), `learnedExts` ([String]), `rules` (`[Rule]`: `id, enabled, conditions[{field: name|ext|from|size, value}], dest, tags, matchAny, builtIn`) |

`types` and `rules` are stored in full, so a user's file does **not** pick up later changes to the built-in defaults.

### `journal.jsonl` — one `Action` per line

```
id (UUID)  run (8 hex, one per apply/undo batch)  ts  kind: sorted | renamed | duplicate | trashed
src  dst  link?  root  shelf  why  source  trigger: auto | menu | sort-everything | review
tags[]  oldName?  details{String:String}  undone  pending
```

- `why` is human-readable provenance ("extension", "rule …", "screenshot", "apple-intelligence new type Torrents", "duplicate of …"); `source` is what the decision read ("metadata only", "from name", "contents, page 1", "size + hash", "Smart Eject").
- `details` keys in use: `from`, `kept`, `size`, `pattern`, `kind`, `organization`, `date`, `corrected`, `action`, `installer`, `tagcolor:<name>`.
- **Write-ahead:** `apply` and journaled trashes append the entry *before* touching the file; a failed move/trash calls `discard(id)` (whole-file rewrite). A completed rewrite of an entry reuses its `id`; on load **the last line with a given id wins**. Undo skips entries whose `dst` is missing.
- `modify` (undo, pending flags, corrections) rewrites the whole file. Fine for years of use; revisit (SQLite) past ~100k lines.
- Undo of the last run = all non-undone actions of the latest `run`. Undo restores `src`, removes the Recents link and Kanso-added tags, clears `app.kanso.original-name`, and adds the Keep tag (otherwise the new ctime would re-sort it; not for restored trashes or items going back into Recents). Undoing a trashed copy makes its duplicate decision `pending` again.

### `pending.json` — `Pending`

`renames[]` (`RenameProposal`: `id, path, newName, shelf, source, details`), `renamesFound?`, `suggestions[]` (`RuleSuggestion`: `id, condition, shelf, files[], ts`), `dismissed[]` (suggestion keys like `from:<host>><shelf>`), `corrections[]` (`Correction`: `name, ext, from?, fromShelf, toShelf, ts`). Compact JSON, sorted keys.

### In the watched folders

- `<root>/My Shelves/<Type>[/<sub>]` — created on first use (`ensureLibrary` creates My Shelves + Manual Shelves on a root's first sort; Recents on its first link). Created folders are never removed. Folder icons (`Icon\r`) are set only on folders Kanso creates.
- `<root>/Manual Shelves` — never modified. Read only to find duplicates when `checkManualShelves` is on.
- `<root>/Recents` — symlinks to new arrivals (links mode, expire after `recentDays` by the link's own mtime) or real files (hold mode).
- Per-file xattrs Kanso writes: Finder tags (`com.apple.metadata:_kMDItemUserTags`), `app.kanso.original-name` after a rename. It reads `kMDItemWhereFroms` and `kMDItemIsScreenCapture` via `getxattr` (never `mdls`).

## 3. Pipeline contract

`AppModel` runs a sort on FSEvents (after `settleSeconds`), on the menu, or on Sort everything: `cleanRecents()` → `detectCorrections()` → `plan()` → `apply()`. The hourly timer runs `cleanRecents()` and `expireDuplicates()`. Nothing is sorted before onboarding finishes.

1. **`candidates(all:)`** — top level of each active root, skipping `My Shelves` / `Manual Shelves` / `Recents`, dotfiles, `~$*`, `Icon\r`, Keep-tagged items. Partial downloads (`.crdownload`, `.download`, `.part`, `.partial`, `.opdownload`, `.tmp`) and items younger than `settleSeconds` (or `graceMinutes` outside Sort everything) become `Waiting`. Auto mode skips ctime < `since`. Folders are skipped unless `sortFolders` (and never if they contain `.git`); bundles whose extension a type claims (`.app`, `.key`…) count as files.
2. **`decide(item)`** — first match wins: enabled rule → screenshot flag → extension in `types` → Apple Intelligence (only if `unknownFiles == askModel`, `appleIntelligence`, and the model is available) → `Unsorted`. The model gets **metadata only** (`Brain.facts`: name, type, screenshot flag, first download URL, up to 20 child names for folders) and picks from every type except Unsorted and Screenshots, plus `new` (only for files with an extension) and `unsure`. An existing pick, or a valid new type, is learned (`learnedExts`, type's `match`); `unsure`, a catch-all name, a name containing the extension, or a model error → `Unsorted`. There is **no von and no other fallback** in Swift.
3. **`plan`** — per item: duplicates (size, then SHA-256 over shelves; the keeper stays, ordered by `keeper`; the copy goes to `Duplicates` as `pending`), then renaming/tagging: only when the name is meaningless or tagging is on, and not on low battery, `Reader` reads ≤ 2,000 chars on-device (never Keys, Manual Shelves or iCloud placeholders). Sort everything, and more than `massRenameThreshold` renames, turn renames into `proposedName` → `pending.renames` for review.
4. **`apply`** — one `run` id per call; write-ahead journal line, move (unique name `X 2.ext`), Recents link, tags, original-name xattr.
5. **Corrections** — a sorted file found on another shelf is a correction; it moves a *learned* extension to the new shelf (built-in extensions never move); 3 with the same download host (or an extension no type claims) become a `RuleSuggestion`.

## 4. CLI and IPC surface

| Surface | Contract |
|---|---|
| `kanso-cli run [--all] [--dry-run]` | plan + apply with trigger `sort-everything` (`--all`) or `menu`. `--dry-run` prints `src -> dest [why · source]` and `planned N, waiting M`, moves nothing, skips `cleanRecents`. |
| `kanso-cli undo` | reverts the latest run; prints `restored N` |
| `kanso-cli status` | state dir, active roots, Apple Intelligence status, action and pending-rename counts |
| `Kanso` launch flags | `--snapshot DIR` (every screen, light + dark, then exit), `--icon FILE`, `--show [--page <name>]`, `--popover`, `--island` |
| `Kanso` env (dev/screenshots only) | `KANSO_HOME`, `KANSO_APPEARANCE`, `KANSO_SELECT`, `KANSO_EXPAND`, `KANSO_INDEX`, `KANSO_SCROLL`, `KANSO_QS`, `KANSO_ACTIVITY`, `KANSO_NOTICE`, `KANSO_BACKDROP`, `KANSO_CAPTURE`, `KANSO_DELAY`, `KANSO_SNAPSHOT_ONLY` |
| Finder services | `skipFiles` / `allowFiles` (port `Kanso`) add/remove the Keep tag; register only from an installed app |
| Python `kanso` | `run [--all] [--dry-run]`, `undo`, `install` / `uninstall` (launchd), `status [--json]`, `roots DIR...`, `config` — reference only |

There is no other IPC: no XPC service, no socket, no URL scheme. The app and `kanso-cli` share state only through the files in §2; don't run both against the same state dir at once (the `Store` lock is in-process).

## 5. Build, test and release topology

| | Where | What |
|---|---|---|
| Agents | Linux server | Write code and docs on `<seat>/KAN-<n>-<slug>` branches. **Cannot build or test Swift** (KansoCore imports AppKit, FoundationModels, PDFKit, Vision). Python tests also need macOS (`/usr/bin/xattr`). |
| Local hooks | each clone (`core.hooksPath .githooks`) | `pre-commit`: territory (`org/territory.yml`) + `Architecture-Ref` trailer, < 2 s, **no tests** (KAN-24) |
| Gate repo | VPS bare repo | `pre-receive` rejects pushes to `main`, misnamed branches, stale merge-base, out-of-territory diffs, missing/stale `Architecture-Ref`; a mirror pushes accepted branches to GitHub and opens the PR (KAN-21) |
| **`scripts/land KAN-<n>`** | Board's Mac | **The only merge path.** Fetch the PR branch, rebase on `main`, run `cd app && swift test` + `uv run python -m unittest discover tests`, merge, push `main`, close the PR. Paired `pre-push` refuses pushes to `main` not made by land with green tests. Never signs, tags or touches Apple secrets (KAN-25). |
| Release | Board's Mac | test → `app/build.sh` → sign (Developer ID, hardened runtime) → DMG → notarize → staple → verify. Needs the Apple Developer account (KAN-3). |

**No GitHub CI.** Tests run only in `scripts/land`; GitHub is a mirror and PR UI. See ADR 0003 (draft).

**Current state vs this target (2026-10-09):** `.githooks/`, the gate repo and `scripts/land` don't exist yet (M3, KAN-21/24/25). `main` still has `.github/workflows/swift.yml` (`swift test` on `macos-latest`), and open PR #11 (KAN-5) extends it into a CI build/sign/notarize pipeline with `scripts/release.sh`, `make-dmg.sh`, `notarize.sh`, `verify-release.sh`. Under this doc the workflow is removed once `scripts/land` exists, and the release scripts run by hand on the Board's Mac. Until then: Swift changes are verified only when the Board lands them; plan tasks so that is acceptable.

Tests today: **48** Swift engine tests (`app/Tests/KansoCoreTests/EngineTests.swift`; fake classifier, temp folders; trash tests put two 4-byte files in `~/.Trash`) and **24** Python tests (`tests/test_kanso.py`; models faked). Counts elsewhere (23, 28, 35, 37) are historical. Quote counts from `grep -c 'func test'` / `grep -c 'def test'`, not from memory.

Build products: `app/build/Kanso.app` (bundle id `app.kanso.Kanso`, `LSUIElement`, `kanso-cli` in `Contents/Helpers`, ad-hoc signed today). `Package.swift` passes `-platform_version macos 14.0 27.0` to the app's linker so macOS doesn't run it in compatibility mode (no Liquid Glass); check with `otool -l … | grep -A4 LC_BUILD_VERSION` (sdk 26+).

## 6. Invariants

Breaking any of these needs an ADR (new or revisited), not just a PR.

1. **Never delete.** Kanso never unlinks user files and never empties the Trash. Every move, rename and trash is journaled and undoable.
2. **ADR 0002 — trash only provably spent files.** On its own, Kanso trashes only an installer whose app is in `/Applications` with a ctime after the mount (Smart Eject). Beyond that, only what the user asked for: ⌘⌫, or a setting they enabled (`duplicatesToTrash`, `autoTrashDuplicates`). Defaults stay off.
3. **ADR 0001 — ask-field trash is gated in code.** Tools get file indices from a closed set, never paths; Kanso writes every confirmation; trash needs ⌘⌫, is capped at 20, and is disabled for a request once any content was read (taint rule).
4. **Write-ahead journal.** The journal line exists before the filesystem changes; a failed operation discards it.
5. **Manual Shelves is never modified.** No moves in, out or within; no renames, tags or icons.
6. **Models see metadata only** when sorting (By kind). Content reading is on-device, ≤ 2,000 chars, kept nowhere, only for opt-in features (renaming, tagging, ask), and never on Keys, vaults, Manual Shelves or iCloud placeholders. Models run locally; cloud is opt-in and a last resort.
7. **Built-in extensions never move** because of a model or a correction; only learned ones do.
8. **`KANSO_HOME` sandboxing.** Anything that runs Kanso outside a user's own session — tests, agents, QA, snapshots — sets `KANSO_HOME=<tmp>` **and** sandbox `roots` in that home's `settings.json`. The default roots are the real Downloads/Desktop/Documents. Engine tests construct `Store(dir:)` on temp dirs. Python: point `HOME` at a temp dir.
9. **Settings decoding stays tolerant.** Old `settings.json` / `journal.jsonl` / `pending.json` files must keep loading; new fields get defaults.

Known gap: `trashInstaller` (Smart Eject) trashes first and journals after, so it is not write-ahead (invariant 4).

## Changing this doc

- Only Forge and the Board edit this file. Anyone who finds it wrong opens a task for Forge with the file/line and the code that contradicts it.
- A PR that changes schema, on-disk data (§2), the CLI/IPC surface (§4), build or release topology (§5), or an invariant (§6) is labelled `arch-required` and must update this file in the same PR or link a Forge task that does. Forge reviews those PRs.
- Decisions with real alternatives get an ADR in `docs/adr/` (Forge drafts, the Board accepts); this file then summarizes the decision and links it.
- Every commit and PR carries `Architecture-Ref: <git rev-parse main:docs/ARCHITECTURE.md>`, the blob of this file the author read.
- Keep facts here, not history: no dated status logs, no test counts without the command that produces them. Update the "Checked against" line when re-verifying.
