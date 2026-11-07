# Balance

How Greenfall's first district (Old Town, 33 junk hexes: 27 land + 6 lake) is paced, how it was
measured, and what was tuned. All numbers are game time (the sim clock, `GameState.stats.time_played`).

## Measuring: the autoplay bot

`tools/autoplay.gd` (AutoplayBot) plays like a sensible human:

- **Cleaning**: one focus hex at a time (the nearest unfinished one, preferring hexes already started),
  bales near the Perfect band, carries bales to the scale until a Haul Bug exists (then leaves them).
- **Parts**: follows the detector to buried parts within 14 m and digs them; at Haggle's it swaps three
  spares for a needed part, and buys the missing rusty parts (80 each) only when that plus the robot's cost
  is affordable.
- **Workbench** (walks back when something worth buying is affordable): research (Robotics/Botany first,
  then the logistics line to the Recycler), goal-unblocking upgrades, robots (Bots tab logic:
  `Fleet.can_build/build`), base levels, stations, Water Tanks, cheapest *useful* upgrade (cleaning upgrades
  stop being useful once the land is clean), Air Scrubbers when rich or when a goal asks, the compost press
  when seeds run short. When the next base level's materials are in, it saves cubes for it and only buys
  robots that can't wait (Drips the garden needs, the lake's Skimmer, the first of each type, goal robots).
- **Command**: paints the clean crew's zone on the nearest unfinished hexes (frontier), the water and plant
  crews' zones on the garden hexes; moves Multibots from clean to water once the land is clean.
- **Garden**: picks up the seed tin, plants one hex at a time, waters by hand until a Drip exists (and
  again when there is nothing left to clean), refills at the base barrel. Reads memory shards (closes the
  document), gives up on unreachable shards/parts/pieces after a while.
- Research runs on wall-clock time in the real game; the bot drives `Research.now_override` from the game
  clock so a time-scaled run sees research at a player's pace.

Run (about 125 game minutes at 8x on a shared 4-core box):

    godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=950

`screenshots/autoplay_report.json` holds: first-time marks (`first_robot_s`, `first_hexlv_4_s`,
`base_3_s`, ...), a `timeline` (every goal completion, hex clean, hex level-up, robot, research start/finish,
base level, station, tank, part), a per-minute `log` (cubes, income rate, lifetime earned, Data, seeds,
materials, hex level counts, fleet, task), `goal_gaps_min` (stretches > 3 min with no goal completed) and
`dead_gaps_min` (> 3 min with no goal and nothing new bought: upgrade, robot, research, station, base).

## Targets

- A next goal within ~1-3 min, no dead stretch > 3 min, through the first ~2 hours.
- First robot ~6-10 min; first planting ~20-25 min; first Sustained hex by ~45 min; base level 3 by ~75 min.
- Research always has something to start; late costs don't explode; no softlocks, no money loops.

## Results (before -> after)

| Milestone (game min) | Before | After |
|---|---|---|
| First hex clean | 0.9 | 1.0 |
| First robot (Scoopie) | 1.7 | 6.2 |
| First Haul Bug | 3.0 | 6.2 |
| First research done | 4.5 | 3.9 |
| Base level 2 | 19.7 | 12.7 |
| First planting (hex Planted) | 5.8 | 20.5 |
| First hex Growing | 6.5 | 21.2 |
| First Seedling | 12.7 | 20.6 |
| First Drip | 25.6 | 24.2 |
| First hex Sustained | 8.7 | 23.4 |
| First hex Thriving | 9.7 | 24.6 |
| First Multibot | never | 47.1 |
| Base level 3 | never | 38.4 |
| Base level 4 | never | 49.7 |
| Base level 5 | never | 74.7 |
| Goals done by end | 37/50 | 93/96 |
| Land+lake hexes clean | 27/33 | 33/33 |
| Research nodes done | 17 | 26 |
| Parts bought at Haggle's | 93 | 72 |
| Cubes earned (lifetime) | 58449 | 189209 |
| Run length (game min) | 124.8 | 120.9 |

**Before** goal gaps > 3 min: [[7.8, 13.0, 5.2], [13.0, 19.7, 6.7], [19.8, 25.6, 5.8], [26.8, 30.9, 4.1], [30.9, 124.8, 93.9]]  
dead gaps (no goal, nothing bought) > 3 min: [[41.5, 44.6, 3.2], [47.3, 50.9, 3.6], [56.3, 59.4, 3.1], [64.8, 68.7, 3.9], [71.3, 101.4, 30.2], [101.4, 124.8, 23.4]]

**After** goal gaps > 3 min: [[12.7, 16.8, 4.1], [16.8, 20.3, 3.5], [30.6, 33.7, 3.1], [43.3, 47.1, 3.9], [54.4, 58.9, 4.5], [61.2, 65.2, 4.0], [65.2, 74.7, 9.5], [74.7, 90.2, 15.5], [90.2, 120.9, 30.7]]  
dead gaps (no goal, nothing bought) > 3 min: [[54.4, 58.9, 4.5], [61.2, 65.2, 4.0], [65.2, 74.7, 9.5], [75.8, 79.7, 3.9], [82.6, 87.8, 5.2], [90.2, 96.1, 5.9], [96.1, 104.4, 8.3], [104.4, 115.1, 10.7], [115.1, 120.9, 5.8]]


Both runs: same bot, seed 4471, `--fresh --autoplay --time-scale=8 --quit-after=950` (the "before" run is the
original data with this bot; its later robustness fixes, such as giving up on unreachable shards, don't change the
early picture). Gaps in the "after" run: up to ~65 min no goal waits more than 4.5 min. From 65 min the district is
finished (all 27 land hexes Thriving, lake skimmed) and the bot saves for base 5 (9.5 min), then the chain asks for
the rocket, which the bot doesn't fly: everything after 75 min is the next district's job.

