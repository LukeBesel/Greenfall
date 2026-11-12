# M3-11: the bot plays the new loop (Nov 11-12)

The autoplay bot now plays Planet 1 the way the new loop asks: it flies between cities as a player
does, fits each city's rig tool, learns the city's kind by hand, builds and directs the crew,
does each source job, plants and tends, and keeps a per-city cadence table. A run that stops
making progress for more than 4 game minutes ends with exit code 1 and says what the bot was doing.

**Verdict.** The bot reached the ending (launch at game minute 613.2, the Bloom, the end screen, exit 0) with
200 robots, the crew cap, but **not in one honest run**: the game cannot be finished without dev
flags today. Old Town cannot pass stage 1 (B41, open), and no robot adds to regrowth stages 2 to 5
on the globe (B44, open), so every later city's stages 2 to 4 are Lumi's hand planting and
watering. The honest run (no flag in city 1, one flag to pass B41, then none) played 459 game
minutes and reached Kettle Bay stage 1; the rest was fast-forwarded one city at a time with
`--district-stage` (the bot still did every job, tool, flight, kind and the rocket) and 2,000 Parts
were given for the rocket to save about 2.5 real hours of Scrounger digging. Six game bugs were
found (B39 to B44; B39, B40 and B42 fixed with tests); the per-city cadence breaks are listed for M3-12.

## What the bot was taught

