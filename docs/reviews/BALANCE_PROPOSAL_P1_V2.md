# Balance proposal for the Planet 1 redesign, second run (M3-01, Nov 10)

The Planet 1 redesign re-tuned on paper after the lead's fourteen decisions (`docs/design/PLANET1_DESIGN.md` section 16) on the conflicts the first proposal found (`BALANCE_PROPOSAL_P1.md`, called V1 here). Nothing in the game or its data was changed. The proposed numbers are in `tools/pace_sim/proposals/planet1/*.json`; the model that plays them is `--model=redesign` (`tools/pace_sim/README.md`).

**Verdict.** With the proposed numbers the default player reaches the launch point (all six cities thriving and the rocket built) at **112.7 bot minutes, 225 minutes for a player (3 h 45 min)**, with a crew of **149 robots**. **Every required check passes**: 13 cadence checks, 8 design checks, 15 economy and crew checks, and the 5 checks that need several runs (five players, rig loadouts, sensitivity). The pass is no longer narrow: every check still passes with each of 30 constants moved 10% down and 10% up, one at a time (60 runs, section 7).

The cube numbers are 8 to 17 times smaller than V1's. That did not come from decision 1 alone (robots earn nothing). It needed one more rule, which is mine and needs the lead's yes: **a hex has a cube value, a unit of work does not** (section 8.1). Three results go against what the brief expects and are stated plainly in section 8: the whole planet takes hundreds of robots, not thousands (8.3); Lumi's cube income stops whenever she is not sweeping (8.2); and the spike rule, the length of the run and a no-robots player pull against each other, which is why city 6's hexes are 32 times as heavy as city 1's (8.4).

## What changed since V1

| | V1 | V2 | |
|---|---|---|---|
| Launch point, bot minutes | 108.0 | 112.7 | |
| Launch point, player | 3 h 36 min | 3 h 45 min | |
| Crew at the launch point | 183 (4 Assemblers counted) | 149 robots and 1 Assembler building | |
| Crew after each city | 8, 28, 53, 75, 102, 165 | 8, 50, 72, 94, 119, 147 | |
| **Largest price paid** | 39,383 cubes | **4,200** | 9.4x smaller |
| **Peak income, cubes a second (bot)** | 1,739 | **103** | 17x smaller |
| **Cubes earned in the run** | 1.94 million | **250,140** | 7.8x smaller |
| **Cubes held at the launch point** | 30,150 | **3,970** | 7.6x smaller |
| Most cubes held | 60,757 | 6,441 | |
| Parts earned / left | 6,796 / 505 | 9,935 / 1,521 | the rocket takes 2,600 |
| Longest wait for a new robot, city 2 on | 5 min 18 s | 3 min 56 s | limit 6 min |
| Longest gap between power spikes | 36 min | 32 min | limit 40 |
| Single-constant changes that break a check | 2 of 4 (at 2-5%) | 0 of 60 (at 10%) | |
| Rig loadouts, best against worst | 1% | 8.4% | limit 8% |
| Field data with nothing to spend it on | 7,243 lost | 0 lost, 3,820 banked at launch | |
| Seeds left over | 2,250 | 1,246 | 1,179 spent on cleansing plants |
| Whole planet with the launch crew | 14 bot hours | 25 to 31 hours | section 6 |

## How this was produced

```
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign                    # sections 1-4, 6
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign --compare=1        # section 5
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign --rigs=1           # section 5
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign --sensitivity=all  # section 7 (top = the eight)
```

A run takes about 6 seconds. **Every limit in `docs/PLAN.md` section 9 is on the player's clock** (decision 2): the model runs in bot seconds and the report multiplies each measured time by 2 before it compares. Growth timers are real time and are not doubled.

**How far to trust it.** The model is rates and events, not a world: no walking, no aiming, no physics. It is calibrated against nothing, because the redesign does not exist yet. Two things to keep in mind:
- **Robots run on the bot's clock too.** A robot's rate is per bot second, so the 2x factor slows the crew as well as Lumi. In the real game robots work in real time, so a slow player gets more crew work per action of their own: their run is shorter than 2x the bot's and their hand share lower. V1 had the same simplification. Only the whole-planet figures (section 6) treat robots as real time.
- The model is touchy: a 1% change in one number can move the launch by 2 bot minutes, because purchases and spikes are single events. The tuning aimed for room on every check for that reason.

