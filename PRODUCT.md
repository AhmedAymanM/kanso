# Kanso: product decisions

Decided in the grilling session on 2026-09-25. This file is the source of truth for *what* we're building and why; `AGENTS.md` covers *how the code works*, and `design-brief.md` is the brief for design tools.

## 1. Identity

- **Name: Kanso** (簡素): the Zen principle of simplicity by removing clutter.
  - Rejected: names already used by other Mac apps, and the runners-up Tidsworth, Sortbird, Kempt and Sheen.
  - Before launch: register `kanso.app` (it looked unregistered) and search USPTO and EUIPO trademarks.
  - The Python CLI is `kanso` (renamed 2026-10-05). Its settings live in `~/.config/kanso`.
- **Positioning: calm and trustworthy, with open source as the proof.** We don't compete on AI cleverness.
  - Pitch: *"Kanso quietly keeps your Mac simple. Your files never leave your Mac, Kanso only reads inside them for the features you turn on, and you can read every line of code."*
- **Standing principles** (apply to every feature):
  1. **Adopt the user's structure** instead of imposing one.
  2. **Learn from their habits.** Every correction is feedback.
  3. **Be seamless and easy:** calm, no setup required, rarely asked, never surprised.

  Research backing: people find files by browsing their own folders more than by searching, and they fail to find files about 5× more often in folders someone else organized (Bergman & Whittaker). Desktop piles act as reminders (Malone 1983; Barreau & Nardi).
- **Who it's for** (goals grilling, 2026-11-19): the owner first, then power and technical Mac users who want tools to manage and structure their files.
- **Vision:** Kanso grows into the one tool a Mac user reaches for for every file job: sorting, automations, downloads, renaming, a shelf, and then actions such as optimizing an image or turning Markdown into a PDF.
- **Wedge (v1):** trustworthy automatic sorting: the container, undo, and code anyone can read. The expansion order is sorting → the Tray → file actions from the Tray and the island.
- **Parity is not a goal.** Kanso ships what is distinct, not a checklist matched against competitors.
- **Renaming is supporting, not the pitch.** macOS 27's Finder suggests file names on demand (English only, no public API). Kanso's renaming is automatic and consistent, with no clicking. Check after every WWDC whether macOS starts organizing files automatically.

## 2. Business

