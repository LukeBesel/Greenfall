# Balance

> **Read first.** Every time below is **bot time**: the autoplay bot (`tools/autoplay.gd`) playing at
> `--time-scale=8`. A person is assumed to take **about twice as long** (reading, looking around,
> getting lost, choosing). That factor is a guess, **not measured** with a real player. If the first
> planet plays too fast or too slow, change **one number**, `data/hub.json` `far_hub.pace`
> (2.0 now): every sale pays 1/pace, so 1.25 makes every cube step about 25% longer and 0.8 about
> 20% shorter. Verdance can also get its own value in `data/homeward.json` `planets[0].far_hub.pace`.

## Verdance, the round planet (v6pace)

Owner's goal (items 57, 58, 61, 63, 64 and the "addictive" brief): about 4-5 hours to the point
where Lumi can fly on, six bases woken by then, roughly 20% of the planet cleaned (not 100%),
cubes growing semi-exponentially (tens to hundreds of thousands of cubes for the big buys), always
one clear next step, something new every 3-6 minutes in the first hour and every 6-10 minutes later,
never more than about 12 minutes without one, no pure-grind wait over about 15 minutes.
In bot time that is the leave point at about **2-2.5 h**.

### The arc

The card (story steps from `data/objectives.json`, then `data/goals.json` in file order) walks
through it; every hub, wake and rocket step shows its price and the cubes saved so far.

1. Start yard: trash bin, chest and scoop upgrades, the Baler, the signal tower, Glim, the first
   hexes, the Bot Bay, the first robot (it cleans on its own: no zone step since v8bot), the first seed.
2. The rocket stands on the pad after the first seed (`data/hub.json` `rocket.after_objective`).
3. Hub 2 Garden Row (600), base level 2, hub 3 Gantry Works (2.4K), then a Haul Bug. Each far
   station first asks for 4 of its hexes cleaned (Gantry Works also an outpost), then the wake.
4. Rocket Mk II (8K) reaches 5 hubs; base level 3 (9K) sits in the gap before hub 4 Signal Heights (9.6K).
5. Goals from `data/goals.json`: a Seedling, base level 4 (60K), hub 5 Fairground (38K), 25 plants,
   rocket Mk III (100K), a Drip, base level 5 (150K), hub 6 Stack Works (200K, `cost_override` "4"),
   the Mk V drive (500K), fly on. Base 4 and 5 sit inside the two longest saves so each is split by
   a real income buy.

Each woken far hub multiplies every sale by `sell_growth` (3.5): x3.5, x12, x43, x150, x525.
Prices grow by `cost_growth` (4.0) a hub. Income grows faster than that early (more robots, base
levels) and slower late, which is where the rocket tiers and the drive take over as the big numbers.

### Away cleaning and the planet %

