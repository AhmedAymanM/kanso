# Kanso — design brief

## What it is
**Kanso** (簡素, the Zen principle of simplicity by removing clutter) is a macOS menu bar app that keeps Downloads, Desktop and Documents tidy automatically.
It sorts every new file into shelves, by type (images, documents, spreadsheets, code…) or later by
purpose (work, personal, expenses…). It also gives meaningless file names clear ones, adds a
couple of helpful tags, and catches duplicates, with no effort from the user. Everything runs on
the Mac: Apple Intelligence on macOS 26, or a small downloadable local model on older versions.
Cloud AI exists only as a clearly labeled opt-in.

Pitch: *"Kanso quietly keeps your Mac simple. Your files never leave your Mac, Kanso only reads
inside them for the features you turn on, and you can read every line of code."* It's open source,
and that's the proof.

Personality: calm, quiet, trustworthy, native to macOS. Zen minimalism: generous empty space, restraint, one strong accent. It should feel like a feature Apple
built, not a third-party utility. It works in the background, so most of the time the user
never sees it.

## Who it's for
Mac users whose Downloads and Desktop pile up with screenshots, PDFs, installers and exports:
developers, designers and knowledge workers. They want order without having to set up rules.

## How it works (what the design has to explain)
In each watched folder, Kanso creates three folders, each with an emoji folder icon:
- **✨ My Shelves**: Kanso sorts files here into type folders. Each folder has a Finder icon with an
  emoji drawn on a standard macOS folder:
  📄 Documents · 📊 Reports (spreadsheets) · 📽️ Presentations · 📚 Ebooks · 🖼️ Images ·
  📸 Screenshots · 🎬 Videos · 🎵 Audio · 🎨 Design · 💻 Code · ⚙️ Automations · 🗄️ Databases ·
  📐 Diagrams · 🧾 JSON · 📦 Archives · 📲 Apps · 🧊 3D Models · 🔑 Keys · 📅 Calendars ·
  👤 Contacts · 🧲 Torrents · 🔤 Fonts · ❓ Unsorted, plus a **🪞 Duplicates** shelf that holds extra copies until the user trashes them
- **🏠 Manual Shelves**: the user's own space. Kanso never moves anything in or out (it only reads it
  to spot duplicates).
- **🆕 Recents**: shortcuts to everything sorted in the last 7 days, so a fresh download is never
  "lost". Modes: shortcuts (default), keep the real file here until it's a week old, or off.

Two equal approaches, chosen during onboarding and switchable later (new files only, unless the user asks to re-sort):
- **By kind:** folders by file type, as above. Metadata only, so Kanso never opens the file.
- **By purpose:** folders by what the file is for (Work, Personal, Expenses, Travel…). Kanso reads contents to decide, **on the Mac only**. It learns from the names of the user's existing folders and from their corrections. **This is "coming soon" in v1:** show it as an equal card in onboarding with a coming-soon state.

Trust is earned per shelf. By kind moves automatically. By purpose moves automatically only when confident and when the user hasn't corrected that shelf recently. Otherwise the file waits in Recents, and the menu bar asks a one-click "Where should this go?" (design this interaction). The first "Sort everything" is always a **preview**: a list of file → shelf, where the user can uncheck items, then Apply.

Optional features, each with its own toggle and a note on whether it reads contents: smart renaming, AI tagging, duplicate detection.
Trust promise: *"Your files never leave your Mac. Kanso only reads inside them for the features you turn on."*

When a file type is unknown, Apple Intelligence picks a folder or creates a new one with its
own name and emoji (for example 🧲 Torrents), and remembers it for next time. If it can't
tell, the file goes to Unsorted.

Safety:
- Every action can be undone.
- **Kanso never deletes anything.** It moves only provably spent files to the Trash on its own (installers after their app is installed); everything else waits for the user.
- It never moves the user's existing folders.
- It never reads 🔑 Keys, password vaults or Manual Shelves.
- It reads only the first page or so of a file, and keeps none of the text.
- Right-clicking a file in Finder and choosing "Don't Sort with Kanso" protects it.
- Partial downloads and files still changing are never moved.

## Distribution
Open source and free. Downloaded directly (notarized, Homebrew cask) first, Mac App Store later.
Optional support: Buy Me a Coffee, and later an opt-in paid cloud tier for context features.
The design needs to cover the "About / Support" surface and an opt-in cloud AI setting that makes clear what gets sent.

## Current UI (a plain native menu, to be redesigned)
Menu bar icon: a tray (outline when paused, filled when active, a spinning-arrows icon while sorting).
Menu contents:
- Auto-Sort toggle, and a status line ("Sorted 12 items")
- Folders: each watched folder, with the actions Show in Finder / Stop Sorting, and "Add Folder…"
- Sort New Files Now · Sort Everything… (with a confirmation) · Undo Last Sort
- "Apple Intelligence: on / off"
- Edit Rules… (currently opens a TOML text file) · Grant Folder Access… · Quit

## Screens to design
1. **Menu bar popover** replacing the plain menu:
   - on/off state
   - the last activity ("Sorted 5 files · 2 min ago", with small type icons)
   - watched folders
   - Sort now / Undo
   - Apple Intelligence / Kanso Local status
   - a dot on the icon when toasts collected quietly during Focus
   - later, with By purpose: pending one-click "Where should this go?" questions
