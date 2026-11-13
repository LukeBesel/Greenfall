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
| hex2 | Clean 2 hexes (1 / 2) | yes: scoop key held on the outlined hex, 87 scoops | **the scoop never saw a piece lying over its hex's edge** (833 of 8540 pieces round the yard): the hex stalled at 58% with the piece 0.85 m ahead, no message | hex outline with % on the ground, count on the card | full chest / too heavy lines (existing) | FIXED | sphere_field.gd: the scoop searches the ring round its hex (sha 043c654) |
| hex3 | Clean 3 hexes (2 / 3) | yes (a robot's hex completes it) | the count moved by itself when a robot cleaned a hex out of sight, with nothing said | as hex2 | - | FIXED | a robot's hex during a "Clean N hexes" step toasts "Your robot cleaned a hex! It counts: 3 / 3" (at most every 20 s) |
| seed (after) | - | water: tool key 3 + button on the bed waters the seed | empty can away from the yard; no seeds left | GardenMarks (thirsty drop, soil, rings) present; not rendered | "Watering can is empty. Refill at the hub.", "Out of seeds. Blooming plants drop more." | OK | the can refills by itself within 16 m of the bench (no marker for that spot: "the hub" is the yard). Slope / 3:2 ring look NOT checked (no render) |
| hex10 / hex20 | Clean 10 / 20 hexes | same code path as hex2 (not walked again) | outline never picks a hex the lift can't clear (Pace.hex_clearable) | outline + count | "Too heavy. Upgrade Lift at the bench." on the card | OK | heavy pieces have no world marker of their own (only the line); not walked |
| base2 | Rebuild the base to level 2 | yes: interact at the bench opens on the base row; price-tag click | short of Parts | card: "Need 50 more parts. Dig up parts and salvage junk to get them." + count; row cyan, tag red | click while short: nothing built, the detail says the 50 Parts | OK | Parts come from electronics junk (6%), buried parts (detector), Lumi levels, events: junk is effectively endless, so no hard dry-out; can be slow |
| haul | Build a Haul Bug | yes: plans arrive, bench opens on the Haul Bug row, price-tag click | plans come only 20 min after the first robot and 8 hexes (or base level 3): nothing the player can do but wait | card had **no bar or number** while waiting; the bench opened on the Bots tab with no row picked | Haul Bug row LOCKED with its hint | FIXED | bar = how far the plans are (Research.story_progress); the bench opens on (and highlights) the Haul Bug row |
| tower2 | Boost the signal tower | yes: bench opens on the tower row; click | - | row cyan | - | OK | |
| research1 | Finish a research project | yes: Research Desk by click, Research tab click, project's price tag, it finishes | **completed itself**: the Bot Bay's free Salvage Logic counted as research_done, so the step flashed done before the Research tab existed; nothing ever pointed at the Research Desk (the tab is locked until bench tier 3) | card now: "First add the Research Desk: workbench, Upgrades tab." + cubes toward it; the bench opens on the desk row | short: price line | FIXED | Research.grant no longer counts; objectives.json `needs_bench: 3`; a save before the step gets the old count back down once |
| base3 | Rebuild the base to level 3 | yes: click | Parts 350 (as base2) | as base2 | as base2 | OK | |
| base3 -> Requests | (toast) | yes: Request Board by click, Requests tab click, 3 offers | **"New at the workbench: the Requests board"** fired at base 3 while the tab stays hidden until the Request Board (bench tier 4) | - | - | FIXED | the board opens with the Request Board; before that, once it can be bought, one line says where |

Not verified here: renders of these moments (no PNG looked at); save and reload in the middle of
each step (the new state lives in GameState flags and stats, which save, but no reload was played);
selling bales late in the game (scaling, tedium); the compost press and seed loop beyond "out of
seeds"; the plant and water rings on slopes and at a 3:2 window; walking to the bench (Lumi is placed
by it); controller input.

Walk note: in one full run (before the main merge) the research project's price-tag click did not
start it; it passed in the three runs since (alone and full). The walk prints the row state and
Research.reason when that check fails, if it comes back.

## Travel (rocket, stations, leaving)

