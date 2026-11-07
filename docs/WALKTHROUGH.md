# Walkthrough: New Game to the ending

The critical path from a fresh save to the true ending (the Cradle comes home) and the post-game
Seed Ark loop, with every gate and what opens it. Times are **game time** from the autoplay bot
(`tools/autoplay.gd` + `tools/autoplay_campaign.gd`, see "Measuring" at the end); a first-time
human player is typically 2-3x slower, which puts the whole game at roughly **15-22 hours**.

**Measured full run** (bot, game time; New Game -> Cradle -> Seed Ark, 7 continued `--save-dir`
stages, 16x; screenshots/autoplay_report.json `campaign_full_run_min`):

| Stage | Bot time | Duration |
|---|---|---|
| Old Town to first launch (final pacing re-run) | 0:00-1:14 | 74 min (full run: 102 with the older pacing) |
| Second district (Harbor Row) to base 5 + launch | 1:42-3:00 | 78 min |
| Dust Flats (base 5 at 4:14, 50% Growing at 4:42) | 3:00-5:08 | 128 min |
| Frozen Port (base 5 at 5:40) | 5:09-5:45 | 36 min |
| Sunken City (3 pump stages, base 5 at 6:48) | 5:46-7:05 | 80 min |
| Cradle Returns (pad, 70% Growing) to finale | 7:06-7:59 | 53 min |
| Finale + credits, then Seed Ark wave 1 | 7:59-8:01 | |

Longest stretch without a goal in the final first-district run: 13 min (waiting on Drip research).

`[bot]` marks the measured bot time; `[est]` is an estimate where the stage was jumped with dev
hooks instead of played through.

## 0. Intro (0:00-0:02)
- Title screen > New Game. The landing-pod cinematic plays (Space skips). Lumi (LM-1) wakes with the
  Bloom Core at 4%: "Grow something."
- Gate: none. The pod stays in the yard as a landmark.

## 1. Old Town: clean, bale, sell (0:00-0:15)
- Hold LMB to scoop, RMB/C to press a bale (Perfect band 90-100%), carry it to the scale. First bale
  ~0:20 s, first sale ~0:40 s, first workbench upgrade ~0:40 s [bot].
- Clean the first hex (~2 min): every piece of junk in it. Hex bonus + 10 Data.
- Memory shards and buried robot parts (the detector beeps) appear as hexes clean.
- Goals: scoop 15 > bale > sell > upgrade > first hex > Perfect bale > 5 upgrades > 10 bales > ...
- Gates: none. Currencies: cubes (selling), Data (cleaning, shards, robot bales), materials (sheet
  metal / plastic / glass from scooped junk; finite per district).

