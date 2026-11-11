# M3-20: crew pacing and the robot chain (Nov 11)

What was built, the crew's size city by city, the chain's numbers, the first robot in two fresh bot runs, and the frame time with 200 robots. The accepted numbers this follows are in `docs/design/PLANET1_DESIGN.md` section 17 and `docs/reviews/BALANCE_PROPOSAL_P1_V2.md`.

**Verdict.** The crew's size, prices and growth are data now, and the chain is in the game: Scroungers dig buried parts out of cleaned ground, the Assembler builds robots from Parts in the player's mix, and the player paints where Scroungers search. On the accepted pace the crew is 8, 50, 74, 98, 123 and 159 after the six cities (accepted: 8, 50, 72, 94, 119, 147), inside 100 to 200 at the launch point, and it cannot run away. Two fresh bot runs still meet M3-21's city 1 targets (first robot at 8.7 and 8.9 minutes). With 200 robots the crew costs about 4 to 5.5 ms a frame on the shared build machine, down from over 16 ms, and the 850 ms hitch is gone. **Not verified in the game itself: cities 2 to 6.** Their waste kinds are not built, so the crew there is checked in the simulator and in tests, not by a bot.

## 1. Crew size by city

`godot --headless --path . res://tools/crew_sim/crew_sim.tscn -- --policy=all`. The simulator is new (`tools/crew_sim`): it plays the six cities on the game's own chain rules (`core/crew_chain.gd`, `core/crew_rules.gd`) and the game's tables. It runs in player time, because robots and the Assembler's line work in real time.

| After city | Accepted | Simulator, default player | Cap | Only Scroungers on the line | No Scroungers |
|---|---|---|---|---|---|
| 1 Old Town | 8 | 8 | 8 | 0 | 8 |
| 2 Ironside | 50 | 50 | 56 | 38 | 50 |
| 3 Kettle Bay | 72 | 74 | 90 | 61 | 68 |
| 4 Highreach | 94 | 98 | 120 | 84 | 83 |
| 5 Lowmeadow | 119 | 123 | 160 | 108 | 104 |
| 6 Old Capital (the launch point) | 147 (149 at launch) | 159 | 200 | 144 | 140 |

Crew by player minute, default player: 10: 0, 20: 3, 30: 8, 50: 11, 60: 23, 80: 47, 100: 63, 120: 79, 140: 94, 160: 110, 180: 125, 200: 140, 220: 155.

- **Cities 1 to 5 are within 5% of the accepted crew.** The launch crew is 159, inside the owner's 100 to 200. It is 10 above the accepted 149 because the rocket's six parts are not in the game yet: in the proposal they hold the line for about nine player minutes of city 6.
- **The climb is paced.** Fastest doubling: 250 player seconds (8 to 16 robots at the start of city 2, by hand; the rule is no faster than 180). Longest wait for a new robot from city 2 on: 80 seconds (the rule is 360).
- **The chain cannot run away.** Three things hold it, each a number in the table: the line builds one robot per 80 s whatever the Parts; the cap; and the ground. A line that builds only Scroungers ends with a smaller crew (144), and it would have cleaned nothing. With ten times the hand Parts the crew still stays under each city's cap and never doubles in under three minutes (a test holds this).
- **Without a single Scrounger the crew still reaches 140.** That is higher than the proposal's 120 for the same player. Reason: the Haul Bug costs 6 Parts since M3-21 (the proposal had 16), so hand Parts alone pay for most of a crew. See open point 2.
- **What the simulator does not do:** cleaning speed. The minutes per city are an input (the accepted 48, 35, 31, 31, 32, 48), so it shows how the crew grows across a planet played at the accepted pace, not how fast a crew cleans. Cities 2 to 6 have no wrecks, slick, smog or blight in the game yet, so the Parts Lumi's hands bring there are the proposal's, marked ESTIMATE in `tools/crew_sim/calibration.json`.

## 2. The chain's numbers

All in `planets/verdance/data/robots.json`.

