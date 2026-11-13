# Goal audit (13 Nov 2026)

Owner, item 86: "Can you do another audit of the game? I need to make sure all goals and all that
work because for example getting stuck on the seeds essentially ruins the entire game because you
cannot move on. It all needs to be visual and easy to understand and work."

Each helper writes its own section below.

## Side goals and clarity

Tools: `--walk-goals` (tools/walk_goals.gd, in tools/check_exit.sh), tools/goal_audit.gd
(tests/test_goal_audit.gd), `--step-shots` (tools/step_shots.gd: a rendered frame as each story
step starts, one run).

### Part 1: every side goal can be completed

The goal chain (data/goals.json, 122 goals left on Verdance after this audit) runs ONE goal at a
time on the objective card once the story is done (story/objectives.gd `_goal_index`). A goal that
can never complete therefore hides every goal after it: it is a dead end, not just a missed
reward. GoalAudit checks every goal and every shown achievement (88): the condition type is one the
round game reads, the stat or flag is written on the globe (a named source per key; an unknown key
fails), the target is within what Verdance has (research projects open: 34, eggs the globe places:
31 over 10 hubs, hubs, base level 5, crew cap, upgrade max, rocket tiers, drive Mk V while the next
planet is closed), the builds it needs are offered, and nothing reads content hidden in this
release (any key a hidden achievement reads, at that target or more).

| goal / kind | card text | completable by real input | stuck risks found | visual marker | refusal reasons | verdict | note |
|---|---|---|---|---|---|---|---|
| tank_1 | Place a Water Tank | no | stat water_tanks is written only by the flat WaterNet; SphereFleet has none: the chain stopped here for good (plant_60 and 80 later goals never showed) | - | - | FIXED (BLOCKER) | removed from data/goals.json |
| late_eggs_38 | Find 38 curiosities | no | the globe places 31 eggs | - | - | FIXED | removed |
| late_eggs_30 | Find 30 curiosities | yes, in theory | 30 of 31: one egg that fails to place (TargetReach) makes it impossible | eggs glow | - | FIXED (risk) | moved to the end of the chain, so it can block nothing |
| ark_1, ark_3, late_ark_5, late_bridge, late_heirloom_1, late_heirloom_10, late_world_1, late_world_2 | Seed Ark / Ark Bridge / Heirloom / new world | no | need the Cradle's answer (Verdance Bloom), closed in this release like their achievements | - | - | FIXED | added to data/homeward.json closed.hide_goals |
| achievement late_eggs_40 | Cabinet of Curiosities (40) | no | 31 eggs | - | - | FIXED | added to closed.hide_achievements |
| stat junk_scooped | Pick up 15 pieces of trash | yes (walk: scoop button held at junk) | - | junk itself; the card count | - | OK | counter 0 -> 6 in 2.5 s |
| stat junk_dumps | Empty your chest in the bin | yes (walk: move key into the bin) | - | beam on the bin when the chest has junk | chest full: buzz + meter shake + "Your chest is full..." | OK | |
| earned | Earn 1,000 cubes (and 6 more) | yes (walk: the bin's cubes count) | - | count | - | OK | |
| upgrade | Chest Size level 3, Lift 1/2, Baler | yes (walk: E at the bench, click on the row) | - | beam on the bench; the row is pre-selected | no cubes: row shows "short", click buzzes, nothing bought | OK | a click on a row's price tag buys at once (ui/list_detail.gd) |
| stat cats_petted | Pet a stray cat | not played: no cat came to the start hub in 60 s of a fresh game | cats come with clean (level 1+) city hexes; none early | "hex" outline (a dirty hex) | E on a cat: purr | OPEN | needs a walk from a later save |
| flag seeds_unlocked, first planting | Find the seed tin, Plant the Settler seed | yes | - | beam on the tin, then the beds | yes | OK | played by tools/seed_walk.gd (v8seed) |
| stat radio_plays, robots_retired, builder_* | Pick a song on the base radio / Retire a robot / Style a robot in the Locker | not played | - | beam pointed at the workbench, not the radio / nursery / locker | - | FIXED | story/objectives.gd YARD_STATS: the beam stands on the build once it is built (the bench before, to build it) |
| stat bales_recycled, air_filtered | Recycle 5 bales / Filter 1,000 m3 of air | not played | written by the Recycler (Stations on the globe) and the Air Scrubber, both bench builds | depot / hex | - | OK (static) | the audit checks the builds are offered |
| robot, tier, hub_level, research, districts, hubs_* | Build a Scoopie ... Launch the rocket onward | not played here | - | beam on the bench / rocket / landmark | bench rows | OK (static) | the story walks (opening, home, travel) play the same conditions |
| hex_level, plants_*, garden_stipend | Get a hex to Planted ... | not played | - | the "hex" target outlines a DIRTY hex: planting needs clean ground | - | OPEN | proposal: no outline for planting goals (as the seed step after the tin), or outline the clean hex with the most free slots |
| decor_* | Place a decoration (H) ... | not played | Garden Mode opens at base level 5 | none | - | OPEN | the "(H)" in the goal text is fixed, not the player's binding; proposal: `{garden_mode}` glyph in goal text |

Verdicts: 1 blocker FIXED (tank_1), 4 more FIXED, 1 FIXED (risk), OPEN 3 (cat walk, planting-goal outline, decor key text).

### Part 2: clarity sweep (first two hours)

(see below)

### Part 3: softlock sweep by resource

| resource | sources on Verdance (always renewable?) | can the story's need be spent / sold / destroyed for good? | verdict |
|---|---|---|---|
| cubes | the bin and the scale (any junk, every hub), goal and event rewards, garden stipend | spent on upgrades only; junk is everywhere on the globe and robots keep cleaning | OK |
| Parts | salvage while scooping (part_drop chance per junk type), digging (detector), Recycler, events, Requests, nursery hand-backs, Lumi level | spent on the Bot Bay, robots, tiers, Locker; scooping always pays more | OK |
| seeds | the tin (and a seed is given back on load if a save sits at none, story/first_seed.gd), SeedFinds while scooping, the compost press, blooming plants, rewards | planting spends them; "Out of seeds" line says where more come from | OK (the line names blooming plants, not scooping) |
| water | the hub's barrel refills the can anywhere in the yard | never runs out at the barrel; "Watering can is empty. Refill at the hub." | OK |
| bales | pressed from any chest of junk (after the Baler) | sold at the scale; always more junk | OK |
| robots | built at the bench from Parts | retiring one at the nursery removes it, but steps count robots of the type now (robot, haul): rebuilding is always possible | OK |
| chest space | the bin (before the Baler), the bale key (after) | full chest: buzz, meter shakes, line says what to do | OK; the bale key on an EMPTY chest said nothing: FIXED ("Your chest is empty. Scoop some trash first.") |
