# M3-18c: polish of the five newer cities

Nov 11 2026, on top of `e31be04`. Sheets: `screenshots/world/<city>/sheet_c.png` (`ironside`, `kettle_bay`, `highreach`, `lowmeadow`, `old_capital`), each with before and after per fix and stages 0, 3 and 5. All renders `opengl3` under xvfb, 1280x720, Medium, one view per run, made with `tools/world_audit/city_shot.sh` (a wrapper round `world_shot.tscn`) and laid out with `tools/world_audit/city_sheet.py`.

The M3-18 sheets were not in the repository (PNGs under `screenshots/` are git-ignored and the earlier worktree is gone), so the "before" tiles were rendered again at `e31be04`. Kettle Bay's before tile of the running ship was rendered after step 1, because the first one faced north, away from the ship. The new sheets are force-added so they stay.

## 1. What changed

| # | Fix | What it is now | Where |
|---|---|---|---|
| 1 | Restored yards | From district stage 3 the yard and the two lots beside it take the city's paving, lawns, shrubs (stage 4) and flower borders (stage 5): a paved square in a planted frame with a lawn in each corner. The kit plates are hidden from stage 3; the lot dressing is tidied from stage 2 and gets planters at stage 4; the yard's ruin dressing (fallen name sign, tipped barrels) goes at stage 3. Each city's pavers take two colours of its own. No street tree stands across the view from the yard to the landmark. | `old_town_ground.gd`, `verdance_site.gd` (`_lot_state_now`, `_dress_level`, `_show_patches`), `verdance_city.gd` (`_across_view`), `cities.json` "paving" |
| 2 | Running against shut down | **Ironside**: a slewing scrap crane in front of the gantry swings a crushed car, the gantry trolley travels, two roof flues send an orange smoke banner across the frame, sparks at the press. Shut down: none of that, cranes parked, lamps with halos. **Kettle Bay**: a gash in the bow on the yard's side pours oil, a slick runs 30 m down the lot (kept free of junk). Shut down: a yellow plate over the gash, the slick gone, clear water in a closed boom with a lit buoy every six floats. **Old Capital**: a flashing amber alarm row along the table, venting at the stage and the trench, the broken arm sways with sparks. Made safe: a steady white row, floodlights. Lamp heads have a halo, so a lit lamp shows by day. | `city_ironside.gd`, `city_kettle_bay.gd`, `city_old_capital.gd`, `city_kit.gd` (`sparks`, `stream`, `glow`), `verdance_city.gd` (`place_part`, `move_part`, `_animate`) |
| 3 | Highreach smog | A street-level haze from the scene's depth: magenta close by, warm coral in the distance, thinning with height (the sky overhead stays blue), capped at 68% so fronts keep their colour. It thins with the district's stage and is gone when the plant is shut down. | `city_haze.gdshader`, `CityKit.haze`, `city_highreach.gd`, `cities.json` "haze_near", "haze_far" |
| 4 | Launch pad | A stone avenue through the approach block with a red and gold line, six pairs of 11 m flags, a red-and-white gate with the pad's name at its end, a red, white and teal target painted on the table, the pad's number on the tower. Once restored the approach block is an avenue between two lawns. | `city_old_capital.gd` (`_avenue`), `cities.json` landmark "avenue" |
| 5 | Lowmeadow | 869 houses (was 428): rows of three narrow houses or two wide ones with a drive between. Every low house gets a rail fence with a gate gap, a path, a hedge, a soil strip with flowers, and behind it a vegetable bed or a painted shed (139 drives, 462 beds and sheds). Gable ends take the wall colour. Tanks stand 4.8 m high (were 2.3 m) with turning scraper bridges; sludge spills over the rims and from the outfall while the works runs, clear water runs from the outfall after. | `city_gardens.gd`, `verdance_site.gd` (`_house_row`), `city_roofs.gd` (`gable_end_mesh`), `city_lowmeadow.gd`, `cities.json` "dense", "gardens" |
| 6 | Budget | `near_cap` (data) caps the floors of the ring next to the yard at 3 after the layout's draw, so both layouts are M3-18's. Highreach also has fewer roof props, stalls and kerb trees and a shorter detail range in its outskirts. | `verdance_site.gd`, `cities.json` |

**Bug found and fixed.** The cities' junk keep-off spots (Kettle Bay's slick, Lowmeadow's stain) were registered in the start yard's frame: they cleared junk at stray spots in Old Town and did nothing at their own hub. They now go in as world footprints in the hub's frame (`VerdanceCity._clear_ground`). Junk keeps off them when the town stands before the junk is laid, which is the order when a player walks in (towns build at 420 m, junk is laid nearer). `--shot-hub` stands on the hub at once, so `world_shot.gd` now moves junk off new keep-off ground the way the start yard does.

## 2. Performance (Medium, `--perf`, triangles in millions)

