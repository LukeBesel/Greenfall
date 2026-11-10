# Planet playbook

A living guide for building every planet after the first. Updated at the end of each milestone. It records how to make a planet, what made Planet 1 work, what failed and how it was fixed, the balance rules, and the checklists and templates.

Status: started in Phase 0 (Nov 9, 2026). Sections marked *(fills in during Mx)* are placeholders for knowledge that does not exist yet; everything else is current.

## 1. How to create a new planet *(steps become exact in M1; this is the target)*
1. Copy `planets/_template/` to `planets/<id>/`. Ids are lowercase, one word, and never change after release.
2. Fill in `planet.tres` (the PlanetDefinition): display name, globe spec (size, site count), target playtime, palette, music set.
3. Fill in the data tables in `planets/<id>/data/`:
   - `districts.json`: the chapters, their order and unlock rules
   - `pollution.json`: pollution kinds, the tool each needs, payouts
   - `upgrades.json`, `rigs.json`, `research.json`: the upgrade tree
   - `regrowth.json`: regrowth stages and their rewards
   - `restoration.json`: how district states add up to planet restoration, and what triggers the ending
   - `tutorial.json`, `goals.json`: onboarding steps and the goal ladder
   - `balance.json`: curves and constants
4. Add art hooks only if needed: `env.gd` (sky, light, weather) and site scripts for the planet's own props. Shared systems call them through the definition.
5. Run the simulator (`tools/pace_sim`) until the cadence rules pass.
6. Run the planet-parameterised tests and the bot on the new id.
7. Play it. Then run the engagement review.

A new planet should need no change outside its folder. If it does, the shared system is missing a data field: add the field, do not add a branch.

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
| Bot-to-player speed | bot is about 2x faster |
| First payout / first upgrade / first clean hex | 20 s / 90 s / 3 min |
| Small win interval | 40 s or less |
| Affordable purchase interval | 3 min or less in the first hour, 4 min after |
| Longest gap between goals | 4 min |
| New mechanic | every 10-15 min in the first hour, every 30-40 min after |
| Power spike | every 30-40 min, at least 2x cleaning rate |
| Hand share of output | 30% or more at all times |
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

### Formulas proposed for the Planet 1 redesign (M3-01)
Proposed, not built: the numbers live in `tools/pace_sim/proposals/planet1/` and the results in `docs/reviews/BALANCE_PROPOSAL_P1.md`. Times are bot seconds; a new player is about 2x slower at actions, and growth timers are real time. Every cadence limit above is a player limit, so a bot time is doubled before it is compared.

**Chest against hex (the first ten minutes)**
- Chest = what a new player fills in about 6 seconds (12 units at 2 units a second). A first hex = 10 chest loads (120 units). The bin is one short walk (2.5 s bot).
- Rule of thumb: the 20-second payout rule sets the chest, the 3-minute hex rule sets the hex at about 10 loads. Change one and the other rule breaks.

**Lumi's rate on a kind**
- Sweep rate = base rate x track levels x kind factor x rig module x (1 + 0.08 x mastery level of that kind).
- With a chest: units a second = chest / (chest / sweep rate + handling), handling = one bin trip loose, or one press plus a share of a carry once the Baler is fitted.
- A loose load pays 1.0x, a perfect bale 1.5x. Loose must stay under the worst bale a player presses, or tipping wins.

**Track prices: one tier per district**
- A track adds the same amount every level: stat x (1 + add x level). Sweep Speed adds 20%, Sweep Width 15%, Chest Size one starting chest.
- Each district opens one tier. Price of a level = tier price x track weight x ratio ^ (position in the tier). Tiers hold 8, 4, 5, 6, 8, 10 levels with ratios 1.6, 1.3, 1.25, 1.2, 1.16, 1.13; tier prices are 1,100, 2,400, 4,100, 7,500 and 10,800 for districts 2-6 (district 1 uses each track's own first price, 40 to 220).
- Rule of thumb: a tier's whole price should be about what the district earns. Too cheap and the bench is empty before the district ends; too dear only delays the last levels to the next district.
- Rule of thumb: a track that raises the sweep rate is worth about twice any other per level. Price it 1.5-2x or it is always the best buy.

**Mastery curve**
- Level L of a kind needs level-1 units x 1.78 ^ (L - 1) units of that kind cleared by Lumi's own hands, in total. Level 1 comes after about a minute of bot work on the kind, level 5 after about ten times that, level 10 after about 180 times.
- Level-1 units rise with each kind (litter 220, wrecks 1,000, slick 2,200, smog 4,000, blight 7,000) so a new kind takes as long to learn as the first did.

**Robot speed rule**
- A robot works a kind at: type rate x (0.4 + 0.12 x Lumi's mastery of that kind) x 1.25 in the district Lumi is in x 1.6 once its type is repaired x 1.25 per base level above 1. Below mastery 1 it cannot work the kind at all.
- Robots clean, tend or carry; only Lumi's hands and the Scroungers bring in Parts.
- Rule of thumb: buy for the kind that lags. A district is finished when its slowest kind is, so ten more robots on a kind that is already ahead add nothing.

**The chain that builds the crew**
- Every cleaned hex leaves buried parts (0 in district 1, then 1.5 to 2.6 a hex). A Scrounger carries 4 per round trip of 30 s + 1.5 s per ring of the district, and nothing when the ground is empty.
- An Assembler builds one robot per 40 s if the Parts are there. Assemblers cost 45, 195, 345, 495 Parts. The crew cap is 8, 28, 70, 110, 160, 200 by base level.
- Three brakes keep the loop smooth: trip time (Parts a minute per Scrounger), buried parts per cleaned hex (growth follows cleaning), assembly time (robots a minute). The cap should be the last thing the player meets, not the first: when the crew sits at the cap for minutes, raise the cap.
- Rule of thumb: about 15% of the crew as Scroungers. All Scroungers or none both finish later.

**Regrowth by tending**
- Planting one hex costs one seed and 1 s. One watering adds 30 growth points at once and 180 s of full growth (1 point a second; 0.25 dry). A hex needs 60, 150 and 300 points to leave planted, growing and sustained. The same hex can be watered again after 15 s.
- So one planting and one watering take a hex from clean to sustained in 3 minutes with no waiting on the player's side, and watering again is always something to do.

**Surge charge**
- 120 s of hand work (sweeping, pressing, tending) fills the core; Core Charge levels divide that by (1 + 0.12 x level). Release: 12 s at 3x Lumi's cleaning, plus 60 growth points for 14 hexes.
- Rule of thumb: that is about +18% on average. The Surge is a moment, not a power spike.

**Payouts**
- A clean hex pays 0.1 cubes per unit of its work; regrowth pays 2, 2, 3 and 5 cubes per hex per stage, times the district's hex work over 120. A robot's work pays 12% of what the same work pays by hand.
- Rule of thumb: keep every payout that is not Lumi's own bale under a fifth of the bale income, or robots earn from rewards the player did not work for (the baseline's third problem).
- No single purchase should raise income more than 3x (the largest here is the Baler, 1.38x); no one-off reward should be worth more than 3 player minutes of income.

**Power spikes**
- A spike is the cleaning volume (units a second, hand and crew) reaching 2x its value at the last spike. One every 30-40 player minutes over 4 hours means the volume ends 100 to 300 times where it started, and income with it. This is the rule that sets how big the late numbers get.

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
