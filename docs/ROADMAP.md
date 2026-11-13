# Greenfall Roadmap

Start here in a new session: `docs/PROGRESS.md` (what exists, known issues, next steps), `docs/PLAN.md` (milestones + owner feature requests), `docs/DECISIONS.md` (choices and assumptions), `docs/BUILD_PROMPT.md` (the owner's full brief).

## Current state of round Verdance (2026-11-10)

The round world is the game, and the work is on its first planet, Verdance. The owner's bar: it must feel finished, with no glitches, easy progress, and simple enough for a young kid (docs/OWNER_FEEDBACK.md, items 1-56). This section is the one status summary; everything below it is the detail and the history.

**Done**
- **Start:** a clean loading screen, Medium quality by default, simple settings, robot beeps under the intro lines, and an intro fall onto a planet covered in trash.
- **World:** Verdance has flat-world trash density. Every hub is a town with its own character, with street furniture, outskirts and waterfronts, and the land between hubs has junk fields, suburbs and industrial edges. Lakes read as water, and the shorelines are clean.
- **Start yard:** a flat, clean pad with trash right up to its edge, the bin bay next to the workbench, a fitted pod collider, and a tall smoke plume that marks home. No vehicle or buddy at the start.
- **Guidance:** one goal timeline with one card. The beam and ring lead only to places. Hint lines cover a full chest, a piece too heavy, too few cubes, nothing nearby and the way home. WREN says why you are cleaning and narrates the goals once the tower is up. Messages and beeps are cut down, and one-time lines play once.
- **Hexes:** a hex counts as clean at 95% and the rest is swept away. The first hexes hold no large items.
- **Workbench:** tiers unlock the tabs (Bot Bay, Research Desk, Request Board). Rows keep a fixed order, a click shows details, and locked rows say what unlocks them.
- **Robots:** the Scoopie comes first. Haul Bug and Skimmer plans arrive later by themselves. Haulers take Lumi's bales. The Command view works on a controller.
- **Story order (v8bot, item 79):** clean the glowing hex, Bot Bay, first robot, "Clean 2 hexes" (card: "Your robot cleans on its own."), "Clean 3 hexes" (WREN: "Your robot cleans on its own. One more hex, Lumi."), the first seed. There is no "show your robot where to clean" step and no zone goal: every robot type works on its own around its hub (nearest work first, robots spread over different hexes). The Command view (B) and zone painting stay as an optional feature the game never asks for; the first-minutes key strip leaves B out (the full list keeps it). The autoplay paints zones only with `--autoplay-zones`. Old saves on the zone step move on to "Clean 2 hexes" (`Objectives._drop_zone_step`, flag `objectives_v3`).
- **Command view calls (v8bot, item 80):** a painted zone calls the N robots of its job nearest by travel (`SphereCrew.zone_count` / `set_zone_count` / `_assign_zones`, `u["called"]`, saved as `zone_n`); the card's "Robots here: - N +" sets N (default all; click, keys - +, D-pad left / right) and shows how many are on the way / working there. A newly called robot drops a job outside the zone at once. The rest leave the zone to them while they have other work. The Haul Bug nag waits for its plans (`CrewTalk.needs_hauler`); in the Command view the event banner and the play HUD step aside. Dev: `--crew-zone=N --crew-zone-n=K --crew-zone-log`.
- **Growing and water:** plants are visible (sizes, soil, thirst). The first seed has a beacon. Hover Jets are needed to cross lakes.
- **Glim:** a story build, the lantern bot who held on to the pod.
- **Reach:** every collectible and objective target stands on reachable ground (`--target-reach`).
- **Map:** our own survey style with sprout, Lumi and plume glyphs. Travel is at the rocket (press E), not in the map. Glyphs no longer cover each other on the start hub, the map shows the HUD's planet %, and the round game has one system map.
- **Text:** all 3,992 strings are translated into German, French, Spanish, Brazilian Portuguese, Simplified Chinese and Japanese. A test fails when an early-game string has no translation.
- **Screens (v6screens):** every 2D screen fits 1280x720, 1920x1080, 2560x1080 and 1280x800 at interface scale 0.8-1.5 in all six languages and pseudo, and works with a controller alone (focus always shown, B closes). The WREN line keeps off Lumi and the goal card. Seed of the Week is hidden (data/weekly.json `enabled`). Settings no longer offers Number format, Best-value tags or the Pseudo test language. Checked with `--ui-audit` (docs/QA_VERDANCE.md); not yet seen in a render.
- **Checks:** the unit tests, the save round trip on the globe (with the shared-state checks of `tools/shared_roundtrip.gd`) and the two-process orbit reload. The dev checks are listed in CLAUDE.md.

**Open**
- **Release check (v7play, docs/RELEASE_CHECK.md):** a full bot playthrough to the drive (145 bot min), saves and reloads at five awkward moments, every menu path, and all the checks. Two things stand between Verdance and release: a crash at quit while a hub town builds (v6qa's Q7 is back: `--orbit-walk-in=1,380 --quit-mid-build=30` exits 134), and the owner's yes on the end-of-Verdance moment. Other planets are closed for now (data/homeward.json `open`, `closed`), with a "to be continued" beat after the drive. Should fix: first-hour gaps (13 and 11 min), the Haul Bug wait card, the far-station chain unmeasured by the bot.
- **Renderers:** every render so far used opengl3 (Compatibility). Nobody has looked at Verdance on Forward+ or Metal, and the owner's Mac perf run (`--quality=1 --perf`) is still to do.
- **Look:** the globe's light was harsher than the flat world's and the pad looked pale at noon. v5look's warm-light and matte-pad pass is merged, but the owner has not seen it yet. A flat grey sea on the horizon and a thin straight line across the junk field were reported and not rechecked since the water fix (docs/QA_VERDANCE.md, 12 and 13).
- **Known glitches (v6qa, docs/QA_VERDANCE.md "Known-glitch list"):** the loading-screen RID errors on a headless continue are not reproduced. A walk-in to a hub town still has single 50-100 ms build steps for about 2 s. The batched shader warm-up is not measured on real hardware.
- **Pacing (items 57, 58, 61, 63, 64, 75; v6pace, v8fix; release check O1-O3, O6, O7):** measured with the bot doing every far station's own chain (docs/BALANCE.md, "Verdance, the round planet"; knobs in docs/ADJUSTING.md). Pace 2.0 (was 1.45: base level 5 at 150K and the earlier first robot took the leave point down to 96 bot min; 1.9 measured below, 2.0 not measured). Bases 2-6 woken at 30, 43, 66, 85 and 117 bot minutes, Mk II 46, Mk III 90, the drive and the leave point at 118 with 21% of the hub regions clean (about 3.9 h for a person if people take twice the bot's time: **not verified**). First robot (Bot Bay after 1 clean hex, 450; Scoopie 250) at 15.3 / 8.7 / 15.4 bot min on three seeds (was 23; item 75 asked for about 12-13; the spread is the first hex's cash burst, see BALANCE.md); no card save over 15 min (longest 12.7); stations take 2-12 bot min; only six stations open the drive. Open: the leave point at pace 2.0 is not measured (117.5 at 1.9); other planets keep their old prices.
- **Autoplay:** the bot follows the card now (it saves for a priced step and sees only the card's goal). Its stuck escapes are fixed (1 in 160 minutes, v5play).
- **Bale clipping** into Lumi's body (item 22) has not been reproduced.
- **Translations** are machine drafts. No native speaker has reviewed them. In-world shop signs (PAWN, SHOE REPAIR, OLD TOWN) stay English in every language.
- **Map:** the survey's hex counts are a snapshot (they update on Re-survey), while its planet % is live.
- **Flat world:** removed (v6flat, docs/FLAT_REMOVAL.md): no flat mode, no `--flat`, no phase A prototype scenes. Old flat saves are copied into the round tree once at startup and migrate on load. The leftovers kept on purpose are listed at the end of docs/FLAT_REMOVAL.md.
- **Other planets** on the globe (Ochre, Rime, Anvil, Tidewell) are out of focus: Haul Bugs find no path there, and the Ochre finale camera is blocked.
- **Polish (item 56):** the v5 wave was still running when this was written (v5play: bugs from play-testing; v5look: light, sky, hinterland; v5load: loader, perf, saves). Add their results here.

## Update: yard machines and hub landmarks on the art kit (wt/v6yard, Nov 11)
- **Picture signs.** Every yard machine carries a round sign with one pictogram and no words
  (spanner, arrow into a bin, pressed cube, belt, sprout, mast with waves, robot head), so a small
  child can tell what it does. Look and size: `data/machine_art.json`.
- **Auto-baler and belt drive rebuilt** as kit models (`systems/camp/machine_art.gd`): the baler
  is a press head over a cube-sized chamber with a wide yellow hopper and a roller ramp; the belt
  drive has a fat finned motor with a belt guard. Far fewer draw calls than before.
- **Six hub landmarks rebuilt** (`planet/sites/hub_landmarks.gd`, `data/landmarks.json`): water
  tower, windpump with a seed vault, gantry crane lifting hull plates, signal mast, big wheel with
  gondolas, tall stack with fuel tanks. They follow the hub's level: broken and dark while the hub
  sleeps, lit and turning once it wakes, restored from level 3. Each has the same wake console.
- **Signal tower** legs and braces are chunkier. **Pod:** a repair cart, work lamp and cones stand by it
  while it is being mended. **Trash bin, workbench, composter, fabricator:** sign added, shape kept.
- Numbers: `tools/machine_stats.tscn`; budgets in docs/PERFORMANCE.md; knobs in docs/ADJUSTING.md.
- **Second batch:** the recycler is a kit model with its own sign (cube to nut); the four extra hubs
  have kit landmarks too: a tower crane whose jib turns (Crane Court's own kind `tower_crane`), the
  last bus at its stop, a lighthouse. All ten Verdance hubs' landmarks stand on clear ground.
- Open: no game render of any of this yet (the render queue never got its 7 GB). Shapes and paint were
  checked with an offline flat-shaded preview only. Other planets' biomes still use the old thin landmarks.

## Milestones (history, from the flat-world era)
- [x] M0 Setup, M1 Slice (city district, Aurora/Patch, baling, tutorial, lens view)
- [x] M2 Planet layer: 40k-hex planet, hand-held survey hologram (M), districts per base, rocket travel. Seamless sphere walking deferred (see DECISIONS).
- [x] M3 Robots: Scoopie, Haul Bug, Seedling, Drip, Skimmer, Multibot; Mk I-IV tiers with visual upgrades; crews with caps; Command mode (B) to paint zones and give orders; build/upgrade from Command.
- [x] M4 Story: intro landing cinematic, WREN, memory shards, first-seed cinematic, Ledger arc (acts 1-4, dump drones, jammers, relay), 17 easter eggs.
- [x] M5 Grow + sustain: planting, watering robots, refill tanks, hex levels Clean > Planted > Growing > Sustained > Thriving, compost press (seeds), wildlife.
- [x] M6 Water: lakes, skimmer robots, clarity (research), clean-lake refills.
- [x] M7 Automation + progression: conveyor feeder, auto-baler, recycler, research tree (30 nodes, Data currency), goals chain (50), base levels, rockets tab.
- [x] M8 Content/meta: Codex, 54 achievements, stats, cosmetics (6 unlockable Lumi designs with add-ons and slight buffs).
- [~] M9 Balance: mid-game autoplay bot (robots, research, Command zones, garden, base levels) and a 2-hour pass: first robot ~6 min, planting ~20, Sustained ~23, base 3 ~38, base 5 ~75 (district done); see docs/BALANCE.md. Re-run after merging Laser Reach / Multi-Lock.
- [~] M10 Polish: title screen, settings, music score, QA pass (40 fixes in flight); Windows/Linux/macOS builds from CI.
- [x] M11 Post-game: Verdance Bloom milestones, Cradle finale (the true ending, then end credits), endless Seed Ark waves, Cradle Mode (new worlds, Starseeds, Heirlooms, world modifiers, Ark Bridge), Garden Mode decorating. Whole game playable New Game -> Cradle -> Seed Ark -> new worlds; see docs/WALKTHROUGH.md.

## Next steps (history, written before the round world became the game)
0. Owner-side Steam/Apple setup: see docs/steam/README.md (app id, depots, signing). Website: enable Pages, fill website/config.js.
0b. Visual QA: see docs/VISUAL_QA.md (render checklist with dev-hook commands and status); its "todo" rows are the next sweep.
1. Play-test feedback from the owner (docs/PLAYTEST.md); fix what they hit first.
2. macOS: universal build works (ETC2/ASTC import enabled). For Steam: sign and notarize with the owner's Apple Developer account.
3. Longer balance: run `--autoplay --time-scale=8 --quit-after=600` and check goals keep a next step within 1-3 minutes past the first hour.
4. More districts content: 41 eggs now; more biome props (nets, satellites) if Poly Haven gets them; per-biome plants/wildlife.
5. Post-game (M11): done (wt/late). Next: per-world story threads with WREN, wildlife using the decor hook, tune Starseed income and Bloom thresholds after play-testing.

## Update: shared art kit (wt/kit, Nov 8) [kit]
- `art/kit/**`: materials (KitMat), bevelled geometry and Builder (KitMesh), props (KitProps), 7 state-aware buildings (KitBuilding: module_small/medium/large, tower, hangar, tank_farm, machine_housing) with `set_state` and `set_powered`, ground patches that replace flat slabs, a decal atlas, and a chunky wind turbine. API and art rules are in docs/ART_KIT.md.
- Paint and trims are colour-per-vertex, so a building is about 9 draw calls. Buildings get auto LODs. Everything is cached.
- Lineup render: `tools/kit_lineup.sh screenshots/kit/lineup`, or `--kit-lineup`. Tests: tests/test_art_kit.gd.
- Next: yard, anvil, ochre, seas and orbD adopt the kit. The kit can add more building kinds on request.

## Update: Tidewell + Rime hub sites at the art bar, on the kit (wt/p_seas, Nov 8)
- Tidewell (`planet/planets/tidewell/tide_props.gd`, used by `sites.gd` and the district env): new ore
  barge (lofted hull with boot-top, hoppers with slid lids, lattice conveyor boom, funnelled wheelhouse,
  windlass and chain, lost container), jack-up dredge rig (K-braced lattice legs through jack houses,
  panel-wall hull, stacked quarters, helideck, derrick, crane, bucket ladder, pipe racks, lifeboat, stair
  tower to a boat landing) and the hub raft (three plank platforms on pontoons with gangways, a slipway,
  shacks, crane, fuel tank, clutter). All parts are KitMesh.Builder keys on the Tidewell palette
  (white / sky, with yellow / orange / red utility parts); state follows restoration through
  KitMat (broken / repaired / restored); lamps light only when restored.
- Colliders: hulls, legs, cabins, tanks, booms and containers are PROP static bodies (skimmers, robots and
  Lumi stop at them; before, they drove through); raft decks and the slipway are WORLD.
- Rime: new `planet/planets/rime/rime_site.gd` (`RimeSite.place(id, root, stage, restore, opts)`, the
  TideSite API shape): hub_camp, derrick, borehole, hot_springs on local ice patches (drifts, ridges,
  cracks, a plated pad with kerbs; walkable trimesh) with kit cabins on skids, a greenhouse dome, tanks,
  comms mast, snowcat. Preview: `res://planet/planets/rime/site_preview.tscn -- --site=hub_camp
  [--site-stage=1 --site-restore=1 --time=0.9 (night)]`. `rime_ice.gdshader` gained `moss_centre`/`moss_off`.
- Tests: `tests/test_p_seas_sites.gd`. Renders: screenshots/p_seas/.
- Follow-up: reef coral, hub_stilts, buoy_field and the flat env's drowned towers and lighthouses are on
  the kit too (TideProps.drowned_tower / lighthouse; preview `--site-props`). Left: the flat env's base
  moorings, floating gardens and future platforms still use older parts.

## Update: loading screen keeps moving, Rime night glint (claude/greenfall-leftovers, Nov 8)
- **District build across frames.** Behind the loading screen `scenes/slice.gd` builds as a coroutine: the
  heavy first half (field generation, FieldView ground/mounds/junk/landmarks, litter, far junk, CityView,
  StreetDressing, sound synthesis) yields to the Loader whenever its slice is used up
  (`systems/build_budget.gd`: `if BuildBudget.due(): await BuildBudget.pause()`; slice 45 ms, grows to 2x
  the cost of a loading-screen frame on slow renderers). The bar shows the real build progress, Lumi keeps
  moving. The scene stays `PROCESS_MODE_DISABLED` and the root viewport's 3D off until it is whole; it joins
  the `persist` group last. Without a budget (tests, tools, save round trip) nothing yields: same code path.
- Off the main thread: the ground's 1200x1200 layout bake (`CityLayout.bake_start`) and the litter carpet's
  placement (`LitterView.start/finish`, now straight into MultiMesh buffers) run on WorkerThreadPool tasks
  (read-only on field and layout; waited on at quit, `BuildBudget.finish_pending`). Model files load on
  loader threads (`BuildBudget.fetch`, `AssetLib.fetch_model`); models the build would load blocking are in
  `data/preload_models.json` (regenerate: `--record-preload`, ids merge across districts).
- The second half (board, hub, Lumi, HUD, story and systems) still runs in one go on purpose: its deferred
  calls hook into systems made later in the same `_ready` (e.g. `LumiLevel._hook_late` -> goals/events), so
  yielding there would change behaviour. `Settings.apply_render_quality` waits for the end of the build (its
  shadow-filter settings recompile every pipeline: a 9 s frozen frame on software Vulkan).
- Same game: field, far junk, eggs and piece transforms identical to before (diffed); tests 637/637, save
  round trip PASS, autoplay without SCRIPT ERROR.
- Measured (`--load-report` prints steps and slow slices; the Loader prints `longest frame`):
  headless New Game, Old Town: ready 21.7 s -> 14.5 s, longest frame 19.5 s -> 0.7-0.86 s.
  GL compat under xvfb: ready 35.4 s -> 30.6 s (shot run), 46-54 s -> 46 s; longest frame 23-28 s -> 4.1-4.4 s,
  now in the shader warm-up, not the build. Renders: screenshots/leftovers/loading_before|after.png.
- Not yet under 100 ms: the one-go second half (~0.5 s headless here: first_seed, outposts, eggs,
  Nursery garden, fauna each 40-110 ms) and single far-junk LOD meshes / city blocks (up to ~0.2 s). Next:
  move those systems' mesh/material building into static caches warmed in the sliced half; spread
  ShaderWarmup over frames (one warm-up frame compiles every pipeline at once).
- **Rime night glint** (`rime_ice.gdshader`): at night bare ice gets a roughness floor (0.3, more where the
  view grazes) and its specular is clamped, so giantshine spreads into a soft sheen instead of a hard white
  hotspot on the flats around the borehole headframe; by day it is unchanged except slight grazing
  roughening. Renders: screenshots/leftovers/rime_night_before|after.png
  (`--planet-env=rime --time=0.0 --rime-nohud --spawn-pos=-45,-80 --spawn-yaw=0.48 --rime-cam=14,-0.18,0.48`).

## Update: movement on a sphere (wt/smove, Nov 8)
- Done: `planet/sphere/` holds standalone movement for round planets. These pieces are adopted by the orbit prototype.
  - SphereMotor: hover spring, radial gravity, jump, hover-boost, slopes, parallel-transported frames.
  - SphereWalker: Lumi.
  - SphereCam: follow and command views, spring arm, level horizon.
  - SphereBot, SphereSteer and SphereSwarm: great-circle travel and avoidance.
  - SphereCrewSim: far bots as records.
  - SpherePath: A* on GeoSphere.
  - SpherePlace: normal-aligned placement and the curved tractor scoop.
  - SphereSurface: the plug-in for terrain height and hex lookup.
- Demo: `--sphere-walk[=boost|play]`, with `--sphere-start=pole`, `--sphere-view=command` and `--sphere-scene=horizon`. Tests: `tests/test_sphere_move.gd`.
- True-scale boost lap at R 1840 m: back within 0.46 m after 11.56 km.
- Next (waits for rollout approval): Patch.gd uses SphereMotor behind a flag.
## Update: Bots tab list + one Locker for all looks (wt/ui7, Nov 8)
- Done: the Bots tab uses the list + detail pattern (`ui/bench_bots.gd`): Build (one row per robot type), Tiers (next Mk), Fleet (fleet upgrades: cheapest few + two locked), and a hidden Fabricator category for orbC (`BenchBots.set_fabricator(func(world) -> Array)`, rows in the ListDetail format, cat "fabricator").
- Done: all cosmetics live at the Locker (yard build), in four sections: Lumi, Glim (CosmeticTargets), Bots and Rocket. Bots: one design per robot TYPE (`systems/robot_design.gd`: Builder parts, paint = fleet liveries, glow colour); every robot of the type wears it, including new and Fabricator-built ones (Fleet.spawn) and restored ones (the design wins on load). Rocket: ship paint (6), trim (3) and engine glow (4) from `data/ship_style.json` (`systems/ship_style.gd`), read by ShipModel's materials; tiers keep their shapes; tier-locked looks stay hidden. The Glim panel now points to the Locker. Tests: `tests/test_ui6.gd`; the save round trip covers robot designs and ship looks.
- Done: workbench and Locker restyle (owner: "more futuristic and roboty, not full screen, a bit see-through"). `ui/holo_frame.gd`: floating glass modules (header, tab strip, list, detail, each its own panel at 74% opacity with 12 px gaps), ~80% of the screen and centred slightly low, a light vignette instead of the dim, and the HUD layers under it hidden while open. The look: chamfered corners (also every BenchKit.holo box), thin cyan edges, corner brackets, tick marks, faint scanlines, status LEDs, a mono "LM-1 // WORKBENCH" header and mono numbers/labels; it opens with a hologram unfold plus one scan sweep and closes with a fold. ListDetail/LockerPanel/BotEditor/ShipEditor take `modules = true`. No background blur (skipped on Compatibility). Pad audit passes at 1280x720, 1280x800 and 1920x1080, 100% and 125%.

## Update: simpler workbench (wt/ui2, Nov 7)
Owner playtest #1: "SIMPLIFY GAME". The workbench is seven tabs (Lumi, Bots, Hub, Research, Rockets, Requests, Locker) with bigger text, one card style (`ui/bench_kit.gd`: card, title/body sizes, big button, cost row with the currency icons, spot pips) and every cost in Parts and/or cubes.
- Done: robot part items are gone from the player-facing flow. `systems/robot_parts.gd`: a dug-up / spotted / rewarded robot part pays Parts at its rarity's value (Rusty 10 ... Legendary 450, `data/parts.json`); `GameState.parts` stays an empty legacy array that `RobotParts.fold_items()` folds into Parts every fleet tick. Save v4 (`SaveManager.migrate_v4`, after pace's v3) converts held items at the same values. Robot builds cost cubes + Parts (`data/robots.json` "parts", x1.2 per robot owned), Mk tiers cubes + `Fleet.TIER_PARTS` (200 / 700 / 2000); no recipes, no Control Cores, no rarity bonus.
- Done: no Trade tab (Haggle's trade, scrap, swap, buy are removed; `ui/trade_panel.gd` deleted). Haggle's rotating builder stall is gone: shop parts are always listed in the Locker.
- Done: Bots tab = one RobotCard per type like the Lumi cards: role icon, name, tier, one line, crew spots (filled / free pips) and Mk steps, big Build and Upgrade buttons with their cost under them; locked types show "Unlock with research: X" + a button to Research. The Multibot allocation board only shows once there are multibots.
- Done: Hub tab = one big card for the next level (name, what it is, "What you get" list from `HubPanel.level_gains`, cost row, big Upgrade button, level pips); scrubbers, bale stations, telescope and jammer sit in a column beside it.
- Done: Requests = short list: each request one line (text, n / N, reward, Claim), the live event on top, and one line for the next reward-track unlock. Requests start on their own and never expire (`Contracts.auto_accept`; the old Accept / Pass flow stays behind the flag). Tab gate API for "onboard": `UpgradesScreen.set_tab_gate("contracts", func() -> bool, hint)`.
- Done: Locker (`ui/locker_panel.gd`) replaces Cosmetics + Builder; opens at hub level 3 (`LockerPanel.HUB_LEVEL`, shows how to open it before that). Left: who you edit (Lumi, then every robot) and the fleet paint (liveries from Requests). Right: the editor. Lumi's editor is pluggable: `LockerPanel.add_editor("lumi", factory_or_control)`; without one it embeds `res://ui/lumi_builder.gd` when present (wt/style's LumiBuilder, embedded mode) or the design picker. Robots use BuilderPanel in `locker_mode`. Builder parts are pure cosmetics: owning one unlocks it for every robot, unlocking costs Parts (+ cubes), the Settler set keeps its small perk, personalities are flavour.
- Done: Research tab text sizes up (cards 210 x 86, 17 / 14 px; details 22 / 16 px).
- Done: new currency glyphs in `ui/hud_icons.gd` (faceted cube with shaded facets and a thin glow, eight-tooth gear with a hex bolt hole, a seed with a sprout); used by the HUD, workbench header, cost rows and the Lumi cards. Sheet: `xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/ui2_icon_sheet.tscn`.
- Done (playtest 2): holographic look for the workbench, pause menu and settings (`BenchKit.holo`: dark glass, thin cyan frame, soft glow; green glow = affordable, dim with "need N" in red = not). Tabs stay hidden until they open (`data/workbench.json`, any-of conditions on lifetime cubes / stats / hub level / flags; opened tabs stay; `UpgradesScreen.set_tab_gate` overrides for onboard). Lumi cards: no idle wobble, hairline bar, Buy / Max. Fleet upgrades sit on each robot card as one-line spots. Settings open on Basics (master, music, quality, fullscreen, sensitivity, language) with "More settings" revealing the full tabs. Pause: Resume, Codex, Photo mode, (Garden / Ark), Keepsakes (Codex Collection), Settings, Quit (saves, then the title; autosave every 60 s and on quit).
- Dev: `--bench-all` shows every workbench tab; `--locker` opens the Locker early; old tab ids `--tab=cosmetics|builder|trade` map to locker / bots. Tests: `tests/test_ui2.gd` (+ updated builder / events / fleet tests).

## Update: whole-game curve and return trips (wt/pace2, Nov 8)
- Garden takes off at 106 min bot (was 163): the bot no longer hoards 1.5x the next base before researching, and researches what an on-screen goal needs; base 3 costs 9000 cubes.
- Leave early, come back: drives open from partial progress (Mk V 60k cubes at Verdance 50% or a level 3 base; Mk VI at another planet 50%); the system map opens before the Cradle answers (`Homeward.system_open()`). Tech from later planets (Deep Drill, Tide Pump, Cryo Beacon, Heat Core; data/homeward.json `tech`, `needs_tech`, research `requires_tech`) caps each planet's restoration until found: Verdance stops at 68%, its frontiers say "Needs Deep Drill: found on Ochre". The campaign bot leaves at the cap or a plateau and returns with new tech.
- Fixed invisible walls in the bare Old Town yard (hidden lean-to posts kept their colliders).
- Open: measure Verdance's Mk V launch and the later planets in staged runs (16x runs at ~2x real time here); tune each planet to 3-4 h human and the whole game to ~20 h; per-hex markers for gated areas inside a district (today the gate is per frontier district and research).

## Update: slow start (wt/pace, Nov 8)
- Owner playtest #2 pacing: Lumi starts with a 12 chest, 3 pieces/s, small junk only and no bale press. New early upgrades: Baler (100), Lift Strength (50 / 500: medium, then large junk), Scoop Size (pieces per pulse), Signal Finder (violet-beam part signals). Before the Baler the chest is emptied loose at the trash bin (camp's TrashBin.deposit) or the scale.
- Helpers (Salvage Logic research) and automation (Conveyor, Auto-Baler, Recycler, Auto Compactor, Magnet Arm) wait for base level 2: first robot ~36 min, stations ~45+ min. Magnet Arm pulls a few loose, liftable pieces at a time.
- No spontaneous reward crates (Supply Drop event and Ledger seed drops off). Events/requests that need an unlock are flag-gated (Pace.sync_flags).
- Old saves (v<3) are granted Baler, Lift 2 and the chest/scoop levels to match. Numbers and before/after table: docs/BALANCE.md "Slow start".
- Open: re-measure after world2 (HexField.piece_size, no large items in the start ring) and camp (trash bin, bench repair) merge; onboarding objective "sell 3 bales" now needs the Baler first; whole-campaign autoplay not re-run (too long), late stages use dev jumps that grant the early unlocks.
## Update: Blink, the camera bot (wt/camp3)
- Done: photo mode is unlocked by a one-time Build-tab build, Blink (`systems/camp/camera_bot.gd`, data/camp.json builds.camera_bot, data/builds.json): a small floating camera drone in the helper palette (pearl shell, coral band, a big dark lens face with an amber iris). Listed only from hub level 2 or after 25 min of play; 400 cubes + 80 parts; game-wide (GameState.flags.yard_global). He hovers by his spot in the yard and watches Lumi; in photo mode he floats beside Lumi as the photographer and his iris flashes on each capture.
- Before him: PhotoMode.block_reason() is "locked" (the hotkey does nothing), the pause-menu button and the key hint are hidden. Old saves that used photo mode (photo_mode_opens, animal photos, photos taken, shots on disk) get him built (CameraBot.migrate). Tests: `tests/test_camera_bot.gd`, round trip camp3_* and camera_bot.

## Update: everything is a Hub build (wt/camp2)
- Done: a fresh base shows only the pod, the broken workbench and the trash bin (`Camp.standing()`; round trip `camp2_fresh_yard`). Every other yard structure is bought at the workbench and appears with the MachineReveal: lean-to, generator, yard lamps (street lamp + the fence pole lamps, street_dressing "Lamps" layer), compost press (after the first sprout; inactive until built), CD player, robot nursery, conveyor / auto-baler / recycler (after their research), telescope, signal tower (hidden, no collision, until tier 1), museum (at its site, no plot sign), signal jammers, air scrubbers.
- Done: one source, `data/builds.json` ({id, kind one_time|tiered, first_build_one_time}) read through `systems/camp/hub_builds.gd` (HubBuilds.available(world, kind), entry, build, built_names, kind_now). ui3's Build tab lists one_time (they drop off once built, a "Built:" line names them); its Upgrades tab lists the next tier of tiered things (trash bin levels, tower tiers 2+, scrubbers, jammers 2+).
- Done: old saves keep what stood (`Camp.migrate2`: lean-to, generator and lamps where they showed, compost press after the first sprout). The tower objective points at the workbench until tier 1. Autoplay builds the compost press once offered. Tests: `tests/test_hub_builds.gd`, round trip camp2_* checks.

## Update: the landing yard (wt/camp, owner playtest #2)
- Done: a fresh base is bare: the escape pod (intro2's crash site), a BROKEN workbench and the trash bin. Old Town's lean-to, generator, street lamp and the yard's poles, crates and festoons (street_dressing "Yard" layer) arrive with hub level 2; the compost press shows once something has grown (with a reveal).
- Done: the workbench starts tilted on a buckled leg, tools in the dirt, sparking. The first E plays a ~2.6 s repair (Lumi turns, welds it with the claw beam, it rights itself); after that E opens it. `systems/camp/camp.gd`, state `GameState.world.camp.bench` (old saves: repaired).
- Done: **TrashBin** (`automation/trash_bin.gd`, `data/trash_bin.json`): 5 levels (Dented Bin, Scrap Skip, Weigh Skip, Compactor, Shredder), each its own body in `automation/depot.gd`; value_mult and feed_interval per level; upgraded with E beside the bin or in the Hub tab (`ui/yard_builds_panel.gd`). Static API for pace: level(), max_level(), level_def(), next_def(), next_cost(), block_reason(hub_level), upgrade(hub_level), value_mult(), feed_interval(), events.changed.
- Done: the radio and the robot nursery are Hub-tab yard builds (`systems/camp/yard_builds.gd`, `data/camp.json`): radio at hub level 2 for cubes, on its own crate by the right fence; nursery listed after the first sprout. Old saves keep theirs (migration in Camp.migrate). Retiring a robot needs the nursery built.
- Done: radio songs replace the score: picking a song cuts the mood piece at once (pads fade in 0.6 s, melody and stingers dropped), stingers are muted while a song plays, and "Back to mood music" fades the score in from silence (`audio/music_director.gd` `_cut`, `tests/test_radio_music.gd`).
- Done: the observatory Telescope stands at the back edge of the yard (-4.4, -6.2, door toward the yard); view fixes: one zoom range per view for wheel and stick (no snapping back), no stale selection ring.
- Done: yard interactables are >= 3 m apart (`data/camp.json` min_gap, `tests/test_camp.gd`, `--camp-report`) and every prompt names its object ("Workbench: upgrades", "Trash bin (Lv 1): upgrade ...", "Radio: ...", "Telescope: ...").
- Done: machines never sell invisibly: Belt Drive / Baler Hydraulics / Recycler Yield need their machine (`requires_station` in data/upgrades.json; hidden on the workbench until it stands), and every machine or yard build gets a reveal (`systems/camp/machine_reveal.gd`: light pillar, its name, a glowing trail from Lumi, chime). `tests/test_machines_appear.gd`.
- Dev: `--camp-broken`, `--camp-fixed`, `--camp-repair`, `--camp-built=radio+nursery`, `--camp-bin=N`, `--camp-buy=conveyor+auto_baler`, `--camp-report`.
- Open: the Keepsakes radio tab still plays songs before the radio is built; the yard builds have no build-from-the-yard placement (fixed spots).

## Update: Anvil planet environment (wt/p_anvil) [planet-anvil]
- Done: `planet/planets/anvil/` (`AnvilEnv` env.gd, `AnvilProps` anvil_props.gd, anvil.json, shaders anvil_terrain / anvil_core / anvil_coat). Entry points (the PlanetEnvs contract, `planet/planets/planet_envs.gd`): `AnvilEnv.dev_hub(planet)` (a wild land hub), `prepare_field(field)` (before `HexField.generate`: registers the `anvil_foundry` junk set into `Economy.biome_sets`, same types and counts), `dress_view(view)` (before `FieldView.setup`: dust ground layers, ripples, no default hills), `apply(world, field, kind)` (everything else; works alone minus the junk swap).
  - Look: rust-red Mars-like world; thin butterscotch sky with a bluish halo round two small, dim suns (binary star, companion disc as a billboard since PhysicalSkyMaterial draws only one; `suns()` reads `SolarSystem.suns_for("anvil")` when it exists, else `data/solar_system.json`, else fallback); twin tiny moons; iron-oxide dust plains, terraced mesas and buttes, a stepped canyon to the west; seven foundry stacks with casting halls, slag heaps, conveyor trusses, the depleted core shaft (open-pit benches down to a dimly glowing ember shaft, with a 105 m headframe); half-buried Ledger ore haulers; an ore-cart rail spur; dust devils and drifting red haze; rust-red acid-drainage lakes; rust/soot junk coat.
  - Restored: stages by base level (ruin 1, mid 2-3, up 2-5, high 3-5, future 4-5) plus `restore` = mean hex level / 5: lichen, then red-leaf groundcover, then green over the dust, mesas and pit benches; red-leaf and lichen plants (MultiMesh) round the field; domed greenhouses with tube links; wind turbines; stacks become vertical gardens with thin warm-white light rings; hauler beds become planters; the core rekindles warm gold; the sky clears to a pale terraformed blue; seed motes replace the haze.
  - Registry: `data/planets.json` (`anvil`: sky, fog, sun, ambient, palette, junk tint, music mood `anvil_foundry`, restored sky targets).
  - Dev: `--planet-env=anvil` (through the shared `[planet-rime]` PlanetEnvs hooks in `scenes/slice.gd`), `--planet-view=x,y,z,lx,ly,lz[,fov]` (free camera), `--planet-cam=dist,pitch,yaw[,fov]`, `--planet-nohud`, `--anvil-restore=X`; combine with `--future=N`. Test: `tests/test_planet_anvil.gd`.
  - Owner passes applied: little haze (fog x0.35, aerial 0.15), vivid red/black contrast (sat 1.15, contrast 1.18, darker palette), ember-cracked slag, a night ambient floor (`night` in planets.json), both suns drawn; nothing reads as plain CG blocks (dented, leaning stack shells with stiffener ribs and repair plates, beveled plates and beams, eroded pit benches, jittered mesa strata, lumpy slag).
  - Paused (owner, Nov 8): flat-world terrain (`AnvilEnv.height`, `_build_terrain`, the pit bench mesh and far props laid out by polar coordinates) waits for the walkable-sphere design and will be rebuilt there.
- Moves to the globe as-is: `anvil_terrain.gdshader` (palette-recoloured dust, strata + varnish cliffs, lichen -> red-leaf -> green restore ramp, `slag` and `ember` modes; world-space, so it needs only a local "up" for slope on a sphere), `anvil_core.gdshader` (shaft wall ember glow), `anvil_coat.gdshader` (rust/soot junk coat), the `palette`/`sky`/`fog`/`sun`/`night`/`restored` values in data/planets.json, `AnvilEnv.sky_grade(r)` and `suns()` + `_sun_disc()` (two sun billboards), the `anvil_foundry` junk set (anvil.json), and the prop builders in `AnvilProps` (`noisy_cyl`, `_stack`, `_hauler`, `_truss`, `_dome`, turbines, `slag_mesh`, ore carts), which take a base Transform/position and only need a local up.
- Restoration rules to keep on a sphere: by base level, ruin (1) shows fallen stacks and gantry spans; up (2-5) turbines; high (3-5) first domes and planted hauler beds; future (4-5) vertical-garden shells and 0.14 m warm-white light rings on stacks, pit rim and shaft rings, hall eave lines, dome clusters with tubes. By `restore` (mean hex level / 5): terrain lichen from 0, red-leaf from 0.15, green from 0.4; plant MultiMesh fill 0.08-0.85; sky grade lerps to the `restored` targets with Rayleigh 1.4 -> 2.6 (the air thickens); core glow ember -> warm gold; dust devils stop past 0.35-0.8; haze off past 0.85; seed motes from 0.45 at base level 3+.
- Lookbook: `--planet-env=anvil --anvil-lookbook [--future=5]` stages the props in front of Lumi.
- Kit rebuild (Nov 9) [planet-anvil]: the sites are built from the art kit (`planet/planets/anvil/anvil_kit.gd` `AnvilKit`: flanged and bolted stacks with galleries, ladders, risers and decals; lattice conveyor truss; furnace with bustle main and tuyeres; ladle crane; pots; I-beams; Ledger hauler; ore carts and track) plus `KitBuilding` hangar / module / machine house / tank farm / dome / greenhouse, kit ground patches as aprons, kit clutter and lamp posts, and kit turbines (`KitProps.wind_turbine` + `turbine_rotor`), also in the wild world. Stage maps to kit state (1 broken, 2-3 repaired, 4-5 restored; powered from 2). Restored ground: meadow grass and flower clumps (Meadow meshes, `anvil_grass.gdshader`), red-leaf and lichen zones, gravel paths; each site ringed by low slag ridges and junk. The shared `BinarySun` draws both suns (Anvil sizes via `setup("anvil")`). Light preview without the game world: `res://planet/planets/anvil/site_preview.tscn -- --anvil-site=id,stage,restoration --planet-view=... --time=...`.
- Site prefabs (owner, Nov 8: hubs and landmarks survive the move to round planets): `planet/planets/anvil/anvil_sites.gd` `AnvilSites.build(site_root, site_id, stage 1..5, restoration 0..1)`, compact local scenes on a locally flat patch at the root's origin (local +Y up, own noisy-edged ground disc dipping under at the rim, no far terrain, no world-origin assumptions), listed in data/planets.json `anvil.sites`: `foundry_yard` (hub base; keeps a 12 m clear core for the hub's own objects), `foundry_tower` (the Ledger's 130 m stack on buttresses), `lava_forge` (running furnace, molten channel and pool: `anvil_lava.gdshader`, Voronoi crust plates on a glowing melt, `heat` cools to a dark glassy crust with one contained warm seam), `ruined_smelter` (collapsed hall frame, tipped pots, toppled stack; restored as a planted pergola). Ruined sites are fully trashed (junk MultiMeshes with the rust/soot coat, scrap mounds); restoration clears trash, greens the ground, plants red-leaf/lichen, and stage 3+/4+ add domes, turbines (`AnvilRotor`), vertical gardens and thin warm-white light lines. The kit (`AnvilEnv.kit()`) gives sites the palette materials without a world. Dev: `--planet-env=anvil --anvil-site=id[,stage[,restoration]]` (hides the flat district; add `--anvil-restore=1` for the restored sky). Tested in `tests/test_planet_anvil.gd`.
- Next: home wires `prepare_field` / `dress_view` / `apply` into Cradle Mode rust worlds; worlds2 can read planets.json for the title profile.
## Update: Homeward, the Verdance system campaign (wt/home)
- The game now ends when the whole system is restored. Five fixed planets (Verdance, Ochre, Tidewell,
  Rime, Anvil; data/homeward.json, systems/homeward.gd) are profile worlds with fixed seeds, types,
  modifiers, a relic each and Ledger lore (arrival memo, half-way intercept, restored note). Cradle
  Returns now plays "The Cradle Answers" (story/cradle_answers.gd) instead of the ending.
- Rocket drive Mk V Orbital / VI Interplanetary / VII Homeward (cubes + parts, kept in the profile),
  per-planet charts (previous planet at 50%), the solar map (ui/system_map.gd: 3D orrery, two suns,
  zoom in to a planet and on into the survey globe), planet flights through the rocket's own sequence.
- Ending: Mk VII at Cradle Returns (launch complex), the last seed, launch home, Homecoming
  (story/homecoming.gd) -> the ark finale -> credits; random Cradle Mode worlds are now post-game.
- Binary star (data/solar_system.json, SolarSystem.suns_for, planet/binary_sun.gd): every sky shows
  Hearth and Ember. Heirlooms come from planet picks (one per restored planet).
- Next: planet-specific goal chains (a new planet replays the Verdance chain from the start, including
  frontier goals); land at a chosen district on another planet (its PlanetData isn't generated until
  visited); pace the four planets end to end with the bot without --home-ff; a Lumi design for the
  ending; worlds2's world picker should honour `Homeward` planets (records with "planet").
## Update: planet globes (wt/globes, Nov 7)
- Done: `ui/planet_globe.gd` (`PlanetGlobe.new()`, `.setup(id, restoration)`, `.set_restoration(f)`), a Node3D for any 3D view, with procedural shaders `art/shaders/planet_{verdance,ochre,tidewell,rime,anvil}.gdshader` (+ `planet_lib.gdshaderinc`, `planet_clouds`, `planet_atmo`, `planet_ring`, `planet_motes`, `planet_shard`): real relief normals from analytic-derivative FBM, night side, soft terminator, atmosphere rim, clouds/storm spirals, binary-sun lighting (both suns, companion warm), restoration blends, MultiMesh rings (Ochre dust ring, Rime ice-spike ring, Anvil fire ring), LOD by screen size. See docs/DECISIONS.md "Planet globes".
- Done: the telescope orrery uses it (`[globes]` in ui/telescope_view.gd; globes lit from the orrery's sun nodes).
- Dev: `res://tools/globe_shots.tscn` renders the close-ups, the lineup and Verdance 0/100% (`--globe-only=ID|lineup|verdance_rest`); `-- --globe-check` is the headless check. Tests: tests/test_planet_globe.gd.
- Next: "home" swaps `ui/system_map.gd`'s spheres for `PlanetGlobe` (instructions in DECISIONS); optionally `story/space_stage.gd`'s cinematic planet.
## Update: world and physics fixes from playtest #1 (wt/world2, Nov 7)
- Done: **no yard fence** (ruined, patched or futuristic; the pole sleeves stay); lot fences elsewhere are broken runs with gaps.
- Done: **every solid prop collides** (`PhysLayers.PROP`, `planet/prop_colliders.gd`, shared box/cylinder shapes): street lamps (slim posts), hydrants, utility boxes, payphones, billboard legs (its shape was never added), shop crates/barrels, yard corner kits (tarps, drums, work light), light poles, name/holo sign posts, planters, ruin junk, outposts (ruin and fixed), eggs (off while hidden), composter, greenhouse frame, landing pod, depot dial post, recycler motor, hub walls/office/masts, launch tower, future-layer posts, frontier ruins and pad pylons (column boxes from their merged geometry). Junk inside a prop is nudged out at load. `tools/collider_audit.gd` (`godot --headless --path . res://tools/collider_audit.tscn -- --fresh [--future=5 --stations=all --scope | --hub=N | --frontier=ID]`) reports 0 for all of those; `tests/test_collider_audit.gd`.
- Done: **bales**: collider matches the drawn bale, CCD, lifted out of the ground after a spawn/put-down, put down short of walls (not onto roofs), rest on junk mounds (`PhysLayers.MOUND`, `planet/mound_colliders.gd`) and settle as the mound shrinks; opaque junk look (cube.gdshader). `tests/test_bale_rest.gd`; `--bale-shot[=mound]` stages a close-up.
- Done: **junk covers the district** (gen 2, new games): see DECISIONS "Junk gen 2" and BALANCE "World2". Radius-4 Old Town field, far static junk past it (`planet/far_junk.gd`). `tests/test_junk_coverage.gd` checks coverage at generation.
- Done (playtest #2): heaps solid for Lumi/robots and shrink as cleared; hub/blocked ground reads dirty until its owners are clean; `HexField.piece_size` size classes (for the "pace" helper's big-item upgrade), no large items in ring 1; bale carried above Lumi; chunkier strapped bale mesh.
- Next: if a frontier should feel bigger again, raise its radius to 5 (perf: ~+60% pieces); far junk could fade into the frontier terrain too.
## Update: Character Builder (wt/style, Nov 7)
- Done: `systems/lumi_style.gd` + `data/style_parts.json`: Lumi's look is a dict of slots (paint, trim, accent, side modules, wear, pattern, eye shape + colour, light strips, head piece, chest icon, shoulders, held item, companion, hover glow, pickup laser, bonus). The six designs are presets read from `PatchModel.VARIANTS`; a custom look takes any unlocked design's bonus (`flags.patch_skin`), "Looks only" unchanged.
- Done: applicator via two tagged hooks in `PatchModel._build` (`LumiStyle.variant_for` / `after_build`) and `player/lumi_style_rig.gd`: eye shapes round / visor bar / hearts as a next_pass (`art/shaders/lumi_eyes.gdshader`), heart chest icon, procedural antenna, halo, med kit, watering can, firefly, tiny drone (replaced by library meshes once the hero models them; names in DECISIONS). Laser colour feeds `PickupFx`; photo mode, title screen, cinematics, telescope/Ark views use the worn look.
- Done: `ui/lumi_builder.gd` (`LumiBuilder`, a self-contained Control the Locker can host; `LumiBuilder.open()` overlays it): slot list, big turntable with zoom and a demo laser (`ui/lumi_preview.gd`), curated swatches + advanced HSV (80 parts), locked parts with how to unlock, randomize, reset to preset, 5 saved looks. Opened from Cosmetics ("Character Builder") or `--lumi-builder`.
- Done: unlocks over the whole game (Lumi Level, hub level, designs, Collection finds, Requests, achievements, a few parts/seeds buys). Saved in flags (`lumi_style`, `lumi_looks`, `style_bought`); round trip covers them. Tests: `tests/test_lumi_style.gd`. Dev: `--lumi-random=SEED`, `--lumi-set=slot:value,..`, `--lumi-look=N`, `--lumi-parts-all`, `--lumi-builder`; lineup `scenes/style_lineup.tscn`.
- Next: the hero helper models `acc_antenna`, `acc_halo`, `acc_icon_heart`, `acc_medkit`, `acc_watering_can`, `acc_firefly`, `acc_drone` and a `side` material; ui2 hosts `LumiBuilder` in the Locker.

## Update: three currencies (wt/money, Nov 7)
- Done: exactly three currencies, Cubes / Parts / Seeds, from one source of truth (`data/currencies.json`, `core/currencies.gd`). Retired ids (bolts, sheet metal, plastic, glass, Data, compost, tokens, trinkets, Settler Fragments; Starseeds in the profile) are a legacy alias layer in `GameState.add_currency/get_currency/spend/can_afford` (fixed rates, one debug warning per id); `Currencies.fold()` for cost dicts, `GameState.can_afford_all/spend_all/add_all`. Every caller and data file uses the new ids (test_money checks the data files).
- Done: save v2 (`SaveManager.migrate_v2`): old balances fold at the same rates; compost goes into the compost press hopper; Settler Fragments become Parts. Round trip has an old-save case.
- Done: Parts from scooped metal/plastic/glass junk, the recycler (parts_per_bale + stock), Haggle's scrap bin, requests and Lumi levels; they pay for base levels, stations, outposts, rockets, robot tiers and the Builder. Research costs cubes (x10) plus real time; the old Data sources pay those cubes as field notes; Thriving wildlife is a small cube trickle. Compost press: organic junk and blooms go into its hopper, seeds come out.
- Done: Contracts + World Events = one Requests board (workbench Requests tab: the live world event, three requests paying cubes or parts, the reward track that replaced the token shop). Trinkets are Collection finds only (decor uses `needs_finds`). Heirlooms are milestone unlocks (`systems/heirloom_track.gd`).
- Done: HUD cluster shows Cubes, plus Parts/Seeds chips when they change; workbench header shows all three with the same glyphs (`ui/currency_icon.gd`); cost labels go through `Currencies.cost_text` / `L10nFmt.amount`.
- Done: the Ledger is rarer and quieter (one uplink line per act; coupons and quips as small notify entries, every 12-20 min).
- Balance: docs/BALANCE.md "Three currencies". Next: the "home" helper owns Cradle Mode; if it drops Heirlooms or the restoration score, delete `systems/heirloom_track.gd` and its two hooks in `systems/cradle_mode.gd`.

## Update: playtest fixes for four easter eggs (wt/eggs2)
- Done: **Gnome Patrol** gnomes are real pickups: E ("E   pick up gnome") lifts each one with the tractor beam (the junk PickupFx) into Lumi's hopper, with a pop, a blip ladder and a "Gnome N / 5 · added to Lumi's collection" toast; the fifth completes the egg. Shared helper for other collectible eggs: `story/egg_collect.gd` (EggCollect: parts/add/lift; opt in with `"collect": true`). Saves: same `flags.egg_<id>_parts` key, so gnomes seen in old saves count as collected (parts normalised to ints after a load).
- Done (owner: "no display for collectibles until the very end"): **Lumi's collection + the Museum** (`data/museum.json`, `systems/museum.gd`). Every collectible is an exhibit (gnomes, Biscuit's shell, time capsule, the last broadcast, duck, WREN's constellation, golden cube, all curiosities, memory shards, trinkets, the four planet relics); kinds egg / egg_parts / eggs / shards / trinkets / relic / flag, so other planets plug in by id. Codex > Collection now opens with "LUMI'S COLLECTION": counts ("Gnome Patrol 3 / 5"), drawn silhouettes for missing ones (`ui/collect_icon.gd`) and hints; trinkets follow. The Museum is a late build at Verdance's Cradle Returns once the Cradle has answered (a "FUTURE MUSEUM" plot sign, 1.5M cubes, 600 parts, 400 seeds): an open stone hall, one plinth per exhibit, ghosts on the empty ones, the gnome patrol on a little bed (`story/egg_display.gd`). Filling every plinth sets `flags.museum_complete` (achievement "For Whoever Comes Next"), a toast, WREN line and the gnomes' salute. No base yard display.
- Done: **The Last Jukebox** hushes the score: `Audio.hush_music(owner)` / `unhush_music(owner)` fade the whole Music bus (mood layers, stingers, radio tracks) out over 1.5 s while the waltz plays; it fades back when the waltz ends or Lumi walks 12 m away.
- Done: **WREN's Constellation** telescope now stands on open ground (a sidewalk street corner when there is one) 28-50 m from the spawn (`min_spawn_dist`, `spot` in eggs.json; a second placement pass, so no other egg moves). Why the look-through was glitchy: it pitched Lumi's own lens camera (bobbing with her idle float, swinging with her yaw, near plane clipping her visor, the lens HUD's blinking REC and grain on top), and the constellation itself never showed: its billboards used the drone's black shadow texture with additive blending, and ignored their per-star scale. Now: a steady eyepiece camera at the telescope's head (`story/star_peek.gd`), the scope and Lumi hidden while looking, a round brass eyepiece mask, HUD hidden, a night-adapted lens environment (no fog, dimmed haze, no DOF), white star texture, `billboard_keep_scale`, and the Wren higher in the sky (~58 deg) so streets rarely hide it. E/Esc leaves; the egg counts when the look ends.
- Done: **Still Broadcasting** (tv) plays Old Town's last news broadcast (`story/tv_broadcast.gd`): six procedurally drawn frames with captions (the green city, LEDGER SECURES EXTRACTION RIGHTS, the system strip-mined, EVACUATION: ALL RESIDENTS TO THE CRADLE, WE'LL BE BACK, static) on the TV screen (SubViewport) and in a close-up overlay; rewatchable; the egg counts when it ends. Lore/Codex text and WREN lines updated.
- Dev: `--spawn-egg=ID --egg-use[=S]`, `--egg-parts=gnomes`, `--tv-frame=N`, `--tv-step=S`, `--museum --museum-here --museum-built --museum-sample --spawn-museum`. Tests: `tests/test_eggs2.gd`; the save round trip checks `egg_collect` (parts + museum).
- Next: the Museum position ((-15, 4) in the Cradle Returns district) needs a look in that district; exhibits for Ochre/Tidewell/Rime/Anvil eggs can be added as `flag`/`egg` entries.
- Not done: the radio egg still uses the old lens-view look-up (`_look_up`).

## Update: the Telescope and remote progress (wt/scope)
- Done: **Telescope** (`automation/telescope.gd`, data in `data/telescope.json`): a pearl-white observatory with a satin plinth, a dark glass band, a thin cyan light seam under the dome and a slim mast. It stands in the yard at (-5.6, -2.8), door facing the depot. Built from the Hub tab (`ui/telescope_panel.gd`): base level 4 or the Observatory Optics research (Robotics tier 6), 6000 cubes and 40 parts (bolts until a parts currency exists). E at the door: the two dome shells part on their rails and the tube rises, then the view opens.
- Done: **Telescope view** (`ui/telescope_view.gd`). System: an orrery with both suns (star_a/star_b from `data/solar_system.json` when it exists, else the canon defaults) and the planets on their orbits (solar system file, else `planets_default`); profile worlds are matched by `planet_id`/name, unknown worlds get outer orbits. A `ui/system_map.gd` with a `planet_picked` signal is used instead when present. Visited worlds (a save on disk) can be picked; the current one is marked. Remote: `ui/remote_district.gd` builds the base district read-only from the save (clean bits + hex levels; ground baked into one texture with noise-warped borders; junk piles as one MultiMesh; base blocks by hub level; ground colours from `data/planets.json` env hints if present, else the world type), with the crew's robot models on simple loops (cleaners beam at the junk front and drop bales, haulers carry them home, Drips spray light over green hexes, Seedlings plant). Two directional lights for the two suns (`SolarSystem.suns_for` if it exists). Framed by `art/shaders/telescope_lens.gdshader` (vignette, faint chromatic shimmer), a reticle and readouts (planet, district %, robots active, last visit, cubes waiting).
- Done: **Remote progress** (`systems/remote_progress.gd`): other worlds' crews work at 50% of the offline rate via `Offline.compute` (same 8 h and junk-left caps), paid on arrival by world travel only (never with the offline payout). See docs/BALANCE.md "Remote progress". **Care package** (400 cubes, 5 min double speed, one at a time, extra capped at 75% of cost). **Sightings**: holding a Ledger wreck or a deer in the reticle unlocks `sightings:ledger_wreck` / `animals:deer`; the first look unlocks `sightings:first_light` (new Codex category "Sightings").
- Hooks (tagged `[scope]`): `scenes/slice.gd` (adds the Telescope node, keeps `scope_from_memory`), `ui/hub_panel.gd` (section), `systems/codex.gd` (category), `data/research.json` (node), `data/codex.json`.
- Dev: `--scope` (built free), `--scope-sample` (a sample visited world with no save), `--open=scope [--scope-pick=N]`, `--scope-open` (dome open), `--scope-look=N` (focus point), `--scope-debug`. Tests: `tests/test_remote_progress.gd`; the save round trip checks the telescope, its Codex entry and a care package in the profile.
- Next: when "home" lands, pass `planet_id` on the profile world records so the five planets match by id; when "extras" lands, make its idle gains call `Offline.compute` too (remote progress only covers non-current worlds).
## Update: keepsakes (wt/extras)
- Done: one hook in `scenes/slice.gd` (`ExtrasDirector.attach`, `systems/extras/`), Pause > **Keepsakes** panel (`ui/extras_panel.gd`; LB/RB tabs, B closes).
  - **Radio** (`radio.gd`, `data/radio.json`): a valve radio on the workbench (E opens the Radio tab). It plays the composed planet tracks from wt/sound (`Audio.play_track` / `stop_track`, titles from `Audio.music_track_title`; a restored planet plays the restored variant), looping with no gaps until "Back to mood music". 14 songs: Verdance's two from the start / 10 hexes, each planet's first on landing there (`Audio.get_planet_theme()`), the rest at that planet's base level 3 / 5, Homecoming with the Cradle. Unlock toast. `flags.radio` {unlocked, song, planets}.
  - **Photo album** (`album.gd`): a "before" picture on first arrival, "after" pictures at half clean / 25% Thriving / base 5, from one fixed camera over the base (384x216 one-shot SubViewport, no SDFGI/SSR/volumetrics, `texture_get_data_async` read-back, JPG on a WorkerThreadPool task). Files in `<save_dir>/album/slot_N/` (per profile and slot; `user://extras_scratch` under --fresh). Before/after slider per district + photo-mode thumbnails. `flags.album`.
  - **Robot nursery** (`nursery.gd`): Retire (Builder tab or the Nursery tab, press twice) for Mk I-II robots or ones in service >= 1 h: +2..8 Parts, they become caretakers in a fenced nursery garden at the base (potter, water the beds, wave at Lumi, E to say hi), keep name, parts and trait. +1% plant growth each, cap 6% (`CradleMode.stat_mod`). `flags.nursery`, `flags.nursery_service`.
  - **Welcome back** (`welcome_back.gd`): small card instead of the toast: away time, fleet and what it did, cubes, plants grown/bloomed, air. Idle maths is **`Offline.simulate(world_state, seconds, junk_left, scrubbers, filter_per_s, garden)`** in `core/offline.gd` (cap CAP_S = 8 h and junk left; counts `offline_units` so nothing pays twice; `Offline.apply()` credits once). Plants grow offline only while watered and bloom once.
  - **Seed of the Week** (`weekly.gd`, `weekly_run.gd`, `data/weekly.json`): ISO week (UTC) -> seed, world type, one of 7 twists (Scoopies Only, Dry Spell, Heavy Junk, Storm Week, Supply Rush, Long Nights, No Haulers). Clean 30 hexes, timed in play time; best time/score and paint chips in `<save_dir>/weekly.save`; runs in save slot 9, main save untouched (round-trip checked). Chips unlock two Garden Mode decorations (`weekly_pennant`, `weekly_arch`, `needs_chips`).
  - 7 achievements, 2 goals; strings translated in all six languages.
- Dev: `--extras=radio|album|nursery|weekly`, `--extras-welcome[=H]`, `--album-snap=before+m50`, `--nursery-sample=N`, `--radio-all`, `--radio-play=ID`, `--weekly`, `--extras-cam=x,z,yaw,dist,pitch`, `--extras-nohud`. Tests: `tests/test_extras.gd`; round trip: `tools/extras_roundtrip.gd`.
- Next: tune the weekly goal (30 hexes) with an autoplay run of the challenge; a radio prop in frontier bases is on the same bench (check it renders there); the welcome card could list research finished offline.

## Update: visual QA pass (wt/vqa)
- Done: Cradle Returns towers are premium curtain-wall glass (`art/shaders/tower_glass.gdshader`: metres-in-UV panel grid, hair-thin satin mullions, spandrels, per-panel tint/tilt, a few lit offices at night) with satin trims instead of white fins and floor bands; glass podiums and pavilions; the apron's dark band was smoothed normals across 30 m faces (`_arc_mesh` now flat); pale cool paving; lush lawn green via biome_tint.
- Done: water (`art/shaders/water_light.gdshaderinc`, used by water + flood): sun shadows keep 30% of their strength on diffuse and sheen, so near-camera shadow slabs on the Sunken City flood are gone (diagnosed with a noon render).
- Done: Frozen Port terrain mesh 160x640 for the mountain ring, rounded ridges with a finer octave, triplanar texturing on steep faces (also fixes vertical streaks on dune lee faces), faint noise-warped ice cracks (the Voronoi crack net read as a polygon grid), deeper clear polar sky.
- Done: rocket launch cameras moved to the open lot beyond the pad (no yard sign, fence, lamps, wires or holo boards in front); lift-off camera out of the vapour ring; tighter boarding framing.
- Done: global glow thin and subtle (glow levels 2-4 only, bloom 0.015, HDR threshold 1.15); natural (warped) lake shorelines in every district; Command view lifts visibility ranges while open (`ui/range_boost.gd`) so junk chunks and gardens no longer vanish when zoomed out.
- Done: UI at 1280x720, 1280x800 @110% and 1920x1080 in en/de/pseudo: wrapping contract cards and blurbs, ellipsized workbench and codex tabs, wrapping cosmetics buttons, Command key strip scales to fit. `--pad-audit` gains `--audit-size=WxH` (headless had a bogus square screen, so earlier clipping passes were meaningless), text-overflow and truncation checks, `--audit-why`.
- Done: Lumi's ears are tech side-pods (white pod stretched front to back, vented plate in the design's trim colour, thin glow stripe, antenna stub; `art/models/aurora/build_aurora.py`, aurora.glb rebuilt); from the side they no longer read as an eye. Pixel's heart lenses still sit on them.
- Done: HUD bottom: the context line is one short phrase (carrying > part signal > hex state) shown only after a change, while carrying or while a signal is strong; the notification stack sits above the hotbar band with a 3-line budget and shorter lifetimes; floating world text is moved out of the top and bottom HUD bands.
- Dev: `--frontier-cam=dist,pitch,yaw,fov` (spring arm no longer collides with the yard).
- Next: the "todo" rows in docs/VISUAL_QA.md (starter district hub levels 1-5, future layer 1-5, night/fog, Dust Flats, restored frontiers, photo mode, lens view, rocket arrival, robots vs walls); frontier junk is ~20M triangles at High (15k bulky pieces, no distance LOD) and is the biggest frontier perf item.
## Update: wildlife and animals (wt/wild)
- Done: `fauna/fauna.gd` (`Fauna`, built at the end of `scenes/slice.gd` `_ready`, `world.fauna`): ambient animals as a visible reward for restoring the world. Who lives where is data (`data/fauna.json`) and pure rules (`fauna/fauna_rules.gd` `FaunaRules.plan()`: per-hex contexts -> {species, hex, count}, seeded so they don't flicker, nearest hexes first, caps per species and `max_agents` per district). Re-planned every 2.5 s and on hex level/clean events; animals leave (walk off, fly off, hop into the water) when their hex stops suiting them, and despawn 70 m from Lumi.
  - City: stray cats (sit, groom a raised paw, wander, curl up asleep on warm spots by the composter/depot/yard, follow Lumi a little when he stops nearby, E to pet: purr + heart + Lumi happy; pet the same cat 3 times and she adopts you, gets a name and lives at that base, following you there), pigeons (head-bobbing walk, coo) and sparrows (chirp) that peck and take off as a flock when Lumi comes through, rats on junk hexes (fewer as the hex is cleaned; gone when clean; Poly Haven CC0 `street_rat`).
  - Green: rabbits (Growing; hops), butterflies over Growing hexes too (`Wildlife.add_butterflies`), deer at the edges of Sustained ground (graze, look up, bound away gracefully if rushed), foxes and bees (around planted flowers), robins singing on Thriving hexes, fireflies on Thriving hexes at night.
  - Water: fish schools visible through clean lakes (bigger with clarity research; dart away), mallards (paddle, dabble, quack) on clean lakes with a green shore, frogs at the edges (croak; plop into the water when startled).
  - Frontiers: lizards and fennec foxes in the Dust Flats, seals (also on the ice), herring gulls (some soaring) and arctic foxes at the Frozen Port, fish, herons and turtles in the Sunken City, white Cradle Cranes circling over Cradle Returns. Ordinary wild biomes get their flavour (`wild_dust`, `wild_frost`, `wild_coast` regions).
  - Look: soft procedural low-poly models (`fauna/fauna_models.gd`, ellipsoids + tapered limbs via `fauna/fauna_mesh.gd`), one MultiMesh per model; `art/shaders/fauna.gdshader` rigs legs (trot), heads (yaw + pitch: grazing, pecking, looking at Lumi), tails, wings and fish bodies from per-vertex pivots (CUSTOM0) and per-instance custom data; coat tints per instance (ginger/black/grey/tabby cats...). Far animals update every third frame. No colliders; every standing spot is checked against live junk pieces, junk mounds and building footprints (`FaunaRules.spot_ok`).
  - Sound (`fauna/fauna_sounds.gd`, synthesized, registered with `Audio.override`): purr, meow, coo, chirp, robin song, quack, gull, frog, seal, flock flutter, a looping cricket bed at night once the ground grows.
  - Collection/Codex: first sightings (in view, near Lumi) unlock the new Codex **Animals** category (21 entries, `flags.fauna_seen`); photos in photo mode (`PhotoMode.camera()`, `captured`) add `pic_<species>` trinkets (source "Animal Photos", `flags.fauna_photos`). Achievements: A Friend in Old Town (pet a cat), Best Friends (adopted), Oh, Deer, Clear as Day (fish in a clean lake), Naturalist (10 species), Wildlife Photographer (6 photos). Goals: "Pet a stray cat" after hex_7, "Spot a deer" after hexlv_4x3; the autoplay bot pets a cat once.
  - Persisted: `flags.fauna_seen`, `fauna_photos`, `fauna_cat` {name, coat, hub}, `seen_deer`, `seen_fish`; stats `cats_petted`, `wildlife_petted` (any animal petted; the Pixel design reads it), `animals_spotted`, `animal_photos`. Save round trip checks them and that the adopted cat is back at the base.
  - Dev: `--fauna-look=SPECIES[,dist,pitch,yaw]` (puts Lumi next to one, frames it with its own held camera, hides the HUD and particle bursts, skips Bloom Core beat cinematics; the subject holds still unless `--fauna-free`; `--fauna-gap=M`, `--fauna-coat=N`, `--fauna-lerp`, `--fauna-fov`), `--fauna-pose=sit|groom|sleep|pet|graze|fly`, `--fauna-dense`, `--fauna-lakes` (clean every lake), `--fauna-report[=S]`, `--fauna-debug`. Tests: `tests/test_fauna.gd`.
- Next: per-animal occlusion for photo credit; seal colony sounds; a female mallard and fawns (variety); robots stepping round animals.

## Update: wildlife pass 2 (wt/fauna2)
- Done (after the owner's "way more real and cuter" note): real models. The cat is sculpted and rigged in Blender (`art/models/fauna/build_cat.py` -> `cat.glb`: seamless remeshed skin, big glossy eyes, tabby/tuxedo/calico coat masks, actions Idle, Walk, Trot, Sit, Groom, Pet, Sleep, Stretch) and drawn by `fauna/fauna_rig.gd` (`FaunaRig`: AnimationPlayer driven from the Fauna state, head turns to look, eyes close asleep and when petted, fur shader + fur shells within 9 m, `art/shaders/fauna_fur.gdshader`, `fauna_eye.gdshader`). Deer, stags, red/fennec/arctic foxes use Quaternius's CC0 animated animals (`art/vendor/quaternius`, smoothed/recoloured by `build_quaternius.py`; walk, gallop, graze, idle). Birds (pigeon, sparrow, robin, gull, heron, crane), the mallard, rabbit, seal and fish are sculpted in Blender as smooth parts (`build_small.py` -> `<id>_parts.glb`, perched/flying poses) and assembled into the MultiMesh vertex-shader rig (`FaunaModels.sculpted`), with feathered two-part wings that flap with a lag and an upstroke fold. Rebuild: `blender -b --python art/models/fauna/build_<x>.py` (needs `apt-get install -y python3-numpy` for Blender's glTF exporter). The procedural builders remain for frogs, lizards, turtles, bees and as a fallback.
- Done: placement rules (`fauna/fauna_space.gd`, `Fauna.spot_free`): body radius per species, no overlap with other grounded animals (where they stand and where they're heading) and a gentle push-apart while moving; a prop occupancy grid stamped from the world's prop-sized meshes (lamp posts, hydrants, utility boxes, crates, pots, barrels...; rebuilt every 90 s), a physics shape query on the static layer (anything with a collider), fences round parking/vacant lots, the hub yard (cats excepted) and its fence, outposts and buildings. Spawn spots, wander/flee targets, bird landings and the periodic re-check all use it.
- Done: songbirds perch (`St.PERCH`): robins (60%), sparrows, pigeons and gulls sit on lamp-post tops, roof crowns and trees (`FaunaSpace.perches`, the top of tall slim meshes), look about, sing, and now and then drop to the ground or hop to another perch; flushed birds often fly up to one.
- Done: Lumi pets with a claw reach and stroke plus a head tilt (`PatchModel.pet_reach`).
- Done (playtest): bird sounds are occasional. One global clock for every bird call (`Fauna.bird_call_ok`, also used by the older `plants/wildlife.gd` birdsong that used to chirp every few seconds): 20-60 s apart, twice that at night, only with a bird within 18 m, softer; wing flutters at most every 1.8-3 s with a softer sound. Headless check `--fauna-callcount`: 1-2 calls a minute with ~32 birds. Feeding: E near pigeons, sparrows or ducks scatters crumbs (free, 4 s cooldown); the flock comes to peck, unafraid for 9 s; stats `wildlife_fed` and `wildlife_petted` (Pixel), Collection trinket `crumb_bag`.
- Done: frontier ambience (`fauna/fauna_ambience.gd`, synthesized in `FaunaSounds`): desert wind and day insects (Dust Flats, dune wilds), far gulls and creaking sea ice (Frozen Port, frost wilds), water lapping and heron calls (Sunken City).
- Dev: `--fauna-look=wide[,dist,pitch,yaw]` frames the busiest patch of animals near Lumi; every `--fauna-look` camera is placed with ray/sphere casts and building checks and pulled in front of a hit, never inside a wall. `res://tools/fauna_lineup.tscn -- --models=deer,seal,... --out=PREFIX` renders model close-ups on their own (opengl3 is enough). Tests: `tests/test_fauna_space.gd`.

## Update: visual QA pass 2 (wt/vqa2)
- Done: frontier junk distance LOD (`planet/junk_lod.gd`): near/far MultiMeshes per junk group, the near look unchanged, far meshes welded + simplified (the 10k-triangle plastic crate whose importer LODs stall drops to 124), packed `visible_instance_count` buffers. Medium spawn views: Sunken City 97.6 M -> 18.9 M primitives, Frozen Port 131 M -> 25.4 M (docs/PERFORMANCE.md). `--no-junk-lod` for A/B.
- Done: level-4 solar row moved from under the spawn camera to the yard's front-right (collider); hub street lamp hidden in the close rocket shots and given a pole collider; rocket arrival touchdown camera in the open lot with yard dressing hidden; day sky no longer shows the star texture as orange dots (SkyDirector fades it with the sun); holo board text no longer mirrored from behind; workbench tabs share the row by name length (pseudo fits); frontier coat on debris mounds.
- Checked: Dust Flats, restored Sunken City / Frozen Port, starter yard at levels 1/3/5, night, photo mode, lens view, rocket arrival, robots against walls (docs/VISUAL_QA.md).
- Open: Sunken City dark patches under the rim buildings (diagnosis in docs/VISUAL_QA.md); Frozen Port restored: far glass spires look like flat blue columns over the mountains, a soft white haze band near the rim; junk LOD adds ~10-30% draw calls (merge far surfaces next).
## Update: code health, part 1 (wt/health)
- Done: the exit crash (code 134) is fixed. Its cause was an unwaited `WorkerThreadPool` task (the `StorySfx` music-box prewarm), whose lambda freed its GDScript after scripting had shut down. `Audio._exit_tree()` now waits for it. Exit leaks are fixed too: the `Settings.bind_text` lambda cycle, the auto-baler chevron meshes, the GlobeView stray label, and stopped audio playbacks. The round trip and autoplay now exit 0.
- Done: `tools/check_exit.sh` (run by `tools/run_tests.sh` and the CI build workflow; `SKIP_ROUNDTRIP=1` skips it) and `tools/warnings_audit.sh`. The GDScript warning count went from 263 to 0.
- Done: perf. `Economy.stat()` indexes upgrades by stat, so robots' per-frame stat calls no longer scan every upgrade.
- Next (part 2): split `scenes/slice.gd` per `docs/ARCHITECTURE.md` section 4 once the parallel helpers have merged. Remaining perf candidates are in section 5.
## Update: Lumi designs (wt/skins)
- Done: six unlockable designs from the owner's concept sheet (`data/designs.json`, `systems/designs.gd`, looks in `PatchModel.VARIANTS`). Aurora (default, +8% detector range), Bolt (hazard-yellow, chevron stripes, shoulder pads, gear in the left claw; 50 bales or 5 robots; +5% bale value), Sprout (olive with moss patches, seedling on the crown, leaf chest icon; 20 blooms; +8% plant growth), Pixel (red/white, wing fins, heart ear lenses, resting ^^ eyes, butterfly companion; 5 animals petted or 5 trinkets; +10% streak time), Nova (gunmetal, cat-ear fins with violet glow, idle holo screen; 10 research; +8% research speed), Patch (white/orange, medic cross, hip toolbox, carry case when idle; repair an outpost or a Mk III fleet; +6% robot work speed).
  - Add-ons are Blender-modelled in `art/models/aurora/build_aurora.py` (exported to `designs.glb`, baked AO/edge wear like the hero; the antenna is now its own part). `hero_paint.gdshader` gained `moss` and `stripes`. Eye/ear/hover/chest/pickup-laser colour follow the design glow.
  - Workbench Cosmetics tab is a picker: spinning 3D preview (`ui/design_preview.gd`), name, tagline, bonus, unlock condition with progress, "Looks only (no bonuses)". Unlock card toast (`ui/design_toast.gd`). Buffs go through `Economy.stat` (+ research duration, streak grace) and show in stat breakdowns.
  - Dev: `--design=ID`, `--designs-all`, `--design-unlock=ID`; lineup render `scenes/design_lineup.tscn -- --out=...`. Test: `tests/test_designs.gd`; save round trip checks the design.
  - Pixel's "animals petted" reads `stats.wildlife_petted` / `cats_petted` (written by fauna/fauna.gd when you pet a cat).

## Update: future layer (wt/future)
- Done: `planet/future_layer.gd` (FutureLayer, built by `scenes/slice.gd`): the district builds up into a glowing, clean future city as it is restored. Pure `FutureLayer.plan()` from seed + hex levels + hub level + cleaned share (no save data); a handful of MultiMeshes (unshaded emissive + env glow), a few Label3D texts, no lights.
  - Per hex level: Clean = light seams inside the hex edges; Planted/Growing = circuit traces, white hex planters with glowing rims around plant slots, drifting seed-lanterns; Sustained = holo way-signs (icons) on white posts, floating light orbs, Tron lanes on the roads beside it; Thriving = magenta seam accents, light strips on nearby building corners/rooflines/floor bands, glass sky-terraces on street faces, tall holo banners, holo billboards and road gates with friendly messages, sidewalk light pylons, hover platforms with light bridges, floating halo rings, drones.
  - Per district score (0.2 cleaned + 0.3 hub + 0.5 mean level): rooflines and beacons across the skyline, white glass hex spires rising in the far ring, holo ads in the sky, hover traffic, aurora curtains at night; small `SkyDirector` hooks (`clear_bonus`, `night_tint`) clear the air and tint the night violet. Hub levels add yard light strips, masts, a halo ring and a sky beam.
  - Level-up moment (`EventBus.hex_level_changed`): a hex curtain of light sweeps up, new lines draw in from their start, holograms flicker on, labels fade in.
  - Shaders: `art/shaders/light_seam.gdshader`, `holo_sign.gdshader`, `future_fx.gdshader`. Dev: `--future=N` (all hexes/hub to level N, cleaned and planted), `--cam-pitch=X` for shots. Test: `tests/test_future_layer.gd`.

## Update: content depth (wt/content)
- Done: Codex **Curiosities** tab (4th tab, `ui/codex_screen.gd`; data from `Codex.curiosities()` in `systems/codex.gd`). Every egg grouped by where it turns up (Old Town / Any district / Wilderness bases): a "? ? ?" silhouette and a hint until found, then the lore, its found-toast as a quote and the reward. Chain eggs show parts found. Dev: `--open=codex --codex-tab=curiosities`.
- Done: 12 new eggs (29 total, `data/eggs.json` + builders in `story/egg_props.gd` + 3-stage WREN lines): The Odd Sock, Employee of the Month, The Weatherman, Best in Show, Night Shift (night radio), Notes From the Builders (doc); wilderness-only (`"where": "wild"`): The Last Scarecrow, Net Gains, Parking Forever, Trail Cairn, The Last Campfire, Back in Five. `per_district` 10; wild districts take up to `wild_per_district` (4) wild eggs first, biome matches first (`"biome"`). Found eggs keep their changed state (sock gone, fire lit, stone on the cairn).
- Done: Wilderness biome sets (`data/junk.json` `biomes`, `Economy.biome_set/landmarks_for`): rustlands, dust_dunes, neon_coast, frostcap, fungal_marsh. Per biome: junk model swaps (same type and count, own RNG, so saves stay valid; shore hexes get their own pool: lifebuoys, crates, buoys), own landmark wrecks (drill presses, compressors, stumps, buoys, sand-blasted drums, lots of covered cars in the dunes), a ground tint and grass tint (`ground_pbr.gdshader` `biome_tint`/`grass_tint`), a sand/frost/moss coat over the wrecks, and a tinted horizon ring of dunes/ridges with biome props (`FieldView._apply_biome`). 11 new Poly Haven models in `data/assets.json`. First landing in a new biome: toast + WREN line (`flags.biomes_visited`). Wild hubs are 24-33 (24 frostcap, 25/29 neon coast, 28 dust dunes, the rest rustlands); hub 3 is a city.
- Done: Post-game (`systems/bloom.gd`, `data/bloom.json`, `story/bloom_finale.gd`). Six Verdance Bloom milestones (Thriving hexes summed over districts, districts >= 60% Thriving, or planet % reclaimed as on the hologram) with rewards. "Verdance Bloom" plays a letterboxed Cradle cinematic (seed pods fall from orbit) and opens the **Seed Ark**: every bloom anywhere fills the next wave (120 x 1.5^n), each wave pays growing rewards; never resets anything. The hologram shows one line (next Bloom milestone, then the Ark wave). Dev: `--bloom-finale`.
- Done: 14 achievements (68 total; new cond type `list` = size of a flags Array). Tests: `tests/test_curiosities.gd`, `tests/test_bloom.gd`.
- Not done: the opt-in "reset a district's junk for a multiplier" prestige (the planet-wide counter was chosen instead).

## Update: Front end (title screen + settings)
- Done: `scenes/main_menu.tscn` (`ui/main_menu.gd`) is now `run/main_scene`: Aurora hovering in a sunset junk lot with a slow swinging camera, Continue (with a one-line save summary), New Game (confirms before erasing), Settings, Credits (from `docs/CREDITS.md`), Quit. Any DevHooks flag skips straight to `slice.tscn`, so `tools/shot.sh`, autoplay and tests work as before; `--menu` (or `--menu=settings|credits|confirm`, `--tab=N`) stays on the title for screenshots. The title screen turns `SaveManager.enabled` off so autosave can't overwrite the slot with blank state.
- Done: `ui/settings_panel.gd` (`SettingsPanel`), shared by the title and pause menus: Audio, Graphics (quality preset, render scale, fullscreen, V-Sync), Controls (sensitivity, invert Y, hold/toggle scoop, read-only binding list), Gameplay. New settings in `Settings.gd`: `fullscreen`, `vsync`, `render_scale`, `apply_display()`, `apply_quality_to_tree()`. Pause menu: Resume / Settings / Save / Quit to title / Quit to desktop.
## Update: Hex levels + Goals tracker
- Done: Hex levels (`plants/hex_levels.gd`, `data/hex_levels.json`). Every non-hub land hex has a level: 0 Junk, 1 Clean, 2 Planted, 3 Growing, 4 Sustained (planted slots watered >= 90% of the last 3 min, which watering robots keep up), 5 Thriving (all in bloom and sustained; extra wildlife). Levels never drop. Each level-up pays cubes/seeds, adds a small permanent growth/seed bonus (applied in `Garden`), counts `hex_lvl_N` stats, and plays a burst, ring, float text, sound and toast. API: `world.hex_levels.level_of(hex)`, `EventBus.hex_level_changed(hex_id, level)`. Saved in `GameState.world.hex_levels` via the persist group. The HUD hex readout shows the level, sustain % and the next step.
- Done: Goals (`story/goals.gd`, `data/goals.json`, `ui/goals_panel.gd`). A chain of 50 goals (clean, bale, upgrade, robots, command zones, plant, watering robots, sustain, base levels, rocket). The top-right HUD card shows the 3 current goals with bars and rewards. A finished goal flashes, its reward counts up, and the next goal slides in. Done ids are saved in `GameState.flags.goals_done`.
## Update: Research tree, Codex, achievements, stats
- Done: Research tab on the workbench (`ui/research_panel.gd`, `ui/research_node_card.gd`). 30 nodes in 5 branches (`data/research.json`): Cleaning, Robotics, Botany, Hydrology, Logistics. Costs the new **Data** currency (hex cleaned / restored, blooms, shards read, robot bales). Research runs on wall-clock time (30 s to 5 min), one active + a queue of 3, finishes offline. Logic and state in `systems/research.gd` (`GameState.flags.research`); effects reach the game through `Economy.stat` (`Research.stat_mod`). Gates: `Research.has(id)` (Logistics nodes `conveyor`, `auto_baler`, `recycler`, `rocket_cargo` are flags for the automation work), robots with `requires_research` in `data/robots.json` (Seedling, Drip, Multibot), plant species with `requires_research` in `data/plants.json` (nettle, mint, hedge, pine; applied to the Garden by the live Research node). Stats `lake_clarity` and `drip.range` are exposed for the water systems to read.
- Done: Codex screen (K, or Pause > Codex): Codex entries (`data/codex.json`, `systems/codex.gd`), 54 achievements (`data/achievements.json`, `systems/achievements.gd`, toast + chime), lifetime Stats (junk kg by type). Unlocks persist in `GameState.flags.codex` / `flags.achievements`. Tests: `tests/test_research.gd`, `tests/test_achievements.gd`.
- Follow-ups: Garden should read `Economy.stat("plant_growth")`-style hooks if Botany gets growth bonuses; water view should read `lake_clarity`; a HUD Data counter.

## Update: Command View + Aurora face pass
- Done: Command View (B / D-pad down). A holo map of the district. Pick a crew or a single robot and paint hexes to set its zone. Modes: Priority, Stay, Follow me, Recall. Orders are saved in `GameState.world.orders` and handled in `Fleet` (`order_for`, `zone_hexes`, `mode_of`); robots honour them in `robot.gd`. Tests are in `tests/test_orders.gd`. Dev hook: `--open=command`, `--order=role:mode:hex+hex|far`.
- Done: Aurora face now has big glossy oval eyes with catchlights, cheeks and ^ ^ when happy. The fin antenna is replaced by a bulb antenna.
- Next, in order:
  1. Automation chain: conveyor/hopper feeder that sends bales to the scale; an auto-baler station; drag-to-assign bots on the map.
  2. Bot build loop: build and upgrade robots straight from the Command panel when at the base, with crew size caps raised by hub level.
  3. Skimmer (water) robot and lake cleaning; Grinder/Recycler to remove trash for good.
  4. Done: tractor-beam pickup show. Patch (player/pickup_fx.gd, pooled): lock-on reticle, twin claw lasers, shader tractor cone (art/shaders/tractor_beam.gdshader), glowing lifted piece with arcs, compress to light, spiral mote stream into the chest hopper, beam hum; heavier take for big pieces. Mk III/IV helpers use a lighter version of the same beam. Dev hook: --demo-scoop.
  5. Cargo rockets (gate on `Research.has("rocket_cargo")`), then content (easter eggs, Ledger) and polish (cinematic intro, music, exports).
  5. Research tree, cargo rockets, then content (easter eggs, Codex, Ledger) and polish (cinematic intro, music, exports).

## Update: bale automation + Recycler (wt/stations)
- Done: `automation/stations.gd` (manager, group "stations", state in `GameState.world.stations`, data in `data/stations.json`) with three machines bought in the Hub tab (`ui/stations_panel.gd`, added to `HubPanel`):
  - Conveyor Feeder (`automation/conveyor.gd`): hopper pad with a roller turntable at (7, -0.8), scrolling cleated belt (`art/shaders/belt.gdshader`) into the scale. Haulers drop there when it is closer (`Stations.haul_drop`); Patch drives on to unload.
  - Auto-baler (`automation/auto_baler.gd`, group "baler_station"): air-dropped at the cleaning frontier; cleaners tip full hoppers into it (`Stations.claim_dump`/`dump_step`, marked `[stations]` in robot.gd) and it presses denser bales with a hydraulic platen, then rolls them out for haulers. "Move to frontier" button.
  - Recycler (`automation/recycler.gd`, hub level 2): shredder drums + smelter; bales are destroyed for bolts, building stock and a few cubes; stats `bales_recycled`, `junk_destroyed_kg`; adds to `air_filtered` (sky haze). Fed by an incline belt (auto-route every Nth bale) or the hand-feed plate.
  - Upgrades (tab hub): Belt Drive, Baler Hydraulics, Recycler Yield (bases in patch.json).
- Dev hooks: `--stations=all --stations-demo --route=N --stations-pose=K`. Tests: `tests/test_stations.gd`.
- Next: robot status text for "dumping at baler", Command View marker for the baler, offline progress for stations.
## Update: watering robots, Skimmer, crews from Command
- Done: Drip waterers are now the sustain system. They go for the thirstiest plants in their zone first (zone, then the district; slots another waterer is heading for are skipped). They spray every planted slot within `spray_radius` with droplet-arc Vfx, using one tank unit per plant. They refill at the nearest refill point: the base water barrel by the depot, placed **Water Tanks**, or any clean lake hex. Tanks are bought in the Command view ("Place refill tank here" at Patch's hex, cubes, max 6, spaced apart). Each tank holds a reserve that tops itself up. They are saved in `GameState.world.water_tanks` (`robots/water_net.gd`). Drip stats and upgrades: tank, spray radius, speed, refill rate. Tank, refill rate and spray radius also scale with the Mk tier. Each Mk tier has its own tank kit with a live level gauge.
- Done: Skimmer (role `skim`). It floats on pontoons over lake hexes, nets the floating junk, bales it and drops the bale on the nearest shore for haulers. It has 4 Mk looks (drum raft with a rubber duck, then painted pontoons, then glossy hulls, then levitating pods with a tractor beam). Cleaners now leave lake hexes to skimmers. Floating junk is no longer generated inside building footprints (200 of 585 lake pieces could never be reached).
- Done: Crew caps = 3 + 3 x hub level per crew (`data/robots.json` `crew_cap`). They show on the Bots tab cards and the Command panel. The Command panel has a Build button per crew and an Upgrade (fleet tier) button, both active only at the workbench. Robots with nothing to do park near their zone (or the base) and play an idle sway and hop. Their status then reads `idle · reason`.
- Done: Stall watch. If a robot gets no closer to its goal for 6 s, it gives up that target and nearby pieces and backs off. Hover and float units keep their height over curbs. Dev flags: `--clean-hexes=N`, `--bot-report` (automatic with `--robots`), `--trace-bot=NAME`. Tests: `tests/test_robots_water.gd`.
- Next: haulers can't keep up with 3 scoopies and a skimmer (about 66 bales made vs 42 hauled in a 120 s run). Look at hauler balance or a shore conveyor.
## Update: The Ledger arc (#30) + curiosities (#29)
- Done: `story/ledger.gd` (`LedgerArc`). Act 1 (3 hexes clean): intercepted Ledger messages in a red/amber monospace glitch box (`story/ledger_uplink.gd`), plus its absurd "coupons". Act 2 (first sprout): dump drones (`story/ledger_drone.gd`) now and then bring a few % of junk back onto a clean, unplanted, dry hex near Patch, with a toast, a red target ring, a shadow and a falling-junk animation. Robots and Patch clean it like any other junk. Signal Jammers (Hub tab, up to 3 per district, `GameState.world.ledger_jammers`) block drops within 22/34/48 m of the base and make drones rarer. Act 3 (hub level 3): the relay terminal appears in that district (red beacon). Act 4 (E at the relay): a letterboxed cinematic where WREN rewrites the contract, and drones then deliver seed crates. State: `flags.ledger_act`, `ledger_relay_hub`, `ledger_coupons`, `ledger_resolved`. Drops edit the field's alive/clean bits (`HexField.revive_pieces`), so saves stay consistent.
- Done: 17 easter eggs (`data/eggs.json`, `story/eggs.gd`, visuals in `story/egg_props.gd`): a duck on a hydrant, a music-box jukebox, the crew mural, the gnome patrol, a time capsule letter, an arcade cabinet, the "Lost: Biscuit" poster chain, the last FIZZ can, WREN's constellation (telescope, at night), a payphone on hold, a TV still on the weather channel, Gus the snail, two bots on a lunch break, a microwave, a WET FLOOR sign, a Ledger camera, a tyre tower. They are placed deterministically per district (Old Town gets the starter set), found once globally (`flags.egg_<id>`, `stats.eggs_found`, trinkets/cubes/seeds) and stay as landmarks. Generic E-interactables: `story/interactables.gd`. 26 new WREN triggers in `data/wren_lines.json`.
- Dev hooks: `--ledger-act=N`, `--ledger-drop[=S]`, `--ledger-resolve[=S]`, `--spawn-relay`, `--spawn-egg=ID [--egg-dist --egg-poke --egg-yaw]`. Tests: `tests/test_ledger.gd`.
- Next: a Codex "Curiosities" page with silhouettes; more eggs per district (aim 40); the coupon collection payoff screen.
## Update: Outposts (wt/outposts)
- Done: Ruined frontier outposts that become extra depots (`automation/outposts.gd` manager, `automation/outpost.gd` visuals, `data/outposts.json`). Each district gets 3-4 at seeded spots on the outer hex rings (`Outposts.plan`: open ground, never on buildings, the yard, water or a road; spread by sector; eggs avoid them). A ruin is a landmark: cracked rusty scale plate, skip tipped on its side, collapsed kiosk with the roof slid off, broken sign, tarp heap, dead lamp and a blinking amber fault light.
- Look: ruins are rusty and derelict; a repaired outpost is clean and futuristic (glossy white shells, dark glass, cyan light lines, orange accents, energy-glow scale plate, floating holo sign, floating spinning status ring, hovering roof and cargo pods), matching Aurora and the Mk III/IV robots, so the repair is a big before/after.
- Repair: E at the kiosk once the outpost's hex is 90% clear; cubes + sheet metal + plastic (Hub.pay, x1.6 per outpost already repaired in the district). Fast-build: the ruin lifts away in dust, scaffolds, welding sparks, parts drop in, then the lamp and green status light come on; toast, WREN (`outpost_repaired`), stat `outposts_repaired`, achievements `outpost_1`, `outpost_3`, `outpost_charge`.
- A repaired outpost is a working scale (`Depot` in `bare` mode, same value logic incl. hub sell bonus, stat `outpost_bales`; Patch can unload there too), a Drip refill drum (`WaterNet.refill_points`), and the parking spot for idle robots when it is nearer than the base. Haul Bugs deliver to the nearest working scale (`Outposts.nearest_depot`, marked `[outposts]` in robot.gd). In a 90 s 4x run with all outposts repaired, 42 of 48 bales went to outposts and total hauled doubled vs. the base-only run.
- Upgrades (E again): 2 Big Skip (wider plate, bigger skip, +15%), 3 Recharge Pad (robots crossing it run 40% faster for 25 s). Command view shows a pin per outpost (grey RUIN / green Lv N); the HUD hex readout notes the outpost on the hex.
- State: `GameState.world.outposts.levels` (per district), covered by `tools/save_roundtrip.gd`. Tests: `tests/test_outposts.gd`.
- Dev hooks: `--outposts=repaired|all:L|I:L[+I:L]` (+ `--outpost-clean`), `--outpost-spawn=N [--outpost-dist --outpost-dx --outpost-yaw]`, `--outpost-repair=N [--outpost-repair-at=S]` (plays the repair sequence).
- Next: offline progress for outpost sales; let the Command panel send a crew to "work from outpost N".
## Update: ruined bases that get fixed up (wt/bases)
- Done: every base but Old Town's starter yard starts ruined and is restored with hub level (`planet/street_dressing.gd`, layers driven by `Hub.level_changed`). L1 ruined: broken fence, toppled light poles with dead festoon wires, cracked/grimy slab with drifted junk and weeds, broken name sign, derelict lean-to (slumped roof, toppled yard lamp; `scenes/slice.gd _apply_base_level`). L2 patched: fence repaired with patch sheets, work lamps, corner salvage kits, festoons and bunting. L3 futuristic: white/glass fence panels with cyan strips, cyan slab seams (`yard_slab.gdshader` `glow`), holographic name sign, guide studs and a landing ring. L4: white planter pods with flowers, flags, hover drones. L5: a floating light ring over the yard and a beacon on the landmark. Live upgrades play a rise/sink flourish (sparkles, dust, paint freshening).
- Done: each base is unique from its seed: palette, paint colour, bay layout, broken slab corners, corner kits, sign slogan, billboard slogan, and a landmark past the junk field (water tower, crane, ferris wheel, radio mast, smokestack, old bus, windpump, lighthouse). Wilderness bases get no skyline or shop dressing; instead biome camps (dunes: sand drifts, bleached tarp shade, wrecked caravan; frostcap: snow caps, heater barrel; coast: pier planks, nets, buoys, beach shack; rustlands: scrap-panel fence, oil drums, tyres; marsh: boardwalk, lanterns).
- Dev hook: `--hub-level=N` starts the current base at level N. Tests: `tests/test_street_dressing.gd`.
- Next: compose with `planet/future_layer.gd` (district-wide future look) once both land.
## Update: world events, cleaning streak, contracts, Collection (wt/events)
- Done: World events director (`systems/events.gd` `WorldEvents`, data `data/events.json`, visuals `systems/event_props.gd`). One event every 4-8 min of real play (timer only runs outside menus, cinematics and rocket flights; starts after 2 lifetime hexes; first one ~3.5 min in; never repeats the last two when it can help it). Announced with a toast, a WREN line (3 memory stages), a top-centre banner with what to do / live progress / time left, an on-screen diamond marker (edge arrow when off-screen) and an EVENT pin in Command view. Events: **Supply Drop** (crate parachutes onto junk; clear the ring around it to pop the lid: cubes, bolts, seeds, a part, sometimes a token), **Salvage Surge** (a hex gets a glowing light curtain; junk Patch scoops there makes bales worth 3x for 2 min; "SURGE" bale label), **Rain Shower** (rain streaks + splashes, cool tint, shimmering puddles; every plant stays watered for 2 min), **Robot Hiccup** (a helper freezes and hiccups steam; walk over + E), **Wildlife Visit** (Glowtail Fox / Moss Deer / Lantern Hedgehog / Prism Heron / Velvet Hare with bioluminescent accents wander a Sustained/Thriving hex; E takes a photo with a camera flash: Collection entry), **Rare Part Signal** (violet beam + ring near a buried part; dig it for a bonus Vintage/Legendary part), **Ledger Audit** (after the Ledger arc: a friendly drone races you to clear a ring of junk, live score board; win = tokens). Nothing is punishing: time-outs just end, the audit loser gets a tip. Rewards scale with progress (`WorldEvents.progress_cubes`: ~N s of current income, floor from lifetime earnings) so they are spikes, not a flood. State: `flags.events` {next_in, recent, done}.
- Done: Cleaning streak (`systems/streak.gd`): every piece Patch scoops adds a point, 30 per tier, 5 tiers, +3% bale value per tier (best tier while the bale filled). 2.2 s grace (a bale press doesn't break it), then it drains gently. HUD meter bottom-right with pips; tier-ups chime, ring and float "STREAK x3". Max tier first time: Streak Medal collectible.
- Done: Contracts board, workbench tab **Contracts** (`systems/contracts.gd`, `ui/contracts_panel.gd`): 3 slots of optional timed jobs from 11 templates (metal-heavy/Perfect/Pure bales, clean hexes, scoop N, dig parts, streak tier, handle events, plant, bloom, Sustained hexes); asks grow with lifetime hexes (4 tiers). Accept starts the timer, Pass/expiry/failure just cool the slot down. Claim pays **tokens** + a cube bonus. Token shop: fleet liveries (`systems/liveries.gd`: neon/sunset underglow, crew pennants, holo halos, equip/unequip), Vintage/Legendary blueprint parts, seed crates, Curio Capsules (collectibles). HUD nudge when a contract is ready. State: `flags.contracts`, `flags.shop_owned`, `flags.livery`, currency `tokens`.
- Done: Collection (`systems/collection.gd`, Codex tab **Collection**): 28 trinkets/photos grouped by source (events, contracts milestones 1/10/25, streak, capsules), hints until found. `flags.trinkets`.
- Hooks into existing code (small, marked `[events]`): `player/patch.gd` (`on_patch_take` before collect, `apply_bale_bonus` at bale), `scenes/slice.gd` (creates the nodes), `ui/upgrades_screen.gd` (tab), `ui/command_view.gd` (pin), `ui/codex_screen.gd` (tab), save round trip covers tokens/contracts/collection/livery.
- Dev: `--event=ID [--event-at=S --event-look=M]`, `--event-every=S`, `--streak=N`, `--tokens=N`, `--trinkets=N`, `--livery=ID`, `--open=upgrades --tab=contracts --contracts-sample`. Check every event end to end: `godot --headless --path . res://tools/events_check.tscn -- --fresh`. Tests: `tests/test_events.gd`.
- Next: achievements for events/contracts (needs `data/achievements.json`), event weights by biome (rain more often in marsh), offline: contracts timers only tick while playing (by design).

## Update: HUD redesign + Lumi Level (wt/hud)
- Done: Minecraft-style hotbar bottom-centre (`ui/hotbar.gd`): glass slots for Scoop / Plant / Water with thin line icons (`ui/hud_icons.gd`), key 1-3 (D-pad glyphs on a pad), seed and water counters, the selected slot raised with a thin cyan glow, locked tools dim with a lock. Mouse wheel and pad LB/RB cycle tools once Plant is unlocked (Ctrl + wheel and holding a bumper still zoom). The hopper gauge (Perfect band, fill line) is a slim bar under the slots plus a faint fill inside the Scoop slot.
- Done: Lumi Level (`systems/lumi_level.gd`, `data/lumi_level.json`): XP from scoops, bales, parts, hexes, hex levels, goals, events, achievements, research, robots, plants. `need(L) = 150 L^1.5`; rewards cubes (capped), seeds, parts, tokens, and Lumi keepsakes every 10 levels (new Collection source `lumi_level`). Thin bar with the level number above the hotbar, "+XP" ticks, restrained flash + chime. State `flags.lumi`, in the save round trip. Curve and measured pacing in docs/BALANCE.md. The Bloom Core charge stays a story meter: a tiny ring at the level bar's left end, fed by `hud.set_core_charge(f)` or a `world.core_charge` node with `shown` (story2's `ui/core_meter.gd` hook in hud.gd should be dropped on merge).
- Done: Minimal currency top-left (`ui/currency_cluster.gd`), compact goal tracker top-right (`ui/goals_panel.gd`, G / L3 expands to 3; restart checklist in the same style), one notification stack bottom-left (`ui/notify_stack.gd`, max 3, merges repeats), contextual hex/signal/carry line above the level bar, slim event banner and small streak by the hotbar (`ui/event_hud.gd`), soft corner scrims instead of boxes. Settings > Gameplay > HUD: Full / Minimal (default, auto-fade) / Hidden. WREN subtitles moved up to clear the hotbar. Dev: `--lumi-level`, `--lumi-xp`, `--lumi-levelup`, `--tool`, `--hud-pad`, `--hud-mode`, `--hud-goals=expanded`. Tests: `tests/test_hud.gd`.

## Merged (Nov 7, 2026)
All helper branches are merged into claude/kind-wright-rhxixd and their worktrees removed:
rocket (+ polish), story2, steam, deck, drones, biomes (+ biomes2 visual pass), photo, hud,
l10n, and the website. Checks at merge: 283/283 tests, save round trip OK, every
`--frontier=ID` and `--locale=de` run with no SCRIPT/SHADER ERROR.
Also on main since: natural borders (ground state, greenery and junk placement follow a shared
noise-warped border, `HexField.border_warp`; old saves keep straight borders), hex-edge light
seams removed, thinner futuristic yard glow, the Cradle Returns completion triggers the ark finale.
Known: Godot exits with code 134 after some headless runs (engine cleanup at quit; pre-existing).

## Update: Rocket + launch pad + launch/arrival cinematics + rocket tiers
- Done: Futuristic rocket (`automation/rocket_model.gd`): lathed pearl hull, dark wraparound visor with Aurora-style glowing eyes, cyan seam rings, tangerine band, swept fins on landing feet, nose beacon, cyan engine. Tiers Mk I-IV (`data/rockets.json`, `automation/rocket_tiers.gd`) add hover rings, side boosters, gold trim, energy fins, a halo and a bigger plume; bought in the workbench Rockets tab. Benefits: shorter countdown and sequence, faster globe flight, faster energy-cell recharge between launches (Mk IV: none + warp), bigger and more frequent cargo pods (`automation/cargo.gd`). Tier + recharge in `GameState.flags` (`rocket_tier`, `rocket_ready_unix`), checked by the save round trip.
- Done: Launch pad (`automation/launch_pad.gd`) at `Rocket.PAD_POS` behind the yard (visible from the default camera): floating deck on three anti-grav emitters, chasing guide lights, energy clamps, service tower with lift, gangway and umbilicals, energy cells, floodlights, beacons with a rotating light, vapour vents. Level 4 shows a hologram of it. A rocket that lands in a district without a pad stays parked (`world.rocket_parked`) and can take off again.
- Done: Cinematics (`automation/rocket.gd`): launch (establishing, Aurora rides the lift and boards, holo countdown + siren + steam, umbilicals and gangway retract, engine charge, ignition with energy plume `art/shaders/rocket_plume.gdshader`, vapour billows, flash and shake, clamps release, lift-off, climb and arc to a dot, globe flight) and arrival (descent on the plume, touchdown, Aurora flies out). Letterbox, skippable (Space/Esc/B), input lock via `slice.launching`. Sounds: `roar`, `siren`, `charge` in `Audio.gd`.
- Screenshot hooks: `--hub-level=N`, `--rocket-tier=N`, `--rocket-arrive`, `--rocket-shots=T1,T2,... --rocket-shot-wait=S --rocket-shot-name=NAME` (fast-forwards the sequence and saves a frame at each time).
- Polish (rocket2): sleeker tapered hull with a waist, recessed visor with Lumi's C eyes, swept blade wings, legs that fold flush in flight; wispy noise/erosion vapour (`art/shaders/vapour_puff.gdshader`) with a ground-hugging ring at ignition; cinematic cameras use a less hazy, higher-contrast environment and hide the yard bulbs/bunting; `art/vfx.gd` billboard fix (unemitted particles drew as dark discs). Preview renderer: `scenes/rocket_preview.tscn`.
## Update: Lumi's ship, the Seedglider (wt/ship)
- Owner (Nov 7): "Space ship still need much better design ... It gets upgraded and bigger and better over time as we finish planets." The vertical rocket is replaced by an original low, wide manta glider (reference qualities: big swept wings, twin nacelles, faceted cyan canopy, layered plates and greebles, small orange lights, pale hull) in Greenfall's language: satin pearl hull, tangerine accents, THIN cyan lines, Lumi's C eyes on the nose sensor.
- Model: `art/models/ship/build_ship.py` (Blender, scripted like build_aurora.py: lofted faceted hull, bevels, boolean panel seams and slots, layered plates, lift fans, baked AO + edge + cavity vertex colours) -> `ship.glb` + `ship_points.json` (nozzles, fans, hinges). Paint: `art/shaders/ship_paint.gdshader` (clean satin pearl, crisp seams, pearlescent shift, optional edge_wear).
- Modular tiers on one base (`automation/ship_tiers.gd`, `ShipTiers.parts_for(look)`): Mk I compact one-seat glider (skids, twin engines, lift fans) -> II drooping wing extensions -> III bigger engines + new canopy -> IV landing gear + cargo pods -> V (Homeward drive) longer hull, second engine pair, fins -> VI big wings, fold ring, wingtip engines -> VII Homeward: seed vault, core engine cluster, light banners. Look = Homeward drive tier when >= 5, else RocketTiers (Mk I-IV); gameplay semantics unchanged. `--ship-tier=N` overrides the look, `--drive=N` the drive.
- Runtime: `automation/ship_model.gd` (ShipModel; `RocketModel` is now a compatibility subclass so old callers get the ship): canopy hinge, folding gear/skids, main-engine plumes streaming back, VTOL lift-fan jets (`set_lift`), blinking lamps, `for_display(t, engines)` and `face_along(node, dir)` helpers for maps/cinematics.
- Landing pad (`automation/launch_pad.gd`, still `LaunchPad`): octagonal pearl deck on anti-grav emitters, landing circle, chevrons, chasing rim, approach lights, docking locks, boarding lift with a light bridge, service mast with beacon/floods/cells/umbilical; grows with the look (`ShipTiers.pad_scale`). Level 4 hologram shows the pad and a ghost ship.
- Cinematics (`automation/rocket.gd`, same structure/skip/safety/`launching`): launch = canopy opens, Lumi rides the lift and drops in, countdown, fans spool, IGNITION (downwash), locks release, LIFT OFF vertical rise to a hover, gear folds, main engines light, pitch up and fly away; arrival = nose-first fly-in, flare, hover, gear down, set down on the fans, canopy opens, Lumi flies out. The ship parks nose-out along the take-off heading (`Rocket.PARK_YAW`).
- Preview: `scenes/ship_preview.tscn` (`--ship-view=lineup|hero|top`, `--out=`; headless self-check). Tests: `tests/test_ship.gd`.
- Owner (Nov 8): "As the spaceship upgrades it should look cooler, not just bigger": per-tier finish in `ShipModel._make_mats` (Mk I plain satin -> graphite metallic accent panels from Mk IV, glossier pearl, polished trim, brighter thin cyan lines, champagne-gold fittings at Mk VII, idle engine glow rising with tier) and runtime tier pieces (`_build_tier_extras`: spinning lift-fan rotors, trailing-edge and chine line lights, Mk III nose canards + dorsal blade fin, Mk IV landing lights, Mk V nozzle halo rings, Mk VI pulsing fold-ring light, Mk VII pulsing seed vault + vault light spine + light banners). Preview views `lineup` / `pair` / `solo` in a dark studio at equal screen size.
- Ark *Cradle* redesigned by wt/ship in the same language (`art/models/ship/build_ark.py` -> `ark.glb` + `ark_points.json`; `story/cradle_ship.gd` keeps alarm/thrust/ring_speed/dome_world/pod_world/pod_xform/release_pod): faceted manta hull with layered plates, 50 m swept wings with drooping tip fins, faceted cyan bridge canopy, C eyes on the nose sensor, faceted glass seed-vault greenhouse at its heart with the garden inside, fold ring, four nacelles + core engine, ventral docking bay, keel with the six-pod rack. `wake_points()` feeds the Homecoming's waking lights. Previews `--ship-view=ark|ark_below`.
- Integrated with wt/home after the merge ([ship] tags): `SystemProps.add_rocket` builds the Mk VII ship (no torus band), Homecoming flies it nose first (`ShipModel.face_along`), the system map shows the ship at the current look by the current planet and flying the trip arc, the Homeward complex towers/ring and the last-seed bed moved outside the Mk VII pad.
- Earlier note for wt/home (now done): `story/system_props.gd add_rocket` should build `RocketModel.new().build(7)` (or `ShipModel.for_display(7, 1.0)`) without the green torus band, and Homecoming should turn it with `ShipModel.face_along(rocket, dock - start)` instead of rolling a vertical rocket; `ui/system_map.gd` can show `ShipModel.for_display()` (current look) beside the current planet (scale ~0.05-0.1 of a planet).
- Next: in-cockpit Lumi silhouette; per-planet pad dressing; a Mk VII complex at Cradle Returns sized for the 8.7 m pad.
## Update: Steam Deck, controller and performance (wt/deck)
- Done: controllers can now press and back out everywhere: Godot 4.7's built-in `ui_accept` / `ui_cancel` had no pad buttons, so A did nothing on focused buttons and B never closed a screen; Settings adds A / B (`tools/pad_audit.gd` found it). `--pad-audit` (headless) opens every screen and tab (workbench incl. Contracts, Command, globe, codex tabs, pause, all Settings tabs, title menu) and checks focus, D-pad reachability, B closes, A presses; all 28 pass. Workbench card grids (Bots, Hub, Lumi with affordable upgrades) were unreachable with the D-pad (Godot's geometric search misses other cards in a scrolled grid): `ui/focus_grid.gd` wires explicit neighbours. Globe: focus lands on Launch / Re-survey, right stick spins and tilts, shoulders zoom (held).
- Done: pad glyphs. `ui/pad_glyphs.gd` (Xbox / PlayStation / Steam Deck names and badge specs, family from the controller name or Settings > Controls > Button prompts), `ui/prompt_glyph.gd` (vector badges: face buttons, PS shapes, bumpers, triggers, D-pad arms, sticks, View/Menu, keycaps), `ui/prompt_label.gd` ("{action}" templates with keyboard/pad-only spans). Used by Settings, workbench, codex, document view, globe, Command view, pause menu, intro skip, tutorial and first-seed lines; `Settings.glyph()` names follow the family; rebind buttons show family names.
- Done: readability. `ui/readable_ui.gd` floors every Label / Button / RichTextLabel at 12 px (`Settings.MIN_FONT_PX`); handheld screens (Deck, small dense screens) get interface scale 110% on first launch.
- Done: auto quality (`systems/quality_detect.gd`, `systems/quality_probe.gd`): first-launch preset from GPU name/type, OS/arch (Apple Silicon vs Intel Mac), screen, RAM and Steam Deck; a one-time 45 fps probe steps down; Settings shows "Detected: ..."; manual choice wins. Low is lighter (FXAA not MSAA, cheaper shadow filter, no DOF, half particles, lighter litter/junk meshes); FSR when render scale < 100%; optional Mobile renderer via `user://renderer_override.cfg` (restart).
- Done: draw calls (`art/mesh_batch.gd`, city skyline/sidewalks/curbs/fences/kit/props/bodies, garden chunks, butterfly MultiMesh, empty junk batches hidden, shared litter material). Numbers and how to measure: `docs/PERFORMANCE.md`; census: `--scene-stats`.
- Next: measure on a real Deck and an Iris Xe laptop (the container has no GPU); the outposts (~120 meshes) and easter-egg props (~70) are the next batching candidates; a right-stick look sensitivity setting.
## Update: photo mode (wt/photo)
- Done: **Photo mode** (`ui/photo_mode.gd`, `ui/photo_panel.gd`, `ui/photo_filters.gd`, `player/photo_poser.gd`, `art/shaders/photo_grade.gdshader`). Opens from the pause menu ("Photo mode") or the rebindable `photo_mode` action (P / left-stick click). Pauses the world; Lumi keeps animating. Its own camera renders into a SubViewport (main 3D off meanwhile), so captures hold the grade, letterbox and stamp but never the HUD/panel. Capture (C / X / panel button) saves `user://screenshots/greenfall_<date>_<time>.png` at 1x or 2x (supersampled) and toasts the path; `PhotoMode.captured(path)` is the hook for Steam's screenshot library.
  - Camera: orbit Lumi or free fly (25 m radius, kept above ground); FOV, roll, distance, height; smooth on mouse (drag, wheel, Ctrl+wheel), keyboard (WASD, R/F, Q/E, Z/X) and pad (sticks, triggers, bumpers, D-pad; View toggles orbit/free, R3 resets).
  - Lens: depth of field with auto-focus on Lumi or a set distance, blur amount, exposure. Look: 8 filters (Natural, Golden Hour, Dawn Mist, Neon Night, Film, Mono, Holo Blue, Bloom) plus contrast, saturation, warmth, vignette, grain. World: time-of-day override, weather Live/Clear/Haze/Mist (via SkyDirector haze + fog).
  - Lumi: 13 procedural poses (hover, wave, thumbs up, peace sign, laser scan, holding a sprout, sitting on a junk cube, hologram map, happy cheer, low battery, heroic hover, selfie aimed at the camera, curious tilt) and 10 eye options (new `wink` uniform in `bot_face.gdshader`); turn Lumi; show/hide robots.
  - Frame: hide HUD (default), rule of thirds (screen only), 2.39:1 letterbox, small Greenfall stamp.
  - Closing restores pause, mouse, UI layers, robots, time/haze/environment, Lumi's joints/transform/face/process mode. Refused during rocket flights, the intro, Ledger and other cinematics (HUD hidden or camera input taken).
  - Dev: `--photo[=S] --photo-seq="pose=wave|filter=golden|time_override=1|time=0.7;..."` (`--photo-first/--photo-every/--photo-open/--photo-copy/--photo-close`), `tools/pose_lineup.tscn` renders every pose. Test: `tests/test_photo_mode.gd`.
- Not done: pad View+Y chord (View already opens the globe; the pad default is left-stick click, rebindable); camera collision with buildings in free fly; Steam `AddScreenshotToLibrary` call (left to the Steam branch via the `captured` signal).
## Update: Robot Builder (wt/drones)
- Done: every robot has five part slots (Chassis, Head, Mobility, Tool, Topper) on top of its Mk tier (`systems/robot_builder.gd` `RobotBuilder`, data `data/robot_parts.json`). 28 parts: each non-cosmetic part trades one stat for another (treads +20% load -12% speed, quad rotor +18% speed -15% load, big-eye +60% scan -5% work, mist sprayer +25% reach -12% tank, ...); tools are crew-specific. Generic stats map to robot stats in `RobotBuilder.CONCRETE`; `Robot.stat()` multiplies `build_mods`. Scan = chance to spot salvage while working (parts, Settler Fragments, a rare Lucky Clover).
- Sources: craft (bolts + a stored part), research-gated crafts (Swarm Sync, Spray Heads, Haul Routes, Auto-Sort, Salvage Logic, Pollinator Survey), Haggle's builder stall (Trade tab, 3 offers rotating every 8 min of play), contract token shop (Fine Sieve, Jet Nozzle, Propeller Cap, Builder Crate, Settler Fragments), drops (starter Treads + Bobble Plant with the first robot, Lucky Clover). The Settler set (shell, optic, glider; +5% speed +6% work when all three are fitted) needs Settler Fragments + Vintage-or-better parts: the grind.
- Looks: `robots/robot_kit.gd` (`RobotKit`) measures the built body and adds the part meshes (same toolkit and materials as `RobotVisual`; one thin light line per part, sleek on Mk III/IV, painted metal on Mk I/II); custom drives hide the wheels and lift the model (rotor/legs/skirt). `robots/robot_persona.gd`: name tag (name + trait) shown near Lumi, 7 traits (Cautious, Speedy, Chatty, Sleepy, Tidy, Curious, Musical; tiny ±2-4% flavour) with idle animations and beeps.
- UI: workbench tab **Builder** (`ui/builder_panel.gd`): robot list, rotating 3D preview, rename, part slots, the parts that fit (focus/hover previews the part and the stat changes), craft/buy+fit on press, crew presets (save / fit on crew), parts bin, Haggle stock. Gamepad: d-pad + A everywhere, LB/RB tabs.
- Save: builds and traits in each robot's dict; bin, fragments, presets in `GameState.flags.builder`; covered by `tools/save_roundtrip.gd`. Goals `builder_1`, `builder_full`, `builder_preset`; achievements Mix and Match, As the Settlers Made It, Hat Rack. Tests: `tests/test_robot_builder.gd`.
- Dev: `--builder-sample` (stocked bin), `--builder-demo` (showcase builds on the robots in the scene), `--builder-shot [--bshot-cam=x,y,z --bshot-at=x,y,z --bshot-fov --bshot-nohud]`, `--open=upgrades --tab=builder [--builder-robot=N --builder-slot=ID --builder-opt=N]`.
- Next: per-hub kiosk for the stall; Codex Parts page entries for builder parts; trait-aware WREN lines.
## Update: frontier districts (wt/biomes)
- Done: four late-game frontier districts, one extra hub each, reached from the Rockets tab's FRONTIERS section (`data/frontiers.json`, `planet/frontiers.gd`, `planet/frontier_district.gd`, `planet/frontier_view.gd`, `ui/frontier_rockets.gd`). Radius-4 fields, bulkier junk, bales x3-x12, base costs x4-x16, own junk sets, ground textures (sand_01, snow_02, damp_sand), ground shader extras (sand ripples, frost, wet silt), sky/fog grades, landmarks staged ruin -> painted -> white/futuristic with base level.
  - Dust Flats: dunes, half-buried ship, solar farm, wind turbines; sandstorms re-dust unsheltered clean hexes (Sustained hexes shelter neighbours); dry well, slow tanks.
  - Frozen Port: cranes, container yard, frozen harbour; per-hex ice locks junk; heaters (E) and Lumi's beam thaw; greenhouses (E with the seed tool) or Cold-Hardy Seeds for planting.
  - Sunken City: flooded downtown, the city rises as pumps drain ring by ring once 80% of the next ring is skimmed; stranded debris on revealed streets.
  - Cradle Returns: white launch city, gantries, landing pad (7 hexes, must be Sustained) + 70% Growing -> `EventBus.cradle_district_complete(hub_index)` (ark finale hook, see DECISIONS).
  - 8 research nodes (tiers 6-7), 7 native/cold-hardy species, 9 Codex Frontiers entries, WREN lines. Tests `tests/test_frontiers.gd`; save round trip covers frontier state. Balance: docs/BALANCE.md "Frontier districts".
- Next: autoplay support (rockets, heaters), achievements for frontiers, a play-test of frontier pacing.
- Done (wt/biomes2 look pass): heightfield terrain to the horizon per frontier, Dust Flats wrecks (buried containers, tanker, fallen water tower) and solar farm, Frozen Port sea ice and organic ice sheets, Sunken City flood unified with the field water, Cradle launch city (lighter glass towers, paved apron, docking halo over the pad), clearer air (aerial perspective), weathered frontier junk. All frontier boundaries (ice, shoreline, flood edge, field/terrain seam) follow the natural-border warp. Shots: screenshots/biomes2/.
- Next (frontier look): Cradle overview re-shot after the apron/lawn fix; Sunken City near-camera dark patches (likely tower shadows) to confirm; low-poly far mountains in the port.
## Update: Steam readiness (wt/steam)
- Done: `SteamService` autoload (`steam/steam_service.gd`) around the GodotSteam GDExtension singleton; no-op without the extension, without Steam, headless, or with `--no-steam`. Achievements mirrored (API name = id upper-cased) on unlock and on load; 14 lifetime stats (`data/steam.json`); Remote Storage cloud sync, newest `saved_unix` wins (`steam/steam_cloud.gd`), or Auto-Cloud by setting `greenfall/steam/cloud_mode`. App ids in `project.godot [greenfall]` (480 placeholder) + `steam_appid.txt`.
- Done: Demo build: `Demo.is_demo()` (feature tag `demo` or `--demo`), first district only, base capped at level 2, no rockets, end-of-demo screen with Wishlist (`steam/demo_end_screen.gd`), demo saves in `user://saves_demo` (imported by the full game). Export presets `* Demo`; CI builds `GreenfallDemo-*` artifacts.
- Fixed: exports excluded `tools/*`, but `scenes/slice.gd` uses `AutoplayBot`/`DemoScoopInput` from tools/, so exported builds failed to load the game scene. Now only `tools/steam/*` is excluded.
- Store: capsule stage `tools/steam/capsule_stage.tscn`, compositor `tools/steam/capsules.tscn` (logo in the title font, achievement icons), `tools/steam/render_store_art.sh`; Steamworks lists `docs/steam/*.csv`; owner checklist `docs/steam/README.md`; shot list `docs/steam/TRAILER.md`. Dev hook `--no-hud`.
- Next (owner): GodotSteam download (Codeberg is unreachable from the sandbox), app ids, Steamworks config, Apple signing, SteamPipe secrets (see docs/steam/README.md).

## Update: Lumi's story told with animation (wt/story2)
- Done: new ~60 s opening (`story/intro.gd` + `story/space_stage.gd`): the ark Cradle over Verdance (Blender model `art/models/cradle/build_cradle.py`, runtime `story/cradle_ship.gd`), Lumi humming to seedlings in the seed vault, the meteor storm and hull breach, Lumi climbing into a cargo pod with the tray, the pod blown out as the ark sails on, re-entry fire, a chase over the junk city, the crash and a low-battery wake (dim flickering eyes/core, BLOOM CORE 4% readout, WREN explains green light and the plan). Dev: `--intro --intro-from=0..4`.
- Done: Bloom Core charge (`story/core_charge.gd`, tiny `ui/core_meter.gd` on the HUD) with beats at 25% (memory of the ark's garden deck, `story/cine.gd`), 50% (glow brightens), 75% (the ark crosses the night sky), 100% (finale: the ark descends and Lumi greets it). Dev: `--core-charge=F`, `--core-beat=25|50|75|100`.
- Next: real voice/hum audio for the vault scene; show the parked ark from more districts.

## Update: localization (wt/l10n)
- Done: gettext pipeline on Godot's TranslationServer (docs/LOCALIZATION.md). `tools/extract_strings.py` builds `locale/greenfall.pot` (~2,460 strings: ~1,060 from GDScript `tr`/`tr_n`/`TranslationServer.translate`/`# l10n` const tables, ~1,400 from the player-facing fields of 20 data/*.json files), regenerates the pseudo-locale `locale/pseudo.po` (accents, brackets, ~35% longer, placeholders kept) and merges new msgids into every other `.po`; rerunnable, `--check` for CI. PO files registered in project.godot and exported (`locale/*.po`).
- Done: ~900 UI strings wrapped in tr() across ~85 scripts (menus, HUD, workbench tabs, Codex, Command, globe, photo mode, toasts, story beats); data text (codex, goals, achievements, upgrades, research, eggs, events, contracts, robots, parts, frontiers, hub, rockets, bloom, shards, WREN and Ledger lines) translated where shown; toasts, subtitles, Ledger lines and captions translate at the sink too. English-text logic checks now compare translated prefixes; `Robot.status_text()` stays English for logic, `status_label()` is shown.
- Done: Settings > Gameplay > Language (System default, English, Deutsch/Español samples, Pseudo); saved as `[ui] language`; panel rebuilds on change; "System default" only picks complete languages (`Settings.SYSTEM_LOCALES`). Dev: `--locale=xx`, `--l10n-audit` (lists on-screen text that skipped tr(), `tools/l10n_audit.gd`). Test: `tests/test_l10n.gd` (locales load, pseudo/de/es translate, placeholders preserved in every translation, setting persists, UI font has Latin-extended glyphs).
- Fonts: UI font (Godot default Open Sans) covers Latin ext, Greek, Cyrillic; Ledger font Anonymous Pro the same minus a few Latin-B letters; neither has CJK/Hangul (fallback needed for ZH/JA/KO).
- Not translated: 3D world signage (street_dressing shop signs, robot decals), proper names (districts, robot names), dev/log text.
- Next: real translations (DE, FR, ES, PT-BR, ZH-CN, JA, KO, RU), CJK fallback font, a pseudo-locale layout pass on every screen with screenshots, `extract_strings.py --check` in CI.

## Update: translations (wt/i18n)
- Done: complete MACHINE-DRAFT translations, 2,523/2,523 strings each: German, French, Spanish, Brazilian Portuguese, Simplified Chinese, Japanese (`locale/{de,fr,es,pt_BR,zh_CN,ja}.po`, header comment "MACHINE DRAFT ... Reviewed: none yet"; not marked fuzzy because Godot skips fuzzy entries). Plural forms per language (fr/pt_BR: n > 1; zh/ja: one form). `msgfmt --check` clean; `tools/l10n_merge_draft.py` validates placeholders.
- Done: CJK fallback fonts: Noto Sans CJK SC/JP subsets (3.3 MB, OFL) in `ui/fonts/cjk/`, built by `tools/build_cjk_fonts.py`, attached by `ui/cjk_fallback.gd` to the UI and Ledger fonts (locale's font first). Language picker lists all six with native names; all six in `Settings.SYSTEM_LOCALES` with `Settings.system_locale_for()` (de_AT -> de, pt_PT -> pt_BR, zh_Hans_CN -> zh_CN, zh_TW -> en). Compass directions ("north of you") now translated (`LedgerArc.compass_label()`).
- Tests: `tests/test_l10n.gd` checks every locale loads, is complete, keeps placeholders (order of % specs) and the `E   ` prefix, plurals, CJK glyph coverage (has_char), system locale mapping.
- Next: native-speaker review per language (workflow in docs/LOCALIZATION.md, "Reviewing a machine draft"); rarity+part name word order (`"%s %s"`) for Romance languages; HUD/button overflow pass in de/fr; `◈` glyph missing from the UI font; Korean/Russian.
- Done (wt/l10n3, Nov 8): content-drop fill, 240 new strings x 6 languages (Glim, workbench/trash bin, profiles, system map, Tidewell sites, Homeward tech, 44 song titles, five world WREN arcs). All six at 3,842/3,842 (100%); CJK subsets rebuilt. The <=5% allowance in `test_full_translations_complete` can go back to strict.

## Update: translation fill pass (wt/i18n2)
- Done: 467 new strings drafted in all six languages (first-hour polish, Lumi designs, wildlife + Codex Animals + photo trinkets, visual QA, late game: Cradle Mode, Ark Bridge, Heirlooms, Garden Mode, 41 eggs, goals, achievements, WREN lines). 2,968/2,968 per language, still MACHINE DRAFT.
- Done: `systems/l10n_fmt.gd` (`L10nFmt`): reward suffixes (`reward()`, `amount()` with plurals: "+25 cubes", "+1 trinket", "+1.2K cubes"), rarity + part as one msgctxt'd pattern `{rarity} {part}` ("part name"; fr/es/pt use `{part} {rarity}`), research effect lines `+{amount}% {robot} {stat}`. Used by eggs, codex, events, Lumi level, contracts, robot builder, trade, research, bloom, hex levels, decor, outposts, hub, salvage toasts.
- Done: token glyph `◈` -> `◆` (in both CJK subsets' base set, reached by the UI and Ledger fonts); "Patch" -> "Lumi" in the tin robot and glowtail fox collectibles (street sign kept); pseudo.po passes `msgfmt --check`.
- Done: `test_full_translations_complete` is strict again (0 missing; handles msgctxt ids). `tools/l10n_status.py` (coverage table, `--missing xx`, `--export` -> `.l10n_work/todo.tsv`, `--check`); `tools/l10n_merge_draft.py` reads keyed plural/context lines. Tests: tests/test_l10n_fmt.gd.
- Next: native review; Romance gender agreement of rarity adjectives (drafts use one form per rarity); districts on the HUD ("OLD TOWN") stay English by design.


## In progress (Nov 7, 2026): deep dive
Wave 1 helpers (worktrees /home/user/gf-wt/<name>, branches wt/<name>):
- beat: full game beatable end to end (autoplay to the Cradle finale), bug hunt, docs/WALKTHROUGH.md, credits
- wild: wildlife (cats, birds, rats, rabbits, deer, foxes, fish, ducks, frogs, frontier animals), Collection hooks
- first: first-hour polish (tutorial panel, juice, pacing)
- vqa: visual QA sweep (docs/VISUAL_QA.md) and the known visual leftovers
Trailer notes (owner): feature some of the cooler Lumi designs (Bolt, Sprout, Pixel, Nova, Patch) in the trailer, e.g. a quick design-swap montage.
Wave 2 (after merging wave 1): late-game Cradle Mode / Garden Mode + eggs, real translations (de/fr/es/pt-BR/zh/ja drafts), code health (exit crash 134, split scenes/slice.gd), trailer capture. Then merge the PR into main.
If a session ends: commit WIP in each worktree, then resume or merge.
## Update: whole game, beatable end to end (wt/beat)
- docs/WALKTHROUGH.md: the critical path with gates and measured times (fresh save -> Old Town ->
  second district -> Dust Flats -> Frozen Port -> Sunken City -> Cradle Returns -> finale -> credits ->
  Seed Ark).
- The Cradle is the true ending (Verdance Bloom = cradle_returned); finale replays if interrupted;
  end credits roll (ui/credits_roll.gd, docs/CREDITS.md, skippable). Bloom Core charge follows the
  campaign. Goal chain 144 goals to the Seed Ark. Garden ramp at ~1 h (base 3 + Pollinator Survey).
- Autoplay plays the whole game: rocket travel, heaters/greenhouses/thaw, skimmers, Cradle pad; staged
  runs with --save-dir / --stop-at / --game-minutes / --no-travel; milestones in
  screenshots/autoplay_milestones_NAME.json; stuck-robot census.
- Next: re-measure the first hour after merging the first-seed pacing (first helper); tune frontier
  costs (Frozen Port went quickly once upgrades were maxed); Data is in surplus after the Dust Flats.

## Update: first-hour polish (wt/first)
- Done: restart checklist rewritten (`story/tutorial.gd`): six steps, one thing each (scoop, press, pick up,
  scale, workbench, finish the hex), shown as a compact glass card (`ui/checklist_card.gd`, inside the goal
  column; step dots, amber key glyphs, a hairline progress bar) that ticks green per step and fades out after
  "Lumi is back on the job". Goal rows stay hidden while it runs. In-world pointer (`story/tutorial_marker.gd`):
  an amber chevron and ground ring on the nearest junk, Lumi's hopper, the bale, the scale or the workbench,
  plus an edge arrow when off screen; the hex step points at the nearest remaining piece. The first-seed hints
  reuse the card (plant, then water).
- Done: juice (`art/feel_fx.gd`, new Vfx `sweep`/`pillar`, new sounds confirm/thunk/tick/sweep in Audio):
  gentle one-octave scoop combo ladder (`Audio.play_ladder`); bale press squash and stretch + thunk + small
  shake (CameraRig honours Reduced motion) and the bale pops out squashed; sale cubes fly from the scale into
  the counter, which counts up as they land (`ui/coin_flight.gd`, `CurrencyCluster.in_flight`); upgrade
  two-note confirm and Lumi shows off the install after closing the bench; first-robot rollout (light beam,
  rings, spring-in, "NEW CREWMATE"); hex reveal dust/glint sweep riding the ground ripple, extra chord and
  sweep on the first hex.
- Done: no HUD/world flash between the title fade and the intro (black cover until the intro overlay is up);
  gameplay camera snapped behind Lumi under the intro's fade-out.
- Done: early pacing and the scarce seed trickle: see docs/BALANCE.md "First hour".
- Dev: `--tutorial-step=N`; `--first-demo=bale|sale|robot|reveal` (optionally `--demo-lead=S`) freezes the moment at
  its peak for screenshots. Tests: `tests/test_first_hour.gd`.
- Next: the autoplay bot never uses the Builder (stalls on `builder_1`); the HUD context line under the
  prompt gets long over outposts (hex level + next + outpost note) and sits close to the level bar.

## Update: late game and post-game (wt/late)
- **Cradle Mode** (prestige / New Game+): `systems/cradle_mode.gd` (static `CradleMode`, booted by the
  `CradleBoot` autoload before any save is read), `systems/world_gen.gd`, `data/cradle.json`.
  - A profile (`user://saves/profile.save`) holds the worlds, the current world, Starseeds and Heirlooms.
    Each world has its own save slot: Verdance stays slot 0 and is always one Travel away.
  - New worlds: fresh planet seed, one of five world types (Ice Moon, Desert World, Ocean World, Marsh
    World, Rust World: biome thresholds, water share, town count and town names via `PlanetData.mix`),
    two modifiers each (Heavy Rain, Long Nights, Rich Salvage, Thin Soil, Tailwinds, Wild Bloom, Heavy
    Junk), their own ground look and a landing town chosen to be dry. They start ruined, with the
    Heirloom kit, an arrival card (`ui/world_banner.gd`) and the restart checklist.
  - Starseeds come from a world's Seed Ark waves, Bloom milestones, Thriving hexes, the Cradle and
    level-5 bases; banked on the Ark Bridge and when leaving (each world only pays what is new).
  - 10 Heirlooms (stat multipliers through `Economy.stat` -> `CradleMode.stat_mod`, or a starting kit:
    cubes, Data, seeds, waiting robots, known research).
  - **Ark Bridge** (`ui/ark_bridge.gd`, Pause > Ark Bridge after the finale): world list with travel,
    "Seed a new world" with a preview, Heirloom shop. Pad friendly.
- **Garden Mode** (`systems/decor.gd`, `art/decor_props.gd`, `ui/garden_placer.gd`, `data/decor.json`):
  H or Pause > Garden Mode, after the finale or at base level 5. 10 decorations (path, flower bed,
  planter, bench, lamp, bird bath, fountain, Settler statue, Lumi sculpture, WREN kite) on a 1 m grid on
  clean ground; place / rotate / cycle / pick up (refunded, so moving is free). Charm raises that
  district's plant growth (0.4% per point, max 8%). Wildlife hook: group "decor", metas `decor_type`
  and `decor_wildlife`; `Decor.liked_by(tree, kind)`.
- **Easter eggs 29 -> 41**: four frontier-only (Sand Piano, Snowbot, Message in a Bottle, Welcome
  Home), five general (Crossword, Hopscotch, Last Balloon, Return to Sender, Patient Tree), one wild
  (Listening Dish), two on new worlds only (Not the First, Heirloom Tin). `story/egg_props_late.gd`;
  Codex Curiosities gains Frontiers / Other worlds groups; WREN lines for each.
- Goals: 12 appended after the Seed Ark (156 total). Achievements: 12 more (86).
- Dev: `--post-finale`, `--world=N`, `--heirlooms=id:lv+...`, `--starseeds=N`, `--sample-worlds=N`,
  `--open=ark|garden`, `--garden-type/--garden-cell/--garden-cam`, `--decor-sample`, `--new-world[=S]`,
  `--no-banner`, `--late-save-after=S` (systems/late_director.gd). Autoplay: `tools/autoplay_late.gd`
  decorates, buys Heirlooms and seeds a new world, then marks `w2_*` milestones.
- Tests: `tests/test_cradle_mode.gd`, `tests/test_decor.gd`, `tests/test_late_eggs.gd`; save round trip
  covers decor, a second world, the profile and travel both ways.
- Next: per-world WREN story beats; a title-screen world picker; Steam Cloud for profile.save; a
  stronger visual identity per world type (sky tint, skyline); wildlife reacting to decor (wt/wild).



## Owner design (Nov 7): the solar-system campaign
The main campaign is a fixed solar system: Verdance plus ~4 handcrafted planets in order. Rocket tiers past Mk IV
(Orbital, Interplanetary) unlock the next planet. Lore: the Ledger corporation strip-mined the system and left
it to die under its trash; each planet reveals more. The game ends when every planet is clean: Lumi returns to
Verdance, builds a big launch base, gives the rocket a final "Homeward" upgrade, plants the last seed and launches
home (reusing the launch sequence, ark finale and space stage), then credits. Random Cradle Mode worlds become
optional post-game. Owner: wt/home (progression, story, ending) + wt/worlds2 (planet looks, 3 save profiles).
Binary star canon (owner): one solar system with TWO suns seen from every planet (warm yellow-white primary,
smaller orange-red companion), sized/lit by orbit distance (Ochre closest, then Verdance, Tidewell, Anvil, Rime
farthest). Source of truth: data/solar_system.json + systems/solar_system.gd (wt/home). Travel UI: a 3D
solar-system orrery that zooms into a planet's globe to pick the hub (wt/home).
- Audio (wt/sound): done. Per-planet music (`Audio.set_planet_theme(id)`, `Audio.set_restoration(0..1)`):
  2-3 composed tracks per planet with motifs, grooves and restored variants (`audio/music_tracks.gd`),
  two upbeat Verdance cleaning tracks, rotation with silence gaps, activity-driven energy; planet
  ambience beds with restored layers (`audio/ambience.gd`); the "homecoming" mood (Greenfall motif,
  first heard as the intro sting); WREN ducking, Master limiter, Ambience bus under SFX; radio API
  `Audio.play_track(id)` / `stop_track()`. See docs/AUDIO.md. Needs wiring on the planet branches:
  call `set_planet_theme` on planet load, `set_music_mood("homecoming")` in the ending, and
  `Audio.loop("hover_spray", x)` while Lumi hovers over water. Next: owner listening pass.
## Update: each world its own look, story and save sync (wt/worlds2)
- **World looks** (`systems/world_look.gd`, `data/world_looks.json`, `planet/world_look_view.gd`): each
  Cradle Mode world type has its own sky grade (over the planet haze, easing off as the district is
  restored but keeping its identity), a sky body (`planet/sky_body.gd`, `art/shaders/sky_body.gdshader`:
  a ringed gas giant over the Ice Moon, twin moons over the Desert, a big tide moon over the Ocean, a
  shattered moon with a debris ring over the Rust World; the Marsh mist hides the sky), a city tint and
  weathering overlay (`art/shaders/world_weather.gdshader`: frosted, sun-bleached, coastal, overgrown,
  corroded), yard dressing (drift colour, bleached cloth, puddles) and a landmark
  (`planet/world_landmark.gd`: seed silo, solar tower, surge barrier, overgrown cooling tower, gantry
  crane; ruined parts until base 3, thin trim lights from base 3, mended from base 4). Modifiers show:
  Long Nights darkens nights (`SkyDirector.night_dark`), Heavy Rain doubles yard puddles, wets the junk
  and thickens the fog, Rich Salvage gives the junk a metallic shine. Verdance is untouched.
- **Save profiles** (3 slots, `user://saves/p1..p3`; `SaveManager.profile_slot/profile_dir/set_profile/
  delete_profile`, `systems/profile_slots.gd`): each has its own worlds, Heirlooms and progress; settings
  are shared. Pre-profile saves move into p1 on first start (`SaveManager.migrate_to_profiles`).
  Title > Profiles (`ui/profile_picker.gd`): per slot name, play time, planets, current planet and
  district, Bloom %, cubes / seeds / parts; Continue (then the planet list, `ui/world_picker.gd`, when
  the profile has more than one), New (confirm), Rename, Delete (confirm). Pad focus grid; cancel backs
  out. `CradleMode.select_world` points Continue at a planet (an unplayed one lands fresh).
- **Planet hook for the fixed solar system**: `WorldLook.planet_id()` (a world record's "planet"/"look"
  key), `data/world_looks.json` "planets" maps planet ids onto look types (with overrides), and when
  `data/planets.json` lists a planet with an env script (default `planet/planets/<id>/env.gd`),
  `WorldLookView` instances it and calls `apply(world, field, kind)` (kind city | wild | frontier;
  optional `set_progress(progress, hub_level)`); the env then owns the art (no generic landmark or sky
  body unless the look says keep_landmark / keep_sky_body); grade, tint and weathering stay data-driven.
- **WREN per world** (`systems/world_story.gd`, `data/wren_lines.json` `world_<planet or type>_<beat>`):
  arrival, two memory notes revealing what the Ledger did to that world (strip-mined, pumped dry,
  dredged, poisoned, its ships broken), halfway and restored, clear over the ark's
  relay (`Wren.say(..., stage_override)`), remembered per world save (`flags.world_story`).
- **Steam Cloud**: `profile.save` is stamped with `saved_unix` and uploaded on every write, so newest-wins
  sync covers it with the world slots (docs/steam/README.md updated for both cloud modes).
- **Binary sun on every planet** (owner rule; `planet/binary_sun.gd`, `art/shaders/sun_disc.gdshader`, made
  by SkyDirector, so Verdance and frontiers too): the PhysicalSky draws the warm primary (scaled by its
  size), the cooler companion gets its own disc with a thin halo at a fixed separation (they rise and set
  together) and an unshadowed warm fill light. Sizes and energies come from `SolarSystem.suns_for(planet)`
  (home's systems/solar_system.gd + data/solar_system.json) when present, else the canon defaults.
- Steam Cloud covers every profile folder under a per-profile prefix (`p2_slot_0.save`); unprefixed cloud
  saves from older builds are adopted into profile 1.
- Dev: `--world-mods=heavy_rain+long_nights` (shots), `--menu=profiles|worlds --sample-worlds=N` (title).
- Tests: `tests/test_world_look.gd` (look selection, planet mapping and env hook, modifiers, easing,
  landmarks, sky bodies, WREN beats and lines, picker focus and selection, profile cloud stamp) and
  `tests/test_profiles.gd` (migration, isolation, New/Delete/Rename, summaries, focus grid, cloud
  prefixes); round trip checks the world look, the WREN thread, the profile stamp, migration into p1
  and two profiles kept apart.
- Next: wildlife and plants per world type (snow hares, dune lizards); per-world music tint; the world
  picker could show a small render of each world.

Music (owner, Nov 7): music is frozen as-is; do not spend more time composing. The owner may source different
music later, so keep tracks swappable (Audio.play_track ids). SFX should stay satisfying (pickup, bale, sale already
tuned in the first-hour pass); no new SFX work unless a bug.
## Update: restored ground turns green (wt/green)
- Root causes of "restored districts look brown": (1) the Poly Haven grass ground textures
  (sparse_grass / leafy_grass) are olive-brown and tan, so even life 1.0 rendered tan under AgX;
  (2) the plant files are whole rows of variants (and their LOD copies) merged into one mesh, then
  decimated to ~1500 tris, so each slot showed a thin smear of life-size 20-40 cm clumps; (3) most of
  a city hex is road, which never changed; (4) only ~15-45 plant slots per 10 m hex.
- `plants/meadow.gd` + `art/shaders/meadow.gdshader`: living ground cover placed once over lots,
  sidewalk fringes and kerb verges (~8-11k grass tufts, ~2-3k flower clumps, ~3.4k row sprouts at
  High), grown entirely in the vertex shader from the field's life texture (R life, G hex level, B row
  angle) at the same warped position as the ground, so the edges follow HexField.border_warp and
  nothing is rebuilt on the CPU. Thriving hexes add shrubs, ferns and small trees (real plant models).
  Planted = dark tilled soil in furrows (ground_pbr) with sprouts on the crests; Growing = young grass
  patches; Sustained = closed sward + flowers; Thriving = dense meadow, flower carpet, shrubs/trees.
- Ground: grass recoloured to rich greens (`grass_mat`), tilled rows, restored streets get clean
  grey asphalt, grass verges from the kerbs and moss in cracks. Life texture is RGBA8 (filterable
  everywhere) and uploads once per frame.
- Garden plants: one variant per slot (`plants/plant_parts.gd`), `plant_scale` 1.4 in plants.json.
  Butterflies 1.8x.
- Dev: `--restore=N[,level]` / `--restore-ramp` / `--restore=lake[,level]` (real planted slots,
  life, part-watered plants, Drips + a Seedling), `--green-cam=hid,dist,pitch,yaw`,
  `--garden-report[=S]`, `--no-meadow`. `--future=N` now uses the same realistic growth.
- Ledger intercepts: compact top-left card, short, no footer, hidden in Command view, photo mode,
  cinematics and with the HUD hidden (the relay cinematic's own lines still show). Header text is
  now "INTERCEPT // LEDGER" / "LEDGER // AMENDED" (new msgids: re-run tools/extract_strings.py after
  merging with the translations branch).
- Duck egg ("Duck on Duty") used the merged fire_hydrant file (clean + aged hydrants plus caps):
  now one aged hydrant. The --fauna-look=duck shot needs a green shore: use `--restore=lake,5`.
- Next: per-variant garden batches raise draw calls (~130 batches with all species); a merged
  per-chunk garden mesh would cut it. Grass density by quality preset should be checked on real GPUs.
## Update: walkable planet (wt/orbit, Nov 8)
- Done (merge now): `planet/world_bounds.gd` (`WorldBounds`, one `[orbit]` hook in scenes/slice.gd): Lumi can't fall off a district: soft wall 3 m inside the ground square (WREN hint), hover-and-fade rescue onto the nearest walkable ground when Lumi is outside or under the ground, robots and loose cubes put back. `--edge-test` (headless PASS/FAIL), tests/test_world_bounds.gd.
- Prototype (owner review first, not rolled out): `--orbit` loads `planet/orbit/orbit_world.tscn`: Verdance's 40,962-cell survey globe as one walkable sphere (R 920 m, 5.8 km around, 21 min on foot): streamed ground chunks with collision, a far shell, per-cell state texture, junk ring around Lumi, radial-gravity walker (PatchModel), parallel-transported camera, local sky/sun, hub sites with beacons, robots on the hex graph, data-only far crews. Dev: `--orbit-walk[=deg] --orbit-lap-quit` (lap report), `--orbit-view=ground|low|mid`, `--orbit-presim=MIN`, `--orbit-trail`, `--orbit-pieces=N`, `--orbit-hubs=N`, `--orbit-hex=M`. Tests: tests/test_orbit_globe.gd. Renders: screenshots/orbit/. The rollout plan is in the orbit report (coordinator).
- Done (orbit view, Nov 8): the far shell is now a **big-hex map** (`planet/sphere/sphere_shell.gd` + `.gdshader`): one flat-coloured hex per level-5 cell (10,242 hexes, ~16 ground hexes each) with a thin outline that fades when hexes get tiny on screen. Each big hex shows the share of its ground hexes that is junk / cleaned / green (planted -> restored) / water, in a per-biome palette, refreshed every 0.5 s as cells change, so the planet visibly changes from orbit while crews clean and plant. Cities (PlanetData.city) are slate-blue clusters with amber outlines and warm lights; hub sites glow cyan. Mid view: closer camera (`--orbit-mid-dist=2.2` radii), atmosphere rim, city name + hub labels (`--orbit-nolabels`). Fix: `Settings.apply_quality_to_tree` was overwriting the orbit fog with the flat-world density (5x thicker), which turned Command view into grey haze; the orbit re-applies its own fog after it. Tests: tests/test_sphere_shell.gd. Renders: screenshots/orbit/.
- Open: some start-base boxes stand in the lake west of the home hub (Command view); the sky is black in the ground views.

### Planet Rime environment (wt/p_rime)
- Done: `planet/planets/rime/` (`RimeEnv`, entry `apply(world, field, kind)` plus `dev_hub`, `prepare_field`,
  `dress_view`), registered in `data/planets.json` (read by `planet/planets/planet_envs.gd`). Own sky shader (black-blue
  thin air, two small distant suns, stars by day, ringed gas giant, faint aurora), ice heightfield to the crater rim
  (glassy ice, pressure ridges + slabs, glowing crevasses, drifts, mesas), borehole + headframe, core-drill
  derricks, frozen geysers, ice spires/arches; restored: hot springs thaw, moss, flowers, ice-lanterns, greenhouse
  domes, warm borehole. Junk set `rime_biome.json`; field ice sheet via `ground_pbr` `frontier_fx.w`.
  Dev: `--planet-env=rime` (`--rime-cam`, `--rime-nohud`, `--rime-restore`). Shots: screenshots/planet_rime/.
- Next (home): call the entry points when a Rime district loads; swap the fallback suns for
  `SolarSystem.suns_for("rime")` (already read when `systems/solar_system.gd` exists).

## Update: loading screen, readable subtitles, a better ark and pod (wt/intro2)
- **Loading screen** (`ui/loading_screen.gd`, autoload `Loader`; `scenes/boot.tscn` is the main scene):
  covers startup, New Game / Continue, back to title, rocket hub travel and world travel. Threaded
  load (`ResourceLoader.load_threaded_request`), then the scene is instanced (the district still builds
  synchronously in `_ready`, ~9 s headless: the bar holds at "Setting the scene"), then
  `systems/shader_warmup.gd` draws every spatial material of the new scene once on tiny quads in front
  of each viewport's camera for 5 frames, then it fades out. A Pixel-design Lumi (red/white, pink-red
  glow) hovers along the bar scooping a line of garbage into its hopper.
  Use `Loader.goto(path)` / `Loader.reload()` instead of `change_scene_to_file` / `reload_current_scene`.
- **The purple screen** was the project's default clear colour, `Color(0.55, 0.45, 0.7)`, visible while
  the first scene loaded and compiled with nothing drawn. Clear colour and boot splash are now
  near-black (no splash image) and the loading screen draws from the first frame.
- **Subtitles** (`ui/subtitles.gd`): one line at a time, bottom centre on a dark pill. Each line is
  fully visible for 55 ms/char + 1.2 s (min 2.5 s), then fades, 0.45 s gap; long lines split into
  one-line chunks at sentences/clauses. WREN, narration, cinematic captions (`Cine.caption`) and the
  Ledger (`LedgerUplink` now wraps the same line, red LEDGER tag) all use it. In cinematics (HUD
  hidden) it drops into the letterbox bar above the overlays. Glitches are purposeful (owner): readable
  text only flickers/scrambles for ~150 ms as it appears; `[glitch]...[/glitch]`, `[REDACTED]` and `█`
  spans glitch heavily the whole time; hostile Ledger lines get short whole-line jitter bursts.
- **Intro** (`story/intro.gd`): all lines in `Intro.lines()`; every beat waits for its lines; slower
  camera moves and ship glides; ~115 s unskipped (was ~55). Snappy wake-up blink flutter. The intro
  waits for the loading screen before starting. `--intro` prints the tightest subtitle margin.
- **The ark** (`story/cradle_ship.gd`, procedural, same API + `release_pod(k)`): broad flattened
  teardrop hull, layered upper deck with a big glass seed-vault dome and garden, keel with a six-pod
  rack, spinning greenhouse ring, two solar wings, five-bell engine cluster, chasing running lights.
  The old Blender glb (`art/models/cradle`) is no longer used.
- **Escape pod** (`story/escape_pod.gd`, `Intro.build_pod()` delegates): one lathed shell with the door
  cut out of it (no overlapping faces), jamb, cabin lining, porthole, beacon; `open_door()` = seal pop
  with steam from the seams, gravity drop into a ramp, settle, warm light spill on the ground.
- **Pod = Seedglider family** (owner): ten-facet shell with sharp chines, swept graphite fins with
  tangerine tips and orange running lamps, cyan glass porthole, thin cyan line, the ship palette;
  uses `art/shaders/ship_paint.gdshader` (wt/ship) when present, else clear-coat StandardMaterial3D.
  The ark's cargo rack holds six of these pods; the intro's pod leaves rack slot 2 exactly where it
  hung (`CradleShip.pod_xform(k)`), falls, lands in its crash pose and opens with a lean-corrected ramp.
- **Crash site** (`story/crash_site.gd`): scorched furrow along the approach, thrown-up clods, two hull
  shards, the pod sunk and leaning, a light smoke plume (one CPUParticles3D), a torn panel with
  flickering wiring, spark bursts and stuttering seams. Mends with upgrades (no new save state):
  first upgrade = sparks stop, panel bolted back, faint smoke; 4 upgrade levels = repaired, clean paint,
  calm beacon (`CrashSite.stage_for_upgrades()`).
- **Playtest #2** (owner): Space / pad A pauses and resumes the intro and the Bloom Core memories
  (`story/story_pause.gd`, freezes Engine.time_scale); Esc / B skips. The Codex has a "Watch the story"
  button: `Intro.replay()` plays the whole intro with a temporary pod and puts Lumi, the camera and the
  real crash site back afterwards (no save change). Repair stages read clearly: torn panel with live
  wiring, then a bolted tangerine-studded patch, then a clean plate with a cyan line, a calm cyan halo on
  the ground and blinking fin lamps.
- Previews: `res://scenes/story_preview.tscn -- --view=ark|pod|crash|loading|introframe --out=...`.
- Tests: `tests/test_subtitles.gd` (rule for every intro line, chunking, glitch spans, one line at a time),
  `tests/test_crash_site.gd` (pod parts, door angle, repair stages).
- Next: split the district build across frames so the loading bar keeps moving during it; pre-build
  the intro's SpaceStage behind the loader (its first frames compile on the intro's black fade now).

## Update: hex globe foundation (wt/sgrid, Nov 8)
- Done: `planet/sphere/` standalone module for the walkable round planets (used by wt/orbit's `--orbit`): `SphereGrid` (Goldberg hex globe, GeoSphere-compatible stable ids, O(1) point lookup, chunks of ~256 hexes, disk cache: level 7 = 163,842 hexes builds in 1.2 s, loads in 30 ms), `SphereTerrain` (true-scale noise terrain, per-cell elevation layer, `reserve_site` tangent-plane hub pads with a surface-aligned transform), `SphereCells` (packed per-hex state + state texture), `SphereStreamer` (WorkerThreadPool chunk builds, LOD 0/1/2 to the horizon + far shell, collision near bodies only, near rings for junk). Recommended size: level 7, hex circumradius 10 m, R 1840 m (table in sphere_grid.gd).
- Dev: `--sphere-demo` (`--sphere-cam=orbit|high|skim|ground`, `--sphere-outlines`, `--sphere-lod-tint`). Tests: tests/test_sphere_grid.gd.
- Phase A (Nov 8, wt/orbit, behind `--orbit`): the real Lumi on the globe. `Patch.enable_sphere()` + SphereMotor (hover, radial gravity, x4 boost, jump, camera-frame input); scoop real junk (`planet/orbit/sphere_field.gd`, `sphere_junk_view.gd`), bales fall with radial gravity, carry and cash at a Depot on the start site; game HUD; Command view (B). Real day and night sides: two suns fixed in space, the planet turns every 24 min (`--orbit-day`, `--orbit-time`). Checks: `--orbit-cash --orbit-cash-quit` PASS, lap with Patch 11.58 km PASS (0.22 m), tests/test_sphere_field.gd. Owner decisions in docs/DECISIONS.md; phases B-F as helper briefs in docs/ORBIT_ROLLOUT.md.
## Update: first minutes, objectives and HUD readability (wt/onboard, Nov 7)
- Done: **why Lumi cleans**. Right after the intro WREN gives the plan in four short lines (`data/objectives.json` "brief"): pod and relay dead, junk pressed into cubes powers the base recycler, power rebuilds the base and builds robots, green charges the Bloom Core so Lumi can call the Cradle. Then one **story objective** at a time on a card above the checklist (`story/objectives.gd`, `ui/objective_card.gd`), each with a one-line why: Power the base: sell 3 bales > Clean a hex > Build your first robot > Send your robot to work > Build a Haul Bug > Plant the first seed > Rebuild the base: level 2 > level 3 (opens the Requests board). Goal rows fold while an objective runs (G shows them). Old saves skip the brief and catch up silently.
- Done: "Clean this hex completely" is gone from the checklist (its last step is the upgrade); the **Clean a hex** objective outlines its target hex on the ground (`story/objective_hex.gd`): marching-squares contour of the warped hex (`HexField.border_warp`, so it follows where the junk ends), a thin additive line with a faint inner wash and a slow running light, cyan warming to green as it clears, and the hex's % floating above. The last 30% gets the amber pointer at the remaining pieces.
- Done: the detector's "SIGNAL %" reads **BURIED PART** and stays quiet during the restart checklist; the first time it picks up a part WREN explains it (plus a hint toast).
- Done: **HUD readability**: HUD theme with a heavier font and a denser halo (`ui/hud_readable.gd`); key hints are a dark pill with key caps at 15 px (`ui/key_hints.gd`), shown for the first 10 min / during the checklist / Full HUD, and the full key list while Tab is held away from the workbench (the "needs a workbench" toast shows once) and in the pause menu; notifications get a soft fading backing; the context line is 14 px and brighter.
- Done: the **Requests board opens later**: base level 3 or 45 min of play (`data/events.json` `unlock_hub_level` / `unlock_play_s`, `Contracts.unlocked()`), with a WREN line and toast; the workbench tab is hidden until then. Saves that already used the board keep it.
- Dev: `--objective=N`, `--objective-clean=F`, `--near-part`, `--hints-full`, `--requests-unlocked`, `--detector-on`. Tests: `tests/test_onboard.gd`; the round trip checks the objective flags.
- Done (playtest 2): a **purple waypoint** (`story/waypoint.gd`: a soft light beam on the target, a ring at its foot, a short flowing chevron trail on the ground from Lumi) points at the current objective's place (the scale with a bale in hand, the workbench for builds and base levels, the greenhouse once WREN hears the seed tin) and, after the objectives, at the current goal's (the next memory shard or the hex hiding it, the scale, the workbench, a buried part). "Read a memory shard" is now "Find a memory shard". The hex Lumi stands in gets a dimmer laser border (same outline as the objective's; contours are cached), replacing the straight amber focus line in the ground shader. The HUD context line always shows the hex % (or "OLD TOWN BASE" on the hub). The "LM-1 online" wake toast is gone (the brief and the card replace it).
- Done (owner story direction): **WREN needs a signal**. In the crash WREN (the Cradle's caretaker AI, Lumi's friend) sends one last two-line message that breaks up (`[glitch]` tag for the subtitle component), then is silent until the **Signal Tower** in the yard is rebuilt (`story/signal_tower.gd`, `data/signal_tower.json`, at (3.4, -6.6), E to build/boost; tiers cost 50 cubes / 900 + 60 parts / 6000 + 300 / 30000 + 1200). Tier = relay signal 25/50/75/100% (HUD district block: "WREN SIGNAL"), WREN's clarity (`Wren.stage()`: tier 1 crackly, 2 clearer, 3+ clear) and releases story lines she couldn't send (`Wren` gate between `line_started` and the new `line_out`; up to 6 wait in `flags.wren_backlog`). Chatter (non-important `say()`) is a third as likely and at least 150 s apart. Objectives "Rebuild the signal tower" (2nd) and "Boost the signal tower" (after base 2). Old saves get tier 1-3 from their old WREN stage. The autoplay bot builds it. Dev: `--signal-tower=N`.
- Open: intro2's crash cinematic still has its own WREN wake lines (story/intro.gd `_wake`); they should shrink to (or become) the one last message. Camp: please keep (3.4, -6.6) free (~3 m around) for the tower.
- Note for "buddy": the outline is the base layer; the light-bot's per-piece highlighting goes on top.
- Next: the objective lines name the "Bots" and "Hub" workbench tabs; if ui2's workbench rework renames them, update `data/objectives.json`.
## Update: Glim, the lantern bot, and brighter nights (wt/buddy, Nov 8)
- Done: **nights** (`planet/sky_director.gd`, `SkyDirector.night_lift()`): early nights get more moonlight (a floor even when the moon is low), ambient and exposure; the sky stays dark and starry. Full lift until Glim is found, 0.65 after (never off). `--night-classic` turns it off for before/after renders. **Clock**: until Glim is found days run at 0.6x and nights at 1.5x (`Glim.clock_mult`, data/glim.json "clock"), so ~70% of the first cycle is day.
- Done: **Glim** (`systems/glim/`: `glim.gd` rules/state in `flags.glim`, `glim_bot.gd` body + one OmniLight (shadows only on High+), `glim_scan.gd` scanner, `glim_director.gd` wiring; one hook in `scenes/slice.gd`). Found in the junk after 5 min played + 25 pieces scooped (the next scoop), or at the first dusk. Follows Lumi at shoulder height with a damped spring, bob and blinks; lantern full at night, a faint glow by day.
- Done: **hex scanner**: tap `glim_scan` (F / LT) for a ring pulse over Lumi's hex; every piece left gets a small floating gem marker (one MultiMesh, per-instance colour, pops as the ring passes, ~4.5 s). Pieces too heavy for Lumi's lift are amber: `GlimScan.too_big` uses `Patch.can_lift_piece(pid)` or `Economy.can_lift_vol(vol)` when the pace helper adds one; until then everything is cyan.
- Done: **upgrades** (data/glim.json, cubes/parts/seeds only): Lantern (range/energy, 3 tiers), Hex Scanner (cooldown, then neighbour rings), Auto-Scan (pulse every 20/12/7 s while the hex has junk), Tidy Tug (gentle magnet for tiny pieces, needs Lantern 2 + Scanner 2). **Looks**: 5 shells, 5 glows, 5 tops (antenna, sprout, beanie, halo); locked ones show "???" + hint. Hold `glim_scan` opens the Glim panel (`ui/glim_panel.gd`; pauses). If `CosmeticTargets` (wt/style) is merged, Glim registers his looks editor there by name (`GlimPanel.GlimLooksEditor`).
- Dev: `--glim`, `--glim-tiers=light:2,scan:3`, `--glim-look=shells:sunset,tops:beanie`, `--glim-scan[=S]`, `--glim-open[=S]`, `--glim-cam[=dist]`, `--night-classic`. Tests: tests/test_glim.gd; round trip checks `flags.glim` and the bot.
- Next: put a Glim entry in the merged Locker / workbench once ui2 and style land (the panel is self-contained today); let the autoplay bot buy Glim tiers; amber markers need the pace helper's lift rule.
## Update: escape pod hero pass, loading-screen street, title cinematic (wt/pod2)
- **Escape pod** (`story/escape_pod.gd`, paint `art/shaders/pod_paint.gdshader`): a sleek twelve-facet
  teardrop on a flared thruster skirt (four bells, tangerine lip), a raked faceted glass canopy over
  the door with graphite frame bars, three swept graphite fins that double as landing legs (tangerine
  tips, cyan leading-edge lines, orange running lamps), dark panel seams, cyan seams, raised plates,
  vent grilles, RCS nubs, grab rails, a mast beacon, and a big porthole in the door with Lumi's C-eye
  glyph. Seedglider palette; the paint is a satin pearl clear-coat with a re-entry heat-tint gradient
  (straw, bronze, blue-violet, soot at the base) driven by one `heat` uniform. Same model in the ark's
  rack, the intro fall and the crash site.
- **Condition** (`EscapePod.set_condition` / `animate`, driven by `CrashSite` from the upgrades
  already bought; nothing new saved): 0 crash-damaged (heat-tinted and sooty, cracked canopy and
  porthole, a torn panel over live wiring with a swaying dangling cable, stuttering seams and glyph,
  sparks, smoke); 1 patched (bolted steel plates, strobing fin lamps, faint smoke); 2 restored
  (`REPAIR_LEVELS` = 4: clean pearl and tangerine, lit fin edges, a soft pulsing hover glow and light
  under the skirt); 3 planter-beacon (`PLANTER_LEVELS` = 14: a ring of seedlings round the skirt and
  a soft green beacon beam).
- **Loading screen** (`ui/loading_vignette.gd`): the 2D bar art is replaced by a small 3D street in
  the game's look (real ground material and junk meshes, one warm light, fog, soft edges) where red
  Lumi (`LoadingVignette.make_lumi()`, the Pixel colourway; swap in the hero helper's red Lumi there)
  glides along as the bar fills and beams up each piece. Built on first use, never headless
  (`--loader-2d` keeps the old 2D bar).
- **Title screen** (`ui/title_cinematic.gd`, hooked from `ui/main_menu.gd`): a 72 s loop: high over the
  junk-covered district, over the crash site (damaged pod smoking and sparking), down to Lumi, who
  cleans the clearing piece by piece (beam, the piece lifts and vanishes, a hop), then up again.
  Low preset: fewer pieces. Dev: `--title-t=S` start time, `--title-hold` freeze the camera.

## Update: Glim in the workbench (wt/buddy2)
- Done: workbench Upgrades tab has a "Glim" section (`ui/glim_bench.gd`, BenchRows, hidden until Glim is found); the Locker lists every unlocked CosmeticTargets bot after Lumi (`ct:<id>` entries in `ui/locker_panel.gd`), so Glim's looks are edited there. Hold F still opens the Glim panel.
- Done: amber scan markers use Pace's lift rule (`GlimScan.too_big` -> `Pace.can_lift(field, pid)`).
- Done: the autoplay bot buys Glim's Lantern and Scanner when affordable (1.5x margin); found at ~5 min.
### [planet-tidewell] Tidewell (Ocean World) environment
- Done (wt/p_tidewell): `planet/planets/tidewell/` (env.gd entry `TidewellEnv.apply(world, field, kind)`, plus
  static hooks `prepare` / `field_water` / `post_generate` that the slice calls while the field is made),
  registered in `data/planets.json`. Opaque ocean shader to the horizon (swell, shore foam, whitecaps, depth
  colour from baked bed maps, refracted seabed with caustics, kelp, coral, fish/whale shadows, oil slicks that
  clear hex by hex), archipelago of isles / sandbars / reefs, Ledger jack-up dredging rigs and a half-sunk ore
  barge, drowned tower tops, buoys, moorings; restored: mangroves, palms, floating gardens, lighthouses with thin
  beams; future: white sea platforms, solar rafts, light buoys. Lumi floats over water (bob, wake ring, spray,
  mirrored reflection; no wading slowdown via `world.meta hover_water`), skimmers leave wakes. Binary suns
  (`TideSuns`: companion light + sky disc, SolarSystem.suns_for when present). Trash rafts (ghost-net mats) and a
  nets-and-buoys junk palette. Dev: `--planet-env=tidewell [--tide-cam=dist,pitch,yaw[,fov]]`. Test:
  `tests/test_planet_tidewell.gd`.
- On the shared contract now (planet/planets/planet_envs.gd: dev_hub / prepare_field / dress_view / apply);
  own slice hooks dropped. Owner (Nov 8): flat-world layout paused for the walkable sphere; env.gd's header lists
  what transfers to a globe (sea shader, generic hover-over-water, suns, props, junk palette, restoration rules).
- Site prefabs for the globe (Nov 8): `TideSite.place(id, root, stage, restoration)` in planet/planets/tidewell/sites.gd
  builds compact local scenes on their own sea patch (ocean shader `local_space`): hubs `hub_raft` (anchored raft) and
  `hub_stilts` (stilt yard on an islet); landmarks `wreck`, `dredge_rig`, `reef_garden`, `buoy_field`. Listed in
  data/planets.json "tidewell".sites. Preview: `res://planet/planets/tidewell/site_preview.tscn -- --site=<id>
  --site-stage=0..2 --site-restore=0..1 --site-cam=dist,pitch,yaw[,fov,ty]`. Floating junk thins with restoration.
- Next: home wires Tidewell as a campaign planet (call the same hooks from its world build); fauna2 may add
  `tidewell` to gull/fish regions; sound: music key `tidewell_swell`.
## Update: the owner's songs, CDs and artists (wt/tunes)
- Done: song library `data/songs.json` (all 45 planned songs from docs/music/suno_prompts.json; files in audio/songs/<id>.mp3, missing ones skipped everywhere, so new MP3s drop in by id + import). `systems/tunes.gd` (rules, class `Tunes`), `audio/tunes_director.gd` (playback on a "Songs" bus, child of Audio; hushes the synth score via `Audio.tunes_hush`, which stays the fallback when no song fits).
- Title screen: a random owned song each time (main theme first on the very first launch), crossfading, with a now-playing tag bottom right (`ui/title_song_tag.gd`). Intro: The Fall of LM-1 from the first frame, paused with the cinematic, faded at the landing.
- In play: background shuffle of owned songs that fit the planet and moment (home planet first, story songs sometimes, other planets rarely; night/restored songs only then), 30-90 s quiet gaps, never the same song twice in a row.
- CDs (`planet/cd_finds.gd`): intact CDs surface on cleaned hexes of the artist's home planet (pity guarantee by 18 hexes, kept in flags.songs.pending until picked up); scratched one-play CDs (5-10 per planet, songs you don't own; "Play now / Keep for later", CD case of 4, `ui/scratched_cd_ui.gd`). 13 in-world artists with homes and bios; Codex "Artists" tab (`ui/codex_artists.gd`). Start songs: Greenfall (Main Theme), Clean Sweep, Morning Shift.
- CD player (Keepsakes tab, `ui/extras_cd_list.gd`): Shuffle / pick on repeat / off, lock + "found on" rows, CD case. Pre-Glim the music comes from the CD player (softer far away) and stops when you leave the district; with Glim's Music upgrade (`Glim.has_music()`, wt/buddy) any CD plays anywhere via N (`ui/tunes_picker.gd`). Credits: "Music by Lucas" (no Suno in the game; licensing note stays in audio/songs/README.md).
- Dev: `--cds=a,b`, `--scratched=a`, `--cd-play=shuffle|id`, `--cd-drop`, `--glim-music`.
- Next: autoplay bot could walk to CDs; a CD-player hub radio model is wt/camp.

## Update: planet Ochre environment (wt/p_ochre)
- Done: `planet/planets/ochre/` (OchreEnv `env.gd`, `pit.gd`, `props.gd`, `excavator.gd`, shaders, `junk_biome.json`):
  the play field sits on a wide haul bench low inside an enormous terraced open-pit mine (2 steps down to a
  sludge pond, 9 benches of layered ochre / terracotta / cream rock up to a ~100 m rim, haul roads spiralling
  between them), layered mesas and salt pans on the plateau, a white-gold two-sun sky (canon binary star,
  reads `SolarSystem.suns_for("ochre")` when home's helper exists) with a companion fill light, heat shimmer,
  dust devils. Three bucket-wheel excavators (one toppled on the rim), haul trucks. Junk: ore tailings,
  broken drill bits and rods, Ledger ore crates, bucket teeth, ore sacks (procedural, registered in AssetLib).
  Stages: ruined (rust, slumped booms, salt crust) -> mid (repainted, booms raised, shade sails) -> future
  (white machines with planters, wind-wheel vanes and a wind-catcher tower, solar sails with thin light
  seams, a light seam on each terrace crest). Restoration (hex levels) greens the terraces from the floor up:
  crop rows along the contours, water channels at each wall toe, vines, palms and succulents, an oasis pool.
- Registry: `data/planets.json` (planet id -> env script, sky, fog, sun, ambient, palette, junk tint, music
  mood); `planet/planets/planet_envs.gd` (PlanetEnvs: prepare/apply, dev hook). Dev: `--planet-env=ochre`
  (a wild district dressed by the env), `--ochre-restore=0..1`, `--ochre-cam=x,y,z,tx,ty,tz`.
- Integration for home/worlds2: call `PlanetEnvs.prepare(kind)` before the field is generated (junk models and
  biome set), set `field.biome = kind.junk_biome`, `view.skip_horizon = true`, `field.set_meta("planet_env", id)`
  (FutureLayer then skips its city spires), then `PlanetEnvs.apply(world, kind)` once the scene is built.
- Next: waterfalls between terrace channels at the futuristic stage; tune on real hardware (pit terrain is
  ~90k vertices in 16 sectors; plants ~4.7k instances in 28 MultiMeshes with visibility ranges).

## Update: Ochre kit for the walkable globes (wt/p_ochre, Nov 8)
Owner: planets become round, hex-covered, walkable globes (orbit helper). The flat pit, mesas and plateau in
`planet/planets/ochre/` (pit.gd, `_build_terrain`, `_build_mesas`, ramps, falls) are a prototype only and will be
rebuilt on the sphere. What carries over, and how to place it on a globe:
- Registry: one `planet/planets/planet_envs.gd` (Rime's contract: dev_hub / prepare_field / dress_view / apply) and
  one `data/planets.json` (rime + ochre). Ochre extras: `junk_biome`, `no_lakes`, `pieces_mult` (junk per hex,
  "the whole world is trashed"), `prefer_biome`, `exposure`.
- Palette (`planets.json` ochre.palette): ochre, terracotta, cream, plum strata; salt; oasis; leaf; Ledger yellow;
  thin-line cyan. Sky/fog/ambient values there are the low-haze, high-contrast set (owner: vivid, not foggy).
- Materials / shaders (`planet/planets/ochre/*.gdshader`), all world-space so they work on any surface:
  - `ochre_terrain`: strata bands by height (pit walls and landforms share layers), quarry-rock triplanar,
    red bench gravel, ochre sand, salt-pan crust (cell cracks), tailings streaks, cheap foot-of-wall occlusion,
    restored crop rows / water channels / vines (COLOR channels: r level, g flat, b across, a "in the mine").
    On a globe: drive COLOR from the hex's height band and slope instead of pit rings.
  - `ochre_sky`: hot white-gold horizon, blue zenith above the haze, both suns from `SolarSystem.suns_for("ochre")`
    (primary burns white, companion stays orange-red), stars at night.
  - `ochre_water` (sludge -> oasis), `ochre_fall`, `ochre_sail` (canvas / solar membrane + thin hem light),
    `ochre_foliage` (sway), `ochre_shimmer` (heat haze ring near the ground).
- Props (`props.gd`, `excavator.gd`, all procedural, one draw per material): bucket-wheel excavator (ruined /
  repainted / futuristic planter + wind wheel + wind-catcher), haul truck, junk set (tailings x2, tricone bit,
  drill rod, crates x2, bucket tooth, ore sack; registered into AssetLib by `prepare_field`), boulder x3 (scree),
  date palm x3, agave x2, barrel cactus, aloe, shade / solar sails. Each takes a Transform3D: place per hub site
  with the local up vector as the basis Y.
- Restoration rules (per hex on a globe, per bench here): junk clears and plants appear from the lowest ground
  up (the water source) as hex levels rise; ruined (1) rust, slumped booms, extra scrap -> mid (2-3) repainted,
  shade sails -> future (4-5) white machines with planters, solar sails, a thin light seam on crests, waterfalls.
- Dev: `--planet-env=ochre`, `--ochre-lookbook=1|2` (kit under both suns), `--ochre-restore`, `--ochre-cam`.
## Update: hub sites, rocket hop, hover-sled (wt/orbD, phase D, Nov 8)
- Done: **Site API** `PlanetEnvs.build_site(site_root, site, stage 1-5, restoration)` -> `SitePrefab` (planet/sites/site_prefab.gd): anchors depot/bench/rocket_pad/door, collision (trimesh of solid meshes unless the builder has bodies), `set_stage`/`set_restoration` (in-place re-dress where the builder supports it, else rebuild). Dispatch in `planet/sites/site_builders.gd`: Verdance (`VerdanceSite`: real CityView + StreetDressing blocks, ruined), Rime (p_seas' `RimeHubSite` via planets.json, like Tidewell), Anvil/Ochre/Tidewell via their own `build`/`place`. `PlanetEnvs.globe(id)` gives radius/hub count (data/planets.json `globe`, else the owner's size table).
- Done: `site_inv` shader global (project.godot): world-space maths in building_city, deco, yard_slab, puddle, mural, fabric, light_seam, junk_coat run in the nearest site's frame on the globe (identity on the flat game).
- Done: `SiteManager` (globe): builds hub prefabs within 420 m of Lumi, frees them past 650 m, clears junk under building footprints, planet % over the built hubs' regions (18 rings; HUD reads `world.planet_fraction()`), per-hub growth radius that greens the rest (SphereCells + survey PlanetData), save_state/load_state ready for B1.
- Done: `HubHop` rocket hop between hubs on the same globe (no scene change): lift-off, arc over the curve, land on the target's rocket_pad; 7-15 s by distance. `--orbit-hop=N[,M]`.
- Done: `HoverSled` (player/vehicle.gd): globe-only Upgrades entry `hover_sled` (3 tiers), retunes Lumi's SphereMotor (`speed_mult`, inertia); E to ride/leave. `--orbit-sled[=T]`. Boost is a Settings action (Shift / LS click; the goals toggle lost its LS pad binding).
- Next (after B1): wire SiteManager into slice-on-globe (hub levels -> set_level, built flags, saves), GlobeView/_launch -> HubHop, place the pod/bench/bin on the start site's anchors.

## Update: round planet phase E (wt/orbE, Nov 8)
- Done: sky and day/night on the globe. SkyDirector sphere mode (planet/sky_director.gd) drives the world-space sky (planet/orbit/orbit_sky.gdshader) over OrbitDay. The spin is the clock and the local time follows Lumi's longitude. Binary suns from BinarySun.suns_for, a full moon opposite the suns, a cloud deck anchored to the planet, haze lifting with cleaning, storm and Long Nights, readable nights (night lift). Glim's lantern replaces the Lumi lamp.
- Done: Future Layer per cell on LOD-0 chunks (planet/future_layer_sphere.gd), from SphereCells.level. Builds are budgeted at 2.5 ms per frame.
- Done: survey hologram (GlobeView sphere mode, far-shell big hexes, "you are here" pin, hand-held on local up), PlanetGlobe overlay of the walked cells, system map globes sized by GlobeSize, photo mode, and core-charge and rocket cameras on local up (WorldUp).
- Done: perf budgets per preset (planet/orbit_quality.gd) and numbers in docs/PERFORMANCE.md "Round planet". All of it is wired into the real slice through planet/orbit_layers.gd (one call in scenes/slice_orbit.gd).
- Pending: day/dusk/night renders (killed for memory twice in the shared container; command in the orbE report), rendered draw-call numbers, Mac fps, flipping the default (main, after owner sign-off).
- Done (orbD, Nov 8 late): the start yard's models on the globe (`planet/sites/yard_site.gd`): the yard helper's own models (YardArt, the build scripts, FabricatorModel, the intro's pod) on the hub-0 anchors. Camp drives the lean-to/bench/lamp/generator bits as on the flat game; YardSite follows the same saved state for the extra lamps, compost press, radio, nursery, telescope, stations and Bot Fabricator. Every planet's start site gets the yard anchors; anchors inside another planet's geometry or off its walkable ground move to reachable, spaced spots, and the models follow. Dev: `--yard-report`, `--yard-all`. `--site-reach` with the whole yard built: Verdance, Ochre, Rime, Anvil PASS; Tidewell's raft deck (~150 m2) is too small for all 20 machines (17/20; the early yard passes).
- Done (orbD): Homeward launch and interplanet rocket on the globe, kit hover-sled with ride animation, footprints for every planet's sites (F_HUB, round-trip safe), lap autowalk detours, SphereMotor wedge fix.

## History 2026-11-08: play-ready wrap-up
Superseded by "Current state of round Verdance" at the top.
- **Merged this round:**
  - Round-planet parity: First Seed, compost press, seed finds, memory shards and the document view.
  - Stations, litter, lakes with fish, street power.
  - Robots: auto-baler, haulers to depots, the Drip water net.
  - Intro, binary sun, lens view, Bloom finale framing.
  - Autoplay pause watchdog.
- **Checks:** 877/877 tests pass, plus the flat save round trip, the orbit round trip and the two-process orbit reload.
- **Round planets** are still a preview: the title toggle "Round planets (preview)".
- **Open (none block play):**
  - Haulbugs get "no path" on Ochre, Rime and Anvil globes.
  - The Ochre Bloom-finale camera is blocked by start-site geometry.
  - A fauna upright check fails on the far-out globes.
  - The orbit_old_* round-trip legs wrongly load the Verdance flat-save fixture under --orbit-planet.
  - A reload resumes from the last autosave rather than the exit state.
  - Autoplay never cashes in at the depot on Tidewell.
- **Held for later:**
  - Wildlife and Meadow on the globe (cf2ca15, reverted in a4b506f).
  - Feel FX (stash on wt/orbB).
  - The Cradle launch onto a globe.
  - The other 5 Lumi designs and planet music themes.
- **Owner:** a Mac perf run, `--orbit --quality=1 --perf`, then the same with `--orbit-planet=anvil`.

## History 2026-11-08 evening: round Verdance v1 pass (owner playtest notes)
Superseded by "Current state of round Verdance" at the top. Most of its open list is closed.
- **Done and merged:**
  - Round world is the only mode.
  - New loading screen, settings and music rules.
  - Trash ×3 density and the flat city on Verdance.
  - Shorelines, and the far and intro trash look.
  - Start yard: trash to the pad edge, a clean pad, the bin bay 5.5 m from the bench, no sled or Glim at the start, and a fitted pod collider.
  - Workbench: tiers gate tabs, fixed order, click for details.
  - One goal timeline, with a beam, ring and trail on every step.
  - WREN's "why" line, the bin toss FX, the bale how-to, and a faster start (tower ~3 min, Bot Bay ~30 min in bot time).
- **Open:**
  - Intro voice-over: samples are made (Kokoro), but the owner hasn't listened yet.
  - The beam/ring and the intro-fall planet haven't been seen in a render.
  - Bale clipping hasn't been reproduced.
  - The globe light is harsher than flat Verdance.
  - The new texts aren't translated.
  - The pad can look pale at noon.
  - Robot timing after the Bot Bay hasn't been checked.

## Update: Verdance start town (wt/v3city, owner item 42, Nov 8)
- Done: the start hub is a town. It has a 7x7 street grid cut to the flat pad and the lake shore (the yard sits on a lakeside peninsula). The forecourt rows stand past 40 m so the first hexes stay whole, then mid-rise blocks, then towers on the outer ring. Street furniture (`planet/street_furniture.gd`): crossings, centre lines, bus stops, benches, bins, post boxes, bollards, name posts, stop signs, traffic lights and parked wrecks. Past the pad, a skyline on the curved ground (`planet/sites/town_outskirts.gd`, 150-330 m, plinths, building_city `local_space`); the cells under those buildings become hub ground (F_HUB), and planet % no longer counts F_HUB cells.
- Checks: `--city-walk` (planet/sites/city_walk.gd: walk area, pockets, all 8 ways out, junk reachability) and `--town-map=PATH` (top-down plan PNG).
- QA fixes: the yard pad is now real bevelled slabs with 12 cm joints (it had 5 cm hairline seams). Open water past the near ring reads as water (murky olive to clear teal, ripple mottle, sheen), and the near lake surface is murky green, not grey.
- Done (round 2): every hub is a town with its own character (VerdanceSite.KINDS: downtown, old town, industrial, suburb, harbour where the lake reaches in) on a 120 m pad, with furniture and outskirts. The outskirts keep junk off per piece (YardKeepOut.add_world) rather than clearing cells, and outposts and eggs avoid the buildings. Hub towns build 6 ms a frame in play (BuildBudget.begin_play). Lake waterfronts: quay, railings with gaps, lamps, piers, boats, an old ship on the start lake. Furniture is batched (144 m cells, 3 surfaces, no small-prop shadows).
- Done: the land between hubs (`planet/sites/hinterland.gd`): open junk fields, suburbs and industrial edges decided per hex past 345 m from any hub. Buildings and props are MultiMeshes over the ring round Lumi (near/far split per instance), with colliders within 70 m and footprints in the junk keep-out. `--hinter-report`, `--no-hinterland`.
- Open: a hinterland walk check.
- [v5look] Done on the hinterland:
  - Houses have pitched tile roofs with chimneys, works sheds have sheet roofs; every building gets its own tint and height (MultiMesh instance colour and scale); 4 looks per archetype.
  - Yards: a garden shed, picket fences, sometimes a wreck in the drive.
  - Roads: continuous hex chains (the edge of a noise region) laid on the ground mesh as dusty asphalt strips. Hexes beside a road get more houses, facing it, and power poles. The lane keeps junk off (a soft keep-out: `YardKeepOut.add_world(..., true)`, not a building for TargetReach) and road hexes get no junk mounds (`SphereField.pile_block`).
  - Dev: `--hinter-goto=track|house|works[,back_m[,side_m]]` stands Lumi there for a render; `--hinter-report` also prints decide time and the nearest house/track.
  - Open: junk materialised before a road was decided (a dev spawn, or a save made right there) stays on the lane; roads end at the hub clearance (345 m), they don't join the town's streets.
- [v5look] Light on round Verdance (`planet/sky_director.gd` sphere mode, `planet/orbit/orbit_sky.gdshader`, `planet/orbit/orbit_day.gd`): warm noon sun in dusty air, warm day fill, golden depth haze whose colour the sky's horizon band shares (`fog_col`), sun discs kept out of the radiance map, the flat game's thin glow settings. The start pad is matte concrete. Open: not seen on Forward+ (glow, SSAO), only opengl3.
- [v5look] Glim on the pod (`systems/glim/glim_bot.gd`): scorched dark, 1.4x while stuck, head hanging, half-shut glowing eyes, a lantern stutter every 2.9 s with sparks; `GlimBot.flare()`. The intro glances at him after the crash (`Intro._glim_beat`, ~2.2 s).
- [v5look] Street corners (`planet/street_furniture.gd`): every corner of a junction is tried for its pole, the yard block counts toward four-way; the start town went from 14 corner poles (3 lights) to 26 (6 lights).

## Update: Verdance clarity pass (wt/v3clear, owner item 41)
- **Texts:** objectives, checklist, prompts, toasts and WREN briefs use short, plain words, start with a verb and show the key glyph. "Compartment Size" is now "Chest Size". Codex toasts stay quiet until the tower is up.
- **One next thing:** the objective card's why line turns into an amber hint for these cases (`Objectives.situation_hint`):
  - chest full
  - piece too heavy
  - not enough cubes (how many are missing and how to earn them)
  - nothing to pick up nearby
  - far from home when the next thing is at home (the beam points home)
- **Pace:**
  - Bot Bay costs 1200 cubes and 40 parts. The first Scoopie costs 800 cubes (was 1100).
  - New steps: "Clean 2 hexes", "Clean 10 hexes", "Finish a research project" and "Clean 20 hexes".
  - Orbit autoplay (8x): the whole story chain to base 2 runs in ~43 min. No step stalls. The gaps between steps are 4-7 min.
  - On the globe, the robot objective counts the crew, and autoplay plants (sparse garden slots).
- **Workbench:** 48 px rows. Affordable rows stand out and the current goal's row has a cyan frame. Locked rows show their name and what unlocks them. A bought row flashes.
- **Fixes:**
  - The trash bin stands inside its bay (`Depot.seat_bin` on the "bin" anchor).
  - The robot objective counts the globe's crew.
  - The HEX line sits above the level bar.
- **Tool:** `--clarity-log` prints over time what the player is told (card, prompts, toasts, WREN).

## Update: reachable targets and real water on Verdance (wt/v4world, owner playtest 3 #53, #55)
- #55, every target reachable: TargetReach (planet/sites/target_reach.gd) covers footprints (start town, hub towns, outskirts, hinterland via YardKeepOut.in_building), water, steep ground and colliders near Lumi, plus a walk-out check (no walled-in courtyards). Shards, CDs and parts move to the nearest reachable ground. Outposts, eggs, gnomes, the Ledger relay and the First Seed greenhouse only take reachable spots. The hub frame waits for a hub's town to be built. The beacon never stands in a collider or footprint. Audit: `--orbit --target-reach` (was 399/2857 unreachable, now 0). Test: tests/test_target_reach.gd.
- #53, water: the near lake surface was wound backwards, so it was culled from above and players only saw the lake bed (the "flat slab"). The new sphere_water.gdshader has world-space waves with noise chop, depth tint from the shore (vertex colours), see-through shallows, shore foam, and murky olive with scum before cleaning, dark blue-green after. Its fresnel sky reflection and sun glints are computed in the shader from the sky material (SphereWater.sync_sky), with the renderer's own reflection off, so opengl3 and Forward+ agree (no cyan or grey slabs). The far ground water uses the same palette, and lake murk now reaches the state texture. Dev: `--lake-view[=back_m]`, `--lake-view-high[=m]`, `--lake-clean`, `--lake-debug`. Test: tests/test_sphere_water_look.gd.
- Open: not yet seen on Forward+/Metal (all renders were opengl3); the murky near-ring water is slightly darker than the far water from high up.
## Update: robot unlock order, hauling Lumi's bales, Hover Jets (wt/v4bots, owner items 44, 46, 52, 54)
- **Unlock order (44, 46):** the Bot Bay (Salvage Logic) brings only the Scoopie. The Haul Bug and the Skimmer are "story unlocks" (`data/research.json` story_unlocks, `Research.check_story`): not tree cards and no cost. They arrive by themselves, and WREN says one line for each (a toast while she is silent).
  - Haul Bug plans: 20 min of play after the first robot, with 8 hexes cleaned.
  - Skimmer plans: 35 min after the first robot, with a first plant.
  - Base level 3 (or owning one already, for older saves) grants them at once.
  - Drip is unchanged (Drip Blueprint, base 3).
  - The "Build a Haul Bug" step moved after "Rebuild the base to level 2". It waits on `flags.haul_rig` with a "WREN is looking for plans" hint, and its pointer leads to the hexes until then.
  - Locked cards say "comes later" instead of naming a research.
- **Haulers take Lumi's bales (52):** on the globe, a loose bale lying still for 3 s near Lumi joins the crew's bales while a Haul Bug is on the crew (`SphereBales.adopt_loose`). It skips bales on feeder, scale or outpost pads and within 6 m of the Depot. The record pays the Depot's sell factor (crew cash is raw value); the cube keeps its own value if Lumi takes it back. Saved with the crew (`raw`).
- **Hover Jets (54):** a new Lumi upgrade (1500 cubes, Tread Speed 1, base 2, stat `hover_water`).
  - Without it, Lumi stops at the shore and slides along it (`Patch.shore_clamp`: a probe ahead, then turns up to 85 degrees; a post-move check undoes a boost that carried him in).
  - Already in water, he can still wade out.
  - The hover-sled and Tidewell's `hover_water` meta also let him cross.
  - A one-time toast names the fix.
  - Lake hexes were never objective targets.
- **Autoplay:**
  - On the globe the bot refilled the can at the flat WATER_STAND (a point near the planet's centre) and wandered off; now it refills by the globe's bench (`_water_at`).
  - It buys Hover Jets first once a shore has stopped it, and saves for base 2 before the first Skimmer.
  - Escapes with water ahead print as `[bot-shore]`.
  - Orbit autoplay (8x): first robot 20.9 min, base 2 34.9, Haul Bug 41.1, Hover Jets 49.2, Skimmer 56.0, no script errors, no shore stalls.
- **Open:** the bot's stuck escapes climb in the garden phase (13 at 47 min, 77 at 107 min, all after Hover Jets). This looks unrelated to the shore block and is worth a look.
- Tests: `tests/test_v4bots.gd` (unlock order and timing, objective order, adoption and pads, the shore clamp, the upgrade).

## 2026-11-10: v5load (loading, hitches, draw cost, cloud saves)
Details and numbers in docs/PERFORMANCE.md (perf passes 6-8).
- Done: no long loading frames on Verdance (longest about 0.12 s of CPU, was 1.2-2.3 s); the build is no slower, rendered or headless.
- Done: hitches in play (junk ring, wildlife, hub switch on a rocket hop, autosave); a fifth of the ring's junk was never drawn, fixed.
- Done: draw cost down 10% on Medium and 21% on Low at the start site; cheaper far water.
- Done: Steam Cloud covers the round world's saves; demo saves carry over into the round tree.
- Open: the frame where the 3D scene first draws at the end of loading (shader warm-up) is one long frame; needs a check on real hardware.
- Open: a hub town building as Lumi walks to it (25-45 ms frames for about 3 s); Anvil's yard builder (0.45 s slice); litter batching (428 MultiMeshes a ring).

## Update: play-test of the first 2 hours on round Verdance (wt/v5play, 2026-11-10)
- Full notes, pacing tables and repro lines: docs/QA_VERDANCE.md, section "Play-test, first 2 hours".
- **Fixed:** Haul Bugs standing "idle: no path" in the town (routes fall back to land-only); junk inside buildings (keep-out buckets); hinterland buildings at least 2.2 m apart; watering and planting across a hex border; the can fills anywhere on the yard; scooped metal, plastic and glass pay Parts on the globe; the rocket's place survives a save; the workbench no longer starts the flat rocket on the globe; "Launch the rocket onward" counts hub hops; the card says what is missing for base levels and robots; a finished step folds in at most 3 goals; the fauna scan's freed-node error.
- **Tools:** `--hinter-walk`, `[bot-esc2]` with `--bot-debug`, `--crew-debug`, `--soak-bales`, a fuller soak digest, the reload check covers the rocket.
- **Result:** base 2 at 40 bot-minutes (was 71), 1 stuck escape in 160 minutes (was 31), haulers carry about 300 bales each (was 20).
- **Open:** the bot does not save for base 3 (137 min); the start got 2.5 min slower with a merge of main; see "Still open" in QA_VERDANCE.md.

## 2026-11-11: v6hubs (every hub has a purpose; the rocket hop)
- **Data:** `data/planets.json` "verdance" has `hub_defaults` and `hubs` (one entry per hub: name, town, landmark, the rocket piece and gift it gives, its local chain). How to change it: docs/ADJUSTING.md, "Hubs".
- **Main path (6 hubs):** Landing Yard (home), Garden Row (seed stock), Gantry Works (hull plates), Signal Heights (star chart), Fairground (power cell), Stack Works (fuel). Four extras open once the six stand.
- **Restore flow:** fly in, clean a few hexes there, press E at the landmark to wake it (price from `Hub.far_cost`). The wake sets the hub to level 2 and built, lights a beacon on the landmark, gives the piece and gift, and stands a field bench by the rocket pad. A woken hub's level then follows its clean share.
- **Picker:** home first (marked HOME), then NEXT STOP, then the other listed hubs; each row has the town type, why to go, its state and the robots working there. The list scrolls. Hubs past the rocket's limit are shown locked.
- **Hop:** skippable (E / jump), HUD hidden in flight, the camera looks down the path at the new town on the approach, the town's name shows once on landing, then the step card.
- **HUD:** the top-right lines are now this base's clean % and "BASES n/6".
- Code: `planet/sites/hub_plan.gd`, `planet/sites/hub_purpose.gd`; tests: `tests/test_hub_plan.gd`.
- **Hop as a moment:** every hop timing, the arrival title's timing and a first-arrival music sting are data (`hub_defaults.hop`, docs/ADJUSTING.md). The arrival title shows the name, the town and landmark, and why we came (`hub_fly_<order>` in data/story_reasons.json, the same line as the goal card). `--hub-walk-fly=N` makes the walkthrough fly the real hop and check long frames on arrival (QA H5: the long frames are behind the veil).
- **Six-base walkthrough** (`--hub-walkthrough`, `planet/sites/hub_walk.gd`, docs/QA_VERDANCE.md): flies to and wakes the five far main-path hubs in order and checks town, landmark kind, reach, sleep card, wake prompt through Interactables, E wake, flags, rocket piece, gift, field bench, beacon, HUD and logged errors. PASS on 2026-11-11. It found that E at a far landmark did nothing in play (the entry was registered before Interactables existed); fixed. The town look and landmark per hub come from the data (`town`, `landmark.kind`), except a lake town is always a harbour (Fairground).
- **Open:** the survey map (M) still shows the old city names and no landmark glyphs; the story text is placeholder (v6story); goal-card steps for "fly to the next hub" and "upgrade the rocket" are v6pace's; the hub town builds behind the veil in about 10 s on this box (headless), to be checked on real hardware.

## 2026-11-11: v6feel (how Lumi feels to play, round Verdance)
- **Carried bale inside Lumi (owner items 22 and 45): cause found and fixed.** The pick-up tweened the bale's height while Patch wrote its x/z every physics tick; the physics server hands a moving frozen body its last transform back before each tick, so the tween's height was thrown away whenever Lumi moved during the lift, and the bale stayed at ground height inside him. Patch now places every carried bale each tick, on a lift path that goes out and over his head; the hold point rides his lean and squash. Also fixed: the hold point cached at 0.8 m when first measured while Lumi was hidden (rocket, loader), never re-measured after a Character Builder rebuild, and the stack sway read zero.
- **Snagging:** on the globe Lumi's lifted collision shape was never applied (the flat box dragged on the ground and stopped dead on every corner, post, kerb and heap). He now has a round body that slides on the level round corners, posts and junk heaps, and hovers over kerbs and planters up to 0.45 m. Fences and walls still stop him.
- **Camera (SphereCam):** a soft arm with whiskers (eases in before a wall cuts the view, out gently), climbs a wall that is close behind Lumi and looks down at him, looks past posts, hides Lumi when the camera is inside him, softer up-and-down follow, and the flat camera's screen shake (bale press, depot, heavy pieces did nothing on the globe).
- **Scoop:** a dim reticle on the piece the next pulse will take; the lock and aim reticles lie on the local ground (they lay in world XZ, tilted on the globe).
- **Controller:** rumble for chest full, heavy piece, bale press, pick-up, put-down and landing (scaled by the Shake setting, off with Reduced motion; never for the autoplay bot).
- **Lumi:** arms up under a carried stack; the run lean stops growing past twice walking speed (a boost leaned him 30 degrees).
- **Local up:** a dug-up part, the holo screen, the butterfly, the depot's "+N" and the upgrade sparkle used world +Y.
- **Tool:** `--feel=carry|bale|move|snag|cam|camwall|map|tour` (tools/feel_probe.gd; `--feel-quit`, `--feel-shots=S` for frame sequences, `--feel-at=x,z`, `--feel-walk=x,z;x,z`). Tests: `tests/test_v6feel.gd`, `tests/test_v6feel_slide.gd`.
- **Town props were ghosts (found by the snag walk, 2026-11-11):** every collider the town builders made in site-local space (City/StreetProps, Furniture/FurnitureBody, the Dressing layers' Props, future posts: 550+ shapes in the start town) sat at the world origin, near the planet's centre, so Lumi and the robots walked through every bench, bin, fence, lamp and bollard in every Verdance town (owner item 41). `PropColliders.body` now puts a body built under a site prefab's Content in the site's frame. `--feel=props --feel-quit` lists ghost bodies (exit 1). Robots now meet these props too; watch `--robots=...` for stuck bots.
- **Snag fixes:** lamp posts and street-furniture poles collide as round poles, `PropColliders.fit` makes upright posts cylinders, Lumi keeps 60% of his speed while rounding a prop he clipped nearly head-on (he dropped to 0.7 m/s for half a second on a lamp post), and the greenhouse's glass-side collider runs post to post (its ends left 0.97 m V pockets that wedged him). Tunables: `data/patch.json` `move` (docs/ADJUSTING.md). `SphereMotor.step` moves by its own delta outside physics frames too (fixed the `test_lap_over_both_poles_with_camera` flake).
- **Camera backed into a tall wall:** the climb now goes up to nearly overhead (pitch -1.5). With Lumi pressed against a building, every slope hit the wall and the camera sat in his head (arm 0.6 m, Lumi hidden); now the arm is 1.85 m and he stays in view (rendered `--feel=camwall --feel-shots`).
- **Renders checked (opengl3, Low, 960x540):** the camera near a wall, a glancing push past a lamp post (`--feel-bump-at=x,z;dx,dz;off`), and the tour (`--feel=tour --orbit-spawn=0,-30 --feel-shots=1`: scoop, press, walk to the bale, carry, boost). The carried bale rides above his head in every frame. The next-piece reticle can't be picked out at Low 960x540; it needs a closer or higher-quality shot.
- **Snag walk:** `--feel=walk --feel-quit` (add `--fixed-fps 60` before `--`; `--feel-hubs=0,1`, `--feel-legs=N`, `--feel-props=N`, `--feel-boost`, `--feel-seed=S`): Lumi really walks random straight legs through each hub town (clear, grazing and kerb-crossing legs), then is pushed past small props on either side. Prints every catch, hop, swerve and stuck push with the collider; exit 1 on a catch. One hub per process on this box (all ten in one run went over the memory limit).
- **Numbers:** bale gap to his body +0.19 m in every phase (was -0.30 m); glancing pushes that get past the greenhouse spot 36 of 48 (was 6), the shack nook 39 of 48 (was 28); 0 camera jumps over 0.6 m round a town block; 0 to 90% speed in 0.27 s, stop in 0.22 s.

## 2026-11-11: v6crew (robots as the heart of the mid-game on Verdance)
- **A robot belongs to one hub** (`u["hub"]`, the hub it is built at: `SphereCrew.nearest_hub`). It cleans that hub's region nearest dirty first, its Haul Bugs fetch only that region's bales and unload at that hub's drop point (`SphereCrew.depot_points[hub_cell]`, default 5 m off the pad; v6hubs can set the exact spot). Painted zones belong to the hub they lie in. `SphereCrew.transfer(u, hub)` / `transfer_some(from, to, n)` move robots (for the rocket).
- **The first robot is a moment.** `SphereCrew.greet()`: a built robot rolls 3 m out, looks left and right, then starts on the nearest dirty hex with no zone painted (nothing ever asks the player to paint one: v8bot). The first build closes the workbench so the player sees it.
- **Zones are "here first"** for cleaners and skimmers (then they carry on around the hub, so nobody idles while work is in reach); planters and waterers keep to their zone.
- **Readable robots.** `BotBadge`: a lamp in the job's colour (pulsing at work, grey "z" resting, amber "!" needs you). `CrewTalk.line()` is the one short line per state or reason; it shows as the prompt when Lumi stands by a robot and on hover in Command. Drips spray while watering.
- **Command view.** Filled zone hexes per job, hover hex, bales as squares, a card with the hub's crew and "About N hexes an hour", a legend row per job, paint hints for mouse or pad, only the jobs you have robots for.
- **Growth.** `crew.hub_summary(hub_cell)` (also used by the rocket picker), the bench's Bots counter shows the rate, and a hub's crew reports once when Lumi returns after 3 minutes or more away (`OrbitCrews._away_tick`).
- Tests: `tests/test_crew_v6.gd`. Dev: `--crew-build=type[,s]`, `--crew-cam=i[,dist,height]`.
- **Command card, piece 2:** an "OTHER BASES" block lists every other base with robots ("Maple Yard: 3 robots, 2 working"), so one glance shows the whole crew; the unpainted hex under the cursor fills softly in the job's colour (what a click does). The lamp sits on the model's real top (`BotBadge.top_of`).
- **Haul Bug weaving:** near robots string-pull their hex path into straight runs over open ground (`SphereCrew.pull_path` / `clear_run`, never across blocked hexes or within 1.1 m of a building circle); with bales aboard a hauler picks the bale on its way home, and one by a bale another hauler is fetching costs 25 m more (`_haul_score`); each hauler of a hub has its own drop slot 3.4 m out, moved round the ring off props; bales and slots keep clear of the dodge zone; a robot keeps the side it passes another robot or the nearest prop on for 1.2 s (SphereBot `_dodge_s` / `_wall_s`). `--bot-motion` now prints metres, deg/100m, trip detour and bunching, and a `haulers:` summary.
  Measured (`--robots=scoopie:6,haulbug:4 --bot-motion --time-scale=4 --quit-after=240`, 9-11 game minutes, runs are noisy): turning 727 -> 545-579 deg/100m, trip detour x1.11 -> x1.03-1.06, bunched 4.6% -> 2.4-4.5%; reversals/min 6.3 -> 4.0-7.9 (no clear change). The remaining reversals are by robots (passing working Scoopies) and rows of building circles in the town, which hex routes cross (`--motion-debug`).
- **Mk tiers on the bot:** besides the tier's model look (salvage, restored, modern, hover), Mk II-IV carry 2-4 gold rank pips circling the lamp, an upgrade rebuilds the model and pips with a gold ring, and the hover line says "Ada the Scoopie (Mk II): ...". The `[bots]` table has a Mk column. Measured in one run, junk per Scoopie in the same time: Mk I 156, Mk II 221, Mk III 307, Mk IV 420 (x1.4, x2.0, x2.7; the data multipliers are x1.5, x2.4, x4, and travel time caps near robots).
- Open: renders of the badge, rank pips, hello and Command card (see the hand-off notes); hauler reversals near town walls; the Drip can be built before any plant exists (it says why it waits).

## 2026-11-11: v6life (the world comes back to life where you clean and plant; owner item 58)
What reacts to cleaning on the globe now, all derived from saved cell state (nothing new is saved):
- **Ground** (`plants/cell_verdure.gd`, `SphereCells.green`, `sphere_ground.gdshader`): a clean cell greens by itself over about two minutes (patches of young grass creeping out from seed spots), and more with every hex level; tufts and small flowers stand in the green patches near Lumi. The hex-complete moment gets a second, soft green ring. On load, clean cells are fully grown.
- **Streets** (`planet/sites/town_life.gd`, `building_city.gdshader`, hook in `site_power.gd`): per city block, from the cells in and round it. Clean share: facades and awnings lose grime. Mostly clean: first windows glow at dusk. Clean: the block's street lamps flicker on. Clean and planted: neon signs, string lights, lit shop windows. The skyline past the pad follows the town as a whole.
- **Small life** (`plants/flutter.gd`): butterflies by day and fireflies from dusk over planted cells (Fauna already brings cats, birds, rabbits and fish).
- **Sound** (`audio/life_ambience.gd`): a low gritty wind and a rare creak over junk; a soft breeze in leaves and a rare far bird phrase over green ground; nearly silent in between.
- **Far view** (`sphere_shell.gd`, `sphere_shell.gdshader`): the far shell and the map read the same green; a trashed city is nearly dark at night and its lights return with cleaning.
- Dev hooks: `planet/sites/life_dev.gd` (`--life-clean`, `--life-grown`, `--life-off`, `--life-report`, `--life-tour`). Tests: `tests/test_cell_verdure.gd`, `tests/test_town_life.gd`.
- **Adjustable (item 62)**: every look and rule value is in `data/life.json` (`_default` plus per-planet overrides, `core/life_cfg.gd`); the ground-following sound bed is `data/sound.json` `planets.<id>.ambience.life` (loops and one-shots can be `res://` files). docs/ADJUSTING.md, "The world coming back to life".
- **Measured (headless, 74 cells cleaned round the start)**: level 1: 11 of 22 blocks at stage 2, 16/42 lights, 217 tufts, 0 butterflies; level 3: 11 blocks at stage 3, 24/42 lights, 502 tufts, 24 butterflies; dirty ground: a creak about every 1 to 2 minutes. Every life one-shot is at least `min_gap_floor_s` (60 s) apart, whatever its event says; the bed's thresholds (`mix`, `when`) are data too (tests/test_town_life.gd checks the script reads them). Tuft building is resumable per cell and stays under 1.3 ms a frame (a town cell's spot search used to take 8 ms in one go); no life work in any `--hitch` frame over 30 ms.
- Dev hooks (not in CLAUDE.md): `--life-clean=RINGS[,LEVEL|ramp[,X,Z]]`, `--life-grown`, `--life-off`, `--life-report`, `--life-sound` (synthesize the beds headless), `--life-tour=PREFIX --life-tour-stops=...`; see the top of `planet/sites/life_dev.gd`.
Open: rendered check of the look (the tour render was blocked by memory); the hinterland's own buildings do not wake yet; other planets' towns have no block map (their prefabs are not VerdanceSite); the green-ground bird phrase did not fire in a 240 game-s headless run (it also waits for Fauna's shared bird clock), so its rate is unmeasured.

## 2026-11-11: v6name (the ark's people are the Settlers)
- Done: every player-facing "Maker(s)" is now "Settler(s)" (story scripts, WREN lines, codex, parts, achievements, decor, eggs, songs, homeward, hub, goals; the docs too). The seed pin's "gardeners" line now names the Settlers. All six languages updated (de Siedler, fr les Colons, es/pt_BR los/os Colonos, zh_CN 定居者, ja 入植者); 4080/4080 each.
- Kept on purpose: ids and save keys (`maker_shell`/`optic`/`glider`/`crest`, set `maker`, `builder_maker`, stats `maker_fragments`/`builder_maker_set`, trinket `maker_badge`), "bale makers" in docs/QA_VERDANCE.md (generic word), GUT's `MethodMaker`/`OptionMaker`. Test: `test_settler_rename_keeps_old_ids` in tests/test_robot_builder.gd.
