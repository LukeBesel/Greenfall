# Greenfall: Planet 1 plan

Written in Phase 0 (Nov 9, 2026) by the lead, from an audit of the merged main line (`claude/kind-wright-rhxixd` at a86fb5b plus the hero-model branch). This file replaces the earlier milestone plan, which is kept at `docs/archive/PLAN_v1_2026-11.md`. Tasks are in `docs/TASKS.md`, rules in `docs/STYLE.md`, calls in `docs/DECISIONS.md`, lessons for later planets in `docs/PLANET_PLAYBOOK.md`.

**Scope:** finish Planet 1 (Verdance) as a complete, polished experience that could ship as a Steam demo, on systems any later planet can reuse. No new content for later planets.

## 1. Feel targets

Principles that make incremental games hard to put down, and how Greenfall reaches each one in its own way.

| # | Principle | How Greenfall does it |
|---|---|---|
| F1 | **Every action answers back at once.** Input to feedback in under 100 ms, with sound, motion and a number. | Each piece Lumi lifts has weight: a pull, a clunk into the chest, a pitch that climbs as the chest fills. The chest gauge on Lumi's body moves with every piece. |
| F2 | **A small win every 20-40 seconds.** | A full chest, a pressed bale, a paid load, a hex ring closing another notch. Hexes are sized so one finishes every 1-3 minutes by hand early on. |
| F3 | **Something to buy is always close.** The next purchase is visible and reachable within 1-3 minutes. | The workbench always shows the nearest affordable fit and how many loads away it is. Costs are tuned by simulation so the wait never passes 4 minutes. |
| F4 | **Three goals at once: short, medium, long.** | This hex (1-3 min), this district's next regrowth stage (10-20 min), the planet (hours). All three are always on screen as one compact readout. |
| F5 | **Work shows.** Progress is visible in the world, not only in numbers. | Ground goes from littered grey to soil, moss, grass, flowers and trees. Animals return. The sky clears. Looking back at where you started is the reward. |
| F6 | **Power spikes, then a new problem.** A big jump in strength every 30-40 minutes, followed by something the new strength does not solve. | Each district brings a new kind of pollution and the tool for it. The tool makes old work trivial and opens harder ground. |
| F7 | **The player's hands stay the engine.** Automation multiplies active play; it never replaces it. | Robots can only do what Lumi has mastered by hand, and work near where Lumi works (section 4, R4). Pollution sources need Lumi in person. |
| F8 | **Choices with trade-offs.** No single best order. | Fitted modules (rigs) compete for three slots on Lumi's body; each district offers two ways to spend its first surplus. |
| F9 | **Escalating spectacle.** The same action looks and sounds bigger as the player grows. | A first hex clears with a puff of dust; a late one clears with a rolling wave of green across its neighbours. |
| F10 | **Depth under a simple surface.** | One verb to start (hold to sweep). Mastery, rigs, pressing skill, secrets, collections and optimisation sit underneath for players who dig. |
| F11 | **Clean stopping points that invite one more.** | Every finished hex or stage shows the next one already part done. Leaving and returning pays a small, capped catch-up. |

## 2. Greenfall identity

What makes this game its own, and how the theme drives the design.

- **The hero is a wreck that gets better.** Lumi starts rusty, slow and half-broken. Upgrades are not abstract levels: they are salvaged parts fitted to the body, and the model shows them. By the end the same robot is restored. The player's power curve is visible on the character.
- **Salvage, repair, regrow.** Nothing is bought from a shop. Trash becomes pressed bales, bales become stock, stock becomes parts, parts repair Lumi, the base and the crew. Clean ground becomes soil, soil becomes meadow. Every currency is something physical the player handled.
- **The planet is the progress bar.** A real, walkable globe that starts buried and ends alive. The map, the sky, the wildlife and the music all read from the same restoration state.
- **Hands first.** Lumi does the work. Robots are apprentices that copy what Lumi has learned, so the player's own cleaning always matters.
- **Grounded realism.** Real-world scale, real materials, real light. Dry humour in the junk and the notes people left behind. No cartoon shapes, no bouncing numbers.
- **A field instrument for an interface.** The HUD and menus read as Lumi's own survey panel: stencilled plates, engraved rules, gauges, amber and cyan indicator lamps (`docs/STYLE.md` section 10).
- **Own vocabulary.** Bale, chest, scale, workbench, district, crew, Bloom Core, regrowth stages. New terms come from salvage and ecology, never from another game.

