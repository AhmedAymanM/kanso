# Indirect competitors: what Kanso can learn (2026-10-30)

Scope: adjacent Mac tools whose features could inform Kanso (shelves/tray, notch UX, rules, AI, duplicates, cleanup, asset libraries, platform risk). Prices come from search snippets, not vendor pages, unless noted. **Unverified** marks figures that conflicted between sources or came from a single weak source. Confirm before any pricing decision. Kanso rules applied throughout: local first, models see metadata only unless opt-in, everything undoable, never deletes by default.

## Tools

### Shelf and tray

**Dropover / Yoink / Unclutter**
- What: drag-and-drop holding areas. Files, text and links are parked on a shelf or tray, then dragged out later. Dropover 5 added flexible folder monitoring.
- Price (unverified): Yoink ~$6.99 regular (old post), with discounts to $1.99. Dropover ~6.99 EUR after a trial. Unclutter regular price listed as $20 (Macworld bundle).
- Adopt: a drop-to-hold **Tray** with an explicit "Organize" action, which is exactly CONTEXT.md's Tray. Hold items without deciding, then file them later.
- Adapt: Dropover's folder monitoring as a per-folder "hold here" option, to keep the Tray separate from watched folders.

**Stacks (macOS built-in)**
- What: Finder groups Desktop and folders by kind, date or tag. Free and always present. Not searched in this pass; description is from general knowledge.
- Adapt: Kanso's shelves should look like a familiar Stacks view, so the sorted state is easy to read.
- Sherlock risk: medium for the Tray. Stacks already groups by kind, so Kanso's value is moving files, Recents and undo, not just grouping.

### Notch and island UX

**NotchNook**
- What: notch "Nook" with media controls and widgets, plus a file Tray. Also runs on non-notch Macs as a floating strip.
- Price (unverified): mixed. Setapp listing $9.99/month after a 7-day trial; direct listing reportedly pay once or subscription.
- Adopt: the floating fallback for Macs without a notch (Kanso already plans this as Below-the-notch mode).
- Avoid: widgets and media controls. They fall outside the island's notices-only scope in CONTEXT.md.

**Droppy**
- What: notch and floating Dynamic Island-style UI with file shelf, clipboard history and Live Activities. Add-ons called Droplets.
- Price (unverified): one listing $9.99 one-time with a 3-day trial; another review calls it free and open source. Conflicting.
- Adopt: a one-time, small-feature island design that people buy outright.
- Avoid: clipboard history. It reads user content and widens scope.

### Post-capture and polish reference

**CleanShot X**
- What: screenshot tool whose post-capture "floating thumbnail" offers quick actions (copy, save, annotate, drag) that stay until dismissed. Adds cloud sharing.
- Price (third-party, consistent across sources): $29 per Mac one-time, $19/year optional for updates after year one. Cloud $8/month.
- Adopt: a post-action card with one-tap **Undo** and quick actions, shown in the island after a sort or rename.
- Adapt: its keyboard-first polish and hover states as the reference for the island's Liquid Glass.

### Search and launchers

**Raycast**
- What: launcher with free File Search. Pro adds AI chat and models from several providers.
- Price (unverified): File Search free. Pro reportedly $8–10/month, with later tiers unclear (conflicting reports).
- Adopt: keyboard-first command entry. Kanso's ask field already fits this model. Add a command for "Organize tray".
- Avoid: a subscription AI tier and cloud model routing. Conflicts with local-first.

**Alfred**
- What: launcher whose Workflows let users chain actions on files.
- Price (unverified): TidBITS lists Powerpack at £34. A 2026 page mentions $40 in passing. Lifetime license option.
- Adapt: user-visible Workflows as the way to write rules beyond the `[[rules]]` table.

### Rules and automation

**Hazel**
- What: rule engine that sorts folders by name, kind, date, or the site or email a file came from. Common uses: move PDFs, trash old `.dmg`s.
- Price (unverified): $42 single license, $65 family pack (Feb 2026 guide). A 35% sale was also reported.
- Adopt: a "what would match" preview of each rule over existing files before it is enabled. Its "where from" condition matches Kanso's `from` download-URL rules.
- Avoid: Hazel-style automatic trash actions. ADR 0002 limits Kanso to provably spent files.

