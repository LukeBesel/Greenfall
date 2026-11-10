# Greenfall: Planet 1 tasks

The work list for `docs/PLAN.md`. One row per task. **Kind** is LEAD (the lead does it) or DELEGATE (a subagent does it). A task is done only when its acceptance criteria pass, the code reviewer has approved it and the QA tester has run the suite. Status values: todo, doing, review, done. In progress now (Nov 10): M1-07.

Every milestone ends with the same gate (not repeated below): full test suite, save round trip, exit check, bot playthrough, engagement review, the dummy-planet reusability test, docs updated, a commit, and a short report to the owner.

Agents: architect (systems-architect-assistant), builder (systems-builder), save (save-engineer), tutorial (tutorial-designer), ui (ui-engineer), feel (game-feel-polisher), world (world-artist), balance (balance-analyst), engage (engagement-reviewer), perf (performance-engineer), qa (qa-tester), fixer (bug-fixer), review (code-reviewer), docs (docs-keeper), release (release-engineer).

## M1 Core redesign, stability, planet-agnostic architecture

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M1-01 | Bug triage on the merged build | qa | DELEGATE | `docs/PLAN.md` section 6, `tests/` | - | **Done (Nov 10), merged.** 5 confirmed with pending tests (B8, B23, B24, B25, B26), 1 already fixed, 2 not reproduced, 1 visual-only; report in `docs/reviews/TRIAGE_M1.md` |
| M1-02 | Design spec: districts, sources, mastery, rigs, Surge, the ending | lead | LEAD | `docs/design/PLANET1_DESIGN.md` | - | **Done (Nov 9).** Each mechanic has rules, data shape, numbers to tune and the events it emits; logged in DECISIONS |
| M1-03 | PlanetDefinition schema and `Planets` autoload | lead | LEAD | `core/planet_definition.gd`, `autoload/Planets.gd`, `planets/verdance/planet.tres` | - | **Done (Nov 9).** Typed resource covering every field in STYLE section 5; `Planets.current()` returns it; unit tests for load and validation errors |