**How each decision was applied**

| # | Decision | In the model and data |
|---|---|---|
| 1 | Robots earn no cubes | Crew cleaning, the clean-hex bonus and per-hex stage rewards pay no cubes. Cubes: Lumi's own loads and bales (about 90% of all cubes) and city stage payouts (26,300 of the 250,140). Haulers only carry Lumi's bales. |
| 2 | Player's clock | As above; stated on every table. |
| 3 | City 3 lightened | Drip (waters, mists smog) is a city 4 blueprint and needs smog mastery 1. The Assembler stays in city 3 and is a building: it is not counted in the crew. |
| 4 | City 6 is the launch site | Six rocket parts, 2,600 Parts, made on the Assembler's line and fitted by Lumi (section 3). |
| 5 | Distance cost | `robots.json distance`: 300 s shifts, 2 s a ring. Cities keep 97% to 90% of robot speed. Whole planet: section 6. |
| 6 | Purchase gap in at least one currency | Required check as before; Parts-only and cube-only waits reported. |
| 7 | Loose 1.0x, any bale more | Loose 1.0, worst bale 1.15 (`bale_mult_worst`), perfect 1.5. Two checks. |
| 8 | Rigs act on the crew | Guide Arm, Sorter, Relay Mast; study in section 5. |
| 9 | Seeds for cleansing plants | 0.35 seeds per blight hex, for Lumi and Seedlings (section 6). |
| 10 | Field data banks | One bank; a node is done when the bank holds its cost. |
| 11 | Finds | 8 colours by schedule, first at hex 36 (player minute 24.9); Sprout's 7 pieces in cities 2 to 6, the last from city 6's source. |
| 12 | "Clear the street" | Ring 1 (7 hexes), done at player minute 9.4. |
| 13 | Surge in city 4 with its wave | First Surge at player minute 129. Not counted as a spike. |
| 14 | No track leads at equal prices | Sweep Speed and Sweep Width now have the same effect and price; lead shares 37%, 39%, 22%, 2%, 0%. |

## 1. Cadence table

| Rule (PLAN section 9) | Limit (player) | Measured (player) | Result | Where |
|---|---|---|---|---|
| First payout | 20 s | 16 s | PASS | bot 8 s |
| First upgrade | 90 s | 52 s | PASS | Sweep Speed, 40 cubes |
| First clean hex | 3 min | 2 min 16 s | PASS | bot 68 s |
| Small win at least every | 40 s | 26 s | PASS | worst on the hop to city 4 |
| Something affordable, first hour | 3 min | 1 min 58 s | PASS | worst from player minute 35 |
| Something affordable, after | 4 min | 1 min 54 s | PASS | worst from player minute 117 |
| Longest gap between goals | 4 min | 60 s | PASS | |
| "Now" goal | 3 min | 60 s | PASS | |
| District-tier goal | 20 min | 9 min 22 s | PASS | the first one is "Clear the street" |
| New mechanic, first hour | 15 min | 10 min 2 s | PASS | seed kit (minute 33) to the source job (43) |
| New mechanic, after | 40 min | 28 min 34 s | PASS | first Seedling (148.5) to city 6 (177) |
| Power spike (cleaning volume x2) | every 40 min | 32 min | PASS | spikes at player minutes 20, 30, 52, 60, 88, 120, 152, 180, 194, 208 |
| Launch point | 105-150 bot min | 112.7 | PASS | aim was 120 |

Design checks: no rig module is best in every city (arm: Wide Sweep 2, Heavy Claw 1, Long Reach 2, Guide Arm 1; chest: Deep Hold 2, Press Frame 4; drive: Sprint Coils 3, Hover Skirt 3) PASS. Tipping never out-earns pressing per second (worst ratio 0.75) PASS. Any pressed bale pays more than a loose load (1.15x against 1.0x) PASS. No track clearly leads at equal prices more than half the time (39%) PASS. First found piece at player minute 24.9 PASS. The Sprout set completes at the last source (bot 110.6 of 112.7) PASS. "Clear the street" at player minute 9.4 (limit 15) PASS. The launch does not wait on the rocket after the last city thrives (0 s, limit 240 s) PASS.

Economy and crew checks (spec section 14):

