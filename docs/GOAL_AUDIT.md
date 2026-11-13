# Goal audit (owner, 13 Nov: "all goals ... need to be visual and easy to understand and work")

Each helper's section: every step they own, played with real input (keys, mouse button, mouse
clicks on the workbench) on the round globe, by a walk in tools/walk_*.gd that runs in
tools/check_exit.sh.

## Home (garden, base, research)

Walk: `--walk-home` (tools/walk_home.gd; `--walk-home-only=hex2,base2,...` for one part). The state
at each step is set up by dev (said in the file): the step index, cubes and Parts at or just under
the price, the tower and bench tiers, a Scoopie. The action under test is always real input: the
scoop / tool keys and the mouse button held, the interact key at the bench, left clicks on the price
tag, the tab buttons and Close.

| step id | card text | completable by real input | stuck risks found | visual marker | refusal reasons | verdict | note |
|---|---|---|---|---|---|---|---|
| hex2 | Clean 2 hexes (1 / 2) | yes: scoop key held on the outlined hex, ~90 scoops; save + reload at 50% (Quit, Continue) and finished | **the scoop never saw a piece lying over its hex's edge** (833 of 8540 pieces round the yard): the hex stalled at 58% with the piece 0.85 m ahead, no message | hex outline with % (headless: set and the same after reload); NOT seen in a frame (Lumi faces away at the step start) | full chest / too heavy | FIXED | sphere_field.gd: the scoop searches the ring round its hex (043c654) |
| hex3 | Clean 3 hexes (2 / 3) | yes (a robot's hex completes it); reload (kill: autosave, no quit save) first | the count moved by itself with nothing said | as hex2 | - | FIXED | a robot's hex during a "Clean N hexes" step toasts "Your robot cleaned a hex! It counts: 3 / 3" (at most every 20 s) |
| seed (after) | was "3 then hold LMB to water it" over "Need 292 more cubes" | water key 3 + held button on the bed waters it; reload with the seed planted, not watered | **the water card was lost on load** (in memory only), so a reload left the seed with no instruction; it also stayed after watering and covered the next step; the step's price line sat under it | thirsty drop over the seed, water ring (frames 02/03, 15) | "Watering can is empty. Refill at the hub.", "Out of seeds. Blooming plants drop more." | FIXED | card: "Press 3 for the watering can, then hold LMB to water the seed" (binding glyphs), no price line under it, cleared once watered, back after a load. Rings only seen on flat ground: the nearest clean ground that takes a seed is 2 deg, so slopes are NOT verified |
| hex10 | Clean 10 hexes (8 / 10) | yes: Lumi one hex by scoop (reload at 50%, kill), 2 real Scoopies the last at time x8 (19 s real) | - | as hex2 | - | OK | |
| base2 | Rebuild the base to level 2 | yes: bench opens on the base row, price-tag click; reload while short of Parts and right after buying | the row said only "Workshop" under a card saying "base level 2" | card "Need 50 more parts..." + count; row (frame 06) | click while short: nothing, "Need 50 more parts" in red | FIXED | row now "Base level 2 · Workshop" (also level 3: "Depot Station") |
| haul | Build a Haul Bug | yes; reload while the plans come (bar kept) | wait with no bar (fixed in cc507ff) | % bar on the card; bench opens on the Haul Bug row (frame 08) | row LOCKED while waiting | OK | |
| tower2 | Boost the signal tower | yes; reload (kill) at the start | **after a load the bench opened on the wrong row and the tower row was missing** (the bench's cached rows were read while the load was building the yard, before the tower stood; select_id only re-read an empty list) | bench on Signal Tower Mk II (frame 10) | - | FIXED | ListDetail.select_id re-reads the rows when the id is not in them |
| research1 | Finish a research project | yes; reload with a project running (same project, time left within 3 min) then it finishes | **a double click on a project's price tag started it and then cancelled it** (the second click hit the row's new "Cancel (refund)") | card: "First add the Research Desk..." + cubes toward it (frame 11); bench on the desk (12) | price line | FIXED | ListDetail ignores a second act on the same row within 450 ms. (The walk's own click was delivered twice: the old flaky miss) |
| hex20 | Clean 20 hexes (18 / 20) | yes: Lumi one hex (reload at 50%), 3 Scoopies the last (9 s real at x8) | - | as hex2 | - | OK | |
| base3 | Rebuild the base to level 3 | yes; reload at the start | as base2 | as base2 | as base2 | OK | |
| base3 -> Requests | (toast) | yes: Request Board by click, tab click, 3 offers; reload (kill) with the board bought and no request taken: same board, tab opens | (fixed in cc507ff) | Requests tab (frame 17) | - | OK | |
| out of order | - | base 2 / 3 bought early, a Haul Bug built early, a project done early: each step passes by itself; base 3 brings the Haul Bug plans at once | none found | - | - | OK | |
| too heavy (outside the start area) | (situation line) | aiming the scoop at a large piece 70-130 m out with Lift 0; a hex scooped of everything liftable | a heavy piece had only a passing float text; a hex that Lift 0 can't finish said nothing once the liftable pieces were gone | **new**: orange ring on the piece + "Needs Lift N" over it, kept 3 s after the scoop last found it (frame 540/17) | card: "Too heavy: this needs Lift 2. Upgrade at the workbench." / "This hex needs Lift 2 to finish. Upgrade at the workbench." | FIXED | Pace.heavy_hint / hex_stuck / hex_need, Vfx.heavy_mark |

Save and reload: 12 reloads in `--walk-home` through the real path (odd: pause key, Quit, the title's Continue; even: autosave, the game dropped without a quit save, Continue), comparing the card, count / bar, outlined hex, bench row and beam, plus per-step values. `--walk-home-noreload` skips them; `--walk-home-shots=/abs/dir` (rendered) saves the frames.

Frames: screenshots/home_540 (960x540) and screenshots/home_1500 (1500x1000), Low preset. Seen: bench rows, cards, water card, thirsty drop, rings on flat ground, the heavy mark. Not my area but seen: a 40-60 m start-town city block 25-30 m from the bench (`.../VerdanceSite_start_yard/City/@MeshInstance3D@...`) renders as a flat black box at Low (frames 04, 05, 15).

Not verified: the outlined hex in a frame; plant/water rings on a real slope; selling bales late in the game; the compost press; walking to the bench (Lumi is placed by it); controller input.

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
| hex_level, plants_*, garden_stipend, hexes_restored | Get a hex to Planted, Plant 25 seeds ... | not played | - | was: the "hex" target outlined a DIRTY hex (and the autoplay log showed "Get a hex to Planted" with no beam and "Nothing to pick up here. Walk to more trash.") | - | FIXED | story/objectives.gd `_grow_target`: the beam stands on the nearest clean hex still under the goal's level; "hex" only while nothing is clean |
| decor_* | Place a decoration (H) ... | not played | Garden Mode opens at base level 5 | none | - | OPEN | the "(H)" in the goal text is fixed, not the player's binding; proposal: `{garden_mode}` glyph in goal text |

Verdicts: 1 blocker FIXED (tank_1); FIXED 5 more rows; FIXED (risk) 1; OK 6 (3 played by real input in --walk-goals: stat, earned, upgrade; 3 static); OPEN 2 (the cat walk, the decor key text).

### Part 2: clarity sweep (first two hours)

Source: `--autoplay --time-scale=8 --clarity-log` to 93 game minutes (station 5 woken; 421 card
changes, 69 toasts shown, 47 WREN lines, longest empty card 0 s), screenshots/v9d_clarity.log;
the frames of tools/step_shots.gd (screenshots/v9/step_NN_<id>.png); a code search of player
actions for refusals with no line. Owner column: whose step it is (opening = intro..first robot,
home = hex2..base3, travel = stations / rocket, me = shared UI, goals, events).

| where | finding | kind | owner | verdict | note / proposal |
|---|---|---|---|---|---|
| bale key (C / RMB) on an empty chest | buzz only, no words | silent refusal | me (player action) | FIXED | toast "Your chest is empty. Scoop some trash first." (6 languages) |
| survey map: resurvey with too few cubes | buzz only | silent refusal | me (shared UI) | FIXED | toast "Not enough cubes" |
| bench: a click on a row the player can't afford | buzz; the row's price tag is red ("short") | refusal shown, no words | me (shared UI) | OK | the detail panel names the cost; --walk-goals checks nothing is bought |
| Glim scan (F) while it cools down | buzz only | silent refusal | me | OPEN | proposal: a short "Glim is still scanning" float text |
| bale key while pieces are still flying in | nothing | silent (lasts < 1 s) | me | OPEN (minor) | |
| world events: robot hiccup, wildlife photo | toast and HUD hint said "press E" whatever the binding | wrong key | me (events) | FIXED | data/events.json uses `{interact}`, systems/events.gd runs Tutorial.glyphs (translations moved over) |
| goal "Place a decoration (H)" | key fixed in the text | wrong key on rebind / pad | me (goals) | OPEN | proposal: `{garden_mode}` in the goal text, and Tutorial.glyphs on the goal card |
| goal steps at the radio, nursery, locker | the beam stood on the workbench | wrong marker | me (goals) | FIXED | beam on the build |
| planting goals | dirty-hex outline + "walk to more trash" | wrong marker | me (goals) | FIXED | beam on a clean hex |
| "Workbench fixed. Press E at it..." (scenes/slice_orbit.gd), "Walk to the rocket ... press E" | fixed key in toasts | wrong key on rebind / pad | opening / travel | OPEN | same `{interact}` + Tutorial.glyphs fix |
| 0.1 min: card "Bring your chest to the trash bin" while the beam stands on the bench | card and beam disagree | two instructions | opening | OPEN | |
| Repair Glim, Bot Bay, first robot steps | the card's situation line swaps every few seconds between "Need N more cubes" and "Carry your bale to the scale" | two messages | opening | OPEN | proposal: keep the line for at least 6 s, or show only the bale line while a bale is carried |
| seed step after planting | card "3 then hold LMB to water it" (the word "Press" is missing before the key) with "Need 292 more cubes" under it | unclear text, two messages | home | OPEN | |
| "Fly to the next station" | the why line names the NEXT station's reason ("The seed tin is nearly empty...") with a cube count | ok, but 2 lines + count | travel | OK | |
| station arrival / return home (22.1, 29.8, 30.2 min) | 3-4 toasts and a WREN line inside 6 s ("Home...", "Hub upgraded", "Compost Press built. Follow the light to it." while the beam shows nothing) | two messages at once; words-only marker | travel | OPEN | proposal (toast system): queue toasts so a new one waits until the last has shown 2 s; the notify stack keeps 3 rows and fades the oldest when over 3 lines, so a burst hides the first lines at once |
| "Rocket piece: Seed Stock · +30 Seeds · New: Wild Mint · The recycling network grew: everything sells for x3.5 now." | 22 words, cut at 2 lines | text too long | travel | OPEN | split into the piece line and the trade line |
| world event toasts (Salvage Surge 18 words, drone 21 and 26, wildlife 19, rain 17) | over ~12 words | text too long | me (events) | OPEN | proposal: "Salvage Surge! A glowing hex north of you: 3x cubes." etc. (needs 6 translations each) |
| WREN station reasons (hub_wake_3/4/5: 13-16 words) | over 12 words on the card | text too long | travel | OPEN | |
| story card titles and why lines | all 12 words or fewer | - | all | OK | data/objectives.json checked |
| objective card (every step) | words and a count only: no picture on the card | VISUAL | me (card widget) | FIXED | ui/objective_card.gd `icon_of`: a glyph per kind of work (scoop, cube, part, data, seed, plant, star) left of OBJECTIVE; tests/test_goal_audit.gd checks every step and goal gets one and the story uses several |
| objective card + base banner, 960x540, first frame | the base banner ("LANDING YARD 0% CLEAN / BASES 1/6") showed through the card's bottom edge as the card first appeared | overlap (transient) | me (HUD column) | OPEN | not seen in later frames nor at 1500x1000; `--ui-audit` at 1500x1000 and 960x540 (en, de): 0 issues |
| world signs (shop names, OLD TOWN, slogans), WREN / LEDGER name tags, robot tags | not translated (`--locale=pseudo --l10n-audit`: 24 texts) | text skipped tr() | world art | OPEN | names and tags are fine as they are; the shop and slogan signs go against "picture signs with no words" (ART_KIT) or need tr() |


Renders (opengl3, Low, one at a time): `tools/shot.sh v9/steps_last --orbit --no-intro
--step-shots=6 --step-shots-at=80` writes screenshots/v9/step_NN_<id>.png (960x540; steps 4-12 and
goals 0-1 were re-shot at 1500x1000 with the card picture: `RES=1500x1000 ... --step-shots-from=4
--step-shots-to=12`) and contact sheets screenshots/v9/sheet_N.png. The frames are taken from the
start position with the card jumped to each step (world state not advanced), so they judge the
card and the HUD, not each step's world marker: the beam, hex outline and target markers of each
story step are the story helpers' walks to check. What they show: every card has a title, a why
line and (where the step counts) a count and bar; before this audit no card had a picture.

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
