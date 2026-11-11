# Verdance release check (helper v7play, 2026-11-11)

The question: is Verdance, the first planet, ready to release? What would a real first-time player
run into between the crash landing and flying off the planet? Tag on fixes: `[v7play]`. Tests:
`tests/test_v7play.gd`.

**Short answer:** not yet, but close. The arc plays end to end with no script error and no dead
card. Two things stand in the way: a crash at quit while a town is building (a regression of an old
fix), and the owner's yes on the end-of-Verdance moment (a closed-planet gate with a "to be
continued" beat is now in place). After that, a few should-fix items in the first hour. See "What
stands between Verdance and release" at the end.

## 1. A full playthrough

`flock /tmp/gf-autoplay.lock godot --headless --path . -- --fresh --orbit --no-intro --autoplay --soak --time-scale=8 --clarity-log --keep-report --save-dir=v7full --quit-after=7000`
on main ce603aa (seed 4471), read with `tools/cadence.py`. It played the whole arc in **145.5 bot
minutes** (about 4 h 50 min for a person at the doc's x2 guess): all six stations woken, Mk V drive
built, exit beat said, launch. 0 SCRIPT ERRORs. The journey below is the bot's; "~Person" is bot
time x2. WREN and Bought are what happened while that card was up. The Beam column is empty
because this run predates the beam logging (`tools/clarity_log.gd` now logs `beam:` lines). The
staged runs in part 2 have it.

| Bot min | ~Person | Card (price) | WREN | Beam | Bought / happened |
|---|---|---|---|---|---|
| 0.1 | 0:00 | Fill the trash bin 3 times | Its bin makes cubes from trash. Find parts, build a signal tower and we can talk. I'll be [glitch]listen—[/glitch] |  | compartment_size L1 |
| 0.4 | 0:00 | Buy a bigger chest (35 cubes) |  |  |  |
| 0.4 | 0:00 | Buy Scoop Size (55 cubes) |  |  |  |
| 1.2 | 0:02 | Save up for the Baler (80 cubes) |  |  | multi_lock L1 |
| 2.4 | 0:04 | Sell 3 bales |  |  | baler L1 |
| 3.1 | 0:06 | Build the signal tower (50 cubes) | ...Lumi? ...It's WREN. Your tower's carrying me. Barely. Keep it standing. |  | signal_tower 1 |
| 3.2 | 0:06 | Repair Glim | Lumi, it's WREN. I run the Cradle, our big ship. I never stopped listening for you.; The Cradle can't land on a dead world. Let's make Verdance green again.; Plants make green light. It fills your Bloom Core, and it shows the Cradle the way home.; Lumi... something's still holding on to your pod. Small. Lantern-shaped. Patch him up at the bench. |  | lift_strength L1 |
| 5.2 | 0:10 | Clean the glowing hex | Glim! He held on to your pod the whole way down, just to stay with you. Welcome back, little light.; First, one clean hex. Clear the outlined one. Green starts on clean ground. |  | build glim; glim_light L1 |
| 6.6 | 0:13 | Clean 2 hexes | One hex clean. Now one more, Lumi. |  | glim_light L2; glim_scan L1 |
| 13.3 | 0:26 | Clean 3 hexes | One more hex, Lumi. The planet notices, believe me. |  | lift_strength L2; glim_scan L2 |
| 22.2 | 0:44 | Add a Bot Bay to the bench (1K cubes, 40 parts) | Add a Bot Bay to the bench. You shouldn't do this alone.; ...that voice... not mine. Cold. It counts things. |  | research salvage_logic; bench_tier 2 |
| 33.1 | 1:06 | Build your first robot (800 cubes, 40 parts) | The Bot Bay hums! It can build you a helper. Try the Bots tab at the workbench.; The relay's strong enough now to hear the Cradle's old work orders. They're on the Requests board at the workbench.; ...another... voice? No. It doesn't talk. It just hums. |  | robot scoopie |
| 46.6 | 1:33 | Show your robot where to clean first |  |  |  |
| 46.6 | 1:33 | Plant the first seed | Something green is waking out there. Plant the first seed.; Lumi, that green signal is back, stronger now. Follow the beam: the old greenhouse.; Wait. Hold it up to the light.; That's a Settler seed tin. Cradle stamp on the lid. One of ours, left behind in the rush. (+6) |  |  |
| 48.8 | 1:37 | Fly to the next station (600 cubes, 30 parts) | The seed tin is nearly empty. Garden Row kept the seed store. |  | landed at site 9; launch 9 |
| 49.5 | 1:39 | Wake station 2 of 6 (600 cubes, 30 parts) | A woken station keeps cleaning, and gives its rocket piece.; On to ten clean hexes. Your robots are learning from you, Lumi. |  | hub 2 restored (site 9)  x2.7 sales; back at the start hub; research wild_mint; glim_light L3 |
| 53.9 | 1:47 | Clean 10 hexes |  |  |  |
| 54.1 | 1:48 | Rebuild the base to level 2 (2K cubes, 150 parts) | A bigger base makes more power, and power runs robots. Rebuild it at the workbench. |  |  |
| 54.2 | 1:48 | Build a Haul Bug | A Haul Bug carries bales for you. Build one at the bench.; ...It's green. Lumi, it's actually green.; Keep it watered. Seeds are rare out here, but every bloom gives one back, and a little green light for your core. This is how it starts.; ...something is flying... toward the clean ground... (+6) |  | base 2; robot scoopie; build composter; composter 2; signal_tower 2; scoop_speed L1 (+44) |
| 66.7 | 2:13 | Fly to the next station (2K cubes, 42 parts) | The rocket's skin is too thin for space. Gantry Works made hulls. |  | landed at site 7; bot_haulbug_speed L1; bot_haulbug_speed L2; research field_notebook; launch 7 |
| 68.6 | 2:17 | Wake station 3 of 6 (2K cubes, 42 parts) | A woken station keeps cleaning, and gives its rocket piece.; A bigger rocket carries supplies to more stations. |  | hub 3 restored (site 7)  x9.4 sales; back at the start hub |
| 73.4 | 2:26 | Upgrade the rocket to Mk II (8K cubes, 150 parts) |  |  | rocket Mk 2 |
| 73.4 | 2:26 | Rebuild the base to level 3 (9K cubes, 350 parts) | One more base level, Lumi. Bigger machines need a stronger base.; The lakes are full of floating junk. I've sent you plans for a Skimmer: it nets what floats. Bots tab. |  | bot_haulbug_carry L1; bot_haulbug_speed L3; multi_lock L3; bot_scoopie_capacity L3; scoop_width L5; bot_scoopie_speed L4 (+7) |
| 77.6 | 2:35 | Fly to the next station (10K cubes, 59 parts) | Nobody knows where to fly. Signal Heights kept the star chart.; Found it. A Ledger relay, still humming. Look for the red beacon.; With enough parts, the workbench can put a helper together. Bots tab, one button. |  | landed at site 8; robot haulbug; base 3; scoop_speed L6; compartment_size L7; bot_haulbug_carry L2 (+20) |
| 84.0 | 2:48 | Wake station 4 of 6 (10K cubes, 59 parts) | A woken station keeps cleaning, and gives its rocket piece. |  | hub 4 restored (site 8)  x33.0 sales; back at the start hub; research wide_beam; bot_scoopie_capacity L5; laser_reach L4; bot_haulbug_carry L3 (+16) |
| 88.6 | 2:57 | Build a Seedling planter |  |  | compactor_pressure L6; bot_scoopie_scoop_rate L7; scoop_speed L9; bot_haulbug_carry L4; detector_range L6; bot_scoopie_efficiency L6 (+12) |
| 91.4 | 3:02 | Upgrade the base to level 4 (60K cubes, 140 parts) |  |  | research auto_baler |
| 98.5 | 3:17 | Fly to the next station (38K cubes, 82 parts) | The water... I can see the bottom. Lumi, there's something moving down there. |  | landed at site 2; station conveyor; base 4; robot skimmer; station auto_baler; research pollinator_survey (+6) |
| 106.6 | 3:33 | Wake station 5 of 6 (38K cubes, 82 parts) |  |  | hub 5 restored (site 2)  x115.4 sales; back at the start hub; research auto_sort |
| 111.6 | 3:43 | Upgrade the rocket to Mk III (100K cubes, 400 parts) | Clear as the garden deck. Now I can tell you everything I couldn't. |  | rocket Mk 3; signal_tower 3; bench_tier 4; research haul_routes; bot_drip_speed L1; bot_drip_refill_rate L1 (+60) |
| 117.2 | 3:54 | Build a Drip watering robot |  |  | robot drip; compartment_size L11; magnet_arm L2; bot_drip_tank L6; baler_speed L4; bot_scoopie_scoop_rate L8 (+15) |
| 117.3 | 3:54 | Upgrade the base to level 5 (250K cubes, 110 parts) |  |  | research multibot_blueprint |
| 119.1 | 3:58 | Fly to the next station (300K cubes, 120 parts) | They meant to come back, Lumi. You came back instead. They'd like that. |  | landed at site 4; robot multibot; bot_multibot_speed L1; bot_multibot_speed L2; bot_multibot_speed L3; bot_multibot_speed L4 (+115) |
| 140.4 | 4:40 | Wake station 6 of 6 (300K cubes, 120 parts) | Half charged. You're glowing, Lumi. Properly glowing. I'd forgotten you could be this bright.; Six stations awake, Lumi. Their robots can look after Verdance now.; To go home we need 10 fuel and 10 power. We have 2 fuel and 2 power.; The star map shows four more worlds. The Ledger buried every one. Why? (+1) |  | hub 6 restored (site 4)  x404.0 sales; back at the start hub; built the Mk V drive; bot_scoopie_scoop_rate L13; bot_scoopie_capacity L12; bot_scoopie_efficiency L11 (+18) |
| 145.5 | 4:51 | Build the Mk V Orbital drive | The rocket can leave now. Verdance isn't finished, and that's all right. |  | PLANET EXIT: launch onward |

(At 3.2 the second WREN line is the double self-introduction fixed below, F4.)

### The arc against BALANCE.md (v6pace's run, same seed)

| | v6pace | this run |
|---|---|---|
| First robot | 31.7 | **46.5** |
| Base 2 woken (Garden Row) | 40.5 | 53.5 |
| Base 3 / Mk II | 59.6 / 64.6 | 72.6 / 73.4 |
| Base 4 | 72.2 | 88.0 |
| Base 5 / Mk III | 98.6 / 105.5 | 110.6 / 117.2 |
| Base 6, drive, leave | 131.7 / 132.8 | 144.4 / 145.4 |
| Planet % at leave | 22.2 | 22.0 |

Cadence (`tools/cadence.py`): 140 new moments in 146 minutes, mean gap 1.0 min. Over target: four
gaps, all in the first hour: **13.4 min** (33.1 to 46.5, saving 800 cubes for the first robot), 10.9
(Bot Bay, 1,200 cubes), 8.2 and 6.6 (cleaning hexes 2 and 3). Card waits: hub 6 "Fly to the next
station" 21.3 min (300K, flagged WALL); the first robot 13.5; "Build a Haul Bug" 12.5 (no price:
waiting for the plans); Bot Bay 10.9. After minute 54 nothing is over 4 minutes except the hub 6 save.
The whole run is 13 minutes slower than v6pace's; nearly all of it is in the first 46 minutes
(income about 100 cubes a minute while the yard's near junk runs out, so the walks grow).

### Judged as a first-time 5-year-old, and as an adult

**Fixed here**

| # | What | Fix |
|---|---|---|
| F1 | **WREN said "Six stations awake, Lumi" with five awake.** The exit beat (`StoryArc.leave_open`) also opened when the planet % reached 50%, and Verdance's % is the Bloom Core charge. In this run the core hit 50% at 143.2, a minute before the sixth station (144.4). A planting-heavy player would hear it with three or four stations. | A planet with a station gate (`leave.hubs`) now leaves by that gate only. Test `test_exit_beat_waits_for_the_six_stations_not_the_core`. |
| F2 | **97,063 engine errors** `!v.is_finite()` at `instance_set_transform` from minute 100 to the end: a robot's bucket arm (RobotVisual `_arm`) went to NaN. Its idle lerp used `delta * 4.0` unclamped; a frame over 0.5 s (here the 8x time scale, for a player a long hitch) overshoots, and repeated it diverges to inf/NaN. The arm (and its 11 meshes) vanished for good. Found with a new dev probe `--nan-probe=S`. | Clamped (and the two same lerps on Lumi's model). Test `test_robot_arm_settles_on_long_frames`. |
| F3 | **A robot shown as "needs help" (red) in the Command view forever** once it had been freed from a stall three times in its life: `SphereCrew.is_stuck` counted escapes over the whole game. In the run all five Haul Bugs were "stuck" for the last 25 minutes while they worked fine. | Only a stall now or an escape in the last 30 s counts. Test `test_robot_stuck_flag_is_recent_not_lifetime`. |
| F4 | WREN introduced herself twice in a row when the tower came up: "...It's WREN. Your tower's carrying me." then "Lumi, it's WREN. I run the Cradle..." | The briefing's first line now starts "I run the Cradle, our big ship...". Six translations. |
| F5 | The card read "Wake station 6 of 6 **[4 / 5]**" and "Build the Mk V Orbital drive **[0 / 5]**" (the count was the station or tier number). | Once the price is covered, these one-off steps (`hubs_woken`, `hubs_seen`, `drive_tier`, `rocket_tier`) show a full bar and no count. |
| F6 | "everything sells for **x42.88** now" | Rounded from x10 on ("x43", "x150", "x525"). |
| F7 | The Telescope's system view said "Seed or visit another world from the **Ark Bridge**", which a Verdance player can never open. | "No other world visited yet. Visit another world, then come back to watch its crew." Six translations. |
| F8 | **The purple beam pointed at the home bench for "Fly to the next station", "Wake station N" and the drive**, even from a far station, a rocket hop away. HubPurpose.goal_target (rocket, landmark) was written for this and never called. | The beam stands on the rocket (fly, the drive; while saving up it leads out to the junk) and, at a far station, on its landmark (wake). Seen in the staged reload at Signal Heights: `beam: site 8 (-19, -35)`, the landmark. |
| F9 | **The exit beat could be lost for good.** When the drive was built before the beat's first check (a reload right after the sixth station, then the drive at once: seen in the staged run), HomewardDirector took the save for an old one "past the exit" and marked the beat done unsaid: no "Six stations awake", no fuel and power line, no "Ochre is next". | Building the drive plays the owed exit beat first; the silent mark is only for saves past Verdance (answered) or without the six stations. |

