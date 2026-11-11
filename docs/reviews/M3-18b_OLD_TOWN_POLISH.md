# M3-18b: Old Town polish

Nov 11 2026, on top of `7ee89f3` (resumed from two WIP snapshots). Renders: `screenshots/world/city1b/` (`sheet.png` plus its tiles), all `opengl3` under xvfb, 1280x720, Medium unless marked, made with `tools/world_audit/world_shot.tscn`. "Before" tiles are the M3-18a renders in `screenshots/world/city1/`; their cameras were not recorded, so the after views are close but not identical.

## 1. What changed

| # | Item | What it is now | Where |
|---|---|---|---|
| 1 | Street trees | Three bare-tree shapes: flared leaning trunk forking four times into limbs, branches and twigs (612 triangles, one MultiMesh a shape). Crowns are leaf clusters on the branch ends (14 alpha-cut leaf cards round a dark core, one MultiMesh for all 1,937 clusters), tinted by species, pale and small at stage 3, full at 4, a fifth of the trees in blossom at 5, with a light sway. | `planets/verdance/sites/old_town_trees.gd`, `tree_leaves.gdshader` |
| 2 | Burst main | A lathe-turned jet 14 m high with a looser skin and a falling curtain (scrolling water shader), flung droplets, rain off the head, drifting mist, a splash ring, and a flooded forecourt with ripples and sky sheen. Loose junk keeps off the water from stage 0. Shut down: cap and damp ground. | `old_town_burst.gd`, `burst_water.gdshader`, `street_flood.gdshader` |
| 3 | Crash furrow | One lofted trench mesh (lips, scorched inner face, dark floor) that shallows and closes at its tail, clods on the lips. Junk and litter keep off it through "soft" keep-out discs that do not make a cell start clean. | `story/crash_site.gd`, `planet/sites/yard_keep_out.gd`, `planet/orbit/sphere_field.gd` (`clear_keep_out`), `sphere_litter.gd` |
| 4 | Restored ground | From stage 3: clay paver paving with stone bands round buildings and on open lots, lawns in the courts, a grass verge at every street tree. Stage 4: washed paving, tufts and shrubs. Stage 5: flower borders and beds at the trees' feet in strong colours (one 87-triangle clump mesh, petal colour per instance). | `old_town_ground.gd`, `old_town_paving.gdshader`, `old_town_flowers.gd`, `old_town_flowers.gdshader` |
| 5 | Stage 5 render | `--town-stage=N` in the shot tool calls `TownSite.set_district_stage` directly; with `--district-stage=old_town:4` it gives a clean, fully restored town and no ending film. Stages 0 to 5 are on the sheet. | `tools/world_audit/world_shot.gd` |
| 6 | Street performance | Tiny litter items (cans, bottles) now hide past 38 m on Low and Medium (60 m on High and Ultra, as before); the paper sheets keep 90 m. | `planet/sites/sphere_litter.gd` (`TINY_RANGE_Q`) |
| 7 | Window speckle | Found the cause of the "dotted moire": the pane hash took an interpolated per-building offset whose last bits wobble, so curtain/glass/board flipped per pixel. The offset is snapped. Glass also no longer carries the wall's brick normal map. Shared shader, so every town gains. | `art/shaders/building_city.gdshader` |
| 7 | Shop names | 18 painted name boards on the buildings nearest the way from the yard to the pump house, past the yard dressing's own 52 m. One MultiMesh for the boards, a Label3D a name (hidden past 70 m). | `old_town_shop_signs.gd` |

A bug found on the way: the furrow's keep-off discs ignored the crash site's 0.5 rad turn, so only the half of the trench beside the pad was clear. The turn is now one constant (`CrashSite.YARD_YAW`) used by the placement in `scenes/slice_orbit.gd` and by the keep-out. No yard object moved.

## 2. Performance (`--perf`, street camera `--orbit-spawn=54,10,0`, stage 0)

| | Triangles | Draw calls |
|---|---|---|
| M3-18a figure, Medium | 7.36 M | 1,389 |
| This branch before the litter change, Medium | 6.16 M | 1,321 |
| After, Medium | **5.78 M** | 1,200 |
| After, Low | **3.68 M** | 1,063 |

- I could not reproduce 7.36 M: the first measurement here, with the new trees already in, gave 6.16 M. The old ball crowns or a different heading may explain the gap; I did not chase it.
- Low was not measured before the change.
- The budget is met at the named camera only. Looking west across the same street from (55, 3) reads 6.06 M on Medium.
- Other views after: yard from above 4.75 M, pumping station 4.15 M, main street stage 0 4.77 M, stage 5 3.22 M.

## 3. Honest state: what is still below the bar

- **Tree crowns** read as leafy trees at street distance, but each cluster is still a visible clump up close and the crowns are small for mature street trees; shadows under them are blocky.
- **Flower clumps** are faceted green domes with flat six-sided blossoms. Bright and readable from 30 m; stylised within 3 m.
- **Lawns and verges** are a flat textured quad: no blades at the edge, and bright yellow-green in full sun.
- **Flood** reads pale blue-white at a low angle rather than as a mirror of the buildings (no real reflection in this renderer). The jet is convincing from the yard, less so within 10 m where the scrolling texture shows.
- **Stages 1 and 2** still show the pale swept ground on open lots: paving only arrives at stage 3. Flat purple scraps stay on cleaned roads (existing litter decals, not touched).
- **Restored paving** is only seen on car parks, lots and the forecourt; roads and sidewalks are the shared town art and unchanged.
- **Shop names** are flat on the facade, so they read face on (the sheet's tile has a tree trunk across half of "CHEMIST") and not looking down the street. Hanging signs would fix that. Names are plain trades, not through `tr()`, like the existing yard signs.
- **Furrow**: clear and readable from above; the lips are low (0.36 m) and the soil is close in colour to the bare ground around it.
- Not done: lit windows by day are still flat yellow squares; the lamp glow is still a disc; `docs/ROADMAP.md` not updated (outside this task's files).
- `planets/verdance/sites/city_old_town.gd` is about 770 lines, over the style guide's 600; the new work went into separate files but the station builder still lives there.

## 4. Checks

- `tools/run_tests.sh`: 983 tests, 983 passing (8 new); save round trip PASS including `orbit_start_view_clear`; orbit reload PASS.
- `--target-reach`: 5,640 targets on 10 hubs, 0 unreachable, PASS. `--city-walk`: PASS.
- Originality: nothing here was modelled on another game. Shop names are ordinary trade words.
- Files outside the task's obvious set that were touched, and why: `scenes/slice_orbit.gd` (two literals became `CrashSite.YARD_YAW`), `planet/sites/sphere_litter.gd` (culling distance, soft discs), `planet/sites/site_manager.gd`, `planet/orbit/sphere_field.gd`, `planet/sites/yard_keep_out.gd` (junk keep-off for the furrow and the flood), `art/shaders/building_city.gdshader` (speckle fix).