Targets: first robot 6.2 min (6-10), first planting 20.5 (20-25), first Sustained 23.4 (by 45), base 3 at 38.4
(by 75). Research: 26 of 30 nodes by ~65 min, always something to start until the last four 250-380 nodes.
Run-to-run spread over the last five runs: first robot 5.5-6.5, planting 17-22, base 3 37-43.

<details><summary>Before: timeline (47 events)</summary>

| min | events |
|---|---|
| 0.1 | goal `scoop_15`, goal `bale_1`, goal `upgrade_1` |
| 0.2 | goal `perfect_1`, goal `cash_1` |
| 0.9 | goal `hex_1` |
| 1.1 | goal `upgrades_5` |
| 1.4 | goal `compartment_3` |
| 1.7 | first scoopie |
| 2.6 | goal `cash_10`, goal `earn_1k`, goal `scoopie_1` |
| 2.9 | goal `hex_3`, goal `zone_1` |
| 3.0 | first haulbug |
| 4.5 | goal `hex_5` |
| 5.5 | goal `seeds` |
| 5.8 | goal `plant_5`, first hex at level 2, goal `hexlv_2`, goal `haulbug_1` |
| 6.5 | first hex at level 3 |
| 7.8 | goal `bloom_5` |
| 8.7 | first hex at level 4 |
| 9.7 | first hex at level 5 |
| 12.7 | first seedling |
| 13.0 | goal `hex_10`, goal `hexlv_3` |
| 19.7 | goal `base_2`, **base level 2** |
| 19.8 | goal `plant_25`, goal `hexlv_4`, goal `shards_2`, goal `robots_4`, goal `bloom_25` |
| 24.4 | station conveyor |
| 25.6 | first drip, goal `drip_1` |
| 26.5 | goal `drip_2` |
| 26.8 | goal `hex_25`, goal `earn_10k` |
| 30.9 | goal `hexlv_4x3`, goal `hexlv_5`, goal `seedling_1`, goal `upgrades_25`, goal `zone_6`, goal `hexlv_5x3` |

</details>

<details><summary>After: timeline (110 events)</summary>

| min | events |
|---|---|
| 0.3 | goal `scoop_15`, goal `bale_1`, goal `upgrade_1`, goal `perfect_1` |
| 0.4 | goal `cash_1` |
| 0.9 | goal `upgrades_5` |
| 1.0 | goal `compartment_3`, goal `hex_1` |
| 3.0 | goal `hex_3`, goal `parts_2`, goal `shards_1` |
| 3.1 | goal `earn_1k` |
| 4.0 | goal `research_1` |
| 4.9 | goal `cash_10`, goal `zone_1` |
| 6.0 | goal `hex_5`, goal `upgrades_12` |
| 6.2 | first scoopie, goal `scoopie_1`, first haulbug, goal `haulbug_1`, goal `earn_3k` |
| 7.2 | goal `research_4` |
| 7.7 | goal `hex_7` |
| 7.9 | goal `upgrades_20` |
| 10.2 | goal `scoopie_2` |
| 10.9 | goal `hex_10` |
| 11.1 | first skimmer |
| 11.4 | goal `bales_20` |
| 12.2 | goal `hex_12` |
| 12.6 | goal `research_6`, goal `robots_4` |
| 12.7 | goal `upgrades_25`, goal `base_2`, **base level 2** |
| 16.8 | goal `hex_15` |
| 20.3 | goal `seeds` |
| 20.5 | goal `plant_5`, first hex at level 2, goal `hexlv_2` |
| 20.6 | first seedling |
| 20.7 | goal `seedling_1` |
| 20.8 | goal `plant_25`, goal `shards_2` |
| 21.2 | first hex at level 3, goal `hexlv_3`, goal `research_8` |
| 22.5 | goal `bloom_5` |
| 23.2 | goal `bloom_25`, goal `earn_10k`, goal `plant_60` |
| 23.4 | first hex at level 4 |
| 24.2 | first drip, goal `drip_1`, goal `tank_1`, goal `zone_6`, goal `bales_100`, goal `hex_17`, goal `hexlv_4` |
| 24.3 | goal `hexlv_4x3`, goal `hex_20`, goal `drip_2` |
| 24.6 | first hex at level 5, goal `hexlv_5` |
| 24.8 | goal `drip_4` |
| 25.2 | goal `research_12` |
| 25.3 | goal `skimmer_1` |
| 27.1 | goal `hexlv_4x5` |
| 28.1 | station conveyor |
| 28.9 | goal `hexlv_5x3` |
| 29.0 | goal `hex_25` |
| 30.6 | goal `hexlv_4x8`, goal `plant_100`, goal `robots_15` |
| 33.3 | station recycler |
| 33.7 | goal `recycle_5` |
| 34.1 | goal `earn_50k` |
| 34.2 | goal `hex_28` |
| 35.1 | station auto_baler |
| 36.6 | goal `hex_30` |
| 38.3 | goal `base_3`, goal `bloom_300` |
| 38.4 | **base level 3** |
| 40.7 | goal `research_20`, goal `upgrades_40`, goal `hexlv_5x8`, goal `earn_75k`, goal `hexlv_4x10` |
| 40.8 | goal `hexlv_4x15` |
| 42.0 | goal `stipend_2k` |
| 43.3 | goal `hexlv_5x15` |
| 47.1 | first multibot, goal `multibot_1`, goal `earn_100k`, goal `hexlv_4x20` |
| 49.7 | **base level 4**, goal `base_4`, goal `bloom_500` |
| 49.8 | goal `hexlv_5x20` |
| 52.0 | goal `stipend_5k` |
| 53.4 | goal `research_24` |
| 54.4 | goal `air_1k` |
| 58.9 | goal `stipend_7k`, goal `hexlv_5x25` |
| 61.2 | goal `research_26` |
| 65.2 | goal `stipend_10k` |
| 74.7 | goal `base_5`, **base level 5**, goal `earn_150k` |
| 90.2 | goal `stipend_20k` |