## 3. Honest assessment

### What exists
A very large 3D game: about 170,000 lines of GDScript in 601 files, 967 passing tests, a walkable true-scale globe (163,842 hexes, 10 hub sites), a detailed hero robot, six robot types, planting and five regrowth stages, base levels, research, story, events, wildlife, photo mode, a character builder, Steam and localisation scaffolding, four partly built later planets and a post-game prestige mode. The engineering quality is good in places (tests, save round trips, dev tools, an autoplay bot).

### Measured pacing (bot, fresh game, Nov 9)
The bot plays about twice as fast as a new player.

| Beat | Bot time | Likely player time |
|---|---|---|
| First upgrade | 1.5 min | 3 min |
| First clean hex | 7.5 min | 12-15 min |
| Second and third hex | 14.1 and 20.3 min | 25-40 min |
| First robot | 24.5 min | 45-50 min |
| Ten hexes | 32.7 min | about 1 h |
| Base level 2 | 52.6 min | about 1 h 45 |

- Between minutes 4 and 20 income sits at 1-5 cubes a second and the bot buys almost nothing.
- Goals arrive in bursts with long gaps: 4, 6.6 and 6.2 minutes early, then **19.9 minutes with no goal at all** (32.7 to 52.6), 15.6 more (to 68.2), and none in the last 32 minutes of the run.
- After 100 bot-minutes: 74 hexes cleaned out of 163,842, base level 2.
- Earlier whole-planet runs put Verdance at 25% after 2 bot-hours and 50% after 7.

### Against the pillars

| Pillar | Verdict | Why |
|---|---|---|
| 1 Easy to pick up | Partly | The first steps are now clear (one objective card). But the player meets three tools, a hotbar, a tabbed workbench, a command view, a hologram map, a lens view, requests, a codex, keepsakes and a locker. Too many surfaces for "understood in seconds". |
| 2 Fast-moving | **Fails** | A hex takes 6 minutes by hand. Much of the early game is walking between trash and the bin. The owner's own note after playing: "the start is too slow, I already want to quit". |
| 3 Real grind | Partly | The hands-on sweeping is real. But research costs real-time waits, the garden is slow on purpose, and after the first hour robots do the work while the player watches. |
| 4 Never boring | **Fails in the middle** | Mechanics exist but arrive unevenly, with a 20-minute empty stretch before base 2. One upgrade path is clearly best. There is no power-spike rhythm. |
| 5 Depth | Passes, unfocused | Plenty of systems, but many are side features (prestige mode, weekly seed, museum, song collecting) built before the core loop was fun. |
| 6 Polish | Uneven | The hero model and globe tech are strong. Open visual issues remain (far water, harsh globe light, bale clipping, hairlines on the ground) and all sound effects are synthesised. The HUD is generic rounded pills and a hotbar, restyled several times without one identity. Against the realistic direction, the yard still leans toy-like: a teal and orange workbench, a white rocket-shaped pod, confetti-bright junk, a cartoon robot on the loading screen (`screenshots/audit/play.png`). The planet readout shows "0.0000%". |