| M1-04 | Remove the flat world | architect | DELEGATE | `scenes/slice.gd`, `planet/hex_field.gd`, `planet/city_*.gd`, `planet/frontier*.gd`, `planet/field_view.gd`, flat branches across the code | M1-01 | **Done (Nov 10), merged.** 11,816 lines removed, 37 files deleted, 948 tests pass. Review follow-ups in M1-04b |
| M1-04b | Review fixes for M1-04: leftover flat rocket path and its callers, HUD planet readout before sites exist, dead kept code, stale docs | architect | DELEGATE | `scenes/slice.gd`, `ui/frontier_rockets.gd`, `automation/rocket.gd`, `ui/hud.gd`, `planet/orbit/orbit_up.gd`, `player/camera_rig.gd` | M1-04 | No UI-reachable path references a removed member (test); suite and bot run clean. **Done (Nov 10), merged.** Removed the workbench Launch lists that crashed at base level 5; hub-to-hub travel at the parked rocket works; 953 tests pass |
| M1-05 | Split world assembly into `world/` builders | architect | DELEGATE | `scenes/slice.gd`, `scenes/slice_orbit.gd`, new `world/*.gd` | M1-04 | One assembler under 300 lines calling named builders in a documented order; no behaviour change (bot run milestones within 5% of before) |
| M1-06 | Move Verdance data and scripts to `planets/verdance/` | architect | DELEGATE | `data/*.json` (planet content), `planet/sites/verdance_site.gd`, `planet/sites/town_outskirts.gd`, `planet/sites/hinterland.gd`, `autoload/Economy.gd` | M1-03 | **Data done (Nov 10), merged.** 28 tables moved to `planets/verdance/data/`; 33 shared scripts read them through `Economy.planet_table`; caches reset when the planet changes; 958 tests pass. Verdance's site scripts move with M1-08 |
| M1-07 | Remove planet names and index branches from shared code | architect | DELEGATE | about 35 files listed by `grep -rl '"verdance"'` and `current_planet() == 0` | M1-06 | The grep for planet ids in shared folders returns nothing; restoration rule and ending come from the definition |
| M1-08 | Park later planets, travel layer, prestige mode and other cut features (R10) | architect | DELEGATE | `planet/planets/*`, `systems/homeward*.gd`, `systems/cradle_*.gd`, `systems/solar_system.gd`, `systems/heirloom_track.gd`, `ui/ark_bridge.gd`, related data and tests | M1-07 | **Done (Nov 10), merged.** 62 files (about 12,500 lines) in `parked/`, which the engine ignores; old saves with parked data load (fixture tests); the 68% cap is gone; 867 tests pass plus 7 pending bug tests. Later planets' environments move in M1-07 |
| M1-09 | Dummy test planet and reusability test | qa | DELEGATE | `tests/fixtures/planets/testworld/`, `tests/test_planet_reuse.gd` | M1-07 | The dummy planet loads, the bot plays 60 s, save/load round trips, with no change outside the fixture folder |
| M1-10 | Restoration model and ending hook (R1), logic only | builder | DELEGATE | `systems/restoration.gd`, `systems/bloom.gd`, `planets/verdance/data/restoration.json` | M1-02, M1-07 | Planet restoration is computed from district states by a data rule; reaching 100% emits `planet_restored`; no cap from other planets; unit tests |
| M1-11 | Fix confirmed P1 bugs (B2, B3, B4 and any found in triage) | fixer | DELEGATE | per bug | M1-01 | **Done (Nov 10), merged.** B8, B23, B24, B25, B26, B27, B29, B30, B31, B32 fixed, one commit and one regression test each; 881 tests pass, none pending |
| M1-12 | Fast balance simulator, first version (R12) | balance | DELEGATE | `tools/pace_sim/*`, `docs/PLANET_PLAYBOOK.md` | M1-06 | **Done (Nov 10), merged.** `tools/pace_sim`: 4 hours in 2.7 s; within 10% of the bot on 14 of 15 beats up to minute 70; baseline in `docs/reviews/PACING_BASELINE.md` (the current game fails 10 of 11 cadence checks) |
| M1-13 | All six designs match the owner's concept sheet (crescent or smiling eyes, never solid); one eye system; add-ons refitted to the new head. Animation polish is a later task | world | DELEGATE | `player/patch_model.gd`, `player/lumi_style_rig.gd`, `art/shaders/bot_face.gdshader`, `art/models/aurora/designs_addons.py` | - | **Parked at "pretty close" (owner, Nov 10), merged.** All six designs have their pieces, colours and eyes; add-ons refitted; one eye system; each piece separately wearable. Remaining differences are task M5-13 |
| M1-14 | Originality audit, pass 1 | review | DELEGATE | whole repo, `docs/ORIGINALITY.md` | - | Every mention of another game removed from code and data; a checklist of elements built "after" a reference (map, workbench, hub hall, terms) with a proposed change for each |
| M1-15 | Architecture doc rewrite | docs | DELEGATE | `docs/ARCHITECTURE.md` | M1-08 | Describes the target layout as built; old split plan removed |