**Still open** (ranked in "What stands between Verdance and release")

| # | What | Who / recommendation |
|---|---|---|
| O1 | First hour: the gaps of 13.4 and 10.9 minutes are the Bot Bay (1,200 cubes) and the first robot (800) bought back to back while income is about 100 cubes a minute. Owner target: never more than about 12, and every 3-6 minutes in the first hour. v6pace measured 31.7 for the first robot on the same seed; this run 46.5. | v6pace: Bot Bay to about 900 and the first Scoopie to about 600 (data/bench_tiers / robots), or a cheaper first-robot price; then re-run the bot twice. |
| O2 | "Build a Haul Bug" sat on the card for 12.5 minutes with no price and "Keep cleaning. WREN is looking for Haul Bug plans." The plans come 20 minutes after the first robot (owner #46: Scoopie alone for a while). A child sees a step they can't do. | v6story/v6pace: put the wait before the card (keep "Clean 10 hexes" or a Scoopie step up until `haul_rig`), or word it as the step: "Let your Scoopie work. WREN is looking for Haul Bug plans." |
| O3 | Hub 6 is one 300K save of 21 minutes with the card on one number (BALANCE.md lever: `far_hub.cost_override."4"` to 200K). | v6pace. |
| O4 | WREN repeats "A woken station keeps cleaning, and gives its rocket piece." at three stations (the `hub_wake_` reason in data/story_reasons.json). | v6story: a `by_id` line per station (`hub_wake_3`..`hub_wake_6`). |
| O5 | The first-seed card ("3 then hold LMB to water it") stays on top of the objective card until the seed is watered, even after a rocket hop to another station. | v1guide/v6story: drop the water hint when Lumi leaves the start hub. Low risk: a player normally waters first. |
| O6 | The bot never does a far station's local chain ("clean N hexes here"); it waits 240 s and pays the wake. A player must clean 3-8 hexes at each station by hand, so the person time per station is not measured. | v6pace: teach the bot the chain, or measure one far station by hand. |
| O7 | The drive (and the system map) still open at Verdance 50% Bloom Core (`requires_planet_pct [0, 0.5]`), not only at six stations. Since F9 the exit beat is no longer lost when the drive comes first, but the drive card comes after the stations anyway. | v6pace: make `leave.hubs` the only drive gate on Verdance (changing it breaks the pct tests in tests/test_homeward.gd, so it is theirs to do). |
| O8 | 15 `Parameter "space" is null` errors at `body_test_motion` from `SphereMotor._level_slide` during rocket hops (Lumi's body is out of a physics space for a frame). Harmless. | v6feel: skip the slide while the body has no space. |
| O9 | "Lumi stuck" soak warnings: all at the bin and bench (the bot shuttling, QA #4) or at a far station's pad (the bot waiting its 240 s). None is a real trap. | none |

**Story order** against docs/STORY_VERDANCE.md: matches (crash, bench, bin, bale, tower, WREN's
briefing, Glim, hexes, Bot Bay, robot, zone, seed and the Ledger's first drones, the first station
hop, base 2, Haul Bug, Gantry Works, Mk II, base 3, Signal Heights, base 4, Fairground, Mk III, base 5,
Stack Works, exit beat, drive). The only deviation was F1.

**Prices:** every price on the card matched what was paid. The "x3.5" sell line counts from the start
of the game (the pace knob divides every sale from the first), so it is right, if not obvious.

## 2. Save and continue at awkward moments

Staged autoplay (`--fresh` once, then continued from the save): each stage stops at a moment with
`--stop-at=<key>` (it saves, then quits), then a second process loads a copy of that save with
`--soak --clarity-log` (no autoplay) for 70 s. New autoplay marks for this: `hop_N_s` (mid-flight),
`landed_N_s` (at a far station, not woken), `exit_beat_s`. The soak digest now also prints the home
meters, the woken stations and the once-only beats (`home=`, `woken=`, `beats=`), and the clarity
log prints the beam (`beam:`). This seed's run reached the first robot at 24.5 bot min (46.5 in
part 1: the early game varies a lot from run to run).

| Moment (bot min) | Saved | After the reload | Verdict |
|---|---|---|---|
| Right after the first robot (24.5) | 1 Scoopie, 460 parts, 8 upgrades, step "zone" | Scoopie, 3 zoned hexes, parts, upgrades all back. The card shows "Build your first robot" for a moment, then the robot step completes again and moves to "Show your robot..." and "Plant the first seed" (the save was taken the instant the robot was built, before the step ticked). Cubes 124 against 724 at exit: the step's goal rewards paid after the save, paid again on reload. Beam: bench, then none. | ok |
| Mid rocket hop to Gantry Works (47.2) | in flight | Lumi is back at home with the rocket on the home pad; card "Fly to the next station" (the hop just didn't happen); robots 4 Scoopies + 1 Haul Bug, 50 plants, cubes 2.63K, all as saved. Nothing lost; the flight is simply redone. | ok |
| Just landed at Signal Heights, not woken (63.4; the bot never does the local chain, so "half woken" here is "arrived, chain not done") | at site 8 | Lumi at Signal Heights, the rocket parked there (`rocket=8`), the station marked seen, card "Wake station 4 of 6", beam on the landmark (`site 8 (-19, -35)`, F8). Stations 2 and 3 at level 2, robots and plants as saved. WREN says the step's line again ("A woken station keeps cleaning..."), see O4. | ok |
| Right after the 6th station woke, before the exit beat (132.3) | at Stack Works, 6 woken | The exit beat plays once on the reload: "Six stations awake...", "To go home we need 10 fuel and 10 power. We have 2 fuel and 2 power.", the star map question, "Ochre is next...", toast "Home: fuel 2/10, power 2/10". Card then "Build the Mk V Orbital drive", beam on the rocket. All 6 stations, 29 robots, 95 plants back. | ok |
| Right after the exit beat (and the drive, 132.3) | beats verdance_exit, verdance_drive; home (2, 2) | No WREN line and no beat replays; home meters (2, 2), the drive kept; the card goes on with Verdance's own goals (Chest Size 3, a memory shard, Pet a stray cat...); "Fly to another planet" is gone (closed gate). | ok, but this stage found F9: the bot bought the drive one second after the reload, and the exit beat was marked done unsaid. Fixed. |

**Found here as well:** the stops right after the 6th wake and right after the exit beat both
crashed at quit with **exit 134, `corrupted size vs. prev_size in fastbins`**, while the bot's hop home
was starting (the save was already written and loaded fine). Repro: `--orbit --save-dir=<a save at a
far station> --orbit-hop=4 --quit-on-hop=4` (quit 4 s into a hop: exit 134; at 0 and 1 s: exit 0).
v6qa's own repro of the old crash (QA_VERDANCE.md Q7) **fails again on main**: `--fresh --orbit
--no-intro --orbit-walk-in=1,380 --quit-mid-build=30` exits 134 ("at load
modular_factory_facade_1k.gltf"), with and without `--quit-mode=free`. So quitting, or going back to
the title, while a hub town is being built crashes the game. It came back after v6qa's fix; the
town build changed since (v7planet's site kit, v6pace's keepers). **Blocker.**

The drive stage itself (stop after the to-be-continued beat) did not finish before the time limit;
the to-be-continued lines were seen in the exit-beat stage: "Rocket drive built: Mk V Orbital.",
"To be continued: the trip to Ochre comes in a future update...", WREN "The drive is ready, Lumi. But
we can't reach Ochre yet..." once.


## 3. Dead ends in menus

Every menu path a Verdance player can reach, checked in code and in the `--ui-audit` runs (part 5):

| Path | What is there | Verdict |
|---|---|---|
| Title: Continue, New Game, Profiles, Settings, Quit | all work | ok. Continue's subtitle says "Hub 1" on the globe always (`current_hub` is the flat world's): nice to have, show the station or planet name |
| Profiles: Continue / New / Rename / Delete per slot | work. "N planets" and the world picker only appear with more than one world, which needs a flight to another planet (now closed) or the Ark Bridge | ok |
| Profiles card "Bloom N%" | the flat world's Bloom milestones; on the globe it moves rarely (one milestone in this run) | nice to have: show the planet % the HUD shows |
| Pause: Resume, Codex, Photo mode, Keepsakes, Settings, Quit | work | ok |
| Pause: Garden Mode | opens at base level 5 (`data/decor.json`), runs per hub on the globe | ok |
| Pause: Ark Bridge | shown only after the Cradle finale or "The Cradle Answers" (needs other planets and the Mk VII). Never on Verdance. Its "Seed a new world" is Cradle Mode, retired on the globe | hidden already, never reachable in this release |
| Pause: Solar system | from the Mk V gate on. Ochre to Anvil now say "Coming in a future update" | ok (after the gate) |
| Keepsakes | CD Player, Album, Nursery: each only once built. Seed of the Week hidden by data/weekly.json | ok |
| Codex | Codex, Achievements, Stats, Curiosities, Collection, Artists | 17 achievements could only be earned on other planets or after the ending (land on another planet, restore planets, relics, Mk VI, Homecoming, Ark Bridge, seed new worlds, Heirlooms, Seed Ark waves). **Hidden** while the next planet is closed (`closed.hide_achievements`) |
| Telescope (yard build, base 4 or research) | shows the system; "watch a crew on another world" has nothing to watch in this release | hint fixed (F7). Should fix: the 6,000-cube Telescope has little to do on Verdance. Owner: let it watch the far Verdance stations' crews, or hide the build until another planet is open |
| Rocket picker (E at the rocket) | stations, home, and "To other planets" (the system map in travel mode) | ok; other planets say "Coming in a future update" |
| Goal chain after the drive | "Fly to another planet" was the next card: impossible with Ochre closed. Later goals: restore planets, Mk VI, Mk VII, the last seed, launch home | **hidden** while the next planet is closed (`closed.hide_goals`). The chain carries on with Verdance goals (perfect bale, shards, research, plants, hexes...) |

The flag, like Seed of the Week's: `data/homeward.json` planets[k] `"open": false` plus a `closed`
block (docs/ADJUSTING.md, "Which planets are open in this release").

## 4. After Verdance

**What happens today if the player flies to Ochre** (the end-of-Verdance save, then the real
interplanet launch, `--open-planets --orbit-planet-hop=1`): Ochre's globe builds, and the player
starts over. The card is "Fix the Settlers' old bench: press E", WREN plays her crash message
("Lumi, it's WREN, up on the Cradle. Your pod fell by an old cleanup station..."), every upgrade
and robot is gone (the arrival kit's robots don't appear: `bots=[]`), the toast says "Lumi's pod is
down on Ochre", the achievement "Seed Mission: Seed a new world from the Cradle's vault" pops, and
Ochre has no stations (no hub plan in data/planets.json), so its story is the Verdance tutorial
again. That is not a finished experience.

**Done (the safe gate):** Ochre, Tidewell, Rime and Anvil have `"open": false`. The map shows them,
with "Coming in a future update"; no launch goes there; the goals and achievements that need them
are hidden. When the Mk V drive is built WREN says, instead of "The rocket can leave now...":

> "The drive is ready, Lumi. But we can't reach Ochre yet. Its sky is still full of dust."
> "So we stay a while. Every town we clean makes Verdance greener for the Settlers."

and a story toast: "To be continued: the trip to Ochre comes in a future update. Keep restoring
Verdance!" The player stays on Verdance; the goal chain goes on with Verdance's own goals.
All the text is data (`data/homeward.json` `closed`), translated in all six languages. To open a
planet later: `"open": true`. Autoplay stops two minutes after the drive when the next planet is
closed ("next planet closed: to be continued"), so pacing runs still end at the leave point.

## Needs a decision

1. **The end-of-Verdance moment.** Recommended: keep the gate and the lines above for the release,
   and add a short "to be continued" card the owner likes (a still of the rocket on the pad under the
   two suns, the home meter "fuel 2/10, power 2/10", "Lumi will be back"). Wording to approve: the
   dust line is a small invention (Ochre's sky); it can be swapped in `closed.drive_lines` without
   code. Alternative: no drive at all in this release (stop the chain at the sixth station). Not
   recommended: the drive is the big final number the arc builds to.
2. **The Telescope** on Verdance (part 3): let it watch the far Verdance stations, or hide it.
3. **Bloom Core vs the chart.** Verdance's planet % for the chart (Ochre's reach) is the Bloom Core
   charge, which is not the % on the HUD. When Ochre opens, the player will need the core at 50%
   after the six stations; in this run that came 1 minute before the drive, but it is not tied to
   the stations. Recommended: chart Ochre with the station gate (Signal Heights gives the star chart
   in the story).
4. **First-hour pace** (O1, O2): v6pace's call; the numbers are above.

## 5. The existing checks (main e904c38 + this branch)

| Check | Result |
|---|---|
| `--city-walk` | **PASS**: 70,674 m2 free, all reached, out on every side, 0 pockets |
| `--target-reach` | checks **PASS** (5,311 targets on 10 hubs, 0 unreachable), but the process **crashes at quit, exit 134** (the Q7 regression in part 2) |
| `--site-reach` | **PASS** |
| `--hop-skip --hub-walkthrough` | **PASS** (all five far stations woken by E, gifts, field benches, BASES n/6) |
| `--hub-walkthrough --hub-walk-fly=1` | **PASS** (Garden Row flown: 10.4 s, worst flight frame 247 ms CPU, on the ground worst 95 ms) |
| `tools/planet_smoke.sh verdance` | **PASS** (write and read) |
| `--ui-audit` in game | **PASS**, 0 issues (the system map with the "Coming in a future update" lines included) |
| `--menu --ui-audit` (title) | **PASS**, 0 issues |
| 20-minute soak (`--autoplay --soak --time-scale=8 --clarity-log --quit-after=1200`, 91 bot min) | **PASS**: 0 SCRIPT ERROR, 0 non-finite transforms, no robot "stuck" (after F3); 4 "Lumi stuck" warnings, all the bot waiting at a far pad or the bin (O9) |
| `tools/run_tests.sh` | **PASS**: 1127/1127 GUT, roundtrip, orbit_reload |
| `save_roundtrip.tscn -- --fresh --orbit` | **PASS** (222 checks, the beacon checks included) |


## What stands between Verdance and release

Ranked. The fixes above (F1-F9) are in. What is left:

**Blocker**

1. **Crash at quit while a hub town builds** (exit 134, heap corruption): v6qa's Q7 repro fails again on
   main, and so do `--target-reach` and a quit 4 s into a rocket hop. A player who quits or goes back to
   the title just after flying to a station, or walking into a town, gets a crash. The save is written
   first, so nothing is lost, but it is a crash. Owner: v6qa (or whoever touched the town build last).
   Repros: `--fresh --orbit --no-intro --orbit-walk-in=1,380 --quit-mid-build=30` and
   `--orbit --save-dir=<save at a far station> --orbit-hop=4 --quit-on-hop=4`.
2. **The end of Verdance needs the owner's yes** (Needs a decision #1). The gate keeps the player out
   of the unfinished Ochre and says "to be continued"; the wording and whether that is the release's
   ending are the owner's call.

**Should fix**

3. First-hour pace (O1): 13.4 and 10.9 minute gaps saving for the Bot Bay and the first robot; the
   first robot came at 46.5 bot minutes in one run and 24.5 in another. Owner target: nothing over 12.
4. "Build a Haul Bug" with nothing to do for 12.5 minutes (O2).
5. The far-station chain is not measured by the bot (O6): the person time per station is unknown.
6. The Telescope has nothing to watch in this release (part 3, Needs a decision #2).
7. Hub 6's single 300K save, 21 minutes on one number (O3).

**Nice to have**

8. WREN repeats the station line (O4); the first-seed water card can sit over a far station (O5).
9. The drive opens at 50% Bloom Core too (O7); Ochre's chart is the core % (Needs a decision #3).
10. Title "Continue" says "Hub 1" always; the profile card's "Bloom N%" is the flat world's measure.
11. 15 `space is null` physics errors during hops (O8).

Everything else a first-time player meets from the crash to the drive worked in these runs: the
story in order, one card at a time with a reason, a price on every priced step that matched what was
paid, WREN's lines once each (but O4), saves that come back whole at every awkward moment tried, all
six stations wakeable by E, and no script error in 145 + 132 + 91 bot minutes of play.

