# AGENTS.md

Kanso is an automatic macOS file sorter, Sparkle-style. It sorts the top level of watched folders (default: `~/Downloads`, `~/Desktop`, `~/Documents`) by **file type** into `<root>/My Shelves/<Type>`. `<root>/Manual Shelves` is the user's own and is never touched. `<root>/Recents` shows new arrivals as symlinks.

- **The extension table (plus the screenshot xattr flag) decides known types with no model.**
- **Apple Intelligence** (on-device Foundation Model through `apple-fm-sdk`) handles unknown extensions and folders. It picks a type, creates a new one (name, emoji and description, only for files that have an extension), or answers unsure, which goes to `Unsorted`.
- **von** ([wfzyx/von](https://github.com/wfzyx/von), local ModernBERT, about 1.5 GB in `~/.cache/huggingface`) is the fallback. It only picks existing types.

**Git workflow (2026-10-05):** never commit or push to `main` directly. Every change goes on a feature branch (`feat/…`, `fix/…`, `chore/…`, `docs/…`) and lands through a pull request.

User decisions:
- **Generative models run locally:** Apple's Foundation Models, or open models that earned their place in `bench.py`. Cloud models are strictly opt-in and a last resort. (Reworded 2026-09-25; it used to be Apple-only.)
- Models see **metadata only** (name, type, download URL, screenshot flag) in the type approach. Content reading (text, OCR) is allowed only in opt-in features and only on-device; see Product decisions.
- **Sort by type, not by guessed meaning** (2026-09-25). The old content subfolders (Finance/Work/…) live on in `[context]` (`enabled = false`), kept for future AI tagging, renaming and context-aware organization. Every type has a `description` for the same reason.
- **n8n / Make / Zapier exports are plain `.json`** (Zapier's are a `.zip`). Default `[[rules]]` use the download URL (`from`) and `*blueprint*.json` to route them to Automations. A self-hosted n8n host without "n8n" in its name still goes to JSON.
- **Emoji choices:** Documents 📄, Reports 📊 (spreadsheets), Presentations 📽️, Diagrams 📐, Apps 📲, Unsorted ❓. The rest are in `default_config.toml`.
- **Databases** is its own type (sql, sqlite, db, bson, dump…), so `.sql` is no longer under Code. Added 2026-09-25 along with Automations (Shortcuts, Automator `.workflow` bundles, AppleScript, Keyboard Maestro, Alfred…), 3D Models, Keys (including `kdbx`), Calendars, Contacts and Torrents, so these common types never depend on a model.
- **Only download models that fit this 8 GB Mac.**

## Product decisions

**Read `PRODUCT.md` before changing behavior**, `CONTEXT.md` for the product's vocabulary (shelf, tray, island, watched folder…), and `docs/adr/` for decisions that must not be quietly reversed (0001: ask-field trash safety; 0002: Kanso trashes on its own only provably spent files). The UI/UX grilling on 2026-09-29 replaced toasts with the island and restructured settings; the Swift app in `app/` predates it. It holds every product decision from 2026-09-25: the name Kanso, the folders, By kind and By purpose, earned trust, content-reading limits, renaming, tags, duplicates, toasts, licensing, the roadmap and the success criteria. The essentials for code work:
- **Kanso v1 is a Swift rewrite.** This Python code is the reference implementation and the benchmark lab.
- **Folders:** `My Shelves` ✨ (sorted), `Manual Shelves` 🏠 (never modified), `Recents` 🆕 (symlinks).
- **Principles:** adopt the user's structure, learn from their habits, be seamless. Everything can be undone, and Kanso never deletes by default.
- **Content reading** is on-device only, reads a little and keeps nothing. It never touches Keys, vaults, Manual Shelves or iCloud placeholders. By kind stays metadata only.
- **Generative models run locally** (Apple FM, or benchmarked open models). Cloud is opt-in and a last resort. Classifiers must produce confidence scores.
- **Only download models that fit this 8 GB Mac.**

## Commands

```bash
uv sync --extra apple --group bench                  # install everything (plain `uv sync` REMOVES apple-fm-sdk and the bench models)
uv run python -m unittest discover tests -v          # all tests (~0.2 s, models are faked)
uv run python -m unittest tests.test_kanso.KansoTest.test_apple_intelligence_decides_without_von
uv run kanso run --all --dry-run                      # preview with the user's config; moves nothing
uv run python bench.py >> BENCHMARKS.md              # compare approaches on real folders (dry run)
menubar/build.sh                                     # build + install ~/Applications/Kanso.app, register Finder services, relaunch
```

CLI: `run [--all] [--dry-run]`, `undo`, `install` / `uninstall` (launchd agent), `status [--json]`, `roots DIR...`, `config`.

Try the CLI on real folders without touching the user's config: point `HOME` at a temp dir and keep the model cache. (`bench.py` doesn't need this, because it uses the shipped default config directly.)

```bash
S=$(mktemp -d); mkdir -p $S/.config/kanso
sed 's#^roots = .*#roots = ["/Users/ahmedayman/Desktop"]#' src/kanso/default_config.toml > $S/.config/kanso/config.toml
HOME=$S HF_HOME=/Users/ahmedayman/.cache/huggingface uv run kanso run --all --dry-run   # without HF_HOME von re-downloads 1.5 GB
```

## Swift app (`app/`, Kanso v1)

A SwiftPM package, no Xcode project. `KansoCore` is the engine (a port of `sorter` + `brain`, plus renaming, tagging, duplicates, stats); `Kanso` is the menu bar app; `kanso-cli` runs the engine headless.

```bash
cd app && swift test                                  # 37 engine tests on temp folders (fake classifier; trash tests put two 4-byte files in ~/.Trash)
cd app && ./build.sh && open build/Kanso.app          # release build → app/build/Kanso.app (ad-hoc signed)
KANSO_HOME=/tmp/k app/.build/debug/kanso-cli run --dry-run   # engine without UI; KANSO_HOME isolates settings/journal
KANSO_HOME=/tmp/k app/.build/debug/Kanso --snapshot /tmp/shots  # renders every screen, light + dark, to PNGs
```

- **State** lives in `~/Library/Application Support/Kanso` (`settings.json`, `journal.jsonl`, `pending.json`), or `$KANSO_HOME`. Always set `KANSO_HOME` plus sandbox `roots` when testing: the default roots are the real Downloads/Desktop/Documents. Nothing is sorted before onboarding finishes.
- **Design source:** `../kanso-designs/handoff/HANDOFF.md` and `DESIGN_SYSTEM.md` (v2 frames; `FINAL —` frames are v1). Tokens (light + derived dark) are in `Theme.swift` (`K`, `Tint`).
- **Pipeline** mirrors the Python one: `candidates` → `decide` (rules → screenshot flag → extension → Apple Intelligence via `DynamicGenerationSchema` → Unsorted) → duplicates (size, then SHA-256; the keeper stays) → renaming/tagging (only meaningless names; PDFKit/Vision reads ≤2,000 chars, `NLTagger` + company-suffix regex for the organization, `NSDataDetector` + month-year for the date) → `apply` (journal line per move, Recents symlink, tags, original name in an xattr).
- **Mass renames** (over `massRenameThreshold`, and everything found by Sort everything) become `pending.renames` for the review window instead of renaming.
- **Corrections:** a sorted file found on another shelf counts as a correction; 3 with the same download host (or an extension no type claims) become a rule suggestion. A correction also moves a *learned* extension (`settings.learnedExts`) to the new shelf; built-in extensions never move.
- **Folders appear only when used:** `ensureLibrary` creates My Shelves + Manual Shelves on a root's first sort, Recents on its first link; created folders are never removed.
- **Trash (ADR 0002):** duplicates go to the Duplicates shelf or straight to the Trash (`duplicatesToTrash`), and held copies can expire after `autoTrashDays` untouched (`expireDuplicates`). Smart Eject (`SmartEject.swift`) ejects a mounted .dmg and trashes it once its app is in /Applications with a ctime after the mount.
- **v1 parity batch (feat/v1-parity, written without a compiler, not built or tested yet):**
  - **Settings are versioned** (`Settings.currentVersion`, `migrate()`); a new field needs a line in `init(from:)`, and `SettingsTests.testEveryFieldSurvivesARoundTrip` fails by key name if one is forgotten. An older `settings.json` is copied to `settings.v<N>.bak` before the migrated file replaces it.
  - **Destination safety:** a relative destination is resolved by `Engine.resolve`, which refuses `..`, Kanso's own folder names (My Shelves, Manual Shelves, Recents; NFKC, case and invisible characters folded) and symlinks that leave My Shelves, and parks the file in Unsorted. Absolute or `~` destinations work only for a rule the user typed (`Decision.userPath`: not `builtIn`, not `automatic`). AI picks, new types, learned extensions, corrections and rule suggestions go through `Engine.automaticShelfAllowed`, which also refuses Keys and Duplicates (the extension table still files `.pem` into Keys). Rules made from suggestions carry `automatic = true`. The rule editor has "Other folder…" with a visible warning (`Engine.destinationWarning`). A future plain-English rule compiler must set `automatic`.
  - **Duplicate keeper reason:** `details["keptWhy"]` is journaled by `plan` (`Engine.keeperReason`) and shown in the Activity duplicate detail.
  - **Rule preview** (`Engine.previewRule`, `RulePreview`): a dry run of one saved or draft rule over the current candidates in rule order, with no model call and no side effects; the editor shows it under "What would match" and flags files an earlier rule takes first.
  - **Excludes:** `Settings.excludes` (name globs, every watched folder) and `Settings.rootExcludes` (watched folder as written in `roots` → subfolder names), checked in `Engine.ignored`, so excluded items are never read, hashed or tagged. UI: `ExcludesSection` on Sorting. Per-folder overrides of other settings are still not built (engineering panel blocker 2).
  - **Undo card:** after a run the user started (`trigger` not `auto`: Sort now, Sort everything, Rename all) with at least 2 actions, `Batch.summary` gives one island card (`Notice.batch`) with one Undo for the run; its per-file rename notices are folded into it. Plain sorts stay silent.
  - **Saved views:** `Settings.savedViews` (`SavedView`: filter label, search, shelf, last N days); `ActivityFilter.includes` is the one place that says which journal actions a filter shows. Views only change the list.
  - **No-model path:** Sorting has an "Unknown file types" row (toggle disabled with the status when Apple Intelligence is unavailable); onboarding's AI step shows no dead-end button when `AppleIntelligence.canBeTurnedOn` is false (macOS 14-15, ineligible Macs). The only network use is the daily update check; the copy says so.
- **App shell** is AppKit (`NSStatusItem` + `NSPopover` for Quick settings, `NSWindow`s with SwiftUI for one App window (sidebar pages: Overview, Activity · Sorting, Renaming, Duplicates, Tagging, Smart Eject · General, Privacy & AI; rules are inline on Sorting; ⌘, opens General), FSEvents watcher, `SMAppService` login item).
- **Island** (`Island.swift`) replaces toasts: a non-activating `NSPanel` at the top center of the active screen. Notch skin: black with ears melting into glass (Droppy-style). Capsule skin (no notch, "below the notch" mode, or when a notch app like NotchNook runs, since Kanso yields): Liquid Glass on macOS 26, material before, solid with Reduce Transparency. One Carbon hot key, ⌥⌘K, opens it. Plain sorts are silent. Return never runs a ⌘⌫ action. `--island` / `--popover` launch flags open them.
- **Liquid Glass needs the real SDK stamp.** SwiftPM writes the deployment target (14.0) as the binary's SDK version, and macOS then runs the app in compatibility mode with no Liquid Glass. `Package.swift` passes `-platform_version macos 14.0 27.0` to the linker; check with `otool -l .build/debug/Kanso | grep -A4 LC_BUILD_VERSION` (sdk must be 26+). The window is a native `NavigationSplitView` in an `NSHostingController` with `sceneBridgingOptions` (toolbar title, glass edge under it); the scroll view must be the detail's root or the edge effect disappears. Buttons use interactive `glassEffect` (`liquid(_:)`), switches are native `Toggle(.switch)`.
- **Window and island behavior (2026-10-01):** the App window is a fixed 1170 × 772 (not resizable), with a 15 pt toolbar title, no back/forward and no sidebar toggle (removing the toggle shrinks the column, hence `.frame(width: 220)` on the sidebar). The soft glass edge under the title is our own `SoftTopEdge` (material band shown once the scroll view is scrolled), because the system edge effect only showed with the sidebar collapsed. `settings.appearance` (system / light / dark) sets `NSApp.appearance`. Buy Me a Coffee is a quiet card at the bottom of the sidebar (butter fill on hover). Quick settings tiles are solid, not glass: on = white/near-black and raised, off = flat grey; the popover hides its arrow via the private `shouldHideAnchor` key (guarded). Island content enters staggered (`Stagger`) after the shape grows; its lip shows only esc to close plus arrows that do something. The notch island grows out from under the notch and shrinks back into it (`NotchReveal`); its work-in-progress beam (`IslandBeam`) runs left to right and never crosses the top edge. Quick settings opens below the menu bar even when its glyph is hidden under the notch.
- **App pages (2026-10-01):** Overview (`OverviewPage.swift`) is the v2 redesign: headline, the Kept-in-order hero beside ONE Needs-you card at a time (pager, Later cycles, Rename all applies every proposal as one run), the month chart beside "Where files went", and four tinted counters. Tagging and Smart Eject have their own pages (designed in Pencil, light + dark): Tagging toggles `tagKind` / `tagOrganization`; Smart Eject has `smartEjectNotice` (island notice) and `smartEjectOnlyEject` (eject, leave the installer). **Activity v3** (`ActivityPage.swift` list, `ActivityDetail.swift` + `ActivityParts.swift` detail, from the Pencil frames "Activity v3", "Tag flow", "Tag picker"): a glass search capsule with a round filter menu, our own All / Needs you · N / Handled capsule (`ActivityFilterBar`, white raised pill, `.isSelected`; the count equals the sidebar badge), NEEDS YOU / TODAY / YESTERDAY groups, and one detail card per entry: head row, a pastel hero (periwinkle rename, lavender rule, mint sorted and batch, butter duplicate, aqua waiting), "How Kanso decided" (a warning triangle when something was a guess), inline pills bottom right, and a footer hint plus shortcuts. Rename review and Batch open a file-by-file view (pager, ← → cycle, esc back, per-file hero, recipe chips or the "Checked in order" ladder; actions Rename this file / Edit name… and Undo this file / Keep change). "Rename all" applies only proposals with a clear title (`details["kind"]`); the rest stay for review. Renamed is the flat tag-flow layout (pill head, decision table, bottom bar with Undo rename, Rename…, Shortcuts ⌘/); tags carry Finder colours (`details["tagcolor:<name>"]`), `+ Add tag` opens `TagPicker` (type, ↩ pick, ⇧↩ create, ← → colour). `Rename…` is `Engine.renameFile` (journaled as a rename, undoable). Not backed by the engine, so omitted: the "Name future IKEA receipts this way" toggle. Snapshots: `KANSO_SELECT=renamed|sorted|batch|rename-review|rule|duplicate|installer|waiting|undone`, plus `KANSO_EXPAND=1 KANSO_INDEX=n` for the file-by-file views; `tag-picker-*` and `name-popover-*` render the popovers standalone (NSPopover itself can't be snapshotted).
- **Tray (beta, 2026-10-30, files only; `Tray.swift` in KansoCore, `TrayModel/TrayViews/TrayDrag.swift` in the app):** behind `settings.trayEnabled` (default false, General > Tray). `TrayStore` keeps references (path + bookmark data, `tray.json` mode 0600, excluded from backup, atomic writes, max 100); a dropped file is never moved, copied or read. `Engine.trayPlan()` runs the normal `decide` (rules, screenshot flag, extension table, Apple Intelligence on the name) with no content reads and no duplicate hashing; `trayOrganize` hands the moves to `apply` as ONE run (`trigger: "tray"`, one undo, Recents links). Rows that stay with a reason: missing, in Manual Shelves, Keep tag or excluded, already on the shelf, a destination inside Manual Shelves. A file outside every watched folder goes to the first active root. Keys are moved by extension and shown with a lock. "Change a shelf" only offers existing types (never Keys/Duplicates). The island gets a Tray page (lip button with a count, `⌘T`, `⌘V`, `↑↓`, `⌥↑⌥↓`, `⌫` forget, `↩` Organize then Move, `⌘Z`; Return/⌘⌫ never trash from here). The preview shows the first 5 plans (`trayPlansShown`), then only for a new shelf or more than 10 files. Drag: `TrayDragMonitor` (global monitors, file-URL drag pasteboard only, 250 ms dwell in a 160 x 44 zone, screen under the pointer, 220 pt hysteresis) opens the island; `.onDrop` on `IslandBody` accepts files and refuses promises and links; after a drop it shrinks in 2 s unless used (never under VoiceOver). Finder service "Add to Kanso Tray" (needs `build.sh` + `pbs -update`). Snapshots: `island-*-tray-{empty,over,items,planning,preview,error}`. **Not done:** the ask field on the Tray, Quick Look on plan rows, reorder persistence across sessions is done but type-to-filter after 8 items is not, `.layoutChanged` post when the island grows for a drag, a real-Mac test of drag detection and multi-monitor placement (global monitors may not see `leftMouseDragged` during every drag session), links and snippets (later, each needs its own review), "Still carrying N things" after 7 days.
- **Illustrations** (`Illustrations.swift`): the feature banners carry small living illustrations drawn with SwiftUI `Canvas` (no Lottie or Rive runtime: no dependency, no asset files, 30 fps only while visible). Each loops, follows the pointer (parallax) and replays on click; Reduce Motion and snapshots draw one settled frame.
- **Island overview** (2026-10-01): one needs-you card at a time (← → or Later cycle), actions come from `Island.actions()` (card actions first, then the Recently rows); after acting, a one-line confirmation shows for 3 s and "Nothing else needs you · N handled" replaces the head when the last card is done. Every expanded island screen has the same two glass buttons in the lip: keyboard shortcuts (⌘/) and Settings (⌘,, which opens the App window). The "All quiet" art is `AllQuietArt.swift` (a PNG exported from the design).
- **Check glass on screen, not in snapshots:** `Kanso --show --page sorting` opens a page; `KANSO_SCROLL=bottom` opens it scrolled (glass edge under the title), `KANSO_QS=menu` opens Quick settings with the Sorting menu open (`--popover`). Capture with `screencapture -l <windowID>`.
- **Snapshots** set `Motion.snapshot`, which draws the solid fallbacks because ImageRenderer can't render glass or materials. Check real glass on screen. SwiftUI's `Settings`/`Group` clash with ours, hence the typealiases in `Theme.swift`.
- **v2 models and rules (2026-10-30):** `Classifier` now carries `name`, `capabilities`, `availability` (ready + plain reason) and an optional `Pick.confidence`; protocol-extension defaults keep small fakes to `available` + `choose`. `Settings.modelChoice` (`appleIntelligence` | `rulesOnly`) replaced the `appleIntelligence` Bool (kept as a computed alias; settings v2 migrates a stored `false` to `rulesOnly`). `ModelPicker.options` feeds Privacy & AI (Kanso Local is a disabled row, "Not available yet"). **No BYOK, no cloud, no network calls to a model.** Plain-English rules (`RuleDraft.swift`): the model returns a `RawRuleDraft` (closed enums for field and destination, strings for values) behind `RuleCompiler`; `RuleDrafting.validate` keeps only condition values that literally occur in the sentence, escapes glob characters, drops path separators, accepts a destination only from the existing allowed shelves or a new name that passes `automaticShelfAllowed` (never Manual Shelves, Recents, Keys, Duplicates, Unsorted, Screenshots, Trash), and marks the rule `automatic`. The Sorting page shows the draft in the normal editor with "What would match"; nothing saves without Save (`Engine.saveDraft` re-checks). The field is hidden with the reason when no model can write rules. Suggested shelves (`ShelfSuggestions.swift`): 5+ items in `My Shelves/Unsorted` sharing an unclaimed extension (or a non-generic leading word) become a `Need.shelf` card; Accept recomputes from disk, creates the type (a word also adds an automatic name rule) and moves the files as one run (trigger `suggestion`); Dismiss is stored in `pending.dismissed` as `shelf:<kind>:<key>`. Names and emoji are deterministic ("QQQ Files", 🗂️); model naming is not wired. Not verifiable in CI: the real `AppleIntelligence.compile` guided generation and the new UI on screen.
- **Ask field** (`IslandAsk.swift`, `Ask.swift`): macOS 26 with Apple Intelligence on, hidden otherwise. Guided generation picks move / trash / read / answer over a closed set of file numbers (never paths); Kanso writes every confirmation; trash needs ⌘⌫, is capped at 20, and is disabled after a read (ADR 0001 taint rule). The thinking orb and a sage beam show while it answers; a read over 2 s shows the same orb in the compact island. **Not done yet:** the "How it works" showcase videos, the island's Reduce Transparency and Increase Contrast checks on real glass, the beam on finished renames (owner to pick variant A or B; only the ASCII sweep exists), the Tray (v2), Kanso Local download (no model exists; shown as "Not available yet"), cloud AI, By purpose, Focus detection (no public API; only full-screen apps quiet the island), "Also normalize my names", security-scoped bookmarks for the sandboxed build, notarization/Homebrew. The GitHub and Buy Me a Coffee URLs in `Components.swift` (`Links`) are placeholders.

## Benchmarking (do this for every classification change)

Any change to how files are classified (new model, prompt, category descriptions, `min_confidence`, new metadata field) gets benchmarked before and after:
1. Add or adjust an entry in `APPROACHES` in `bench.py`. Keep the old approach so both show up side by side.
2. Run `uv run python bench.py >> BENCHMARKS.md`. It adds a dated section with accuracy, ms/file, a table of disagreements and all per-file results.
3. Under that section, add a short `### Findings` list: the accuracy change, safe misses (left at the category) vs wrong folders, and patterns.

Ground truth is `bench_labels.json` (`"<root>/<file>": "My Shelves/<Type>"`). Since the switch to types, the labels come from the extension table and the screenshot flag, so only unknown types (currently one `.pem`) actually test a model. Add hand labels for new unknown types as they show up. Unlabeled files aren't scored. `bench.py` points `sorter.LEARNED` at a temp file so it never teaches the real config. The `Typed` adapters (laya, decider, verdict) need `--group bench`.

Both `BENCHMARKS.md` and the labels file contain real personal file names, so keep them out of public repos.

## Architecture

- `src/kanso/sorter.py`: all file logic, no models.
  - Config: `load_config()` merges `learned.json` into `categories`; `learn()` writes to it.
  - Scanning: `candidates()`, then `inspect()` (xattr metadata only).
  - Deciding: `decide()` checks rules, then the screenshot flag, then the `Brain`.
  - Acting: `plan()` builds `Move`s (with `link` in links mode) and `apply()` moves, links, journals and tags. Also `undo()`, `clean_recents()`, `prepare_roots()`, `make_dir()` (creates a folder and sets its emoji icon) and `set_folder_icon()` (a JXA script via `osascript`).
- `src/kanso/brain.py`: the only place that touches models, and they load lazily.
  - `classify()` returns the type immediately when the extension is known, unless natural-language `when` rules exist.
  - For unknowns, `folder_options()` offers every type except Unsorted and Screenshots.
  - `_fm_choose()` does guided generation of `Pick{folder anyOf [types…, "new"?, "unsure"], name, emoji, description}`.
  - `_von_classify()` makes one `system_one` call, with a p1 − p2 confidence check.
  - Picks for extensions are remembered with `sorter.learn()`.
  - `state_for()` is the only input either model gets.
- `src/kanso/__init__.py`: the CLI, and it writes the launchd agent `com.kanso.agent`. The agent uses `WatchPaths` on the roots and `Recents/`, plus `StartInterval` 3600 so Recents links expire and held files age out. Nothing stays resident.
- `src/kanso/default_config.toml`: copied to `~/.config/kanso/config.toml` on first load. It defines categories (`match` extensions, `sub` subfolders with descriptions the models choose between) and user `[[rules]]` (`glob`, `ext`, `from`, `when`). An existing user config does **not** pick up later default changes.
- `menubar/Kanso.swift`: a SwiftUI `MenuBarExtra` with no logic of its own. It shells out to the `.venv/bin/kanso` path baked into Info.plist (`KansoCLI`) by `build.sh`. It also provides the Finder services **Don't Sort with Kanso** / **Allow Kanso to Sort**, declared as `NSServices` and working by toggling the Keep tag.
- `bench.py`: runs each entry of `APPROACHES` through `sorter.plan()` and prints markdown. Model output goes to stderr.

Pipeline for an item:
1. It must pass `candidates()`.
2. In `hold` mode, a new item moves to `<root>/Recents/` and waits `recent_days`.
3. `inspect()`, then `decide()`.
4. `resolve()` puts a relative destination under `<root>/My Shelves/`.
5. `apply()` moves the item. In `links` mode, when the item arrived within `recent_days`, it also leaves a symlink in `Recents`.
6. Each run starts with `clean_recents()`, which drops expired or broken links, and `prepare_roots()`.

### Non-obvious behavior

- **Arrival time is `st_ctime`,** which changes when an item is moved or renamed in. Auto mode ignores anything with a ctime before the `since` value in `~/.config/kanso/state.json`, which is set on first run or install, so pre-existing clutter is only touched with `--all`.
- **Metadata comes from xattrs via `/usr/bin/xattr -px`, never `mdls`.** `mdls` returns "could not find" in sandboxed and background processes. `kMDItemWhereFroms`, `kMDItemIsScreenCapture` and `_kMDItemUserTags` are binary plists.
- **Keep tag** (`keep_tag`, default `Keep`): items with this tag are never moved. `undo` adds it to restored items, because otherwise their new ctime would make them get re-sorted immediately.
- **Folders don't move** unless `sort_folders = true`. Folders containing `.git` never move. Bundles whose extension matches a category (`.app`, `.key`…) count as files.
- **Relative destinations** (types, rule `dest`) resolve inside `<root>/My Shelves/`. Absolute or `~` destinations are used as-is.
- **Unsure goes to `Unsorted`.** That happens when Apple Intelligence answers `unsure` or proposes a catch-all name (`CATCH_ALL`, like "Unknown Files"), or when von's confidence (p1 − p2) is below `min_confidence` 0.4.
- **Learned types** (`~/.config/kanso/learned.json`, `{ext: {type, emoji, description}}`) make an extension "known" from then on. That's also true when the model picked an existing type, so a bad pick sticks until the entry is deleted. Extensionless files and folders are never learned and can't create types.
- **Apple Intelligence** leaned toward existing types (`.ics`, `.vcf` and `.kdbx` went to Documents) even with instructions that name `new`. `.torrent` and `.p12` did get new types.
- **Recents links** expire by the symlink's own mtime. Real files in Recents are left alone in links mode. `undo` deletes the run's links (the journal entry has a `link` key).
- **Folder icons** come from `set_folder_icon`, which draws the system folder icon with the emoji on top and writes `Icon\r`. They're set only when Kanso creates the folder, so existing folders (for example Sparkle's) keep their icon. Tests patch this function out.
- **Journal:** every move is appended to `~/.config/kanso/journal.jsonl` as it happens. `undo` reverts the last run id.
- **Tests:**
  - `FakeVon` is injected through `brain._von`. `FakeAI` subclasses `Brain`, overriding `_fm_choose` (it returns a `NS(folder, name, emoji, description)`) and setting `_fm = True`.
  - `setUp` patches `sorter.set_folder_icon` and `sorter.LEARNED`.
  - Real torch and the SDK are never imported.
  - The real `_fm_choose` is smoke-tested by hand against the real SDK (see BENCHMARKS.md 2026-09-25).
- **Finder services** only register from an installed app, which is why `build.sh` copies it to `~/Applications` and runs `pbs -update`.
- **Full Disk Access:** the background agent needs it granted to the real Python binary (`kanso status --json` → `python`), otherwise macOS blocks Desktop, Documents and Downloads.

## Environment facts (verified 2026-09-24; updated 2026-09-25: Xcode 27.0 installed, `apple-fm-sdk` builds, `kanso status` shows apple intelligence on)

- **Machine:** Apple M2 with 8 GB RAM. The benchmark reports macOS 27.0. Xcode 27.0 is installed and selected, with the license accepted.
- **Apple Intelligence works.** `uv sync --extra apple --group bench` builds `apple-fm-sdk` 0.2.1, and `kanso status` shows apple intelligence on. A call takes about 1.2 s warm and about 6 s for the first one. Note that a plain `uv sync` removes the apple extra and the bench group.
- **Without Xcode:** the `shortcuts` CLI exists, and on macOS 26 the Shortcuts app has a "Use Model" action. That's a possible bridge (`shortcuts run NAME -i FILE`), but the user chose the SDK route.
- **Sparkle is not installed** (the user confirmed this on 2026-09-25). `~/Desktop/My Shelves` and `~/Desktop/Recents` are leftovers from it. Kanso's own names differ except for `Recents`, which Kanso reuses.
- **`~/.config/kanso/config.toml`** was replaced with the type-based default on 2026-09-25 and refreshed after the new types were added. It's identical to the shipped default. The old one is `config.toml.bak`; it had default roots and no rules.

## Status

Done and verified:
- CLI and sorting pipeline, with 23 unit tests passing.
- 2026-09-25: **type-based layout** (My Shelves, Manual Shelves, Recents links or hold or off, emoji folder icons, learned types). Verified with a real run and undo in a temp root, and with a dry run on the real Desktop.
- Sandbox runs with real von: sort, undo and the Keep tag work.
- Apple Intelligence as the classifier, with von as fallback. Contents are never read.
- Menu bar app builds, installs and launches, and loads status through the CLI.
- Finder services tested with `NSPerformService`: the Keep tag is added, then removed.
- `bench.py` and `BENCHMARKS.md`. First scored run on 90 real files: extension only 10/90, von 35/90 (43 safe misses, 12 wrong).
- 2026-09-25: small typed-decision models, through `Typed` in `bench.py` (bench-only deps: `uv sync --group bench`). Results: **laya-multilingual 54/90** (10/14 German names right), decider-0.8b 51/90 (fewest wrong, 3), laya 30/90, verdict 26/90.
  - Skipped as too big for 8 GB: nimble 9B, openjev's DiffusionGemma 26B, decider-2b.
- 2026-09-25: **real Apple Intelligence path works** (`uv sync --extra apple --group bench`). It scored 59/90 at 1.55 s/file but **never answers unsure**, so all 31 of its misses are wrong moves.

- 2026-09-26: **Swift app** in `app/`: every FINAL screen (popover, overview, activity with all detail types, insights, general, models, approach, folders, types, rules, renaming, tagging, duplicates, privacy, about, review window, toasts) plus onboarding, in light and dark. 28 engine tests pass. Verified in a sandbox: a real run where Apple Intelligence picked shelves for unknown extensions, undo, template renames (`Invoice-Vattenfall-2026-03.pdf`), duplicates, a rule suggestion, live FSEvents auto-sort, the popover and toast panel on screen, and first-launch onboarding.
- 2026-09-29: **UI/UX grilling decisions implemented** (designs ignored for now): the island replaces toasts (notch + Liquid Glass capsule, ⌥⌘K, yields to notch apps); Quick settings popover; Settings window with 4 tabs; the Kanso window has only Overview and Activity; pastel mint theme; 3-step onboarding with the permission explained first; sorting off with a duration; Smart Eject; duplicates to Trash with expiry; no empty folders; corrections teach learned types. 35 tests pass; snapshots checked in light and dark. The live glass look hasn't been screenshotted (no Screen Recording permission for the agent).

Not yet exercised:
- The launchd agent on the real home folder (never installed).
- The Swift app on the real home folders, global hot keys pressed by hand, Finder services from the installed Swift app, open-at-login.

## Backlog (priority order)

1. **Kanso v1 in Swift** (see Product decisions; built 2026-09-26 in `app/`, see "Swift app" for what's left). Port `sorter` and `brain` behavior:
   - By kind, My Shelves / Manual Shelves / Recents, emoji icons, learned types
   - earned trust, and a preview for the first Sort everything
   - template renaming, tagging, duplicates
   - onboarding, menu bar, settings
   - macOS 14+ on Apple silicon; Developer ID + Homebrew

   The Python code stays as the reference implementation and the benchmark lab.
2. **Benchmark small local LLMs** (Qwen2.5-0.5B/1.5B, Llama 3.2 1B, Gemma 3 1B, Qwen3-1.7B; 4-bit via mlx-lm or llama-cpp-python) in `bench.py`:
   - classification with option-probability scoring
   - a renaming test set, compared against Apple FM, laya and template renaming

   Only models under about 2 GB. A winner becomes "Kanso Local+" in the v2 picker.
3. **Kanso Local model for v1:** check that laya-multilingual (or a smaller typed-decision model) converts to Core ML or ONNX, for tagging and unknown types on macOS 14–15.
4. **By purpose research** (for the release after v1): the content-reading pipeline within the agreed limits, adopting existing folder names, earned-trust thresholds, and a benchmark with content labels. Earlier findings: name-only tops out around 60–66%, and laya-multilingual handles German well.
5. **Personal use now:** `kanso install` with the Python agent (grant Full Disk Access) until the Swift app exists.

Reading file contents was dropped on 2026-09-24 and re-opened on 2026-09-25 for the opt-in context approach, renaming, tagging and dedupe, local only. The PDFKit/Vision "Kanso-see" prototype from the first BENCHMARKS.md table is the starting point.