## M2 Save and load

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M2-01 | Save schema v5 design: `global` + `planets.<id>` | lead | LEAD | `docs/design/SAVE_V5.md` | M1-07 | Every existing key is assigned to global or planet; migration rules written for v1-v4 and the globe schema |
| M2-02 | Implement v5 with migrations | save | DELEGATE | `autoload/SaveManager.gd`, `autoload/GameState.gd`, `core/save_*.gd` | M2-01 | Fixtures of every older format load and play; round trip passes; one save tree (the flat/round split is gone) |
| M2-03 | Atomic writes, rolling backup, corruption fallback | save | DELEGATE | `autoload/SaveManager.gd`, `tests/test_save_safety.gd` | M2-02 | Killing the process mid-write never loses the previous save; a truncated or garbled file loads the backup and tells the player |
| M2-04 | Exit-state save (B2) and autosave rules | save | DELEGATE | `autoload/SaveManager.gd`, `world/world_persistence.gd` | M2-02 | Quit at 20 random moments in a bot run and reload: state matches (positions, carried bale, crew zones, timers) |
| M2-05 | One profile plus backup; settings persistence check | save | DELEGATE | `systems/profile_slots.gd`, `ui/main_menu.gd`, `autoload/Settings.gd` | M2-02 | Three-profile UI removed; existing profile 1 migrates; settings survive restart |
| M2-06 | Save fuzz and long-run test | qa | DELEGATE | `tests/test_save_fuzz.gd`, `tools/save_soak.sh` | M2-03 | 500 random save/load cycles across a bot run with zero differences; dummy planet included |
| M2-07 | Steam Cloud path check | release | DELEGATE | `steam/steam_service.gd`, `docs/steam/` | M2-02 | Cloud file list matches the v5 layout; conflict rule documented |