| Rule | Limit | Measured | Result |
|---|---|---|---|
| First bale sells for tens of cubes | 10-99 | 44 | PASS |
| First upgrade costs tens | under 100 | 40 | PASS |
| District 1 tops out in the low thousands | 5,000 | 1,611 | PASS |
| Whole numbers in the first two districts | under 10,000 | 2,628 | PASS |
| Largest income jump from one purchase | x3 | x1.37 (the Baler) | PASS |
| Largest one-off reward | 3 min of income | 0.66 of that (city 1 thriving) | PASS |
| One job per currency | 0 wrong | 0 | PASS |
| Parts per hex in district 1 | 0-3 | 1.33 (0.84 from hands, the rest the source's 45) | PASS |
| First robot | player minute 20 +/- 5 | 18.8 | PASS |
| Crew at the launch point | 100-200 | 149 | PASS |
| Crew climb | a handful, then tens | 8 after city 1, 72 after city 3 | PASS |
| Fastest crew doubling | not under 3 min | 9 min 30 s | PASS |
| Longest wait for a new robot, city 2 on | 6 min | 3 min 56 s | PASS |
| Parts split between upgrading and building | each at least 15% | 27% on type upgrades | PASS |
| Hand share of volume, cities 1-3 | at least 10% | 69%, 40%, 23% | PASS |
| *Reported only:* longest wait for a Parts purchase | 4 min | 9 min 6 s | section 8.7 |
| *Reported only:* longest wait for a cube purchase | 4 min | 3 min 24 s | section 8.2 |
| *Reported only:* longest wait for a new robot in city 1 | 6 min | 5 min 28 s | |

Checks whose measure I changed since V1, so that the change is not hidden:
- **Crew** counts robots only. The Assembler is a building (lead's choice) and is left out; V1 counted its four Assemblers.
- **Largest one-off reward** is compared with the best 3 bot minutes of income in the last 12, not the last 3. Lumi's income is zero while she tends, so "current income" at the moment a city thrives was zero and any payout failed.
- **Build against upgrade** is now the share of Parts spent on type upgrades against new robots. V1 counted the times both were affordable at the bench and found 4 such moments in a run; with one Assembler doing the building there is 1. A 15% rule cannot be judged on one sample.
- **Track lead at equal prices**: a track counts as leading only when its gain is at least 10% above the next. Two tracks with the same effect are otherwise called "leader" by the order they are listed in.
- **Rig loadouts**: a loadout wins a city only when it is at least 2% quicker than the next.

## 2. Beat timeline

| Beat | Bot min | Player min | PLAN target |
|---|---|---|---|
| Sweep and bin | 0.0 | 0 | 0 |
| First upgrade (bench) | 0.4 | 0.9 | 1.5 |
| First clean hex | 1.1 | 2.3 | 3 |
| Baler | 3.6 | 7.3 | 8 |
| "Clear the street" (ring 1) | 4.7 | 9.4 | 10 |
| Signal tower, mastery starts | 6.7 | 13.3 | 15 |
| First robot (hand-built Scoopie) | 9.4 | 18.8 | 20 |
| Research from field data | 10.5 | 21.0 | |
| First found piece, Locker | 12.4 | 24.9 | 25 |
| Seed found: planting, watering | 16.5 | 33.0 | 30 |
| City 1 source job opens | 21.5 | 43.1 | 40 |
| City 1 source shut: arm slot, Wide Sweep | 22.6 | 45.2 | 40 |
| City 2: wrecks, Lift II; first Scrounger | 23.9 | 47.7 | 50 |
| First Haul Bug | 25.0 | 50.0 | |
| City 2 source shut: drive slot, Hover Skirt | 39.8 | 79.6 | |
| City 3: slick; first Assembler 20 s later | 41.2 | 82.5 | 80 |
| First Skimmer | 43.0 | 86.1 | |
| First robot type repaired | 55.7 | 111.4 | |
| City 3 source shut: chest slot, Deep Hold | 55.9 | 111.7 | |
| City 4: smog | 56.8 | 113.5 | 110 |
| First Drip (waters, mists smog) | 58.1 | 116.1 | |
| First Surge, with its wave | 64.6 | 129.2 | 110 |
| City 4 source shut: Power Cell II | 71.0 | 141.9 | |
| City 5: blight, cleansing plants | 72.4 | 144.9 | 145 |
| First Seedling (plants, cleansing plants) | 74.3 | 148.5 | |
| City 5 source shut: Power Cell III | 88.2 | 176.4 | |
| City 6: the launch site | 88.5 | 177.1 | 180 |
| Crew Overhaul (added, see 8.9) | 100.3 | 200.6 | |
| First rocket part ordered; fitted | 100.6; 101.4 | 201; 203 | |
| Last source shut, Sprout set complete | 110.6 | 221.2 | 225 |
| Rocket complete | 111.6 | 223.2 | |
| The Bloom: launch ready | 112.7 | 225.3 | 225 |

## 3. Per-city table

| City | Rings | Hexes | Work per hex | Cubes per hex (loose) | Player min (spec target) | Crew at stage 4 (cap) | Hand share of volume | Income, cubes a bot second | Longest wait for a robot (player) |
|---|---|---|---|---|---|---|---|---|---|
| 1 Old Town | 6 | 127 | 144 | 116 | 48 (50) | 8 (8) | 69% | 14 | 5 min 28 s |
| 2 Scrapyard | 9 | 271 | 340 | 120 | 35 (30) | 50 (56) | 40% | 16 | 2 min 18 s |
| 3 Greywater | 12 | 469 | 305 | 125 | 31 (30) | 72 (90) | 23% | 33 | 3 min 36 s |
| 4 Smogworks | 16 | 817 | 540 | 130 | 31 (35) | 94 (120) | 26% | 40 | 2 min 38 s |
| 5 Ash Fields | 20 | 1,261 | 960 | 135 | 32 (35) | 119 (160) | 26% | 71 | 1 min 20 s |
| 6 The Works | 26 | 2,107 | 4,600 | 330 | 48 (45) | 147 (200) | 7% | 51 | 2 min 50 s |

- **The crew curve** (bot minute: robots): 10: 1, 20: 6, 30: 20, 40: 45, 50: 62, 60: 76, 70: 91, 80: 107, 90: 122, 100: 137, launch: 149 (30 Scoopies, 27 Haul Bugs, 23 Skimmers, 24 Drips, 22 Seedlings, 23 Scroungers; every working type repaired). The Assembler built 96 of them. The Scroungers carried in 8,309 of the 9,935 Parts earned.
- **What paces the crew.** In cities 1 and 2 it is Parts: Lumi builds each robot by hand. From city 3 it is the Assembler's one line, a robot every 40 s, about 1.5 a bot minute. Parts are in surplus from then on, and the surplus is what the rocket costs. This is why the crew no longer stalls or runs away when a number moves: the crew at the launch point stayed between 140 and 161 in all 60 sensitivity runs.
- **City 2 is hand-building at speed** (the owner's check): 8 to 50 robots in 35 player minutes, a robot every 50 seconds at the bench. It does not stall, but that is a lot of bench visits (8.6).
- **The rocket** (city 6's goal ladder). Six parts, ordered one at a time once 35%, 45%, 55%, 65%, 75% and 85% of the city's cleaning work is done (the last also needs the source shut). Each costs Parts (300, 350, 400, 450, 500, 600), takes the Assembler's line for 45 s, and is fitted by Lumi in 20 s. Fitted at player minutes 203, 206, 210, 213, 216 and 223; the launch is at 225 and never waits on the rocket. It takes 26% of all Parts earned. Weak point: the six parts fall in the last 22 of the city's 48 minutes (8.5).
- **Mastery at the end:** litter 8, wrecks 9, slick 7, smog 8, blight 8 of 10.
- **Lumi's time:** sweeping 71%, planting 4%, watering 6%, source jobs 4%, the rest at the bench, on hops and fitting. Never idle.

## 4. The first ten minutes: chest against hex

| | Today (baseline) | V1 | V2 |
|---|---|---|---|
| Chest | 12 units | 12 | 12 |
| Junk to clear in a first hex | 387 units | 120 | 144 |
| Loads per first hex | 34 | 10 | 12 |
| First payout | 51 s | 16 s player | 16 s player: 9.7 cubes |
| First upgrade | 84 s | 52 s player | 52 s player: 40 cubes |
| First clean hex | 7.0 min | 1 min 58 s player | 2 min 16 s player |
| "Clear the street" | none | none | 9 min 24 s player |
| Purchases in the first 10 bot minutes | 13 | 19 | 19 |

The start is V1's with a slightly heavier first hex (the search asked for it: city 1 was 5 minutes under its 50-minute target). The first found piece moved from hex 42 to hex 36 to stay at minute 25.

## 5. Five players, and five rigs, on the same numbers

| Player | Launch (bot min) | Crew | Crew after each city | Required checks failed |
|---|---|---|---|---|
| default | 112.7 | 149 | 8, 50, 72, 94, 119, 147 | none |
| rush robots (every robot before any other Parts purchase) | 161.1 | 200 | 8, 46, 90, 120, 153, 200 | 6 |
| never builds robots | 289.4 | 0 | 0 | 13 |
| Assembler builds only Scroungers | 166.4 | 200 (161 Scroungers) | 8, 51, 90, 119, 153, 200 | 5 |
| Assembler never builds a Scrounger | 234.6 | 120 | 8, 44, 55, 68, 81, 100 | 12 |

- **All five reach the launch point; none is faster than the default** (required: none under 60% of the default's time). PASS on both.
- **Rushing robots is still slower, not faster** (161 against 113): that player sits at the crew cap in cities 3, 4 and 6 and waits for the base level.
- **The chain cannot be exploited**: all Scroungers ends 54 minutes late with a crew that cannot clean.
- **Without Scroungers the game is finishable but slow** (235): the one hand-built Scrounger and Lumi's own digging pay for the rocket. That player's line is paused for the rocket after 90 s of waiting.
- **No robots at all: 289 bot minutes, about 9 h 40 min for a player.** It passes the 300-minute cap by 4%. It only passes because the last two track tiers hold 30 levels a track, of which the default player buys about 8; a solo player earns 1.25 million cubes and buys them all (8.4).

**Rig loadouts** (default player; each loadout held for the whole run once owned; the Foreman wears the Sweeper rig until its modules can be built in city 5):

| Loadout | Modules | Launch (bot min) | Player minutes in cities 3, 4, 5, 6 |
|---|---|---|---|
| Sweeper | Wide Sweep, Deep Hold, Sprint Coils | 118.5 | 31.3, 30.9, 33.9, 58.2 |
| Wrecker | Heavy Claw, Press Frame, Hover Skirt | 119.8 | 31.1, 32.5, 38.2, 55.3 |
| Skimmer | Long Reach, Deep Hold, Hover Skirt | 117.8 | 31.0, **28.2**, 35.7, 58.2 |
| Trader | Wide Sweep, Press Frame, Tow Hitch | 117.2 | 31.3, 32.3, **31.1**, 57.0 |
| Foreman | Guide Arm, Sorter, Relay Mast | 110.5 | 31.3, 30.9, 33.0, **42.9** |

- Spread between the best and the worst: **8.4%** (limit 8%) PASS, by a small margin.
- No loadout is quickest in every city: Skimmer wins city 4, Trader city 5, Foreman city 6; cities 1 to 3 are ties (no slot or no choice yet) PASS.
- The default player, who refits for each city by her own rule of thumb, finishes at 112.7: slower than a player who simply wears the Foreman rig from city 5. See 8.6.

## 6. The numbers the owner asked to judge

| | V1 | V2 |
|---|---|---|
| Largest price paid | 39,383 cubes | 4,200 cubes (a Sweep level in city 6's tier; the dearest one-off is Base level 6 at 3,000) |
| Peak income | 1,739 cubes a second (bot) | 103 a second at bot speed, about 51 for a player, late in city 5 |
| Income at bot minute 20 / 40 / 60 / 80 / 100 | 27 / 48 / 107 / 301 / 1,389 | 18 / 19 / 19 / 65 / 59 |
| Income by city, cubes a bot second | | 14, 16, 33, 40, 71, 51 |
| Most cubes held | 60,757 | 6,441 |
| Cubes held at the launch point | 30,150 | 3,970 |
| Cubes earned in the run | 1.94 million | 250,140 |
| Parts earned / left at the launch point | 6,796 / 505 | 9,935 / 1,521 |
| Dearest Parts price | 495 (fourth Assembler) | 600 (the rocket's nose cone); 414 for a type upgrade |

**What the floor is and what sets it.** With robots earning nothing, cube income is Lumi's own pace: **hexes a second by hand x cubes per hex x the bale multipliers** (1.5 perfect, Bale Tuning 1.2, Press Frame 1.25). The start is pinned by the rule that a bale sells for tens of cubes: 12 units x 0.81 = 9.7 loose, 14.6 baled. After that the only two things that make cubes grow are how many hexes a minute Lumi does and what a hex is worth.
- Lumi's hexes: her share of a city's cleaning x the city's hexes over its minutes. Cities are large (2,107 hexes in 48 player minutes in city 6), so even a 7% share is 3 hexes a player minute.
- Cubes per hex: 116 in city 1, then 120, 125, 130, 135 and 330.
- So the smallest numbers the cadence rules allow are simply the smallest hex values the lead accepts. The cadence rules never needed income to grow: they need prices to be 30 to 60 seconds of income, and prices are derived from income. Income here grows about 5x from city 1 to city 5 and prices with it. Flat hex values (116 everywhere) would cut city 6's income to about a third, and its prices with it. What that would cost: arriving in city 6, where a hex is nearly five times the work, would cut Lumi's income by two thirds.
- What does **not** set the floor any more: the spike rule. It still forces the cleaning volume up about 2,500x (4 units a second to 10,000), but that is now paid in hex weight (144 to 4,600 units), not in cubes.

**Seeds** (decision 9): earned 7,477 (20 from the kit, 1 a hex when it starts growing, 0.4 when it thrives, a slow bloom from thriving ground). Spent 6,231: 5,052 on planting, 1,179 on cleansing plants for blight in cities 5 and 6. Left 1,246, nearly all given back by city 6 as it thrives at the very end. Blight work never waited on seeds.

**Field data** (decision 10): earned 11,385, spent 7,565 on 20 research nodes, 3,820 unspent at the launch point. City 6 alone pays out about 4,400 (its hexes cleaned and their stages), most of it in the last minutes.

**The whole planet** (decision 5). After the launch point 158,790 cells are left: 31 times the six cities. Taken at city 6's weight (4,600 units a hex), cleaning only, with robots in real time:

| | Robots keep | Launch crew of 149 takes | To finish in 10 more hours | 20 hours | 40 hours |
|---|---|---|---|---|---|
| From the 6 city bases only (each serves 94 rings) | 71% of their speed | 31 hours | 459 robots | 229 | 115 |
| With 76 outposts (each serves 26 rings, like city 6) | 90% | 25 hours | 365 robots | 183 | 91 |

**"Thousands of robots" does not hold.** It holds only if the planet is to be finished in under 5 hours (4 with outposts). See 8.3.

## 7. How narrow the pass is

V1 broke on 2 of 4 changes of 2-5%. V2 was tuned for room and tested harder: 30 constants, each moved 10% down and 10% up, one at a time, default player. **All 60 runs pass every required check.** Launch between 109.8 and 118.1 bot minutes; crew between 140 and 161.

The eight most sensitive constants (largest relative move of the launch time or the launch crew), which the test suite re-runs:

| Constant | Value | -10%: launch, crew | +10%: launch, crew | Failed checks |
|---|---|---|---|---|
| Assembler seconds per robot | 40 | 113.5, 161 | 114.1, 140 | none |
| Lumi's base sweep rate | 4.0 | 118.1, 155 | 109.8, 150 | none |
| Mastery growth per level | 1.78 | 111.0, 145 | 117.5, 156 | none |
| Litter's Parts yield (hands) | 0.007 | 112.8, 149 | 116.2, 152 | none |
| City 1 work per hex | 144 | 114.4, 153 | 109.9, 146 | none |
| Sweep Speed, effect per level | 0.18 | 114.7, 152 | 110.3, 146 | none |
| Scoopie price in Parts | 10 | 115.0, 152 | 113.1, 149 | none |
| Chest size | 12 | 114.8, 152 | 111.0, 147 | none |

Tightest checks in the proposal itself: first payout (16 of 20 s, fixed by the chest), spike gap (32 of 40 min), track lead (39% of 50%), first hex (136 of 180 s). The rig spread (8.4% against 8%) is the narrowest result and is not covered by the sensitivity runs.

What made it robust, in order of effect: one Assembler line pacing the crew instead of Parts; research started only when the bank covers it (a slow node used to block the only slot and with it every blueprint); the Crew Overhaul as a clean doubling in the middle of city 6; salvage on arrival in city 3.

Still true: the search is a hill-climb plus hand tuning. It found a set that passes with room; it does not show this is the best set.

## 8. Where the decisions create new conflicts

Ordered by how much they matter.

### 8.1 Decision 1 alone does not make the numbers small; the hex-value rule does (my addition)
With robots earning nothing but each unit of work still paying, Lumi's income follows her own cleaning volume. That volume must keep up with the crew's (the spike rule, and hand share): her cleaning rate grows about 130x over the run (4 units a second to over 500). City 6's hexes are 4,600 units; paid by the unit that is about 4,400 cubes a hex against the 330 proposed, so about 13 times the income: roughly 700 cubes a second at the peak and prices around 50,000. That is where V1 already was.

So the proposal adds one rule: each city states what one hex is worth (`hex_cubes`), and a unit pays that divided by the hex's work. It is V1's option "pay by the hex" on top of decision 1. Its cost, as V1 said: heavier hexes do not pay more, so a spike is felt in speed and in the city, not in the wallet. **The lead should confirm this rule; every cube number in this document depends on it.**

### 8.2 Lumi's cubes stop whenever she is not sweeping
All cube income is now her own bales, so it is zero while she plants, waters, does a source job, fits a rocket part, or after the last hex of a city is clean. Measured: the longest time with no cube-priced offer in reach is 3 min 24 s (limit 4 min, reported only), and one-off payouts had to be re-measured (section 1). The fix in the proposal is to make **city stage payouts the tending income**: 100, 150, 300, 1,000 and 1,200 x the city's hex value over 100 (city 6: 3,300 for stage 4). Together they are about a tenth of all cubes (26,300), and the largest against income is 0.66 of the 3-minute cap (city 1 thriving).
Does the hand loop stay worth doing? Yes, and more than before: it is the only source of cubes, of mastery (which sets crew speed: 0.4 + 0.12 a level), and of source jobs and rocket fitting; with the source jobs and salvage it also brings 16% of Parts. Its share of the cleaning itself is small late (7% in city 6).
Can cubes pace a purchase every 3-4 minutes in cities 4-6? Yes: the longest cube-only wait in the whole run is the 3 min 24 s above, at the end of city 3, because prices are set from her income, not the crew's.

### 8.3 "The whole planet takes thousands of robots": it takes hundreds
Decision 5 expected distance to do this. It does not, for a plain reason: distance and outposts cancel. Tuned so that cities are barely touched (97% to 90% of robot speed), six bases alone still keep 71% over the whole planet; 76 outposts bring it back to 90%. The crew a job needs is work / (hours x robot rate), and the work is 31 cities' worth while the launch crew just did the largest city in 24 bot minutes. Result: 25 to 31 hours with the launch crew of 149; 365 to 459 robots for 10 hours.
What would make "thousands" true, each with its number:
- finish in under about 4.6 hours from the six bases (1,000 robots), or 2.3 hours (2,000);
- open ground about 3 times as heavy as city 6 (then 10 hours needs about 1,100 to 1,400 robots);
- robots that are slow away from a levelled base. The launch crew's speed is 17 times a rusty crew's (base levels x8.7, the Crew Overhaul x2). If a robot at a bare outpost keeps a third of its city speed, 10 hours needs about 1,100 to 1,400 robots; if it keeps none of the bonuses, about 6,000.
Recommendation: the third. It is a rule, not a bigger number: a robot is fast near a levelled base and slow at a bare outpost, so the long goal is building and levelling outposts. It needs the lead's decision and a model of outposts; neither exists yet.

### 8.4 The spike rule, the run's length and a no-robots player pull three ways
- The spike rule wants each long city to double the cleaning volume twice. Volume ends at about 10,000 units a second against 4 at the start.
- The run must not end before 105 bot minutes, so the hexes must be heavy enough to absorb that volume: 144, 340, 305, 540, 960 and 4,600 units a hex.
- A player with no robots must still clear those hexes alone: city 6 takes that player 125 bot minutes (over 4 hours of play), and the whole run 289 of the 300 the simulator allows.
The three are balanced on the edge. The hex weights are also ugly: city 2 is heavier than city 3, and city 6 is 4.8 times city 5. Recommendation: say that the no-robots player need only finish, with no time cap; or drop that player from the required list. Then city 6 can come down to about 2,000 units with a third spike source instead of raw weight.

### 8.5 The rocket is a ladder, but a short one
Its six parts are gated on city 6's progress and fall between player minutes 203 and 223: one every 3 to 4 minutes for 20 minutes, after 26 minutes with no rocket work. It cannot start earlier without failing the new-mechanic rule the other way (first order at minute 201 leaves 24 minutes before and after). Parts never hold it up for the default player (1,521 left over). If the lead wants the rocket to span the whole city, city 6 needs one more mechanic of its own late on.

### 8.6 Rigs: crew modules win wherever they exist
Decision 8 asked for crew modules and an 8% spread. Both are met (8.4%), but only by keeping the crew modules out until city 5. Once the crew does three quarters of the work, a module on Lumi's own rate moves a city by 2-9% and the three crew modules together by 26% (city 6: 42.9 minutes against 55 to 58). If they were buildable in city 3 the Foreman rig would win every city from there on. So "no loadout best in every city" passes on availability, not on trade-off. To make it a real choice the crew modules need a cost on Lumi (for example Guide Arm: robots +30%, Lumi's sweep -30%), which this proposal did not tune.
Also: city 2's crew is hand-built, 42 robots in 35 player minutes. That is a purchase every 50 seconds for one city. A "build 5" button or a smaller city 2 crew (buried parts 1.0 to 0.5 a hex) would fix it.

### 8.7 Parts: scarce at the start, in surplus from city 3
City 1 is as the owner asked: 0.84 Parts a hex by hand, the first robot at minute 18.8, 8 robots by the end. From city 3 the design keeps Parts in surplus on purpose, so that the Assembler's line and not luck paces the crew. The cost: Parts are no longer the reason for anything late except the rocket. The longest wait for a Parts purchase is 9 min 6 s (in city 3, from player minute 86, while the line keeps building robots); reported, not required.

### 8.8 Smaller conflicts
- **Robots on the bot's clock** (see "How far to trust it"). The full-game bot must settle how much shorter a real player's run is.
- **City 6 pays more per hex than city 5 by 2.4x** (330 against 135) and still earns less per second (51 against 71). It is the price of 8.4. Monotone income would need 460 a hex and a peak near 140 a second.
- **Seeds and field data are both left over** (1,246 and 3,820), mostly because the last city pays them out at the very end. They are what the player carries into open ground.
- **The Seedling moved to city 5.** The spec's order has planter and waterer in cities 3-4. With the Drip moved to city 4 (decision 3) I put the Seedling in city 5, where blight is, so city 4 does not become the new city 3. It needs blight mastery 2.
- **Stage share 80%**: unchanged; the default player cleans 100% of every city.

### 8.9 Things I added that section 16 did not ask for
Each is in the data and can be taken out; the numbers were tuned with them in.
- **Hex value per city** (8.1).
- **Crew Overhaul**: research in city 6 at 33% progress, 200 Parts and 1,500 field data, crew speed x2. It is city 6's second power spike, a late use for Parts and field data. It replaces V1's Linked Surge, which is removed.
- **One Assembler, no upgrade on this planet** (the spec has "a faster line, then a second line"). More lines made the crew's size depend on when the Parts pile was large enough, which is what made V1 narrow.
- **Salvage on arrival in city 3** (130 Parts, the shell of the old factory), so the Assembler stands 20 seconds after arrival instead of 4 minutes.
- **Lumi can dig buried parts herself** (1 per 3 s) when there is nothing else to do. Used for 2 Parts by the default player; it is what lets a player with no Scroungers finish.
- **Thriving ground keeps giving seeds** (0.006 a hex a minute). Without it city 6 locked up at 80% clean: blight needs seeds, seeds need planted hexes, hexes cannot be planted until the blight is gone.
- **Blueprints wait on mastery** (Drip: smog 1; Seedling: blight 2).
- **Research is started only when the bank holds its field data** (a rule of the simulated player, and a good rule for the game's bench).
- **Deeper last two track tiers** (10 and 20 levels) for a player who cleans by hand (8.4).
- Nothing here copies another game; the Assembler-and-Scrounger chain and the rocket are the owner's and the lead's.

## 9. What I would change, in order
1. Confirm or reject the hex-value rule (8.1). It decides every cube number.
2. Decide what "thousands of robots" should rest on (8.3); I recommend slow robots at unlevelled outposts.
3. Free the no-robots player from the time cap (8.4), then bring city 6's hex weight down.
4. Give crew rig modules a cost on Lumi and tune them as a trade-off (8.6).
5. Have the full-game bot measure the robots-in-real-time effect before any of these numbers is built (8.8).
