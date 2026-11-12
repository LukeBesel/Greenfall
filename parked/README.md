# Parked features

Systems Planet 1 does not need, kept for later planets (task M1-08, `docs/PLAN.md` R10; the side
systems of task M3-13 in `side/` and `extras/nursery/`). The
`.gdignore` file in this folder makes Godot skip everything here: nothing is imported, parsed,
run or exported, and every export preset excludes `parked/*` as well. Nothing outside this folder
refers to a class or data file in it.

What "parked" means here:
- The files were moved with `git mv`, so `git log --follow` shows their history.
- They are as they were on the day they left the game (commit `b928ead` plus the M1-08 commits;
  for the M3-13 side systems, commit `e8c19d9` plus the M3-13 commits).
  They are not compiled, so they drift: expect to fix call sites when one comes back.
- Code that other files called was removed from those files. Small pieces of shared files that
  only served a parked feature were cut out and saved here as snippets (named below). For every
  other removed call site, read `git diff b928ead..HEAD -- . ':(exclude)parked'` of the M1-08 branch
  (M3-13: `git diff e8c19d9..<its last commit> -- . ':(exclude)parked'`).
- Tests of parked features are in `parked/tests/`. They do not run.

Bringing a feature back: move its files out of `parked/` to the paths in the tables, put the
snippets back, run `godot --headless --import --path .`, restore its call sites, move its tests to
`tests/`, take its stats off `data/parked.json`, and restore its achievements from
`achievements_parked.json`. A later planet must come back through its `PlanetDefinition`
(`docs/STYLE.md` section 3), not through the old planet-index code in these files.

## campaign/ : the five-planet campaign and the travel layer

What it did: after Verdance, the rocket's interplanetary drive (Mk V to Mk VII) opened four more
planets in a fixed order. Each planet was its own world in its own save slot. Restoring all five
let Lumi build the Homeward rocket and fly up to the Cradle for the true ending.

| File | Was at | What it is |
|---|---|---|
| `homeward.gd`, `homeward.json` | `systems/`, `data/` | Campaign rules and state: planet order, restoration per planet, drive tiers, tech found on later planets, relics, travel between worlds |
| `homeward_director.gd` | `systems/` | Puts the campaign in a world: the map, the launch, the arrival, story beats |
| `system_map.gd` | `ui/` | The solar-system map (view and travel mode) |
| `homecoming.gd`, `cradle_answers.gd`, `system_props.gd` | `story/` | The two campaign cinematics and their props |
| `world_look.gd`, `world_looks.json`, `world_look_view.gd`, `sky_body.gd`, `world_landmark.gd` | `systems/`, `data/`, `planet/` | The look of a world other than Verdance: sky grade, a body in the sky, city tint, yard dressing, a landmark |
| `world_story.gd` | `systems/` | WREN's story lines for other worlds |
| `world_banner.gd` | `ui/` | The arrival card of a new world |
| `late_director.gd` | `systems/` | Wired the post-game layer into a world. Its Garden Mode part lives on as `systems/garden_director.gd` |
| `autoplay_home.gd` | `tools/` | The bot's campaign layer |
| `hub_hop_interplanet.gd` | snippet of `planet/sites/hub_hop.gd` | The rocket's interplanet departure and arrival legs |
| `orbit_sites_travel.gd` | snippet of `planet/sites/orbit_sites.gd` | Launch to a planet, launch home, arrival, the rocket list's planet wiring, dev hooks |
| `telescope/` | `automation/telescope.gd`, `ui/telescope_view.gd`, `ui/telescope_panel.gd`, `ui/remote_district.gd`, `systems/remote_progress.gd`, `data/telescope.json` | The Telescope building: watch your crews on other worlds, and the pay for the work they did while Lumi was away. `yard_art_observatory.gd` is its kit art, cut from `systems/camp/yard_art.gd` |

Depended on: `CradleMode` (world list and save slots, see prestige), `Frontiers`, `Research`,
`Bloom`, `GameState`, `SaveManager`, `Economy`, `Offline` (remote progress), `SphereCam`,
`SpaceStage`, `CradleShip`, `ShipModel`, `PlanetGlobe`, `SolarSystem`, `HubHop`, `OrbitSites`,
`RocketPicker` (it had "Other planets" and "Launch home" buttons, removed), `GlobeView` (it had a
"Solar system" button, removed), the pause menu (a "Solar system" entry, removed), the `Loader`
autoload, and `planet/planets/*` for each planet's environment.