## 2. Robots and research (0:05-0:30)
- Research (workbench, Research tab) costs Data and real time. Tier-0 nodes are 25 Data.
- First Scoopie ~0:07, Haul Bug ~0:09 [bot] (build cost + parts; Haggle's sells missing rusty parts).
- Command (B): paint zones for crews. Base level 2 (1.5k cubes + 25 metal + 15 plastic) ~0:11-0:20.

## 3. The first seed, and the slow garden (0:12-0:60)
- A green signal leads to the old greenhouse: the seed tin (a small story moment). Plant with tool 2,
  water with tool 3 (refill in the yard).
- On purpose, the garden is slow here: few seeds, slow growth, hand watering. Cleaning drives
  progress and the goal chain (hexes 10-30, upgrades, bales, recycler, base 3).
- Seedling Blueprint (160 Data) and Drip Blueprint (200 Data) need a level-3 base (Depot Station,
  ~0:43 [bot]): Seedling ~0:49, Drip ~1:03 [bot].

## 4. The garden takes off (~1:00-1:30)
- **Pollinator Survey** (Botany, 200 Data after Wild Mint, base 3; ~1:10 [bot]): +75% plant growth, +60% seeds per
  bloom. With Seedlings planting and Drips watering, hexes go Planted > Growing > Sustained > Thriving
  in minutes. The goal chain pays out a run of garden goals here ("the garden takes off").
- Sustain is done by watering robots (Drip, Multibot on water) plus Water Tanks; never sprinklers.
- Thriving hexes pay a garden stipend (cubes/min, capped at 900/min) and wildlife Data (0.6/min each),
  so a finished district keeps moving.
- Bloom Core 25% (WREN's signal clears, garden-deck memory) lands in this stretch.

## 5. Old Town base levels 3-5 and the rocket (1:00-1:45)
- Base 3: 12k cubes + 90 metal / 60 plastic / 30 glass. Base 4: 28k + 100 plastic / 40 glass.
  Base 5: 30k + 80 plastic / 30 glass. Measured: base 3 ~0:43, base 4 ~1:09, base 5 ~1:14 [bot].
- Base 5 builds the launch pad and the Mk I rocket. "Launch the rocket onward" (globe, M).
  Rocket cells recharge 5 min after each launch (Mk II-IV faster; Mk IV warps).

## 6. Second district (1:45-3:00)
- Any ordinary district (each base starts derelict at level 1; robots stay in their district, research,
  upgrades and currencies are global). Clean, plant, sustain, base to 5 again. Measured: arrive 1:42,
  base 5 2:32 [bot].
- Goals: fix up the new base (3, 4), Clean 50 hexes, 800 blooms, 40 restored hexes, second base at 5.
- **Dust Flats unlock**: research Dune Charts (logistics line: ... Haul Routes > Rocket Cargo >
  Dune Charts, 1,920 Data in all) **and** two bases at level 5.

## 7. Dust Flats (3:00-4:30)
- Radius-4 frontier (60 hexes), bulkier junk, bales x3, base costs x4 (286k cubes for levels 2-5).
- Sandstorms every 5-8 min (first after 2.5 min) re-dust clean, bare, unplanted hexes that no
  Sustained hex shelters. Plant early; Dune Fences research widens shelter.
- The well is dry: Drips refill at Water Tanks only (Dew Condensers research triples tank refill).
- **Frozen Port unlock**: Thermal Lance research (cleaning line, 1,775 Data), three bases at 5, Dust
  Flats base at 3. The bot finishes Dust (base 5 + 50% Growing) before moving on.

## 8. Frozen Port (4:30-6:00)
- Junk is locked in ice: Lumi's beam thaws a hex slowly (twice as fast with the Thermal Lance);
  heaters (E on ice, 90 cubes growing x1.32, max 16) thaw their hex fast and warm the neighbours.
- Outdoors only cold-hardy plants grow after Cold-Hardy Seeds (Botany line, 2.3k Data); before that,
  greenhouses (E with the seed tool on a clean hex; 450 cubes growing x1.25) take any seed.
- **Sunken City unlock**: Pump Works research (hydrology line, 2,625 Data), four bases at 5, Frozen
  Port base at 3.

## 9. Sunken City (6:00-7:30)
- Mostly water: Skimmers net the floating junk. When 80% of the next ring's water hexes are clean the
  old pumps run, the water drops a stage and that ring becomes streets with stranded junk (3 stages).
- Base costs x8; bales x8.

## 10. Cradle Returns and the finale (7:30-9:00)
- **Unlock**: Ark Beacon research (5,045 Data in all, needs Dune Charts + Dew Condensers), all three
  frontier bases at level 5, and every frontier at least 50% Growing.
- The base starts at level 3 (ground crews kept it). Clean the 7-hex landing pad, plant it and get
  every pad hex to Sustained; get 70% of the district Growing.
- Then `FrontierDistrict.complete()` fires `EventBus.cradle_district_complete` once. That sets
  `flags.cradle_returned`, which is the **Verdance Bloom** milestone (data/bloom.json): the Bloom Core
  hits 100% and `Bloom.play_finale()` plays the ark-landing cinematic (story/bloom_finale.gd).
- After the finale the **end credits** roll once (ui/credits_roll.gd, built from docs/CREDITS.md;
  any key skips). The title screen's Credits page shows them any time.
- Bloom Core beats along the way (story/core_charge.gd): 25% ~Old Town garden, 50% ~Dust Flats,
  75% ~arriving at Sunken City / the Cradle, 100% = the finale.

## 11. Post-game: the Seed Ark loop
- The ark stays parked over the district; the game carries on. Every bloom anywhere counts toward the
  next Seed Ark wave (120 x 1.5^n blooms, rewards x1.35^n). Goals: plant one and three waves.
- Later Verdance Bloom milestones (Wide Bloom, Evergreen) keep going: 6 / 12 districts in bloom or
  3% / 5% of the planet. Rocket Mk II-IV, contracts, the Collection, eggs and achievements stay open.

## 12. Cradle Mode and Garden Mode (post-game, wt/late)
- **Ark Bridge** (Pause > Ark Bridge; a story toast and WREN point to it after the finale). Opening it
  banks the Starseeds Verdance has earned: 4 per Seed Ark wave, 6 per Bloom milestone, 1.5 x sqrt(Thriving
  hexes), 20 for the Cradle, 3 per level-5 base (a full campaign is roughly 80-110).
- **Heirlooms** (10, data/cradle.json) are bought there and kept forever: plant growth, hopper, scoop
  rate, bale value, move speed, seeds per bloom, and a starting kit (cubes, Data, seeds, waiting robots,
  known research).
- **Seed a new world**: the preview shows its name, type and two modifiers. Launching saves Verdance,
  makes a new save slot and lands Lumi's pod in the new world's driest town. The new world starts
  ruined (base level 1, junk everywhere, the restart checklist) and runs the whole campaign again, with
  the kit and Heirlooms. Verdance (and every other world) stays one "Travel" away on the bridge.
- **Each world looks like itself** (wt/worlds2): Ice Moon (pale icy sky, a ringed gas giant, frosted
  city, the old seed silo iced to the waist), Desert World (amber haze, twin moons, sun-bleached city, a
  solar tower in a field of fallen mirrors), Ocean World (deep blue, a big tide moon, salt-stained
  coastal city, a storm-surge barrier, more puddles), Marsh World (green-grey mist, overgrown city, a
  cooling tower gone to shelf fungi), Rust World (rust-red dusty sky, a shattered moon, corroded city, a
  ship-breaking gantry). The weather eases as the base is restored; trim lights come on at base 3.
  WREN tells each world's thread: arrival, two memories, halfway, restored.
- **Title screen > Profiles**: three save profiles (own worlds, Heirlooms, progress); Continue a profile,
  then pick a planet when it has several; New, Rename, Delete. Old saves are profile 1.
- **Garden Mode** (H, or Pause > Garden Mode; after the finale or with this base at level 5): place
  decorations on clean ground. Each district's charm speeds its plants up a little (up to 8%).
- Goals after the Seed Ark: open the Ark Bridge, place a decoration, buy an Heirloom, 10 decorations, 5
  kinds, 5 Seed Ark waves, 30 curiosities, seed a new world, 20 charm, 10 Heirloom levels, a second
  new world, 38 curiosities.
- Measured (bot, 16x, game minutes from landing; Verdance fresh vs the first new world, an Ice Moon
  with Rich Salvage + Heavy Rain):

| Milestone | Verdance | New world, no Heirlooms | New world, 12 Heirloom levels |
|---|---|---|---|
| Base 2 | 18.5 | 14.1 | 5.6 |
| Base 3 | 39.0 | 32.8 | 24.9 |
| Base 4 | 62.4 | 78.6 | 54.6 |
| Garden takes off | 64.7 | 78.0 | 50.7 |

- Dev: `--post-finale` (Verdance won, Seed Ark open), `--open=ark`, `--world=N --heirlooms=...`.
  Staged autoplay into Cradle Mode: `godot --headless --path . -- --fresh --save-dir=late --post-finale
  --autoplay --time-scale=16 --quit-after=700` (milestones `cradle_mode_open_s`, `first_decor_s`,
  `heirlooms_s`, `seed_world_s`, `w2_*` in screenshots/autoplay_milestones_late.json).

## Gates and reachability (checked)
| Gate | Needs | Earned from | Verified |
|---|---|---|---|
| Robots | build cost + parts | cubes; parts dug up / Haggle's | autoplay |
| Research | Data | hexes cleaned 10, restored 15, shards 20, robot bales 1, blooms 1.5, Thriving wildlife 0.6/min | autoplay (all 38 nodes done by ~3:00) |
| Base levels | cubes + materials | selling, garden stipend; scooped junk | autoplay x2 districts + Dust |
| Dust Flats | Dune Charts + 2 bases L5 | | autoplay |
| Frozen Port | Thermal Lance + 3 bases L5 + Dust L3 | | autoplay |
| Sunken City | Pump Works + 4 bases L5 + Frozen L3 | | autoplay / dev jump |
| Cradle | Ark Beacon + 3 frontier bases L5 + 50% Growing each | | dev jump + test |
| Finale | Cradle complete | | save round trip (also mid-cinematic) |
| Goals | 156 goals; every type/key checked by tests/test_beat.gd | | test |

Dead ends found and fixed while mapping this (see docs/BALANCE.md "Whole game"):
- The finale could play early in an ordinary district (three districts in bloom), leaving the Cradle
  Returns ending a dud; and the Cradle path never opened the Seed Ark. Now the Verdance Bloom *is* the
  Cradle.
- After the 100-goal chain ended (Clean 100 hexes) there were no goals for the whole late game;
  research goals sat inside Old Town where Data runs out; builder goals walled the chain.
- In a finished district research stalled forever (no Data source) and income fell to a 400/min cap.
- The rocket's recharge ran on the wall clock (fine for players; it stalled time-scaled runs).

## Measuring
- Fresh run in stages (each stage saves to `user://saves_NAME`; milestones add up in
  `screenshots/autoplay_milestones_NAME.json`, game time):
  `godot --headless --path . -- --fresh --save-dir=camp --autoplay --time-scale=16 --game-minutes=600 --quit-after=3600`
  then the same without `--fresh` to continue. `--stop-at=<milestone>` (e.g. `base_5_s`,
  `arrive_frozen_port_s`) saves and quits there; `--no-travel` keeps the bot in its district.
- Jump to a stage with a realistic state: `--frontier=frozen_port --research=a+b+... --give=200000 --unlock-seeds --autoplay`.
- Finale and credits: `--frontier=cradle_returns --frontier-done=3`; credits alone: `--credits=3`.
