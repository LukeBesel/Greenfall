# Planet playbook

A living guide for building every planet after the first. Updated at the end of each milestone. It records how to make a planet, what made Planet 1 work, what failed and how it was fixed, the balance rules, and the checklists and templates.

Status: started in Phase 0 (Nov 9, 2026). Sections marked *(fills in during Mx)* are placeholders for knowledge that does not exist yet; everything else is current.

## 1. How to create a new planet *(steps become exact in M1; this is the target)*
1. Copy `planets/_template/` to `planets/<id>/`. Ids are lowercase, one word, and never change after release.
2. Fill in `planet.tres` (the PlanetDefinition): display name, globe spec (size, site count), target playtime, palette, music set.
3. Fill in the data tables in `planets/<id>/data/`:
   - `districts.json`: the chapters, their order and unlock rules
   - `pollution.json` (table `pollution_kinds`): pollution kinds, how each is worked, its spawn rule, the tool it needs, its payout weight. The junk models are the `pollution` table (`junk.json`)
   - `upgrades.json`, `rigs.json`, `research.json`: the upgrade tree
   - `regrowth.json`: regrowth stages and their rewards
   - `restoration.json`: how district states add up to planet restoration, and what triggers the ending
   - `tutorial.json`, `goals.json`: onboarding steps and the goal ladder
   - `balance.json`: curves and constants
   - `cities.json` (optional, visual only): each city's palette, building mix, roof props, street dressing and source landmark, read by the planet's own site scripts
4. Add art hooks only if needed: `env.gd` (sky, light, weather) and site scripts for the planet's own props. Shared systems call them through the definition.
5. Run the simulator (`tools/pace_sim`) until the cadence rules pass.
6. Run the planet-parameterised tests and the bot on the new id.
7. Play it. Then run the engagement review.

A new planet should need no change outside its folder. If it does, the shared system is missing a data field: add the field, do not add a branch.

### What a planet folder holds today (M1-07)
`Planets` registers every `planets/<id>/planet.tres` at start. `shipped = false` keeps a planet out of the game but loadable by id (tests, and the dev flag `--orbit-planet=<id>`). Five are registered: the first planet ships; four later ones are parked as data (their READMEs say what they inherit).

