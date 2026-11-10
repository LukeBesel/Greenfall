# Balance proposal for the Planet 1 redesign (M3-01, Nov 10)

The Planet 1 redesign, tuned on paper with the fast simulator before any of it is built. Nothing in the game or its data was changed. The proposed numbers are in `tools/pace_sim/proposals/planet1/*.json`; the model that plays them is `--model=redesign` (see `tools/pace_sim/README.md`).

**Verdict.** With the proposed numbers the default player reaches the launch point (all six cities thriving) at **108 bot minutes** (about 3 h 36 min for a player) with a crew of **183 robots**, and **every required check passes**: 12 cadence checks, 6 design checks and 15 economy and crew checks. Two more numbers are reported but not required, because the rules behind them contradict other rules (section 8). The pass is real but **narrow**: small changes to one number break the crew-stall check (section 7), and three rules pass only under a reading I had to choose (section 8). Read section 8 before building from this.

Rules followed: `docs/PLAN.md` section 9, `docs/design/PLANET1_DESIGN.md` sections 1-14 as they stood at the end of Nov 10 (two goals; crew of 100 to 200 built by a Scrounger and Assembler chain; Assembler in city 3; one job per currency; scarce early Parts; the 30% hand-share rule replaced by 10% before district 4).

## How this was produced

```
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign            # the report below
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign --compare=1 # section 5
godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign --search=230 # the number search
```

A run takes about 4 seconds. Times are **bot** minutes; a new player is taken to be 2x slower. Every limit in PLAN section 9 is a player limit, so the report multiplies each measured time by 2 before comparing. This is stricter than the M1-12 baseline, which compared bot times with player limits. Growth timers (a watered hex grows for 180 s) are real time and are not doubled.

**How far to trust it.** The model is rates and events, not a world: no walking, no aiming, no physics. It is calibrated against nothing, because the redesign does not exist yet. Its use is to show which rules can hold together and roughly what size the numbers must be; the full-game bot has to confirm each milestone once it is built. The player policy is one plausible player (section 5 shows four others).

## 1. Cadence table

| Rule (PLAN section 9) | Limit (player) | Measured (player) | Result | Where |
|---|---|---|---|---|
| First payout | 20 s | 16 s | PASS | bot 8 s: 2 s to the first sweep, a 12-unit chest in 3 s, 2.5 s to the bin |
| First upgrade | 90 s | 52 s | PASS | Sweep Speed, 40 cubes |
| First clean hex | 3 min | 1 min 58 s | PASS | bot 59 s |
| Small win at least every | 40 s | 30 s | PASS | worst at the hop to district 2 |
| Something affordable, first hour | 3 min | 2 min 0 s | PASS | worst from player minute 31 |
| Something affordable, after | 4 min | 3 min 6 s | PASS | worst from player minute 97 (late city 3) |
| Longest gap between goals | 4 min | 58 s | PASS | |
| "Now" goal | 3 min | 58 s | PASS | |
| District-tier goal | 20 min | 13 min 12 s | PASS | the first 13 minutes: nothing district-sized completes before mastery starts |
| New mechanic, first hour | 15 min | 12 min 12 s | PASS | seed (minute 29) to the source job (minute 41) |
| New mechanic, after | 40 min | 35 min 56 s | PASS | district 5 entry (142) to district 6 entry (178) |
| Power spike (cleaning volume x2) | every 40 min | 36 min | PASS | spikes at player minutes 20, 38, 56, 80, 116, 140, 174, 194 |
| Launch point | 105-150 bot min | 108.0 | PASS | aim was 120 |

Design checks: no rig module is best in every city (arm: Wide Sweep 2 cities, Heavy Claw 1, Long Reach 3; chest: Deep Hold 3, Press Frame 3; drive: Sprint Coils 3, Hover Skirt 3) PASS. Tipping never out-earns pressing (worst ratio 0.74) PASS. No track leads the value ranking more than half the time (Sweep Speed 45%, Sweep Width 38%, Chest 9%, Tending 8%) PASS. First found piece at player minute 24.6 PASS. The Sprout set completes at the last source (bot 104.3 of 108) PASS.

Economy and crew checks (spec section 14):