## M3 Core loop, grind loops, progression, balance

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M3-01 | Balance targets and curves for all six districts | lead | LEAD | `planets/verdance/data/balance.json`, `docs/design/PLANET1_DESIGN.md` | M1-12 | Simulator meets every cadence rule on paper before any code changes |
| M3-02 | Faster hands (R3): start layout, hex sizes, first upgrades | builder | DELEGATE | `player/patch.gd`, `planets/verdance/data/*`, `planet/sites/yard_site.gd` | M3-01 | Bot: first clean hex under 2 min, then a hex at least every 2 min in the first 15; walking share of the first 10 minutes under 35% |
| M3-03 | Districts as chapters (R2): district state, order, unlock, travel | builder | DELEGATE | `systems/districts.gd`, `planet/sites/site_manager.gd`, `planets/verdance/data/districts.json` | M1-10 | Six districts unlock in order from data; each tracks its regrowth stage; the planet readout shows district progress, not a 4-decimal planet figure |
| M3-04 | Pollution kinds 2-5 as data-driven types with their tools | builder | DELEGATE | `systems/pollution.gd`, `planets/verdance/data/pollution.json`, existing lift, skimmer, recycler and planting code | M3-03 | Each kind has spawn rules, a tool gate, a payout and events; adding a kind needs data only (proved on the dummy planet) |
| M3-05 | Mastery and apprentice robots (R4) | builder | DELEGATE | `systems/mastery.gd`, `robots/sphere/sphere_crew.gd`, `robots/sphere/sphere_robot_kinds.gd` | M3-04 | Robots cannot work an unmastered kind; crew rate scales with mastery; hand share of output stays above 30% in the simulator and the bot |
| M3-06 | Work-driven research and tending (R5) | builder | DELEGATE | `systems/research.gd`, `plants/garden.gd`, planet data | M3-01 | No research or growth step requires idle waiting; offline bonus is capped by data |
| M3-07 | District sources: the Lumi-only capstone jobs | builder | DELEGATE | `systems/sources.gd`, `planets/verdance/sources/*.gd`, data | M3-03 | Each district has a multi-step source job that gates its last stage; all six are completable by the bot |
| M3-08 | Rigs (R6): three slots, modules, fitting at the bench | builder | DELEGATE | `systems/rigs.gd`, `player/patch_model.gd`, `planets/verdance/data/rigs.json` | M3-01 | At least 3 modules per slot with real trade-offs (simulator shows no module dominating all districts); fitted modules show on the model |
| M3-09 | Surge (R7) | builder | DELEGATE | `systems/surge.gd`, `story/core_charge.gd` | M3-05 | Charges only from active play; release at least doubles output for its duration; scales by district |
| M3-10 | Goals rebuilt as short/medium/long from data | builder | DELEGATE | `story/goals.gd`, `story/objectives.gd`, planet data | M3-03 | Always one of each tier active; no gap over 4 min in the bot run |
| M3-11 | Teach the bot the new loop | qa | DELEGATE | `tools/autoplay*.gd` | M3-03 to M3-09 | Bot plays start to ending headless; prints the cadence table; exits non-zero on a stall over 4 min |
| M3-12 | Balance pass 1 | balance | DELEGATE | planet data only | M3-11 | Simulator and bot agree within 15%; every cadence rule met; report lists each number changed and why |
| M3-14 | Looks from found pieces: piece list, find placement, remove counter and purchase unlocks | builder | DELEGATE | `data/cosmetics.json`, `planets/verdance/data/finds.json`, `systems/lumi_style.gd`, `systems/designs.gd`, `data/designs.json`, `data/style_parts.json` | M1-13, M3-03 | No look unlocks from a stat, level or cost; every piece has a find; bot run: first piece near minute 12 (bot time); only one new design (Sprout) can be completed on Planet 1 and not before the last district; the other four designs have no pieces on Planet 1; old saves keep what they had |
| M3-15 | Robot wrecks and buried cosmetic finds in the world | world | DELEGATE | `planets/verdance/finds/*.gd`, `story/interactables.gd`, detector | M3-14 | Wrecks in some districts, reachable (reach audit), recognisably the planet's design, plus at most one unsalvageable tease of a later design; found pieces play a reveal on Lumi |
| M3-16 | The Locker as a place: build, turntable, silhouettes and hints for unfound pieces | ui | DELEGATE | `ui/locker_panel.gd`, `ui/lumi_builder.gd`, `planet/sites/yard_site.gd`, `data/builds.json` | M3-14 | Offered after the first find; only found pieces can be worn; unfound pieces show as silhouettes with a hint; the only place looks are edited |
| M3-17 | World audit: what each of the ten hub sites and the land between them holds today (buildings, streets, junk density, landmarks), with renders, against design section 15; a plan for six full cities | world | DELEGATE | `docs/reviews/WORLD_AUDIT.md`, renders in `screenshots/world/` | M1-07 | Every site rated; gaps listed with the work to close each; no code changes |
| M3-18 | Six full cities under junk, each with its own character and source landmark; junk-covered land between | world | DELEGATE | `planets/verdance/sites/*`, `art/kit/*` | M3-17, M3-03 | Each city passes the audit checklist and the Low-preset budget; reach audit reports 0 unreachable targets |
| M3-19 | Economy scale and the three currencies' jobs (design section 14): small numbers, no reward bursts, no conversions, bin never beats bale | builder | DELEGATE | planet data, `autoload/Economy.gd`, goals and rewards code | M3-01 | Simulator: largest purchase under 50,000; no income jump over 3x; no reward over 3 minutes of income; parts waits within the cadence rules |
| M3-20 | Crew pacing: scarce early parts, two robot tiers, a paced climb to 100-200 robots by the launch point, a production queue for batch building, area zones, the Scrounger | builder | DELEGATE | `robots/*`, planet data | M3-05, M3-19 | Simulator and bot: first robot near minute 10 (bot), crew size by district as in the proposal (100-200 at the launch point); batch orders build over time; performance budget holds with 200 robots; the Scrounger finds and Lumi digs |
| M3-13 | Trim side systems to what Planet 1 uses | lead | LEAD | events, requests, collection, extras | M3-10 | Each kept system has a stated job in the loop; the rest are parked; logged in DECISIONS |

## M4 Tutorial and onboarding

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M4-01 | Tutorial step schema and runner | tutorial | DELEGATE | `systems/tutorial_runner.gd`, `planets/verdance/data/tutorial.json` | M3-10 | Steps have trigger, text, pointer, completion and skip rule; runner listens to events only |
| M4-02 | Author the Planet 1 steps (PLAN section 8) | tutorial | DELEGATE | `planets/verdance/data/tutorial.json` | M4-01 | Every system is taught at first need; each line under 12 words with a key glyph |
| M4-03 | Out-of-order safety | qa | DELEGATE | `tests/test_tutorial_order.gd` | M4-02 | 200 random action orders in a headless harness never stall the chain |
| M4-04 | Skip, replay, and contextual hints | tutorial | DELEGATE | `ui/pause_menu.gd`, `ui/settings_panel.gd`, runner | M4-01 | Skip from pause; replay from settings; "stuck" hints (chest full, cannot afford, too heavy) appear after 20 s of no progress |
| M4-05 | Pointers that lead only to reachable places | tutorial | DELEGATE | `story/waypoint.gd`, `planet/sites/target_reach.gd` | M4-02 | Reach audit reports 0 unreachable targets across all six districts |
| M4-06 | First-15-minutes review | engage | DELEGATE | report in `docs/reviews/` | M4-02 | Clarity log shows one instruction at a time and no instruction for a locked ability |

