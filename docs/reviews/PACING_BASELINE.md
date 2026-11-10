# Pacing baseline: the current game over 4 hours (M1-12, Nov 10)

The first job of the fast balance simulator (`tools/pace_sim`): where the current game stands against the cadence rules of `docs/PLAN.md` section 9, before any redesign. No game data was changed.

**Verdict: the current game fails 10 of the 11 cadence checks.** It passes only "first upgrade within 90 s". Two of the ten (first payout, small win) fail only because of an inferred 40-second landing delay and are not certain; the other eight fail by a wide margin.

## How this was produced

```
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --planet=verdance --minutes=240 --purchases=1 --csv=series.csv
```

It runs in under 3 seconds. Policy: `greedy`, which buys in the full-game bot's order. Times are simulator minutes, which are bot speed; a new player is about twice as slow.

**How far to trust it.** The simulator matches the Nov 10 bot run within 10% on 14 of 15 beats up to minute 70 (table in `tools/pace_sim/README.md`). Base level 2 is 26% off that run and 21% off the Nov 9 run; the two bot runs themselves differ by 37% there. Past minute 70 there is no bot data to check against, so the rows below from minute 80 on are an extrapolation. The garden is coarse. Goals past the story objectives stop at a step the simulator cannot do (minute 103), so goal gaps are judged only up to there.

## Cadence table

| Rule (PLAN section 9) | Limit | Measured | Result | Where |
|---|---|---|---|---|
| First payout | 20 s | 51 s | FAIL (uncertain) | 40 s of landing, then an 11 s first load. The 40 s is inferred from the bot's third load at 84 s; the bot does not log its first payout |
| First upgrade | 90 s | 84 s | PASS | |
| First clean hex | 3 min | 7.0 min | FAIL | bot: 7.5 min |
| Small win at least every | 40 s | 51 s | FAIL (uncertain) | only the wait before the first payout; after it the longest gap is 32 s |
| Purchase at least every (first hour) | 3 min | 6.3 min | FAIL | minute 13.6 to 19.9 |
| Purchase at least every (after) | 4 min | 8.7 min | FAIL | minute 103.6 to 112.3 |
| Longest gap between goals | 4 min | 44.4 min | FAIL | minute 54.7 to 99.0; bot: no step from 45.2 to the end of its run at 83 |
| New mechanic (first hour) | 15 min | 17.4 min | FAIL | minute 2.5 (Baler) to 19.9 (Bot Bay) |
| New mechanic (after) | 40 min | 97 min | FAIL | minute 134 to 231 |
| Power spike (rate x2) | every 40 min | 149 min without one | FAIL | spikes at minutes 28, 31 and 91 only |
| Hand share of cleaning | 30% or more | 17% | FAIL | minutes 30 to 40, right after the first robots, and again minutes 163 to 173 |

Beats: first upgrade 1.4 min, Baler 2.5, first hex 7.0, hexes 2 and 3 at 13.4 and 19.6, Bot Bay 19.9, first robot 26.1, garden opens 28.9, ten hexes 32.8, base level 2 at 41.5, first Haul Bug 46.4, 50 hexes 67.0, 100 hexes 97.7, base level 3 at 99.0, base level 4 at 99.8, 200 hexes 158.0, base level 5 at 162.8.

**After 4 hours: 338 hexes clean.** That is 41% of the start hub's region (817 hexes) and 0.2% of the planet (163,842). There is no ending to reach.

## Time series

| Minute | Cubes on hand | Income (cubes/s) | Hexes | Robots | Upgrades bought | Parts | Base level |
|---|---|---|---|---|---|---|---|
| 5 | 9 | 1.6 | 0 | 0 | 8 | 95 | 1 |
| 10 | 70 | 1.6 | 1 | 0 | 13 | 150 | 1 |
| 15 | 360 | 1.6 | 2 | 0 | 13 | 184 | 1 |
| 20 | 191 | 12.5 | 3 | 0 | 13 | 197 | 1 |
| 25 | 565 | 1.6 | 3 | 0 | 13 | 242 | 1 |
| 30 | 340 | 18.5 | 6 | 3 | 15 | 41 | 1 |
| 40 | 795 | 7.8 | 17 | 3 | 49 | 165 | 1 |
| 60 | 3,593 | 11.7 | 40 | 6 | 66 | 129 | 2 |
| 80 | 3,644 | 18.5 | 71 | 10 | 75 | 494 | 2 |
| 100 | 45,226 | 1,727.6 | 103 | 11 | 75 | 8 | 4 |
| 120 | 11,171 | 24.0 | 132 | 18 | 124 | 772 | 4 |
| 140 | 14,656 | 31.6 | 164 | 24 | 124 | 1,274 | 4 |
| 160 | 24,386 | 37.1 | 203 | 24 | 124 | 2,033 | 4 |
| 180 | 8,220 | 15.7 | 229 | 24 | 146 | 2,765 | 5 |
| 200 | 12,927 | 21.3 | 259 | 25 | 158 | 3,805 | 5 |
| 220 | 1,223 | 32.8 | 297 | 35 | 158 | 3,407 | 5 |
| 240 | 4,725 | 43.2 | 338 | 35 | 176 | 5,280 | 5 |

Income is the average over that one minute. The 1,727 at minute 100 is one burst: finishing the "base level 3" step completes 16 waiting goals at once, and the next step 5 more.

