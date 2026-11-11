# Flat world removal (v6flat)

The owner's instruction: "Make the round world close to flat and remove flat world." The round
world (`SliceOrbit`, the globe) is the only game. This file is the inventory and the running log
of the removal: what goes, what stays and why, and what is unsure.

## How things were judged

"Flat" is not a folder. The globe reuses most flat-era systems, and `scenes/slice.gd` is the host
scene for both modes. So nothing was removed by name. For each candidate:

1. **Who builds it?** `scenes/slice.gd` had two build paths in `_ready()`: the globe's
   (`SliceOrbit.build`) and the flat district's. A class that only the flat path makes is a
   candidate.
2. **Who else reaches it?** A liveness script walks the scripts from the project's roots
   (autoloads, the main scene, `data/*.json` script paths, the slice) along *strong* edges:
   `X.new()`, `extends X`, `X.static_member`, `res://` paths. A type-only mention (`var a: X`,
   `as X`, `is X`) does not keep a class alive. Tests are not roots.
3. **Which slice fields are never set on the globe?** `layout`, `city`, `rocket`, `wildlife`,
   `water`, `frontier`, `planet_env`, `bounds`, `slice_cells`, `cam` (the flat `CameraRig`; the
   globe's camera is `SliceOrbit.cam`), `command`, `dressing`, `street_power`, `_sun`, `_env`,
   `_flower`. Code behind `world.<one of these>` is dead on the globe.
4. **Tests.** The full suite, the save round trip and the round-Verdance checks ran after each
   piece.

## Baseline (before any removal)

- `tools/run_tests.sh`: 976 GUT tests pass, then `roundtrip`, `roundtrip_flat`, `orbit_reload`.
  5 min 42 s.

## What goes

### The mode itself
| What | Where |
|---|---|
| `--flat` dev hook | `SaveManager.round_planets()`, tests, `tools/check_exit.sh` |
| `Settings.round_planets`, `SaveManager.round_planets()` / `set_round_planets()` | always true now |
| `SliceOrbit.wanted()` | always true, except the phase A prototype hooks `--orbit=globe` / `--orbit=v1` |
| `--menu=round-new` / `round-continue` | same as New Game / Continue now |
| `roundtrip_flat` | `tools/check_exit.sh` |
| `tests/test_round_planets.gd` | tests the removed toggle |

### The flat build path in `scenes/slice.gd` (about 1,000 of 1,511 lines)
- `_ready()` after the globe branch: planet survey at level 6, `CityLayout`, `HexField`,
  `FieldView`, `LitterView`, `FarJunk`, `WaterView`, `CityView`, `StreetDressing`, the flat yard
  (`_build_board`, `_build_flower`), the flat camera, `GlobeView`, `CommandView`, `WorldBounds`,
  `Wildlife`, `CargoPods`, `FrontierDistrict`, the flat `Rocket` site, and every dev flag handled
  there.
- `_build_environment`, `_build_board`, `_setup_street_power`, `_apply_base_level`,
  `_build_flower`, `_map_slice_to_planet`, `_preload_models`, `_record_preload`, `_step`,
  `_refresh_rocket_site`, `refresh_rocket`, `_place_rocket`, `_arrive_by_rocket`, `travel_to`,
  `_open_command`, and the flat half of every `if orbit: ... return` hook.
- Stays in `slice.gd`: the globe hand-off, `_setup_research_codex` (the globe calls it),
  `salvage_materials`, `add_cube`, `_hitstop`, `command_markers`, the thin hooks that forward to
  `SliceOrbit`, and the fields the globe fills.

### Files only the flat path reaches (first pass of the liveness script)
`ui/command_view.gd` (1,534 lines), `planet/frontier_district.gd` (644), `player/camera_rig.gd`
(259), `planet/world_bounds.gd`, `planet/edge_test.gd`, `planet/straight_walk_input.gd`,
`plants/wildlife.gd`, `water/water_view.gd`, `art/shaders/water.gdshader`, `automation/cargo.gd`,
`ui/range_boost.gd`, `tools/bale_shot.gd`, `tools/demo_scoop.gd`. More fall out in later passes,
once the code that mentions these is cleaned (the flat `Rocket` flight, `GlobeView`, frontier
views, flat-only dev tools). Each pass is logged below.

### Saves
- The flat save tree (`user://saves`) is no longer written or opened as a game.
- `SaveManager.root_dir(flat)` / `profile_dir(n, flat)`: the `flat` switch goes; one small
  read-only helper for the old tree stays for the import below.

### Tools, flags, docs, CI
- Flat-only dev flags (`--spawn-pos`, `--spawn-yaw`, `--spawn-hex`, `--hub`, `--frontier`,
  `--planet-env`, `--edge-test`, `--demo-scoop`, `--bale-shot`, `--order`, `--clean-hexes`, ...)
  go with the flat build path, unless the globe has the same flag.
- `tools/shot.sh`, `tools/turnaround.sh`, the title-screen command: checked one by one.
- `CLAUDE.md`, `docs/ROADMAP.md`, `docs/ORBIT_ROLLOUT.md`, `docs/ORBIT_PARITY.md`: the rollout
  is finished and the flat mode is removed.

## What stays, and why

- **Shared systems the globe runs:** CityView, StreetDressing, StreetPower (site power),
  LitterView (sphere litter), FieldView (SphereJunkView extends it), HexField (SphereField
  extends it), CityLayout (town sites), Garden, HexLevels, Fleet, Stations, Depot, Camp,
  Objectives, Goals, Tutorial, Wren, Hub, Contracts, WorldEvents, Fauna, EasterEggs, Outposts,
  LedgerArc, Decor, Telescope, Extras, Glim, Bloom, CoreCharge, Intro, PhotoMode, SkyDirector,
  FutureLayer. HubFrame (`planet/orbit/hub_frame.gd`) runs the yard systems per hub in
  site-local metres, so their "flat" x/z maths is live code.
- **`OrbitUp`** (`planet/orbit/orbit_up.gd`): its flat fallbacks (`Vector3.UP`, x/z distance) are
  what unit tests of shared systems use without a globe. They stay.
- **The old-save migration:** `core/save_orbit_migrate.gd` (OrbitMigrate), its fixture
  `tests/fixtures/flat_v4_oldtown.save`, `tests/test_orbit_migrate.gd`, and the `orbit_old_*`
  checks in the round trip. `GameState.world` / `districts` / `planet_state` stay as the fields a
  flat save is read from.
- **Save version migrations** (v1 to v4 currencies, parts): shared, not flat.
- **Steam Cloud:** round saves keep their `r_` names. Old flat cloud saves still sync down to
  `user://saves`, so the import below can pick them up.
- **Phase A prototypes** (`--orbit=globe`, `--orbit=v1`, `--sphere-walk`): nothing in the round game or its tests
  reached them, so they went too (piece 5). `SphereWalker` stays: `tests/test_sphere_move.gd` drives SphereMotor
  through it.

## Unsure (decisions for main / the owner)

1. **Old flat saves never reach the migration today.** OrbitMigrate only runs when the *round*
   save tree holds a save with no globe in it. Flat saves live in `user://saves`; the round game
   reads `user://saves_round`; nothing copies one to the other. So since the round default, an
   old player sees no Continue. Plan: a one-time import at startup (flat tree pN to round tree
   pN, only into a profile that has no saves, never overwriting, with a marker file), like the
   demo import. It is its own commit, easy to drop. **Done** (main approved; Log 4).
2. **Other planets' flat envs** (`planet/planets/{ochre,tidewell,anvil,rime}/env.gd`, about
   5,400 lines): `apply(world, field, kind)` dresses a flat district. Their globe sites
   (`sites.gd`, `rime_site.gd`, `anvil_sites.gd`) reuse parts of them. Cut only what the liveness
   script proves dead; the rest is listed at the end.