Shared code that used it, and what it uses now:
- Planet restoration: `Homeward.measure_current()` is now `Restoration.value()` (`systems/restoration.gd`).
- The current planet id for the sky and the globe: `Planets.current_id()`.
- The Bloom Core cap from later-planet tech (`story/core_charge.gd`) and the tech gate on four
  research nodes (`systems/research.gd`, key `requires_tech`) are gone: nothing outside the planet
  holds Verdance back.
- `Bloom.play_finale` plays the ark finale directly (the campaign redirected it to "The Cradle Answers").
- `ShipTiers.look()` follows the in-planet rocket tier only (looks 5 to 7 were the drive tiers).
- `Tunes.planet_name()` uses the planet id.

## prestige/ : Cradle Mode

What it did: after the finale the ark could seed a new, generated world with its own save slot.
A profile file held the world list, a restoration score and Heirloom levels that gave every
world permanent multipliers and a starting kit. The endless Seed Ark loop paid rewards for
blooms after the finale.

| File | Was at | What it is |
|---|---|---|
| `cradle_mode.gd`, `cradle.json` | `systems/`, `data/` | The profile, worlds and their slots, Heirlooms, world modifiers, the stat hook |
| `cradle_boot.gd` | `systems/` | The `CradleBoot` autoload (removed from `project.godot`): loaded the profile at start and pointed `SaveManager.slot` at the current world |
| `heirloom_track.gd` | `systems/` | Heirloom levels unlocked along a score track |
| `world_gen.gd` | `systems/` | Name, type, biome mix and modifiers of a generated world |
| `ark_bridge.gd` | `ui/` | The Ark Bridge screen: worlds, Heirlooms, seed a new world |
| `world_picker.gd` | `ui/` | The title screen's world list |
| `bloom_seed_ark.gd` | snippet of `systems/bloom.gd` | The Seed Ark loop (the milestone logic stayed in Bloom) |
| `autoplay_late.gd` | `tools/` | The bot's post-game layer |

Depended on: `Homeward` (and it on this: park or restore the two together), `Bloom`, `Research`,
`Decor`, `Nursery`, `WeeklyChallenge`, `SaveManager` (slot, save folder), `SteamService`,
`Economy.planet`, the `Loader` autoload, `DevHooks`.

Shared code that used it, and what it uses now:
- `Economy.stat` applied `CradleMode.stat_mod` (Heirlooms, world modifiers, decor charm, nursery).
  It now multiplies by `Decor.stat_mult` and `Nursery.stat_mult` directly.
- `SkyDirector` (night speed of a world modifier) and `WorldEvents` (event weights of a world
  modifier): the factor was 1.0 on Verdance and is gone.
- Garden Mode unlock (`Decor.unlocked`) reads `flags.bloom_finale_seen` itself.
- The album's "does this run write saves" rule (`systems/extras/album.gd`) is its own small function.
- `SaveManager.slot` stays 0: the first slot is the only world. New Game deletes that slot only.
- Curiosities that only wait on a generated world (`"where": "new_world"` in the eggs table) are
  never placed and the Codex does not list them.

## extras/

| Folder | Was at | What it did | Depended on |
|---|---|---|---|
| `weekly/` | `systems/extras/weekly*.gd`, `data/weekly.json`, `tools/extras_roundtrip.gd` | Seed of the Week: one seed and one twist for everyone each week in its own save slot, a paint chip per finished week, two decorations bought with chips. `extras_panel_weekly.gd` is its Keepsakes tab (cut from `ui/extras_panel.gd`), `decor_weekly.txt` its two entries of `data/decor.json` | `CradleMode` (seed, modifiers, scene change), `Fleet` (robot bans), `Decor`, `SaveManager` |
| `museum/` | `systems/museum.gd` | The Museum building at Cradle Returns: a plinth for every collectible. The catalogue half stayed in the game as `systems/exhibits.gd` (the Codex Collection page). `yard_art_museum.gd` is its kit art | `Homeward` (unlock, site, relics), `HubBuilds`, `EggDisplay`, `EggCollect`, `Collection`, `YardArt` |
| `fabricator/` | `robots/fabricator/bot_fabricator.gd`, `ui/fabricator_panel.gd`, `systems/camp/fabricator_model.gd`, `data/fabricator.json` | The Bot Fabricator: a build from the third planet on that makes robots by itself on a mix the player sets. `yard_art_fabricator.gd` is its kit art | `Homeward` (unlock planet), `SphereCrew`, `HubBuilds`, `BenchBots` (it had a Fabricator category, removed), `YardArt` |
| `profiles/` | `systems/profile_slots.gd`, `ui/profile_picker.gd` | The title screen's three save profiles: pick, rename, delete, then pick a world | `CradleMode` (profile file, worlds), `SaveManager` (its profile functions are still there), `WorldPicker` |