| Number | Value | Note |
|---|---|---|
| Crew cap by cities open | 8, 56, 90, 120, 160, 200 | accepted |
| Crew cap by base level | 4, 8, 56, 120, 200 | new: the game has five base levels and sells levels 2 and 3 in city 1, so the cap is the smaller of the two lists |
| Robot price growth | x1.0 per robot owned | was a literal x1.2 in `robots/fleet.gd`: the 30th Scoopie would have cost 1,977 Parts |
| Robot prices (Parts) | Haul Bug 6, Scoopie 10, Scrounger 18, Skimmer 22, Drip 22, Seedling 30, Multibot 45 | Scrounger 18 is the accepted price |
| Tiers | Rusty x1.0, Repaired x1.6 (a repaired type costs x1.5 to build) | two tiers, was four (Mk I to IV at 200, 700 and 2,000 Parts) |
| Tier step | the type's 30 to 90 Parts + 0.9 x build price x robots owned, at most 600 | open from the second city |
| Crew upgrades | Parts, 4 or 5 levels, 8 to 82 Parts a level | were cubes, 15 levels, the last over 60,000 |
| Dearest crew price | 600 Parts (a tier step at its cap) | the planet's largest Parts price is the rocket's 600 |
| Buried parts per cleaned hex | 0, 1.0, 1.8, 2.2, 2.0, 2.4 by city | accepted. 10,491 in all six cities |
| Arrival salvage | 130 Parts in city 3 | accepted: it pays for the Assembler (45) at once |
| Scrounger | 2.4 m/s, digs a part in 2 s, carries 8 | a full sack takes 140 s from ring 3 and 250 s from ring 9: 1 to 3.5 Parts a minute each, falling as the cleaned ground moves out. A test holds the simulator's trip within 25% of the real robot's |
| Assembler | 45 Parts, on offer from city 3, one line, 80 s a robot | the accepted 40 s was on the bot's clock; 80 s in real time gives the accepted 22 robots a city |
| Default build mix | Scoopie 3, Haul Bug 2, Scrounger 1 | the player changes it at the bench |
| Redeploy | a robot idle for 45 s in another city is shipped to the city Lumi is in | new |

Parts over the whole run (default player): 9,963 earned (8,348 by Scroungers, 1,485 by hand, 130 salvage), 3,417 spent on robots, 1,025 on tier steps, 5,476 left. The accepted run earned 9,935 and left 1,521 after the rocket's 2,600: the same surplus.

## 3. What was built

| Rule | Where |
|---|---|
| Crew cap and every robot price from the table | `core/crew_rules.gd` (new). `robots/fleet.gd` asks it; the literals x1.2, x1.35 and the Mk prices are gone. One cap for the whole crew: it was a cap per job |
| Crew upgrades in Parts | `Economy.upgrade_currency`; an upgrade row may name a `currency`. The bench list, the robot card and the upgrade card show it |
| Scroungers | A robot type with role `find`: `robots/sphere/sphere_scrounge.gd`, called from `SphereCrew`'s brain, so one near Lumi and one far away as a record behave the same. Its look is a Scoopie body with a detector coil and a parts crate (`robots/robot_visual.gd`). Plans arrive with the second city (`research.json`, new condition `cities_open`) |
| Buried parts tied to cleaned ground | `core/crew_chain.gd` (new, plain data). A hex is seeded the first time it is clean, once, whoever cleaned it. Dirtying it again and cleaning it again gives nothing |
| The Assembler | A base build (`systems/camp/hub_builds.gd`, `builds.json`), on offer the first time Lumi stands in city 3. Its line is `CrewChain.tick_line`; the node is `systems/crew/robot_chain.gd` (new), stepped on the fixed tick. The building is `automation/assembler_model.gd`, at the back of the start yard (position in the table); one render checked it stands clear of the city's name board |
| Build mix | `ui/assembler_panel.gd`: a row in the workbench Bots tab once the Assembler stands. A share number per type with - and +, the share in percent, the Parts for one, the next six robots, Pause |
| Search and work areas | Command view's zone painting, as before, with one more role: Tab now cycles Clean, Search, Plant, Water, Haul. The label at the top names the area being painted. Zones are saved with the crew |
| Where robots work | New robots work for the base of the city Lumi is in; idle robots in another city follow (`RobotChain.redeploy`, `SphereCrew.reassign`) |
| Events | `EventBus`: `parts_scrounged`, `salvage_found`, `assembler_offered`, `assembler_built`, `robot_assembled`. Nothing calls UI |
| Save | `GameState.orbit["chain"]` (ground, mix, the robot on the line). A Scrounger's sack is saved with the robot. An older save loads with its clean ground spent and nothing built |
| The bot | Buys crew upgrades and tier steps with Parts only when the crew is full (section 4); never spends Parts on them through its cube rule. It builds a Scrounger for every six robots once it has the plans, and the Assembler when it is on offer (neither happens in city 1). The city 1 simulator (`tools/pace_sim`) mirrors the Parts rule |
| Dev flags | `--assembler`, `--chain-ground=RINGS[:PARTS]`, `--zone=ROLE:RINGS`, `--chain-report`; the `[bots]` report prints the crew's cost per frame |

