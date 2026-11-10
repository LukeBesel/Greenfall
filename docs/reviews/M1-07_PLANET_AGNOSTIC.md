# M1-07: shared code is planet-agnostic

Base commit `3942954`. Six commits: `aabc848` (later planets as data), `249f026` (Planet 1's site scripts move), `48d00dd` (literals), `6857963` (stopgaps), `ab01055` (tests), and the closing one (comments, docs, this report). Planet 1 plays the same: no balance value, id or content row changed except the two stopgap clean-ups in section 6.

## 1. What replaced the old per-planet system
| Was | Now |
|---|---|
| `data/planets.json` (584 lines, five entries) | Each planet's `planets/<id>/planet.tres` plus two tables in its folder: `data/look.json` (sky, fog, sun, ambient, palette, junk tint, env flags, map globe, orbit) and `data/sites.json` (the site list) |
| `PlanetEnvs` (`planet/planets/planet_envs.gd`): `all()`, `entry(id)`, `call_env`, `dev_hub`, `globe(id)`, `GLOBE_DEFAULTS`, `VERDANCE_R`, `build_site` | `Planets.by_id(id)` / `Planets.current()`; `PlanetDefinition.look()`, `call_env(hook, args)`, `has_hook` / `call_hook`, `radius_m()`; `SiteBuilders.build_site` |
| `GlobeSpec` (`of(id)`, `current_id()`, `DEFAULT`, `VERDANCE_FREQ`, `HEX_M`, `cells_for`) | `PlanetDefinition.globe_spec()`, `cells_for()`, `CELL_M`, `RADIUS_M_PER_FREQUENCY` |
| `GlobeSize` (`IDS`, `VERDANCE_R`, `scale_of`, `radius_m`, `cells_of`) | `PlanetDefinition.radius_m()`, `cell_count()`; `OrbitQuality.REFERENCE_R` for the far-distance tuning |
| `SiteBuilders.VERDANCE_SITES` and its `match planet_id` branches | The planet's `sites` table (`sites`, `start_only`, `hub_pad_m`, `fill_pad`, `yard_keep_out`) and its `sites_script` hooks (`build_site`, `restyle_site`, `build_surroundings`) |
| `OrbitPlanet.VERDANCE_HUB_SITE_M` and two `== "verdance"` branches | `SiteBuilders.hub_pad_m()`, `SiteBuilders.has_yard_keep_out()` |
| `PlanetGlobe.IDS`, `PlanetGlobe.CFG`, a `match` on five shader paths | `look.json` `globe` block, `PlanetDefinition.globe_shader`; `PlanetGlobe.has_look(id)` |
| `data/solar_system.json` `planets` block; `SolarSystem.planet(id)` falling back to `"verdance"` | `look.json` `orbit` block; the fallback is the first shipped planet. The file keeps the two stars only |
| `PlanetThemes.IDS`; tracks, instrument groups and ambience beds keyed by planet id; `_active_theme == "verdance"` | `PlanetDefinition.music_set` names one of `MusicTracks.SETS` (`regrowth`, `desert_heat`, `ocean_swell`, `glass_ice`, `foundry`); `MusicTracks.GENERATIVE_CALM`. `Audio.set_planet_theme(id)` still takes a planet id and looks its set up |
| `--orbit-planet=<id>` read by `GlobeSpec.current_id()` | `Planets._ready` calls `set_current(id)` for the flag, so Economy, Audio and the globe all follow it |
| `"verdance_bloom"` in `Bloom` and `CoreCharge` | `Bloom.finale_id()`: the milestone the postgame table marks `"finale": true` |
| "Verdance" inside eleven translated strings | A `{planet}` / `{PLANET}` token filled by `PlanetDefinition.name_in()`; the same eleven msgids changed in the seven `.po` files and the `.pot` |
| `Economy.planet["name"]` with a `"Verdance"` default in the HUD | `Planets.current().display_name` |

`PlanetDefinition` gained: `sites_script`, `globe_shader` (fields); `"look"` in `OPTIONAL_TABLES`; `CELL_M`, `RADIUS_M_PER_FREQUENCY`; `cells_for`, `radius_m`, `globe_spec`, `look`, `name_in`, `call_env`, `has_hook`, `call_hook`. `docs/PLANET_PLAYBOOK.md` section 1 has the field table.

## 2. What moved
- `planet/planets/{rime,ochre,tidewell,anvil}/` to `planets/<id>/` (`git mv`, 52 files with their `.uid`s; only paths and the way each script finds its own entry changed inside them).
- `art/shaders/planet_{verdance,ochre,tidewell,rime}.gdshader` to `planets/<id>/globe.gdshader`. `planet_anvil.gdshader` became the shared `art/shaders/planet_rocky.gdshader`: it was already the fallback for unknown ids, and Anvil's definition points at it.
- `planet/sites/{verdance_site,town_outskirts,hinterland}.gd` to `planets/verdance/sites/`. Class names are unchanged (`VerdanceSite`, `TownOutskirts`, `Hinterland`); no shared script uses them any more.
- New in each later planet's folder: `planet.tres` (`shipped = false`; order ochre 1, tidewell 2, rime 3, anvil 4; frequency and hub count from the old file: 109/8, 166/12, 205/16, 256/20), `data/look.json`, `data/sites.json`, `README.md` ("inherits Planet 1's tables until its own are written": the five required tables point at `planets/verdance/data/`).
- New shared file: `planet/sites/town_site.gd` (`TownSite`, 13 lines): the two fields (`layout`, `town_r`) the garden, street power and outposts read from a town. `VerdanceSite` extends it.
- `SitePrefab.START_YARD_ANCHORS`: the start-yard anchor table moved here from `VerdanceSite` because every planet's start site already used it. `VerdanceSite.START_YARD_ANCHORS` is an alias, so tests and the planet's own code read the same table.

Removed: `planet/planets/planet_envs.gd` (123 lines), `planet/orbit/globe_spec.gd` (40), `planet/globe_size.gd` (23), `data/planets.json` (584), `data/parked.json` (4), the fixture's `minimal.json` (1): 775 lines in six files, plus three `.uid` files. Their tests were rewritten against the definition, not dropped (section 7).

## 3. Planet-name literals
- Quoted planet ids in shared `.gd` files (`"verdance"`, `"Rime"`, and so on): 103 in 23 files at the base, 0 now. The task's grep returns nothing for all five ids.
- Lines that name a planet at all in shared `.gd` files (code or comment, whole word): 190 in 55 files at the base, 6 in 4 files now. All six are comments in files this task was told to leave alone (list in section 8).
- Planet-index branches: none were left after M1-08; the name branches are listed in section 1.

## 4. Behaviour notes
Nothing changes for a player on Planet 1. These are the edges that did change:
1. **`--orbit-planet=<id>` (dev) now switches the whole game**, not just the globe: Economy reads that planet's tables (the first planet's, inherited) and Audio plays its music set. Before, only the globe and the sites changed.
2. **A save whose globe belongs to another planet than the one being played** is rebuilt fresh with the existing warning ("saved globe is X, building Y fresh"). Before, the slice built whatever planet the save named. Only a dev run with `--orbit-planet` could write such a save into slot 0.
3. **A site with no builder is a bare pad** with the shared yard anchors. Before, `SiteBuilders.build_site` left the prefab unbuilt and `OrbitPlanet.build_start_site` waited for it forever. Found by the reuse test.
4. **Instrument samples of the four later planets' music are seeded by the set name** (`hash("foundry")`, not `hash("anvil")`), so their noise-based samples differ by the random draw. Planet 1's instruments are built from the same seeds as before.
5. **The foundry set's metal-strike sample** is named `forge_strike` (it was `"anvil"`, which the name scan would flag).
6. **Tooling:** `site_preview --site=` defaults to the current planet's start site; `sky_preview --preview-planet=` reads the radius from the definition.