**DEVONthink 4**
- What: AI-assisted classification, "see connections", and AI actions inside smart rules. Supports Ollama and LM Studio for local models; also cloud providers via API token.
- Price (unverified): no figures found. Pro tier reportedly holds AI features.
- Adapt: an AI step inside a rule that must pick one of the existing types, with a confidence score (Kanso's rule for classifiers). Opt-in, local backend only.
- Avoid: cloud API tokens as a default.

### Asset libraries and linking

**Eagle**
- What: asset manager with multi-tag assets and smart folders (saved filter rules). An MCP server plugin added smart-folder tools in v0.3.1 (2026-05-19).
- Price (unverified): $29.95 for two devices in several listings; $34.95 in one 2026 listing.
- Adopt: **Saved views** over shelves. A saved filter (type plus source plus date) shows files from any shelf, without moving anything. It is undoable by nature.
- Avoid: a full tagging library for every file. That moves toward metadata beyond the agreed scope.

**Hookmark**
- What: bookmark manager that links URLs and documents into apps such as DEVONthink and Pinboard, with Shortcuts and AppleScript automation.
- Price: Standard $29.99, Pro $69.99 (vendor site, as listed in a search snippet; not checked on the vendor page). Setapp option.
- Adapt: the Shortcuts and AppleScript hooks as a later extension point, not core.

**Pixave**
- No usable data found. Left unverified.

### Duplicates and cleanup

**Gemini 2 (MacPaw)**
- What: duplicate and similar-file finder with a "smart cleanup" that picks which copy to keep. The free Mac App Store version can only reveal duplicates in Finder.
- Price (unverified): MacPaw page lists from $1.95/month; older reviews show $19.99/year or $44.95 one-time. Conflicting.
- Adopt: a keeper suggestion with a stated reason ("newest", "in Manual Shelves") shown before any action. Kanso already keeps the first copy.

**CleanMyMac**
- Price not found. Its duplicate module was mentioned without a price.
- Avoid: scary "junk found" scans and one-click deletes. Conflicts with never deleting by default.

**DaisyDisk**
- What: disk map that shows space use as a sunburst. Read-only until the user chooses to remove something.
- Price (unverified): $9.99 one-time for up to five personal Macs. Sales have run as low as $5.49 or $6.99.
- Adapt: a read-only "where space went" map in Kanso's stats (Overview's "Where files went" already points this way).

### Cloud and AI organizing

**Dropbox Dash / Dropbox AI**
- What: Dash is a cross-app AI search product. Core Dropbox AI added "ask AI to organize or rename files" in the plans list (per a pricing tracker dated 2026-10-26; low reliability).
- Price (unverified): $19/user/month (Q3 2025 earnings call). Current 2026 price not confirmed.
- Avoid: sending files to the cloud to be organized. Kanso is local-first and metadata-only.
- Adapt: batch rename proposals with a single review step ("Rename all" already does this).

**Sparkle (direct competitor, listed for reference)**
- What: AI tool that builds a folder structure for Desktop, Downloads and Documents, then sorts new arrivals. It is the Sparkle-style reference in AGENTS.md. Apple Intelligence or Finder integration was not confirmed.
- Relevance: the closest rival to Kanso's core promise. Differentiate on undo, Recents, Manual Shelves and local-only operation.

## Platform and Sherlocking risk

- **macOS 27 (Golden Gate), WWDC 2026:** Macworld reports that file and folder names will be suggested from their contents (unverified beyond that summary). This overlaps Kanso's renaming. Stacks and Apple Intelligence tab organization are other overlaps. Mitigation: keep renaming tied to meaningful names and undoable; do not compete on naming alone.
- **Apple Foundation Models:** Kanso already uses them, so Apple gains no new risk from its classifier. A system-wide "organize my folders" feature would be the real threat. Watch the macOS 27 release notes.

## Ranked list