| In the definition | What it is for | Read by |
|---|---|---|
| `id`, `display_name`, `tagline`, `order`, `shipped` | Identity. Text takes the name through `name_in("... {planet} ...")` | `Planets`, HUD, story text |
| `globe_frequency`, `hub_count`, `world_seed` | Globe size (10 m cells, radius 14.375 m per unit of frequency), number of hub sites, seed: `globe_spec()` | `OrbitPlanet`, `SphereOffline` |
| `tables` | Table name to JSON file. Five are required; the rest are optional | `Economy.planet_table(name)` |
| `tables["look"]` | Sky, fog, sun, ambient, palette, junk tint (the env script's values), `globe` (the map globe) and `orbit` (place round the binary star) | the env script, `PlanetGlobe`, `SolarSystem` |
| `tables["sites"]` | The hub and landmark site list, plus `hub_pad_m`, `fill_pad`, `yard_keep_out` | `SiteBuilders`, `OrbitPlanet` |
| `sites_script` | Static hooks that build the sites: `build_site` (or `build_async` / `build` / `place`), optional `restyle_site`, `build_surroundings` | `SiteBuilders` only |
| `env_script` | Static hooks for the planet's own environment art: `dev_hub`, `prepare_field`, `dress_view`, `apply` | `PlanetDefinition.call_env` only |
| `globe_shader` | Surface shader of the map globe (empty: the shared rocky world) | `PlanetGlobe` |
| `music_set` | One of `MusicTracks.SETS`: tracks, instruments and ambience bed | `Audio` |

A site script that is a town on a street grid extends the shared `TownSite` (`planet/sites/town_site.gd`), so the garden, street power and outposts can read its streets without knowing the planet. A planet with no sites table gets a bare pad with the shared yard anchors (`SitePrefab.START_YARD_ANCHORS`).

Two tests hold the rule: `tests/test_planets.gd` fails when a shared script quotes a planet id or a planet folder, and `tests/test_planet_reuse.gd` builds, runs, saves and loads the world on the dummy planet in `tests/fixtures/planets/testworld/` (six small tables, one site, one 18-line sites script). Its pollution kinds table holds a kind no shipped planet has (`tests/test_pollution.gd`).

## 2. What made Planet 1 addictive *(fills in during M3-M6)*
Design intent, to be confirmed by measurement:
- A win every 20-40 seconds and a purchase within 3 minutes, at every stage.
- Hexes sized to finish in 1-3 minutes by hand early on.
- One new pollution kind and one new tool per district, with a power spike that at least doubles cleaning rate.
- Hand work stays above 30% of output: robots copy what the player has mastered.
- The planet itself shows progress; the player can always see what they changed.

## 3. What did not work and how it was fixed
| Problem (found Nov 9, before the redesign) | Evidence | Fix (task) |
|---|---|---|
| The first hour was slow and empty | First hex at 7.5 bot-minutes, then one every 6; gaps of 20, 16 and 32 minutes with no goal; 74 hexes after 100 bot-minutes | Faster hands, districts, goal ladder (M3-02, M3-03, M3-10) |
| The planet could not be finished | No code path set the restored state; restoration capped at 68% pending later planets | Restoration model and ending owned by the planet's data (M1-10) |
| Progress was shown as a planet percentage with four decimals | HUD read "0.0000%" after minutes of work | District-level progress readout (M3-03) |
| Waiting on timers stood in for play | Research cost real time; the garden was slow on purpose | Work-driven research and tending (M3-06) |
| Planet logic was hardcoded | 200 planet-name literals; index branches; global data files | PlanetDefinition and per-planet folders (M1-03 to M1-07) |
| Two world modes doubled every system | 78 flat-or-globe branches | Remove the flat world (M1-04) |
| Tuning needed a 30-minute bot run per game hour | Bot wall-clock times | Fast simulator on the same data (M1-12) |
| Breadth came before a fun core | Five planets and a prestige mode while pillars 2 and 4 failed | Park everything Planet 1 does not need (M1-08) |

## 4. Balance rules of thumb
Targets, to be replaced by measured values as milestones land.

| Rule | Target |
|---|---|
| Playtime to a planet's ending (first-time player) | about 4 h for Planet 1; later planets set theirs in the definition |
| Bot-to-player speed | bot is about 2x faster; every cadence limit below is on the player's clock, so the simulator checks each at half its stated time |
| First payout / first upgrade / first clean hex | 20 s / 90 s / 3 min |
| Small win interval | 40 s or less |
| Affordable purchase interval | 3 min or less in the first hour, 4 min after, in at least one currency (Parts-only and cube-only waits are reported, not required) |
| Longest gap between goals | 4 min |
| New mechanic | every 10-15 min in the first hour, every 30-40 min after |
| Power spike | every 30-40 min, at least 2x cleaning rate |
| Hand share of output | 10% or more of cleaning volume before district 4; Lumi's actions always decide what the crew can do next (the 30% rule was dropped with the 100-200 robot crew) |
| Offline bonus | capped; never more than a few minutes of active play |

**Cost curves (target):** inside a district, a track's cost grows by a fixed ratio per level, tuned so the time to the next level rises about 10-15% each step. A new district starts a new tier: income jumps, the first purchases are quick, then the curve climbs again. *(Target ratios are set in M3-01 and M3-12.)*

### Formulas the simulator uses (current game, M1-12)
`tools/pace_sim` computes these from the planet's tables. Names in `code` are table fields or calibration constants (`tools/pace_sim/calibration.json`). Example numbers are Planet 1 today.

**Junk in a hex**
- A hex holds a fixed volume of junk (407 units) and counts as clean when 95% is gone: 387 units to scoop.
- One scoop lock takes up to 1.22 units of a piece. Averaged over the junk table that is 1.04 units a take, 372 takes a hex.
- Average value: the junk types' `value`, weighted by their share of the volume. 0.81 cubes a unit.

**Hand rate (units of junk a second)**
- Seconds per unit = 1 / (`scoop_rate` x `pickup_count` x mean take x `hand_duty`) + `seek_s_per_volume` / beam gain.
- Beam gain = (scoop width x reach, over their base values) ^ `beam_exponent`.
- The second term does not shrink with scoop speed. Rule of thumb: past about 3 levels of Scoop Speed and Scoop Size, finding junk is the limit, not the pulse.

**Time for one chest load**
- Fill: 0.95 x `capacity` / hand rate.
- Before the Baler: one bin trip per load = 2 x distance / `move_speed` + `trip_overhead_s`.
- With the Baler: 1.7 s press + `bale_handle_s` per load, and one bin trip per `carry_stack` bales. With a Haul Bug: no trips.
- Distance to the n-th hex = `yard_offset_m` + ring x 17.3 m. Ring 1 is hexes 2 to 7, ring 2 hexes 8 to 19, ring r ends at hex 1 + 3r(r+1).
- Rule of thumb: loads per hex = 387 / (0.95 x capacity). At the starting chest of 12 that is 34 trips for one hex, which is why the first hex takes 7 minutes.

**What a load pays**
- Loose in the bin: volume x average value x `dump.mult` x `cube_value_mult`.
- As a bale: volume x average value x `cube_value_mult` x 1.5 for a full chest (`perfect_mult`) x sell factor.
- Sell factor = the bin level's `value_mult` + the base level's `sell_mult` bonus.

**What a clean hex pays** (whoever cleaned it)
- `bonus_base` + `bonus_per_volume` x hex volume, plus one field note (`data_rewards.hex_cleaned` x `note_cubes`), plus the regrowth table's level 1 reward. Today: 122 + 100 + 25 = 247 cubes.
- For comparison, the junk in that hex is worth about 470 cubes baled by hand and about 27 cubes baled by a Scoopie. Rule of thumb: a robot's income is the hex bonus, not its bales.

**Parts**
- Expected Parts per take = sum over junk types of (share of takes x `part_drop` chance) x the rarity table's mean value (38.4). Buried parts add `chance_per_hex` x 38.4 a hex.
- That gives about 130 Parts per hand-cleaned hex; the bot measured half (`parts_luck`). Robots find none.

**Robots**
- A cleaner takes `scoop_rate` x 0.315 units a second; a hex is 63 x 0.95 = 60 of its units. Seconds per hex = 60 / rate + `crew_travel_s_per_ring` x ring. A first Scoopie: 136 s of work plus 50 s per ring.
- A bale is one hopper (`capacity` units) and pays capacity x 0.75 x `efficiency`.
- A hauler moves `carry` bales per trip of 2 x distance / speed + `haul_overhead_s`.
- Crew cap per role = `crew_cap.base` + `crew_cap.per_level` x base level.

**Cost growth**
- Upgrade: `base_cost` x `growth` ^ level.
- Robot: `cost` x 1.35 ^ owned of that type in cubes, `parts` x 1.2 ^ owned in Parts. Mk tier: `cost` x the tier's `cost_mult`, plus 200 / 700 / 2,000 Parts.
- Base levels, workbench tiers, tower tiers, stations: flat costs from their tables.

**Time to next**
- Time to next purchase = (cost + reserve - cubes on hand) / income rate, and for Parts the same with the Parts rate. The slower of the two decides.
- The reserve is what the buyer is saving for: the next robot, then the next base level once its Parts are in.
- Rule of thumb for a geometric track: with ratio g and steady income, each level takes g times as long as the one before. A track only stays inside the 3-minute purchase rule if income grows by g between its levels.

**Garden**
- Plant slots in a hex = hex area / `slot_spacing`^2 (49). Planted needs `planted_min_frac` of them: 13 seeds.
- A seed turns up once per `cooldown_s` + 1 / (`chance` x takes a second) of scooping. Bloom takes 4 x `grow_s` (about 5 min) and drops `seed_yield` seeds.

### Walking, and fitting a first city to it (M3-21)
The accepted proposal had no distance in it, and the real game ran 1.5 to 2.5 times slower. These replace the "Time for one chest load" lines above for the current game. Measured values are in `docs/reviews/M3-21_PACING_FIT.md`.

**Distance**
- The simulator walks the real yard: `yard_hexes.middles` are the measured middles of the hexes round the start yard, each measured against the yard's bin and scale anchors. Hexes are worked nearest the bin first. Past the measured hexes: `yard_offset_m` + ring x 17.3 m.
- Inside one hex the walk grows as it is cleaned: middle distance + (share cleaned - 0.5) x `hex_span_m` (16 m).
- One way = metres x `path_factor` / `move_speed` + half of `trip_overhead_s`. `path_factor` (2.1) is the route against the straight line: round the fence, along streets, turning. Within the bin's reach (4 m) a loose load tips with no walk at all.
- Rule of thumb: at 5 m/s a load from 20 m costs about 21 s there and back. A 24-unit chest fills in 6 s, so before the Baler **three quarters of the second hex is walking**. Hexes 2 to 4 are the slowest of the first ten minutes (100 to 125 s each for the bot); price the Baler at about 60 s of income, not more.

**Yard layout**
- Junk must start within 4 m of the bin and the first hex's middle within 8 m of it, the scale within 12 m. `tests/test_pacing_fit.gd` measures this on the real globe. The second-nearest hex is a hex spacing further (17 m) whatever the layout: a layout fixes the first minute only.

**The first robot is a hauler**
- With a hauler Lumi makes no trips: a hex drops from about 100 s to about 50 s near minute 9. That is the first power spike, and it must come before the walk grows past ring 1.
- A hauler moves `carry` bales per trip of 2 x distance / speed + `haul_overhead_s`. Whether one Haul Bug (2 bales, 2.8 m/s) still keeps up past ring 2 was not measured.

**Side income**
- Level rewards, salvage surges and weather add `side_income_share` (0.4) on top of Lumi's loads, growing from nothing over `side_income_ramp_s` (10 minutes). Rule of thumb: the bot earns about 260 cubes per clean hex in the first 20 minutes, where the hex itself pays 116 x 1.5 for perfect bales.
- The bot's income: about 2 cubes a second before the Baler, 1 to 2.5 while the first bales are carried to the scale (minutes 2 to 5), 4 to 5 after that, 5 to 7 with the Haul Bug.

**Pricing rules that came out of the fit**
- **A price is a wait.** The bot saves for what the card asks and buys nothing dearer than a fifth of it meanwhile, so the longest wait is price / income. For "no wait over 120 s" with a margin for a slow run, a card purchase costs at most about 60 to 75 s of income at the time it is asked for: 130 at minute 1, 100 at minute 3 (income dips to 1 to 2 a second while every bale is carried), 260 to 350 from minute 8.
- **Gate by hexes, not by price, when a step must not come early.** The Bot Bay waits for 6 clean hexes; base level 3 waits for the Research Desk and 24 hexes. A gate adds no saving time, so nothing else stops being bought. A dear price does the opposite: with the base's 1,100 on offer the bot bought nothing for 4 minutes 40 s.
- **Put a purchase on the card as soon as it is on offer.** While the card asked for 7 clean hexes the tower was nobody's goal and arrived anywhere from minute 6.7 to minute 11. The card now asks for the tower as soon as the base has power, before the 7 hexes.
- **A story sequence is a wait too.** The first seed takes Lumi off the work for about 110 s. Nothing dear may be on offer when it comes (the Research Desk now waits for the tin), and by itself it is nearly the whole 120 s allowance.
- **Run-to-run spread is about 25%.** The same build gave the first robot at 8.0 and at 12.0 minutes: digs, a salvage surge and the order hexes are finished in move it. Aim the median at least 20% inside a limit, and judge a number on two runs, never one.

### Pollution kinds (M3-04)
The rules are `systems/pollution.gd`; every number is in the planet's `pollution_kinds` table, and each city's `pollution` list in the districts table says which kinds its hexes hold. Measured values are in `docs/reviews/M3-04_POLLUTION.md`.

- **One ledger per hex.** A hex holds its city's `hex_work` units whatever is on it. Each kind beside the base kind owns `spawn.share` of that; the base kind (loose junk) has the rest. All the other kinds together never own more than 0.9, and no kind less than 0.08, so nothing sweeps away untouched under the 95% rule.
- **Clean is still one rule:** 95% of the ledger gone. Waste a scoop cannot take (a `held` kind: smog, blight) is a floor under the hex's junk for cleaners, far crews and the offline jump, so the hex stays dirty until that kind's own tool has been at it.
- **How many hexes hold a kind** = the city's hexes of that ground past `min_ring` x `density`. With `cluster` above 0 the kind lies in patches about 60 m across and the count is only about right (measured 0.7 to 1.1 of the density).
- **Lumi's rate on a held kind** = `hand_factor` x scoop pulse volume x scoop rate: her scoop upgrades speed every kind.
- **Payout:** a take pays the hex's plain share (HexWorth) x the kind's `yield.cubes` over the hex's average yield (each kind's share x its yield). The weights move value between kinds on one hex; the hex still pays its city's `hex_cubes`. Robots are paid nothing.
- **A cost** (`cost.per_hex` of a currency) is charged as the work adds up and spent a whole unit at a time; what is owed is saved.
- Rule of thumb: a kind's gate should be something the city itself gives (its tool, its robot). A gate the player may already own on arrival is not felt as a gate.
- Rule of thumb: keep `tool_use_per_unit` low enough that one tank clears about ten hexes; the can only fills at the base.