| Area | What it does | Where |
|---|---|---|
| Where to be | A planner picks the city: the earliest open city whose source job is on offer and paid for; else the newest city until it reaches the stage that opens the next; else (all open) the earliest city below stage 5 | `tools/autoplay_travel.gd` `target_city` |
| Travel | Sets bales down, walks to the parked rocket and flies when the planner points elsewhere and the cells are full. A refused hop is retried after 30 s. A walk that cannot reach the rocket in 120 s boards from where Lumi stands and is counted (`board_stuck`) | `tools/autoplay.gd` `_do_travel` |
| Home trips | The only workbench is in the start yard. Away, the bot flies home for a city's tool, for the Assembler, or for shopping at most every 15 minutes; leaving home, it visits the bench first | `_want_home`, `AutoplayTravel.home_wanted` |
| Play area | The cells of the city whose pad the rocket stands on (was 18 rings round the start). The wider ring is cleaned only when the city has nothing left; base point, refills, zones and the trap escape use the city's own pad | `_hexes`, `_base_at`, `_city_has_work` |
| Kinds | Lakes count as ground once the Skim Skirt is fitted (slick); held kinds (smog, blight) as before | `_pick_focus`, `_do_learn` |
| Garden | Plants before it waters (a quarter of a hex's open slots makes it Planted, so hexes under that come first); plants a pile of seeds even past its garden share once the city has stage 1; a clean city is all garden; leaves a hex whose open slots it cannot reach | `_garden_task`, `_pick_plant_hex`, `_plant_task` |
| Crew | The first Scrounger first; several robots a bench visit; Parts kept for robots over the tower and Glim; past city 1 robots stop waiting for the base's cube savings; waterers (1 per 8 planted hexes) and planters (1 per 4 cleaners) wait for the city's first stage; robots are chosen for the city the bot is heading for | `_next_robot`, `_shop`, `_crew_first` |
| Directing | Paints the Scroungers' search area (clean ground still holding parts, nearest the base) and a cleaners' zone that grows with the crew (up to 60 hexes); sets the Assembler's mix (cleaners, haulers, finders, a skimmer while lakes are dirty, planters and waterers once the garden is open) and pauses the line while a source job waits for Parts | `_paint_search`, `_paint_zones`, `_set_mix` |
| Cadence | Per city: arrival, first hex, mastery 1 of its new kind, source shut, stage 4 and 5, crew in and out; over its span: purchases, longest wait between purchases, longest goal gap, most cubes held, Parts. Printed as `[cadence]` lines and written to the report (`cadence`, `launch_s`) | `tools/autoplay_cadence.gd` |
| Stalls | No purchase, goal, hex or stage for over 4 game minutes (flights and cinematics excluded): prints `STALL` with the task, city, target, cubes, Parts, crew and rocket state, writes the report, exits 1. `--no-stall-exit` turns it off for dev starts | `tools/autoplay_stall.gd` |
| Dev aids | `--garden-audit` (share of a city's land that can hold a plant), `[garden]` and `[crew]` lines each minute, `[bot-plant]` and `[bot-board]` with `--bot-debug` | `tools/autoplay.gd` |

## How the full run was made

The run is staged with `--save-dir=m311` (each stage saves; the next loads it and goes on; the
cadence table carries over in `screenshots/autoplay_cadence_m311.json`). Time-scale 8 throughout;
the game ran at 1.7x to 4.6x real time, slowing as the crew grew.

1. **Stage A, no dev flags:** `--fresh --autoplay --time-scale=8 --save-dir=m311 --game-minutes=80`.
   Old Town from a fresh start. It reached stage 1 at 51.5 minutes and stopped there: B41 holds it
   (37 of 74 land hexes cannot take a plant). With no flag the game cannot go further.
2. **Stage B, one dev flag to get past B41:** the same save, `--district-stage=old_town:5` (sets
   Old Town's hexes to stage 5; its source job still gates the stage, and the bot does it). From
   here on the bot plays with no flags: Old Town's job, the Plate Cutter, the flight to Ironside,
   the crew, Ironside's job, the Skim Skirt, the flight to Kettle Bay, the Assembler.
3. **Stages C and D:** the same save, no flags, resumed after bot fixes (a stage cut short loses at
   most the minute since the last autosave).

Commands to reproduce the start: `godot --headless --path . -- --fresh --autoplay --time-scale=8
--save-dir=m311 --game-minutes=80 --quit-after=3300`, then `godot --headless --path . --
--autoplay --time-scale=8 --save-dir=m311 --district-stage=old_town:5 --quit-after=14000`.
4. **Fast-forward (copy of the stage D save, `--save-dir=m311ff`):** one stage per city,
   `--district-stage=<city>:5` to skip its regrowth (B44), then the bot alone does the city's
   job, fits the next tool at the bench, flies, learns the new kind and builds crew:
   `kettle_bay:5` (to minute 505), `highreach:5` (540), `lowmeadow:5,scrapyard:5` (565),
   `old_capital:5` (stalled at 586, see below), then `--no-stall-exit` and, last,
   `--give-parts=2000` to the ending at 613.9. The report of that last stage, with the whole
   table, is `screenshots/autoplay_report.json`.

## Per-city table

Game minutes (time played; control at 1.1). Spans run from a city's arrival to the next city's.
Cities after Kettle Bay stage 1 (about minute 397) were fast-forwarded: their stage 4 and 5
times are the dev flag's, their arrival, first hex, mastery and crew are the bot's.

| City | Arrive | 1st hex | Mastery 1 (kind) | Source shut | Stage 4 | Stage 5 | Crew in / out | Buys | Longest wait | Goal gap | Cubes max | Parts max / end |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Old Town | 1.1 | 2.1 | 3.6 (litter) | 82.6 | 82.6 (flag) | 82.6 | 0 / 5 | 75 | 430 s | 157 s | 10,390 | 59 / 59 |
| Ironside | 83.8 | 84.6 | 88.0 (wrecks) | 345.3 | 340.1 | 540.8 (flag) | 7 / 57 | 174 | 1,254 s | 592 s | 9,556 | 111 / 99 |
| Kettle Bay | 350.1 | 351.2 | 363.8 (slick) | 460.7 | 459.5 (flag) | 460.7 | 57 / 120 | 122 | 3,460 s | 427 s | 6,012 | 531 / 198 |
| Highreach | 467.4 | 471.4 | 478.5 (smog) | 507.6 | 506.0 (flag) | 507.6 | 120 / 120 | 59 | 2,398 s | 193 s | 7,509 | 553 / 194 |
| Lowmeadow | 513.3 | 517.1 | 534.9 (blight) | 542.6 | 540.8 (flag) | 542.6 | 160 / 160 | 79 | 959 s | 184 s | 12,529 | 668 / 302 |
| Old Capital | 548.9 | 550.3 | none new | 613.2 | 565.8 (flag) | 613.2 | 200 / 200 | 35 | 944 s | 1,162 s | 27,385 | 2,281 / 403 |

**Launch point:** game minute 613.2 (time played, about 612 after control), crew 200 (89 Scoopies,
44 Haul Bugs, 34 Scroungers, 13 Seedlings, 20 Drips). Honest play only: Old Town stage 1 at 51.5,
Ironside stage 1 at 163.1, 2 at 199.0, 3 at 327.7, 4 at 340.1, Kettle Bay stage 1 at 397.4.
The flights: 46 hops, none boxed in on the way to the rocket in the final runs (`board_stuck` 0;
one dev start in Ironside's outskirts gave up after 120 s, 165 m out). The only script error in
the final runs was B43's, once per trip home that bought a base level.

## Stalls and cadence breaks

**The stall watch fired twice, both real:**
- A dev start with Ironside fully clean (`--district-stage=old_town:5,scrapyard:4`): after the job
  the bot waits 5 minutes for the rocket's cells with nothing to clean in reach. Cells recharging
  (300 s) with no work left is dead time a player would feel too.
- Old Capital, fast-forwarded to stage 4: the rocket's second part waits for Parts (Scroungers
  bring about 30 a minute; the six parts cost 2,600) and nothing else is left to do or buy:
  `STALL ... task=plant city=old_capital stage=4 ... parts=142 crew=200`, exit 1 at minute 586.
  The rest of that stage was run with `--no-stall-exit` to reach the ending.

No stall in the honest run (stages A to D, 459 game minutes): the longest stretch with no
progress was about 1 minute. But "progress" counts any hex cleaned, and the wider land round a
finished city always has one, so the watch cannot see a city that is not moving on.

**Cadence breaks (docs/PLAN.md section 9), for M3-12:**

| Rule | Where it breaks | Seen |
|---|---|---|
| An affordable purchase at least every 3 min (first hour) / 4 min after | Old Town minutes 20 to 80; every city after | Old Town longest wait 430 s. Away from the start yard nothing can be bought: the workbench is only there, so purchases come in bursts at home trips every 15 to 20 minutes (Ironside 1,254 s). Once the crew is at its cap (90 with three cities, 120 with four) the Parts pile up and nothing is bought for most of an hour (Kettle Bay 3,460 s, Highreach 2,398 s) |
| No gap between goals over 4 min | Ironside stages 2 to 3 | 592 s (minutes 307 to 317), 506 s, 474 s; six gaps over 4 min |
| City pacing toward about 4 hours in all | Every city after the first | Ironside alone took 256 minutes from arrival to stage 4: cleaning to stage 1 in 79 min with 7 to 27 robots, then 177 min of hand planting and watering for stages 2 to 4 (B44: robots add nothing to stages 2 to 5). Old Capital: 0% of the way to stage 1 after 15 minutes with 200 robots (hex work 4,600 a hex, 13 times Ironside's) |
| Hand share at least 10% before district 4 | Met | Old Town 79% |
| First beats (city 1) | Met | First hex 60 s after control, first robot 9.1 min, longest purchase wait in the first 20 min 148 s (accepted 136) |
| Research always running | Breaks | Longest research idle 1,067 s in Old Town; away from home nothing new is started (the Research tab is at the bench) |

## Bugs found

| # | Sev | What | State |
|---|---|---|---|
| B39 | P2 | `SphereJunkView.update_bands` read past its arrays when a shown cell got new pieces between pumps (script error after a hop home) | Fixed, `tests/test_sphere_junk_lod.gd` |
| B40 | P1 | A hex's Planted quarter and its life counted slots on paving, which never take a seed: Ironside had only 77% of its land able to pass stage 1 | Fixed, `tests/test_hex_levels.gd` (two tests) |
| B41 | P1 | Old Town cannot pass regrowth stage 1: 37 of its 74 land hexes have no slot off paving, so 50% of its land can be Planted against the 80% share. Blocks the game | Open, design call (see `docs/PLAN.md`) |
| B42 | P1 | Every save dropped `rocket_site` and `rocket_owned`: after the next autosave in another city the rocket counted as back on the start pad | Fixed, round-trip check `orbit_save_keeps_the_rocket` |
| B43 | P2 | After a trip away and back, `Camp._apply_builds` errors on freed yard models (built once on the start site's prefab, freed when it unloads, never rebuilt) | Open |
| B44 | P1 | On the globe, planting and watering robots only move a cell's state; they never plant or water the garden's slots, which the hex stages read. No robot adds to stages 2 to 5 | Open, not small (see `docs/PLAN.md`) |

Also seen, not logged: an engine error `Parameter "space" is null` (`body_test_motion`, `sphere_motor.gd:163`) once at a hop's take-off.

## Numbers for the balance pass (recorded, not changed)

- **Seeds:** 20,000 held by minute 360 and 30,000 by the end; blooms give far more than anything
  can plant (Lumi plants 6 slots a seed; robots plant no slots, B44).
- **Old Town plantable share 50%** (B41); Ironside 87%, Kettle Bay 92%, Highreach 96%,
  Lowmeadow 98%, Old Capital 98% after B40 (from `--garden-audit`; Ironside and later recounted
  with the bot's `[garden]` line once their towns were loaded: 234 of 235 Ironside hexes).
- **Hex size of later cities:** about 45 open slots a hex in Ironside (10,688 over 235 hexes)
  against about 13 in Old Town. Growing needs life 0.35 over every open slot.
- **Crew at each city's arrival** (bot): 0, 7, 57, 120, 160, 200 (cap reached by Old Capital);
  the accepted proposal after each city: 8, 50, 72, 94, 119, 147.
- **Parts:** Ironside's ground gives 1 a hex (237 in all); most held 111 in Ironside, 668 in
  Lowmeadow; the rocket's 2,600 take about 85 minutes of Scrounger digging at 200 robots.
- **Cubes:** away from the start yard income is 0 to 2 a second (bales hauled by robots only);
  city stage payouts are the big sums (10,390 held after Old Town's, 22,723 after Lowmeadow's).
- **Rocket cells:** 300 s after every hop; a trip home for the bench costs at least 5 minutes, so
  about a quarter of the time away from Old Town was spent at home.
- **Mastery 1 of each city's kind**, minutes after arrival: wrecks 4.2, slick 13.7, smog 11.1,
  blight 21.6 (with a home trip in between).
- **Source jobs** take 1 to 3 minutes each; Old Capital's waits for Parts.

## Tests

- `tools/run_tests.sh`: 1,318 tests, 1,318 passing (1,299 before this task), then the save round
  trip and the two-process reload, both PASS. `tools/warnings_audit.sh`: no warning in the new
  bot files (the project's 148 others are older).
- New: `tests/test_autoplay_whole_game.gd` (16): the planner on the first planet and the dummy
  planet (start city, job first, newest city, an unpaid job does not hold Lumi, laggards when all
  are open, the last city until its job is done, the unlock stage read from data, home trips),
  the cadence table (new kind per city, spans by arrival, one arrival per city, report rows,
  carry-over between stages), the stall watch (fires after 4 minutes and once, resets on
  progress, does not count flights).
- Regression tests: `test_band_update_survives_pieces_laid_on_a_shown_cell_since_the_last_pump`
  (B39), `test_planted_counts_a_quarter_of_the_slots_that_can_take_a_seed` and
  `test_life_is_measured_over_the_slots_that_can_hold_a_plant` (B40), round-trip check
  `orbit_save_keeps_the_rocket` (B42). Each failed before its fix.
- Bot not run with `--planet=testworld` end to end (the planner tests cover the one-district case).