## M5 Original UI, game feel, the ending

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M5-01 | UI identity spec and theme | lead | LEAD | `docs/design/UI_SPEC.md`, `ui/theme/` | M1-14 | Mock-ups (rendered) of HUD, workbench, map and pause in the field-instrument style; passes the originality checklist |
| M5-02 | HUD rebuild | ui | DELEGATE | `ui/hud.gd`, `ui/objective_card.gd`, `ui/currency_cluster.gd` and widgets | M5-01 | Three-tier goal readout, one message line, diegetic chest gauge; five aspect ratios; controller focus |
| M5-03 | Workbench rebuild (own layout) | ui | DELEGATE | `ui/upgrades_screen.gd`, `ui/workbench*.gd` | M5-01 | Tracks, rigs, crew and build in one layout of our own; shows "loads until affordable" |
| M5-04 | Map view rebuild (own style) | ui | DELEGATE | `ui/globe_view.gd` and related | M5-01 | District states readable at a glance; no element shared with the old view |
| M5-05 | Menus, settings, pause, end screen | ui | DELEGATE | `ui/main_menu.gd`, `ui/settings_panel.gd`, `ui/pause_menu.gd`, `ui/end_screen.gd` | M5-01 | Same identity; settings persist; end-of-demo screen with stats and the hook |
| M5-06 | Core-action feedback pass (F1, F2) | feel | DELEGATE | `player/pickup_fx.gd`, `art/vfx.gd`, `autoload/Audio.gd` | M3-02 | Every core action has sound, motion and number within 100 ms; rising pitch on chest fill |
| M5-07 | Escalating cleanup and regrowth effects (F9) | feel | DELEGATE | `art/vfx.gd`, `planet/sphere/sphere_ground.gdshader`, regrowth views | M3-03 | Hex-clear effect has at least four tiers tied to progress; stage changes are visible from 30 m |
| M5-08 | The Bloom: planet-restored finale | feel | DELEGATE | `story/bloom_finale.gd`, sky, audio | M1-10 | A 60-90 s sequence where green sweeps the globe; skippable; ends on the end screen |
| M5-09 | World art pass on the six districts | world | DELEGATE | `planets/verdance/*`, `art/kit/*` | M3-03 | Each district has its own look for polluted and restored states; open visual bugs B11, B13, B18, B19 closed |
| M5-10 | Lumi's visible repair stages and rig models | world | DELEGATE | `art/models/aurora/*`, `player/patch_model.gd` | M3-08 | Lumi's wear steps from wrecked to restored with progress; each rig module has a model |
| M5-11 | Sound replacement plan and hooks | feel | DELEGATE | `docs/AUDIO.md`, `autoload/Audio.gd` | M5-06 | Every event has a named hook; list of sounds that need recorded or licensed replacements |
| M5-13 | Design polish pass 2 (when the owner returns to character design): wide low pill head and wide visor as in the six portraits, slim crescent-ring eyes, chunkier torso with longer arms and bigger claws, heavier chips and grime, Pixel's crest shape, Nova's glowing torso seams, Patch's satchel at the hip, bigger Sprout leaves; then animation that makes sense | world | DELEGATE | `art/models/aurora/*`, `player/patch_model.gd`, `art/shaders/*` | M1-13 | Side-by-side sheet against `art/concept/lumi_concept.png` with every listed difference closed or explained |
| M5-12 | Originality audit, pass 2 | review | DELEGATE | `docs/ORIGINALITY.md` | M5-02 to M5-05 | Checklist passes for all rebuilt UI |