### Rigs (M3-08)
The rules are `systems/rigs.gd`; every number is in the planet's `rigs` table. Measured values are in `docs/reviews/M3-08_RIGS.md`.

- **A stat of Lumi's with a rig** = max((value after upgrades, research and sets + the modules' `adds`) x the modules' `mods`, the modules' `floors`). Keys that are not upgrade stats (`kind_<id>`, `parts_yield`, `crew_near`, `crew_radius`) are plain multipliers read where they act.
- **A kind's tool is its gate.** `gate.module` in the kinds table names a rig module; Lumi can work the kind only while it is fitted. The tool's plan arrives when the first city that holds the kind opens, free; its price is the slot.
- **Tools that share a slot are a choice per outing**, so give two tools the same slot only when their kinds never lie on one hex (slick is whole lake hexes; blight is land).
- **Every other module is a trade:** one gain, one loss, built once for cubes and Parts under the city price cap.
- **The rig study** (`tools/pace_sim/rig_study.gd`, `--rig-study=1`) scores each module in each city as cubes, cleaning and Parts a minute, weighted by city. A loadout without a city's new tool loses the share of hexes that hold the new kind (nobody can open them). The study fails when one module is the best fit of its slot in every city.
- Rule of thumb: a tool should also carry what its kind needs from upgrades (lift, hover), or a first-city upgrade becomes a hidden second gate.
- Rule of thumb: no rig module in the first city. The first city teaches the loop; the rig is the second city's new mechanic.

