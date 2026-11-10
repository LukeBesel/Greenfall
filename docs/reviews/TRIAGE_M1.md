# M1-01 bug triage (Nov 10, merged build, round planet only)

Build: `worktree-agent-a9ff469a71dce40d3` with `claude/greenfall-aurora` merged (flat world removed, six designs merged). Rows marked "verify" in `docs/PLAN.md` section 6, plus B23 and whatever turned up. Severity: P1 blocks finishing or loses progress, P2 hurts the experience, P3 cosmetic.

Every status below was re-run on the merged build. Failing tests live in `tests/test_triage_m1.gd`, each marked `pending("B# ...")` after it was seen to fail, so the suite stays green until the fix lands. Remove the `pending` line and the `return` under it to see the failure.

## 1. Results

| Bug | Sev | Status | Evidence | Suspected cause | Suggested fix |
|---|---|---|---|---|---|
| B2 reload resumes from the autosave | P1 | Fixed already | `tools/exit_probe.tscn` write then read (commands in the tool's header): exit at 206 s, last autosave 181 s, reload matched the exit moment on all 22 keys (cubes, cells, carried bale, Lumi's place, upgrades). `tools/check_exit.sh` passes | - | - |
| B3 / B24 hex sticks below the clean rule | P1 | Fixed (`Fix B24: the junk keep-out registered a footprint only in the hash boxes its sample points fell in`) | `tools/hex_stick_probe.tscn -- --fresh`: cell 153095, 149 m from the start, 5.0% of its junk can never be scooped, the rule sweeps 5%. Test `test_b3_keep_out_covers_a_whole_building_footprint` (97 and 238 unblocked spots inside a 24 m footprint) | `planet/sites/yard_keep_out.gd:121-142` registers a footprint only in the hash boxes its sample points fall in, and `:152-164` looks in one box. A tilted footprint crosses boxes no sample landed in, so junk is laid there, inside the building's collider | Register every hash box the grown footprint overlaps (or look in the neighbouring boxes too) |
| B4 / B25 objective chain stalls | P1 | Fixed (`Fix B25: step 1 counted only loose bin trips, which the Baler ends for good`) | Section 2. Test `test_b4_baler_bought_before_the_third_bin_trip_does_not_strand_the_bin_step` | `core/pace.gd:222-227`: with the Baler fitted the bin takes no loose loads (`data/patch.json` `dump.after_baler` false), so `junk_dumps` stops below 3 for good. The Baler has no prerequisite and costs 80 cubes | Count a sold bale as a bin trip for step 1, or keep loose dumping until step 1 is done, or hide the Baler until step 1 is done |
| B6 lake blocks the way before Hover Jets | P2 | Not reproduced as a blocker | `tools/shore_reach_probe.tscn -- --fresh`: bench, bin, scale, seed tin, greenhouse, the refill cell and all 19 secret props are on the start's land group. 62% of cells within 300 m are water; 25 of 431 land cells there are islands. Bot: 2 shore stops in 109 game minutes (36.3 and 36.8 min, cell 100874, walking a straight line across an inlet) | The bot walks straight lines; the land is joined. The 25 island cells cannot be cleaned before Hover Jets | None needed for finishing. Consider leaving island cells out of any count the player is asked to complete before Hover Jets |
| B7 bot stuck-escapes climb | P2 | Confirmed, a bot fault with a player-side cause (B27) | Bot run with `--bot-debug`: 95 escapes by 109 min; 85 of the first 89 at one spot, (1308.4, 294.3, -1258.5), cell 99759, task `refill`, no water ahead | `tools/autoplay.gd` `_water_at()` sent the bot to the bench to refill. The bench stands one cell outside hub ground, where the can does not refill, so the bot pushed at the bench until the escape fired | Bot fixed in this branch (refills at the scale). See section 4 for the re-run |
| B8 carried bale clips into Lumi | P2 | Fixed (`Fix B8: the bale's lift was an idle-frame tween on a frozen body, undone by each physics frame's stack write`) | Test `test_b8_carried_bale_rises_onto_the_stack_while_lumi_carries_it`: bale bottom 0.59 m above Lumi's feet, body top at 1.53 m. Running game: `exit_probe.tscn ... --exit-carrying --probe-verbose` prints the bale at pick-up height for every frame, and a height set by hand is gone the next frame. The resting point itself is right on all six designs, 0.20 m clear (`test_b8_carry_point_is_clear_of_the_body_on_every_design`) | `player/patch.gd:631-641`: the lift is an idle-frame tween on a frozen `RigidBody3D`. `_update_stack` (`:696-713`) writes the bale's x, z and tilt every physics frame; with that running the tween's height is undone each frame, so the bale stays where it was picked up, inside the body | Set the bale's whole position, height included, in `_update_stack` (ease the height there), or run the tween in the physics step |
| B9 planted plants hard to see | P2 | Visual-only, not checked | Logic only: `tests/test_garden_marks.gd` passes (soil, sprout and thirst marks exist, plants have height). No render was made | - | Needs a rendered check by the world artist |
| B10 too many messages, repeated WREN lines | P2 | Not reproduced | Bot run with `--clarity-log`, 109 game minutes: 42 WREN lines, all different; 41 toasts shown, 205 cut by the calm filter; at most 3 messages in any tenth of a game minute. Repeats are recurring events only (Rain Shower 6 times, Salvage Surge 6 times) and one hint twice (57.1 and 61.3 min) | - | - |
| B23 magnet on the globe | P2 | Fixed (`Fix B23: the globe magnet moved every piece in range; the flat rule's cap and filters were lost`) | Tests `test_b23_magnet_leaves_pieces_too_heavy_for_the_lift_tier`, `..._leaves_pieces_embedded_in_a_heap`, `..._pulls_only_a_few_pieces_at_a_time` (12 of 12 pulled). Control `test_b23_magnet_pulls_a_loose_piece_lumi_can_lift` passes | `player/patch.gd:372-379` moves every piece from `pieces_within`; the removed flat rule (`Pace.magnet_step`) skipped embedded and unliftable pieces and pulled 2 + one per level | Filter with `Pace.can_lift` and `piece_embed == 0`, and cap the count from data |

