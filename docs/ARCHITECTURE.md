# Greenfall architecture

How the game is put together, and the plan for splitting `scenes/slice.gd` (code health, part 2).
Written in the `[health]` pass, Nov 2026, against Godot 4.7.2. Line counts are approximate.

## 1. Big picture

- Pure GDScript with static typing. Almost nothing is authored in `.tscn` files: scenes are one root node with a script, and the script builds its children in code.
- Two playable scenes:
  - `scenes/main_menu.tscn` (`ui/main_menu.gd`) is `run/main_scene`. It shows the title screen, then calls `change_scene_to_file("res://scenes/slice.tscn")`. Any DevHooks flag skips straight to the slice, except `--menu`.
  - `scenes/slice.tscn` (`scenes/slice.gd`, about 1160 lines) is "the world": one district (hub), built from data and the save every time it loads. Rocket travel saves, switches `GameState.current_hub`, sets `GameState.reload_in_memory` and calls `reload_current_scene()`, so every district is a fresh build of the same scene.
- Tool scenes: `tools/save_roundtrip.tscn`, `tools/events_check.tscn`, `tools/frontier_balance.tscn`, `tools/pose_lineup.tscn`, `scenes/turnaround.tscn`, `scenes/robot_lineup.tscn` and `scenes/rocket_preview.tscn`.
- Data lives in `data/*.json` (English) and is read through `Economy.read_json()`. Player-facing text goes through `tr()` (see docs/LOCALIZATION.md).

### Folder map

| Folder | Scripts / lines | What lives there |
|---|---|---|
| `autoload/` | 9 / 2.9k | singletons (below) |
| `core/` | 4 / 0.5k | `BigNum`, `Hex` math, small pure helpers |
| `planet/` | 13 / 9.5k | `HexField` (sim of one district), `FieldView` (ground and junk MultiMeshes), `LitterView`, `CityLayout`/`CityView`, `StreetDressing`, `FutureLayer`, `SkyDirector`, `PlanetData` (40k-cell planet), frontier districts |
| `player/` | 9 / 2.6k | `Patch` (Lumi: input, scoop, tools, carry), `PatchModel`, `CameraRig`, `Detector`, pickup FX, photo poser |
| `robots/` | 6 / 3.7k | `Fleet` (spawn, orders, zones), `Robot` (role AI in `_physics_process`), `RobotVisual`/`RobotKit`/`RobotPersona` (looks and animation), `WaterNet` |
| `automation/` | 15 / 5.6k | `Hub` (base levels), `Depot`/scale, `Stations` (conveyor, auto-baler, recycler), `Rocket`/`LaunchPad`/`RocketTiers`, `Outposts`, `CargoPods`, `JunkCube` |
| `plants/` | 4 / 1k | `Garden` (slots, growth, watering), `HexLevels`, `Composter`, `Wildlife` |
| `story/` | 18 / 6.6k | `Wren` (companion lines), `Intro`, `FirstSeed`, `ShardSystem`, `EasterEggs`/`EggProps`, `LedgerArc`, `CoreCharge`, `BloomFinale`, `Goals`, `Interactables`, `StorySfx` |
| `systems/` | 14 / 4.5k | `Research`, `Achievements`, `Codex`, `WorldEvents`, `Contracts`, `Bloom`, `LumiLevel`, `RobotBuilder`, `Collection`, `QualityProbe` (mostly static data and logic plus one node each) |
| `ui/` | 44 / 12k | `HUD`, hotbar, goals panel, upgrades/research/codex/command/globe screens, pause menu, settings panel, photo mode, `UITheme` |
| `water/`, `audio/`, `art/`, `steam/` | | lake view; music director and synth; `ProcMesh`/`Mats`/`AssetLib`/`Vfx`; the Steam wrapper and demo gating |
| `tools/`, `tests/` | | autoplay bot, round trip, audits; 40+ GUT test files |

## 2. Autoloads (in load order)

