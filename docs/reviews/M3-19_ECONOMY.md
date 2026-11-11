# M3-19 and M3-02: the accepted economy in the real game, city 1 (Nov 11)

What was built, what the bot measures against the accepted proposal (`docs/reviews/BALANCE_PROPOSAL_P1_V2.md`), and what could not be applied yet.

**Verdict.** The rules are in and tested: a hex has a cube value, robots earn no cubes, tipping never beats pressing, goals pay when they complete, numbers are small and whole. The first minute is fast (first payout 2 s, first upgrade 16 s after control). **From the first hex on the game runs about 1.5 to 2.5 times slower than the proposal, and two acceptance numbers miss:** the bot's first hex takes 100 s (target 90) and its longest wait between purchases in the first 20 minutes is 172 s (target 120). The cause is one thing: the proposal has no walking (a 2.5 s tip, a 3 s carry), and in the game the junk is 10 to 30 m from the bin.

## 1. Beats: bot against proposal

One fresh run: `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=900`. No SCRIPT ERROR. Times are from the moment the bot takes control (the bot now prints `control_s`; the 62 s of loading before it used to be counted as play).

| Beat | Proposal (bot) | Game (bot) | Ratio |
|---|---|---|---|
| First payout | 8 s | 2 s | 0.3 |
| First upgrade | 26 s | 16 s | 0.6 |
| First clean hex | 68 s | 100 s | 1.5 |
| Hexes 2 to 5 | about 36 s each | 204, 325, 396, 468 s (92 s each) | 2.5 |
| Baler | 3.6 min | 4.1 min | 1.1 |
| "Clear the street" (7 hexes) | 4.7 min | 10.1 min | 2.1 |
| Signal tower | 6.7 min | 12.6 min | 1.9 |
| Bot Bay | (before the robot) | 23.2 min | |
| First robot | 9.4 min | 23.7 min | 2.5 |
| Base level 2 | city 2 | 32.6 min | |

Other acceptance numbers from the same run:
- **Purchases:** 29 in the first 20 minutes; longest wait 172 s (limit 120 s). FAIL by 52 s. It falls while saving for the tower.
- **Most cubes held:** 608 in the first 20 minutes, 1,305 in the whole run (113 game minutes). Proposal's city 1 limit: 5,000. PASS.
- **Income:** 2 to 7 cubes a second through the first 40 minutes (proposal: 14 on average over city 1).
- **Parts:** 6, 13 and 17 on hand at game minutes 5, 10 and 15: about 1 a minute, so the first robot's 10 Parts are in hand before its 800-cube Bot Bay. In this run cubes, not Parts, set the first robot's time.

Runs made while tuning (slightly different bot rules) gave a first hex at 85, 89, 98 and 103 s. Much of the spread is whether the bot walks off to dig a buried part during the first hex (about 18 s in the one run where I timed it).

**For a player** (twice the bot): first payout about 4 s, first upgrade about 30 s, first hex about 3 min 20 s (limit 3 min), then a hex about every 3 minutes (rule: every 2 to 3).

## 2. Why it is slower than the proposal, and what would close it

Measured on the bot's hand loop (`--hand-log`, new):
- **Sweeping is on target:** 12 units in about 3 s, the proposal's 4 units a second.
- **The trip is not.** The nearest dirty hex spans 5 to 15 m from the bin; the other ring 1 hexes are 13 to 30 m away. A loose tip costs 4 to 8 s there and back, against the proposal's 2.5 s. With the Baler the bot walks 25 to 30 m to the scale for every one or two bales.

**Distance needed (for the task that places the yard):** for the proposal's 2.5 s tip, junk must start within 4 m of the bin and the middle of the first hex must be within 8 m of it. Today the first hex's middle is about 10 m away and ring 1 averages about 17 m. The scale has the same need once the Baler is bought.