### The four biggest problems
1. **Planet 1 cannot be finished.** On the round globe nothing sets the "planet restored" state: the old ending lived in a flat district that was retired, and Verdance's restoration is capped at 68% until tools arrive from later planets. There is no ending to reach.
2. **The first hour is too slow and too empty.** See the table above.
3. **Planet 1 is not separable.** Planet-specific logic is hardcoded: 200 planet-name literals across the code, `if planet == 0` branches, global data files shared by all planets, one flat save with no per-planet section, and two world assemblers (`scenes/slice.gd`, 1,506 lines, and `scenes/slice_orbit.gd`, 1,157 lines) with 78 flat-or-globe branches. The flat world is no longer playable but its code is still there.
4. **Breadth before depth.** Five planets, a prestige mode and dozens of side systems exist while the core loop fails pillars 2 and 4.

### Too close to a reference game
The repo's own notes name the main reference as the model for specific things. These need to become clearly ours:
- **The planet map view.** The owner already flagged it as too close ("legal risk", feedback item 40).
- **The workbench layout.** It was restyled to floating glass modules "like" the reference (feedback, Nov 8).
- **The hub's hero building.** A code comment describes it as the reference game's "big hub hall".
- **The overall structure:** a small walkable round planet covered in cells, with bots cleaning what the player never walks on. The owner asked for this by reference. The structure itself is a genre shape, but I cannot inspect the reference game from here, so every specific (cell shape and outline look, crew control, map, hub layout, terms) gets a side-by-side originality check by someone who can (task M1-14, then again in M5 and M8).

## 4. Proposed redesigns

| # | Change | Why |
|---|---|---|
| R1 | **Give Planet 1 a real ending.** Verdance is fully restorable on its own. Remove the 68% cap and the dependency on later planets. Restoration is the sum of its districts; when the last district thrives, the regrowth front sweeps the whole globe in one big finale, followed by an end-of-demo screen and a hook (a signal from the next world). | Problem 1. The brief requires a "planet restored" moment. |
| R2 | **Districts as chapters.** The hub sites become districts restored in sequence. Each one introduces one new kind of pollution and the tool for it, and ends with a pollution **source** Lumi must shut down in person. Planet 1 uses 6 districts for the ending (the other sites become optional extra ground). | Gives the short/medium/long goal ladder (F4), a new mechanic every 30-40 minutes (F6), and a paced path to the ending. |
| R3 | **Faster hands.** Smaller first hexes, trash right at the pad, the bin a few steps away, a first clean hex inside 3 minutes and then one every 1-3 minutes. Early upgrades change how sweeping feels (wider beam, bigger chest), not just numbers. | Problem 2, pillar 2. |
| R4 | **Apprentice robots.** A robot type can only handle a pollution kind Lumi has mastered by hand, and its speed scales with that mastery. Crews work best near Lumi. Robots arrive around minute 20 as helpers, not replacements. | Pillar 3: upgrades and automation amplify the grind instead of replacing it. Keeps the owner's earlier call that automation comes later. |
| R5 | **No waiting for timers.** Research progresses from field work (cleaning, planting, finds), not from the clock. Plant growth is pushed by watering and tending. Offline time pays a small capped bonus only. | Pillar 3. Removes "wait" from the loop. |
| R6 | **Rigs: fitted modules with trade-offs.** Three slots on Lumi (arm, chest, drive). Each slot has modules found or built from salvage; one fits at a time and shows on the model. Linear upgrade tracks stay as the steady amplifier. | Pillar 4 (meaningful choices) and the identity (the robot visibly changes). The character-builder slot system already supports it. |
| R7 | **Surge.** Active sweeping charges the Bloom Core; a full core releases a short, loud burst of cleanup or regrowth that grows with progress. | F6 and F9: a power spike the player earns and triggers. |
| R8 | **One world assembler, flat world removed.** Delete the flat game's world code and the 78 flat-or-globe branches. Split world assembly into small builders under `world/`. | Problem 3. Half the complexity serves a mode nobody can play. |
| R9 | **PlanetDefinition and per-planet data.** Everything unique to Verdance moves to `planets/verdance/`. Shared systems read the current definition. Save format becomes `global` plus `planets.<id>`, with migration. | Problem 3; the brief's reusability rule. |
| R10 | **Park what Planet 1 does not need.** Out of the shipped flow and the export: the four later planets, the solar-system travel layer, the prestige mode and its heirlooms, the endless post-game loop, the weekly seed, the three-profile system (one save plus a backup), and the flat frontier districts. Code that is clean and reusable moves to `parked/` with its tests; the rest is deleted. Kept but trimmed: story, events, wildlife, photo mode, the character builder, song finds. | Problem 4. Focus. Nothing is lost for good: git keeps it, and `docs/FUTURE.md` lists what to bring back. |
| R11 | **One UI identity.** Rebuild the HUD, workbench, map and menus on the field-instrument style. New map view and workbench layout of our own. | Pillar 6 and the originality rule. |
| R12 | **A fast balance simulator.** A headless model of the economy that runs a whole planet in seconds from the same data files, next to the slower full-game bot. | The bot takes 30+ real minutes per game hour, too slow to tune with. |

