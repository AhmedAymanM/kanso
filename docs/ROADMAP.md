# Kanso roadmap

What ships, in what order, by when, and how we know it worked. Owned by Nova (CPO) with the Board; the Board approves every change.

- **What and why:** `PRODUCT.md` (Board). This file never adds scope; it schedules what `PRODUCT.md` decides. Where they disagree, `PRODUCT.md` wins and this file gets fixed.
- **Live status:** the Paperclip projects and milestones named below. Dates here are targets; a slipped milestone moves here in the same PR that explains why.
- Last updated 2026-10-09.

## 1. Releases

From `PRODUCT.md` §8. Only v1 has a date. Later releases are dated at the post-launch review (2027-01-03), once we know whether v1 earned trust.

| Release | Contents (summary of `PRODUCT.md` §8) | Target |
|---|---|---|
| **v1** | Swift app, By kind, renaming, dimension tags, duplicates, the island (⌥⌘K), Quick settings, Smart Eject, preview for Sort everything, onboarding, settings, local stats, Apple Intelligence + Kanso Local, Homebrew | **Public 2026-12-04** (P3 · M12) |
| **v1.1** | The ask field (macOS 26+, ADR 0001 rules, an evaluation set before shipping) | Not dated |
| **By purpose** | Content reading within the limits, adopting folder names, earned trust, status and reminder tags, per-folder profiles | Not dated. Blocked by the trust criterion in §4 |
| **v2** | The Tray, the full model picker, natural-language rules UI, suggested new shelves | Not dated |
| **Later** | Chat with your files (own opt-in), Mac App Store build | Not dated |

## 2. Projects and milestones (v1)

Four Paperclip projects. Each milestone is a parent issue labelled `milestone` whose children are single-seat tasks.

### P0 · Org foundation (target 2026-10-23)
The org chart becomes a real guardrail before the agents build the product. Guardrail infrastructure is Board-owned.

| Milestone | Due | Owner | Done when |
|---|---|---|---|
| **M1** Leadership docs tell the truth (KAN-9) | 2026-10-14 | Forge | `docs/ARCHITECTURE.md` and this file on `main`, Board-approved; `AGENTS.md` is a short command reference with no contradiction of `PRODUCT.md`; the company goal matches `PRODUCT.md` |
| **M2** Personas and hires (KAN-14) | 2026-10-09 | Forge | All 9 Build-phase seats exist with their v4.1 model, effort and manager; personas generated from `org/territory.yml` |
| **M3** Territories enforced (KAN-18) | 2026-10-20 | Forge | No agent can write outside its territory, push `main`, merge, or reach the Board's GitHub token (proven by M5) |
| **M4** Jev task gates (KAN-28) | 2026-10-22 | Forge | Jev checks every new task for seat fit, arch-required and readiness; ≥ 90% agreement with the Board on 30 labelled tasks |
| **M5** Red-team proof (KAN-31) | 2026-10-23 | Forge | For every seat, an instructed out-of-territory write is blocked at L2 and, if bypassed, at L3 |

### P2 · Market (target 2026-10-30)
Evidence for this roadmap and for the launch. Runs in parallel with P0.

| Milestone | Due | Owner | Done when |
|---|---|---|---|
| **M9** Market picture (KAN-49) | 2026-10-30 | Nova | Dated, sourced competitor matrix and threats/opportunities memo in `docs/research/` (Scout); Nova's positioning brief approved by the Board; `kanso.app` registered and trademark search done (Board) |

### P1 · Ship v1 (target 2026-11-20)
Make v1 releasable, then prove it on the owner's real folders.

