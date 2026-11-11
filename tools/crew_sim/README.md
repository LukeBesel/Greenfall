# crew_sim: how the crew grows across a planet

Plays the crew's growth over every city of a planet in well under a second. It runs the game's own rules: `CrewChain` (`core/crew_chain.gd`) for the buried parts in the ground and the Assembler's line, `CrewRules` (`core/crew_rules.gd`) for the crew cap and every price. It reads the planet's robots table and its districts. Nothing in it names a planet.

Use it for the late game, where the full-game bot cannot go yet. Use the bot (`tools/autoplay.gd`) and `tools/pace_sim` for the first city.

## Run it

```
godot --headless --path . res://tools/crew_sim/crew_sim.tscn -- [options]
```

| Option | Meaning |
|---|---|
| `--planet=<id>` | Planet to play (default: the current planet). |
| `--policy=NAME` | `default`, `all_scroungers` (the line builds nothing else), `no_scroungers` (it never builds one), or `all` for the three. |
| `--set=key=value,...` | Replace a calibration number for this run (plain numbers only). |

From code or a test: `CrewSim.run(def, CrewSim.load_calibration(), policy)` returns a dictionary (keys listed above `run`).

## What it prints

For each policy: the crew when each city is done, the crew every ten player minutes, when the first robot and the Assembler arrive, how many robots were built by hand and by the line, where the Parts came from and went, how many buried parts cleaning left and how many are still in the ground, the fastest the crew ever doubled, and the longest wait for a new robot from the second city on.

## What is simulated

All times are player time: robots work in real time.

| Thing | How |
|---|---|
| Cleaning | Each city is cleaned evenly over its calibrated minutes, nearest hex first. The minutes are an input: a bigger crew does not finish a city sooner here. |
| Buried parts | Every cleaned hex leaves its city's parts, once (`CrewChain.seed_cell`). |
| Lumi's hands | Parts per hex cleaned, by city (calibrated). Arrival salvage from the table. |
| Scroungers | One trip at a time: out to the nearest hexes that hold parts, one hop per further hex, a dig at the type's dig rate, and back. Distance is rings times the hex spacing times a path factor. The city in play first, then earlier cities. |
| The bench | One robot by hand per visit until the Assembler stands, then only the first of each type. The Assembler is built on the first visit that can pay for it. A tier step when Parts are to spare. |
| The Assembler | `CrewChain.tick_line`, with the policy's build mix. |
| Crew cap | `CrewRules.cap` from the base level (calibrated per city) and the cities open. |

Not simulated: cleaning speed, cubes, the rocket's Parts, the per-type crew upgrades.

## Calibration

`calibration.json` holds what the tables cannot say, each with how it was found. Numbers marked ESTIMATE come from the accepted proposal's model (`docs/reviews/BALANCE_PROPOSAL_P1_V2.md`), because cities 2 to 6 and their mechanics are not in the game yet. Measure them again when they are.

## Tests

`tests/test_crew_chain.gd` runs the simulator on the first planet and holds its numbers: the crew after each city within 15% of the accepted curve, 100 to 200 robots at the launch point, no doubling in under three minutes, no wait over six minutes, and no bigger crew from building only Scroungers or from ten times the Parts.
