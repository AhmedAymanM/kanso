# Engineering panel review (2026-10-30)

Read-only review on Linux (no Swift toolchain): "verify" means `swift test` on macOS.

## Findings

**BLOCKER 1. No Settings version and no migration.** `Settings.init(from:)` is a hand-written list of ~60 `d(.key,&key)` lines. Any new field not added there is silently never loaded, and decoding fails soft with no signal. There is no `schemaVersion`. Every candidate below adds fields, so first add a `version` plus a test that round-trips an old-version JSON fixture and asserts every property is decoded (reflection or a Mirror count check).

**BLOCKER 2. Per-folder settings have nowhere to live.** `Engine.s` is one global `Settings`; `candidates`, `decide` and `plan` read `s.rules`, `s.types` and `s.sortFolders` directly, and `roots` is `[String]`. Per-folder overrides need `RootConfig` keyed by path, with `Engine.settings(for: root)` threaded into `decide`. `decide(_ item)` takes no root today.

**MAJOR 3. `Classifier` is too narrow for a model picker.** `choose(facts:options:creating:)` returns a `Pick`. Nothing covers rule parsing, ask, or rename (`Ask.swift` uses FoundationModels directly). `appleIntelligence: Bool` is the only switch. BYOK needs `Provider` settings, Keychain storage, async network, timeouts and privacy gating. AGENTS.md says metadata-only and "cloud strictly opt-in". Also `Engine.init` defaults to `AppleIntelligence()`, so tests inject via the init and `FakeAI` is per-file; share one `FakeClassifier` in a test-support target.

**MAJOR 4. AppModel is a god object.** 544 lines, 14 `@Published`, 40 pass-through methods that all end with `refresh()`. Every new feature adds more. The undo card, saved views and Tray each need state; put them in separate `ObservableObject`s owned by AppModel rather than adding fields. Untestable by `swift test` since `Kanso` is an executable target; logic must go in KansoCore.

**MAJOR 5. Rule model is positional first-match with a closed `Field` enum.** Plain-English rules must compile to `Condition`s (deterministic, previewable) rather than evaluating a model per file; otherwise the rules path becomes nondeterministic and slow and breaks "extension table decides with no model". Adding `Field` cases is safe (Codable enum decode of unknown case throws, and `Rule` uses `LossyArray`, so an older build drops the rule: a downgrade risk to note). Rule order matters; "first match wins" must be shown in the preview.

**MAJOR 6. Test seams.** `plan(now:)` is injectable; `Stat`/`Tags` hit real disk (temp dirs, fine). The Tray needs bookmark resolution that can fail.

**MINOR 7.** `Engine` is `@unchecked Sendable` with `var s` read across tasks; per-root config must not widen unlocked reads. Island `actions()` is the one place for the undo card; new model-driven actions fall under ADR 0001.

## Candidates

| Candidate | Fit | Prerequisite | Risk | Size | Auto-verifiable |
|---|---|---|---|---|---|
| Excludes + per-folder settings | Medium | Blocker 1, 2 | Behaviour change in `candidates`; defaults must be identical | M-L | Yes: temp-dir tests |
| Plain-English rules | Needs Classifier extension | Rule compiler, Blocker 1 | Model gives wrong conditions; macOS 26 only | M | Compiler with fake model yes; quality no |
| Rule preview | Excellent: `plan(all:)` is pure | None (dry run of one rule over candidates) | Cost on large folders | S | Yes |
| Saved views | Activity filter state | Codable filter struct in Settings | Low | S | Partly: predicate yes, UI no |
| Post-action undo card | Island `actions()` + `undoLast` | None | Focus stealing, Return rule | S | Logic yes, UI snapshot only |
| Duplicate keeper reason | `keeperOrder` + `details["kept"]` | Return a reason string | Low | S | Yes |
| Suggested shelves | `Learning` + `suggestTypes` exist | Count unknown-ext frequency | Noise | S-M | Yes with fake classifier |
| Model picker + BYOK | Needs Classifier v2 | Blocker 1, privacy copy, Keychain | Largest: privacy policy, network, ADR | L | Protocol and fakes yes; Keychain/network no |
| Tray | New subsystem, island page | Island page routing, bookmarks, Links/Notes types | L, owner decisions open | L | Store and plan yes; drag UI no |

Do tonight: rule preview, keeper reason, undo card, saved views, excludes (global, not per folder). Defer BYOK and Tray.

## Sequence of mergeable PRs

1. `chore/settings-version`: `Settings.swift`, `StoreTests.swift` (version field, old-fixture round-trip, completeness test).
2. `chore/test-support`: `Package.swift`, new `Tests/Support/FakeClassifier.swift`, `EngineTests.swift`.
3. `feat/keeper-reason`: `Engine.swift`, `ActivityDetail.swift`, `EngineTests.swift`.
4. `feat/rule-preview`: `Engine.swift` (`previewRule`), `RulesView` (Sorting page), `EngineTests.swift`.
5. `feat/excludes`: `Settings.swift` (`excluded: [String]` globs), `Engine.swift` (`ignored`), Sorting page, tests.
6. `feat/undo-card`: `Island.swift`, `AppModel.swift`.
7. `feat/saved-views`: `Settings.swift`, `ActivityPage.swift`, `ActivityFilterBar`.
8. `refactor/per-root-config`: `RootConfig`, `Engine.settings(for:)`, Folders UI. Then `feat/plain-rules` after `refactor/classifier-v2`.