## 5. The reuse test
`tests/test_planet_reuse.gd` sets the dummy planet current (`tests/fixtures/planets/testworld/`: globe frequency 16, 2 hubs), instantiates `scenes/slice.tscn` headless, waits for the player, runs 3 seconds, checks the globe, sites and player, saves, loads into a second world and compares planet id, frequency, cell count, seed, sites, the three packed cell arrays, cubes and the player's direction. GUT fails the test on any script error. **Result: pass, 37 asserts, about 10 s.**

The fixture is five small tables (`pollution` with two junk types, `upgrades` with one, `regrowth`, `tutorial` with one step, `goals` with two), one `sites` table and an 18-line sites script that puts a marker block on the pad. No robots, research, hub, stations, plants or field table: the shared systems coped with all of those being absent.

What the build needed beyond fixture data:
- **`SiteBuilders.build_site` / `OrbitPlanet.build_start_site`** assumed every planet has a site prefab: without one the build never finished (note 3 above). Fixed in shared code, generically.
- Nothing else failed in a 3-second run.

Shared code that still assumes Planet 1's content, found by scanning shared scripts for ids that exist only in Planet 1's tables (not reached in 3 seconds without a bot, so the reuse test does not catch them):
- **Biome ids** (`rustlands`, `dust_dunes`, `neon_coast`, `frostcap`, `fungal_marsh`, `dust_flats`, `frozen_port`, `sunken_city`, `cradle_landing`) are quoted in `planet/planet_data.gd` (the survey's biome list is a constant), `planet/frontiers.gd`, `fauna/fauna_rules.gd`, `fauna/fauna_ambience.gd`, `planet/street_dressing.gd`, `story/core_charge.gd`, `story/goals.gd`. The survey gives every planet Planet 1's biomes.
- **Robot type ids** (`scoopie`, `haulbug`, `drip`, `seedling`, `skimmer`, `multibot`) in 17 files, among them `core/offline.gd`, `planet/orbit/orbit_crews.gd`, `robots/robot.gd`, `robots/robot_visual.gd`, `robots/sphere/sphere_robot_kinds.gd`, `robots/water_net.gd`, `story/objectives.gd`.
- **Junk type ids** (`metal`, `rubber`, `paper`, `plastic`, `electronics`, `glass`) in `automation/stations.gd`, `automation/junk_cube.gd`, `planet/hex_field.gd`, `planet/orbit/sphere_field.gd`, `plants/composter.gd`.
- **Research ids used as feature switches** (`conveyor`, `auto_baler`, `recycler`, `rocket_cargo`, `irrigation`, `dew_condensers`, `drip_blueprint`) in `automation/*.gd`, `planet/sites/yard_site.gd`, `robots/sphere/sphere_crew.gd`, `robots/water_net.gd`, `plants/garden.gd`, `systems/camp/camp.gd`.
- **Upgrade ids** (`baler`, `auto_compactor`, `scoop_width`, `signal_finder`, `belt_speed`, `baler_speed`, `recycler_yield`, `compartment_size`) in `core/pace.gd`, `player/patch.gd`, `story/tutorial.gd`, `automation/stations.gd`, `ui/upgrade_card.gd`, `ui/bench_lists.gd`.
- **Yard build ids** as anchor names (`radio`, `signal_tower`, `composter`, `nursery`, `generator`, `locker`, `camera_bot`, and the parked `telescope` and `fabricator`) in `SitePrefab.START_YARD_ANCHORS`, `planet/sites/site_reach.gd`, `planet/sites/yard_site.gd`, `scenes/slice_orbit.gd`.
- **The frontier `cradle_returns`** in `planet/planet_data.gd` and `story/core_charge.gd`.
- **Global data keyed by planet id:** `data/songs.json` (193 lines name a planet), `data/radio.json` (13), `data/achievements.json` (6). `Tunes` and `Radio` match them against `Audio.get_planet_theme()`, which is the current planet's id.
- **Track ids** in `audio/music_tracks.gd` keep their first names (`verdance_sprout`, `anvil_foundry`, 13 ids): saves hold the radio's unlocked ids, so they cannot be renamed.
- **Default seed 4471** (Planet 1's `world_seed`) is still the default argument in `SiteManager`, `OrbitPlanet.seed_value`, `TownOutskirts` and a few tools. The slice passes the definition's seed, so it only matters to callers that pass none.

These are ids of shared mechanics (a baler, a scoop robot) more than names of a place, so they need a design answer per group: either the id is part of the shared schema every planet must provide, or the system has to read it from a table. That is M1-09/M1-10 and later work, not something to patch around here.

A real bug the reuse test exposed (not fixed: `systems/research.gd` is being edited by another task): **`Research._ready` connects two lambdas to `EventBus.hex_cleaned` / `hex_restored` that outlive the node**, because they only call static functions. Every world built in one process adds another pair, so research data is awarded once per world built (3 x after two more worlds: `tests/test_research.gd::test_live_node_awards_data_from_events` read 75 where it expects 25). In the game that is every time the world scene is loaded again in one process (`Loader.goto` / `Loader.reload`: back to the title and in again, New Game). The reuse test disconnects what its worlds added so later tests are not affected.

## 6. Stopgaps cleared
- `planets/verdance/data/goals.json`: the 17 goals of parked features are gone (168 to 151 goals; the order of the rest is unchanged, checked by comparing the parsed lists). `data/parked.json`, `Goals.PARKED_PATH`, `Goals._parked_stats` and `Goals.playable()` are deleted; the chain is the table. `tests/test_beat.gd` now holds the nine parked stat keys and fails if any goal waits on one or any code writes one.
- `planets/verdance/data/research.json`: node `observatory` removed (39 to 38 nodes). No node required it. `data/achievements.json` `research_all` asks for 30 finished nodes, as before (that number was already not "every" node).
- Old saves: `tests/test_parked_saves.gd` loads the M1-08 fixture, which has five of those goals in `goals_done` and `observatory` in the research `done` list. The goals are not in the chain and do not count; `Research` carries the unknown id and skips it (`def(id)` is empty). One assertion block added for the research id.
- Unused msgids for the removed goals and node stay in `locale/*.po` until the next extraction (harmless).

## 7. Tests
- `tests/test_planets.gd`: 5 new tests (16 in the file). All five planets register in campaign order, validate, and only the first ships; parked planets keep their own look, sites and scripts and inherit exactly the five required tables; the globe spec, radius and `name_in` come from the definition; **no shared script quotes a planet id (lowercase, capitalised, display name, either quote) or a `res://planets/<id>` path** (ids from `Planets.all()`; folders `tests`, `tools`, `planets`, `addons`, `parked` are skipped); the scanner is checked against a planted string. The dummy planet still registers alone from its folder.
- `tests/test_planet_reuse.gd`: new, 2 tests (section 5).
- Rewritten against the definition: `test_globe_sizes`, `test_orbe_maps`, `test_hub_sites`, `test_sphere_crew`, `test_planet_globe`, `test_planet_audio`, `test_planet_ochre`, `test_planet_rime`, `test_planet_tidewell`, `test_planet_anvil`, `test_beat`, `test_parked_saves`.
- `tools/run_tests.sh`: 119 scripts, 881 tests, 874 pass, 7 pending (the same seven bug tests of `test_triage_m1.gd` as before), 0 fail; the save round trip and the two-process reload pass. Base: 118 scripts, 874 tests, 867 pass, 7 pending.
- Bot (`--fresh --autoplay --time-scale=8 --quit-after=600`): exit 0, no SCRIPT ERROR, objective `hex` done at 7.7 game minutes, 46.9 game minutes played (20 story objectives done). See section 10 for the spread.
- Parked planet by id (`--fresh --orbit-planet=<id> --quit-after=60`, headless), all four: exit 0, no SCRIPT ERROR. rime R 2,948 m, 420,252 hexes, 16 hubs; ochre 1,567 m, 118,812, 8; tidewell 2,387 m, 275,562, 12; anvil 3,681 m, 655,362, 20. Nothing parked in M1-08 was needed.

## 8. Left alone, and why
- **Comments that still name a planet (6 lines) or `VerdanceSite` (2 lines)** are in files this task was told not to touch or to change by one forced line only: `autoload/DevHooks.gd:62-63`, `planet/sites/hub_hop.gd:11`, `player/patch.gd:148,207`, `player/patch_model.gd:3`, `planet/sites/yard_keep_out.gd:4,43`.
- **Lines changed in files another task is editing:** `planet/sites/yard_keep_out.gd:37` (one line: the pod anchor comes from `SitePrefab`), `planet/sites/orbit_sites.gd:240-258` (the hinterland block: the `"verdance"` test is gone and the node comes from `SiteBuilders.build_surroundings`; 9 lines added and 11 removed, because the class it built moved into the planet's folder).
- **Shader comments** in `art/shaders/*.gdshader` and `planet/orbit/orbit_sky.gdshader` still name planets (8 files). Not scripts; not in the scan.
- **`ui/planet_globe.gd` is not used by the running game** (only tests and `tools/globe_shots.gd` create one since the telescope and system map were parked). It is data-driven now and kept for the map work.
- **The env scripts' flat-world hooks** (`dev_hub`, `prepare_field`, `dress_view`, `apply`) are called only by the planets' own tests: the globe uses the site scripts. The definition carries `env_script` so the hooks stay reachable when a planet is brought back.
- **TASKS.md says "restoration rule and ending come from the definition"** for this task. The finale milestone now comes from the postgame table; the restoration rule itself is M1-10.

## 9. Originality
- `audio/music_tracks.gd` described the foundry tracks with a term from another game. Reworded ("heavy and molten").
- `ui/hotbar.gd:3` names another game in a comment ("...-style" hotbar). Not in this task's files: for the lead to reword, and to judge whether the hotbar itself is too close.

## 10. Is Planet 1 unchanged? What was measured
Because the first hex came at 7.7 minutes in the acceptance run (M1-08 reported 7.1 and 7.4), the base commit was extracted next to this tree and both were measured on the same machine, alternating.

Identical between the two trees:
- The start build: 22 blocks, 79 buildings, 211 outskirts buildings, 9,220 pieces and 19 parts in the near ring, hub distances, load time (10.7 s both).
- `--yard-probe`: all 20 lines (pieces per 4 m band out to 60 m, nearest piece, pod ring).
- `--city-walk`: 62,745 m2 free, all reached, 9,220 pieces, 0 unreachable.
- `--hinter-report`: 3,373 cells, 476 buildings.
- The save round trip's 143 check lines, apart from three values that vary from run to run in both trees (cubes and the hashes of the junk and state arrays). The state hash takes the same three values in both trees (five runs each), which is 163,842 cells agreeing byte for byte.
- Every changed code line in shared gameplay scripts was read again for this (the list is `git diff 3942954 -- '*.gd'` without tests, tools, planets and audio): none changes a value Planet 1 reads.

The bot's first hex, in game seconds (the bot is not seeded, and its pace follows the frame rate, because at time scale 8 the physics steps are capped per frame):
- Base, 14 runs: 386, 395, 399, 419, 420, 421, 423, 426, 427, 428, 469, 480, 483, 493. Mean 433.
- This tree, 16 runs: 411, 420, 423, 440, 440, 442, 449, 458, 459, 461, 462, 463, 471, 515, 528, 533. Mean 461.
- Frame rate in the last five pairs (`--print-fps`): base 76 to 88, this tree 80 to 87; first hex in those pairs: base mean 448, this tree mean 433.

So the first ten pairs put this tree about 45 seconds later and the last five put it 15 seconds earlier, with no difference found in the world, the data, the code path or the frame cost. The machine was shared with another agent's runs the whole time, which moves the frame rate and with it the bot's pace. **I could not prove the 28-second mean gap is noise, and I could not find a cause.** If it matters, the clean check is the same alternating comparison on an idle machine.

Also seen while measuring: `godot --headless --fixed-fps 60 ... -- --fresh --autoplay` aborts during the globe build with `malloc_consolidate(): invalid chunk size` on the base commit (twice out of twice). Not caused by this task; it rules out fixed-step runs as a way to compare.