### Mastery and apprentice robots (M3-05)
The rules are `core/mastery_rules.gd` (plain maths, shared with the simulators); the state is `systems/mastery.gd`; which hexes robots must leave alone is `systems/pollution_crew.gd`. Numbers: the `mastery` block and each kind's `mastery_level1_units` in the planet's `pollution_kinds` table, and `mastery_speed` and `proximity` in its `robots` table. Measured values are in `docs/reviews/M3-05_MASTERY.md`.

- **Only Lumi's own work counts:** units of a kind she clears x the kind's `mastery_per_unit`. Robot work teaches nothing.
- **Level L is held at** `mastery_level1_units x growth^(L-1)` units in all. With growth 1.78 level 5 takes ten times the work of level 1.
- **Lumi's rate on a kind** = her rate x (1 + `hand_bonus_per_level` x level). For scooped kinds the scoop pulses that much sooner; for tool kinds the take per second is that much larger.
- **A robot's rate on a kind** = its own rate x (`base` + `per_level` x level), and nothing under `min_level`. The rates in the robots table are therefore the rates at the level where the factor is 1 (level 5 on Planet 1).
- **Within `proximity.radius_m` of Lumi** a robot works (1 + `bonus`) times as fast.
- **The gate on the ground.** Scooped kinds share a hex's pieces, so a hex that still holds an unlearnt scooped kind is shut to robots as a whole (`SphereCells.shut`); it opens when Lumi learns the kind or clears it off that hex herself. Tool kinds are gated one by one, so a cleaner still takes the litter off a smog hex.
- **Time away** is worked at the base kind's rate; shut hexes are skipped.
- **A save from before mastery** is credited `legacy_credit` of the waste of its clean hexes, kind by kind, and at least the robot level in every kind its robots work.
- Rule of thumb: set a kind's `mastery_level1_units` to about two minutes of Lumi's hand work on it in the city where it first appears (the heavier that city's hexes and the faster her hands by then, the larger the number).
- Rule of thumb: the first robot of a role must be useful the moment it is built, so its plans should arrive after the first level of the kind it works. The simulators check this (`robots_never_wait_on_mastery`, and the robot-minutes spent waiting in `tools/crew_sim`).

### Source jobs (M3-07)
The rules and the state are `systems/sources.gd`; where a step stands in the world, its marker and prompt are `systems/source_sites.gd`; every job is data in the planet's `sources` table. Measured values are in `docs/reviews/M3-07_SOURCES.md`.

- **The hold.** A city with a job cannot reach `gates_stage` until the job is done (`Districts.set_stage_cap`): its hexes may all be there, the city waits one stage short. The next city opens before that, so the job never blocks moving on. A planet with no table holds nothing.
- **Offered** from the city's `open_stage` (a job may set its own), and a step with `at_clean` only once that share of the city's land hexes is clean.
- **Three step types, no script:** `use` (walk there, use it), `work` (use it, then stay in reach for `seconds`; leaving pauses it) and `carry` (pick a part up at `from`, paying `cost`, carry it to `at`, fit it for `seconds`). Work with a `kind` runs at Lumi's hand bonus for that kind (1 + `hand_bonus_per_level` x level), so mastering the city's kind shortens its capstone.
- **Spots** are metres in the frame of the city's source landmark (`TownSite.source_frame`: x to the right, z toward the yard), so the site decides where its landmark is. Keep every spot on a street or an open lot: the tests check the first planet's against its landmarks' footprints.
- **Done:** `EventBus.source_shut_down(district)`, the hold lifts (the last stage and its payout follow at once if the hexes are there), the landmark goes to its shut-down state, the reward is paid, the city's source finds are given.
- **Reward:** cubes under the 3-minute rule for that city's own `income_ref` (Planet 1 pays about one minute), plus Parts where the job costs none.
- **A save from before jobs:** a city already at the gated stage counts as shut down, unpaid; every other city gets its job.
- Rule of thumb: three to five steps, the first a plain `use`, one `work` step on the kind the city introduces, at most 10 s standing still in any one step.
- Rule of thumb: a planet's last job can be its ending's set piece (Planet 1: the rocket, six `carry` steps that take the late Parts surplus). Gate its steps with `at_clean`, not with the city's stage, so they spread over the city instead of piling up at its end.

### Surge (M3-09)
The rules are `core/surge_rules.gd` (plain maths); the state is `systems/surge.gd`; the look and sound are `art/surge_fx.gd`. Numbers: the `surge` block of the planet's `balance` table. Measured values are in `docs/reviews/M3-09_SURGE.md`.

- **Only Lumi's own work charges the core:** units of waste she clears / `charge.units[district]`, plus `charge.per_bale` for each bale she presses and `charge.per_plant` / `charge.per_water` for each seed and each pour. Robot work, standing still and time away add nothing; nor does work during a Surge.
- **Charge needed** is one entry per district in play order, about four minutes of Lumi's hand rate there, so better tools shorten it inside a city and the next city resets it.
- **Fastest fill** = `charge.min_fill_s` seconds of work, whatever the tools: a Surge stays a moment.
- **A stat during a Surge** = stat x (1 + (`stats[stat]` - 1) x power), power = 1 + `power_per_district` x (district - 1). **Output** = the `scoop_rate` multiplier x the `pickup_count` multiplier (pulses a second x waste a pulse). Keep it at 3 or more in every district; the suite measures it on a real sweep.
- **Chest room of swept waste** = `chest_pack` / output of its volume (cube value unchanged). At 1 the chest fills as fast as in plain sweeping; below 1 slower. Without this a Surge is spent walking to the bin.
- **Growth wave:** from `wave.from_district` on, every plant within `wave.rings` (+ `rings_per_district` per later district) rings of Lumi gets `wave.water_s` of water and `wave.stages` of a growth stage.
- Rule of thumb: put the output on both the pulse rate and the pulse size. Rate alone is rounded to whole frames at high upgrade levels; size alone does not feel faster.
- Rule of thumb: the first Surge should come after the first hex and before the first robot, so it is learnt as Lumi's own move.

### The crew and the robot chain (M3-20)
Every number is in the planet's robots table. The rules are `core/crew_rules.gd` (cap, prices) and `core/crew_chain.gd` (the ground, the Assembler's line); `tools/crew_sim` plays a whole planet on them. Measured values are in `docs/reviews/M3-20_CREW.md`.