Only R1 and R2 change how Planet 1 is structured; neither touches the core premise or the art direction.

## 5. Architecture

### Today
- Autoloads: EventBus, Settings, GameState (all state as plain data, 10 Hz sim tick), Economy (loads `data/*.json`), SaveManager, Audio, Story, Vfx, DevHooks and others.
- `scenes/slice.gd` builds the world and acts as a façade that other scripts reach into about 1,000 times. On the globe it hands off to `scenes/slice_orbit.gd`.
- Globe tech is solid and already per-planet by data: `planet/sphere/*` (grid, terrain, cells, threaded streaming), `planet/orbit/*`, `planet/sites/*`, `GlobeSpec` from `data/planets.json`.
- Content is mostly JSON (55 files in `data/`), but the files are global, not per planet.
- Save: one dict, version 4, plus a separate globe section with its own schema 2. Two save trees (flat and round) and three profiles.

### Target
```
Planets (autoload)  ->  PlanetDefinition (planets/<id>/planet.tres)
                          |- globe spec, districts and sites
                          |- pollution types, resources
                          |- upgrade tracks, rigs, research
                          |- regrowth stages, restoration rule, ending
                          |- tutorial steps, goals
                          |- balance curves
                          |- visuals (env hook, palette, sky), music set
World (world/*)     builds a playable planet from the definition, in a fixed documented order
Systems (systems/*) cleanup, regrowth, economy, upgrades, research, crew, tutorial runner, goals: all read the definition
Save                {version, global, planets: {<id>: ...}, current_planet}
```
Steps (milestone M1, in this order, each behind the full test suite):
1. Remove the flat world and its branches (R8).
2. Split `slice.gd` + `slice_orbit.gd` into `world/` builders, keeping the façade until callers are moved.
3. Add `PlanetDefinition`, the `Planets` autoload and `planets/verdance/`; move Verdance's tables and scripts there; make `Economy` load through the definition.
4. Replace every planet-name literal and index branch in shared code with definition fields or hooks.
5. Park later-planet content (R10).
6. Add the dummy test planet and the reusability test.

## 6. Planet 1 bug list

Severity: **P1** blocks finishing or loses progress, **P2** hurts the experience, **P3** cosmetic. "Verify" means it was reported and its current state is not yet confirmed on the merged build. The Nov 9 bot run (100 game minutes, 74 hexes cleaned, base level 2) produced no script errors.