| Autoload | Role | Notes |
|---|---|---|
| `EventBus` | global signals (`hex_cleaned`, `junk_scooped`, `toast`, `hex_level_changed`, `robot_built`, ...) | gameplay emits; UI, audio, story and stats listen |
| `Settings` | player settings and the input map, glyphs, `bind_text()` | hot file. `bind_text` bindings are cleared in `_exit_tree` (see section 5) |
| `GameState` | all persistent state as plain data: currencies (`BigNum`), `upgrades`, `flags`, `stats`, `world` (per district), `planet_state`, districts | runs a 10 Hz sim tick in `_physics_process`. `to_dict`/`from_dict`, `switch_hub` |
| `Economy` | loads `data/*.json`; `stat()`, `robot_stat()`, costs, cube evaluation | `stat()` is on the robots' per-frame path; upgrades are indexed by stat (`_by_stat`) |
| `SaveManager` | versioned, compressed save in `user://`, migrations, autosave (60 s, focus loss, pause, quit) | calls `persist_save()` on the `persist` group before writing; `enabled = false` under `--fresh` |
| `SteamService` | the only code that talks to GodotSteam; it degrades to a no-op when the extension is missing | no GDExtension ships in the repo today |
| `Audio` | procedural SFX (synthesized at startup), music buses, `play()`/`loop()`/`override()` | `_exit_tree` waits for `StorySfx` worker tasks and lets the mixer free stopped playbacks (section 5) |
| `Story` | tiny: `Story.once(id, line)` | |
| `Vfx` | pooled CPU particle bursts, floating numbers, rings | |
| `DevHooks` | command-line flags (`--fresh`, `--autoplay`, `--quit-after`, `--shot`, `--perf`, ...) | hot file. Every dev flag is listed in its header |

## 3. How the world is assembled (`scenes/slice.gd`)

`_ready()` is one 430-line function. In order:

1. **Boot and load**: joins the `persist` group, unpauses, `_build_environment()` (sky, sun, Environment). It then decides `loaded` (in-memory reload after a rocket trip, else `SaveManager.load_game()` unless `--fresh`) and applies the dev flags `--hub`, `--hub-level` and `--frontier`.
2. **District generation**: `PlanetData.new(seed).generate()` plus the saved planet state. It picks the hub, anchor cell, district name and city/wild, and reads the frontier params (`Frontiers.field_params`). Then come `CityLayout`, then `HexField` (radius, hex size, biome, pieces per hex, lake hexes taken from planet water cells, natural borders for old saves), then `field.generate()`, landmarks, buried parts and the saved `field` dict. Last is `_map_slice_to_planet()`.
3. **Views**: `FrontierDistrict` (frontiers only), `FieldView`, `WaterView`, `LitterView`, `CityView`, `StreetDressing` (unless `--no-dressing`), the cubes root, `Depot`, the board.
4. **Base and player**: `Hub` (level changes call `_apply_base_level`), rocket site, `Stations`, the flower, `Patch` (with `AutoplayBot`/`DemoScoopInput` input under dev flags), `CameraRig`, `LumiLevel`, `HUD`, `LensOverlay`, `GlobeView` (lambdas for rocket state), `Fleet`, `RobotBuilder`, `UpgradesScreen`, `MusicHooks`, `CommandView`, `PauseMenu`, `PhotoMode`.
5. **Restore**: `_restore_world()` (cubes, Patch, offline catch-up), `cam.snap()`, spawn dev flags.
6. **Dev setup**: camera presets, `--give`, `--unlock-seeds`, `--upgrade-levels`, `--give-parts`, `--clean-hexes`, `--robots`, `--order`, `--open=...`.
7. **Global hooks**: `EventBus.hitstop_requested` and the cosmetics unlock checks. It prints `[slice] built in N ms`, then handles `--auto-launch` and the rocket arrival.
8. **Story and systems** (the order matters: later nodes read earlier ones in `setup()`): `Wren` + `Subtitles`, `Garden`, `HexLevels`, `FutureLayer` (plus `--future` preview), `Goals`, `Wildlife`, `FirstSeed`, `ShardSystem`, `DocumentView`, `Tutorial`, research/codex/achievements (`_setup_research_codex`), `CargoPods`, `Composter`, `Interactables`, `Outposts`, `EasterEggs`, `LedgerArc`, `WorldEvents`, `Contracts`, `Bloom`, frontier setup, `CoreCharge`, `Intro` (plays, or places the pod and wakes WREN).

The rest of the file:
- sim hooks: `collect_piece`, `_on_hex_clean` with its milestones, `salvage_materials`, `add_cube`, `_hitstop`, `planet_cell_at`
- rocket and travel: `_launch`, `rocket_status`, `_refresh_rocket_site`, `refresh_rocket`, `_place_rocket`, `_arrive_by_rocket`, `travel_to`
- interaction and modals: `try_interact`, `interact_prompt`, `near_bench`, `open_upgrades`, `_open_codex`, `_open_command`, `any_modal_open`, `_on_modal_closed`, `_unhandled_input`
- persistence: `persist_save`, `_restore_world`
- `command_markers`