**Crew cap**
- cap = the smaller of `crew_cap.by_base_level[base level]` and `crew_cap.by_cities_open[cities open]`. One cap for the whole crew, whatever the jobs. Buildings are not robots.
- Write `by_cities_open` first, as the crew each city should end with plus about a fifth of room. Then write `by_base_level` so that a new city's cap needs the next base level: the base level stays a purchase that matters.

**Prices**
- A robot costs `parts` x `price.parts_growth`^owned x the tier's `build_mult`. Keep the growth at 1.0: with a crew of 150 any compounding passes every other price on the planet (1.2 per robot was 1,977 Parts for the 30th Scoopie).
- A tier step costs the type's `tier_parts` + `price.tier_per_robot` x its build price x robots owned, never more than `price.tier_max_parts`. Set that cap to the planet's dearest Parts price.
- Crew upgrades cost Parts (`upgrade_currency`). Few levels, small prices: their job is the choice between a better crew and a bigger one, not a second price curve.
- `price.tier_cities_open` keeps tier steps out of the first city, where Parts are for the first robots.

**The ground**
- A hex leaves `chain.ground[city]` buried parts when it is first cleaned, once. That is all the Scroungers can ever bring in, so crew growth follows cleaning. Total = the sum over cities of hexes x parts per hex: check it against what the planet's robots, tier steps and late Parts sinks cost.
- A Scrounger's Parts a minute = sack / trip time. Trip = (ring out + one hop per further hex + ring back) x 17.35 m x `path_factor` / speed + sack / dig rate. Rule of thumb on the first planet: 1 to 3.5 Parts a minute per Scrounger, falling as a city's cleaned ring moves out. The ground, not the Scroungers, is the limit from the third city on.