| Milestone | Due | Owner | Done when |
|---|---|---|---|
| **M6** Release-ready app (KAN-33) | 2026-11-06 | Forge | String Catalog, a working Sparkle update check, real GitHub / Buy Me a Coffee links, and an engine with no known data-loss bug (Probe's safety audit closed) |
| **M7** Signed, notarized, installable (KAN-41) | 2026-11-13 | Forge | A Developer ID signed, notarized, stapled DMG from `scripts/release.sh` on the Board's Mac, installable from the Homebrew tap; Board decision on Kanso Local in v1 (KAN-45) |
| **M8** Dogfood gate (KAN-46) | 2026-11-20 | Forge | The launch gate in §4 is met |

### P3 · Launch (target 2026-12-04)
Going public. Pixel and Echo are hired at the start of this project.

| Milestone | Due | Owner | Done when |
|---|---|---|---|
| **M10** Launch team and OSS surface (KAN-54) | 2026-11-20 | Nova | Pixel and Echo hired; CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG and issue templates in the repo; GPL-3.0 `LICENSE` and the CLA in place before any outside contribution |
| **M11** Landing page and copy (KAN-58) | 2026-12-01 | Nova | `kanso-site` live with SEO basics; app copy humanized; at least one translation shipped through the String Catalog |
| **M12** Go public (KAN-64) | 2026-12-04 | Nova | The Board has made the launch decision; release published; announcement posted |

## 3. Timeline and critical path

```
Oct  09 M2 ─ 14 M1 ─ 20 M3 ─ 22 M4 ─ 23 M5            P0 Org foundation
            └──────────────────────── 30 M9            P2 Market (parallel)
Nov  06 M6 ─ 13 M7 ─ 20 M8 (dogfood 11-06 → 11-20)     P1 Ship v1
                     20 M10 ─ Dec 01 M11 ─ 04 M12      P3 Launch
```

The critical path is **M6 → dogfood → M12**. The dogfood needs 14 full days and M8 is due 2026-11-20, so it must **start on 2026-11-06 with the M6 build** (ad-hoc signed, from `app/build.sh`), not wait for the signed M7 DMG. Signing changes no behavior, so the M6 build is a fair test; the Board swaps to the signed build when M7 lands without restarting the clock. If M6 slips, the dogfood, M8 and launch slip day for day.

Launch-side work that doesn't wait for the gate: M9 positioning (feeds the landing page brief), M10 hires and OSS files, M11 site and copy. Only the M12 launch decision waits for M8.

## 4. Success criteria and who measures them

From `PRODUCT.md` §9. No telemetry exists, so every number comes from something we can observe.

### Launch gate (before M12)

| Criterion | Measured by | Source | When |
|---|---|---|---|
| The owner runs Swift v1 on their real Downloads, Desktop and Documents for **14 days** | Board (runs it) | Dates in the journal | 2026-11-06 → 2026-11-20 |
| **Undo rate under 5%** of automatic actions | Board runs `kanso-cli stats --undo-rate` (KAN-47); Probe checks the tool against a hand-counted journal | `journal.jsonl` | 2026-11-20 |
| No open "moved my file wrongly" bug | Probe | Paperclip / GitHub issues | 2026-11-20 |

Nova writes the go/no-go recommendation from these three; the Board decides (M12). A miss means a fix and a fresh 14 days, not a launch with an asterisk.

### After launch

Reviewed at **launch + 30 days, 2027-01-03**, by Nova with the Board. That review dates v1.1, By purpose and v2.

| Criterion | Target | Measured by | Source |
|---|---|---|---|
| **Retention** | ~60% of installs still checking for updates after 30 days | Nova, from data the Board pulls | Update-check fetch counts on the appcast host (host chosen in KAN-36 so fetches are countable) |
| **Trust** | Undo rate under 5% of automatic actions. Higher means fix it before building By purpose | Nova | Opt-in shared stats (see open question 1) |
| **Qualitative** | Of the first 20 GitHub issues and discussions, mostly feature requests rather than "it moved my file wrongly" | Nova (triage labels every one) | GitHub issues and discussions |
| **Value** | Buy Me a Coffee supporters; shared "your month with Kanso" stats | Board (owns the Buy Me a Coffee account) reports the count; Nova counts shared stats | Buy Me a Coffee dashboard; public posts (see open question 2) |

## 5. Open questions for the Board

1. **Opt-in shared stats don't exist in any milestone.** The post-launch trust criterion depends on them. Options: add a small v1 task (a "Share my stats" export the user sees before sending, in M6), or measure trust after launch from issues only until v1.1. Nova recommends the export: it is a few lines over the existing local stats and keeps the "no analytics" promise.
2. **"Your month with Kanso" sharing** isn't specified either. Same choice: fold it into the export above, or drop it from the value criterion until it exists.
3. **Kanso Local in v1** (KAN-45, due with M7). No model exists yet (`AGENTS.md`), while `PRODUCT.md` §8 lists it in v1. Deferring it means macOS 14–15 send unknown types to ❓ Unsorted; the v1 row in `PRODUCT.md` would need the Board's edit.
4. **Distribution scope of v1.** `PRODUCT.md` §2 says sandbox-compatible from day one with security-scoped bookmarks; those are still on the "not done" list in `AGENTS.md` and in no milestone. They matter for the Mac App Store build (Later), not for the direct download, so Nova proposes leaving them out of v1 explicitly.

## 6. Changing this file

Changes go through a PR on a `nova/KAN-<n>-…` branch and need Board approval. A milestone that slips gets its new date here and a one-line reason in the PR, so the dates stay honest.