## The three biggest pacing problems

### 1. Nothing to aim for between minute 55 and minute 99
The story card shows one step at a time. After "clean 20 hexes" (minute 54.7) the next step is "rebuild the base to level 3", and it takes 44 minutes. The bot run shows the same wall: its last finished step is at minute 45.2 and it is still on base level 2 when the run ends at minute 83.

Data rows that cause it:
- `hub` table, level 3: **9,000 cubes and 350 parts**. Level 2 was 1,500 cubes and 150 parts: six times the cubes in one step.
- Income from minute 55 to 99 averages **18 cubes a second**, and the buyer spends it as it comes: 2 more Scoopies and 3 Haul Bugs (about 7,700 cubes), 9 research nodes (about 13,500), three stations, two Mk II tiers (7,200). Each is the "next cheapest thing", so the 9,000 is never on hand.
- `tutorial` table: there is no step between `hex20` and `base3`. The goals that do complete in between (hex counts, earnings, research counts) are only paid out when the base step finishes, so 16 goals and about 68,000 cubes land in one second at minute 99, and base level 4 (28,000 cubes) is bought 48 seconds after level 3. Two of those goals, `base2_3` and `base2_4` (15,000 and 20,000 cubes), look meant for a second base but are met by the first, because their type is plain `hub_level`.

### 2. The start is slow and then dries up
First clean hex at 7.0 minutes against a 3-minute rule; hexes 2 and 3 take 6.4 and 6.2 minutes each. From minute 13.6 to 19.9 nothing is bought at all, and from minute 10 to 30 only 2 upgrades are.

Data rows that cause it:
- `player` table: chest `capacity` **12** against **387 units** of junk per hex. That is 34 bin trips for the first hex. Each `compartment_size` level adds 5 (`upgrades` table), so hex 3 still needs 13 trips.
- Income sits at **1.6 cubes a second** from minute 5 to minute 25 (it was 1-5 in the Nov 9 bot run).
- `data/workbench.json`, tier 2 (Bot Bay): **1,200 cubes and 40 parts**, gated on 3 clean hexes. At 1.6 cubes a second that is 12 minutes of saving with nothing else to buy; the simulator waits from minute 13.6 to 19.9 for the third hex, then buys it with the hex reward.
- `upgrades` table, `lift_strength`: `growth` **10** (50, then 500 cubes). The second level takes the whole reward of the first hex.
- The first new mechanic after the Baler (minute 2.5) is the Bot Bay at minute 19.9: 17 minutes with no new verb.

### 3. Robots take over at once, then output goes flat for three hours
Hand share falls to 17% in the ten minutes after the first robots (rule: at least 30%). After that the cleaning rate hardly moves: 15 hexes in minutes 60 to 70, 16 in 100 to 110, 19 in 150 to 160, 21 in 230 to 240, while the fleet grows from 10 robots to 35. The rate doubles only at minutes 28, 31 and 91; then there are 149 minutes without a power spike.

Data rows that cause it:
- `robots` table, Scoopie: `scoop_rate` **1.4**, `cost` **800 cubes, 70 parts**. That is 136 seconds of work per hex against Lumi's 6 minutes at the same point of the game. Three can be built at base level 1 (`crew_cap`: base 1 + 2 per level), all within 4 minutes (26.1 to 29.6).
- A clean hex pays **247 cubes whoever cleans it** (`field` table `bonus_base` 20 + `bonus_per_volume` 0.25 x 407, `research` table field note 100, `regrowth` level 1 reward 25). A Scoopie's bales from that hex are worth 27 cubes. So robots earn almost all of their income from a reward the player set up but did not work for.
- Why it goes flat: `crew_cap` gives 5 cleaners at base level 2 and only 2 more per level, each next Scoopie costs 1.35x the last (3,587 cubes for the sixth), and every hex is farther out than the one before, so each robot gets slower as the clean area grows. Nothing in the data gives a jump: fleet upgrades add 12-15% a level and their costs grow 1.6x.
- In the same stretch purchases stall: **no upgrade is bought between minute 120 and 150**, 10 between minute 60 and 90.

## Also worth knowing

- **Parts decide the early gates and they are luck.** Base level 2 needs 150 parts, the first three Scoopies 255. Parts come from rare finds (a Legendary pays 450, a Rusty 10). The two bot runs reached base level 2 at 33.0 and 52.6 minutes for this reason alone.
- **Goals arrive in bursts.** 7 at once at minute 44 in the bot run, 16 at once at minute 99 in the simulator. See problem 1.
- **Later in the run parts pile up unused** (5,280 on hand at minute 240) while cubes are short.

## Found in the calibration bot run (not pacing, for the bug list)

- From about minute 73 to 80 the crew did nothing: income reads 0.00 cubes a second for minutes 77 to 80, and three hexes were cleaned in 13 minutes with five Scoopies. This is a stall over the 4-minute limit.
- The log filled with `Condition "!v.is_finite()" is true` errors (`instance_set_transform`), 18,270 lines by the end. Something is being placed at a non-finite position.
- `--quit-after=1800` did not end the run; it was still going after 2,100 real seconds and had to be stopped by hand.
- The run changed `screenshots/autoplay_milestones.json`, a tracked file. It was restored.
