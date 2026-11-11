# M3-07: district sources, the Lumi-only capstone jobs

Nov 11 2026, on top of `6b33866`. Rules and state: `systems/sources.gd`. The world's side (spots, markers, prompts, landmark state): `systems/source_sites.gd`. Data: `planets/verdance/data/sources.json` (table `sources`). Formulas: `docs/PLANET_PLAYBOOK.md`, "Source jobs (M3-07)".

## 1. What was built

- **A job per city, as data.** Three step types cover all six jobs, so `planets/verdance/sources/` holds no script: `use` (walk there, use it), `work` (use it, then stay in reach for some seconds; leaving pauses it) and `carry` (pick a part up, pay its price if it has one, carry it to its place, fit it). A `work` step names a pollution kind and runs at Lumi's hand bonus for it, so mastering a city's kind shortens its capstone.
- **The gate.** A city with a running source is held one stage short of the last (`Districts.set_stage_cap`). All its hexes may be thriving; the city reads "Sustained 80%" until the job fills the last fifth of the bar (`hold_share`), and launch progress cannot read 100% while a source runs. The next city still opens at stage 4, so the job never blocks moving on.
- **Only Lumi.** A step moves on only when Lumi uses its spot through the interact key and, for timed work, stays within 2.8 m. Nothing a robot does touches a job.
- **On the card and the beam.** Once the story objectives are done, the job of the city the readouts follow takes the objective card while one of its steps is on offer (title, why line, "2 / 4", a bar that fills with the job). The beam stands on the step's spot; the spot has a marker with Lumi's cyan ring. The goal chain keeps paying behind the card and returns when the job is done or waiting.
- **On completion:** `EventBus.source_shut_down(district)`, the hold lifts (stage 5 and its payout follow at once if the hexes are there), the landmark goes to its shut-down state (`TownSite.set_source_state`), the reward is paid, a notice shows, and the city's source finds are given. `source_shut_at_stage` is gone from the finds table and from `systems/finds.gd`.
- **Saved per planet** (`orbit.sources`): step, carried part, shut. A save from before jobs: a city already at stage 5 counts as shut down (unpaid); every other city gets its job. A save loaded with a shut source whose find was never given gets the find.
- **The bot** does the job of the city it is in as soon as a step is on offer (`AutoplayBot._do_source`), ahead of everything else, and rests a step it cannot reach after 150 s.
- **Dev flags:** `--sources-shut=all|id,id` and `--give-parts=N`; `--launch-ready` shuts every source first. `--district-stage=id:5` now leaves the city at stage 4 with its job on offer, which is the dev start for a job.

## 2. The six jobs

| City | Source | Steps | Reward |
|---|---|---|---|
| Old Town | The burst main | Close the feed valve; dig out the blocked drain (litter, 6 s); fetch the pipe cap and bolt it on (5 s) | 300 cubes, 45 Parts |
| Ironside | The crusher yard | Pull the boiler breaker; cut the wreck out of the press (wrecks, 8 s); fetch the brake shoe and fit it on the scrap crane (5 s); park the gantry | 960 cubes, 90 Parts |
| Kettle Bay | The tanker's leak | Close the transfer valve; fetch the hull plate and weld it over the gash (6 s); skim the slick off the shore (slick, 8 s); winch the boom shut | 1,980 cubes, 80 Parts |
| Highreach | The incinerator | Stop the feed belt; scrub the choked flue (smog, 8 s); fetch a filter cartridge and fit it (5 s); shut the furnace dampers | 2,400 cubes, 150 Parts |
| Lowmeadow | The treatment works | Close the inlet sluice; dig the sludge out of the channel (blight, 8 s); fetch the lime and dose the tank (5 s); fetch the plug and seal the outfall (6 s); start the clean water pumps | 4,260 cubes, 250 Parts |
| Old Capital | The rocket | Six parts, each built at the parts yard on the avenue, carried to the pad and fitted (6 s): launch frame 300, fuel tanks 350, engine cluster 400, guidance core 450, hull plates 500, nose cone 600 Parts (2,600 in all); offered at 35, 45, 55, 65, 75 and 85% of the city clean | 3,060 cubes |

- Cubes are one minute of each city's `income_ref` (the limit is three). Parts are the accepted proposal's source payouts; the rocket pays none back.
- Cities 1 to 5 are offered from stage 3 (Growing). The rocket is offered from the start of the city, part by part as it is cleaned.
- The rocket is the last source: when it is done and Old Capital's hexes are thriving, the city reaches stage 5, the launch rule (every city at stage 5) is met and `story/planet_ending.gd` plays as before. The ending needs the six cities and nothing of the rest of the planet.