| Rule | Limit | Measured | Result |
|---|---|---|---|
| First bale sells for tens of cubes | 10-99 | 44 | PASS |
| First upgrade costs tens | under 100 | 40 | PASS |
| District 1 tops out in the low thousands | 5,000 | 1,442 | PASS |
| Whole numbers in the first two districts | under 10,000 | 2,436 | PASS |
| Largest income jump from one purchase | x3 | x1.38 (the Baler) | PASS |
| Largest one-off reward | 3 min of income | 0.13 of that | PASS |
| One job per currency | 0 wrong | 0 | PASS |
| Parts per hex in district 1 | 0-3 | 1.35 (0.84 from hands, the rest the source's 45) | PASS |
| First robot | player minute 20 +/- 5 | 17.3 | PASS |
| Crew at the launch point | 100-200 | 183 | PASS |
| Crew climb | a handful, then tens | 8 after city 1, 53 after city 3 | PASS |
| Fastest crew doubling | not under 3 min | 13 min 14 s | PASS |
| Longest wait for a new robot, city 2 on | 6 min | 5 min 18 s | PASS (narrow) |
| Build against upgrade | each chosen at least 15% | 3 builds, 1 upgrade | PASS (only 4 real choices in the run) |
| Hand share of volume, cities 1-3 | at least 10% | 66%, 44%, 37% | PASS |
| *Reported only:* longest wait for a Parts purchase | 4 min | 19 min 40 s | see section 8.4 |
| *Reported only:* longest wait for a new robot in city 1 | 6 min | 6 min 16 s | see section 8.4 |

## 2. Beat timeline

| Beat | Bot min | Player min | PLAN target |
|---|---|---|---|
| Sweep and bin | 0.0 | 0 | 0 |
| First upgrade (bench) | 0.4 | 0.9 | 1.5 |
| First clean hex | 1.0 | 2.0 | 3 |
| Baler | 3.2 | 6.4 | 8 |
| Signal tower, mastery starts | 5.9 | 11.8 | 15 |
| First robot (hand-built Scoopie) | 8.7 | 17.3 | 20 |
| Research from field data | 10.2 | 20.3 | |
| First found piece, Locker | 12.3 | 24.6 | 25 |
| Seed found: planting, watering | 14.5 | 29.0 | 30 |
| City 1 source job opens | 20.6 | 41.2 | 40 |
| City 1 source shut: arm slot, Wide Sweep (spike) | 21.6 | 43.1 | 40 |
| City 2: wrecks, Lift II | 22.6 | 45.3 | 50 |
| First Scrounger, first Haul Bug | 27.5 | 55.0 | |
| City 2 source shut: drive slot, Hover Skirt | 34.8 | 69.6 | |
| City 3: slick | 36.7 | 73.4 | 80 |
| First Assembler: the chain closes (spike) | 42.7 | 85.4 | |
| First Skimmer; first Drip | 45.4; 47.2 | 91; 94 | |
| First robot type repaired | 53.9 | 107.8 | |
| City 3 source shut: chest slot, Deep Hold | 54.1 | 108.2 | |
| City 4: smog | 55.6 | 111.2 | 110 |
| First Surge | 60.6 | 121.2 | 110 |
| First Seedling | 61.7 | 123.4 | |
| City 4 source shut: Power Cell II | 70.5 | 140.9 | |
| City 5: blight | 71.0 | 142.0 | 145 |
| City 5 source shut: Power Cell III | 88.5 | 176.9 | |
| City 6: all five kinds | 89.0 | 177.9 | 180 |
| Linked Surge (added, see 8.7) | 99.1 | 198.2 | |
| Last source shut, Sprout set complete | 104.3 | 208.6 | 225 |
| The Bloom: launch ready | 108.0 | 216.0 | 225 |

Cleaning volume doubles at player minutes 20, 38, 56, 80, 116, 140, 174 and 194. Counted in hexes a minute instead, the rate goes from 1 at the start to about 105 at the end (bot speed).

## 3. Per-city table

| City | Rings | Hexes | Work per hex | Player min in city (spec target) | Crew at stage 4 (cap) | Hand share of volume | Buried parts per hex |
|---|---|---|---|---|---|---|---|
| 1 Old Town | 6 | 127 | 120 | 45 (50) | 8 (8) | 66% | 0 (hands only) |
| 2 Scrapyard | 9 | 271 | 125 | 28 (30) | 28 (28) | 44% | 1.5 |
| 3 Greywater | 12 | 469 | 155 | 38 (30) | 53 (70) | 37% | 1.8 |
| 4 Smogworks | 16 | 817 | 345 | 31 (35) | 75 (110) | 19% | 1.8 |
| 5 Ash Fields | 20 | 1,261 | 520 | 36 (35) | 102 (160) | 24% | 2.2 |
| 6 The Works | 26 | 2,107 | 880 | 38 (45) | 165 (200) | 25% | 2.6 |

- **Sizes.** The six cities are 5,052 hexes, **3.1% of the planet's 163,842 cells**. They are larger than the spec's first sizes (rings 6-16, 2,592 hexes) because 100-200 robots need ground and because the spike rule needs volume (8.1).
- **Crew over time** (bot minute: robots): 10: 2, 20: 6, 30: 14, 40: 32, 50: 46, 60: 59, 70: 75, 80: 90, 90: 107, 100: 141, launch: 183 (54 Scoopies, 33 Haul Bugs, 32 Skimmers, 28 Scroungers, 19 Seedlings, 13 Drips, 4 Assemblers; every type but the chain's two repaired). The Assemblers built 142 of them; the Scroungers carried in 3,858 of the 6,796 Parts earned.
- **City 2 on hand-building** (the owner's check): the crew goes from 8 to 28 by hand in 14 bot minutes, the longest wait for a robot is 5 min 18 s (player), and something is affordable at least every 2 minutes. It does not stall, but this is the narrowest check in the proposal.
- **Mastery at the end:** litter 7, wrecks 7, slick 8, smog 8, blight 7 of 10. Nothing is maxed.
- **Lumi's time:** sweeping 67%, planting 6%, watering 8%, source jobs 3%, the rest at the bench and on hops. Never idle.

## 4. The first ten minutes: chest against hex

| | Today (baseline) | Proposal |
|---|---|---|
| Chest | 12 units | 12 units |
| Junk to clear in a first hex | 387 units | 120 units |
| Loads per first hex | 34 | 10 |
| Sweep rate, bot | about 1 unit/s | 4 units/s (a player: 2) |
| Bin trip | 8 s and more | 2.5 s bot (bin a few steps from the pad) |
| First payout | 51 s | 8 s bot, 16 s player: 9.7 cubes |
| First upgrade | 84 s | 26 s bot, 52 s player: 40 cubes |
| First clean hex | 7.0 min | 59 s bot, 1 min 58 s player |
| Purchases in the first 10 bot minutes | 13 | 19 |

Why these sizes: the 20-second payout rule fixes the chest at what a new player fills in about 6 seconds; the 3-minute hex rule then caps a hex at about 10 such loads. A bigger chest breaks the first rule, a bigger hex the second. A loose load pays 1.0x and a perfect bale 1.5x, so the Baler (250 cubes, bot minute 3.2) is a 38% income step, not a jump. Chest Size adds one starting chest per level, so the first pressed bale already sells for 44 cubes.

## 5. Five players on the same numbers

| Player | Launch (bot min) | Crew | Crew after each city | Checks failed |
|---|---|---|---|---|
| default | 108.0 | 183 | 8, 28, 53, 75, 102, 165 | none |
| rush robots (every robot before any other Parts purchase) | 162.9 | 200 | 8, 28, 61, 110, 160, 200 | 8, see below |
| never builds robots | 179.0 | 0 | 0 | 11 (all the crew and spike rules) |
| Assembler builds only Scroungers | 159.3 | 200 (172 Scroungers) | 8, 28, 70, 110, 160, 200 | 6 |
| Assembler never builds a Scrounger | 128.5 | 127 | 8, 26, 40, 67, 91, 119 | 3 (spike gap, mechanic gap, crew stall) |

- **All five reach the launch point, and none in under 60% of the target (72 minutes).** The fastest is the default.
- **Rushing robots is slower, not faster.** That player spends every Part on the cheapest robot, never saves the 20 Parts for the Haul Rig, and ends with 200 Scoopies that cannot work wrecks, slick, smog or blight. Mastery and tool gates do their job. But the result is harsh: a player who does this gets a much worse game and nothing tells them why. The bench should refuse or warn ("no Scoopie can work wrecks").
- **The chain cannot be exploited.** An all-Scrounger mix hits the crew cap with 172 Scroungers, the ground runs out of buried parts, and the player finishes 51 minutes later than the default. The crew never doubles in under 3 minutes in any run.
- **The chain does not stall without Scroungers.** With only the one hand-built Scrounger and Lumi's own finds the Assemblers still build to 127 robots and the launch comes 20 minutes late.
- **No robots at all: 179 bot minutes, about 6 player hours.** Finishable, slow, and by hand through 4,400 hexes. The cities are sized for a crew.
- **Rig loadouts** (default player, modules held for the whole run): Wide Sweep + Deep Hold + Sprint Coils 108.7; Heavy Claw + Press Frame + Hover Skirt 107.7; Long Reach + Sorter + Tow Hitch 108.3; best per city 108.0. No module dominates, but see 8.9: the rig hardly matters.

## 6. The numbers the owner asked to judge

| | Value |
|---|---|
| Largest price paid | 39,383 cubes (Sweep Speed, last level of the city 6 tier) |
| Peak income | 1,739 cubes a second at bot speed (about 870 for a player), in city 6 |
| Income at bot minute 20 / 40 / 60 / 80 / 100 | 27 / 48 / 107 / 301 / 1,389 cubes a second |
| Most cubes held | 60,757 |
| Cubes held at the launch point | 30,150 |
| Cubes earned in the run | 1.94 million |
| Parts earned / left at the launch point | 6,796 / 505 |
| Dearest Parts price | 495 for the fourth Assembler (45, 195, 345, 495) |

**The whole planet.** After the launch point 158,790 cells are left. If open ground is as heavy as city 6 (880 units a hex), cleaning it at the launch-point rate (2,705 units a second with 183 robots) takes **about 14 bot hours**. Finishing in 10 more bot hours needs about 260 robots; in 40 hours, 66. So on these numbers the whole planet takes **hundreds of robots or tens of hours, not thousands** (8.6).

## 7. How narrow the pass is

Four single changes of 2-5% to one number each (city 6 hex work 880 to 920, city 1 hex work 120 to 126, the city 4 tier price 4,100 to 4,300, Scoopie rate 1.2 to 1.26): two still pass everything; two fail **crew_stall** (6 min 42 s and 9 min 18 s against 6 min). Nothing else moved. The cause is the hand-building stretch in cities 2 and 3: the player saves Parts for the next blueprint or the first robot of a new type, and for that long no robot is built. The other 31 checks have more room; the tightest are the spike gap (36 of 40 min), the later mechanic gap (36 of 40) and the launch time (108 against a floor of 105).

The search (`--search`) is a coordinate hill-climb over 17 numbers (hex work per city, tier prices, robot rates, two track weights). It found a set that passes; it does not show that this set is the best, or the slowest price curve.

## 8. Where the design rules do not work

Ordered by how much they matter.

### 8.1 The spike rule forces big numbers; "numbers stay small" cannot hold after city 3
The rule "a power spike every 30-40 minutes, each at least doubling the cleaning rate" over 4 hours is 6 to 8 doublings: the cleaning rate at the end must be 64 to 256 times the rate at the start. The proposal has 8 spikes and ends at about 300 times the starting volume. Income follows volume. From 1.2 cubes a second at the start that is 1,700 a second at the end, a largest price of 39,383 and 1.94 million cubes earned, even after I cut everything that multiplies income (robot bales pay 12% of hand value, hex and stage payouts are 10-20% of a hex's hand value, no income multiplier above x1.35).

The early limits hold (bale 44, first upgrade 40, city 1 at most 1,442, cities 1-2 under 2,500). The late numbers are not small. The three rules "spike every 30-40 min", "crew of 100-200" and "slowest price curve" cannot all be met. Options, each with a cost:
- **Pay by the hex, not by the unit** (a bale's price rises only with the city's richness, about 1.3x a city). Income would then grow with hexes a minute (about 100x) instead of with volume (1,400x here). Cost: heavier hexes stop paying more, so the spike is felt in speed only.
- **Relax the spike rule to "every 30-40 min in the first 2 hours, then one per city".** Cost: a flatter late game.
- **Accept 5-digit prices in cities 5 and 6.** This is what the proposal does.

Also note the spec's own section 12 line ("hand rate grows from 1 hex per 2.5 min to about 4 hexes a minute") is a 10x growth, three doublings. It cannot satisfy the spike rule by itself; the proposal makes later hexes heavier (120 to 880 units) and the cities bigger to get there. Measured in hexes a minute the rate still grows about 100x.

### 8.2 Player time against bot time
PLAN section 9 limits are written for a player and checked on the bot. At 2x, "a purchase every 3 minutes" means every 90 bot seconds and "a spike every 40 minutes" every 20 bot minutes. The proposal is tuned to that stricter reading. The M1-12 baseline was not; its PASS on "first upgrade within 90 s" (84 bot seconds) is a FAIL for a player. The plan should say which clock each rule uses.

### 8.3 City 3 is where everything collides
The Assembler now arrives in city 3. So city 3 must: introduce slick, have Lumi hand-build the first Skimmer and Drip, pay for two blueprints, build the Assembler, and keep the crew growing, all from Parts that only three or four hand-built Scroungers bring in. It runs 38 player minutes against a target of 30, and it is the reason the pass is narrow. Recommendation: move one thing out. The cleanest is to give the first Assembler as city 2's source reward (it stands idle until the blueprint research in city 3, or simply works at once), or to make the Drip a city 4 unlock.

### 8.4 Scarce Parts against "never wait more than 4 minutes for Parts" and "never more than a few minutes without a new robot"
In city 1 a hex gives 0.84 Parts by hand and a Scoopie costs 10. That is one robot per 12 hand-cleaned hexes, 6 min 16 s at worst for a player, and it is what makes the first robot "an achievement". The same scarcity makes "a Parts-priced offer is never out of reach for more than 4 minutes" false: the longest such wait is 19 min 40 s (in city 5, while a type upgrade or the next Assembler is out of reach; in city 1 it is about 6 min). Both are reported, not required. What holds: something is always affordable in cubes, so Parts are never the reason *nothing* can be bought. If the owner wants the stronger rule, city 1 needs about 1.5 Parts a hex and a Scoopie at 8.

### 8.5 The hand-share rule
The old 30% rule cannot hold with a crew of 100-200: hand share is 19-25% in cities 4-6 even though Lumi's own cleaning volume grows about 100x. The new rule (10% before city 4) passes easily (66%, 44%, 37%). "Lumi's actions always decide what the crew can do" holds in the model by construction: no robot works a kind below mastery 1, no hex passes stage 3 before the source job, every first robot of a type is hand-built.

### 8.6 "The whole planet takes thousands of robots"
On these numbers it takes about 14 more bot hours with the launch crew (section 6). A crew strong enough to restore 2,107 hexes in 15 bot minutes does the other 158,790 in hours. For "thousands of robots" to be true, open ground must be about 10x heavier than city ground, or the crew's speed must fall with distance from a base (the current game does this: 50 s a ring). The second is the better lever and fits "zones at scale"; it is not in the model.

### 8.7 City 6 has no mechanic of its own
Cities 2-5 each bring a kind. City 6 is "everything at once", so from its entry to the launch there is no new mechanic for 38 player minutes, and with city 5's 36 the later-mechanic rule only just passes. I added one: **Linked Surge** (research in city 6: the crew in Lumi's city works at double speed during a Surge). It lands at player minute 198. It is my addition, not the spec's; replace it with anything that is a new verb.

### 8.8 Smaller conflicts
- **Tipping against pressing.** Today loose trash pays 1.3x and a perfect bale 1.5x. A player who presses imperfectly earns less than one who tips. The proposal sets loose to 1.0x.
- **Finds.** "About one piece per 40 hexes" and "about 8 colours in total" differ by 16x over 5,052 hexes. The proposal places 8 by schedule (first at hex 42).
- **Surge.** Spec section 8 has the growth wave "from district 4", PLAN section 7 has the Surge unlocked in district 4. The proposal unlocks both together in city 4. At 12 s of x3 per 120 s of charge the Surge is an 18% average gain: a moment, not a power spike.
- **Stage share 80%.** A city thrives with a fifth of it untouched. The default player cleans 94-100% anyway because cleaning is what Lumi does while plants grow.
- **Research.** One node at a time, fed only while active: 7,243 field data (about half) is earned with nothing to spend it on. Either bank it or add nodes.
- **No smog robot** is named in the unlock order. The proposal lets the Drip mist smog. Without that, 30% of city 4 is hand-only and the crew idles.
- **Seeds** stop mattering after the first minute of planting (2,250 left over). As a currency they need a second use.
- **District-tier goals:** nothing of that size completes in the first 13 player minutes.

### 8.9 Things that pass but are weak
- **Rigs barely matter.** The best fixed loadout and the worst differ by 1 bot minute in 108. Once the crew does 75% of the volume, Lumi's rate on one kind is a small term. If rigs are meant to be a real choice they need effects on the crew or on Parts.
- **Sweep Speed is nearly dominant.** It passes (45% of leads) only because it is priced 1.55x and Sweep Width 1.7x a Chest level. At equal prices one of the two leads 70% of the time.
- **Build against upgrade** is a real choice only 4 times in the run. Most of the time the Assembler builds and the bench upgrades from what is left.
- **Parts have little to buy late**: once the fourth Assembler and the type upgrades are bought, only robots are left, and the Assemblers set the pace.

## 9. What I would change, in order
1. Decide 8.1 (pay by the hex or accept 5-digit prices). It moves every late number.
2. Move one job out of city 3 (8.3).
3. Add distance cost to far crews so the whole planet is a long goal (8.6).
4. State the clock for each cadence rule (8.2).
5. Give city 6 a mechanic (8.7) and the rig a reason (8.9).
