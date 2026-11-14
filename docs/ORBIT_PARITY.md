# Round planets: parity with the flat game

**[v6flat] History.** The flat game has been removed (docs/FLAT_REMOVAL.md); the round world is the only game, and `--orbit` only skips the title screen. Rows below marked *retired* are gone with it.

What the flat game had, and where each piece stands on the walkable globe. Last checked Nov 9 on `wt/orbB` (orbB); First Seed, compost press, seed finds and memory shards turned green in the wrap-up.

**Status**
- **works**: built on the globe and exercised by a check.
- **partial**: built, but part of it is missing or unchecked.
- **missing**: not built on the globe yet.
- **retired**: replaced on the globe, or not needed there.

**Owner** is the helper whose phase the gap falls in (docs/ORBIT_ROLLOUT.md):
- orbB: world, saves, flat systems ported per hub.
- orbC: robots, Command view, offline.
- orbD: sites, yard, travel, planet %.
- orbE: sky, story layers, maps, cinematics, perf.

## How this was checked

| Check | Command | What it shows |
|---|---|---|
| System audit | `godot --headless --path . res://tools/system_audit.tscn -- --fresh [--orbit]` | The slice's named systems (set or null) and every script class in its tree, flat vs globe. |
| Orbit round trip | `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --orbit` | About 90 checks (`orbit_*`), plus a save/load comparison of about 35 state keys. |
| Fresh-process reload | `tools/orbit_reload_check.sh` (run by `tools/check_exit.sh`) | Lumi's position, cubes and cells survive a quit and restart. |
| Autoplay | `-- --fresh [--orbit] --autoplay --time-scale=4 --quit-after=200` | Early game in about 13 game minutes, flat vs globe. |
| Robots | `-- --fresh --orbit --robots=scoopie:3,haulbug:2 --time-scale=4 --quit-after=90` | The `[bots]` table. |
| Exported build | `--export-pack "macOS"`, then `--main-pack` with `--menu=round-new` / `round-continue` | The preview works from an exported pack. |

**Autoplay, 200 s at x4 (Nov 9):**

| Metric | Flat | Globe |
|---|---|---|
| Game time | 13.1 min | 12.6 min |
| Goals done | 9 | 9 |
| First cash-in | 651 s | 495 s |
| Earned | 486 cubes | 419 cubes |

Same upgrades bought, no errors.

**Robots, globe:** 5 near robots and 0 stuck, 4 cells cleaned, live count equal to the cell recount, 126 cubes cashed.

**Soak:** orbD's `planet/sites/soak_watch.gd` (`--soak-hops`) covers long hub-hopping runs; not re-run for this audit.

## Core loop

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Walking, scooping, chest, carrying | works | | `SphereMotor` + `SphereCam`; `orbit_cell_cleaned`; autoplay. |
| Junk field (pieces, heaps, parts, wrecks, lakes) | works | | `SphereField` per cell; `orbit_has_dirty_near_cell`; `orbit_snap` cells. |
| Near junk view, LOD | works | | `SphereJunkView`. |
| Far junk | retired | | The globe's far shell (cells texture) replaces `FarJunk`. |
| Ground litter (`LitterView`) | missing | orbD | Dense ground-cover trash on junk cells. |
| Water view (`WaterView`) | partial | orbD | Lakes are cells with floating junk; no flat-style water surface pass. |
| Depot, scale, bale cash-in | works | | `--orbit-cash` (bale cashed, cubes 15 to 72); autoplay. |
| Pacing (scoop speed, bale size, hex value) | works | | Decision (b): cells hold a flat hex's volume; autoplay matches the flat game. |
| Hex clean flow, bonus, milestones | works | | `orbit_cell_cleaned`, `orbit_first_hex_milestone`. |
| Hex levels (sparse) | works | | `orbit_hex_level_1`. |
| Lumi Level | works | | Built; rewards ride the same flow. |
| World bounds / fall rescue | retired | | There's no edge on a globe; gravity keeps everything on it. |