## 2. B4: all 21 steps

Method: `tests/test_triage_m1.gd` satisfies each step first, alone, before anything else, then plays the rest in order (`test_b4_a_step_done_before_its_turn_completes_when_it_comes_up`); does all 21 up front (`test_b4_all_steps_done_up_front_drain_one_per_tick`); and loads a save made out of order (`test_b4_load_catches_up_past_steps_done_out_of_order`). All pass: a step whose condition already holds completes on the next card tick (0.25 s, then a 1.5 s beat). The values read are lifetime stats, upgrade levels, flags and tiers, which never go down; the zone can be erased and then simply asks again (`test_b4_zone_step_reads_the_current_zone`).

So a stall needs something that stops a step's action from ever being possible. Each step was read for that.

| # | Step | Reads | Done early | Can it be closed off? |
|---|---|---|---|---|
| 1 | dump3 | `junk_dumps` >= 3 | completes | **Yes: the Baler (B25). Stalls the whole chain on card 1** |
| 2 | compartment | upgrade level | completes | No |
| 3 | scoop_size | upgrade level | completes | No |
| 4 | baler | upgrade level | completes | No |
| 5 | power | `cubes_cashed` >= 3 | completes | No |
| 6 | tower | tower tier 1 | completes | No (50 cubes) |
| 7 | glim | flag | completes | No |
| 8-10 | hex, hex2, hex3 | `hexes_cleaned` | completes | No. A stuck hex (B3) is one of many |
| 11 | bench2 | bench tier 2 | completes | No. Waits on tower 1 and 3 hexes, both earlier steps |
| 12 | robot | fleet size | completes | No. Robots are never removed |
| 13 | zone | painted cells | completes | No |
| 14 | seed | `plants_planted` | completes | No. The seed tin is on walkable land |
| 15 | hex10 | `hexes_cleaned` | completes | No |
| 16 | base2 | base level | completes | No |
| 17 | haul | Haul Bugs owned | completes | No, but it waits: see B28 |
| 18 | tower2 | tower tier 2 | completes | No |
| 19 | research1 | `research_done` >= 1 | **always done early** | See B26 |
| 20 | hex20 | `hexes_cleaned` | completes | No |
| 21 | base3 | base level | completes | No. Not reached in 109 bot minutes (B5) |