## 3. Checks

- `tools/run_tests.sh`: **1,175 tests, 1,175 passing** (26 new in `tests/test_sources.gd`; one test in `tests/test_looks.gd` rewritten and one adjusted for the real shutdown). Save round trip: PASS, 180 checks (new: a source shut down and its hold lifted survive the save, the other five cities stay held; an old flat save loads with all six sources running and all six cities held). Orbit reload: PASS.
- `tests/test_sources.gd`: one run per city (parameterised over the six ids) that the city is held at stage 4 with every hex thriving, the job is on offer, Lumi's steps finish it, `source_shut_down` fires once, stage 5 opens at once and the reward is paid; the launch point waits for all six; a planet with no table (the dummy planet and a parked one) has no job and no hold; a one-step job on the dummy planet from a fixture table, gating stage 4 and paying seeds, with no code; work stops when Lumi leaves reach; mastery speeds a step of its kind; a part cannot be taken without the Parts and is paid for once; saves, old saves, the card, the beam's target and the marker's prompt; every spot of the first planet is on a street or the open lot and clear of its landmark's footprint; no reward is over three minutes of its city's income; the rocket is six parts for 2,600 Parts.
- **The bot does every job from a dev start** (`--fresh --autoplay --no-travel --district-stage=<cities before>:4,<city>:5 --orbit-hop=<site> --time-scale=4`, one run a city; Old Capital with `--give-parts=2600`). Game minutes from the start of the run to the shutdown, which includes about 0.5 to 0.8 minutes before the bot has control:

| City | Steps | Shut down at | Source find |
|---|---|---|---|
| Old Town (no hop) | 3 | 1.2 min | held_bottle |
| Ironside (site 7) | 4 | 1.6 min | |
| Kettle Bay (site 3) | 4 | 1.3 min | glow_sprout |
| Highreach (site 8) | 4 | 1.6 min | |
| Lowmeadow (site 9) | 5 | 1.9 min | |
| Old Capital (site 1) | 6 | 2.4 min | head_sprout |

- **The rocket leads into the ending.** One run with every city's hexes at stage 5, the five other sources shut by flag and 2,600 Parts: the bot hops to Old Capital, builds and fits the six parts by minute 2.5, `launch_ready` fires in the same second, the Bloom plays, the end screen opens and "Keep playing" returns control. `--launch-ready=20` still reaches the end screen.
- **City 1 pacing** (`--fresh --autoplay --time-scale=8 --quit-after=250`, one run): first hex 57 s after control (limit 90), first robot 8.6 minutes after control (limit 12), longest wait between purchases in the first 20 minutes 116 s (accepted 136), most cubes held 617. Old Town's job is not on offer in that window (it opens at stage 3), so nothing in the first 25 minutes changed.
- A job takes Lumi about 40 s to 2 minutes of walking and hand work once she is at the city's yard. The proposal counted source jobs as 4% of Lumi's time; no full-game run was made to measure it here.
- **A script error that is not this task's** showed in one bot run (Lowmeadow): `Camp._apply_builds` (`systems/camp/camp.gd:272`), "Trying to cast a freed object", when the bot bought a yard build from 5 km away after the dev hop had unloaded the start site. It needs a hop away from the start yard and a remote purchase; the other ten headless runs had no script error.
- `tools/warnings_audit.sh`: no warning in the new or changed code (project total 141, all in code that was already there).

## 4. Design calls for the lead