| City | Yard, stage 0 | Yard, shut down | Street, stage 0 | Yard, stage 3 | Yard, stage 5 |
|---|---|---|---|---|---|
| Ironside | 5.77 | 5.77 | 5.67 | 3.38 | 3.80 |
| Kettle Bay | 5.41 | 5.41 | 5.81 | 3.14 | 3.68 |
| Highreach | **5.92** (was 6.15) | 5.93 | 5.82 (before the last trim) | 3.98 | 4.77 |
| Lowmeadow | 5.09 (lot 4.68) | lot 4.68 | 5.38 | 3.93 | 4.62 (street 4.48) |
| Old Capital | **5.98** (was 6.21) | 5.96 | 5.72 | 4.42 | 4.78 |

Old Capital from 130 m: 2.71 (stage 0), 3.09 (stage 5); over the pad from 70 m: 4.32 and 3.99.

- Every view is under 6 M. The margins are thin: 1.4% at Highreach, 0.4% at Old Capital.
- About 70 s into every run the count rises by 0.108 M and 21 draw calls, in every city and before this task too. I did not find what it is. All figures here are after that rise (as M3-18's were).
- Changing a city's `rings` re-rolls its whole layout (one more or fewer random draw per ruined building); a first try that way moved Old Capital from 6.14 M to 6.41 M. `near_cap` avoids that.
- The haze costs one full-screen pass and a depth copy. Its cost in milliseconds was not measured (software rendering here). Low preset not measured.

## 3. Checks

- `tools/run_tests.sh`: 1,059 tests, 1,059 passing (8 new in `tests/test_cities.gd`). Save round trip: PASS; orbit reload: PASS.
- `--target-reach`: 5,635 targets on 10 hubs, 0 unreachable, PASS.
- `tools/warnings_audit.sh`: no new warnings in the files touched (project total 144, all in code that was already there).
- Highreach's shut-down yard and the five stage 3 yards were rendered again after the last data change. Highreach's street views and Old Capital's shut-down yard and 130 m views were not; they date from before the last trims (Highreach) and before the junk went back on the avenue (Old Capital).

## 4. Honest state: what is still below the bar

**All cities**
- **The yard view gives the landmark the top fifth of the frame.** The camera looks down at Lumi, so anything 72 m away is small. The new effects read, but none is loud: Ironside's sparks are a few yellow dots over the press, Kettle Bay's slick is a thin rainbow strip, Old Capital's alarm row is nine small lamps.
- **Motion was not checked in a render.** Every picture is one frame. The crane swing, trolley, bridges, alarm flash and arm sway are covered by a unit test of the part's transform only. Someone should watch them in a real session.
- **From stage 3 the yard's own name board stands in the view line** and covers part of the landmark (it comes with the yard's dressing at level 2). Wrecks stay parked in the lots at stage 5 (street furniture follows the base level).
- **Raising the yard's dressing to level 2 at stage 3 is my call**, to get rid of the fallen sign in a restored yard. It also brings the bunting and lights of that level. If the base level must stay the only thing that drives the dressing, revert `_dress_level` in `verdance_site.gd`.
- The restored yard is the same plan in every city (only the paver colours differ). Highreach's lilac and mint pavers may be too sweet, and Ironside's and Lowmeadow's wash out close to white in full sun at stages 3 to 5. Lawns are flat; stage 3 grass is pale.
- Landmarks are still plain shapes up close; names and the pad's number are plain painted text, not through `tr()`.
- No night render was made. Lamp halos were only seen by day.

**By city**
- **Ironside**: the gantry beam and its trolley are still above the frame from the yard; only the scrap crane shows. The smoke banner is thin at its far end.
- **Kettle Bay**: the lake slick is a sliver from the yard; the lot slick depends on the junk keep-off described above. The lit buoys are small.
- **Highreach**: the haze shader reads the depth texture. It works on `opengl3`; it was **not run on Vulkan** (Forward+ or Mobile), where the depth convention differs (the shader has a branch for it, untested). Smoke and glass behind the haze are not fogged. Not rendered from above. The yard is still ringed by three-floor walk-ups, now all of them.
- **Old Capital**: the pad reads as a destination from the yard and from over the lot, but from 130 m it is still small among the towers. The avenue is under junk at the start: I first kept it clear, then put the junk back, because the owner's rule is that nothing starts cleared. Flags are flat and do not move. The tower's top is still out of frame.
- **Lowmeadow**: hedges are textured boxes, fences are two rails and posts (no pickets, no colliders), beds are boxes. The main street mostly shows house sides, so fences show on the cross streets. The lot view was rendered from one spot only. The denser rows change which hexes are under houses at this hub.

## 5. Things to know

- Files outside `planets/verdance/`: `tools/world_audit/world_shot.gd` (junk re-seat for `--shot-hub`), `tools/world_audit/city_shot.sh` and `city_sheet.py` (new), `tests/test_cities.gd`. Nothing in `systems/research.gd`, `story/`, `ui/` or robots.
- `cities.json` is visual data only; no gameplay or economy table was changed. Layout changes: Lowmeadow (dense rows); Highreach and Old Capital keep their plans with lower buildings next to the yard.
- `verdance_site.gd` is now 1,007 lines (was 927), well over the style guide's 600; `verdance_city.gd` is 580. Splitting the site file was outside this task.
- Originality: nothing here was modelled on another game. Cranes, booms, flags and garden fences are ordinary real-world things.
- `docs/ROADMAP.md` and `docs/DECISIONS.md` were not updated (lead's files).
