# pace_sim: the fast balance simulator

Plays a whole planet's economy in seconds, from the same data files the game reads. No world, no nodes, no physics: a state machine in one-second ticks. A 4-hour game takes about 3 seconds. Use it to tune pacing; use the full-game bot (`tools/autoplay.gd`) to confirm.

## Run it

```
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --planet=<id> [options]
```

| Option | Meaning |
|---|---|
| `--planet=<id>` | Planet to simulate (default: the current planet). Nothing in the tool names a planet. |
| `--minutes=N` | Game minutes to play (default: the planet's `target_playtime_min`). |
| `--policy=NAME` | Buying policy, a script in `policies/` (default `greedy`). |
| `--csv=PATH` | Write one row per minute: minute, cubes, income rate, hexes, robots, upgrades bought, parts, hand and crew output, base level. |
| `--purchases=1` | Print every purchase with its time and cost. |
| `--goals=1` | Print every finished goal with its time. |
| `--seed=N` | 0 (default) uses expected values everywhere. Any other seed rolls salvage finds; the same seed gives the same run. |
| `--set=id=value,...` | What-if: replace calibration constants for this run. |
| `--planets-dir=res://...` | Register planets from another folder first (the test planet lives in `res://tests/fixtures/planets`). |

From code or a test: `PaceSim.run(planet_id, minutes, policy, seed)` returns the model, the report and the real time taken. It puts the game's progress state aside for the run and puts it back after.

## What it prints

- **Beats**: the first time each thing happens (first payout, first upgrade, hex counts, first robot, base levels, each objective), in simulator minutes and as a player estimate (x2, see `bot_to_player`).
- **Cadence checks**: one PASS or FAIL line per rule of `docs/PLAN.md` section 9, with the measured number. The limits are in `PaceSimReport.LIMITS`. Checks use simulator time, which is bot speed, so a FAIL here is a FAIL for a player too.
- **Notes**: steps the model cannot complete, time Lumi stood stuck, a region that ran out of hexes.

How each check is measured:

| Check | Measure |
|---|---|
| `first_payout`, `first_upgrade`, `first_hex` | time of the beat |
| `small_win` | longest gap between any of: a payout, a bale, a purchase, a clean hex, a hex level, a finished objective or research |
| `purchase_first_hour`, `purchase_later` | longest gap between purchases the policy made |
| `goal_gap` | longest gap between finished card steps, up to the first step the model cannot do |
| `mechanic_first_hour`, `mechanic_later` | longest gap between new mechanics: one-level unlock upgrades, workbench tiers, a first robot of a type, the garden, stations, story unlocks |
| `spike_gap` | longest gap between moments the cleaning rate (5-minute average) reaches 2x its value at the previous spike |
| `hand_share` | lowest share of cleaning done by hand over any 10 minutes |

## What is modelled

| Area | Source |
|---|---|
| Lumi's stats and upgrade costs | `Economy.stat`, `Economy.upgrade_cost`, `Economy.is_unlocked` on the planet's upgrade and player tables |
| Junk per hex, the 95% clean rule, bite size | `SphereField` and `SphereCells` constants; mix, value and sizes from the pollution table |
| Hand loop | scoop until the chest is full, walk to the bin and back, or press a bale (`Patch.CUBE_TIME`) and carry a stack; values from `Pace.dump_value` and `Economy.evaluate_cube` |
| Hex payout | `Economy.hex_bonus`, the field note (`Research.reward`), the regrowth table's level reward |
| Parts | salvage chance per take and the rarity table (`data/parts.json`), buried parts per hex |
| Objectives and goals | the tutorial and goals tables; one card step at a time, done goals folded into each step, as the game does |
| Workbench tiers, signal tower, base levels, yard builds, stations, bin | their tables (`BenchTiers`, hub, signal tower, yard, stations, trash bin) |
| Robots | costs and crew caps from the robots table, work rate from `Offline.unit_rate`, bale value from `Offline.units_value`, Mk tiers, fleet upgrades, haulers |
| Research | costs, durations, prerequisites, queue size, story unlocks from the research table |
| Garden (coarse) | seed finds, seeds per hex from slot spacing, bloom time and seed yield from the plants table; levels, rewards and stipend from the regrowth table |

## Calibration

Everything that cannot be derived from data is a named constant in `calibration.json`, each with a note on how it was measured. Constants marked ESTIMATE were not measured.

Reference: one fresh bot run on Nov 10 (83 game minutes; its `[Autoplay]` and `[onboard]` lines are in `calibration_bot_run.log`) and the Nov 9 run in `docs/PLAN.md` section 3.

| Beat | Bot Nov 9 | Bot Nov 10 | Simulator | Against Nov 10 |
|---|---|---|---|---|
| First upgrade | 1.5 | 1.44 | 1.4 | -3% |
| Baler | - | 2.46 | 2.5 | +2% |
| First clean hex | 7.5 | 7.52 | 7.0 | -7% |
| Hex 2 | 14.1 | 14.5 | 13.4 | -8% |
| Hex 3 | 20.3 | 19.6 | 19.6 | 0% |
| Workbench tier 2 | - | 19.8 | 19.9 | +1% |
| First robot | 24.5 | 24.1 | 26.1 | +8% |
| Garden opens | - | 26.2 | 28.9 | +10% |
| Ten hexes | 32.7 | 32.8 | 32.8 | 0% |
| Base level 2 | 52.6 | 33.0 | 41.5 | **+26%** (-21% against Nov 9) |
| 20 hexes | - | 41.3 | 42.3 | +2% |
| 40 hexes | - | 59.7 | 60.0 | +1% |
| First Haul Bug | - | 44.1 | 46.4 | +5% |
| First research done | - | 45.2 | 44.2 | -2% |
| 50 hexes | - | 69.2 | 67.0 | -3% |
| 74 hexes | 100 | not reached by 83 | 81.3 | -19% against Nov 9 |
| Hexes at minute 83 | - | 53 | 76 | **+43%** |

Two beats miss the 20% target:
- **Base level 2.** It waits on 150 Parts, and Parts come in rare big finds. The two bot runs differ by 37% on this beat; the simulator uses expected values and lands between them.
- **Hexes after minute 70.** In the Nov 10 run the crew stopped: income reads 0.00 cubes a second for minutes 77 to 80 and three hexes were cleaned in 13 minutes with five cleaners. The simulator has no such stall. Treat everything past minute 70 as an extrapolation.

To re-calibrate: run the bot (`godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=1800 > LOG 2>&1`), compare its beats with a simulator run, and adjust the fitted constants with `--set` until they agree. Then write the new values and how you got them into `calibration.json`.

## Policies

A policy is one script in `policies/` that extends `PaceSimPolicy` and implements `shop(model)` (Lumi is at the bench) and `wants_trip(model)` (is the bench worth a walk). It can only call the model's buy and build methods, which enforce every cost and rule.

`greedy` mirrors the bot's order in `tools/autoplay.gd` (`_shopping_list`, `_shop`): the card's purchase, research, the Baler and Lift Strength, robots by role, the base level, stations, then the cheapest useful upgrade above a reserve. The few lists the bot hardcodes (research order) are in `calibration.json` under `bot_mirror`.

## Known gaps

- **The ending.** The current game has none on the globe; the simulator reports hexes cleaned, not planet restored.
- **Other hubs and travel.** One hub region only. A note is printed if it runs out of hexes.
- **Lakes and Skimmers, heavy junk past the start area.** Lake hexes are not modelled. Lift Strength gates hexes outside the small-pieces-only start area, but the policy buys it early, so it never binds.
- **The garden is coarse and barely calibrated.** The bot run had no Planted hex by minute 83; the simulator has the first at minute 51. Seeds, watering and the later levels need a longer bot run.
- **Events, the Ledger's drops, requests, Lumi Level rewards, air scrubbers, the composter, the conveyor and auto-baler effects** are left out. Stations are cube sinks only, except the recycler's Parts.
- **Side goals.** Shards and the cat use estimated times. Goals that wait on something else unmodelled (the CD player) stop the card; the report says where and stops judging goal gaps there.
- **Crew at distance.** `crew_travel_s_per_ring` fits four windows of one run. It decides the late game and should be measured again with the robot report (`--robots=...`).
- **Bench trips.** Past minute 160 the greedy policy walks to the bench so often that hand output drops. The bot has the same rule, but this was not checked against a run.

## Files

| File | Job |
|---|---|
| `pace_sim.gd`, `pace_sim.tscn` | command line, `PaceSim.run`, state swap |
| `pace_sim_data.gd` | everything derived once from tables and calibration |
| `pace_sim_model.gd` | state and purchases |
| `pace_sim_work.gd` | hand loop, crew, garden |
| `pace_sim_chains.gd` | objectives, goals, research, story unlocks |
| `pace_sim_log.gd`, `pace_sim_report.gd` | records, beats table, cadence checks, CSV |
| `pace_sim_policy.gd`, `policies/greedy.gd` | policy base and the bot-like policy |
| `calibration.json`, `calibration_bot_run.log` | constants and the run they were measured from |
