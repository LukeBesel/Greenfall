# Round planets: rollout after phase A

**Finished (Nov 11).** The round world is the only game: the flat mode, `--flat`, the title toggle and the phase A prototype scenes (`--orbit=globe`, `--orbit=v1`) are removed (docs/FLAT_REMOVAL.md). Old flat saves are imported once into the round save tree and migrate on load (OrbitMigrate). This file is kept as history; "the flat game" below means the removed mode.

Owner decisions are in `docs/DECISIONS.md` ("Round planets"). Phase A is on `wt/orbit` behind `--orbit`: the real Lumi (`player/patch.gd`) walks, scoops, presses bales, carries them and cashes them at a Depot on Verdance's 163,842-hex globe, with real day and night sides. Everything below builds on it. Start every helper from `wt/orbit` once phase A has merged.

## What already exists (read before starting)
- **Grid and streaming** (sphere-grid, `docs/HANDOVER_SPHERE_GRID.md`, `planet/sphere/`):
  - `SphereGrid`, `SphereTerrain` (incl. `reserve_site`, `set_cell_elevation`), `SphereCells` (per-hex junk/state/level/biome/flags, state texture).
  - `SphereStreamer`: threaded LOD chunks, collision near centres, a near ring per centre.
- **Movement** (sphere-move, `docs/HANDOVER_SPHERE_MOVE.md`):
  - `SphereSurface`, `SphereMotor`, `SphereCam` (follow and Command), `SphereBot`, `SphereSteer`, `SphereSwarm`, `SpherePath`, `SphereCrewSim`, `SpherePlace`, `SphereMath`.
- **Integration and phase A** (orbit):
  - `planet/orbit/verdance_globe.gd` (the `--orbit` scene).
  - `planet/orbit/sphere_field.gd`: a `HexField` over cell ids that materializes pieces in the near ring.
  - `planet/orbit/sphere_junk_view.gd`: the `FieldView` role.
  - `Patch.enable_sphere()`, `JunkCube.planet_radius`, and the Depot pad in its own frame.
- **Dev flags:**
  - `--orbit` and `--orbit-walk[=boost] --orbit-lap-quit` (the lap test)
  - `--orbit-walk --orbit-scoop` (scoop walk)
  - `--orbit-cash --orbit-cash-quit` (bale-to-depot test)
  - `--orbit-view=follow|ground|command|mid`, `--orbit-day=MIN`, `--orbit-time=0..1`, `--orbit-presim=MIN`, `--orbit-trail`
- **Rules for every helper:**
  - The flat game must keep working until phase F flips the default; the full suite and the save round trip must pass.
  - No curvature tricks. True scale.
  - Use local up (`surface.up_at(p)`) wherever code uses `Vector3.UP`, `.y` or `Vector3(x, 0, z)` for "horizontal".
  - About 1,200 such spots exist (`grep -n "Vector3.UP\|\.y = \|position\.y"` per folder). Fix them where your system needs it, not all at once.

## Order
- **Helper 1 (B)** goes first: it owns the scene the others plug into.
- **Helpers 2-4** start in parallel as soon as helper 1 has pushed the `--orbit` slice skeleton (B1).
- Each brief lists its first deliverable so the others can unblock.

---

## Helper 1: World and saves (phase B)
**Goal:** `scenes/slice.gd` itself runs on the globe under `--orbit`. One world per planet replaces the flat district. Saves store the planet, and old saves migrate.

1. **B1, skeleton (first, within the first day):**
   - With `--orbit`, `slice.gd` builds on `SphereGrid` + `SphereTerrain` + `SphereCells` + `SphereStreamer` instead of `HexField`/`FieldView`/`CityLayout`. Use `SphereField` as `field` and `SphereJunkView` as `view`. Real Patch, `SphereCam`, HUD, Depot.
   - Systems not ported yet are skipped behind `if not orbit`.
   - Push it; the other helpers build on it.
2. **Field:**
   - Move what the flat `HexField` still has into `SphereField`, per cell id: parts (`bury_parts`, `nearest_part`, so the detector digs), piles/mounds, landmarks (big wreck props on cells), `locked` cells (biomes), floating junk on water cells.
   - Port JunkLOD (`planet/junk_lod.gd`) onto `SphereJunkView`: near full meshes, a far impostor ring, budget per frame. The game density is 260-420 pieces per flat district hex, about 70 per 10 m globe hex; keep that.
