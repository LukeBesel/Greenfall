# Goal audit (owner, 13 Nov)

Owner: "Can you do another audit of the game? I need to make sure all goals and all that work because
for example getting stuck on the seeds essentially ruins the entire game because you cannot move on.
It all needs to be visual and easy to understand and work."

Each area is played the way a player does, with real input (keys, mouse buttons, aim, clicks on the
real workbench buttons), by a walk tool that runs in `tools/check_exit.sh`.

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
| checklist | Fix the bench (E) / Pick up trash (hold LMB) / Bring your chest to the trash bin / Buy an upgrade | yes | **the bin did not take the chest where the beam points** (see dump3) | beam on the bench, then on the bin; count 3 / 8 | - | FIXED | "Buy an upgrade" needs a few loads first (no upgrade costs less than 35 cubes); the card shows dump3 meanwhile |
| dump3 | Fill the trash bin 3 times | yes | **blocker:** the globe has no trash-bin node, so the chest emptied only within 1.7 m of the scale's centre, while the beam stands on the bin body 3.3 m away. Walking up to the bin (stopped at 1.0 m by its body) did nothing unless the player crossed the scale | beam on the bin while the chest is full, else the dirty-hex outline; 1 / 3 | - | FIXED | `automation/depot.gd` also empties the chest within `Pace.BIN_RADIUS` of the bin body |
| compartment | Buy a bigger chest | yes: click on the price square | spending the cubes on something else first (Scoop Speed): the card then says "Need 35 more cubes. Pick up trash to earn them.", points out to the junk, shows 0.97 / 35, and the bin still pays | beam on the bench once affordable; the bench opens on Chest Size, its row framed cyan | a click on a price you can't pay buys nothing, buzzes, and the detail says "Need N more cubes" | OK | a buried part lies by the bench on this seed: there E digs first (the prompt says "dig"), the next E opens the bench |
| scoop_size | Buy Scoop Size | yes: the detail panel's Install button | as above | as above | as above | OK | |
| baler | Save up for the Baler | yes | as above | as above | as above | OK | the buy says how to make a bale (toast) |
| power | Sell 3 bales | yes: RMB presses, E picks up, walk onto the scale | **after the Baler a chest walked to the bin got no word at all** (the bin takes no loose trash then) | beam on the scale while a bale is carried; "1 / 3"; the card names RMB | now "No loose trash now. Press [RMB] for a bale, then put it on the scale." | FIXED | bales always earn more, so no cube state blocks the later prices |
| tower | Build the signal tower | yes: Build tab, click | can be built early (it's in the Build tab from the start): the step is then skipped | beam on the bench once affordable; the bench opens on Build, Signal Tower | short price: as above | OK | |
| glim | Repair Glim | yes: Build tab, click; the repair plays and control comes back | **saving up showed no price, no count and no "need" line** (only "Build tab" and a hex outline): 80 cubes and 10 Parts with nothing saying so | beam on the bench once affordable | now "Need N more cubes / parts ..." and "20 / 80" | FIXED | Parts: E on the detector's spot digs one up (+10, played) |
| hex | Clean the glowing hex | yes: LMB held on the outlined hex's junk to 100% (bales pressed with RMB when full) | none found: the start-area audit (`--hex-audit`) passes | the hex outline on the ground and its % on the card | - | OK | |
| bench2 | Add a Bot Bay to the bench | yes: click | before a clean hex the row is locked with "Clean 1 hex first." | beam on the bench; cubes / price on the card | locked reason, short price as above | OK | the 40-Part robot kit is paid and the Bots tab opens |
| robot | Build your first robot | yes: Bots tab, click on the Scoopie's price | Parts spent elsewhere: the card says how many are missing and how to get them | beam on the bench; the bench opens on Bots, Scoopie | as above | OK | the next step (Clean 2 hexes) comes at once |

Other checks in the walk: the first-minutes key strip (M map, V lens, G goals) shows the keys that are
bound, and each does what it says (M opens the map; M or Esc closes it and Lumi moves again).

Not verified: renders of each step's start (only headless state: beam target, outline, card text);
the controller mapping; save and reload in the middle of a step; a full real-input grind (cubes past
two loads or bales are a top-up).