Walk: `--walk-travel` (tools/walk_travel.gd). How the start states are made (dev, said in the file):
the card is set to the step, the price the step asks for is given (or half of it, to test the
refusal), the workbench is fixed and the tutorial is done. For the late part, stations 3-5 are woken
for free, Mk II is set and the home base is at level 5, as the card has them at that point. The
action under test is always real input: interact at the rocket, a left click on the row's Fly
button, interact to skip the flight, the scoop button held at the station's junk, interact at the
landmark, the outpost and the bench, clicks on "Upgrade the rocket", "Other planets" and "Build the
drive", Esc, and the key that closes the end card. Every click first checks that its button is in
view (on screen and inside its scrolling list). `--walk-travel-save` then `--walk-travel-resume`
reloads in the middle of station 2's chain. `--walk-travel-end` loads the save made after the end
card (Continue). All four runs are in tools/check_exit.sh. The full chain to the end on Verdance:
objectives hub_fly_2, hub_wake_2, (hex10, base2), hub_fly_3, hub_wake_3, (... hex20), rocket_tier_2,
(base3), hub_fly_4, hub_wake_4; goals hub_fly_5, hub_wake_5, (plant_25), rocket_tier_3, (drip_1,
base_5), hub_fly_6, hub_wake_6, home_drive_5, then the "to be continued" card. After that the goals go
on (perfect_1 ...) and the goals for other planets are hidden (data/homeward.json closed.hide_goals).

| step id | card text | completable by real input | stuck risks found | visual marker | refusal reasons | verdict | note |
|---|---|---|---|---|---|---|---|
| hub_fly_2 | Fly to the next station | yes: E at the rocket, a click on Fly by NEXT STOP, E skips the flight; control comes back 5 m from the pad; arrival title with the reason | **BLOCKER: E at the rocket did nothing** (its interact entry was registered before the yard's Interactables existed; the bot and the hub walkthrough call hop_to). Short of the station's price: no beam, so the player goes and earns. Flights are free, so a player is never stranded (flown home with 0 cubes) | beam on the parked rocket once the price is there; NEXT STOP tag in the list | card: "Need 300 more cubes, 30 more parts. Pick up trash to earn them." | FIXED | c6eb106: registration retried until it takes |
| hub_wake_2 | Wake station 2 of 6 (station card "Clean hexes here: n / 4") | yes: real scoops at the station take its junk (12-13 pieces in a few s); the rest by the crews' cell clean (dev); E at the landmark | **no hex was outlined and the beam stood on the landmark** during "clean 4 hexes" (the pad's town has no junk within 2 hexes; the card's hex search looked 2 rings out). **A Ledger dump on a cleaned hex took the count back** (3/4 after 4/4; the Ledger drops in the region Lumi is in). Save + reload mid-chain: back at Garden Row, card, count 2/4, rocket on its pad: OK | the hex to clean outlined (search goes out to 6 rings when 2 has none); beam on the landmark once the hexes are done; station card count; wake prompt "E   Wake the Windpump (600 cubes · 30 parts)" | E without the price: "Waking the Windpump needs 600 cubes · 30 parts." | FIXED | 56 of 66 dirty hexes within 6 rings of the pad can be outlined with Lift 0 (the walk checks at least 4 at each station it lands at) |
| hub_fly_3 / hub_wake_3 | Fly to the next station / Wake station 3 of 6 (+ "Repair an outpost here") | yes (same as station 2): fly by click; the outpost repaired by E once its hex is cleared, with the price | the outpost step had no beam (the beam stood on the landmark) | beam on the nearest ruined outpost; outpost prompt with its price | outpost prompt "clear its hex first (n% / 90%)", "(need more)" | FIXED | walked: beam on the outpost's kiosk, E with the price repairs it, then the landmark |
| hub_fly_4 / hub_wake_4, hub_fly_5 / hub_wake_5 | Fly to the next station / Wake station N of 6 | same code and data as stations 2 and 6 (HubPurpose chain from hub_defaults; no own chain); not walked by input | as station 2 | as station 2 | as station 2 | OK (audit) | `--hub-walkthrough` PASS: every station's town, landmark (39-58 m from the pad), open ground at its foot, E prompt, wake, gift, field bench, HUD 2/6..6/6 |
| rocket_tier_2 | Upgrade the rocket to Mk II | same code as rocket_tier_3 (story objective id branch); not walked | station 4 locked until Mk II | bench row (fixed) | the station's Fly button is off, with "Upgrade the rocket first" in its row | FIXED (audit) | |
| rocket_tier_3 | Upgrade the rocket to Mk III | yes: E at the bench opens on the rocket's row, a click on "Upgrade the rocket" | **the step had no target at all** (a goals.json stat step with key rocket_tier fell to "hex": no beam, no bench row); **the bench didn't open on the rocket's row** when that row appeared after the last fill (ListDetail.select_id used the stale list) | bench beam, rocket row selected | at Mk II the last station's Fly is off with "Upgrade the rocket first"; "Not enough cubes or parts" on the row | FIXED | |
| hub_fly_6 / hub_wake_6 | Fly to the next station / Wake station 6 of 6 | yes: as station 2 (rocket click, outline, landmark E) | as station 2 | as station 2 | "Waking the Tall Stack needs 200K cubes · 60 parts." | OK | |
| (station card after 6/6) | "All 6 bases stand. Fly home and make the rocket ready to leave." | - | **two instructions at odds**: the card said fly home while the beam stood on this station's rocket (the drive is built from any rocket) | - | - | FIXED | now "All 6 bases stand. Build the drive at the rocket." (6 languages) |
| home_drive_5 | Build the Mk V Orbital drive | yes: E at the rocket, click "Other planets", click "Build the drive" in the system map, Esc | **"Other planets" sat at the bottom of the scrolling hub list, out of view** once every station is listed. **The map opened on Verdance with no Build button** (the drive row showed only on the next planet, and Ochre is charted only after WREN's exit beat) | beam on the rocket; Build the drive button on the map | drive button shows its blocker in place of "Build the drive" | FIXED | Launch home / Other planets now under the list; the drive row shows on the current planet from the rocket, and the next planet is selected once charted |
| (end) | "To be continued" card | yes: it comes once WREN is done; E closes it; the next goal comes up (perfect_1); Lumi can move | **the E that closed the card also opened the rocket's list** (the card paused the game but never turned Lumi's input off) | full-screen card with the rocket and the home meters | - | FIXED | Continue (the post-end save loaded): no second card, drive and stations kept, Lumi by the rocket at Stack Works, can move |
| (arrival) | title: name, town and landmark, why we came | - | (clarity read) 3-4 toasts and a WREN line landed in the same 6 s on arriving and on getting home, so lines scrolled off | the title, then the station card and its marker | - | FIXED | cut: the hub's `hint` toast (it repeated the title's reason), "Home. The workbench is by the pod." and "The rocket waits on the pad. Home is first on its list." (the list shows HOME first). Kept: the title, and on a return visit one "N% clean, up M% while you were away" line. The rocket's how-to line uses the interact key's glyph, not a hard-coded E. A machine's reveal toast no longer says "Follow the light to it." (the light could be gone by the time the bench closed) |
| (travel between, home) | - | yes: home is always listed first (HOME), flown with 0 cubes | the rocket stays on the last pad; walking home leaves it there (the beam then has no rocket to point at until Lumi walks back) | - | - | OK | not walked |
| (base keepers) | arrival toast "N% clean, up M% while you were away" | not walked (BaseKeepers clears cells of woken stations while Lumi is elsewhere) | - | - | - | OK (code read) | not verified by a run |