Files outside `robots/*` and planet data that had to change, and why: `autoload/Economy.gd` (upgrade currency), `autoload/EventBus.gd` (five signals), `autoload/DevHooks.gd` (flag list), `systems/research.gd` (one condition), `systems/camp/hub_builds.gd` (the build), `scenes/slice_orbit.gd` (creates the chain and saves it: 7 lines), `ui/bench_bots.gd`, `ui/bench_lists.gd`, `ui/robot_card.gd`, `ui/upgrade_card.gd`, `ui/hub_panel.gd` (prices and cap shown), `tools/autoplay.gd`, `tools/pace_sim/*` (the same rules), `tools/orbit_roundtrip.gd` (the chain in the save round trip), `planet/sphere/sphere_bot.gd` and `planet/sphere/sphere_swarm.gd` (the near robots' cost, section 5), `planets/verdance/data/research.json`, `builds.json`, `codex.json`, `locale/*` (36 strings), and four older test files (section 7). `planets/verdance/data/districts.json` and everything under `planets/verdance/sites/` are untouched: the per-city chain numbers are in the robots table.

## 4. The first city: two fresh bot runs

`godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=250`, twice on the final build, one after the other. No SCRIPT ERROR, no bot trap. Seconds from the moment the bot takes control.

| Target (M3-21) | Limit | M3-21 runs | Run 1 | Run 2 | Result |
|---|---|---|---|---|---|
| First clean hex | under 90 s | 86, 54 | 58 s | 58 s | met |
| First robot (a Haul Bug) | by minute 12, near minute 9 | 9.7, 8.5 min | 8.7 min | 8.9 min | met |
| Longest wait between purchases, first 20 min | 120 s (the seed tin accepted) | 136, 130 s | 125 s | 126 s | as before |
| A hex, through minute 15 | about every 60 to 90 s | 75, 64 s | 71 s (12 hexes) | 73 s (12 hexes) | met |
| Most cubes held | under 5,000 | 450, 709 | 706 | 682 | met |
| Largest price in city 1 | under 4,200 | 4,000 | 4,000 | 4,000 | met (unchanged data) |

- **Crew at the end of the runs (game minute 32): 2 robots,** a Haul Bug and a Scoopie, of a cap of 8. The Scoopie stood at minute 17.2 in run 1 and minute 25 in run 2. Its plans arrive near minute 17 in both; what moves it is Parts: in run 2 the bot holds 4 to 9 Parts from minute 12 to 25 (it spends 6 on Glim at minute 11), and the Scoopie costs 10. That is the "Parts are hard to get early" rule at work, and the spread is the luck of buried parts.
- **One thing the first run of this task showed and the bot now avoids.** With crew upgrades priced in Parts, the bot bought the Haul Bug's Drive Motors (8 Parts) while it waited for the Scoopie's plans, and the Scoopie came six minutes late. The bot now keeps Parts for the next robot while the crew has room. A player will meet the same choice; the bench shows both prices.
- What changed before the first robot: nothing the bot can see. The crew cap is 4 at base level 1 (it was 3 per job) and 8 at level 2. Crew upgrades no longer take cubes.

## 5. 200 robots: frame time

`godot --headless --path . -- --fresh --robots=scoopie:100,haulbug:60,scrounger:20,skimmer:20 --chain-ground=8:2 --perf --quit-after=180`. All 200 work round the start base: 48 are real robots near Lumi (the crew's near budget), 152 are records. The machine is a shared 4-core VM with no GPU and other builds running (load 2 to 5), so every number is wall-clock on a busy machine; the "best second" row is the fairest one.

| | Before | After |
|---|---|---|
| Crew cost per frame, average | about 16 ms (thinking 9.6; the near robots' own steps about 6.9, from a separate profiling run) | 5.4 ms (thinking 1.5, near robots 3.9) |
| Crew cost per frame, best second | not measured | 4.0 to 4.2 ms |
| Worst frame | 849 ms | 57 ms, on the crew's first frame (under the loading screen) |
| Whole headless frame | 18 to 65 ms (15 to 57 frames a second) | 11 to 18 ms (55 to 90 frames a second) |
| Frames in the same 180 s run | 6,321 | 11,081 |

The budget in `docs/PLAN.md` is 60 frames a second and no frame over 100 ms in play. The crew now takes about a quarter to a third of a 16.6 ms frame on this machine, with rendering not counted (headless). `docs/PERFORMANCE.md` does not exist yet (M7-01), so there is no agreed share for the crew to hold it against: open point 11.

What was slow, and what changed (`robots/sphere/sphere_crew.gd`, `planet/sphere/sphere_bot.gd`, `planet/sphere/sphere_swarm.gd`):
- **Looking for work.** Every idle robot searched its hub's whole region about once a second, then searched a route; across a lake the route search failed after 6,000 steps (up to 100 ms) and the robot tried the next hex a second later, for ever. Now: land robots only claim ground they can drive to (one flood per hub, kept until buildings change); a search that found nothing is not repeated for 1.5 s for that job and hub; searches started in one tick are capped at 1.5 ms; a robot whose routes fail waits up to eight times longer.
- **All far robots stepped on the same frame** every quarter second. Each now has its own clock.
- **Near robots thought every frame while working.** They now think every fourth tick with the time since. The "tight corner" check scanned every building each frame; it is looked up once per waypoint.
- **Near robots' steps.** Two neighbour searches of 27 buckets became one search of the buckets in reach; buildings are looked up every eighth step; the terrain normal (three ground samples) is taken again only after 0.4 m; a parked robot keeps its transform; robots more than 45 m from Lumi animate every second frame, more than 110 m every fourth.

The search and clock rules have tests in `tests/test_crew_chain.gd`; the near robots' movement is covered by `tests/test_sphere_crew.gd` and `tests/test_sphere_move.gd`, which pass unchanged. The robot report (`--robots`, `--bot-report`) now prints the crew's cost per frame.

Not done: the near robots' steps are still two thirds of the cost (about 80 microseconds each a frame on this machine). The next step would be stepping robots that are off screen at half rate.

## 6. Open points

1. **The Assembler stands in the start yard, not in city 3.** The only base with a bench is the first one. It is on offer when Lumi first stands in Kettle Bay, and it is built at the back of the start yard, beside the city's name board (`chain.assembler.pos` in the table; the old `fabricator` anchor is now under that board). When city 3 has a base site of its own the table can name an anchor there instead. Design call: is it right for city 3's landmark to stand at home?
2. **Parts are in surplus from city 3, and a player with no Scrounger still gets 140 robots.** The accepted proposal has the same surplus on purpose (the line paces the crew, the surplus pays for the rocket). With the Haul Bug at 6 Parts it is larger. If Scroungers should matter more: a dearer Haul Bug after city 1, or a smaller hand yield in cities 3 to 6.
3. **The rocket's six parts are not built.** They are the late use for 2,600 Parts and take the line for part of city 6. Without them the launch crew is 159, not 149.
4. **Tier steps have no "repair bench" gate.** The proposal opens them with a research the game does not have. They open with the second city (`price.tier_cities_open`).
5. **Robots are shipped between cities, not driven.** An idle robot in an old city appears beside the base of the city Lumi is in. Cities are 1.6 to 5.5 km apart across lakes: a drive would take over half an hour. The player does not see it happen: Lumi is in the other city, and a robot that happens to be near her is taken off the ground first. Design call: a visible transport (a crawler, the rocket's hold) later?
6. **Cleaners work a base's region, not the city's rings.** `SphereCrew.rings` is one number for the planet. A city of 26 rings is larger than that region. Not changed here; it belongs with the cities (M3-18) and the balance pass (M3-12).
7. **City 2 is still a robot every 50 seconds at the bench** (the proposal's open point 8.6). The Assembler arriving in city 2, or a "build 5" button, would fix it. Not changed: the owner put the factory in city 3.
8. **No bot run plays the chain.** The bot has rules for a Scrounger and for the Assembler, but it cannot reach city 2, so neither was ever used in a run. The simulator and the tests stand in for it.
9. **The flat Command screen (`ui/command_view.gd`) still shows a job's robots against the whole crew's cap.** It is the flat world's screen; the globe uses `SphereCommand`.
10. **The whole translation template is out of date** (it was before this task: M3-19's and M3-21's strings are missing). Running `tools/extract_strings.py` rewrites 34,000 lines of the locale files and drops the parked features' translations, so this task added only its own 36 strings to each file, with machine drafts for the six languages. Regenerating the template is a task of its own.
11. **No agreed frame-time share for the crew.** See section 5.
12. **Nothing here copies another game.** A factory that builds workers from gathered parts is a common shape in games about automation. Ours is tied to cleaned ground (a hex gives its parts once), has one line and no conveyor layouts, recipes or factory planning; the names and the look are the salvage theme's own. Flagged so the lead can judge.

## 7. Tests

1,034 pass (1,028 before this task). The save round trip passes (`tools/check_exit.sh`): it now stands the Assembler up with a mix of the player's and a robot half built, buries parts in a hex, gives a robot a sack, saves, loads and compares; and it loads the old flat fixture save and checks that its clean ground is spent and nothing is on offer.

`tests/test_crew_chain.gd` (41 tests), by rule:
- **Cap and prices are data:** the cap is the smaller of the two lists; a table without them keeps the old rule; the first planet holds the accepted crew per city and never more than 200; a price does not compound; the fleet reads prices from the table (first planet and dummy planet); a tier step's price and its cap; no crew price passes 600 Parts with 0 to 200 robots of every type; crew upgrades take Parts and not cubes; a full crew blocks building and says whether the base level or the next city is missing; tier steps open with the second city.
- **Growth is tied to cleaned ground:** a hex leaves its parts once; parts dug never exceed parts seeded; delivered Parts are paid whole and none are lost; arrival salvage is paid once; the first city has no buried parts and the Assembler belongs to the third.
- **The line:** one robot at a time, paid up front, after the assembly time; it waits for Parts (keeping the reserve), for room and for the player; it follows the mix (3:2:1 within 2%), never builds a type Lumi has not built by hand, and a new mix counts from now; the chain's state survives a save, and an empty save gives the defaults.
- **Scroungers:** one digs the ground empty and brings every part home, a sack at a time, then waits; it searches only the painted area; the cleaners' area does not hold it; its sack survives a save and a robot saved before sacks loads; a robot can be shipped to another hub.
- **The chain in a world:** a hex is seeded when first cleaned and never again, and ground under a new building gives nothing; a planet without the chain has none (first planet and dummy planet); Parts brought home go into the wallet whole; the Assembler comes with its city, its salvage pays for it, and it builds the crew with no click, one robot per assembly time, stopping when Parts run out and at the cap; new robots work for the city Lumi is in and idle ones follow; ground cleaned before the chain gives nothing; the chain saves and loads.
- **The whole planet (simulator):** the crew after each city is within 15% of the accepted curve, 100 to 200 at the launch point, no doubling under 180 s, no wait over 360 s; only Scroungers, or ten times the Parts, makes no bigger crew; without Scroungers the crew still passes 100; the simulator's Scrounger keeps pace with the real one (within 25%).
- **The bench:** the Assembler's row appears when it stands, first in the list; its panel lists every type Lumi has plans for, says which are not built by hand yet, and its buttons set the mix and pause the line.
- **200 robots stay cheap:** a search that found nothing is not repeated at once; land robots take no work across water; looking for work is spread over the ticks; far robots step on their own clocks.

Changed to the new rules: `test_robots_water` (one cap for the whole crew), `test_ui2` (prices from the table, the tier step's price and gate), `test_qa_fixes_b` (multibots change jobs freely inside the cap), `test_ui6` (the tier row waits for the second city).

Checked by eye, not by a machine: the building in the yard (one render). Not checked by eye: the Assembler panel in the workbench (its rows and buttons are tested; the workbench does not open from a dev flag on the globe, so no render was made). Two of seven save round trips printed "RID allocations of type DummyMesh were leaked at exit" (a note, not a failure) from the headless renderer; five did not. Not tracked down.