**The Assembler**
- One line, one robot per `assembly_s`, in real time. The crew can grow by at most 60 / `assembly_s` robots a minute, whatever the Parts: this is what makes the curve steady. 80 s gives about 22 robots in a 30-minute city.
- The accepted proposal counted seconds on the bot's clock, which runs twice as fast as a player. Robots and the line run in real time, so a number taken from the proposal for a machine doubles (40 s became 80 s).
- Before the Assembler the bench paces the crew: a robot per bench visit. In the city of hand building keep robots cheap and Parts plentiful enough for a robot every 50 s, or the city feels like a queue.
- The line builds a type only after Lumi has built the first one by hand, and never past the crew cap.

**Where robots work**
- New robots work for the base of the city Lumi is in. A robot with nothing to do in another city for `chain.redeploy_idle_s` is shipped there. Robots still at work stay.

### Formulas proposed for the Planet 1 redesign (M3-01, second run)
Proposed, not built: the numbers live in `tools/pace_sim/proposals/planet1/` and the results in `docs/reviews/BALANCE_PROPOSAL_P1_V2.md` (the first run: `BALANCE_PROPOSAL_P1.md`). They follow the lead's decisions in `docs/design/PLANET1_DESIGN.md` section 16. Times are bot seconds; a new player is about 2x slower at actions, and growth timers are real time. Every cadence limit above is a player limit, so a bot time is doubled before it is compared.

**Chest against hex (the first ten minutes)**
- Chest = what a new player fills in about 6 seconds (12 units at 2 units a second). A first hex = 12 chest loads (144 units). The bin is one short walk (2.5 s bot).
- Rule of thumb: the 20-second payout rule sets the chest, the 3-minute hex rule caps the hex at about 15 loads. Change one and the other rule breaks.

**Lumi's rate on a kind**
- Sweep rate = base rate x track levels x kind factor x rig module x (1 + 0.08 x mastery level of that kind).
- With a chest: units a second = chest / (chest / sweep rate + handling), handling = one bin trip loose, or one press plus a share of a carry once the Baler is fitted.
- A loose load pays 1.0x, the worst pressed bale 1.15x, a perfect bale 1.5x. Any pressed bale must pay more than a loose load, and pressing must also win per second (it does: tipping earns 0.75 of pressing at worst).

