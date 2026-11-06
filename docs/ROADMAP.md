# Greenfall Roadmap

Start here in a new session: `docs/PROGRESS.md` (what exists, known issues, next steps), `docs/PLAN.md` (milestones + owner feature requests), `docs/DECISIONS.md` (choices and assumptions), `docs/BUILD_PROMPT.md` (the owner's full brief).

## Status
- [x] M0 Setup
- [x] M1 The Slice (city district, Patch, baling, tutorial, lens view)
- [~] M2 Planet: sphere data + globe done; walking on the sphere (M2b) next
- [~] M3 Robots: 5 robot types, workshop, fleet upgrades, Mk tiers, Haggle trade; visual redesign in progress
- [~] M4 Story: WREN, shards, first-seed cinematic; ruins/acts 2+ pending
- [~] M5 Growing: planting, watering, growth, allocation board, wildlife; ecosystems/compost pending
- [ ] M6 Water, M7 Hubs+Rockets (hub levels done), M8-M11

## Update: Command View + Aurora face pass
- Done: Command View (B / D-pad down). A holo map of the district. Pick a crew or a single robot and paint hexes to set its zone. Modes: Priority, Stay, Follow me, Recall. Orders are saved in `GameState.world.orders` and handled in `Fleet` (`order_for`, `zone_hexes`, `mode_of`); robots honour them in `robot.gd`. Tests are in `tests/test_orders.gd`. Dev hook: `--open=command`, `--order=role:mode:hex+hex|far`.
- Done: Aurora face now has big glossy oval eyes with catchlights, cheeks and ^ ^ when happy. The fin antenna is replaced by a bulb antenna.
- Next, in order:
  1. Automation chain: conveyor/hopper feeder that sends bales to the scale; an auto-baler station; drag-to-assign bots on the map.
  2. Bot build loop: build and upgrade robots straight from the Command panel when at the base, with crew size caps raised by hub level.
  3. Skimmer (water) robot and lake cleaning; Grinder/Recycler to remove trash for good.
  4. Tractor-beam pickup visuals for Mk III+ and Patch.
  5. Research tree, cargo rockets, then content (easter eggs, Codex, Ledger) and polish (cinematic intro, music, exports).

## Update: watering robots, Skimmer, crews from Command
- Done: Drip waterers are now the sustain system. They go for the thirstiest plants in their zone first (zone, then the district; slots another waterer is heading for are skipped). They spray every planted slot within `spray_radius` with droplet-arc Vfx, using one tank unit per plant. They refill at the nearest refill point: the base water barrel by the depot, placed **Water Tanks**, or any clean lake hex. Tanks are bought in the Command view ("Place refill tank here" at Patch's hex, cubes, max 6, spaced apart). Each tank holds a reserve that tops itself up. They are saved in `GameState.world.water_tanks` (`robots/water_net.gd`). Drip stats and upgrades: tank, spray radius, speed, refill rate. Tank, refill rate and spray radius also scale with the Mk tier. Each Mk tier has its own tank kit with a live level gauge.
- Done: Skimmer (role `skim`). It floats on pontoons over lake hexes, nets the floating junk, bales it and drops the bale on the nearest shore for haulers. It has 4 Mk looks (drum raft with a rubber duck, then painted pontoons, then glossy hulls, then levitating pods with a tractor beam). Cleaners now leave lake hexes to skimmers. Floating junk is no longer generated inside building footprints (200 of 585 lake pieces could never be reached).
- Done: Crew caps = 3 + 3 x hub level per crew (`data/robots.json` `crew_cap`). They show on the Bots tab cards and the Command panel. The Command panel has a Build button per crew and an Upgrade (fleet tier) button, both active only at the workbench. Robots with nothing to do park near their zone (or the base) and play an idle sway and hop. Their status then reads `idle · reason`.
- Done: Stall watch. If a robot gets no closer to its goal for 6 s, it gives up that target and nearby pieces and backs off. Hover and float units keep their height over curbs. Dev flags: `--clean-hexes=N`, `--bot-report` (automatic with `--robots`), `--trace-bot=NAME`. Tests: `tests/test_robots_water.gd`.
- Next: haulers can't keep up with 3 scoopies and a skimmer (about 66 bales made vs 42 hauled in a 120 s run). Look at hauler balance or a shore conveyor.
