# QA: round Verdance, first 60–90 minutes (owner item 41)

Glitch hunt on the default game (`--orbit`, first planet Verdance) by helper v3qa. Each row: what, status, and how to reproduce it. Positions are start-site local metres (x east, z south), the same as `--orbit-spawn=x,z`.

**Status:** fixed (with the commit tag `[v3qa]`), handed (to the helper who owns that area), open, or not reproduced.

## Tools used
- Soak: `godot --headless --path . -- --fresh --orbit --autoplay --soak --time-scale=8 --quit-after=2400` (game-minute lines `[soak] t=...`, `[soak] WARN ...`).
- Ground probe (new, `planet/sites/ground_probe.gd`): `godot --headless --path . -- --fresh --orbit --no-intro --ground-probe=300 --ground-probe-quit [--orbit-spawn=x,z] [--ground-probe-r=120]`. Lists floating and sunken props and junk pieces off the ground around Lumi.
- Round trips: `tools/run_tests.sh`; `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --orbit`.

## Glitches

| # | Area | What | Status | Repro |
|---|---|---|---|---|
| 1 | Progress | The story stopped at "Build your first robot": robots were built (cubes and parts spent, toast shown) but the step never completed, so nothing after it (zone, Haul Bug, seed, base levels) was ever offered. On the globe the Fleet keeps its robots in the crew and `robots()` is empty; objectives and goals counted `robots().size()`. The soak sat 36+ minutes with no new step after the Bot Bay. | fixed | Soak above: before the fix, `[onboard] objective bench2 done at 30.7 min`, then no objective for the rest of the run; `robot {"fleet":0,...}` events. Test: `tests/test_v3qa.gd::test_robot_objective_counts_globe_crews`. |
| 2 | Progress / save | "Send your robot to work" (paint a zone, B) could never complete on the globe: the count read the flat game's `GameState.world.orders`, and the globe crew's painted zones weren't saved either (lost on reload). | fixed | Paint a zone in the B view with a robot built: step stays at 0. Test: `test_globe_zones_count_and_save`. |
| 3 | Yard | Three small meshes of the workbench sit wholly under the ground (top 0.19 m below), at (-7.4, 8.2). Invisible; harmless. | open (cosmetic, not visible) | Ground probe at spawn: `[ground] sunk StartSite/Site_start_yard_#/Workbench/...`. |
| 4 | Soak | `Lumi stuck` warning at 5 min near the bin (-7.2, 2.9): autoplay shuttles between the bin and the junk next to it, so 3-minute displacement is under 3 m. Not a real stuck spot. | not a glitch | Soak, first 5 minutes. |
| 5 | Walking | Outpost wrecks on a slope: pieces float up to 0.56 m (a lying window frame, the tipped skip). The outpost stands on one tangent plane at its centre; the ground falls away under its far pieces. Now each top-level piece of the wreck (and of the rebuilt outpost) rides to the terrain under its own footprint, on the globe only. The rebuilt outpost's drop-in sparks also used world up (sideways on the globe). | fixed | Ground probe: `--orbit-spawn=160,0` (outpost near (176, -49)) and `--orbit-spawn=60,200` (near (-19, 180)): `[ground] float Outpost#/Ruin/... alt 0.56 m` before, gone after. |
| 6 | Events | Salvage Surge's sparkle tick picked a random piece of the glowing cell with `randi() % size`; a globe cell with no near pieces would divide by zero. Guarded. | fixed | Code path; not hit in two soaks. |
| 7 | Ground probe noise | Painted shop signs, neon backings and the billboard panel read as "floating" (they hang on walls and poles merged into big batches). Checked in code: they're attached. | not a glitch | Ground probe at spawn. |
| 8 | Robots / pad | The globe's Command view (B) only took the mouse: on a controller you could pan but not paint a zone or change the role, so "Send your robot to work" could not be done on a pad. Now the screen centre is the cursor (a reticle shows), hold A paints, hold X erases, Y cycles the role; the hint line follows the device. | fixed | Pad only: build a robot, D-pad down, try to paint. Test: `test_globe_command_pad_paints_and_cycles`. |
| 9 | Tools | Autoplay never painted globe zones (it wrote the flat game's orders, counted cleaners with the flat API and sorted cells by distance from the planet's centre), logged globe robots as type "?", and the soak didn't check SphereBots at all. Fixed in the tools: autoplay paints the crew's zones nearest the depot for the "Send your robot to work" step, and the soak warns on globe robots off the ground or stuck. | fixed (tools) | Soak: `robot {"fleet":0,"type":"?"}` before. |
| 10 | Progress (verified) | After fix #1 the soak's story moved on: `[onboard] objective robot done at 58.8 min` right after the first robot was built (soak 2). | verified | Soak above. |
| 11 | Night | Night at the yard (`--orbit-time=0.02`): moonlit, readable, the pod's plume shows. No glitch seen. | checked | `--rendering-driver opengl3 ... --orbit-time=0.02 --orbit-spawn=0,-6,180`. |
| 12 | Far water | From about 190 m north of the yard, the sea on the horizon reads as a flat grey plane with junk dotted over it. Probably the far water at a grazing angle; worth a look by the shoreline/world owner. | open (to check) | `--orbit-spawn=37,-189,0`, opengl3 render. |
| 13 | HUD | A long thin straight line across the junk field and faint dark lines across the pad (cell outline or paving seams?). | open (to check) | Yard render at spawn; `--orbit-spawn=37,-189,0`. |

