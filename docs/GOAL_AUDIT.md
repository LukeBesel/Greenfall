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