**The world is a façade.** Other scripts reach into the slice through a `world` reference about 1,000 times. The most used are `field` (239), `patch` (140), `wren` (64), `fleet` (60), `garden` (41), `cam`, `hub`, `planet`, `music`, `view`, `hex_levels`, `hud`, `goals`, `depot`, `sky_director` and `interactables`. Some are duck-typed (`world.get("garden")`, `world.has_method("collect_piece")`). The split must keep every one of these member names and public methods on the slice node.

### Per-frame work (where the time goes)

Headless autoplay at time-scale 4: about 7 ms a frame, of which GDScript `_process`/`_physics_process` is about 1.1 ms. With 21 robots (`--robots=... --future=4`) that rises to about 3.3 to 4.5 ms. From the `[health]` instrumented profile:
- `Robot._physics_process` takes about 1.6 ms (21 robots): `_think` 0.5, `move_and_slide` 0.5, speed and stats 0.16, `visual.animate` 0.15.
- `Patch._physics_process` takes about 0.33 ms; most of it is the autoplay bot's input.
- `Wildlife` takes about 0.17 ms. HUD, goals panel, Audio, event HUD and currency cluster take about 0.05 to 0.15 ms each. `RobotKit` + `RobotPersona` take about 0.18 ms (21 robots).

The rest is engine work (physics, MultiMesh and scene updates).

## 4. Plan for part 2: split `scenes/slice.gd`

Goals: smaller files that each own one job, so parallel helpers stop colliding in `slice.gd`; and an explicit build order. No behaviour change: same node names, same children order where it matters, same save data, and `world.<member>` keeps working.

Shape: `slice.gd` stays the root `Node3D` and keeps every public member variable and public method (the façade). The logic moves into focused helpers under a new `world/` folder. Each helper is a `RefCounted` holding `var world` and exposing static-like functions, or a child `Node` when it needs `_process`/`_unhandled_input`/signals. The slice keeps thin one-line wrappers for every public method that other scripts call.

### Components

**A. `world/district_builder.gd` (`DistrictBuilder`, RefCounted).** Generates the district data and the static views.
- Functions: `decide_load() -> {loaded, from_memory}` (the load/reload branch), `build_planet()`, `pick_hub()` (hub index, anchor, district name, is_city, frontier params), `build_field(loaded)` (layout, HexField, water ids, natural borders, generate, landmarks, parts, apply_dict), `map_to_planet()` (from `_map_slice_to_planet`), `planet_cell_at(pos)`, `build_views(fk)` (FrontierDistrict.prepare, FieldView, WaterView, LitterView, CityView, StreetDressing), `build_environment()` (from `_build_environment`), `build_board()`, `build_flower()`.
- Reads: `Economy.planet`, `Economy.junk_*`, `Economy.biome_set`, `Frontiers`, `GameState.world/planet_state/current_hub`, `SaveManager.load_game`, `DevHooks` (`seed`, `hub`, `hub-level`, `frontier`, `no-dressing`).
- Writes on the world: `planet`, `hub_index`, `anchor_cell`, `district_name`, `layout`, `field`, `slice_cells`, `frontier`, `view`, `water`, `litter`, `city`, `dressing`, `_sun`, `_env`, `sky_director`, `_flower`.

**B. `world/base_site.gd` (`BaseSite`, RefCounted).** The hub yard and its level visuals.
- Functions: `build_hub()` (Hub + level_changed/leveled wiring), `apply_base_level(l, animate)` (+ `_ruin_bits`), `build_stations()`, `build_depot()`.
- Depends on A (`field`, `layout`, `dressing`). Reads `GameState.world.hub_level`.

**C. `world/rocket_travel.gd` (`RocketTravel`, child Node).** The rocket pad, launch, flight and arrival.
- Functions: `launch(to_hub)` (`_launch`), `status()` (`rocket_status`), `refresh_site()` (`_refresh_rocket_site`), `refresh()` (`refresh_rocket`), `place(with_pad)` (`_place_rocket`), `arrive()` (`_arrive_by_rocket`), `travel_to(to_hub)`. It owns `rocket`, `_pad_holo` and `launching`; the slice keeps them as properties that forward.
- Depends on: `hub`, `planet`, `Frontiers`, `Demo`, `GameState` (`rocket_parked`, `arrived_from_rocket`, `patch_cargo`, `switch_hub`, `reload_in_memory`), `SaveManager.save_game`, the `persist` group, `globe` (lambdas), `patch`, `cam`, and `DevHooks` (`rocket`, `auto-launch`, `rocket-arrive`).
- Keep the wrappers `world._launch`, `world.rocket_status`, `world.refresh_rocket`, `world.travel_to` and `world.launching`, which are used externally.

