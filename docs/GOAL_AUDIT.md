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