**Where cubes come from (decision 16.1)**
- Only two places: Lumi's own loads and bales, and city stage payouts. Robots earn nothing: no bale income, no clean-hex bonus, no payout when a hex they tend changes stage.
- **A hex has a value, not a unit.** Each city sets `hex_cubes`: what the waste of one hex is worth tipped loose by hand (116, 120, 125, 130, 135 and 330 for cities 1 to 6). A unit of a kind pays hex_cubes / hex_work x that kind's yield over the mix's average yield.
- So: **cube income = Lumi's hexes a second x cubes per hex x bale and value multipliers.** It follows Lumi's own pace in hexes, not the cleaning volume and not the crew.
- Rule of thumb for the floor: income cannot fall below (Lumi's share of a city's cleaning) x (that city's hexes / its minutes) x cubes per hex. With 2,107 hexes in 48 player minutes and Lumi doing 7% of them, city 6 gives about 3 hexes a player minute by hand. To make the numbers smaller, cut the share, the city or the hex value; nothing else moves them.
- A city stage payout = (100, 150, 300, 1000, 1200 for stages 1 to 5) x hex_cubes / 100. This is what pays while Lumi tends, when her bale income stops. Keep the stage 4 payout large enough to buy one track level: after the last hex is clean there is no other cube income.
- No single purchase should raise income more than 3x (the largest is the Baler, 1.38x). No one-off payout should be worth more than 3 player minutes of income, where "income" is the best 3 bot minutes of the last 12 (it is zero while she tends).

**Cube prices are seconds of Lumi's income**
- Every cube price is set from the average hand income of the city it belongs to (14, 16, 33, 40, 71 and 51 cubes a bot second in cities 1 to 6).
- First level of a city's track tier: 25 to 40 bot seconds of that income (650, 800, 1150, 1900, 2100 for cities 2 to 6). A tool: 20 to 30 seconds. A base level: 25 to 60. A research node about Lumi: 30 to 55.
- Price of a level = tier price x track weight x ratio ^ (position in the tier). Tiers hold 8, 4, 5, 5, 10, 20 levels with ratios 1.6, 1.3, 1.25, 1.2, 1.12, 1.12. District 1 uses each track's own first price (40 to 60).
- Rule of thumb: a tier's whole price should be about three quarters of what the city earns. Too cheap and the bench is empty before the city ends; too dear and the last levels wait for the next city. The two late tiers hold 30 levels a track and the default player buys about 8 of them: the rest are there for a player who cleans far more by hand (without them a no-robots player cannot finish inside 300 bot minutes).
- Rule of thumb: when a city's hexes get heavier, raise its hex value by about the same factor as Lumi's hexes a minute fall, or arriving in a new city cuts her income.

**Tracks (decision 16.14)**
- A track adds the same amount every level: stat x (1 + add x level). Sweep Speed and Sweep Width each add 18% to the sweep rate and cost the same; Chest Size adds one starting chest; Tending Reach adds 30% to tending and costs 0.7 of a sweep level; Core Charge adds 12% and costs 0.6.
- The check: with every open track priced the same, no track is clearly the best buy (10% or more ahead of the next) in more than half of the track purchases.
- Rule of thumb: tracks in one tier stay within a level of each other, because each level raises that track's price. So a track with a larger effect leads all the time. Fix dominance by evening the effects, not by pricing the strong track up.

**Mastery curve**
- Level L of a kind needs level-1 units x 1.78 ^ (L - 1) units of that kind cleared by Lumi's own hands, in total. Level-1 units rise with each kind (litter 220, wrecks 1,000, slick 2,200, smog 4,000, blight 7,000) so a new kind takes as long to learn as the first did.
- A robot type for a new kind opens only after Lumi has learnt it: the Drip needs smog mastery 1, the Seedling blight mastery 2.

**Robot speed rule (decisions 16.3 and 16.5)**
- A robot works a kind at: type rate x (0.4 + 0.12 x Lumi's mastery of that kind) x 1.25 in the district Lumi is in x 1.6 once its type is repaired x the base levels' multipliers (1.38, 1.5, 1.3, 1.8, 1.8 for levels 2 to 6) x 2 after the Crew Overhaul x its reach. Below mastery 1 it cannot work the kind at all.
- **Reach (distance from a base):** a robot works `shift_s` seconds between trips and a trip costs `s_per_ring` seconds for every ring out, so its speed at ring r is shift_s / (shift_s + s_per_ring x r). With 300 s and 2 s a ring the average over a city is 97% (6 rings), 94% (12 rings) and 90% (26 rings). Sixty rings out a robot keeps 71%.
- Rule of thumb: distance makes outposts worth building, it does not make crews large. A patch the size of the largest city round every base brings reach back to 90%; the crew a job needs is still work / (hours x robot rate).
- Robots clean, tend or carry and are paid nothing. The Drip (city 4) waters and mists smog; the Seedling (city 5) plants and sets cleansing plants.
- Rule of thumb: buy for the kind that lags. A district is finished when its slowest kind is, so ten more robots on a kind that is already ahead add nothing.

**The chain that builds the crew**
- Every cleaned hex leaves buried parts (0 in city 1, then 1.0, 1.8, 2.2, 2.0, 2.4 a hex). A Scrounger carries 8 per round trip of 30 s + 1.5 s per ring of the city, and nothing when the ground is empty. Lumi can dig them herself, 1 part per 3 s, when there is nothing else to do.
- Parts by hand are per hex, not per unit: a kind's yield is for a 120-unit hex and thins out as hexes get heavier. A hex gives Lumi about 0.8 to 1.4 Parts everywhere.
- The Assembler is one building with one line: one robot per 40 s when the Parts are there. **From city 3 on the line, not the Parts, paces the crew**: about 1.5 robots a bot minute, so 50 robots at the end of city 2 become about 150 at the launch point whatever the Parts supply does. Parts are kept in surplus and the surplus is what the rocket costs.
- The crew cap is 8, 56, 90, 120, 160, 200 by base level. It should never be met: when the crew sits at the cap for minutes, raise the cap.
- Rule of thumb: about 15% of the crew as Scroungers. All Scroungers or none both finish later.
- Rule of thumb: when the crew stalls on arrival in a new city, it is waiting for Parts for the first robot of the new type. Give the city salvage on arrival (city 3: 130 Parts) instead of making robots cheaper.

**The rocket (decision 16.4)**
- Six large parts, in order: 300, 350, 400, 450, 500, 600 Parts (2,600, about a quarter of all Parts earned). Each is ordered at the bench once that share of city 6's cleaning work is done (35%, 45%, 55%, 65%, 75%, 85%; the last also needs the source shut), takes the Assembler's line for 45 s, then Lumi fits it by hand in 20 s.
- The launch point is every city thriving AND the rocket complete.
- Rule of thumb: gate each part on the city's progress, not on its clean hexes or its stage. Clean hexes wait on the kind that lags and all arrive at the end, which turns a ladder into a wall.
- Rule of thumb: the line keeps building robots; the rocket is paid from what the line leaves over. Price the rocket at about the Parts left over without it.

**Regrowth, seeds and field data**
- Planting one hex costs one seed and 1 s. One watering adds 30 growth points at once and 180 s of full growth (1 point a second; 0.25 dry). A hex needs 60, 150 and 300 points to leave planted, growing and sustained.
- Seeds: a hex gives back 1 seed when it starts growing and 0.4 when it thrives; a thriving hex keeps giving 0.006 a minute. Clearing the blight of one hex costs 0.35 seeds of cleansing plants (decision 16.9).
- Rule of thumb: a hex with blight cannot be planted until it is clean, so its seeds come back late. The slow bloom of thriving ground is what stops seeds from locking up; without it the last city stalls at about 80% clean.
- Field data is banked (decision 16.10). A node is started when the bank holds its field data and is then done at once. Price nodes at what the bank holds when the node should arrive, or one slow node blocks the only research slot.

**Surge charge**
- 120 s of hand work (sweeping, pressing, tending) fills the core; Core Charge levels divide that by (1 + 0.12 x level). Release: 12 s at 3x Lumi's cleaning, plus 60 growth points for 14 hexes. It unlocks in city 4 together with the wave.
- Rule of thumb: that is about +18% on average. The Surge is a moment, not a power spike.

**Rigs (decision 16.8)**
- Each slot has one module that acts on the crew: Guide Arm (every robot x1.3), Sorter (Scroungers carry x1.35, Lumi's Parts x2), Relay Mast (robots in Lumi's city x1.4). The Guide Arm and the Relay Mast can be built from city 5; the Sorter is found in city 4.
- Rule of thumb: once the crew does four fifths of the work, a module on Lumi's own rate changes a city by a few percent and a crew module by a third. Crew modules win every city they are available in; keep them late, or no other loadout is ever right.

**Power spikes**
- A spike is the cleaning volume (units a second, hand and crew, averaged over 6 player minutes) reaching 2x its value at the last spike. One every 30-40 player minutes over 4 hours is 7 to 10 doublings, and each one overshoots: the volume ends about 2,500 times where it started (4 units a second to 10,000).
- With robots earning nothing this no longer sets the cube numbers. It sets the hex weights (144 units in city 1, 4,600 in city 6) and the crew multipliers.
- Rule of thumb: one doubling at a city's door is not enough for a city longer than about 32 player minutes. Give long cities a second doubling in the middle (city 6: the Crew Overhaul at 33% progress, crew x2), and make each one a clean x2 so it always counts.
- Rule of thumb: the spike rule, a 105-minute floor on the bot's run and a no-robots player who can still finish pull against each other. Heavier late hexes help the first two and hurt the third.

## 5. Checklists

**New planet setup**
- [ ] Folder copied from the template; id chosen
- [ ] Definition validates (`Planets` reports no errors)
- [ ] Every data table has a `_doc` and passes the schema test
- [ ] Simulator meets the cadence rules
- [ ] No change outside `planets/<id>/`

**Testing**
- [ ] Planet-parameterised tests pass on the new id
- [ ] Bot plays start to ending with no stall over 4 minutes
- [ ] Save round trip and old-save migration pass
- [ ] Out-of-order tutorial test passes

**Polish**
- [ ] Every district has distinct polluted and restored looks, readable from 30 m
- [ ] Every core action has sound, motion and a number
- [ ] Ending sequence and end screen in place
- [ ] Engagement review has no flag above minor
- [ ] Originality checklist passes

**Release**
- [ ] Performance budgets met on every preset
- [ ] Translations complete for shipped languages
- [ ] Credits and version updated

## 6. Templates *(created in M1 and M8)*
- `planets/_template/planet.tres`: PlanetDefinition with every field and comments
- `planets/_template/data/*.json`: each table with a `_doc` and one example row
- Tutorial step: `{id, trigger, text, pointer, done_when, skip_if}`
- Upgrade track: `{id, stat, base_cost, cost_ratio, max, tier, requires}`
- Planet test case: `tests/planet_case.gd`, a base class that takes a planet id