</details>


## What the "before" run showed

- **Robots at 1.7 min.** Haggle's sells rusty parts for 80 cubes; a Scoopie was 120 + 4 parts = 440 cubes.
  Crew cap 6 per crew at level 1, so 6 Scoopies and 3 Haul Bugs by 10 min.
- **Seeds at 5 min, Sustained at 9 min, Thriving at 10 min.** The seed tin needed 5 clean hexes (the six
  ring-1 hexes are tiny: ~115 pieces, ~17 plant slots) and Patch can hand-water a small hex to Sustained.
- **Goal chain stuck for 90 minutes.** `parts_2` (dig up 2 parts) could never finish: the field buried
  exactly one part (`chance_per_hex` 0.14). `hex_50`/`hex_100`/`earn_100k` could not be reached in a district
  with 33 junk hexes and ~60k cubes of junk. From 31 min on, no goal completed at all.
- **Land clean at 37 min, then zero income.** Every cube came from junk; once it was gone only one-off
  hex-level rewards remained. Base 3 needed 80 sheet metal and the district only yielded ~60 at 0.12/unit:
  base 3 never happened; base 4 (18k) and base 5 (90k cubes, 500 metal) were unreachable: the rocket was
  soft-locked.
- **Research starved.** Data came at 3 per hex; the tree (7,000 Data) could not be afforded; long idle
  stretches with nodes open.

## Data changes

| File | Key | Before | After | Why |
|---|---|---|---|---|
| robots.json | scoopie / haulbug / seedling / drip / skimmer / multibot cost | 120 / 160 / 400 / 400 / 450 / 900 | 1100 / 400 / 700 / 700 / 800 / 1600 | First robot ~6 min instead of 1.7; robots are a purchase you plan for |
| robots.json | crew_cap base + per_level x hub level | 3 + 3 (6 at L1) | 1 + 2 (3 at L1, 5 at L2, 7 at L3) | Base levels unlock crew room: "upgrade the base, build more bots" |
| parts.json | chance_per_hex | 0.14 | 0.45 | ~10 buried parts instead of 1 (the dig goal was impossible) |
| plants.json | first_seed.hexes_needed | 5 | 17 | Seed tin (first planting) at ~20 min, after the robot/automation phase |
| research.json | node costs by tier | 25/60/120/220/380/600 | 25/60/100/160/250/380 | Whole tree affordable in the district |
| research.json | data_rewards | hex 3, restored 6, bloom 1, shard 15, robot bale 0.5 | 10, 15, 1.5, 20, 1.0 | Research never waits long for Data |
| research.json | recycler | tier 4, needs haul_routes + auto_sort, 250 | tier 3, needs auto_baler, 160 | Recycler arrives while there is still junk to recycle |
| research.json | haul_routes / rocket_cargo | tier 3 needs auto_baler / needs recycler | tier 4 needs recycler + auto_sort / needs haul_routes | Keeps the logistics column a line |
| hub.json | material per_unit metal/plastic/glass | 0.12 / 0.10 / 0.10 | 0.30 / 0.12 / 0.15 | Metal was the hard wall for base 3 |
| hub.json | L2 | 600c, 25 metal, 10 plastic | 1500c, 25 metal, 15 plastic | |
| hub.json | L3 | 3500c, 80 metal, 40 plastic, 20 glass | 12000c, 90 metal, 60 plastic, 30 glass | Base 3 at ~45-75 min |
| hub.json | L4 | 18000c, 200 metal, 120 plastic, 90 glass | 35000c, 100 plastic, 40 glass | Fits what a district yields (no metal after the junk is gone) |
| hub.json | L5 | 90000c, 500 metal, 300 plastic, 250 glass | 30000c, 80 plastic, 30 glass | Reachable: was a rocket softlock |
| hub.json | Air Scrubber | 1200c + 30 metal + 15 plastic | 1200c | Scrubbers can't eat the materials the base needs |
| stations.json | auto_baler / recycler metal | 30 / 40 | 20 / 25 | |
| hex_levels.json | sustain_ratio | 0.9 | 0.8 | 27 hexes sustained by ~9 Drips at crew cap; was a 40-min stall at 20 hexes |
| robots.json | drip tank | 20 | 26 | Fewer refill trips per sustained hex |
| hex_levels.json | Sustained / Thriving bonus | grow/seed only | + cubes_per_min 5 / 10 (cap 400) | Garden stipend: income after the junk is gone |
| hex_levels.json | Sustained / Thriving reward | 300c + 5 seeds / 750c + 8 seeds | 150c + 5 seeds + 10 Data / 400c + 8 seeds + 20 Data | Late research keeps moving |
| goals.json | chain | 50 goals | 96 goals | Filled the 5-12, 13-20 and 22-60 min holes; replaced unreachable `hex_50` -> `hex_30`, `earn_100k` -> `earn_50k` (+ later `earn_100k`/`earn_150k`), moved `hex_100` after the rocket; new research/robot-bale/Drip/Skimmer/Recycler/Sustained/Thriving/stipend/air goals |