3. **Frontier districts and Cradle Mode worlds:** retired on the globe (`SliceOrbit` header).
   `FrontierDistrict` goes; `Frontiers` (static data helpers used by goals, codex, research)
   stays where round code calls it. **Done** (Log 7).
4. **The flat save round trip's shared checks.** `tools/save_roundtrip.gd` without `--orbit`
   booted the flat scene and also checked shared state (contracts, designs, Lumi style, robot
   builder, Glim, extras, camp, profiles, Homeward, old save versions). Those checks move onto the
   globe round trip; only the flat-geometry ones (frontier districts, flat hexes) are dropped.
   **Done** (Log 5).

## Log

Each piece was handed to main green: `tools/run_tests.sh` (GUT + roundtrip + orbit_reload),
`save_roundtrip.tscn -- --fresh`, `--city-walk`, `--target-reach` and a 600 s autoplay with no SCRIPT
ERROR. (`--target-reach` shows a `fauna/fauna_rules.gd:191` SCRIPT ERROR between hubs and now and then
crashes at quit with heap corruption; both happen on main too and are v6qa's.)

1. **Mode switch** (3c5cb90): `--flat`, `Settings.round_planets`, `SaveManager.round_planets()` /
   `set_round_planets()`, the `flat` switch of `root_dir`/`profile_dir`, `roundtrip_flat`,
   `tests/test_round_planets.gd`. New `tests/test_save_tree.gd`.
2. **The slice** (92572a5): `scenes/slice.gd` 1,511 -> 261 lines, the globe's host only.
3. **Files only the flat path reached** (b33950f, 6c0e590): CommandView, WorldBounds (+ its test),
   EdgeTest, Wildlife, CargoPods, RangeBoost, the `--sphere-walk` demo, `tools/bale_shot.gd`,
   `tools/demo_scoop.gd`. `FrontierView.Batch` / `_beam_xf` moved into `PropBatch` (Rime, Tidewell
   and Anvil sites build with it). Flat-cam and frontier reads dropped from Garden, HexLevels, Robot,
   Goals, Bloom, LateDirector, WorldLookView, EventHUD, Hotbar, PhotoMode; Eggs' constellation peek
   and StarPeek use the globe's SphereCam.
4. **Old flat saves** (884a087): `SaveManager.import_flat_tree` copies `user://saves` pN into
   `user://saves_round` pN once at startup, only into a round profile with no save, never over a
   file, never changing the flat tree; `flat_import.done` marks it (written once a flat save was
   seen, so a later Steam Cloud sync-down still gets imported). Skipped under `--fresh`/`--nosave`
   (unless `--save-dir`) and under GUT. Test: `tests/test_flat_import.gd`.
5. **Save round trip** (8a0168c): `tools/save_roundtrip.gd` 833 -> 29 lines, the globe's round trip
   only. The flat trip's shared checks run on the globe (`tools/shared_roundtrip.gd`, `shared_*`
   lines, hooked into `tools/orbit_roundtrip.gd` around its save and reload), then the scene-free ones
   (v1 and v2 save migrations, Homeward, profiles).