## side/ and extras/nursery/ : side systems Planet 1 does not use (task M3-13)

The lead's list is in `docs/DECISIONS.md` ("Side systems trimmed to what Planet 1 uses"); the
report with line counts is `docs/reviews/M3-13_TRIM.md`. Saves keep everything these systems
wrote (`tests/test_side_systems_saves.gd` loads an old save that used all of them).

| Folder | Files and where they were | What it did | Depended on |
|---|---|---|---|
| `side/requests/` | `contracts.gd` (`systems/`), `contracts_panel.gd` (`ui/`); `contracts_table.json` (the `contracts` block and WREN's `contract_done` pool of the planet's events table); `workbench_tier.json` (the Mk IV bench tier and the tab gate, from `data/workbench.json`); snippet `save_migrate_v2_contracts.gd` (from `SaveManager.migrate_v2`) | The Requests board: three timed jobs for cubes or Parts, a reward track of Curio Capsules and robot parts, world events counted as requests. Opened by Workbench Mk IV | `WorldEvents` (progress_cubes, the event count, the streak peak), `Collection`, `RobotParts`, `UpgradesScreen` (the Requests tab and its gate), `EventHUD` ("request ready" nudge), `BenchTiers` (contracts_done for old saves) |
| `side/trinkets/` | `collection.gd` (`systems/`); `trinkets_table.json` (the `trinkets` table of the events table and the Codex `trinkets` exhibit of `museum.json`); snippet `codex_screen_trinkets.gd` (the trinket list on the Codex Collection tab) | Trinkets and curios from events, requests, streaks, Lumi levels and photos, listed on the Codex Collection tab | `WorldEvents` (trinket_chance, the max-streak medal, Wildlife Visit photos), `Fauna` (crumb bag, pic_ photos), `Contracts`, `LumiLevel`, `Exhibits` (kind `trinkets`), `Decor` (needs_finds) |
| `side/garden/` | `decor.gd`, `garden_director.gd` (`systems/`), `garden_placer.gd`, `late_menu.gd` (`ui/`), `decor.json` (`data/`); `wren_lines_garden.json` (WREN's `garden_place` pool); snippet `orbit_roundtrip_garden.gd` (the Garden Mode checks of `tools/orbit_roundtrip.gd`) | Garden Mode after the finale: place decorations per hub; their charm sped plants up through `Economy.stat` | `HubFrame` (a Decor node per hub), `SliceOrbit`, `SphereCam`, the pause menu's Garden Mode button, the `garden_mode` key (H), `Collection`, `DecorProps` (stays: shared art) |
| `extras/nursery/` | `nursery.gd` (`systems/extras/`); `yard_build.json` (its yard build in `camp.json` and its entry in `builds.json`); snippet `extras_panel_nursery.gd` (the Keepsakes Nursery tab with Retire) | Old robots retire into a garden at the base as caretakers; a small plant-growth bonus through `Economy.stat` | `ExtrasDirector`, `ExtrasPanel`, `Camp` (migration, build reveal, report), `YardSite` (its model), `YardBuilds.IDS`, `RobotBuilder` (traits), `YardArt.nursery*` (stays: art) |
| `side/lumi_level/` | `lumi_level.gd` (`systems/`), `lumi_level.json` (the planet's `robot_level` table, also dropped from `PlanetDefinition.OPTIONAL_TABLES`); snippet `hotbar_level_bar.gd` (the XP bar and level-up banner of `ui/hotbar.gd`) | A second experience bar from everything Lumi did, paying cubes and seeds per level | `HUD` (level-up line, hiding the context line), `Hotbar`, `Collection`, `WorldEvents.progress_cubes`, `Goals` and `WorldEvents` signals |
| `side/ship_looks/` | `ship_style.gd` (`systems/`), `ship_style.json` (`data/`); snippet `locker_editors_rocket.gd` (the Locker's Rocket section) | Rocket paint, trim and glow, free, tier-unlocked or bought for Parts | `ShipModel` (its colours), `LockerPanel` (the Rocket tab), `RocketTiers` |
| `side/events/` | snippets `events_cut.gd` (`systems/events.gd`), `event_props_cut.gd` (`systems/event_props.gd`), `events_check_cut.gd` (`tools/events_check.gd`); `events_cut.json` (the three events, the `animals` table and their WREN pools) | Supply Drop (already off), Robot Hiccup, Wildlife Visit: cut, not just parked (the report says why) | `WorldEvents`, `EventProps`, `Collection`, `Interactables`, `Fleet` |

Shared code that used them, and what it does now:
- **Lumi Level's rewards feed pacing, so they moved, not vanished.** `systems/mastery_rewards.gd` pays
  each mastery level Lumi gains what the same-numbered Lumi level paid (same formula and numbers,
  in the pollution table's `mastery.level_reward`). Bringing Lumi Level back means taking them off
  mastery again.
- `Economy.stat` no longer multiplies by `Decor.stat_mult` and `Nursery.stat_mult`.
- `ShipModel` uses its own `PEARL`, `ACCENT` and `GLOW` colours.
- The pause menu chains focus over its visible buttons itself (`LateMenu.refresh` did it before).
- The Codex Collection tab lists `Exhibits` only; `Exhibits.KINDS` lost `trinkets`.
- World event cubes are capped at `reward.max_income_s` of current income (`WorldEvents.capped_cubes`).
- `YardBuilds.IDS` lost `nursery`; `Camp` and `YardSite` lost its migration, reveal and model.
- `BenchTiers` lost tier 4 (the Request Board); a save on Mk IV reads as the top tier (its flag stays 4).
- Dev hooks gone with them: `--requests-done`, `--trinkets`, `--tab=contracts`, `--contracts-sample`,
  `--requests-unlocked`, `--lumi-level`, `--lumi-xp`, `--lumi-levelup`, `--open=garden`, `--garden*`,
  `--decor-sample`, `--nursery-sample`, `--extras=nursery`, `--open-locker=rocket`, `--event-land`.

Still in the game, on purpose: `Looks.migrate_save` reads old `lumi` levels and `trinkets_found` /
`contracts_done` stats (it turns old unlocks into found pieces); `tools/orbit_roundtrip.gd` still
compares the saved decor lists (the data must survive a round trip); the yard prefab keeps its
`nursery` anchor and `YardArt` its nursery models.

## tests/

One file per parked feature, plus parts cut out of tests that stayed:
`test_museum.gd` (from `tests/test_eggs2.gd`), `test_weekly.gd` (from `tests/test_extras.gd`),
`test_seed_ark.gd` (from `tests/test_bloom.gd`), `test_rocket_picker_system_map.gd` (the old
`tests/test_rocket_picker.gd` with its solar-system map test).
Task M3-13: `test_requests.gd` (from `tests/test_events.gd`, `test_onboard.gd`,
`test_robot_builder.gd`), `test_trinkets.gd` (from `tests/test_events.gd`), `test_decor.gd` (moved
whole), `test_nursery.gd` (from `tests/test_extras.gd`), `test_lumi_level.gd` (from
`tests/test_hud.gd`, `test_qafix.gd`, `test_economy_scale.gd`), `test_ship_looks.gd` (from
`tests/test_ui6.gd`).

## achievements_parked.json

The 30 achievements that can no longer be earned on Planet 1, each with the feature it waits for:
20 from task M1-08; from task M3-13 the four of Garden Mode, the two of the nursery, the three
robot-part ones (Planet 1 places no robot parts, M3-14b) and `home_answered` (nothing on Planet 1
sets `cradle_answered`).

## Still in the game because the planet tables are not cleaned yet

`planets/verdance/data/` was out of bounds for task M1-08, so these entries of parked features are
still in the tables. The game skips them; delete them when the tables are next edited:
- `builds.json`: `telescope`, `museum`, `bot_fabricator` (`HubBuilds.ids()` only lists builds a system owns).
- `goals.json`: 17 goals that wait on a stat in `data/parked.json` (`Goals.playable()` leaves them out).
- `codex.json`: categories `homeward` and `sightings` (`Codex.categories()` only lists categories with entries).
- `museum.json`: four `relic` exhibits, plus the building's `cost`, `pos`, `yaw_deg` (`Exhibits` only lists kinds it can count).
- `eggs.json`: `older_pod`, `heirloom_tin` (`"where": "new_world"`).
- `research.json`: node `observatory` (still researchable, unlocks nothing) and four `requires_tech` keys (ignored).
- `bloom.json` (the postgame table): the `seed_ark` block (unused).
- `wren_lines.json`: pools `museum_complete`, `ark_wave`, `cradle_mode`, `new_world`, `home_*`, `world_*`, `egg_older_pod`, `egg_heirloom_tin` (never spoken).