3. **Hex clean flow:** `collect_piece` / `_on_hex_clean` / hex bonuses / milestones / `EventBus.hex_cleaned` / hex levels (`hex_levels`) by cell id. The ground focus ring takes a cell id (`set_focus_hex`).
4. **Saves (`SaveManager`, `GameState.world`):**
   - The planet is `SphereCells.to_dict()` (packed bytes) plus the sites.
   - Every position (Lumi, cubes, robots, props) is saved as a direction plus height, never a flat x/z. Add a schema version.
5. **Old-save migration:**
   - Map each old district hex to its planet cell (`slice_cells`, which already maps slice hex to planet cell at level 6).
   - Re-map level-6 cells to level 7: a level-6 id is a level-7 id, since the grid is hierarchical and coarse ids are a prefix.
   - Spread each old hex's junk fraction over the level-7 cells it covers, keep hub levels, and put Lumi at the start site.
   - Test it on the saves in `tests/fixtures/` (add one from main if missing).
6. **Done when:**
   - `--orbit` loads the slice on the globe with no script errors.
   - The save round trip (`tools/save_roundtrip.tscn`) passes with `--orbit`.
   - An old save loads into the globe.
   - The flat game is unchanged.

**[orbB] Status (Nov 8):** B1 skeleton, per-planet sizes, field parity, JunkLOD, the hex-clean flow by cell id, save schema 2 and old-save migration are done (`--orbit` round trip covers each). Since then (Nov 8-9) the game's systems run on the globe: per-hub world dict, Hub, workbench + Upgrades, Research/Codex, story (WREN, goals, tutorial, objectives + cell outline, core charge, signal tower, pod), events, Camp on orbD's anchors, extras, telescope, Glim, the garden (sparse), the autoplay bot, and pacing matched to the flat game (decision b). The "Not here" list in `scenes/slice_orbit.gd` names what is left and whose it is.

## Helper 2: Robots, Command view, offline (phase C)
**Goal:** the crew works the globe. Near robots are real; far robots are data. Command view drives them.

1. **Robots (`robots/`, `automation/fleet.gd`):**
   - Each robot type's movement goes through `SphereBot` + `SphereSteer` (or `SphereMotor` for wheeled bodies).
   - Jobs target cell ids: `claim_dirty`, `path` (`SpherePath.astar`), `work_cell`.
   - Scooping removes `SphereField` pieces near Lumi (`SphereField.reduce_to`) and numbers far away.
   - Every working robot registers a streamer centre (`set_centre(key, pos, BODY, ring_m)`), so its cell's junk is real while Lumi is near.
2. **Far crews:**
   - Past ~320 m from Lumi, a robot is demoted to a record (`SphereCrewSim.advance`, `to_record`/`from_record`) and is promoted back under ~260 m.
   - Far work uses the same per-hub rate maths as `core/offline.gd`. One code path for "off-screen" and "offline".
3. **Command view:**
   - `SphereCam` `view = "command"` (30-400 m) replaces the flat overhead camera. Zone painting, robot orders and hex picking ray-cast against the globe and return cell ids.
   - The hex outline overlay uses `SphereStreamer.outlines` (debug) or a proper decal pass.
4. **Offline progress (`core/offline.gd`):** per hub region, by cell id. It writes `SphereCells` and settles materialized cells (`SphereField.settle`).
5. **Done when:**
   - `--robots=scoopie:3,haulbug:2` on `--orbit` prints the `[bots]` table with no stuck robots.
   - Robots cleaning 1 km away change the far shell's colour.
   - A 2 h offline jump matches between flat and orbit within 10%.

## Helper 3: Hub sites, start yard, travel (phase D)
**Goal:** every hub is a site prefab on its pad, with the start yard as the shared vision describes it. The rocket hops between hubs, and boost/vehicle cover ground nearby.