## M6 Engagement pass

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M6-01 | Full engagement review, start to ending | engage | DELEGATE | `docs/reviews/ENGAGEMENT_1.md` | M5 | Timeline of every stretch over 3 min without a win, every confusing moment, every unrewarded grind, mapped to pillars |
| M6-02 | Decide fixes for every flagged stretch | lead | LEAD | `docs/DECISIONS.md`, TASKS | M6-01 | Each flag has a fix, a cut or a written reason to keep |
| M6-03 | Implement the fixes | builder, feel, ui | DELEGATE | per fix | M6-02 | Each fix verified by a bot or simulator metric |
| M6-04 | Balance pass 2 | balance | DELEGATE | planet data | M6-03 | All cadence rules met; playtime in range |
| M6-05 | Secrets and depth pass | builder | DELEGATE | finds, mastery extras, optional sites | M6-03 | At least 8 hours of optional goals for completionists without touching the main path's pace |
| M6-06 | Second engagement review | engage | DELEGATE | `docs/reviews/ENGAGEMENT_2.md` | M6-04 | No flags above "minor" |

## M7 Performance

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M7-01 | Budgets and capture tooling | perf | DELEGATE | `docs/PERFORMANCE.md`, `tools/perf_capture.sh` | M6 | Per-preset budgets for frame time, draw calls, memory and load; one-command capture the owner can run on real hardware |
| M7-02 | Hot-path fixes | perf | DELEGATE | per profile | M7-01 | Headless script time per frame under 2 ms with a full crew; items from ARCHITECTURE "perf candidates" closed |
| M7-03 | Streaming, loading and shader warm-up | perf | DELEGATE | `planet/sphere/sphere_streamer.gd`, `ui/loading_screen.gd`, `systems/shader_warmup.gd` | M7-01 | Load under 10 s; no frame over 100 ms in a 30-min bot run |
| M7-04 | Pooling and long-session stability | perf | DELEGATE | vfx, fauna, bales, robots | M7-01 | 4-hour soak: memory growth under 5%, no leaked nodes |
| M7-05 | Physics tick rate decision | lead | LEAD | `project.godot` | M7-01 | 60 or 120 chosen with measurements; logged |
| M7-06 | Low-preset pass (B17) | perf | DELEGATE | litter, junk LOD | M7-01 | Low preset meets its budget |

## M8 Demo release prep

| ID | Title | Owner | Kind | Files | Depends | Acceptance |
|---|---|---|---|---|---|---|
| M8-01 | Export presets and CI for the demo | release | DELEGATE | `export_presets.cfg`, `.github/workflows/build.yml` | M7 | Windows, Linux and macOS demo builds from CI; parked content excluded |
| M8-02 | Version display, credits, licences | release | DELEGATE | `ui/main_menu.gd`, `docs/CREDITS.md` | M8-01 | Version on title and pause; credits complete for every asset |
| M8-03 | Steam demo config | release | DELEGATE | `steam/*`, `docs/steam/` | M8-01 | Demo app settings, achievements subset, cloud paths documented; runs without Steam |
| M8-04 | Localisation sweep | docs | DELEGATE | `locale/*` | M6 | No untranslated string in the audit for shipped languages, or languages cut to those that are complete |
| M8-05 | Full regression and release checklist | qa | DELEGATE | `docs/RELEASE_CHECKLIST.md` | M8-01 | Every Definition of Done box ticked with evidence |
| M8-06 | Originality audit, final | review | DELEGATE | `docs/ORIGINALITY.md` | M8-05 | Signed-off checklist |
| M8-07 | Finalise the playbook and templates | lead | LEAD | `docs/PLANET_PLAYBOOK.md`, `planets/_template/` | M8-05 | A new planet can be started by copying the template and following the steps |
| M8-08 | Final report | lead | LEAD | `docs/PROGRESS.md` | all | What shipped, what was cut, what is next |
