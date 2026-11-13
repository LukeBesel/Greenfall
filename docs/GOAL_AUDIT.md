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

## Opening (to the first robot)

Walk: `--walk-opening` (tools/walk_opening.gd): `godot --headless --path . -- --fresh --orbit --intro --walk-opening`.
From a fresh game: the intro (Space pauses, Space resumes, Esc skips), the first-minutes key strip,
the restart checklist, then every story step to the first robot. Lumi walks with W/A/S/D in the
camera's frame (to the bench, the bin, the scale, each piece of junk, a buried part), scoops with
LMB held, presses bales with RMB, picks them up with E, opens the bench with E and closes it with Tab,
and buys by clicking the price square or the detail panel's button. Saving up past one or two real
loads or bales is a dev top-up to the step's price (logged as `note: top-up`); the autoplay run
reaches every one of these prices by playing (first robot at 15.6 bot min, 300+ Parts by then).

| step id | card text | completable by real input | stuck risks found | visual marker | refusal reasons | verdict | note |
|---|---|---|---|---|---|---|---|
| intro | (cinematic) | yes: Space pauses, Space resumes, Esc skips; the card comes and Lumi moves | the Esc that skips does not also open the pause menu | letterbox, "Space pause / Esc skip" hint | - | OK | headless runs need `--intro` |
| checklist | Fix the bench (E) / Pick up trash (hold LMB) / Bring your chest to the trash bin / Buy an upgrade | yes | **the bin did not take the chest where the beam points** (see dump3); **the beam stayed on the bench** while the card already said "Bring your chest to the trash bin" (it was only refreshed once WREN's brief revealed the card) | beam on the bench, then none while picking up, then on the bin; count 3 / 8 | - | FIXED | "Buy an upgrade" needs a few loads first (no upgrade costs less than 35 cubes); the card shows dump3 meanwhile. "Workbench fixed" named a fixed E on the globe: it uses the bound key now |
| dump3 | Fill the trash bin 3 times | yes | **blocker:** the globe has no trash-bin node, so the chest emptied only within 1.7 m of the scale's centre, while the beam stands on the bin body 3.3 m away. Walking up to the bin (stopped at 1.0 m by its body) did nothing unless the player crossed the scale | beam on the bin while the chest is full, else the dirty-hex outline; 1 / 3 | - | FIXED | `automation/depot.gd` also empties the chest within `Pace.BIN_RADIUS` of the bin body |
| compartment | Buy a bigger chest | yes: click on the price square | spending the cubes on something else first (Scoop Speed): the card then says "Need 35 more cubes. Pick up trash to earn them.", points out to the junk, shows 0.97 / 35, and the bin still pays | beam on the bench once affordable; the bench opens on Chest Size, its row framed cyan | a click on a price you can't pay buys nothing, buzzes, and the detail says "Need N more cubes" | OK | a buried part lies by the bench on this seed: there E digs first (the prompt says "dig"), the next E opens the bench |
| scoop_size | Buy Scoop Size | yes: the detail panel's Install button | as above | as above | as above | OK | |
| baler | Save up for the Baler | yes | as above | as above | as above | OK | the buy says how to make a bale (toast) |
| power | Sell 3 bales | yes: RMB presses, E picks up, walk onto the scale | **after the Baler a chest walked to the bin got no word at all** (the bin takes no loose trash then) | beam on the scale while a bale is carried; "1 / 3"; the card names RMB | now "No loose trash now. Press [RMB] for a bale, then put it on the scale." | FIXED | bales always earn more, so no cube state blocks the later prices |
| tower | Build the signal tower | yes: Build tab, click | can be built early (it's in the Build tab from the start): the step is then skipped | beam on the bench once affordable; the bench opens on Build, Signal Tower | short price: as above | OK | |
| glim | Repair Glim | yes: Build tab, click; the repair plays and control comes back | **saving up showed no price, no count and no "need" line** (only "Build tab" and a hex outline): 80 cubes and 10 Parts with nothing saying so. On this and every step with a price (Bot Bay, first robot) **the hint flipped** between "Need N more cubes" and "Carry your bale to the scale": the missing price wins now | beam on the bench once affordable | now "Need N more cubes / parts ..." and "20 / 80" | FIXED | Parts: E on the detector's spot digs one up (+10, played) |
| hex | Clean the glowing hex | yes: LMB held on the outlined hex's junk to 100% (bales pressed with RMB when full) | none found: the start-area audit (`--hex-audit`) passes | the hex outline on the ground and its % on the card | - | OK | |
| bench2 | Add a Bot Bay to the bench | yes: click | before a clean hex the row is locked with "Clean 1 hex first." | beam on the bench; cubes / price on the card | locked reason, short price as above | OK | the 40-Part robot kit is paid and the Bots tab opens |
| robot | Build your first robot | yes: Bots tab, click on the Scoopie's price | Parts spent elsewhere: the card says how many are missing and how to get them | beam on the bench; the bench opens on Bots, Scoopie | as above | OK | the next step (Clean 2 hexes) comes at once |

Other checks in the walk: the first-minutes key strip (M map, V lens, G goals) shows the keys that are
bound, and each does what it says (M opens the map; M or Esc closes it and Lumi moves again).

Not verified: renders of each step's start (only headless state: beam target, outline, card text);
the controller mapping; save and reload in the middle of a step; a full real-input grind (cubes past
two loads or bales are a top-up).
