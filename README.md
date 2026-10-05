<p align="center"><img src="docs/assets/icon.png" width="128" alt="Kanso"></p>

# tidy

Keeps `~/Downloads`, `~/Desktop` and `~/Documents` sorted without you thinking about it.

- Files are sorted by **type**, using the extension (and the screenshot flag), into `My Shelves/<Type>`. Each type folder gets a Finder icon with its emoji.
- New arrivals also show up in `Recents` as symlinks for a week, so you can still find what you just downloaded.
- `Manual Shelves` is yours: tidy never moves anything in or out of it.
- **Models only run for unknown types.** Apple Intelligence (the on-device Foundation Model) picks a type or creates a new one with its own emoji (for example 🔑 Certificates for `.p12`). The choice is remembered for that extension, so the next file like it skips the model. **[von](https://github.com/wfzyx/von)** is the fallback and only picks existing types. Anything still unclear goes to `Unsorted`.
- Models see only **metadata**: the file name, type, download URL and screenshot flag. File contents are never opened, and nothing leaves your Mac.

```text
~/Downloads/
  My Shelves/     📄 Documents  📊 Reports  📽️ Presentations  📚 Ebooks  🖼️ Images  📸 Screenshots
                  🎬 Videos  🎵 Audio  🎨 Design  💻 Code  ⚙️ Automations  🗄️ Databases  📐 Diagrams  🧾 JSON
                  📦 Archives  📲 Apps  🧊 3D Models  🔑 Keys  📅 Calendars  👤 Contacts  🧲 Torrents
                  🔤 Fonts  ❓ Unsorted  (+ types Apple Intelligence created)
  Manual Shelves/ yours, never touched
  Recents/        symlinks to what was sorted in the last `recent_days`
```

`recents` in the config picks the mode:
- `"links"` (the default): sort now and leave a symlink in Recents.
- `"hold"`: the file itself waits in Recents for `recent_days`, then gets sorted.
- `"off"`: no Recents at all.

## Kanso app

<p align="center"><img src="docs/assets/overview.png" width="720" alt="Overview"></p>
<p align="center"><img src="docs/assets/sorting.png" width="720" alt="Sorting"></p>
<p align="center">
  <img src="docs/assets/island-processing.png" width="300" alt="The island reading a file">
  <img src="docs/assets/island-renamed.png" width="300" alt="The island after a rename">
</p>
<p align="center">
  <img src="docs/assets/island-recent.png" width="300" alt="The island's recent activity">
  <img src="docs/assets/quick-settings.png" width="220" alt="Quick settings">
</p>

(Screenshots use mock data.)

## Install

```bash
uv sync
uv run tidy run --all --dry-run   # preview what it would do with what's already there
uv run tidy install               # start the background agent
```

Then open **System Settings → Privacy & Security → Full Disk Access** and add the Python path that `install` prints. Without it, macOS blocks background access to Desktop, Documents and Downloads.

`install` only affects items that arrive after it runs. Run `tidy run --all` to clean up what's already there.

### Menu bar app

```bash
menubar/build.sh    # builds, installs to ~/Applications/Tidy.app and launches it
```

From the menu bar you can turn auto-sort on or off, add or remove folders to sort, sort new files now, sort everything, undo the last sort, edit rules, and set up folder access. The app only calls the `tidy` CLI in this folder. Sorting happens in the background agent, even when the app is closed.

| command | |
|---|---|
| `tidy run [--all] [--dry-run]` | sort now |
| `tidy undo` | revert the last run and remove its Recents links; restored items get the `Keep` tag, so tidy leaves them alone |
| `tidy status` | agent state, and whether Apple Intelligence is in use |
| `tidy config` | open `~/.config/tidy/config.toml` |
| `tidy uninstall` | remove the agent (config and journal stay) |
| `tidy roots DIR...` | set the folders to sort |

A launchd agent (`WatchPaths`) runs tidy when a watched folder changes, and hourly to expire Recents. Nothing stays resident, and models load only when a file has an unknown type. The log is at `~/Library/Logs/tidy.log`.

## Apple Intelligence

Needs macOS 26, Apple Intelligence turned on, and **Xcode 26** to build Apple's `apple-fm-sdk` Python bindings:

```bash
uv sync --extra apple              # add --group bench to keep the benchmark models installed
```

Without it, von picks an existing type for unknown files, from the same metadata. See `BENCHMARKS.md` for how each approach scores on real folders.

## Your own rules

These go in `config.toml`. They're checked from the top, and the first match wins:

```toml
[[rules]]
glob = "*rechnung*"                    # file name pattern
dest = "Documents/Invoices"             # inside My Shelves; absolute paths work too
tags = ["Invoice"]

[[rules]]
from = "github.com"                    # text in the download URL
dest = "~/Developer/Downloads"

[[rules]]
when = "a university lecture, assignment or exam"   # plain English, judged by von
dest = "Documents/University"
tags = ["Uni"]
```

Types are config too: `[categories.<Type>]` with `emoji`, `description` and `match` (extensions). Models read the descriptions when they classify unknown types. Types created by Apple Intelligence are kept in `~/.config/tidy/learned.json`. You can edit or delete that file to reset them.

`[context]` holds the old content-based subfolders (Finance, Work, Personal…). Nothing uses it yet; it's reserved for AI tagging, renaming and context-aware sorting.

Default rules send JSON exports of automation workflows to Automations when they were downloaded from make.com, zapier.com or an n8n host, and do the same for files named `*blueprint*.json`. These tools have no file extension of their own.

## Safety

- Only the top level of each root is touched. tidy never looks inside subfolders, including `My Shelves`, `Manual Shelves` and `Recents`.
- Folders stay where they are unless you set `sort_folders = true`. Folders containing `.git` never move. App and document bundles (`.app`, `.key`…) count as files.
- To exclude one file, right-click it in Finder → **Don't Sort with Tidy** (**Allow Tidy to Sort** reverses it). This sets the `Keep` Finder tag. In some macOS versions these items are under Quick Actions or Services.
- It skips hidden files, partial downloads (`.crdownload`, `.download`, `.part`), Office lock files, and anything still changing.
- Name clashes become `name 2.ext`. Nothing is overwritten.
- Every move is journaled (`~/.config/tidy/journal.jsonl`) before tidy moves on.
- **iCloud Drive:** add `~/Library/Mobile Documents/com~apple~CloudDocs` to `roots`. File contents are never read, so files that aren't downloaded stay that way.

## Tests

```bash
uv run python -m unittest discover tests -v
uv run python bench.py >> BENCHMARKS.md    # compare approaches on your real folders (dry run)
```