| Rank | Verdict | Idea | Source tool | Reason | Effort |
|---|---|---|---|---|---|
| 1 | Adopt | Tray with explicit Organize | Dropover, Yoink | Already in CONTEXT.md; hold without deciding | M |
| 2 | Adopt | Saved views over shelves | Eagle smart folders | Filters without moving files; undoable | M |
| 3 | Adopt | Post-action card with Undo | CleanShot X | Makes undo visible and one tap | S |
| 4 | Adopt | "What would match" rule preview | Hazel | Earned trust before a rule runs | S |
| 5 | Adopt | Keeper suggestion with reason | Gemini 2 | Duplicates stay reviewed, never auto-deleted | S |
| 6 | Adapt | AI step in rules, existing types only, local | DEVONthink 4 | Matches the classifier and confidence rules | L |
| 7 | Adapt | Keyboard-first ask commands | Raycast, Alfred | Ask field already fits; add "Organize tray" | S |
| 8 | Adapt | Read-only space map | DaisyDisk | Visible value with no deletion | M |
| 9 | Adapt | Floating fallback with no notch | NotchNook, Droppy | Already planned as Below-the-notch | S |
| 10 | Adapt | Workflows for power rules | Alfred | Extends `[[rules]]` for advanced users | L |
| 11 | Avoid | Subscription or cloud AI tier | Raycast Pro, Dash, Gemini | Breaks local-first and pricing trust | - |
| 12 | Avoid | Widgets, media and clipboard in the island | NotchNook, Droppy | Outside the notices-only scope | - |
| 13 | Avoid | Auto-trash or "junk" one-click cleanup | CleanMyMac, Hazel | ADR 0002: only provably spent files | - |
| 14 | Avoid | Full asset library tagging | Eagle, Pixave | Goes beyond the agreed metadata scope | - |

## Sources

Verified in search results (figures marked unverified above):
- Dropover, Yoink, Unclutter: https://blog.eternalstorms.at/2025/11/04/yoink-for-mac-is-77-off-as-part-of-bundlehunts-2025-black-friday-macos-bundle/ ; https://www.ifun.de/dropover-fuer-mac-5-0-bessere-optik-und-flexiblere-ordnerueberwachung-249295/ ; https://www.macworld.com/article/554394/cyber-monday-mac-utility-bundle.html
- NotchNook: https://setapp.com/de/apps/notchnook ; https://www.appgefahren.de/notchnook-mac-app-erweitert-macbook-notch-zur-dynamic-island-363100.html
- Droppy: https://www.producthunt.com/products/droppy-4?launch=droppy-4 ; https://scour.ing/p/https://appaddict.app/post/droppy-a-notch-app-with-a-lot-to-like
- Hazel: https://www.asianefficiency.com/technology/hazel-intro/ ; https://www.noodlesoft.com/reviews/page/3/ ; https://alternativeto.net/software/hazel/?p=4
- Gemini 2: https://macpaw.com/gemini/upgrade ; https://apps.apple.com/app/id1090488118
- Raycast: https://raycast.com/blog/introducing-raycast-pro ; https://toolradar.com/tools/raycast/pricing
- Alfred: https://www.alfredapp.com/shop ; https://alfredapp.com/blog/announcements/alfred-5-licensing-faq
- Eagle: https://www.capterra.com/p/184384/Eagle/ ; https://community-en.eagle.cool/plugin/mcp-server ; https://geekchamp.com/products/eagle/
- Hookmark: https://hookproductivity.com/buy/ ; https://hookproductivity.com/help/features/
- DEVONthink 4: https://devontechnologies.com/apps/devonthink/new ; https://www.macstories.net/reviews/ai-adds-a-new-dimension-to-devonthink-4/ ; https://www.macsparky.com/blog/2025/06/devonthink-4-beta-ai-that-makes-sense-for-power-users-sponsor/
- CleanShot X: https://toolradar.com/tools/cleanshot/pricing ; https://gappsy.com/tools/cleanshot-x/
- DaisyDisk: https://daisydiskapp.com/support/pricing ; https://cleanmymac.com/blog/daisydisk-alternative
- Dropbox Dash: https://dash.dropbox.com/plans ; https://www.capterra.com/p/10023732/Dropbox-Dash/alternatives/ ; https://pricingsaas.com/companies/dropbox/diffs/2026W44 (low reliability)
- Sparkle: https://www.igeeksblog.com/organize-mac-with-sparkle-ai/ ; https://every.to/p/introducing-sparkle
- macOS 27 / WWDC 2026: https://www.macworld.com/article/3139330/macos-27-features-siri-apple-intelligence-release-compatibility.html ; https://iboysoft.com/tips/wwdc-2026.html

Not verified (no source found or from memory):
- Stacks behavior (general knowledge, not searched).
- Pixave (no data found).
- CleanMyMac current price.
- Dash 2026 price.
- macOS 27 file-naming feature details beyond one Macworld summary.
- Alfred file-search details.