| # | Sev | Bug | Source |
|---|---|---|---|
| B1 | P1 | Planet 1 has no reachable ending on the globe (nothing sets the restored state; 68% cap). | Audit |
| B2 | P1 | A reload resumes from the last autosave, not the state at exit. | Roadmap, open |
| B3 | P1 | A hex can stick at 96% with no findable pieces (the 95% auto-clear rule). Verify. | Owner item 36/39 |
| B4 | P1 | Objective chain is strictly ordered; doing steps out of order may stall it. Verify each step. | Audit |
| B5 | P2 | Long stretches with no goal: minutes 33-53, 53-68 and 68-100. | Bot run |
| B6 | P2 | The bot is blocked by a lake when going to water plants before Hover Jets (3 times in 60 min); a player would be too. | Bot run |
| B7 | P2 | Bot stuck-escapes climb during the garden phase (11 by 57 min, 85 by 100 min). Find the pathing cause. | Roadmap, open; bot run |
| B8 | P2 | Carried bale clips into Lumi's body. Verify. | Owner item 22 |
| B9 | P2 | Planted plants are hard to see, so watering has no feedback. Verify. | Owner item 51 |
| B10 | P2 | Too many messages at once; repeated WREN lines. Verify after the "calm" pass. | Owner items 45, 47, 49 |
| B11 | P2 | Far water reads as a flat grey plane; lake edges glitch. | QA 12, owner 16 |
| B12 | P2 | Lake water not yet checked on the real renderers (Forward+, Metal). | Roadmap, open |
| B13 | P2 | Globe daylight is harsher than intended; the pad looks pale at noon. | Roadmap, open |
| B14 | P2 | Two eye systems (shader shapes and the builder overlay) after the hero merge; the five other designs' add-ons still fit the old head. | Merge, hero handover |
| B15 | P2 | Loading takes about 15 s with a frame of about 0.8 s. | QA 23 |
| B16 | P2 | New texts are not translated. | Roadmap, open |
| B17 | P2 | Low preset: very high litter instance counts; frame rate at risk on weak machines. | QA 24 |
| B18 | P3 | Thin straight line across the junk field and faint lines on the pad. | QA 13 |
| B19 | P3 | Three workbench meshes sit under the ground. | QA 3 |
| B20 | P3 | Objects leak at exit (ObjectDB warnings). | QA 35 |
| B21 | P3 | The bot's report shows no robots on the globe (tool bug). | Bot run |
| B23 | P2 | The magnet on the globe is uncapped and pulls pieces that are buried or too heavy for Lumi to lift (owner rule: capped, never pulls what Lumi cannot lift). The old cap was flat-only. | M1-04 review |
| B24 | P1 | Confirmed: junk hidden inside building footprints leaves a hex stuck below 100%. | Triage (B3) |
| B25 | P1 | Confirmed: buying the Baler before finishing "fill the bin 3 times" stalls the first objective. | Triage (B4) |
| B26 | P2 | "Finish a research project" completes by itself when the Bot Bay is bought. | Triage |
| B27 | P2 | The watering can refills only inside one unmarked 10 m cell at the scale; the bench and greenhouse are outside it. | Triage |
| B28 | P2 | The objective card waits 11 minutes on "Build a Haul Bug" while later steps are already done. Belongs with the pacing work. | Triage |
| B29 | P3 | `--quit-after` counts real seconds; the docs say game seconds. | Triage |
| B30 | P2 | The rocket's recharge after a hop never starts. | M1-04b |
| B31 | P2 | `EventBus.shake_requested` has no listener, so screen shake never happens. | M1-04b |
| B32 | P3 | `boot.gd` still reads the old `--orbit` flag. | M1-04b |
| B22 | P3 | Other-planet issues (hauler paths, finale camera, fauna upright) are out of scope and leave with R10. | Roadmap |

**Fixed and merged (Nov 10):** B8, B21, B23, B24, B25, B26, B27, B29, B30, B31, B32, each with a regression test. Still open: B1 (the ending, task M1-10), B5 and B28 (pacing, M3), B9 and B11-B13, B18, B19 (visual, M5), B14 (design polish, M5-13), B15-B17, B20 (performance and translation, M7-M8), and B33 below.

| B33 | P2 | Nothing asks the player to buy the Research Desk, so "Finish a research project" can sit open for a long time. | Bug-fix pass |
| B34 | P2 | A long bot run printed NaN transform errors and the crew stalled from minute 73 to 80; `--quit-after` did not stop that run. Needs triage. | Simulator calibration run |