Code changes are small: `plants/hex_levels.gd` pays the stipend (`_pay_stipend`, data-driven
`cubes_per_min` bonus) and shows Data in level-up toasts; `core/offline.gd` + one call in `scenes/slice.gd`
(exploit fixes below); `player/patch.gd` gets a fall-through safety net (one long run pushed Patch
through the ground near the base and he fell forever; he is now put back in the yard and the `fell_through` stat counts it).

## Exploits found and fixed

1. **Offline income from nothing.** `Offline.compute` paid cleaners for up to 8 h of junk per session no
   matter how much junk was left, and never removed it. A clean district paid out forever by closing and
   reopening the game (the "waiting at the hub" path even paid without haulers). Fix: `compute(...,
   junk_left)` caps offline junk at the district's remaining volume (`tests/test_offline.gd`).
2. **Ledger dumps were profitable.** A dump drone revives a few pieces on a clean hex; re-cleaning it paid the
   full hex bonus again (`20 + 0.25 x total volume`) and counted again toward "Clean N hexes". Fix: a hex pays
   its volume bonus and counts once (`GameState.world.hexes_paid`); re-cleans pay the flat part only.
3. Checked and fine: goal and hex-level rewards are one-off (levels never drop); plants bloom once per slot
   (seeds can't loop); recycler pays 0.25x cube value plus materials (no loop); Haggle's buy/swap/scrap has no
   path back to cubes; the auto-baler presses at 0.85x.

## Lumi Level (Lumi XP)

A light, always-on level shown as the thin bar above the hotbar (`systems/lumi_level.gd`,
`data/lumi_level.json`). XP comes from everything: scoop 1 per piece, bale pressed 3, bale sold 4 (robot
deliveries count), part dug 12, hex cleaned 25, hex level-up 15 x (level - 1), goal 20 + 1 per chain index,
world event handled 50 (missed 10), achievement 15, research 20, upgrade 3, robot built 8, plant 2, bloom 2.

Curve: XP from level L to L+1 is `need(L) = round(150 * L^1.5)`.

| Level | XP to next | Lifetime XP to reach the next level |
|---|---|---|
| 1 | 150 | 150 |
| 2 | 424 | 574 |
| 3 | 779 | 1,353 |
| 5 | 1,677 | 4,230 |
| 10 | 4,743 | 21,400 |
| 15 | 8,714 | 56,709 |
| 20 | 13,416 | 114,117 |
| 30 | 24,648 | 308,189 |

Rewards per level: cubes = about 30 s of current income, floored at 15 x L and capped at
max(30 x L^1.5, 0.4% of lifetime cubes) so early income spikes can't flood the economy; seeds every 2nd
level once the garden is open (4 + L/10); every 5th level a robot part (Common, then better rarities every
15 levels) and tokens (1 + L/10); every 10th level a Lumi keepsake for the Collection (5 in order, then 3
tokens). Level-up: thin flash along the bar, "LEVEL N" and the reward line, one soft chime.

Measured with the autoplay bot (`--autoplay --time-scale=8`, game minutes): level 2 at 0.3 (the first
goals pay XP), 3 at 1.5, 4 at 4.5, 5 at 7.2, 6 at 11.9, 7 at 19.1, 8 at 25.5, 9 at 33.5, 10 at 41.8, 11 at 61.9
(still 11 at 90 min, when the land is clean and XP comes from the garden, events and research). Early levels
come every 1-5 minutes, then every 6-8, then 20+: the grind is the late game. The bot ignores most world
events, so a human levels a little faster.

## Formulas (current)

- Upgrade cost: `base_cost * growth^level` (data/upgrades.json; robots' fleet upgrades in robots.json).
- Robot build cost: `cost * 1.35^(robots of that type)` (fleet.gd); Mk tiers: `cost * cost_mult` + a core
  of the tier's rarity + 10/40/150 bolts.
- Crew cap per role: `crew_cap.base + crew_cap.per_level * hub level`.
- Hex clean bonus: `bonus_base + bonus_per_volume * hex volume` (planet.json), once per hex.
- Garden stipend: `sum over hexes of the cubes_per_min of every level reached` (capped), paid every sample.
- Bale value: `sum(volume * junk value) * cube_value_mult * (2 if pure) * (1.5 if perfect) * (0.8 if lumpy)`
  then `* (1 + hub sell_mult)` at the scale.

## Notes and open issues

- A district's junk (and so its materials) is finite: ~11,000 volume of land junk, ~200 metal without the
  Recycler, ~300+ with it. After the land is clean, cubes come from the garden stipend, hex-level rewards and
  goals. Keep base 4/5 material costs under what one district yields.
- Haggle's part prices are hard-coded in `ui/trade_panel.gd` (`BUY_PRICE`, 80 for a rusty part); they set how
  early the first robot can be. Moving them to data/parts.json would make them tunable.
- Patch can hand-water a small ring-1 hex to Sustained a few minutes after planting, so the first Sustained
  hex comes ~3-5 min after the first planting; later hexes need Drips (crew caps scale with base level).
- **Laser Reach / Multi-Lock** (added on the main branch while this pass ran, not in this worktree): the bot buys
  them like any other cheapest-useful Patch upgrade and treats them as cleaning upgrades. Multi-Lock (several
  pieces per pulse) speeds Patch's own cleaning, which pulls the seed tin (gated on 17 clean hexes) and the first
  planting earlier; re-run the sim after the merge and, if planting lands before ~18 min, raise
  `first_seed.hexes_needed` or Multi-Lock's `base_cost`.
- `tier_1` (Mk II) needs a Restored Control Core, which only comes from digging/salvage luck; it sits late in
  the chain so it can't block.

## Frontier districts (late game, wt/biomes)

Four frontier districts extend the grind after the ordinary bases (`data/frontiers.json`). Numbers from
`godot --headless --path . res://tools/frontier_balance.tscn` (one representative seed; "Value at scale" is
volume x junk value x the frontier's `value_mult`, before Pure/Perfect bonuses and hub sell bonus;
"Base 1-5 cubes" is the sum of hub level cube costs x `cost_mult`):

| District | Hexes (water) | Pieces | Junk volume | Volume x value | Value at scale | Base 1-5 cubes |
|---|---|---|---|---|---|---|
| Ordinary district | 32 (0) | 13232 | 12925 | 10130 | 10130 | 78500 |
| Dust Flats | 60 (0) | 23729 | 37772 | 31109 | 93327 | 314000 |
| Frozen Port | 60 (23) | 22520 | 38924 | 28777 | 143885 | 549500 |
| Sunken City | 60 (54) | 15569 | 19193 | 13209 | 105675 | 628000 |
| Cradle Returns | 60 (0) | 23729 | 48696 | 39197 | 470369 | 1256000 (starts at base 3: 1.04M left) |

- **Size**: radius 4 (60 junk hexes vs ~33), 1.5-3x the junk volume of an ordinary district, bulkier pieces
  (`vol_mult` 1.3-1.6: more compartment per piece, so more bales per hex). Sunken City floats 3.2x the usual
  lake junk and every drained hex gets ~30% of its pieces back as stranded silt.
- **Pay**: bales sell for x3 / x5 / x8 / x12, so cubes per minute keep pace with late-game research and robot
  tiers; base levels cost x4 / x7 / x8 / x16 the cubes (materials unchanged: finite per district). The
  cost-to-junk-value ratio (3-6) stays under the ordinary district's (~7.8) because the garden stipend and
  hex-level rewards are not multiplied in frontiers.
- **Gates** (unlock chain): Dust Flats = Dune Charts (600 Data, 7 min) + 2 bases at level 5; Frozen Port =
  Thermal Lance (800, 8 min) + 3 bases at 5 + Dust Flats base 3; Sunken City = Pump Works (1000, 10 min,
  after Dew Condensers) + 4 bases at 5 + Frozen Port base 3; Cradle Returns = Ark Beacon (1500, 15 min) +
  all three frontier bases at 5 + every frontier 50% Growing or better. Research tiers 6-7 add 8 nodes
  (5,850 Data in total).
- **Rarer seeds**: frontier natives have seed_yield 0.6-0.9 (meadow species 0.5-1.5) and ordinary species
  only roll at `native_mult` (0.35 in the Dust Flats, 0.5 in the Sunken City); the Frozen Port grows nothing
  outdoors without Cold-Hardy Seeds (950 Data) and only cold-hardy species then.
- **Twists that cost time** (all tunable in data):
  - Dust Flats: a sandstorm every 5-8 min (first ~2.5 min after landing) re-dusts 2 + cleaned/10 hexes (max 6)
    with ~7% of their volume; planted hexes and anything within 1 ring (2 with Dune Fences, which also cut the
    storm 40%) of a Sustained hex are safe. Plants dry 1.5x faster; the base well is dry and tanks refill at
    0.3x (x2.5 with Dew Condensers), so Drips need several tanks.
  - Frozen Port: ~85% of hexes (50% of ring 1) and the whole harbour start iced. Beam thaw 240 s per hex
    (120 s with the Thermal Lance), heater 80 s (50 s with Heat Pumps) plus 22% (33%) on each neighbour.
    Heaters cost 90 x 1.32^n cubes (max 16), greenhouses 450 x 1.25^n (+25% growth inside).
  - Sunken City: 54 of 60 hexes start under water; each pump stage needs 80% of the next ring skimmed. Three
    stages (rings 2, 3, 4), each reveals streets with stranded junk for Scoopies and Lumi.
  - Cradle Returns: the 7-hex landing pad must be Sustained (level 4) and 70% of the district Growing (3+).
- **Pacing (estimate, not yet measured)**: with a late-game fleet (Mk III-IV, ~15 robots per district), an
  ordinary district took ~75 min to base 5 in the 2-hour autoplay pass. Scaling by junk volume and the extra
  mechanics, expect roughly 2.5-3.5 h per frontier to base 5 and 50% Growing, and 3-5 h for the Cradle pad
  and 70% Growing: about 12-16 h of long tail. The autoplay bot cannot fly rockets or place heaters yet, so
  these need a play-test; tune `pieces_mult`, `value_mult`, `cost_mult` and the storm/ice numbers first.

## Whole game and the garden ramp (wt/beat, Nov 7)

Owner's curve: one special seed at ~10-15 min (story), seeds scarce and growth slow while cleaning
drives progress until ~1 h, then "the garden takes off". The early part (first seed, the trickle) is
tuned by the first-seed helper; this section is the 1 h+ ramp and everything after it.

**The ramp (data):**
- New stats `plant_growth` and `seed_yield` (data/patch.json, base 1.0) multiply garden growth and
  seeds per bloom (plants/garden.gd). Research raises them: **Pollinator Survey** +75% growth / +60%
  seeds (the "takes off" node, 240 Data after Wild Mint), Hedgerows +25% growth, Evergreen Saplings
  +30% seeds.
- Seedling Blueprint 60 -> 160 Data, Drip Blueprint 100 -> 200 Data (now after Big Tanks), Pollinator
  Survey 160 -> 200, and all three need a level-3 base (`min_base_level`, research.json): planters and
  watering bots arrive around the hour mark instead of ~20-30 min, for any research order.
- Goal chain after "Plant 5 seeds": cleaning, bales, recycler, skimmer, hexes 20-30, base 3 carry
  minutes 15-60; the garden goals (Seedling, Drip, Pollinator Survey, 25/60/100 plants, Sustained,
  Thriving) follow as one run of rewards ("the garden takes off").
- Bloom Core: the 25% beat now lands with the garden ramp; 50% in the Dust Flats; 75% around the
  Sunken City / Cradle arrival; 100% is the Cradle finale (story/core_charge.gd `campaign_progress`:
  bases at 5, frontiers visited, frontier bases levelled and Growing, the Cradle pad and district).

**Walls removed:**
- Old Town stalled ~100 min at base 3-5 once its junk was gone: income fell to the 400 cubes/min
  stipend cap and research stopped (no Data source left). Now Sustained/Thriving pay 8/20 cubes/min
  (cap 900), Thriving hexes add 0.6 Data/min (wildlife notes, cap 30/min), base 4 costs 28k (was 35k).
- Research goals 20/24/26 moved after the rocket (Old Town's Data can't reach 20 nodes).
- Builder goals moved after the rocket (optional tinkering walled the chain for ~50 min).
- The 100-goal chain ended at "Clean 100 hexes": no goals for the whole late game. Now 144 goals:
  second district, each frontier (visit, storms, heaters/thaw, greenhouses, pumps, base levels,
  Growing), the Cradle (pad, district, Call the Cradle home) and the Seed Ark (1 and 3 waves). New goal
  types: research, bases_l5, frontier_base, frontier_growing (story/goals.gd).
- Rocket recharge used the wall clock: a 16x autoplay waited ~80 game-minutes per trip. The bot now
  drives `RocketTiers.now_override` from the game clock (players are unaffected; recharge is also
  clamped to one full cycle, so a clock change can't strand the rocket).

**Measured (autoplay, game time; see docs/WALKTHROUGH.md for the full step list):**
| Milestone | Before | After |
|---|---|---|
| Seed tin | 31 min | (first-seed helper) |
| Seedling robot | 32 min | 49 min (base 3 at 43) |
| Drip robot | 34 min | 63 min |
| Pollinator Survey ("takes off") | n/a | 70 min |
| Old Town base 5 / first launch | >200 min (stipend wall) | 74 min |
| Second district base 5 | | +78 min |
| Dust Flats / Frozen Port / Sunken City / Cradle | | 128 / 36 / 80 / 53 min |
| New Game to the Cradle finale | not reachable without dev hooks | ~7.5-8 h bot (~15-22 h human) |

## First hour (wt/first, Nov 7)

Owner direction: the first hour is cleaning, robots, upgrades and base levels; planting starts as a
story hook (one Maker seed, ~min 10-15) and stays a slow, scarce side track until the ~60-min ramp
(owned by the "beat" pass: plant_growth / seed_yield stats, Pollinator Survey, Seedling/Drip gates,
goals after `plant_5`, compost press yield).

Measured with `--fresh --autoplay --time-scale=4` (same seed; game minutes). The bot plays fast and
ignores the tutorial order, so a first-time player is roughly 2-3x slower on the first three marks.

| Milestone | Before | After | Target |
|---|---|---|---|
| First bale | 0.29 | 0.29 | < 1 |
| First sale | 0.36 | 0.36 | < 2 |
| First upgrade | 0.33 (before the first sale) | 0.36 (after the sale) | ~3 for a player |
| First hex clean | 1.3 | 1.3 | |
| First robot (Scoopie) | 6.0 | 4.7-6 (parts luck) | 6-8 |
| Seed tin found (first seed) | ~23 | ~12 | 10-15 |
| First hex Planted | 24.2 | 14-16 | (was 15-20) |
| Seeds in stock at 20 / 30 / 40 min | 0 / 109 / 296 | 11 / 29 / 60 | a trickle |
| Seeds at 60 min | 741 | 366 | ramp after 60 (beat) |

Goals keep completing every 1-4 min through ~33 min; after that the bot stalls on `builder_1` (it never
uses the Builder), which is a bot gap, not a game gap: a player sees "Fit a part in the Builder".

Data changes (early-game values only):
- `goals.json`: Scoop 15 pays 10 (was 15), first bale 10 (was 20), so the first upgrade needs the first
  sale (earn, then spend). "Find the seed tin" pays no seeds (was 5). `plant_5` (id kept for saves and
  the chain split) is now "Plant the Maker seed", target 1, +1 seed.
- `plants.json`: `first_seed` at 7 clean hexes (was 17) and gives 1 seed (was 15). Base meadow species
  grow at half speed (`grow_s` x2) and yield 60% of their seeds per bloom, so beat's growth/seed stats
  have room to make the garden take off. New `seed_finds`: 0.6% per scooped piece (x2.5 for paper),
  at most one per 60 s, only after the tin (`plants/seed_finds.gd`).
- `hex_levels.json`: Planted pays no seeds (was 2, it refunded the seeds that planted it), Growing 1 (3),
  Sustained 2 (5), Thriving 4 (8). **Flag for beat**: the last two also matter after 60 min.
- `lumi_level.json`: seeds every 3rd level, 2 + level/10 (was every 2nd, 4 + level/10). **Flag for beat.**
- `events.json`: event seed rewards about halved (Supply Drop 2-5, Rain 1-3, Wildlife 2-6). **Flag.**
- Code: the dormant compost press (before the first sprout) only heaps up 8 compost, so its first output
  is two seeds, not an hour of paper (`plants/composter.gd` DORMANT_CAP).
- Tried and reverted: Scoopie 1200-1350 (first robot ~8 min, but the second-Scoopie goal stalled 10 min).

## Cradle Mode (post-game prestige, wt/late)
- **Starseeds** (data/cradle.json `prestige`): 4 per Seed Ark wave, 6 per Bloom milestone,
  1.5 x sqrt(Thriving hexes over all districts), 20 for the Cradle, 3 per level-5 base. A finished
  campaign (4 milestones, 1-3 waves, ~600 Thriving hexes, 7 bases at 5) is ~95; every further wave is 4.
  A world only ever pays what it earned since it last banked (`claimed`).
- **Heirloom costs**: cost x growth^level (5-15 base, x1.45-2.0). ~95 Starseeds buys about 10-12
  cheap levels or 4-5 deep ones; maxing everything costs ~1,900, so the loop lasts many worlds.
- **Modifiers** are mild (x0.85-1.3 on one or two stats) and each world has two, one usually a gift.
- **Measured** (bot, game minutes after landing): with 12 Heirloom levels the first new world reached
  base 2/3/4 at 5.6 / 24.9 / 54.6 min, against 14.1 / 32.8 / 78.6 on the same world with none and
  18.5 / 39.0 / 62.4 on Verdance. An early Seed Vault that skipped the seed tin made the bot water by
  hand instead of cleaning (base 3 at 74.6 min); it now only adds seeds, and each world keeps its tin.
- **Garden charm**: +0.4% plant growth per charm point in that district, capped at +8% (charm 20;
  the fountain is 4, a bench 1.5, a path 0.2). Decorations refund in full when picked up.


## Three currencies (wt/money, Nov 7)

Owner: "mostly focus on fewer currencies ... keep it extremely low like 3 or less." The game now has
exactly three, defined in `data/currencies.json` (`core/currencies.gd`).

**Currencies, before -> after**

| Before (12) | After (3) | Rate (old -> new) | Where it went |
|---|---|---|---|
| Cubes | **Cubes** | 1 | unchanged: bales sold; pays upgrades, robots, base levels, research, rockets, decor |
| Data | Cubes | 1 Data = 10 cubes | research costs cubes x10 plus real time; the old Data sources ("field notes") pay the cubes |
| Bolts | **Parts** | 1 bolt = 5 parts | robot tiers (50/200/750 parts), Builder crafts, Haggle's stall, rocket Mk IV |
| Sheet metal / plastic stock / glass | Parts | 1 = 1 part | scooping metal/plastic/glass junk gives Parts; base levels, stations, outposts, rockets |
| Contract tokens | Parts (or unlocks) | 1 token = 5 parts | Requests pay cubes or parts; the token shop became the Requests reward track |
| Maker Fragments | Parts | 1 = 25 parts | Maker set crafts cost parts + a Vintage robot part |
| Trinkets (as a currency) | Cubes | 1 = 150 cubes | trinkets are only Collection finds; decor that cost trinkets needs Collection finds |
| Compost | Seeds (press hopper) | 4 compost = 1 seed | the press's hopper is a machine fill level; it makes seeds directly |
| Seeds | **Seeds** | 1 | unchanged |
| Starseeds (profile) | none | - | a restoration score that unlocks Heirloom milestones |
| Heirloom purchases | milestone unlocks | old prices as thresholds | cheapest first, round-robin by level |

Rates are the alias layer's and the save migration's (save v2), so an old save keeps everything it
earned: 45 Data -> 450 cubes, 10 bolts + 30 metal + 20 plastic + 5 glass -> 105 parts, and so on.

**Cost changes (data files)**
- Base levels (hub.json): L2 1.5k cubes + 150 parts (was 25 metal + 15 plastic), L3 12k + 350 parts
  (was 90 metal + 60 plastic + 30 glass), L4 28k + 140 parts, L5 30k + 110 parts. With one pooled
  currency the per-type gates vanished (base 2 and 3 waited on metal and glass); 150 and 350 parts
  arrive when those gates opened (~16 and ~31 min).
- Stations, outposts, rockets, signal jammers: the old material costs summed into Parts
  (bolts x5), e.g. Recycler 1.5k cubes + 45 parts, rocket Mk II 150k cubes + 1,050 parts.
- Research (research.json): x10 cubes per old Data for tiers 0-5 (Scoop Beam 250, Pollinator
  Survey 2k, Rocket Cargo 3.8k), x25 for the frontier tiers 6-7 (Dune Charts 15k, Ark Beacon 37.5k):
  late cubes are plentiful, and Data used to be the late gate. Field notes pay 10 cubes per old Data point (hex cleaned 100, restored 150, shard
  200, robot bale 10, bloom 15). Thriving wildlife notes: 6 cubes/min per hex, cap 300/min.
- Recycler: 10 parts x (0.5 + fill) per bale plus the bale's stock (was 2 bolts + stock).
- Hex levels: Sustained 250 cubes, Thriving 600 (Data folded in).
- Events and requests: bolts x5 -> parts; the Wildlife Visit's Data became more cubes.
- Requests: cube requests pay 90-180 s of income, part requests 30-130 parts.
- Lumi Level: every 5th level 5 + 5/10 levels Parts (was tokens).
- Eggs and Bloom milestones: trinket rewards became 150 cubes each.
- The compost press: unchanged rates (4 organic -> 1 seed per cycle), so the owner's planting curve
  holds: one Maker seed at ~13 min, a trickle until ~1 h, then the garden takes off.

**Milestones, before -> after** (autoplay, game minutes, `--fresh --autoplay --time-scale=16`, the
same staged campaign as WALKTHROUGH.md; the 4x first-hour run in brackets)

| Milestone | Before | After | Change |
|---|---|---|---|
| First upgrade | 0.7 | 0.6 | -8% |
| First hex clean | 2.1 | 4.6 | +119% |
| First robot (Scoopie) | 8.0 | 8.8 | +10% |
| First research started | 8.3 | 9.1 | +9% |
| Seed tin (the Maker seed) | 13.5 | 14.7 | +9% |
| First hex Planted | 16.0 | 17.5 | +9% |
| Base level 2 | 16.8 | 14.8 | -12% |
| First hex Sustained | 18.0 | 19.3 | +7% |
| First Skimmer | 30.6 | 27.1 | -11% |
| First hex Thriving | 23.9 | 34.9 | +46% |
| Base level 3 | 46.1 | 43.6 | -5% |
| First Seedling (garden robots) | 49.2 | 47.6 | -3% |
| First Drip | 57.9 | 64.0 | +11% |
| Base level 4 | 66.8 | 64.5 | -3% |
| Garden takes off (Pollinator Survey) | 65.9 | 72.0 | +9% |
| Old Town base 5 / first launch | 73.7 | 80.6 | +9% |
| Second district base 5 / launch | 161.0 | 149.0 | -7% |
| Arrive in the Dust Flats | 161.7 | 149.7 | -7% |
| Second district (launch to launch) | 87.3 | 68.4 | -22% |
| Seeds in stock at 20 / 30 / 40 / 60 min | 8 / 79 / 139 / 227 | 0 / 35 / 126 / 130 | a trickle to ~1 h |

Before = the branch before this pass; after = the final data. The 16x "before" run was cut short at
185 min by the shared box's OOM killer, so the comparison stops at the first frontier (the 4x
first-hour "before" run crashed in the engine at 43 min and is not used). Single-run noise at 16x is
large: "first hex clean" ranged 2.3-4.8 min across five after-runs with near-identical data, and
"first Thriving" is one hex's garden luck. Everything on the critical path is within about 10%;
the second district is ~20% quicker (cubes fund research there now, where Data used to run dry).

Tuning runs (16x, same seed): pooling the materials first made base 2 and 3 come ~8-10 min early
(the metal and glass gates vanished) and the second district took 26 min instead of 87 (a bot
arriving rich, research no longer Data-starved). Fixed with base 2/3 parts costs (150 / 350), a
research reserve in the bot, and x25 cubes for the frontier research tiers; x15/x20 for tiers 4-5
was tried and reverted (Old Town launch slipped to 93 min).

**Notes**
- The bot treats field-note cubes as its research fund (`AutoplayBot._research_ok`), like a player
  who spends what used to be Data on research; it also researches when it is rich.
- Parts pile up after the first district (the recycler and requests keep paying); the late sinks are
  rocket stages (Mk III 3,300, Mk IV 10,000 parts), robot tiers and the Builder.

## Remote progress and the Telescope (wt/scope, Nov 7)
Robots on the other worlds of a Cradle Mode profile keep working while Lumi is elsewhere. One function
does the maths for both: `Offline.compute` (core/offline.gd). `RemoteProgress.compute` (systems/remote_progress.gd)
calls it and scales the result; nothing is duplicated.
- **Rate:** `remote_factor` 0.5 of the offline rate (data/telescope.json), and offline is already 0.5 of the
  online scoop rate, so a remote crew works at **25%** of what it does with Lumi there. Scrubbers pay nothing
  from afar.
- **Caps:** the offline 8 h cap (`Offline.CAP_S`) per absence, and the junk left in that district
  (junk hexes x 337 units, the measured mean, minus `offline_units` already paid). A clean district pays nothing.
- **When it pays:** on arrival by world travel (`CradleMode.switch_world` loads the world in memory, so the
  slice skips its own offline payout; `Telescope` calls `RemoteProgress.on_district_ready`). The window starts
  at that world's last save, i.e. when Lumi left it; under 120 s pays nothing. A cold start onto a world gets
  the normal offline payout instead, and rocket travel inside one world gets neither, so time is never paid
  twice. The units paid are added to `offline_units`, so the same junk can't pay again (the same rule as offline).
  If the extras idle-gains work lands, it should also call `Offline.compute`; remote progress only covers
  worlds other than the current one, so the two never overlap.
- **What the telescope shows** is the same number live (`RemoteProgress.pending`): the district % and
  "waiting for you" cubes tick up at the remote rate; piles shrink and hexes turn clean nearest the base first.
  Estimates use the current world's upgrades; the payout on arrival uses the visited world's own.
- **Size of it:** a Mk I Scoopie earns about 0.05 cubes/s remotely (~180 cubes/h, with a hauler in the crew).
  A full 8 h away banks what that crew makes in about 2 h with Lumi there, and never more junk than the
  district has left.
- **Care package:** 400 cubes spent here, 5 min of double speed for the watched world's crew, one at a time
  per world. Its extra payout is capped at 75% of its cost (`care.extra_cap`), so it can never turn cubes
  here into more cubes there. It is a nudge you can watch, not an income source.
- **Telescope unlock:** base level 4, or the Observatory Optics research (Robotics tier 6, 500 Data). Cost
  6000 cubes + 40 parts (bolts until the money rework adds a parts currency). Tests: `tests/test_remote_progress.gd`.