**D. `world/world_persistence.gd` (`WorldPersistence`, RefCounted).** The world's save hooks.
- Functions: `save()` (body of `persist_save`: field, planet, garden, patch, cubes...), `restore(from_memory)` (`_restore_world`, including offline catch-up), `load_cubes()`.
- Depends on: `field`, `planet`, `garden`, `patch`, `_cubes_root`, `GameState.world/saved_unix`, `JunkCube`.
- `slice.persist_save()` stays a one-line wrapper (it is called through the `persist` group). The round-trip tool must still pass unchanged.

**E. `world/systems_wiring.gd` (`WorldSystems`, RefCounted).** Creates the gameplay, story and UI nodes in a fixed, documented order.
- Functions: `build_player()` (Patch, CameraRig, LumiLevel, HUD, LensOverlay), `build_ui()` (GlobeView, UpgradesScreen, CommandView, PauseMenu, PhotoMode, DocumentView, MusicHooks), `build_fleet()` (Fleet, RobotBuilder), `build_story()` (Wren + Subtitles, Garden, HexLevels, FutureLayer, Goals, Wildlife, FirstSeed, ShardSystem, Tutorial, CargoPods, Composter, Interactables, Outposts, EasterEggs, LedgerArc, WorldEvents, Contracts, Bloom, CoreCharge, Intro).
- Each step is a short `_add(name, node)` that sets `world`, adds the child and stores it on the façade. The order above is load-bearing; keep it, with a comment per dependency (HexLevels before FutureLayer, Garden before HexLevels, `first_seed.setup()` after `shards.setup()`, and so on).

**F. `world/modal_router.gd` (`ModalRouter`, child Node).** Input and modal routing.
- Functions: `unhandled_input(event)` (from `_unhandled_input`), `open_upgrades()`, `open_codex(tab)`, `open_command()`, `any_modal_open()`, `on_modal_closed()`, `try_interact(p)`, `interact_prompt(p)`, `near_bench()`, `setup_research_codex()` (non-dev part).
- Depends on: `upgrades`, `codex`, `command`, `globe`, `doc_view`, `pause_menu`, `photo`, `interactables`, `depot`, `hub`, `patch`, `launching`, `Settings` actions.
- Keep the wrappers `world.any_modal_open`, `world.try_interact`, `world.interact_prompt` and `world.near_bench`.

**G. `world/field_hooks.gd` (`FieldHooks`, RefCounted).** Simulation hooks called by Patch, robots and stations.
- Functions: `collect_piece(pid)`, `on_hex_clean(hid)` (+ `HEX_MILESTONES`, `hexes_paid`), `salvage_materials(type_id, vol)`, `add_cube(cube)`, `hitstop(duration, scale)`, `command_markers()`.
- Depends on: `field`, `planet`, `slice_cells`, `view`, `litter`, `GameState`, `EventBus`, `Economy`.
- Keep the wrappers `world.collect_piece` (7 external callers plus `has_method` probes), `world.add_cube`, `world.salvage_materials` and `world.command_markers`.

**H. `world/dev_world.gd` (`DevWorld`, RefCounted).** Every `DevHooks.has(...)` block in `_ready()` and `_setup_research_codex()`.
- Flags covered: `give`, `unlock-seeds`, `upgrade-levels`, `give-parts`, `clean-hexes`, `robots`, `freeze-robots`, `order`, `open=*`, `spawn-pos`/`spawn-yaw`, `spawn-hex`, `demo-scoop`/`demo-yaw`/`demo-dist`, `lens`, `cam`, `cam-pitch`, `future` (preview call), `give-data`, `research`, `research-start`/`research-elapsed`, `codex-sample`, `codex-tab`.
- Split into `apply_pre_restore()` and `apply_post_build()` so each block runs exactly where it runs today. This file is where new dev flags go, which takes them out of `slice.gd`.

