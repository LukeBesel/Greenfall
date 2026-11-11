# M3-21: city 1 fitted to the game's real walking (Nov 11)

The problem is measured in `docs/reviews/M3-19_ECONOMY.md`; the decisions this follows are the last section of `docs/DECISIONS.md`. This lists what changed, every number and why, and what the bot measures now.

**Verdict.** Four of five targets are met in both final bot runs. **One is missed in both: the longest wait between purchases is 136 s and 130 s (limit 120).** Both waits lie across the first-seed sequence, which takes Lumi off the work for about 105 to 113 s with no cubes coming in. Prices cannot fix that; it needs a design decision (section 5). Every other wait in the two runs is 117 s or less.

## 1. Targets, two fresh bot runs

`godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=250`, run twice on the final data, one after the other. No SCRIPT ERROR, no bot trap. Times are seconds from the moment the bot takes control.

| Target | Limit | Run 1 | Run 2 | Result |
|---|---|---|---|---|
| First clean hex | under 90 s | 86 s | 54 s | met (run 1 is close) |
| Longest wait between purchases, first 20 min | 120 s | 136 s | 130 s | **missed** (the seed tin, section 5) |
| First robot (a Haul Bug) | by minute 12 | 9.7 min | 8.5 min | met |
| A hex, through minute 15 | about every 60 to 90 s | 75 s (11 hexes) | 64 s (14 hexes) | met on average, see below |
| Largest price in city 1 | under 4,200 | 4,000 | 4,000 | met (Auto-Baler research) |
| Most cubes held | under 5,000 | 450 | 709 (1,096 by minute 26) | met |
| Largest single reward | 3 min of real income (900) | 870 | 870 | met (city reaching Thriving) |

Other beats of the same runs: first payout 2 s and 2 s; first upgrade 12 s and 14 s; Baler 140 s and 107 s; signal tower 266 s and 234 s; Bot Bay 581 s and 508 s; base level 2 at 740 s and 603 s; seed tin 886 s and 791 s; Research Desk 918 s and 795 s. Purchases in 20 minutes: 31 and 36.

**Seconds per hex.** Run 1: 86, 100, 125, 80, 87, 56, 61, 35, 73, 53, 68, 114. Run 2: 54, 103, 115, 67, 52, 70, 41, 51, 35, 69, 47, 108, 31, 52. Hexes 2 to 4 take 100 to 125 s: Lumi still carries every bale 17 to 25 m to the scale. With the Haul Bug a hex takes 31 to 73 s: 7 of the 13 hexes after the robot took under 60 s. The slow one near minute 13 (114 and 108 s) is the seed tin.

## 2. What changed, and why

**The first robot is a Haul Bug.** Its plans come with the Bot Bay; the Scoopie's plans follow 8 minutes of play after the first robot and at 14 clean hexes (bot: about minute 16 to 19). It costs Parts only. The owner's earlier note (items 44 and 46: the Scoopie comes alone, the Haul Bug later) is reversed by the lead's decision of Nov 11.

**The card runs power, tower, Glim, street, Bot Bay, robot.** It used to ask for the street's 7 hexes before the tower. Nobody saved for the tower while it was not on the card, and it arrived anywhere from minute 6.7 to minute 11.0, the Bot Bay after it.

**Gates instead of dear prices.** The bot saves for what the card asks and buys nothing dearer than a fifth of it meanwhile, so a price is a wait of price / income. The Bot Bay, base level 3 and the Research Desk are held back by a condition; their prices stay about a minute of income.