1. **The gate is on stage 5, as the task says.** Design spec section 4 says a running source holds hexes at stage 3 and trickles new waste round it. Neither is built: hexes grow freely and no waste comes back. If the trickle is wanted it is a rule in `systems/pollution.gd` keyed on `Sources.is_shut`.
2. **Old Capital has six steps, one per part** (the task's "3 to 5" and "six parts" cannot both hold).
3. **Rocket parts are bought on the spot, not made on the Assembler's line.** The proposal has each part take the line for 45 s. Here Lumi pays the Parts at the parts yard and has the part at once, so the launch crew is not slowed by the rocket (M3-20 counted on about nine player minutes of line time). Fitting takes 6 s, not 20: twenty seconds standing still six times read as sluggish.
4. **No power spike on shutdown.** The spec gives each source a rig slot or tool tier. Rigs are another task; a job has no `grants` field yet.
5. **No step needs robots.** "Hold a lever while robots clear around" is not built: a step that waits on a crew can strand a player who has none there.
6. **The job takes the card ahead of the goal chain** from the moment it is on offer. In cities 1 to 5 that is stage 3, when planting is still the main work; if that is too early, raise `open_stage` to 4.
7. **Spots stand on the street in front of each landmark and on the open lot**, not on the landmark, because only that ground is sure to be free of buildings. A valve "of the tanker" therefore stands a few metres from the hull.
8. **An old save whose city was at stage 5 keeps it and is never paid for the job**; one at stage 4 or below must do the job even if every hex is thriving.

## 5. Honest state: what is below the bar

- **Markers are plain props** (a post with a wheel, a box with a lever, a striped trestle, a crate, a plate with a peg) in flat paint with a cyan ground ring. They work and they are far from commercial quality: no models, no animation, no sound of their own beyond a chime. None was rendered.
- **The rocket does not grow.** The landmark has two states (running, shut down); fitting a part changes nothing on the pad until the last one. A per-part hook on the landmark is needed for the launch site to read as a build.
- **Lumi carries a small crate over her head** for every carried part, whatever the part is. No carry animation.
- **Timed work has no effect or animation**: Lumi stands in the ring while the card's bar fills.
- **Nothing was seen on screen.** The card, the beam, the ring and the notice are covered by tests and headless bot runs only.
- **No WREN line, no sound design, no camera moment** for a shutdown: the "set piece" is the landmark's state change and a notice.
- `story/objectives.gd` grew by about 60 lines and is 903 lines (it was 845, already over the style guide's 600).

## 6. Things to know

- Files outside `systems/` and the planet folder, and why: `planet/sites/town_site.gd` and `planets/verdance/sites/verdance_site.gd` (`source_frame()`, the landmark's frame), `core/planet_definition.gd` and `planets/verdance/planet.tres` (the `sources` table), `autoload/EventBus.gd` (`source_job_opened`, `source_step_done`), `story/objectives.gd` (the card and the beam), `scenes/slice_orbit.gd` (wiring, save section, `--give-parts`), `systems/districts.gd` (the hold), `systems/districts_dev.gd` and `autoload/DevHooks.gd` (dev flags), `systems/finds.gd` and `finds.json` (finds on the real shutdown; Old Capital's hint now names the rocket), `tools/autoplay.gd`, `tools/orbit_roundtrip.gd`, `tests/test_looks.gd`.
- `planet.tres` and `core/planet_definition.gd` each gain one line; the rigs task may touch the same lines.
- New strings are in `sources.json` (`name`, `text`, `text_1`, `desc`, `prompt`, `final_prompt`, `toast`: all keys the extractor reads) and three `tr()` calls in code. `tools/extract_strings.py` was not run.
- The simulators (`tools/pace_sim`, `tools/crew_sim`) were not changed: the pace simulator's proposal tables already model a source job and the rocket their own way.
- Originality: nothing here was modelled on another game. A multi-step repair job with a carried part is common across games; the steps are ordinary plant work on each city's own landmark.
- `docs/ROADMAP.md`, `docs/DECISIONS.md` and `docs/TASKS.md` were not updated (lead's files).

## M3-07b: follow-up (Nov 11 2026, on top of `7f77e2c`)

The lead's three decisions on section 4, built. Formulas: `docs/PLANET_PLAYBOOK.md`, "Source jobs", the two M3-07b entries.

### What was built

1. **A running source holds and fouls the ground round it** (`systems/source_spread.gd`, table key `spread`; the waste itself is `systems/pollution_soil.gd`).
   - Its reach is the 12 land hexes nearest the city's site, where the landmark stands. Hexes in the reach cannot pass stage 3 (`hex_stage`): `HexLevels` asks `SourceSpread.hex_cap` before it raises a hex, so a hex that would be sustained or thriving waits at Growing and rises by itself at shutdown.
   - From city stage 1 (`from_stage`), every 90 s (`every_s`) one clean hex of the reach is fouled again with a quarter of its waste (`amount`), of the source's `soil_kind`. The trickle waits while 3 hexes of the reach lie dirty (`max_soiled`). It stops at shutdown.
   - What comes back is the hex's own ledger: its own pieces where Lumi cleaned it this session, pieces laid out now where it was loaded clean, smog or blight as itself on a hex that holds that kind (the can or the planter clears it, as before). The hex keeps its regrowth level and shows its growth again when it is clean.
   - The hex readout says "SOURCE STILL RUNNING" on a reach hex held at its stage and on one lying fouled. The first hex ever fouled comes with one hint toast. `EventBus.source_soiled(district, cell)`.
   - Trickle: 0.25 x 63 / 90 = 0.175 units a second, 40% of one Rusty Scoopie (0.44). The most that can lie fouled: 47 units, 107 s of that robot.
2. **Rocket parts are built, not bought** (`systems/sources.gd`, `core/crew_chain.gd`). A carry step with `built`: Lumi orders the part at the parts yard (the Parts are spent then), it takes 45 s (`build.line_s`) on the Assembler's line, and the line builds no robot until it is done; a robot already on the line keeps its progress. Then it waits at the parts yard; Lumi fetches it and fits it at the pad (6 s). **Fallback, chosen: with no Assembler standing the workbench builds the part in 135 s** (`build.bench_s`, three times the line), with the same order, price and steps, so no player is stranded. An Assembler built half way takes the part over. The card reads "Wait for the part" with its bar filling, then "Fetch the finished part". The Assembler's panel says the line is building a part for Lumi. `EventBus.source_part_ordered`, `source_part_built`.
3. **Jobs open at stage 4** (`open_stage`); the rocket is still offered part by part from the start of its city.

The planet's ending still needs only the launch point. Nothing in `locale/` was touched and the extractor was not run.

### Checks

- GUT suite: **1,227 tests, 1,226 passing**. The one failure is `test_full_translations_complete` (the translation backlog, known at `7f77e2c`). Because that test fails, `tools/run_tests.sh` stops before its round trip step, so the round trip was run by itself (`tools/check_exit.sh`): save round trip PASS, orbit reload PASS. The round trip now fouls the hex Lumi cleaned and checks that it lies dirty and that the save keeps what it showed before.
- New tests, by rule. `tests/test_source_spread.gd` (15 tests, 4 of them once per polluting city): the five reaches and the rocket's none; the trickle is at most half of one first-tier cleaner and its backlog under three minutes of it; the reach never locks a city out of its job (reach at stage 3, rest at stage 4: the city is at 4, the job is on offer, the next city opens); a reach hex waits at stage 3 and rises at shutdown, and a level a hex has is never taken back; the readout's line; one hex a period, not before the city's stage, not in a locked city, not past the limit, on again when one is cleared, none after shutdown; a fouled hex keeps its level and state; smog comes back as smog and survives a save; a laid-out hex gets its own pieces back and a hex laid out clean gets pieces; water, hub ground and dirty hexes are never fouled; a planet with no table (dummy and parked); the dummy planet with its own numbers from a fixture table. `tests/test_source_parts.gd` (10 tests): the six parts' times and prices; order, wait, fetch, fit, paid once; the part holds the line, no robot starts or leaves, the robot on it keeps its progress; a paused line still builds the part; the workbench fallback, and the whole rocket built without an Assembler; the take-over; saves in both phases; a built part on the dummy planet from data; the simulator's launch crew. `tests/test_sources.gd`: three tests changed for stage 4 and the build.
- **Crew at the launch point: 155** (`tools/crew_sim`, default player; 159 before, accepted 149; cap 200). After each city: 8, 50, 74, 98, 123, 155. The six parts hold the line for 270 s and take 2,600 Parts; 2,974 Parts are left. Longest wait for a robot from city 2 on: 124 s (rule 360). Only Scroungers: 140. No Scroungers: 140, and that player earns 1,615 Parts in all and spends them on robots, so the simulator builds no rocket part for it; a real player would have to keep Parts back.
- **The bot does all six jobs** from the same dev starts as section 3, one run each, no script error: Old Town 1.2 min, Ironside 1.6, Kettle Bay 1.3, Highreach 1.7, Lowmeadow 2.0. The rocket, with every city's hexes at stage 5 and the other five sources shut by flag: on the Assembler's line (`--assembler`) it is shut down at 11.5 min, at the workbench at 16.1 min (2.5 min a part); both runs go on to `launch_ready`, the Bloom, the end screen and "Keep playing". The bot stands by the parts yard while a part is built: in the one run where it wandered off during a workbench build it got wedged on the way back and was reset to the start yard.
- **City 1 pacing** (`--fresh --autoplay --time-scale=8 --quit-after=250`, one run): first hex 55 s after control (limit 90), first robot 9.2 min after control (limit 12), longest wait between purchases in the first 20 minutes 121 s. No hex was fouled in the run: the city does not reach stage 1 in it.
- The trickle seen in a run (`--district-stage=old_town:3`, the job not yet on offer): a hex fouled every 1.5 game minutes, cleaned again by the bot, no script error. In the same run with two Scoopies the robots were heading for the fouled hexes when the run ended; a robot cleaning one to the end was not seen.
- `tools/warnings_audit.sh`: 141, as before; none in new or changed lines.

### Calls for the lead

1. **Decisions 1 and 3 cannot both hold for a whole city, so the stage-3 hold is on the reach, not on every hex.** A city is at stage 4 when 80% of its hexes are. If every hex stopped at 3, the city could never reach 4: the job would never open and the next city would never unlock. So the 12 hexes round the landmark stop at 3 and are fouled; the rest of the city grows on, the city reaches stage 4, the job opens, and the city-wide hold on stage 5 from M3-07 stays as it was. All of it is data: `spread.hexes` is the reach (a number at or above a city's land count holds every hex) and `hex_stage` the stage. Holding every hex at 3 needs `open_stage` 3 and the next city's unlock at stage 3 with it; setup logs an error for a table that would lock a city.
2. **The rocket fouls nothing** (`"spread": {"hexes": 0}`): it is a build, not a leak.
3. **Kettle Bay's trickle is loose waste, not slick.** Slick is a lake kind (M3-04); the reach is land.
4. **A source goes on fouling its reach in a city the player has left**, up to the 3 hexes. Robots that still work there clean them; robots that followed Lumi do not.
5. **The part is ordered and fetched at Old Capital's parts yard while the Assembler stands in the start yard.** It is shipped unseen, like robots are (M3-20 open point 5).
6. **The line still spends Parts on robots while Lumi saves for a part.** A player must pause the line or run a surplus; there is no "keep N Parts back" control (`reserve_parts` is a table number, 0).
7. **Waiting is 45 s six times (135 s at the workbench).** The card shows the bar; there is nothing to do at the yard meanwhile but leave and come back. If that reads as sluggish: order from the workbench panel instead of at the yard, or let the next part be ordered while the last is carried.
8. **Save format:** `orbit.sources` gains `building`, `build` and `ready` per city, and `orbit.pollution` gains `soiled`. Both are read with defaults and old saves load unchanged (the round trip's old flat save passes); no version step or fixture save was added. Say if STYLE section 7 wants one for added keys.

### Honest state

- **Nothing was seen on screen.** The readout line, the hint, the card's wait text, the panel's line and waste coming back in view (pieces appear with a puff of dust; no fall, no sound) are covered by tests and headless runs only.
- **No mark in the world for the reach.** A player learns which hexes the source holds from the readout alone.
- **One save round trip failed the new fouled-hex check, and the cause is not proven.** The first run reported the hex not fouled. Three runs of the same check then passed. The likely cause is that the hex was already dirty: the round trip's own Ledger act lets a drone dump on clean hexes on its own clock. The check now cleans the hex first if it is dirty; the two runs since passed, which does not show the guard was what was needed.
- The robot report's "field cleaned live N, recount from cells M FAIL" shows on runs with `--district-stage` and `--robots` with every source shut as well (hex 152626, restored site ground). It was not checked on `7f77e2c`.
- `HexLevels` applies the hold when it raises a hex. The dev flag `--district-stage` writes levels directly and passes it, which is what the dev starts need.
- Files outside `systems/` and the planet folder, and why: `core/crew_chain.gd` (the line's hold), `plants/hex_levels.gd` (`cap_fn`, `capped`), `planet/orbit/sphere_field.gd` (`lay_again`; `materialize` is split in two and lays out what it did), `planet/orbit/sphere_junk_view.gd` (`show_pieces`), `scenes/slice_orbit.gd` (wiring), `ui/hud.gd` (the readout), `ui/assembler_panel.gd` (one status line), `autoload/EventBus.gd` (three signals), `tools/autoplay.gd`, `tools/crew_sim/*`, `tools/orbit_roundtrip.gd`, `docs/PLANET_PLAYBOOK.md`.
- New strings (8): five in `sources.json` (`build`), "SOURCE STILL RUNNING", the hint toast, the panel's status line. None is in `locale/`.
- Originality: nothing here was modelled on another game. Waste creeping back from an unstopped source and a factory line shared between two jobs are both common shapes; here they are the leak and the Assembler the planet already had.
