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
| hub_fly_3 / hub_wake_3 | Fly to the next station / Wake station 3 of 6 (+ "Repair an outpost here") | yes (same as station 2): fly by click; the outpost repaired by E once its hex is cleared, with the price | the outpost step had no beam (the beam stood on the landmark) | beam on the nearest ruined outpost; outpost prompt with its price | outpost prompt "clear its hex first (n% / 90%)", "(need more)" | FIXED | see the run note below for the walk result |
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

Not verified here: rendered shots of these moments (see the run note); stations 4 and 5 and
rocket_tier_2 by input (same code, audited); the outpost repair on a station other than Gantry
Works; a controller; walking (not flying) home from a far station; the base keepers by a run;
the "Launch home" (Homeward) path, which is hidden while Ochre is closed.