**I. `world/story_glue.gd` (`StoryGlue`, RefCounted).** The cinematic and story wiring that lives in `_ready` as lambdas.
- Covers: the WREN wake line after `Intro` (or after placing the pod), the `robot_built` "press B for Command" hint, the cosmetics unlock checks on `hex_cleaned/robot_built/upgrade_bought`, the frontier `setup()` call, and the hub `level_changed` → dressing `set_level`.
- Named functions replace the inline lambdas, which also fixes "lambda outlived the scene" bugs like the one `[beat]` hit with Bloom.

After the split, `slice.gd` is about 200 lines: the member list (façade), `_ready()` calling A → B → E → D → H → I in today's order, `_process` (the flower sway), and one-line wrappers.

### Migration steps (one commit each; run tests, the round trip and a 3-minute autoplay after each)

1. Add `world/` with **H (dev hooks)** first. It is pure moving and gives the biggest conflict relief.
2. **C (rocket/travel)** and **G (field hooks)**: self-contained, with wrappers kept.
3. **D (persistence)**: diff a save written before and after (`tools/save_roundtrip.gd` plus a JSON diff of `user://` saves from a fixed `--autoplay --quit-after=60` run).
4. **F (modals/input)**: verify with `--pad-audit` and the GUT HUD tests.
5. **A + B (district/base)**: verify the `[slice] built` timing, `--scene-stats` triangle counts, and one rendered screenshot per biome (`--frontier=*`, a wild hub, Old Town) compared against the pre-split shots.
6. **E + I (systems wiring, story glue)** last, since they touch the most helpers' code paths.

Rules for the split:
- No renamed members on the façade.
- Node names and the order of `add_child` calls stay identical. Some code finds nodes by name (`get_node_or_null("Fleet")`) and some by order.
- No new autoloads.
- Lambdas that outlive the scene become named methods or are disconnected in `_exit_tree`.
- Tag the moved code `[health2]`.

## 5. Health rules learned in part 1

- **Never leave a `WorkerThreadPool` task unwaited at quit.** The pool keeps the task's Callable until it is waited on. A GDScript lambda Callable holds a reference to its script, so the script is destroyed after `GDScriptLanguage` has shut down, and the engine segfaults and aborts (exit code 134). That was the "exit crash": every run that built a district with the jukebox egg (Old Town has it) prewarmed the music box on a worker task that nothing waited on. Fixed by `StorySfx.finish_pending()`, called from `Audio._exit_tree()`. New background tasks must be waited on, or registered with the same hook.
- **No reference cycles between lambdas and the arrays or dictionaries they capture.** `Settings.bind_text` kept `[apply, on_dev]` in an array that both lambdas captured. The cycle leaked the lambdas, their scripts and everything they captured. Break such cycles (`cbs.clear()`) and clear the registries in `_exit_tree`.
- **Don't create a node and then `continue` or `return` before `add_child`.** The auto-baler leaked three `MeshInstance3D` per build that way, and `GlobeView` kept an unused `Label`. Check the condition first.
- Stopped `AudioStreamPlayer`s only queue their playbacks for deletion on the mixer thread, so `Audio._exit_tree()` gives the mixer about 150 ms at quit.
- `tools/check_exit.sh` (run by `tools/run_tests.sh` and CI) fails when the round trip exits non-zero or prints a SCRIPT ERROR, and lists any "leaked at exit" lines. `--quick` adds a 15 s plain run.
- `tools/warnings_audit.sh` lists every GDScript warning (Godot only shows them in the editor) by turning warn-level warnings into errors through a temporary `override.cfg`. Keep it at 0. Intentional integer divisions and mixed-type ternaries carry `@warning_ignore(...)`. `static_called_on_instance` is off because autoload statics (`Economy.read_json`, `Settings.event_label`) can only be called through the instance.

### Perf candidates not done in part 1 (they touch hot files; do them with the split)

- `FutureLayer._update_movers()` writes constant colours and custom data for every mover every frame, and `_mover_xf()` returns a new Array per mover per frame. Set the constants once at build and return through out-params.
- `RobotKit._process` reads 1 to 3 `get_meta()` values per animated part per frame. Cache them in typed arrays when the kit is built.
- `Robot._physics_process` calls `DevHooks.get_s("trace-bot")` per robot per tick. Cache it at `_ready`.
- `Economy.base_stat()` splits `"type.stat"` strings on every call. Cache per stat id; the data is static after `load_data()`.
- HUD labels are rebuilt from format strings every frame (`_field_label`, `_planet_label`, `_prompt`). Rebuild them only when their inputs change.