6. **Phase A prototypes** (2089a06): VerdanceGlobe, OrbitWorld, OrbitBot, OrbitGlobe, OrbitCam,
   OrbitWalker, StraightWalkInput, `orbit_ground.gdshader`, `tests/test_orbit_globe.gd`,
   `SliceOrbit.wanted()`; `--orbit` goes straight into the game.
7. **Frontier districts and flat views** (ecfca4e): FrontierDistrict, FrontierView, CameraRig,
   WaterView and the water, flood, ice-slab and tower-glass shaders; the slice's `cam`, `water`,
   `frontier` fields; autoplay's frontier chores. Ledger's cinematic now locks the globe's camera.

### Totals
- 32 files deleted (plus their `.uid`s); 10,991 lines removed and 752 added over the 8 commits.
- Tests: 3 test files and 25 test functions removed; 4 converted (the globe-only slice check,
  round cloud names into `test_save_tree.gd`, the save tree, the frontier species rules); 7 new
  (`test_flat_import.gd`, `test_no_mode_switch_is_left`). The save round trip gained 34 `shared_*`
  checks on the globe and kept the scene-free ones; it dropped the flat-geometry checks (frontier
  district trips, the Cradle second-world trip, Seed of the Week, the flat district snapshot's hex
  and station counts, which the orbit trip checks per cell).

## Leftovers kept on purpose

| What | Why it stays |
|---|---|
| `automation/rocket.gd` (Rocket, the flat launch/arrival flight) | Never built on the globe, but LaunchPad (`Rocket.PARK_YAW`), HomewardDirector, Homecoming and the rocket/ship preview scenes reference it, and v6hubs is building the globe's rocket hop now. Its `world.cam` lines only run in the flat flight. |
| Slice fields the globe never sets: `layout`, `city`, `rocket`, `planet_env`, `slice_cells`, `dressing`, `street_power`, `_sun`, `_env`, `_flower` | Read with `world.get(...)` in many shared systems and the planet envs; null on the globe, so those branches are dead but harmless. Removing them is a sweep over files other helpers own. |
| `world.get("cam")` branches (Telescope, Cine, Intro, BloomFinale, TvBroadcast, StarPeek, Outposts dev, GardenPlacer, Rime/Ochre/Anvil/Tidewell envs) | Always null now (no `cam` field), so they do nothing; left for their owners. |
| Planet envs `planet/planets/{ochre,tidewell,anvil,rime}/env.gd` (`apply(world, field, kind)`, ~5,400 lines) | Their globe sites reuse parts of them; dressing a flat district is dead, but separating the two is per-planet work for when those planets are in focus. |
| `planet/frontiers.gd` (Frontiers) | Static data rules that Goals, the planet data and autoplay still call. |
| `planet/sphere/sphere_walker.gd`, `planet/sphere/sphere_demo.*` (`--sphere-demo`) | SphereWalker is the SphereMotor test harness (`tests/test_sphere_move.gd`); the grid demo is round, not flat. |
| `core/save_orbit_migrate.gd`, `tests/fixtures/flat_v4_oldtown.save`, `GameState.world` / `districts` / `planet_state` | The one-way flat -> round migration. |
| `SaveManager.old_flat_root()` / `old_flat_profile_dir()`, Steam Cloud's flat names | The import above, and old flat cloud saves still sync down for it. |
| Seed of the Week (WeeklyChallenge, WeeklyRun) | Still offered in the Keepsakes panel, but on the globe the week's seed is ignored and a resumed run has no robots. Its round trip ran on the flat district and was dropped. Needs an owner: make it round or hide it. |
| Frontier goals in `data/goals.json` (`storm_*`, `heater_1`, `thaw_*`, `greenhouse_1`, `drain_*`, `visit_*` frontiers, `*_base*`, `*_grow*`, `frontiers_growing`, `cradle_*`) | Nothing on the globe raises their stats or flags now (the live frontier districts are gone; `tests/test_beat.gd` lists the stats in `RETIRED_FRONTIER_STATS`). Data is v6pace's: drop or replace them there. |
| `tools/pad_audit.gd`, `tools/scene_stats.gd` and other dev tools that still read flat fields | Dev only; they read with `get()` and skip what is missing. |
