# M3-18 (rest): the five other cities

Nov 11 2026, on top of `da9bba2`. Renders: `screenshots/world/<city>/` (`sheet.png` plus its tiles; `ironside`, `kettle_bay`, `highreach`, `lowmeadow`, `old_capital`), all `opengl3` under xvfb, 1280x720, Medium, made with `tools/world_audit/world_shot.tscn`. Old Town checks are in `screenshots/world/old_town/`.

## 1. What was built

**Shared base.** `city_old_town.gd` (772 lines) is now 240: the pump house only. What every city shares moved out:

| File (`planets/verdance/sites/`) | Job |
|---|---|
| `verdance_city.gd` | The base every city extends: reserves the landmark's ground, builds street dressing, roofs, trees, ground, shop names, lamp glow and lake edge, `set_stage(0-5)`, `set_source_state("broken" / "shut_down")`, helpers to place landmark parts that show in one state only |
| `city_look.gd` | Reads `planets/verdance/data/cities.json`: palette, building mix, roof props, street dressing, names, landmark blocks, haze; owns the city's two building materials, so one city's lights come back without its neighbour's |
| `city_roofs.gd` | Roof props as MultiMeshes: tanks, signs, parasols (Old Town's), plus pitched roofs, saw-tooth skylights, hoardings, domes and flags |
| `city_street.gd` | Main street dressing: stalls (Old Town's), containers, crushed-car stacks, picket fences, banner poles |
| `city_kit.gd`, `city_film.gdshader` | Lattice towers, banded stacks, ball tanks, smoke, flat films (oil slick, stain, smog layer), lamp heads, lettering |

Each city is one row of data and one script that builds only its landmark (165 to 288 lines).

| City (site) | Look, from data | Source landmark | Running | Shut down |
|---|---|---|---|---|
| **Ironside** (7) | Low works in safety yellow, orange, container blue and red; saw-tooth skylights on about 240 roofs; stacks of crushed cars down the main street | Crusher yard: a yellow gantry crane over the street, a blue press with hopper and conveyor, a 44 m red-and-white stack over an orange boiler house, a wall of crushed cubes in car paint | Orange smoke, a crushed car on the hook over the street, amber beacon | No smoke, crane parked with the hook up, floodlights on, green beacon |
| **Kettle Bay** (3) | Navy, white, rust red and buoy orange; flags on the roofs; shipping containers down the main street | The tanker Long Tide, 70 m, driven bow first onto the shore where the lake took a block, listing; a dock crane at her bow | Rainbow oil slick on the lake and up the lot, a torn plate with a black run, the orange boom torn open | Slick gone, boom closed in a ring round the hull, deck lamps on |
| **Highreach** (8) | Glass-blue and white towers to 34 floors; magenta, cyan and yellow hoardings on about 140 roofs | Incinerator: three red-and-white stacks (54 to 72 m) on the main axis behind the waste bunker, a sky-blue boiler hall, a cyan tipping hall, a yellow conveyor gallery and a silver flue duct over the streets | Violet plumes and a lilac-to-peach smog layer over this district only (it thins with the district's stage) | Plumes and layer gone (blue sky), stack lights and plant lamps on |
| **Lowmeadow** (9) | Pastel houses (mint, butter, coral, sky, lilac) under red and green pitched roofs (about 330); white picket fences and letter boxes | Treatment works: two round settling tanks with scraper bridges, a butter-yellow digester, a 30 m coral-and-white header tower with a mint ball tank, a mint control house, three pastel dosing tanks, a cracked outfall | Lime sludge under a violet film, green fumes, a pink flare, a violet-and-lime stain down the lot | Clear blue water in the tanks, stain gone, a clear run at the outfall, lamps on |
| **Old Capital** (1) | Sandstone, cream and copper green; about 150 domes and 240 flags on the roofs; red and gold banner poles | Launch Pad 1: a concrete launch table with a flame trench, an orange mount carrying a rocket's first stage (cream, teal band, bare frames above), a 78 m red-and-white service tower with a hammerhead crane, two 56 m lightning masts, a propellant sphere, an assembly shed with a nose cone on a cradle | Top swing arm hangs broken, the sphere vents vapour, the pad is dark | Arms level, floodlights and tower lamps on |

All five: stages 0 to 5 through the same hook as Old Town (signs clean from 1, shop lights and lamp heads from 2, rooms lit and trees in leaf from 3, washed paving and shrubs from 4, blossom, flowers and every light at 5). The blocks between the yard and the landmark are kept open so the landmark closes the view on arrival. The yard's name sign now reads the city's own name (it read "OLD TOWN" in every town). Outskirts fill every block past the pad and carry streets, as in Old Town.

Other changes:
- `TownSite.set_source_state(state)`: a shared hook beside `set_district_stage`, a no-op by default. Nothing in the game calls it yet; the source gameplay (M3-07) should.
- `tools/world_audit/world_shot.gd`: `--shot-hub=N[,x,z,yaw]` (stand on any hub in its own frame, in daylight) and `--town-source=shut_down`.
- `cities.json` is registered as the planet's `cities` table (`planet.tres`, `core/planet_definition.gd` `OPTIONAL_TABLES`, one line in `docs/PLANET_PLAYBOOK.md`): the planets test requires every file in the data folder to be a registered table.

## 2. Performance (Medium, `--perf`)

| City | Street | Landmark view | 130 m | Command 300 m | Stage 5 |
|---|---|---|---|---|---|
| Ironside | **5.67 M**, 1,483 draws | 5.34 M | 2.29 M | 1.68 M | 3.27 M |
| Kettle Bay | **5.88 M**, 1,456 | 4.55 M | 2.21 M | 2.07 M | 3.43 M |
| Highreach | **5.99 M**, 1,385 | 6.08 M | 2.82 M | 2.13 M | 4.49 M |
| Lowmeadow | **5.30 M**, 1,138 | 4.71 M | 1.95 M | 1.75 M | 3.60 M |
| Old Capital | **5.85 M**, 1,268 | 6.19 M | 2.81 M | 2.29 M | 4.72 M |
| Old Town (`--orbit-spawn=54,10,0`) | 5.78 M, 1,206 (was 5.78 M, 1,200) | | | | 3.21 M (was 3.22 M) |

- Street camera: `--shot-hub=N,18,44,0` (the main street, looking north); Kettle Bay at `18,20`.
- Highreach and Old Capital first measured 7.05 M and 6.47 M. The cost was the detailed fronts of the ring next to the yard, about 0.3 M a floor. That ring is now 3 to 4 floors in both (towers start one block out). They pass by 0.2% and 2.5%: any new geometry there breaks the budget.
- **The yard view of Highreach (6.08 M) and Old Capital (6.19 M) is over 6 M.** Only the street view was the stated limit; I did not cut further.
- Low preset not measured.

## 3. Checks

- `tools/run_tests.sh`: 1,010 tests, 1,010 passing (17 new in `tests/test_cities.gd`; one of them checks Old Town's paint against the palette as it stood in code, over 300 buildings).
- Save round trip: **failed once, then passed four times in a row** with no code change between. The one failure was `orbit_ledger_drop_dirties_cell` at hub 0 (the Ledger's dump left its cell clean), in code this task did not touch, in the run straight after the unit tests. `tools/check_exit.sh` now reports PASS for the round trip (145 checks) and the orbit reload. I did not find the cause; treat the check as flaky until someone does.
- `--target-reach`: 5,645 targets on 10 hubs, 0 unreachable, PASS (was 5,640).
- Old Town: same stalls, tanks, signs, trees and station triangles in the build log as before; the street frame matches the M3-18b one.

## 4. Honest state: what is below the bar

**All cities**
- **The landmarks are plain procedural shapes** (boxes, cylinders, rods in the building shader). They read from 50 m and from above; within 10 m they have no bolts, ladders, railings, weld lines or decals. None is at hero-model standard.
- **Running against shut down is hard to see from the street** in three cities. Clear: Highreach (the sky changes), Lowmeadow (fumes and stain). Weak: Ironside (the smoke is above the frame from the lot; the hanging car is small), Kettle Bay (the slick is on the far side from the yard; it shows from above), Old Capital (a dropped arm and a vapour wisp are too small at 80 m; the lamps do not show by day).
- **Nothing is animated** but smoke and the beacon: the crane does not move, the scraper bridges do not turn, water does not run from the outfall.
- **Lamps are unshaded spheres**, with no light cast and no glow by day. No night render was made.
- **The yard itself is unchanged**: dark kit plates on pale swept ground fill the lower half of every stage 3 and 5 frame.
- The generic yard prop (radio mast, lighthouse, old bus) and the billboard still stand near the view line and sometimes cut across the landmark. Parked wrecks often block the low parts.
- Shop names and landmark names are plain painted words, not through `tr()` (as in Old Town).
- Trees, paving, lawns and flowers are Old Town's, with the faults listed in M3-18b.

**By city**
- **Ironside**: the yard has no fence, tyre piles or car-shell stacks inside it; the cube wall is one short row. From 300 m the gantry is a thin yellow line.
- **Kettle Bay**: one dock crane, not a row; no quay wall where the ship lies; the hull is flat-sided with hard chines; the ship's name is on the wheelhouse only. Container stacks stand in the carriageway and crowd the street camera.
- **Highreach**: the inner ring is 3 to 4 floors for the budget, so the yard is ringed by walk-ups with towers behind, not towers to the kerb. The smog layer is a flat sheet 95 m up: it tints the sky and does not fog the streets. Many pad fronts still read as red brick, not glass.
- **Lowmeadow**: 428 houses in all, the thinnest city; no drives, garden plots or hedges; gable ends take the roof colour; fences only on the main street. The tanks are 2.3 m high and hide behind wrecks from the lot; the header tower and digester carry the skyline.
- **Old Capital**: the pad does not yet read as the goal of the whole game. The stage is a banded cylinder with frames above; the tower top is out of frame from the yard; the fronts near the yard read as ordinary brick blocks and the street view is the least distinct of the five. No plaza, station hall or avenue was built. The audit's "transfer terminal" source was replaced by the launch pad as the task asked; its "broken / shut down" states are a stand-in until the rocket's build steps exist (M3-07).

## 5. Things to know

- **City layouts changed at the five sites** (building mix, open approach lots, landmark footprints, outskirts on every block), so hub-ground hexes there differ from before. District sizes and all balance data are untouched.
- Files outside the planet folder that were touched, and why: `planet/sites/town_site.gd` (source hook), `core/planet_definition.gd` (table name), `tools/world_audit/world_shot.gd` (flags), `docs/PLANET_PLAYBOOK.md` (one line).
- `OldTownTrees`, `OldTownGround`, `OldTownFlowers`, `OldTownShopSigns` now serve all six cities and keep their names.
- `verdance_site.gd` is 927 lines (was 902) and `verdance_city.gd` 506; both hold code that was already there.
- Every render run prints leaked-instance errors at quit (Old Town's too). I did not check whether they predate this task; the headless exit check reports none as a failure.
- Originality: nothing here was modelled on another game. The landmarks are ordinary industrial plant; names are plain words.
- `docs/ROADMAP.md` was not updated (outside this task's files).
