# M3-10 Goals in three tiers (Nov 11, 2026)

Task row: always one goal of each tier active; no gap over 4 minutes without a goal finishing in the bot run.

## What was built
- **Three tiers from planet data** (`planets/verdance/data/goals.json`, `tiers[]`): `short` (label NOW), `medium` (CITY), `long` (PLANET). 115 authored goals plus 8 repeating ones:
  - NOW: 41 authored (first trash, bin, bale, sale, perfect bale, Lift, Chest, first Surge, zoning, planting stages, each city's rig tool, each new kind learnt by hand, Scrounger, Assembler, Skimmer, Drip, Locker) and 6 repeating jobs (more hexes, bales, Surges, growth, Parts, perfect bales) that count side by side; the row shows the one nearest done. Patience 180 s: an authored NOW goal with no progress for 3 minutes steps aside (still pays).
  - CITY: 65 authored (litter mastery 2 to 10, each city's stages 1 to 5, each source job, each later kind's mastery 3 and 5, crew 2 to 150) and 2 repeating ones.
  - PLANET: 9 (Old Town restored, 3 of 6 cities, the launch point, the Sprout set, 1/5/25/50/100% of the planet).
- **Rules** `story/goals.gd`; measures `story/goal_measures.gd`; guidance `story/goal_guide.gd` (every goal has a beam target; a goal's `guide` entry overrides its type); HUD `ui/goal_readout.gd` (one plate, one row per tier, stamped DONE then the next slides in, 160 ms); `ui/goals_panel.gd` (G steps the beam through the goals and back to the card).
- **The story card stays the first guide**: story steps, then a city's source job, then the NOW goal. The readout leaves out the row the card is carrying.
- **Removed**: 114 old goal ids that pointed at parked or side systems (frontier districts, late garden, extras, shards, cats, builder, tanks/heaters/greenhouses, old rocket) or duplicated the card.
- **Old saves**: finished ids stay finished; goals new to the save that already hold are marked done without a payout (no reward burst on load).
- **A city-stage goal's gauge fills with the city's share** of the way to the next stage, so "Restore Old Town" moves from the first hex instead of reading 0 / 5 for half an hour.
- **Simulator** (`tools/pace_sim`): one goal per tier on screen; only goals on offer pay, as in the game.

## Bot (two fresh runs, `--fresh --autoplay --time-scale=4 --quit-after=420`, about 25 game minutes)

| Tier | Run 1: done / longest gap | Run 2: done / longest gap |
|---|---|---|
| NOW | 39 / 2.3 min | 42 / 1.9 min |
| CITY | 7 / 5.5 min | 8 / 4.1 min |
| PLANET | 0 / whole run | 0 / whole run |
| All tiers | 46 / **2.0 min** | 50 / **1.9 min** |

No tier ever stood without an active goal (0.0 s in both runs). No script errors.

City 1 pacing (seconds from control): first hex 85 and 56 s (limit 90), first robot 9.4 and 8.2 minutes (limit 12). Simulator: first hex 62 s, first robot 9.2 minutes.

## Tests
`tests/test_goals.gd` (29 tests, both planets where it applies): tiers from data, one active per tier, next of the tier takes its place, pay at once and one per beat, offer gates, patience, repeats, guidance for every goal, card stays primary, follow key, readout rows and reveal, titles fit, old-save migration, the bot's gap table, the city-stage gauge. Save round trip checks goals per tier and repeat counts.

HUD shot: `screenshots/goals/hud.png` (1280x720, opengl3). The readout was 340 px wide under a 300 px card; it now matches the card, so the column reads as one instrument.

## Open calls
- **PLANET finishes nothing in the first 25 minutes.** By design (hours), and its gauge now moves; the lead may want an earlier first long goal (for example "Bring Old Town to Planted" as a planet step).
- **Purchase waits of 155 and 198 s** at minutes 14 to 20, after the first robot (M3-09 saw 157 s in the same stretch). Not from goals (early rewards are 5 to 30 cubes); for M3-12.
- **The simulator's goal-gap check still fails** (372 s) because it does not model repeating goals; the bot is the measure for this rule.
- New strings are not extracted (as instructed); `test_full_translations_complete` may fail until they are.
- Originality: tiered goal lists are common in the genre; the tiers, labels and contents come from Greenfall's own cleanup and regrowth.
