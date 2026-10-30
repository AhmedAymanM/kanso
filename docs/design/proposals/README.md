# Kanso design proposals (2026-10-30)

Three design directions for the Swift app, a Tray design, six references and an audit of what is not yet polished. Nothing here changes code. Mockups are throwaway HTML (inline CSS, no external assets); open them in a browser and use the Light / Dark button.

| File | What |
|---|---|
| [proposal-a.md](proposal-a.md) / [proposal-a.html](proposal-a.html) | **A · Paper & Ink**: evolve today's identity |
| [proposal-b.md](proposal-b.md) / [proposal-b.html](proposal-b.html) | **B · Glass Shelf**: Liquid Glass forward |
| [proposal-c.md](proposal-c.md) / [proposal-c.html](proposal-c.html) | **C · Ink Notch**: the island is the product, the window is a ledger |
| [tray.md](tray.md) | The Tray (roadmap v2, files only): drag detection, flows, states, keyboard, accessibility, security invariants, ADR fit |
| [final-direction.md](final-direction.md) | **The decision**: A as base, exact tokens mapped to `Theme.swift`, motion values, ordered change list |

**Recommendation: A as the base, with B's material rules and C's mono-for-paths detail.** The concrete version is [final-direction.md](final-direction.md). The proposals were revised after the panel reviews (see `docs/research/panel/`): the island and Tray now differ per direction and use the real two-row structure, B's glass morph is cut and its window rejected, and every text token is measured against WCAG.

## How the references were found (honest note)

The Awwwards MCP server (`/tmp/tmp.eymAdd0Zi8/repo`, built with `npm ci --ignore-scripts` + `npm run build`, driven by `/tmp/awwwards-client/client.mjs`) **starts and answers**, but it fits this job poorly:

- Its local index held 31 sites (the full crawl was not run on this 4 GB box). Free-text `search_sites` queries ("mac app", "productivity app", "file manager") returned nothing; only tag/award filters work live (`app-style`, `mobile-apps`, `technology`, `minimal`, `clean`).
- Tag searches return mostly portfolios and agencies. Awwwards indexes **websites**, and almost no real Mac utilities are on it (Raycast, Linear, Things, CleanShot, Craft and Cron have no entries; name collisions such as "Craft" the jet charter or "Arc" the timber builder appeared instead).
- `get_site_details` and `get_site_elements` worked (scores, award dates, element video links). Playwright tools (`capture_live_site`, motion capture) were **not** used: no browser installed, and 4 GB RAM.
- So the shortlist came from the MCP (`app-style` tag, `get_site_details`) **plus WebSearch/WebFetch of awwwards.com pages**. Palettes are the coarse hex lists Awwwards publishes; Awwwards pages give **no font names**, and live sites have changed since they won (Taskade is now pink/Comfortaa; Hyperfocus's site did not respond to curl). Where type/motion is inferred from tags, tooling (Lottie, Three.js, GSAP) or the dev-award sub-scores, it says so.

These are sites **of apps**, reviewed for principles only. No assets are copied or embedded in this repo.

## The six references

### 1. Superlist (productivity app, by GC Studio, Unseen Studio)
- Link: https://www.awwwards.com/sites/superlist · live: https://superlist.craftedbygc.com/
- Award: **Site of the Day (19 Apr 2021), Site of the Month (Apr 2021)**; overall 7.84 (design 7.98); dev award animations/transitions **9.0**.
- Palette (Awwwards): black, white and one warm red (`#D14836`); the page text uses a mid grey (`#646464`) on near-white.
- Type: not published. Tags say Clean, Illustration; the face is not confirmed (the live page's CSS did not expose a font-family in a quick curl), so assume a restrained grotesk.
- Motion: Three.js 3D objects and a "notification button" microinteraction plus a smooth loading transition (the two element videos Awwwards catalogues). Highest-scored aspect is transitions.
- Layout: single column, one idea per screen, generous empty space; the product is shown as one object, not a dashboard.
- Why it feels premium: restraint. A 3-colour palette, almost no chrome, and motion used for a single moment of delight (the notification), not everywhere.
- **Lesson for Kanso:** spend the accent colour and the motion budget on the one moment that matters (the "needs you" arrival), and keep everything else still. Kanso's Overview uses six hues and a looping illustration on every page; Superlist shows that one accent plus one animated moment reads as more expensive.

### 2. Butter (video editor for creatives, ToyFight)
- Link: https://www.awwwards.com/sites/butter · live: https://www.butter.video/
- Award: **Site of the Day (28 Sep 2026), Developer Award**; overall 7.5; animations/transitions 8.2.
- Palette (Awwwards): charcoal `#1E1E1E`, off-white `#F7F7F7` (also `#404040`, `#F3F2F2`). Live CSS adds a light cyan `#4DC5E5`, butter yellow `#E9D352` and green `#63AD45` as tool-colour accents.
- Type: live CSS uses DieGrotesk (display) and ABC Diatype (UI) (found in the page's `font-family`). A neo-grotesk pair, no serif.
- Motion: WebGL + p5.js filters; the timeline element is the hero and moves as the product would.
- Layout: App Style: real product UI at actual size, neutral shell with small pops of tool colour.
- Why it feels premium: the neutral shell lets small coloured tools read as objects, and the UI shown is the real UI.
- **Lesson:** colour belongs to *things* (tools, file types), the shell stays neutral. Kanso's pastel tints should mark a shelf or action type and nothing else, so the Overview's four coloured counter tiles become one quiet line.

### 3. Hyperfocus for macOS (focus/health menu bar app)
- Link: https://www.awwwards.com/sites/hyperfocus-for-macos · live: http://hyperfocus.health
- Award: **Honorable Mention (23 Feb 2023)**.
- Palette (Awwwards): deep blue-black `#1D1D24`, `#0E0E15`.
- Type: not published (tags: Clean, Minimal).
- Motion: parallax and transitions (tags); a "main feature interaction" and a plus-features video gallery.
- Layout: big background imagery, a manifesto page and an academic-research page next to the product, the app sells *why*, with evidence.
- Why it feels premium: it is the closest Mac-native utility tone in the set: dark, quiet, and it explains its restraint in words.
- **Lesson:** state the principle. Kanso's "Your files never leave your Mac" line is tiny, at the bottom of the sidebar. A calm tool earns trust by saying what it will not do, in the place users look (Privacy page, onboarding, Tray empty state).

### 4. Taskade (organization / tasks / notes tool)
- Link: https://www.awwwards.com/sites/taskade · live: https://www.taskade.com
- Award: **Honorable Mention (15 Apr 2020)**.
- Palette (Awwwards): soft coral `#FF9398`, warm yellow `#ECD06F`; tags Clean, Colorful, Minimal. (The live site has since moved to a stronger pink.)
- Type: not published; the live site uses Comfortaa, a rounded face (not recommended for Kanso).
- Motion: no evidence recorded (interaction design tag only).
- Layout: the app UI is the hero; tasks, notes and chat on one page.
- Why it feels premium: warm pastel pair on white, nothing else.
- **Lesson:** two pastels are enough. Kanso's mint + butter carry the whole product; periwinkle, lavender and aqua can be demoted to icon strokes only.

### 5. Haptic (action-based journal)
- Link: https://www.awwwards.com/sites/haptic-app · live: https://haptic.app/
- Award: **Honorable Mention (10 Sep 2020)**.
- Palette (Awwwards): pure black (and `#404040`).
- Type: not published; tags Graphic design, UI design, Microinteractions.
- Motion: microinteraction-led (tag).
- Layout: a single device, one screen at a time, high contrast.
- Why it feels premium: one decision per screen; black and white make the tiny interactions the content.
- **Lesson:** one card, one decision. Kanso already does this on the island (one needs-you card at a time); the window should too: the Overview shows one Needs-you card and a calm "nothing" state, not an empty card taking two thirds of the width.

### 6. Protagonist (reading app for literary magazines)
- Link: https://www.awwwards.com/sites/protagonist · live: https://www.protagonist.app
- Award: **Honorable Mention (5 May 2021)**.
- Palette (Awwwards): black, white, red `#D14836` (the page shares this palette block with Superlist, so treat it as approximate).
- Type: not published; an editorial reading app, so a serif/sans pairing is likely (inferred).
- Motion: Lottie + After Effects illustrations; tags Storytelling, Motion.
- Layout: text-led storytelling, Unusual Navigation.
- Why it feels premium: editorial voice. Words are set like a magazine, with illustration as punctuation.
- **Lesson:** Kanso's serif ("Your Mac is in order.") is its strongest identity cue but appears only on Overview. Use the serif for statements and numerals everywhere a sentence is the headline, and SF for everything you operate. Illustrations (Lottie-style) are punctuation, not wallpaper.

Not adopted: Cerebrium (SOTD Sep 2026, dev tool) and Pluto (SOTD Aug 2021, spatial computing) were looked at; both are service sites with immersive scroll that does not translate to a calm utility.

## Principles drawn from the references

1. **One accent, one moment.** Spend colour and motion where the user is needed (Superlist, Haptic).
2. **Neutral shell, coloured things.** Tints identify file types and action kinds; surfaces stay neutral (Butter, Taskade).
3. **One card, one decision.** Never show an empty card as large as a full one (Haptic).
4. **State the promise in the product.** Privacy and "never deletes" are features; show them where trust is decided (Hyperfocus).
5. **Editorial voice for sentences, system type for controls** (Protagonist).
6. **Show the real UI at real size.** No decorative dashboards (Butter).
7. **Motion is quiet and settles.** One transition that ends, no loops after 15 s (Kanso's own rule; Superlist's transitions scored highest because they resolve cleanly).

Website ideas that do **not** transfer: scroll-jacking, WebGL heroes, custom cursors, full-bleed imagery, anything that animates while the user is not looking. Kanso is a window and an island, not a page.

## Audit: where the current app is not yet polished

From `docs/assets/*.png` and `app/Sources/Kanso/Theme.swift`. Specific, in rough priority order.

**Overview (`overview.png`, `OverviewPage.swift`)**
1. The empty "Needs you" card takes about two thirds of the top row to say "Nothing needs you". The empty state is the common state, so the biggest card is usually the least useful. Make it collapse to one line, or give the width to the month chart.
2. The four pastel counter tiles (periwinkle, aqua, butter, mint) sit at slightly different vertical positions (tile tops about 1035 / 1030 / 1028 / 1030 px in the 1888 px screenshot), and the numerals' baselines differ. Four hues at the bottom compete with the mint hero; "0 Installers ejected" is a stat that does nothing. Collapse to one quiet row of counts (A and C do) or tint only the one that has news.
3. The month chart draws about 25 empty "future" bars across the width; the used days are black and today is green, so the eye reads black blocks as the key data. Show only elapsed days; use ink for past, accent for today.
4. "KEPT IN ORDER" is dim grey-green on dark green with a diagonal hatch pattern behind: low contrast and noisy for the hero. Check against 4.5:1 and remove the hatch.
5. "Where files went" uses system emoji at 22 px next to 13 pt text; the Documents emoji renders as a grey file glyph that looks disabled next to coloured neighbours.

**Activity (`activity.png`, `ActivityPage/Detail/Parts.swift`)**
6. The list groups are out of order: TODAY, 1. OCTOBER, 3. OCTOBER, YESTERDAY. Date labels also mix "1. OCTOBER" (header) with "1. Oct" (row) and "Yesterday". Sort groups newest first and use one date format (the sandbox data may explain it; the ordering bug is still real).
7. Every row thumbnail is the same generic grey page icon; sorted-batch rows all show the same cardboard box and "Sorted into N shelves". Rows are indistinguishable at a glance; use the file's Quick Look icon and the destination shelf emoji.
8. The detail pane ends at about 55% height with a dead area, and a section titled "Don't rename files like this" has no body (an orphan heading). Remove or give it its control.
9. Sidebar selection is flat grey while `Theme.swift` declares mint as the selection colour (`accentSoft`): two selection languages (sidebar grey, Activity filter white pill, Overview mint).

**Sorting (`sorting.png`, `FeaturePages.swift`)**
10. The illustration banner is about 260 px tall and pushes the real controls below the first screenful; the Approach cards are cropped at the bottom edge.
11. Three greens fight: mint banner, dark green hero (Overview), and the system switch green (`K.switchOn` `#34C759`). Native switches are right for macOS; make the banner and hero use the same mint ink so the app has two greens at most (brand + system).
12. Watched-folder icons are the macOS 3D folder icons while the sidebar uses thin line symbols and the rest uses flat emoji: three icon styles on one page.
13. "Downloads → ✨ My Shelves → Documents" is set in a monospace chip while everything else is SF/serif: a fourth type voice. (C embraces mono deliberately; A and B should not use it.)

**Island (`island-*.png`, `Island.swift`, `IslandViews.swift`)**
14. (Cause found: the notch skin leaves only 38 pt beside the cutout at width `notch + 110`; final-direction widens it to `notch + 140`.) In the compact island the shortcut chip is truncated to "⌥..." in three of four states; in the expanded card "Extra copy · 120 MB · id..." is truncated. Truncating a shortcut is a bug; drop the chip to icon-only after the first dwell.
15. **Owner call, not a defect.** The bottom of the expanded island melts into glass ("ears melting into glass", Droppy-style): a recorded owner decision in AGENTS.md. The smudge under the ask field and the low contrast of "esc to close" are real: confine the melt to the last 12 pt and keep the esc row on solid black. The clean edge with a 0.5 px highlight is only a proposal for the owner.
16. Both thumbnails in the duplicates card are identical white page glyphs, so the "Kept" vs "Extra copy" distinction relies on 11 pt grey captions.
17. In the compact states the icon sits left, the text is centred and the chip right: three alignment axes in 360 px. Left-align icon + text, keep the chip at the far right.

**Quick settings (`quick-settings.png`, `QuickSettings.swift`)**
18. Off tile ("Tagging", flat grey with grey "Off") has low contrast and reads as disabled, not as a choice; the on/off cue is only a dot (filled vs hollow). Add a text weight or glyph change.
19. The tile grid has unequal gutters (about 18 px between columns vs about 20 px between rows in the screenshot) and the "Sorting" row is a different shape from the tiles. Pick a 12 pt grid and use it.

**System-level (code)**
20. `TS` has 13 type sizes (10 to 52). A scale this large invites one-off sizes; collapse to 8 (see each proposal).
21. The serif is used for Overview headline and numerals, Quick settings wordmark, and the Sorting banner, but not for the Activity headline or page titles: identity is inconsistent.
22. Tints: five pastel pairs plus mint plus system green plus black plus white in the hero. `Tint.of(Action)` ties colour to action kind, which is right; the Overview then uses the same colours for four counters, which dilutes the meaning.
23. Motion: `Motion.spring(0.35)` is the only token. There are no duration or curve tokens for the island grow, the stagger, or hover; illustrations loop (stopped after 15 s, good) but no rule says where else motion may appear.
24. `GlassSurface` radius defaults to 26 for every floating surface (popover, island panel); concentric radii (inner = outer minus padding) are not enforced, so inner buttons look slightly off the container curve.

## Recommended direction

**A (Paper & Ink), upgraded with two ideas.**

- It is the smallest change to `Theme.swift` and the only one that keeps what is already distinctive (serif statements, warm paper, mint ink), so users and the existing design handoff keep working.
- It answers most of the audit directly (empty state, counters, chart, type scale, tints, selection, icon style).
- Take **B's rule** for materials: solid surfaces in the window; Liquid Glass only for things that float (island capsule, popover, Tray lip, toolbar). This is also what the `GlassSurface` code already does.
- Take **C's rule** for the activity feed: paths and counts in a monospace *inside the Activity detail only*, because that is where users verify what happened.
- B alone makes the window a glass showcase (heavier, harder on Reduce Transparency, repeats the "Liquid Glass wallpaper" look of every other macOS 26 app). C alone is dark-led and technical and changes the product's tone from calm to precise; it would need new onboarding copy and a new icon language.

Open questions for the owner: whether Overview may drop the four counters entirely (A keeps them as one line); whether the Activity list may move to a mono path line (C); and whether the Tray's snippets are stored (see `tray.md`).