## 3. New bugs

| Bug | Sev | What | Evidence | Cause | Suggested fix |
|---|---|---|---|---|---|
| B26 (Fixed: `Fix B26: the Bot Bay gave Salvage Logic through the research-finished path, which counts and toasts`) | P2 | Step 19 "Finish a research project" finishes by itself; the player is told "Research complete: Salvage Logic" on buying the Bot Bay and never has to open Research | Test `test_b4_research_step_is_not_finished_by_the_bot_bay_gift` (1 / 1 with no project run). Bot: `research1` done in the same second as `haul` and `tower2` (45.4 min) | `ui/bench_tiers.gd:113-114` gives Salvage Logic through `Research.grant`, which counts `research_done` and toasts (`systems/research.gd:322-332`) | Grant it quietly, as story unlocks are (no stat, no toast) |
| B27 (Fixed: `Fix B27: the can refilled only on cells flagged as base ground, which is one cell on the globe`) | P2 | "Watering can is empty. Refill at the hub." but the can refills only inside one 10 m cell (the scale's), with nothing marking it; the bench and the greenhouse, 16 m away, are outside it | `shore_reach_probe`: hub cells within 80 m: only 99758; bench in 99759 and greenhouse in 99760, "not a hub cell". It is what trapped the bot (B7) | `player/patch.gd:296` refills where `hex_hub == 1`; on the globe that is a single cell (`planet/orbit/sphere_field.gd:111`). The comment still says "anywhere in the yard" | Refill anywhere on the start site's yard, or at a visible water point, and name that place in the message |
| B28 | P2 | The card waits on "Build a Haul Bug" until 20 minutes after the first robot, while later steps are already done | Bot: `base2` at 34.4 min, `haul` at 45.4 min (11 minutes on one card), then `tower2`, `research1`, `hex20` all within 6 s | `data/research.json` `story_unlocks.haul_rig`: `since_first_robot 1200` and 8 hexes, or base level 3 | Shorten the wait, or let the card move on to steps that are open (belongs with B5) |
| B29 | P3 | `--quit-after` counts real seconds; `autoload/DevHooks.gd:9` and the bot command in `CLAUDE.md` say game seconds | `autoload/DevHooks.gd:140,163`. `--quit-after=6000` at `--time-scale=8` was still running at 109 game minutes (75 real minutes) | Wall clock on purpose (comment at `:139`) | Correct the two texts |
| B30 (Fixed: `Fix B30: nothing started the rocket's recharge once the flat launch path was removed`) | P2 | The rocket's energy cells never drain after a hub hop: it can hop again at once, and the recharge the workbench sells upgrades for never shows | Test `test_b30_a_hub_hop_starts_the_rockets_recharge` (0 s left after a hop, 300 s expected at Mk I) | `RocketTiers.mark_launched` had one caller, the flat `Rocket.launch`, removed in M1-04b; `OrbitSites.hop_to` never called it and the destination list only refused while in flight | Done: `hop_to` starts the recharge when the hop lands; the list and `can_hop_to_hub` refuse while the cells refill |
| B31 (Fixed: `Fix B31: the screen-shake listener was the flat camera rig, removed with the flat world`) | P2 | Screen shake never happens: 20-odd places emit `EventBus.shake_requested`, nothing listens | Tests `test_b31_a_requested_shake_moves_the_globe_camera`, `test_b31_the_shake_setting_at_zero_keeps_the_camera_still` | `CameraRig.add_trauma` was the only listener; M1-04b removed the rig and the globe camera (`planet/sphere/sphere_cam.gd`) never had one | Done: `SphereCam` listens and swings the lens offset, scaled by the Camera shake setting, off under reduced motion |
| B21 | P3 | The bot's report showed no robots on the globe. **Fixed in this branch (tool)** | Before: every `[Autoplay]` line printed `robots={ }` after the Scoopie at 23.9 min. After: `--robots=scoopie:3,haulbug:2` run prints `robots={ "scoopie": 3, "haulbug": 2 }` | `tools/autoplay.gd` walked `Fleet.robots()`; on the globe robots live in the crew | Done: it asks `fleet.count(id)` |

Nothing found in this pass felt close to another game.

## 4. Bot runs

Command: `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=S --bot-debug [--clarity-log]`. No script errors in either run.

| | Before the merge (removed report `autoplay_report_m1long.json`) | Merged build, run 1 | Merged build, run 2 (bot refill fixed) |
|---|---|---|---|
| Game minutes | 100 | 109 | 123 |
| Hexes cleaned | 69 | 57 | 93 |
| Base level | 2 | 2 | 2 |
| Stuck-escapes | 6 | 95 (85 at the bench) | 20 (none at the bench; 14 in cell 109) |
| Shore stops | - | 2 | 0 |
| First hex / first robot / base 2 (min) | 6.5 / 16.7 / 50.3 | 7.9 / 23.9 / 34.4 | 7.5 / 25.1 / 39.9 |

Run 1 objective times (min): dump3 1.5, compartment 1.5, scoop_size 2.9, baler 3.1, power 3.7, tower 3.7, glim 3.9, hex 7.9, hex2 12.3, hex3 17.4, bench2 17.6, robot 23.9, zone 23.9, seed 26.7, hex10 34.3, base2 34.4, haul 45.4, tower2 45.4, research1 45.4, hex20 45.5; base3 not reached by 109 min (the last card stood for 64 minutes: B5).

Before the merge the same bot logged dead stretches (min) 46.8-50.3, 51.9-55.1, 58.5-62.9, 63.3-70.2, 71.4-91.6, 91.6-98.5 and goal gaps 26.1-50.3 and 50.3-100.

Run 2 confirms the cause of B7: with the bot refilling at the scale there is no escape with task `refill` in 123 minutes. The 20 left are ordinary bumps, 14 of them in cell 109 (the greenhouse cell, 19 m from the start) on the way to the bench or a plant; about one per six minutes, steady, not climbing. Base level 3 (step 21) was not reached in either run.

## 5. Tools added or changed

- `tools/hex_stick_probe.tscn` (B3), `tools/shore_reach_probe.tscn` (B6, B27), `tools/exit_probe.tscn` (B2, B8, B9 counts).
- `tools/autoplay.gd`: `--bot-debug` prints every stuck-escape with task, place and water ahead; the bot refills at the scale; the robot counts come from the fleet's own count (B21).
- `tools/exit_probe.gd`: the carried-bale measure waits 12 frames, not one game second (at time scale 8 that was a single frame).

## 6. Counts

Of the nine bugs handed over: confirmed 5 (B3/B24, B4/B25, B7, B8, B23), fixed already 1 (B2), not reproduced 2 (B6, B10), visual-only not checked 1 (B9). New: B26, B27, B28 (P2), B29 (P3). B21 fixed (tool).

Confirmed P1: B24 (junk laid inside building footprints leaves a hex stuck) and B25 (the Baler before the third bin trip stops the objective chain on its first card). Both have pending tests.

Not checked in this pass: anything that needs a render (B9, B11-B13, B18, B19), the motion of the carried stack once B8 is fixed, and the escape sidestep in `tools/autoplay.gd` `_watch_stuck`, which still builds its direction from world x and z, not the ground's tangent (bot only).