A woken far base keeps cleaning its own region while Lumi is at another hub
(`planet/sites/base_keepers.gd`, `data/hub.json` `far_hub.keep`):
cells per minute = `cells_per_min` (4) + `per_level` (1) x (base level - 1) + `per_robot` (0.5) x
robots left there. Cells go centre-first, so on the next visit the town is visibly cleaner and the
arrival line says how much. The planet % on the HUD counts the land of every hub region (the ten
towns' regions, about 8,000 land cells on Verdance: `far_hub.pct_over` "all_regions"), so it only
ever goes up; the whole-globe share (open land between towns, the far hinterland) stays in
`SphereCells.clean_fraction()` for a later "100%" extra. `--keep-report` prints a `[keep]` line a
game minute.

### Measured (2026-11-12, v8fix pass, seed 4471, `--time-scale=8`, pace 1.9)

Changes since the release-check pass: base level 5 costs 150K (was 250K, the only card save over
15 minutes); item 75 (first robot too late): the Bot Bay costs 250 cubes (was 900) and opens after
2 clean hexes (was 3), the first Scoopie costs 150 cubes (was 600), "Clean 3 hexes" comes after
the first robot; no junk heaps or wrecks inside outpost ruins (the Gantry Works bot trap). With
those at pace 1.45 the leave point fell to **96 bot min** (14.6% clean: base 5's 20-minute save
was gone and the garden took off earlier), so `far_hub.pace` went 1.45 -> 1.9. Numbers below are
the pace 1.9 run; the bot logged no trap in either run.

| Bot min | ~Person (x2) | What | Sales x | Base | Planet % |
|---|---|---|---|---|---|
| 14.9 | 0:30 | Bot Bay (250 cubes; the card waits on the 2nd clean hex, 8.6 min) | 0.5 | 1 | 0 |
| 15.1 | 0:30 | first robot (Scoopie, 150) | 0.5 | 1 | 0 |
| 20.9 | 0:42 | first hop (the first seed is planted before it) | 0.5 | 1 | 0.1 |
| 29.5 | 0:59 | **base 2** Garden Row woken (chain: 4 hexes, 8.0 min) | 1.8 | 1 | 0.2 |
| 43.0 | 1:26 | **base 3** Gantry Works woken (4 hexes + an outpost, 11.5 min) | 6.4 | 2 | 1.4 |
| 43.8 | 1:28 | Haul Bug, base level 3 | 6.4 | 3 | 1.4 |
| 46.2 | 1:32 | rocket Mk II (8K) | 6.4 | 3 | 1.8 |
| 65.8 | 2:12 | **base 4** Signal Heights woken (8.0 min) | 23 | 3 | 4.8 |
| 73.9 | 2:28 | base level 4 (60K) | 23 | 4 | 6.5 |
| 85.4 | 2:51 | **base 5** Fairground woken (3.5 min) | 79 | 4 | 9.3 |
| 89.9 | 3:00 | rocket Mk III (100K) | 79 | 4 | 10.6 |
| 101.7 | 3:23 | base level 5 (150K, an 11.8 min save) | 79 | 5 | 14.3 |
| 116.5 | 3:53 | **base 6** Stack Works woken (2.1 min) | 276 | 5 | 20.5 |
| 117.5 | 3:55 | Mk V drive (500K), **leave point** (opens on the six stations only) | 276 | 5 | **21.0** |

(Sales x: every sale's multiplier, `sell_growth`^woken / `pace`. Planet %: the HUD's number,
every hub region's land; the keepers cleared 1,417 cells by the end, woken towns 30-70% clean.)

**Cubes per minute** between wakes: 273, 1.7K (x6.1), 4.0K (x2.4), 6.6K (x1.6), 44K (x6.6).

**Reward cadence** (`tools/cadence.py`): 88 new moments in 120 minutes, mean gap 1.4 min. Over
target: 11.5 min at 31.5-43.0 (Gantry Works' chain), 8.6 min at 6.3-14.9 (the 2nd clean hex),
8.0 min at 21.5-29.5 (Garden Row's chain). Nothing over 12 minutes.

**Card waits:** none over 15 minutes. Longest: hub 6's flight 12.7 (200K), Gantry Works' wake 12.2
(its chain), base level 5 11.8, hub 4's flight 11.6.

**First robot (item 75), follow-up (short runs to the first robot only, pace 2.0):** the Bot Bay
now opens after the first clean hex (450 cubes), the first Scoopie costs 250, and "Clean 2 hexes"
and "Clean 3 hexes" come after the robot (the robot helps). First Scoopie at **15.3, 8.7 and 15.4**
bot min on seeds 4471, 1234 and 9001 (mean 13.1). The spread comes from cash, not from the
prices' size: cleaning the first hex pays a burst of bales (300-700 cubes, depending on the seed),
and once the bot holds about 250 cubes it buys cheaper upgrades on the way, so a price just
above what the burst covers waits much longer. Tried on the same seeds: Bot Bay 350 + Scoopie
150: 7.1, 8.3, 13.8; 350 + 250: 6.4, 10.3, 15.0; 350 + 300: 18.7, 19.8, 16.8; 550 + 200: 19.0,
22.2, 10.5. The earlier gate (2 clean hexes, pace 1.45) gave 13.6-15.4 with a 3.5-8.6 min second
hex. The table above is the pace 1.9 run with that earlier gate; **pace 2.0 (set with this change)
and the new first-robot step are not measured over the whole arc** (a few minutes later leave
point expected).

**Station chains** (O6): 2.1-11.5 bot minutes each. The outpost trap (bot boxed in at
-239.6, 1108.5, -1459.9 by Gantry Works' outpost 0) was a junk mound rolled under the ruin; 33 of
37 outposts on Verdance had a heap or a wreck inside the ruin. Outposts now clear both
(`automation/outposts.gd` `_clear_heaps`), and `--target-reach` checks it.

**Run to run:** the leave point measured 118 min at pace 1.3 and 131 at 1.45 with the earlier
data, 96 at 1.45 and 117.5 at 1.9 with this pass's. Earlier passes are in git history.

### Measuring a planet's arc

    flock /tmp/gf-autoplay.lock godot --headless --path . -- --fresh --orbit --no-intro --autoplay \
        --time-scale=8 --clarity-log --keep-report --quit-after=7000 > run.log 2>&1
    python3 tools/cadence.py screenshots/autoplay_report.json run.log

`cadence.py` prints the arc (each hub woken, rocket tier, drive, exit), cubes per minute between
hubs and the factor from one to the next, the gaps between "something new" moments (an upgrade
level, a robot, research done, a machine or station, a base level, a hub, a rocket tier, a story
step) against the targets, and the longest card waits (`*` = a price on the card; `WALL` = a priced
step up longer than 15 minutes). On this shared 4-core box 8x runs at 2-4x real time: a full
Verdance arc takes 40-70 minutes of wall time.

### Retuning for another planet

Everything below is per planet: put the key in `data/homeward.json` `planets[k].far_hub` (it is
merged over `data/hub.json` `far_hub` by `Hub.far_cfg()`); hub order, gifts and rocket pieces are
in `data/planets.json` (v6hubs), the leave gate in `data/homeward.json` `planets[k].leave`.

| Knob | Verdance | What it does |
|---|---|---|
| `far_hub.pace` | 2.0 | Whole-planet speed: every sale pays 1/pace. Start here after a playtest. |
| `far_hub.cost_base`, `cost_growth` | 600 x 4.0 | The hub price ladder (600, 2.4K, 9.6K, 38K; hub 6 200K by override). A bigger planet: raise `cost_base` so its numbers start where the last planet ended. |
| `far_hub.cost_override` | hub 6: 200K | One rung of the ladder, by step number. |
| `far_hub.sell_growth` | 3.5 | Income multiplier per woken hub. Keep it below `cost_growth`, or later hubs come faster and faster. |
| `far_hub.keep` | 4 + 1/level + 0.5/robot cells a minute | How fast woken bases clean while Lumi is away: the main lever on the % at leave. |
| `far_hub.pct_over` | all_regions | What the HUD's planet % counts. |
| `leave.hubs`, `leave.hub_level` (homeward) | 6 at level 2 | When the drive and the star map open. |
| `drive[k].cost` (homeward) | 500K | The planet's last and biggest buy. |
| `data/rockets.json` `tiers[].hubs`, `.cost` | Mk I 3, Mk II 5 (8K), Mk III all (100K) | How many hubs each rocket reaches, so the rocket is upgraded along the arc. Global, not per planet. |
| `data/objectives.json`, `data/goals.json` | | Step order. Hub, wake and rocket steps carry no `desc`: their why is `data/story_reasons.json`. |

Order of work for a new planet: set the leave gate and the drive price, run the bot once with
`--keep-report`, then move `pace` until the leave point lands where you want it, `cost_growth` /
`sell_growth` until no step is a wall (cadence.py), and `keep` until the % at leave feels right.
`tests/test_v6pace.gd` pins Verdance's numbers and checks that every step on the card can be done
on the globe (a known stat or flag writer, no flat-world-only system).

## Earlier notes (before v6, mostly the flat world)

Everything below predates the round planet's arc above: the flat Old Town (33 hexes), the frontier
districts and the older whole-game passes. Kept for their methods and formulas; where a number
disagrees with the section above, the section above is current.

How Greenfall's first district (Old Town, 33 junk hexes: 27 land + 6 lake) is paced, how it was
measured, and what was tuned. All numbers are game time (the sim clock, `GameState.stats.time_played`).

### Measuring: the autoplay bot

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
- **Command** (only with `--autoplay-zones` since v8bot; the game no longer asks for zones): paints the clean crew's zone on the nearest unfinished hexes (frontier), the water and plant
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

### Targets

- A next goal within ~1-3 min, no dead stretch > 3 min, through the first ~2 hours.
- First robot ~6-10 min; first planting ~20-25 min; first Sustained hex by ~45 min; base level 3 by ~75 min.
- Research always has something to start; late costs don't explode; no softlocks, no money loops.

### Results (before -> after)

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


### What the "before" run showed

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

### Data changes

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

### Exploits found and fixed

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

### Lumi Level (Lumi XP)

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

### Formulas (current)

- Upgrade cost: `base_cost * growth^level` (data/upgrades.json; robots' fleet upgrades in robots.json).
- Robot build cost: `cost * 1.35^(robots of that type)` (fleet.gd); Mk tiers: `cost * cost_mult` + a core
  of the tier's rarity + 10/40/150 bolts.
- Crew cap per role: `crew_cap.base + crew_cap.per_level * hub level`.
- Hex clean bonus: `bonus_base + bonus_per_volume * hex volume` (planet.json), once per hex.
- Garden stipend: `sum over hexes of the cubes_per_min of every level reached` (capped), paid every sample.
- Bale value: `sum(volume * junk value) * cube_value_mult * (2 if pure) * (1.5 if perfect) * (0.8 if lumpy)`
  then `* (1 + hub sell_mult)` at the scale.

### Notes and open issues

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

### Frontier districts (late game, wt/biomes)

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

### Whole game and the garden ramp (wt/beat, Nov 7)

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

### First hour (wt/first, Nov 7)

Owner direction: the first hour is cleaning, robots, upgrades and base levels; planting starts as a
story hook (one Settler seed, ~min 10-15) and stays a slow, scarce side track until the ~60-min ramp
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
  the chain split) is now "Plant the Settler seed", target 1, +1 seed.
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

### Cradle Mode (post-game prestige, wt/late)
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


### Homeward pacing (wt/home, Nov 7)
Owner target: the whole campaign 25-40 h for a human, every planet shorter than Verdance with its own twist.
- Verdance to "The Cradle Answers": ~15-22 h human (unchanged, see above).
- The four planets start from the Heirloom kit and the carried rocket tier (warp hops from the start) and
  have smaller restoration targets (data/homeward.json): Ochre 110 Thriving + 1 base 5 (~2-2.5 h),
  Tidewell 140 + 2 (~2.5-3 h), Rime 160 + 2 with Long Nights and Thin Soil (~3-3.5 h), Anvil 200 + 3
  with Heavy Junk (~3.5-4.5 h): ~11-13.5 h, so ~27-36 h in all. *(assumption: scaled from the new-world
  opening measured in wt/late, base 4 at ~55-80 game min; not measured end to end yet)*
- Drive costs: Mk V 2.5M cubes + 300 parts is paid on Verdance late game (a Cradle-era stipend covers it in
  well under an hour); Mk VI 1.2M + 500 parts on Ochre or Tidewell, around their base 5; Mk VII 8M + 2,000
  parts back on Verdance after the system is restored (the Seed Ark gifts and four planets of stipends).
- Each restored planet: a relic and one Heirloom pick (four picks over the campaign, so later planets speed up).
### Three currencies (wt/money, Nov 7)

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
| Settler Fragments | Parts | 1 = 25 parts | Settler set crafts cost parts + a Vintage robot part |
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
  holds: one Settler seed at ~13 min, a trickle until ~1 h, then the garden takes off.

**Milestones, before -> after** (autoplay, game minutes, `--fresh --autoplay --time-scale=16`, the
same staged campaign as WALKTHROUGH.md; the 4x first-hour run in brackets)

| Milestone | Before | After | Change |
|---|---|---|---|
| First upgrade | 0.7 | 0.6 | -8% |
| First hex clean | 2.1 | 4.6 | +119% |
| First robot (Scoopie) | 8.0 | 8.8 | +10% |
| First research started | 8.3 | 9.1 | +9% |
| Seed tin (the Settler seed) | 13.5 | 14.7 | +9% |
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

### Remote progress and the Telescope (wt/scope, Nov 7)
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

### Slow start (wt/pace, Nov 8)
Owner playtest #2: the start was far too fast and strong (4 upgrades after two bales, auto-cubing
and robots within minutes). Lumi now starts small and earns his tools (core/pace.gd).

Start: chest 12 (was 30), scoop 3 pieces/s (was 8), 1 piece per pulse, small junk only, no bale
press. Before the Baler the chest is emptied loose into the trash bin (camp's TrashBin.deposit,
else the scale pad) for 1.0 x junk value (no Pure/Perfect/sell bonuses). Lumi Level cube rewards
were the hidden early flood (+85 at level 2): cap_cubes_base 30 -> 8, floor 15 -> 5 per level.

| Upgrade | Cost | Notes |
|---|---|---|
| Baler | 100 | unlocks bales (stat baler_unlocked) |
| Lift Strength | 50, 500 | Lv1 medium (jerrycans, crates), Lv2 large (tyres, TVs, fridges); stat lift_class |
| Scoop Size (multi_lock) | 70 x2.4, max 4 | +1 piece per pulse, no longer gated |
| Compartment Size | 45 x1.55 | +5 chest |
| Scoop Speed | 45 x1.6 | +40 % per level |
| Carry Stack / Compactor Pressure | 120 / 150 | need the Baler |
| Signal Finder | 400 | needs Detector Coil 1; Rare Part Signal (violet beam) event only after it |
| Magnet Arm | 1500 x1.9 | Scoop Width 3 + Lift 2 + base 2; pulls 2 + 1/level loose surface pieces, never heaps or heavy ones |
| Auto Compactor | 2500 | Auto-Baler research + Compartment 6 |

Research: Salvage Logic (1000, base 2) unlocks Scoopie / Haul Bug / Skimmer; Conveyor (3000),
Auto-Baler (4500) and Recycler need base 2. Upgrades take `requires_research` / `min_base_level`.
Events take `requires.flag` (Pace.sync_flags: has_baler, has_lift_medium, has_lift_large,
has_signal_finder) and `enabled`; bale requests need has_baler. Supply Drop and the Ledger's seed
drops are off (no spontaneous reward crates). Old saves (v < 3) get Baler, Lift 2 and
data/patch.json old_save_grant (Compartment +4, Scoop Speed +5).

Autoplay, game minutes at --time-scale=4 (Old Town; before = 5db7ed8):

| Milestone | Before | After | Target |
|---|---|---|---|
| First upgrade | 0.3 | 1.3 | 1.5-3 |
| Upgrades bought by the 2nd bale | 1 (5 by 0.7 min) | 4-8 incl. Baler + Lift 1 (0-1 affordable, purse 28-84) (0 affordable then) | ~1 after two bales |
| Baler / first bale | (no Baler) 0.3 | 3.5-4.9 / 3.6-5.0 | 4-6 |
| Large lift | (always) | 9.3-9.8 (Lift 2 now 500, was 400 in these runs) | 10-15 |
| First hex | 1.3 | 5.7-6.8 | |
| First seed (seed tin) | 13.0 | 16.1-21.2 | 18-22 |
| Base 2 | 18.0 | 25.6-31.1 | |
| First robot | 6.3 | 37.2 (Salvage Logic 2500) | 35-45 |
| Conveyor / Auto-Baler station | 32.0 / 35.2 | Conveyor research starts 42-50, station after | 35-45+ |

Run-to-run spread is about a minute early on. Without world2's HexField.piece_size the start ring
can still hold large models; Pace counts those as medium so the first hexes can be cleaned.
### World2: the district reads covered (wt/world2, Nov 7)

Owner: "the only clear areas should be what you or bots pick up." Junk gen 2 (new games; saves without
`junk_gen` keep gen 1 and radius 3): Old Town's field is radius 4 (55 junk hexes, was 33), no mid-road
sparsity, a full ring around the base, 40% of landfill junk between the heaps, and the streets of
building-blocked hexes plus the hub hex outside the yard belong to the nearest junk hex. Every hex keeps
gen 1's junk volume: pieces are smaller (`vol_scale`), and one pickup (Lumi's beam or a robot's scoop)
takes the nearby little cluster along (`HexField.hex_cluster`, ~1/vol_scale pieces), so bales, cubes and
hex flips pace as before. Past the field, `planet/far_junk.gd` lays static junk and paper to 125 m.

Generation (seed 4471): 13.2k pieces / 13.3k volume (radius 3, gen 1) -> 25.7k pieces / 21.9k volume
(radius 4, gen 2). Coverage (a piece within 1 m of open ground, `tests/test_junk_coverage.gd`): roads
56% -> 92%, the ring around the base 38-59% -> 86-90%, nothing bare (> 3 m from junk).

First-30-min autoplay (`--fresh --autoplay --time-scale=8 --quit-after=300`, game minutes, before ->
after; the after bot first detoured to dig a buried part, hence the late first bale):

| Milestone | Before | After |
|---|---|---|
| First bale / sale / upgrade | 0.3 / 0.4 / 0.4 | 1.3 / 1.6 / 1.4 |
| First hex clean | 1.1 | 2.8 |
| First research done | 5.3 | 5.8 |
| First robot (Scoopie) | 6.4 | 6.0 |
| First Haul Bug | 6.9 | 6.0 |
| Seed tin | 13.9 | 11.4 |
| Base level 2 | 13.0 | 16.9 |
| First hex Sustained (lv 4) | 18.2 | 16.5 |
| First hex Thriving (lv 5) | 25.1 | 24.9 |
| First Skimmer | 25.2 | 15.6 |
| At ~36 min: hexes clean / goals / earned | 22 / 49 / 42.5k (38 min) | 21 / 48 / 38.6k |

Without the cluster pickup (volume kept, more pickups) the same run was 15-35% slower (base 2 at 18,
first Thriving at 34.5); with gen-2 counts but no volume scaling the economy would run ahead instead.
Solid props add bot "stuck escapes" (6 -> 31 in the run; the bot steers straight): no robot got stuck.

Playtest #2 run (heaps now solid for Lumi and robots, `--save-dir` isolated): first robot 8.6, base 2
16.6, first Thriving 32.2, 15 hexes / 44 goals / 29.8k earned at 34.7 min. Scooping heaps from the edge
costs time on landfill hexes; the "pace" helper is re-pacing the start anyway (slower by design).
Single autoplay runs vary a lot (part luck, the bot digging first); compare several before tuning.

Render cost at the start view (lavapipe, `--perf`, primitives / draw calls): Low 9.71M / 1848 (gen 1)
-> 6.02M / 1739 (gen 2, after the Low budget: tiny litter items at 24 tris and 14% of the carpet,
half the far layer in one batch per model); High 20.6M -> 27.4M before the far-layer cut (estimator
after it: 15.4M -> 19.9M, Medium 12.5M -> 16.8M).

### Whole-game curve and return trips (wt/pace2, Nov 8)
Owner targets: the whole game about 20 h for a typical player, grindy but never boring; Verdance
(New Game to the first launch to another planet) 3-4 h; planting ramps at 1-2 h (garden takes off
75-110 min); something new every 5-10 min early and 10-20 min later; no goal-less stretch over
10-15 min. You can leave a planet at about 50%; 100% needs tools from later planets.

**Bot-to-human factor: about 2x.** The autoplay bot never reads, never explores and shops
instantly, but it now loses time to props and heaps (world2 colliders) and plays the slow start
the same as a person. So bot targets are half the human ones:

| Stretch | Human target | Bot target | Bot measured (pace2 run 4, 16x) |
|---|---|---|---|
| Baler / first bale | 5-10 min | 3-5 | 9.5 |
| Base 2 | 40-60 min | 20-30 | 27.5 |
| First robot | 60-90 min | 35-45 | 46.8 (Salvage Logic 2500; now 1800) |
| Base 3 | 2.5-3 h | 75-100 | 102.1 |
| Garden takes off (Pollinator Survey) | 2.5-3.5 h | 75-110 | 106.0 (was 163) |
| Base 4 | 4.5-5.5 h | 150-170 | 168.3 (was 164) |
| Verdance system opens (Mk V: 50% or a level 3 base) | 3-4 h | 1.5-2 h | gate at base 3 = 102; Mk V (60k) est. 130-140, to measure |
| Each later planet to its chart (50%) | 3-4 h | 1.5-2 h | not measured yet |
| Return trips (Verdance 68% -> 100%, each planet's cap) + Homeward | 3-4 h | 1.5-2 h | not measured yet |
| Whole game | ~20 h | ~10 h | not measured yet |

Before (main after the pace merge, coordinator's run): base 2 31, first robot 40, base 3 81,
garden 163, base 4 164, base 5 / launch 246 min. The garden fix was the bot hoarding 1.5x the next
base's cost before researching (Pollinator Survey 2000 waited 80 min with 17k cubes in hand); the
bot now keeps half the next base and works an on-screen goal's research first.

**Return trips (data/homeward.json `tech`, planets' `needs_tech`, research `requires_tech`).**
A planet's restoration (Homeward's planet-% value, whatever it counts: hub regions on round
planets) is capped until the listed tech is found; each tech is found when its planet reaches
25%. Every cap is above the chart (50%), so you can always move on.

| Planet | Found there (at 25%) | Where it is needed |
|---|---|---|
| Verdance | (start) | Its own cap: 68% without the Deep Drill, 80% without the Tide Pump, 90% without the Heat Core, 97% without the Cryo Beacon |
| Ochre | Deep Drill | Verdance's buried landfill: Dune Charts research, so the Dust Flats; caps Ochre at 75% without the Tide Pump, 90% without the Heat Core |
| Tidewell | Tide Pump | Verdance's flooded streets: Pump Works, so the Sunken City; Ochre's last quarter; caps Tidewell at 75% without the Cryo Beacon, 90% without the Heat Core |
| Rime | Cryo Beacon | Verdance's Ark Beacon (the Cradle Returns and the finale); Tidewell's last quarter; Rime itself caps at 80% without the Heat Core |
| Anvil | Heat Core | Verdance's Thermal Lance, so the Frozen Port's ice; the last 10% of Ochre, Tidewell and Rime |

Drives open from partial progress: Mk V (60k cubes, was 2.5M) needs Verdance at 50% or a base at level 3 (data `or_base_level`: the core only passes 25% around base 3 now that the frontiers wait for later-planet tech); Mk VI needs
another planet at 50%; only Mk VII Homeward keeps the whole system at 100% plus all relics. Relics
and 100% stay completion rewards. The Bloom Core follows Verdance's cap, so the 75% ark-star beat
and the Cradle finale come on a return trip; the system map, the late menu's planet switch and the
Ark Bridge open with `Homeward.system_open()` (the Cradle's answer, a built Mk V, or the Mk V gate).

The campaign bot (tools/autoplay_home.gd) works a planet until it reaches its current cap, or
plateaus past its chart for 30 min, then goes to the first planet that can still improve: forward
while there are new planets, back once new tech raises an earlier cap.

Levers for round planets: everything above is data (caps, `at`, drive gates and costs), read through
Homeward.stored_pct, so a new planet-% definition keeps the same gates.

Measured run 4 (pace2, 16x; before the Mk V `or_base_level` gate, so the bot stayed on Verdance):
base 5 177 min (was 246), second district base 5 208; Bloom Core 25% at 105 min and still under
50% at 222 min. Goal-less stretches over 15 min: 29.5-46.8 (saving for Salvage Logic; now 1800
cubes) and 102-143 (the bot did not research the Seedling Blueprint; it now researches what an
on-screen goal needs). A 16x run manages only about 2x real time here, so later planets need staged
runs (`--save-dir=campaign_pace2` without `--fresh`).

Also fixed on the way (bot pacing was skewed): the bare Old Town yard hid the lean-to but kept its
front posts solid (invisible walls where Lumi stuck for minutes; camp now turns collision off with
the hidden parts); the bot sidesteps obstacles, and when boxed in for 90 s hops back to the yard and
logs `[bot-trap]`; `--time-scale` above 4 raises the physics tick rate so steps stay as short as 4x.

### Cross-planet pacing (orbC, Nov 8)
Owner: later planets are bigger (up to 4x Verdance's area on Anvil) but each must play faster, never
slower: the tools, bots and drive upgrades from each planet speed the work up. Whole game ~20 h,
Verdance 3-4 h, something new every 5-20 min. Bot-to-human factor about 2x (see above), so a later
planet's "can leave" point (50%) should come in about 1.5-2 h of bot time, and never after Verdance's.

**Method.** The flat autoplay bot (tools/autoplay.gd), one stage per planet, headless at 16x:
`--fresh --save-dir=pace_<id> --planet-start=<id> --heirlooms=<picks> --autoplay --time-scale=16
--quit-at-pct=50` (scratchpad/orbc/pace.sh). `--planet-start` (systems/cradle_mode.gd) lands on a
campaign planet the way rocket travel does (new world state, carried flags, rocket tier).
`--quit-at-pct=N` saves and stops when Homeward.measure_current() reaches N%; the log carries
`planet`/`pct` per minute and the milestones file `pct25/50/75_<id>_s`. Assumed Heirloom picks, one
per planet before (the restoration reward): Ochre Old Crew 1; Tidewell Old Crew 2 + Head Start 1;
Rime + Quick Beam 1; Anvil + Archivist 1. The flat game stands in for the round planets (autoplay
does not play the globe yet): a planet's size there is its Thriving target (110 / 140 / 160 / 200
Thriving hexes and 1 / 2 / 2 / 3 bases at level 5, so more districts to restore).

**Levers (data).**
- `data/homeward.json` planets[k].`arrival` (new, Homeward.apply_arrival on landing): what the crew
  brings from the planets before: research tier (every research below it granted: blueprints, beam,
  stations), a starting crew on top of the Heirloom kit, robot Mk tiers, cubes, parts, seeds.

| Planet | research tier | crew | robot Mk (index) | cubes / parts / seeds |
|---|---|---|---|---|
| Ochre | 3 | 2 Scoopie, Haul Bug, Seedling | - | 4k / 400 / - |
| Tidewell | 3 | 2 Scoopie, Haul Bug, Seedling, Drip | Scoopie II | 5k / 500 / - |
| Rime | 4 | 2 Scoopie, Haul Bug, 2 Seedling, 2 Drip | Scoopie, Haul Bug, Seedling II; Drip III | 10k / 1k / 80 |
| Anvil | 5 | 3 Scoopie, Haul Bug, 3 Seedling, 2 Drip, Multibot | Scoopie, Haul Bug III; Seedling, Drip IV | 15k / 1.5k / 150 |

- The Bot Fabricator (data/fabricator.json, from Tidewell on): 8k cubes + 300 parts, robots at 0.35x
  their price (a Scoopie 385 cubes + 25 parts) with no growth, 30 s each, fleet cap 0.6 per 1,000
  hexes on a globe (Verdance 98, Ochre 71, Tidewell 165, Rime 252, Anvil 393), 3x the crew cap on a
  flat district. It was 30k + 900 and robots 0.6x: on Tidewell that landed at about 2-2.5 h, near
  the planet's end.
- The bot (tools/autoplay.gd): builds the Fabricator as soon as it is offered and paid for (robot
  builds wait, the upgrade loop saves for it), keeps one robot's cubes in reserve while the line runs
  below its cap, and sets a mix of cleaners and haulers plus planters and waterers once researched
  (more Seedlings when seeds pile up). `_fabricator_mix`.

**Measured (bot game minutes to the planet's 50%).**

| Planet | before (no arrival kit) | v1 kit | final | 25% | base 5 | Fabricator | goal gaps over 20 min |
|---|---|---|---|---|---|---|---|
| Verdance (fresh) | 50% at 433; leave point base 3 at 114 (Mk V gate) | - | - | 120 | 162 | - | none (max 15.2) |
| Ochre | 25% not reached at 155 | 143 | 122 | 80 | 118 | (not unlocked) | none |
| Tidewell | Fabricator never bought in 92 min | 119.5 | 119.5 | 84 | 112 | 29 | none (max 5.2) |
| Rime | - | 146 (v1) | ~145 (139 / 151, 3 runs) | 75 | 100-106 | 5 | 20.0 max (one, at the edge) |
| Anvil | - | 227 | 140 (v2 kit 152) | 70 | 76 | 4 | none |

Goals came every 2.5-4 min on every planet; no goal-less stretch over 20 min anywhere (the longest
20.0 min, once, on Rime). Run-to-run spread is large (Anvil's 25% came at 75 and at 139 min with the same
data), so treat single numbers as +-20%.

**Whole game (bot time, x2 for a person).** Verdance to its leave point ~1.9-2.2 h (base 3 at 114
min, Mk V soon after), then Ochre ~2.0, Tidewell ~2.0, Rime ~2.4, Anvil ~2.3 to 50%, plus the
return trips (50% -> 100% with the later tech, est. 1.5-2 h): about 10-11 h bot, so ~20-22 h for a
person. Verdance's own 50% (the Bloom Core) comes much later (433 bot min) because its frontiers wait
for later-planet tech; that is by design (return trips).

Result: every later planet reaches 50% in 2.0-2.5 bot hours (4-5 h for a person), within ~20% of
the 1.5-2 h target and never slower than Verdance's own path to the same point. They still come in
a little after Verdance's leave point (base 3, ~1.9 h bot), mostly because the 50% needs Thriving
hexes over several districts (planting is the bottleneck: seeds pile up while Seedlings are few).
Next lever if a person's runs come in slow: more planters in the arrival kits or a Seedling-first
default Fabricator mix, not lower Thriving targets (those are the planets' size).

**Caveats.** The flat districts don't grow with the globe's area: on round planets the Fabricator's
size-scaled fleet cap and far crews carry the bigger planets (orbit autoplay is not wired yet). The
bot spends greedily, so the Fabricator's fleet stays near 20 robots on a flat district; a person who
sets the mix and lets it run gets more. Two bot runs stalled with the tree paused (a modal the bot
does not close) at random times; the watchdog in those runs found `paused=true`, cause still open.