| File | Number | Was | Now | Why |
|---|---|---|---|---|
| `planet/sites/site_prefab.gd` | bin position in the yard | (-8.0, -1.3) | (-8.0, 3.1) | first hex's middle 7.9 m from the bin, nearest junk 3.2 m |
| same | scale position | (-8.0, 2.0) | (-8.0, -0.2) | swapped with the bin; 10.6 m from the first hex's middle |
| `districts.json` | Old Town `first_hexes.work` | 120 | 108 | nine loads of the starting chest; first hex 54 to 86 s (was 85 to 103) |
| same | Old Town `income_ref` | 14 | 5 | the bot's measured income, not the proposal's; the 3-minute rule now allows 900 |
| same | `stage_reward.cubes` stages 4 and 5 | 1,000 and 1,200 | 600 and 750 | 696 and 870 in city 1 (were 1,160 and 1,392, over 900). **The rule is shared: cities 2 to 6 pay 40% and 37.5% less at these two stages** |
| `upgrades.json` | Baler | 250 | 130 | before the Baler most of the second hex is walking; at 180 one run waited 152 s for it |
| same | Lift Strength growth | x4 (120, 480) | x2.5 (120, 300) | 480 was a wait of 2 to 3 minutes in the simulator |
| `signal_tower.json` | first tier | 500 | 100 | asked for near minute 3 at 1 to 2 cubes a second: 128 s wait at 280, 123 s at 200, 174 s at 160 |
| `data/workbench.json` | Bot Bay | 800 | 260 | about a minute of income at minute 8 |
| same | Bot Bay gate | tower, 3 hexes | tower, 6 hexes | holds the first robot near minute 9 without a wait |
| same | Research Desk | 600 | 350 | about a minute of income |
| same | Research Desk gate | base level 2 | base level 2 and the seed tin | saved for during the seed tin it was a wait of 144 to 190 s in four runs |
| `hub.json` | base level 2 | 700 | 320 | about a minute of income with the Haul Bug |
| same | base level 3 gate | none | Research Desk, 24 hexes | with 1,100 on offer at minute 15 the bot bought nothing for 282 s |
| `robots.json` | Haul Bug Parts | 16 | 6 | found by about minute 5 in every run, so cubes and hexes, not luck, set the time |
| same | Scoopie needs | `salvage_logic` | `scoopie_rig` | the cleaner follows the hauler |
| `research.json` | `haul_rig` arrives | 20 min after the first robot, 8 hexes | with the Bot Bay | |
| same | `scoopie_rig` (new) | | 480 s after the first robot, 14 hexes | |
| same | `skimmer_rig` requires | `haul_rig` | `scoopie_rig` | order kept: hauler, cleaner, skimmer |
| same | Auto-Baler research | 4,500 | 4,000 | the only city 1 price over 4,200 |
| `plants.json` | first seed `hexes_needed` | 7 | 13 | after the robot and base level 2. In practice the card's own timer gives the signal 75 s after base level 2 |
| `objectives.json` | step order; new step `scoopie` replaces `haul`; robot texts | | | above |
| `goals.json` | `haulbug_1` before `scoopie_1` | | | |

Unchanged on purpose: hex value 116, hex weight 144, track prices (40, 40, 50, ratio 1.6), city 1 research other than the Auto-Baler, Parts per hex, crew cap.

## 3. The simulator

`--model=current` now walks the yard's measured hexes (bin and scale anchors, nearest first), grows the walk across a hex, tips in reach of the bin, counts side income (level rewards, salvage surges, weather) growing over the first ten minutes, reads every gate through one condition check, and builds the Bot Bay's robot on the same visit. New line in its output: `first-city fit`. Constants moved: `trip_overhead_s` 3 to 4, `path_factor` new at 2.1, `hex_span_m` new at 16, `side_income_share` 0.1 to 0.4, `side_income_ramp_s` new at 600.

Against the mean of the two final runs (seconds from control):

| Beat | Run 1 | Run 2 | Mean | Simulator | Difference |
|---|---|---|---|---|---|
| First hex | 86 | 54 | 70 | 62 | -11% |
| Hex 2 | 186 | 157 | 172 | 175 | +2% |
| Hex 3 | 311 | 272 | 292 | 247 | -15% |
| Baler | 140 | 107 | 124 | 126 | +2% |
| Hex 5 | 478 | 391 | 435 | 382 | -12% |
| Clear the street (7 hexes) | 595 | 502 | 549 | 518 | -6% |
| Signal tower | 266 | 234 | 250 | 222 | -11% |
| Bot Bay | 581 | 508 | 545 | 498 | -9% |
| First robot | 582 | 509 | 546 | 498 | -9% |
| Base level 2 | 740 | 603 | 672 | 642 | -4% |
| Seed tin | 886 | 791 | 839 | 846 | +1% |
| Research Desk | 918 | 795 | 857 | 852 | -1% |