Triage is done: `docs/reviews/TRIAGE_M1.md` has the evidence, causes and suggested fixes. B2 was already fixed; B6 and B10 did not reproduce; B7 and B21 were faults in the bot and are fixed there; B9 needs a rendered check.

## 7. Core loop and progression

### The loops
- **Seconds:** hold to sweep. Pieces fly into the chest; the gauge climbs; the pitch rises.
- **Half a minute:** chest full. Press a bale (a short timing skill: a good press is worth more) or tip loose trash in the bin. Drop it on the scale. Paid.
- **Minutes:** the hex ring fills as the hex empties; at 95% the rest is swept away and the ground turns. Field data and stock come in. Fit an upgrade. The next hex goes faster.
- **Tens of minutes:** a district climbs its regrowth stages (clean, planted, growing, sustained, thriving). Each stage pays out and changes the look. The district's new pollution type needs its tool; mastery by hand teaches the crew.
- **Hours:** shut down each district's source, bring every district to thriving, trigger the Bloom.

### Grind loops that keep hands busy
1. **Sweep and press** (always): volume, press quality, streaks.
2. **Mastery** (from minute 15): each pollution kind has a mastery bar filled only by Lumi's own work. Mastery raises Lumi's rate on that kind and sets what the crew can do.
3. **Tending** (from minute 25): planting and watering push growth directly.
4. **Sources** (one per district): a multi-step job only Lumi can do, the district's set piece.
5. **Finds** (always): buried parts, notes, songs, rig modules, secrets.

### Progression map (player time, target)

| Time | District | New mechanic or spike |
|---|---|---|
| 0:00 | Landing | Sweep, bin, first upgrade |
| 0:03 | 1 Old Town | First clean hex; chest and beam upgrades |
| 0:08 | | Baler: pressing skill, bales pay more (spike) |
| 0:15 | | Signal tower: WREN returns. Mastery starts |
| 0:20 | | First apprentice robot; crew zones |
| 0:30 | | First seed: planting and watering |
| 0:40 | | District 1 source. First rig slot (spike) |
| 0:50 | 2 | Heavy wrecks: lifting and cutting. Haulers |
| 1:20 | 3 | Fouled water: skimming. Hover drive (spike) |
| 1:50 | 4 | Smog: scrubbers clear the sky. Surge unlocked (spike) |
| 2:25 | 5 | Poisoned soil: cleansing plants. Crew mark II |
| 3:00 | 6 | Everything at once, at scale. Base at full level |
| 3:45 | | Last source. The Bloom: planet restored |
| 4:00 | | End screen, the hook, free play for 100% |

Pollution kinds 2-5 reuse systems that already exist (lift classes, lake skimming, the air recycler, planting) and present them as district chapters.

## 8. Tutorial flow

Data-driven steps in the planet's folder. Each step has a trigger, a one-line instruction with the key glyph, an optional world pointer, a completion condition and a skip rule (already done counts). Steps never block: any step whose condition is already met completes silently, and the chain never requires an order the game does not enforce. Skippable from the pause menu and replayable from settings.

| Step | Trigger | Teaches |
|---|---|---|
| Sweep | Player gains control | Hold to sweep |
| Bin | Chest first full | Tip loose trash in the bin |
| Bench | First 30 cubes | Fit an upgrade |
| Hex | First upgrade fitted | Clear the outlined hex; the ring |
| Baler | Baler affordable | Press and timing; the scale |
| Tower | 3 bales sold | Build; WREN explains the goal |
| Mastery | First mastery tick | Hand work teaches the crew |
| Robot | Bot bay built | Build a robot, give it a zone |
| Seed | Seed found | Plant and water |
| Stages | First planted hex | Regrowth stages and the district bar |
| Source | District at stage 3 | The source job |
| Rig | First module found | Fit a module; trade-offs |
| Travel | District 1 thriving | Move to the next district |
| Later tools | First contact with each new pollution kind | One line each, at the moment of need |

## 9. Balance plan and target playtime

