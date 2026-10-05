# Kanso: product decisions

Decided in the grilling session on 2026-09-25. This file is the source of truth for *what* we're building and why; `AGENTS.md` covers *how the code works*, and `design-brief.md` is the brief for design tools.

## 1. Identity

- **Name: Kanso** (簡素): the Zen principle of simplicity by removing clutter.
  - Rejected: **Tidy** (the same-concept [Tidy](https://tidymacapp.com/) Mac app exists), **Sortie** (sounds like [Sorty](https://github.com/sorty-organizer/Sorty), an open-source AI organizer, and every domain is taken), and Tidsworth, Sortbird, Kempt and Sheen (runners-up).
  - Before launch: register `kanso.app` (it looked unregistered) and search USPTO and EUIPO trademarks.
  - The code and CLI are still called `tidy`; they get renamed in the Swift rewrite.
- **Positioning: calm and trustworthy, with open source as the proof.** We don't compete with Sparkle on AI cleverness.
  - Pitch: *"Kanso quietly keeps your Mac simple. Your files never leave your Mac, Kanso only reads inside them for the features you turn on, and you can read every line of code."*
- **Standing principles** (apply to every feature):
  1. **Adopt the user's structure** instead of imposing one.
  2. **Learn from their habits.** Every correction is feedback.
  3. **Be seamless and easy:** calm, no setup required, rarely asked, never surprised.

  Research backing: people find files by browsing their own folders more than by searching, and they fail to find files about 5× more often in folders someone else organized (Bergman & Whittaker). Desktop piles act as reminders (Malone 1983; Barreau & Nardi).

## 2. Business

- **Public, open source, free.** Support comes through Buy Me a Coffee. Later there's an optional **paid cloud tier**, for weak machines or better quality.
- **License: GPL-3.0** for the app, with a **CLA** so the owner can dual-license (for example the App Store build). The paid cloud service is **closed and server-side**. Set up the CLA (for example CLA Assistant) before accepting the first outside contribution.
- **Distribution:** direct download first (Developer ID, notarized, GitHub Releases, a Homebrew cask, the Sparkle *updater* framework), and the Mac App Store later. It's built sandbox-compatible from day one: security-scoped folder bookmarks, no Full Disk Access, no private APIs.

## 3. Platform and technology

- **Apple silicon only, macOS 14 Sonoma or later.**
  - Apple Intelligence (Foundation Models) is used on macOS 26+ via `if #available`.
  - macOS 14–15 use the downloadable local model.
  - Liquid Glass exists only on 26, so the UI needs a classic fallback.
- **Swift for the product, Python for the lab.** Port the `sorter` and `brain` behavior to a native Swift app. Python stays for `bench.py` and for converting and evaluating models.
- **Models:**
  - **Local first, for everything.** Cloud (BYOK or paid) is strictly opt-in and the **last resort**, and it must say what it sends.
  - **Generative models run locally:** Apple's Foundation Models, or open models that earned their place in the benchmark. (This rule was Apple-only until 2026-09-25.)
  - **Classification needs confidence:** a generated answer has no confidence score (Apple FM never said "unsure" in the bench). Any generative classifier must score the options by probability, so earned trust keeps working.
  - **v1 model picker:** Apple Intelligence (26+) and one downloadable **Kanso Local** model. The full picker (more local models, BYOK, cloud) comes in v2, Handy/FluidVoice-style.
  - **No von.** The von classifier (local ModernBERT) is no longer part of the product (decided 2026-10-05). Unknown types go to Apple Intelligence or Kanso Local; when neither can answer, the file goes to ❓ Unsorted.
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
- Each shelf folder gets a Finder icon with its emoji. Sparkle is the only competitor that uses a container; the others sort into the root.
- Unlike Sparkle, Kanso **never moves the user's existing folders** on first run.
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
- **Everything can be undone.** Kanso **never deletes** and never empties the Trash. It moves a file to the Trash on its own only when the file is **provably spent** (an installer whose app is installed, see Smart Eject); everything else goes to the Trash only when the user presses ⌘⌫. Every trash is journaled and one ⌘Z away. See `docs/adr/0002-trash-only-provably-spent-files.md`.
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

**v1 = By kind + renaming + tagging + duplicates**, on macOS 14+. Each feature has its own toggle and states whether it reads contents.

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

### Smart Eject
*Decided 2026-09-29.* When an app from a mounted `.dmg` lands in `/Applications` (same bundle ID; a reinstall of the same version counts), or a `.pkg` installer finishes, Kanso waits for the copy to settle, **ejects the volume and moves the installer to the Trash automatically**. It's journaled, and the island shows "Installed Figma · installer moved to Trash · ⌘Z". A `.dmg` from which nothing was installed (opened to read a README or copy one file) is never trashed. Reference: Tidy's Smart Eject.

### The island and shortcuts
*Revised in the UI/UX grilling on 2026-09-28; terms are defined in `CONTEXT.md`.*
- **Plain sorts are silent.** A sort is what the user asked for, so it shows nothing in the moment; it appears in the popover's Done list and in Recents. Only renames, duplicates and needs-you items get a notice, which keeps notices rare enough to be read.
- **The island replaces the toast.** Notices grow out of the notch, Dynamic-Island style, and never steal focus. On a screen without a notch (Mac mini/Studio, external displays, clamshell) the same shape appears as a pill at the top center. It always appears on the **active screen**, the one with the focused menu bar, even if the notch is on another display. In full-screen apps notices collect quietly with the menu bar dot, as under Focus.
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
- **Notch-free option** (General, owner's request): because other apps compete for the notch, the user can choose **Island: From the notch / Below the notch**. "Below the notch" uses the notch-less design (a Liquid Glass capsule that drops from just below the menu bar at the top center) on every screen, including notch screens. The setting has three choices: **Automatic** (default) · From the notch · Below the notch. Automatic follows detection both ways: below the notch while a known notch app runs (NotchNook, Alcove, Droppy, Boring Notch, Notchy…), back in the notch when it quits. An explicit choice is always respected. Mode switches happen only between notices, never mid-animation. **Kanso yields to other notch apps:** it has no window at rest, so hovering the notch reaches the other app. If another notch app's panel covers the spot where Kanso's capsule would appear, Kanso holds its notice until that panel collapses; if it expands over a showing capsule, Kanso collapses to compact and reappears afterwards, never fighting for the front (detected from the window list, no permissions). With an explicit "From the notch" while such an app runs, the setting notes: "NotchNook also uses the notch; both may react when you hover it."
- **Turning Sorting off asks for how long:** 15 minutes · 1 hour · until tomorrow · until I turn it on. Timed choices turn Sorting back on by themselves. If Sorting has been off for 24 hours, the island says so **once** ("Sorting has been off since yesterday · ↩ Turn on") and never again for that off period. There is no separate Pause setting.
- **The island's overview state** (⌥⌘K, a notch click or the popover's "Show Kanso" row, with no notice showing) is only about now; stats live in the Overview window. Top to bottom: **Needs you** (one tinted row per pending item with its morph icon; ↑ ↓ select, Return runs the row's main action; 4 or more shows 3 and "+ N more · Activity"), then **Recently** (the last 3 things Kanso did, ⌘Z undoes the selected one), then two small icons: **Open Kanso** (the window) and a **gear that always opens the Settings window** (not Quick settings). **No Sort Now button** on the island. With nothing pending and nothing in the last 24 hours it shows one calm line ("All quiet · 312 files kept in order this month") and no empty sections. The ask field joins the bottom in v1.1.
- **Two skins, one island,** chosen by the screen: on a notch screen it's **black** and grows out of the notch with concave "ear" corners; the expanded island is black with Liquid Glass controls inside. On a screen without a notch there is **nothing at rest**; a notice drops a **Liquid Glass capsule** (`.ultraThinMaterial` on 14–15) from just below the menu bar at the top center, with all corners rounded and a small gap, so it floats instead of imitating hardware (NotchRail's approach). Identity comes from shape and motion, not color. Visual reference: Droppy's island.
- **Motion:** move toward Liquid Glass, fluid spring animations and micro-interactions throughout. A keyboard-opened island animates fast (a spring settling in about 200–250 ms, no delay); the dwell and click paths can use the fuller expansion.
- **One global shortcut, ⌥⌘K** (above); the old ⌃⌥⌘Z / ⌃⌥⌘⌫ chords are gone. Older actions go through the Activity list. **A duplicate notice's primary action is Undo**; Move to Trash is only ever ⌘⌫, so ⌥⌘K then Return can never trash.
- **Under Focus and in full-screen apps,** notices collect silently and the menu bar icon shows a dot.
- **Review windows** (mass renames, the Sort everything preview) are real windows where plain ⌘Z and ⌘⌫ work.

*These decisions were validated against the design skills in `docs/design-validation-2026-09-29.md`; its resolutions (focus rings, reduced motion, pastels only on surfaces, no glass on glass or on content, VoiceOver announcements, spring values) are part of the design. The designer's brief is `docs/design-handoff-prompt.md`.*

### Settings structure (decided 2026-09-29)
- **The problem is dense screens, not the number of menu items.** Each screen shows only what the user actually changes; everything else gets a good default and no control. Hero illustrations, "how it works" placeholders and per-feature Recent lists go; Activity already covers history, and onboarding plus the island teach what features do.
- **One App window (decided 2026-09-30, replaces the separate Kanso and Settings windows):** a sidebar with Overview, Activity · Sorting, Renaming, Duplicates, Tagging, Smart Eject · General, Privacy & AI. No toolbar navigation, only the page title. ⌘, and every Settings button open General. **Overview** has no Sort Now: a statement, **Needs you** (only when something is pending), **Since you started** (four pinned cards: Sorted today, Renamed, Duplicates found, Undo rate) and **Highlights** (two cards: monthly sorting, shelves by size). Each feature page is a showcase banner, the feature's switch card, then its options; a switched-off feature dims its options.
- **Rules** live inline on the Sorting page: only the user's own sorting rules (add, edit inline, switch off, remove). Kanso's built-in extension table and its default rules (Make, n8n, Zapier exports) are not shown; they just work. There is no Types screen.
- **Unknown files have no settings:** Kanso always asks the model; if the model creates a fitting new type it gets its own shelf (suggesting new types is always on), and if there's no meaningful answer the file goes to ❓ Unsorted.
- **Corrections teach types:** a learned type is fixed by moving the file. Moving it to another shelf (in Finder, or Activity's "Move to another shelf…") updates the learned mapping, so the next file with that extension follows. Learned types are not listed anywhere; Activity's "How Kanso decided" explains any single file.
- **Features** each have a page (see above) with a switch, one sentence and a reads-contents badge. **Auto-Sort becomes the "Sorting" feature**, and the approach, watched folders and Recents are configured inside the Sorting row.
- **What each Features row keeps** (everything else: a default, no control):
  - **Sorting**: a plain on/off switch like every other row (no separate "Auto-Sort" concept). Expanded: watched folders (+ Add), Recents (Shortcuts / Hold / Off), wait before sorting, approach (By kind · By purpose *soon*).
  - **Renaming**: on/off. Expanded: name format (template, separator, date format) and "ask before renaming more than 10 at once". **Name language is removed** (match the shelf, then system, then English, always).
  - **Tagging**: on/off only.
  - **Duplicates**: on/off. Expanded: where extra copies go (**Duplicates shelf** by default, or Trash), auto-trash held copies after N days (**off** by default; 30 days preset when turned on; opening a held copy resets its timer, so only untouched copies expire), space held with **Move all to Trash…**.
  - **Smart Eject**: on/off only.
- **Activity detail:** no Timeline (its one useful fact, when it happened, joins the metadata line). A visual block appears only where the picture explains the decision (rename: old name struck through over the new one, and the page preview; duplicate: the two copies side by side; batch: shelf bars); a plain sort or a waiting item has none. "How Kanso decided" stays as the heart of the screen. From 6 blocks to 3–4.
- **Insights style references** (owner, 2026-09-29): Tomáš Sebastián's "Analytics Micro-interaction" (layers.to; one chart per tinted card, big number with a caption and delta pill, hover scrubbing with a snapping pill tooltip, count-up and rolling digits, bars growing in a stagger, round icon buttons in the card header) and a Dribbble "Insight" card set (large serif numerals on flat tinted cards, a delta top-right, a short label).
- **Pastel theme** (decided 2026-09-29): every color keeps its meaning and becomes a pair, a pastel for surfaces, chips and button fills plus a deep ink of the same family for text, icons and lines. Starting values (to be checked for contrast): Kanso/sorted mint `#CFE8D8` / `#2E5A4B` · rename periwinkle `#D9E0FA` / `#3C509A` · duplicate butter `#F7E4B5` / `#7E531B` · rule lavender `#E5DCF7` / `#5A4687` · where aqua `#D0ECEC` / `#1E666B` · neutral stone `#ECEAE5` / `#48484D`. **Mint is the brand accent** (switches, selection, links). No white-text buttons: primary buttons are pastel with ink text. Dark mode uses the ink hue at about 25% for surfaces and a lightened pastel for text. Cards are tinted by what they measure. The island stays black or glass, with pastels only inside it. This supersedes the sage tokens in `kanso-designs/DESIGN_SYSTEM.md`.
- **General** (6 controls): Open at login · Island: Automatic / From the notch / Below the notch · Show the ⌥⌘K hint (turns itself off after a few days) · During Focus and full-screen: collect notices quietly · Island shortcut ⌥⌘K (Change) · Menu bar icon Show/Hide (when hidden, Settings stays reachable through the island's gear).
- **Privacy & AI** (mostly statements): model status (Apple Intelligence; Kanso Local when it exists) · what reads inside files, shown as facts (the switches live in Features) · every network call (update checks with a switch, model download on request, cloud AI "not available") · crash reports (off) · one "never read" sentence (Keys, vaults, Manual Shelves, iCloud placeholders) · About (version, GitHub, Buy Me a Coffee, Send feedback).
- **Removed, now fixed behavior:** "only while plugged in" (content reading always pauses on battery below 20%), "low priority" (always background priority), "show toasts" (no toasts exist) and the three old shortcuts (⌥⌘K replaces them).
- All screens use the island's design language: Liquid Glass, the same components, springs and keycaps.

### Onboarding (decided 2026-09-29)
Three steps, learning by doing; approach, feature switches and details live in Settings (defaults: Sorting, Renaming, Duplicates and Smart Eject on; Tagging off).
1. **Folders.** "Kanso needs to open three folders." An explanation (top level only, shelves inside the same folder, nothing leaves the Mac, macOS asks once per folder), the three folders pre-checked (unchecking narrows the request), and **one button, Continue**, which triggers macOS's prompt per checked folder (in the sandboxed build, the folder picker preselected on each). Per the HIG: no "Allow" wording and no close/cancel before the system prompt. Folder access is Kanso's only permission (Carbon hot keys need no Accessibility; no Full Disk Access; the island replaces notifications).
   - A declined folder is skipped silently and shows in the Sorting row as "not allowed" with **Open Privacy Settings**; it turns normal once access is detected. Nothing on the island.
   - If every folder is declined, onboarding ends on one calm screen, "Kanso needs at least one folder to work", with Open Privacy Settings as its only button.
2. **The island.** A live demo inside the window with a pretend file (real files untouched): the rename sweep and beam, then "press ⌥⌘K", which expands the demo island. Never blocking: a Skip link, and after 10 s it expands on its own ("or click the island").
3. **Existing files.** Only sort new files / Preview a cleanup.
- **Conditional:** if Apple Intelligence is off or unavailable, a short step before 3 offers turning it on (without it, unknown types go to ❓ Unsorted).

## 8. Roadmap

| Release | Contents |
|---|---|
| **v1** | Swift app, By kind, renaming, dimension tags, duplicates, **the island** (replaces toasts; ⌥⌘K), **quick settings popover**, **Smart Eject**, preview for Sort everything, onboarding, settings, local stats, Apple Intelligence + Kanso Local, Homebrew |
| **v1.1** | **The ask field** (macOS 26+, ADR 0001 safety rules, an evaluation set before shipping); the island reserves its slot from v1 |
| **By purpose release** | content reading within the limits above, adopting folder names, earned trust, status and reminder tags, per-folder profiles |
| **v2** | **the Tray** (drop files, links and snippets on the island; AI organizing; own design session), the full model picker (benchmarked local LLMs, BYOK, paid cloud), natural-language rules UI, suggested new shelves |
| **Later** | chat with your files (needs a stored index, so it gets its own opt-in and is revisited then), Mac App Store build |

## 9. Success criteria

- **Launch gate (dogfood):** the owner uses the Swift v1 on their real Downloads, Desktop and Documents for **two weeks**, with an **undo rate under 5%** measured from the journal.
- **After launch** (no telemetry, so only signals we can observe):
  - **Retention:** about 60% of installs still checking for updates after 30 days (from the update-check logs).
  - **Trust:** an undo rate under 5% of automatic actions, from opt-in shared stats. If it's higher, fix it before building By purpose.
  - **Qualitative:** among the first 20 GitHub issues and discussions, mostly feature requests rather than "it moved my file wrongly".
  - **Value:** Buy Me a Coffee supporters, and shared "your month with Kanso" stats.