2. **Onboarding (3–4 steps):**
   - what Kanso does, shown with the folder layout
   - choose an approach: By kind or By purpose, as two equal cards with one sentence each
   - optional features: renaming, tagging, duplicates
   - choose which folders to watch. The user picks each folder once in the standard macOS folder
     picker; there's no Full Disk Access step.
   - AI: if Apple Intelligence is on (macOS 26+), confirm it. Otherwise offer "download Kanso Local
     (~0.7 GB)", "turn on Apple Intelligence" (26+ only) or "use cloud AI" (opt-in, clearly labeled).
   - existing clutter: "Only sort new files" or "Preview a cleanup". The first Sort everything is
     always a preview, in the review window.
3. **Settings window** (native macOS settings style, with tabs):
   - General: folders, Auto-Sort, toasts, and global shortcuts (Undo ⌃⌥⌘Z, Move to Trash ⌃⌥⌘⌫,
     both editable)
   - Models: Apple Intelligence or Kanso Local (download size, delete to free space). The full picker
     comes later.
   - Approach: By kind / By purpose, plus "Re-sort everything"
   - Features: renaming, tagging and duplicates toggles, each with a "reads contents" badge. Renaming
     has a name-language setting (default: match the shelf, then the system language, then English).
   - Recents: mode (Shortcuts / Hold / Off) and the number of days
   - Types: a list of types with their emoji, extensions and description. Types that Apple
     Intelligence created get a small "learned" badge, and can be edited, merged or deleted.
   - Rules: a visual editor for "if the name matches / the extension is / it was downloaded
     from … then move to …". Rules can also be plain-English conditions judged by AI.
   - Privacy: which features read contents (all on this Mac), a "Network" list of every call Kanso
     can make (updates, chosen model downloads, cloud AI if enabled), opt-in crash reports, and
     Apple Intelligence status.
   - Stats (local only): "This month: 312 files sorted · 41 renamed · 1.2 GB of duplicates found". It's
     the "Kanso is working for you" moment, next to Buy Me a Coffee.
   - About / Support: version, GitHub link, Buy Me a Coffee, and "Send feedback", which opens a
     prefilled GitHub issue or email the user sees before sending.
4. **Activity / history:** a timeline of everything Kanso did (sorted, renamed, tagged, duplicate
   moved). Each row shows file → shelf / new name with the type emoji, what the decision used
   ("from name" or "from contents, page 1"), and Undo.
5. **Toasts:** Kanso's own floating toast near the menu bar (never takes focus, fades after about 6 seconds, Arc-style). It shows the action and its global shortcuts: Undo ⌃⌥⌘Z, Move to Trash ⌃⌥⌘⌫. There are variants for sorted, renamed, duplicate and "N files can be renamed. Review?". Under Focus, toasts collect quietly and the menu bar icon gets a dot.
6. **Review window** for mass renames and the first Sort everything preview: file → new name / shelf rows, with checkboxes and Apply.
7. **App icon and menu bar glyph** (monochrome template image).

## v1 scope
By kind, plus renaming, tagging and duplicates. By purpose is shown in onboarding as "coming soon".
Renaming produces consistent template names like `Invoice-Vattenfall-2026-03.pdf` (kind, organization, date).
Renames of new downloads with meaningless names (`Scan_0012`, `IMG_1615`, `download (3)`) happen automatically; names a person wrote are left alone, and a small notice from the menu bar says "Renamed Scan_0012.pdf → Invoice-Vattenfall-2026-03.pdf", with **Undo** (like Arc's toasts). Mass renames show a toast: "42 files can be renamed. Review?" leading to a review list. The original name stays searchable.
Duplicates: extra copies of new downloads move to a Duplicates shelf, with a notice "Already have invoice.pdf. Moved the copy to Duplicates": **Undo (⌃⌥⌘Z)** or **Move to Trash (⌃⌥⌘⌫)**. The shelf shows the space it holds ("340 MB"), with "Move all to Trash". Kanso never deletes on its own. Notices should be operable from the keyboard.
Tags are Finder tags. v1 adds up to two "dimension" tags per file (kind + organization, for example `Invoice` `Vattenfall`) with no color. Later, with By purpose, it adds a status tag (`To do` / `Waiting`) and a reminder tag colored by urgency (`Due later` green, `Due soon` yellow, `Due now` red). If the user already has their own tags, Kanso uses those instead.
Model picker in v1: "Apple Intelligence" (macOS 26+) or "Kanso Local" (a one-time download, showing its size).

## Coming later (leave room in the design)
- natural-language rules ("put lecture slides in Uni")
- model picker: Apple Intelligence, downloadable local models, opt-in cloud (BYOK or paid)
- chat with your files (a local index)

## Constraints
- Apple silicon, macOS 14 or later. Liquid Glass is 26-only, so design a classic fallback for macOS 14–15. Apple Intelligence is used on macOS 26+. On older macOS versions, or when it's off, onboarding offers: download a local model (showing its size) or opt into cloud, plus "turn Apple Intelligence on" on 26+.
- Look: macOS 26 native, with a classic fallback for 14–15: SF Symbols, SF Pro, native materials and vibrancy, light and dark mode, and
  accessibility (VoiceOver labels, keyboard navigation).
- Keep the popover about 320–360 pt wide. The settings window should use the standard macOS
  settings layout.
- Emoji on folders are part of the brand. Use them consistently for types everywhere in the UI.
- Color: never rely on color alone (reminder tags later use green/yellow/red with words).
- Full keyboard support: toasts show their shortcuts, and the review windows work with ⌘Z / ⌘⌫ / Return.