- **Public, open source, free, with donations, for good.** Support comes through Buy Me a Coffee. There is no paid tier.
- **License: MIT** (`LICENSE`, since the repo went public). MIT already allows any other build, an App Store one included, so no CLA is needed.
- **Distribution without a paid Apple account** (decided 2026-11-19; the Developer Program fee waiver doesn't cover individuals):
  - Signed with a **self-signed code-signing certificate** (`build.sh` `SIGN_ID`). A stable identity keeps folder permissions across updates, which ad-hoc signing doesn't. Not notarized.
  - **GitHub Releases** plus the owner's own **Homebrew tap**. homebrew/cask doesn't take apps that fail Gatekeeper, and Homebrew 5 removed `--no-quarantine`.
  - A first-launch guide walks through **System Settings → Privacy & Security → Open Anyway**.
  - Updates use the Sparkle updater framework with **EdDSA-signed** updates from a pinned host. User-facing copy says "updates" and never names the framework.
  - The Mac App Store and notarization come back only if a paid account ever happens.
  - Built sandbox-compatible from day one: security-scoped folder bookmarks, no Full Disk Access, no private APIs.

## 3. Platform and technology

- **Apple silicon only, macOS 14 Sonoma or later.**
  - Apple Intelligence (Foundation Models) is used on macOS 26+ via `if #available`.
  - Without Apple Intelligence (macOS 14–15, or turned off), everything with a known extension still works, and unknown types go to ❓ Unsorted.
  - Liquid Glass exists only on 26, so the UI needs a classic fallback.
- **Swift for the product, Python for the lab.** Port the `sorter` and `brain` behavior to a native Swift app. Python stays for `bench.py` and for converting and evaluating models.
- **Models:**
  - **Local first, for everything.** Cloud stays a principle only: strictly opt-in, the **last resort**, and it must say what it sends. Nothing cloud (BYOK or hosted) is on the roadmap.
  - **Generative models run locally:** Apple's Foundation Models, or open models that earned their place in the benchmark. (This rule was Apple-only until 2026-09-25.)
  - **Classification needs confidence:** a generated answer has no confidence score (Apple FM never said "unsure" in the bench). Any generative classifier must score the options by probability, so earned trust keeps working.
  - **v1 model:** Apple Intelligence (26+) only. **Kanso Local is not part of the v1 promise**: no model exists yet, so the picker shows it as "Not available yet" until one earns its place in `bench.py`.
  - **No von.** The von classifier (local ModernBERT) is no longer part of the product (decided 2026-10-05). Unknown types go to Apple Intelligence; when it can't answer, the file goes to ❓ Unsorted.
  - Small local LLMs (≤2 GB) get benchmarked later; a winner becomes "Kanso Local+".
- **Docs state only current facts:** the README and the product docs describe what Kanso does today. Retired components, dropped ideas and stale references are deleted, not kept as history (git has the history).

## 4. Folders

Each watched folder gets a container, so Kanso never mixes with the user's own folders:

| Folder | Emoji | Role |
|---|---|---|
| **My Shelves** | ✨ | where Kanso sorts files |
| **Manual Shelves** | 🏠 | yours; Kanso never moves anything in or out (it may *read* it to find duplicates) |
| **Recents** | 🆕 | symlinks to everything sorted in the last 7 days (the mode is configurable: links, hold or off) |

- **No empty folders** (decided 2026-09-29): shelves and Kanso's folders are created only at the moment something goes into them, never ahead of time "just in case". The Duplicates shelf stays; it appears with the first held copy. **Exception: Manual Shelves** is created automatically in a watched folder the first time Kanso actually sorts something there (its first cleanup), together with My Shelves, so the user sees their own never-touched space next to Kanso's. A watched folder Kanso has never sorted anything in gets nothing. **Once created, a folder stays**: a shelf that becomes empty again (undo, Keep both, the user moving files out) is kept, so folders don't flicker in and out of existence under the user.
- Each shelf folder gets a Finder icon with its emoji.
- Kanso **never moves the user's existing folders** on first run.
- Rejected: "Library" (clashes with `~/Library`), and "Shelves / My Shelves" (the pair was ambiguous).
- **v1 uses the same rules for every root,** the Desktop included. Per-folder profiles come later (for example the Desktop in hold mode with a longer grace period, where touching a file resets its timer).

## 5. Two sorting approaches

These are equal, and the user picks one during onboarding. They aren't "simple vs advanced".

- **By kind:** shelves by file type (📄 Documents, 📊 Reports, 🖼️ Images, 💻 Code, ⚙️ Automations, 🗄️ Databases…).
  - **Metadata only;** Kanso never opens the file. Deterministic and always automatic.
  - Unknown types go to Apple Intelligence or the local model, which picks a shelf or creates a new one (with a name, emoji and description) and remembers it for that extension.
- **By purpose:** shelves by what a file is for (Work, Personal, Expenses…). It reads contents, **on the Mac only**. It comes **after v1**.
  - **Where the shelves come from** (options C + D): learn the user's existing folder *names* and reuse their words, and seed with a starter set of common patterns. Later, suggest new shelves from recurring clusters. Kanso proposes, the user decides.
  - **Flat in v1;** the user's existing nesting is mirrored, never invented.
- **Switching approaches** affects new files only, unless the user runs "Re-sort everything" (which can be undone).

## 6. Trust mechanics

- **Earned trust, per shelf:**
  - By kind is always automatic.
  - By purpose moves automatically only when the model is confident *and* the shelf hasn't been corrected recently.
  - When it's unsure, the file waits in Recents and a one-click "Where should this go?" appears. Each answer teaches Kanso, and each correction lowers that shelf's trust.
- **The first "Sort everything" is always a preview:** the plan as a list, where the user unchecks items and then applies.
- **Everything can be undone.** Kanso **never deletes** and never empties the Trash. It moves a file to the Trash on its own only when the file is **provably spent** (an installer whose app is installed, see Smart Installer) or when it's a carrier under a timer the user turned on (see Cleanup). Everything else goes to the Trash only when the user presses ⌘⌫. Every trash is journaled and one ⌘Z away. See `docs/adr/0002-trash-only-provably-spent-files.md`.
- **AI may only make removal more careful.** Wherever a model helps decide what leaves (the v1.1 review, the v1.2 uninstaller), Kanso's own code finds the candidates and a fixed guard wins. The model labels each item ("Slack's message cache, rebuilt on next launch") and may move it *down* to Review or Keep, never up. It sees metadata only. Without Apple Intelligence the feature still works, with fewer explanations.
- **Content-reading limits** (for By purpose, renaming and tagging):
  - Read a little: the first 1–2 pages or about 2,000 characters, via PDFKit/text and Vision OCR. Audio, video, archives, apps and code are never read.
  - **Keep nothing:** extracted text is used for the decision and discarded. Only the decision goes in the journal.
  - **Never read** 🔑 Keys, password vaults, keychains, Manual Shelves, or iCloud placeholders (those fall back to the name).
  - Sensitive-looking text (IDs, cards) never goes to cloud AI, even with cloud on.
  - The activity log shows what each decision used ("from name" or "from contents, page 1").
- **Network:**
  - **No analytics.** The only network calls are update checks, model downloads the user chose, and cloud AI if opted in.
  - Crash reports are opt-in, asked once after a crash, and stripped of paths and names.
  - Privacy settings list every possible network call.
  - Feedback goes through a prefilled GitHub issue or email that the user sees before sending.
  - **Local stats** are shown only to the user ("312 files sorted · 41 renamed · 1.2 GB of duplicates this month").

## 7. Features in v1

**v1 = By kind + renaming + tagging + duplicates + Smart Installer + Cleanup + the Tray**, on macOS 14+. Each feature has its own toggle and states whether it reads contents.

### Renaming
- **Automatic, for new downloads with meaningless names only:** scanner, camera or download patterns (`Scan_0012`, `IMG_1615`, `download (3)`, `document`, `untitled`), bare numbers, UUIDs or timestamps.
  - This check is deterministic, with no model.
  - Human-written names are left alone. Normalizing them is opt-in through user rules.
- **Template names from non-generative on-device parts:** document kind (classifier) + organization (`NaturalLanguage` NER) + date (`NSDataDetector`), for example `Invoice-Vattenfall-2026-03.pdf`. Apple FM can refine them on 26+.
- **The original name is kept** (in an xattr or Finder comment, and in the journal), so Spotlight still finds it and undo restores it.
- **Name language:** match the language already used in that shelf. Otherwise use the system language if supported, falling back to English. The config can override it.
- **Notices:**
  - A single rename shows a toast with Undo.
  - Mass renames show a toast ("42 files can be renamed. Review?") that opens a review window.

### Tagging (Finder tags)
- At most **4 tags per file**, usually 3 or fewer.

| Slot | Values | Color | When |
|---|---|---|---|
| Dimensions (1–2) | kind (`Invoice`, `Contract`, `Ticket`…) + organization (`Vattenfall`) | none | **v1** |
| Status (0–1), from GTD | `To do`, `Waiting`; Reference = no tag | none | with By purpose |
| Reminder (0–1), from a date in the file | `Due later` 🟢 >7 days · `Due soon` 🟡 ≤7 · `Due now` 🔴 ≤1 day or overdue; re-colored as the date approaches | traffic light | with By purpose |

- **Red is only for real deadlines,** because of the mere-urgency effect (Zhu, Yang & Hsee 2018).
- **Words carry the meaning,** for color-blind users.
- **Every reminder has a toast naming the action** ("Sign Lease by Oct 3"). Reminders work only when they name both the cue and the action.
- **The user's existing tags come first:** their names and colors are read at onboarding and mapped to Kanso's slots, and Kanso learns from their re-tagging.

### Duplicates
- Detected by **size, then hash.** No model.
- **Keep one copy:** the oldest, the best-named, or the one already on a shelf.
- **Extra copies of new downloads go to a 🪞 `Duplicates` shelf,** with a toast offering Undo or Move to Trash.
- The Duplicates shelf shows the space it holds and has a user-pressed **"Move all to Trash"**.
- Duplicates are never trashed on Kanso's own judgment (identical bytes don't prove the user doesn't want both copies), only by ⌘⌫ or by the opt-in Duplicates settings (straight to Trash, or auto-trash after N days).

### Smart Installer
*Decided 2026-11-20; replaces Smart Eject.* Installing happens when the user opens the download, not after Kanso waits for them to drag the app.
- **Opening a disk image with exactly one app** shows on the island: "Install Figma → Applications", with **Trash the download** ticked. Both answers are remembered, so after the first time it's one step.
- Kanso copies the app, checks its signature, ejects the image, moves the `.dmg` to the Trash (journaled, ⌘Z) and **opens the app from `/Applications`** (not from a translocated copy). The island says what happened, and which step failed if one did ("Installed, but the disk image couldn't be ejected; the download was kept").
- **Already installed:** Replace when the new version is newer and the app isn't running, otherwise Skip.
- **A zip holding exactly one `.app`** gets the same offer.
- **Fallback:** an image with a `.pkg`, several items or a layout Kanso can't read keeps the old behavior: when the app lands in `/Applications` (same bundle ID) or the `.pkg` finishes, Kanso ejects the volume and trashes the installer. An image from which nothing was installed is never trashed.
- Homebrew's cached installers are ignored.
- **The same "done with it" offer for other carriers:** when an archive's extracted folder appears next to it, the island offers **Trash the zip**; when a `.torrent` has been opened by a torrent app, it offers **Trash it**. Unanswered, the Cleanup timers apply.

### Cleanup (Downloads)
*Decided 2026-11-20.* Downloads is an inbox: everything there is in transit and leaves by one of **two exits**.
- **Spent → Trash, automatically only for carriers**: files whose job ends once used. Off by default; offered once as a Needs-you card after a week of sorting, with real numbers ("4 installers and 6 archives you've finished with · 3.4 GB").
  - Installers: Smart Installer; one never used leaves after 14 days unused.
  - Archives: 3 days after the extracted sibling appears (its top-level names match the archive's listing), otherwise 30 days unused.
  - Screenshots: 7 days unused, by the screenshot flag, wherever they are.
  - Torrents: 7 days.
  - Duplicates: their own setting (see Duplicates).
- **Content is never on a timer** (documents, images, media, code, keys). It leaves only by ⌘⌫. The monthly "Still need these?" review comes in v1.1.
- **Kept → filed.** A file showing it's kept gets a **Move to Documents** suggestion: it moves to `~/Documents/My Shelves/<Type>`, journaled and undoable. In v1 Kanso suggests and never moves it on its own.
- **Signs a file is kept** take it off every timer: any Finder tag (Keep included), a rename by the user, a move out of My Shelves, or opening it twice. Manual Shelves, Keys and files outside `~/Downloads` (screenshots excepted) never expire.
- **"Unused" is measured from** the latest of: when Kanso sorted it, the `com.apple.lastuseddate#PS` xattr, and the modification date. **Never the access time**, which Kanso's own reads move and real opens often don't. The same clock fixes duplicate expiry, which uses access time today.
- **Calm notices:** one weekly island card ("Sunday: 9 installers and archives leave · 2.1 GB · Review / Keep all"); Keep all tags them Keep. After a cleanup, one line: "Moved 9 to Trash · ⌘Z". Each cleanup is one journaled run.
- If Finder empties the Trash after 30 days, the Cleanup page says "Undo works for 30 days".

### The Tray
*Decided 2026-11-19; design in `docs/design/final-direction.md`, which gets a UX redesign in Pencil before it's built.* A temporary holding place on the island for things the user is carrying until they decide where they go.
- **Holds files, links and snippets.** Organize files them like any sort: files by type; links as `.webloc` on a new 🔗 Links shelf; snippets as `.txt`/`.md` on a new 📝 Notes shelf.
- **Link titles are not fetched** by default; turning it on applies the SSRF rules in `docs/design/final-direction.md`.
- **Snippets** are stored mode 0600, excluded from backup and Spotlight, wiped by "Forget everything", and never sent to a model without a user action.
- **Refused in v1:** file promises (images dragged from a browser, Mail attachments): "Save it first."
- The drop target follows the island skin and position.

### The island and shortcuts
*Revised in the UI/UX grilling on 2026-09-28; terms are defined in `CONTEXT.md`.*
- **Plain sorts are silent.** A sort is what the user asked for, so it shows nothing in the moment; it appears in the popover's Done list and in Recents. Only renames, duplicates and needs-you items get a notice, which keeps notices rare enough to be read.
- **The island replaces the toast.** Notices appear in a capsule (or, in the notch style, grow out of the notch, Dynamic-Island style) and never steal focus. It always appears on the **active screen**, the one with the focused menu bar, even if the notch is on another display. In full-screen apps notices collect quietly with the menu bar dot, as under Focus.
- **The notice is the object changing state** (Linear's status control): the island's compact state is one icon and one line. The line swaps; the icon morphs about 300 ms to show what happened (fill, color crossfade, flip, check). No separate "Kanso did X" message. Each state has its own shape, so color is never the only signal.
- **Rename:** a subtle border beam runs around the island while the old name sweeps into the new one (ASCII-sweep style, sage glyphs, about 0.8 s, no tearing or aberration). With Reduce Motion the new name simply appears.
- **The island opens when the work is done,** playing the short morph as it opens. It opens early (a filling pie) only when the work takes over about 2 s, such as OCR on a big scan, so a pause is never a mystery.
- **Several notices at once become one island that counts up** ("3 renamed") as each finishes; expanding it shows the list.
- **Life cycle** (proposed by the owner, 2026-09-29): an action happens → a minimal, fluid notice appears on the compact island → it expands after a **300 ms dwell**, a **click**, or **one global island shortcut** (which replaces the separate undo / trash / menu shortcuts) → the expanded island shows the details and actions, operable by click or by keys → a subtle Liquid Glass **ask field** at the bottom takes natural language, answered on device by Apple's Foundation Models.
- **The island shortcut is ⌥⌘K** (K for Kanso; changeable in General). It replaces ⌃⌥⌘Z, ⌃⌥⌘⌫ and ⌃⌥⌘K. The HIG reserves ⌃⌘Space (Special Characters) and ⌥⌘Space (Spotlight); ⌃⌥Space switches input sources and ⌥Space belongs to Alfred and Raycast. While a notice is showing, ⌥⌘K opens *that* notice with its primary action selected, so ⌥⌘K then Return undoes a surprise. The compact island shows the ⌥⌘K hint for the first few days only.
- **Keys in the expanded island** (no action is a bare letter, because letters go to the ask field): Return runs the selected action · Esc collapses, then hides · ← → page notices · ↑ ↓ move the selection · Space opens Quick Look · ⌘Z undoes the notice · ⌘⌫ moves the duplicate to the Trash · ⌘R reveals in Finder · ⌘O opens · Tab or any letter focuses the ask field. Plain ⌫ never trashes.
- **Keys in the ask field:** Return sends · ↑ recalls the last question · ⌫ and all its combinations edit text normally (⌘⌫ deletes the line, not a file; it trashes only when the field isn't focused) · Esc leaves the field *without* clearing it: the field unfocuses, its text dims slightly, and the actions are live again. After the field is emptied by editing, Return stays inert for 1 s so a cleared question can't fire an action by accident.
- **The ask field** runs on Foundation Models (macOS 26+ with Apple Intelligence on; hidden otherwise). Its context is the notice's files: their metadata, plus the first page or about 2,000 characters when a question needs contents, read on this Mac and not kept, never from Keys, vaults or Manual Shelves. Questions are answered immediately. **Every model-proposed action waits for Return:** it shows as a preview line ("Move 3 files → 🎓 Uni · ↩ Do it"), then lands in Activity with Undo like any other action. **Move to Trash from the ask field** is possible only under the rules in `docs/adr/0001-ask-field-destructive-actions.md` (closed ID set, Kanso-written confirmation, ⌘⌫ to confirm, 20-item cap, and no trash tool in any request that read file contents; the user gets a plain button instead).
- **Three surfaces, three jobs:** the **menu bar icon opens the quick settings popover** (configuring Kanso: Auto-Sort, tracked folders and their switches, the Renaming / Tagging / Duplicates tiles, model status, Settings and Quit), the **island** holds everything about what Kanso is doing (notices, the overview state with Needs you and done items, the ask field), and the **main window** holds deep settings, history and **stats** (the tallies move from the popover to Overview and Insights). The popover keeps one row that links to the island ("2 need you · Show Kanso ⌥⌘K"), which also teaches the shortcut; on notch Macs, clicking the notch also opens the island.
- **The capsule is the default** (decided 2026-11-19): many apps already use the notch, and Kanso shouldn't compete with them. General has **Style: Capsule (default) / Notch** and **Position: Top / Bottom**. Top drops the capsule from just below the menu bar; Bottom sits above the Dock and moves down when the Dock auto-hides. The notch style uses the notch on notch screens and the capsule elsewhere. Style switches happen only between notices, never mid-animation. **Kanso yields to other notch apps** (in the notch style): it has no window at rest, so hovering the notch reaches the other app. If another notch app's panel covers the spot where Kanso's capsule would appear, Kanso holds its notice until that panel collapses; if it expands over a showing capsule, Kanso collapses to compact and reappears afterwards, never fighting for the front (detected from the window list, no permissions). While such an app runs, the notch style falls back to the capsule, and the setting notes: "Another app is using the notch, so Kanso shows the capsule."
- **Turning Sorting off asks for how long:** 15 minutes · 1 hour · until tomorrow · until I turn it on. Timed choices turn Sorting back on by themselves. If Sorting has been off for 24 hours, the island says so **once** ("Sorting has been off since yesterday · ↩ Turn on") and never again for that off period. There is no separate Pause setting.
- **The island's overview state** (⌥⌘K, a notch click or the popover's "Show Kanso" row, with no notice showing) is only about now; stats live in the Overview window. Top to bottom: **Needs you** (one tinted row per pending item with its morph icon; ↑ ↓ select, Return runs the row's main action; 4 or more shows 3 and "+ N more · Activity"), then **Recently** (the last 3 things Kanso did, ⌘Z undoes the selected one), then two small icons: **Open Kanso** (the window) and a **gear that always opens the Settings window** (not Quick settings). **No Sort Now button** on the island. With nothing pending and nothing in the last 24 hours it shows one calm line ("All quiet · 312 files kept in order this month") and no empty sections. The ask field joins the bottom in v1.1.
- **Two skins, one island:** the **notch** skin is **black** and grows out of the notch with concave "ear" corners, its bottom edge melting into glass over the last 12 pt only, with the esc row on solid black; the expanded island is black with Liquid Glass controls inside. The **capsule** skin (the default, and every screen without a notch) has **nothing at rest**; a notice drops a **Liquid Glass capsule** (`.ultraThinMaterial` on 14–15) from just below the menu bar at the top center, with all corners rounded and a small gap, so it floats instead of imitating hardware. Identity comes from shape and motion, not color.
- **Motion:** move toward Liquid Glass, fluid spring animations and micro-interactions throughout. A keyboard-opened island animates fast (a spring settling in about 200–250 ms, no delay); the dwell and click paths can use the fuller expansion.
- **One global shortcut, ⌥⌘K** (above); the old ⌃⌥⌘Z / ⌃⌥⌘⌫ chords are gone. Older actions go through the Activity list. **A duplicate notice's primary action is Undo**; Move to Trash is only ever ⌘⌫, so ⌥⌘K then Return can never trash.
- **Under Focus and in full-screen apps,** notices collect silently and the menu bar icon shows a dot.
- **Review windows** (mass renames, the Sort everything preview) are real windows where plain ⌘Z and ⌘⌫ work.

*These decisions were validated against the design skills in `docs/design-validation-2026-09-29.md`; its resolutions (focus rings, reduced motion, pastels only on surfaces, no glass on glass or on content, VoiceOver announcements, spring values) are part of the design. The designer's brief is `docs/design-handoff-prompt.md`.*

### Settings structure (decided 2026-09-29)
- **The problem is dense screens, not the number of menu items.** Each screen shows only what the user actually changes; everything else gets a good default and no control. Hero illustrations, "how it works" placeholders and per-feature Recent lists go; Activity already covers history, and onboarding plus the island teach what features do.
- **One App window (decided 2026-09-30, replaces the separate Kanso and Settings windows):** a sidebar with Overview, Activity · Sorting, Renaming, Duplicates, Tagging, Smart Installer, Cleanup · General, Privacy & AI. No toolbar navigation, only the page title. ⌘, and every Settings button open General. **Overview** has no Sort Now: a statement, **Needs you** (only when something is pending), **Since you started** (four pinned cards: Sorted today, Renamed, Duplicates found, Undo rate) and **Highlights** (two cards: monthly sorting, shelves by size). Each feature page is a showcase banner, the feature's switch card, then its options; a switched-off feature dims its options.
- **Rules** live inline on the Sorting page: only the user's own sorting rules (add, edit inline, switch off, remove). Kanso's built-in extension table and its default rules (Make, n8n, Zapier exports) are not shown; they just work. There is no Types screen.
- **Unknown files have no settings:** Kanso always asks the model; if the model creates a fitting new type it gets its own shelf (suggesting new types is always on), and if there's no meaningful answer the file goes to ❓ Unsorted.
- **Corrections teach types:** a learned type is fixed by moving the file. Moving it to another shelf (in Finder, or Activity's "Move to another shelf…") updates the learned mapping, so the next file with that extension follows. Learned types are not listed anywhere; Activity's "How Kanso decided" explains any single file.
- **Features** each have a page (see above) with a switch, one sentence and a reads-contents badge. **Auto-Sort becomes the "Sorting" feature**, and the approach, watched folders and Recents are configured inside the Sorting row.
- **What each Features row keeps** (everything else: a default, no control):
  - **Sorting**: a plain on/off switch like every other row (no separate "Auto-Sort" concept). Expanded: watched folders (+ Add), Recents (Shortcuts / Hold / Off), wait before sorting, approach (By kind · By purpose *soon*).
  - **Renaming**: on/off. Expanded: name format (template, separator, date format) and "ask before renaming more than 10 at once". **Name language is removed** (match the shelf, then system, then English, always).
  - **Tagging**: on/off only.
  - **Duplicates**: on/off. Expanded: where extra copies go (**Duplicates shelf** by default, or Trash), auto-trash held copies after N days (**off** by default; 30 days preset when turned on; opening a held copy resets its timer, so only untouched copies expire), space held with **Move all to Trash…**.
  - **Smart Installer**: on/off. Expanded: Trash the download after installing (on), open the app after installing (on).
  - **Cleanup**: on/off (off). Expanded: one row per carrier with its days, and "Suggest moving kept files to Documents".
- **Activity detail:** no Timeline (its one useful fact, when it happened, joins the metadata line). A visual block appears only where the picture explains the decision (rename: old name struck through over the new one, and the page preview; duplicate: the two copies side by side; batch: shelf bars); a plain sort or a waiting item has none. "How Kanso decided" stays as the heart of the screen. From 6 blocks to 3–4.
- **Insights style references** (owner, 2026-09-29): Tomáš Sebastián's "Analytics Micro-interaction" (layers.to; one chart per tinted card, big number with a caption and delta pill, hover scrubbing with a snapping pill tooltip, count-up and rolling digits, bars growing in a stagger, round icon buttons in the card header) and a Dribbble "Insight" card set (large serif numerals on flat tinted cards, a delta top-right, a short label).
- **Pastel theme** (decided 2026-09-29): every color keeps its meaning and becomes a pair, a pastel for surfaces, chips and button fills plus a deep ink of the same family for text, icons and lines. Starting values (to be checked for contrast): Kanso/sorted mint `#CFE8D8` / `#2E5A4B` · rename periwinkle `#D9E0FA` / `#3C509A` · duplicate butter `#F7E4B5` / `#7E531B` · rule lavender `#E5DCF7` / `#5A4687` · where aqua `#D0ECEC` / `#1E666B` · neutral stone `#ECEAE5` / `#48484D`. **Mint is the brand accent** (switches, selection, links). No white-text buttons: primary buttons are pastel with ink text. Dark mode uses the ink hue at about 25% for surfaces and a lightened pastel for text. Cards are tinted by what they measure. The island stays black or glass, with pastels only inside it. This supersedes the sage tokens in `kanso-designs/DESIGN_SYSTEM.md`.
- **General** (7 controls): Open at login · Island style: Capsule / Notch · Island position: Top / Bottom (capsule only) · Show the ⌥⌘K hint (turns itself off after a few days) · During Focus and full-screen: collect notices quietly · Island shortcut ⌥⌘K (Change) · Menu bar icon Show/Hide (when hidden, Settings stays reachable through the island's gear).
- **Privacy & AI** (mostly statements): model status (Apple Intelligence; Kanso Local when it exists) · what reads inside files, shown as facts (the switches live in Features) · every network call (update checks with a switch, model download on request, cloud AI "not available") · crash reports (off) · one "never read" sentence (Keys, vaults, Manual Shelves, iCloud placeholders) · About (version, GitHub, Buy Me a Coffee, Send feedback).
- **Removed, now fixed behavior:** "only while plugged in" (content reading always pauses on battery below 20%), "low priority" (always background priority), "show toasts" (no toasts exist) and the three old shortcuts (⌥⌘K replaces them).
- All screens use the island's design language: Liquid Glass, the same components, springs and keycaps.

### Onboarding (decided 2026-09-29)
Three steps, learning by doing; approach, feature switches and details live in Settings (defaults: Sorting, Renaming, Duplicates and Smart Installer on; Tagging and Cleanup off). The first launch of the self-signed build starts with the Open Anyway guide.
1. **Folders.** "Kanso needs to open three folders." An explanation (top level only, shelves inside the same folder, nothing leaves the Mac, macOS asks once per folder), the three folders pre-checked (unchecking narrows the request), and **one button, Continue**, which triggers macOS's prompt per checked folder (in the sandboxed build, the folder picker preselected on each). Per the HIG: no "Allow" wording and no close/cancel before the system prompt. Folder access is Kanso's only permission (Carbon hot keys need no Accessibility; no Full Disk Access; the island replaces notifications).
   - A declined folder is skipped silently and shows in the Sorting row as "not allowed" with **Open Privacy Settings**; it turns normal once access is detected. Nothing on the island.
   - If every folder is declined, onboarding ends on one calm screen, "Kanso needs at least one folder to work", with Open Privacy Settings as its only button.
2. **The island.** A live demo inside the window with a pretend file (real files untouched), shown in the capsule style: the rename sweep and beam, then "press ⌥⌘K", which expands the demo island. Never blocking: a Skip link, and after 10 s it expands on its own ("or click the island").
3. **Existing files.** Only sort new files / Preview a cleanup.
- **Conditional:** if Apple Intelligence is off or unavailable, a short step before 3 offers turning it on (without it, unknown types go to ❓ Unsorted).

## 8. Roadmap

| Release | Contents |
|---|---|
| **v1** (launch **Tuesday 2027-01-26**) | Swift app, By kind, renaming, dimension tags, duplicates, the island (capsule default, Top/Bottom), quick settings popover, **Smart Installer**, **Cleanup** (carrier timers, kept signals, Move to Documents suggestions), **the Tray** (files, links, snippets), preview for Sort everything, onboarding, settings, local stats, Apple Intelligence. Shipping basics: self-signed build, EdDSA updates from a pinned host, the owner's Homebrew tap, the Open Anyway guide |
| **v1.1** | **Integrations**: App Intents (Shortcuts), Raycast and Alfred, all over one surface (App Intents plus `kanso-cli`). **The ask field** (macOS 26+, ADR 0001, an evaluation set before shipping). **Rename templates as a rule action** ("Also normalize my names", "Name future IKEA receipts this way"). **Cleanup's "Still need these?" review** (content unused for 60 days, AI labels and demotes, ⌘⌫ to trash, each file also offers File in Documents) |
| **v1.2** | **File actions** from the Tray and the island (optimize an image, Markdown → PDF, …). **Uninstall unused apps and clean their leftovers**: candidates by bundle ID and signing team, AI labels and demotes, a fixed guard, Trash only, ⌘⌫ only |
| **By purpose release** | after the post-launch review shows an undo rate under 5%: content reading within the limits above, adopting folder names, earned trust, status and reminder tags, per-folder profiles |
| **Later** | moving kept files to Documents automatically (once the suggestions are almost always accepted). Chat with your files (needs a stored index, so it gets its own opt-in). An optional **Finder replacement**, exploration only and not committed: a browser built on what only Kanso knows (why each file is where it is, undo), views asked for in plain English that become saved views, and views, columns and actions in a plain-text config that the AI writes and the user can edit; it starts only if v1.1 shows people search and browse through Kanso. Kanso Local, once a model earns it in `bench.py`. Mac App Store and notarization, only with a paid Apple account |

Already built (#16, #18): plain-English rules with preview and an explicit Save, the model picker (Apple Intelligence, or rules and extensions only), suggested shelves.

**The path to v1:** #17 (design polish, rebased, keeping the four tinted Overview tiles) lands first; the Tray (a revert of #20 after its Pencil redesign) and the Smart Installer UX follow. **UI freeze 2027-01-04**, dogfood **2027-01-05 → 2027-01-19**, launch **2027-01-26**.

## 9. Success criteria

- **Launch gate (dogfood):** the owner uses the Swift v1 on their real Downloads, Desktop and Documents for **two weeks**, with an **undo rate under 5%** measured from the journal (`kanso-cli stats --undo-rate`). The dogfood also proves Kanso's own claims:
  - **Network:** only update checks leave the Mac (watched with `nettop` or Little Snitch).
  - **Signing:** folder permissions survive an update of the self-signed build, and a clean user account installs from the tap.
  - **Cleanup:** zero false expiries. Every archive-extraction match is logged with both name lists and checked by hand; on day 7, the files due to expire are checked for any still in use. Trashes and their undos are counted apart from sorts, and **any undo of an automatic trash stops the feature**.
- **After launch** (no telemetry, so only signals we can observe):
  - **Retention:** about 60% of installs still checking for updates after 30 days (from the update-check logs).
  - **Trust:** an undo rate under 5% of automatic actions, from opt-in shared stats. If it's higher, fix it before building By purpose.
  - **Qualitative:** among the first 20 GitHub issues and discussions, mostly feature requests rather than "it moved my file wrongly".
  - **Value:** Buy Me a Coffee supporters, and shared "your month with Kanso" stats.
  - **Cleanup's v1.1 review:** what share of pre-ticked files people untick. Over 20% means start unticked, or narrow it to 90 days.