- **Target:** a first-time player reaches the planet-restored ending in **about 4 hours** (acceptable range 3.5 to 5). Full completion (every find, every optional site) about 8 hours. The bot should finish in about 2 hours.
- **Cadence rules** (the simulator and the bot both check these):
  - first payout within 20 s, first upgrade within 90 s, first clean hex within 3 min
  - a small win at least every 40 s; an affordable purchase at least every 3 min in the first hour and every 4 min after
  - no gap between goals longer than 4 min
  - a new mechanic every 10-15 min in the first hour, every 30-40 min after
  - a power spike every 30-40 min, each at least doubling the player's cleaning rate
  - hand work stays at least 30% of total cleaning output at every point
- **Method:** `tools/pace_sim` models income, costs, mastery and crew from the planet's data and prints the beats above in seconds. The full-game bot confirms each milestone build. Numbers change only with simulator output attached.
- **Curves:** track costs grow geometrically within a tier and reset at each district's new tier, so time-to-next rises gently inside a district and drops at each spike. Formulas are documented in the playbook.

## 10. Technical risks

| Risk | Mitigation |
|---|---|
| Size: 170k lines, a 1,000-reference façade | Remove dead code first (R8, R10); move callers gradually behind the tests |
| Parallel development on the main branch by another session | One lead at a time; see the open question in the Phase 0 report |
| Save format in flux (v4 plus a separate globe schema, two trees) | One schema, atomic writes with backup, fixtures and a migration test for every old format |
| Performance on real hardware is unmeasured here (software rendering only) | Performance milestone uses headless timings plus an owner-run capture script; budgets per preset |
| Physics at 120 ticks per second | Measure; drop to 60 if movement feel survives |
| Streaming hitches and 15 s loads | Build budgets per frame, shader warm-up, load-time targets in the Definition of Done |
| Input: touch does not exist yet | All input already goes through actions and an input source; the UI rules require touch-sized targets now, and a touch layout is a later task |
| Resolution scaling | Container-only layouts, tested at five aspect ratios and the interface-scale range |
| Renders in this environment are slow | GL renderer for checks, small resolutions, one at a time |

## 11. Definition of Done (Planet 1)

**Playable**
- [ ] A new game reaches the planet-restored ending and the end screen with no dev flags.
- [ ] The bot plays start to ending with no script errors, softlocks or stalls longer than 4 minutes.
- [ ] Full test suite, save round trip and exit check pass. Warnings audit is at 0.
- [ ] No open P1 or P2 bugs.

**Feel**
- [ ] Simulator and bot meet every cadence rule in section 9.
- [ ] Player time to ending is within 3.5-5 hours (bot about 2 hours).
- [ ] The engagement review finds no stretch flagged boring, confusing or unrewarded.
- [ ] Every core action has sound, motion and a number within 100 ms.

**Saves**
- [ ] Quit at any moment and reload to the same state. Every older save format loads.
- [ ] A corrupted save falls back to the backup.

**Tutorial**
- [ ] Every system is taught at the moment of need. The tutorial can be skipped and replayed, and never blocks when steps are done out of order.

**UI and polish**
- [ ] One UI identity on every screen; works at 16:9, 16:10, 21:9, 4:3 and 1280x800; mouse, keyboard and controller.
- [ ] 60 fps on the Medium preset on the target machine; loads under 10 s; no frame over 100 ms in play.
- [ ] No placeholder or TODO code in shipped systems.

**Originality**
- [ ] The side-by-side originality check passes for the HUD, map, workbench, hub layout, terms and progression.
- [ ] No other game is named in code, data or text.

**Reusability**
- [ ] No planet name or planet index in shared code.
- [ ] The dummy planet loads, plays 60 seconds under the bot and saves/loads with no code change.
- [ ] `docs/PLANET_PLAYBOOK.md` walks through making a new planet from the templates.

**Release**
- [ ] Demo export builds for Windows, Linux and macOS with version shown, credits, settings that persist and an end-of-demo screen.