## Base, progression and economy

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Hub (levels, upgrades) | works | | `orbit_hub_upgrade`; `orbit_site_stage` (the site prefab shows its stage). |
| Workbench, Upgrades screen | works | | `orbit_bench_*`, `orbit_upgrades_open`. |
| Research, Achievements, Codex | works | | Built through slice.gd's `_setup_research_codex`. Research isn't reached in a 13-minute autoplay on either game. |
| Goals, Tutorial, Objectives, cell outline | works | | `orbit_outline_*`; autoplay goals 9/9. |
| Contracts board | partial | orbB | Built; not exercised on the globe. |
| World events (+ streak HUD) | partial | orbB | Built; `tools/events_check.tscn` is flat-only. Port it to `--orbit`. |
| Camp: broken bench, trash bin, yard builds | works | | On orbD's anchors; `orbit_bin_prompt`, `yard_built` in the save comparison. |
| Stations (conveyor, auto baler, recycler) | partial | orbD / orbC | The machines stand in the yard, idle. The flat `Stations` node (their feeding logic) isn't built on the globe. |
| Composter (organic junk to seeds) | works | | On the start yard's `composter` anchor (YardSite's stand-in steps aside). Paper feeds it and it presses seeds. Checks: `orbit_composter_*`. |
| Seed finds (early trickle) | works | | `orbit_seed_finds`. |
| Garden (plant, water, grow) | works | | Sparse, per cell; `orbit_garden_planted`, `orbit_garden_slots_on_ground`. |
| Seeds unlock: First Seed (greenhouse, Settler tin, first sprout) | works | | The greenhouse stands on a clear patch east of the start yard (`FirstSeed.find_spot`). Checks: `orbit_first_seed_built`, `orbit_greenhouse_east_on_ground`, `orbit_seed_*` (prompt, cinematic, unlock, controls back). |
| Meadow (restored ground cover) | missing | orbB / orbE | Grass and flowers over restored cells. A per-cell `MeadowSphere` exists in history (cf2ca15, reverted for the playtest), ready to re-land. |
| Wildlife (butterflies, birdsong) | missing | orbB | Separate from Fauna; ambience over restored cells. A per-hub port exists in history (cf2ca15, reverted for the playtest), ready to re-land. |
| Fauna (animals) | works | | Per hub. Checks: `orbit_fauna_*` (frame, ground, upright far out, hops, sleep). Perf about 1.6 ms/frame. |
| Garden Mode decor | works | | Per hub; `orbit_decor_*`, `orbit_garden_mode_*`. |
| Outposts | works | | Per hub; `orbit_outpost*`. Robots delivering to outposts wait on orbC's real Fleet. |
| Signal Tower | works | | Built on its anchor. |
| Telescope (+ remote progress) | works | | `orbit_telescope_at_anchor`. |
| Extras: CD player, nursery, album, welcome back, Seed of the Week | works | | `orbit_radio_*`; the nursery is on its anchor. |
| Glim (light, scanner, upgrades) | works | | `orbit_glim_scan_marks`. |
| Cargo pods (other districts' robots pay) | retired | | Far crews on the globe are records that keep working (orbC, `orbit_offline_2h_within_10pct`). |
| Feel FX (bale press juice, hex reveal) | partial | orbB | The bale press squash runs (Patch calls it). The rest (bale pop, upgrade show-off, hex sweep on the local up) is in a stash on wt/orbB ("orbB Feel FX WIP"). |

## Robots and Command view

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Near robots (scoopie, haulbug, ...) | works | | `SphereCrew`; the `[bots]` table, stuck=0. |
| Far crews and offline | works | | `orbit_robot_near_far`, `orbit_robot_positions_within_1m`, `orbit_offline_2h_within_10pct`. |
| Fleet (`world.fleet`) and robot builder (parts, presets, traits) | partial | orbC | `world.fleet` is null on the globe; SphereCrew runs the robots. `RobotBuilder` isn't built. Autoplay buys no robots on either game in 13 minutes. |
| Water net (Drip refills) | missing | orbC | Outposts expose refill points; nothing reads them on the globe yet. |
| Bot Fabricator | works | | Built by `OrbitCrews`. |
| Command view | works | | `SphereCommand` + `CommandOverlay` (`cam.view = "command"`). |

## World, travel and sites

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Hub sites (10 on Verdance), site prefabs, stages | works | | `SiteManager` / `SitePrefab` / `VerdanceSite`; `orbit_site_stage`. |
| City blocks and street dressing | works | | Inside the site prefabs (`CityView` / `StreetDressing` per site). |
| Street power (broken lamps fixed with parts) | missing | orbD | The flat district's lamps; the globe's sites have none to fix. |
| Rocket between hubs | works | | `HubHop` (orbD); the HubFrame re-anchors (`orbit_fauna_frame_hops`). |
| Hover sled | works | | `HoverSled` (orbD). |
| Planet % (hub regions) | works | | `OrbitSites`. |
| Other planets (Rime, Tidewell, Anvil, Ochre) | partial | orbD | Their envs build sites on their globes. Their data JSON was missing from exports and is now packed. |
| Frontier districts | retired | | DECISIONS (Nov 9): they become parts of the other planets. |

## Story

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| WREN, subtitles, uplink | works | | Built; the Ledger's uplink lines run. |
| Intro cinematic | works | orbE | A new game plays the whole intro on the globe (ark, storm, fall, landing, wake). The landing and wake shots run in the start site's "pod" anchor frame (`Intro.site_xf`, level on the local up), the crash site lies on the pad, and the end places the pod the globe's way. Lumi stands on the ground beside it. Saves, tools and headless runs place the pod at once. Headless check: `--orbit --intro` (finishes, input restored, Lumi 0.0 m above ground, 3.4 m from the pod). |
| Crashed pod | works | | `orbit_pod_out_of_view`, `orbit_camera_clear_of_pod`. |
| Core charge | works | | Built. |
| Memory shards + document view | works | | In the start hub's region; they surface on the ground when their cell is clean. The paper view also opens the Ledger's contract and the eggs' notes. Checks: `orbit_shard*`. |
| Easter eggs, collectibles, museum | works | | Per hub; `orbit_eggs_*`, `orbit_egg_prompt`. |
| Ledger arc (drones, jammers, relay, resolve) | works | | Per hub; `orbit_ledger_*`. The resolve cinematic runs in the frame; I didn't take a picture of it. |
| Bloom (milestones, Seed Ark, finale) | works | orbE | Headless framing check (`--orbit --bloom-finale`, all planets): camera 1.3 m up, no roll, ark 40 deg up, same as the flat game. On a globe the orbit picks its clearest start yaw and a two-way spring arm keeps site geometry from blocking the view. Verdance, Anvil, Tidewell and Rime are clear. Open: on Ochre, Lumi's spawn spot is under or against the start site's geometry, so the camera can't see her from any side. That needs a site or spawn fix (orbD / p_ochre). |
| Late game: Ark Bridge, Cradle Mode worlds, Homeward | partial | orbB / orbE | Built (`LateDirector`, `HomewardDirector`, `ArkBridge`). Launching a new Cradle world onto a globe is unchecked. |

## Sky, maps, camera, UI

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Day/night, weather, clouds (`SkyDirector`) | works | | Sphere mode via OrbitLayers (orbE); `sky_spin` / `sky_clouds` in the save comparison. |
| Binary sun companion | works | orbE | The globe builds the same `BinarySun` (`sky_director.binary`: planet id, unshadowed warm fill). The sphere sky drives its fill along the spin; the world-space sky shader draws the disc. Tested in `tests/test_sky_sphere.gd`. |
| Future Layer | works | | `FutureLayerSphere`. |
| Survey hologram (`GlobeView`), system map | works | | OrbitLayers (orbE). |
| Photo mode | works | | OrbitLayers (orbE). |
| Lens view overlay | works | orbE | SphereCam has the lens view (V / R3, `--lens`): the eye at Lumi's lens, level on the local up. `LensOverlay` is built on the globe. Tested in `tests/test_sphere_lens.gd`. |
| HUD, pause menu, settings, music | works | | Built; one planet line on the globe. |
| Camera | works | | `SphereCam` replaces `CameraRig` (`world.cam` is null on the globe). |

## Saves and builds

| System | Status | Owner | Evidence and notes |
|---|---|---|---|
| Save / load (all systems) | works | | Orbit round trip (35 keys equal after reload); the fresh-process reload. |
| Old flat save migration | works | | `orbit_old_*` (fixtures). |
| Separate preview saves (`user://saves_round`) | works | | `tests/test_round_planets.gd`; a flat sentinel save stays byte-identical. |
| Steam Cloud | works | | Flat saves only; preview files never upload. |
| Exported build (macOS preset) | works | | `--export-pack "macOS"`, run with `--main-pack`: preview on, New Game on the globe, saved, Continue loaded it, no errors. This is a pack run on Linux, not a Mac binary. |
| Performance | partial | orbE | Fauna about 1.6 ms. orbE's pass and the Mac numbers are in docs/PERFORMANCE.md. |

## Gaps by owner

| Owner | Gaps |
|---|---|
| orbB | Wildlife and Meadow (re-land cf2ca15); Feel FX (stash); an `--orbit` events check and a contracts check; Cradle-world launch onto a globe (with orbE). |
| orbC | Fleet / robot builder on the globe; water net (Drip refills); haulers delivering to outposts. |
| orbD | Ground litter; water surface; street power; Stations' feeding logic in the yard (with orbC); other planets' end-to-end check. |
| orbE | Intro cinematic; binary sun; lens overlay; Bloom finale on the globe; perf on the Mac. |