Audits: `--hub-walkthrough` PASS (5 stations); `--target-reach` PASS. `--hex-audit-hubs` (r=110 m)
counts most far-station hexes as "stuck" only because it treats every piece over Lift 0 as stuck,
which is the start area's rule (HexLeftovers: big pieces count only where the hex should have none).
The card only outlines hexes the current Lift can clear (Pace.hex_clearable), and the walk checks
that at least four of those lie within 6 rings of each pad it lands at (Lift 0, stricter than a real
player at station 6). Colliders (junk under or inside things) are only loaded round Lumi, so they
were not audited for the far stations.

Renders (one rendered run of the walk, `--walk-travel-shots`; it runs at about 2 fps, so its own
checks time out and only the pictures count; screenshots/v9/travel_*.png in the v9c worktree): the
arrival at Garden Row reads well (big name, town and landmark, the reason, the rocket parked beside
Lumi). By the Windpump the station card shows "Wake the Windpump (600 cubes · 30 parts)", but **the
landmark's E prompt sits under WREN's subtitle bar** when she speaks (OPEN, the HUD layout is the
clarity helper's). After a wake that gives a design, the "New design unlocked" panel covers the
station card for a few seconds (OPEN, minor).

Not verified here: stations 4 and 5 and
rocket_tier_2 by input (same code, audited); the outpost repair on a station other than Gantry
Works; a controller; walking (not flying) home from a far station; the base keepers by a run;
the "Launch home" (Homeward) path, which is hidden while Ochre is closed.
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