## Not covered here
- Renders on Forward+ (lavapipe) were killed or ran under 1 fps on the shared box; the renders above use the Compatibility renderer (`--rendering-driver opengl3`), which runs fine.
- Frame times: the headless soak's `[orbit-perf]` numbers (avg 50–100 ms) reflect four helpers sharing four cores, not the game.

## Play-test, first 2 hours (helper v5play, 2026-11-10)

One 144-minute orbit autoplay from a fresh save (`--fresh --orbit --autoplay --soak --bot-debug --time-scale=8 --save-dir=...`), then a continue in new processes, plus the checks below. Fixes carry the tag `[v5play]`; tests are in `tests/test_v5play.gd`.

### New tools
- **Hinterland walk check** (`planet/sites/hinter_walk.gd`): `godot --headless --path . -- --fresh --orbit --no-intro --hinter-walk [--hinter-walk-spots=N] [--hinter-walk-at=x,z]`. Puts Lumi in the densest building clusters in view of the start town, flood-fills his box over a 50 m disc against the hinterland's colliders, lakes and steep ground, and reports walled-in pockets, shut directions, junk on unreachable ground and the tightest gap between two footprints. Exit 1 on a failure.
- **Bot escapes**: with `--bot-debug` every stuck escape prints `[bot-esc2]` with the place (start-site metres, as `--orbit-spawn`) and the colliders Lumi pushes against.
- **Soak digest**: also robots by type, zoned hexes, plants, loose bales, crew bales, Hover Jets, the story step, goals done, once-per-save flags and the rocket's hub. `--soak-bales` lists where the loose bales lie. `--crew-debug` prints each failed robot route.
- **Two-process reload** (`tools/orbit_reload_check.sh`) also checks the rocket's keys.

### Found and fixed

