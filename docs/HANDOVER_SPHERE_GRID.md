# Handover: sphere-grid (wt/sgrid, Nov 8)

## Done (committed, tests green)
- `planet/sphere/` started as a standalone module. It is now the game's ground: the slice builds on it through `planet/orbit/orbit_planet.gd` (`scenes/slice_orbit.gd`); the `--orbit` switch and `planet/orbit/verdance_globe.gd` are gone.
  - `sphere_grid.gd` `SphereGrid`: Goldberg hex globe.
    - Ids are the same as GeoSphere/PlanetData at the same level, and hierarchical (coarse ids are a prefix of the fine ones).
    - CSR-free neighbours (stride 6, counter-clockwise from outside), shared corners (triangle centroids), 12 pentagons (ids 0-11).
    - O(1) `cell_at` (cube-map buckets plus a greedy walk, about 3 µs), `cells_around`, `cells_within`, `distance_m`, `great_circle_m`, `frame(dir)`.
    - Chunks: nearest cell of level-4 (about 256 hexes).
    - Disk cache `user://sphere_grid_<lv>.bin`: level 7 generates in 1.2 s and loads in 30 ms. GeoSphere took minutes at level 7.
  - `sphere_terrain.gd` `SphereTerrain`: true-scale noise (7 m rolling at a 420 m wavelength, plus 0.9 m detail).
    - `set_cell_elevation(values, scale, offset)`: a per-cell layer (PlanetData.elevation), interpolated barycentrically.
    - `height`, `ground`, `ground_normal`, `altitude`, `local_to_dir` (exp map).
    - `reserve_site(cell, flat_m, blend_m, blocked)` flattens the pad to its exact tangent plane and returns a transform aligned to the surface normal (prefab local y=0 = ground, tested to 1 cm). It refuses overlaps. Also `release_site`, `site_at`, `site_chunks`. The sites array is copy-on-write, so worker threads are safe.
  - `sphere_cells.gd` `SphereCells`: packed per-hex junk/state/level/biome/flags, an RGBA8 state texture (512 wide), `flush()`, `to_dict`/`apply_dict`, `from_planet(PlanetData)`.
  - `sphere_streamer.gd` + `sphere_chunk_job.gd` `SphereStreamer`: chunk builds on WorkerThreadPool, at most 2 applied per frame.
    - LOD0: 24 tris/hex with noise-warped owner borders, within 240 m.
    - LOD1: 12 tris/hex, crack-free against LOD0, within 650 m.
    - LOD2: 6 tris/hex, out to the horizon computed from the view altitude (cap 2 km).
    - Far shell: level-5 icosphere reading the state texture. Only the shell draws above 1500 m.
    - Collision (trimesh) only within 70 m of BODY centres.
    - Near rings (70 m) for the view and every body: `near_changed(added, removed)`, `near_cells()`, `is_near()`.
    - Also `rebuild(chunks)`, `settle()`, `outlines` (debug hex lines), `lod_debug`, `stats`.
  - `sphere_ground.gdshader`: lifted from the orbit prototype ground, with the new state decode.
  - `sphere_demo.gd/.tscn`: `--sphere-demo` (removed with its hook in scenes/boot.gd; kept here as a record). Its flags were: `--sphere-cam=orbit|high|skim|ground`, `--sphere-alt`, `--sphere-speed`, `--sphere-outlines`, `--sphere-lod-tint`, `--sphere-nohud`. Keys: Tab, WASD, Q/E, O, L. Prints a `[sphere]` perf line every 3 s.
- Tests: tests/test_sphere_grid.gd (14 tests): counts, 12 pentagons, ids match GeoSphere, hierarchy, symmetry/CCW/shared corners, lookup round trip and brute-force check, metrics, rings, chunk partition, cache, site flatness, cells save, LOD border match, streaming budget, elevation layer, body near rings. Full `tools/run_tests.sh`: 501/501 pass, roundtrip PASS.

## Measured (headless, level 7)
- Ground view (Lumi camera, about 6 m up): 7 LOD0 + 16 LOD1 chunks, 92k ground tris, 3 collision chunks, 61 near hexes. Worker builds average 8 ms per chunk (max 21 ms); main-thread apply about 1 ms average.
- Command view (400 m up): 129 chunks (7/21/101), 262k tris.
- Orbit (2.5 R): far shell only, 20,480 tris.
- Demo: ready about 1.05 s, settle about 0.6 s.

## Next (not done)
- Gated renders of the demo were never captured: the render queue was busy. To capture them:
  - globe from orbit: `--sphere-cam=orbit`
  - ground skim showing the curve: `--sphere-cam=ground` and `--sphere-cam=high`, or `--sphere-cam=skim --sphere-alt=40 --sphere-speed=60`
  - hex outlines: `--sphere-outlines`
  - This used tools/shot.sh plus `--sphere-demo` (removed: shoot the game itself with tools/shot.sh), then copy the shots to /home/user/Greenfall/screenshots/sphere/.
- Rendered perf on the Low preset (frame time, draw calls, prims, video memory) comes from the `[sphere]` lines in that log.
- Ideas:
  - Analytic noise normals (cheaper builds).
  - LOD-aware shell (sinks 3 m today).
  - Using PlanetGlobe shaders for the far view.

## Decisions
- Size: level 7 (163,842 hexes), hex circumradius 10 m (17.3 m flat-to-flat, like the districts), R 1840 m, 11.6 km around (42 min on foot).
  - From Lumi's camera the horizon is 150-210 m away and dips 6.5°, so the ground reads flat nearby, with a gentle curve at the horizon. The orbit lead and owner agreed: no bend shader, true scale. The size table is in the header of sphere_grid.gd.
- The sky and sun in the demo follow the camera's local up (orbit prototype approach).