Every beat is within 20% of the mean. **It is not within 20% of each run:** the two runs differ from each other by 59% on the first hex and by 12 to 31% on the rest, so no single number can be. The simulator runs early on every beat between minute 4 and minute 11, and it reports a longest purchase wait of 106 s: it does not model the seed sequence's stop.

## 4. Run-to-run spread

Twelve bot runs were made while fitting. The same build gave the first robot at 8.0 and at 12.0 minutes, and a first hex at 54 and at 86 s. What moves a run: walks to buried-part pings (one run earned nothing for a minute after the first hex), a salvage surge (pieces at triple value: 3 pieces in one run, 200 in another), the order hexes are finished in, and bales sold two at a time.

The bot itself was changed, and the numbers depend on it:
- It walks round a lake instead of pushing at the shore. One run stood at the shore for 100 s and was put back in the yard by the trap rule.
- It walks to the bench when a bench tier is on offer and paid for, and goes to the bench before the seed tin when it has something to buy. In one run it stood by the tin holding 596 cubes.
- It walks straight to the seed tin. The old stand point was a flat-world offset that can lie inside the greenhouse wall.
- Until the first hex is clean it digs only pings within 6 m (already in the earlier commit).

## 5. Open points

1. **The purchase-wait target and the first seed.** From WREN's signal to the end of the tin's cinematic the bot earns nothing for 105 to 113 s. Any purchase before and after it makes the wait longer than 120 s. Ways out, each a design call: shorten the sequence; count the seed tin as a purchase-like win in the rule; let Lumi buy something at the greenhouse; or move the first seed past minute 20 (the owner asked for minute 10 to 15).
2. **Hexes under 60 s after the Haul Bug.** Seven of the 13 hexes cleaned after the robot in the two runs took 31 to 55 s. Slowing them means heavier hexes in ring 2 (hex weight was left at the accepted 144) or a slower Haul Bug.
3. **Card guidance for the new `scoopie` step.** `story/objectives.gd` `step_target` still has a case for the old step id `haul` and none for `scoopie`: while the Scoopie's plans have not arrived the beam points at the bench. Shared story code, outside this task.
4. **The locked Research Desk says "Not yet. Keep playing."** `ui/bench_tiers.gd` `requirement_text` has no text for a flag condition. Outside this task.
5. **Three frontier research nodes have no gate of their own:** Dune Fences (17,500), Cold-Hardy Seeds (23,750) and Dew Condensers (16,250) need only tier 5 nodes, so on paper they can be bought in city 1. The price cap test counts tiers 0 to 5 as city 1's.
6. **Crew upgrades are still priced in cubes** (15 levels at x1.6, the last over 60,000). Left for the crew task, and not counted in the largest price.
7. **`data/workbench.json` is a shared file holding this planet's numbers** (bench tier prices and gates), as M3-19 noted.
8. **The first hex was 86 s in one of the two runs.** Earlier runs on the same hex weight gave 54 to 75 s.

## 6. Tests

`tests/test_pacing_fit.gd` (9 tests): the simulator walks the measured hexes; the trip grows with the route; the yard's distances on the real globe; the first robot is a hauler for Parts only; the card's order; the Bot Bay's gate and price ceilings; the Research Desk's gate; base level 3's gate; the simulator meets the targets (first hex, first robot between minute 7 and 12, purchase wait, cubes held, largest price, mean hex time).

Changed to the new rules: `test_v4bots` (unlock order), `test_economy_scale` (Baler price, nine loads, price cap now under 4,200 and counting bench tiers and research, Lumi level rewards judged at the measured income), `test_bench_tiers`, `test_triage_m1` (the Bot Bay's and the Desk's gates are asked for by earlier steps), `test_research`, `test_robots_water`, `test_ui2`, `test_steam`, `test_first_hour`.