| # | Area | What | Status | Repro / check |
|---|---|---|---|---|
| P1 | Robots | Every Haul Bug stood "idle: no path" for most of the game: 301 bales waiting at 144 min, each hauler had carried about 20. In the town the cells under buildings and street kit are blocked for routes; on 17 m cells that cuts the cell graph into pockets, and a hauler inside one found no route to the Depot. It also picked the same unreachable bale again every second. Now a failed strict route falls back to a route over land through blocked cells (near robots steer round the walls themselves), and haulers skip a bale they just failed to reach. Same save, 9 minutes later: 218 bales waiting, haulers at 51-82 bales each, cubes 2K to 8.7K with Lumi standing still. | fixed | `--bot-report` on a long save: `idle: no path`. Test: `test_route_leaves_a_pocket_of_blocked_cells`. |
| P2 | Junk | Junk lay inside buildings on the outskirts and in the hinterland (10 and 37 pieces in two of four 50 m discs), where nobody can clean it. The keep-out filed each footprint under the 16 m buckets of sample points 8 m apart, so a bucket the footprint only clipped got nothing. Now every bucket the footprint's box touches. | fixed | `--hinter-walk` before: `junk ... / 37 unreachable`. Test: `test_keep_out_covers_whole_footprints` (435 of 68,820 points missed before). |
| P3 | Hinterland | A warehouse (18 x 15 m, on hexes 17 m apart) could stand 0.5 m from the house on the next hex, or overlap it: a wedge spot for Lumi (1.1 m wide) and robots. Now the smaller of two neighbours closer than 2.2 m is dropped (2 of 512 footprints in view of the start town). | fixed | `--hinter-walk`: `tightest gap 0.50 m` before, 2.33 m after. Test: `test_hinterland_leaves_no_wedge_gaps`. |
| P4 | Garden | A plant just across a hex border (or across the pad's edge) got no water, and a free spot there took no seed, though the ring showed it in reach: only Lumi's hex and the hex 1 m ahead were looked at. The autoplay bot stood for minutes "watering" such a plant. Now every hex the reach circle touches. A pour gives 60 s once (it was 30 s twice, as the plant was listed twice). | fixed | Test: `test_plant_over_the_hex_border_is_in_reach`. |
| P5 | Economy | On the globe scooped junk paid no Parts (the function returned early since the first globe port), so Parts came only from digs, events and requests. Base 2 (150 Parts) and base 3 (350) sat behind a Parts wall whenever the player had spent Parts on robots, and the hint "Dig up parts and salvage junk" was half wrong. Scooped metal, plastic and glass pay Parts again, as `data/hub.json` says (stat `parts_salvaged`). No cost was changed. | fixed | Run 1: Parts 14 from minute 51 to 69 while base 2 needed 150. |
| P6 | Clarity | "Rebuild the base to level N" and "Build a ..." showed no hint about what was missing. The card now says "Need N more cubes / parts" for base levels and robots too. | fixed | `--clarity-log` on a save at base 2: `card: Rebuild the base to level 3 | Need 7.6K more cubes. Pick up trash to earn them.` |
| P7 | Rocket / save | After a rocket hop, a save and a reload, Lumi stood at the far hub but the rocket was back on the start pad (and gone below base level 5): `save_world` rebuilt `GameState.orbit` without `rocket_site` and `rocket_owned`. Kept now. | fixed | `--rocket --orbit-survey-launch=0 --save-dir=X`, then continue with `--orbit-rocket-open`: `parked true at site 9`. `tools/orbit_reload_check.sh`: `rocket=kept`. |
| P8 | Rocket / goals | The goal "Launch the rocket onward" could never complete on the globe (it counted the flat game's districts) and had no beam. It now counts the hubs Lumi has flown to (`orbit.hubs_flown`) and the beam stands on the rocket, or leads to the bench while the base is under level 5. | fixed | Code; the goal comes after base 5, far past 2 hours. |
| P9 | Autoplay | The bot's sideways escape used world X/Z on the globe (a random slanted direction), so an escape rarely freed it: this is why "stuck escapes" climbed. It now steps sideways along the ground, and walks round the First Seed greenhouse. | fixed (tool) | Run 1: 14 escapes in a row at (-7.7, 9.3), then a `[bot-trap]`. |

| P10 | Garden | The watering can filled only on hexes with the hub flag. On the globe that is some of the pad's hexes, and not the one the workbench stands on: "Watering can is empty. Refill at the hub." and then nothing happened by the bench or the pod. It now fills anywhere within 16 m of the workbench too. | fixed | Autoplay with `--bot-debug`: `[bot-refill] ... water 0.0 / 30.0 at hex 99759 hub flag 0` for 30 minutes. |
| P11 | Rocket | At base level 5 the workbench's "Launch pad" row listed "Nearby bases" with Launch buttons that started the flat game's rocket on the globe: script errors (`Rocket._begin`, `_launch_camera`), no flight. On the globe the row now says "Walk to the rocket on the launch pad and press E to choose where to fly", and `Slice._launch` refuses with the same line. | fixed | Autoplay past base 5 (minute 232 of run 2): 5 SCRIPT ERRORs. `--rocket --bench-all --open=upgrades --tab=rockets`: clean. |
| P12 | Autoplay | After the Auto-Baler the bot moved it every second at 40 cubes a time (it compared a Stations-local point with a world position), so it never saved a cube again: 4,000 cubes in 8 minutes. It also bumped the bench on every refill. Both fixed; the bot no longer tries the flat launch on the globe. | fixed (tool) | Run 2: cubes near 0 from minute 109 to 170. |
| P13 | Tools | The ground probe counted junk lying on its heap as floating (300+ a disc in the hinterland). It now takes the heap's height off. | fixed (tool) | `--ground-probe=300 --orbit-spawn=27,401`: `junk=318` before, 0 after. |

### Stuck spots (lead 1)
- All 31 escapes of run 1 were at two places: the First Seed greenhouse at (11, 12), on the straight line between the bench and the eastern fields (15 escapes), and the nook between the shack and the workbench at (-7.7, 9.3), where the bot pushed at a plant behind the shack with a bale beside it (14 escapes, one trap). Neither is a trap for a player: both are visible obstacles with open ground round them. None at kerbs, quay railings, piers, new town buildings or the shore.
- Start town walk (`--city-walk`): 70,674 m2 free, all reached, out on every side, no pockets. Hinterland walk: four spots, all free ground reached, no pockets.

### Pacing, run 1 (before the fixes)
| Step | Bot minute |
|---|---|
| Baler, first bale, signal tower, Glim | 2.9 - 3.6 |
| First hex / 2 hexes / 3 hexes | 7.3 / 14.2 / 19.9 |
| Bot Bay (bench tier 2) | 20.1 |
| First Scoopie, first zone | 28.2 |
| Seed tin | 30.7 |
| 10 hexes | 38.4 |
| Haul Bug plans | 48.2 |
| **Base level 2** | **71.4** (33 minutes after "10 hexes") |
| Haul Bug, tower 2, research, 20 hexes (all done at once) | 71.5 |
| Hover Jets | 71.4 |
| Skimmer | 91.7 |
| **Base level 3** | **not reached by 144** |

Gaps over 8 minutes: Bot Bay to first Scoopie (8.1), 10 hexes to base 2 (33), base 2 to the end (73, base 3 never came). Causes: P1 (no hauling, so little income), P5 (no Parts) and P4 (the bot watered one unreachable plant for minutes). The bot also bought three Haul Bugs (146 Parts) while the card asked for base 2.

### Save and continue (lead 4)
- A continue in a new process after the 144-minute run: robots (5 Scoopies, 5 Haul Bugs, 1 Skimmer), 6 zoned hexes, 11 plants, 48 loose bales, 294 crew bales, Hover Jets, the story step (base 3), 42 goals, Glim repaired and every once-per-save flag came back. No WREN line and no once-per-save toast played again. Two exits and reloads in a row gave the same digest.
- Not a bug, a dev-flag limit: `--quit-after` quits without the save-on-close, so a reload starts from the last 60 s autosave. A player's quit (window close, pause, focus loss) saves.
- No SCRIPT ERROR and no warning in 144 minutes.

### Rocket (lead 3)
- The rocket comes with base level 5 (28,000 cubes and 140 Parts for level 4, then 30,000 and 110): far past the first two hours. The Upgrades tab says so on the base card, the Rockets panel says "The launch pad comes with a level 5 base", and the goal chain leads there (base 4, base 5, "Launch the rocket onward").
- With `--rocket`: the prompt "E  Rocket: choose a destination" shows at the pad, the list offers the six nearest hubs, the hop to hub 9 (1.6 km) lands Lumi by its pad and the save brings him and the rocket back there (after P7).
