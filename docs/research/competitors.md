# Competitor research: Mac automatic file sorters

Researched 2026-10-30 with web search and page fetches. Vendor pages are marketing; reviews are scarce. "Unverified" means I could not confirm it from a primary source. Kanso's column is based on `AGENTS.md`, `PRODUCT.md` and the README, not on the marketing pitch.

## 1. Products covered

Sparkle, Hazel 6, Tidy (tidymacapp.com, not TidyMac or Desktop Tidy), Sorty (open source), Sortio, Cosmos, plus a long tail of listings. Cleaner suites and Default Folder X were not researched.

## 2. Per-competitor notes

### Sparkle (Every)
- **Features:** cleanup (junk, duplicates, "wasted storage", app uninstaller), AI folder organization, natural-language requests, 10+ custom rules, schedule, local iCloud/Google Drive folders, trash first with undo. Rebuilt as an "agent-native" app; Every called it its biggest update since the 2024 launch. Download link on the site points to a "canary" GitHub release (seen 2026-10-30).
- **Pricing (seen 2026-10-30, conflicting):** site says plans "start at $9.25 for a month", 15-day trial; Every Bundle $30/month. G2 lists $9.25/mo + $30/mo bundle. Directories list lifetime $179 (and yearly $99); an older write-up says $119 lifetime. Earlier reviews: $20/mo or $200/yr (Sept 2024); $5/mo, $50/yr or $89 outright (Apr 2025). I could not load a pricing page (`/pricing` is 404). Unverified which is current.
- **Privacy:** site says it "reads your files only to sort them" with "zero data retention" but does not say local or cloud. Every's help text (via search snippet, page 404 on fetch) says it runs locally and file names are purged after 30 days. A 2024 write-up says file names go to Every's server and OpenAI (GPT-4). Net: file names probably leave the Mac. Unverified.
- **Reviews:**
  - Praise: "Sparkle did exactly what it said it was going to do." ([Substack, Sept 2024](https://aooarchived.substack.com/p/21-days-with-sparkle-a-review))
  - Complaint: "It's difficult to justify the cost." (same review); EPUBs mixed into Documents.
  - Praise: "Sparkle works quickly, sorting several thousand files for me in a day." ([Matthew Becher, Apr 2025](https://matthewbecher.substack.com/p/mini-review-sparkle-file-organizer))
  - Complaint: sorts by file name, so categories like "art" and "artwork" split; duplicate detection only worked after gathering files into one folder.
  - No Reddit, Hacker News or App Store reviews found.
- **Claims to discount:** "18 GB recovered on average", "10,000+ users" are vendor claims.

### Hazel 6 (Noodlesoft)
- **Features:** rule engine on watched folders (name, date, type, source site, and more), actions: move, rename, tag, archive, upload, run scripts, Shortcuts/AppleScript/Automator; trash management; App Sweep (leftovers of deleted apps); 6.0 added on-the-fly text recognition (OCR). No AI features advertised. Spotlight/Photos/Music import. Built-in duplicate finder: not advertised (unverified).
- **Pricing (seen 2026-10-30):** $42 single, $65 family, $20 upgrade, free upgrade if bought Hazel 5 in 2024. A 20th-anniversary sale at 35% off was reported; not confirmed active. One-time, no subscription.
- **Platform:** macOS 13+ for 6.x (6.1 added Tahoe UI; a Japanese listing shows 6.1.2, Feb 2026). Local only.
- **Reviews:** AlternativeTo has one 1-star (Dec 2024: clean-up "misses files") and a 2020 5-star praising PDF content sorting ([AlternativeTo](https://alternativeto.net/software/hazel/about/)). Common community theme (not directly quoted here): rules need setup and a learning curve. Unverified.

### Tidy (tidymacapp.com)
- **Features:** Auto-Drop (archives screenshots, renames them by content with on-device OCR, trashes later), Smart Eject (ejects a .dmg and trashes the installer), Flow Rules (type, filename, file text; plain-English rules built by Apple Intelligence), rename preview, search inside images and scanned PDFs, duplicate detection by content, privacy audit for sensitive documents, Siri/Shortcuts, iPhone scanning. Never deletes (archive or Trash), only touches files created after a folder is added, dry run, searchable history, run-level undo.
- **Pricing (seen 2026-10-30):** US$9 one-time, lifetime updates, 14-day guarantee.
- **Platform:** macOS 14+, Apple silicon and Intel; English, Spanish, German, Portuguese, French.
- **Privacy:** on-device OCR, encrypted local index (key in Keychain), no account, no server, no telemetry. Optional Claude connector, off by default, sees summaries not files. Some AI needs macOS 26 / Apple Intelligence.
- **Reviews:** Product Hunt launch 2026-07-21, 96 points, #17 of the day ([PH](https://www.producthunt.com/products/tidy-5/launches/tidy-6)). A launch comment (via search snippet, not fetched in full) asked for a way to exclude subfolders from auto-sort. No independent review found; a Six Colors quote on the site was not verified.
- **Why it matters:** it ships much of Kanso's v1 plan at $9 closed source. It is the main threat.

### Sorty (open source)
- Free, GPL-3.0, native SwiftUI, macOS 15+ (Apple Foundation Models need 26+). Content-aware sorting into semantically named folders, "Learnings" profile from corrections, personas, Finder right-click, menu bar, preview before moving, history with undo, duplicate detection.
- Cloud providers (OpenAI, Anthropic, Gemini and others) or local (Ollama, Apple FM); metadata goes to the chosen provider.
- 53 stars, 5 forks at fetch time (small). Release date not visible. No reviews found.

### Sortio
- Mac/Windows/Linux. Reads contents, renames, routes to folders, plain-English rules, watch folders, semantic search, undo. "Runs locally by default" with optional cloud/own key; other vendor text says filenames and summaries go to its servers (conflict, unverified). Pricing conflicts: $13 one-time vs free tier plus Pro $14.99/mo or $99/yr. Listed 2025-12-15.

### Long tail (listings only, unverified)
- **Cosmos:** $24.99, macOS 14+, Apple silicon, review-before-move, undo, learns from accept/reject; no ratings yet ([App Store](https://apps.apple.com/app/id6759027625)). Also Folder Organizer $5.99, Tiny Sort $0.99, Neatify $31 (rule-based), Floxtop, OCDify (free, open source), AI File Sorter (MIT), Files Magic AI (names sent to servers). Crowded with cheap one-person apps and few ratings.

## 3. Feature parity matrix

Y = yes, P = partial, N = no, ? = unverified. Kanso column reflects the code/docs as of 2026-10-30 (README says "still in early development"). Kanso "Not done" items from AGENTS.md are marked N.

| Feature | Kanso | Sparkle | Hazel 6 | Tidy | Sorty | Sortio | Cosmos |
|---|---|---|---|---|---|---|---|
| Auto-sort new files in watched folders | Y | Y | Y | Y | P (manual runs, menu bar) ? | Y | ? |
| Sort by file type without a model | Y | ? | Y (rules) | Y | ? | ? | ? |
| AI for unknown types, creates new type | Y (Apple FM) | Y | N | Y | Y | Y | Y |
| Container folder (My Shelves) + untouched Manual Shelves | Y | Y | N | N | N | N | ? |
| Recents symlinks | Y | ? | N | N | N | N | N |
| User-written rules | Y (glob, ext, URL) | Y (plain English) | Y (very deep) | Y (plain English) | P | Y (plain English) | Y |
| Natural-language rules | N (`when` rules exist in Python only) | Y | N | Y | Y | Y | ? |
| Rename by content | Y | N? | P (scripts, OCR) | Y | Y | Y | ? |
| Tagging (Finder tags) | Y | ? | Y | ? | ? | ? | ? |
| Duplicates | Y (size + SHA-256) | Y | N? | Y | Y | ? | ? |
| Smart Eject (.dmg) | Y | N | N | Y | N | N | N |
| Screenshot handling | Y (shelf, flag) | ? | via rules | Y (Auto-Drop, OCR rename) | ? | ? | ? |
| Learns from corrections | Y (rule suggestions, learned exts) | ? | N | ? | Y | ? | Y |
| Undo / journal | Y (every move) | Y | N (no global undo, ?) | Y | Y | Y | Y |
| Preview first (dry run) | Y (first sort everything) | ? | Y (preview) | Y | Y | ? | Y |
| Only new files by default | Y | ? | Y (per folder) | Y | n/a | ? | ? |
| Search by content | N | ? | N | Y | N? | Y | Y |
| Ask field / natural-language commands | Y (macOS 26 + AI) | Y | N | N | N | N | Y (search) |
| Notch/island UI | Y | N | N | N | N | N | N |
| On-device only by default | Y | ? (names likely sent) | Y | Y | P (user choice) | P | Y (declared) |
| Cloud AI option | N (planned, opt-in) | Y (inherent) | N | P (Claude connector) | Y | Y | N |
| Works without Apple Intelligence (macOS 14-15) | N (Kanso Local not built) | Y | Y | P | Y (cloud/Ollama) | Y | ? |
| Intel Macs | N | ? | Y | Y | ? | ? | N |
| Shortcuts / AppleScript | N | N | Y | Y (Shortcuts) | P (deeplinks) | ? | ? |
| Open source | Y (GPL-3.0 planned; repo status per docs) | N | N | N | Y | N | N |
| Signed + notarized release, auto-update | N yet | Y | Y | Y | N? | ? | Y (App Store) |
| Localization | N | ? | Y (partly) | Y (5 languages) | ? | ? | ? |
| Cloud-folder aware (iCloud placeholders) | Y (never reads placeholders) | P | Y (6.1 options) | ? | ? | ? | ? |

## 4. Pricing table

| Product | Model | Price seen | Date seen |
|---|---|---|---|
| Kanso | Free, donations (Buy Me a Coffee); optional paid cloud tier later (PRODUCT.md) | $0 | 2026-10-30 |
| Sparkle | Subscription, maybe lifetime | from $9.25/mo; 15-day trial; lifetime $179 and yearly $99 per directories (unconfirmed) | 2026-10-30 |
| Hazel 6 | One-time | $42 / $65 family / $20 upgrade | 2026-10-30 |
| Tidy | One-time | $9 | 2026-10-30 |
| Sorty | Free, GPL-3.0 (user pays own cloud keys) | $0 | 2026-10-30 |
| Sortio | Freemium | free tier; Pro $14.99/mo or $99/yr (listing also says $13 one-time; conflict) | 2026-10-30 |
| Cosmos | One-time | $24.99 | 2026-10-30 |
| Folder Organizer / Tiny Sort / Neatify | One-time | $5.99 / $0.99 / $31 | 2026-10-30 |

## 5. Positioning map (in words)

Axes: how much the user configures, and where the intelligence runs.

- **High configuration, no AI:** Hazel. Power users, scripts, 20 years of trust. Weak first-run experience.
- **Low configuration, cloud or unclear AI, subscription:** Sparkle. "Describe what you want", cleanup plus organize, aimed at a productivity-newsletter audience, bundled with Every.
- **Low configuration, on-device, cheap one-time:** Tidy and Cosmos, plus many $1-$6 App Store apps. Tidy is the strongest.
- **Open source, user-chosen model (cloud or local):** Sorty, AI File Sorter, OCDify. Technical audience, rough edges.
- **Kanso:** low configuration, on-device first, free, open source, container-folder design that leaves the user's folders alone. It sits between Tidy (same philosophy, closed, $9) and Sorty (open, cloud-friendly, content-driven). Its AI is deliberately narrow (unknown types only): a trust story, but a smaller capability story than Sparkle, Sortio or Tidy.

## 6. SWOT for Kanso

**Strengths**
- Deterministic by-type sorting needs no model for known types; models see metadata only.
- Safety design is stronger than most: journal, undo for every move, ADRs on trash, "provably spent" only, Manual Shelves never touched, Keep tag, first run is a preview.
- Free and open source with a clear privacy stance; no analytics.
- Breadth in v1: rename, tags, duplicates, Smart Eject, Activity with "how Kanso decided", island UI, ask field.

**Weaknesses**
- Not shipped: README says early development; no notarized release, Homebrew cask or updater; GitHub and donation URLs are placeholders (AGENTS.md).
- Requires macOS 26 with Apple Intelligence for the model features; no Kanso Local model for macOS 14-15 (the plan lists macOS 14+). Apple silicon only.
- No natural-language rules in the Swift app, no content search, no Shortcuts, no localization, no By purpose yet.
- One developer; no reviews, ratings or user base to cite.
- Sandbox and security-scoped bookmarks not done; Full Disk Access friction.

**Opportunities**
- Sparkle's price and privacy ambiguity; Kanso can show "nothing leaves the Mac" in public code.
- Hazel is powerful but rule-heavy with no AI: the "Hazel without setup" audience.
- Tidy is closed source and $9; no free equal exists.
- macOS 26 Foundation Models make on-device AI free to ship.

**Threats**
- Tidy already ships Smart Eject, content renaming, plain-English rules, duplicates and undo at $9, in five languages.
- The App Store is flooded with $1-$25 sorters; "free" is a weak differentiator.
- Apple may add its own organization to Finder.
- Sparkle has Every's audience. One bad move in an early free app costs reputation fast.

## 7. Parity gaps

**Must have (before a public 1.0)**
1. **Shipping basics: notarized build, auto-update, working GitHub/donation links, Homebrew cask.** Everyone in the table except Sorty ships a signed installer. Without it nothing else matters.
2. **A path for macOS 14-15 and non-Apple-Intelligence Macs (Kanso Local or a clear deterministic-only mode).** Tidy supports macOS 14 and Hazel macOS 13. Today Kanso's headline AI is limited to one OS and hardware tier. At minimum, ship by-type sorting, rename templates, duplicates and Smart Eject working fully without a model, and say so.
3. **Plain-English rules ("move invoices from Acme to Finance").** Sparkle, Tidy and Sortio all lead with this; Kanso's rules are glob/ext/URL. The ask-field infrastructure exists, so this is a product gap, not a research one.
4. **Excluding subfolders and per-folder settings** (the one concrete Tidy complaint on Product Hunt). Needed for trust; also the planned per-folder profiles.
5. **Proof of the safety claims in public:** a short demo of undo, first-run preview and Manual Shelves. Competitors state "never deletes"; Kanso should show it.

**Should have**
6. **Shortcuts actions** (Tidy and Hazel have them). Cheap with App Intents; helps power users.
7. **Search by content / OCR search.** Tidy, Sortio and Cosmos sell it. It conflicts with "keep nothing", so only do it with an on-device index the user opts into, or skip (see below).
8. **Localization** (Tidy ships five languages; the benchmark already found German names matter).
9. **Intel support:** Tidy and Hazel have it; revisit only if requests appear.

**Skip (for now)**
- **Cloud AI and a paid tier:** dilutes local-first; build last.
- **Junk cleanup, uninstallers (Sparkle) and App Sweep (Hazel):** a different product.
- **Deep scripting (Hazel) and content-based By purpose:** off-brand now; By purpose after v1 as planned.

## 8. Where Kanso can win

1. **Verifiable privacy:** open source, metadata-only for sorting, no analytics, a listed set of network calls. Sparkle's and Sortio's own statements are inconsistent; Tidy is closed. A one-page "what leaves your Mac: nothing, here is the code" beats claims.
2. **Respect for the user's structure:** Manual Shelves is never touched, existing folders are never moved, no empty folders, Recents symlinks keep new downloads findable. Only Sparkle has a comparable container, and it reorganizes more aggressively.
3. **Trust mechanics shown as a feature:** the Activity page ("How Kanso decided", a warning when it guessed), full journal undo, and Smart Eject only when the install is provable. Sorting by type is boring, predictable and explainable, which is the opposite of "AI guesses meaning".
4. **Free + open source at feature parity with a $9 closed app**, if the shipping basics land.
5. **The island and ask field** are distinctive on macOS 26; a delighter, not a reason to buy.

## Sources (all accessed 2026-10-30)

- Sparkle: https://makeitsparkle.co ; https://aooarchived.substack.com/p/21-days-with-sparkle-a-review ; https://matthewbecher.substack.com/p/mini-review-sparkle-file-organizer ; https://every.to/on-every/introducing-sparkle ; https://help.every.to/en/articles/13225433-how-sparkle-protects-your-files-and-data (404 on fetch; text from search snippet) ; https://www.igeeksblog.com/organize-mac-with-sparkle-ai/ ; https://www.toolmage.com/en/tool/sparkle-1/ ; https://ai.g2.com/marketplace/tools/sparkle
- Hazel: https://www.noodlesoft.com/ ; https://www.noodlesoft.com/?p=1852 (Hazel 6 FAQ) ; https://www.noodlesoft.com/?p=2008 (6.1 notes) ; https://alternativeto.net/software/hazel/about/ ; https://tidbits.com/watchlist/hazel-6-1/
- Tidy: https://tidymacapp.com/ ; https://www.producthunt.com/products/tidy-5/launches/tidy-6 ; https://www.producthunt.com/p/tidy-5/tidy-6
- Sorty: https://github.com/sorty-organizer/Sorty
- Sortio: https://alternativeto.net/software/sortio/about ; https://ai.g2.com/marketplace/tools/sortio
- Cosmos: https://apps.apple.com/app/id6759027625
- Kanso: `/home/agents-user/kanso/AGENTS.md`, `PRODUCT.md`, `README.md`

Gaps: no Reddit or Hacker News threads were returned by search; no App Store review text for Hazel, Tidy or Sparkle; Sparkle current pricing and data flow unconfirmed.