1. **Site API:**
   - `PlanetEnvs` (`planet/planets/planet_envs.gd`, `data/planets.json`) gets `build_site(site_root: Node3D, site: Dictionary, stage: int, restoration: float)`.
   - `site` is what `SphereTerrain.reserve_site` returns: `transform`, `flat`, `blend`, `cells`.
   - The cloud renders showed grey-box buildings: those were phase-A stand-ins. Real city dressing (the flat game's `StreetDressing`/`CityView` buildings, props and materials) must come over here; nothing blocky ships.
   - Prefabs are 60-100 m and built in site-local metres (+Y up, y = 0 on the pad), with their own collision. They provide named anchors (`depot`, `bench`, `rocket_pad`, `door`) and `set_stage` / `set_restoration`.
   - Port Rime first (it's already in that shape), then Ochre/Tidewell/Anvil from their helpers.
2. **Verdance hubs:**
   - The 10 hubs come from `PlanetData.hubs` (farthest-point subset, see `verdance_globe.gd:_place_hubs`).
   - The start yard is pod + broken workbench + trash bin; everything else is a Hub build. `planet/street_dressing.gd` and `planet/city_view.gd` become site prefabs: ruined blocks on the cells around a hub, not a flat city.
3. **Rocket between hubs:** `GlobeView` / `_launch` (`scenes/slice.gd`) land at another site's `rocket_pad` anchor on the same globe. There's no scene change on the same planet; teleport plus a short flight cinematic over the curve.
4. **Ground travel:** a buyable vehicle or hover-sled (an `Upgrades` entry) as a `SphereMotor` with higher speed and inertia, plus enter/exit. The x4 boost already exists (Shift/LT, `SphereInput`); add it to Settings key binding.
5. **Planet %:**
   - Counted over hub regions: the cells within N rings of each built hub (owner decision).
   - The rest of the globe greens slowly as hubs thrive: a per-hub growth radius on `SphereCells` state, shown on the far shell and the survey hologram.
6. **Done when:**
   - All 10 hubs exist as sites on Verdance and Rime's env builds its site on its own globe.
   - A rocket hop works both ways.
   - The vehicle drives a full lap.

## Helper 4: Sky, story layers, maps, polish (phase E + F)
**Goal:** everything that looks at the world from above or over time works on the globe, and it holds up on a Mac.

1. **Day and night:**
   - Merge `planet/sky_director.gd` (weather, clouds, Glim, the binary-sun look) with phase A's real day/night sides (`verdance_globe.gd:_update_day`: two suns fixed in space, planet turns every 24 min) and its world-space sky (`planet/orbit/orbit_sky.gdshader`: zenith = local up, haze below the horizon, stars at night, never black). The flat game's PhysicalSkyMaterial can't be used with a rotated sky dome (the cloud renders showed a black sky).
   - Night readability rules from the shared vision. Glim's light replaces phase A's Lumi lamp.
2. **Future layer (`planet/future_layer.gd`):** per cell from `SphereCells.level` (4 bits), drawn on chunks near the camera.
3. **Survey hologram, `GlobeView`, system map (`ui/system_map.gd`), `PlanetGlobe` (`ui/planet_globe.gd`):** read `SphereCells` directly (same ids), with a "you are here" marker from Lumi's cell.
4. **Homeward / cinematics / photo mode:**
   - Every camera that assumed world up uses the local frame.
   - Space shots (`story/space_stage.gd`) can show the real globe.
5. **Performance (F):**
   - On Low at 960x540 and on a Mac: draw calls, triangles, junk instances, chunk build times.
   - Tune streamer radii, LOD distances and junk density. Target: 60 fps on the owner's Mac on Medium.
6. **Flip the default (F):** after owner review, `--orbit` becomes the game and the flat district code is retired.
7. **Done when:**
   - Day/night works across a full lap (with renders).
   - Hologram and map match the walked state.
   - Perf numbers are in `docs/PERFORMANCE.md`.
   - The owner signs off on renders.

---

## Shared checks for every helper
- `tools/run_tests.sh` (all pass, round trip passes).
- Headless autoplay at 200 s with 0 SCRIPT ERROR (flag off).
- `--orbit --orbit-cash --orbit-cash-quit` prints `PASS`.
- `--orbit --orbit-walk --orbit-lap-quit --time-scale=8` prints `LAP ... PASS`.
- Commit locally and send "ready to merge". The coordinator pushes and reconciles.