That only fixes the first hexes. From ring 2 on every hex is 17 to 35 m out whatever the yard looks like. The proposal reaches its pace there because its model has no distance. Closing that gap needs a design decision (haulers earlier than city 2, a bale drop point that moves with the work, or prices set from the game's real income): **question for the lead.**

What I changed toward it, inside this task: Lumi tips within 4 m of the bin body or on the weigh plate (was the plate only, 1.7 m); base speed 5.0 m/s (was 4.6); a chest level adds a whole starting chest (12); Lumi carries 2 bales from the start. I tried 6.0 m/s: no measurable gain over run-to-run noise, so it is back at 5.0.

## 3. What was built

| Rule | Where |
|---|---|
| A hex has a cube value | `core/hex_worth.gd` (new); `districts.json` `hex_cubes`, `hex_work`, `first_hexes`. A load's worth is its share of each hex it came from (`Compartment.worth`). City 1: 116 cubes a hex; ring 1 holds 120 units, ring 2 132, the rest 144 |
| Only waste down to the 95% line pays | `HexWorth.share_of`: a hex cleaned by hand from full pays exactly its value; the swept 5% pays nothing |
| Loose 1.0x, plain 1.15x, good 1.3x, perfect 1.5x | `Economy.evaluate_cube`, `press_quality`, `press_mult`; `patch.json` `cube`. "Good" (60% full or more) is my addition between the proposal's two. The pure-bale x2 and the overstuffed x0.8 are gone |
| Robots earn no cubes | Robot bales are worth 0 (`sphere_crew.gd`, `robot.gd`, `auto_baler.gd`); time away pays nothing (`core/offline.gd`); a hauler still pays Lumi for her own bales. Removed: clean-hex bonus, cubes for a hex's stage, garden stipend, wildlife trickle, cubes for field notes. `automation/cargo.gd` deleted (it paid cubes for remote robots and was never created anywhere) |
| City stage payouts | `systems/city_payouts.gd` (new): 116, 174, 348, 1,160, 1,392 for city 1, each once; saved; an old save is not paid for stages it already has |
| Track prices by city tier | `Economy.track_cost`, `upgrade_cap`; `upgrades.json` `tiers`. Scoop Speed 40, Scoop Size 40, Chest Size 50, ratio 1.6, 8 levels in city 1; the two scoop tracks have the same effect (+18%). A new city opens the next tier |
| The scoop lifts volume, not pieces | `patch.gd`, `Pace.pulse_volume`: 1.22 units a pulse times Scoop Size, 4 pulses a second |
| Goals pay when they complete | `story/goals.gd` `check` scans the whole chain every beat; the fold into the next card step is removed |
| Parts are scarce | `robots.json` `salvage`: a find pays 1 to 3 Parts, a buried part in one hex of three, stripping scaled so a heavier hex holds the same Parts. About 0.8 Parts a hex. Robots cost Parts only (Scoopie 10) |
| Builds and base levels cost cubes only | Baler 250, tower 500, Bot Bay 800, base level 2 700 (waits for the Bot Bay), then 1,100, 1,400, 1,800 |
| Whole numbers under 100,000 | `core/big_num.gd` |
| Whole cubes, nothing lost | `Economy.pay_whole_cubes` keeps the fraction for the next payout |

**Largest cube price reachable in city 1:** 4,500 (Auto-baler research; the research table is not rescaled, see section 5). Outside research: 2,500 (Signal Tower Mk IV). The dearest track level is 1,342 (Chest Size 8).
**Largest one-off reward in city 1:** 1,392 cubes (the city reaching Thriving). Limit: 2,520 (3 minutes at the proposal's 14 a second). At the income the bot actually has (about 5 a second, 900 in 3 minutes) the two last stage payouts are over the rule. Largest goal reward: 600, late in the chain; the first twelve goals pay 5 to 20.

## 4. The simulator agrees again

`--model=current` now reads hex weight and value from the districts table, lifts volume per pulse, pays goals as they complete, gives robot bales no value and knows the Bot Bay gate on base level 2. Its policy mirrors the bot's new rules. Six calibration constants moved (each with its reason in `tools/pace_sim/calibration.json`): `start_delay_s` 40 to 2, `trip_overhead_s` 8 to 3, `yard_parts` 70 to 4, `parts_luck` 0.5 to 1.0, `buried_find_share` 0.5 to 0.8, `garden_time_share` 0.37 to 0.2.

| Beat (min from control) | Bot | Simulator | Difference |
|---|---|---|---|
| First hex | 1.7 | 1.4 | -16% |
| Hex 2 | 3.4 | 3.0 | -12% |
| Hex 3 | 5.4 | 4.5 | -17% |
| Baler | 4.1 | 6.5 | **+58%** |
| Hex 5 | 7.8 | 7.4 | -5% |
| Clear the street | 10.1 | 9.7 | -4% |
| Signal tower | 12.6 | 14.0 | +11% |
| Bot Bay | 23.2 | 27.4 | +18% |
| First robot | 23.7 | 27.9 | +18% |
| Base level 2 | 32.6 | 31.9 | -2% |

Nine of ten within 20%. The Baler is not: the simulated player buys more early track levels before it than the bot does. Fitted to one run. `--model=redesign` is untouched and still passes its checks.

## 5. Not applied, and why

- **Base level 2 waits for city 2** in the proposal. Here it waits for the Bot Bay only: the story card needs it in city 1 and travel between cities belongs to M3-18.
- **Mastery, sources, field data, tending tracks, rigs:** the Bot Bay's "litter mastery 1" condition, Tending Reach, field data for a clean hex and source payouts need mechanics that do not exist.
- **Crew:** crew cap (8 at base level 1 in the proposal, 3 here), the robot price growth per robot (x1.2 Parts, a literal in `robots/fleet.gd`) and fleet upgrades still priced in cubes are M3-20's.
- **Research prices** are unchanged (up to 4,500 in city 1, 37,500 for the frontier nodes). A first rescale broke 30 research tests that count in the old unit; left for the research task. Field notes pay 0 cubes through a new `note_pay` key.
- **Parts outside city 1's loop:** Glim's tracks (6 to 140 Parts), outposts, the Ledger's jammer, the museum, the rocket and the Locker's style parts still use the old Parts scale. Event and request rewards were divided by 25.
- **Multipliers parked at neutral, to be decided:** Compactor Pressure (now city 2, +4% a level), the bin's level (pays 1.0x at every level), base levels (no sale bonus).
- **The recycler** now yields a quarter of a Part a bale and no cubes. It is still a way to turn a bale into Parts; whether it stays is a design call.
- **`data/workbench.json`** holds the bench tier prices and is shared, not a planet table. I changed the numbers there.
- **`docs/STYLE.md` section 10** still says numbers use `12.4k` with 4 significant digits. The game now shows whole numbers under 100,000.
- **New player-facing strings** ("GOOD BALE", "NEXT CITY", "Clear the street" and a few more) are not in the translation files.

## 6. Things to know

- **The bot changed, and the numbers above depend on it.** It works the hex nearest the bin (its old rule measured distance from the planet's centre, a leftover from the flat world), saves for what the card asks before dear upgrades, carries a full stack, and gives the garden at most a quarter of its time. Before the last rule it watered for 75 game minutes with zero income: with robots earning nothing, **Lumi's cubes stop whenever she is not sweeping** (the proposal's section 8.2, now real).
- **The Ledger's junk drops turn clean hexes dirty again.** The bot log shows the clean-hex count going down many times in a run. Not new, and not changed here.
- **Old saves:** a chest saved without a worth is paid by the unit as before; a robot's saved bale loads as waste; old Parts totals are kept, so an old save is rich in the new Parts scale.
- **Hex weights for cities 2 to 6** (340 to 4,600 units) are in the table as accepted. With today's tools nobody should clean a 4,600-unit hex by hand; they wait on those cities' mechanics.

## 7. Tests

970 pass (946 before; 24 new: `tests/test_economy_scale.gd` and two in `tests/test_sphere_crew.gd`). The save round trip passes. Tests whose expected numbers changed: `test_beat`, `test_big_num` (whole numbers), `test_camera_bot`, `test_ui6`, `test_onboard`, `test_stations`, `test_steam`, `test_hub` (cubes-only costs, the Bot Bay gate), `test_camp` (the bin pays 1.0x), `test_economy`, `test_pace` (track prices, press quality, start rate), `test_events`, `test_ui2`, `test_robot_builder`, `test_sphere_field_parity` (Parts scale), `test_extras`, `test_offline`, `test_qa_fixes_a`, `test_sphere_crew` (robots earn nothing), `test_hex_levels` (no stage cubes, no stipend), `test_hud`, `test_qafix` (no Parts from Lumi levels), `test_research` (notes pay no cubes), `test_v1guide_guidance` (goals pay at once), and `tools/orbit_roundtrip.gd`.
